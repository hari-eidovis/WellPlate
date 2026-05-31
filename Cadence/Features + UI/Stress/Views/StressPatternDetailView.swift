//
//  StressPatternDetailView.swift
//  Cadence
//
//  Detailed view of today's stress pattern + 7-day trend, surfaced from
//  a long press on the "Today's Pattern" chart on StressView. Also
//  carries the "Top driver today" summary that previously lived on the
//  Stress tab itself.
//

import SwiftUI

struct StressPatternDetailView: View {

    let todayReadings: [StressReading]
    let weekReadings: [StressReading]

    @Environment(\.dismiss) private var dismiss

    private static let themeBlue = Color(hex: "5E9FFF")

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── TODAY ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("TODAY · \(formattedToday)")
                        todayStatsGrid
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                    // ── 7-DAY TREND ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("7-DAY TREND")
                        StressWeekChartView(readings: weekReadings)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)

                    Spacer().frame(height: 40)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Stress Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Today Stats

    private var todayStatsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            statCell(
                label: "AVERAGE",
                value: avgScore.map { "\(Int($0.rounded()))" } ?? "—",
                subtitle: "of 100",
                tint: .secondary
            )
            statCell(
                label: "READINGS",
                value: "\(todayReadings.count)",
                subtitle: todayReadings.count == 1 ? "captured today" : "captured today",
                tint: .secondary
            )
            statCell(
                label: "PEAK",
                value: peakReading.map { "\(Int($0.score.rounded()))" } ?? "—",
                subtitle: peakReading.map { formatTime($0.timestamp) } ?? "no data",
                tint: Color(hex: "E08A2B")
            )
            statCell(
                label: "LOWEST",
                value: lowReading.map { "\(Int($0.score.rounded()))" } ?? "—",
                subtitle: lowReading.map { formatTime($0.timestamp) } ?? "no data",
                tint: Color(hex: "1FA971")
            )
        }
    }

    private func statCell(label: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint == .secondary ? .primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.card)
                .appShadow(radius: 12, y: 4)
        )
    }

    // MARK: - Computed

    private var avgScore: Double? {
        let scores = todayReadings.map(\.score)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private var peakReading: StressReading? {
        todayReadings.max { $0.score < $1.score }
    }

    private var lowReading: StressReading? {
        todayReadings.min { $0.score < $1.score }
    }

    private var formattedToday: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: Date()).uppercased()
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(1.2)
            .padding(.leading, 4)
    }
}

// MARK: - Preview

#Preview {
    let now = Date()
    let cal = Calendar.current
    let today: [StressReading] = [
        StressReading(timestamp: cal.date(byAdding: .hour, value: -8, to: now)!, score: 28, levelLabel: "Good"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -6, to: now)!, score: 44, levelLabel: "Moderate"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -4, to: now)!, score: 61, levelLabel: "High"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -2, to: now)!, score: 48, levelLabel: "Moderate"),
        StressReading(timestamp: now, score: 72, levelLabel: "High"),
    ]
    var week: [StressReading] = today
    for offset in 1...6 {
        guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
        for _ in 0..<Int.random(in: 0...4) {
            let score = Double.random(in: 22...80)
            week.append(StressReading(timestamp: day, score: score, levelLabel: "Moderate"))
        }
    }
    return StressPatternDetailView(
        todayReadings: today,
        weekReadings: week
    )
}
