//
//  StressDayChartView.swift
//  WellPlate
//
//  Renders an intraday stress score line chart using SwiftCharts.
//  Each data point is a StressReading captured today.
//

import SwiftUI
import Charts

// MARK: - StressDayChartView

struct StressDayChartView: View {

    let readings: [StressReading]

    @State private var selectedReading: StressReading? = nil

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if readings.isEmpty {
                emptyState
            } else {
                chartContent
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Chart

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Legend row
            HStack(spacing: 16) {
                legendDot(color: Color(hue: 0.33, saturation: 0.70, brightness: 0.80), label: "Low")
                legendDot(color: Color(hue: 0.14, saturation: 0.85, brightness: 0.90), label: "Moderate")
                legendDot(color: Color(hue: 0.00, saturation: 0.80, brightness: 0.85), label: "High")
                Spacer()
                if let sel = selectedReading {
                    Text("\(sel.timestamp, format: .dateTime.hour().minute()) · \(Int(sel.score))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(colorFor(score: sel.score))
                        .transition(.opacity)
                }
            }

            Chart {
                // Area fill
                ForEach(readings) { reading in
                    AreaMark(
                        x: .value("Time", reading.timestamp, unit: .hour),
                        y: .value("Score", reading.score)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [stressGradientColor(for: reading.score).opacity(0.30), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Line
                ForEach(readings) { reading in
                    LineMark(
                        x: .value("Time", reading.timestamp, unit: .hour),
                        y: .value("Score", reading.score)
                    )
                    .foregroundStyle(stressGradientColor(for: reading.score))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Points
                ForEach(readings) { reading in
                    PointMark(
                        x: .value("Time", reading.timestamp, unit: .hour),
                        y: .value("Score", reading.score)
                    )
                    .symbolSize(selectedReading?.id == reading.id ? 120 : 60)
                    .foregroundStyle(stressGradientColor(for: reading.score))
                    .annotation(position: .top) {
                        if selectedReading?.id == reading.id {
                            annotationLabel(reading: reading)
                        }
                    }
                }

                // Rule mark at selected time
                if let sel = selectedReading {
                    RuleMark(x: .value("Time", sel.timestamp, unit: .hour))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
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
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.10))
                    AxisValueLabel(format: .dateTime.hour())
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: todayDomain)
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
                                    if let date: Date = proxy.value(atX: location.x) {
                                        selectedReading = closestReading(to: date)
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        selectedReading = nil
                                    }
                                }
                        )
                }
            }
            .frame(height: 200)
            .animation(.easeInOut(duration: 0.3), value: readings.count)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.45))

            VStack(spacing: 4) {
                Text("No readings yet today")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Stress snapshots will appear here automatically when your score changes.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Helpers

    private var todayDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .hour, value: 24, to: start) ?? Date()
        return start...end
    }

    private func closestReading(to date: Date) -> StressReading? {
        readings.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }

    private func stressGradientColor(for score: Double) -> Color {
        let t = min(max(score / 100.0, 0), 1)
        return Color(hue: 0.33 * (1.0 - t), saturation: 0.75, brightness: 0.78)
    }

    private func colorFor(score: Double) -> Color { stressGradientColor(for: score) }

    @ViewBuilder
    private func annotationLabel(reading: StressReading) -> some View {
        VStack(spacing: 2) {
            Text(reading.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(Int(reading.score))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(stressGradientColor(for: reading.score))
            Text(reading.levelLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    let now = Date()
    let cal = Calendar.current
    let samples: [StressReading] = [
        StressReading(timestamp: cal.date(byAdding: .hour, value: -7, to: now)!, score: 18, levelLabel: "Excellent"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -5, to: now)!, score: 35, levelLabel: "Good"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -3, to: now)!, score: 58, levelLabel: "Moderate"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -1, to: now)!, score: 72, levelLabel: "High"),
        StressReading(timestamp: now, score: 45, levelLabel: "Moderate"),
    ]
    VStack {
        StressDayChartView(readings: samples)
            .padding()
        StressDayChartView(readings: [])
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
