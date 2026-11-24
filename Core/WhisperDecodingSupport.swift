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
        // Without a fixed language WhisperKit does not detect one unless asked:
        // it prefills <|en|> and "transcribes" everything as English.
        options.detectLanguage = language == nil
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
        // Without a fixed language WhisperKit does not detect one unless asked:
        // it prefills <|en|> and "transcribes" everything as English.
        options.detectLanguage = language == nil
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

    // MARK: - Language detection across the whole recording

    /// Detects the language in up to `maxWindows` 30-second windows spread
    /// over the recording and returns how many windows voted for each.
    /// `WhisperKit.detectLanguage(audioPath:)` only listens to the first 30 s:
    /// a meeting that opens with silence, small talk or a phone call in
    /// another language was labelled by that opening alone.
    static func surveyLanguages(whisper: WhisperKit, audioURL: URL, maxWindows: Int = 8) async -> [String: Int] {
        guard let file = try? AVAudioFile(forReading: audioURL) else { return [:] }
        let duration = Double(file.length) / max(file.fileFormat.sampleRate, 1)
        var votes: [String: Int] = [:]
        // Twice as many candidates as votes: the quietest half is discarded,
        // because Whisper names an arbitrary language for silence.
        var candidates: [(rms: Float, samples: [Float])] = []
        for start in surveyWindowStarts(duration: duration, count: surveyWindowCount(duration: duration, maxWindows: maxWindows) * 2) {
            guard let buffer = try? AudioProcessor.loadAudio(fromPath: audioURL.path, startTime: start, endTime: min(duration, start + 30))
            else { continue }
            let samples = AudioProcessor.convertBufferToArray(buffer: buffer)
            guard samples.count > 16000 else { continue }
            let rms = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
            candidates.append((rms, samples))
        }
        let keep = max(1, (candidates.count + 1) / 2)
        for candidate in candidates.sorted(by: { $0.rms > $1.rms }).prefix(keep) {
            guard let detected = try? await whisper.detectLangauge(audioArray: candidate.samples) else { continue }
            votes[detected.language, default: 0] += 1
        }
        return votes
    }

    /// A language code, "multilingual" for mixed audio, or nil.
    static func detectLanguage(whisper: WhisperKit, audioURL: URL) async -> String? {
        let votes = await surveyLanguages(whisper: whisper, audioURL: audioURL)
        logger.info("Language survey: \(String(describing: votes), privacy: .public)")
        return languageVerdict(votes: votes)
    }
#endif

    static func surveyWindowCount(duration: Double, maxWindows: Int) -> Int {
        min(maxWindows, max(1, Int(duration / 45)))
    }

    /// Evenly spread 30-second window starts covering the whole recording.
    static func surveyWindowStarts(duration: Double, count: Int, window: Double = 30) -> [Double] {
        guard duration > window, count > 1 else { return [0] }
        let step = duration / Double(count)
        return (0..<count).map { min(max(0, (Double($0) + 0.5) * step - window / 2), duration - window) }
    }

    /// One language code, or "multilingual" when a second language holds a
    /// real share of the windows (twice, or once in a recording too short
    /// to have four windows). `nil` when nothing was detected.
    static func languageVerdict(votes: [String: Int]) -> String? {
        let total = votes.values.reduce(0, +)
        guard total > 0 else { return nil }
        let ranked = votes.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let hasSecondLanguage = ranked.dropFirst().contains { $0.value >= 2 || total < 4 }
        return hasSecondLanguage ? "multilingual" : ranked[0].key
    }

    // MARK: - Engine-neutral segment

    struct Segment: Sendable {
        var start: Double
        var end: Double
        var text: String
        /// Language Whisper decoded this segment's window in, when known.
        var language: String? = nil
    }

    // MARK: - Stray languages

    /// A language holding less than this share of the transcribed time is a
    /// decoder slip, not a language of the meeting.
    static let strayLanguageShare = 0.05

    /// Languages that hold a real share of the recording, most spoken first.
    /// Without a fixed language Whisper picks one per 30-second window, and
    /// on a Spanish + Basque meeting a few windows came out in English,
    /// German, Japanese or Russian.
    static func spokenLanguages(_ segments: [Segment]) -> [String] {
        var seconds: [String: Double] = [:]
        for segment in segments {
            guard let language = segment.language else { continue }
            seconds[language, default: 0] += max(0, segment.end - segment.start)
        }
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return [] }
        let ranked = seconds.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return ranked.enumerated().filter { $0.offset == 0 || $0.element.value / total >= strayLanguageShare }.map(\.element.key)
    }

    /// Time ranges decoded in a language outside `spoken`; neighbouring stray
    /// segments (under 2 s apart) form one range.
    static func strayLanguageRanges(_ segments: [Segment], spoken: [String]) -> [ClosedRange<Double>] {
        guard !spoken.isEmpty else { return [] }
        var ranges: [ClosedRange<Double>] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            guard let language = segment.language, !spoken.contains(language) else { continue }
            let end = max(segment.end, segment.start)
            if let last = ranges.last, segment.start - last.upperBound < 2 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, end)
            } else {
                ranges.append(segment.start...end)
            }
        }
        return ranges
    }

    /// Removes words in a script the transcript is not written in: a lone
    /// "それから" or "Спасибо" inside Latin-script text. Nothing is removed
    /// unless one script holds over 90 % of the letters.
    static func strippingStrayScripts(_ segments: [Segment]) -> [Segment] {
        var latin = 0
        var other = 0
        for scalar in segments.lazy.flatMap(\.text.unicodeScalars) where scalar.properties.isAlphabetic {
            if isLatin(scalar) { latin += 1 } else { other += 1 }
        }
        let total = latin + other
        guard total > 0, max(latin, other) * 10 > total * 9, min(latin, other) > 0 else { return segments }
        let keepLatin = latin > other
        return segments.map { segment in
            var cleaned = segment
            cleaned.text = segment.text.split(separator: " ").filter { word in
                !word.unicodeScalars.contains { $0.properties.isAlphabetic && isLatin($0) != keepLatin }
            }.joined(separator: " ")
            return cleaned
        }
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x250 || (0x1E00...0x1EFF).contains(scalar.value)
    }

    /// The window language of each raw segment text: "<|es|>" among its tokens.
    static func languageToken(in rawText: String) -> String? {
        guard let match = rawText.range(of: #"<\|[a-z]{2,3}\|>"#, options: .regularExpression) else { return nil }
        return String(rawText[match].dropFirst(2).dropLast(2))
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

    /// Segments as far as they really cover speech. Punctuation-only
    /// segments ("-" over 23 s) are dropped and a long segment holding a
    /// word or two is cut down to that word, so the stretch around it counts
    /// as a gap and gets retried instead of passing as transcribed.
    static func coveringSpeech(_ segments: [Segment]) -> [Segment] {
        segments.compactMap { segment in
            guard TranscriptSegments.hasSpokenContent(segment.text) else { return nil }
            let duration = segment.end - segment.start
            let words = Double(segment.text.split(whereSeparator: \.isWhitespace).count)
            guard duration >= sparseSegmentSeconds, words / duration < sparseWordsPerSecond else { return segment }
            var trimmed = segment
            trimmed.end = segment.start + max(2, words)
            return trimmed
        }
    }

    static let sparseSegmentSeconds = 10.0
    static let sparseWordsPerSecond = 0.3

    /// Merges recovered segments into the primary list: keep primary text
    /// wherever both exist (it was decoded with stricter settings), keep
    /// recovered text only where it genuinely fills a hole.
    static func merge(primary: [Segment], recovered: [Segment], gap: ClosedRange<Double>? = nil) -> [Segment] {
        guard !recovered.isEmpty else { return primary.sorted { $0.start < $1.start } }
        var result = primary
        for candidate in recovered {
            let trimmed = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // The retry slice is padded on both sides: text decoded in the
            // padding belongs to the neighbours, which the main pass already has.
            if let gap {
                let middle = (candidate.start + candidate.end) / 2
                guard middle >= gap.lowerBound - 0.5, middle <= gap.upperBound + 0.5 else { continue }
            }
            let candidateLength = max(candidate.end - candidate.start, 0.1)
            let overlapsPrimary = primary.contains { existing in
                let overlap = min(existing.end, candidate.end) - max(existing.start, candidate.start)
                return overlap > candidateLength * 0.5
            }
            guard !overlapsPrimary else { continue }
            // Drop obvious hallucination loops: the same short phrase decoded
            // repeatedly inside one recovered window.
            guard !isRepetitionLoop(trimmed) else { continue }
            result.append(Segment(start: candidate.start, end: candidate.end, text: trimmed, language: candidate.language))
        }
        return result.sorted { $0.start < $1.start }
    }

    /// True when a segment is one short phrase repeated 3+ times — the classic
    /// low-signal Whisper hallucination shape.
    static func isRepetitionLoop(_ text: String) -> Bool {
        // Compared without case or punctuation: "-Baina baina baina…" is a loop.
        let words = text.split(separator: " ").map(TranscriptSegments.loopKey).filter { !$0.isEmpty }
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
            // Measured on a 45-minute mixed meeting (2026-11-23): with 4
            // retries, 12-second gaps holding 30 and 53 words stayed empty.
            profile == .maximumCoverage ? GapPolicy(minimumGap: 6, maxRetries: 16) : GapPolicy(minimumGap: 10, maxRetries: 10)
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
        var segments = coveringSpeech(segments(from: results.flatMap(\.segments), offset: 0))
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
                    segments = merge(
                        primary: segments,
                        recovered: coveringSpeech(self.segments(from: sliceResults.flatMap(\.segments), offset: slice.offset)),
                        gap: gap
                    )
                    recoveredSegments += max(0, segments.count - before)
                }
                try? FileManager.default.removeItem(at: slice.url)
            }
        }
        // Stray languages: only without a fixed language, where Whisper
        // chooses one per window. Each stray stretch is decoded again in the
        // languages the recording is really in and the likelier one is kept;
        // a stretch that then comes back empty was noise.
        var redecodedLanguageRanges = 0
        if language == nil {
            let spoken = Array(spokenLanguages(segments).prefix(2))
            for range in strayLanguageRanges(segments, spoken: spoken).prefix(gapPolicy.maxRetries) {
                var best: (segments: [Segment], score: Float)?
                if let slice = try? await extractSlice(from: audioURL, range: range) {
                    for candidate in spoken {
                        guard let sliceResults = try? await whisper.transcribe(
                            audioPath: slice.url.path, decodeOptions: makeOptions(language: candidate, profile: profile)
                        ) else { continue }
                        let raw = sliceResults.flatMap(\.segments)
                        let found = coveringSpeech(self.segments(from: raw, offset: slice.offset))
                            .map { Segment(start: $0.start, end: $0.end, text: $0.text, language: candidate) }
                        guard !found.isEmpty else { continue }
                        let score = raw.map(\.avgLogprob).reduce(0, +) / Float(max(raw.count, 1))
                        if best == nil || score > best!.score { best = (found, score) }
                    }
                    try? FileManager.default.removeItem(at: slice.url)
                }
                segments.removeAll { segment in
                    guard let segmentLanguage = segment.language, !spoken.contains(segmentLanguage) else { return false }
                    return segment.start >= range.lowerBound - 0.01 && segment.start <= range.upperBound
                }
                segments = merge(primary: segments, recovered: best?.segments ?? [], gap: range)
                redecodedLanguageRanges += 1
            }
            segments = strippingStrayScripts(segments)
        }
        if redecodedLanguageRanges > 0 {
            logger.info("Stray-language stretches decoded again: \(redecodedLanguageRanges)")
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
        // Every segment of a window shares its language; not every one
        // carries the token in its text.
        var languageBySeek: [Int: String] = [:]
        for segment in whisperSegments where languageBySeek[segment.seek] == nil {
            languageBySeek[segment.seek] = languageToken(in: segment.text)
        }
        return whisperSegments.compactMap { segment in
            let text = stripSpecialTokens(segment.text)
            guard !text.isEmpty else { return nil }
            return Segment(
                start: Double(segment.start) + offset, end: Double(segment.end) + offset, text: text,
                language: languageBySeek[segment.seek]
            )
        }
    }

    static func stripSpecialTokens(_ text: String) -> String {
        // Remove WhisperKit special tokens like <|startoftranscript|>, <|endoftext|>, <|en|>, etc.
        let stripped = text.replacingOccurrences(of: "<\\|[^|]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "Speaks in spanish": what Whisper writes when it is told the audio is in
        // one language and hears another (a fixed language on mixed audio).
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
