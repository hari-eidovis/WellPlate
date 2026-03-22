//
//  StressWeekChartView.swift
//  WellPlate
//
//  Renders a 7-day stress trend bar chart using SwiftCharts.
//  Each bar shows the average stress score for that calendar day.
//

import SwiftUI
import Charts

// MARK: - Daily Stress Average

private struct DayAverage: Identifiable {
    let id = UUID()
    let day: Date          // start-of-day
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

        // Build a dictionary: startOfDay → [readings]
        var groups: [Date: [StressReading]] = [:]
        for reading in readings {
            let d = reading.day
            groups[d, default: []].append(reading)
        }

        // Build 7 slots (oldest → newest)
        return (0..<7).compactMap { offset -> DayAverage? in
            guard let day = calendar.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            let dayReadings = groups[day] ?? []
            let avg = dayReadings.isEmpty ? 0 : dayReadings.map(\.score).reduce(0, +) / Double(dayReadings.count)
            let dominant = dominantLevel(in: dayReadings) ?? "—"
            return DayAverage(
                day: day,
                averageScore: avg,
                dominantLevel: dominant,
                isToday: calendar.isDateInToday(day)
            )
        }
    }

    private func dominantLevel(in readings: [StressReading]) -> String? {
        guard !readings.isEmpty else { return nil }
        let counts = Dictionary(grouping: readings, by: \.levelLabel).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func barColor(for avg: Double) -> Color {
        guard avg > 0 else { return Color.secondary.opacity(0.15) }
        let t = min(max(avg / 100.0, 0), 1)
        return Color(hue: 0.33 * (1.0 - t), saturation: 0.70, brightness: 0.80)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary line
            HStack {
                if let sel = selectedDay, sel.averageScore > 0 {
                    Text(shortDayName(for: sel.day))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("avg \(Int(sel.averageScore))  ·  \(sel.dominantLevel)")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("7-day average")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !readings.isEmpty {
                        let overall = readings.map(\.score).reduce(0, +) / Double(readings.count)
                        Text("\(Int(overall))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(barColor(for: overall))
                    }
                }
            }

            Chart(dayAverages) { item in
                BarMark(
                    x: .value("Day", shortDayName(for: item.day)),
                    y: .value("Score", max(item.averageScore, item.averageScore == 0 ? 0 : 4))
                )
                .foregroundStyle(
                    item.averageScore == 0
                        ? Color.secondary.opacity(0.12)
                        : barColor(for: item.averageScore)
                )
                .cornerRadius(6)
                .annotation(position: .top, alignment: .center) {
                    if item.averageScore > 0 {
                        Text("\(Int(item.averageScore))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(barColor(for: item.averageScore).opacity(0.85))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
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
                                    let location = CGPoint(
                                        x: value.location.x - origin.x,
                                        y: value.location.y - origin.y
                                    )
                                    if let label: String = proxy.value(atX: location.x) {
                                        selectedDay = dayAverages.first(where: { shortDayName(for: $0.day) == label })
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        selectedDay = nil
                                    }
                                }
                        )
                }
            }
            .frame(height: 160)
            .animation(.easeInOut(duration: 0.3), value: readings.count)

            // Today indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text("Today is highlighted with a brighter bar")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Helpers

    private func shortDayName(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
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
        let count = Int.random(in: 1...5)
        for _ in 0..<count {
            let score = Double.random(in: 15...85)
            let level: String
            switch score {
            case ..<21:   level = "Excellent"
            case 21..<41: level = "Good"
            case 41..<61: level = "Moderate"
            case 61..<81: level = "High"
            default:      level = "Very High"
            }
            samples.append(StressReading(timestamp: day, score: score, levelLabel: level))
        }
    }
    return StressWeekChartView(readings: samples)
        .padding()
        .background(Color(.systemGroupedBackground))
}
