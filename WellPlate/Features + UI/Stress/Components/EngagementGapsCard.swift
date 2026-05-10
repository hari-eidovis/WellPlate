import SwiftUI
import SwiftData

/// Surfaces active engagement gaps (no_mood / no_food / no_water / low_steps /
/// no_reflection) with one-tap CTAs that route the user to the appropriate
/// logger. Visible only when `viewModel.engagementPenaltyValue > 0`.
struct EngagementGapsCard: View {
    @ObservedObject var viewModel: StressViewModel
    @EnvironmentObject var tabSelector: TabSelector
    @Binding var activeSheet: StressSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(.orange)
                Text("Quick wins")
                    .font(.r(.headline, .semibold))
                Spacer()
                Text("+\(Int(viewModel.engagementPenaltyValue.rounded())) stress")
                    .font(.r(.caption, .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }

            ForEach(activeGaps, id: \.self) { gap in
                gapRow(gap)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.88))
                .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
        )
    }

    // MARK: - Gap definition

    private enum Gap: Hashable {
        case mood, food, water, steps, reflection

        var label: String {
            switch self {
            case .mood:       return "Log your mood"
            case .food:       return "Log a meal"
            case .water:      return "Log water"
            case .steps:      return "Track activity"
            case .reflection: return "Add a reflection"
            }
        }

        var icon: String {
            switch self {
            case .mood:       return "face.smiling"
            case .food:       return "fork.knife"
            case .water:      return "drop.fill"
            case .steps:      return "figure.walk"
            case .reflection: return "pencil.and.outline"
            }
        }
    }

    private var activeGaps: [Gap] {
        // Derive which gaps fire from the available factor / mood data.
        var gaps: [Gap] = []
        let allFactors = viewModel.allFactors
        if !allFactors.contains(where: { $0.title == "Mood" && $0.hasValidData }) {
            gaps.append(.mood)
        }
        if !allFactors.contains(where: { $0.title == "Diet" && $0.hasValidData }) {
            gaps.append(.food)
        }
        if !allFactors.contains(where: { $0.title == "Hydration" && $0.hasValidData }) {
            gaps.append(.water)
        }
        // For steps gap we use the current exerciseFactor data marker
        if !viewModel.exerciseFactor.hasValidData {
            gaps.append(.steps)
        }
        return gaps
    }

    @ViewBuilder
    private func gapRow(_ gap: Gap) -> some View {
        Button {
            HapticService.impact(.light)
            handleTap(gap)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: gap.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppColors.brand.opacity(0.12)))
                Text(gap.label)
                    .font(.r(.subheadline, .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func handleTap(_ gap: Gap) {
        switch gap {
        case .mood:
            activeSheet = .mood
        case .food:
            tabSelector.switchTo(.home, andPresent: .foodLog)
        case .water:
            tabSelector.switchTo(.home, andPresent: .water)
        case .steps:
            tabSelector.switchTo(.home)
        case .reflection:
            activeSheet = .mood
        }
    }
}
