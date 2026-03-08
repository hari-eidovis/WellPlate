import SwiftUI

// MARK: - StressInsightCard
// Compact suggestion card: stress level label, tip, and a tappable Start button.

struct StressInsightCard: View {

    let stressLevel: String      // e.g. "Low", "Moderate", "High"
    let tip: String              // Short suggestion string
    let onStart: () -> Void

    @State private var isPressed = false

    private var iconBackground: Color {
        switch stressLevel.lowercased() {
        case "low":      return Color(hue: 0.76, saturation: 0.18, brightness: 0.97)
        case "moderate": return Color(hue: 0.10, saturation: 0.22, brightness: 0.98)
        default:         return Color(hue: 0.00, saturation: 0.20, brightness: 0.97) // High → reddish
        }
    }

    private var iconTint: Color {
        switch stressLevel.lowercased() {
        case "low":      return Color(hue: 0.76, saturation: 0.50, brightness: 0.72)
        case "moderate": return Color(hue: 0.10, saturation: 0.75, brightness: 0.88)
        default:         return Color(hue: 0.00, saturation: 0.72, brightness: 0.82)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 52, height: 52)

                Image(systemName: "wind")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(iconTint)
            }

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text("Stress Level: \(stressLevel)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(tip)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Start button
            Button(action: {
                HapticService.impact(.light)
                onStart()
            }) {
                Text("Start")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(iconTint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(iconBackground)
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isPressed)
            ._onButtonGesture(pressing: { isPressed = $0 }, perform: {})
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        StressInsightCard(
            stressLevel: "Low",
            tip: "Try a 5-min breathing exercise to stay centered 🧘",
            onStart: {}
        )
        StressInsightCard(
            stressLevel: "Moderate",
            tip: "A short walk can help reset your focus 🌿",
            onStart: {}
        )
    }
    .padding()
}
