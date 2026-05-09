import Foundation
import SwiftData

/// User-typed fallback for sensor data the device cannot supply on a given day.
/// Kept separate from `WellnessDayLog` so logged behaviour and sensor-fallback
/// estimates do not entangle.
@Model
final class ManualDailyInput {
    @Attribute(.unique) var day: Date

    // Morning fields
    var sleepHours: Double?
    var sleepQuality: Int?
    var bedtime: Date?
    var wakeTime: Date?

    // Evening fields
    var screenTimeHours: Double?
    var heavyEveningScreens: Bool?
    var exerciseMinutes: Int?
    var amDaylightOutside: Bool?

    // Prompt bookkeeping
    var morningAskedAt: Date?
    var eveningAskedAt: Date?

    var createdAt: Date

    init(day: Date) {
        self.day = Calendar.current.startOfDay(for: day)
        self.createdAt = .now
    }
}
