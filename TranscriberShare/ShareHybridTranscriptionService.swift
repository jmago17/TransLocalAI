import Foundation
import AVFoundation
import Speech
import CoreMedia
#if canImport(WhisperKit)
import WhisperKit
#endif

protocol TranscriptionEngine {
    func detectLanguage(audioURL: URL) async throws -> String
    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult
}

protocol ModelPreparingTranscriptionEngine: TranscriptionEngine {
    func prepareModel(for language: String, progress: (@Sendable (Double) -> Void)?) async throws
}

enum TranscriptionEngineError: Error, LocalizedError {
    case unimplemented
    case unsupportedLanguage(String)
    case invalidAudio
    case permissionDenied
    case modelUnavailable
    case modelDownloadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unimplemented: return "Feature not implemented"
        case .unsupportedLanguage(let lang): return "Unsupported language: \(lang)"
        case .invalidAudio: return "Invalid audio input"
        case .permissionDenied: return "Permission denied"
        case .modelUnavailable: return "Model unavailable"
        case .modelDownloadFailed(let msg): return "Model download failed: \(msg)"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        }
    }
}

struct TranscriptionResult {
    let text: String
    let language: String
    let duration: TimeInterval
    let engineUsed: EngineKind

    enum EngineKind { case appleSpeech, whisper }
}

// MARK: - Apple Speech Engine (SpeechAnalyzer)

final class ShareAppleSpeechEngine: TranscriptionEngine {

    private static var _cachedLanguages: Set<String>?

    func detectLanguage(audioURL: URL) async throws -> String {
        let candidateLocales = [Locale(identifier: "en-US"), Locale(identifier: "es-ES")]
        var bestLanguage = "en-US"
        var bestScore: Int = 0

        let trimmedURL = try await trimAudio(audioURL: audioURL, seconds: 10)
        let shouldCleanup = (trimmedURL != audioURL)

        defer {
            if shouldCleanup {
                try? FileManager.default.removeItem(at: trimmedURL)
            }
        }

        for locale in candidateLocales {
            let score = try await scoreLocale(locale, audioURL: trimmedURL)
            if score > bestScore {
                bestScore = score
                bestLanguage = locale.identifier
            }
        }

        return bestLanguage
    }

    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
        let normalized = normalize(language)
        let supported = await ShareAppleSpeechEngine.fetchSupportedLanguages()
        guard supported.contains(normalized) else {
            throw TranscriptionEngineError.unsupportedLanguage(normalized)
        }
        let text = try await transcribeWithSpeechAnalyzer(audioURL: audioURL, locale: Locale(identifier: normalized))
        let audioFile = try? AVAudioFile(forReading: audioURL)
        let duration = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        return TranscriptionResult(text: text, language: normalized, duration: duration, engineUsed: .appleSpeech)
    }

    static var supportedLanguages: Set<String> {
        _cachedLanguages ?? ["en-US", "es-ES", "en-GB", "fr-FR", "de-DE", "it-IT", "pt-BR", "ja-JP", "ko-KR", "zh-CN"]
    }

    static func fetchSupportedLanguages() async -> Set<String> {
        if let cached = _cachedLanguages { return cached }
        let locales = await SpeechTranscriber.supportedLocales
        // Locale.identifier uses underscores (en_US) — normalize to BCP-47 hyphens (en-US)
        let set = Set(locales.map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
        _cachedLanguages = set
        return set
    }

    // MARK: - SpeechAnalyzer transcription

    private func transcribeWithSpeechAnalyzer(audioURL: URL, locale: Locale) async throws -> String {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        let installedLocales = await SpeechTranscriber.installedLocales
        let isInstalled = installedLocales.contains { $0.identifier == locale.identifier }

        if !isInstalled {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await downloader.downloadAndInstall()
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let textFuture: String = {
            var segments: [String] = []
            for try await result in transcriber.results {
                if result.isFinal {
                    let plainText = String(result.text.characters).trimmingCharacters(in: .whitespaces)
                    guard !plainText.isEmpty else { continue }

                    if let timeRange = result.text.audioTimeRange {
                        let stamp = Self.formatTimestamp(timeRange.start.seconds)
                        segments.append("[\(stamp)] \(plainText)")
                    } else {
                        segments.append(plainText)
                    }
                }
            }
            return segments.joined(separator: "\n")
        }()

        let audioFile = try AVAudioFile(forReading: audioURL)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        }

        return try await textFuture
    }

    static func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Language scoring

    private func scoreLocale(_ locale: Locale, audioURL: URL) async throws -> Int {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        let installedLocales = await SpeechTranscriber.installedLocales
        guard installedLocales.contains(where: { $0.identifier == locale.identifier }) else {
            return 0
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let textFuture: String = {
            var fullText = ""
            for try await result in transcriber.results {
                if result.isFinal {
                    fullText += String(result.text.characters) + " "
                }
            }
            return fullText.trimmingCharacters(in: .whitespaces)
        }()

        let audioFile = try AVAudioFile(forReading: audioURL)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        }

        let text = try await textFuture
        let wordCount = text.split(separator: " ").count
        return wordCount * 100
    }

    // MARK: - Helpers

    private func trimAudio(audioURL: URL, seconds: TimeInterval) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds

        if duration <= seconds {
            return audioURL
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return audioURL
        }

        let timeRange = CMTimeRange(
            start: .zero,
            end: CMTime(seconds: seconds, preferredTimescale: 600)
        )
        exportSession.timeRange = timeRange

        let trimmedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: trimmedURL)

        try await exportSession.export(to: trimmedURL, as: .m4a)
        return trimmedURL
    }

    private func normalize(_ lang: String) -> String {
        let normalized = lang.replacingOccurrences(of: "_", with: "-")
        let lower = normalized.lowercased()
        if lower == "eu" { return "eu-ES" }
        if lower == "es" { return "es-ES" }
        if lower == "en" { return "en-US" }
        return normalized
    }
}

// MARK: - WhisperKit Engine (fallback)

final class WhisperKitEngine: ModelPreparingTranscriptionEngine {
    private let modelManager: WhisperModelManager

#if canImport(WhisperKit)
    private let sessionCache = WhisperKitSessionCache()
#endif

    init(modelManager: WhisperModelManager = .shared) {
        self.modelManager = modelManager
    }

    func prepareModel(for language: String, progress: (@Sendable (Double) -> Void)?) async throws {
#if canImport(WhisperKit)
        let normalized = normalize(language)
        let modelIdentifier = await modelManager.modelIdentifier(for: normalized)
        _ = try await modelManager.ensureModelAvailable(modelIdentifier: modelIdentifier, progress: progress)
#else
        throw TranscriptionEngineError.unimplemented
#endif
    }

    func detectLanguage(audioURL: URL) async throws -> String {
#if canImport(WhisperKit)
        let defaultLanguage = "eu-ES"
        let modelIdentifier = await modelManager.modelIdentifier(for: defaultLanguage)
        let modelId = try await modelManager.ensureModelAvailable(modelIdentifier: modelIdentifier, progress: nil)
        let session = try await sessionCache.session(modelId: modelId, language: nil)
        return try await session.detectLanguage(audioURL: audioURL) ?? defaultLanguage
#else
        throw TranscriptionEngineError.unimplemented
#endif
    }

    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
#if canImport(WhisperKit)
        let normalized = normalize(language)
        let modelIdentifier = await modelManager.modelIdentifier(for: normalized)
        let modelId = try await modelManager.ensureModelAvailable(modelIdentifier: modelIdentifier, progress: nil)
        let session = try await sessionCache.session(modelId: modelId, language: normalized)
        let text = try await session.transcribe(audioURL: audioURL)
        let audioFile = try? AVAudioFile(forReading: audioURL)
        let duration = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        return TranscriptionResult(text: text, language: normalized, duration: duration, engineUsed: .whisper)
#else
        throw TranscriptionEngineError.unimplemented
#endif
    }

    private func normalize(_ lang: String) -> String {
        let normalized = lang.replacingOccurrences(of: "_", with: "-")
        let lower = normalized.lowercased()
        if lower == "eu" { return "eu-ES" }
        if lower == "es" { return "es-ES" }
        if lower == "en" { return "en-US" }
        return normalized
    }
}

#if canImport(WhisperKit)
private actor WhisperKitSessionCache {
    private var cache: [String: WhisperKitSession] = [:]

    func session(modelId: String, language: String?) async throws -> WhisperKitSession {
        let key = "\(modelId)|\(language ?? "auto")"
        if let existing = cache[key] {
            return existing
        }
        let session = try await WhisperKitSession(modelId: modelId, language: language)
        cache[key] = session
        return session
    }
}

private final class WhisperKitSession {
    private let whisper: WhisperKit
    /// ISO 639-1 code (e.g. "en", "es", "eu") — WhisperKit does not accept BCP-47 region tags.
    private let language: String?

    init(modelId: String, language: String?) async throws {
        // modelId is a local folder path returned by WhisperKit.download()
        // e.g. ".../argmaxinc/whisperkit-coreml/openai_whisper-small"
        // modelFolder must be the full path to the directory containing .mlmodelc files
        let config = WhisperKitConfig(
            modelFolder: modelId,
            download: false
        )
        // WhisperKit expects ISO 639-1 codes ("en", "es"), not BCP-47 ("en-US", "es-ES")
        self.language = language.map { Self.toISO639($0) }
        self.whisper = try await WhisperKit(config)
    }

    /// Converts a BCP-47 tag (e.g. "en-US") to its ISO 639-1 base ("en").
    private static func toISO639(_ code: String) -> String {
        if let hyphen = code.firstIndex(of: "-") {
            return String(code[..<hyphen])
        }
        return code
    }

    func transcribe(audioURL: URL) async throws -> String {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: options)
        var lines: [String] = []
        for result in results {
            for segment in result.segments {
                let text = Self.stripSpecialTokens(segment.text)
                guard !text.isEmpty else { continue }
                let stamp = Self.formatTimestamp(Double(segment.start))
                lines.append("[\(stamp)] \(text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func stripSpecialTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    func detectLanguage(audioURL: URL) async throws -> String? {
        let result = try await whisper.detectLanguage(audioPath: audioURL.path)
        return result.language
    }
}
#endif

// MARK: - Engine Preference

enum EnginePreference: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case apple = "Apple"
    case whisper = "WhisperKit"

    var id: String { rawValue }
}

// MARK: - Hybrid Service

final class HybridTranscriptionService {
    private let appleEngine: TranscriptionEngine
    private let whisperEngine: TranscriptionEngine

    init(
        appleEngine: TranscriptionEngine = ShareAppleSpeechEngine(),
        whisperEngine: TranscriptionEngine = WhisperKitEngine()
    ) {
        self.appleEngine = appleEngine
        self.whisperEngine = whisperEngine
    }

    func detectLanguage(audioURL: URL, preferApple: Bool = true) async throws -> String {
        if preferApple, let appleLang = try? await appleEngine.detectLanguage(audioURL: audioURL) {
            return normalize(appleLang)
        }
        if let whisperLang = try? await whisperEngine.detectLanguage(audioURL: audioURL) {
            return normalize(whisperLang)
        }
        return "eu-ES"
    }

    func prepareModelIfNeeded(language: String, engine: EnginePreference = .auto, progress: (@Sendable (Double) -> Void)?) async throws {
        let normalized = normalize(language)
        guard engine == .whisper || (engine == .auto && shouldUseWhisper(for: normalized)) else { return }
        if let preparer = whisperEngine as? ModelPreparingTranscriptionEngine {
            try await preparer.prepareModel(for: normalized, progress: progress)
        }
    }

    func engineKind(for language: String, engine: EnginePreference = .auto) -> TranscriptionResult.EngineKind {
        switch engine {
        case .apple: return .appleSpeech
        case .whisper: return .whisper
        case .auto:
            let normalized = normalize(language)
            return shouldUseWhisper(for: normalized) ? .whisper : .appleSpeech
        }
    }

    func transcribe(audioURL: URL, language: String, engine: EnginePreference = .auto) async throws -> TranscriptionResult {
        let normalized = normalize(language)
        switch engine {
        case .apple:
            return try await appleEngine.transcribe(audioURL: audioURL, language: normalized)
        case .whisper:
            return try await whisperEngine.transcribe(audioURL: audioURL, language: normalized)
        case .auto:
            if shouldUseWhisper(for: normalized) {
                return try await whisperEngine.transcribe(audioURL: audioURL, language: normalized)
            }
            if shouldUseApple(for: normalized) {
                return try await appleEngine.transcribe(audioURL: audioURL, language: normalized)
            }
            return try await whisperEngine.transcribe(audioURL: audioURL, language: normalized)
        }
    }

    private func shouldUseApple(for language: String) -> Bool {
        if isBasque(language) { return false }
        return ShareAppleSpeechEngine.supportedLanguages.contains(language)
    }

    private func shouldUseWhisper(for language: String) -> Bool {
        if isBasque(language) { return true }
        return !ShareAppleSpeechEngine.supportedLanguages.contains(language)
    }

    private func isBasque(_ language: String) -> Bool {
        return normalize(language).hasPrefix("eu")
    }

    private func normalize(_ lang: String) -> String {
        let normalized = lang.replacingOccurrences(of: "_", with: "-")
        let lower = normalized.lowercased()
        if lower == "eu" { return "eu-ES" }
        if lower == "es" { return "es-ES" }
        if lower == "en" { return "en-US" }
        return normalized
    }
}
