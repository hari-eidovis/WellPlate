import SwiftUI

// MARK: - Event Model

struct FastingCompletionEvent: Identifiable, Equatable {
    let id = UUID()
    let durationHours: Double
    let scheduleLabel: String
}

// MARK: - Overlay

struct FastingCelebrationOverlay: View {
    let event: FastingCompletionEvent
    let onDismiss: () -> Void

    @State private var cardAppeared = false
    @State private var confettiActive = false
    @State private var burstScale: CGFloat = 0.4
    @State private var burstOpacity: Double = 0
    @State private var checkmarkScale: CGFloat = 0.0

    private static let autoDismissAfter: TimeInterval = 4.5

    private static let palette = (
        start: Color(hue: 0.07, saturation: 0.78, brightness: 0.95),
        mid:   Color(hue: 0.13, saturation: 0.78, brightness: 0.95),
        end:   Color(hue: 0.40, saturation: 0.62, brightness: 0.72),
        cta:   Color(hue: 0.40, saturation: 0.62, brightness: 0.72)
    )

    private static let confettiColors: [Color] = [
        Color(hex: "FFD24A"),
        Color(hex: "FF7A3D"),
        Color(hex: "39D194"),
        Color(hex: "55E6E1"),
        Color(hex: "5E9FFF"),
        Color(hex: "B58CFF")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(cardAppeared ? 0.32 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            GeometryReader { geo in
                ZStack {
                    ForEach(0..<40, id: \.self) { i in
                        FastingConfettiPiece(index: i,
                                             isActive: confettiActive,
                                             canvasSize: geo.size,
                                             palette: Self.confettiColors)
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(spacing: 18) {
                heroBadge

                VStack(spacing: 6) {
                    Text("Fast Complete!")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Self.palette.start, Self.palette.mid, Self.palette.end],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 6)
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

    private var subtitle: String {
        let hours = Int(event.durationHours)
        let minutes = Int((event.durationHours - Double(hours)) * 60)
        if minutes > 0 {
            return "You fasted for \(hours)h \(minutes)m. Nice work."
        }
        return "You fasted for \(hours)h. Nice work."
    }

    private var heroBadge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Self.palette.end.opacity(0.45), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 180, height: 180)
                .scaleEffect(burstScale)
                .opacity(burstOpacity)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Self.palette.start, Self.palette.end],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)
                .shadow(color: Self.palette.end.opacity(0.55), radius: 18, x: 0, y: 8)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )

            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(.white)
                .scaleEffect(checkmarkScale)
        }
        .frame(height: 130)
    }

    private var ctaButton: some View {
        Button { dismiss() } label: {
            Text("Nice")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Self.palette.start, Self.palette.cta],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: Self.palette.cta.opacity(0.45), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(AppColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Self.palette.start.opacity(0.35), Self.palette.end.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .appShadow(radius: 36, y: 14)
    }

    private func runEntrance() {
        HapticService.celebrationBurst()

        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
            cardAppeared = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) {
            checkmarkScale = 1
        }
        withAnimation(.easeOut(duration: 0.6)) {
            burstScale = 1.4
            burstOpacity = 1
        }
        withAnimation(.easeIn(duration: 0.9).delay(0.3)) {
            burstOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.05)) {
            confettiActive = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissAfter) {
            dismiss()
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

private struct FastingConfettiPiece: View {
    let index: Int
    let isActive: Bool
    let canvasSize: CGSize
    let palette: [Color]

    private var color: Color { palette[index % palette.count] }

    private var startX: CGFloat {
        let slot = CGFloat(index % 14) / 14.0
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
            .opacity(fallen ? 0 : 0.95)
            .onChange(of: isActive) { _, active in
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
        switch index % 4 {
        case 0:
            Circle().frame(width: 8, height: 8)
        case 1:
            RoundedRectangle(cornerRadius: 1.5)
                .frame(width: 6, height: 13)
        case 2:
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
        default:
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
        }
    }
}
