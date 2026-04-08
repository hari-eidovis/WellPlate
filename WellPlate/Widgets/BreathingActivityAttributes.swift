import ActivityKit
import Foundation

struct BreathingActivityAttributes: ActivityAttributes {

    // Static data
    var sessionName: String          // e.g. "Physiological Sigh", "PMR"
    var totalSteps: Int              // 3 for Sigh (cycles), 8 for PMR (muscle groups)
    var stepLabel: String            // "Cycle" for Sigh, "Group" for PMR

    // Dynamic data — updated on phase transitions
    struct ContentState: Codable, Hashable, Sendable {
        var phaseName: String        // e.g. "First inhale", "Long exhale", "Tense — Shoulders"
        var phaseEndDate: Date       // when the current phase ends
        var currentStep: Int         // 1-based — cycle number (Sigh) or muscle group number (PMR)
        var totalProgress: Double    // 0.0–1.0 across all phases
        var isCompleted: Bool        // session finished
    }
}
