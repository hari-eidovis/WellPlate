//
//  AmbientBlobView.swift
//  WellPlate
//

import SwiftUI

/// A single softly-glowing orb that drifts to `targetOffset` and back.
/// Animation duration is randomised once at struct creation (stored in @State)
/// so re-renders never reset the loop.
struct AmbientBlobView: View {

    let color: Color
    let size: CGFloat
    let targetOffset: CGSize

    // Stored in @State so the random value survives every re-render.
    @State private var animDuration: Double = Double.random(in: 5...7)
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.85), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .opacity(0.22)
            .offset(isAnimating ? targetOffset : .zero)
            .scaleEffect(isAnimating ? 1.1 : 0.85)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .linear(duration: animDuration)
                    .repeatForever(autoreverses: true)
                ) {
                    isAnimating = true
                }
            }
    }
}
