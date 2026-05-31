import SwiftUI

// MARK: - HomeFocusCard
//
// Brand-blue hero card at the top of the dashboard. Surfaces the day's top
// insight ("Today's Focus") with a "See why →" pill that opens the Insights
// hub. Handles loading + insufficient-data states so it never shows empty.

struct HomeFocusCard: View {
    let insight: InsightCard?
    let isGenerating: Bool
    let insufficientData: Bool
    let daysRemaining: Int
    var onSeeWhy: () -> Void

    // MARK: - Derived

    private var headlineText: String {
        if let insight { return insight.headline }
        if insufficientData {
            let d = max(0, daysRemaining)
            if d > 0 {
                return "Keep logging — \(d) more day\(d == 1 ? "" : "s") to unlock your daily focus."
            }
            return "Your daily focus is on its way."
        }
        return "You're all set for today — tap to explore your insights."
    }

    /// Pill only makes sense when there's a real insight (or enough data) to dig into.
    private var showPill: Bool { insight != nil || !insufficientData }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Eyebrow
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Text("TODAY'S FOCUS")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(.white.opacity(0.9))

            // Headline / state copy
            if isGenerating {
                loadingLines
            } else {
                Text(headlineText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // See why pill
            if showPill && !isGenerating {
                Button {
                    HapticService.impact(.light)
                    onSeeWhy()
                } label: {
                    HStack(spacing: 6) {
                        Text("See why")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(focusBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .appShadow(radius: 15, y: 5)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Background (brand fill + soft decorative circles)

    private var focusBackground: some View {
        ZStack {
            HomePalette.hero
            GeometryReader { geo in
                let w = geo.size.width
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .offset(x: w - 130, y: -70)
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 130, height: 130)
                    .offset(x: w - 50, y: 60)
            }
        }
    }

    // MARK: - Loading

    private var loadingLines: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 5)
                .fill(.white.opacity(0.25))
                .frame(height: 16)
            RoundedRectangle(cornerRadius: 5)
                .fill(.white.opacity(0.25))
                .frame(height: 16)
                .frame(maxWidth: 200)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview("Home Focus Card") {
    VStack(spacing: 16) {
        HomeFocusCard(
            insight: InsightCard(
                id: UUID(), type: .correlation, domain: .stress,
                headline: "You're calmest in the evenings — protect focus work after 5pm.",
                narrative: "",
                chartData: .sparkline(points: [40, 35, 30, 25, 18, 15]),
                priority: 0.9, isLLMGenerated: true, generatedAt: Date(),
                detailSuggestions: []
            ),
            isGenerating: false, insufficientData: false, daysRemaining: 0, onSeeWhy: {}
        )
        HomeFocusCard(insight: nil, isGenerating: false, insufficientData: true, daysRemaining: 2, onSeeWhy: {})
        HomeFocusCard(insight: nil, isGenerating: true, insufficientData: false, daysRemaining: 0, onSeeWhy: {})
    }
    .padding(16)
    .background(HomePalette.background)
}
