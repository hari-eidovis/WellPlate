import Foundation
import SwiftData

// MARK: - ReportDataBuilder
//
// Fetches all SwiftData + HealthKit data for 15-day window, builds
// ReportContext with per-day summaries, food-symptom links, cross-domain
// correlations, intervention results, and experiment summaries.

@MainActor
final class ReportDataBuilder {

    private let lookbackDays = 15

    // MARK: - Public API

    func buildReportContext(
        modelContext: ModelContext,
        healthService: HealthKitServiceProtocol
    ) async -> ReportContext? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today) else { return nil }
        let interval = DateInterval(start: windowStart, end: .now)

        // MARK: SwiftData fetches

        let stressDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= windowStart },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let allReadings = (try? modelContext.fetch(stressDescriptor)) ?? []

        let wellnessDescriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let wellnessLogs = (try? modelContext.fetch(wellnessDescriptor)) ?? []

        let foodDescriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let foodLogs = (try? modelContext.fetch(foodDescriptor)) ?? []

        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let symptomEntries = (try? modelContext.fetch(symptomDescriptor)) ?? []

        let adherenceDescriptor = FetchDescriptor<AdherenceLog>(
            predicate: #Predicate { $0.day >= windowStart }
        )
        let adherenceLogs = (try? modelContext.fetch(adherenceDescriptor)) ?? []

        let supplementDescriptor = FetchDescriptor<SupplementEntry>()
        let allSupplements = ((try? modelContext.fetch(supplementDescriptor)) ?? []).filter { $0.isActive }

        let fastingDescriptor = FetchDescriptor<FastingSession>(
            predicate: #Predicate { $0.startedAt >= windowStart }
        )
        let fastingSessions = ((try? modelContext.fetch(fastingDescriptor)) ?? []).filter { !$0.isActive }

        let interventionDescriptor = FetchDescriptor<InterventionSession>(
            predicate: #Predicate { $0.startedAt >= windowStart }
        )
        let interventionSessions = ((try? modelContext.fetch(interventionDescriptor)) ?? []).filter { $0.completed }

        let experimentDescriptor = FetchDescriptor<StressExperiment>()
        let allExperiments = (try? modelContext.fetch(experimentDescriptor)) ?? []

        let goals = UserGoalsSnapshot(from: UserGoals.current(in: modelContext))

        // MARK: Concurrent HealthKit fetches

        async let sleepFetch = safeFetch { try await healthService.fetchDailySleepSummaries(for: interval) }
        async let stepsFetch = safeFetchMetric { try await healthService.fetchSteps(for: interval) }
        async let energyFetch = safeFetchMetric { try await healthService.fetchActiveEnergy(for: interval) }
        async let heartRateFetch = safeFetchMetric { try await healthService.fetchHeartRate(for: interval) }
        async let exerciseFetch = safeFetchMetric { try await healthService.fetchExerciseMinutes(for: interval) }
        async let restingHRFetch = safeFetchMetric { try await healthService.fetchRestingHeartRate(for: interval) }
        async let hrvFetch = safeFetchMetric { try await healthService.fetchHRV(for: interval) }
        async let systolicFetch = safeFetchMetric { try await healthService.fetchBloodPressureSystolic(for: interval) }
        async let diastolicFetch = safeFetchMetric { try await healthService.fetchBloodPressureDiastolic(for: interval) }
        async let respiratoryFetch = safeFetchMetric { try await healthService.fetchRespiratoryRate(for: interval) }
        async let daylightFetch = safeFetchMetric { try await healthService.fetchDaylight(for: interval) }

        let (sleepSummaries, stepsData, energyData, heartRateData, exerciseData) =
            await (sleepFetch, stepsFetch, energyFetch, heartRateFetch, exerciseFetch)
        let (restingHRData, hrvData, systolicData, diastolicData, respiratoryData, daylightData) =
            await (restingHRFetch, hrvFetch, systolicFetch, diastolicFetch, respiratoryFetch, daylightFetch)

        // MARK: Available vitals (zero-tolerance rule)

        var availableVitals = Set<VitalMetric>()
        if !heartRateData.isEmpty    { availableVitals.insert(.heartRate) }
        if !restingHRData.isEmpty    { availableVitals.insert(.restingHeartRate) }
        if !hrvData.isEmpty          { availableVitals.insert(.hrv) }
        if !systolicData.isEmpty     { availableVitals.insert(.systolicBP) }
        if !diastolicData.isEmpty    { availableVitals.insert(.diastolicBP) }
        if !respiratoryData.isEmpty  { availableVitals.insert(.respiratoryRate) }

        // MARK: Per-day summary loop

        var days: [WellnessDaySummary] = []

        for dayOffset in stride(from: -(lookbackDays - 1), through: 0, by: 1) {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
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

            var summary = WellnessDaySummary(
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
                journalLogged: false
            )

            // Mutate new var fields
            let triggerStrings = dayFood.flatMap { $0.eatingTriggers ?? [] }
            summary.eatingTriggers = Dictionary(triggerStrings.map { ($0, 1) }, uniquingKeysWith: +)
            let typeStrings = dayFood.compactMap { $0.mealType }
            summary.mealTypes = Dictionary(typeStrings.map { ($0, 1) }, uniquingKeysWith: +)
            summary.foodNames = dayFood.map(\.foodName)
            summary.coffeeType = wellness?.coffeeType
            summary.mealTimestamps = dayFood.map(\.createdAt)
            summary.stressMin = dayReadings.map(\.score).min()
            summary.stressMax = dayReadings.map(\.score).max()
            summary.stressReadingCount = dayReadings.count
            summary.restingHeartRateAvg = restingHRData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            summary.hrvAvg = hrvData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            summary.systolicBPAvg = systolicData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            summary.diastolicBPAvg = diastolicData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            summary.respiratoryRateAvg = respiratoryData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
            summary.daylightMinutes = daylightData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value

            days.append(summary)
        }

        // MARK: Compute aggregates

        let foodSymptomLinks = computeFoodSymptomLinks(
            symptomEntries: symptomEntries,
            foodLogs: foodLogs,
            days: days
        )

        let crossCorrelations = await computeCrossCorrelations(
            days: days,
            availableVitals: availableVitals
        )

        let interventionResults = computeInterventionResults(
            sessions: interventionSessions,
            readings: allReadings
        )

        let experimentSummaries = buildExperimentSummaries(
            experiments: allExperiments,
            windowStart: windowStart
        )

        let topFoods = computeTopFoods(foodLogs: foodLogs)
        let perSupplementAdherence = computePerSupplementAdherence(
            adherenceLogs: adherenceLogs,
            supplements: allSupplements
        )

        // Data quality note
        var missingCategories: [String] = []
        if !healthService.isAuthorized { missingCategories.append("HealthKit data") }
        if sleepSummaries.isEmpty { missingCategories.append("sleep") }
        if foodLogs.isEmpty { missingCategories.append("food logs") }
        let qualityNote = missingCategories.isEmpty ? "" : "Some data was unavailable: \(missingCategories.joined(separator: ", "))."

        return ReportContext(
            days: days,
            goals: goals,
            availableVitals: availableVitals,
            foodSymptomLinks: foodSymptomLinks,
            crossCorrelations: crossCorrelations,
            interventionResults: interventionResults,
            experimentSummaries: experimentSummaries,
            topFoods: topFoods,
            perSupplementAdherence: perSupplementAdherence,
            dataQualityNote: qualityNote
        )
    }

    // MARK: - Prompt Context

    func buildPromptContext(from context: ReportContext) -> ReportPromptContext {
        let days = context.days
        let goals = context.goals
        var lines: [String] = []

        let daysWithData = days.filter { d in
            d.stressScore != nil || d.totalCalories != nil || d.sleepHours != nil || d.steps != nil
        }.count

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startLabel = formatter.string(from: days.first?.date ?? .now)
        let endLabel = formatter.string(from: days.last?.date ?? .now)

        lines.append("Period: \(startLabel) - \(endLabel) (\(days.count) days, \(daysWithData) with data)")
        lines.append("")

        // Stress
        let stressValues = days.compactMap(\.stressScore)
        if !stressValues.isEmpty {
            let avg = stressValues.reduce(0, +) / Double(stressValues.count)
            let best = stressValues.min() ?? 0
            let worst = stressValues.max() ?? 0
            lines.append("Stress: avg \(Int(avg)), range \(Int(best))-\(Int(worst))")
        }

        // Sleep
        let sleepValues = days.compactMap(\.sleepHours)
        if !sleepValues.isEmpty {
            let avg = sleepValues.reduce(0, +) / Double(sleepValues.count)
            let metGoal = sleepValues.filter { $0 >= goals.sleepGoalHours }.count
            lines.append("Sleep: avg \(String(format: "%.1f", avg))h, goal \(String(format: "%.0f", goals.sleepGoalHours))h, met goal \(metGoal)/\(sleepValues.count) nights")
        }

        // Steps
        let stepValues = days.compactMap(\.steps)
        if !stepValues.isEmpty {
            let avg = stepValues.reduce(0, +) / stepValues.count
            let metGoal = stepValues.filter { $0 >= goals.dailyStepsGoal }.count
            lines.append("Steps: avg \(avg), goal \(goals.dailyStepsGoal), met goal \(metGoal)/\(stepValues.count) days")
        }

        // Calories
        let calValues = days.compactMap(\.totalCalories)
        if !calValues.isEmpty {
            let avg = calValues.reduce(0, +) / calValues.count
            let protAvg = days.compactMap(\.totalProteinG).reduce(0, +) / max(1, Double(days.compactMap(\.totalProteinG).count))
            let fiberAvg = days.compactMap(\.totalFiberG).reduce(0, +) / max(1, Double(days.compactMap(\.totalFiberG).count))
            lines.append("Calories: avg \(avg), goal \(goals.calorieGoal). Protein avg \(Int(protAvg))g (goal \(goals.proteinGoalGrams)g), Fiber avg \(Int(fiberAvg))g (goal \(goals.fiberGoalGrams)g)")
        }

        // Water
        let waterValues = days.compactMap(\.waterGlasses)
        if !waterValues.isEmpty {
            let avg = Double(waterValues.reduce(0, +)) / Double(waterValues.count)
            let metGoal = waterValues.filter { $0 >= goals.waterDailyCups }.count
            lines.append("Water: avg \(String(format: "%.1f", avg)) cups, goal \(goals.waterDailyCups), met \(metGoal)/\(waterValues.count) days")
        }

        // Coffee
        let coffeeValues = days.compactMap(\.coffeeCups)
        if !coffeeValues.isEmpty {
            let avg = Double(coffeeValues.reduce(0, +)) / Double(coffeeValues.count)
            lines.append("Coffee: avg \(String(format: "%.1f", avg)) cups, limit \(goals.coffeeDailyCups)")
        }

        // Symptoms
        let symptomDays = days.filter { !$0.symptomNames.isEmpty }
        if !symptomDays.isEmpty {
            let allNames = symptomDays.flatMap(\.symptomNames)
            let counts = Dictionary(allNames.map { ($0, 1) }, uniquingKeysWith: +)
            let top = counts.sorted { $0.value > $1.value }.prefix(3)
            let desc = top.map { "\($0.key) (\($0.value) days)" }.joined(separator: ", ")
            lines.append("Symptoms: \(symptomDays.count) days with symptoms. Top: \(desc)")
        }

        // Correlations
        if !context.crossCorrelations.isEmpty {
            let top = context.crossCorrelations.prefix(3)
            let desc = top.map { "\($0.xName)↔\($0.yName) r=\(String(format: "%.2f", $0.spearmanR))" }.joined(separator: ", ")
            lines.append("Correlations: \(desc)")
        }

        // Food-symptom links
        let triggers = context.foodSymptomLinks.filter { $0.classification == .potentialTrigger }
        if !triggers.isEmpty {
            let desc = triggers.prefix(3).map { "\($0.foodName)→\($0.symptomName) (\(String(format: "%.1f", $0.ratio))x)" }.joined(separator: ", ")
            lines.append("Food triggers: \(desc)")
        }

        // Interventions
        if !context.interventionResults.isEmpty {
            let desc = context.interventionResults.map {
                "\($0.resetType): \($0.sessionCount) sessions, avg delta \(String(format: "%.1f", $0.avgDelta))"
            }.joined(separator: "; ")
            lines.append("Interventions: \(desc)")
        }

        return ReportPromptContext(text: lines.joined(separator: "\n"))
    }

    // MARK: - Food-Symptom Correlations

    private func computeFoodSymptomLinks(
        symptomEntries: [SymptomEntry],
        foodLogs: [FoodLogEntry],
        days: [WellnessDaySummary]
    ) -> [FoodSymptomLink] {
        let calendar = Calendar.current
        var results: [FoodSymptomLink] = []

        // Group symptoms by name, filter to >= 3 occurrences
        let symptomsByName = Dictionary(grouping: symptomEntries, by: \.name)
        let qualifyingSymptoms = symptomsByName.filter { $0.value.count >= 3 }

        // All food days (dates with food logs)
        let foodByDay = Dictionary(grouping: foodLogs) { calendar.startOfDay(for: $0.day) }

        for (symptomName, entries) in qualifyingSymptoms {
            let symptomDays = Set(entries.map { calendar.startOfDay(for: $0.day) })
            let allFoodDays = Set(foodByDay.keys)
            let clearDays = allFoodDays.subtracting(symptomDays)

            guard !clearDays.isEmpty else { continue }

            // Collect all unique foods
            let allFoodNames = Set(foodLogs.map(\.foodName))

            for food in allFoodNames {
                // Require food appears >= 2 times total
                let totalAppearances = foodLogs.filter { $0.foodName == food }.count
                guard totalAppearances >= 2 else { continue }

                // Count appearances on symptom days (same day or day before)
                var symptomDayAppearances = 0
                for sd in symptomDays {
                    let dayBefore = calendar.date(byAdding: .day, value: -1, to: sd) ?? sd
                    let foodsOnDay = (foodByDay[sd] ?? []) + (foodByDay[dayBefore] ?? [])
                    if foodsOnDay.contains(where: { $0.foodName == food }) {
                        symptomDayAppearances += 1
                    }
                }

                // Count appearances on clear days
                var clearDayAppearances = 0
                for cd in clearDays {
                    if (foodByDay[cd] ?? []).contains(where: { $0.foodName == food }) {
                        clearDayAppearances += 1
                    }
                }

                // Compute ratio
                let symptomDayCount = symptomDays.count
                let clearDayCount = clearDays.count
                guard clearDayAppearances > 0, clearDayCount > 0 else { continue }

                let symptomRate = Double(symptomDayAppearances) / Double(symptomDayCount)
                let clearRate = Double(clearDayAppearances) / Double(clearDayCount)
                guard clearRate > 0 else { continue }

                let ratio = symptomRate / clearRate

                let classification: FoodSymptomClassification
                if ratio > 2.0 { classification = .potentialTrigger }
                else if ratio < 0.5 { classification = .potentialProtective }
                else { classification = .neutral }

                guard classification != .neutral else { continue }

                results.append(FoodSymptomLink(
                    symptomName: symptomName,
                    foodName: food,
                    symptomDayCount: symptomDayCount,
                    clearDayCount: clearDayCount,
                    symptomDayAppearances: symptomDayAppearances,
                    clearDayAppearances: clearDayAppearances,
                    ratio: ratio,
                    classification: classification
                ))
            }
        }

        return results.sorted { $0.ratio > $1.ratio }
    }

    // MARK: - Cross-Domain Correlations

    private func computeCrossCorrelations(
        days: [WellnessDaySummary],
        availableVitals: Set<VitalMetric>
    ) async -> [CrossCorrelation] {
        struct Pair {
            let xName: String; let yName: String
            let xDomain: WellnessDomain; let yDomain: WellnessDomain
            let xExtract: (WellnessDaySummary) -> Double?
            let yExtract: (WellnessDaySummary) -> Double?
        }

        var pairs: [Pair] = [
            Pair(xName: "Sleep", yName: "Stress", xDomain: .sleep, yDomain: .stress, xExtract: { $0.sleepHours }, yExtract: { $0.stressScore }),
            Pair(xName: "Steps", yName: "Stress", xDomain: .activity, yDomain: .stress, xExtract: { $0.steps.map(Double.init) }, yExtract: { $0.stressScore }),
            Pair(xName: "Coffee", yName: "Stress", xDomain: .caffeine, yDomain: .stress, xExtract: { $0.coffeeCups.map(Double.init) }, yExtract: { $0.stressScore }),
            Pair(xName: "Coffee", yName: "Sleep", xDomain: .caffeine, yDomain: .sleep, xExtract: { $0.coffeeCups.map(Double.init) }, yExtract: { $0.sleepHours }),
            Pair(xName: "Protein", yName: "Stress", xDomain: .nutrition, yDomain: .stress, xExtract: { $0.totalProteinG }, yExtract: { $0.stressScore }),
            Pair(xName: "Fiber", yName: "Stress", xDomain: .nutrition, yDomain: .stress, xExtract: { $0.totalFiberG }, yExtract: { $0.stressScore }),
            Pair(xName: "Water", yName: "Stress", xDomain: .hydration, yDomain: .stress, xExtract: { $0.waterGlasses.map(Double.init) }, yExtract: { $0.stressScore }),
            Pair(xName: "Exercise", yName: "Stress", xDomain: .activity, yDomain: .stress, xExtract: { $0.exerciseMinutes.map(Double.init) }, yExtract: { $0.stressScore }),
            Pair(xName: "Sleep", yName: "Steps", xDomain: .sleep, yDomain: .activity, xExtract: { $0.sleepHours }, yExtract: { $0.steps.map(Double.init) }),
            Pair(xName: "Calories", yName: "Steps", xDomain: .nutrition, yDomain: .activity, xExtract: { $0.totalCalories.map(Double.init) }, yExtract: { $0.steps.map(Double.init) }),
        ]

        // Conditionally add vital-based pairs
        if availableVitals.contains(.heartRate) {
            pairs.append(Pair(xName: "Heart Rate", yName: "Stress", xDomain: .stress, yDomain: .stress, xExtract: { $0.heartRateAvg }, yExtract: { $0.stressScore }))
        }

        var results: [CrossCorrelation] = []

        for pair in pairs {
            var xValues: [Double] = []
            var yValues: [Double] = []
            var scatterPoints: [(x: Double, y: Double)] = []

            for day in days {
                guard let x = pair.xExtract(day), let y = pair.yExtract(day) else { continue }
                xValues.append(x)
                yValues.append(y)
                scatterPoints.append((x: x, y: y))
            }

            guard xValues.count >= 5 else { continue }

            let (r, ciLow, ciHigh) = await Task.detached(priority: .userInitiated) {
                let r = CorrelationMath.spearmanR(xValues, yValues)
                let (lo, hi) = CorrelationMath.bootstrapCI(xValues: xValues, yValues: yValues)
                return (r, lo, hi)
            }.value

            let ciSpansZero = ciLow < 0 && ciHigh > 0
            guard abs(r) >= 0.3 && !ciSpansZero else { continue }

            results.append(CrossCorrelation(
                xName: pair.xName,
                yName: pair.yName,
                xDomain: pair.xDomain,
                yDomain: pair.yDomain,
                spearmanR: r,
                ciLow: ciLow,
                ciHigh: ciHigh,
                pairedDays: xValues.count,
                isSignificant: !ciSpansZero,
                scatterPoints: scatterPoints
            ))
        }

        return results.sorted { abs($0.spearmanR) > abs($1.spearmanR) }
    }

    // MARK: - Intervention Results

    private func computeInterventionResults(
        sessions: [InterventionSession],
        readings: [StressReading]
    ) -> [InterventionResult] {
        let grouped = Dictionary(grouping: sessions, by: \.resetType)
        var results: [InterventionResult] = []

        for (type, typeSessions) in grouped {
            var preScores: [Double] = []
            var postScores: [Double] = []
            var deltas: [Double] = []

            for session in typeSessions {
                let sessionStart = session.startedAt
                let sessionEnd = sessionStart.addingTimeInterval(TimeInterval(session.durationSeconds))
                let fourHours: TimeInterval = 4 * 3600

                // Find closest reading before session (within 4 hours)
                let preReading = readings
                    .filter { $0.timestamp < sessionStart && $0.timestamp > sessionStart.addingTimeInterval(-fourHours) }
                    .max(by: { $0.timestamp < $1.timestamp })

                // Find closest reading after session (within 4 hours)
                let postReading = readings
                    .filter { $0.timestamp > sessionEnd && $0.timestamp < sessionEnd.addingTimeInterval(fourHours) }
                    .min(by: { $0.timestamp < $1.timestamp })

                if let pre = preReading, let post = postReading {
                    preScores.append(pre.score)
                    postScores.append(post.score)
                    deltas.append(post.score - pre.score)
                }
            }

            let hasMeasurable = !deltas.isEmpty
            results.append(InterventionResult(
                resetType: type,
                sessionCount: typeSessions.count,
                avgPreStress: hasMeasurable ? preScores.reduce(0, +) / Double(preScores.count) : 0,
                avgPostStress: hasMeasurable ? postScores.reduce(0, +) / Double(postScores.count) : 0,
                avgDelta: hasMeasurable ? deltas.reduce(0, +) / Double(deltas.count) : 0,
                hasMeasurableData: hasMeasurable
            ))
        }

        return results
    }

    // MARK: - Experiment Summaries

    private func buildExperimentSummaries(
        experiments: [StressExperiment],
        windowStart: Date
    ) -> [ExperimentSummary] {
        let now = Date()
        return experiments
            .filter { $0.startDate <= now && $0.endDate >= windowStart }
            .map { exp in
                ExperimentSummary(
                    name: exp.name,
                    hypothesis: exp.hypothesis,
                    interventionType: exp.interventionType,
                    baselineAvg: exp.cachedBaselineAvg,
                    experimentAvg: exp.cachedExperimentAvg,
                    delta: exp.cachedDelta,
                    ciLow: exp.cachedCILow,
                    ciHigh: exp.cachedCIHigh,
                    isComplete: exp.isComplete
                )
            }
    }

    // MARK: - Top Foods

    private func computeTopFoods(foodLogs: [FoodLogEntry]) -> [(name: String, count: Int, totalCalories: Int)] {
        let grouped = Dictionary(grouping: foodLogs, by: \.foodName)
        return grouped
            .map { (name: $0.key, count: $0.value.count, totalCalories: $0.value.map(\.calories).reduce(0, +)) }
            .sorted { $0.count > $1.count }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - Per-Supplement Adherence

    private func computePerSupplementAdherence(
        adherenceLogs: [AdherenceLog],
        supplements: [SupplementEntry]
    ) -> [(name: String, rate: Double)] {
        let grouped = Dictionary(grouping: adherenceLogs, by: \.supplementName)
        return grouped
            .map { name, logs in
                let taken = Double(logs.filter { $0.status == "taken" }.count)
                let total = Double(logs.count)
                return (name: name, rate: total > 0 ? taken / total : 0)
            }
            .sorted { $0.rate < $1.rate }
    }

    // MARK: - Safe Fetch Helpers

    nonisolated private func safeFetch(_ block: () async throws -> [DailySleepSummary]) async -> [DailySleepSummary] {
        (try? await block()) ?? []
    }

    nonisolated private func safeFetchMetric(_ block: () async throws -> [DailyMetricSample]) async -> [DailyMetricSample] {
        (try? await block()) ?? []
    }
}
