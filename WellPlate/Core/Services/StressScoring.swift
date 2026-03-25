import Foundation

// MARK: - StressScoring
//
// Pure, stateless scoring functions shared by StressViewModel and StressInsightService.
// No side effects. No SwiftData or HealthKit dependencies.
// Adding a new factor = add one static func here; both consumers pick it up automatically.

enum StressScoring {

    // MARK: - Exercise (0–25, higher = more activity = lower stress)

    /// Returns 0–25. Neutral (12.5) when both inputs are nil.
    static func exerciseScore(steps: Double?, energy: Double?) -> Double {
        guard steps != nil || energy != nil else { return 12.5 }
        var scores: [Double] = []
        if let s = steps  { scores.append(25.0 * clamp(s / 10_000.0)) }
        if let e = energy { scores.append(25.0 * clamp(e / 600.0)) }
        return scores.reduce(0, +) / Double(scores.count)
    }

    // MARK: - Sleep (0–25, higher = better sleep = lower stress)

    /// Returns 0–25. Neutral (12.5) when summary is nil.
    static func sleepScore(summary: DailySleepSummary?) -> Double {
        guard let s = summary else { return 12.5 }
        let h = s.totalHours

        let baseScore: Double
        switch h {
        case ..<4:   baseScore = 0
        case 4..<5:  baseScore = lerp(from: 0,  to: 5,  t: (h - 4) / 1)
        case 5..<6:  baseScore = lerp(from: 5,  to: 12, t: (h - 5) / 1)
        case 6..<7:  baseScore = lerp(from: 12, to: 18, t: (h - 6) / 1)
        case 7..<9:  baseScore = lerp(from: 18, to: 20, t: (h - 7) / 2)
        case 9..<10: baseScore = lerp(from: 20, to: 16, t: (h - 9) / 1)
        default:     baseScore = 14
        }

        let deepBonus: Double
        if h > 0 {
            let deepRatio = s.deepHours / h
            deepBonus = clamp(deepRatio / 0.18) * 5
        } else {
            deepBonus = 2.5
        }

        return Swift.min(25, baseScore + deepBonus)
    }

    // MARK: - Diet (0–25, higher = more balanced = lower stress)

    /// Returns 0–25 based on protein/fiber balance vs fat/carb excess.
    /// Neutral (12.5) when logs are empty.
    static func dietScore(protein: Double, fiber: Double, fat: Double, carbs: Double, hasLogs: Bool) -> Double {
        guard hasLogs else { return 12.5 }

        let proteinRatio  = clamp(protein / 60.0)
        let fiberRatio    = clamp(fiber / 25.0)
        let balancedScore = proteinRatio * 0.55 + fiberRatio * 0.45

        let fatRatio   = clamp(fat / 65.0)
        let carbRatio  = clamp(carbs / 225.0)
        let excessScore = fatRatio * 0.45 + carbRatio * 0.55

        let netBalance = clamp((balancedScore - excessScore * 0.6 + 0.5) / 1.0)
        return 25.0 * netBalance
    }

    // MARK: - Screen Time (0–25, higher = more usage = higher stress)

    /// Returns 0–25. Returns 0 when hours is nil (no data detected).
    static func screenTimeScore(hours: Double?) -> Double {
        guard let h = hours else { return 0 }
        return Swift.min(25, h * 2.0)
    }

    // MARK: - Private Helpers

    private static func clamp(_ value: Double, min lo: Double = 0, max hi: Double = 1) -> Double {
        Swift.min(hi, Swift.max(lo, value))
    }

    private static func lerp(from a: Double, to b: Double, t: Double) -> Double {
        a + (b - a) * clamp(t)
    }
}
