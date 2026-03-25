//
//  StressDayChartView.swift
//  WellPlate
//
//  Renders an intraday stress score line chart using SwiftCharts.
//  Aesthetic: minimal, editorial — single muted line, whisper-thin area fill.
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
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
    }

    // MARK: - Chart

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Scrub tooltip — only shown while dragging
            if let sel = selectedReading {
                HStack(spacing: 6) {
                    Text(sel.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(Int(sel.score))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(lineColor(for: sel.score))
                    Text(sel.levelLabel)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Static subtitle: current / last reading
                if let last = readings.last {
                    HStack(spacing: 4) {
                        Text("now")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(Color.secondary.opacity(0.4))
                        Text("\(Int(last.score))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(lineColor(for: last.score))
                    }
                    .transition(.opacity)
                }
            }

            Chart {
                // Whisper-thin area fill
                ForEach(readings) { r in
                    AreaMark(
                        x: .value("Time", r.timestamp, unit: .hour),
                        y: .value("Score", r.score)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                lineColor(for: r.score).opacity(0.12),
                                lineColor(for: r.score).opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Main line — single muted stroke
                ForEach(readings) { r in
                    LineMark(
                        x: .value("Time", r.timestamp, unit: .hour),
                        y: .value("Score", r.score)
                    )
                    .foregroundStyle(lineColor(for: r.score))
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Scrub rule
                if let sel = selectedReading {
                    RuleMark(x: .value("Time", sel.timestamp, unit: .hour))
                        .foregroundStyle(Color.secondary.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    PointMark(
                        x: .value("Time", sel.timestamp, unit: .hour),
                        y: .value("Score", sel.score)
                    )
                    .symbolSize(50)
                    .foregroundStyle(lineColor(for: sel.score))
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
                                .foregroundStyle(Color.secondary.opacity(0.50))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                        .foregroundStyle(Color.secondary.opacity(0.08))
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.55))
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
                                    let x = value.location.x - origin.x
                                    if let date: Date = proxy.value(atX: x) {
                                        withAnimation(.easeOut(duration: 0.1)) {
                                            selectedReading = closestReading(to: date)
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        selectedReading = nil
                                    }
                                }
                        )
                }
            }
            .frame(height: 170)
            .animation(.easeInOut(duration: 0.3), value: readings.count)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Color.secondary.opacity(0.35))

            VStack(spacing: 3) {
                Text("No readings yet today")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Snapshots appear automatically when your score changes.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Helpers

    /// Low stress (≤40%) → .primary at reduced opacity (calm, editorial)
    /// High stress         → warm terracotta → rust
    private func lineColor(for score: Double) -> Color {
        let t = min(max(score / 100.0, 0), 1)
        if t <= 0.40 {
            // primary fades from 0.35 (calm) to 0.55 (warning edge)
            return Color.primary.opacity(0.35 + t * 0.50)
        }
        let ht = (t - 0.40) / 0.60  // 0→1 across the warm half
        return Color(
            hue: 0.12 - ht * 0.11,          // amber (0.12) → rust (0.01)
            saturation: 0.50 + ht * 0.18,
            brightness: 0.68 - ht * 0.12
        )
    }

    private var todayDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .hour, value: 24, to: start) ?? Date()
        return start...end
    }

    private func closestReading(to date: Date) -> StressReading? {
        readings.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }
}

// MARK: - Preview

#Preview {
    let now = Date()
    let cal = Calendar.current
    let samples: [StressReading] = [
        StressReading(timestamp: cal.date(byAdding: .hour, value: -8, to: now)!, score: 22, levelLabel: "Good"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -6, to: now)!, score: 38, levelLabel: "Good"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -4, to: now)!, score: 55, levelLabel: "Moderate"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -2, to: now)!, score: 68, levelLabel: "High"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -1, to: now)!, score: 48, levelLabel: "Moderate"),
        StressReading(timestamp: now, score: 72, levelLabel: "High"),
    ]
    VStack(spacing: 16) {
        StressDayChartView(readings: samples)
            .padding()
        StressDayChartView(readings: [])
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
