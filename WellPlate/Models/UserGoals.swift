import Foundation
import SwiftData

@Model
final class UserGoals {

    // MARK: - Hydration

    var waterCupSizeML: Int
    var waterDailyCups: Int
    var coffeeDailyCups: Int = 4

    // MARK: - Nutrition

    var calorieGoal: Int
    var carbsGoalGrams: Int
    var proteinGoalGrams: Int
    var fatGoalGrams: Int
    var sugarGoalGrams: Int
    var fiberGoalGrams: Int
    var sodiumGoalMG: Int

    // MARK: - Exercise (flat per-day to avoid SwiftData [Codable] issues)

    var activeEnergyGoalKcal: Int
    var dailyStepsGoal: Int
    var workoutMinSun: Int
    var workoutMinMon: Int
    var workoutMinTue: Int
    var workoutMinWed: Int
    var workoutMinThu: Int
    var workoutMinFri: Int
    var workoutMinSat: Int

    // MARK: - Sleep

    var sleepGoalHours: Double

    // MARK: - Init

    init(
        waterCupSizeML: Int = 250,
        waterDailyCups: Int = 8,
        coffeeDailyCups: Int = 4,
        calorieGoal: Int = 2000,
        carbsGoalGrams: Int = 220,
        proteinGoalGrams: Int = 150,
        fatGoalGrams: Int = 65,
        sugarGoalGrams: Int = 50,
        fiberGoalGrams: Int = 30,
        sodiumGoalMG: Int = 2300,
        activeEnergyGoalKcal: Int = 500,
        dailyStepsGoal: Int = 10_000,
        workoutMinSun: Int = 0,
        workoutMinMon: Int = 45,
        workoutMinTue: Int = 45,
        workoutMinWed: Int = 45,
        workoutMinThu: Int = 45,
        workoutMinFri: Int = 45,
        workoutMinSat: Int = 0,
        sleepGoalHours: Double = 8.0
    ) {
        self.waterCupSizeML = waterCupSizeML
        self.waterDailyCups = waterDailyCups
        self.coffeeDailyCups = coffeeDailyCups
        self.calorieGoal = calorieGoal
        self.carbsGoalGrams = carbsGoalGrams
        self.proteinGoalGrams = proteinGoalGrams
        self.fatGoalGrams = fatGoalGrams
        self.sugarGoalGrams = sugarGoalGrams
        self.fiberGoalGrams = fiberGoalGrams
        self.sodiumGoalMG = sodiumGoalMG
        self.activeEnergyGoalKcal = activeEnergyGoalKcal
        self.dailyStepsGoal = dailyStepsGoal
        self.workoutMinSun = workoutMinSun
        self.workoutMinMon = workoutMinMon
        self.workoutMinTue = workoutMinTue
        self.workoutMinWed = workoutMinWed
        self.workoutMinThu = workoutMinThu
        self.workoutMinFri = workoutMinFri
        self.workoutMinSat = workoutMinSat
        self.sleepGoalHours = sleepGoalHours
    }

    static func defaults() -> UserGoals { UserGoals() }
}

// MARK: - Per-Day Workout Accessors

extension UserGoals {

    /// Calendar weekday: 1 = Sunday … 7 = Saturday
    func workoutMinutes(for weekday: Int) -> Int {
        switch weekday {
        case 1: return workoutMinSun
        case 2: return workoutMinMon
        case 3: return workoutMinTue
        case 4: return workoutMinWed
        case 5: return workoutMinThu
        case 6: return workoutMinFri
        case 7: return workoutMinSat
        default: return 0
        }
    }

    func setWorkoutMinutes(_ minutes: Int, for weekday: Int) {
        let clamped = min(max(minutes, 0), 480)
        switch weekday {
        case 1: workoutMinSun = clamped
        case 2: workoutMinMon = clamped
        case 3: workoutMinTue = clamped
        case 4: workoutMinWed = clamped
        case 5: workoutMinThu = clamped
        case 6: workoutMinFri = clamped
        case 7: workoutMinSat = clamped
        default: break
        }
    }

    var todayWorkoutGoal: Int {
        workoutMinutes(for: Calendar.current.component(.weekday, from: .now))
    }
}

// MARK: - Singleton Accessor

extension UserGoals {

    @MainActor
    static func current(in context: ModelContext) -> UserGoals {
        let descriptor = FetchDescriptor<UserGoals>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let newGoals = UserGoals.defaults()
        context.insert(newGoals)
        try? context.save()
        return newGoals
    }
}

// MARK: - Reset

extension UserGoals {

    func resetToDefaults() {
        waterCupSizeML = 250
        waterDailyCups = 8
        coffeeDailyCups = 4
        calorieGoal = 2000
        carbsGoalGrams = 220
        proteinGoalGrams = 150
        fatGoalGrams = 65
        sugarGoalGrams = 50
        fiberGoalGrams = 30
        sodiumGoalMG = 2300
        activeEnergyGoalKcal = 500
        dailyStepsGoal = 10_000
        workoutMinSun = 0
        workoutMinMon = 45
        workoutMinTue = 45
        workoutMinWed = 45
        workoutMinThu = 45
        workoutMinFri = 45
        workoutMinSat = 0
        sleepGoalHours = 8.0
    }
}
