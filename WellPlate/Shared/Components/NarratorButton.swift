import SwiftUI

// MARK: - NarratorButton
//
// Displays as a sparkle icon at rest and an animated waveform when speaking.
// Fires HapticService.narratorStart() on tap. The actual narrative generation
// and speech is delegated to NutritionNarratorService via the onTap closure.

struct NarratorButton: View {

    let isSpeaking: Bool
    let isGenerating: Bool
    let onTap: () -> Void

    @State private var pulsing: Bool = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Glow ring — visible when speaking
                if isSpeaking {
                    Circle()
                        .stroke(Color.orange.opacity(0.25), lineWidth: 6)
                        .scaleEffect(pulsing ? 1.35 : 1.0)
                        .opacity(pulsing ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                            value: pulsing
                        )
                }

                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isSpeaking
                                ? [Color.orange, Color.orange.opacity(0.75)]
                                : [Color(.secondarySystemBackground), Color(.secondarySystemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(
                        color: isSpeaking ? .orange.opacity(0.35) : .clear,
                        radius: 8, x: 0, y: 4
                    )

                // Icon
                Group {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(
                                tint: Color(.tertiaryLabel)
                            ))
                            .scaleEffect(0.75)
                    } else if isSpeaking {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .symbolEffect(.variableColor.iterative, isActive: isSpeaking)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isSpeaking) { _, speaking in
            pulsing = false
            if speaking {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    pulsing = true
                }
            }
        }
    }
}

#Preview("Idle") {
    NarratorButton(isSpeaking: false, isGenerating: false, onTap: {})
        .padding()
}

#Preview("Generating") {
    NarratorButton(isSpeaking: false, isGenerating: true, onTap: {})
        .padding()
}

#Preview("Speaking") {
    NarratorButton(isSpeaking: true, isGenerating: false, onTap: {})
        .padding()
}
