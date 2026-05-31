//
//  StressDayChartView.swift
//  Cadence
//
//  Intraday stress chart card — a smooth "today's arc" (area + line) on a
//  light card background, with a status pill and an info button. The arc
//  mirrors the score's movement across the day; the KPI footer grounds it
//  with Start / Peak / Low / Now.
//

import SwiftUI
import Charts

// MARK: - StressDayChartView

struct StressDayChartView: View {

    let readings: [StressReading]
    var onLongPress: (() -> Void)? = nil
    var onInfoTap: (() -> Void)? = nil

    // MARK: - Theme

    private static let themeBlue = Color(hex: "5E9FFF")

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
        let scores = readings.map(\.score)
        let firstScore = scores.first ?? 0
        let currentScore = scores.last ?? 0
        let peakScore = scores.max() ?? currentScore
        let lowScore = scores.min() ?? currentScore

        return VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 16)

            if scores.count < 2 {
                singleReadingState(currentScore: currentScore)
            } else {
                arcChart
                    .frame(height: 112)
                    .padding(.bottom, 14)

                kpiRow(
                    firstScore: firstScore,
                    peakScore: peakScore,
                    lowScore: lowScore,
                    currentScore: currentScore
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
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
    }

    // MARK: - Arc Chart

    private var arcChart: some View {
        Chart {
            ForEach(Array(readings.enumerated()), id: \.offset) { _, r in
                AreaMark(x: .value("t", r.timestamp), y: .value("score", r.score))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Self.themeBlue.opacity(0.30), Self.themeBlue.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", r.timestamp), y: .value("score", r.score))
                    .foregroundStyle(Self.themeBlue)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.4))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .animation(.easeInOut(duration: 0.3), value: readings.count)
    }

    // MARK: - KPI Row

    private func kpiRow(
        firstScore: Double,
        peakScore: Double,
        lowScore: Double,
        currentScore: Double
    ) -> some View {
        HStack(spacing: 0) {
            arcKpi(label: "Start", value: Int(firstScore.rounded()))
            Spacer()
            arcKpi(label: "Peak",  value: Int(peakScore.rounded()))
            Spacer()
            arcKpi(label: "Low",   value: Int(lowScore.rounded()))
            Spacer()
            arcKpi(label: "Now",   value: Int(currentScore.rounded()), highlight: true)
        }
    }

    private func arcKpi(label: String, value: Int, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: highlight ? 18 : 15, weight: .bold, design: .rounded))
                .foregroundColor(highlight ? Self.themeBlue : .primary)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.6)
        }
    }

    // MARK: - Single Reading State

    /// Shown when only one snapshot exists today — an arc needs at least two
    /// points, so surface the current score and a hint that the arc fills in.
    private func singleReadingState(currentScore: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(Int(currentScore.rounded()))")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Current score")
                    .font(.r(.subheadline, .semibold))
                Text("Today's arc fills in as your score moves.")
                    .font(.r(.caption, .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
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
