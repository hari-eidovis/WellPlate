import SwiftUI
import Charts

private struct MoodDualPoint: Identifiable {
    let id = UUID()
    let date: Date; let value: Double; let series: String
}

struct MoodSection: View {
    let data: ReportData

    var body: some View {
        ReportSectionCard(title: "Mood", domain: .mood) {
            moodDistribution
            moodStressAlignment
        }
    }

    private var moodCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for day in data.context.days {
            guard let mood = day.moodLabel else { continue }
            counts[mood, default: 0] += 1
        }
        return counts
    }

    @ViewBuilder
    private var moodDistribution: some View {
        let counts = moodCounts
        if !counts.isEmpty {
            Text("Mood Distribution").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            let sorted = MoodOption.allCases.compactMap { opt -> (label: String, count: Int)? in
                guard let c = counts[opt.label], c > 0 else { return nil }
                return (label: opt.label, count: c)
            }
            Chart {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Mood", item.label)
                    )
                    .foregroundStyle(WellnessDomain.mood.accentColor.opacity(0.7))
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 10, design: .rounded)) }
            }
            .frame(height: CGFloat(sorted.count) * 28 + 10)

            let most = counts.max(by: { $0.value < $1.value })
            let logged = counts.values.reduce(0, +)
            StatPillRow(pills: [
                (label: "Most common", value: most?.key ?? "—", color: nil),
                (label: "Logged", value: "\(logged) of \(data.context.days.count) days", color: nil),
            ])
        }
    }

    @ViewBuilder
    private var moodStressAlignment: some View {
        let paired = data.context.days.compactMap { d -> (date: Date, mood: Double, stress: Double)? in
            guard let moodLabel = d.moodLabel,
                  let mood = MoodOption.allCases.first(where: { $0.label == moodLabel }),
                  let stress = d.stressScore else { return nil }
            return (date: d.date, mood: Double(4 - mood.rawValue) * 25, stress: stress)
        }

        if paired.count >= 5 {
            Text("Mood vs Stress").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)

            let points: [MoodDualPoint] = paired.flatMap { p in
                [
                    MoodDualPoint(date: p.date, value: p.mood, series: "Mood (inverted)"),
                    MoodDualPoint(date: p.date, value: p.stress, series: "Stress"),
                ]
            }

            Chart(points) { pt in
                LineMark(
                    x: .value("Day", pt.date, unit: .day),
                    y: .value("Score", pt.value)
                )
                .foregroundStyle(by: .value("Series", pt.series))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale([
                "Mood (inverted)": WellnessDomain.mood.accentColor,
                "Stress": WellnessDomain.stress.accentColor,
            ])
            .chartLegend(position: .bottom, spacing: 8)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true).font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 140)
        }
    }
}
