import SwiftUI

// MARK: - DailyInsightCard
//
// Home-screen "Today's Focus" card showing the top insight over light floral
// artwork (chosen per domain), with domain/type badges, a progress/sparkline
// bottom row, and an optional inline action button. Taps on the card body open
// the Insights hub; the action button fires a domain-specific quick action.
// Falls back to a loading or "keep logging" state when no insight is ready.

struct DailyInsightCard: View {
    let card: InsightCard?
    let isGenerating: Bool
    var actionLabel: String? = nil
    var actionIcon: String? = nil
    var onTap: () -> Void
    var onAction: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    /// Empty-state copy when no insight is ready yet (mirrors the old hero card).
    var insufficientData: Bool = false
    var daysRemaining: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    // The floral artwork is always light, so text stays dark in both color schemes.
    private let inkPrimary = Color(red: 0.13, green: 0.13, blue: 0.15)
    private let inkSecondary = Color(red: 0.33, green: 0.34, blue: 0.38)

    var body: some View {
        if isGenerating {
            loadingState
        } else if let card {
            cardContent(card)
        } else {
            fallbackState
        }
    }

    // MARK: - Loading State

    @State private var shimmer = false

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay { ProgressView().scaleEffect(0.7) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Analyzing your data...")
                        .font(.r(.subheadline, .semibold))
                        .foregroundStyle(inkPrimary)
                    Text("Generating personalized insights")
                        .font(.r(.caption, .regular))
                        .foregroundStyle(inkSecondary)
                }
            }

            // Shimmer placeholder bars
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.08))
                .frame(height: 10)
                .opacity(shimmer ? 0.4 : 1)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.08))
                .frame(height: 10)
                .frame(maxWidth: 200)
                .opacity(shimmer ? 0.4 : 1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floralCard("floral_faded")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }

    // MARK: - Fallback (no insight yet)

    private var fallbackHeadline: String {
        if insufficientData {
            let d = max(0, daysRemaining)
            return d > 0
                ? "Keep logging — \(d) more day\(d == 1 ? "" : "s") to unlock your daily focus."
                : "Your daily focus is on its way."
        }
        return "You're all set for today — tap to explore your insights."
    }

    private var fallbackState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("TODAY'S FOCUS")
                    .font(.r(.caption, .bold))
                    .tracking(1.1)
            }
            .foregroundStyle(inkSecondary)

            Text(fallbackHeadline)
                .font(.r(.body, .bold))
                .foregroundStyle(inkPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !insufficientData {
                seeInsightsPill
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floralCard("floral_faded")
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { if !insufficientData { onTap() } }
    }

    // MARK: - Card Content

    private func cardContent(_ card: InsightCard) -> some View {
        let color = card.domain.accentColor

        return VStack(alignment: .leading, spacing: 14) {
            // Top row: domain badge + type badge + dismiss
            HStack {
                domainBadge(card: card, color: color)
                Spacer()
                if !isRedundantTypeBadge(card: card) {
                    typeBadge(card: card, color: color)
                }
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
                .foregroundStyle(inkPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Narrative
            Text(card.narrative)
                .font(.r(.subheadline, .regular))
                .foregroundStyle(inkSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            // Bottom row: progress / sparkline / action
            bottomRow(card: card, color: color)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floralCard(card.domain.floralBackground)
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

    private func isRedundantTypeBadge(card: InsightCard) -> Bool {
        card.domain == .cross && card.type == .correlation
    }

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
        if case .weeklyHydration(let days) = card.chartData, !days.isEmpty {
            weeklyDotsRow(days: days, color: color)
        } else if let progress = extractProgress(from: card) {
            progressRow(progress: progress, color: color)
        } else if case .sparkline(let points) = card.chartData, !points.isEmpty {
            sparklineRow(points: points, color: color)
        } else {
            fallbackRow(color: color)
        }
    }

    // MARK: - Weekly Hydration Dots Row

    private func weeklyDotsRow(days: [HydrationDay], color: Color) -> some View {
        HStack(spacing: 12) {
            // inkSecondary keeps the weekday initials legible on the light floral art.
            WeeklyHydrationDots(days: days, accentColor: color, labelColor: inkSecondary)
                .frame(maxWidth: .infinity)

            if let actionLabel, let onAction {
                nudgeButton(label: actionLabel, icon: actionIcon, color: color, action: onAction)
            }
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
        seeInsightsPill
    }

    /// "See insights" pill with a solid rounded-rectangle background that flips
    /// black (light mode) / white (dark mode), with contrasting text.
    private var seeInsightsPill: some View {
        HStack(spacing: 4) {
            Text("See insights")
                .font(.r(.caption, .semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white : Color.black)
        )
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

// MARK: - Floral Card Background

private extension View {
    /// Lays a light floral illustration behind the card with a leading white
    /// scrim so the dark, left-aligned text stays legible across all 5 images.
    func floralCard(_ imageName: String) -> some View {
        self
            .background {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.82), location: 0.0),
                                .init(color: .white.opacity(0.55), location: 0.45),
                                .init(color: .white.opacity(0.32), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            )
            .appShadow(radius: 12, y: 4)
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
                chartData: .weeklyHydration(days: {
                    let cal = Calendar.current
                    let today = cal.startOfDay(for: Date())
                    let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
                    let sample: [Double] = [1.0, 1.0, 0.5, 1.0, 0.0, 1.0, 0.7]
                    return (0..<7).compactMap { i -> HydrationDay? in
                        guard let date = cal.date(byAdding: .day, value: i, to: weekStart) else { return nil }
                        let isFuture = date > today
                        return HydrationDay(date: date, fraction: isFuture ? 0 : sample[i], isFuture: isFuture)
                    }
                }()),
                priority: 0.9, isLLMGenerated: false, generatedAt: Date(),
                detailSuggestions: ["Keep it up."]
            ),
            isGenerating: false,
            onTap: {}
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
