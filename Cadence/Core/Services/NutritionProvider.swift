import Foundation

/// Internal provider abstraction for nutrition analysis.
protocol NutritionProvider {
    func analyze(_ request: NutritionAnalysisRequest) async throws -> NutritionalInfo
}
