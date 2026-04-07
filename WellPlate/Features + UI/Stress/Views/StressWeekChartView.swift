//
//  StressWeekChartView.swift
//  WellPlate
//
//  7-day stress trend — gradient capsule bars with trend line overlay,
//  score annotations, and teal → amber → rust color palette.
//

import SwiftUI
import Charts

// MARK: - Daily Stress Average

private struct DayAverage: Identifiable {
    let id = UUID()
    let day: Date
    let averageScore: Double
    let dominantLevel: String
    let isToday: Bool
}

// MARK: - StressWeekChartView

struct StressWeekChartView: View {

    let readings: [StressReading]

    @State private var selectedDay: DayAverage? = nil

    // MARK: - Computed Data

    private var dayAverages: [DayAverage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var groups: [Date: [StressReading]] = [:]
        for r in readings {
            groups[r.day, default: []].append(r)
        }
        return (0..<7).compactMap { offset -> DayAverage? in
            guard let day = calendar.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            let dayReadings = groups[day] ?? []
            let avg = dayReadings.isEmpty ? 0 : dayReadings.map(\.score).reduce(0, +) / Double(dayReadings.count)
            let dominant = dominantLevel(in: dayReadings) ?? "—"
            return DayAverage(day: day, averageScore: avg, dominantLevel: dominant,
                              isToday: calendar.isDateInToday(day))
        }
    }

    private var weekAverage: Double {
        let active = dayAverages.filter { $0.averageScore > 0 }.map(\.averageScore)
        guard !active.isEmpty else { return 0 }
        return active.reduce(0, +) / Double(active.count)
    }

    private func dominantLevel(in readings: [StressReading]) -> String? {
        guard !readings.isEmpty else { return nil }
        return Dictionary(grouping: readings, by: \.levelLabel).mapValues(\.count)
            .max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tooltipHeader

            Chart {
                // ── Week average line ──
                if weekAverage > 0 {
                    RuleMark(y: .value("Avg", weekAverage))
                        .foregroundStyle(Color.secondary.opacity(0.14))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                ForEach(dayAverages) { item in
                    // ── Gradient bar ──
                    BarMark(
                        x: .value("Day", shortDayName(for: item.day)),
                        y: .value("Score", max(item.averageScore, item.averageScore == 0 ? 0 : 3)),
                        width: .ratio(0.50)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                barColor(for: item.averageScore, isToday: item.isToday).opacity(0.25),
                                barColor(for: item.averageScore, isToday: item.isToday)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(6, style: .continuous)

                    // ── Score label on every bar ──
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        if item.averageScore > 0 {
                            Text("\(Int(item.averageScore))")
                                .font(.system(size: 9, weight: item.isToday ? .bold : .medium, design: .rounded))
                                .foregroundStyle(barColor(for: item.averageScore, isToday: item.isToday)
                                    .opacity(item.isToday ? 1.0 : 0.65))
                        }
                    }
                }

                // ── Trend line connecting averages ──
                ForEach(dayAverages.filter { $0.averageScore > 0 }) { item in
                    LineMark(
                        x: .value("Day", shortDayName(for: item.day)),
                        y: .value("Trend", item.averageScore)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", shortDayName(for: item.day)),
                        y: .value("Trend", item.averageScore)
                    )
                    .symbolSize(10)
                    .foregroundStyle(Color.secondary.opacity(0.18))
                }
            }
            .chartYAxis {
                AxisMarks(values: [25, 50, 75]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.35))
                        .foregroundStyle(Color.secondary.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .foregroundStyle(Color.secondary.opacity(0.40))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.50))
                }
            }
            .chartYScale(domain: 0...100)
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let origin = geo[proxy.plotAreaFrame].origin
                                    let x = value.location.x - origin.x
                                    if let label: String = proxy.value(atX: x) {
                                        withAnimation(.easeOut(duration: 0.1)) {
                                            selectedDay = dayAverages.first {
                                                shortDayName(for: $0.day) == label
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.25)) { selectedDay = nil }
                                }
                        )
                }
            }
            .frame(height: 150)
            .animation(.easeInOut(duration: 0.3), value: readings.count)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
    }

    // MARK: - Tooltip Header

    private var tooltipHeader: some View {
        Group {
            if let sel = selectedDay, sel.averageScore > 0 {
                HStack(spacing: 5) {
                    Circle()
                        .fill(barColor(for: sel.averageScore, isToday: sel.isToday))
                        .frame(width: 7, height: 7)
                    Text(sel.isToday ? "Today" : shortDayName(for: sel.day))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(Int(sel.averageScore))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(barColor(for: sel.averageScore, isToday: sel.isToday))
                    Text(sel.dominantLevel.lowercased())
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(barColor(for: sel.averageScore, isToday: sel.isToday).opacity(0.10))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack {
                    Text("this week")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                    Spacer()
                    if weekAverage > 0 {
                        Text("avg \(Int(weekAverage))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: selectedDay?.id)
    }

    // MARK: - Chart Color Palette

    /// Teal (calm) → amber (moderate) → rust (stressed).
    private func barColor(for avg: Double, isToday: Bool) -> Color {
        guard avg > 0 else {
            return Color.secondary.opacity(isToday ? 0.18 : 0.10)
        }
        let t = min(max(avg / 100.0, 0), 1)
        let boost: Double = isToday ? 0.06 : 0

        if t <= 0.35 {
            let local = t / 0.35
            return Color(hue: 0.48,
                         saturation: 0.32 + local * 0.22 + boost,
                         brightness: 0.70 + local * 0.05 + boost)
        } else if t <= 0.55 {
            let local = (t - 0.35) / 0.20
            return Color(hue: 0.48 - local * 0.36,
                         saturation: 0.50 + local * 0.08 + boost,
                         brightness: 0.74 - local * 0.02 + boost)
        } else {
            let local = (t - 0.55) / 0.45
            return Color(hue: 0.12 - local * 0.11,
                         saturation: 0.55 + local * 0.15 + boost,
                         brightness: 0.72 - local * 0.10 + boost)
        }
    }

    // MARK: - Helpers

    private func shortDayName(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let now = Date()
    let cal = Calendar.current
    var samples: [StressReading] = []
    for dayOffset in 0..<7 {
        guard let day = cal.date(byAdding: .day, value: -(6 - dayOffset), to: now) else { continue }
        let count = Int.random(in: 1...4)
        for _ in 0..<count {
            let score = Double.random(in: 20...80)
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
