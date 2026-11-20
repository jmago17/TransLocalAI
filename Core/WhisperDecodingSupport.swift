import Foundation
import AVFoundation
import os
#if canImport(WhisperKit)
import WhisperKit
#endif

/// Shared decoding policy for both WhisperKit engine copies (app + Share
/// extension): coverage profiles, the ranked-vocabulary prompt, gap detection
/// with relaxed-settings retry, segment merging, and per-run metrics.
///
/// Everything here is `nonisolated` and pure where possible — the engines call
/// it from background tasks.
nonisolated enum WhisperDecodingSupport {

    static let logger = Logger(subsystem: "com.josumartinez.transcriber", category: "WhisperDecoding")

    // MARK: - Profiles

    enum Profile: String, CaseIterable, Identifiable, Sendable {
        case fast = "Fast"
        case balanced = "Balanced"
        case maximumCoverage = "Maximum coverage"

        var id: String { rawValue }

        private static let defaultsKey = "transcription.whisperProfile"
        private static let store = UserDefaults(suiteName: "group.com.josumartinez.transcriber") ?? .standard

        /// User-selected profile (Settings), defaulting to `.balanced`.
        static var current: Profile {
            get { store.string(forKey: defaultsKey).flatMap(Profile.init(rawValue:)) ?? .balanced }
            set { store.set(newValue.rawValue, forKey: defaultsKey) }
        }
    }

#if canImport(WhisperKit)
    /// Baseline decoding options per profile.
    ///
    /// All profiles use VAD-based chunking: windows are cut at detected
    /// silence instead of blind 30-second seeks, which both parallelizes
    /// decoding and stops sentences from being sliced mid-word — the main
    /// coverage complaint against the previous sequential decode.
    static func makeOptions(language: String?, profile: Profile) -> DecodingOptions {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.chunkingStrategy = .vad
        options.usePrefillPrompt = true

        switch profile {
        case .fast:
            // Fewer fallback re-decodes: speed over squeezing hard windows.
            options.temperatureFallbackCount = 2
        case .balanced:
            // WhisperKit/OpenAI reference thresholds, made explicit so they
            // are visible and measurable.
            options.temperatureFallbackCount = 5
            options.compressionRatioThreshold = 2.4
            options.logProbThreshold = -1.0
            options.firstTokenLogProbThreshold = -1.5
            options.noSpeechThreshold = 0.6
        case .maximumCoverage:
            // Keep borderline speech: harder to declare a window "silent"
            // (noSpeech ↑) or "failed" (logProb ↓), and more retries before
            // giving up on a window.
            options.temperatureFallbackCount = 7
            options.compressionRatioThreshold = 2.6
            options.logProbThreshold = -1.4
            options.firstTokenLogProbThreshold = -2.0
            options.noSpeechThreshold = 0.8
        }
        return options
    }

    /// Relaxed options for re-decoding a suspicious gap: assume there IS
    /// speech (very high noSpeech threshold), accept low-confidence tokens,
    /// and drop the vocabulary prompt so it cannot suppress or echo.
    static func relaxedOptions(language: String?) -> DecodingOptions {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.usePrefillPrompt = true
        options.temperatureFallbackCount = 3
        options.compressionRatioThreshold = 2.8
        options.logProbThreshold = -1.8
        options.firstTokenLogProbThreshold = nil
        options.noSpeechThreshold = 0.9
        return options
    }

    /// Encodes the ranked vocabulary as prompt tokens, hard-capped so the
    /// prompt can never crowd out Whisper's 224-token conditioning window.
    static func promptTokens(tokenizer: any WhisperTokenizer, terms: [String], maxTokens: Int = 96) -> [Int]? {
        guard !terms.isEmpty else { return nil }
        let prompt = " Glossary: " + terms.joined(separator: ", ") + "."
        let tokens = tokenizer.encode(text: prompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        guard !tokens.isEmpty else { return nil }
        return Array(tokens.prefix(maxTokens))
    }
#endif

    // MARK: - Engine-neutral segment

    struct Segment: Sendable {
        var start: Double
        var end: Double
        var text: String
    }

    // MARK: - Gap detection

    /// Time ranges longer than `minimumGap` where no segment produced text.
    /// These are the "missing portions" — either true silence or speech that
    /// every temperature fallback rejected and the seek skipped over.
    static func detectGaps(
        segments: [Segment],
        totalDuration: Double,
        minimumGap: Double = 10
    ) -> [ClosedRange<Double>] {
        guard totalDuration > 0 else { return [] }
        let sorted = segments.sorted { $0.start < $1.start }
        var gaps: [ClosedRange<Double>] = []
        var cursor = 0.0
        for segment in sorted {
            if segment.start - cursor >= minimumGap {
                gaps.append(cursor...segment.start)
            }
            cursor = max(cursor, segment.end)
        }
        if totalDuration - cursor >= minimumGap {
            gaps.append(cursor...totalDuration)
        }
        return gaps
    }

    /// Merges recovered segments into the primary list: keep primary text
    /// wherever both exist (it was decoded with stricter settings), keep
    /// recovered text only where it genuinely fills a hole.
    static func merge(primary: [Segment], recovered: [Segment]) -> [Segment] {
        guard !recovered.isEmpty else { return primary.sorted { $0.start < $1.start } }
        var result = primary
        for candidate in recovered {
            let trimmed = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let candidateLength = max(candidate.end - candidate.start, 0.1)
            let overlapsPrimary = primary.contains { existing in
                let overlap = min(existing.end, candidate.end) - max(existing.start, candidate.start)
                return overlap > candidateLength * 0.5
            }
            guard !overlapsPrimary else { continue }
            // Drop obvious hallucination loops: the same short phrase decoded
            // repeatedly inside one recovered window.
            guard !isRepetitionLoop(trimmed) else { continue }
            result.append(Segment(start: candidate.start, end: candidate.end, text: trimmed))
        }
        return result.sorted { $0.start < $1.start }
    }

    /// True when a segment is one short phrase repeated 3+ times — the classic
    /// low-signal Whisper hallucination shape.
    static func isRepetitionLoop(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count >= 6 else { return false }
        for period in 1...max(1, words.count / 3) {
            let pattern = Array(words.prefix(period))
            var repeats = true
            for index in words.indices where words[index] != pattern[index % period] {
                repeats = false
                break
            }
            if repeats { return true }
        }
        return false
    }

    // MARK: - Audio slicing (for gap retries)

    /// Exports `range` of the source audio (padded on both sides so the retry
    /// window overlaps its neighbors and no sentence is cut) to a temp file.
    static func extractSlice(
        from audioURL: URL,
        range: ClosedRange<Double>,
        padding: Double = 2.0
    ) async throws -> (url: URL, offset: Double) {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds
        let start = max(0, range.lowerBound - padding)
        let end = min(duration, range.upperBound + padding)
        guard end - start > 1.0,
              let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { throw TranscriptionEngineError.invalidAudio }

        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        let sliceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gap-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: sliceURL)
        try await exportSession.export(to: sliceURL, as: .m4a)
        return (sliceURL, start)
    }

    // MARK: - Metrics

    struct Metrics: Codable, Sendable {
        var engine: String = "whisper"
        var profile: String = ""
        var audioDuration: Double = 0
        var processingTime: Double = 0
        var segmentCount: Int = 0
        var coveredSeconds: Double = 0
        var coveragePercent: Double = 0
        var gapCount: Int = 0
        var gapSeconds: Double = 0
        var retriedGaps: Int = 0
        var recoveredSegments: Int = 0

        var realtimeFactor: Double {
            processingTime > 0 ? audioDuration / processingTime : 0
        }
    }

    static func computeMetrics(
        segments: [Segment],
        totalDuration: Double,
        processingTime: Double,
        profile: Profile,
        retriedGaps: Int,
        recoveredSegments: Int
    ) -> Metrics {
        var metrics = Metrics()
        metrics.profile = profile.rawValue
        metrics.audioDuration = totalDuration
        metrics.processingTime = processingTime
        metrics.segmentCount = segments.count
        metrics.coveredSeconds = segments.reduce(0) { $0 + max(0, $1.end - $1.start) }
        metrics.coveragePercent = totalDuration > 0
            ? min(100, metrics.coveredSeconds / totalDuration * 100)
            : 0
        let gaps = detectGaps(segments: segments, totalDuration: totalDuration)
        metrics.gapCount = gaps.count
        metrics.gapSeconds = gaps.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        metrics.retriedGaps = retriedGaps
        metrics.recoveredSegments = recoveredSegments
        return metrics
    }

    /// Most recent run's metrics, exposed for diagnostics/UI. Stored in the
    /// App Group so the Share extension's runs are visible to the app too.
    static var lastRunMetrics: Metrics? {
        get {
            let store = UserDefaults(suiteName: "group.com.josumartinez.transcriber") ?? .standard
            guard let data = store.data(forKey: "transcription.lastWhisperMetrics") else { return nil }
            return try? JSONDecoder().decode(Metrics.self, from: data)
        }
        set {
            let store = UserDefaults(suiteName: "group.com.josumartinez.transcriber") ?? .standard
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else { return }
            store.set(data, forKey: "transcription.lastWhisperMetrics")
        }
    }

    // MARK: - Shared pipeline

    /// How many silent stretches to re-decode and how long they must be.
    struct GapPolicy: Sendable {
        var minimumGap: Double
        var maxRetries: Int

        /// The app's policy for a profile.
        static func app(_ profile: Profile) -> GapPolicy {
            profile == .maximumCoverage ? GapPolicy(minimumGap: 6, maxRetries: 6) : GapPolicy(minimumGap: 10, maxRetries: 4)
        }

        /// Tighter cap for the Share extension's memory and time budget.
        static let shareExtension = GapPolicy(minimumGap: 10, maxRetries: 2)
    }

    struct PipelineOutput {
        /// Whisper's segments after gap recovery, before T4 and corrections.
        var rawSegments: [Segment]
        /// Segments from the main pass alone, before any gap retry.
        var primarySegments: [Segment]
        /// Gaps found after the main pass, and the ones that were retried.
        var gaps: [ClosedRange<Double>]
        var retriedGaps: [ClosedRange<Double>]
        var text: String
        var timings: [TranscriptSegments.Timing]
        var metrics: Metrics
    }

    /// Everything after WhisperKit is loaded: decode, retry long gaps, tidy
    /// the segments (T4) and apply the vocabulary corrections. The app, the
    /// Share extension and the evaluation bench all run this same code.
    /// Stores nothing: callers decide whether to persist the metrics.
    static func runPipeline(
        whisper: WhisperKit,
        audioURL: URL,
        language: String?,
        profile: Profile,
        gapPolicy: GapPolicy,
        vocabulary: [String],
        callback: TranscriptionCallback = nil,
        adjustOptions: ((inout DecodingOptions) -> Void)? = nil   // evaluation bench only
    ) async throws -> PipelineOutput {
        var options = makeOptions(language: language, profile: profile)
        // No vocabulary prompt. Measured on a 28-minute meeting with
        // large-v3-v20240930 (tools/WhisperBench, 2026-11-18): the main pass
        // covered 94% of the audio without a prompt, 80% with just "Hello.",
        // 14% with a natural sentence and 9% with the 16-term glossary, and
        // ran twice as slow. The vocabulary is applied afterwards instead,
        // as corrections.
        adjustOptions?(&options)

        let startedAt = Date()
        let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: options, callback: callback)
        var segments = segments(from: results.flatMap(\.segments), offset: 0)
        let primarySegments = segments

        let audioFile = try? AVAudioFile(forReading: audioURL)
        let totalDuration = audioFile.map { Double($0.length) / max($0.fileFormat.sampleRate, 1) } ?? 0

        // Gap recovery: re-decode long uncovered stretches with relaxed
        // thresholds instead of silently accepting the hole.
        var retriedGaps = 0
        var recoveredSegments = 0
        var gaps: [ClosedRange<Double>] = []
        var retried: [ClosedRange<Double>] = []
        if profile != .fast, totalDuration > 0 {
            gaps = detectGaps(segments: segments, totalDuration: totalDuration, minimumGap: gapPolicy.minimumGap)
            // Longest first: in time order, short gaps at the start used up
            // every retry and a 145 s gap at the end was dropped.
            let worst = gaps.sorted { ($0.upperBound - $0.lowerBound) > ($1.upperBound - $1.lowerBound) }
            for gap in worst.prefix(gapPolicy.maxRetries) {
                guard let slice = try? await extractSlice(from: audioURL, range: gap) else { continue }
                retriedGaps += 1
                retried.append(gap)
                if let sliceResults = try? await whisper.transcribe(
                    audioPath: slice.url.path, decodeOptions: relaxedOptions(language: language)
                ) {
                    let before = segments.count
                    segments = merge(primary: segments, recovered: self.segments(from: sliceResults.flatMap(\.segments), offset: slice.offset))
                    recoveredSegments += max(0, segments.count - before)
                }
                try? FileManager.default.removeItem(at: slice.url)
            }
        }
        segments.sort { $0.start < $1.start }

        let metrics = computeMetrics(
            segments: segments,
            totalDuration: totalDuration,
            processingTime: Date().timeIntervalSince(startedAt),
            profile: profile,
            retriedGaps: retriedGaps,
            recoveredSegments: recoveredSegments
        )
        // T4: drop punctuation-only lines, split >12 s, merge very short ones.
        let rendered = TranscriptSegments.render(
            segments.map { TranscriptSegments.Segment(start: $0.start, end: $0.end, text: $0.text) },
            correct: { TranscriptionVocabulary.correcting($0, terms: vocabulary) }
        )
        return PipelineOutput(
            rawSegments: segments, primarySegments: primarySegments, gaps: gaps, retriedGaps: retried,
            text: rendered.text, timings: rendered.timings, metrics: metrics
        )
    }

    /// Callers pass `results.flatMap(\.segments)`: the app has its own
    /// `TranscriptionResult`, and `WhisperKit.` names the class, not the module.
    static func segments(from whisperSegments: [TranscriptionSegment], offset: Double) -> [Segment] {
        whisperSegments.compactMap { segment in
            let text = stripSpecialTokens(segment.text)
            guard !text.isEmpty else { return nil }
            return Segment(start: Double(segment.start) + offset, end: Double(segment.end) + offset, text: text)
        }
    }

    static func stripSpecialTokens(_ text: String) -> String {
        // Remove WhisperKit special tokens like <|startoftranscript|>, <|endoftext|>, <|en|>, etc.
        let stripped = text.replacingOccurrences(of: "<\\|[^|]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove language-change markers generated by Whisper in multilingual mode (e.g. "Speaks in spanish")
        if stripped.range(of: #"^Speaks in \w+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return ""
        }
        return stripped
    }

    static func logMetrics(_ metrics: Metrics) {
        logger.info("""
        Whisper run [\(metrics.profile, privacy: .public)]: \
        \(String(format: "%.0f", metrics.audioDuration))s audio in \
        \(String(format: "%.0f", metrics.processingTime))s (\
        \(String(format: "%.1f", metrics.realtimeFactor))x RT), \
        coverage \(String(format: "%.1f", metrics.coveragePercent))%, \
        \(metrics.gapCount) gaps (\(String(format: "%.0f", metrics.gapSeconds))s), \
        \(metrics.retriedGaps) retried, \(metrics.recoveredSegments) segments recovered
        """)
    }
}

// MARK: - Offline model resolution

/// Finds the local WhisperKit model folder without touching the network when
/// possible. `WhisperKit.download` always lists the Hugging Face repo first
/// and rethrows on failure without looking at the local copy, so used alone
/// it made Whisper unusable offline and contacted huggingface.co on every
/// transcription. Shared by the app and the Share extension (each resolves
/// inside its own sandbox).
nonisolated enum WhisperLocalModels {
    /// Every component WhisperKit loads, and the files that make each one
    /// usable. Hub downloads land file-by-file, so an interrupted download
    /// can leave some of these missing.
    static let requiredComponents = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
    static let requiredFiles = ["coremldata.bin", "model.mil", "weights/weight.bin"]

    private static let verifiedKey = "whisper.verifiedModelFolders"

    /// Where `WhisperKit.download` puts models when no `downloadBase` is given
    /// (swift-transformers' HubApi default: Documents/huggingface).
    static var defaultBase: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    static func isComplete(_ folder: URL) -> Bool {
        let fileManager = FileManager.default
        return requiredComponents.allSatisfy { component in
            requiredFiles.allSatisfy { file in
                fileManager.fileExists(atPath: folder.appendingPathComponent(component).appendingPathComponent(file).path)
            }
        }
    }

    /// Order:
    /// 1. A folder this process already downloaded and verified → no network.
    /// 2. Otherwise download (and verify).
    /// 3. If the download fails (offline, Hub down) but a complete copy sits
    ///    at the default location — models downloaded before this check
    ///    existed — use it.
    static func resolve(
        modelId: String,
        base: URL = defaultBase,
        defaults: UserDefaults = .standard,
        download: @Sendable () async throws -> URL
    ) async throws -> URL {
        if let path = verifiedFolders(defaults)[modelId] {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            if isComplete(folder) { return folder }
            forget(path: path, defaults: defaults)
        }
        do {
            let folder = try await download()
            if isComplete(folder) {
                var all = verifiedFolders(defaults)
                all[modelId] = folder.path
                defaults.set(all, forKey: verifiedKey)
            }
            return folder
        } catch {
            let local = base.appendingPathComponent(modelId, isDirectory: true)
            if isComplete(local) {
                logger.info("Model download failed (\(error.localizedDescription, privacy: .public)); using local copy")
                return local
            }
            throw error
        }
    }

    /// Called when WhisperKit cannot load a verified folder (corrupted on
    /// disk): the next attempt downloads again instead of failing forever.
    static func forget(path: String, defaults: UserDefaults = .standard) {
        var all = verifiedFolders(defaults)
        let filtered = all.filter { $0.value != path }
        guard filtered.count != all.count else { return }
        all = filtered
        defaults.set(all, forKey: verifiedKey)
    }

    private static func verifiedFolders(_ defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: verifiedKey) as? [String: String] ?? [:]
    }

    private static var logger: Logger { WhisperDecodingSupport.logger }

#if canImport(WhisperKit)
    /// Downloads the tokenizer next to the model so the first transcription
    /// after an offline download does not need the network either. WhisperKit
    /// looks for it in the same default Hub location.
    static func prefetchTokenizer(forModelId modelId: String) async {
        let variant: ModelVariant? = modelId.contains("large-v3") ? .largev3
            : modelId.contains("small") ? .small
            : nil
        guard let variant else { return }
        _ = try? await ModelUtilities.loadTokenizer(for: variant)
    }
#endif
}
