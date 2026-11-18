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

        // Save the audio-only entry before anything that can take minutes or
        // fail (model download, transcription): the recording must reach the
        // library even if the intent is cut off.
        let schema = Schema([Transcription.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let modelContext = modelContainer.mainContext

        let transcription = Transcription(
            title: title,
            transcriptionText: "",
            language: "multilingual",
            duration: RecordingRecovery.audioDuration(url: fileURL),
            audioFileURL: fileURL.lastPathComponent,
            engineUsed: ""
        )
        modelContext.insert(transcription)
        try modelContext.save()
        PendingRecordings.remove(fileName: fileURL.lastPathComponent)

        guard transcribeAfterStopping else {
            return .result(dialog: "Recording '\(title)' saved.")
        }

        let hybridService = HybridTranscriptionService()
        do {
            try await hybridService.prepareModelIfNeeded(language: "multilingual") { _ in }
            let result = try await hybridService.transcribe(audioURL: fileURL, language: "multilingual")
            transcription.transcriptionText = result.text
            transcription.language = result.language
            transcription.duration = result.duration
            transcription.engineUsed = result.engineUsed.persistedValue
            transcription.segmentTimings = TranscriptSegments.encode(result.segmentTimings)
            try modelContext.save()
        } catch {
            return .result(dialog: "Recording '\(title)' saved, but transcription failed: \(error.localizedDescription). You can transcribe it from the library.")
        }

        return .result(dialog: "Recording '\(title)' stopped and transcribed successfully.")
    }
}

import AVFoundation
