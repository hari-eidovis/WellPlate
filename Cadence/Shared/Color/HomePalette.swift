import SwiftUI

// MARK: - HomePalette
//
// Palette for the redesigned Home dashboard: a cream background, a blue hero
// and accent (the app's primary `#5E9FFF`, shared with the Stress tab), with
// warm-brown water and golden-amber move tiles. Light values mirror the mockup;
// dark values are brighter equivalents so the same hues stay legible on a dark
// background.

enum HomePalette {
    /// Cream app background behind the Home cards (true black in dark mode).
    static let background  = dyn((0.945, 0.937, 0.906), (0.0, 0.0, 0.0))
    /// Primary-blue "Today's Focus" hero fill — a touch deeper than `accent`
    /// so the white headline keeps enough contrast.
    static let hero        = dyn((0.235, 0.498, 0.918), (0.156, 0.318, 0.557))
    /// Primary blue (`#5E9FFF`) — small glyphs, the calories bar, the fasting pill.
    static let accent      = dyn((0.369, 0.624, 1.000), (0.451, 0.690, 1.000))
    /// Warm brown — Water tile.
    static let water       = dyn((0.557, 0.431, 0.271), (0.714, 0.549, 0.353))
    /// Golden amber — Move tile.
    static let amber       = dyn((0.745, 0.549, 0.212), (0.851, 0.651, 0.302))
    /// Muted teal — Screen Time tile.
    static let screen      = dyn((0.180, 0.545, 0.580), (0.373, 0.706, 0.741))
    /// Terracotta — moderate stress.
    static let terracotta  = dyn((0.753, 0.439, 0.235), (0.851, 0.561, 0.353))
    /// Rust — high / very high stress.
    static let rust        = dyn((0.690, 0.314, 0.227), (0.796, 0.435, 0.329))

    /// Tint for the stress ring/pill by level: primary blue when calm, warming
    /// through amber and terracotta to rust as stress climbs.
    static func stressTint(_ level: StressLevel) -> Color {
        switch level {
        case .excellent, .good: return accent
        case .moderate:         return amber
        case .high:             return terracotta
        case .veryHigh:         return rust
        }
    }

    /// Builds an adaptive color from light/dark sRGB component tuples.
    private static func dyn(_ l: (Double, Double, Double), _ d: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { tc in
            let c = tc.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
