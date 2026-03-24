import AppIntents
import AVFoundation

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Starts recording audio with Transcriber. The app must open to begin the audio session.")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Recording Name", default: "Shortcut Recording")
    var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start recording named \(\.$name)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorder = AudioRecorderManager.shared

        if recorder.isRecording {
            return .result(dialog: "A recording is already in progress: \(recorder.recordingTitle)")
        }

        let granted = await recorder.requestPermission()
        guard granted else {
            throw RecordingIntentError.microphonePermissionDenied
        }

        do {
            try recorder.startRecording(title: name)
            return .result(dialog: "Recording started: \(name). You can switch to another app — recording will continue in the background.")
        } catch {
            throw RecordingIntentError.recordingFailed(error.localizedDescription)
        }
    }
}

enum RecordingIntentError: Error, LocalizedError {
    case microphonePermissionDenied
    case recordingFailed(String)
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required to record audio."
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
        case .noActiveRecording:
            return "No active recording to stop."
        }
    }
}
