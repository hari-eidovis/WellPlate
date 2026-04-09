import SwiftUI

// MARK: - InsightCardView
//
// Reusable card rendering any InsightCard with appropriate chart + narrative.

struct InsightCardView: View {
    let card: InsightCard
    var onDetailsTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: card.domain.icon)
                    .font(.r(.footnote, .semibold))
                    .foregroundStyle(card.domain.accentColor)
                Text(card.domain.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(card.domain.accentColor)
                    .tracking(1.0)
                Spacer()
                Text(card.type.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
            }

            // Headline
            Text(card.headline)
                .font(.r(.headline, .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Chart
            chartView(for: card.chartData)

            // Narrative
            Text(card.narrative)
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Details button
            if onDetailsTap != nil {
                Button {
                    HapticService.impact(.light)
                    onDetailsTap?()
                } label: {
                    HStack(spacing: 4) {
                        Text("See Details")
                            .font(.r(.footnote, .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(card.domain.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    // MARK: - Chart Router

    @ViewBuilder
    private func chartView(for data: InsightChartData) -> some View {
        switch data {
        case .trendLine(let points, let goal, let label, let unit):
            TrendAreaChart(points: points, goalLine: goal, metricLabel: label, unit: unit, accentColor: card.domain.accentColor)
        case .correlationScatter(let points, let r, let xLabel, let yLabel):
            CorrelationScatterChart(points: points, r: r, xLabel: xLabel, yLabel: yLabel)
        case .comparisonBars(let bars, let highlight):
            ComparisonBarChart(bars: bars, highlight: highlight)
        case .macroRadar(let actual, let goals):
            MacroGroupedBarChart(actual: actual, goals: goals)
        case .milestoneRing(let current, let target, let label):
            HStack {
                Spacer()
                MilestoneRingView(current: current, target: target, streakLabel: label)
                Spacer()
            }
        case .sparkline(let points):
            SparklineView(points: points, accentColor: card.domain.accentColor)
        }
    }
}

// MARK: - InsightEntrance Modifier (shared)

struct InsightEntrance: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.78)
                .delay(Double(index) * 0.08),
                value: appeared
            )
            .onAppear { appeared = true }
    }
}

extension View {
    func insightEntrance(index: Int) -> some View {
        modifier(InsightEntrance(index: index))
    }
}

// MARK: - Preview

#Preview("InsightCardView") {
    InsightCardView(
        card: InsightCard(
            id: UUID(), type: .trend, domain: .stress,
            headline: "Stress declining 4 days",
            narrative: "Your stress score has dropped from 72 to 48 over the last 4 days.",
            chartData: .trendLine(points: (0..<7).map { i in
                (date: Calendar.current.date(byAdding: .day, value: -6 + i, to: Date())!, value: [72.0, 68, 62, 58, 55, 50, 48][i])
            }, goalLine: 50, metricLabel: "Stress", unit: "/100"),
            priority: 0.75, isLLMGenerated: false, generatedAt: Date(),
            detailSuggestions: ["Keep it up.", "Maintain sleep schedule."]
        ),
        onDetailsTap: {}
    )
    .padding()
}
