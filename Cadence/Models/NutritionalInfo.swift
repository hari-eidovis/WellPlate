import Foundation
import SwiftUI
import SwiftData

struct NutritionalInfo: Codable, Identifiable,Equatable {
    let id: UUID
    let foodName: String
    let servingSize: String?
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let confidence: Double?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        foodName: String,
        servingSize: String? = nil,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double = 0,
        confidence: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.foodName = foodName
        self.servingSize = servingSize
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.confidence = confidence
        self.timestamp = timestamp
    }
}
