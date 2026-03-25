//
//  StressScoreGaugeView.swift
//  WellPlate
//

import SwiftUI

struct StressScoreGaugeView: View {

    let score: Double
    let level: StressLevel
    var size: CGFloat = 230
    var immersive: Bool = false

    @State private var animatedProgress: Double = 0

    private let trackWidth: CGFloat = 22
    // 270° arc: starts bottom-left, sweeps clockwise
    private let startAngle: Double = 135
    private let sweepAngle: Double = 270

    var body: some View {
        ZStack {
            // Outer glow halo — pulses with stress level color
            Circle()
                .fill(level.color.opacity(immersive ? 0.22 : 0.13))
                .frame(width: size + 52, height: size + 52)
                .blur(radius: 24)

            Circle()
                .fill(level.color.opacity(immersive ? 0.12 : 0.07))
                .frame(width: size + 28, height: size + 28)

            // Track ring
            arcShape
                .stroke(Color(.systemGray5), style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))

            // Progress ring
            arcShape
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [level.color.opacity(0.6), level.color]),
                        center: .center,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(startAngle + sweepAngle * animatedProgress)
                    ),
                    style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                )

            // Thumb dot at the tip of the arc
            thumbDot

            // Center content
            VStack(spacing: 6) {
                Text(level.label.uppercased())
                    .font(.system(size: size * 0.065, weight: .semibold, design: .rounded))
                    .foregroundColor(level.color)
                    .tracking(1.5)

                Text("\(Int(score))")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundColor(immersive ? level.color : .primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size + 52, height: size + 52)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.72).delay(0.15)) {
                animatedProgress = score / 100.0
            }
        }
        .onChange(of: score) { _, newValue in
            withAnimation(.spring(response: 0.65, dampingFraction: 0.75)) {
                animatedProgress = newValue / 100.0
            }
        }
    }

    // MARK: - Thumb Dot
    private var thumbDot: some View {
        let progress = animatedProgress
        let sweepRad = sweepAngle * .pi / 180.0
        let progressAngle = startAngle + sweepAngle * progress
        let rad = progressAngle * .pi / 180.0
        let radius = size / 2
        let x = radius * CGFloat(cos(rad))
        let y = radius * CGFloat(sin(rad))

        return Circle()
            .fill(level.color)
            .frame(width: trackWidth + 4, height: trackWidth + 4)
            .shadow(color: level.color.opacity(0.6), radius: 6, x: 0, y: 2)
            .offset(x: x, y: y)
            .opacity(progress > 0.01 ? 1 : 0)
    }

    private var arcShape: some Shape {
        Arc(startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweepAngle),
            clockwise: false)
    }
}

// MARK: - Custom Arc Shape

private struct Arc: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let clockwise: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        StressScoreGaugeView(score: 22, level: .good)
        StressScoreGaugeView(score: 72, level: .high, size: 180)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
