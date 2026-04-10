import SwiftUI

struct ExecutiveSummarySection: View {
    let data: ReportData

    private var summary: ExecutiveSummaryNarrative { data.narratives.executiveSummary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Executive Summary")
                .font(.r(.headline, .bold))
                .foregroundStyle(.primary)

            Text(summary.narrative)
                .font(.r(.body, .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                pillView(text: summary.topWin, color: .green)
                pillView(text: summary.topConcern, color: .orange)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func pillView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
            .lineLimit(2)
    }
}
