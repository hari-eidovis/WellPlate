import Foundation
import SwiftUI

@MainActor
final class PlaygroundStore: ObservableObject {
    @Published var draftFood: String = ""
    @Published var entries: [FoodEntry] = []
    @Published var todaySteps: Double = 7800
    @Published var todayActiveEnergy: Double = 430
    @Published var lastNightSleepHours: Double = 7.2
    @Published var lastNightDeepSleepHours: Double = 1.5
    @Published var manualScreenTimeHours: Double = 3.0

    let goals = MacroGoals.default

    init() {
        resetDemo()
    }

    var totalCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    var totalProtein: Double {
        entries.reduce(0) { $0 + $1.protein }
    }

    var totalCarbs: Double {
        entries.reduce(0) { $0 + $1.carbs }
    }

    var totalFat: Double {
        entries.reduce(0) { $0 + $1.fat }
    }

    var totalFiber: Double {
        entries.reduce(0) { $0 + $1.fiber }
    }

    var calorieProgress: Double {
        guard goals.calories > 0 else { return 0 }
        return min(Double(totalCalories) / Double(goals.calories), 1.0)
    }

    var proteinProgress: Double {
        guard goals.protein > 0 else { return 0 }
        return min(totalProtein / goals.protein, 1.0)
    }

    var carbsProgress: Double {
        guard goals.carbs > 0 else { return 0 }
        return min(totalCarbs / goals.carbs, 1.0)
    }

    var fatProgress: Double {
        guard goals.fat > 0 else { return 0 }
        return min(totalFat / goals.fat, 1.0)
    }

    var weeklyCalories: [DailyCalories] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let total = entries
                .filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.calories }
            return DailyCalories(date: day, calories: total)
        }
        .reversed()
    }

    func addDraftFood() {
        let trimmed = draftFood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addFood(named: trimmed)
        draftFood = ""
    }

    func addFood(named name: String) {
        let estimate = estimateNutrition(for: name)
        entries.append(
            FoodEntry(
                name: name,
                calories: estimate.calories,
                protein: estimate.protein,
                carbs: estimate.carbs,
                fat: estimate.fat,
                fiber: estimate.fiber
            )
        )
        entries.sort { $0.loggedAt > $1.loggedAt }
    }

    func remove(_ entry: FoodEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func resetDemo() {
        let now = Date()
        entries = [
            FoodEntry(
                loggedAt: now.addingTimeInterval(-60 * 60 * 5),
                name: "Oatmeal Bowl",
                calories: 320,
                protein: 11,
                carbs: 52,
                fat: 8,
                fiber: 7
            ),
            FoodEntry(
                loggedAt: now.addingTimeInterval(-60 * 60 * 3),
                name: "Grilled Chicken Rice",
                calories: 540,
                protein: 34,
                carbs: 58,
                fat: 14,
                fiber: 4
            ),
            FoodEntry(
                loggedAt: now.addingTimeInterval(-60 * 60),
                name: "Greek Yogurt",
                calories: 140,
                protein: 12,
                carbs: 10,
                fat: 4,
                fiber: 0
            ),
        ]
        todaySteps = 7800
        todayActiveEnergy = 430
        lastNightSleepHours = 7.2
        lastNightDeepSleepHours = 1.5
        manualScreenTimeHours = 3.0
        draftFood = ""
    }

    private func estimateNutrition(for raw: String) -> NutritionEstimate {
        let query = raw.lowercased()
        let catalog: [(name: String, estimate: NutritionEstimate)] = [
            ("apple", .init(calories: 95, protein: 0.5, carbs: 25, fat: 0.3, fiber: 4.4)),
            ("banana", .init(calories: 105, protein: 1.3, carbs: 27, fat: 0.3, fiber: 3.1)),
            ("salad", .init(calories: 220, protein: 8, carbs: 18, fat: 12, fiber: 6)),
            ("biryani", .init(calories: 640, protein: 22, carbs: 75, fat: 24, fiber: 4)),
            ("dal", .init(calories: 260, protein: 13, carbs: 34, fat: 7, fiber: 8)),
            ("rice", .init(calories: 210, protein: 4, carbs: 45, fat: 0.5, fiber: 0.8)),
            ("egg", .init(calories: 78, protein: 6, carbs: 0.6, fat: 5.3, fiber: 0)),
            ("paneer", .init(calories: 320, protein: 18, carbs: 8, fat: 22, fiber: 0)),
            ("chicken", .init(calories: 250, protein: 28, carbs: 2, fat: 13, fiber: 0)),
            ("yogurt", .init(calories: 140, protein: 12, carbs: 10, fat: 4, fiber: 0)),
            ("oats", .init(calories: 320, protein: 11, carbs: 52, fat: 8, fiber: 7)),
            ("smoothie", .init(calories: 280, protein: 9, carbs: 44, fat: 7, fiber: 6)),
        ]

        if let matched = catalog.first(where: { query.contains($0.name) }) {
            return matched.estimate
        }

        // Simple fallback so free-form text still feels consistent in demo mode.
        let wordCount = max(1, query.split(separator: " ").count)
        let calories = min(700, 140 + wordCount * 70)
        let protein = Double(wordCount * 4 + 4)
        let carbs = Double(wordCount * 11 + 12)
        let fat = Double(wordCount * 3 + 4)
        let fiber = Double(max(1, wordCount))

        return NutritionEstimate(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber
        )
    }
}
