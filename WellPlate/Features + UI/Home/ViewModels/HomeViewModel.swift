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

    func logFood(on date: Date, coachOverride: String? = nil, context: MealContext? = nil) async {
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
            // Real mode bypasses cache so we don't reuse stale mock values.
            if AppConfig.shared.mockMode, let cached = try fetchCache(key: key) {
                insertLog(from: cached, day: day, typedName: canonicalName, key: key, context: context)
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
            // Serving priority: user-entered quantity from MealContext > HomeViewModel.servingSize field
            let resolvedServing: String?
            if let contextServing = context?.formattedServing {
                resolvedServing = contextServing
            } else {
                resolvedServing = servingSize.isEmpty ? nil : servingSize
            }
            let request = NutritionAnalysisRequest(
                foodDescription: canonicalName,
                servingSize: resolvedServing
            )
            let result = try await nutritionService.analyzeFood(request: request)
            nutritionalInfo = result

            // 5) Upsert cache + insert log
            try upsertCache(from: result, key: key, displayName: canonicalName)
            insertLog(from: result, day: day, typedName: canonicalName, key: key, context: context)

            try modelContext.save()
            refreshWidget(for: day)
        } catch {
            #if DEBUG
            print("❌ [HomeViewModel] logFood failed: \(error)")
            #endif
            showErrorMessage(userFacingErrorMessage(for: error))
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

    private func insertLog(from cache: FoodCache, day: Date, typedName: String, key: String, context: MealContext? = nil) {
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
            confidence: cache.confidence,
            mealType: context?.mealType?.rawValue,
            eatingTriggers: context?.eatingTriggers.isEmpty == false ? context?.eatingTriggers.map(\.rawValue) : nil,
            hungerLevel: context?.hungerLevel,
            presenceLevel: context?.presenceLevel,
            reflection: context?.reflection?.isEmpty == false ? context?.reflection : nil,
            quantity: context?.quantity,
            quantityUnit: context?.quantityUnit
        )
        modelContext.insert(entry)
    }

    private func insertLog(from info: NutritionalInfo, day: Date, typedName: String, key: String,
                           context: MealContext? = nil,
                           barcodeValue: String? = nil,
                           logSource: String? = nil) {
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
            confidence: info.confidence,
            mealType: context?.mealType?.rawValue,
            eatingTriggers: context?.eatingTriggers.isEmpty == false ? context?.eatingTriggers.map(\.rawValue) : nil,
            hungerLevel: context?.hungerLevel,
            presenceLevel: context?.presenceLevel,
            reflection: context?.reflection?.isEmpty == false ? context?.reflection : nil,
            quantity: context?.quantity,
            quantityUnit: context?.quantityUnit,
            barcodeValue: barcodeValue,
            logSource: logSource
        )
        modelContext.insert(entry)
    }

    // MARK: - Barcode direct save

    /// Direct packaged-food save path — skips MealCoachService and NutritionService.
    /// Called by BarcodeScanView after a successful barcode lookup.
    func logFoodDirectly(
        nutrition: NutritionalInfo,
        barcode: String? = nil,
        on date: Date,
        context: MealContext? = nil
    ) async {
        print("[HomeViewModel] logFoodDirectly called — food: '\(nutrition.foodName)', barcode: \(barcode ?? "nil"), cal: \(nutrition.calories)")
        isLoading = true
        showError = false
        errorMessage = ""
        defer { isLoading = false }

        let key = normalizeFoodKey(nutrition.foodName)
        let day = Calendar.current.startOfDay(for: date)

        do {
            try upsertCache(from: nutrition, key: key, displayName: nutrition.foodName)
            insertLog(
                from: nutrition,
                day: day,
                typedName: nutrition.foodName,
                key: key,
                context: context,
                barcodeValue: barcode,
                logSource: "barcode"
            )
            try modelContext.save()
            refreshWidget(for: day)
            print("[HomeViewModel] ✅ logFoodDirectly saved successfully")
        } catch {
            print("❌ [HomeViewModel] logFoodDirectly failed: \(error)")
            showErrorMessage(userFacingErrorMessage(for: error))
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        if let providerError = error as? NutritionProviderError {
            switch providerError {
            case .missingAPIKey:
                return "Groq API key is missing. Add GROQ_API_KEY in Secrets.plist."
            case .timeout:
                return "Nutrition request timed out. Please try again."
            case .invalidModelOutput, .invalidResponseShape:
                return "Couldn't parse nutrition details. Please try another wording."
            case .requestFailed:
                return "Nutrition service is unavailable right now. Please try again."
            case .invalidURL, .network:
                return "Network error while fetching nutrition. Please try again."
            }
        }

        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Nutrition request timed out. Please try again."
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .networkError:
                return "Network error while fetching nutrition. Please try again."
            default:
                return "Failed to log food. Please try again."
            }
        }

        return "Failed to log food. Please try again."
    }

    // MARK: - Widget Refresh

    /// Aggregates today's food logs, writes to AppGroup UserDefaults, then tells
    /// WidgetKit to reload the food widget timeline.
    func refreshWidget(for day: Date) {
        let goals = UserGoals.current(in: modelContext)
        WidgetRefreshHelper.refresh(goals: goals, context: modelContext)
    }
}
