import SwiftUI
import Charts

struct SymptomSection: View {
    let data: ReportData

    private var narrative: SectionNarrative? { data.narratives.sectionNarratives["symptoms"] }

    var body: some View {
        ReportSectionCard(title: narrative?.headline ?? "Symptoms", domain: .symptoms) {
            if let n = narrative {
                Text(n.narrative).font(.r(.subheadline, .regular)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            symptomFrequency
            symptomTimeline
            categoryBreakdown
            foodSensitivityTable
            symptomStressLink
        }
    }

    // MARK: - Frequency

    private var symptomCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for day in data.context.days {
            for name in day.symptomNames { counts[name, default: 0] += 1 }
        }
        return counts
    }

    @ViewBuilder
    private var symptomFrequency: some View {
        let counts = symptomCounts
        if !counts.isEmpty {
            Text("Symptom Frequency").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            let sorted = counts.sorted { $0.value > $1.value }
            Chart {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Days", item.value),
                        y: .value("Symptom", item.key)
                    )
                    .foregroundStyle(WellnessDomain.symptoms.accentColor.opacity(0.7))
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
            .frame(height: CGFloat(counts.count) * 28 + 10)
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var symptomTimeline: some View {
        let timelinePoints = data.context.days.compactMap { d -> (date: Date, maxSeverity: Int, count: Int, stressScore: Double?)? in
            guard !d.symptomNames.isEmpty, let sev = d.symptomMaxSeverity else { return nil }
            return (date: d.date, maxSeverity: sev, count: d.symptomNames.count, stressScore: d.stressScore)
        }
        if timelinePoints.count >= 2 {
            Text("Severity Timeline").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            SymptomTimelineChart(points: timelinePoints)
        }
    }

    // MARK: - Category Breakdown

    private var categoryCountMap: [SymptomCategory: Int] {
        var categoryCounts: [SymptomCategory: Int] = [:]
        let allNames = data.context.days.flatMap(\.symptomNames)
        for name in allNames {
            let cat = SymptomDefinition.library.first(where: { $0.name == name })?.category ?? .cognitive
            categoryCounts[cat, default: 0] += 1
        }
        return categoryCounts
    }

    @ViewBuilder
    private var categoryBreakdown: some View {
        let categoryCounts = categoryCountMap
        if categoryCounts.count >= 2 {
            Text("Category Breakdown").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            SymptomCategoryDonut(slices: categoryCounts.map { (category: $0.key, count: $0.value) })
        }
    }

    // MARK: - Food Sensitivity Table

    @ViewBuilder
    private var foodSensitivityTable: some View {
        let links = data.context.foodSymptomLinks
        if !links.isEmpty {
            Text("Food Sensitivities").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)

            let bySymptom = Dictionary(grouping: links, by: \.symptomName)
            ForEach(Array(bySymptom.keys.sorted()), id: \.self) { symptomName in
                let symptomLinks = bySymptom[symptomName] ?? []
                let triggers = symptomLinks.filter { $0.classification == .potentialTrigger }
                let protective = symptomLinks.filter { $0.classification == .potentialProtective }

                VStack(alignment: .leading, spacing: 6) {
                    Text(symptomName)
                        .font(.r(.subheadline, .bold))
                        .foregroundStyle(.primary)

                    if !triggers.isEmpty {
                        Text("Potential Triggers")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.8))
                        ForEach(triggers) { link in
                            FoodSensitivityRow(link: link)
                        }
                    }

                    if !protective.isEmpty {
                        Text("Potential Protective")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green.opacity(0.8))
                        ForEach(protective) { link in
                            FoodSensitivityRow(link: link)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Correlations require more data to confirm — these patterns may change with additional tracking.")
                    .font(.r(.caption, .regular))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Symptom-Stress Link

    private var symptomStressPaired: (scatter: [(x: Double, y: Double)], r: Double) {
        var scatter: [(x: Double, y: Double)] = []
        for day in data.context.days {
            guard let stress = day.stressScore, let sev = day.symptomMaxSeverity else { continue }
            scatter.append((x: stress, y: Double(sev)))
        }
        let r = scatter.count >= 5 ? CorrelationMath.spearmanR(scatter.map(\.x), scatter.map(\.y)) : 0
        return (scatter, r)
    }

    @ViewBuilder
    private var symptomStressLink: some View {
        let paired = symptomStressPaired
        if paired.scatter.count >= 5 && abs(paired.r) >= 0.2 {
            Text("Stress vs Symptom Severity").font(.r(.footnote, .semibold)).foregroundStyle(.secondary)
            CorrelationScatterChart(points: paired.scatter, r: paired.r, xLabel: "Stress", yLabel: "Severity")
        }
    }
}
