//
//  NutritionService.swift
//  WellPlate
//
//  Created by Claude on 16.02.2026.
//

import Foundation

/// Implementation of NutritionServiceProtocol using switchable providers
class NutritionService: NutritionServiceProtocol {
    private let liveProvider: NutritionProvider
    private let mockProvider: NutritionProvider

    /// Initialize with provider injection for testing
    init(
        liveProvider: NutritionProvider = GroqNutritionProvider(),
        mockProvider: NutritionProvider = MockNutritionProvider()
    ) {
        self.liveProvider = liveProvider
        self.mockProvider = mockProvider
    }

    /// Analyze food and return nutritional information
    func analyzeFood(request: NutritionAnalysisRequest) async throws -> NutritionalInfo {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        let source = AppConfig.shared.mockMode ? "MOCK" : "LIVE (Groq)"
        print("┌─── 🔍 NUTRITION SERVICE ─────────────────────────")
        print("│ Action: Analyze Food")
        print("│ Food: \"\(request.foodDescription)\"")
        print("│ Provider: \(source)")
        print("└──────────────────────────────────────────────────")
        #endif

        let nutritionalInfo: NutritionalInfo
        if AppConfig.shared.mockMode {
            nutritionalInfo = try await mockProvider.analyze(request)
        } else {
            do {
                nutritionalInfo = try await liveProvider.analyze(request)
            } catch let providerError as NutritionProviderError where Self.shouldFallbackToMock(for: providerError) {
                #if DEBUG
                print("┌─── ⚠️ NUTRITION SERVICE FALLBACK ────────────────")
                print("│ Reason: Groq rate-limit (HTTP 429)")
                print("│ Action: Falling back to mock provider")
                print("└──────────────────────────────────────────────────")
                #endif
                nutritionalInfo = try await mockProvider.analyze(request)
            }
        }

        #if DEBUG
        let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        print("┌─── ✅ NUTRITION SERVICE COMPLETE ─────────────────")
        print("│ Result: \(nutritionalInfo.foodName)")
        print("│ Calories: \(nutritionalInfo.calories) kcal")
        print("│ Total Time: \(elapsed)")
        print("└──────────────────────────────────────────────────")
        #endif

        return nutritionalInfo
    }

    private static func shouldFallbackToMock(for error: NutritionProviderError) -> Bool {
        guard case .requestFailed(let statusCode, _) = error else {
            return false
        }
        return statusCode == 429
    }
}
