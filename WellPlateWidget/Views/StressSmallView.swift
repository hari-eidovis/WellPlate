import SwiftUI
import WidgetKit

// MARK: - Small Widget  (~155 × 155 pt)
// Shows: stress ring + level label + top factor hint

struct StressSmallView: View {
    let data: WidgetStressData

    private var levelColor: Color {
        StressWidgetColor.color(for: data.levelRaw)
    }

    private var topFactor: WidgetStressFactor? {
        data.factors
            .filter { $0.hasValidData }
            .max(by: { $0.contribution < $1.contribution })
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
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Stress")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: StressWidgetColor.systemImage(for: data.levelRaw))
                    .font(.caption2)
                    .foregroundStyle(levelColor)
            }

            Spacer(minLength: 6)

            // Stress ring
            StressRingView(data: data, ringWidth: 9)
                .frame(width: 82, height: 82)

            Spacer(minLength: 6)

            // Level label
            Text(data.levelRaw)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(levelColor)

            Spacer(minLength: 4)

            // Top factor or encouragement
            if let factor = topFactor, data.totalScore >= 41 {
                HStack(spacing: 4) {
                    Image(systemName: factor.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(levelColor)
                    Text(factor.title)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(data.encouragement)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open WellPlate\nto get started")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
    }
}
