import Foundation

struct StressLabResult {
    let baselineAvg: Double
    let experimentAvg: Double
    let delta: Double
    let ciLow: Double
    let ciHigh: Double
    let baselineDayCount: Int
    let experimentDayCount: Int
}

struct StressLabAnalyzer {

    static let minimumDays = 3

    static func analyze(
        experiment: StressExperiment,
        allReadings: [StressReading]
    ) -> StressLabResult? {
        let cal = Calendar.current

        let baselineEnd   = experiment.startDate
        let baselineStart = cal.date(byAdding: .day, value: -7, to: baselineEnd) ?? baselineEnd
        let experimentEnd = min(experiment.endDate, cal.startOfDay(for: Date()))

        let baselineReadings   = allReadings.filter { $0.timestamp >= baselineStart && $0.timestamp < baselineEnd }
        let experimentReadings = allReadings.filter { $0.timestamp >= experiment.startDate && $0.timestamp < experimentEnd }

        let baselineDailyAvgs   = StressAnalyticsHelper.dailyAverages(from: baselineReadings)
        let experimentDailyAvgs = StressAnalyticsHelper.dailyAverages(from: experimentReadings)

        guard baselineDailyAvgs.count >= minimumDays,
              experimentDailyAvgs.count >= minimumDays else { return nil }

        let baselineAvg   = baselineDailyAvgs.reduce(0, +) / Double(baselineDailyAvgs.count)
        let experimentAvg = experimentDailyAvgs.reduce(0, +) / Double(experimentDailyAvgs.count)
        let delta         = experimentAvg - baselineAvg

        let (ciLow, ciHigh) = bootstrapCI(
            baseline: baselineDailyAvgs,
            experiment: experimentDailyAvgs,
            iterations: 1000
        )

        return StressLabResult(
            baselineAvg: baselineAvg,
            experimentAvg: experimentAvg,
            delta: delta,
            ciLow: ciLow,
            ciHigh: ciHigh,
            baselineDayCount: baselineDailyAvgs.count,
            experimentDayCount: experimentDailyAvgs.count
        )
    }

    private static func bootstrapCI(
        baseline: [Double],
        experiment: [Double],
        iterations: Int
    ) -> (low: Double, high: Double) {
        var deltas: [Double] = []
        deltas.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let bSample = (0..<baseline.count).map { _ in baseline.randomElement() ?? 0 }
            let eSample = (0..<experiment.count).map { _ in experiment.randomElement() ?? 0 }
            let bAvg = bSample.reduce(0, +) / Double(bSample.count)
            let eAvg = eSample.reduce(0, +) / Double(eSample.count)
            deltas.append(eAvg - bAvg)
        }

        deltas.sort()
        let lo = Int(Double(iterations) * 0.05)
        let hi = Int(Double(iterations) * 0.95)
        return (deltas[lo], deltas[hi])
    }
}
