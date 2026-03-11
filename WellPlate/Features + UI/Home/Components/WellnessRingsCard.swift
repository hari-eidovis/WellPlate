import SwiftUI

// MARK: - Ring Destination

enum WellnessRingDestination: Identifiable {
    case calories, water, exercise, stress
    var id: Self { self }
}

// MARK: - WellnessRingsCard
// Shows four animated circular progress rings: Calories, Water, Exercise, Stress.

struct WellnessRingItem: Identifiable {
    let id = UUID()
    let label: String
    let sublabel: String
    let value: String
    let progress: CGFloat        // 0.0 – 1.0
    let color: Color
    let emojiOrSymbol: String?   // Optional emoji shown instead of value for Stress
    let destination: WellnessRingDestination
}

struct WellnessRingsCard: View {

    let rings: [WellnessRingItem]
    let completionPercent: Int
    var onRingTap: (WellnessRingDestination) -> Void = { _ in }

    @State private var animate = false

    var body: some View {
        VStack(spacing: 16) {

            // Header row
            HStack {

                Spacer()

                Text("Tap a ring to explore")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                    )
            }

            // Rings row
            HStack(spacing: 0) {
                ForEach(rings) { ring in
                    WellnessRingButton(ring: ring, animate: animate) {
                        HapticService.impact(.light)
                        onRingTap(ring.destination)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.15)) {
                animate = true
            }
        }
    }
}

// MARK: - WellnessRingButton

private struct WellnessRingButton: View {

    let ring: WellnessRingItem
    let animate: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    // Track
                    Circle()
                        .stroke(ring.color.opacity(0.15), lineWidth: 7)
                        .frame(width: 64, height: 64)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: animate ? ring.progress : 0)
                        .stroke(
                            ring.color,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 64, height: 64)
                        .animation(
                            .spring(response: 1.1, dampingFraction: 0.72).delay(0.15),
                            value: animate
                        )

                    // Center: emoji or numeric value
                    if let emoji = ring.emojiOrSymbol {
                        Text(emoji)
                            .font(.system(size: 22))
                    } else {
                        Text(ring.value)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                }

                VStack(spacing: 2) {
                    Text(ring.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(ring.sublabel)
                        .font(.system(size: 8, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(RingButtonStyle(color: ring.color))
    }
}

// MARK: - RingButtonStyle

private struct RingButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    WellnessRingsCard(
        rings: [
            WellnessRingItem(label: "Calories", sublabel: "/ 2000", value: "1420",
                             progress: 0.71, color: AppColors.brand, emojiOrSymbol: nil, destination: .calories),
            WellnessRingItem(label: "Water", sublabel: "/ 8 cups", value: "5",
                             progress: 0.625, color: .blue, emojiOrSymbol: nil, destination: .water),
            WellnessRingItem(label: "Exercise", sublabel: "/ 45 min", value: "32",
                             progress: 0.71, color: Color(hue: 0.45, saturation: 0.6, brightness: 0.72), emojiOrSymbol: nil, destination: .exercise),
            WellnessRingItem(label: "Stress", sublabel: "Low", value: "",
                             progress: 0.25, color: Color(hue: 0.76, saturation: 0.55, brightness: 0.78), emojiOrSymbol: "😌", destination: .stress)
        ],
        completionPercent: 71
    )
    .padding()
}
