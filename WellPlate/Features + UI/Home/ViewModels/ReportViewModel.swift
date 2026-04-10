import Foundation
import SwiftData
import Combine

// MARK: - AI15DayReportViewModel

@MainActor
final class AI15DayReportViewModel: ObservableObject {

    @Published var reportState: ReportState = .idle

    private let dataBuilder = ReportDataBuilder()
    private let narrativeGenerator = ReportNarrativeGenerator()
    private var modelContext: ModelContext?
    private let healthService: HealthKitServiceProtocol

    init(healthService: HealthKitServiceProtocol = HealthKitService()) {
        self.healthService = healthService
    }

    func bindContext(_ context: ModelContext) {
        modelContext = context
    }

    // MARK: - Generate

    func generateReport() async {
        // Same-day cache
        if case .ready(let data) = reportState,
           Calendar.current.isDateInToday(data.generatedAt) {
            return
        }

        // Mock mode
        if AppConfig.shared.mockMode {
            reportState = .generating(progress: 0.5)
            try? await Task.sleep(for: .milliseconds(400))
            reportState = .ready(Self.mockReportData())
            return
        }

        reportState = .generating(progress: 0)

        guard let ctx = modelContext else {
            reportState = .error("No data context available.")
            return
        }

        // Step 1: Build context
        reportState = .generating(progress: 0.1)
        guard let context = await dataBuilder.buildReportContext(
            modelContext: ctx,
            healthService: healthService
        ) else {
            reportState = .error("Could not build report context.")
            return
        }

        // Step 2: Build prompt context
        reportState = .generating(progress: 0.3)
        let promptContext = dataBuilder.buildPromptContext(from: context)

        // Step 3: Generate narratives
        reportState = .generating(progress: 0.4)
        let narratives = await narrativeGenerator.generateNarratives(
            for: context,
            promptContext: promptContext
        )

        // Step 4: Assemble
        reportState = .generating(progress: 1.0)
        let reportData = ReportData(
            context: context,
            narratives: narratives,
            generatedAt: .now
        )

        reportState = .ready(reportData)
    }

    func clearAndRegenerate() async {
        reportState = .idle
        await generateReport()
    }

    // MARK: - Mock Data

    private static func mockReportData() -> ReportData {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        func dateAgo(_ d: Int) -> Date {
            cal.date(byAdding: .day, value: -d, to: today) ?? today
        }

        let stressScores: [Double] = [54, 58, 66, 73, 79, 75, 67, 57, 49, 48, 52, 55, 50, 48, 45]
        let sleepHours: [Double] = [7.2, 6.5, 5.8, 6.0, 5.5, 6.8, 7.0, 7.5, 7.8, 8.0, 6.5, 7.2, 7.0, 7.5, 7.8]
        let stepCounts: [Int] = [8200, 7400, 6100, 5500, 9200, 10500, 8800, 7600, 11200, 9800, 7200, 8400, 9600, 10200, 8900]

        var days: [WellnessDaySummary] = []
        for i in 0..<15 {
            var s = WellnessDaySummary(
                date: dateAgo(14 - i),
                stressScore: stressScores[i],
                stressLabel: StressLevel(score: stressScores[i]).label,
                sleepHours: sleepHours[i],
                deepSleepHours: sleepHours[i] * 0.18,
                remSleepHours: sleepHours[i] * 0.22,
                bedtime: nil,
                wakeTime: nil,
                steps: stepCounts[i],
                activeCalories: 200 + stepCounts[i] / 20,
                exerciseMinutes: 20 + i * 2,
                heartRateAvg: 68 + Double(i % 5),
                totalCalories: 1600 + i * 30,
                totalProteinG: 55 + Double(i * 3),
                totalCarbsG: 180 + Double(i * 5),
                totalFatG: 55 + Double(i * 2),
                totalFiberG: 15 + Double(i),
                mealCount: i % 2 == 0 ? 3 : 2,
                waterGlasses: 4 + i % 5,
                coffeeCups: 2 + i % 3,
                moodLabel: ["Good", "Okay", "Great", "Good", "Awful", "Good", "Great", "Good", "Okay", "Great", "Good", "Good", "Great", "Good", "Great"][i],
                symptomNames: i == 2 || i == 5 || i == 8 ? ["Bloating"] : (i == 4 ? ["Headache", "Bloating"] : []),
                symptomMaxSeverity: i == 2 || i == 5 || i == 8 ? 5 : (i == 4 ? 7 : nil),
                fastingHours: i % 4 == 0 ? 16.0 : nil,
                fastingCompleted: i % 4 == 0 ? true : nil,
                supplementAdherence: i < 12 ? 0.75 : 1.0,
                journalLogged: false
            )
            s.stressMin = stressScores[i] - 8
            s.stressMax = stressScores[i] + 12
            s.stressReadingCount = 4
            s.mealTypes = ["breakfast": 1, "lunch": 1, "dinner": i % 2 == 0 ? 1 : 0]
            s.eatingTriggers = i % 3 == 0 ? ["stressed": 1] : ["hungry": 1]
            s.foodNames = ["Oatmeal", "Chicken salad", "Rice bowl"]
            s.mealTimestamps = [dateAgo(14 - i)]
            days.append(s)
        }

        let goals = UserGoalsSnapshot(from: UserGoals.defaults())

        let context = ReportContext(
            days: days,
            goals: goals,
            availableVitals: [.heartRate],
            foodSymptomLinks: [
                FoodSymptomLink(symptomName: "Bloating", foodName: "Dairy", symptomDayCount: 4, clearDayCount: 11, symptomDayAppearances: 3, clearDayAppearances: 2, ratio: 4.12, classification: .potentialTrigger),
                FoodSymptomLink(symptomName: "Bloating", foodName: "Greek yogurt", symptomDayCount: 4, clearDayCount: 11, symptomDayAppearances: 1, clearDayAppearances: 5, ratio: 0.27, classification: .potentialProtective),
            ],
            crossCorrelations: [
                CrossCorrelation(xName: "Sleep", yName: "Stress", xDomain: .sleep, yDomain: .stress, spearmanR: -0.62, ciLow: -0.85, ciHigh: -0.30, pairedDays: 15, isSignificant: true, scatterPoints: zip(sleepHours, stressScores).map { (x: $0, y: $1) }),
                CrossCorrelation(xName: "Steps", yName: "Stress", xDomain: .activity, yDomain: .stress, spearmanR: -0.45, ciLow: -0.72, ciHigh: -0.10, pairedDays: 15, isSignificant: true, scatterPoints: zip(stepCounts.map(Double.init), stressScores).map { (x: $0, y: $1) }),
            ],
            interventionResults: [
                InterventionResult(resetType: "pmr", sessionCount: 3, avgPreStress: 68, avgPostStress: 52, avgDelta: -16, hasMeasurableData: true)
            ],
            experimentSummaries: [],
            topFoods: [
                (name: "Oatmeal", count: 12, totalCalories: 3600),
                (name: "Chicken salad", count: 10, totalCalories: 4500),
                (name: "Rice bowl", count: 8, totalCalories: 4800),
                (name: "Greek yogurt", count: 7, totalCalories: 980),
                (name: "Banana", count: 6, totalCalories: 630),
            ],
            perSupplementAdherence: [
                (name: "Omega-3", rate: 0.53),
                (name: "Vitamin D", rate: 0.87),
            ],
            dataQualityNote: ""
        )

        let narratives = ReportNarratives(
            executiveSummary: ExecutiveSummaryNarrative(
                narrative: "Over the past 15 days, your stress has been declining — dropping from 73 to 45. Sleep improved in the second week, averaging 7.4h vs 6.3h in the first. Your step count may suggest a link with lower stress the following day.",
                topWin: "Stress down 38% over 15 days",
                topConcern: "Protein 40% below goal"
            ),
            sectionNarratives: [
                "stress": SectionNarrative(headline: "Stress trending down", narrative: "Your stress dropped from 73 to 45 over 15 days, with the biggest improvement in the last week."),
                "nutrition": SectionNarrative(headline: "Calorie intake steady", narrative: "Averaging 1,820 kcal/day against your 2,000 goal. Protein remains below target."),
                "sleep": SectionNarrative(headline: "Sleep improving", narrative: "Sleep hours improved from 6.3h in the first week to 7.4h recently."),
                "activity": SectionNarrative(headline: "8,700 steps/day average", narrative: "You averaged 8,700 steps, meeting your 10K goal on 4 days."),
            ],
            actionPlan: [
                ActionRecommendation(title: "Prioritize 7.5h+ sleep", rationale: "On nights with 7.5h+ sleep, your next-day stress averaged 18% lower.", domain: "sleep"),
                ActionRecommendation(title: "Increase protein intake", rationale: "Protein averaged 70g, 53% below your 150g goal.", domain: "nutrition"),
                ActionRecommendation(title: "Continue PMR sessions", rationale: "Your 3 PMR sessions showed an average 16-point stress reduction.", domain: "stress"),
            ]
        )

        return ReportData(context: context, narratives: narratives, generatedAt: .now)
    }
}
