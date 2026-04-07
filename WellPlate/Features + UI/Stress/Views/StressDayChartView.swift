//
//  StressDayChartView.swift
//  WellPlate
//
//  Intraday stress rhythm — gradient area chart with zone indicators,
//  rich color palette (teal → amber → rust), and interactive scrub tooltip.
//

import SwiftUI
import Charts

// MARK: - StressDayChartView

struct StressDayChartView: View {

    let readings: [StressReading]

    @State private var selectedReading: StressReading? = nil

    // MARK: - Computed

    private var averageScore: Double {
        guard !readings.isEmpty else { return 0 }
        return readings.map(\.score).reduce(0, +) / Double(readings.count)
    }

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

    // MARK: - Chart Content

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            tooltipHeader
            chart
        }
    }

    // MARK: - Tooltip Header

    private var tooltipHeader: some View {
        Group {
            if let sel = selectedReading {
                HStack(spacing: 5) {
                    Circle()
                        .fill(chartColor(for: sel.score))
                        .frame(width: 7, height: 7)
                    Text(sel.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(Int(sel.score))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(chartColor(for: sel.score))
                    Text(sel.levelLabel.lowercased())
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(chartColor(for: sel.score).opacity(0.10))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack(spacing: 5) {
                    if let last = readings.last {
                        Circle()
                            .fill(chartColor(for: last.score))
                            .frame(width: 6, height: 6)
                        Text("now")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(Int(last.score))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(chartColor(for: last.score))
                    }
                    Spacer()
                    if readings.count > 1 {
                        Text("avg \(Int(averageScore))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.55))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: selectedReading?.id)
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // ── Zone boundary: moderate threshold ──
            RuleMark(y: .value("Zone", 40))
                .foregroundStyle(Color.orange.opacity(0.12))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [5, 5]))

            // ── Zone boundary: high threshold ──
            RuleMark(y: .value("Zone-Hi", 70))
                .foregroundStyle(Color.red.opacity(0.10))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [5, 5]))

            // ── Day average line ──
            if readings.count > 1 {
                RuleMark(y: .value("Avg", averageScore))
                    .foregroundStyle(Color.secondary.opacity(0.14))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // ── Gradient area fill ──
            ForEach(readings) { r in
                AreaMark(
                    x: .value("Time", r.timestamp, unit: .hour),
                    y: .value("Score", r.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: chartColor(for: r.score).opacity(0.30), location: 0),
                            .init(color: chartColor(for: r.score).opacity(0.10), location: 0.55),
                            .init(color: chartColor(for: r.score).opacity(0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // ── Main curve ──
            ForEach(readings) { r in
                LineMark(
                    x: .value("Time", r.timestamp, unit: .hour),
                    y: .value("Score", r.score)
                )
                .foregroundStyle(chartColor(for: r.score))
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            // ── Data-point dots ──
            ForEach(readings) { r in
                PointMark(
                    x: .value("Time", r.timestamp, unit: .hour),
                    y: .value("Score", r.score)
                )
                .symbolSize(r.id == readings.last?.id ? 38 : 14)
                .foregroundStyle(chartColor(for: r.score).opacity(r.id == readings.last?.id ? 1.0 : 0.65))
            }

            // ── Scrub indicator ──
            if let sel = selectedReading {
                RuleMark(x: .value("Sel", sel.timestamp, unit: .hour))
                    .foregroundStyle(chartColor(for: sel.score).opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                PointMark(
                    x: .value("Sel", sel.timestamp, unit: .hour),
                    y: .value("SelScore", sel.score)
                )
                .symbolSize(65)
                .foregroundStyle(chartColor(for: sel.score))
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
                            .foregroundStyle(Color.secondary.opacity(0.38))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    .foregroundStyle(Color.secondary.opacity(0.06))
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.48))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: todayDomain)
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
        .frame(height: 180)
        .animation(.easeInOut(duration: 0.3), value: readings.count)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.secondary.opacity(0.06), Color.secondary.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "waveform.path")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.secondary.opacity(0.40), Color.secondary.opacity(0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

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

    // MARK: - Chart Color Palette

    /// Teal (calm) → amber (moderate) → rust (stressed).
    /// Gives low-stress readings a distinctive color instead of neutral gray.
    private func chartColor(for score: Double) -> Color {
        let t = min(max(score / 100.0, 0), 1)
        if t <= 0.35 {
            let local = t / 0.35
            return Color(hue: 0.48,
                         saturation: 0.32 + local * 0.22,
                         brightness: 0.70 + local * 0.05)
        } else if t <= 0.55 {
            let local = (t - 0.35) / 0.20
            return Color(hue: 0.48 - local * 0.36,
                         saturation: 0.50 + local * 0.08,
                         brightness: 0.74 - local * 0.02)
        } else {
            let local = (t - 0.55) / 0.45
            return Color(hue: 0.12 - local * 0.11,
                         saturation: 0.55 + local * 0.15,
                         brightness: 0.72 - local * 0.10)
        }
    }

    // MARK: - Helpers

    private var todayDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .hour, value: 24, to: start) ?? Date()
        return start...end
    }

    private func closestReading(to date: Date) -> StressReading? {
        readings.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
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
