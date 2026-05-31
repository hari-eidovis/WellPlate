import SwiftUI

// MARK: - ActivityCard
// "Today's Activity" card with three animated progress bar rows:
// Exercise (minutes), Burned (calories), Steps.

struct ActivityMetric: Identifiable {
    let id = UUID()
    let label: String
    let symbol: String
    let iconBackground: Color
    let iconTint: Color
    let valueText: String
    let progress: CGFloat   // 0.0 – 1.0
    let barColor: Color
}

struct ActivityCard: View {

    let metrics: [ActivityMetric]
    @State private var animate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Today's Activity")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 18) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    ActivityRow(metric: metric, animate: animate, delay: Double(index) * 0.12)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.74).delay(0.1)) {
                animate = true
            }
        }
    }
}

// MARK: - ActivityRow

private struct ActivityRow: View {

    let metric: ActivityMetric
    let animate: Bool
    let delay: Double

    var body: some View {
        HStack(spacing: 14) {
            // Icon circle
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(metric.iconBackground)
                    .frame(width: 42, height: 42)

                Image(systemName: metric.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(metric.iconTint)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(metric.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(metric.valueText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(metric.barColor.opacity(0.15))
                            .frame(height: 8)

                        // Fill
                        Capsule()
                            .fill(metric.barColor)
                            .frame(
                                width: animate
                                    ? max(geo.size.width * min(metric.progress, 1.0), 8)
                                    : 0,
                                height: 8
                            )
                            .animation(
                                .spring(response: 1.0, dampingFraction: 0.74).delay(delay + 0.1),
                                value: animate
                            )
                    }
                }
                .frame(height: 8)
            }
        }
    }
}

// MARK: - Convenience defaults

extension ActivityCard {
    static func sample() -> ActivityCard {
        ActivityCard(metrics: [
            ActivityMetric(
                label: "Exercise",
                symbol: "timer",
                iconBackground: Color(hue: 0.40, saturation: 0.22, brightness: 0.96),
                iconTint: Color(hue: 0.40, saturation: 0.65, brightness: 0.68),
                valueText: "32 min",
                progress: 0.71,
                barColor: Color(hue: 0.40, saturation: 0.65, brightness: 0.68)
            ),
            ActivityMetric(
                label: "Burned",
                symbol: "drop.fill",
                iconBackground: Color(hue: 0.07, saturation: 0.25, brightness: 0.98),
                iconTint: Color(hue: 0.07, saturation: 0.75, brightness: 0.90),
                valueText: "280 cal",
                progress: 0.56,
                barColor: Color(hue: 0.07, saturation: 0.75, brightness: 0.90)
            ),
            ActivityMetric(
                label: "Steps",
                symbol: "figure.walk",
                iconBackground: Color(hue: 0.76, saturation: 0.18, brightness: 0.97),
                iconTint: Color(hue: 0.76, saturation: 0.50, brightness: 0.75),
                valueText: "6,430",
                progress: 0.64,
                barColor: Color(hue: 0.76, saturation: 0.50, brightness: 0.75)
            )
        ])
    }
}

// MARK: - Preview

#Preview {
    ActivityCard.sample()
        .padding()
}
