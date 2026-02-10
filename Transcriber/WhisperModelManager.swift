import Foundation

// MARK: - Gestión de modelo Whisper (descarga/caché)
actor WhisperModelManager {
    static let shared = WhisperModelManager()

    struct ModelDescriptor: Sendable {
        let identifier: String
        let displayName: String
        let modelId: String
        let supportedLanguages: Set<String>
        let estimatedSizeMB: Int
    }

    private let modelsByIdentifier: [String: ModelDescriptor]
    private let languageToModel: [String: String]

    init(
        models: [ModelDescriptor] = WhisperModelCatalog.defaultModels,
        languageToModel: [String: String] = WhisperModelCatalog.defaultLanguageToModel
    ) {
        self.modelsByIdentifier = Dictionary(uniqueKeysWithValues: models.map { ($0.identifier, $0) })
        self.languageToModel = languageToModel
    }

    func modelIdentifier(for language: String) -> String {
        let normalized = normalize(language)
        if let mapped = languageToModel[normalized] {
            return mapped
        }
        return WhisperModelCatalog.defaultModelIdentifier
    }

    func ensureModelAvailable(
        modelIdentifier: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> String {
        guard let descriptor = modelsByIdentifier[modelIdentifier] else {
            throw TranscriptionEngineError.modelUnavailable
        }
        progress?(0)
        // WhisperKit manages download + cache by model ID (e.g., Hugging Face ID).
        progress?(1)
        return descriptor.modelId
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

// MARK: - Modelo catalog
enum WhisperModelCatalog: Sendable {
    nonisolated static let defaultModelIdentifier = "whisper-small"

    nonisolated static let defaultModels: [WhisperModelManager.ModelDescriptor] = [
        WhisperModelManager.ModelDescriptor(
            identifier: "whisper-small",
            displayName: "Whisper Small",
            modelId: "openai_whisper-small",
            supportedLanguages: [],
            estimatedSizeMB: 466
        )
    ]

    nonisolated static let defaultLanguageToModel: [String: String] = [
        "eu-ES": "whisper-small"
    ]
}
