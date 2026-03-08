import Foundation
import SwiftData
import WidgetKit

enum WidgetRefreshHelper {

    @MainActor
    static func refresh(goals: UserGoals, context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day == today }
        )
        let entries = (try? context.fetch(descriptor)) ?? []

        let recentFoods = entries
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(3)
            .map { WidgetFoodItem(id: $0.id, name: $0.foodName, calories: $0.calories) }

        let widgetData = WidgetFoodData(
            totalCalories: entries.reduce(0) { $0 + $1.calories },
            totalProtein:  entries.reduce(0.0) { $0 + $1.protein },
            totalCarbs:    entries.reduce(0.0) { $0 + $1.carbs },
            totalFat:      entries.reduce(0.0) { $0 + $1.fat },
            recentFoods:   Array(recentFoods),
            calorieGoal:   goals.calorieGoal,
            proteinGoal:   Double(goals.proteinGoalGrams),
            carbsGoal:     Double(goals.carbsGoalGrams),
            fatGoal:       Double(goals.fatGoalGrams),
            lastUpdated:   .now
        )
        widgetData.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "com.hariom.wellplate.foodWidget")
    }
}
