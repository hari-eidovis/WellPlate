import Foundation
import SwiftUI
import Combine

// MARK: - SymptomCorrelation

struct SymptomCorrelation: Identifiable {
    let id: UUID = UUID()
    let symptomName: String
    let factorName: String
    let factorIcon: String      // SF Symbol
    let spearmanR: Double       // −1 to +1
    let ciLow: Double           // 2.5th percentile
    let ciHigh: Double          // 97.5th percentile
    let pairedDays: Int
    let interpretation: String
    let isSignificant: Bool     // CI doesn't span zero
}

// MARK: - SymptomCorrelationEngine

@MainActor
final class SymptomCorrelationEngine: ObservableObject {
    @Published var correlations: [SymptomCorrelation] = []
    @Published var isComputing: Bool = false

    private let minimumDays = 7

    func computeCorrelations(
        symptomName: String,
        symptomEntries: [SymptomEntry],
        foodLogs: [FoodLogEntry],
        wellnessLogs: [WellnessDayLog],
        stressReadings: [StressReading],
        sleepHours: [Date: Double]
    ) async {
        isComputing = true
        defer { isComputing = false }

        let cal = Calendar.current

        // Aggregate symptom entries by day: max severity per day
        let symptomByDay: [Date: Int] = Dictionary(grouping: symptomEntries) { $0.day }
            .compactMapValues { entries in entries.map(\.severity).max() }

        // Daily stress averages
        let stressByDay = StressAnalyticsHelper.dailyAveragesByDate(from: stressReadings)

        // Daily food totals keyed by start-of-day
        let foodByDay = Dictionary(grouping: foodLogs) { cal.startOfDay(for: $0.day) }
        let dailyCalories  = foodByDay.mapValues { $0.reduce(0) { $0 + $1.calories } }
        let dailyProtein   = foodByDay.mapValues { $0.reduce(0.0) { $0 + $1.protein } }
        let dailyFiber     = foodByDay.mapValues { $0.reduce(0.0) { $0 + $1.fiber } }

        // Wellness logs keyed by start-of-day
        let wellnessByDay  = Dictionary(grouping: wellnessLogs) { $0.day }
            .compactMapValues { $0.first }

        // Factor definitions
        struct Factor {
            let name: String
            let icon: String
            let value: (Date) -> Double?
        }

        let factors: [Factor] = [
            Factor(name: "Caffeine",     icon: "cup.and.saucer.fill") { day in wellnessByDay[day].map { Double($0.coffeeCups) } },
            Factor(name: "Stress score", icon: "brain.head.profile.fill") { day in stressByDay[day] },
            Factor(name: "Sleep hours",  icon: "moon.stars.fill") { day in sleepHours[day] },
            Factor(name: "Calories",     icon: "fork.knife") { day in dailyCalories[day].map { Double($0) } },
            Factor(name: "Protein",      icon: "fish.fill") { day in dailyProtein[day] },
            Factor(name: "Fiber",        icon: "leaf.fill") { day in dailyFiber[day] },
            Factor(name: "Water",        icon: "drop.fill") { day in wellnessByDay[day].map { Double($0.waterGlasses) } },
        ]

        // Compute correlation per factor
        let symptomDays = Array(symptomByDay.keys)
        var results: [SymptomCorrelation] = []

        for factor in factors {
            // Build paired arrays for days where both symptom and factor exist
            var symptomValues: [Double] = []
            var factorValues: [Double] = []

            for day in symptomDays {
                guard let sev = symptomByDay[day],
                      let fVal = factor.value(day) else { continue }
                symptomValues.append(Double(sev))
                factorValues.append(fVal)
            }

            let n = symptomValues.count

            if n < minimumDays {
                // Not enough data — create a collecting-data placeholder
                results.append(SymptomCorrelation(
                    symptomName: symptomName,
                    factorName: factor.name,
                    factorIcon: factor.icon,
                    spearmanR: 0,
                    ciLow: -1,
                    ciHigh: 1,
                    pairedDays: n,
                    interpretation: "Collecting data",
                    isSignificant: false
                ))
            } else {
                // Compute off main actor
                let (r, ciLow, ciHigh) = await Task.detached(priority: .userInitiated) {
                    let r = Self.spearmanR(symptomValues, factorValues)
                    let (lo, hi) = Self.bootstrapCI(symptomValues: symptomValues, factorValues: factorValues, iterations: 1000)
                    return (r, lo, hi)
                }.value

                let ciSpansZero = ciLow < 0 && ciHigh > 0
                let interp = Self.interpretationLabel(r: r, ciSpansZero: ciSpansZero)

                results.append(SymptomCorrelation(
                    symptomName: symptomName,
                    factorName: factor.name,
                    factorIcon: factor.icon,
                    spearmanR: r,
                    ciLow: ciLow,
                    ciHigh: ciHigh,
                    pairedDays: n,
                    interpretation: interp,
                    isSignificant: !ciSpansZero
                ))
            }
        }

        // Sort: significant first, then by |r| descending, collecting-data last
        results.sort {
            if $0.pairedDays >= minimumDays && $1.pairedDays < minimumDays { return true }
            if $0.pairedDays < minimumDays && $1.pairedDays >= minimumDays { return false }
            return abs($0.spearmanR) > abs($1.spearmanR)
        }

        correlations = results
    }

    // MARK: - Spearman Rank Correlation

    nonisolated private static func spearmanR(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 2 else { return 0 }
        let rx = ranks(of: x)
        let ry = ranks(of: y)
        return pearsonR(rx, ry)
    }

    nonisolated private static func ranks(of values: [Double]) -> [Double] {
        let n = values.count
        let indexed = values.enumerated().sorted { $0.element < $1.element }
        var result = [Double](repeating: 0, count: n)

        var i = 0
        while i < n {
            var j = i
            // Find ties
            while j < n - 1 && indexed[j].element == indexed[j + 1].element { j += 1 }
            // Assign average rank (1-based)
            let avgRank = Double(i + j) / 2.0 + 1.0
            for k in i...j {
                result[indexed[k].offset] = avgRank
            }
            i = j + 1
        }
        return result
    }

    nonisolated private static func pearsonR(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        let xBar = x.reduce(0, +) / n
        let yBar = y.reduce(0, +) / n
        let num = zip(x, y).reduce(0.0) { $0 + ($1.0 - xBar) * ($1.1 - yBar) }
        let dxSq = x.reduce(0.0) { $0 + pow($1 - xBar, 2) }
        let dySq = y.reduce(0.0) { $0 + pow($1 - yBar, 2) }
        let denom = sqrt(dxSq * dySq)
        guard denom > 0 else { return 0 }
        return max(-1, min(1, num / denom))
    }

    // MARK: - Bootstrap CI (95%)

    nonisolated private static func bootstrapCI(
        symptomValues: [Double],
        factorValues: [Double],
        iterations: Int
    ) -> (low: Double, high: Double) {
        let pairs = Array(zip(symptomValues, factorValues))
        let n = pairs.count
        var rValues: [Double] = []
        rValues.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let sample = (0..<n).map { _ in pairs.randomElement()! }
            let sX = sample.map(\.0)
            let sY = sample.map(\.1)
            rValues.append(spearmanR(sX, sY))
        }

        rValues.sort()
        let lo = Int(Double(iterations) * 0.025) // 2.5th percentile → 95% CI
        let hi = Int(Double(iterations) * 0.975) // 97.5th percentile
        return (rValues[lo], rValues[hi])
    }

    // MARK: - Interpretation

    nonisolated static func interpretationLabel(r: Double, ciSpansZero: Bool) -> String {
        if ciSpansZero { return "No clear pattern (yet)" }
        let direction = r > 0 ? "positive" : "negative"
        let strength: String
        switch abs(r) {
        case 0..<0.3: strength = "weak"
        case 0.3..<0.6: strength = "moderate"
        default: strength = "strong"
        }
        return "\(strength) \(direction) association"
    }
}
