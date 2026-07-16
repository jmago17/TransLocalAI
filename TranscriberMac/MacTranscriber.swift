import Foundation

@MainActor
enum MacTranscriber {
    static func transcribe(audioURL: URL) async throws -> String {
        let service = HybridTranscriptionService()
        let language = try await service.detectLanguage(audioURL: audioURL, preferApple: true)
        try await service.prepareModelIfNeeded(language: language, engine: .auto, progress: nil)
        return try await service.transcribe(audioURL: audioURL, language: language, engine: .auto).text
    }
}
