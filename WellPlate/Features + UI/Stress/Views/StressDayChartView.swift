//
//  StressDayChartView.swift
//  WellPlate
//
//  Intraday stress chart card — bar chart on a gradient background
//  with large score, status badge, and sun/moon time indicators.
//

import SwiftUI
import Charts

// MARK: - StressDayChartView

struct StressDayChartView: View {

    let readings: [StressReading]

    @State private var selectedReading: StressReading? = nil

    // MARK: - Theme

    private static let cardColor = Color(hex: "7B8CDE")

    // MARK: - Computed

    private var latestScore: Double? {
        readings.last?.score
    }

    private var stressLevel: StressLevel {
        StressLevel(score: latestScore ?? 0)
    }

    private var statusText: String {
        switch stressLevel {
        case .excellent, .good: return "Normal"
        case .moderate:         return "Moderate"
        case .high, .veryHigh:  return "Elevated"
        }
    }

    private var statusIcon: String {
        switch stressLevel {
        case .excellent, .good: return "checkmark.seal.fill"
        default:                return "exclamationmark.triangle.fill"
        }
    }

    /// Groups readings by hour → average score per hour.
    private var hourlyBars: [HourlyStressBar] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: readings) {
            cal.component(.hour, from: $0.timestamp)
        }
        return grouped.map { hour, items in
            HourlyStressBar(hour: hour, score: items.map(\.score).reduce(0, +) / Double(items.count))
        }
        .sorted { $0.hour < $1.hour }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if readings.isEmpty {
                emptyState
            } else {
                cardContent
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Self.cardColor.gradient)
        )
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("STRESS LEVEL")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(0.8)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11))
                    Text(statusText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .padding(.bottom, 12)

            // Scrub tooltip
            if let sel = selectedReading {
                HStack(spacing: 5) {
                    Text(sel.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Text("·")
                    Text("\(Int(sel.score))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.bottom, 6)
                .transition(.opacity)
            }

            // Chart
            chartView
                .padding(.bottom, 4)

            // Sun / Moon
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Image(systemName: "moon.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Bar Chart

    private var chartView: some View {
        Chart {
            ForEach(hourlyBars) { bar in
                BarMark(
                    x: .value("Hour", bar.hour),
                    y: .value("Score", bar.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.2)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .cornerRadius(2.5)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [25, 50, 75]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
        }
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: [6, 12, 18]) { value in
                AxisValueLabel {
                    if let h = value.as(Int.self) {
                        Text(hourLabel(h))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
        }
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
                                if let hour: Int = proxy.value(atX: x) {
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        selectedReading = closestReading(toHour: hour)
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
        .frame(height: 120)
        .animation(.easeInOut(duration: 0.3), value: readings.count)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.25))
                Text("No readings yet today")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Text("Snapshots appear automatically when your score changes.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
            }
            .frame(height: 120, alignment: .center)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12AM" }
        if hour < 12 { return "\(hour)AM" }
        if hour == 12 { return "12PM" }
        return "\(hour - 12)PM"
    }

    private func closestReading(toHour hour: Int) -> StressReading? {
        let cal = Calendar.current
        return readings.min(by: {
            abs(cal.component(.hour, from: $0.timestamp) - hour) <
            abs(cal.component(.hour, from: $1.timestamp) - hour)
        })
    }
}

// MARK: - Hourly Bar Model

private struct HourlyStressBar: Identifiable {
    let hour: Int
    let score: Double
    var id: Int { hour }
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
