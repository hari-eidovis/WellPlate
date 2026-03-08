import SwiftUI

// MARK: - MoodOption

enum MoodOption: Int, CaseIterable, Identifiable {
    case awful = 0, bad, okay, good, great

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .awful: "😢"
        case .bad:   "😕"
        case .okay:  "😐"
        case .good:  "😊"
        case .great: "🤩"
        }
    }

    var label: String {
        switch self {
        case .awful: "Awful"
        case .bad:   "Bad"
        case .okay:  "Okay"
        case .good:  "Good"
        case .great: "Great"
        }
    }

    /// Accent color used for the selection ring and glow.
    var accentColor: Color {
        switch self {
        case .awful: Color(hue: 0.00, saturation: 0.72, brightness: 0.85) // red
        case .bad:   Color(hue: 0.07, saturation: 0.72, brightness: 0.95) // orange
        case .okay:  Color(hue: 0.14, saturation: 0.65, brightness: 0.98) // amber
        case .good:  Color(hue: 0.38, saturation: 0.58, brightness: 0.82) // green
        case .great: Color(hue: 0.56, saturation: 0.72, brightness: 0.92) // teal-blue
        }
    }
}

// MARK: - MoodCheckInCard

/// Drop-in card component. Bind `selectedMood` to observe the user's pick.
struct MoodCheckInCard: View {

    @Binding var selectedMood: MoodOption?

    /// Called when the user confirms their mood (tap on already-selected item).
    var onConfirm: ((MoodOption) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("How are you feeling today?")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Tap to check in with yourself")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Mood pills
            HStack(spacing: 0) {
                ForEach(MoodOption.allCases) { mood in
                    MoodPill(
                        mood: mood,
                        isSelected: selectedMood == mood
                    ) {
                        handleTap(mood)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.001)) // transparent — tinted by gradient below
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.94, green: 0.91, blue: 0.97),
                            Color(red: 0.96, green: 0.93, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
    }

    // MARK: Private

    private func handleTap(_ mood: MoodOption) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
            if selectedMood == mood {
                // Double-tap → confirm
                onConfirm?(mood)
            } else {
                selectedMood = mood
            }
        }
    }
}

// MARK: - MoodPill

private struct MoodPill: View {

    let mood: MoodOption
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var didBounce = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Selection ring + glow
                if isSelected {
                    Circle()
                        .stroke(mood.accentColor.opacity(0.45), lineWidth: 2.5)
                        .frame(width: 54, height: 54)
                        .shadow(color: mood.accentColor.opacity(0.4), radius: 8, x: 0, y: 0)
                        .transition(.scale.combined(with: .opacity))
                }

                // Frosted pill background
                Circle()
                    .fill(
                        isSelected
                            ? mood.accentColor.opacity(0.12)
                            : Color(uiColor: .systemBackground).opacity(0.6)
                    )
                    .frame(width: 50, height: 50)

                // Emoji
                Text(mood.emoji)
                    .font(.system(size: 28))
                    .scaleEffect(isPressed ? 0.80 : (isSelected ? 1.18 : 1.0))
                    .rotationEffect(.degrees(isSelected ? (didBounce ? 0 : -12) : 0))
                    .animation(
                        isSelected
                            ? .spring(response: 0.32, dampingFraction: 0.55)
                            : .spring(response: 0.3, dampingFraction: 0.7),
                        value: isSelected
                    )
                    .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isPressed)
            }

            Text(mood.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isSelected ? mood.accentColor : .secondary)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            triggerBounce()
            onTap()
        }
        ._onButtonGesture(pressing: { pressing in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
        .onChange(of: isSelected) { _, selected in
            if selected { triggerBounce() }
        }
    }

    private func triggerBounce() {
        didBounce = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                didBounce = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Mood Check-In") {
    struct PreviewWrapper: View {
        @State private var mood: MoodOption? = nil
        var body: some View {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                MoodCheckInCard(selectedMood: $mood) { confirmed in
                    print("Confirmed: \(confirmed.label)")
                }
                .padding(.horizontal, 16)
            }
        }
    }
    return PreviewWrapper()
}
