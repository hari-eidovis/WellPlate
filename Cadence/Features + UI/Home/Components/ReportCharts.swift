import SwiftUI
import Charts

// MARK: - StatPillRow

struct StatPillRow: View {
    let pills: [(label: String, value: String, color: Color?)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                HStack(spacing: 4) {
                    Text(pill.label)
                        .foregroundStyle(.secondary)
                    Text(pill.value)
                        .foregroundStyle(pill.color ?? .primary)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
            }
        }
    }
}

// MARK: - StressVolatilityChart

struct StressVolatilityChart: View {
    let points: [(date: Date, min: Double, max: Double, avg: Double)]

    private struct Item: Identifiable {
        let id = UUID()
        let date: Date; let min: Double; let max: Double; let avg: Double
    }

    private var items: [Item] {
        points.map { Item(date: $0.date, min: $0.min, max: $0.max, avg: $0.avg) }
    }

    var body: some View {
        Chart(items) { item in
            RuleMark(
                x: .value("Day", item.date, unit: .day),
                yStart: .value("Min", item.min),
                yEnd: .value("Max", item.max)
            )
            .foregroundStyle(Color.secondary.opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round))

            PointMark(
                x: .value("Day", item.date, unit: .day),
                y: .value("Avg", item.avg)
            )
            .foregroundStyle(WellnessDomain.stress.accentColor)
            .symbolSize(30)
        }
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
        .frame(height: 130)
    }
}

// MARK: - FactorDecompositionChart

struct FactorDecompositionChart: View {
    let items: [(label: String, exercise: Double, sleep: Double, diet: Double, screenTime: Double)]

    private struct BarSegment: Identifiable {
        let id = UUID()
        let label: String; let factor: String; let value: Double
    }

    private var segments: [BarSegment] {
        items.flatMap { item in
            [
                BarSegment(label: item.label, factor: "Exercise", value: item.exercise),
                BarSegment(label: item.label, factor: "Sleep", value: item.sleep),
                BarSegment(label: item.label, factor: "Diet", value: item.diet),
                BarSegment(label: item.label, factor: "Screen", value: item.screenTime),
            ]
        }
    }

    var body: some View {
        Chart(segments) { seg in
            BarMark(
                x: .value("Score", seg.value),
                y: .value("Day", seg.label)
            )
            .foregroundStyle(by: .value("Factor", seg.factor))
        }
        .chartForegroundStyleScale([
            "Exercise": Color.green,
            "Sleep": Color.indigo,
            "Diet": Color.orange,
            "Screen": Color.purple,
        ])
        .chartLegend(position: .bottom, spacing: 8)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 10, design: .rounded)) }
        }
        .frame(height: CGFloat(items.count) * 36 + 40)
    }
}

// MARK: - MealTimingHeatmap

struct MealTimingHeatmap: View {
    let cells: [(dayLabel: String, bucket: String, count: Int)]

    private struct Cell: Identifiable {
        let id = UUID()
        let dayLabel: String; let bucket: String; let count: Int
    }

    private var cellItems: [Cell] {
        cells.map { Cell(dayLabel: $0.dayLabel, bucket: $0.bucket, count: $0.count) }
    }

    private let maxCount: Int = 3

    var body: some View {
        Chart(cellItems) { cell in
            RectangleMark(
                x: .value("Day", cell.dayLabel),
                y: .value("Time", cell.bucket)
            )
            .foregroundStyle(
                AppColors.brand.opacity(cell.count == 0 ? 0.05 : min(1.0, Double(cell.count) / Double(maxCount)))
            )
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 8, design: .rounded)) }
        }
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 9, design: .rounded)) }
        }
        .frame(height: 130)
    }
}

// MARK: - BedtimeScatterChart

struct BedtimeScatterChart: View {
    let points: [(date: Date, bedtime: Date?, wakeTime: Date?)]

    private struct TimePoint: Identifiable {
        let id = UUID()
        let date: Date; let hour: Double; let series: String
    }

    private var timePoints: [TimePoint] {
        var result: [TimePoint] = []
        for pt in points {
            if let bed = pt.bedtime {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: bed)
                var h = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
                if h < 12 { h += 24 }
                result.append(TimePoint(date: pt.date, hour: h, series: "Bedtime"))
            }
            if let wake = pt.wakeTime {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: wake)
                let h = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
                result.append(TimePoint(date: pt.date, hour: h, series: "Wake"))
            }
        }
        return result
    }

    var body: some View {
        Chart(timePoints) { pt in
            PointMark(
                x: .value("Day", pt.date, unit: .day),
                y: .value("Time", pt.hour)
            )
            .foregroundStyle(by: .value("Series", pt.series))
            .symbolSize(30)
        }
        .chartForegroundStyleScale(["Bedtime": Color.indigo, "Wake": Color.orange])
        .chartLegend(position: .bottom, spacing: 8)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        let displayH = h >= 24 ? Int(h - 24) : Int(h)
                        let suffix = h >= 24 || h < 12 ? "AM" : "PM"
                        Text("\(displayH)\(suffix)").font(.system(size: 9, design: .rounded))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true).font(.system(size: 9, design: .rounded))
            }
        }
        .frame(height: 150)
    }
}

// MARK: - VitalTrendChart

struct VitalTrendChart: View {
    let points: [DailyMetricSample]
    let metric: VitalMetric

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date; let value: Double
    }

    private var chartPoints: [ChartPoint] {
        points.map { ChartPoint(date: $0.date, value: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                    .foregroundStyle(metric.accentColor)
                    .font(.system(size: 14, weight: .semibold))
                Text(metric.rawValue)
                    .font(.r(.subheadline, .semibold))
                Spacer()
                if let avg = averageValue {
                    Text("\(String(format: "%.0f", avg)) \(metric.unit)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(metric.statusColor(for: avg))
                }
            }

            Chart(chartPoints) { pt in
                LineMark(x: .value("Day", pt.date, unit: .day), y: .value(metric.rawValue, pt.value))
                    .foregroundStyle(metric.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                AreaMark(x: .value("Day", pt.date, unit: .day), y: .value(metric.rawValue, pt.value))
                    .foregroundStyle(.linearGradient(colors: [metric.accentColor.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true).font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 100)

            Text(metric.normalRange)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private var averageValue: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }
}

// MARK: - SymptomTimelineChart

struct SymptomTimelineChart: View {
    let points: [(date: Date, maxSeverity: Int, count: Int, stressScore: Double?)]

    private struct BubblePoint: Identifiable {
        let id = UUID()
        let date: Date; let severity: Int; let count: Int; let stress: Double?
    }

    private var bubbles: [BubblePoint] {
        points.map { BubblePoint(date: $0.date, severity: $0.maxSeverity, count: $0.count, stress: $0.stressScore) }
    }

    var body: some View {
        Chart {
            ForEach(bubbles) { pt in
                PointMark(
                    x: .value("Day", pt.date, unit: .day),
                    y: .value("Severity", pt.severity)
                )
                .foregroundStyle(severityColor(pt.severity))
                .symbolSize(CGFloat(pt.count) * 40)
            }
        }
        .chartYScale(domain: 0...10)
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
        .frame(height: 130)
    }

    private func severityColor(_ severity: Int) -> Color {
        switch severity {
        case ..<4: return .green
        case 4...6: return .yellow
        default: return .red
        }
    }
}

// MARK: - CorrelationMatrixChart

struct CorrelationMatrixChart: View {
    let metrics: [String]
    let correlations: [(xIdx: Int, yIdx: Int, r: Double, isSignificant: Bool)]

    private struct Cell: Identifiable {
        let id: String
        let xLabel: String; let yLabel: String; let r: Double; let isSignificant: Bool
    }

    private var cells: [Cell] {
        correlations.map { c in
            Cell(
                id: "\(c.xIdx)-\(c.yIdx)",
                xLabel: metrics[c.xIdx],
                yLabel: metrics[c.yIdx],
                r: c.r,
                isSignificant: c.isSignificant
            )
        }
    }

    var body: some View {
        Chart(cells) { cell in
            RectangleMark(
                x: .value("X", cell.xLabel),
                y: .value("Y", cell.yLabel)
            )
            .foregroundStyle(cellColor(r: cell.r, significant: cell.isSignificant))
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 8, design: .rounded)) }
        }
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 8, design: .rounded)) }
        }
        .frame(height: CGFloat(metrics.count) * 28 + 30)
    }

    private func cellColor(r: Double, significant: Bool) -> Color {
        guard significant else { return Color(.systemGray5) }
        if r > 0 {
            return Color.red.opacity(min(1, abs(r)))
        } else {
            return Color.blue.opacity(min(1, abs(r)))
        }
    }
}

// MARK: - AdherenceGauge

struct AdherenceGauge: View {
    let rate: Double
    let label: String

    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(WellnessDomain.supplements.accentColor.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: appeared ? CGFloat(min(1, rate)) : 0)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: appeared)

            VStack(spacing: 2) {
                Text("\(Int(rate * 100))%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 80)
        .onAppear { appeared = true }
    }

    private var gaugeColor: Color {
        if rate >= 0.8 { return .green }
        if rate >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - FoodSensitivityRow

struct FoodSensitivityRow: View {
    let link: FoodSymptomLink

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.foodName)
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                Text("appeared \(link.symptomDayAppearances)/\(link.symptomDayCount) symptom days vs \(link.clearDayAppearances)/\(link.clearDayCount) clear days")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1fx", link.ratio))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(link.classification == .potentialTrigger ? Color.red : Color.green)
                )
        }
    }
}

// MARK: - SymptomCategoryDonut

struct SymptomCategoryDonut: View {
    let slices: [(category: SymptomCategory, count: Int)]

    private struct Slice: Identifiable {
        let id: String
        let category: SymptomCategory; let count: Int
    }

    private var sliceItems: [Slice] {
        slices.map { Slice(id: $0.category.rawValue, category: $0.category, count: $0.count) }
    }

    var body: some View {
        Chart(sliceItems) { slice in
            SectorMark(
                angle: .value("Count", slice.count),
                innerRadius: .ratio(0.5),
                angularInset: 1.5
            )
            .foregroundStyle(slice.category.color)
            .cornerRadius(4)
        }
        .chartLegend(position: .bottom, spacing: 8)
        .frame(height: 160)
    }
}
