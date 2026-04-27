import Foundation

// MARK: - StressScoring
//
// Pure, stateless scoring functions shared by StressViewModel and StressInsightService.
// No side effects. No SwiftData or HealthKit dependencies.
// Adding a new factor = add one static func here; both consumers pick it up automatically.

enum StressScoring {

    // MARK: - Factor Weights (Phase 1: Sleep 35 / Exercise 25 / Diet 20 / Screen 20)

    enum Weights {
        static let sleep: Double      = 35
        static let exercise: Double   = 25
        static let diet: Double       = 20
        static let screenTime: Double = 20
        // total = 100
    }

    // MARK: - Exercise (0–Weights.exercise, higher = more activity = lower stress)

    /// Returns 0–`Weights.exercise`. Returns nil when both inputs are nil (missing data).
    /// Q3: step target lowered 10k → 7k per Research §4a (benefits plateau at 5–7k).
    static func exerciseScore(steps: Double?, energy: Double?) -> Double? {
        guard steps != nil || energy != nil else { return nil }
        let max = Weights.exercise
        var scores: [Double] = []
        if let s = steps  { scores.append(max * clamp(s / 7_000.0)) }
        if let e = energy { scores.append(max * clamp(e / 600.0)) }
        return scores.reduce(0, +) / Double(scores.count)
    }

    // MARK: - Sleep (0–Weights.sleep, higher = better sleep = lower stress)

    /// Returns 0–`Weights.sleep`. Returns nil when summary is missing.
    /// Encodes Research §3b: deep sleep <45 min caps the score regardless of total hours.
    static func sleepScore(summary: DailySleepSummary?) -> Double? {
        guard let s = summary else { return nil }
        let max = Weights.sleep
        let h = s.totalHours

        // Duration curve — was anchored to 0…25; re-scaled to a 0…0.80 fraction of `max` (35).
        let durationFraction: Double
        switch h {
        case ..<4:   durationFraction = 0.0
        case 4..<5:  durationFraction = lerp(from: 0.00, to: 0.20, t: (h - 4) / 1)
        case 5..<6:  durationFraction = lerp(from: 0.20, to: 0.48, t: (h - 5) / 1)
        case 6..<7:  durationFraction = lerp(from: 0.48, to: 0.72, t: (h - 6) / 1)
        case 7..<9:  durationFraction = lerp(from: 0.72, to: 0.80, t: (h - 7) / 2)
        case 9..<10: durationFraction = lerp(from: 0.80, to: 0.64, t: (h - 9) / 1)
        default:     durationFraction = 0.56
        }
        var score = max * durationFraction

        // Deep-sleep ratio bonus (scaled to new ceiling — up to 20% of max).
        if h > 0 {
            let deepRatio = s.deepHours / h
            score += clamp(deepRatio / 0.18) * (max * 0.20)
        }

        // Q4: absolute deep-sleep floor — cap at 70% of max if <45 min even if hours are optimal.
        // Research §3b: "If deep sleep duration falls below 45 minutes, cortisol clearance is incomplete".
        // NOTE (M1): 70% is an engineering choice (no research anchor for magnitude).
        // Re-evaluated in Phase 3 alongside age-band lowered thresholds (S3).
        let deepMinutes = s.deepHours * 60.0
        if deepMinutes < 45 {
            score = Swift.min(score, max * 0.70)
        }

        return Swift.min(max, score)
    }

    // MARK: - Diet (0–Weights.diet, higher = more balanced = lower stress)

    /// Returns 0–`Weights.diet`. Returns nil when `hasLogs == false`.
    static func dietScore(protein: Double, fiber: Double, fat: Double, carbs: Double, hasLogs: Bool) -> Double? {
        guard hasLogs else { return nil }
        let max = Weights.diet

        let proteinRatio  = clamp(protein / 60.0)
        let fiberRatio    = clamp(fiber / 25.0)
        let balancedScore = proteinRatio * 0.55 + fiberRatio * 0.45

        let fatRatio   = clamp(fat / 65.0)
        let carbRatio  = clamp(carbs / 225.0)
        let excessScore = fatRatio * 0.45 + carbRatio * 0.55

        let netBalance = clamp((balancedScore - excessScore * 0.6 + 0.5) / 1.0)
        return max * netBalance
    }

    // MARK: - Screen Time (0–Weights.screenTime, higher = more usage = higher stress)

    // Q5 evening ×1.5 multiplier ships in StressScoringV2 — requires hourly-bucket refactor of ScreenTimeManager, tracked in Phase 2.
    /// Returns 0–`Weights.screenTime`. Returns nil when hours is nil.
    static func screenTimeScore(hours: Double?) -> Double? {
        guard let h = hours else { return nil }
        let max = Weights.screenTime
        return Swift.min(max, h * (max / 8.0))
    }

    // MARK: - Private Helpers

    private static func clamp(_ value: Double, min lo: Double = 0, max hi: Double = 1) -> Double {
        Swift.min(hi, Swift.max(lo, value))
    }

    private static func lerp(from a: Double, to b: Double, t: Double) -> Double {
        a + (b - a) * clamp(t)
    }
}
