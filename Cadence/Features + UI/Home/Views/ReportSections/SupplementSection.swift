import SwiftUI
import Charts

struct SupplementSection: View {
    let data: ReportData

    var body: some View {
        ReportSectionCard(title: "Supplement Adherence", domain: .supplements) {
            overallGauge
            perSupplementBreakdown
        }
    }

    @ViewBuilder
    private var overallGauge: some View {
        let adherenceValues = data.context.days.compactMap(\.supplementAdherence)
        if !adherenceValues.isEmpty {
            let avg = adherenceValues.reduce(0, +) / Double(adherenceValues.count)
            HStack {
                Spacer()
                AdherenceGauge(rate: avg, label: "Overall")
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var perSupplementBreakdown: some View {
        let supplements = data.context.perSupplementAdherence
        if !supplements.isEmpty {
            Text("Per Supplement").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(supplements.enumerated()), id: \.offset) { _, supp in
                    BarMark(
                        x: .value("Rate", supp.rate * 100),
                        y: .value("Name", supp.name)
                    )
                    .foregroundStyle(adherenceColor(supp.rate))
                    .cornerRadius(4)
                }
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 10, design: .rounded)) }
            }
            .frame(height: CGFloat(supplements.count) * 30 + 10)
        }
    }

    private func adherenceColor(_ rate: Double) -> Color {
        if rate >= 0.8 { return .green }
        if rate >= 0.5 { return .orange }
        return .red
    }
}
