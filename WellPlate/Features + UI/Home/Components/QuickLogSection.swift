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

    let onLogMeal: () -> Void
    let onLogWater: () -> Void
    let onExercise: () -> Void
    let onMood: () -> Void

    private var items: [QuickLogItem] {
        [
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
            ),
            QuickLogItem(
                label: "Exercise",
                symbol: "figure.run",
                tint: Color(hue: 0.40, saturation: 0.58, brightness: 0.72),
                background: Color(hue: 0.40, saturation: 0.22, brightness: 0.96),
                action: onExercise
            ),
            QuickLogItem(
                label: "Mood",
                symbol: "face.smiling",
                tint: Color(hue: 0.76, saturation: 0.45, brightness: 0.78),
                background: Color(hue: 0.76, saturation: 0.18, brightness: 0.97),
                action: onMood
            )
        ]
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

    // Press-scale state (existing)
    @State private var isPressed = false

    // Confirmation animation state
    @State private var bounceSymbol   = false
    @State private var showCheck      = false
    @State private var showIncrement  = false
    @State private var incrementOffset: CGFloat = 0
    @State private var incrementOpacity: Double = 0

    var body: some View {
        Button {
            HapticService.impact(.light)
            item.action()
            runConfirmation()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    // Icon container
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.tint.opacity(0.18))
                            .frame(width: 42, height: 42)

                        // Primary icon — bounces on tap
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(item.tint)
                            .symbolEffect(.bounce, value: bounceSymbol)

                        // Checkmark flash overlay
                        if showCheck {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(item.tint)
                                .transition(
                                    .scale(scale: 0.4)
                                    .combined(with: .opacity)
                                )
                        }
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

                // Floating "+1" counter
                if showIncrement {
                    Text("+1")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(item.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(item.tint.opacity(0.14))
                        )
                        .offset(y: incrementOffset)
                        .opacity(incrementOpacity)
                        .padding(.top, 6)
                        .padding(.trailing, 10)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        ._onButtonGesture(pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    // MARK: - Animation Sequence

    private func runConfirmation() {
        // 1. Bounce the icon symbol
        bounceSymbol.toggle()

        // 2. Flash checkmark for 450 ms
        withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) {
            showCheck = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.18)) {
                showCheck = false
            }
        }

        // 3. Float "+1" upward and fade out
        showIncrement  = true
        incrementOffset  = 0
        incrementOpacity = 0

        withAnimation(.easeOut(duration: 0.15)) {
            incrementOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.1)) {
            incrementOffset  = -28
        }
        withAnimation(.easeIn(duration: 0.25).delay(0.35)) {
            incrementOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            showIncrement  = false
            incrementOffset  = 0
        }
    }
}

// MARK: - Preview

#Preview {
    QuickLogSection(
        onLogMeal: {},
        onLogWater: {},
        onExercise: {},
        onMood: {}
    )
    .padding()
}
