//
//  CircadianService.swift
//  WellPlate
//
//  Stateless scoring for circadian health: sleep regularity + daylight exposure.
//  Follows the StressScoring pattern — pure functions, no side effects.
//

import Foundation

enum CircadianService {

    // MARK: - Level Labels

    enum CircadianLevel: String {
        case aligned   = "Aligned"
        case adjusting = "Adjusting"
        case disrupted = "Disrupted"

        init(score: Double) {
            switch score {
            case 70...:   self = .aligned
            case 40..<70: self = .adjusting
            default:      self = .disrupted
            }
        }
    }

    // MARK: - Composite Result

    struct CircadianResult {
        let score: Double              // 0–100
        let regularityScore: Double    // 0–100 (SRI sub-score)
        let daylightScore: Double?     // 0–100 (nil if no Watch data)
        let level: CircadianLevel
        let tip: String
        let hasEnoughData: Bool        // false if < 5 nights
    }

    // MARK: - Compute

    static func compute(
        sleepSummaries: [DailySleepSummary],
        daylightSamples: [DailyMetricSample]
    ) -> CircadianResult {
        let (regScore, hasData) = sleepRegularityIndex(from: sleepSummaries)
        let dayScore = daylightScore(from: daylightSamples)

        let composite: Double
        if let ds = dayScore {
            composite = regScore * 0.5 + ds * 0.5
        } else {
            composite = regScore
        }

        let finalScore = hasData ? composite : 0
        let tip = selectTip(regularityScore: regScore, daylightScore: dayScore)
        let level = CircadianLevel(score: finalScore)

        return CircadianResult(
            score: finalScore,
            regularityScore: regScore,
            daylightScore: dayScore,
            level: level,
            tip: tip,
            hasEnoughData: hasData
        )
    }

    // MARK: - Sleep Regularity Index

    /// Compute SRI from sleep summaries.
    /// Requires >= 5 nights with valid bedtime data.
    /// Returns 0-100 where 100 = perfectly regular.
    static func sleepRegularityIndex(from summaries: [DailySleepSummary]) -> (score: Double, hasEnoughData: Bool) {
        let validNights = summaries.filter { $0.bedtime != nil && $0.wakeTime != nil }
        guard validNights.count >= 5 else { return (0, false) }

        let bedtimeMinutes = validNights.compactMap { $0.bedtime.map { minutesPast6PM($0) } }
        let wakeMinutes = validNights.compactMap { $0.wakeTime.map { minutesPast6PM($0) } }

        let bedSD = standardDeviation(bedtimeMinutes)
        let wakeSD = standardDeviation(wakeMinutes)

        // Wake time weighted 60%, bedtime 40% (wake consistency more important for entrainment)
        let combinedSD = wakeSD * 0.6 + bedSD * 0.4
        let score = max(0, 100.0 * (1.0 - combinedSD / 75.0))

        return (min(100, score), true)
    }

    // MARK: - Daylight Score

    /// Score from daily daylight exposure.
    /// Returns 0-100 where 100 = >= 30 min/day average. Nil if no samples.
    static func daylightScore(from samples: [DailyMetricSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let avg = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return min(100, avg / 30.0 * 100.0)
    }

    // MARK: - Tip Selection

    static func selectTip(regularityScore: Double, daylightScore: Double?) -> String {
        if let ds = daylightScore {
            if regularityScore <= ds {
                return "Try going to bed within 30 min of your usual time"
            } else {
                return "10 min of outdoor light before noon helps set your clock"
            }
        }
        if regularityScore >= 70 {
            return "Great sleep rhythm — keep it up!"
        }
        return "Consistent bed and wake times help your body recover"
    }

    // MARK: - Private Helpers

    /// Convert a Date to minutes past 6 PM (handles midnight crossing).
    /// 6 PM = 0, 11 PM = 300, midnight = 360, 2 AM = 480.
    private static func minutesPast6PM(_ date: Date) -> Double {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let min = cal.component(.minute, from: date)
        let totalMin = Double(hour * 60 + min)
        let shifted = totalMin - (18 * 60)
        return shifted >= 0 ? shifted : shifted + (24 * 60)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
