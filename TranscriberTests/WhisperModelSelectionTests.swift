import Foundation
import Testing
@testable import Transcriber

struct WhisperModelSelectionTests {
    @Test func catalogContainsOnlyExplicitMultilingualVariants() {
        let models = WhisperModelCatalog.defaultModels
        #expect(models.map(\.identifier).contains(WhisperModelCatalog.defaultModelIdentifier))
        #expect(models.contains { $0.modelId == "openai_whisper-small_216MB" })
        #expect(models.contains { $0.modelId == "openai_whisper-large-v3-v20240930_626MB" })
        #expect(models.allSatisfy { !$0.modelId.contains(".en") })
        #expect(Set(models.map(\.identifier)).count == models.count)
    }

    @Test func defaultModelRemainsLargeAndInvalidIdentifierFails() async {
        let manager = WhisperModelManager()
        let expected = WhisperModelCatalog.defaultModelIdentifier
        #expect(await manager.modelIdentifier(for: "eu-ES") == expected)
        #expect(await manager.modelIdentifier(for: "es-ES") == expected)
        do {
            _ = try await manager.ensureModelAvailable(modelIdentifier: "unknown-model", progress: nil)
            Issue.record("Unknown model was accepted")
        } catch TranscriptionEngineError.modelUnavailable {
            // Rejected before any network access.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
