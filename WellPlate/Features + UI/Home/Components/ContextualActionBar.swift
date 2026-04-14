import SwiftUI

// MARK: - ContextualBarState

enum ContextualBarState: Equatable, Hashable {
    case defaultActions
    case logNextMeal(mealLabel: String)
    case goalsCelebration
    case stressActionable(level: String)
}

// MARK: - ContextualActionBar
// Persistent bottom bar replacing DragToLogOverlay.
// Switches content based on ContextualBarState with animated state transitions.

struct ContextualActionBar: View {
    let state: ContextualBarState
    var onLogMeal: () -> Void
    var onAddWater: () -> Void
    var onStressTab: () -> Void
    var onSeeInsight: () -> Void
    var onLogSymptom: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        barContent
            .id(state)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97)))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: state)
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quick Actions")
    }

    // MARK: - Bar Content

    private var barContent: some View {
        HStack(spacing: 12) {
            primaryPill
            Spacer()
            trailingActions
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
                .appShadow(radius: 16, y: -4)
        )
    }

    // MARK: - Primary Pill

    @ViewBuilder
    private var primaryPill: some View {
        switch state {
        case .defaultActions:
            actionPill(icon: "fork.knife", label: "Log Meal", color: AppColors.brand) {
                HapticService.impact(.medium)
                onLogMeal()
            }
        case .logNextMeal(let label):
            actionPill(icon: "fork.knife", label: "Log \(label)", color: AppColors.brand) {
                HapticService.impact(.medium)
                onLogMeal()
            }
        case .goalsCelebration:
            actionPill(icon: "party.popper", label: "All goals met!", color: AppColors.success) {
                onSeeInsight()
            }
        case .stressActionable(let level):
            actionPill(
                icon: "figure.mind.and.body",
                label: "Stress is \(level) — try breathing",
                color: AppColors.warning
            ) {
                onStressTab()
            }
        }
    }

    // MARK: - Action Pill Helper

    private func actionPill(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.r(13, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(label)
    }

    // MARK: - Trailing Actions

    @ViewBuilder
    private var trailingActions: some View {
        switch state {
        case .defaultActions, .logNextMeal:
            HStack(spacing: 8) {
                trailingIconButton(
                    icon: "drop.fill",
                    color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82),
                    label: "Add water"
                ) {
                    HapticService.impact(.light)
                    SoundService.play("water_log_sound", ext: "mp3")
                    onAddWater()
                }
                trailingIconButton(
                    icon: "heart.text.square.fill",
                    color: AppColors.brand.opacity(0.8),
                    label: "Log symptom"
                ) {
                    HapticService.impact(.light)
                    onLogSymptom()
                }
            }
        case .goalsCelebration:
            trailingIconButton(
                icon: "chevron.right",
                color: AppColors.brand,
                label: "See AI insight"
            ) {
                onSeeInsight()
            }
        case .stressActionable:
            trailingIconButton(
                icon: "play.fill",
                color: AppColors.warning,
                label: "Start breathing"
            ) {
                onStressTab()
            }
        }
    }

    // MARK: - Trailing Icon Button Helper

    private func trailingIconButton(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(Circle().fill(color.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(label)
    }
}

// MARK: - Previews

#Preview("Default") {
    ContextualActionBar(
        state: .defaultActions,
        onLogMeal: {}, onAddWater: {},
        onStressTab: {}, onSeeInsight: {}, onLogSymptom: {}
    )
    .padding()
}
