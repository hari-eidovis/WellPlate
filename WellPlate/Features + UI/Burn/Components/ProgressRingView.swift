//
//  ProgressRingView.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI

/// Circular progress ring — used on the Burn hero card.
struct ProgressRingView: View {
    let progress: Double    // 0.0 – 1.0  (clamped internally)
    let color: Color
    let size: CGFloat

    private var clamped: Double { min(max(progress, 0), 1) }
    private var lineWidth: CGFloat { size * 0.11 }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            // Fill arc
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    LinearGradient(
                        colors: [color, color.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.65, dampingFraction: 0.8), value: clamped)

            // Percentage label
            VStack(spacing: 1) {
                Text("\(Int(clamped * 100))%")
                    .font(.r(size * 0.19, .bold))
                    .foregroundColor(color)
                    .monospacedDigit()
                Text("goal")
                    .font(.r(size * 0.13, .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ProgressRingView(progress: 0.72, color: AppColors.brand, size: 90)
        .padding()
}
