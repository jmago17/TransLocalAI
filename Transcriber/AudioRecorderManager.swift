import AVFoundation
import ActivityKit
import Observation
import SwiftData

@Observable
final class AudioRecorderManager: NSObject, AVAudioRecorderDelegate {
    static let shared = AudioRecorderManager()

    var isRecording = false
    /// The system paused capture (phone call, Siri, alarm…) and has not
    /// resumed it. The file is intact; `resumeRecording()` continues it.
    var isPaused = false
    var currentRecordingURL: URL?
    var lastStoppedURL: URL?
    var recordingTitle = ""
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0
    /// Set when the system, not the user, ended the recording. The audio up
    /// to that point is kept and recovered; the UI shows this once.
    var systemStopMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var elapsedTimer: Timer?
    private var levelTimer: Timer?
    private var recordingStartDate: Date?
    private var recordingActivity: Activity<RecordingActivityAttributes>?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        observeAudioSession()
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

    /// Linear PCM in CAF: unlike AAC/M4A (whose index is only written on a
    /// clean stop), every sample already on disk stays readable if the app is
    /// killed mid-recording. 16 kHz mono is what every engine resamples to
    /// anyway; it costs ~115 MB per hour.
    static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    func startRecording(title: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let sanitizedTitle = title.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "\(sanitizedTitle)-\(timestamp).caf"

        let fileURL = AudioFileManager.shared.audioDirectory.appendingPathComponent(fileName)

        let recorder = try AVAudioRecorder(url: fileURL, settings: Self.recordingSettings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderError.couldNotStart
        }

        let startDate = Date()
        PendingRecordings.add(fileName: fileName, title: title, startDate: startDate)

        audioRecorder = recorder
        currentRecordingURL = fileURL
        lastStoppedURL = nil
        recordingTitle = title
        isRecording = true
        isPaused = false
        systemStopMessage = nil
        elapsedTime = 0
        recordingStartDate = startDate

        startLiveActivity(title: title, startDate: startDate)

        // Recorded time, not wall-clock time: `currentTime` stops advancing
        // while an interruption has capture paused.
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                self.elapsedTime = recorder.currentTime
            }
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.audioRecorder else { return }
                guard recorder.isRecording else { self.audioLevel = 0; return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                // Normalize from dB range (-60...0) to 0...1
                self.audioLevel = max(0, (power + 60) / 60)
            }
        }
    }

    /// Continues a recording the system paused, appending to the same file.
    @discardableResult
    func resumeRecording() -> Bool {
        guard isRecording, let recorder = audioRecorder else { return false }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return false
        }
        guard recorder.record() else { return false }
        isPaused = false
        updateLiveActivity()
        return true
    }

    func stopRecording() -> URL? {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        recordingStartDate = nil

        if let recorder = audioRecorder {
            let recorded = recorder.currentTime
            if recorded > 0 { elapsedTime = recorded }
            recorder.stop()
        }
        audioRecorder = nil

        let url = currentRecordingURL
        currentRecordingURL = nil
        lastStoppedURL = url
        isRecording = false
        isPaused = false
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
            PendingRecordings.remove(fileName: url.lastPathComponent)
        }

        currentRecordingURL = nil
        lastStoppedURL = nil
        isRecording = false
        isPaused = false
        elapsedTime = 0
        audioLevel = 0

        endLiveActivity()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The system ended capture on its own. Close the file cleanly so what
    /// was recorded is kept; the pending mark stays, so the library entry is
    /// created by `RecordingRecovery` (the app root runs it when
    /// `isRecording` goes false, and again on next launch).
    private func stopAfterSystemFailure(_ reason: String) {
        guard isRecording else { return }
        _ = stopRecording()
        systemStopMessage = reason
    }

    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { String(localized: "The microphone could not start recording.") }
    }

    // MARK: - Audio session events

    private func observeAudioSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // The recorder object is dead after a reset; keep what's on disk.
                self?.stopAfterSystemFailure(String(localized: "The system audio service restarted, so the recording was stopped. Everything recorded until then was saved."))
            }
        })
    }

    private func handleInterruption(typeValue: UInt?, optionsValue: UInt) {
        guard isRecording, let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            // Capture is already paused by the system; reflect it.
            isPaused = true
            audioLevel = 0
            updateLiveActivity()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                resumeRecording()
            }
            // Otherwise stay paused: the UI offers "Resume".
        @unknown default:
            break
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity(title: String, startDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(recordingTitle: title, startDate: startDate)
        let content = ActivityContent(
            state: RecordingActivityAttributes.ContentState(timerStart: startDate),
            staleDate: nil
        )
        recordingActivity = try? Activity<RecordingActivityAttributes>.request(
            attributes: attributes,
            content: content
        )
    }

    /// Pauses/resumes the Live Activity timer so it shows recorded time.
    private func updateLiveActivity() {
        guard let activity = recordingActivity else { return }
        let recorded = audioRecorder?.currentTime ?? elapsedTime
        let state = RecordingActivityAttributes.ContentState(
            timerStart: Date().addingTimeInterval(-recorded),
            pausedElapsed: isPaused ? recorded : nil
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
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
        guard !flag else { return }
        Task { @MainActor in
            guard self.audioRecorder === recorder else { return }
            self.stopAfterSystemFailure(String(localized: "The system stopped the recording. Everything recorded until then was saved."))
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        Task { @MainActor in
            guard self.audioRecorder === recorder else { return }
            self.stopAfterSystemFailure(String(localized: "An audio error stopped the recording. Everything recorded until then was saved."))
        }
    }
}

// MARK: - Pending recordings

/// Recordings started but not yet in the library. Written when capture
/// starts, cleared once a `Transcription` references the file. Anything left
/// here (app killed, system stop, stop intent that crashed) is recovered by
/// `RecordingRecovery`. Only marked files are recovered, so an audio file
/// whose entry was deleted on purpose is never resurrected.
enum PendingRecordings {
    private static let key = "recording.pending"
    private static var store: UserDefaults { .standard }

    struct Entry {
        var fileName: String
        var title: String
        var startDate: Date
    }

    static func add(fileName: String, title: String, startDate: Date) {
        var all = raw
        all[fileName] = ["title": title, "start": startDate.timeIntervalSince1970]
        store.set(all, forKey: key)
    }

    static func remove(fileName: String) {
        var all = raw
        guard all.removeValue(forKey: fileName) != nil else { return }
        store.set(all, forKey: key)
    }

    static var entries: [Entry] {
        raw.compactMap { name, value in
            guard let dict = value as? [String: Any] else { return nil }
            return Entry(
                fileName: name,
                title: dict["title"] as? String ?? "",
                startDate: Date(timeIntervalSince1970: dict["start"] as? Double ?? Date().timeIntervalSince1970)
            )
        }
    }

    private static var raw: [String: Any] {
        store.dictionary(forKey: key) ?? [:]
    }
}

enum RecordingRecovery {
    /// Creates library entries for pending recordings that are not the one
    /// in progress. Returns how many were recovered.
    @discardableResult
    static func recover(into context: ModelContext) -> Int {
        let active = AudioRecorderManager.shared.currentRecordingURL?.lastPathComponent
        var recovered = 0
        for entry in PendingRecordings.entries where entry.fileName != active {
            guard let url = AudioFileManager.shared.audioURL(for: entry.fileName) else {
                PendingRecordings.remove(fileName: entry.fileName)
                continue
            }
            let fileName = entry.fileName
            let existing = (try? context.fetchCount(FetchDescriptor<Transcription>(
                predicate: #Predicate { $0.audioFileURL == fileName }
            ))) ?? 0
            if existing > 0 {
                PendingRecordings.remove(fileName: fileName)
                continue
            }
            let duration = audioDuration(url: url)
            guard duration >= 0.5 else {
                // Nothing usable was captured.
                try? FileManager.default.removeItem(at: url)
                PendingRecordings.remove(fileName: fileName)
                continue
            }
            context.insert(Transcription(
                timestamp: entry.startDate,
                title: entry.title,
                transcriptionText: "",
                language: "multilingual",
                duration: duration,
                audioFileURL: fileName,
                engineUsed: ""
            ))
            do {
                try context.save()
                PendingRecordings.remove(fileName: fileName)
                recovered += 1
            } catch {
                // Keep the mark; next launch retries.
            }
        }
        return recovered
    }

    static func audioDuration(url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.fileFormat.sampleRate
        return sampleRate > 0 ? Double(file.length) / sampleRate : 0
    }
}
