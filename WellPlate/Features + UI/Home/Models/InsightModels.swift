import SwiftUI

// MARK: - WellnessDomain

enum WellnessDomain: String, CaseIterable {
    case stress, nutrition, sleep, activity, hydration, caffeine, mood, fasting, symptoms, cross, supplements

    var label: String {
        switch self {
        case .stress:    return "Stress"
        case .nutrition: return "Nutrition"
        case .sleep:     return "Sleep"
        case .activity:  return "Activity"
        case .hydration: return "Hydration"
        case .caffeine:  return "Caffeine"
        case .mood:      return "Mood"
        case .fasting:   return "Fasting"
        case .symptoms:  return "Symptoms"
        case .cross:        return "Patterns"
        case .supplements:  return "Supplements"
        }
    }

    var icon: String {
        switch self {
        case .stress:    return "brain.head.profile.fill"
        case .nutrition: return "fork.knife"
        case .sleep:     return "moon.zzz.fill"
        case .activity:  return "figure.walk"
        case .hydration: return "drop.fill"
        case .caffeine:  return "cup.and.saucer.fill"
        case .mood:      return "face.smiling"
        case .fasting:   return "timer"
        case .symptoms:  return "stethoscope"
        case .cross:        return "arrow.triangle.swap"
        case .supplements:  return "pill.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .stress:    return Color(hue: 0.76, saturation: 0.50, brightness: 0.75)
        case .nutrition: return AppColors.brand
        case .sleep:     return .indigo
        case .activity:  return .green
        case .hydration: return Color(hue: 0.58, saturation: 0.68, brightness: 0.82)
        case .caffeine:  return Color(hue: 0.10, saturation: 0.75, brightness: 0.88)
        case .mood:      return Color(hue: 0.14, saturation: 0.70, brightness: 0.95)
        case .fasting:   return .orange
        case .symptoms:  return AppColors.error
        case .cross:        return AppColors.brand
        case .supplements:  return Color(hue: 0.72, saturation: 0.50, brightness: 0.80)
        }
    }
}

// MARK: - InsightType

enum InsightType: String, CaseIterable {
    case trend
    case correlation
    case milestone
    case imbalance
    case sleepQuality
    case reinforcement

    var label: String {
        switch self {
        case .trend:         return "Trend"
        case .correlation:   return "Pattern"
        case .milestone:     return "Milestone"
        case .imbalance:     return "Alert"
        case .sleepQuality:  return "Sleep"
        case .reinforcement: return "Win"
        }
    }

    var icon: String {
        switch self {
        case .trend:         return "chart.line.uptrend.xyaxis"
        case .correlation:   return "arrow.triangle.swap"
        case .milestone:     return "star.fill"
        case .imbalance:     return "exclamationmark.triangle.fill"
        case .sleepQuality:  return "moon.stars.fill"
        case .reinforcement: return "checkmark.seal.fill"
        }
    }
}

// MARK: - InsightChartData

enum InsightChartData {
    case trendLine(points: [(date: Date, value: Double)], goalLine: Double?, metricLabel: String, unit: String)
    case correlationScatter(points: [(x: Double, y: Double)], r: Double, xLabel: String, yLabel: String)
    case comparisonBars(bars: [(label: String, value: Double, domain: WellnessDomain)], highlight: Int?)
    case macroRadar(actual: [String: Double], goals: [String: Double])
    case milestoneRing(current: Int, target: Int, streakLabel: String)
    case sparkline(points: [Double])
}

// MARK: - InsightCard

struct InsightCard: Identifiable, Equatable, Hashable {
    let id: UUID
    let type: InsightType
    let domain: WellnessDomain
    var headline: String
    var narrative: String
    let chartData: InsightChartData
    let priority: Double
    var isLLMGenerated: Bool
    let generatedAt: Date
    var detailSuggestions: [String]

    static func == (lhs: InsightCard, rhs: InsightCard) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - WellnessDaySummary

struct WellnessDaySummary {
    let date: Date
    // Stress
    let stressScore: Double?
    let stressLabel: String?
    // Sleep
    let sleepHours: Double?
    let deepSleepHours: Double?
    let remSleepHours: Double?
    let bedtime: Date?
    let wakeTime: Date?
    // Activity
    let steps: Int?
    let activeCalories: Int?
    let exerciseMinutes: Int?
    let heartRateAvg: Double?
    // Nutrition
    let totalCalories: Int?
    let totalProteinG: Double?
    let totalCarbsG: Double?
    let totalFatG: Double?
    let totalFiberG: Double?
    let mealCount: Int
    // Hydration & Caffeine
    let waterGlasses: Int?
    let coffeeCups: Int?
    // Mood
    let moodLabel: String?
    // Symptoms
    let symptomNames: [String]
    let symptomMaxSeverity: Int?
    // Fasting
    let fastingHours: Double?
    let fastingCompleted: Bool?
    // Supplements
    let supplementAdherence: Double?
    // Journal
    let journalLogged: Bool

    // Report-specific fields (var with defaults — preserves memberwise init)
    var eatingTriggers: [String: Int] = [:]
    var mealTypes: [String: Int] = [:]
    var foodNames: [String] = []
    var coffeeType: String? = nil
    var mealTimestamps: [Date] = []
    var interventionSessions: [(type: String, stressDelta: Double?)] = []
    // Stress detail
    var stressMin: Double? = nil
    var stressMax: Double? = nil
    var stressReadingCount: Int = 0
    // Vitals
    var restingHeartRateAvg: Double? = nil
    var hrvAvg: Double? = nil
    var systolicBPAvg: Double? = nil
    var diastolicBPAvg: Double? = nil
    var respiratoryRateAvg: Double? = nil
    var daylightMinutes: Double? = nil
}

// MARK: - WellnessContext

struct WellnessContext {
    let days: [WellnessDaySummary]
    let goals: UserGoalsSnapshot
    let dataQualityNote: String
}

// MARK: - UserGoalsSnapshot

struct UserGoalsSnapshot {
    let calorieGoal: Int
    let proteinGoalGrams: Int
    let carbsGoalGrams: Int
    let fatGoalGrams: Int
    let fiberGoalGrams: Int
    let waterDailyCups: Int
    let coffeeDailyCups: Int
    let dailyStepsGoal: Int
    let activeEnergyGoalKcal: Int
    let sleepGoalHours: Double

    init(from goals: UserGoals) {
        self.calorieGoal = goals.calorieGoal
        self.proteinGoalGrams = goals.proteinGoalGrams
        self.carbsGoalGrams = goals.carbsGoalGrams
        self.fatGoalGrams = goals.fatGoalGrams
        self.fiberGoalGrams = goals.fiberGoalGrams
        self.waterDailyCups = goals.waterDailyCups
        self.coffeeDailyCups = goals.coffeeDailyCups
        self.dailyStepsGoal = goals.dailyStepsGoal
        self.activeEnergyGoalKcal = goals.activeEnergyGoalKcal
        self.sleepGoalHours = goals.sleepGoalHours
    }
}
