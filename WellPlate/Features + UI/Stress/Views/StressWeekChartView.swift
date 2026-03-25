//
//  StressWeekChartView.swift
//  WellPlate
//
//  7-day stress trend — minimal capsule bars, muted earth-tone palette.
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

    private func dominantLevel(in readings: [StressReading]) -> String? {
        guard !readings.isEmpty else { return nil }
        return Dictionary(grouping: readings, by: \.levelLabel).mapValues(\.count)
            .max(by: { $0.value < $1.value })?.key
    }

    /// Low stress (≤40%) → .primary at opacity; higher → amber → rust
    private func barColor(for avg: Double, isToday: Bool) -> Color {
        guard avg > 0 else {
            return Color.secondary.opacity(isToday ? 0.18 : 0.10)
        }
        let t = min(max(avg / 100.0, 0), 1)
        if t <= 0.40 {
            let base = 0.28 + t * 0.40
            return Color.primary.opacity(isToday ? base + 0.10 : base)
        }
        let ht = (t - 0.40) / 0.60
        return Color(
            hue: 0.12 - ht * 0.11,
            saturation: isToday ? (0.52 + ht * 0.18) : (0.40 + ht * 0.15),
            brightness: isToday ? (0.70 - ht * 0.12) : (0.76 - ht * 0.10)
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Tooltip row — visible only while scrubbing
            Group {
                if let sel = selectedDay, sel.averageScore > 0 {
                    HStack(spacing: 5) {
                        Text(sel.isToday ? "Today" : shortDayName(for: sel.day))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("·  avg \(Int(sel.averageScore))")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("·  \(sel.dominantLevel)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack {
                        Text("this week")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.secondary.opacity(0.65))
                        Spacer()
                        if !readings.isEmpty {
                            let overall = readings.map(\.score).reduce(0, +) / Double(readings.count)
                            Text("avg \(Int(overall))")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: selectedDay?.id)

            Chart(dayAverages) { item in
                BarMark(
                    x: .value("Day", shortDayName(for: item.day)),
                    y: .value("Score", max(item.averageScore, item.averageScore == 0 ? 0 : 3)),
                    width: .ratio(0.55)
                )
                .foregroundStyle(barColor(for: item.averageScore, isToday: item.isToday))
                .cornerRadius(5, style: .continuous)
                // Subtle value label only for today or selected
                .annotation(position: .top, alignment: .center) {
                    if item.isToday && item.averageScore > 0 {
                        Text("\(Int(item.averageScore))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(barColor(for: item.averageScore, isToday: true).opacity(0.75))
                    }
                }
            }
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
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }
            .chartYScale(domain: 0...100)
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
            .frame(height: 140)
            .animation(.easeInOut(duration: 0.3), value: readings.count)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
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
