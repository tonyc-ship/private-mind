import Foundation
import ActivityKit

struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        enum RecordingState: Codable, Hashable {
            case recording(startTime: Date)
            case paused(elapsedTime: TimeInterval)
        }
        var state: RecordingState
    }

    // Static data that is set once and does not change.
    var meetingTitle: String
} 