import XCTest
@testable import WellPlate

final class NutritionServiceTests: XCTestCase {
    private final class StubProvider: NutritionProvider {
        let output: NutritionalInfo

        init(output: NutritionalInfo) {
            self.output = output
        }

        func analyze(_ request: NutritionAnalysisRequest) async throws -> NutritionalInfo {
            output
        }
    }

    private final class ThrowingProvider: NutritionProvider {
        let error: Error

        init(error: Error) {
            self.error = error
        }

        func analyze(_ request: NutritionAnalysisRequest) async throws -> NutritionalInfo {
            throw error
        }
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "app.networking.mockMode")
    }

    func testAnalyzeFoodUsesMockProviderWhenModeIsMock() async throws {
        UserDefaults.standard.set(true, forKey: "app.networking.mockMode")

        let mockInfo = NutritionalInfo(
            foodName: "Mock Meal",
            servingSize: "1 bowl",
            calories: 210,
            protein: 12,
            carbs: 24,
            fat: 7,
            fiber: 4,
            confidence: 0.8
        )
        let liveInfo = NutritionalInfo(
            foodName: "Live Meal",
            servingSize: "1 bowl",
            calories: 999,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            confidence: 0.1
        )

        let service = NutritionService(
            liveProvider: StubProvider(output: liveInfo),
            mockProvider: StubProvider(output: mockInfo)
        )

        let result = try await service.analyzeFood(request: .init(foodDescription: "salad"))
        XCTAssertEqual(result.foodName, "Mock Meal")
        XCTAssertEqual(result.calories, 210)
    }

    func testAnalyzeFoodUsesLiveProviderWhenModeIsRealAPI() async throws {
        UserDefaults.standard.set(false, forKey: "app.networking.mockMode")

        let mockInfo = NutritionalInfo(
            foodName: "Mock Meal",
            servingSize: "1 bowl",
            calories: 210,
            protein: 12,
            carbs: 24,
            fat: 7,
            fiber: 4,
            confidence: 0.8
        )
        let liveInfo = NutritionalInfo(
            foodName: "Live Meal",
            servingSize: "1 plate",
            calories: 420,
            protein: 20,
            carbs: 40,
            fat: 14,
            fiber: 5,
            confidence: 0.9
        )

        let service = NutritionService(
            liveProvider: StubProvider(output: liveInfo),
            mockProvider: StubProvider(output: mockInfo)
        )

        let result = try await service.analyzeFood(request: .init(foodDescription: "biryani"))
        XCTAssertEqual(result.foodName, "Live Meal")
        XCTAssertEqual(result.calories, 420)
    }

    func testAnalyzeFoodFallsBackToMockWhenLiveProviderReturns429() async throws {
        UserDefaults.standard.set(false, forKey: "app.networking.mockMode")

        let mockInfo = NutritionalInfo(
            foodName: "Mock Meal",
            servingSize: "1 cup",
            calories: 155,
            protein: 8,
            carbs: 18,
            fat: 5,
            fiber: 3,
            confidence: 0.7
        )

        let service = NutritionService(
            liveProvider: ThrowingProvider(error: NutritionProviderError.requestFailed(statusCode: 429, message: "quota exceeded")),
            mockProvider: StubProvider(output: mockInfo)
        )

        let result = try await service.analyzeFood(request: .init(foodDescription: "tea"))
        XCTAssertEqual(result.foodName, "Mock Meal")
        XCTAssertEqual(result.calories, 155)
    }

    func testAnalyzeFoodDoesNotFallbackToMockForNon429LiveProviderError() async {
        UserDefaults.standard.set(false, forKey: "app.networking.mockMode")

        let mockInfo = NutritionalInfo(
            foodName: "Mock Meal",
            servingSize: "1 cup",
            calories: 155,
            protein: 8,
            carbs: 18,
            fat: 5,
            fiber: 3,
            confidence: 0.7
        )

        let service = NutritionService(
            liveProvider: ThrowingProvider(error: NutritionProviderError.requestFailed(statusCode: 401, message: "invalid key")),
            mockProvider: StubProvider(output: mockInfo)
        )

        do {
            _ = try await service.analyzeFood(request: .init(foodDescription: "tea"))
            XCTFail("Expected requestFailed")
        } catch let error as NutritionProviderError {
            guard case .requestFailed(let statusCode, _) = error else {
                XCTFail("Expected requestFailed, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 401)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
