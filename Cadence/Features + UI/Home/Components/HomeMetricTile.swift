import SwiftUI

// MARK: - HomeMetricTile
//
// Compact dashboard tile shared by the four Home bento metrics — Water, Move,
// Stress, and Calories. Shows an icon, label, a big value, an optional
// pace/status line, and a vertical fill gauge on the trailing edge. Enum-driven
// so every variant shares one layout (and therefore one size).

struct HomeMetricTile: View {

    enum Metric {
        /// `behind` = cups behind the expected pace (0 = on track).
        case water(current: Int, goal: Int, behind: Int)
        case move(steps: Int, goal: Int)
        /// `score` 0–100 (nil until a reading exists); `level` drives the tint.
        case stress(score: Int?, level: StressLevel?)
        case calories(current: Int, goal: Int)
        /// Today's total screen time in hours (nil until detected/entered).
        case screenTime(hours: Double?)
    }

    let metric: Metric
    var onTap: () -> Void

    init(_ metric: Metric, onTap: @escaping () -> Void) {
        self.metric = metric
        self.onTap = onTap
    }

    // MARK: - Per-metric derivation

    private var icon: String {
        switch metric {
        case .water:      "drop.fill"
        case .move:       "figure.walk"
        case .stress:     "brain.head.profile"
        case .calories:   "fork.knife"
        case .screenTime: "iphone"
        }
    }

    private var label: String {
        switch metric {
        case .water:      "Water"
        case .move:       "Move"
        case .stress:     "Stress"
        case .calories:   "Calories"
        case .screenTime: "Screen Time"
        }
    }

    private var accent: Color {
        switch metric {
        case .water:    HomePalette.water
        case .move:     HomePalette.amber
        case .stress(_, let level): level.map(HomePalette.stressTint) ?? Color(.systemGray3)
        case .calories: HomePalette.accent
        case .screenTime: HomePalette.screen
        }
    }

    private var fillFraction: CGFloat {
        switch metric {
        case .water(let c, let g, _): return g > 0 ? min(1, CGFloat(c) / CGFloat(g)) : 0
        case .move(let s, let g):     return g > 0 ? min(1, CGFloat(s) / CGFloat(g)) : 0
        case .stress(let score, _):
            // "Calm" fill: a low stress score reads as a nearly-full gauge.
            guard let score else { return 0 }
            return max(0, min(1, CGFloat(100 - score) / 100))
        case .calories(let c, let g): return g > 0 ? min(1, CGFloat(c) / CGFloat(g)) : 0
        case .screenTime(let hours):
            // Usage meter against an 8h reference — more screen time, fuller gauge.
            guard let hours else { return 0 }
            return max(0, min(1, CGFloat(hours) / 8))
        }
    }

    private var isWater: Bool {
        if case .water = metric { return true }
        return false
    }

    /// True once the metric's goal is met or exceeded.
    private var goalReached: Bool {
        switch metric {
        case .water(let c, let g, _): return g > 0 && c >= g
        case .move(let s, let g):     return g > 0 && s >= g
        case .calories(let c, let g): return g > 0 && c >= g
        case .stress:                 return false
        case .screenTime:             return false
        }
    }

    /// Pace/status line shown under the value. `nil` hides the row — Stress is
    /// intentionally bare (just the number) per the dashboard design.
    private var status: (text: String, icon: String)? {
        switch metric {
        case .water(let c, let g, let behind):
            if c == 0 { return ("Insufficient", "arrow.up") }
            if g > 0 && c >= g { return ("Excellent", "checkmark") }
            return behind == 0 ? ("On track", "arrow.down") : ("Keep going", "arrow.up")
        case .move(let s, let g):
            return (g > 0 && s >= g) ? ("On track", "arrow.down") : ("Keep going", "arrow.up")
        case .calories(let c, let g):
            return (g > 0 && c >= g) ? ("On track", "arrow.down") : ("Keep going", "arrow.up")
        case .stress:
            return nil
        case .screenTime:
            return nil
        }
    }

    /// Status row + fill gauge switch to the primary blue once the water goal is reached.
    private var statusTint: Color {
        (isWater && goalReached) ? HomePalette.accent : accent
    }

    // MARK: - Body

    var body: some View {
        Button(action: { HapticService.impact(.light); onTap() }) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // Icon + label
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                        Text(label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    valueView

                    // Status
                    if let status {
                        HStack(spacing: 5) {
                            Image(systemName: status.icon)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(statusTint)
                                .frame(width: 15, height: 15)
                                .background(Circle().fill(statusTint.opacity(0.15)))
                            Text(status.text)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(statusTint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VerticalGauge(fraction: fillFraction, tint: statusTint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.card)
                    .appShadow(radius: 14, y: 5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Value (variant-specific)

    @ViewBuilder
    private var valueView: some View {
        switch metric {
        case .water(let c, let g, _):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(c)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("/ \(g)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .move(let s, let g):
            VStack(alignment: .leading, spacing: 0) {
                Text(s.formatted())
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("of \(g.formatted()) steps")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .stress(let score, _):
            // Just the number — no ring, no level words.
            Text(score.map(String.init) ?? "—")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        case .calories(let c, let g):
            VStack(alignment: .leading, spacing: 0) {
                Text(c.formatted())
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("of \(g.formatted()) kcal")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .screenTime(let hours):
            VStack(alignment: .leading, spacing: 0) {
                Text(hours.map { String(format: "%.1fh", $0) } ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("today")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - VerticalGauge

private struct VerticalGauge: View {
    let fraction: CGFloat
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let clamped = max(0, min(1, fraction))
            let fillH = max(8, h * clamped)
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(tint.opacity(0.15))
                    .frame(width: 6)

                Capsule()
                    .fill(tint)
                    .frame(width: 6, height: fillH)

                // Knob anchored at the top of the fill.
                Circle()
                    .fill(AppColors.card)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(tint, lineWidth: 3))
                    .offset(y: -(fillH - 7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: fillH)
        }
        .frame(width: 16)
    }
}

// MARK: - Preview

#Preview("Home Metric Tiles") {
    HStack(alignment: .top, spacing: 12) {
        VStack(spacing: 12) {
            HomeMetricTile(.stress(score: 42, level: StressLevel(score: 42)), onTap: {})
            HomeMetricTile(.calories(current: 1240, goal: 2000), onTap: {})
        }
        VStack(spacing: 12) {
            HomeMetricTile(.water(current: 6, goal: 8, behind: 0), onTap: {})
            HomeMetricTile(.move(steps: 5240, goal: 8000), onTap: {})
        }
    }
    .padding(16)
    .background(HomePalette.background)
}
