import SwiftUI

// MARK: - DisambiguationChipsView
//
// Surfaced as an overlay in HomeView when MealCoachService returns confidence < 0.6.
// Shows 2–3 food option chips and an "Add as typed" escape hatch (audit fix #8).

struct DisambiguationChipsView: View {

    let question: String
    let options: [FoodOption]
    let rawInput: String
    let onSelect: (FoodOption) -> Void
    let onAddAsTyped: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppColors.brand.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "questionmark.bubble.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.brand)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Did you mean…")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Text(question)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }

                // Option Chips
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        Button(action: {
                            HapticService.selectionChanged()
                            onSelect(option)
                        }) {
                            HStack {
                                Text(option.label)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("~\(option.calorieEstimate) kcal")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppColors.brand)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(AppColors.brand.opacity(0.12))
                                    )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Escape hatch — "Add as typed" (audit fix #8)
                Button(action: {
                    HapticService.impact(.light)
                    onAddAsTyped()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.cursor")
                            .font(.system(size: 13))
                        Text("Add \"\(rawInput)\" as typed")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: -8)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .offset(y: appeared ? 0 : 300)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: appeared)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear { appeared = true }
        .background(
            Color.black.opacity(appeared ? 0.18 : 0)
                .ignoresSafeArea()
                .animation(.easeIn(duration: 0.2), value: appeared)
        )
    }
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        DisambiguationChipsView(
            question: "What kind of pizza?",
            options: [
                FoodOption(label: "Thin-crust pizza slice", calorieEstimate: 220),
                FoodOption(label: "Deep-dish pizza slice", calorieEstimate: 380),
                FoodOption(label: "Frozen pizza slice", calorieEstimate: 310)
            ],
            rawInput: "pizza",
            onSelect: { _ in },
            onAddAsTyped: {}
        )
    }
}
