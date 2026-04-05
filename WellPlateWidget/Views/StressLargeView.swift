import SwiftUI
import WidgetKit

// MARK: - Large Widget  (~329 × 345 pt)
// Shows: stress ring + 4-factor breakdown + 7-day trend + vitals

struct StressLargeView: View {
    let data: WidgetStressData

    private var levelColor: Color {
        StressWidgetColor.color(for: data.levelRaw)
    }

    private var highestContribution: Double {
        data.factors.map(\.contribution).max() ?? 0
    }

    private var validWeeklyCount: Int {
        data.weeklyScores.compactMap(\.score).count
    }

    var body: some View {
        Link(destination: URL(string: "wellplate://stress")!) {
            if data.factors.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .wellPlateWidgetBackground {
            ZStack {
                Color(.systemBackground)
                LinearGradient(
                    colors: [levelColor.opacity(0.06), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.title3)
                        .foregroundStyle(levelColor)
                    Text("Stress Level")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                Spacer()
                Text(Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 12)

            // Score section
            HStack(spacing: 14) {
                StressRingView(data: data, ringWidth: 9)
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    Text(data.levelRaw)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(levelColor)
                    Text(data.encouragement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 10)

            Divider()
                .padding(.bottom, 10)

            // 4 factor rows
            VStack(spacing: 7) {
                ForEach(data.factors, id: \.title) { factor in
                    StressFactorBar(factor: factor)
                        .padding(.horizontal, factor.contribution == highestContribution ? 4 : 0)
                        .padding(.vertical, factor.contribution == highestContribution ? 2 : 0)
                        .background(
                            factor.contribution == highestContribution
                                ? RoundedRectangle(cornerRadius: 6)
                                    .fill(StressWidgetColor.color(for: data.levelRaw).opacity(0.08))
                                : nil
                        )
                }
            }

            Divider()
                .padding(.vertical, 8)

            // 7-day trend
            if validWeeklyCount >= 2 {
                trendChart
            } else {
                Text("Not enough data yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            // Vitals row
            if data.restingHR != nil || data.hrv != nil || data.respiratoryRate != nil {
                Spacer(minLength: 4)
                vitalsRow
            }
        }
        .padding(16)
    }

    private var trendChart: some View {
        VStack(spacing: 4) {
            Text("7-Day Trend")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data.weeklyScores, id: \.date) { dayScore in
                    VStack(spacing: 3) {
                        if let score = dayScore.score {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForScore(score))
                                .frame(height: max(CGFloat(score) / 100.0 * 36, 4))
                        } else {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 2)
                        }
                        Text(dayOfWeekLabel(for: dayScore.date))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 52)
        }
    }

    private var vitalsRow: some View {
        HStack(spacing: 12) {
            if let rhr = data.restingHR {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red.opacity(0.7))
                    Text("\(Int(rhr)) bpm")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let hrv = data.hrv {
                HStack(spacing: 3) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 9))
                        .foregroundStyle(.green.opacity(0.7))
                    Text("\(Int(hrv))ms")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let rr = data.respiratoryRate {
                HStack(spacing: 3) {
                    Image(systemName: "lungs.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.cyan.opacity(0.7))
                    Text("\(Int(rr)) br/min")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open WellPlate to get started")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    // MARK: - Helpers

    private func colorForScore(_ score: Double) -> Color {
        let level: String
        switch score {
        case ..<21:   level = "Excellent"
        case 21..<41: level = "Good"
        case 41..<61: level = "Moderate"
        case 61..<81: level = "High"
        default:      level = "Very High"
        }
        return StressWidgetColor.color(for: level)
    }

    private func dayOfWeekLabel(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let symbols = Calendar.current.shortWeekdaySymbols
        let symbol = symbols[weekday - 1]
        return String(symbol.prefix(1))
    }
}
