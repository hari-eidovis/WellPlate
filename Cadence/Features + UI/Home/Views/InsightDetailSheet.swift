import SwiftUI

// MARK: - InsightDetailSheet
//
// Deep-dive modal with full-size chart, extended narrative, and suggestions.

struct InsightDetailSheet: View {
    let card: InsightCard
    @ObservedObject var engine: InsightEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Domain header
                    HStack(spacing: 8) {
                        Image(systemName: card.domain.icon)
                            .font(.r(.subheadline, .semibold))
                            .foregroundStyle(card.domain.accentColor)
                        Text(card.domain.label)
                            .font(.r(.subheadline, .semibold))
                            .foregroundStyle(card.domain.accentColor)
                        Spacer()
                        Text(card.type.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }

                    // Headline
                    Text(card.headline)
                        .font(.r(.title3, .bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Full-size chart
                    detailChart
                        .padding(.vertical, 8)

                    // Narrative
                    Text(card.narrative)
                        .font(.r(.body, .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Suggestions
                    if !card.detailSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SUGGESTIONS")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(card.domain.accentColor)
                                .tracking(1.0)

                            ForEach(card.detailSuggestions, id: \.self) { suggestion in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(card.domain.accentColor)
                                    Text(suggestion)
                                        .font(.r(.subheadline, .regular))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(card.domain.accentColor.opacity(0.06))
                        )
                    }

                    // Caution for correlations
                    if card.type == .correlation {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.warning)
                            Text("Correlation does not imply causation. Continue tracking to strengthen confidence in this pattern.")
                                .font(.r(.caption, .regular))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColors.warning.opacity(0.08))
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle(card.domain.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Detail Chart (larger frames)

    @ViewBuilder
    private var detailChart: some View {
        switch card.chartData {
        case .trendLine(let points, let goal, let label, let unit):
            TrendAreaChart(points: points, goalLine: goal, metricLabel: label, unit: unit, accentColor: card.domain.accentColor)
                .frame(height: 200)
        case .correlationScatter(let points, let r, let xLabel, let yLabel):
            CorrelationScatterChart(points: points, r: r, xLabel: xLabel, yLabel: yLabel)
                .frame(height: 220)
        case .comparisonBars(let bars, let highlight):
            ComparisonBarChart(bars: bars, highlight: highlight)
                .frame(height: 120)
        case .macroRadar(let actual, let goals):
            MacroGroupedBarChart(actual: actual, goals: goals)
                .frame(height: 200)
        case .milestoneRing(let current, let target, let label):
            HStack {
                Spacer()
                MilestoneRingView(current: current, target: target, streakLabel: label)
                    .scaleEffect(1.5)
                Spacer()
            }
            .frame(height: 140)
        case .sparkline(let points):
            SparklineView(points: points, accentColor: card.domain.accentColor)
                .frame(width: 200, height: 60)
        }
    }
}

// MARK: - Preview

#Preview("InsightDetailSheet") {
    InsightDetailSheet(
        card: InsightCard(
            id: UUID(), type: .correlation, domain: .cross,
            headline: "Sleep & Stress are inversely linked",
            narrative: "On days you slept 7h+, stress averaged 18% lower. This moderate inverse association (r = -0.62) has been consistent over the 14-day window.",
            chartData: .correlationScatter(points: [
                (5.5, 72), (6.0, 68), (6.5, 61), (7.0, 55), (7.5, 48), (8.0, 42)
            ], r: -0.62, xLabel: "Sleep (h)", yLabel: "Stress"),
            priority: 0.85, isLLMGenerated: false, generatedAt: Date(),
            detailSuggestions: ["Aim for 7.5h+ tonight.", "Consistent bedtime helps."]
        ),
        engine: InsightEngine()
    )
}
