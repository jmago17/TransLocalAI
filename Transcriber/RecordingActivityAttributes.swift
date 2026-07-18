import ActivityKit
import Foundation

nonisolated struct RecordingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        // No dynamic updates needed — timer advances automatically via startDate
    }

    var recordingTitle: String
    var startDate: Date
}
