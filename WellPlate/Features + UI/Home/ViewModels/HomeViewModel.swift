import Foundation
import SwiftData
import Combine
import WidgetKit

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var foodDescription: String = ""
    @Published var servingSize: String = ""
    @Published var nutritionalInfo: NutritionalInfo?
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    /// Non-nil when MealCoachService needs the user to pick between alternatives.
    @Published var disambiguationState: DisambiguationState?

    private let nutritionService: NutritionServiceProtocol
    private let mealCoach: MealCoachService
    private var modelContext: ModelContext!

    /// Lightweight init for `@StateObject` — no `ModelContext` needed yet.
    @MainActor
    init() {
        self.nutritionService = NutritionService()
        self.mealCoach = MealCoachService()
    }

    /// Full init for previews / tests where ModelContext is immediately available.
    @MainActor
    init(
        modelContext: ModelContext,
        nutritionService: NutritionServiceProtocol = NutritionService(),
        mealCoach: MealCoachService = MealCoachService()
    ) {
        self.modelContext = modelContext
        self.nutritionService = nutritionService
        self.mealCoach = mealCoach
    }

    /// Call from `.onAppear` to inject the SwiftData context once the environment is available.
    func bindContext(_ context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context
    }

    func logFood(on date: Date, coachOverride: String? = nil) async {
        let rawInput = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { showErrorMessage("Please enter a food description"); return }

        isLoading = true
        defer { isLoading = false }

        // 1) Run MealCoachService to canonicalize input (falls back to raw on older OS)
        let extraction: FoodExtraction
        if let override = coachOverride {
            // Called from disambiguation chip selection — skip coach, use chip label directly
            extraction = FoodExtraction(foodName: override, portion: "unknown", confidence: 1.0, clarifyingQuestion: "")
        } else {
            extraction = await mealCoach.extractFoodEntry(from: rawInput)
        }

        // 2) If confidence is low and a clarifying question exists, surface disambiguation
        if extraction.needsDisambiguation && coachOverride == nil {
            let options = await mealCoach.generateOptions(for: rawInput)
            if !options.isEmpty {
                isLoading = false
                disambiguationState = DisambiguationState(
                    question: extraction.clarifyingQuestion,
                    options: options,
                    rawInput: rawInput
                )
                return
            }
            // If option generation failed, fall through and log with extracted name
        }

        let canonicalName = extraction.foodName
        let day = Calendar.current.startOfDay(for: date)
        let key = normalizeFoodKey(canonicalName)  // audit fix #7: key from coach-extracted name

        do {
            // 3) Cache lookup
            if let cached = try fetchCache(key: key) {
                insertLog(from: cached, day: day, typedName: canonicalName, key: key)
                nutritionalInfo = NutritionalInfo(
                    foodName: cached.displayName,
                    servingSize: cached.servingSize,
                    calories: cached.calories,
                    protein: cached.protein,
                    carbs: cached.carbs,
                    fat: cached.fat,
                    fiber: cached.fiber,
                    confidence: cached.confidence
                )
                try modelContext.save()
                refreshWidget(for: day)
                return
            }

            // 4) API call using canonical name
            let request = NutritionAnalysisRequest(
                foodDescription: canonicalName,
                servingSize: servingSize.isEmpty ? nil : servingSize
            )
            let result = try await nutritionService.analyzeFood(request: request)
            nutritionalInfo = result

            // 5) Upsert cache + insert log
            try upsertCache(from: result, key: key, displayName: canonicalName)
            insertLog(from: result, day: day, typedName: canonicalName, key: key)

            try modelContext.save()
            refreshWidget(for: day)
        } catch {
            showErrorMessage("Failed to log food. Please try again.")
        }
    }

    private func fetchCache(key: String) throws -> FoodCache? {
        let fd = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.key == key })
        return try modelContext.fetch(fd).first
    }

    private func upsertCache(from info: NutritionalInfo, key: String, displayName: String) throws {
        if let existing = try fetchCache(key: key) {
            existing.displayName = displayName
            existing.servingSize = info.servingSize
            existing.calories = info.calories
            existing.protein = info.protein
            existing.carbs = info.carbs
            existing.fat = info.fat
            existing.fiber = info.fiber
            existing.confidence = info.confidence
            existing.updatedAt = .now
        } else {
            let cache = FoodCache(
                key: key,
                displayName: displayName,
                servingSize: info.servingSize,
                calories: info.calories,
                protein: info.protein,
                carbs: info.carbs,
                fat: info.fat,
                fiber: info.fiber,
                confidence: info.confidence
            )
            modelContext.insert(cache)
        }
    }

    private func insertLog(from cache: FoodCache, day: Date, typedName: String, key: String) {
        let entry = FoodLogEntry(
            day: day,
            foodName: typedName,
            key: key,
            servingSize: cache.servingSize,
            calories: cache.calories,
            protein: cache.protein,
            carbs: cache.carbs,
            fat: cache.fat,
            fiber: cache.fiber,
            confidence: cache.confidence
        )
        modelContext.insert(entry)
    }

    private func insertLog(from info: NutritionalInfo, day: Date, typedName: String, key: String) {
        let entry = FoodLogEntry(
            day: day,
            foodName: typedName,
            key: key,
            servingSize: info.servingSize,
            calories: info.calories,
            protein: info.protein,
            carbs: info.carbs,
            fat: info.fat,
            fiber: info.fiber,
            confidence: info.confidence
        )
        modelContext.insert(entry)
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    // MARK: - Widget Refresh

    /// Aggregates today's food logs, writes to AppGroup UserDefaults, then tells
    /// WidgetKit to reload the food widget timeline.
    private func refreshWidget(for day: Date) {
        let descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day == day }
        )
        guard let entries = try? modelContext.fetch(descriptor) else { return }

        let recentFoods = entries
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(3)
            .map { WidgetFoodItem(id: $0.id, name: $0.foodName, calories: $0.calories) }

        let widgetData = WidgetFoodData(
            totalCalories: entries.reduce(0) { $0 + $1.calories },
            totalProtein:  entries.reduce(0.0) { $0 + $1.protein },
            totalCarbs:    entries.reduce(0.0) { $0 + $1.carbs },
            totalFat:      entries.reduce(0.0) { $0 + $1.fat },
            recentFoods:   Array(recentFoods),
            calorieGoal:   2000,
            proteinGoal:   60,
            carbsGoal:     225,
            fatGoal:       65,
            lastUpdated:   .now
        )
        widgetData.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "com.hariom.wellplate.foodWidget")
    }
}
