//
//  StressMockSnapshot.swift
//  WellPlate
//
//  Deterministic fixture used by StressViewModel in mock mode.
//  Contains all data that would normally come from HealthKit,
//  ScreenTimeManager, SwiftData, and live sensors.
//

import Foundation

struct StressMockSnapshot {

    // MARK: - Today's values (used for factor scoring)

    let steps: Double
    let energy: Double
    let sleepSummary: DailySleepSummary

    /// Hours of screen time today — drives the screen-time factor score.
    let screenTimeHours: Double

    // MARK: - 30-Day Histories (used by detail views)

    let stepsHistory: [DailyMetricSample]
    let energyHistory: [DailyMetricSample]
    let sleepHistory: [DailySleepSummary]
    let heartRateHistory: [DailyMetricSample]
    let restingHRHistory: [DailyMetricSample]
    let hrvHistory: [DailyMetricSample]
    let systolicBPHistory: [DailyMetricSample]
    let diastolicBPHistory: [DailyMetricSample]
    let respiratoryRateHistory: [DailyMetricSample]
    let daylightHistory: [DailyMetricSample]
    let waterHistory: [DailyMetricSample]
    let exerciseMinutesHistory: [DailyMetricSample]

    // MARK: - Chart Readings (non-persisted, display-only)

    let todayReadings: [StressReading]
    let weekReadings: [StressReading]

    // MARK: - Diet Logs (non-persisted, display-only)

    let currentDayLogs: [FoodLogEntry]

    // MARK: - v3 driver/recovery fixtures

    /// Today's logged mood (drives mood factor + recovery `mindful`).
    let mood: MoodOption?
    /// Today's symptom entries (drives symptoms factor).
    let todaySymptoms: [SymptomEntry]
    /// Today's journal presence (drives recovery `journal`).
    let todayJournal: JournalEntry?
    /// Today's completed intervention sessions (drives recovery `intervention`).
    let todayInterventions: [InterventionSession]
    /// Last 3 days of WellnessDayLog (drives 3-day pattern penalties).
    let recentWellnessLogs: [WellnessDayLog]
    /// Last 3 days of food logs grouped by day (drives `no_food_3d` pattern).
    let recentFoodLogs: [FoodLogEntry]
    /// Last completed FastingSession end (drives `no_fast_14d` pattern).
    let lastCompletedFastEnd: Date?
    /// Today's water glasses (drives hydration factor).
    let waterGlasses: Int
    /// Today's coffee cups (drives caffeine factor).
    let coffeeCups: Int
    /// Today's coffee type (drives caffeine factor mg per cup).
    let coffeeType: CoffeeType?

    // MARK: - Change Log Fixtures
    // MARK: keep in sync with StressChangeEntry
    /// Pre-baked change-log entries shown in the Activity sheet under mock mode.
    /// Defaults to empty; populated by individual factory methods (e.g. `makeDefault`).
    var changeEntries: [MockChangeEntry] = []

    // MARK: - Default Factory

    static let `default`: StressMockSnapshot = makeDefault()

    /// Sparse-data variant — only sleep + screen time have valid data (legacy 2-of-4 coverage).
    static let sparse: StressMockSnapshot = makeSparse()

    /// Driver budget mostly within healthy ranges + good vitals.
    static let fullyLoggedBalancedDay: StressMockSnapshot = makeFullyLoggedBalancedDay()

    /// Driver budget in adverse ranges — score should land in "Very High".
    static let fullyLoggedBadDay: StressMockSnapshot = makeFullyLoggedBadDay()

    /// Bad day at 21:00 with most user-logs missing (engagement penalty maxes).
    static let disengagedBadDay21h: StressMockSnapshot = makeDisengagedBadDay21h()

    /// Day-1 user — almost no data; score must hide (low confidence).
    static let dayOneNoData: StressMockSnapshot = makeDayOneNoData()

    private static func makeSparse() -> StressMockSnapshot {
        let base = makeDefault()
        var stepsHist = base.stepsHistory
        var energyHist = base.energyHistory
        if !stepsHist.isEmpty {
            stepsHist[stepsHist.count - 1] = DailyMetricSample(date: stepsHist.last!.date, value: 0)
        }
        if !energyHist.isEmpty {
            energyHist[energyHist.count - 1] = DailyMetricSample(date: energyHist.last!.date, value: 0)
        }
        return StressMockSnapshot(
            steps: 0,
            energy: 0,
            sleepSummary: base.sleepSummary,
            screenTimeHours: base.screenTimeHours,
            stepsHistory: stepsHist,
            energyHistory: energyHist,
            sleepHistory: base.sleepHistory,
            heartRateHistory: base.heartRateHistory,
            restingHRHistory: base.restingHRHistory,
            hrvHistory: base.hrvHistory,
            systolicBPHistory: base.systolicBPHistory,
            diastolicBPHistory: base.diastolicBPHistory,
            respiratoryRateHistory: base.respiratoryRateHistory,
            daylightHistory: base.daylightHistory,
            waterHistory: base.waterHistory,
            exerciseMinutesHistory: base.exerciseMinutesHistory,
            todayReadings: base.todayReadings,
            weekReadings: base.weekReadings,
            currentDayLogs: [],
            mood: nil,
            todaySymptoms: [],
            todayJournal: nil,
            todayInterventions: [],
            recentWellnessLogs: [],
            recentFoodLogs: [],
            lastCompletedFastEnd: nil,
            waterGlasses: 0,
            coffeeCups: 0,
            coffeeType: nil
        )
    }

    private static func makeFullyLoggedBalancedDay() -> StressMockSnapshot {
        let base = makeDefault()
        // Today: 7.5h sleep, 8000 steps, 4h screen, mood good, 5 water, 1 latte.
        return StressMockSnapshot(
            steps: 8000,
            energy: 380,
            sleepSummary: base.sleepSummary,
            screenTimeHours: 4.0,
            stepsHistory: base.stepsHistory,
            energyHistory: base.energyHistory,
            sleepHistory: base.sleepHistory,
            heartRateHistory: base.heartRateHistory,
            restingHRHistory: base.restingHRHistory,
            hrvHistory: base.hrvHistory,
            systolicBPHistory: base.systolicBPHistory,
            diastolicBPHistory: base.diastolicBPHistory,
            respiratoryRateHistory: base.respiratoryRateHistory,
            daylightHistory: base.daylightHistory,
            waterHistory: base.waterHistory,
            exerciseMinutesHistory: base.exerciseMinutesHistory,
            todayReadings: base.todayReadings,
            weekReadings: base.weekReadings,
            currentDayLogs: base.currentDayLogs,
            mood: .good,
            todaySymptoms: [],
            todayJournal: nil,
            todayInterventions: [],
            recentWellnessLogs: [],
            recentFoodLogs: base.currentDayLogs,
            lastCompletedFastEnd: Date().addingTimeInterval(-3 * 24 * 3600),
            waterGlasses: 6,
            coffeeCups: 1,
            coffeeType: .latte
        )
    }

    private static func makeFullyLoggedBadDay() -> StressMockSnapshot {
        let base = makeDefault()
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        // Sleep: 4.5h total, 20min deep — heavy penalty
        let badSleep = DailySleepSummary(
            date: today,
            totalHours: 4.5,
            coreHours: 3.5,
            remHours: 0.7,
            deepHours: 0.3,
            bedtime: cal.date(byAdding: .hour, value: -5, to: now),
            wakeTime: cal.date(byAdding: .hour, value: -1, to: now)
        )

        // 4 awful symptoms (cognitive + pain)
        let symptoms = [
            SymptomEntry(name: "Headache", category: .pain, severity: 8),
            SymptomEntry(name: "Anxiety", category: .cognitive, severity: 8),
            SymptomEntry(name: "Brain fog", category: .energy, severity: 7),
            SymptomEntry(name: "Fatigue", category: .energy, severity: 7),
        ]

        return StressMockSnapshot(
            steps: 1500,
            energy: 70,
            sleepSummary: badSleep,
            screenTimeHours: 9.0,
            stepsHistory: base.stepsHistory,
            energyHistory: base.energyHistory,
            sleepHistory: base.sleepHistory,
            heartRateHistory: base.heartRateHistory,
            restingHRHistory: base.restingHRHistory,
            hrvHistory: base.hrvHistory,
            systolicBPHistory: base.systolicBPHistory,
            diastolicBPHistory: base.diastolicBPHistory,
            respiratoryRateHistory: base.respiratoryRateHistory,
            daylightHistory: base.daylightHistory,
            waterHistory: base.waterHistory,
            exerciseMinutesHistory: base.exerciseMinutesHistory,
            todayReadings: base.todayReadings,
            weekReadings: base.weekReadings,
            currentDayLogs: base.currentDayLogs,
            mood: .awful,
            todaySymptoms: symptoms,
            todayJournal: nil,
            todayInterventions: [],
            recentWellnessLogs: [],
            recentFoodLogs: base.currentDayLogs,
            lastCompletedFastEnd: nil,   // → no_fast_14d pattern fires
            waterGlasses: 1,
            coffeeCups: 5,
            coffeeType: .coldBrew
        )
    }

    private static func makeDisengagedBadDay21h() -> StressMockSnapshot {
        let base = makeDefault()
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        // Sleep is the only logged driver: 5h total, 30min deep.
        let badSleep = DailySleepSummary(
            date: today,
            totalHours: 5.0,
            coreHours: 3.5,
            remHours: 1.0,
            deepHours: 0.5,
            bedtime: nil,
            wakeTime: nil
        )

        return StressMockSnapshot(
            steps: 0,
            energy: 0,
            sleepSummary: badSleep,
            screenTimeHours: 0,        // no auto reading
            stepsHistory: base.stepsHistory,
            energyHistory: base.energyHistory,
            sleepHistory: base.sleepHistory,
            heartRateHistory: base.heartRateHistory,
            restingHRHistory: base.restingHRHistory,
            hrvHistory: base.hrvHistory,
            systolicBPHistory: base.systolicBPHistory,
            diastolicBPHistory: base.diastolicBPHistory,
            respiratoryRateHistory: base.respiratoryRateHistory,
            daylightHistory: base.daylightHistory,
            waterHistory: base.waterHistory,
            exerciseMinutesHistory: base.exerciseMinutesHistory,
            todayReadings: base.todayReadings,
            weekReadings: base.weekReadings,
            currentDayLogs: [],
            mood: nil,
            todaySymptoms: [],
            todayJournal: nil,
            todayInterventions: [],
            recentWellnessLogs: [],
            recentFoodLogs: [],
            lastCompletedFastEnd: nil,
            waterGlasses: 0,
            coffeeCups: 0,
            coffeeType: nil
        )
    }

    private static func makeDayOneNoData() -> StressMockSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let emptySleep = DailySleepSummary(
            date: today,
            totalHours: 0,
            coreHours: 0,
            remHours: 0,
            deepHours: 0,
            bedtime: nil,
            wakeTime: nil
        )
        return StressMockSnapshot(
            steps: 0,
            energy: 0,
            sleepSummary: emptySleep,
            screenTimeHours: 0,
            stepsHistory: [],
            energyHistory: [],
            sleepHistory: [],
            heartRateHistory: [],
            restingHRHistory: [],
            hrvHistory: [],
            systolicBPHistory: [],
            diastolicBPHistory: [],
            respiratoryRateHistory: [],
            daylightHistory: [],
            waterHistory: [],
            exerciseMinutesHistory: [],
            todayReadings: [],
            weekReadings: [],
            currentDayLogs: [],
            mood: nil,
            todaySymptoms: [],
            todayJournal: nil,
            todayInterventions: [],
            recentWellnessLogs: [],
            recentFoodLogs: [],
            lastCompletedFastEnd: nil,
            waterGlasses: 0,
            coffeeCups: 0,
            coffeeType: nil
        )
    }

    // swiftlint:disable function_body_length
    private static func makeDefault() -> StressMockSnapshot {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        func daysAgo(_ n: Int) -> Date {
            cal.date(byAdding: .day, value: -n, to: today) ?? today
        }

        // ── Today's Input Values ─────────────────────────────────────
        let steps: Double  = 7_500
        let energy: Double = 340.0
        let screenTime: Double = 4.5

        let sleepTodayBedtime = cal.date(bySettingHour: 23, minute: 0, second: 0,
                                          of: cal.date(byAdding: .day, value: -1, to: today)!)
        let sleepToday = DailySleepSummary(
            date: today,
            totalHours: 7.2,
            coreHours: 3.1,
            remHours: 1.8,
            deepHours: 2.3,
            bedtime: sleepTodayBedtime,
            wakeTime: sleepTodayBedtime?.addingTimeInterval(7.2 * 3600)
        )

        // ── 30-Day History Helpers (pattern-based, no randomness) ─────
        let stepsBase: [Double] = [
            6200, 8100, 7500, 9300, 5800, 7200, 8400,
            6700, 7800, 9100, 5500, 8200, 7300, 6900,
            8800, 7100, 6400, 9200, 7700, 8000,
            6500, 7900, 8300, 5900, 7600, 9000, 6800,
            7400, 8600, steps
        ]
        let energyBase: [Double] = [
            280, 360, 340, 420, 250, 310, 390,
            300, 355, 410, 230, 375, 320, 290,
            400, 305, 275, 415, 345, 365,
            270, 355, 385, 255, 340, 410, 295,
            330, 395, energy
        ]
        let sleepTotals: [Double] = [
            7.1, 6.8, 7.4, 8.0, 6.3, 7.6, 7.2,
            6.9, 7.5, 8.2, 6.1, 7.3, 7.8, 6.7,
            8.1, 7.0, 6.5, 7.9, 7.3, 6.8,
            7.2, 8.0, 7.6, 6.4, 7.1, 7.8, 6.9,
            7.4, 7.2, 7.2
        ]
        let hrBase: [Double] = [
            73, 70, 75, 68, 76, 72, 74,
            71, 69, 77, 73, 70, 72, 74,
            71, 75, 73, 69, 72, 70,
            74, 71, 73, 76, 70, 72, 74,
            71, 73, 72
        ]
        let restHRBase: [Double] = [
            58, 56, 60, 55, 61, 57, 59,
            56, 58, 62, 57, 55, 59, 60,
            56, 58, 57, 54, 58, 56,
            59, 57, 58, 61, 55, 57, 59,
            56, 58, 58
        ]
        let hrvBase: [Double] = [
            44, 48, 41, 50, 38, 45, 47,
            42, 46, 51, 39, 44, 43, 47,
            40, 46, 44, 49, 42, 45,
            43, 48, 45, 38, 47, 50, 42,
            44, 46, 42
        ]
        let sysBPBase: [Double] = [
            119, 117, 121, 116, 122, 118, 120,
            117, 119, 123, 118, 116, 120, 121,
            117, 119, 118, 115, 119, 117,
            120, 118, 119, 122, 116, 118, 120,
            117, 119, 118
        ]
        let diasBPBase: [Double] = [
            77, 75, 78, 74, 79, 76, 77,
            75, 77, 80, 76, 74, 77, 78,
            75, 77, 76, 73, 77, 75,
            78, 76, 77, 79, 74, 76, 77,
            75, 77, 76
        ]
        let rrBase: [Double] = [
            15, 14, 16, 14, 16, 15, 15,
            14, 15, 16, 15, 14, 15, 16,
            14, 15, 15, 14, 15, 14,
            15, 15, 16, 14, 15, 16, 15,
            14, 15, 15
        ]

        let count = 30
        let stepsHist   = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: stepsBase[$0]) }
        let energyHist  = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: energyBase[$0]) }
        let hrHist      = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: hrBase[$0]) }
        let restHRHist  = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: restHRBase[$0]) }
        let hrvHist     = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: hrvBase[$0]) }
        let sysBPHist   = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: sysBPBase[$0]) }
        let diasBPHist  = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: diasBPBase[$0]) }
        let rrHist      = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: rrBase[$0]) }

        let deepRatios: [Double] = [0.20, 0.18, 0.22, 0.19, 0.17, 0.21, 0.20, 0.18, 0.22, 0.19,
                                    0.17, 0.21, 0.20, 0.18, 0.22, 0.19, 0.17, 0.21, 0.20, 0.18,
                                    0.22, 0.19, 0.17, 0.21, 0.20, 0.18, 0.22, 0.19, 0.20, 0.19]
        let remRatios:  [Double] = [0.20, 0.21, 0.19, 0.20, 0.22, 0.20, 0.21, 0.20, 0.19, 0.21,
                                    0.22, 0.20, 0.21, 0.19, 0.20, 0.22, 0.20, 0.19, 0.21, 0.22,
                                    0.20, 0.21, 0.22, 0.19, 0.21, 0.20, 0.19, 0.21, 0.20, 0.21]
        let bedtimeHours: [Double] = [
            23.0, 23.3, 22.8, 23.5, 22.5, 23.1, 23.2,
            22.9, 23.4, 23.0, 22.6, 23.3, 23.1, 23.5,
            22.7, 23.0, 23.4, 22.8, 23.2, 23.6,
            23.0, 22.9, 23.3, 22.4, 23.1, 23.0, 23.5,
            22.8, 23.2, 23.0
        ]
        let daylightBase: [Double] = [
            25, 30, 15, 35, 10, 28, 32,
            20, 33, 40, 12, 27, 35, 22,
            38, 18, 25, 42, 30, 28,
            22, 35, 31, 14, 26, 38, 24,
            30, 34, 28
        ]
        let daylightHist = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: daylightBase[$0]) }

        let waterBase: [Double] = [
            1.5, 2.0, 1.8, 2.2, 1.3, 1.9, 2.1,
            1.7, 2.1, 2.4, 1.2, 1.8, 2.0, 1.6,
            2.3, 1.5, 1.4, 2.2, 1.9, 2.0,
            1.6, 2.1, 2.2, 1.3, 1.8, 2.3, 1.7,
            1.9, 2.1, 1.8
        ]
        let exerciseBase: [Double] = [
            30, 45, 0, 60, 20, 35, 50,
            25, 40, 55, 0, 30, 45, 15,
            50, 20, 10, 60, 35, 40,
            0, 45, 50, 15, 30, 55, 25,
            35, 45, 30
        ]
        let waterHist = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: waterBase[$0]) }
        let exerciseHist = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: exerciseBase[$0]) }

        let sleepHist: [DailySleepSummary] = (0..<count).map { i in
            let total = sleepTotals[i]
            let deep  = total * deepRatios[i]
            let rem   = total * remRatios[i]
            let core  = max(0, total - deep - rem)
            let dayDate = daysAgo(count - 1 - i)
            let prevDay = cal.date(byAdding: .day, value: -1, to: dayDate)!
            let btDecimal = bedtimeHours[i]
            let btDate = cal.date(bySettingHour: Int(btDecimal),
                                  minute: Int((btDecimal.truncatingRemainder(dividingBy: 1)) * 60),
                                  second: 0, of: prevDay)
            let wtDate = btDate?.addingTimeInterval(total * 3600)
            return DailySleepSummary(date: dayDate, totalHours: total,
                                     coreHours: core, remHours: rem, deepHours: deep,
                                     bedtime: btDate, wakeTime: wtDate)
        }

        // ── Today's Intraday Readings (hour, score pairs) ─────────────
        let intradayData: [(hour: Int, score: Double)] = [
            (7, 18), (9, 25), (11, 32), (13, 28), (15, 36), (17, 30), (19, 24)
        ]
        let todayReadings: [StressReading] = intradayData.compactMap { item in
            guard let ts = cal.date(bySettingHour: item.hour, minute: 0, second: 0, of: today) else { return nil }
            return StressReading(timestamp: ts, score: item.score,
                                 levelLabel: StressLevel(score: item.score).label, source: "mock")
        }

        // ── Week Readings (one per day, last 7 days) ──────────────────
        let weekScores: [Double] = [45, 38, 52, 29, 41, 35, 33]
        let weekReadings: [StressReading] = weekScores.enumerated().compactMap { (i, score) in
            let day = daysAgo(6 - i)
            guard let ts = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day) else { return nil }
            return StressReading(timestamp: ts, score: score,
                                 levelLabel: StressLevel(score: score).label, source: "mock")
        }

        // ── Diet Logs ─────────────────────────────────────────────────
        let logs: [FoodLogEntry] = [
            FoodLogEntry(day: today, foodName: "Oatmeal with Berries", key: "oatmeal_berries",
                         servingSize: "1 bowl", calories: 310, protein: 9, carbs: 52, fat: 6, fiber: 7,
                         confidence: 0.90, mealType: "Breakfast"),
            FoodLogEntry(day: today, foodName: "Grilled Chicken Salad", key: "chicken_salad",
                         servingSize: "1 plate", calories: 450, protein: 38, carbs: 22, fat: 14, fiber: 6,
                         confidence: 0.88, mealType: "Lunch"),
            FoodLogEntry(day: today, foodName: "Greek Yogurt", key: "greek_yogurt",
                         servingSize: "1 cup", calories: 130, protein: 17, carbs: 10, fat: 2, fiber: 0,
                         confidence: 0.95, mealType: "Snack"),
        ]

        // ── Change Log Fixtures ───────────────────────────────────────
        // ~12 entries spanning today + yesterday. Hand-crafted to read like
        // a plausible day-in-the-life narrative. Mix of kinds + sources.
        let changeEntries: [MockChangeEntry] = makeMockChangeEntries(today: today, yesterday: cal.date(byAdding: .day, value: -1, to: today) ?? today)

        return StressMockSnapshot(
            steps: steps,
            energy: energy,
            sleepSummary: sleepToday,
            screenTimeHours: screenTime,
            stepsHistory: stepsHist,
            energyHistory: energyHist,
            sleepHistory: sleepHist,
            heartRateHistory: hrHist,
            restingHRHistory: restHRHist,
            hrvHistory: hrvHist,
            systolicBPHistory: sysBPHist,
            diastolicBPHistory: diasBPHist,
            respiratoryRateHistory: rrHist,
            daylightHistory: daylightHist,
            waterHistory: waterHist,
            exerciseMinutesHistory: exerciseHist,
            todayReadings: todayReadings,
            weekReadings: weekReadings,
            currentDayLogs: logs,
            mood: nil,
            todaySymptoms: [],
            todayJournal: nil,
            todayInterventions: [],
            recentWellnessLogs: [],
            recentFoodLogs: logs,
            lastCompletedFastEnd: Date().addingTimeInterval(-2 * 24 * 3600),
            waterGlasses: 4,
            coffeeCups: 1,
            coffeeType: .latte,
            changeEntries: changeEntries
        )
    }
    // swiftlint:enable function_body_length

    // MARK: - Change Log Fixtures

    private static func makeMockChangeEntries(today: Date, yesterday: Date) -> [MockChangeEntry] {
        let cal = Calendar.current

        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        // Today's recompute groups (each group shares timestamp + groupID).
        let g1 = UUID()
        let t1 = at(today, 8, 5)
        let g2 = UUID()
        let t2 = at(today, 11, 12)
        let g3 = UUID()
        let t3 = at(today, 13, 30)
        let g4 = UUID()
        let t4 = at(today, 17, 45)
        let g5 = UUID()
        let t5 = at(today, 19, 20)

        // Yesterday's recompute groups.
        let yg1 = UUID()
        let yt1 = at(yesterday, 9, 0)
        let yg2 = UUID()
        let yt2 = at(yesterday, 18, 30)

        return [
            // Today — 8:05 AM: cold-launch anchor (first reading of the day)
            MockChangeEntry(
                id: UUID(), timestamp: t1, groupID: g1, sequence: 0,
                kind: .anchor, subjectKey: "anchor", subjectIcon: "circle.dashed",
                deltaPoints: 0, prevValue: 38, nextValue: 32,
                totalBefore: 38, totalAfter: 32,
                source: .autoAppOpen, detailText: "Day started"
            ),

            // Today — 11:12 AM: logged a healthy breakfast (food + diet improved)
            MockChangeEntry(
                id: UUID(), timestamp: t2, groupID: g2, sequence: 0,
                kind: .factor, subjectKey: "diet", subjectIcon: "leaf.fill",
                deltaPoints: -1.8, prevValue: 4.0, nextValue: 2.2,
                totalBefore: 32, totalAfter: 30,
                source: .manualFoodLog, detailText: "Diet improved"
            ),

            // Today — 1:30 PM: logged 16 oz water (no_water gap closed)
            MockChangeEntry(
                id: UUID(), timestamp: t3, groupID: g3, sequence: 0,
                kind: .engagementGap, subjectKey: "no_water", subjectIcon: "drop.fill",
                deltaPoints: -2.5, prevValue: 2.5, nextValue: 0,
                totalBefore: 30, totalAfter: 28,
                source: .manualWater, detailText: "Water gap closed"
            ),

            // Today — 5:45 PM: screen time creeping up (auto)
            MockChangeEntry(
                id: UUID(), timestamp: t4, groupID: g4, sequence: 0,
                kind: .factor, subjectKey: "screen_time", subjectIcon: "iphone",
                deltaPoints: 1.2, prevValue: 4.5, nextValue: 5.7,
                totalBefore: 28, totalAfter: 29,
                source: .autoTicker, detailText: "Screen Time worsened"
            ),
            MockChangeEntry(
                id: UUID(), timestamp: t4, groupID: g4, sequence: 1,
                kind: .engagementGap, subjectKey: "no_mood", subjectIcon: "face.smiling",
                deltaPoints: 1.6, prevValue: 0, nextValue: 1.6,
                totalBefore: 28, totalAfter: 29,
                source: .autoTicker, detailText: "Mood gap opened"
            ),

            // Today — 7:20 PM: mood logged (great) → mood factor good + closes mood gap
            MockChangeEntry(
                id: UUID(), timestamp: t5, groupID: g5, sequence: 0,
                kind: .factor, subjectKey: "mood", subjectIcon: "face.smiling",
                deltaPoints: -2.5, prevValue: 2.0, nextValue: -0.5,
                totalBefore: 29, totalAfter: 26,
                source: .manualMood, detailText: "Mood improved"
            ),
            MockChangeEntry(
                id: UUID(), timestamp: t5, groupID: g5, sequence: 1,
                kind: .engagementGap, subjectKey: "no_mood", subjectIcon: "face.smiling",
                deltaPoints: -3.2, prevValue: 3.2, nextValue: 0,
                totalBefore: 29, totalAfter: 26,
                source: .manualMood, detailText: "Mood gap closed"
            ),

            // Yesterday — 9:00 AM: cold-launch anchor
            MockChangeEntry(
                id: UUID(), timestamp: yt1, groupID: yg1, sequence: 0,
                kind: .anchor, subjectKey: "anchor", subjectIcon: "circle.dashed",
                deltaPoints: 0, prevValue: 41, nextValue: 35,
                totalBefore: 41, totalAfter: 35,
                source: .autoAppOpen, detailText: "Day started"
            ),

            // Yesterday — 6:30 PM: pattern penalty grew + calibrator tightened (vitals)
            MockChangeEntry(
                id: UUID(), timestamp: yt2, groupID: yg2, sequence: 0,
                kind: .patternPenalty, subjectKey: "pattern", subjectIcon: "waveform.path.ecg",
                deltaPoints: 2.0, prevValue: 0, nextValue: 2.0,
                totalBefore: 35, totalAfter: 38,
                source: .autoScenePhase, detailText: "Pattern penalty grew"
            ),
            MockChangeEntry(
                id: UUID(), timestamp: yt2, groupID: yg2, sequence: 1,
                kind: .calibrator, subjectKey: "calibrator", subjectIcon: "gauge.with.dots.needle.50percent",
                deltaPoints: 1.4, prevValue: 1.0, nextValue: 1.04,
                totalBefore: 35, totalAfter: 38,
                source: .autoScenePhase, detailText: "Vitals calibrator tightened"
            ),
            MockChangeEntry(
                id: UUID(), timestamp: yt2, groupID: yg2, sequence: 2,
                kind: .engagementActivated, subjectKey: "engagement", subjectIcon: "bell.badge",
                deltaPoints: 5.0, prevValue: 0, nextValue: 5.0,
                totalBefore: 35, totalAfter: 38,
                source: .autoScenePhase, detailText: "Engagement scoring activated"
            ),

            // Yesterday — earlier sleep factor improved
            MockChangeEntry(
                id: UUID(), timestamp: at(yesterday, 7, 15), groupID: UUID(), sequence: 0,
                kind: .factor, subjectKey: "sleep", subjectIcon: "moon.fill",
                deltaPoints: -3.5, prevValue: 9.0, nextValue: 5.5,
                totalBefore: 41, totalAfter: 38,
                source: .autoAppOpen, detailText: "Sleep improved"
            ),

            // Yesterday — symptoms logged
            MockChangeEntry(
                id: UUID(), timestamp: at(yesterday, 14, 0), groupID: UUID(), sequence: 0,
                kind: .factor, subjectKey: "symptoms", subjectIcon: "bandage",
                deltaPoints: 2.1, prevValue: 0, nextValue: 2.1,
                totalBefore: 35, totalAfter: 37,
                source: .manualSymptoms, detailText: "Symptoms worsened"
            ),
        ]
    }
}
