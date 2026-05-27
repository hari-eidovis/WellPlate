//
//  StressWeekChartView.swift
//  Cadence
//
//  7-day stress trend — per-day RuleMark range (min→max) with an average
//  PointMark on top. Visual language matches the meal-insights charts
//  (e.g. StressVolatilityChart).
//

import SwiftUI
import Charts

// MARK: - Daily Aggregate

private struct DayAggregate: Identifiable, Hashable {
    let id = UUID()
    let day: Date
    let avgScore: Double
    let minScore: Double
    let maxScore: Double
    let dominantLevel: StressLevel?
    let readingCount: Int
    let isToday: Bool

    var hasData: Bool { readingCount > 0 }
    var spread: Double { max(0, maxScore - minScore) }
}

// MARK: - StressWeekChartView

struct StressWeekChartView: View {

    let readings: [StressReading]

    @State private var selectedDay: Date?

    // MARK: - Computed Data

    private var aggregates: [DayAggregate] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let groups = Dictionary(grouping: readings) { cal.startOfDay(for: $0.timestamp) }
        return (0..<7).compactMap { offset -> DayAggregate? in
            guard let day = cal.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            let dayReadings = groups[day] ?? []
            let scores = dayReadings.map(\.score)
            let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
            let dominant: StressLevel? = {
                guard !dayReadings.isEmpty else { return nil }
                let counts = Dictionary(grouping: dayReadings) { StressLevel(score: $0.score) }
                    .mapValues(\.count)
                return counts.max(by: { $0.value < $1.value })?.key
            }()
            return DayAggregate(
                day: day,
                avgScore: avg,
                minScore: scores.min() ?? 0,
                maxScore: scores.max() ?? 0,
                dominantLevel: dominant,
                readingCount: dayReadings.count,
                isToday: cal.isDateInToday(day)
            )
        }
    }

    private var weekAvg: Double {
        let active = aggregates.filter(\.hasData).map(\.avgScore)
        guard !active.isEmpty else { return 0 }
        return active.reduce(0, +) / Double(active.count)
    }

    private var weekMin: Double? {
        aggregates.filter(\.hasData).map(\.minScore).min()
    }

    private var weekMax: Double? {
        aggregates.filter(\.hasData).map(\.maxScore).max()
    }

    private var trackedDayCount: Int {
        aggregates.filter(\.hasData).count
    }

    private var selectedAggregate: DayAggregate? {
        guard let selectedDay else { return nil }
        return aggregates.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            chart
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .appShadow(radius: 15, y: 5)
    }

    // MARK: - Header

    private var header: some View {
        Group {
            if let sel = selectedAggregate, sel.hasData {
                selectionHeader(sel)
            } else {
                summaryHeader
            }
        }
        .animation(.easeOut(duration: 0.18), value: selectedDay)
    }

    private var summaryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(weekRangeLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weekAvg > 0 ? "\(Int(weekAvg))" : "—")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("avg")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let lo = weekMin, let hi = weekMax {
                    Text("RANGE")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                        .tracking(0.6)
                    Text("\(Int(lo))–\(Int(hi))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                }
                Text("\(trackedDayCount)/7 tracked")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.75))
            }
        }
    }

    private func selectionHeader(_ sel: DayAggregate) -> some View {
        let level = sel.dominantLevel ?? StressLevel(score: sel.avgScore)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 6, height: 6)
                    Text(sel.isToday ? "TODAY · \(longDayLabel(sel.day))" : longDayLabel(sel.day).uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Int(sel.avgScore))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(level.color)
                    Text(level.label.lowercased())
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if sel.spread > 0 {
                    Text("\(Int(sel.minScore))–\(Int(sel.maxScore))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                }
                Text("\(sel.readingCount) reading\(sel.readingCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.75))
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // ── Today's column highlight (behind everything) ──
            if let today = aggregates.first(where: \.isToday) {
                RectangleMark(
                    x: .value("Day", today.day, unit: .day),
                    width: .ratio(0.55)
                )
                .foregroundStyle(Self.chartBlue.opacity(0.07))
                .cornerRadius(10)
            }

            // ── Week-average baseline ──
            if weekAvg > 0 {
                RuleMark(y: .value("Week Avg", weekAvg))
                    .foregroundStyle(Color.secondary.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .leading, alignment: .trailing, spacing: 4) {
                        if selectedDay == nil {
                            Text("avg")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.secondary.opacity(0.55))
                        }
                    }
            }

            // ── Smooth trend line through daily averages ──
            ForEach(aggregates.filter(\.hasData)) { item in
                LineMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Avg", item.avgScore),
                    series: .value("Trend", "avg")
                )
                .foregroundStyle(Self.chartBlue.opacity(0.30))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }

            // ── Per-day marks (range stick + avg dot) ──
            ForEach(aggregates) { item in
                if item.hasData {
                    rangeStick(for: item)
                    avgPoint(for: item)
                } else {
                    emptyDayMark(for: item)
                }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [25, 50, 75]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                    .foregroundStyle(Color.secondary.opacity(0.10))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.secondary.opacity(0.45))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: aggregates.map(\.day)) { value in
                if let d = value.as(Date.self),
                   let agg = aggregates.first(where: { Calendar.current.isDate($0.day, inSameDayAs: d) }) {
                    AxisValueLabel(centered: true) {
                        VStack(spacing: 2) {
                            Text(singleLetterDay(d))
                                .font(.system(size: 11, weight: agg.isToday ? .bold : .medium, design: .rounded))
                                .foregroundStyle(agg.isToday ? Self.chartBlue : Color.secondary.opacity(0.75))
                            Text(dayNumber(d))
                                .font(.system(size: 9, weight: agg.isToday ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(agg.isToday ? Self.chartBlue.opacity(0.85) : Color.secondary.opacity(0.5))
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 170)
        .animation(.easeInOut(duration: 0.3), value: readings.count)
    }

    // ── Range stick (min → max for the day) — rounded RuleMark ──
    @ChartContentBuilder
    private func rangeStick(for item: DayAggregate) -> some ChartContent {
        // Floor the visible height so single-reading days still register a tick.
        let topY = max(item.maxScore, item.minScore + 1.5)
        RuleMark(
            x: .value("Day", item.day, unit: .day),
            yStart: .value("Min", item.minScore),
            yEnd: .value("Max", topY)
        )
        .foregroundStyle(stickColor(for: item))
        .lineStyle(StrokeStyle(lineWidth: isSelected(item) ? 7 : 6, lineCap: .round))
        .opacity(opacity(for: item))
    }

    // ── Average dot on top of the range stick — halo'd for separation from the stick ──
    @ChartContentBuilder
    private func avgPoint(for item: DayAggregate) -> some ChartContent {
        let selected = isSelected(item)
        let size: CGFloat = selected ? 13 : 10
        PointMark(
            x: .value("Day", item.day, unit: .day),
            y: .value("Avg", item.avgScore)
        )
        .symbol {
            Circle()
                .fill(dotColor(for: item))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                )
                .shadow(
                    color: dotColor(for: item).opacity(selected ? 0.35 : 0),
                    radius: selected ? 5 : 0
                )
        }
        .opacity(opacity(for: item))
    }

    // ── Empty-day placeholder so the X axis and scale still anchor it ──
    @ChartContentBuilder
    private func emptyDayMark(for item: DayAggregate) -> some ChartContent {
        PointMark(
            x: .value("Day", item.day, unit: .day),
            y: .value("None", 4)
        )
        .symbol {
            Circle()
                .stroke(
                    Color.secondary.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [1.5, 2])
                )
                .frame(width: 6, height: 6)
        }
        .opacity(selectedDay == nil ? 1.0 : (isSelected(item) ? 1.0 : 0.4))
    }

    // MARK: - Helpers

    private func opacity(for item: DayAggregate) -> Double {
        guard selectedDay != nil else { return 1.0 }
        return isSelected(item) ? 1.0 : 0.32
    }

    private func isSelected(_ item: DayAggregate) -> Bool {
        guard let selectedDay else { return false }
        return Calendar.current.isDate(item.day, inSameDayAs: selectedDay)
    }

    private static let chartBlue = Color(hex: "5E9FFF")

    /// Saturated color for the average dot — keys to the day's dominant StressLevel.
    private func dotColor(for item: DayAggregate) -> Color {
        guard item.hasData else { return Color.secondary.opacity(0.30) }
        let level = item.dominantLevel ?? StressLevel(score: item.avgScore)
        return level.color
    }

    /// Subtle, desaturated tint for the range stick — keeps the chart minimal
    /// while still hinting at the day's stress level.
    private func stickColor(for item: DayAggregate) -> Color {
        guard item.hasData else { return Color.secondary.opacity(0.18) }
        return dotColor(for: item).opacity(0.28)
    }

    private func singleLetterDay(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEEE"
        return fmt.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: date)
    }

    private func longDayLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: date)
    }

    private var weekRangeLabel: String {
        guard let first = aggregates.first?.day,
              let last  = aggregates.last?.day else { return "THIS WEEK" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: first).uppercased()) – \(fmt.string(from: last).uppercased())"
    }
}

// MARK: - Preview

#Preview {
    let now = Date()
    let cal = Calendar.current
    var samples: [StressReading] = []
    for dayOffset in 0..<7 {
        guard let day = cal.date(byAdding: .day, value: -(6 - dayOffset), to: now) else { continue }
        // Simulate 0–5 readings with realistic intra-day variation.
        let count = Int.random(in: 0...5)
        for _ in 0..<count {
            let score = Double.random(in: 18...88)
            let level: String
            switch score {
            case ..<21:   level = "Excellent"
            case 21..<41: level = "Good"
            case 41..<61: level = "Moderate"
            case 61..<81: level = "High"
            default:       level = "Very High"
            }
            samples.append(StressReading(timestamp: day, score: score, levelLabel: level))
        }
    }
    return StressWeekChartView(readings: samples)
        .padding()
        .background(Color(.systemGroupedBackground))
}
