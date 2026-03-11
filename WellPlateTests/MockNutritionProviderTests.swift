import XCTest
@testable import WellPlate

final class MockNutritionProviderTests: XCTestCase {
    private func sampleResponse(foodName: String) -> NutritionAnalysisResponse {
        NutritionAnalysisResponse(
            success: true,
            message: "ok",
            data: .init(
                foodName: foodName,
                servingSize: "1 serving",
                nutrition: .init(
                    calories: 100,
                    protein: 10,
                    carbohydrates: 12,
                    fat: 4,
                    fiber: 2
                ),
                confidence: 0.9
            )
        )
    }

    func testAnalyzeUsesSaladMockForSaladInput() async throws {
        var loadedFilename: String?

        let provider = MockNutritionProvider(
            delayProvider: { 0 },
            dataLoader: { filename in
                loadedFilename = filename
                return self.sampleResponse(foodName: "Salad")
            }
        )

        _ = try await provider.analyze(.init(foodDescription: "green salad with olive oil"))
        XCTAssertEqual(loadedFilename, "mock_nutrition_salad")
    }

    func testAnalyzeUsesDefaultMockWhenNoKeywordMatches() async throws {
        var loadedFilename: String?

        let provider = MockNutritionProvider(
            delayProvider: { 0 },
            dataLoader: { filename in
                loadedFilename = filename
                return self.sampleResponse(foodName: "Default")
            }
        )

        _ = try await provider.analyze(.init(foodDescription: "tofu sandwich"))
        XCTAssertEqual(loadedFilename, "mock_nutrition_default")
    }
}
