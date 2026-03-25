import Foundation
import SwiftData
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - StressInsightServiceProtocol

@MainActor
protocol StressInsightServiceProtocol {
    var isGenerating: Bool { get }
    var report: StressInsightReport? { get }
    var insufficientData: Bool { get }
    func generateInsight() async
    func clearAndRegenerate() async
    func bindContext(_ context: ModelContext)
}

// MARK: - StressInsightService

@MainActor
final class StressInsightService: StressInsightServiceProtocol, ObservableObject {

    // MARK: - Published State

    @Published var isGenerating: Bool = false
    @Published var report: StressInsightReport?
    @Published var insufficientData: Bool = false

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private let healthService: HealthKitServiceProtocol

    private let lookbackDays: Int = 10

    // MARK: - Init

    @MainActor
    init(healthService: HealthKitServiceProtocol = HealthKitService()) {
        self.healthService = healthService
    }

    func bindContext(_ context: ModelContext) {
        modelContext = context
    }

    // MARK: - Public API

    func generateInsight() async {
        // Guard: context must be bound before generating
        guard modelContext != nil else {
            WPLogger.home.warning("StressInsightService: bindContext() must be called before generateInsight()")
            #if DEBUG
            assertionFailure("StressInsightService: bindContext() was not called before generateInsight()")
            #endif
            return
        }

        // Same-day cache: return immediately if we already have today's report
        if let existing = report, Calendar.current.isDateInToday(existing.generatedAt) {
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        // Mock mode: return synthetic fixture without touching SwiftData or HealthKit
        if AppConfig.shared.mockMode {
            report = mockReport()
            return
        }

        // Build aggregated context from SwiftData + HealthKit
        guard let context = await buildContext() else {
            insufficientData = true
            return
        }

        // Log context in DEBUG for debugging wrong or unexpected insights
        #if DEBUG
        logContext(context)
        #endif

        // Generate report — Foundation Models if available, template otherwise
        if #available(iOS 26, *) {
            report = await generateWithFoundationModels(context: context) ?? templateReport(context: context)
        } else {
            report = templateReport(context: context)
        }
    }

    func clearAndRegenerate() async {
        report = nil
        insufficientData = false
        await generateInsight()
    }

    // MARK: - Data Aggregation

    private func buildContext() async -> StressInsightContext? {
        guard let ctx = modelContext else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -lookbackDays, to: startOfToday) else { return nil }
        let interval = DateInterval(start: windowStart, end: now)

        // --- SwiftData: StressReading gate check ---
        let stressDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= windowStart },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let allReadings = (try? ctx.fetch(stressDescriptor)) ?? []
        let readingDays = Set(allReadings.map { calendar.startOfDay(for: $0.timestamp) })
        guard readingDays.count >= 2 else { return nil }

        // --- HealthKit: concurrent fetches ---
        async let sleepFetch     = fetchSleepSafely(range: interval)
        async let stepsFetch     = fetchDailyStepsSafely(range: interval)
        async let energyFetch    = fetchDailyEnergySafely(range: interval)
        async let heartRateFetch = fetchHeartRateSafely(range: interval)
        let (sleepSummaries, stepsData, energyData, heartRateData) = await (sleepFetch, stepsFetch, energyFetch, heartRateFetch)

        // --- SwiftData: WellnessDayLog + FoodLogEntry ---
        let wellnessDescriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let wellnessLogs = (try? ctx.fetch(wellnessDescriptor)) ?? []

        let foodDescriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let foodLogs = (try? ctx.fetch(foodDescriptor)) ?? []

        // --- Build per-day summaries ---
        var days: [StressInsightDaySummary] = []
        var missingCategories: [String] = []

        for dayOffset in stride(from: -(lookbackDays - 1), through: 0, by: 1) {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            // Stress readings for this day
            let dayReadings = allReadings.filter {
                $0.timestamp >= dayStart && $0.timestamp < dayEnd
            }
            let avgScore: Double? = dayReadings.isEmpty ? nil : dayReadings.map(\.score).reduce(0, +) / Double(dayReadings.count)

            // WellnessDayLog for this day
            let wellness = wellnessLogs.first { calendar.isDate($0.day, inSameDayAs: dayStart) }

            // Food entries for this day
            let dayFood = foodLogs.filter { $0.day == dayStart }

            // HealthKit sleep for this day (match by date)
            let sleep = sleepSummaries.first { calendar.isDate($0.date, inSameDayAs: dayStart) }

            // HealthKit steps, energy, heart rate for this day
            let stepsValue    = stepsData.first    { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            let energyValue   = energyData.first   { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            let heartRateValue = heartRateData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value

            days.append(StressInsightDaySummary(
                date: dayStart,
                stressScore: avgScore,
                stressLabel: wellness?.stressLevel,
                sleepHours: sleep?.totalHours,
                deepSleepHours: sleep?.deepHours,
                steps: stepsValue.map { Int($0) },
                activeCalories: energyValue.map { Int($0) },
                heartRateAvg: heartRateValue,
                waterGlasses: wellness?.waterGlasses,
                coffeeCups: wellness?.coffeeCups,
                moodLabel: wellness?.mood?.label,
                totalCalories: dayFood.isEmpty ? nil : dayFood.map(\.calories).reduce(0, +),
                totalProteinG: dayFood.isEmpty ? nil : dayFood.map(\.protein).reduce(0, +),
                totalFiberG: dayFood.isEmpty ? nil : dayFood.map(\.fiber).reduce(0, +),
                totalFatG: dayFood.isEmpty ? nil : dayFood.map(\.fat).reduce(0, +),
                totalCarbsG: dayFood.isEmpty ? nil : dayFood.map(\.carbs).reduce(0, +),
                mealCount: dayFood.count
            ))
        }

        // Build data quality note
        if !healthService.isAuthorized {
            missingCategories.append("HealthKit data")
        }
        if sleepSummaries.isEmpty { missingCategories.append("sleep") }
        if foodLogs.isEmpty { missingCategories.append("food logs") }

        let qualityNote = missingCategories.isEmpty
            ? ""
            : "Some data was unavailable: \(missingCategories.joined(separator: ", "))."

        return StressInsightContext(days: days, dataQualityNote: qualityNote)
    }

    // MARK: - Foundation Models Generation (iOS 26+)

    @available(iOS 26, *)
    private func generateWithFoundationModels(context: StressInsightContext) async -> StressInsightReport? {
        #if canImport(FoundationModels)
        // Check model availability explicitly before creating a session
        guard case .available = SystemLanguageModel.default.availability else {
            WPLogger.home.info("StressInsightService: Foundation Models not available on this device — using template")
            return nil
        }

        let prompt = buildPrompt(from: context)

        do {
            let session = LanguageModelSession()
            let result = try await session.respond(to: prompt, generating: _StressInsightSchema.self)
            let schema = result.content
            return StressInsightReport(
                headline: schema.headline,
                summary: schema.summary,
                strongestPositiveFactor: schema.strongestPositiveFactor,
                strongestNegativeFactor: schema.strongestNegativeFactor,
                suggestions: schema.suggestions.map(\.text),
                cautionNote: schema.cautionNote,
                generatedAt: Date(),
                isTemplateGenerated: false,
                days: context.days
            )
        } catch {
            WPLogger.home.warning("StressInsightService: Foundation Models generation failed — \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Prompt Construction

    private func buildPrompt(from context: StressInsightContext) -> String {
        let calendar = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "EEE"

        var lines = [
            "You are a wellness coach summarising a user's stress patterns from the last \(lookbackDays) days.",
            "Use only patterns and signals — no causal certainty, no medical language, no diagnosis.",
            "Data summary (one line per day, oldest first):",
            ""
        ]

        for day in context.days {
            let dayName = df.string(from: day.date)
            var parts: [String] = [dayName]
            if let score = day.stressScore    { parts.append("stress \(Int(score))/100") }
            if let sleep = day.sleepHours     { parts.append(String(format: "sleep %.1fh", sleep)) }
            if let deep  = day.deepSleepHours { parts.append(String(format: "deep %.1fh", deep)) }
            if let steps = day.steps          { parts.append("\(steps) steps") }
            if let kcal  = day.activeCalories { parts.append("\(kcal) kcal burned") }
            if let hr    = day.heartRateAvg   { parts.append(String(format: "HR %.0fbpm", hr)) }
            if let water = day.waterGlasses   { parts.append("\(water) glasses water") }
            if let coffee = day.coffeeCups, coffee > 0 { parts.append("\(coffee) coffees") }
            if let protein = day.totalProteinG { parts.append(String(format: "protein %.0fg", protein)) }
            if let fiber   = day.totalFiberG   { parts.append(String(format: "fiber %.0fg", fiber)) }
            if let fat     = day.totalFatG     { parts.append(String(format: "fat %.0fg", fat)) }
            if let carbs   = day.totalCarbsG   { parts.append(String(format: "carbs %.0fg", carbs)) }
            if day.mealCount > 0               { parts.append("\(day.mealCount) meals") }
            lines.append(parts.joined(separator: ", "))
        }

        if !context.dataQualityNote.isEmpty {
            lines.append("")
            lines.append("Note: \(context.dataQualityNote)")
        }

        lines.append("")
        lines.append("Generate a structured insight report with: a short headline, a 2–3 sentence summary, the strongest positive factor, the strongest negative factor, exactly 2 actionable suggestions, and a caution note (empty string if data is complete).")

        return lines.joined(separator: "\n")
    }

    // MARK: - Template Fallback (deterministic, no model)

    private func templateReport(context: StressInsightContext) -> StressInsightReport {
        let days = context.days

        // Find the day with highest and lowest stress score
        let scoredDays = days.compactMap { d -> (StressInsightDaySummary, Double)? in
            guard let score = d.stressScore else { return nil }
            return (d, score)
        }

        let worstDay  = scoredDays.max(by: { $0.1 < $1.1 })?.0
        let bestDay   = scoredDays.min(by: { $0.1 < $1.1 })?.0

        let positiveFactor = determineBestFactor(day: bestDay)
        let negativeFactor = determineWorstFactor(day: worstDay)

        let avgScore = scoredDays.isEmpty ? 50.0 : scoredDays.map(\.1).reduce(0, +) / Double(scoredDays.count)
        let trend = avgScore > 60 ? "elevated" : avgScore > 40 ? "moderate" : "low"

        let headline = "Your stress trended \(trend) over the last \(days.count) days"
        let summary  = "Looking at your recent data, your stress levels were \(trend). \(positiveFactor.sentence) However, \(negativeFactor.sentence.lowercased())"

        let suggestions = [
            TemplateCopy.suggestion(for: negativeFactor.key),
            TemplateCopy.suggestion(for: positiveFactor.key, reinforcing: true)
        ]

        return StressInsightReport(
            headline: headline,
            summary: summary,
            strongestPositiveFactor: positiveFactor.label,
            strongestNegativeFactor: negativeFactor.label,
            suggestions: suggestions,
            cautionNote: context.dataQualityNote,
            generatedAt: Date(),
            isTemplateGenerated: true,
            days: context.days
        )
    }

    private struct FactorInfo {
        let key: String
        let label: String
        let sentence: String
    }

    private func determineBestFactor(day: StressInsightDaySummary?) -> FactorInfo {
        guard let day else {
            return FactorInfo(key: "general", label: "consistent habits", sentence: "Maintaining regular habits is helping manage your stress.")
        }
        // Pick the strongest positive signal
        if let sleep = day.sleepHours, sleep >= 7 {
            return FactorInfo(key: "sleep", label: "quality sleep", sentence: "Getting \(String(format: "%.1f", sleep))h of sleep on your best day helped keep stress lower.")
        }
        if let steps = day.steps, steps >= 7000 {
            return FactorInfo(key: "exercise", label: "physical activity", sentence: "Reaching \(steps) steps on your most active day contributed positively.")
        }
        if let fiber = day.totalFiberG, fiber >= 20 {
            return FactorInfo(key: "diet", label: "balanced nutrition", sentence: "Your nutrition was well-balanced on your lower-stress day.")
        }
        return FactorInfo(key: "general", label: "consistent habits", sentence: "Maintaining regular habits is helping manage your stress.")
    }

    private func determineWorstFactor(day: StressInsightDaySummary?) -> FactorInfo {
        guard let day else {
            return FactorInfo(key: "screen_time", label: "screen time", sentence: "Screen time may be contributing to stress.")
        }
        // Pick the strongest negative signal
        if let sleep = day.sleepHours, sleep < 6 {
            return FactorInfo(key: "sleep", label: "short sleep", sentence: "On your highest-stress day, sleep was only \(String(format: "%.1f", sleep))h.")
        }
        if let coffee = day.coffeeCups, coffee >= 4 {
            return FactorInfo(key: "caffeine", label: "high caffeine intake", sentence: "High coffee intake (\(coffee) cups) may have contributed to elevated stress.")
        }
        if let steps = day.steps, steps < 3000 {
            return FactorInfo(key: "exercise", label: "low activity", sentence: "Low activity (\(steps) steps) on your highest-stress day may have amplified stress.")
        }
        if let fiber = day.totalFiberG, fiber < 10 {
            return FactorInfo(key: "diet", label: "low fiber intake", sentence: "Low fiber intake on your highest-stress day may be a factor.")
        }
        return FactorInfo(key: "screen_time", label: "screen time or low recovery", sentence: "Recovery habits like sleep and movement may need attention.")
    }

    // MARK: - Mock Report

    private func mockReport() -> StressInsightReport {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 10-day arc: stress peaks around day 4–5, then recovers with better sleep + activity
        // Index 0 = oldest (9 days ago), index 9 = today
        let stressScores:  [Double] = [54, 58, 66, 73, 79, 75, 67, 57, 49, 43]
        let sleepHours:    [Double] = [7.0, 6.5, 6.0, 5.5, 5.2, 5.8, 6.5, 7.2, 7.8, 8.1]
        let deepHours:     [Double] = [1.4, 1.2, 1.0, 0.9, 0.8, 1.0, 1.2, 1.5, 1.7, 1.9]
        let steps:         [Int]    = [7400, 6100, 5200, 4000, 3800, 4600, 6200, 9100, 9800, 10300]
        let energy:        [Int]    = [290, 240, 200, 155, 145, 180, 245, 365, 390, 415]
        let heartRates:    [Double] = [70, 71, 73, 76, 78, 76, 74, 72, 70, 68]
        let water:         [Int]    = [6, 5, 4, 4, 3, 4, 5, 7, 7, 8]
        let coffee:        [Int]    = [2, 2, 3, 4, 4, 3, 2, 2, 1, 2]
        let calories:      [Int]    = [1850, 2050, 2200, 2350, 2400, 2200, 2000, 1850, 1780, 1800]
        let protein:       [Double] = [72, 65, 58, 55, 52, 58, 65, 76, 80, 84]
        let fiber:         [Double] = [22, 18, 14, 11, 9, 13, 16, 22, 26, 28]
        let fat:           [Double] = [62, 70, 80, 88, 92, 84, 74, 64, 58, 60]
        let carbs:         [Double] = [210, 235, 260, 285, 295, 270, 245, 210, 195, 200]
        let moods = ["Good", "Okay", "Okay", "Stressed", "Stressed", "Stressed", "Okay", "Good", "Good", "Great"]

        let mockDays: [StressInsightDaySummary] = (0..<10).map { i in
            let dayOffset = -(9 - i)
            let date = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            let score = stressScores[i]
            return StressInsightDaySummary(
                date: date,
                stressScore: score,
                stressLabel: score > 65 ? "High" : score > 45 ? "Moderate" : "Low",
                sleepHours: sleepHours[i],
                deepSleepHours: deepHours[i],
                steps: steps[i],
                activeCalories: energy[i],
                heartRateAvg: heartRates[i],
                waterGlasses: water[i],
                coffeeCups: coffee[i],
                moodLabel: moods[i],
                totalCalories: calories[i],
                totalProteinG: protein[i],
                totalFiberG: fiber[i],
                totalFatG: fat[i],
                totalCarbsG: carbs[i],
                mealCount: 3
            )
        }

        return StressInsightReport(
            headline: "Stress peaked mid-window, trending down now",
            summary: "Over the last 10 days your stress peaked around days 4–5, correlating with shorter sleep (as low as 5.2h) and higher caffeine. The last 3 days show a clear recovery as sleep improved past 7.5h and daily steps crossed 9,000.",
            strongestPositiveFactor: "Improved sleep and activity in the last 3 days",
            strongestNegativeFactor: "Short sleep and high caffeine around day 4–5",
            suggestions: [
                "Aim to keep sleep above 7.5h — your data shows a strong link between sleep duration and next-day stress.",
                "Limit caffeine to 2 cups on high-stress days — your pattern suggests 4 cups amplifies stress responses."
            ],
            cautionNote: "",
            generatedAt: Date(),
            isTemplateGenerated: true,
            days: mockDays
        )
    }

    // MARK: - HealthKit Safe Fetchers

    private func fetchSleepSafely(range: DateInterval) async -> [DailySleepSummary] {
        (try? await healthService.fetchDailySleepSummaries(for: range)) ?? []
    }

    private func fetchDailyStepsSafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchSteps(for: range)) ?? []
    }

    private func fetchDailyEnergySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchActiveEnergy(for: range)) ?? []
    }

    private func fetchHeartRateSafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchHeartRate(for: range)) ?? []
    }

    // MARK: - Debug Context Logging

    #if DEBUG
    private func logContext(_ context: StressInsightContext) {
        let df = DateFormatter()
        df.dateFormat = "EEE dd"
        var lines = context.days.map { day -> String in
            var parts: [String] = [df.string(from: day.date)]
            parts.append("stress: \(day.stressScore.map { String(Int($0)) } ?? "—")")
            parts.append("sleep: \(day.sleepHours.map { String(format: "%.1fh", $0) } ?? "—")")
            parts.append("steps: \(day.steps.map { String($0) } ?? "—")")
            parts.append("meals: \(day.mealCount)")
            return parts.joined(separator: " | ")
        }
        if !context.dataQualityNote.isEmpty { lines.append("⚠ \(context.dataQualityNote)") }
        WPLogger.home.block(emoji: "🤖", title: "StressInsightContext (sent to model)", lines: lines)
    }
    #endif
}

// MARK: - Internal @Generable Schemas (iOS 26+, private to this file)

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct _StressInsightSchema {
    @Guide(description: "Short editorial headline, max 12 words, no medical claims, no diagnosis")
    var headline: String

    @Guide(description: "2–3 sentence summary of stress patterns. Use 'may suggest' or 'appears linked' — not 'causes'.")
    var summary: String

    @Guide(description: "The single factor that most helped reduce stress, e.g. 'consistent sleep schedule'")
    var strongestPositiveFactor: String

    @Guide(description: "The single factor that most drove stress up, e.g. 'late screen time and low fiber'")
    var strongestNegativeFactor: String

    @Guide(description: "Exactly 2 specific, actionable suggestions based on the data")
    var suggestions: [_InsightSuggestion]

    @Guide(description: "Data quality note if important signals were missing, or empty string if data is complete")
    var cautionNote: String
}

@available(iOS 26, *)
@Generable
private struct _InsightSuggestion {
    @Guide(description: "One specific, actionable suggestion, e.g. 'Try to be in bed by 10:30 PM for at least 3 nights this week'")
    var text: String
}
#endif

// MARK: - Template Copy

private enum TemplateCopy {
    static func suggestion(for key: String, reinforcing: Bool = false) -> String {
        if reinforcing {
            switch key {
            case "sleep":    return "Keep up your sleep routine — it's clearly helping."
            case "exercise": return "Maintain your activity level — it's making a difference."
            case "diet":     return "Your nutrition balance is working well — keep it up."
            default:         return "Continue the habits that helped lower your stress this week."
            }
        }
        switch key {
        case "sleep":       return "Aim to be in bed by 10:30 PM — even one extra hour of sleep can noticeably lower next-day stress."
        case "exercise":    return "A 20-minute walk tomorrow morning can help reset your baseline stress level."
        case "diet":        return "Add a high-fiber food to your next meal — beans, oats, or leafy greens all count."
        case "caffeine":    return "Try capping caffeine at 2 cups and avoid any after 2 PM to improve sleep quality."
        case "screen_time": return "Stop screen use 30 minutes before bed to improve sleep onset and reduce next-day stress."
        default:            return "Focus on one recovery habit today: sleep, movement, or a nutritious meal."
        }
    }
}

