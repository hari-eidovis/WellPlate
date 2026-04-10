import SwiftUI

struct CrossDomainSection: View {
    let data: ReportData

    private var correlations: [CrossCorrelation] { data.context.crossCorrelations }

    var body: some View {
        ReportSectionCard(title: "Cross-Domain Patterns", domain: .cross) {
            correlationMatrix
            top3Links
            disclaimer
        }
    }

    // MARK: - Matrix

    @ViewBuilder
    private var correlationMatrix: some View {
        if correlations.count >= 2 {
            let allMetrics = Set(correlations.flatMap { [$0.xName, $0.yName] })
            let metrics = Array(allMetrics.prefix(8)).sorted()

            let metricToIdx = Dictionary(uniqueKeysWithValues: metrics.enumerated().map { ($0.element, $0.offset) })

            let matrixCells: [(xIdx: Int, yIdx: Int, r: Double, isSignificant: Bool)] = correlations.compactMap { c in
                guard let xi = metricToIdx[c.xName], let yi = metricToIdx[c.yName] else { return nil }
                return (xIdx: xi, yIdx: yi, r: c.spearmanR, isSignificant: c.isSignificant)
            }

            Text("Correlation Matrix").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            CorrelationMatrixChart(metrics: metrics, correlations: matrixCells)
        }
    }

    // MARK: - Top 3

    @ViewBuilder
    private var top3Links: some View {
        let top = Array(correlations.prefix(3))
        if !top.isEmpty {
            Text("Strongest Links").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)

            ForEach(top) { corr in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(corr.xName) & \(corr.yName)")
                            .font(.r(.subheadline, .semibold))
                        Spacer()
                        Text(String(format: "r = %.2f", corr.spearmanR))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(corr.spearmanR < 0 ? Color.blue : Color.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                    CorrelationScatterChart(
                        points: corr.scatterPoints,
                        r: corr.spearmanR,
                        xLabel: corr.xName,
                        yLabel: corr.yName
                    )
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }
        }
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Correlation does not imply causation. Continue tracking to strengthen confidence in these patterns.")
                .font(.r(.caption, .regular))
                .foregroundStyle(.tertiary)
        }
    }
}
