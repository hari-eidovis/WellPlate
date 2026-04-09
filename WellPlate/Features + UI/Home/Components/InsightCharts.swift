import SwiftUI
import Charts

// MARK: - TrendAreaChart

struct TrendAreaChart: View {
    let points: [(date: Date, value: Double)]
    let goalLine: Double?
    let metricLabel: String
    let unit: String
    let accentColor: Color

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var chartPoints: [ChartPoint] {
        points.map { ChartPoint(date: $0.date, value: $0.value) }
    }

    var body: some View {
        Chart {
            ForEach(chartPoints) { p in
                AreaMark(
                    x: .value("Day", p.date, unit: .day),
                    y: .value(metricLabel, p.value)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [accentColor.opacity(0.25), accentColor.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", p.date, unit: .day),
                    y: .value(metricLabel, p.value)
                )
                .foregroundStyle(accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.catmullRom)
            }

            if let goal = goalLine {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true)
                    .font(.system(size: 9, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.system(size: 9, design: .rounded))
            }
        }
        .frame(height: 130)
    }
}

// MARK: - CorrelationScatterChart

struct CorrelationScatterChart: View {
    let points: [(x: Double, y: Double)]
    let r: Double
    let xLabel: String
    let yLabel: String

    private struct ScatterPoint: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
    }

    private var scatterPoints: [ScatterPoint] {
        points.map { ScatterPoint(x: $0.x, y: $0.y) }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Chart {
                ForEach(scatterPoints) { p in
                    PointMark(
                        x: .value(xLabel, p.x),
                        y: .value(yLabel, p.y)
                    )
                    .foregroundStyle(AppColors.brand.opacity(0.7))
                    .symbolSize(40)
                }

                // Trend line (simple linear regression)
                if let (slope, intercept) = linearRegression() {
                    let minX = points.map(\.x).min() ?? 0
                    let maxX = points.map(\.x).max() ?? 1
                    LineMark(
                        x: .value(xLabel, minX),
                        y: .value(yLabel, slope * minX + intercept)
                    )
                    .foregroundStyle(AppColors.brand.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                    LineMark(
                        x: .value(xLabel, maxX),
                        y: .value(yLabel, slope * maxX + intercept)
                    )
                    .foregroundStyle(AppColors.brand.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 150)

            // r-value badge
            Text(String(format: "r = %.2f", r))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(r < 0 ? AppColors.success : AppColors.error)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(.secondarySystemBackground))
                )
                .padding(8)
        }
    }

    private func linearRegression() -> (slope: Double, intercept: Double)? {
        guard points.count >= 2 else { return nil }
        let n = Double(points.count)
        let sumX = points.map(\.x).reduce(0, +)
        let sumY = points.map(\.y).reduce(0, +)
        let sumXY = points.map { $0.x * $0.y }.reduce(0, +)
        let sumX2 = points.map { $0.x * $0.x }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept)
    }
}

// MARK: - ComparisonBarChart

struct ComparisonBarChart: View {
    let bars: [(label: String, value: Double, domain: WellnessDomain)]
    let highlight: Int?

    private struct BarItem: Identifiable {
        let id: Int
        let label: String
        let value: Double
        let color: Color
        let isHighlighted: Bool
    }

    private var items: [BarItem] {
        bars.enumerated().map { idx, bar in
            BarItem(id: idx, label: bar.label, value: bar.value, color: bar.domain.accentColor, isHighlighted: idx == highlight)
        }
    }

    var body: some View {
        Chart(items) { item in
            BarMark(
                x: .value("Value", item.value),
                y: .value("Label", item.label)
            )
            .foregroundStyle(item.isHighlighted ? item.color : item.color.opacity(0.4))
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.system(size: 9, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 11, design: .rounded))
            }
        }
        .frame(height: 80)
    }
}

// MARK: - MacroGroupedBarChart

struct MacroGroupedBarChart: View {
    let actual: [String: Double]
    let goals: [String: Double]

    private struct MacroBar: Identifiable {
        let id = UUID()
        let name: String
        let category: String  // "Actual" or "Goal"
        let value: Double
    }

    private var bars: [MacroBar] {
        let keys = ["Protein", "Carbs", "Fat", "Fiber"]
        var result: [MacroBar] = []
        for key in keys {
            if let a = actual[key] { result.append(MacroBar(name: key, category: "Actual", value: a)) }
            if let g = goals[key] { result.append(MacroBar(name: key, category: "Goal", value: g)) }
        }
        return result
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Macro", bar.name),
                y: .value("Grams", bar.value)
            )
            .foregroundStyle(by: .value("Type", bar.category))
            .cornerRadius(4)
            .position(by: .value("Type", bar.category))
        }
        .chartForegroundStyleScale([
            "Actual": AppColors.brand,
            "Goal": Color.secondary.opacity(0.3)
        ])
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 10, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.system(size: 9, design: .rounded))
            }
        }
        .chartLegend(.hidden)
        .frame(height: 130)
    }
}

// MARK: - MilestoneRingView

struct MilestoneRingView: View {
    let current: Int
    let target: Int
    let streakLabel: String

    @State private var appeared = false

    private var progress: CGFloat {
        guard target > 0 else { return 0 }
        return min(1.0, CGFloat(current) / CGFloat(target))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.brand.opacity(0.15), lineWidth: 8)

            Circle()
                .trim(from: 0, to: appeared ? progress : 0)
                .stroke(AppColors.brand, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: appeared)

            VStack(spacing: 2) {
                Text("\(current)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("days")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 80)
        .onAppear { appeared = true }
    }
}

// MARK: - SparklineView

struct SparklineView: View {
    let points: [Double]
    let accentColor: Color

    private struct SparkPoint: Identifiable {
        let id: Int
        let value: Double
    }

    private var sparkPoints: [SparkPoint] {
        points.enumerated().map { SparkPoint(id: $0.offset, value: $0.element) }
    }

    var body: some View {
        Chart(sparkPoints) { p in
            LineMark(
                x: .value("Index", p.id),
                y: .value("Value", p.value)
            )
            .foregroundStyle(accentColor)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(width: 60, height: 24)
    }
}

// MARK: - Previews

#Preview("TrendAreaChart") {
    TrendAreaChart(
        points: (0..<7).map { i in
            (date: Calendar.current.date(byAdding: .day, value: -6 + i, to: Date())!, value: [54, 58, 66, 60, 55, 50, 48][i])
        },
        goalLine: 50,
        metricLabel: "Stress",
        unit: "/100",
        accentColor: AppColors.brand
    )
    .padding()
}

#Preview("CorrelationScatter") {
    CorrelationScatterChart(
        points: [(5.5, 72), (6.0, 68), (6.5, 61), (7.0, 55), (7.5, 48), (8.0, 42)],
        r: -0.62,
        xLabel: "Sleep (h)",
        yLabel: "Stress"
    )
    .padding()
}

#Preview("ComparisonBars") {
    ComparisonBarChart(
        bars: [("Earlier", 19.5, .sleep), ("Recent", 23.0, .sleep)],
        highlight: 1
    )
    .padding()
}

#Preview("MacroGroupedBar") {
    MacroGroupedBarChart(
        actual: ["Protein": 65, "Carbs": 210, "Fat": 62, "Fiber": 24],
        goals: ["Protein": 90, "Carbs": 220, "Fat": 65, "Fiber": 30]
    )
    .padding()
}

#Preview("MilestoneRing") {
    MilestoneRingView(current: 5, target: 7, streakLabel: "Water Goal")
}

#Preview("Sparkline") {
    SparklineView(points: [6, 7, 8, 8, 7, 8, 8], accentColor: .blue)
}
