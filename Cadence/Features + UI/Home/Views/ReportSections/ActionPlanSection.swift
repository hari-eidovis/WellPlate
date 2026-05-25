import SwiftUI

struct ActionPlanSection: View {
    let data: ReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("ACTION PLAN")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
                    .tracking(1.0)
            }

            Text("Personalised Recommendations")
                .font(.r(.headline, .bold))
                .foregroundStyle(.primary)

            ForEach(Array(data.narratives.actionPlan.enumerated()), id: \.element.id) { idx, rec in
                recommendationCard(index: idx + 1, rec: rec)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func recommendationCard(index: Int, rec: ActionRecommendation) -> some View {
        let domain = WellnessDomain(rawValue: rec.domain)
        let color = domain?.accentColor ?? AppColors.brand

        return HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(rec.title)
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                Text(rec.rationale)
                    .font(.r(.caption, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.06))
        )
    }
}
