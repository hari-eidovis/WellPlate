import SwiftUI
import Charts

struct HydrationCaffeineSection: View {
    let data: ReportData

    private var goals: UserGoalsSnapshot { data.context.goals }

    var body: some View {
        ReportSectionCard(title: "Hydration & Caffeine", domain: .hydration) {
            waterTrend
            coffeeTrend
            caffeineStressLink
        }
    }

    @ViewBuilder
    private var waterTrend: some View {
        let waterDays = data.context.days.compactMap { d -> (date: Date, value: Double)? in
            guard let w = d.waterGlasses, w > 0 else { return nil }
            return (date: d.date, value: Double(w))
        }
        if !waterDays.isEmpty {
            Text("Water Intake").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            TrendAreaChart(points: waterDays, goalLine: Double(goals.waterDailyCups), metricLabel: "Cups", unit: "cups", accentColor: WellnessDomain.hydration.accentColor)

            let avg = waterDays.map(\.value).reduce(0, +) / Double(waterDays.count)
            let metGoal = waterDays.filter { $0.value >= Double(goals.waterDailyCups) }.count
            StatPillRow(pills: [
                (label: "Avg", value: String(format: "%.1f", avg), color: nil),
                (label: "Goal met", value: "\(metGoal)d", color: .green),
            ])
        }
    }

    @ViewBuilder
    private var coffeeTrend: some View {
        let coffeeDays = data.context.days.compactMap { d -> (date: Date, value: Double)? in
            guard let c = d.coffeeCups, c > 0 else { return nil }
            return (date: d.date, value: Double(c))
        }
        if !coffeeDays.isEmpty {
            Text("Coffee Intake").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            TrendAreaChart(points: coffeeDays, goalLine: Double(goals.coffeeDailyCups), metricLabel: "Cups", unit: "cups", accentColor: WellnessDomain.caffeine.accentColor)
        }
    }

    @ViewBuilder
    private var caffeineStressLink: some View {
        let lowCoffeeDays = data.context.days.filter { ($0.coffeeCups ?? 0) <= 2 && $0.stressScore != nil }
        let highCoffeeDays = data.context.days.filter { ($0.coffeeCups ?? 0) >= 3 && $0.stressScore != nil }

        if lowCoffeeDays.count >= 3 && highCoffeeDays.count >= 3 {
            let lowAvg = lowCoffeeDays.compactMap(\.stressScore).reduce(0, +) / Double(lowCoffeeDays.count)
            let highAvg = highCoffeeDays.compactMap(\.stressScore).reduce(0, +) / Double(highCoffeeDays.count)

            Text("Caffeine & Stress").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            ComparisonBarChart(bars: [
                (label: "0-2 cups", value: lowAvg, domain: .caffeine),
                (label: "3+ cups", value: highAvg, domain: .caffeine),
            ], highlight: lowAvg < highAvg ? 0 : 1)
        }
    }
}
