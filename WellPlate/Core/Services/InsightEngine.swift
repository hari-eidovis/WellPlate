import Foundation
import SwiftData
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - InsightEngine
//
// Unified insight generation service. Aggregates data from SwiftData + HealthKit,
// detects patterns/trends/correlations/milestones, generates narratives via
// Foundation Models (template fallback for iOS < 26), and caches per day.
// Replaces the stress-only StressInsightService.

@MainActor
final class InsightEngine: ObservableObject {

    // MARK: - Published State

    @Published var insightCards: [InsightCard] = []
    @Published var dailyInsight: InsightCard?
    @Published var isGenerating: Bool = false
    @Published var insufficientData: Bool = false

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private let healthService: HealthKitServiceProtocol
    private let lookbackDays: Int = 14

    // MARK: - Init

    init(healthService: HealthKitServiceProtocol = HealthKitService()) {
        self.healthService = healthService
    }

    func bindContext(_ context: ModelContext) {
        modelContext = context
    }

    // MARK: - Public API

    func generateInsights() async {
        guard modelContext != nil else { return }

        // Same-day cache
        if let first = insightCards.first, Calendar.current.isDateInToday(first.generatedAt) {
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        // Mock mode
        if AppConfig.shared.mockMode {
            let mocks = mockInsights()
            insightCards = mocks
            dailyInsight = mocks.first
            return
        }

        guard let context = await buildWellnessContext() else {
            insufficientData = true
            return
        }

        // Detect all insights
        var cards: [InsightCard] = []
        cards.append(contentsOf: detectTrends(context: context))
        cards.append(contentsOf: detectCorrelations(context: context))
        cards.append(contentsOf: detectMilestones(context: context))
        cards.append(contentsOf: detectImbalances(context: context))
        cards.append(contentsOf: detectSleepQuality(context: context))
        cards.append(contentsOf: detectReinforcements(context: context))

        cards = prioritise(cards)
        cards = await generateNarratives(cards, context: context)

        insightCards = cards
        dailyInsight = cards.first
    }

    func clearAndRegenerate() async {
        insightCards = []
        dailyInsight = nil
        insufficientData = false
        await generateInsights()
    }

    // MARK: - Data Aggregation

    private func buildWellnessContext() async -> WellnessContext? {
        guard let ctx = modelContext else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -lookbackDays, to: startOfToday) else { return nil }
        let interval = DateInterval(start: windowStart, end: now)

        // Fetch UserGoals
        let goals = UserGoalsSnapshot(from: UserGoals.current(in: ctx))

        // SwiftData fetches
        let stressDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= windowStart },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let allReadings = (try? ctx.fetch(stressDescriptor)) ?? []
        let stressDayCount = Set(allReadings.map { calendar.startOfDay(for: $0.timestamp) }).count

        let wellnessDescriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let wellnessLogs = (try? ctx.fetch(wellnessDescriptor)) ?? []

        let foodDescriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let foodLogs = (try? ctx.fetch(foodDescriptor)) ?? []

        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let symptomEntries = (try? ctx.fetch(symptomDescriptor)) ?? []

        let fastingDescriptor = FetchDescriptor<FastingSession>(
            predicate: #Predicate { $0.startedAt >= windowStart }
        )
        let fastingSessions = ((try? ctx.fetch(fastingDescriptor)) ?? []).filter { !$0.isActive }

        let adherenceDescriptor = FetchDescriptor<AdherenceLog>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let adherenceLogs = (try? ctx.fetch(adherenceDescriptor)) ?? []

        let journalDescriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let journalEntries = (try? ctx.fetch(journalDescriptor)) ?? []

        // Multi-domain gate check: require >= 2 domains with >= 2 days of data
        let foodDayCount = Set(foodLogs.map { $0.day }).count
        let wellnessDayCount = wellnessLogs.count
        var domainsWith2Days = 0
        if stressDayCount >= 2 { domainsWith2Days += 1 }
        if foodDayCount >= 2 { domainsWith2Days += 1 }
        if wellnessDayCount >= 2 { domainsWith2Days += 1 }
        // Sleep/steps checked after HK fetch below

        // Concurrent HealthKit fetches
        async let sleepFetch = fetchSleepSafely(range: interval)
        async let stepsFetch = fetchDailyStepsSafely(range: interval)
        async let energyFetch = fetchDailyEnergySafely(range: interval)
        async let heartRateFetch = fetchHeartRateSafely(range: interval)
        async let exerciseFetch = fetchExerciseMinutesSafely(range: interval)
        let (sleepSummaries, stepsData, energyData, heartRateData, exerciseData) = await (sleepFetch, stepsFetch, energyFetch, heartRateFetch, exerciseFetch)

        if sleepSummaries.count >= 2 { domainsWith2Days += 1 }
        if stepsData.count >= 2 { domainsWith2Days += 1 }
        guard domainsWith2Days >= 2 else { return nil }

        // Build per-day summaries
        var days: [WellnessDaySummary] = []
        var missingCategories: [String] = []

        for dayOffset in stride(from: -(lookbackDays - 1), through: 0, by: 1) {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            // Stress
            let dayReadings = allReadings.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            let avgScore: Double? = dayReadings.isEmpty ? nil : dayReadings.map(\.score).reduce(0, +) / Double(dayReadings.count)

            // WellnessDayLog
            let wellness = wellnessLogs.first { calendar.isDate($0.day, inSameDayAs: dayStart) }

            // Food
            let dayFood = foodLogs.filter { $0.day == dayStart }

            // Sleep
            let sleep = sleepSummaries.first { calendar.isDate($0.date, inSameDayAs: dayStart) }

            // HealthKit daily metrics
            let stepsValue = stepsData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            let energyValue = energyData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            let heartRateValue = heartRateData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            let exerciseValue = exerciseData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value

            // Symptoms
            let daySymptoms = symptomEntries.filter { calendar.isDate($0.day, inSameDayAs: dayStart) }
            let symptomNames = Array(Set(daySymptoms.map(\.name)))
            let symptomMax = daySymptoms.map(\.severity).max()

            // Fasting
            let dayFasting = fastingSessions.filter { calendar.isDate($0.day, inSameDayAs: dayStart) }
            let fastingHours: Double? = dayFasting.isEmpty ? nil : dayFasting.map(\.actualDurationSeconds).reduce(0, +) / 3600.0
            let fastingCompleted: Bool? = dayFasting.isEmpty ? nil : dayFasting.contains(where: \.completed)

            // Supplements
            let dayAdherence = adherenceLogs.filter { $0.day == dayStart }
            let supplementAdherence: Double? = dayAdherence.isEmpty ? nil : {
                let taken = Double(dayAdherence.filter { $0.status == "taken" }.count)
                let total = Double(dayAdherence.count)
                return total > 0 ? taken / total : nil
            }()

            // Journal
            let journalLogged = journalEntries.contains { calendar.isDate($0.day, inSameDayAs: dayStart) }

            days.append(WellnessDaySummary(
                date: dayStart,
                stressScore: avgScore,
                stressLabel: wellness?.stressLevel,
                sleepHours: sleep?.totalHours,
                deepSleepHours: sleep?.deepHours,
                remSleepHours: sleep?.remHours,
                bedtime: sleep?.bedtime,
                wakeTime: sleep?.wakeTime,
                steps: stepsValue.map { Int($0) },
                activeCalories: energyValue.map { Int($0) },
                exerciseMinutes: exerciseValue.map { Int($0) },
                heartRateAvg: heartRateValue,
                totalCalories: dayFood.isEmpty ? nil : dayFood.map(\.calories).reduce(0, +),
                totalProteinG: dayFood.isEmpty ? nil : dayFood.map(\.protein).reduce(0, +),
                totalCarbsG: dayFood.isEmpty ? nil : dayFood.map(\.carbs).reduce(0, +),
                totalFatG: dayFood.isEmpty ? nil : dayFood.map(\.fat).reduce(0, +),
                totalFiberG: dayFood.isEmpty ? nil : dayFood.map(\.fiber).reduce(0, +),
                mealCount: dayFood.count,
                waterGlasses: wellness?.waterGlasses,
                coffeeCups: wellness?.coffeeCups,
                moodLabel: wellness?.mood?.label,
                symptomNames: symptomNames,
                symptomMaxSeverity: symptomMax,
                fastingHours: fastingHours,
                fastingCompleted: fastingCompleted,
                supplementAdherence: supplementAdherence,
                journalLogged: journalLogged
            ))
        }

        // Data quality note
        if !healthService.isAuthorized { missingCategories.append("HealthKit data") }
        if sleepSummaries.isEmpty { missingCategories.append("sleep") }
        if foodLogs.isEmpty { missingCategories.append("food logs") }
        let qualityNote = missingCategories.isEmpty ? "" : "Some data was unavailable: \(missingCategories.joined(separator: ", "))."

        return WellnessContext(days: days, goals: goals, dataQualityNote: qualityNote)
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

    private func fetchExerciseMinutesSafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchExerciseMinutes(for: range)) ?? []
    }
}

// MARK: - Insight Detectors

private extension InsightEngine {

    // MARK: Trends (3+ day directional change)

    func detectTrends(context: WellnessContext) -> [InsightCard] {
        var cards: [InsightCard] = []

        struct MetricDef {
            let name: String
            let unit: String
            let domain: WellnessDomain
            let extract: (WellnessDaySummary) -> Double?
            let goalLine: Double?
        }

        let metrics: [MetricDef] = [
            MetricDef(name: "Stress", unit: "/100", domain: .stress, extract: { $0.stressScore }, goalLine: 50),
            MetricDef(name: "Sleep", unit: "h", domain: .sleep, extract: { $0.sleepHours }, goalLine: context.goals.sleepGoalHours),
            MetricDef(name: "Steps", unit: "", domain: .activity, extract: { $0.steps.map(Double.init) }, goalLine: Double(context.goals.dailyStepsGoal)),
            MetricDef(name: "Calories", unit: "kcal", domain: .nutrition, extract: { $0.totalCalories.map(Double.init) }, goalLine: Double(context.goals.calorieGoal)),
            MetricDef(name: "Water", unit: "cups", domain: .hydration, extract: { $0.waterGlasses.map(Double.init) }, goalLine: Double(context.goals.waterDailyCups)),
            MetricDef(name: "Coffee", unit: "cups", domain: .caffeine, extract: { $0.coffeeCups.map(Double.init) }, goalLine: nil),
        ]

        for metric in metrics {
            let dataPoints: [(date: Date, value: Double)] = context.days.compactMap { day in
                guard let val = metric.extract(day) else { return nil }
                return (date: day.date, value: val)
            }
            guard dataPoints.count >= 3 else { continue }

            // Check last 3+ values for monotonic trend
            let recent = Array(dataPoints.suffix(5))
            guard recent.count >= 3 else { continue }

            let values = recent.map(\.value)
            let isRising = zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
            let isFalling = zip(values, values.dropFirst()).allSatisfy { $0 > $1 }

            guard isRising || isFalling else { continue }

            let first = values.first!, last = values.last!
            let pctChange = first != 0 ? abs((last - first) / first * 100) : abs(last - first)
            let direction = isRising ? "rising" : "declining"

            let headline = "\(metric.name) \(direction) \(recent.count) days"
            let narrative = "\(metric.name) has been \(direction) for \(recent.count) consecutive days."
            let priority = min(1.0, pctChange / 100.0 * 0.8 + 0.2)

            cards.append(InsightCard(
                id: UUID(),
                type: .trend,
                domain: metric.domain,
                headline: headline,
                narrative: narrative,
                chartData: .trendLine(points: dataPoints, goalLine: metric.goalLine, metricLabel: metric.name, unit: metric.unit),
                priority: priority,
                isLLMGenerated: false,
                generatedAt: Date(),
                detailSuggestions: [
                    "Track this metric closely over the next few days.",
                    "Consider what may have changed recently."
                ]
            ))
        }

        return cards
    }

    // MARK: Correlations (cross-domain r-value)

    func detectCorrelations(context: WellnessContext) -> [InsightCard] {
        var cards: [InsightCard] = []

        struct Pair {
            let xName: String; let yName: String
            let xDomain: WellnessDomain; let yDomain: WellnessDomain
            let xExtract: (WellnessDaySummary) -> Double?
            let yExtract: (WellnessDaySummary) -> Double?
        }

        let pairs: [Pair] = [
            Pair(xName: "Sleep", yName: "Stress", xDomain: .sleep, yDomain: .stress, xExtract: { $0.sleepHours }, yExtract: { $0.stressScore }),
            Pair(xName: "Steps", yName: "Stress", xDomain: .activity, yDomain: .stress, xExtract: { $0.steps.map(Double.init) }, yExtract: { $0.stressScore }),
            Pair(xName: "Coffee", yName: "Stress", xDomain: .caffeine, yDomain: .stress, xExtract: { $0.coffeeCups.map(Double.init) }, yExtract: { $0.stressScore }),
            Pair(xName: "Protein", yName: "Stress", xDomain: .nutrition, yDomain: .stress, xExtract: { $0.totalProteinG }, yExtract: { $0.stressScore }),
            Pair(xName: "Fiber", yName: "Stress", xDomain: .nutrition, yDomain: .stress, xExtract: { $0.totalFiberG }, yExtract: { $0.stressScore }),
            Pair(xName: "Water", yName: "Stress", xDomain: .hydration, yDomain: .stress, xExtract: { $0.waterGlasses.map(Double.init) }, yExtract: { $0.stressScore }),
            Pair(xName: "Sleep", yName: "Steps", xDomain: .sleep, yDomain: .activity, xExtract: { $0.sleepHours }, yExtract: { $0.steps.map(Double.init) }),
        ]

        for pair in pairs {
            var xValues: [Double] = []
            var yValues: [Double] = []
            var scatterPoints: [(x: Double, y: Double)] = []

            for day in context.days {
                guard let x = pair.xExtract(day), let y = pair.yExtract(day) else { continue }
                xValues.append(x)
                yValues.append(y)
                scatterPoints.append((x: x, y: y))
            }

            guard xValues.count >= 7 else { continue }

            let r = CorrelationMath.spearmanR(xValues, yValues)
            let (ciLow, ciHigh) = CorrelationMath.bootstrapCI(xValues: xValues, yValues: yValues)
            let ciSpansZero = ciLow < 0 && ciHigh > 0

            guard abs(r) >= 0.3 && !ciSpansZero else { continue }

            let direction = r > 0 ? "positively" : "inversely"
            let headline = "\(pair.xName) & \(pair.yName) are \(direction) linked"
            let narrative = "\(pair.xName) and \(pair.yName) show a \(CorrelationMath.interpretationLabel(r: r, ciSpansZero: false)) (r = \(String(format: "%.2f", r)), N = \(xValues.count) days)."

            cards.append(InsightCard(
                id: UUID(),
                type: .correlation,
                domain: .cross,
                headline: headline,
                narrative: narrative,
                chartData: .correlationScatter(points: scatterPoints, r: r, xLabel: pair.xName, yLabel: pair.yName),
                priority: min(1.0, abs(r)),
                isLLMGenerated: false,
                generatedAt: Date(),
                detailSuggestions: [
                    "This pattern may suggest a link worth exploring.",
                    "Correlation does not imply causation — keep tracking."
                ]
            ))
        }

        return cards
    }

    // MARK: Milestones (streaks)

    func detectMilestones(context: WellnessContext) -> [InsightCard] {
        var cards: [InsightCard] = []
        let goals = context.goals
        let days = context.days

        struct StreakDef {
            let name: String
            let domain: WellnessDomain
            let check: (WellnessDaySummary) -> Bool
            let target: Int
        }

        let streakDefs: [StreakDef] = [
            StreakDef(name: "Water Goal", domain: .hydration, check: { ($0.waterGlasses ?? 0) >= goals.waterDailyCups && goals.waterDailyCups > 0 }, target: 7),
            StreakDef(name: "Step Goal", domain: .activity, check: { ($0.steps ?? 0) >= goals.dailyStepsGoal && goals.dailyStepsGoal > 0 }, target: 7),
            StreakDef(name: "Calorie Target", domain: .nutrition, check: {
                guard let cal = $0.totalCalories, goals.calorieGoal > 0 else { return false }
                let ratio = Double(cal) / Double(goals.calorieGoal)
                return ratio >= 0.9 && ratio <= 1.1
            }, target: 7),
            StreakDef(name: "Sleep Goal", domain: .sleep, check: { ($0.sleepHours ?? 0) >= goals.sleepGoalHours && goals.sleepGoalHours > 0 }, target: 7),
        ]

        for def in streakDefs {
            var streak = 0
            for day in days.reversed() {
                if def.check(day) { streak += 1 } else { break }
            }
            guard streak >= 3 else { continue }

            let headline = "\(streak)-day \(def.name) streak!"
            let narrative = "You've hit your \(def.name.lowercased()) for \(streak) consecutive days."
            let priority = min(1.0, Double(streak) / 7.0 * 0.6 + 0.2)

            cards.append(InsightCard(
                id: UUID(),
                type: .milestone,
                domain: def.domain,
                headline: headline,
                narrative: narrative,
                chartData: .milestoneRing(current: streak, target: def.target, streakLabel: def.name),
                priority: priority,
                isLLMGenerated: false,
                generatedAt: Date(),
                detailSuggestions: [
                    "Keep the streak going!",
                    "Consistency is the strongest predictor of long-term results."
                ]
            ))
        }

        return cards
    }

    // MARK: Imbalances (macro deficits)

    func detectImbalances(context: WellnessContext) -> [InsightCard] {
        var cards: [InsightCard] = []
        let goals = context.goals
        let recent = context.days.suffix(7)

        struct MacroDef {
            let name: String
            let goal: Int
            let extract: (WellnessDaySummary) -> Double?
        }

        let macroDefs: [MacroDef] = [
            MacroDef(name: "Protein", goal: goals.proteinGoalGrams, extract: { $0.totalProteinG }),
            MacroDef(name: "Fiber", goal: goals.fiberGoalGrams, extract: { $0.totalFiberG }),
            MacroDef(name: "Fat", goal: goals.fatGoalGrams, extract: { $0.totalFatG }),
            MacroDef(name: "Carbs", goal: goals.carbsGoalGrams, extract: { $0.totalCarbsG }),
        ]

        var actualMap: [String: Double] = [:]
        var goalMap: [String: Double] = [:]

        for def in macroDefs {
            guard def.goal > 0 else { continue }
            let values = recent.compactMap { def.extract($0) }
            guard values.count >= 3 else { continue }
            let avg = values.reduce(0, +) / Double(values.count)
            let ratio = avg / Double(def.goal)
            actualMap[def.name] = avg
            goalMap[def.name] = Double(def.goal)

            if ratio < 0.7 {
                let pct = Int((1.0 - ratio) * 100)
                let headline = "\(def.name) is \(pct)% below goal"
                let narrative = "\(def.name) has averaged \(Int(avg))g/day over the last \(values.count) days — \(pct)% below your \(def.goal)g goal."

                cards.append(InsightCard(
                    id: UUID(),
                    type: .imbalance,
                    domain: .nutrition,
                    headline: headline,
                    narrative: narrative,
                    chartData: .macroRadar(actual: actualMap, goals: goalMap),
                    priority: min(1.0, (1.0 - ratio) * 0.8 + 0.2),
                    isLLMGenerated: false,
                    generatedAt: Date(),
                    detailSuggestions: [
                        "Try adding \(def.name.lowercased())-rich foods to your next meal.",
                        "Small increases add up — aim for 10% more this week."
                    ]
                ))
            }
        }

        return cards
    }

    // MARK: Sleep Quality (deep sleep ratio changes)

    func detectSleepQuality(context: WellnessContext) -> [InsightCard] {
        let days = context.days
        let half = days.count / 2
        guard half >= 3 else { return [] }

        let firstHalf = Array(days.prefix(half))
        let secondHalf = Array(days.suffix(half))

        func avgDeepRatio(_ slice: [WellnessDaySummary]) -> Double? {
            let pairs = slice.compactMap { d -> (Double, Double)? in
                guard let total = d.sleepHours, total > 0, let deep = d.deepSleepHours else { return nil }
                return (deep, total)
            }
            guard pairs.count >= 2 else { return nil }
            return pairs.map { $0.0 / $0.1 }.reduce(0, +) / Double(pairs.count)
        }

        guard let firstRatio = avgDeepRatio(firstHalf),
              let secondRatio = avgDeepRatio(secondHalf) else { return [] }

        let change = (secondRatio - firstRatio) / firstRatio
        guard abs(change) > 0.15 else { return [] }

        let direction = change > 0 ? "improved" : "declined"
        let pctChange = Int(abs(change) * 100)
        let headline = "Deep sleep \(direction) \(pctChange)%"
        let narrative = "Your deep sleep ratio \(direction) \(pctChange)% in the second half of the lookback window compared to the first."

        return [InsightCard(
            id: UUID(),
            type: .sleepQuality,
            domain: .sleep,
            headline: headline,
            narrative: narrative,
            chartData: .comparisonBars(bars: [
                (label: "Earlier", value: firstRatio * 100, domain: .sleep),
                (label: "Recent", value: secondRatio * 100, domain: .sleep),
            ], highlight: change > 0 ? 1 : 0),
            priority: min(1.0, abs(change) * 0.8 + 0.3),
            isLLMGenerated: false,
            generatedAt: Date(),
            detailSuggestions: [
                change > 0 ? "Whatever you changed recently is working — keep it up."
                            : "Consider what may have disrupted your sleep quality.",
                "Consistent bedtime and avoiding screens before bed can help deep sleep."
            ]
        )]
    }

    // MARK: Reinforcements (positive habits)

    func detectReinforcements(context: WellnessContext) -> [InsightCard] {
        var cards: [InsightCard] = []
        let goals = context.goals
        let recent = Array(context.days.suffix(7))
        guard recent.count >= 5 else { return [] }

        struct ReinforceDef {
            let name: String
            let domain: WellnessDomain
            let extract: (WellnessDaySummary) -> Double?
            let goal: Double
        }

        let defs: [ReinforceDef] = [
            ReinforceDef(name: "Water", domain: .hydration, extract: { $0.waterGlasses.map(Double.init) }, goal: Double(goals.waterDailyCups)),
            ReinforceDef(name: "Steps", domain: .activity, extract: { $0.steps.map(Double.init) }, goal: Double(goals.dailyStepsGoal)),
            ReinforceDef(name: "Sleep", domain: .sleep, extract: { $0.sleepHours }, goal: goals.sleepGoalHours),
        ]

        for def in defs {
            guard def.goal > 0 else { continue }
            let values = recent.compactMap { def.extract($0) }
            let metDays = values.filter { $0 >= def.goal }.count
            guard metDays >= 5 else { continue }

            let headline = "Consistent \(def.name) — keep going!"
            let narrative = "You've hit your \(def.name.lowercased()) goal \(metDays) out of the last \(recent.count) days."
            let sparklinePoints = recent.compactMap { def.extract($0) }

            cards.append(InsightCard(
                id: UUID(),
                type: .reinforcement,
                domain: def.domain,
                headline: headline,
                narrative: narrative,
                chartData: .sparkline(points: sparklinePoints),
                priority: 0.2,
                isLLMGenerated: false,
                generatedAt: Date(),
                detailSuggestions: [
                    "Consistency is your superpower — keep it up.",
                    "Your body responds best to sustained habits."
                ]
            ))
        }

        return cards
    }
}

// MARK: - Prioritisation

private extension InsightEngine {

    func prioritise(_ cards: [InsightCard]) -> [InsightCard] {
        let typeOrder: [InsightType: Int] = [
            .correlation: 0, .trend: 1, .imbalance: 2,
            .sleepQuality: 3, .milestone: 4, .reinforcement: 5,
        ]

        var sorted = cards.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return (typeOrder[a.type] ?? 6) < (typeOrder[b.type] ?? 6)
        }

        // Deduplicate: keep highest priority per domain
        var seenDomains: Set<WellnessDomain> = []
        sorted = sorted.filter { card in
            if card.domain == .cross { return true } // cross-domain always kept
            if seenDomains.contains(card.domain) { return false }
            seenDomains.insert(card.domain)
            return true
        }

        return Array(sorted.prefix(12))
    }
}

// MARK: - Narrative Generation

private extension InsightEngine {

    func generateNarratives(_ cards: [InsightCard], context: WellnessContext) async -> [InsightCard] {
        if #available(iOS 26, *) {
            if let updated = await generateWithFoundationModels(cards, context: context) {
                return updated
            }
        }
        // Template fallback
        return cards.map { card in
            var updated = card
            let template = templateNarrative(for: card, context: context)
            updated.headline = template.headline
            updated.narrative = template.narrative
            updated.detailSuggestions = template.suggestions
            return updated
        }
    }

    @available(iOS 26, *)
    func generateWithFoundationModels(_ cards: [InsightCard], context: WellnessContext) async -> [InsightCard]? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        var updated = cards
        // Generate individually for top 5 cards
        for i in 0..<min(5, updated.count) {
            let card = updated[i]
            let prompt = buildNarrativePrompt(for: card, context: context)
            do {
                let session = LanguageModelSession()
                let result = try await session.respond(to: prompt, generating: _InsightNarrativeSchema.self)
                updated[i].headline = result.content.headline
                updated[i].narrative = result.content.narrative
                updated[i].detailSuggestions = result.content.suggestions.map(\.text)
                updated[i].isLLMGenerated = true
            } catch {
                WPLogger.home.warning("InsightEngine: FM failed for card \(i) — \(error.localizedDescription)")
                // Fall back to template for this card
                let template = templateNarrative(for: card, context: context)
                updated[i].headline = template.headline
                updated[i].narrative = template.narrative
                updated[i].detailSuggestions = template.suggestions
            }
        }
        return updated
        #else
        return nil
        #endif
    }

    func buildNarrativePrompt(for card: InsightCard, context: WellnessContext) -> String {
        var lines = [
            "You are a wellness coach writing a short insight card for a health app.",
            "Insight type: \(card.type.label). Domain: \(card.domain.label).",
            "Data: \(card.narrative)",
            "",
            "Write a punchy headline (max 60 chars), a 1-2 sentence narrative using 'may suggest' framing (no medical claims),",
            "and exactly 2 specific actionable suggestions."
        ]
        if !context.dataQualityNote.isEmpty {
            lines.append("Note: \(context.dataQualityNote)")
        }
        return lines.joined(separator: "\n")
    }

    func templateNarrative(for card: InsightCard, context: WellnessContext) -> (headline: String, narrative: String, suggestions: [String]) {
        // Return the pre-built headline/narrative from detectors as-is (they are already templated)
        return (headline: card.headline, narrative: card.narrative, suggestions: card.detailSuggestions)
    }
}

// MARK: - Mock Data

private extension InsightEngine {

    func mockInsights() -> [InsightCard] {
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        func dateAgo(_ days: Int) -> Date {
            cal.date(byAdding: .day, value: -days, to: today) ?? today
        }

        return [
            // 1. Sparkline reinforcement (first = dailyInsight, uses .sparkline)
            InsightCard(
                id: UUID(), type: .reinforcement, domain: .hydration,
                headline: "Consistent hydration this week",
                narrative: "You've hit your water goal 6 out of the last 7 days — great consistency.",
                chartData: .sparkline(points: [6, 7, 8, 8, 7, 8, 8]),
                priority: 0.9, isLLMGenerated: false, generatedAt: now,
                detailSuggestions: ["Keep it up — hydration supports every system.", "Try pairing water with each meal."]
            ),
            // 2. Correlation
            InsightCard(
                id: UUID(), type: .correlation, domain: .cross,
                headline: "Sleep & Stress are inversely linked",
                narrative: "On days you slept 7h+, stress averaged 18% lower (r = -0.62, N = 12 days).",
                chartData: .correlationScatter(points: [
                    (x: 5.5, y: 72), (x: 6.0, y: 68), (x: 6.5, y: 61), (x: 7.0, y: 55),
                    (x: 7.5, y: 48), (x: 8.0, y: 42), (x: 7.2, y: 50), (x: 6.8, y: 58),
                    (x: 5.8, y: 70), (x: 7.8, y: 44), (x: 8.2, y: 40), (x: 6.2, y: 65)
                ], r: -0.62, xLabel: "Sleep (h)", yLabel: "Stress"),
                priority: 0.85, isLLMGenerated: false, generatedAt: now,
                detailSuggestions: ["Aim for 7.5h+ tonight.", "Correlation does not imply causation — keep tracking."]
            ),
            // 3. Trend
            InsightCard(
                id: UUID(), type: .trend, domain: .stress,
                headline: "Stress declining 4 days",
                narrative: "Your stress score has dropped from 72 to 48 over the last 4 days.",
                chartData: .trendLine(points: (0..<14).map { i in
                    let scores = [54.0, 58, 66, 73, 79, 75, 67, 57, 49, 48, 52, 55, 50, 48]
                    return (date: dateAgo(13 - i), value: scores[i])
                }, goalLine: 50, metricLabel: "Stress", unit: "/100"),
                priority: 0.75, isLLMGenerated: false, generatedAt: now,
                detailSuggestions: ["Your recovery is on track.", "Maintain sleep and activity levels."]
            ),
            // 4. Milestone
            InsightCard(
                id: UUID(), type: .milestone, domain: .activity,
                headline: "5-day Step Goal streak!",
                narrative: "You've hit 10,000 steps for 5 consecutive days.",
                chartData: .milestoneRing(current: 5, target: 7, streakLabel: "Step Goal"),
                priority: 0.65, isLLMGenerated: false, generatedAt: now,
                detailSuggestions: ["2 more days to a full week!", "Consistency matters more than intensity."]
            ),
            // 5. Imbalance
            InsightCard(
                id: UUID(), type: .imbalance, domain: .nutrition,
                headline: "Protein 28% below goal",
                narrative: "Protein has averaged 65g/day over the last 7 days — 28% below your 90g goal.",
                chartData: .macroRadar(actual: ["Protein": 65, "Carbs": 210, "Fat": 62, "Fiber": 24], goals: ["Protein": 90, "Carbs": 220, "Fat": 65, "Fiber": 30]),
                priority: 0.6, isLLMGenerated: false, generatedAt: now,
                detailSuggestions: ["Add Greek yogurt or eggs to breakfast.", "Protein shakes can close the gap quickly."]
            ),
            // 6. Sleep quality
            InsightCard(
                id: UUID(), type: .sleepQuality, domain: .sleep,
                headline: "Deep sleep improved 18%",
                narrative: "Your deep sleep ratio improved 18% in the last week compared to the week before.",
                chartData: .comparisonBars(bars: [
                    (label: "Earlier", value: 19.5, domain: .sleep),
                    (label: "Recent", value: 23.0, domain: .sleep)
                ], highlight: 1),
                priority: 0.55, isLLMGenerated: false, generatedAt: now,
                detailSuggestions: ["Whatever you changed is working.", "Consistent bedtime helps maintain deep sleep."]
            ),
        ]
    }
}

// MARK: - Foundation Models Schema (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct _InsightNarrativeSchema {
    @Guide(description: "Short punchy headline, max 60 chars, no medical claims")
    var headline: String
    @Guide(description: "1-2 sentence narrative. Use 'may suggest' or 'appears linked'. No diagnosis or medical language.")
    var narrative: String
    @Guide(description: "2 specific actionable suggestions based on the data")
    var suggestions: [_InsightSuggestionItem]
}

@available(iOS 26, *)
@Generable
private struct _InsightSuggestionItem {
    @Guide(description: "One specific, actionable suggestion")
    var text: String
}
#endif
