import SwiftUI

// MARK: - LiquidGaugeTile
// A tall card with an animated liquid-fill background that rises with progress.
// Water variant uses WaterWaveShape (sine wave); coffee uses a smooth gradient fill.

struct LiquidGaugeTile: View {

    enum Style {
        case water
        case coffee
    }

    let style: Style
    let emoji: String
    let label: String
    let count: Int
    let goal: Int
    let subtitle: String?
    let deltaText: String?
    let deltaPositive: Bool
    let showIncrementButton: Bool
    var onTap: () -> Void
    var onIncrement: (() -> Void)?

    // MARK: - Wave state (water only)

    @State private var wavePhase: Double = 0
    @State private var isAnimating = false

    // MARK: - Derived

    private var fillFraction: Double {
        goal > 0 ? min(1.0, Double(count) / Double(goal)) : 0
    }

    private var accentColor: Color {
        switch style {
        case .water:  Color(hue: 0.58, saturation: 0.68, brightness: 0.82)
        case .coffee: Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
        }
    }

    private var fillColorLight: Color {
        switch style {
        case .water:  accentColor.opacity(0.12)
        case .coffee: Color(hue: 0.08, saturation: 0.35, brightness: 0.92).opacity(0.55)
        }
    }

    private var accentBg: Color {
        switch style {
        case .water:  Color(hue: 0.58, saturation: 0.18, brightness: 0.96)
        case .coffee: Color(hue: 0.08, saturation: 0.18, brightness: 0.96)
        }
    }

    private var isComplete: Bool { count >= goal }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Liquid fill layer ──────────────────────────────────
            liquidFill
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .animation(.spring(response: 0.7, dampingFraction: 0.7), value: fillFraction)

            // ── Card content ──────────────────────────────────────
            VStack(spacing: 0) {
                // Top section: label + delta
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(emoji)
                            .font(.system(size: 24))

                        Spacer()

                        if let delta = deltaText {
                            deltaBadge(delta)
                        }
                    }

                    Text(label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Center: big count
                VStack(spacing: 2) {
                    Text("\(count)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: count)

                    Text("of \(goal) cups")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(accentColor.opacity(0.8))
                        .padding(.top, 2)
                }

                Spacer()

                // Bottom: + button
                if showIncrementButton {
                    Button {
                        HapticService.impact(.light)
                        onIncrement?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("Add")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            Capsule()
                                .fill(accentBg)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    // Goal reached indicator
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Done")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppColors.success)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        Capsule()
                            .fill(AppColors.success.opacity(0.12))
                    )
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 14, y: 5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { onTap() }
        .onAppear {
            if style == .water { startWaveAnimation() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label): \(count) of \(goal)")
    }

    // MARK: - Liquid Fill

    @ViewBuilder
    private var liquidFill: some View {
        switch style {
        case .water:
            WaterWaveShape(fillFraction: fillFraction, wavePhase: wavePhase)
                .fill(fillColorLight)

        case .coffee:
            // Smooth rising rectangle with a gradient
            GeometryReader { geo in
                let height = geo.size.height * fillFraction
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            Color(hue: 0.08, saturation: 0.45, brightness: 0.88).opacity(0.25),
                            Color(hue: 0.08, saturation: 0.55, brightness: 0.78).opacity(0.18)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: height)
                }
            }
        }
    }

    // MARK: - Delta Badge

    private func deltaBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(deltaPositive ? AppColors.success : AppColors.warning)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((deltaPositive ? AppColors.success : AppColors.warning).opacity(0.12))
            )
    }

    // MARK: - Wave Animation

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

#Preview("Liquid Gauge Tiles") {
    HStack(spacing: 10) {
        LiquidGaugeTile(
            style: .water,
            emoji: "💧",
            label: "Water",
            count: 5,
            goal: 8,
            subtitle: "1250 mL",
            deltaText: "Δ +1",
            deltaPositive: true,
            showIncrementButton: true,
            onTap: {},
            onIncrement: {}
        )

        LiquidGaugeTile(
            style: .coffee,
            emoji: "☕",
            label: "Coffee",
            count: 2,
            goal: 4,
            subtitle: "160mg caffeine",
            deltaText: "Δ -1",
            deltaPositive: false,
            showIncrementButton: true,
            onTap: {},
            onIncrement: {}
        )
    }
    .padding()
}
