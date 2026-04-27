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
        case .defaultActions, .logNextMeal:
            symptomPill {
                HapticService.impact(.light)
                onLogSymptom()
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

    private func mealPill(label: String, action: @escaping () -> Void) -> some View {
        MealBowlButton(label: label, action: action)
    }

    private func symptomPill(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "pills.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Symptom")
                    .font(.r(13, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Log symptom")
    }

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
        case .defaultActions:
            mealPill(label: "Log Meal") {
                HapticService.impact(.medium)
                onLogMeal()
            }
        case .logNextMeal(let label):
            mealPill(label: "Log \(label)") {
                HapticService.impact(.medium)
                onLogMeal()
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

// MARK: - Meal Bowl Button

private struct MealBowlButton: View {
    let label: String
    let action: () -> Void

    @State private var bob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image("bowl")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.32), radius: 8, x: 2, y: 6)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.black))
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                        .offset(x: -2, y: 6)
                }
                .offset(x: 8, y: bob ? -14 : -8)
                .rotationEffect(.degrees(bob ? 2 : -2), anchor: .bottom)
        }
        .buttonStyle(.plain)
        .frame(width: 88, height: 52, alignment: .trailing)
        .accessibilityLabel(label)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                bob = true
            }
        }
    }
}

// MARK: - Previews

#Preview("Default") {
    ContextualActionBar(
        state: .defaultActions,
        onLogMeal: {},
        onStressTab: {}, onSeeInsight: {}, onLogSymptom: {}
    )
    .padding()
}
