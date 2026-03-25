import SwiftUI

// MARK: - HydrationCard
// Shows a row of 8 water-glass icons; filled ones are tinted blue.
// The card background animates with a rising water-wave fill as cups are logged.

struct HydrationCard: View {

    @Binding var glassesConsumed: Int
    let totalGlasses: Int
    var cupSizeML: Int = 250
    var onTap: (() -> Void)? = nil

    // MARK: - Wave animation state
    @State private var wavePhase: Double = 0
    @State private var isAnimating: Bool = false

    private var fillFraction: Double {
        totalGlasses > 0 ? min(1.0, Double(glassesConsumed) / Double(totalGlasses)) : 0
    }

    private let waveColor = Color(hue: 0.58, saturation: 0.65, brightness: 0.82)

    var body: some View {
        // ZStack: wave fill on bottom, card content on top
        ZStack {
            // ── Water fill layer ──────────────────────────────────────────────
            GeometryReader { geo in
                WaterWaveShape(fillFraction: fillFraction, wavePhase: wavePhase)
                    .fill(waveColor.opacity(0.13))
                    .animation(
                        .spring(response: 0.75, dampingFraction: 0.68),
                        value: fillFraction
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            // ── Card content ──────────────────────────────────────────────────
            VStack(spacing: 24) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hydration")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        HStack(spacing: 2) {
                            Text("\(glassesConsumed)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hue: 0.58, saturation: 0.65, brightness: 0.75))
                                .contentTransition(.numericText(countsDown: false))
                                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: glassesConsumed)

                            Text("of \(totalGlasses) cups")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text("· \(glassesConsumed * cupSizeML) mL")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(hue: 0.58, saturation: 0.50, brightness: 0.70))
                                .contentTransition(.numericText(countsDown: false))
                                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: glassesConsumed)
                        }
                    }

                    Spacer()

                    if glassesConsumed < totalGlasses {
                        // + button
                        Button {
                            addGlass()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hue: 0.58, saturation: 0.65, brightness: 0.82))
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color(hue: 0.58, saturation: 0.22, brightness: 0.96))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(glassesConsumed >= totalGlasses)
                    }
                }

                // Glass icons
                HStack(spacing: 8) {
                    ForEach(0..<totalGlasses, id: \.self) { index in
                        GlassIcon(isFilled: index < glassesConsumed)
                            .onTapGesture {
                                toggleGlass(at: index)
                            }
                    }
                }
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            startWaveAnimation()
        }
    }

    // MARK: - Wave

    private func startWaveAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        withAnimation(
            .linear(duration: 2.5)
            .repeatForever(autoreverses: false)
        ) {
            wavePhase = .pi * 2
        }
    }

    // MARK: - Actions

    private func addGlass() {
        guard glassesConsumed < totalGlasses else { return }
        HapticService.impact(.light)
        SoundService.play("water_log_sound", ext: "mp3")
        glassesConsumed += 1
    }

    private func toggleGlass(at index: Int) {
        if index < glassesConsumed {
            HapticService.notify(.error)
            glassesConsumed = index
        } else {
            HapticService.impact(.light)
            SoundService.play("water_log_sound", ext: "mp3")
            glassesConsumed = index + 1
        }
    }
}

// MARK: - GlassIcon

private struct GlassIcon: View {
    let isFilled: Bool

    private let filledColor = Color(hue: 0.58, saturation: 0.65, brightness: 0.82)
    private let emptyColor  = Color(hue: 0.58, saturation: 0.15, brightness: 0.88)

    var body: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: 22))
            .foregroundStyle(isFilled ? filledColor : emptyColor)
            .animation(.easeInOut(duration: 0.18), value: isFilled)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    struct Wrap: View {
        @State var glasses = 5
        var body: some View {
            HydrationCard(glassesConsumed: $glasses, totalGlasses: 8)
                .padding()
        }
    }
    return Wrap()
}
