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

    // MARK: - Chart Readings (non-persisted, display-only)

    let todayReadings: [StressReading]
    let weekReadings: [StressReading]

    // MARK: - Diet Logs (non-persisted, display-only)

    let currentDayLogs: [FoodLogEntry]

    // MARK: - Default Factory

    static let `default`: StressMockSnapshot = makeDefault()

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

        let sleepToday = DailySleepSummary(
            date: today,
            totalHours: 7.2,
            coreHours: 3.1,
            remHours: 1.8,
            deepHours: 2.3
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
        let sleepHist: [DailySleepSummary] = (0..<count).map { i in
            let total = sleepTotals[i]
            let deep  = total * deepRatios[i]
            let rem   = total * remRatios[i]
            let core  = max(0, total - deep - rem)
            return DailySleepSummary(date: daysAgo(count - 1 - i), totalHours: total,
                                     coreHours: core, remHours: rem, deepHours: deep)
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
            todayReadings: todayReadings,
            weekReadings: weekReadings,
            currentDayLogs: logs
        )
    }
    // swiftlint:enable function_body_length
}
