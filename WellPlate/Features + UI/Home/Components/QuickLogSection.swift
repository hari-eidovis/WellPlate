import SwiftUI

// MARK: - QuickLogSection
// 2×2 grid of tappable coloured tiles for rapid logging actions.

struct QuickLogItem: Identifiable {
    let id = UUID()
    let label: String
    let symbol: String
    let tint: Color
    let background: Color
    let action: () -> Void
}

struct QuickLogSection: View {

    let showsMoodLog: Bool
    let onLogMeal: () -> Void
    let onLogWater: () -> Void
    let onExercise: () -> Void
    let onMood: () -> Void

    private var items: [QuickLogItem] {
        var baseItems: [QuickLogItem] = [
            QuickLogItem(
                label: "Log Meal",
                symbol: "fork.knife",
                tint: Color(hue: 0.07, saturation: 0.72, brightness: 0.92),
                background: Color(hue: 0.07, saturation: 0.30, brightness: 0.98),
                action: onLogMeal
            ),
            QuickLogItem(
                label: "Log Water",
                symbol: "drop.fill",
                tint: Color(hue: 0.58, saturation: 0.68, brightness: 0.88),
                background: Color(hue: 0.58, saturation: 0.22, brightness: 0.97),
                action: onLogWater
            )
        ]

        if showsMoodLog {
            baseItems.append(
                QuickLogItem(
                    label: "Mood",
                    symbol: "face.smiling",
                    tint: Color(hue: 0.76, saturation: 0.45, brightness: 0.78),
                    background: Color(hue: 0.76, saturation: 0.18, brightness: 0.97),
                    action: onMood
                )
            )
        }

        return baseItems
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Log")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { item in
                    QuickLogTile(item: item)
                }
            }
        }
    }
}

// MARK: - QuickLogTile

private struct QuickLogTile: View {

    let item: QuickLogItem

    @State private var isPressed = false

    var body: some View {
        Button {
            HapticService.impact(.light)
            SoundService.playConfirmation()
            item.action()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.tint.opacity(0.18))
                        .frame(width: 42, height: 42)

                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(item.tint)
                }

                Text(item.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(item.background)
                    .shadow(color: item.tint.opacity(0.12), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        ._onButtonGesture(pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Preview

#Preview {
    QuickLogSection(
        showsMoodLog: true,
        onLogMeal: {},
        onLogWater: {},
        onExercise: {},
        onMood: {}
    )
    .padding()
}
