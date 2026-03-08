import SwiftUI

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
}

struct WellnessRingsCard: View {

    let rings: [WellnessRingItem]
    let completionPercent: Int
    var onTap: () -> Void = {}

    @State private var animate = false

    var body: some View {
        VStack(spacing: 16) {

            // Header row
            HStack {
                Text("Today's Wellness")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                // Completion pill
                Text("\(completionPercent)% Complete")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                    WellnessRingView(ring: ring, animate: animate)
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
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            HapticService.impact(.light)
            onTap()
        }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.15)) {
                animate = true
            }
        }
    }
}

// MARK: - WellnessRingView

private struct WellnessRingView: View {

    let ring: WellnessRingItem
    let animate: Bool

    var body: some View {
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
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }

            VStack(spacing: 2) {
                Text(ring.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(ring.sublabel)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WellnessRingsCard(
        rings: [
            WellnessRingItem(label: "Calories", sublabel: "/ 2000", value: "1420",
                             progress: 0.71, color: .orange, emojiOrSymbol: nil),
            WellnessRingItem(label: "Water", sublabel: "/ 8 cups", value: "5",
                             progress: 0.625, color: .blue, emojiOrSymbol: nil),
            WellnessRingItem(label: "Exercise", sublabel: "/ 45 min", value: "32",
                             progress: 0.71, color: Color(hue: 0.45, saturation: 0.6, brightness: 0.72), emojiOrSymbol: nil),
            WellnessRingItem(label: "Stress", sublabel: "Low", value: "",
                             progress: 0.25, color: Color(hue: 0.76, saturation: 0.55, brightness: 0.78), emojiOrSymbol: "😌")
        ],
        completionPercent: 71
    )
    .padding()
}
