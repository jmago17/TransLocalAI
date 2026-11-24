import Foundation
import AVFoundation
import Speech
import CoreML
#if canImport(WhisperKit)
import WhisperKit
#endif

// MARK: - Protocolo del motor de transcripción
protocol TranscriptionEngine {
    func detectLanguage(audioURL: URL) async throws -> String
    func transcribe(
        audioURL: URL,
        language: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptionResult
}

extension TranscriptionEngine {
    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, language: language, progress: nil)
    }
}

protocol ModelPreparingTranscriptionEngine: TranscriptionEngine {
    func prepareModel(for language: String, progress: (@Sendable (Double) -> Void)?) async throws
}

/// Per-request selection, without changing the engine's shared/default configuration.
protocol ModelSelectingTranscriptionEngine: ModelPreparingTranscriptionEngine {
    func prepareModel(for language: String, modelIdentifier: String?, progress: (@Sendable (Double) -> Void)?) async throws
    func transcribe(audioURL: URL, language: String, modelIdentifier: String?, progress: (@Sendable (Double) -> Void)?) async throws -> TranscriptionResult
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
    /// Start/end of each transcript line, when the engine provides them.
    var segmentTimings: [TranscriptSegments.Timing] = []

    enum EngineKind {
        case appleSpeech, whisper, voz
        var displayName: String {
            switch self {
            case .appleSpeech: return "Apple Speech"
            case .whisper: return "WhisperKit"
            case .voz: return "Voz"
            }
        }
        var persistedValue: String {
            switch self {
            case .appleSpeech: return "apple"
            case .whisper: return "whisper"
            case .voz: return "voz"
            }
        }
    }
}

// MARK: - Apple Speech Engine (optional, user-selected)
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

    func transcribe(
        audioURL: URL,
        language: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptionResult {
        let normalized = normalize(language)
        let supported = await AppleSpeechEngine.fetchSupportedLanguages()
        guard supported.contains(normalized) else {
            throw TranscriptionEngineError.unsupportedLanguage(normalized)
        }
        let text = try await manager.transcribe(audioURL: audioURL, language: normalized, progress: progress)
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

// MARK: - WhisperKit Engine (default)
final class WhisperKitEngine: ModelSelectingTranscriptionEngine {
    private let modelManager: WhisperModelManager

#if canImport(WhisperKit)
    private let sessionCache = WhisperKitSessionCache()
#endif

    init(modelManager: WhisperModelManager = .shared) {
        self.modelManager = modelManager
    }

    func prepareModel(for language: String, progress: (@Sendable (Double) -> Void)?) async throws {
        try await prepareModel(for: language, modelIdentifier: nil, progress: progress)
    }

    func prepareModel(for language: String, modelIdentifier: String?, progress: (@Sendable (Double) -> Void)?) async throws {
#if canImport(WhisperKit)
        let identifier: String
        if let modelIdentifier { identifier = modelIdentifier }
        else { identifier = await modelManager.modelIdentifier(for: normalize(language)) }
        _ = try await modelManager.ensureModelAvailable(modelIdentifier: identifier, progress: progress)
#else
        throw TranscriptionEngineError.unimplemented
#endif
    }

    func detectLanguage(audioURL: URL) async throws -> String {
        try await detectLanguage(audioURL: audioURL, modelIdentifier: nil)
    }

    func detectLanguage(audioURL: URL, modelIdentifier: String?) async throws -> String {
#if canImport(WhisperKit)
        let defaultLanguage = "eu-ES"
        let identifier: String
        if let modelIdentifier { identifier = modelIdentifier }
        else { identifier = await modelManager.modelIdentifier(for: defaultLanguage) }
        let modelId = try await modelManager.ensureModelAvailable(modelIdentifier: identifier, progress: nil)
        let session = try await sessionCache.session(modelId: modelId, language: nil)
        return try await session.detectLanguage(audioURL: audioURL) ?? "multilingual"
#else
        throw TranscriptionEngineError.unimplemented
#endif
    }

    func transcribe(
        audioURL: URL,
        language: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, language: language, modelIdentifier: nil, progress: progress)
    }

    func transcribe(
        audioURL: URL,
        language: String,
        modelIdentifier: String?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptionResult {
#if canImport(WhisperKit)
        let isMultilingual = language == "multilingual"
        let normalized = isMultilingual ? "eu-ES" : normalize(language)
        let sessionLanguage: String? = isMultilingual ? nil : normalized
        let identifier: String
        if let modelIdentifier { identifier = modelIdentifier }
        else { identifier = await modelManager.modelIdentifier(for: normalized) }
        let modelId = try await modelManager.ensureModelAvailable(modelIdentifier: identifier, progress: nil)
        let session = try await sessionCache.session(modelId: modelId, language: sessionLanguage)
        let output = try await session.transcribe(audioURL: audioURL, progress: progress)
        let audioFile = try? AVAudioFile(forReading: audioURL)
        let duration = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        return TranscriptionResult(text: output.text, language: language, duration: duration,
                                   engineUsed: .whisper, segmentTimings: output.timings)
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
        let session: WhisperKitSession
        do {
            session = try await WhisperKitSession(modelId: modelId, language: language)
        } catch {
            // A folder that passed the file check but will not load is
            // corrupt: drop it from the verified list so the next attempt
            // downloads again instead of failing forever.
            WhisperLocalModels.forget(path: modelId)
            throw error
        }
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
        // e.g. ".../argmaxinc/whisperkit-coreml/openai_whisper-medium"
        // modelFolder must be the full path to the directory containing .mlmodelc files
        let config = WhisperKitConfig(
            modelFolder: modelId,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuOnly,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine,
                prefillCompute: .cpuOnly
            ),
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

    func transcribe(audioURL: URL, progress progressHandler: (@Sendable (Double) -> Void)? = nil) async throws -> (text: String, timings: [TranscriptSegments.Timing]) {
        let profile = WhisperDecodingSupport.Profile.current
        let vocabulary = await MainActor.run { TranscriptionTerminology.activeVocabularyLines }
        // WhisperKit tracks overall completion on its Progress object; sample
        // it whenever a decoding window reports in.
        let callback: TranscriptionCallback = progressHandler.map { handler in
            { [progressObject = whisper.progress] _ in
                handler(min(progressObject.fractionCompleted, 0.99))
                return true
            }
        } ?? nil

        let output = try await WhisperDecodingSupport.runPipeline(
            whisper: whisper,
            audioURL: audioURL,
            language: language,
            profile: profile,
            gapPolicy: .app(profile),
            vocabulary: vocabulary,
            callback: callback
        )
        WhisperDecodingSupport.logMetrics(output.metrics)
        WhisperDecodingSupport.lastRunMetrics = output.metrics
        return (output.text, output.timings)
    }

    /// A language code, "multilingual" for mixed audio, or nil.
    func detectLanguage(audioURL: URL) async throws -> String? {
        await WhisperDecodingSupport.detectLanguage(whisper: whisper, audioURL: audioURL)
    }
}
#endif

// MARK: - Engine Preference

enum EnginePreference: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case apple = "Apple"
    case whisper = "WhisperKit"
    case voz = "Voz"

    var id: String { rawValue }
}

// MARK: - Servicio Híbrido (selección de motor)
final class HybridTranscriptionService: @unchecked Sendable {
    private let appleEngine: TranscriptionEngine
    private let whisperEngine: TranscriptionEngine
    private let vozEngine: TranscriptionEngine

    init(appleEngine: TranscriptionEngine, whisperEngine: TranscriptionEngine, vozEngine: TranscriptionEngine = VozTranscriptionEngine.shared) {
        self.appleEngine = appleEngine
        self.whisperEngine = whisperEngine
        self.vozEngine = vozEngine
    }

    @MainActor
    convenience init() {
        self.init(appleEngine: AppleSpeechEngine(), whisperEngine: WhisperKitEngine())
    }

    func detectLanguage(audioURL: URL, preferApple: Bool = false, modelIdentifier: String? = nil) async throws -> String {
        if preferApple, let appleLang = try? await appleEngine.detectLanguage(audioURL: audioURL) {
            return normalize(appleLang)
        }
        let whisperLang: String?
        if let selecting = whisperEngine as? WhisperKitEngine {
            whisperLang = try? await selecting.detectLanguage(audioURL: audioURL, modelIdentifier: modelIdentifier)
        } else {
            whisperLang = try? await whisperEngine.detectLanguage(audioURL: audioURL)
        }
        if let whisperLang {
            return normalize(whisperLang)
        }
        // Fallback to Apple if WhisperKit detection failed
        if let appleLang = try? await appleEngine.detectLanguage(audioURL: audioURL) {
            return normalize(appleLang)
        }
        // Nothing could tell: no guessed language. Whisper then detects it
        // window by window while transcribing.
        return "multilingual"
    }

    func prepareModelIfNeeded(language: String, engine: EnginePreference = .auto, modelIdentifier: String? = nil, progress: (@Sendable (Double) -> Void)?) async throws {
        if engineKind(for: language, engine: engine) == .voz {
            try VozLanguagePolicy.validate(language)
            if let preparer = vozEngine as? ModelPreparingTranscriptionEngine {
                try await preparer.prepareModel(for: language, progress: progress)
            }
            return
        }
        guard engineKind(for: language, engine: engine) == .whisper else { return }
        let normalized = language == "multilingual" || (engine == .voz && VozLanguagePolicy.base(language) == "eu") ? "eu-ES" : normalize(language)
        if let preparer = whisperEngine as? ModelSelectingTranscriptionEngine {
            try await preparer.prepareModel(for: normalized, modelIdentifier: modelIdentifier, progress: progress)
        } else if let preparer = whisperEngine as? ModelPreparingTranscriptionEngine {
            try await preparer.prepareModel(for: normalized, progress: progress)
        }
    }

    func engineKind(for language: String, engine: EnginePreference = .auto) -> TranscriptionResult.EngineKind {
        if language == "multilingual" || (engine == .voz && VozLanguagePolicy.base(language) == "eu") { return .whisper }
        switch engine {
        case .voz: return .voz
        case .apple: return .appleSpeech
        case .whisper: return .whisper
        case .auto: return normalize(language) == "eu-ES" ? .whisper : .appleSpeech
        }
    }

    func transcribe(
        audioURL: URL,
        language: String,
        engine: EnginePreference = .auto,
        modelIdentifier: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscriptionResult {
        let result = try await transcribeWithSelectedEngine(
            audioURL: audioURL, language: language, engine: engine, modelIdentifier: modelIdentifier, progress: progress
        )
        try Task.checkCancellation()
        // Feedback loop: terms that actually appeared gain ranking weight for
        // the next transcription's contextual vocabulary / prompt.
        await MainActor.run { TranscriptionTerminology.recordRecognitions(in: result.text) }
        return result
    }

    private func transcribeWithSelectedEngine(
        audioURL: URL,
        language: String,
        engine: EnginePreference,
        modelIdentifier: String?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptionResult {
        func useWhisper(_ language: String) async throws -> TranscriptionResult {
            if let selecting = whisperEngine as? ModelSelectingTranscriptionEngine {
                return try await selecting.transcribe(audioURL: audioURL, language: language, modelIdentifier: modelIdentifier, progress: progress)
            }
            return try await whisperEngine.transcribe(audioURL: audioURL, language: language, progress: progress)
        }
        if language == "multilingual" {
            return try await useWhisper("multilingual")
        }
        if engine == .voz && VozLanguagePolicy.base(language) == "eu" {
            return try await useWhisper("eu-ES")
        }
        let normalized = normalize(language)
        switch engine {
        case .voz:
            try VozLanguagePolicy.validate(language)
            return try await vozEngine.transcribe(audioURL: audioURL, language: normalized, progress: progress)
        case .apple:
            return try await appleEngine.transcribe(audioURL: audioURL, language: normalized, progress: progress)
        case .whisper:
            return try await useWhisper(normalized)
        case .auto:
            if normalized == "eu-ES" {
                return try await useWhisper(normalized)
            }
            do {
                return try await appleEngine.transcribe(audioURL: audioURL, language: normalized, progress: progress)
            } catch TranscriptionEngineError.unsupportedLanguage {
                return try await useWhisper(normalized)
            }
        }
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
