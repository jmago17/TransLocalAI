import ActivityKit
import Foundation

nonisolated struct TranscriptionActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var progress: Double          // 0.0 to 1.0
        var phase: String             // "Detecting language...", "Downloading model...", "Transcribing..."
        var elapsedSeconds: Int
    }

    var fileName: String
    var engine: String                // "Auto", "Apple", "WhisperKit"
}
