import ActivityKit
import Foundation

nonisolated struct RecordingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Start of a running timer that shows recorded time: shifted forward
        /// by any time spent paused by an interruption.
        var timerStart: Date
        /// Recorded seconds while capture is paused; `nil` while recording.
        var pausedElapsed: TimeInterval? = nil
    }

    var recordingTitle: String
    var startDate: Date
}
