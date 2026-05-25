import ActivityKit
import Foundation

struct FastingActivityAttributes: ActivityAttributes {

    // Static data — set once at activity start, never changes
    var scheduleLabel: String       // e.g. "16:8 Fast"

    // Dynamic data — updated on state transitions only
    struct ContentState: Codable, Hashable, Sendable {
        var fastStartDate: Date     // when the fast began
        var targetEndDate: Date     // when the fast should end (eat window opens)
        var progress: Double        // 0.0–1.0
        var isCompleted: Bool       // true = fast ended naturally
        var isBroken: Bool          // true = user broke the fast early
    }
}
