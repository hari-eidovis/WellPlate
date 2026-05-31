import Foundation

struct FoodEntry: Identifiable, Hashable {
    let id: UUID
    let loggedAt: Date
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double

    init(
        id: UUID = UUID(),
        loggedAt: Date = .now,
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
    }
}

struct MacroGoals {
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double

    static let `default` = MacroGoals(
        calories: 2000,
        protein: 60,
        carbs: 225,
        fat: 65,
        fiber: 25
    )
}

struct DailyCalories: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Int
}

struct NutritionEstimate {
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
}
