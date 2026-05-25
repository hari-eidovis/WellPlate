import SwiftUI

// MARK: - WaterWaveShape
//
// An animatable Shape that renders a "water fill" region with a sine-wave
// top edge.  Two properties drive the visual:
//   • fillFraction (0–1): how high the water sits in the bounding rect
//   • wavePhase   (0–2π): lateral phase offset; animate this to make the
//                         wave appear to flow continuously
//
// Usage:
//   WaterWaveShape(fillFraction: 0.4, wavePhase: phase)
//       .fill(Color.blue.opacity(0.15))
//       .animation(.easeInOut(duration: 0.8), value: fillFraction)

struct WaterWaveShape: Shape {

    /// 0.0 = empty, 1.0 = full
    var fillFraction: Double
    /// Phase offset in radians for the sine wave; animate for a flowing effect
    var wavePhase: Double

    // Expose both properties to the animation engine so SwiftUI can interpolate
    // them smoothly when either value changes.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(fillFraction, wavePhase) }
        set {
            fillFraction = newValue.first
            wavePhase    = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let waveAmplitude: CGFloat = 4          // height of sine crest/trough
        let waveLength:   CGFloat = rect.width  // one full wave per card width
        let waterTop: CGFloat = rect.height * (1 - CGFloat(fillFraction))

        // Start at bottom-left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))

        // Trace the sine-wave top edge left → right
        let step: CGFloat = 2
        var x = rect.minX
        while x <= rect.maxX + step {
            let angle = (x / waveLength) * 2 * .pi + CGFloat(wavePhase)
            let y = waterTop + waveAmplitude * sin(angle)
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }

        // Close the shape down to the bottom-right, across the bottom, back to start
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}
