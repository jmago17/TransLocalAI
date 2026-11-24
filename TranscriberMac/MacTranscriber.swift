import Foundation

@MainActor
enum MacTranscriber {
    private static let service = HybridTranscriptionService()

    static func transcribe(audioURL: URL, language: String = "auto", engine: EnginePreference = .auto,
                           progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        if engine == .voz && language == "auto" { try VozLanguagePolicy.validate(language) }
        let selectedLanguage: String
        if language == "auto" {
            // Whisper first: Apple's detector only tells English from Spanish.
            selectedLanguage = try await service.detectLanguage(audioURL: audioURL)
        } else {
            selectedLanguage = language
        }
        try await service.prepareModelIfNeeded(language: selectedLanguage, engine: engine, progress: progress)
        return try await service.transcribe(audioURL: audioURL, language: selectedLanguage, engine: engine, progress: progress).text
    }
}
