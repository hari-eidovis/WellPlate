import SwiftUI
import SwiftData
import Charts

// MARK: - StressSparklineStrip
//
// Compact home-screen card showing today's intraday stress trajectory
// as a sparkline chart with score, delta badge, and auto-annotation.
// Taps navigate to the Stress tab.

struct StressSparklineStrip: View {
    let readings: [StressReading]
    let stressLevel: String?
    let scoreDelta: Int?
    var onTap: () -> Void

    // MARK: - Chart Data Model

    private struct IntradayPoint: Identifiable {
        let id: Int
        let timestamp: Date
        let score: Double
    }

    private var chartPoints: [IntradayPoint] {
        readings.enumerated().map {
            IntradayPoint(id: $0.offset, timestamp: $0.element.timestamp, score: $0.element.score)
        }
    }

    // MARK: - Animation

    @State private var lineDrawn = false

    // MARK: - Computed Helpers

    private var latestScore: Double? { readings.last?.score }

    private var latestLevel: StressLevel? {
        latestScore.map { StressLevel(score: $0) }
    }

    private var emoji: String {
        switch stressLevel?.lowercased() {
        case "excellent": return "😄"
        case "good":      return "😌"
        case "moderate":  return "😐"
        case "high":      return "😣"
        case "very high": return "😰"
        default:          return "—"
        }
    }

    private var accentColor: Color {
        latestLevel?.color ?? Color(.systemGray3)
    }

    /// Finds the pair of consecutive readings with the largest absolute delta.
    /// Returns a caption only when |delta| >= 8.
    private var inflectionAnnotation: String? {
        guard readings.count >= 2 else { return nil }
        var maxDelta: Double = 0
        var maxIdx = 1
        for i in 1..<readings.count {
            let delta = readings[i].score - readings[i - 1].score
            if abs(delta) > abs(maxDelta) {
                maxDelta = delta
                maxIdx = i
            }
        }
        guard abs(maxDelta) >= 8 else { return nil }
        let pts = Int(abs(maxDelta).rounded())
        let hour = Calendar.current.component(.hour, from: readings[maxIdx].timestamp)
        let period: String
        switch hour {
        case 5..<12:  period = "Morning"
        case 12..<17: period = "Afternoon"
        default:      period = "Evening"
        }
        if maxDelta < 0 {
            return "\(period) activity helped ↓\(pts) pts"
        } else {
            return "\(period) spike ↑\(pts) pts"
        }
    }

    // MARK: - Body

    var body: some View {
        Button(action: { HapticService.impact(.medium); onTap() }) {
            VStack(alignment: .leading, spacing: 8) {
                headerRow
                chartArea
                if let note = inflectionAnnotation {
                    Text(note)
                        .font(.r(.caption2, .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 15, y: 5)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.75)) {
                lineDrawn = true
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("Stress today")
                .font(.r(.subheadline, .semibold))
                .foregroundStyle(.primary)

            Spacer()

            // Delta badge
            if let delta = scoreDelta {
                let worse = delta > 0
                Text("\(worse ? "↑" : "↓") \(abs(delta))")
                    .font(.r(.caption2, .semibold))
                    .foregroundStyle(worse ? AppColors.error : AppColors.success)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((worse ? AppColors.error : AppColors.success).opacity(0.12))
                    )
            }

            // Emoji + score + level
            if let score = latestScore {
                HStack(spacing: 4) {
                    Text(emoji)
                        .font(.system(size: 15))
                    Text("\(Int(score.rounded()))")
                        .font(.r(.subheadline, .bold))
                        .foregroundStyle(.primary)
                    if let lvl = stressLevel {
                        Text(lvl)
                            .font(.r(.caption, .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("—")
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chart Area

    private var chartArea: some View {
        Group {
            if readings.count < 2 {
                emptyChartPlaceholder
            } else {
                realChart
            }
        }
        .frame(height: 52)
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 0.5)
                .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .frame(height: 1)
            Text("No stress data yet")
                .font(.r(.caption2, .regular))
                .foregroundStyle(Color(.systemGray3))
        }
        .frame(maxWidth: .infinity)
    }

    private var realChart: some View {
        Chart(chartPoints) { p in
            AreaMark(
                x: .value("Time", p.timestamp),
                y: .value("Stress", p.score)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [accentColor.opacity(0.20), accentColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", p.timestamp),
                y: .value("Stress", p.score)
            )
            .foregroundStyle(accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .mask {
            Rectangle()
                .scaleEffect(x: lineDrawn ? 1 : 0, anchor: .leading)
        }
    }
}

// MARK: - Previews

#Preview("StressSparklineStrip — Filled") {
    let now = Date()
    let cal = Calendar.current
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: StressReading.self, configurations: config)
    let readings = [
        StressReading(timestamp: cal.date(byAdding: .hour, value: -6, to: now)!, score: 58, levelLabel: "Moderate"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -4, to: now)!, score: 72, levelLabel: "High"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -2, to: now)!, score: 48, levelLabel: "Moderate"),
        StressReading(timestamp: now, score: 34, levelLabel: "Good"),
    ]
    return StressSparklineStrip(readings: readings, stressLevel: "Good", scoreDelta: -18, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .modelContainer(container)
}

#Preview("StressSparklineStrip — Empty") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: StressReading.self, configurations: config)
    return StressSparklineStrip(readings: [], stressLevel: nil, scoreDelta: nil, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .modelContainer(container)
}
