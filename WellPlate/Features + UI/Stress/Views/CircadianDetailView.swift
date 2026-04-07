//
//  CircadianDetailView.swift
//  WellPlate
//

import SwiftUI
import Charts

struct CircadianDetailView: View {

    let result: CircadianService.CircadianResult
    let sleepSummaries: [DailySleepSummary]
    let daylightSamples: [DailyMetricSample]

    @Environment(\.dismiss) private var dismiss

    private var last7Summaries: [DailySleepSummary] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sleepSummaries
            .filter { $0.date >= cutoff && $0.bedtime != nil && $0.wakeTime != nil }
            .sorted { $0.date < $1.date }
    }

    private var last7Daylight: [DailyMetricSample] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return daylightSamples
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // Score Summary
                    scoreSummary
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    // Sleep Regularity
                    if !last7Summaries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("SLEEP REGULARITY")
                            regularityChart
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                    }

                    // Daylight Exposure
                    if result.daylightScore != nil, !last7Daylight.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("DAYLIGHT EXPOSURE")
                            daylightChart
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                    }

                    // Tips
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("TIPS")
                        tipsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                    Spacer().frame(height: 40)
                }
            }
            .navigationTitle("Circadian Health")
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

    // MARK: - Score Summary

    private var scoreSummary: some View {
        VStack(spacing: 8) {
            if result.hasEnoughData {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(result.score))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                    Text("/100")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Text(result.level.rawValue.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(levelColor)
                    .tracking(1.5)

                // Sub-scores
                HStack(spacing: 20) {
                    subScoreView(label: "Regularity", value: result.regularityScore)
                    if let ds = result.daylightScore {
                        subScoreView(label: "Daylight", value: ds)
                    }
                }
                .padding(.top, 8)
            } else {
                Text("Not Enough Data")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Need 5+ nights of sleep data")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func subScoreView(label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value))")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Regularity Chart

    private var regularityChart: some View {
        let data = last7Summaries.compactMap { summary -> SleepBarEntry? in
            guard let bed = summary.bedtime, let wake = summary.wakeTime else { return nil }
            return SleepBarEntry(date: summary.date, bedtime: bed, wakeTime: wake)
        }

        return Chart(data) { entry in
            BarMark(
                x: .value("Date", entry.date, unit: .day),
                yStart: .value("Bedtime", entry.bedtimeHours),
                yEnd: .value("Wake", entry.wakeHours)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.40, green: 0.20, blue: 0.85).opacity(0.7),
                             Color(red: 0.45, green: 0.55, blue: 0.95).opacity(0.7)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .cornerRadius(4)
        }
        .chartYScale(domain: 21...33) // 9 PM (21) to 9 AM next day (33)
        .chartYAxis {
            AxisMarks(values: [22, 24, 26, 28, 30, 32]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(hourLabel(hours))
                            .font(.system(size: 10))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .frame(height: 200)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 8)
        )
    }

    // MARK: - Daylight Chart

    private var daylightChart: some View {
        Chart(last7Daylight) { sample in
            BarMark(
                x: .value("Date", sample.date, unit: .day),
                y: .value("Minutes", sample.value)
            )
            .foregroundStyle(Color.orange.opacity(0.7))
            .cornerRadius(4)

            // Target line at 30 min
            RuleMark(y: .value("Target", 30))
                .foregroundStyle(.orange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .trailing, alignment: .leading) {
                    Text("30 min")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .frame(height: 160)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 8)
        )
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            tipRow(icon: "lightbulb.fill", color: .orange, text: result.tip)

            if result.regularityScore < 70 {
                tipRow(icon: "alarm.fill", color: .indigo,
                       text: "Set a bedtime alarm to build consistency")
            }
            if result.daylightScore != nil, (result.daylightScore ?? 100) < 70 {
                tipRow(icon: "figure.walk", color: .green,
                       text: "A morning walk combines daylight and exercise")
            }
            if result.daylightScore == nil {
                tipRow(icon: "applewatch", color: .secondary,
                       text: "Pair an Apple Watch for daylight tracking")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 8)
        )
    }

    private func tipRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Helpers

    private var levelColor: Color {
        switch result.level {
        case .aligned:   return .green
        case .adjusting: return .orange
        case .disrupted: return .red
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(1.2)
            .padding(.leading, 4)
    }

    /// Convert hours-since-midnight to a label. Values > 24 = next day.
    private func hourLabel(_ h: Double) -> String {
        let adjusted = h >= 24 ? h - 24 : h
        let hour = Int(adjusted)
        let ampm = hour < 12 ? "AM" : "PM"
        let display = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(display) \(ampm)"
    }
}

// MARK: - Sleep Bar Entry

private struct SleepBarEntry: Identifiable {
    let id = UUID()
    let date: Date
    let bedtime: Date
    let wakeTime: Date

    /// Bedtime as hours since midnight (e.g., 23.5 = 11:30 PM).
    /// Values for evening bedtimes stay as-is; we add 24 for display continuity.
    var bedtimeHours: Double {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: bedtime))
        let m = Double(cal.component(.minute, from: bedtime))
        return h + m / 60.0
    }

    /// Wake time as hours since midnight, shifted +24 if it's the next morning.
    var wakeHours: Double {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: wakeTime))
        let m = Double(cal.component(.minute, from: wakeTime))
        let raw = h + m / 60.0
        // If wake is in the morning (< 12) and bed is in the evening (> 12), add 24
        return raw < bedtimeHours ? raw + 24 : raw
    }
}
