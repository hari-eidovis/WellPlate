import SwiftUI

// MARK: - QuickStatTile
// A single tile with split touch zones:
//   - Body area (onTapGesture) → navigate to detail
//   - Plus button → increment the tracked value

struct QuickStatTile: View {
    let emoji: String
    let label: String
    let value: String
    let deltaText: String?
    let deltaPositive: Bool
    let showIncrementButton: Bool
    var onTap: () -> Void
    var onIncrement: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(emoji + " " + label)
                        .font(.r(11, .semibold))
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.r(15, .semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    if let delta = deltaText {
                        deltaBadge(delta, positive: deltaPositive)
                    }
                }

                Spacer()

                if showIncrementButton {
                    plusButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onTap() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Delta Badge

    private func deltaBadge(_ text: String, positive: Bool) -> some View {
        Text(text)
            .font(.r(10, .semibold))
            .foregroundStyle(positive ? AppColors.success : AppColors.warning)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((positive ? AppColors.success : AppColors.warning).opacity(0.12))
            )
    }

    // MARK: - Plus Button

    private var plusButton: some View {
        Button {
            HapticService.impact(.light)
            onIncrement?()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.brand)
                .frame(width: 36, height: 36)
                .background(Circle().fill(AppColors.brand.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Add one \(label)")
    }
}

// MARK: - Preview

#Preview {
    QuickStatTile(
        emoji: "💧", label: "Water", value: "5 / 8",
        deltaText: "Δ +1", deltaPositive: true,
        showIncrementButton: true,
        onTap: {}, onIncrement: {}
    )
    .padding()
}
