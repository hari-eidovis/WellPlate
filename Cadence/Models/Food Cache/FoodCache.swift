import Foundation
import SwiftData

@Model
final class FoodCache {
    @Attribute(.unique) var key: String          // normalized (e.g. "paneer butter masala")
    var displayName: String                      // original / canonical
    var servingSize: String?
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var confidence: Double?
    var updatedAt: Date

    init(key: String,
         displayName: String,
         servingSize: String?,
         calories: Int,
         protein: Double,
         carbs: Double,
         fat: Double,
         fiber: Double,
         confidence: Double?,
         updatedAt: Date = .now) {
        self.key = key
        self.displayName = displayName
        self.servingSize = servingSize
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.confidence = confidence
        self.updatedAt = updatedAt
    }
}
