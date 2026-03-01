import Foundation
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - FoodExtraction (Public domain model — no @Generable)
//
// Result of MealCoachService parsing a freeform food input.
// Uses sentinel strings instead of Optionals (audit fix #3).

struct FoodExtraction {
    /// Canonical food name, e.g. "overnight oats with banana"
    let foodName: String
    /// Serving size, e.g. "1 cup" or "unknown" if not specified
    let portion: String
    /// Confidence 0.0–1.0. Values below 0.6 trigger disambiguation.
    let confidence: Double
    /// Question to clarify the food, or empty string if confident
    let clarifyingQuestion: String

    var needsDisambiguation: Bool {
        confidence < 0.6 && !clarifyingQuestion.isEmpty
    }

    /// Passthrough fallback — uses raw input as-is.
    static func passthrough(_ raw: String) -> FoodExtraction {
        FoodExtraction(
            foodName: raw,
            portion: "unknown",
            confidence: 1.0,
            clarifyingQuestion: ""
        )
    }
}

// MARK: - DisambiguationState

struct DisambiguationState {
    let question: String
    let options: [FoodOption]
    let rawInput: String
}

// MARK: - MealCoachService
//
// Parses freeform meal input into a canonical FoodExtraction using FoundationModels.
// Falls back to FoodExtraction.passthrough on unsupported devices.

final class MealCoachService: ObservableObject {

    // MARK: - Public API

    /// Extracts a canonical FoodExtraction from freeform user input.
    func extractFoodEntry(from rawInput: String) async -> FoodExtraction {
        guard !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .passthrough(rawInput)
        }

        if #available(iOS 26, *) {
            return (try? await extractWithFoundationModels(raw: rawInput))
                ?? .passthrough(rawInput)
        }
        return .passthrough(rawInput)
    }

    /// Generates 2–3 FoodOption variants for an ambiguous input.
    func generateOptions(for ambiguousInput: String) async -> [FoodOption] {
        if #available(iOS 26, *) {
            return (try? await generateOptionsWithFoundationModels(for: ambiguousInput)) ?? []
        }
        return []
    }

    // MARK: - Foundation Models (iOS 26+)

    @available(iOS 26, *)
    private func extractWithFoundationModels(raw: String) async throws -> FoodExtraction {
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let prompt = """
        The user typed this into a food logging app: "\(raw)"
        Extract the food information. If multiple very different foods are possible, set confidence below 0.6 and provide a clarifying question.
        Use "unknown" for portion if not specified. Never use null or nil.
        """
        let result = try await session.respond(
            to: prompt,
            generating: _FoodExtractionSchema.self
        )
        let schema = result.content
        return FoodExtraction(
            foodName: schema.foodName,
            portion: schema.portion,
            confidence: schema.confidence,
            clarifyingQuestion: schema.clarifyingQuestion
        )
        #else
        throw CoachError.unsupported
        #endif
    }

    @available(iOS 26, *)
    private func generateOptionsWithFoundationModels(for input: String) async throws -> [FoodOption] {
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let prompt = """
        The user typed "\(input)" into a food logging app.
        Generate exactly 3 specific, common interpretations as food options with realistic calorie estimates.
        """
        let result = try await session.respond(
            to: prompt,
            generating: _FoodOptionsSchema.self
        )
        return result.content.options.map {
            FoodOption(label: $0.label, calorieEstimate: $0.calorieEstimate)
        }
        #else
        throw CoachError.unsupported
        #endif
    }
}

// MARK: - Internal @Generable Schemas (iOS 26+, private to this file)

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct _FoodExtractionSchema {
    @Guide(description: "Canonical food name, e.g. 'overnight oats with banana, 1 cup'")
    var foodName: String
    @Guide(description: "Serving size, e.g. '2 cups', or 'unknown' if not mentioned")
    var portion: String
    @Guide(description: "Confidence from 0.0 (very ambiguous) to 1.0 (very specific)")
    var confidence: Double
    @Guide(description: "Clarifying question for the user, or empty string if confident")
    var clarifyingQuestion: String
}

@available(iOS 26, *)
@Generable
private struct _FoodOptionsSchema {
    @Guide(description: "Exactly 3 distinct, specific interpretations of the food input")
    var options: [_FoodOptionSchema]
}

@available(iOS 26, *)
@Generable
private struct _FoodOptionSchema {
    @Guide(description: "Specific food description, e.g. 'Thin-crust pizza slice'")
    var label: String
    @Guide(description: "Realistic calorie estimate as an integer, e.g. 220")
    var calorieEstimate: Int
}
#endif

// MARK: - Errors

private enum CoachError: Error {
    case unsupported
}
