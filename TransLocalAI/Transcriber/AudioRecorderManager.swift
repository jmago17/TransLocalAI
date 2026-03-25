import AVFoundation
import ActivityKit
import Observation

@Observable
final class AudioRecorderManager: NSObject, AVAudioRecorderDelegate {
    static let shared = AudioRecorderManager()

    var isRecording = false
    var currentRecordingURL: URL?
    var lastStoppedURL: URL?
    var recordingTitle = ""
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var elapsedTimer: Timer?
    private var levelTimer: Timer?
    private var recordingStartDate: Date?
    private var recordingActivity: Activity<RecordingActivityAttributes>?

    private override init() {
        super.init()
    }

    var formattedElapsedTime: String {
        let total = Int(elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording(title: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let sanitizedTitle = title.replacingOccurrences(of: " ", with: "-")
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "\(sanitizedTitle)-\(timestamp).m4a"

        let fileURL = AudioFileManager.shared.audioDirectory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.record()

        audioRecorder = recorder
        currentRecordingURL = fileURL
        lastStoppedURL = nil
        recordingTitle = title
        isRecording = true
        elapsedTime = 0
        let startDate = Date()
        recordingStartDate = startDate

        startLiveActivity(title: title, startDate: startDate)

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartDate else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            // Normalize from dB range (-60...0) to 0...1
            let normalized = max(0, (power + 60) / 60)
            self.audioLevel = normalized
        }
    }

    func stopRecording() -> URL? {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        recordingStartDate = nil

        audioRecorder?.stop()
        audioRecorder = nil

        let url = currentRecordingURL
        lastStoppedURL = url
        isRecording = false
        audioLevel = 0

        endLiveActivity()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return url
    }

    func cancelRecording() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        recordingStartDate = nil

        audioRecorder?.stop()
        audioRecorder = nil

        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        currentRecordingURL = nil
        lastStoppedURL = nil
        isRecording = false
        elapsedTime = 0
        audioLevel = 0

        endLiveActivity()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Live Activity

    private func startLiveActivity(title: String, startDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(recordingTitle: title, startDate: startDate)
        let content = ActivityContent(state: RecordingActivityAttributes.ContentState(), staleDate: nil)
        recordingActivity = try? Activity<RecordingActivityAttributes>.request(
            attributes: attributes,
            content: content
        )
    }

    private func endLiveActivity() {
        guard let activity = recordingActivity else { return }
        recordingActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            MainActor.assumeIsolated {
                isRecording = false
            }
        }
    }
}
