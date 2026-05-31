import SwiftUI

// MARK: - HomeFastingCard
//
// Full-width promo card inviting the user to start an intermittent fast.
// Tapping anywhere (or the "Set up" pill) opens the fasting tracker.

struct HomeFastingCard: View {
    var onSetUp: () -> Void

    var body: some View {
        Button(action: { HapticService.impact(.light); onSetUp() }) {
            HStack(spacing: 14) {
                Image("fasting_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color(.tertiarySystemFill).opacity(0.6))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Start a fast")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Track its effect on stress")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("Set up")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(HomePalette.accent))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.card)
                    .appShadow(radius: 15, y: 5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start a fast. Track its effect on stress.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#Preview("Home Fasting Card") {
    HomeFastingCard(onSetUp: {})
        .padding(16)
        .background(HomePalette.background)
}
