import Foundation
import AVFoundation
import Speech
#if canImport(WhisperKit)
import WhisperKit
#endif

// MARK: - Protocolo del motor de transcripción
protocol TranscriptionEngine {
    func detectLanguage(audioURL: URL) async throws -> String
    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult
}

protocol ModelPreparingTranscriptionEngine: TranscriptionEngine {
    func prepareModel(for language: String, progress: (@Sendable (Double) -> Void)?) async throws
}

// MARK: - Tipos compartidos
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

// MARK: - Apple Speech Engine (principal)
final class AppleSpeechEngine: TranscriptionEngine {
    private let manager: SpeechTranscriptionManager

    /// Cached set populated once from `SpeechTranscriber.supportedLocales`.
    private static var _cachedLanguages: Set<String>?

    nonisolated init(manager: SpeechTranscriptionManager) {
        self.manager = manager
    }

    @MainActor
    convenience init() {
        self.init(manager: SpeechTranscriptionManager())
    }

    func detectLanguage(audioURL: URL) async throws -> String {
        return try await manager.detectLanguage(audioURL: audioURL)
    }

    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
        let normalized = normalize(language)
        let supported = await AppleSpeechEngine.fetchSupportedLanguages()
        guard supported.contains(normalized) else {
            throw TranscriptionEngineError.unsupportedLanguage(normalized)
        }
        let text = try await manager.transcribe(audioURL: audioURL, language: normalized)
        let audioFile = try? AVAudioFile(forReading: audioURL)
        let duration = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        return TranscriptionResult(text: text, language: normalized, duration: duration, engineUsed: .appleSpeech)
    }

    /// Synchronous accessor — returns cached set or a hardcoded fallback.
    static var supportedLanguages: Set<String> {
        _cachedLanguages ?? ["en-US", "es-ES", "en-GB", "fr-FR", "de-DE", "it-IT", "pt-BR", "ja-JP", "ko-KR", "zh-CN"]
    }

    /// Async accessor that populates the cache from SpeechTranscriber.
    static func fetchSupportedLanguages() async -> Set<String> {
        if let cached = _cachedLanguages { return cached }
        let locales = await SpeechTranscriber.supportedLocales
        // Locale.identifier uses underscores (en_US) — normalize to BCP-47 hyphens (en-US)
        let set = Set(locales.map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
        _cachedLanguages = set
        return set
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
    private let language: String?

    init(modelId: String, language: String?) async throws {
        // modelId is now a local folder path returned by WhisperKit.download()
        let config = WhisperKitConfig(modelFolder: modelId)
        self.language = language
        self.whisper = try await WhisperKit(config)
    }

    func transcribe(audioURL: URL) async throws -> String {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: options)
        var lines: [String] = []
        for result in results {
            for segment in result.segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let stamp = Self.formatTimestamp(Double(segment.start))
                lines.append("[\(stamp)] \(text)")
            }
        }
        return lines.joined(separator: "\n")
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

// MARK: - Servicio Híbrido (selección de motor)
final class HybridTranscriptionService: @unchecked Sendable {
    private let appleEngine: TranscriptionEngine
    private let whisperEngine: TranscriptionEngine

    init(appleEngine: TranscriptionEngine, whisperEngine: TranscriptionEngine) {
        self.appleEngine = appleEngine
        self.whisperEngine = whisperEngine
    }

    @MainActor
    convenience init() {
        self.init(appleEngine: AppleSpeechEngine(), whisperEngine: WhisperKitEngine())
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
        return AppleSpeechEngine.supportedLanguages.contains(language)
    }

    private func shouldUseWhisper(for language: String) -> Bool {
        if isBasque(language) { return true }
        return !AppleSpeechEngine.supportedLanguages.contains(language)
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
