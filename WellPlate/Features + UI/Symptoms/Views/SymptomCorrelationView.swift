import SwiftUI

// MARK: - SymptomCorrelationView

struct SymptomCorrelationView: View {
    let symptomName: String
    @ObservedObject var engine: SymptomCorrelationEngine

    var body: some View {
        Group {
            if engine.isComputing {
                loadingView
            } else if engine.correlations.isEmpty {
                emptyView
            } else {
                correlationList
            }
        }
        .navigationTitle("\(symptomName) Insights")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Analysing patterns…")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("Not enough data yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Log symptoms for 7+ days to see\nhow they relate to your habits.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Correlation List

    private var correlationList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(engine.correlations) { correlation in
                    if correlation.pairedDays >= 7 {
                        correlationCard(correlation)
                    } else {
                        collectingDataCard(correlation)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Correlation Card (sufficient data)

    private func correlationCard(_ c: SymptomCorrelation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: c.factorIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.brand)
                Text(c.factorName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text("N=\(c.pairedDays)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // r value + interpretation
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "r = %.2f", c.spearmanR))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(rColor(c.spearmanR, significant: c.isSignificant))
                Text(c.interpretation)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // CI band visualization
            ciBand(r: c.spearmanR, ciLow: c.ciLow, ciHigh: c.ciHigh)

            // CI text
            Text(String(format: "95%% CI: [%.2f, %.2f]", c.ciLow, c.ciHigh))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            // Disclaimer
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Correlation does not imply causation. Track more days to strengthen confidence.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
        )
    }

    // MARK: - CI Band

    private func ciBand(r: Double, ciLow: Double, ciHigh: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let midX = w / 2
            // Range is −1.0 to +1.0 (total range 2.0)
            let scale = w / 2.0
            let loX  = midX + CGFloat(ciLow) * scale
            let hiX  = midX + CGFloat(ciHigh) * scale
            let dotX = midX + CGFloat(r) * scale
            let bandWidth = max(4, hiX - loX)

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color(.systemFill))
                    .frame(height: 6)

                // CI band
                Capsule()
                    .fill(AppColors.brand.opacity(0.25))
                    .frame(width: bandWidth, height: 10)
                    .offset(x: min(loX, hiX))

                // Dot at r
                Circle()
                    .fill(AppColors.brand)
                    .frame(width: 14, height: 14)
                    .offset(x: dotX - 7)

                // Zero line
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1.5, height: 20)
                    .offset(x: midX - 0.75)
            }
        }
        .frame(height: 20)
    }

    // MARK: - Collecting Data Card

    private func collectingDataCard(_ c: SymptomCorrelation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: c.factorIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(c.factorName)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            // Progress pill
            Text("\(c.pairedDays)/7 days")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.7))
        )
    }

    // MARK: - Helpers

    private func rColor(_ r: Double, significant: Bool) -> Color {
        guard significant else { return .secondary }
        if r > 0 { return Color(hue: 0.00, saturation: 0.65, brightness: 0.80) } // red — more symptom
        return Color(hue: 0.38, saturation: 0.58, brightness: 0.72) // green — less symptom
    }
}

// MARK: - Preview

#Preview("Correlation View") {
    let engine = SymptomCorrelationEngine()
    // Inject mock correlations
    Task { @MainActor in
        engine.correlations = [
            SymptomCorrelation(symptomName: "Headache", factorName: "Caffeine", factorIcon: "cup.and.saucer.fill", spearmanR: 0.52, ciLow: 0.18, ciHigh: 0.79, pairedDays: 14, interpretation: "moderate positive association", isSignificant: true),
            SymptomCorrelation(symptomName: "Headache", factorName: "Sleep hours", factorIcon: "moon.stars.fill", spearmanR: -0.38, ciLow: -0.65, ciHigh: -0.04, pairedDays: 14, interpretation: "moderate negative association", isSignificant: true),
            SymptomCorrelation(symptomName: "Headache", factorName: "Fiber", factorIcon: "leaf.fill", spearmanR: 0, ciLow: -1, ciHigh: 1, pairedDays: 3, interpretation: "Collecting data", isSignificant: false),
        ]
    }
    return NavigationStack {
        SymptomCorrelationView(symptomName: "Headache", engine: engine)
    }
}
