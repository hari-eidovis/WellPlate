import Foundation

/// Bundles all meal context fields for atomic save with FoodLogEntry.
struct MealContext {
    var mealType: MealType?
    var eatingTriggers: [EatingTrigger]
    var hungerLevel: Double?
    var presenceLevel: Double?
    var reflection: String?

    init(
        mealType: MealType? = nil,
        eatingTriggers: [EatingTrigger] = [],
        hungerLevel: Double? = nil,
        presenceLevel: Double? = nil,
        reflection: String? = nil
    ) {
        self.mealType = mealType
        self.eatingTriggers = eatingTriggers
        self.hungerLevel = hungerLevel
        self.presenceLevel = presenceLevel
        self.reflection = reflection
    }
}
