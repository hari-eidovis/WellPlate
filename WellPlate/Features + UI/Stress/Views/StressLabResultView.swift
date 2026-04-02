import SwiftUI
import SwiftData

struct StressLabResultView: View {
    let experiment: StressExperiment
    let allReadings: [StressReading]

    @State private var result: StressLabResult? = nil
    @State private var isComputing = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isComputing {
                        ProgressView("Analyzing\u{2026}")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let result {
                        resultContent(result)
                    } else {
                        notEnoughDataView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(experiment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppColors.brand)
                }
            }
        }
        .presentationDetents([.large])
        .task {
            let computed = await Task.detached(priority: .userInitiated) {
                StressLabAnalyzer.analyze(experiment: experiment, allReadings: allReadings)
            }.value
            result = computed
            isComputing = false

            if let r = computed {
                experiment.cachedBaselineAvg   = r.baselineAvg
                experiment.cachedExperimentAvg = r.experimentAvg
                experiment.cachedDelta         = r.delta
                experiment.cachedCILow         = r.ciLow
                experiment.cachedCIHigh        = r.ciHigh
                if experiment.completedAt == nil && experiment.isComplete {
                    experiment.completedAt = experiment.endDate
                }
                try? modelContext.save()
            }
        }
    }

    // MARK: - Result Content

    private func resultContent(_ r: StressLabResult) -> some View {
        VStack(spacing: 20) {
            scoreComparisonCard(r)
            confidenceCard(r)
            interpretationCard(r)
            dataCoverageNote(r)
        }
    }

    private func scoreComparisonCard(_ r: StressLabResult) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Before")
                        .font(.r(.caption, .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .textCase(.uppercase)
                    Text(String(format: "%.1f", r.baselineAvg))
                        .font(.r(.largeTitle, .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("avg stress")
                        .font(.r(.caption2, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Image(systemName: r.delta < 0 ? "arrow.down" : "arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(r.delta < 0 ? .green : .red)
                    Text(String(format: "%+.1f", r.delta))
                        .font(.r(.headline, .bold))
                        .foregroundColor(r.delta < 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("During")
                        .font(.r(.caption, .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .textCase(.uppercase)
                    Text(String(format: "%.1f", r.experimentAvg))
                        .font(.r(.largeTitle, .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("avg stress")
                        .font(.r(.caption2, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func confidenceCard(_ r: StressLabResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confidence Band (90%)")
                .font(.r(.subheadline, .semibold))
                .foregroundColor(AppColors.textPrimary)

            GeometryReader { geo in
                let range = 40.0
                let midX  = geo.size.width / 2
                let scale = geo.size.width / range
                let loX   = midX + CGFloat(r.ciLow)  * scale
                let hiX   = midX + CGFloat(r.ciHigh) * scale
                let dotX  = midX + CGFloat(r.delta)  * scale

                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 6)
                    Capsule()
                        .fill(AppColors.brand.opacity(0.25))
                        .frame(width: max(4, hiX - loX), height: 10)
                        .offset(x: min(loX, hiX))
                    Circle()
                        .fill(AppColors.brand)
                        .frame(width: 14, height: 14)
                        .offset(x: dotX - 7)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 20)
                        .offset(x: midX)
                }
            }
            .frame(height: 20)

            Text("The band shows where the true delta likely falls. A band entirely below zero suggests a real improvement; one crossing zero is inconclusive.")
                .font(.r(.caption, .regular))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func interpretationCard(_ r: StressLabResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .foregroundColor(AppColors.brand)
                Text("What the data shows")
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
            Text(interpretation(for: r))
                .font(.r(.subheadline, .regular))
                .foregroundColor(AppColors.textSecondary)
            Text("This is an observation, not a proof. Many factors affect stress \u{2014} this experiment can't isolate just one.")
                .font(.r(.caption, .regular))
                .foregroundColor(AppColors.textSecondary.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func dataCoverageNote(_ r: StressLabResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            Text("Based on \(r.baselineDayCount) baseline days and \(r.experimentDayCount) experiment days with stress readings.")
                .font(.r(.caption, .regular))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private var notEnoughDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textSecondary.opacity(0.4))
            Text("Not enough data yet")
                .font(.r(.headline, .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text("At least 3 days of stress readings are needed in both the baseline (7 days before) and experiment windows. Keep the app open daily to collect more data.")
                .font(.r(.subheadline, .regular))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func interpretation(for r: StressLabResult) -> String {
        let deltaMag = abs(r.delta)
        let ciSpansZero = r.ciLow < 0 && r.ciHigh > 0

        if ciSpansZero {
            return "During \"\(experiment.name)\", your average stress was \(String(format: "%.1f", r.experimentAvg)) compared to \(String(format: "%.1f", r.baselineAvg)) before. The difference (\(String(format: "%+.1f", r.delta)) points) is within the range of normal variation \u{2014} the data doesn\u{2019}t clearly support or contradict your hypothesis."
        } else if r.delta < 0 {
            return "During \"\(experiment.name)\", your average stress dropped \(String(format: "%.1f", deltaMag)) points \u{2014} from \(String(format: "%.1f", r.baselineAvg)) to \(String(format: "%.1f", r.experimentAvg)). The confidence band sits below zero, suggesting this wasn\u{2019}t random variation."
        } else {
            return "During \"\(experiment.name)\", your average stress rose \(String(format: "%.1f", deltaMag)) points \u{2014} from \(String(format: "%.1f", r.baselineAvg)) to \(String(format: "%.1f", r.experimentAvg)). The confidence band sits above zero. This could mean the intervention didn\u{2019}t help, or that other factors were at play."
        }
    }
}
