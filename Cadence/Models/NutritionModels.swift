//
//  NutritionModels.swift
//  WellPlate
//
//  Created by Claude on 16.02.2026.
//

import Foundation

// MARK: - Request Model

/// Request model for nutrition analysis
struct NutritionAnalysisRequest: Codable {
    let foodDescription: String
    let servingSize: String?

    init(foodDescription: String, servingSize: String? = nil) {
        self.foodDescription = foodDescription
        self.servingSize = servingSize
    }
}

// MARK: - Response Models

/// API response wrapper for nutrition analysis
struct NutritionAnalysisResponse: Codable {
    let success: Bool
    let message: String
    let data: NutritionData

    struct NutritionData: Codable {
        let foodName: String
        let servingSize: String
        let nutrition: NutritionValues
        let confidence: Double?

        struct NutritionValues: Codable {
            let calories: Int
            let protein: Double
            let carbohydrates: Double
            let fat: Double
            let fiber: Double
        }
    }
}

// MARK: - Mapping Extensions

extension NutritionAnalysisResponse {
    /// Convert API response to domain model
    func toNutritionalInfo() -> NutritionalInfo {
        NutritionalInfo(
            foodName: data.foodName,
            servingSize: data.servingSize,
            calories: data.nutrition.calories,
            protein: data.nutrition.protein,
            carbs: data.nutrition.carbohydrates,
            fat: data.nutrition.fat,
            fiber: data.nutrition.fiber,
            confidence: data.confidence
        )
    }
}
