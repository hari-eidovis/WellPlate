//
//  NutritionServiceProtocol.swift
//  WellPlate
//
//  Created by Claude on 16.02.2026.
//

import Foundation

/// Protocol for nutrition analysis services
/// Enables dependency injection and testing
protocol NutritionServiceProtocol {
    /// Analyze food and return nutritional information
    /// - Parameter request: The nutrition analysis request
    /// - Returns: Nutritional information for the food
    /// - Throws: APIError if the request fails
    func analyzeFood(request: NutritionAnalysisRequest) async throws -> NutritionalInfo
}
