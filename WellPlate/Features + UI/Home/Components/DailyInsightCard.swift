import SwiftUI

// MARK: - DailyInsightCard
//
// Compact home-screen card showing the top insight with sparkline.
// Taps navigate to the full InsightsHubView.

struct DailyInsightCard: View {
    let card: InsightCard?
    let isGenerating: Bool
    var onTap: () -> Void

    var body: some View {
        if isGenerating {
            loadingState
        } else if let card {
            cardContent(card)
        }
        // nil card + not generating = don't render
    }

    // MARK: - Loading

    private var loadingState: some View {
        HStack(spacing: 14) {
            ProgressView()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Analyzing your data...")
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                Text("Generating insights")
                    .font(.r(.caption, .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    // MARK: - Card Content

    private func cardContent(_ card: InsightCard) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(card.domain.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: card.type.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(card.domain.accentColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.headline)
                        .font(.r(.subheadline, .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(card.narrative)
                        .font(.r(.caption, .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // Sparkline
                if case .sparkline(let points) = card.chartData, !points.isEmpty {
                    SparklineView(points: points, accentColor: card.domain.accentColor)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("DailyInsightCard") {
    VStack(spacing: 16) {
        DailyInsightCard(
            card: InsightCard(
                id: UUID(), type: .reinforcement, domain: .hydration,
                headline: "Consistent hydration this week",
                narrative: "You've hit your water goal 6 out of 7 days.",
                chartData: .sparkline(points: [6, 7, 8, 8, 7, 8, 8]),
                priority: 0.9, isLLMGenerated: false, generatedAt: Date(),
                detailSuggestions: ["Keep it up."]
            ),
            isGenerating: false,
            onTap: {}
        )

        DailyInsightCard(card: nil, isGenerating: true, onTap: {})
    }
    .padding()
}
