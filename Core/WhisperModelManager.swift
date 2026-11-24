import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

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
        #if canImport(WhisperKit)
        // Local first: only goes to Hugging Face when the model is not
        // already verified on disk (see `WhisperLocalModels`).
        let modelFolderURL = try await WhisperLocalModels.resolve(modelId: descriptor.modelId) {
            let folder = try await WhisperKit.download(
                variant: descriptor.modelId,
                progressCallback: { downloadProgress in
                    Task { @MainActor in
                        progress?(downloadProgress.fractionCompleted)
                    }
                }
            )
            await WhisperLocalModels.prefetchTokenizer(forModelId: descriptor.modelId)
            return folder
        }
        progress?(1)
        return modelFolderURL.path
        #else
        progress?(1)
        return descriptor.modelId
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

// MARK: - Modelo catalog
enum WhisperModelCatalog: Sendable {
    nonisolated static let defaultModelIdentifier = "whisper-large-v3-20240930-compressed"

    nonisolated static let defaultModels: [WhisperModelManager.ModelDescriptor] = [
        WhisperModelManager.ModelDescriptor(
            identifier: "whisper-large-v3-20240930-compressed",
            displayName: "Whisper Large v3 Turbo (compressed)",
            modelId: "openai_whisper-large-v3-v20240930_626MB",
            supportedLanguages: [],
            estimatedSizeMB: 626
        ),
        WhisperModelManager.ModelDescriptor(
            identifier: "whisper-small-216mb",
            displayName: "Whisper Small",
            modelId: "openai_whisper-small_216MB",
            supportedLanguages: [],
            estimatedSizeMB: 216
        )
    ]

    nonisolated static let defaultLanguageToModel: [String: String] = [
        "eu-ES": "whisper-large-v3-20240930-compressed"
    ]
}
