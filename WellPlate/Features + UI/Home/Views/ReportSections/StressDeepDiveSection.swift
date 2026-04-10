import SwiftUI
import Charts

struct StressDeepDiveSection: View {
    let data: ReportData

    private var stressDays: [(date: Date, value: Double)] {
        data.context.days.compactMap { d in
            guard let s = d.stressScore else { return nil }
            return (date: d.date, value: s)
        }
    }

    private var narrative: SectionNarrative? { data.narratives.sectionNarratives["stress"] }

    var body: some View {
        ReportSectionCard(title: narrative?.headline ?? "Stress Overview", domain: .stress) {
            if let n = narrative {
                Text(n.narrative)
                    .font(.r(.subheadline, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 2a: Trend
            TrendAreaChart(points: stressDays, goalLine: 50, metricLabel: "Stress", unit: "/100", accentColor: WellnessDomain.stress.accentColor)

            stressStatPills

            // 2b: Volatility
            let volatilityPoints = data.context.days.compactMap { d -> (date: Date, min: Double, max: Double, avg: Double)? in
                guard let avg = d.stressScore, let mn = d.stressMin, let mx = d.stressMax else { return nil }
                return (date: d.date, min: mn, max: mx, avg: avg)
            }
            if volatilityPoints.count >= 3 {
                Text("Daily Stress Range")
                    .font(.r(.footnote, .semibold))
                    .foregroundStyle(.secondary)
                StressVolatilityChart(points: volatilityPoints)
            }

            // 2c: Factor decomposition
            factorDecomposition

            // 2d: Best vs worst day
            bestWorstComparison

            // 2e: Interventions
            interventionSection

            // 2f: Experiments
            experimentSection
        }
    }

    // MARK: - Stat Pills

    private var stressStatPills: some View {
        let values = data.context.days.compactMap(\.stressScore)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let best = values.min() ?? 0
        let worst = values.max() ?? 0
        return StatPillRow(pills: [
            (label: "Avg", value: "\(Int(avg))", color: nil),
            (label: "Best", value: "\(Int(best))", color: .green),
            (label: "Worst", value: "\(Int(worst))", color: .red),
        ])
    }

    // MARK: - Factor Decomposition

    private var factorDecompItems: [(label: String, exercise: Double, sleep: Double, diet: Double, screenTime: Double)] {
        let scored = data.context.days.compactMap { d -> (date: Date, stress: Double, exercise: Double, sleep: Double, diet: Double, screen: Double)? in
            guard let stress = d.stressScore else { return nil }
            let ex = StressScoring.exerciseScore(steps: d.steps.map(Double.init), energy: d.activeCalories.map(Double.init))
            let sl = StressScoring.sleepScore(summary: d.sleepHours.map { h in
                DailySleepSummary(date: d.date, totalHours: h, coreHours: 0, remHours: 0, deepHours: d.deepSleepHours ?? 0)
            })
            let dt = StressScoring.dietScore(protein: d.totalProteinG ?? 0, fiber: d.totalFiberG ?? 0, fat: d.totalFatG ?? 0, carbs: d.totalCarbsG ?? 0, hasLogs: d.totalCalories != nil)
            let sc = StressScoring.screenTimeScore(hours: nil)
            return (date: d.date, stress: stress, exercise: ex, sleep: sl, diet: dt, screen: sc)
        }

        guard scored.count >= 4 else { return [] }
        let sorted = scored.sorted { $0.stress < $1.stress }
        let bestDays = sorted.prefix(3)
        let worstDays = sorted.suffix(3)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        return bestDays.map { d in
            (label: "Low \(formatter.string(from: d.date))", exercise: d.exercise, sleep: d.sleep, diet: d.diet, screenTime: d.screen)
        } + worstDays.map { d in
            (label: "High \(formatter.string(from: d.date))", exercise: d.exercise, sleep: d.sleep, diet: d.diet, screenTime: d.screen)
        }
    }

    @ViewBuilder
    private var factorDecomposition: some View {
        let items = factorDecompItems
        if !items.isEmpty {
            Text("Factor Breakdown: Best vs Worst Days")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)
            FactorDecompositionChart(items: items)
        }
    }

    // MARK: - Best vs Worst

    @ViewBuilder
    private var bestWorstComparison: some View {
        let withStress = data.context.days.filter { $0.stressScore != nil }
        if let best = withStress.min(by: { ($0.stressScore ?? 100) < ($1.stressScore ?? 100) }),
           let worst = withStress.max(by: { ($0.stressScore ?? 0) < ($1.stressScore ?? 0) }) {
            HStack(spacing: 10) {
                dayCard(title: "Best Day", day: best, color: .green)
                dayCard(title: "Worst Day", day: worst, color: .red)
            }
        }
    }

    private func dayCard(title: String, day: WellnessDaySummary, color: Color) -> some View {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(f.string(from: day.date))
                .font(.r(.caption, .regular))
                .foregroundStyle(.secondary)
            metricLine("Stress", value: "\(Int(day.stressScore ?? 0))")
            metricLine("Sleep", value: day.sleepHours.map { String(format: "%.1fh", $0) } ?? "—")
            metricLine("Steps", value: day.steps.map { "\($0)" } ?? "—")
            metricLine("Mood", value: day.moodLabel ?? "—")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.06)))
    }

    private func metricLine(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
    }

    // MARK: - Interventions

    @ViewBuilder
    private var interventionSection: some View {
        if !data.context.interventionResults.isEmpty {
            Text("Intervention Effectiveness")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)

            ForEach(data.context.interventionResults) { result in
                let typeName = ResetType(rawValue: result.resetType)?.title ?? result.resetType
                if result.hasMeasurableData {
                    ComparisonBarChart(bars: [
                        (label: "Pre", value: result.avgPreStress, domain: .stress),
                        (label: "Post", value: result.avgPostStress, domain: .stress),
                    ], highlight: 1)
                    Text("\(typeName): \(result.sessionCount) sessions, avg \(String(format: "%.0f", result.avgDelta)) pts change")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(typeName): \(result.sessionCount) sessions — insufficient stress readings to measure effectiveness")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Experiments

    @ViewBuilder
    private var experimentSection: some View {
        if !data.context.experimentSummaries.isEmpty {
            ForEach(data.context.experimentSummaries) { exp in
                VStack(alignment: .leading, spacing: 6) {
                    Text(exp.name)
                        .font(.r(.footnote, .semibold))
                    if let h = exp.hypothesis {
                        Text(h).font(.r(.caption, .regular)).foregroundStyle(.secondary)
                    }
                    if let baseline = exp.baselineAvg, let experiment = exp.experimentAvg {
                        ComparisonBarChart(bars: [
                            (label: "Baseline", value: baseline, domain: .stress),
                            (label: "Experiment", value: experiment, domain: .stress),
                        ], highlight: experiment < baseline ? 1 : 0)
                    }
                }
            }
        }
    }
}
