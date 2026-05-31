import SwiftUI
import Charts

struct ActivitySection: View {
    let data: ReportData

    private var goals: UserGoalsSnapshot { data.context.goals }
    private var narrative: SectionNarrative? { data.narratives.sectionNarratives["activity"] }

    var body: some View {
        ReportSectionCard(title: narrative?.headline ?? "Activity", domain: .activity) {
            if let n = narrative {
                Text(n.narrative).font(.r(.subheadline, .regular)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            stepsTrend
            activeEnergyTrend
            exerciseMinutesTrend
            movementStressLink
        }
    }

    @ViewBuilder
    private var stepsTrend: some View {
        let stepDays = data.context.days.compactMap { d -> (date: Date, value: Double)? in
            guard let s = d.steps else { return nil }
            return (date: d.date, value: Double(s))
        }
        if !stepDays.isEmpty {
            Text("Steps").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            TrendAreaChart(points: stepDays, goalLine: Double(goals.dailyStepsGoal), metricLabel: "Steps", unit: "", accentColor: .green)

            let avg = stepDays.map(\.value).reduce(0, +) / Double(stepDays.count)
            let metGoal = stepDays.filter { $0.value >= Double(goals.dailyStepsGoal) }.count
            StatPillRow(pills: [
                (label: "Avg", value: "\(Int(avg))", color: nil),
                (label: "Goal met", value: "\(metGoal)d", color: .green),
                (label: "Total", value: "\(Int(stepDays.map(\.value).reduce(0, +)))", color: nil),
            ])
        }
    }

    @ViewBuilder
    private var activeEnergyTrend: some View {
        let energyDays = data.context.days.compactMap { d -> (date: Date, value: Double)? in
            guard let e = d.activeCalories else { return nil }
            return (date: d.date, value: Double(e))
        }
        if !energyDays.isEmpty {
            Text("Active Energy").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            TrendAreaChart(points: energyDays, goalLine: Double(goals.activeEnergyGoalKcal), metricLabel: "kcal", unit: "kcal", accentColor: AppColors.brand)
        }
    }

    @ViewBuilder
    private var exerciseMinutesTrend: some View {
        let exerciseDays = data.context.days.compactMap { d -> (date: Date, value: Double)? in
            guard let e = d.exerciseMinutes else { return nil }
            return (date: d.date, value: Double(e))
        }
        if !exerciseDays.isEmpty {
            Text("Exercise Minutes").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            TrendAreaChart(points: exerciseDays, goalLine: nil, metricLabel: "Minutes", unit: "min", accentColor: .green)
        }
    }

    private var stepsStressPaired: (scatter: [(x: Double, y: Double)], r: Double) {
        var scatter: [(x: Double, y: Double)] = []
        for day in data.context.days {
            guard let steps = day.steps, let stress = day.stressScore else { continue }
            scatter.append((x: Double(steps), y: stress))
        }
        let r = scatter.count >= 5 ? CorrelationMath.spearmanR(scatter.map(\.x), scatter.map(\.y)) : 0
        return (scatter, r)
    }

    @ViewBuilder
    private var movementStressLink: some View {
        let paired = stepsStressPaired
        if paired.scatter.count >= 5 && abs(paired.r) >= 0.25 {
            Text("Steps vs Stress").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            CorrelationScatterChart(points: paired.scatter, r: paired.r, xLabel: "Steps", yLabel: "Stress")
        }
    }
}
