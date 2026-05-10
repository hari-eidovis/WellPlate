import SwiftUI

// MARK: - InsightsHubView
//
// Scrollable feed of prioritised InsightCardView instances.
// Three display states: loading, insufficient data, loaded cards.

struct InsightsHubView: View {
    @ObservedObject var engine: InsightEngine
    @State private var selectedCard: InsightCard?
    @State private var showFullReport = false

    var body: some View {
        ZStack {
            if engine.isGenerating {
                loadingView
            } else if engine.insufficientData {
                insufficientDataView
            } else if engine.insightCards.isEmpty {
                readyToGenerateView
            } else {
                cardFeed
            }
        }
        .navigationTitle("Your Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Cheap day-count refresh on appear; never auto-generates.
            await engine.refreshDayCount()
        }
        .sheet(item: $selectedCard) { card in
            InsightDetailSheet(card: card, engine: engine)
        }
        .navigationDestination(isPresented: $showFullReport) {
            AI15DayReportView()
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
        let logged = engine.loggedDayCount
        let target = engine.dayCountThreshold
        let remaining = engine.daysRemaining
        let progress = target > 0 ? min(1.0, Double(logged) / Double(target)) : 0

        return VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.brand.opacity(0.6))

            Text(remaining == 1 ? "1 day to go" : "\(remaining) days to go")
                .font(.r(.title3, .bold))
                .foregroundStyle(.primary)

            Text("Use WellPlate for \(remaining == 1 ? "1 more day" : "\(remaining) more days") so we have enough data to generate personalized insights for you.")
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColors.brand.opacity(0.15))
                        Capsule()
                            .fill(AppColors.brand)
                            .frame(width: max(0, geo.size.width * progress))
                    }
                }
                .frame(height: 8)

                Text("\(logged) of \(target) days logged")
                    .font(.r(.caption, .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ready to Generate

    private var readyToGenerateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.brand)

            Text("Ready for insights")
                .font(.r(.title3, .bold))
                .foregroundStyle(.primary)

            Text("You've logged \(engine.loggedDayCount) days of wellness data. Tap below to generate personalized insights using on-device AI.")
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                HapticService.impact(.medium)
                Task { await engine.generateInsights() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                    Text("Generate Insights")
                        .font(.r(.subheadline, .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(AppColors.brand))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card Feed

    private var cardFeed: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                InsightsHubHeader(cardCount: engine.insightCards.count)
                    .insightEntrance(index: 0)

                // Full Report navigation card
                Button {
                    HapticService.impact(.light)
                    showFullReport = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.brand)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("15-Day Wellness Report")
                                .font(.r(.headline, .bold))
                                .foregroundStyle(.primary)
                            Text("Comprehensive analysis across all your data")
                                .font(.r(.caption, .regular))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppColors.brand.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .insightEntrance(index: 1)

                ForEach(Array(engine.insightCards.enumerated()), id: \.element.id) { idx, card in
                    InsightCardView(card: card) {
                        selectedCard = card
                    }
                    .insightEntrance(index: idx + 2)
                }

                InsightsHubFooter(engine: engine)
                    .insightEntrance(index: engine.insightCards.count + 2)
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
