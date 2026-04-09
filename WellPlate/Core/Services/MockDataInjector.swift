//
//  MockDataInjector.swift
//  WellPlate
//
//  Generates and injects 30 days of realistic mock data into SwiftData.
//  Controlled from ProfileView. DEBUG only.
//

#if DEBUG
import Foundation
import SwiftData

enum MockDataInjector {

    // MARK: - Public API

    /// Inject 30 days of mock data into SwiftData.
    /// Guards against double-injection via AppConfig flag.
    static func inject(into context: ModelContext) {
        guard !AppConfig.shared.mockDataInjected else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        injectFoodLogs(into: context, today: today, cal: cal)
        injectWellnessLogs(into: context, today: today, cal: cal)
        injectStressReadings(into: context, today: today, cal: cal)

        do {
            try context.save()
            AppConfig.shared.mockDataInjected = true
        } catch {
            WPLogger.app.error("Mock data injection failed: \(error.localizedDescription)")
        }
    }

    /// Remove all mock-injected data.
    static func deleteAll(from context: ModelContext) {
        // 1. FoodLogEntry — delete where logSource == "mock"
        let foodDescriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.logSource == "mock" }
        )
        if let mockFoods = try? context.fetch(foodDescriptor) {
            mockFoods.forEach { context.delete($0) }
        }

        // 2. StressReading — delete where source == "mock"
        let stressDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.source == "mock" }
        )
        if let mockReadings = try? context.fetch(stressDescriptor) {
            mockReadings.forEach { context.delete($0) }
        }

        // 3. WellnessDayLog — delete by tracked dates
        let formatter = ISO8601DateFormatter()
        let trackedDates = AppConfig.shared.mockInjectedWellnessLogDates.compactMap { formatter.date(from: $0) }
        for date in trackedDates {
            let start = date
            let end = Calendar.current.date(byAdding: .second, value: 1, to: start)!
            let descriptor = FetchDescriptor<WellnessDayLog>(
                predicate: #Predicate { $0.day >= start && $0.day < end }
            )
            if let logs = try? context.fetch(descriptor) {
                logs.forEach { context.delete($0) }
            }
        }

        // 4. Save + clear flags
        try? context.save()
        AppConfig.shared.mockDataInjected = false
        AppConfig.shared.mockInjectedWellnessLogDates = []
    }

    // MARK: - Food Logs

    private static let mealTemplates: [(name: String, key: String, serving: String,
                                         cal: Int, protein: Double, carbs: Double,
                                         fat: Double, fiber: Double, meal: String)] = [
        // Breakfast (index 0-4)
        ("Oatmeal with Berries",      "oatmeal_berries",   "1 bowl",   310, 9, 52, 6, 7,   "Breakfast"),
        ("Scrambled Eggs & Toast",    "eggs_toast",         "2 eggs",   350, 22, 28, 16, 2,  "Breakfast"),
        ("Greek Yogurt Parfait",      "yogurt_parfait",     "1 cup",    280, 18, 35, 8, 3,   "Breakfast"),
        ("Avocado Toast",             "avocado_toast",      "2 slices", 320, 10, 30, 18, 7,  "Breakfast"),
        ("Banana Smoothie",           "banana_smoothie",    "1 glass",  260, 8, 45, 5, 4,    "Breakfast"),
        // Lunch (index 5-9)
        ("Grilled Chicken Salad",     "chicken_salad",      "1 plate",  450, 38, 22, 14, 6,  "Lunch"),
        ("Turkey Sandwich",           "turkey_sandwich",    "1 whole",  420, 30, 38, 12, 4,  "Lunch"),
        ("Vegetable Stir Fry",        "veg_stirfry",        "1 bowl",   380, 15, 42, 16, 8,  "Lunch"),
        ("Lentil Soup",               "lentil_soup",        "1 bowl",   340, 18, 45, 8, 12,  "Lunch"),
        ("Quinoa Bowl",               "quinoa_bowl",        "1 bowl",   410, 16, 50, 14, 9,  "Lunch"),
        // Dinner (index 10-14)
        ("Salmon with Rice",          "salmon_rice",        "1 plate",  520, 35, 45, 18, 3,  "Dinner"),
        ("Pasta Primavera",           "pasta_primavera",    "1 plate",  480, 16, 62, 14, 6,  "Dinner"),
        ("Chicken Tikka Masala",      "tikka_masala",       "1 serving", 550, 32, 40, 22, 4, "Dinner"),
        ("Grilled Fish & Vegetables", "fish_vegetables",    "1 plate",  420, 38, 25, 16, 7,  "Dinner"),
        ("Dal with Roti",             "dal_roti",           "2 roti",   460, 18, 55, 12, 10, "Dinner"),
        // Snack (index 15-19)
        ("Greek Yogurt",              "greek_yogurt",       "1 cup",    130, 17, 10, 2, 0,   "Snack"),
        ("Mixed Nuts",                "mixed_nuts",         "1 handful", 180, 5, 8, 16, 3,   "Snack"),
        ("Apple with Peanut Butter",  "apple_pb",           "1 apple",  200, 6, 28, 10, 4,   "Snack"),
        ("Protein Bar",               "protein_bar",        "1 bar",    220, 20, 24, 8, 3,   "Snack"),
        ("Hummus & Carrots",          "hummus_carrots",     "1 cup",    160, 6, 18, 8, 5,    "Snack"),
    ]

    private static func injectFoodLogs(into context: ModelContext, today: Date, cal: Calendar) {
        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let startOfDay = cal.startOfDay(for: day)

            // Breakfast, Lunch, Dinner from rotating templates
            let breakfast = mealTemplates[offset % 5]          // index 0-4
            let lunch     = mealTemplates[5 + (offset % 5)]    // index 5-9
            let dinner    = mealTemplates[10 + (offset % 5)]   // index 10-14

            let meals = offset % 3 == 0
                ? [breakfast, lunch, dinner]
                : [breakfast, lunch, dinner, mealTemplates[15 + (offset % 5)]]  // + snack

            for (i, tmpl) in meals.enumerated() {
                // Stagger createdAt within the day for ordering
                let createdAt = cal.date(byAdding: .hour, value: 7 + i * 4, to: startOfDay) ?? startOfDay
                let entry = FoodLogEntry(
                    day: startOfDay,
                    foodName: tmpl.name,
                    key: tmpl.key,
                    servingSize: tmpl.serving,
                    calories: tmpl.cal,
                    protein: tmpl.protein,
                    carbs: tmpl.carbs,
                    fat: tmpl.fat,
                    fiber: tmpl.fiber,
                    confidence: 0.90,
                    createdAt: createdAt,
                    mealType: tmpl.meal,
                    logSource: "mock" // Convention: used for cleanup. Do not use for real entries.
                )
                context.insert(entry)
            }
        }
    }

    // MARK: - Wellness Logs

    private static func injectWellnessLogs(into context: ModelContext, today: Date, cal: Calendar) {
        // Fetch existing WellnessDayLog dates in the 30-day range to avoid collisions
        let start = cal.date(byAdding: .day, value: -29, to: today)!
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day >= start }
        )
        let existingDays = Set((try? context.fetch(descriptor))?.map { cal.startOfDay(for: $0.day) } ?? [])

        var injectedDates: [String] = []
        let formatter = ISO8601DateFormatter()

        let exerciseValues = [0, 30, 45, 20, 60, 35, 50]
        let calorieValues  = [150, 280, 340, 200, 420, 310, 380]
        let stepValues     = [4200, 6800, 7500, 5100, 9300, 7200, 8400]
        let stressLevels   = ["Excellent", "Good", "Moderate", "Good", "High"]
        let coffeeTypes    = ["Latte", "Americano", "Cappuccino", nil] as [String?]

        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let startOfDay = cal.startOfDay(for: day)
            guard !existingDays.contains(startOfDay) else { continue }

            let log = WellnessDayLog(
                day: startOfDay,
                moodRaw: offset % 5,
                waterGlasses: 3 + (offset % 6),
                exerciseMinutes: exerciseValues[offset % 7],
                caloriesBurned: calorieValues[offset % 7],
                steps: stepValues[offset % 7],
                stressLevel: stressLevels[offset % 5],
                coffeeCups: offset % 4,
                coffeeType: coffeeTypes[offset % 4]
            )
            context.insert(log)
            injectedDates.append(formatter.string(from: startOfDay))
        }

        AppConfig.shared.mockInjectedWellnessLogDates = injectedDates
    }

    // MARK: - Stress Readings

    private static func injectStressReadings(into context: ModelContext, today: Date, cal: Calendar) {
        let hours = [7, 10, 13, 16, 20]
        let baseScores: [[Double]] = [
            [18, 25, 32, 28, 22],
            [22, 30, 38, 35, 25],
            [15, 20, 28, 24, 18],
            [25, 35, 45, 40, 30],
            [20, 28, 35, 30, 24],
        ]

        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let pattern = baseScores[offset % 5]
            let readingCount = 3 + (offset % 3)  // 3, 4, or 5

            for i in 0..<readingCount {
                guard let ts = cal.date(bySettingHour: hours[i], minute: 0, second: 0, of: day) else { continue }
                let score = pattern[i]
                let reading = StressReading(
                    timestamp: ts,
                    score: score,
                    levelLabel: StressLevel(score: score).label,
                    source: "mock"
                )
                context.insert(reading)
            }
        }
    }
}
#endif
