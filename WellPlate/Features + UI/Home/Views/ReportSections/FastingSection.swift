import SwiftUI

struct FastingSection: View {
    let data: ReportData

    var body: some View {
        ReportSectionCard(title: "Fasting", domain: .fasting) {
            fastingSummary
            fastingStressLink
        }
    }

    @ViewBuilder
    private var fastingSummary: some View {
        let fastingDays = data.context.days.filter { $0.fastingHours != nil }
        if !fastingDays.isEmpty {
            let totalSessions = fastingDays.count
            let completed = fastingDays.filter { $0.fastingCompleted == true }.count
            let avgHours = fastingDays.compactMap(\.fastingHours).reduce(0, +) / Double(fastingDays.count)
            let longest = fastingDays.compactMap(\.fastingHours).max() ?? 0

            StatPillRow(pills: [
                (label: "Sessions", value: "\(totalSessions)", color: nil),
                (label: "Completed", value: "\(completed)", color: .green),
                (label: "Avg", value: String(format: "%.1fh", avgHours), color: nil),
                (label: "Longest", value: String(format: "%.1fh", longest), color: .orange),
            ])
        }
    }

    @ViewBuilder
    private var fastingStressLink: some View {
        let fastingDays = data.context.days.filter { $0.fastingHours != nil && $0.stressScore != nil }
        let nonFastingDays = data.context.days.filter { $0.fastingHours == nil && $0.stressScore != nil }

        if fastingDays.count >= 3 && nonFastingDays.count >= 3 {
            let fastingStress = fastingDays.compactMap(\.stressScore).reduce(0, +) / Double(fastingDays.count)
            let nonFastingStress = nonFastingDays.compactMap(\.stressScore).reduce(0, +) / Double(nonFastingDays.count)

            Text("Fasting vs Non-Fasting Stress").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            ComparisonBarChart(bars: [
                (label: "Fasting", value: fastingStress, domain: .fasting),
                (label: "Non-fasting", value: nonFastingStress, domain: .fasting),
            ], highlight: fastingStress < nonFastingStress ? 0 : 1)
        }
    }
}
