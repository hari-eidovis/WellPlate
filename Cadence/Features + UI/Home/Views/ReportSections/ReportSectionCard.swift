import SwiftUI

struct ReportSectionCard<Content: View>: View {
    let title: String
    let domain: WellnessDomain
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: domain.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(domain.accentColor)
                Text(domain.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(domain.accentColor)
                    .tracking(1.0)
            }

            Text(title)
                .font(.r(.headline, .bold))
                .foregroundStyle(.primary)

            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }
}
