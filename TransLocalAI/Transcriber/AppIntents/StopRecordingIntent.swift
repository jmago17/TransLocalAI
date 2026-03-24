import AppIntents
import SwiftData

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stops the current recording and optionally transcribes it.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Transcribe After Stopping", default: true)
    var transcribeAfterStopping: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Stop recording and transcribe: \(\.$transcribeAfterStopping)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorder = AudioRecorderManager.shared

        guard recorder.isRecording else {
            throw RecordingIntentError.noActiveRecording
        }

        let title = recorder.recordingTitle

        guard let fileURL = recorder.stopRecording() else {
            throw RecordingIntentError.recordingFailed("Failed to save recording file.")
        }

        if transcribeAfterStopping {
            let hybridService = HybridTranscriptionService()

            try await hybridService.prepareModelIfNeeded(language: "multilingual") { _ in }

            let result = try await hybridService.transcribe(
                audioURL: fileURL,
                language: "multilingual"
            )

            let schema = Schema([Transcription.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let modelContext = modelContainer.mainContext

            let transcription = Transcription(
                title: title,
                transcriptionText: result.text,
                language: result.language,
                duration: result.duration,
                audioFileURL: fileURL.lastPathComponent,
                engineUsed: result.engineUsed == .appleSpeech ? "apple" : "whisper"
            )

            modelContext.insert(transcription)
            try modelContext.save()

            return .result(dialog: "Recording '\(title)' stopped and transcribed successfully.")
        } else {
            let schema = Schema([Transcription.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let modelContext = modelContainer.mainContext

            let audioFile = try? AVAudioFile(forReading: fileURL)
            let duration = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0

            let transcription = Transcription(
                title: title,
                transcriptionText: "",
                language: "en-US",
                duration: duration,
                audioFileURL: fileURL.lastPathComponent,
                engineUsed: ""
            )

            modelContext.insert(transcription)
            try modelContext.save()

            return .result(dialog: "Recording '\(title)' saved.")
        }
    }
}

import AVFoundation
