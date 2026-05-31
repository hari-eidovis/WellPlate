import SwiftUI

struct FastingInsightChart: View {
    let sessions: [FastingSession]
    let readings: [StressReading]

    private var fastDays: Set<Date> {
        Set(sessions.filter { !$0.isActive }.map { Calendar.current.startOfDay(for: $0.startedAt) })
    }

    private var dailyAverages: [Date: Double] {
        StressAnalyticsHelper.dailyAveragesByDate(from: readings)
    }

    private var fastDayAvg: (mean: Double, count: Int) {
        let scores = dailyAverages.filter { fastDays.contains($0.key) }.map(\.value)
        guard !scores.isEmpty else { return (0, 0) }
        return (scores.reduce(0, +) / Double(scores.count), scores.count)
    }

    private var nonFastDayAvg: (mean: Double, count: Int) {
        let scores = dailyAverages.filter { !fastDays.contains($0.key) }.map(\.value)
        guard !scores.isEmpty else { return (0, 0) }
        return (scores.reduce(0, +) / Double(scores.count), scores.count)
    }

    private var hasSufficientData: Bool {
        fastDayAvg.count >= 3 && nonFastDayAvg.count >= 3
    }

    /// Positive = fasting days have lower stress (better)
    private var delta: Double {
        nonFastDayAvg.mean - fastDayAvg.mean
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fasting & Stress")
                .font(.r(.headline, .semibold))

            if hasSufficientData {
                dataView

                // Delta indicator
                if abs(delta) > 1 {
                    HStack(spacing: 5) {
                        Image(systemName: delta > 0 ? "arrow.down.right" : "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(delta > 0 ? .green : .orange)
                        Text("\(String(format: "%.1f", abs(delta))) pts \(delta > 0 ? "lower" : "higher") on fast days")
                            .font(.r(.caption2, .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill((delta > 0 ? Color.green : Color.orange).opacity(0.08))
                    )
                }

                Text("Correlation does not imply causation.")
                    .font(.r(.caption2, .regular))
                    .foregroundColor(.secondary)
            } else {
                Text("Log 7+ days to see your fasting × stress pattern.")
                    .font(.r(.footnote, .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private var dataView: some View {
        VStack(spacing: 12) {
            barRow(label: "Fast days", avg: fastDayAvg.mean, count: fastDayAvg.count,
                   color: .orange, maxValue: max(fastDayAvg.mean, nonFastDayAvg.mean))
            barRow(label: "Non-fast days", avg: nonFastDayAvg.mean, count: nonFastDayAvg.count,
                   color: .secondary, maxValue: max(fastDayAvg.mean, nonFastDayAvg.mean))
        }
    }

    private func barRow(label: String, avg: Double, count: Int, color: Color, maxValue: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.r(.caption, .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("avg \(String(format: "%.1f", avg))")
                    .font(.r(.caption, .semibold))
                Text("n = \(count) days")
                    .font(.r(.caption2, .regular))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                let width = maxValue > 0 ? CGFloat(avg / maxValue) * geo.size.width : 0
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.80)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(width, 4), height: 10)
            }
            .frame(height: 10)
        }
    }
}
