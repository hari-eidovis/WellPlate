import Foundation
import SwiftData

/// Persists one row per calendar day capturing mood, hydration, exercise,
/// and stress data. Food data lives separately in `FoodLogEntry`.
@Model
final class WellnessDayLog {
    // MARK: - Stored Properties

    /// Start-of-day timestamp — one record per calendar day.
    @Attribute(.unique) var day: Date

    /// Maps to `MoodOption.rawValue` (0–4). `nil` = not logged.
    var moodRaw: Int?

    /// Number of water glasses consumed (0–8).
    var waterGlasses: Int

    /// Exercise duration in minutes.
    var exerciseMinutes: Int

    /// Active calories burned.
    var caloriesBurned: Int

    /// Step count.
    var steps: Int

    /// Stress level label, e.g. "Excellent", "Good", "Moderate", "High", "Very High". `nil` = not logged.
    var stressLevel: String?

    var createdAt: Date

    // MARK: - Init

    init(
        day: Date,
        moodRaw: Int? = nil,
        waterGlasses: Int = 0,
        exerciseMinutes: Int = 0,
        caloriesBurned: Int = 0,
        steps: Int = 0,
        stressLevel: String? = nil,
        createdAt: Date = .now
    ) {
        self.day = Calendar.current.startOfDay(for: day)
        self.moodRaw = moodRaw
        self.waterGlasses = waterGlasses
        self.exerciseMinutes = exerciseMinutes
        self.caloriesBurned = caloriesBurned
        self.steps = steps
        self.stressLevel = stressLevel
        self.createdAt = createdAt
    }

    // MARK: - Convenience

    /// Resolved `MoodOption` from the stored raw value.
    var mood: MoodOption? {
        guard let raw = moodRaw else { return nil }
        return MoodOption(rawValue: raw)
    }
}
