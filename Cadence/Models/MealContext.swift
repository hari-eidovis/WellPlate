import Foundation

/// Bundles all meal context fields for atomic save with FoodLogEntry.
struct MealContext {
    var mealType: MealType?
    var eatingTriggers: [EatingTrigger]
    var hungerLevel: Double?
    var presenceLevel: Double?
    var reflection: String?
    /// Raw quantity string as entered by the user, e.g. "250"
    var quantity: String?
    /// Unit string, either "g" or "ml"
    var quantityUnit: String?

    /// Formatted serving string passed to the nutrition API, e.g. "250 ml". Nil when quantity is blank.
    var formattedServing: String? {
        guard let qty = quantity, !qty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let unit = quantityUnit else { return nil }
        return "\(qty.trimmingCharacters(in: .whitespacesAndNewlines)) \(unit)"
    }

    init(
        mealType: MealType? = nil,
        eatingTriggers: [EatingTrigger] = [],
        hungerLevel: Double? = nil,
        presenceLevel: Double? = nil,
        reflection: String? = nil,
        quantity: String? = nil,
        quantityUnit: String? = nil
    ) {
        self.mealType = mealType
        self.eatingTriggers = eatingTriggers
        self.hungerLevel = hungerLevel
        self.presenceLevel = presenceLevel
        self.reflection = reflection
        self.quantity = quantity
        self.quantityUnit = quantityUnit
    }
}
