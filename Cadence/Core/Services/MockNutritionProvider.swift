import Foundation

final class MockNutritionProvider: NutritionProvider {
    private let delayProvider: () -> TimeInterval
    private let dataLoader: (String) throws -> NutritionAnalysisResponse

    init(
        delayProvider: @escaping () -> TimeInterval = { AppConfig.shared.mockResponseDelay },
        dataLoader: @escaping (String) throws -> NutritionAnalysisResponse = { try MockDataLoader.load($0) }
    ) {
        self.delayProvider = delayProvider
        self.dataLoader = dataLoader
    }

    func analyze(_ request: NutritionAnalysisRequest) async throws -> NutritionalInfo {
        let delay = max(0, delayProvider())
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        let filename = mockFilename(for: request.foodDescription)
        let response = try dataLoader(filename)

        guard response.success else {
            throw NutritionProviderError.invalidResponseShape
        }

        return response.toNutritionalInfo()
    }

    private func mockFilename(for foodDescription: String) -> String {
        let normalized = foodDescription.lowercased()

        if normalized.contains("salad") {
            return "mock_nutrition_salad"
        }
        if normalized.contains("paratha") {
            return "mock_nutrition_paratha"
        }
        if normalized.contains("biryani") {
            return "mock_nutrition_biryani"
        }

        return "mock_nutrition_default"
    }
}
