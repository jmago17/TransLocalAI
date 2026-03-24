import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        // No dynamic updates needed — timer advances automatically via startDate
    }

    var recordingTitle: String
    var startDate: Date
}
