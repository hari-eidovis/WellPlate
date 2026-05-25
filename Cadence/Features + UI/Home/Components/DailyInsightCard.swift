import SwiftUI

// MARK: - DailyInsightCard
//
// Nudge-style home-screen card showing the top insight with tinted background,
// domain/type badges, progress bar (when available), and an optional inline action button.
// Taps on the card body navigate to InsightsHubView; the action button fires a domain-specific quick action.

struct DailyInsightCard: View {
    let card: InsightCard?
    let isGenerating: Bool
    var actionLabel: String? = nil
    var actionIcon: String? = nil
    var onTap: () -> Void
    var onAction: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        if isGenerating {
            loadingState
        } else if let card {
            cardContent(card)
        }
        // nil card + not generating = don't render
    }

    // MARK: - Loading State

    @State private var shimmer = false

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 32, height: 32)
                    .overlay { ProgressView().scaleEffect(0.7) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Analyzing your data...")
                        .font(.r(.subheadline, .semibold))
                        .foregroundStyle(.primary)
                    Text("Generating personalized insights")
                        .font(.r(.caption, .regular))
                        .foregroundStyle(.secondary)
                }
            }

            // Shimmer placeholder bars
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 10)
                .opacity(shimmer ? 0.4 : 1)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 10)
                .frame(maxWidth: 200)
                .opacity(shimmer ? 0.4 : 1)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.brand.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(AppColors.brand.opacity(0.10), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }

    // MARK: - Card Content

    private func cardContent(_ card: InsightCard) -> some View {
        let color = card.domain.accentColor

        return VStack(alignment: .leading, spacing: 14) {
            // Top row: domain badge + type badge + dismiss
            HStack {
                domainBadge(card: card, color: color)
                Spacer()
                typeBadge(card: card, color: color)
                if let onDismiss {
                    Button {
                        HapticService.impact(.light)
                        withAnimation(.easeOut(duration: 0.25)) { onDismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Headline
            Text(card.headline)
                .font(.r(.body, .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Narrative
            Text(card.narrative)
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            // Bottom row: progress / sparkline / action
            bottomRow(card: card, color: color)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(color.opacity(0.12), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { onTap() }
    }

    // MARK: - Domain Badge

    private func domainBadge(card: InsightCard, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: card.domain.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(card.domain.label)
                .font(.r(.caption, .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Type Badge

    private func typeBadge(card: InsightCard, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: card.type.icon)
                .font(.system(size: 9, weight: .bold))
            Text(card.type.label)
                .font(.r(.caption2, .bold))
        }
        .foregroundStyle(color.opacity(0.7))
    }

    // MARK: - Bottom Row

    @ViewBuilder
    private func bottomRow(card: InsightCard, color: Color) -> some View {
        if let progress = extractProgress(from: card) {
            progressRow(progress: progress, color: color)
        } else if case .sparkline(let points) = card.chartData, !points.isEmpty {
            sparklineRow(points: points, color: color)
        } else {
            fallbackRow(color: color)
        }
    }

    // MARK: - Progress Row

    private func progressRow(progress: ProgressInfo, color: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(color.opacity(0.15))
                        Capsule()
                            .fill(color)
                            .frame(width: max(0, geo.size.width * progress.fraction))
                    }
                }
                .frame(height: 6)

                Text(progress.label)
                    .font(.r(.caption2, .medium))
                    .foregroundStyle(.secondary)
            }

            if let actionLabel, let onAction {
                nudgeButton(label: actionLabel, icon: actionIcon, color: color, action: onAction)
            }
        }
    }

    // MARK: - Sparkline Row

    private func sparklineRow(points: [Double], color: Color) -> some View {
        HStack {
            SparklineView(points: points, accentColor: color)
            Spacer()
            if let actionLabel, let onAction {
                nudgeButton(label: actionLabel, icon: actionIcon, color: color, action: onAction)
            } else {
                detailsChevron(color: color)
            }
        }
    }

    // MARK: - Fallback Row

    private func fallbackRow(color: Color) -> some View {
        HStack {
            Spacer()
            if let actionLabel, let onAction {
                nudgeButton(label: actionLabel, icon: actionIcon, color: color, action: onAction)
            } else {
                detailsChevron(color: color)
            }
        }
    }

    // MARK: - Nudge Button

    private func nudgeButton(label: String, icon: String?, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.impact(.light)
            action()
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(label)
                    .font(.r(.caption, .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Details Chevron

    private func detailsChevron(color: Color) -> some View {
        HStack(spacing: 4) {
            Text("See insights")
                .font(.r(.caption, .semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
    }

    // MARK: - Progress Extraction

    private struct ProgressInfo {
        let fraction: Double
        let label: String
    }

    private func extractProgress(from card: InsightCard) -> ProgressInfo? {
        switch card.chartData {
        case .milestoneRing(let current, let target, let streakLabel):
            guard target > 0 else { return nil }
            let frac = min(1.0, Double(current) / Double(target))
            let label = streakLabel.isEmpty ? "\(current) / \(target)" : streakLabel
            return ProgressInfo(fraction: frac, label: label)
        case .trendLine(let points, let goalLine, _, let unit):
            if let goal = goalLine, goal > 0, let last = points.last?.value {
                let frac = min(1.0, last / goal)
                return ProgressInfo(fraction: frac, label: "\(Int(last)) / \(Int(goal)) \(unit)")
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Preview

#Preview("Nudge — Milestone with Progress") {
    VStack(spacing: 16) {
        DailyInsightCard(
            card: InsightCard(
                id: UUID(), type: .milestone, domain: .hydration,
                headline: "6-day hydration streak!",
                narrative: "You've hit your water goal 6 out of 7 days this week. One more day to go.",
                chartData: .milestoneRing(current: 6, target: 7, streakLabel: "6 / 7 days"),
                priority: 0.9, isLLMGenerated: false, generatedAt: Date(),
                detailSuggestions: ["Keep it up."]
            ),
            isGenerating: false,
            actionLabel: "Add",
            actionIcon: "plus",
            onTap: {},
            onAction: {}
        )

        DailyInsightCard(
            card: InsightCard(
                id: UUID(), type: .reinforcement, domain: .nutrition,
                headline: "Protein intake improved",
                narrative: "Your average protein went from 45g to 62g over the past week.",
                chartData: .sparkline(points: [45, 48, 55, 58, 60, 61, 62]),
                priority: 0.8, isLLMGenerated: true, generatedAt: Date(),
                detailSuggestions: []
            ),
            isGenerating: false,
            onTap: {}
        )

        DailyInsightCard(card: nil, isGenerating: true, onTap: {})
    }
    .padding(16)
}
