import AppIntents
import AVFoundation
import SwiftData

/// Minimal intent for the recording Live Activity stop button.
/// Stops the active recording and saves an audio-only entry to the library.
struct StopRecordingLiveActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let recorder = AudioRecorderManager.shared
        let title = recorder.recordingTitle

        guard let fileURL = recorder.stopRecording() else {
            return .result()
        }

        let duration = RecordingRecovery.audioDuration(url: fileURL)

        let schema = Schema([Transcription.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            let transcription = Transcription(
                title: title,
                transcriptionText: "",
                language: "multilingual",
                duration: duration,
                audioFileURL: fileURL.lastPathComponent,
                engineUsed: ""
            )
            container.mainContext.insert(transcription)
            if (try? container.mainContext.save()) != nil {
                PendingRecordings.remove(fileName: fileURL.lastPathComponent)
            }
        }
        // If saving failed the pending mark stays and the app recovers it.

        return .result()
    }
}
