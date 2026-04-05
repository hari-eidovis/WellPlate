import SwiftUI
import WidgetKit

// MARK: - Medium Widget  (~329 × 155 pt)
// Shows: stress ring on left, top factor + vitals + change indicator on right

struct StressMediumView: View {
    let data: WidgetStressData

    private var levelColor: Color {
        StressWidgetColor.color(for: data.levelRaw)
    }

    private var topFactor: WidgetStressFactor? {
        data.factors
            .filter { $0.hasValidData }
            .max(by: { $0.contribution < $1.contribution })
    }

    private var scoreDelta: Int? {
        guard let yesterday = data.yesterdayScore else { return nil }
        return Int(data.totalScore - yesterday)
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
                    colors: [levelColor.opacity(0.05), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            // Left column: ring + label
            VStack(spacing: 6) {
                Text("Stress")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                StressRingView(data: data, ringWidth: 10)
                    .frame(width: 94, height: 94)

                Text(data.levelRaw)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(levelColor)
            }
            .frame(width: 114)

            // Divider
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 0.5)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)

            // Right column: factor + vitals + change
            VStack(alignment: .leading, spacing: 8) {
                // Top factor
                if let factor = topFactor {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top Factor")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        StressFactorBar(factor: factor)
                    }
                }

                // Vitals row
                if data.restingHR != nil || data.hrv != nil {
                    HStack(spacing: 10) {
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
                    }
                }

                // Change indicator
                if let delta = scoreDelta {
                    let isImproved = delta < 0
                    HStack(spacing: 3) {
                        Image(systemName: isImproved ? "arrow.down.right" : "arrow.up.right")
                            .font(.system(size: 9))
                        Text("\(abs(delta)) from yesterday")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(isImproved
                        ? StressWidgetColor.color(for: "Good")
                        : StressWidgetColor.color(for: "High")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
        .padding(14)
    }
}
