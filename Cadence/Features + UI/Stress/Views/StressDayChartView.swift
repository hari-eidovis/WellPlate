//
//  StressDayChartView.swift
//  Cadence
//
//  Intraday stress chart card — bar chart on a light card background
//  with status pill and sun/moon time indicators.
//

import SwiftUI
import Charts

// MARK: - StressDayChartView

struct StressDayChartView: View {

    let readings: [StressReading]
    var onLongPress: (() -> Void)? = nil
    var onInfoTap: (() -> Void)? = nil

    @State private var selectedReading: StressReading? = nil
    @State private var dismissTask: Task<Void, Never>? = nil

    // MARK: - Theme

    private static let barColor = Color(hex: "B6C0EE")

    /// Bucket size (hours) for grouping readings — 2 yields ~7 bars across 6AM–6PM.
    private static let bucketHours = 2

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

    private var statusColor: Color {
        switch stressLevel {
        case .excellent, .good: return Color(hex: "1FA971")
        case .moderate:         return Color(hex: "E08A2B")
        case .high, .veryHigh:  return Color(hex: "D64545")
        }
    }

    /// Groups readings into fixed-size hour buckets → average score per bucket.
    /// Bucket key is the bucket's starting hour (e.g. 0, 2, 4, …, 22 for 2-hour buckets).
    private var hourlyBars: [HourlyStressBar] {
        let cal = Calendar.current
        let size = Self.bucketHours
        let grouped = Dictionary(grouping: readings) { reading -> Int in
            let h = cal.component(.hour, from: reading.timestamp)
            return (h / size) * size
        }
        return grouped.map { bucketHour, items in
            HourlyStressBar(
                hour: bucketHour,
                score: items.map(\.score).reduce(0, +) / Double(items.count)
            )
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
                .fill(AppColors.card)
                .appShadow(radius: 15, y: 5)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in onLongPress?() }
        )
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("STRESS LEVEL")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(statusColor.opacity(0.13)))

                if let onInfoTap {
                    Button {
                        onInfoTap()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)

            // Scrub tooltip
            if let sel = selectedReading {
                HStack(spacing: 5) {
                    Text(sel.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Text("·")
                    Text("\(Int(sel.score))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
                .transition(.opacity)
            }

            // Chart
            chartView
                .padding(.bottom, 6)

            // Sun / Moon
            HStack {
                Image(systemName: "sun.min")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.55))
                Spacer()
                Image(systemName: "moon")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.55))
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
    }

    // MARK: - Bar Chart

    private var chartView: some View {
        Chart {
            ForEach(hourlyBars) { bar in
                BarMark(
                    x: .value("Hour", bar.hour),
                    y: .value("Score", bar.score),
                    width: .fixed(22)
                )
                .foregroundStyle(Self.barColor)
                .cornerRadius(6)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [25, 50, 75]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.22))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary.opacity(0.65))
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
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary.opacity(0.7))
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
                                dismissTask?.cancel()
                                dismissTask = nil
                                let origin = geo[proxy.plotAreaFrame].origin
                                let x = value.location.x - origin.x
                                if let hour: Int = proxy.value(atX: x) {
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        selectedReading = closestReading(toHour: hour)
                                    }
                                }
                            }
                            .onEnded { _ in
                                scheduleSelectionDismiss()
                            }
                    )
            }
        }
        .frame(height: 130)
        .animation(.easeInOut(duration: 0.3), value: readings.count)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            HStack {
                Text("STRESS LEVEL")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
                Spacer()
            }
            VStack(spacing: 8) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("No readings yet today")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Text("Snapshots appear automatically when your score changes.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(height: 130, alignment: .center)
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

    private func scheduleSelectionDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                selectedReading = nil
            }
        }
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
