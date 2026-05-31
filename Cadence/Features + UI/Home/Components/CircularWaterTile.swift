import SwiftUI

// MARK: - CircularLiquidTile
// Circular log tile inspired by the "Water filling up" Lottie:
// two layered sine waves (light + dark variant of the liquid color) sweep
// continuously inside a circle, fill height tied to progress. Used for
// both water and coffee on the home screen.

struct CircularLiquidTile: View {

    enum Style {
        case water
        case coffee
    }

    let style: Style
    let emoji: String
    let count: Int
    let goal: Int
    let unitLabel: String              // e.g. "cups"
    let subtitleText: String?          // e.g. "1250 mL" or "160mg caffeine"
    var onTap: () -> Void
    var onIncrement: () -> Void

    @State private var wavePhase: Double = 0
    @State private var isAnimating = false

    private var fillFraction: Double {
        goal > 0 ? min(1.0, Double(count) / Double(goal)) : 0
    }
    private var isComplete: Bool { count >= goal }

    // Liquid colors per style
    private var darkLiquid: Color {
        switch style {
        case .water:  Color(hue: 0.58, saturation: 0.65, brightness: 0.82)
        case .coffee: Color(hue: 0.08, saturation: 0.78, brightness: 0.45)
        }
    }
    private var lightLiquid: Color {
        switch style {
        case .water:  Color(hue: 0.58, saturation: 0.22, brightness: 0.96)
        case .coffee: Color(hue: 0.08, saturation: 0.55, brightness: 0.78)
        }
    }
    private var accentColor: Color {
        switch style {
        case .water:  darkLiquid
        case .coffee: Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
        }
    }

    var body: some View {
        ZStack {
            // ── Water fill (two waves) masked to circle ────────────
            ZStack {
                WaterWaveShape(fillFraction: fillFraction, wavePhase: wavePhase)
                    .fill(darkLiquid.opacity(0.9))

                WaterWaveShape(
                    fillFraction: fillFraction,
                    wavePhase: wavePhase + .pi
                )
                .fill(lightLiquid.opacity(0.7))
            }
            .mask(Circle())
            .animation(.spring(response: 0.7, dampingFraction: 0.7), value: fillFraction)

            // ── Center content ─────────────────────────────────────
            VStack(spacing: 2) {
                Text(emoji)
                    .font(.system(size: 22))

                Text("\(count)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: count)

                Text("of \(goal) \(unitLabel)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor.opacity(0.85))

                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(textColor.opacity(0.75))
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: count)
                }
            }
            .allowsHitTesting(false)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 210)
        .contentShape(Circle())
        .onTapGesture { onTap() }
        .overlay(alignment: .bottomTrailing) { incrementBadge }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(style == .water ? "Water" : "Coffee"): \(count) of \(goal) \(unitLabel)")
        .onAppear { startWaveAnimation() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var incrementBadge: some View {
        Group {
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.success)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(AppColors.card)
                    )
                    .appShadow(radius: 6, y: 2)
            } else {
                Button {
                    HapticService.impact(.light)
                    onIncrement()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(AppColors.card)
                        )
                        .appShadow(radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
    }

    // White text once the fill rises past the center, otherwise primary.
    private var textColor: Color {
        fillFraction > 0.55 ? .white : .primary
    }

    // MARK: - Animation

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
}

// MARK: - Preview

#Preview("Circular Liquid Tiles") {
    struct Wrap: View {
        @State var water = 5
        @State var coffee = 2
        var body: some View {
            HStack(spacing: 10) {
                CircularLiquidTile(
                    style: .water,
                    emoji: "💧",
                    count: water,
                    goal: 8,
                    unitLabel: "cups",
                    subtitleText: "\(water * 250) mL",
                    onTap: {},
                    onIncrement: { water += 1 }
                )

                CircularLiquidTile(
                    style: .coffee,
                    emoji: "☕",
                    count: coffee,
                    goal: 4,
                    unitLabel: "cups",
                    subtitleText: "\(coffee * 80)mg caffeine",
                    onTap: {},
                    onIncrement: { coffee += 1 }
                )
            }
            .padding()
        }
    }
    return Wrap()
}
