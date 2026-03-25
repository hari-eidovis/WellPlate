import Foundation

// MARK: - StressInsightReport
//
// Public output type consumed by HomeAIInsightView.
// No FoundationModels dependency — safe to use in any target.
// Phase 2: move to WellPlate/Models/ if consumed outside the Home feature.

struct StressInsightReport {
    /// Short editorial headline, max ~12 words.
    let headline: String
    /// 2–3 sentence narrative summary of recent stress patterns.
    let summary: String
    /// The factor that most helped reduce stress over the lookback window.
    let strongestPositiveFactor: String
    /// The factor that most contributed to elevated stress.
    let strongestNegativeFactor: String
    /// 2 specific, actionable suggestions.
    let suggestions: [String]
    /// Non-empty when some data categories were unavailable.
    let cautionNote: String
    /// When the report was generated (used for same-day cache key).
    let generatedAt: Date
    /// True when Foundation Models was unavailable OR mock mode is active.
    let isTemplateGenerated: Bool
    /// Per-day summaries used for chart rendering — oldest first.
    let days: [StressInsightDaySummary]
}

// MARK: - StressInsightContext (internal to StressInsightService)
//
// Compact aggregated summary of the lookback window.
// This is what gets serialised into the Foundation Models prompt.

struct StressInsightContext {
    /// Per-day summaries, oldest first.
    let days: [StressInsightDaySummary]
    /// Describes missing data categories; empty when all data is present.
    let dataQualityNote: String
}

// MARK: - StressInsightDaySummary

struct StressInsightDaySummary {
    let date: Date
    /// Average StressReading.score for this calendar day (0–100).
    let stressScore: Double?
    /// WellnessDayLog.stressLevel label, e.g. "High".
    let stressLabel: String?
    /// HealthKit: total sleep hours last night.
    let sleepHours: Double?
    /// HealthKit: deep sleep hours (subset of sleepHours).
    let deepSleepHours: Double?
    /// HealthKit: total step count.
    let steps: Int?
    /// HealthKit: active calories burned.
    let activeCalories: Int?
    /// HealthKit: average heart rate in bpm.
    let heartRateAvg: Double?
    /// WellnessDayLog: water glasses consumed.
    let waterGlasses: Int?
    /// WellnessDayLog: coffee cups consumed.
    let coffeeCups: Int?
    /// WellnessDayLog: resolved mood label, e.g. "Happy".
    let moodLabel: String?
    /// FoodLogEntry: total calories summed across all meals.
    let totalCalories: Int?
    /// FoodLogEntry: total protein grams summed.
    let totalProteinG: Double?
    /// FoodLogEntry: total fiber grams summed.
    let totalFiberG: Double?
    /// FoodLogEntry: total fat grams summed.
    let totalFatG: Double?
    /// FoodLogEntry: total carbohydrate grams summed.
    let totalCarbsG: Double?
    /// FoodLogEntry: number of meals logged.
    let mealCount: Int
}
