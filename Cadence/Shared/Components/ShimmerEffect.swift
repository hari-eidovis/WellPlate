import SwiftUI

// MARK: - Shimmer
//
// A sweeping highlight that animates across content to signal "loading".
// Designed to compose with `.redacted(reason: .placeholder)` so skeleton
// placeholders feel alive rather than stuck on a flat grey block.
//
// Respects Reduce Motion: when that accessibility setting is on, the content is
// shown static (no sweep), leaving the plain redacted placeholder.
//
// Usage:
//   CardBody()
//     .redacted(reason: .placeholder)
//     .shimmering(active: isLoading)

private struct ShimmerModifier: ViewModifier {
    let active: Bool
    var duration: Double = 1.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay { ShimmerBand(duration: duration).mask(content) }
        } else {
            content
        }
    }
}

/// A soft highlight band that slides left→right across its container, looping
/// forever. Masked to the host content by `ShimmerModifier`.
private struct ShimmerBand: View {
    let duration: Double
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.6), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.5)
            // phase 0 → band parked just off the left edge;
            // phase 1 → band parked just off the right edge.
            .offset(x: -width * 0.5 + phase * (width * 1.5))
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

extension View {
    /// Sweeps a soft highlight across the view while `active`, signalling a
    /// loading skeleton. Compose right after `.redacted(reason: .placeholder)`.
    /// No-op (and motion-free) when `active` is false or Reduce Motion is on.
    func shimmering(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}
