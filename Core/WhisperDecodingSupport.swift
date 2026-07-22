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
