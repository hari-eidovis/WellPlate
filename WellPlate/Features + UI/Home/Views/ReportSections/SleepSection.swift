import SwiftUI
import Charts

private struct SleepBar: Identifiable {
    let id = UUID()
    let date: Date; let stage: String; let hours: Double
}

struct SleepSection: View {
    let data: ReportData

    private var goals: UserGoalsSnapshot { data.context.goals }
    private var narrative: SectionNarrative? { data.narratives.sectionNarratives["sleep"] }

    var body: some View {
        ReportSectionCard(title: narrative?.headline ?? "Sleep", domain: .sleep) {
            if let n = narrative {
                Text(n.narrative).font(.r(.subheadline, .regular)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            sleepDurationChart
            deepSleepRatio
            bedtimeConsistency
            sleepStressLink
        }
    }

    // MARK: - Duration Stacked Bars

    private var sleepBars: [SleepBar] {
        data.context.days.filter { $0.sleepHours != nil }.flatMap { d in
            [
                SleepBar(date: d.date, stage: "Deep", hours: d.deepSleepHours ?? 0),
                SleepBar(date: d.date, stage: "REM", hours: d.remSleepHours ?? 0),
                SleepBar(date: d.date, stage: "Core", hours: max(0, (d.sleepHours ?? 0) - (d.deepSleepHours ?? 0) - (d.remSleepHours ?? 0))),
            ]
        }
    }

    @ViewBuilder
    private var sleepDurationChart: some View {
        let bars = sleepBars
        if !bars.isEmpty {
            Text("Sleep Duration by Stage")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)

            Chart(bars) { bar in
                BarMark(
                    x: .value("Day", bar.date, unit: .day),
                    y: .value("Hours", bar.hours)
                )
                .foregroundStyle(by: .value("Stage", bar.stage))
            }
            .chartForegroundStyleScale([
                "Deep": SleepStage.deep.color,
                "REM": SleepStage.rem.color,
                "Core": SleepStage.core.color,
            ])
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true).font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 140)

            let sleepValues = data.context.days.compactMap(\.sleepHours)
            let avg = sleepValues.reduce(0, +) / max(1, Double(sleepValues.count))
            let metGoal = sleepValues.filter { $0 >= goals.sleepGoalHours }.count
            StatPillRow(pills: [
                (label: "Avg", value: String(format: "%.1fh", avg), color: nil),
                (label: "Goal met", value: "\(metGoal) nights", color: .green),
            ])
        }
    }

    // MARK: - Deep Sleep Ratio

    @ViewBuilder
    private var deepSleepRatio: some View {
        let ratioPoints = data.context.days.compactMap { d -> (date: Date, value: Double)? in
            guard let total = d.sleepHours, total > 0, let deep = d.deepSleepHours else { return nil }
            return (date: d.date, value: (deep / total) * 100)
        }
        if ratioPoints.count >= 3 {
            Text("Deep Sleep %")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)
            TrendAreaChart(points: ratioPoints, goalLine: 17.5, metricLabel: "Deep %", unit: "%", accentColor: SleepStage.deep.color)
        }
    }

    // MARK: - Bedtime Consistency

    @ViewBuilder
    private var bedtimeConsistency: some View {
        let bedtimePoints = data.context.days.compactMap { d -> (date: Date, bedtime: Date?, wakeTime: Date?)? in
            guard d.bedtime != nil || d.wakeTime != nil else { return nil }
            return (date: d.date, bedtime: d.bedtime, wakeTime: d.wakeTime)
        }
        if bedtimePoints.count >= 3 {
            Text("Bedtime & Wake Consistency")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)
            BedtimeScatterChart(points: bedtimePoints)
        }
    }

    // MARK: - Sleep-Stress Link

    private var sleepStressPaired: (scatter: [(x: Double, y: Double)], r: Double) {
        var scatter: [(x: Double, y: Double)] = []
        let days = data.context.days
        for i in 0..<(days.count - 1) {
            guard let sleep = days[i].sleepHours, let stress = days[i + 1].stressScore else { continue }
            scatter.append((x: sleep, y: stress))
        }
        let r = scatter.count >= 5 ? CorrelationMath.spearmanR(scatter.map(\.x), scatter.map(\.y)) : 0
        return (scatter, r)
    }

    @ViewBuilder
    private var sleepStressLink: some View {
        let paired = sleepStressPaired
        if paired.scatter.count >= 5 && abs(paired.r) >= 0.25 {
            Text("Sleep → Next-Day Stress")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)
            CorrelationScatterChart(points: paired.scatter, r: paired.r, xLabel: "Sleep (h)", yLabel: "Next-day Stress")
        }
    }
}
