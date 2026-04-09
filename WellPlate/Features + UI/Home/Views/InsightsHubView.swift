import SwiftUI

// MARK: - InsightsHubView
//
// Scrollable feed of prioritised InsightCardView instances.
// Three display states: loading, insufficient data, loaded cards.

struct InsightsHubView: View {
    @ObservedObject var engine: InsightEngine
    @State private var selectedCard: InsightCard?

    var body: some View {
        ZStack {
            if engine.isGenerating {
                loadingView
            } else if engine.insufficientData {
                insufficientDataView
            } else if engine.insightCards.isEmpty {
                loadingView
            } else {
                cardFeed
            }
        }
        .navigationTitle("Your Insights")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedCard) { card in
            InsightDetailSheet(card: card, engine: engine)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Analyzing your wellness data...")
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Insufficient Data

    private var insufficientDataView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.brand.opacity(0.6))

            Text("Not Enough Data")
                .font(.r(.title3, .bold))
                .foregroundStyle(.primary)

            Text("Log your wellness data for a few more days to unlock AI insights across all domains.")
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card Feed

    private var cardFeed: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                InsightsHubHeader(cardCount: engine.insightCards.count)
                    .insightEntrance(index: 0)

                ForEach(Array(engine.insightCards.enumerated()), id: \.element.id) { idx, card in
                    InsightCardView(card: card) {
                        selectedCard = card
                    }
                    .insightEntrance(index: idx + 1)
                }

                InsightsHubFooter(engine: engine)
                    .insightEntrance(index: engine.insightCards.count + 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - InsightsHubHeader

private struct InsightsHubHeader: View {
    let cardCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
                Text("LAST 14 DAYS")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.brand)
                    .tracking(1.2)
            }
            Text("\(cardCount) insights found")
                .font(.r(.title3, .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.brand.opacity(0.08))
        )
    }
}

// MARK: - InsightsHubFooter

private struct InsightsHubFooter: View {
    @ObservedObject var engine: InsightEngine

    private var generatedAtText: String {
        guard let first = engine.insightCards.first else { return "" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "Generated today at \(f.string(from: first.generatedAt))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(generatedAtText)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)

            Button {
                HapticService.impact(.light)
                Task { await engine.clearAndRegenerate() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Regenerate")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(AppColors.brand)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppColors.brand.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
            .disabled(engine.isGenerating)
            .appDisabled(engine.isGenerating)
        }
        .padding(.top, 8)
    }
}

// MARK: - Preview

#Preview("InsightsHubView") {
    NavigationStack {
        InsightsHubView(engine: {
            let engine = InsightEngine()
            // Mock mode will populate on generateInsights
            return engine
        }())
    }
}
