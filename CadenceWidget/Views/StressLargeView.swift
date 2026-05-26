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
        Link(destination: URL(string: "cadence://stress")!) {
            if data.factors.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .cadenceWidgetBackground {
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
        VStack(alignment: .leading, spacing: 6) {
            // Combined header + score row
            HStack(spacing: 10) {
                StressRingView(data: data, ringWidth: 6)
                    .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.caption2)
                            .foregroundStyle(levelColor)
                        Text(data.levelRaw)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(levelColor)
                    }
                    Text(data.encouragement)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }

            Divider()

            // 4 factor rows (compact, large-widget-only)
            VStack(spacing: 2) {
                ForEach(data.factors, id: \.title) { factor in
                    CompactStressFactorBar(factor: factor)
                        .padding(.horizontal, factor.contribution == highestContribution ? 4 : 0)
                        .background(
                            factor.contribution == highestContribution
                                ? RoundedRectangle(cornerRadius: 6)
                                    .fill(StressWidgetColor.color(for: data.levelRaw).opacity(0.08))
                                : nil
                        )
                }
            }

            // 7-day trend
            if validWeeklyCount >= 2 {
                trendChart
            }

            // Vitals row
            if data.restingHR != nil || data.hrv != nil || data.respiratoryRate != nil {
                vitalsRow
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var trendChart: some View {
        VStack(spacing: 2) {
            Text("7-Day Trend")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(data.weeklyScores, id: \.date) { dayScore in
                    VStack(spacing: 2) {
                        if let score = dayScore.score {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForScore(score))
                                .frame(height: max(CGFloat(score) / 100.0 * 18, 3))
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
            .frame(height: 26)
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
            Text("Open Cadence to get started")
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

// MARK: - Compact Factor Bar (single-row, large-widget only)

private struct CompactStressFactorBar: View {
    let factor: WidgetStressFactor

    private var fraction: Double {
        guard factor.maxScore > 0 else { return 0 }
        return min(factor.contribution / factor.maxScore, 1.0)
    }

    private var barColor: Color {
        guard factor.hasValidData else { return Color(.systemGray3) }
        let stressRatio = min(max(factor.contribution / factor.maxScore, 0), 1)
        return Color(hue: 0.33 * (1.0 - stressRatio), saturation: 0.65, brightness: 0.75)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: factor.icon)
                .font(.system(size: 10))
                .foregroundStyle(factor.hasValidData ? barColor : Color(.systemGray3))
                .frame(width: 12)

            Text(factor.title)
                .font(.system(size: 10))
                .foregroundStyle(factor.hasValidData ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(barColor.opacity(0.2))
                        .frame(height: 5)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(barColor)
                        .frame(width: max(geo.size.width * fraction, 0), height: 5)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)

            Text("\(Int(factor.contribution))/\(Int(factor.maxScore))")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .opacity(factor.hasValidData ? 1.0 : 0.5)
    }
}
