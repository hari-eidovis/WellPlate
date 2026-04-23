import SwiftUI

extension View {
    @ViewBuilder
    func wellPlateWidgetBackground<Background: View>(
        @ViewBuilder _ background: () -> Background
    ) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                background()
            }
        } else {
            self.background(background())
        }
    }
}

// MARK: - Widget Color Helper

enum StressWidgetColor {
    static func color(for levelRaw: String) -> Color {
        switch levelRaw {
        case "Excellent":  return Color(hue: 0.33, saturation: 0.60, brightness: 0.72)
        case "Good":       return Color(hue: 0.27, saturation: 0.55, brightness: 0.70)
        case "Moderate":   return Color(hue: 0.12, saturation: 0.55, brightness: 0.72)
        case "High":       return Color(hue: 0.06, saturation: 0.60, brightness: 0.70)
        case "Very High":  return Color(hue: 0.01, saturation: 0.65, brightness: 0.65)
        default:           return Color.gray
        }
    }

    static func systemImage(for levelRaw: String) -> String {
        switch levelRaw {
        case "Excellent":  return "face.smiling.inverse"
        case "Good":       return "face.smiling"
        case "Moderate":   return "face.dashed"
        case "High":       return "exclamationmark.triangle"
        case "Very High":  return "exclamationmark.triangle.fill"
        default:           return "face.dashed"
        }
    }
}

// MARK: - Stress Ring

struct StressRingView: View {
    let data: WidgetStressData
    var ringWidth: CGFloat = 10

    private var fraction: Double {
        min(data.totalScore / 100.0, 1.0)
    }

    private var levelColor: Color {
        StressWidgetColor.color(for: data.levelRaw)
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(levelColor.opacity(0.18), lineWidth: ringWidth)

            // Fill
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [levelColor, levelColor.opacity(0.7)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle:   .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    .spring(response: 0.65, dampingFraction: 0.78),
                    value: fraction
                )

            // Labels
            VStack(spacing: 1) {
                Text("\(Int(data.totalScore))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.default, value: data.totalScore)
                Text("/100")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Stress score: \(Int(data.totalScore)) out of 100, \(data.levelRaw)")
    }
}

// MARK: - Stress Factor Bar

struct StressFactorBar: View {
    let factor: WidgetStressFactor

    private var fraction: Double {
        guard factor.maxScore > 0 else { return 0 }
        return min(factor.contribution / factor.maxScore, 1.0)
    }

    private var barColor: Color {
        guard factor.hasValidData else { return Color(.systemGray3) }
        let stressRatio = min(max(factor.contribution / factor.maxScore, 0), 1)
        return Color(hue: 0.33 * (1.0 - stressRatio), saturation: 0.65, brightness: 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: factor.icon)
                    .font(.caption2)
                    .foregroundStyle(factor.hasValidData ? barColor : Color(.systemGray3))
                    .frame(width: 14)
                Text(factor.title)
                    .font(.caption2)
                    .foregroundStyle(factor.hasValidData ? .primary : .secondary)
                Spacer()
                Text("\(Int(factor.contribution))/\(Int(factor.maxScore))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.2))
                        .frame(height: 5)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(geo.size.width * fraction, 0), height: 5)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.72),
                            value: fraction
                        )
                }
            }
            .frame(height: 5)
        }
        .opacity(factor.hasValidData ? 1.0 : 0.5)
    }
}
