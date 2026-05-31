//
//  StressCelebrationOverlay.swift
//  Cadence
//
//  Global overlay shown when the stress score shifts sharply during a session.
//  Two flavors driven by `StressEventKind`:
//    • `.drop` — gentle cream confetti + encouraging copy when stress falls 8+ pts.
//    • `.rise` — soft breathing ring + grounding copy when stress climbs 7+ pts.
//  Hosted globally by `CelebrationWindowPresenter` so it can appear over any
//  tab or sheet.
//
//  Visual language: Claude-inspired minimalism. Warm neutral surfaces
//  (Pampas / Cloudy) with a single Crail accent used sparingly per kind.
//

import SwiftUI

// MARK: - Event Model

enum StressEventKind: Equatable {
    case drop
    case rise
}

struct StressCelebrationEvent: Identifiable, Equatable {
    let id: UUID
    let kind: StressEventKind
    let magnitude: Int
    let previousScore: Double
    let newScore: Double
    let message: String

    init(kind: StressEventKind, magnitude: Int, previousScore: Double, newScore: Double) {
        self.id = UUID()
        self.kind = kind
        self.magnitude = magnitude
        self.previousScore = previousScore
        self.newScore = newScore
        self.message = StressCelebrationMessages.random(forKind: kind, magnitude: magnitude)
    }
}

// MARK: - Copy

enum StressCelebrationMessages {
    private static let dropLines: [String] = [
        "Boom! Stress just took a nosedive.",
        "Yesss — that's a serious vibe shift.",
        "Look at you go! Stress is melting.",
        "Crushing it. Keep that energy.",
        "Big win — your body's thanking you.",
        "On a roll! Calm mode activated.",
        "Glow-up unlocked. Stress fell hard.",
        "Smooth move — stress is on the run.",
        "Heck yes! That's how it's done.",
        "You're winning the day."
    ]

    private static let riseLines: [String] = [
        "Heads up — stress just spiked.",
        "Whoa, your stress climbed fast.",
        "Pause for a beat. Big jump detected.",
        "Stress is rising — give yourself a moment.",
        "Tension's creeping in. Time to breathe.",
        "Your body's on alert. Slow it down.",
        "Quick spike — let's reset before it sticks.",
        "Stress just escalated. You've got this.",
        "Sharp rise noticed. A breath can help.",
        "Stress is up. Step back and steady yourself."
    ]

    static func random(forKind kind: StressEventKind, magnitude: Int) -> String {
        let lines: [String]
        switch kind {
        case .drop: lines = dropLines
        case .rise: lines = riseLines
        }
        return lines.randomElement() ?? fallback(forKind: kind, magnitude: magnitude)
    }

    private static func fallback(forKind kind: StressEventKind, magnitude: Int) -> String {
        switch kind {
        case .drop: return "Stress dropped \(magnitude) points!"
        case .rise: return "Stress rose \(magnitude) points."
        }
    }
}

// MARK: - Palette (Claude-inspired)

private enum ClaudePalette {
    /// Terracotta — the one saturated accent. Used once per overlay (CTA or headline).
    static let crail  = Color(hex: "C15F3C")
    /// Warm gray — borders, dividers, secondary surfaces.
    static let cloudy = Color(hex: "B1ADA1")
    /// Cream — primary soft surface for badges and card warmth.
    static let pampas = Color(hex: "F4F3EE")
}

private struct OverlayPalette {
    let badgeFill: Color
    let badgeStroke: Color
    let iconColor: Color
    let cta: Color
    let ctaText: Color
    let headlineColor: Color
    let confetti: [Color]
    let icon: String
    let ctaTitle: String
    let sign: String
    let useWarningPulse: Bool

    /// Drop: cream badge, neutral headline, Crail reserved for the CTA.
    static let drop = OverlayPalette(
        badgeFill:     ClaudePalette.pampas,
        badgeStroke:   ClaudePalette.cloudy.opacity(0.35),
        iconColor:     ClaudePalette.crail,
        cta:           ClaudePalette.crail,
        ctaText:       .white,
        headlineColor: .primary,
        confetti: [
            ClaudePalette.pampas,
            ClaudePalette.cloudy.opacity(0.7),
            ClaudePalette.crail.opacity(0.5),
            Color(hex: "DED9CF")
        ],
        icon: "arrow.down",
        ctaTitle: "Keep it up",
        sign: "−",
        useWarningPulse: false
    )

    /// Rise: tinted Crail badge + Crail headline (this is the alert), calming
    /// `.primary` CTA so the resolution feels steady rather than urgent.
    static let rise = OverlayPalette(
        badgeFill:     ClaudePalette.crail.opacity(0.12),
        badgeStroke:   ClaudePalette.crail.opacity(0.35),
        iconColor:     ClaudePalette.crail,
        cta:           .primary,
        ctaText:       Color(.systemBackground),
        headlineColor: ClaudePalette.crail,
        confetti: [],
        icon: "arrow.up",
        ctaTitle: "Take a breath",
        sign: "+",
        useWarningPulse: true
    )
}

// MARK: - Overlay

struct StressCelebrationOverlay: View {
    let event: StressCelebrationEvent
    let onDismiss: () -> Void

    @State private var cardAppeared = false
    @State private var confettiActive = false
    @State private var haloScale: CGFloat = 0.6
    @State private var haloOpacity: Double = 0
    @State private var displayedMagnitude: Int = 0
    @State private var warningPulse: CGFloat = 0.9

    private static let autoDismissAfter: TimeInterval = 4.0

    private var palette: OverlayPalette {
        switch event.kind {
        case .drop: return .drop
        case .rise: return .rise
        }
    }

    var body: some View {
        ZStack {
            // Tap-anywhere-to-dismiss scrim. Softer than before to keep focus on the card.
            Color.black.opacity(cardAppeared ? 0.22 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            // Confetti — drop only, reduced count, Claude-palette colors.
            if event.kind == .drop {
                GeometryReader { geo in
                    ZStack {
                        ForEach(0..<22, id: \.self) { i in
                            StressConfettiPiece(
                                index: i,
                                isActive: confettiActive,
                                canvasSize: geo.size,
                                colors: palette.confetti
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }

            VStack(spacing: 20) {
                heroBadge

                VStack(spacing: 8) {
                    headline
                    Text(event.message)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }

                ctaButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
            .frame(maxWidth: 340)
            .background(cardBackground)
            .scaleEffect(cardAppeared ? 1 : 0.86)
            .opacity(cardAppeared ? 1 : 0)
            .padding(.horizontal, 32)
        }
        .onAppear { runEntrance() }
    }

    // MARK: - Hero Badge

    private var heroBadge: some View {
        ZStack {
            // Soft halo — single tone, fades out after entrance.
            Circle()
                .fill(palette.iconColor.opacity(0.10))
                .frame(width: 140, height: 140)
                .scaleEffect(haloScale)
                .opacity(haloOpacity)

            // Rise-only breathing ring. Slow + thin for "concerned, not alarming".
            if palette.useWarningPulse {
                Circle()
                    .stroke(palette.iconColor.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(warningPulse)
                    .opacity(2 - Double(warningPulse))
            }

            // Solid badge — flat fill + 1pt warm stroke. No gradients.
            Circle()
                .fill(palette.badgeFill)
                .frame(width: 84, height: 84)
                .overlay(
                    Circle()
                        .strokeBorder(palette.badgeStroke, lineWidth: 1)
                )

            Image(systemName: palette.icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(palette.iconColor)
        }
        .frame(height: 130)
    }

    // MARK: - Headline

    private var headline: some View {
        Text("\(palette.sign)\(displayedMagnitude) stress")
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.headlineColor)
            .contentTransition(.numericText())
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button { dismiss() } label: {
            Text(palette.ctaTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.ctaText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(palette.cta, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(AppColors.card)
            .overlay(
                // Subtle Pampas warmth that survives both light + dark mode.
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(ClaudePalette.pampas.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(ClaudePalette.cloudy.opacity(0.28), lineWidth: 1)
            )
            .appShadow(radius: 28, y: 10)
    }

    // MARK: - Entrance / Dismiss

    private func runEntrance() {
        switch event.kind {
        case .drop: HapticService.celebrationBurst()
        case .rise: HapticService.stressRiseAlert()
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            cardAppeared = true
        }
        withAnimation(.easeOut(duration: 0.55)) {
            haloScale = 1.25
            haloOpacity = 1
        }
        withAnimation(.easeIn(duration: 1.0).delay(0.3)) {
            haloOpacity = 0
        }

        if palette.useWarningPulse {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                warningPulse = 1.45
            }
        }

        if event.kind == .drop {
            withAnimation(.easeOut(duration: 0.05)) {
                confettiActive = true
            }
        }

        animateCountUp(to: event.magnitude)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissAfter) {
            dismiss()
        }
    }

    private func animateCountUp(to target: Int) {
        guard target > 0 else { return }
        let stepCount = min(target, 18)
        let totalDuration = 0.7
        let stepDelay = totalDuration / Double(stepCount)
        for i in 1...stepCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * stepDelay) {
                withAnimation(.easeOut(duration: stepDelay * 1.5)) {
                    displayedMagnitude = Int(Double(target) * (Double(i) / Double(stepCount)))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.02) {
            withAnimation { displayedMagnitude = target }
        }
    }

    private func dismiss() {
        guard cardAppeared else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            cardAppeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            onDismiss()
        }
    }
}

// MARK: - Confetti Piece

private struct StressConfettiPiece: View {
    let index: Int
    let isActive: Bool
    let canvasSize: CGSize
    let colors: [Color]

    private var color: Color {
        guard !colors.isEmpty else { return .clear }
        return colors[index % colors.count]
    }

    private var startX: CGFloat {
        let slot = CGFloat(index % 12) / 12.0
        let jitter = CGFloat((index * 37) % 50) - 25
        return slot * canvasSize.width + jitter
    }

    private var endY: CGFloat {
        canvasSize.height + CGFloat(40 + (index * 17) % 100)
    }

    private var startY: CGFloat { -80 - CGFloat((index * 23) % 140) }

    private var fallDuration: Double { 2.4 + Double((index * 7) % 16) * 0.08 }
    private var fallDelay: Double { Double((index * 11) % 11) * 0.05 }
    private var spinSpeed: Double { 1.0 + Double((index * 5) % 7) * 0.22 }

    @State private var fallen = false
    @State private var rotation: Double = 0

    var body: some View {
        shape
            .foregroundStyle(color)
            .position(
                x: startX + (fallen ? CGFloat((index * 13) % 80) - 40 : 0),
                y: fallen ? endY : startY
            )
            .rotationEffect(.degrees(rotation))
            .opacity(fallen ? 0 : 0.85)
            .onChange(of: isActive) { active in
                guard active else { return }
                withAnimation(.easeIn(duration: fallDuration).delay(fallDelay)) {
                    fallen = true
                }
                withAnimation(
                    .linear(duration: fallDuration * spinSpeed)
                        .repeatForever(autoreverses: false)
                        .delay(fallDelay)
                ) {
                    rotation = 720
                }
            }
    }

    @ViewBuilder
    private var shape: some View {
        switch index % 3 {
        case 0:
            Circle().frame(width: 6, height: 6)
        case 1:
            RoundedRectangle(cornerRadius: 1)
                .frame(width: 4, height: 10)
        default:
            Circle().frame(width: 4, height: 4)
        }
    }
}
