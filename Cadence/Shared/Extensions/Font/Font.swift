import SwiftUI

// MARK: - Typography (SF Pro Rounded)
extension Font {

    // MARK: Core
    /// SF Pro Rounded via system font (Dynamic Type friendly).
    static func r(_ style: TextStyle, _ weight: Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    /// SF Pro Rounded with explicit size (use when you really need fixed sizing).
    static func r(_ size: CGFloat, _ weight: Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: Weight shortcuts (TextStyle)
    static func rR(_ style: TextStyle) -> Font { r(style, .regular) }
    static func rM(_ style: TextStyle) -> Font { r(style, .medium) }
    static func rS(_ style: TextStyle) -> Font { r(style, .semibold) }
    static func rB(_ style: TextStyle) -> Font { r(style, .bold) }
    static func rH(_ style: TextStyle) -> Font { r(style, .heavy) }
    static func rBl(_ style: TextStyle) -> Font { r(style, .black) }

    // MARK: Weight shortcuts (Size)
    static func rR(_ size: CGFloat) -> Font { r(size, .regular) }
    static func rM(_ size: CGFloat) -> Font { r(size, .medium) }
    static func rS(_ size: CGFloat) -> Font { r(size, .semibold) }
    static func rB(_ size: CGFloat) -> Font { r(size, .bold) }
    static func rH(_ size: CGFloat) -> Font { r(size, .heavy) }
    static func rBl(_ size: CGFloat) -> Font { r(size, .black) }

    // MARK: Common roles (edit once, updates everywhere)
    /// App-level big KPI number (calories/macros).
    static var metric: Font { r(34, .bold) }

    /// Large title on top screens.
    static var title: Font { r(.title2, .semibold) }

    /// Section headers like "Goals", "Recently Added".
    static var section: Font { r(.title3, .semibold) }

    /// Card title / row primary text.
    static var row: Font { r(.headline, .semibold) }

    /// Secondary text under a row.
    static var sub: Font { r(.subheadline, .regular) }

    /// Tertiary / hint / placeholder.
    static var hint: Font { r(.callout, .regular) }

    /// Small metadata (dates, units).
    static var cap: Font { r(.caption, .regular) }

    /// Tiny labels (chips, badges).
    static var tiny: Font { r(.caption2, .medium) }

    // MARK: Special cases
    /// Use for buttons so they feel “snappy”.
    static var btn: Font { r(.headline, .semibold) }

    /// Use for pills/chips like "Today".
    static var chip: Font { r(.subheadline, .semibold) }

    /// Use for tab labels.
    static var tab: Font { r(.caption, .semibold) }
}

// MARK: - Numeric helpers (calorie apps need this)
extension View {
    /// Prevents number width “jitter” while values change (e.g., 999 -> 1000).
    func digits() -> some View { self.monospacedDigit() }

    /// Apply SF Rounded font + monospaced digits in one shot (nice for counters).
    func metricFont(_ size: CGFloat = 34, weight: Font.Weight = .bold) -> some View {
        self.font(.r(size, weight)).monospacedDigit()
    }
}
