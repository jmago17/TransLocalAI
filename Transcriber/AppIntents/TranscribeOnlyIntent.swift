//
//  TranscribeOnlyIntent.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 19/12/25.
//

import AppIntents
import Speech

/// Transcribes audio and returns the text without saving to the library
struct TranscribeOnlyIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe Audio"
    static var description = IntentDescription("Transcribes an audio file and returns the text. Does not save to library.")

    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    @Parameter(title: "Audio File", description: "The audio file to transcribe")
    var audioFile: IntentFile

    @Parameter(title: "Auto-detect Language",
               description: "Automatically detect the language",
               default: true)
    var autoDetect: Bool

    @Parameter(title: "Language",
               description: "The language of the audio (if not auto-detecting)",
               default: "en-US")
    var language: String

    static var parameterSummary: some ParameterSummary {
        Summary("Transcribe \(\.$audioFile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Check permission
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            throw TranscribeError.permissionDenied
        }

        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe-\(UUID().uuidString).m4a")
        try audioFile.data.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let hybridService = HybridTranscriptionService()

        var languageToUse = language

        if autoDetect {
            do {
                languageToUse = try await hybridService.detectLanguage(audioURL: tempURL, preferApple: true)
            } catch {
                languageToUse = language
            }
        }

        try await hybridService.prepareModelIfNeeded(language: languageToUse, progress: nil)
        let result = try await hybridService.transcribe(audioURL: tempURL, language: languageToUse)

        return .result(value: result.text)
    }
}
