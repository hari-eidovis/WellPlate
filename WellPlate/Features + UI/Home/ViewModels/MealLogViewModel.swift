import Foundation
import SwiftData
import Combine

// MARK: - QuantityUnit

/// Unit for user-entered meal quantity. Drives the g / ml toggle in MealLogView.
enum QuantityUnit: String, CaseIterable, Identifiable {
    case grams = "g"
    case millilitres = "ml"

    var id: String { rawValue }

    var label: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .grams: return "scalemass"
        case .millilitres: return "drop"
        }
    }
}

// MARK: - MealLogViewModel

@MainActor
final class MealLogViewModel: ObservableObject {
    // MARK: - Form state
    @Published var selectedMealType: MealType
    @Published var foodDescription: String = ""
    @Published var selectedTriggers: Set<EatingTrigger> = []
    @Published var hungerLevel: Double = 0.5
    @Published var presenceLevel: Double = 0.5
    @Published var reflection: String = ""
    @Published var showMoreContext: Bool = false

    // MARK: - Quantity state
    /// Numeric amount entered by the user (e.g. "250"). Empty string means not specified.
    @Published var quantity: String = ""
    /// Unit for the quantity — g for solid food, ml for drinks/liquids.
    @Published var quantityUnit: QuantityUnit = .grams

    // MARK: - Save flow state
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var disambiguationState: DisambiguationState?
    /// Set to true on successful save so the view can dismiss the sheet.
    @Published var shouldDismiss: Bool = false

    private let mealCoach = MealCoachService()
    private weak var homeViewModel: HomeViewModel?

    var isValid: Bool {
        !foodDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Formatted serving passed to the API, e.g. "250 ml". Nil when quantity field is blank.
    var formattedServing: String? {
        let trimmed = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "\(trimmed) \(quantityUnit.rawValue)"
    }

    var currentMealContext: MealContext {
        MealContext(
            mealType: selectedMealType,
            eatingTriggers: Array(selectedTriggers),
            hungerLevel: hungerLevel,
            presenceLevel: presenceLevel,
            reflection: reflection.isEmpty ? nil : reflection,
            quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            quantityUnit: quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : quantityUnit.rawValue
        )
    }

    init(homeViewModel: HomeViewModel?, selectedDate: Date = Date()) {
        self.homeViewModel = homeViewModel
        self.selectedMealType = MealType.current(for: selectedDate)
    }

    /// Call from view when user taps "Save & Reflect". Handles extraction, disambiguation, and final log.
    func saveMeal(selectedDate: Date) async {
        let rawInput = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else {
            showErrorMessage("Please enter what you ate.")
            return
        }
        guard let home = homeViewModel else {
            showErrorMessage("Unable to save.")
            return
        }

        isLoading = true
        disambiguationState = nil
        defer { isLoading = false }

        let extraction = await mealCoach.extractFoodEntry(from: rawInput)

        if extraction.needsDisambiguation {
            let options = await mealCoach.generateOptions(for: rawInput)
            if !options.isEmpty {
                disambiguationState = DisambiguationState(
                    question: extraction.clarifyingQuestion,
                    options: options,
                    rawInput: rawInput
                )
                return
            }
        }

        await performLog(
            home: home,
            selectedDate: selectedDate,
            canonicalName: extraction.foodName,
            coachOverride: nil
        )
    }

    /// Called when user selects a disambiguation chip.
    func resolveWithOption(_ option: FoodOption, selectedDate: Date) async {
        guard let home = homeViewModel else { return }
        disambiguationState = nil
        home.foodDescription = option.label
        await performLog(
            home: home,
            selectedDate: selectedDate,
            canonicalName: option.label,
            coachOverride: option.label
        )
    }

    /// Called when user taps "Add as typed" in disambiguation.
    func resolveWithRawInput(selectedDate: Date) async {
        guard let state = disambiguationState else { return }
        guard let home = homeViewModel else { return }
        disambiguationState = nil
        home.foodDescription = state.rawInput
        await performLog(
            home: home,
            selectedDate: selectedDate,
            canonicalName: state.rawInput,
            coachOverride: state.rawInput
        )
    }

    private func performLog(
        home: HomeViewModel,
        selectedDate: Date,
        canonicalName: String,
        coachOverride: String?
    ) async {
        home.foodDescription = canonicalName
        let context = currentMealContext
        await home.logFood(on: selectedDate, coachOverride: coachOverride, context: context)

        if home.showError {
            errorMessage = home.errorMessage
            showError = true
        } else {
            shouldDismiss = true
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
