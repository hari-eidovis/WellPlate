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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fasting & Stress")
                .font(.r(.headline, .semibold))

            if hasSufficientData {
                dataView
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
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.7))
                    .frame(width: max(width, 4), height: 8)
            }
            .frame(height: 8)
        }
    }
}
