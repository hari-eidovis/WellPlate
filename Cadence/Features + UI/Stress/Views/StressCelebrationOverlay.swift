//
//  StressCelebrationOverlay.swift
//  WellPlate
//
//  Confetti + encouraging alert shown when the stress score drops by 8+ points
//  during a session. Hosted globally by `CelebrationWindowPresenter` so it can
//  appear over any tab or sheet.
//

import SwiftUI

// MARK: - Event Model

struct StressCelebrationEvent: Identifiable, Equatable {
    let id: UUID
    let dropPoints: Int
    let previousScore: Double
    let newScore: Double
    let message: String

    init(dropPoints: Int, previousScore: Double, newScore: Double) {
        self.id = UUID()
        self.dropPoints = dropPoints
        self.previousScore = previousScore
        self.newScore = newScore
        self.message = StressCelebrationMessages.random(forDrop: dropPoints)
    }
}

// MARK: - Encouraging copy

enum StressCelebrationMessages {
    private static let lines: [String] = [
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

    static func random(forDrop drop: Int) -> String {
        lines.randomElement() ?? "Stress dropped \(drop) points!"
    }
}

// MARK: - Palette

private enum CelebrationPalette {
    static let badgeStart = Color(hex: "FFB14A")  // warm gold
    static let badgeMid   = Color(hex: "FF7A3D")  // tangerine
    static let badgeEnd   = Color(hex: "FF4E8A")  // hot pink
    static let cta        = Color(hex: "1FA971")  // wellness green
    static let ctaGlow    = Color(hex: "39D194")
    static let confetti: [Color] = [
        Color(hex: "FFD24A"),   // gold
        Color(hex: "FF7A3D"),   // tangerine
        Color(hex: "FF4E8A"),   // hot pink
        Color(hex: "5E9FFF"),   // brand blue
        Color(hex: "39D194"),   // green
        Color(hex: "B58CFF"),   // lavender
        Color(hex: "55E6E1")    // teal
    ]
}

// MARK: - Overlay

struct StressCelebrationOverlay: View {
    let event: StressCelebrationEvent
    let onDismiss: () -> Void

    @State private var cardAppeared = false
    @State private var confettiActive = false
    @State private var burstScale: CGFloat = 0.4
    @State private var burstOpacity: Double = 0
    @State private var raysRotation: Double = 0
    @State private var shimmerX: CGFloat = -1
    @State private var displayedDrop: Int = 0

    /// Auto-dismiss timing.
    private static let autoDismissAfter: TimeInterval = 4.0

    var body: some View {
        ZStack {
            // Tap-anywhere-to-dismiss scrim.
            Color.black.opacity(cardAppeared ? 0.28 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            // Confetti — fills the screen, particles fall from above.
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<48, id: \.self) { i in
                        StressConfettiPiece(
                            index: i,
                            isActive: confettiActive,
                            canvasSize: geo.size
                        )
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            // Centered alert card
            VStack(spacing: 18) {
                heroBadge

                VStack(spacing: 8) {
                    gradientHeadline
                    Text(event.message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }

                ctaButton
                    .padding(.top, 6)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 28)
            .frame(maxWidth: 340)
            .background(cardBackground)
            .scaleEffect(cardAppeared ? 1 : 0.82)
            .opacity(cardAppeared ? 1 : 0)
            .padding(.horizontal, 32)
        }
        .onAppear { runEntrance() }
    }

    // MARK: - Hero Badge

    private var heroBadge: some View {
        ZStack {
            // Soft outer glow halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [CelebrationPalette.badgeStart.opacity(0.45), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 180, height: 180)
                .scaleEffect(burstScale)
                .opacity(burstOpacity)

            // Rotating sunburst rays
            SunburstRays(rayCount: 12, color: CelebrationPalette.badgeStart.opacity(0.55))
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(raysRotation))
                .opacity(cardAppeared ? 0.9 : 0)

            // Solid gradient disc
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            CelebrationPalette.badgeStart,
                            CelebrationPalette.badgeMid,
                            CelebrationPalette.badgeEnd
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)
                .shadow(color: CelebrationPalette.badgeMid.opacity(0.55), radius: 18, x: 0, y: 8)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )

            // Icon — heart with a down arrow (semantic: stress dropping)
            Image(systemName: "arrow.down.heart.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .frame(height: 130)
    }

    // MARK: - Gradient Headline

    private var gradientHeadline: some View {
        Text("−\(displayedDrop) stress")
            .font(.system(size: 36, weight: .heavy, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        CelebrationPalette.badgeStart,
                        CelebrationPalette.badgeMid,
                        CelebrationPalette.badgeEnd
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .contentTransition(.numericText())
            .overlay(
                // Sheen — moves across the text
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80)
                .offset(x: shimmerX * 200)
                .mask(
                    Text("−\(displayedDrop) stress")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            )
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button { dismiss() } label: {
            Text("Keep it up")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [CelebrationPalette.ctaGlow, CelebrationPalette.cta],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: CelebrationPalette.cta.opacity(0.45), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                CelebrationPalette.badgeStart.opacity(0.08),
                                .clear,
                                CelebrationPalette.badgeEnd.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                CelebrationPalette.badgeStart.opacity(0.35),
                                CelebrationPalette.badgeEnd.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .appShadow(radius: 36, y: 14)
    }

    // MARK: - Entrance / Dismiss

    private func runEntrance() {
        HapticService.celebrationBurst()

        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
            cardAppeared = true
        }
        withAnimation(.easeOut(duration: 0.6)) {
            burstScale = 1.4
            burstOpacity = 1
        }
        withAnimation(.easeIn(duration: 0.9).delay(0.3)) {
            burstOpacity = 0
        }
        withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
            raysRotation = 360
        }
        withAnimation(.easeOut(duration: 0.05)) {
            confettiActive = true
        }
        // Number count-up
        animateCountUp(to: event.dropPoints)
        // Sheen sweep over the headline (twice)
        withAnimation(.easeInOut(duration: 1.1).delay(0.35)) {
            shimmerX = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            shimmerX = -1
            withAnimation(.easeInOut(duration: 1.1)) { shimmerX = 1 }
        }

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
                    displayedDrop = Int(Double(target) * (Double(i) / Double(stepCount)))
                }
            }
        }
        // Snap to exact final value
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.02) {
            withAnimation { displayedDrop = target }
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

// MARK: - Sunburst Rays

private struct SunburstRays: View {
    let rayCount: Int
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = size.width / 2
            let innerRadius = outerRadius * 0.42
            let halfAngle = (CGFloat.pi / CGFloat(rayCount)) * 0.35

            for i in 0..<rayCount {
                let angle = CGFloat(i) * (2 * .pi / CGFloat(rayCount))
                var path = Path()
                let tip = CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                )
                let leftBase = CGPoint(
                    x: center.x + cos(angle - halfAngle) * innerRadius,
                    y: center.y + sin(angle - halfAngle) * innerRadius
                )
                let rightBase = CGPoint(
                    x: center.x + cos(angle + halfAngle) * innerRadius,
                    y: center.y + sin(angle + halfAngle) * innerRadius
                )
                path.move(to: tip)
                path.addLine(to: leftBase)
                path.addLine(to: rightBase)
                path.closeSubpath()
                ctx.fill(path, with: .color(color))
            }
        }
    }
}

// MARK: - Confetti Piece

private struct StressConfettiPiece: View {
    let index: Int
    let isActive: Bool
    let canvasSize: CGSize

    private var color: Color {
        CelebrationPalette.confetti[index % CelebrationPalette.confetti.count]
    }

    private var startX: CGFloat {
        let slot = CGFloat(index % 16) / 16.0
        let jitter = CGFloat((index * 37) % 50) - 25
        return slot * canvasSize.width + jitter
    }

    private var endY: CGFloat {
        canvasSize.height + CGFloat(40 + (index * 17) % 100)
    }

    private var startY: CGFloat { -80 - CGFloat((index * 23) % 140) }

    private var fallDuration: Double { 2.0 + Double((index * 7) % 16) * 0.08 }
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
            .opacity(fallen ? 0 : 0.98)
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
        switch index % 5 {
        case 0:
            Circle().frame(width: 8, height: 8)
        case 1:
            RoundedRectangle(cornerRadius: 1.5)
                .frame(width: 6, height: 13)
        case 2:
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
        case 3:
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
        default:
            CelebrationTriangle().frame(width: 9, height: 9)
        }
    }
}

private struct CelebrationTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
