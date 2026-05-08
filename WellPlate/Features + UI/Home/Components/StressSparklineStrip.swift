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
    @State private var nowPulse = false

    // MARK: - Computed Helpers

    private var latestScore: Double? { readings.last?.score }

    private var latestLevel: StressLevel? {
        latestScore.map { StressLevel(score: $0) }
    }

    private var accentColor: Color {
        latestLevel?.color ?? Color(.systemGray3)
    }

    private var peakScore: Double? { readings.map(\.score).max() }
    private var avgScore: Double? {
        guard !readings.isEmpty else { return nil }
        return readings.map(\.score).reduce(0, +) / Double(readings.count)
    }

    private var startTimeLabel: String? {
        guard let first = readings.first?.timestamp else { return nil }
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f.string(from: first).lowercased()
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
            return "\(period) ↓\(pts)"
        } else {
            return "\(period) ↑\(pts)"
        }
    }

    // MARK: - Body

    var body: some View {
        Button(action: { HapticService.impact(.medium); onTap() }) {
            VStack(alignment: .leading, spacing: 12) {
                topBar
                heroRow
                chartArea
                footerRow
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
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                nowPulse = true
            }
        }
    }

    // MARK: - Top Bar (caption + chevron)

    private var topBar: some View {
        HStack(spacing: 6) {
            Text("Stress today")
                .font(.r(.caption, .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    // MARK: - Hero Row (score + level + trend pill)

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let score = latestScore {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                if let level = stressLevel {
                    Text(level)
                        .font(.r(.subheadline, .semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(accentColor.opacity(0.14))
                        )
                }
            } else {
                Text("—")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let delta = scoreDelta {
                trendPill(delta: delta)
            }
        }
    }

    private func trendPill(delta: Int) -> some View {
        let worse = delta > 0
        let tint = worse ? AppColors.error : AppColors.success
        return HStack(spacing: 4) {
            Image(systemName: worse ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text("\(abs(delta))")
                .font(.r(.caption, .bold))
            Text("vs yest.")
                .font(.r(.caption2, .regular))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.12)))
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
        .frame(height: 64)
    }

    private var emptyChartPlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(.systemGray3))
            Text("Trend appears once we have a few readings")
                .font(.r(.caption2, .regular))
                .foregroundStyle(Color(.systemGray))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
        )
    }

    private var realChart: some View {
        let lineGradient = LinearGradient(
            colors: [
                StressLevel(score: 75).color,
                StressLevel(score: 50).color,
                StressLevel(score: 25).color
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        return Chart(chartPoints) { p in
            // Soft zone dividers at moderate (40) and high (60) thresholds.
            RuleMark(y: .value("Moderate", 40))
                .foregroundStyle(Color(.systemGray4).opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            RuleMark(y: .value("High", 60))
                .foregroundStyle(Color(.systemGray4).opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

            AreaMark(
                x: .value("Time", p.timestamp),
                y: .value("Stress", p.score)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [accentColor.opacity(0.28), accentColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", p.timestamp),
                y: .value("Stress", p.score)
            )
            .foregroundStyle(lineGradient)
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.catmullRom)

            // Pulsing "now" dot on the latest reading.
            if let last = readings.last {
                PointMark(
                    x: .value("Time", last.timestamp),
                    y: .value("Stress", last.score)
                )
                .symbol {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.25))
                            .frame(width: nowPulse ? 18 : 10, height: nowPulse ? 18 : 10)
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 9, height: 9)
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .mask {
            Rectangle()
                .scaleEffect(x: lineDrawn ? 1 : 0, anchor: .leading)
        }
    }

    // MARK: - Footer Row (start time, stats, now)

    private var footerRow: some View {
        HStack(spacing: 6) {
            if let start = startTimeLabel {
                Text(start)
                    .font(.r(.caption2, .regular))
                    .foregroundStyle(Color(.tertiaryLabel))
            }

            Spacer(minLength: 4)

            if let peak = peakScore, let avg = avgScore, readings.count >= 2 {
                statChip(label: "Avg", value: Int(avg.rounded()))
                statDivider
                statChip(label: "Peak", value: Int(peak.rounded()))
                if let note = inflectionAnnotation {
                    statDivider
                    Text(note)
                        .font(.r(.caption2, .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Text("Now")
                .font(.r(.caption2, .semibold))
                .foregroundStyle(accentColor)
        }
    }

    private func statChip(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.r(.caption2, .regular))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.r(.caption2, .bold))
                .foregroundStyle(.primary)
        }
    }

    private var statDivider: some View {
        Text("·")
            .font(.r(.caption2, .regular))
            .foregroundStyle(Color(.tertiaryLabel))
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
