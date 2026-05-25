import SwiftUI

// MARK: - AI15DayReportView

struct AI15DayReportView: View {
    @StateObject private var viewModel = AI15DayReportViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            switch viewModel.reportState {
            case .idle:
                loadingView(progress: 0)
            case .generating(let progress):
                loadingView(progress: progress)
            case .ready(let data):
                reportContent(data: data)
            case .error(let message):
                errorView(message: message)
            }
        }
        .navigationTitle("Wellness Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.bindContext(modelContext)
            Task { await viewModel.generateReport() }
        }
    }

    // MARK: - Loading

    private func loadingView(progress: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Analyzing your wellness data...")
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
            if progress > 0 {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.brand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Report Generation Failed")
                .font(.r(.title3, .bold))
            Text(message)
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await viewModel.clearAndRegenerate() }
            } label: {
                Text("Retry")
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppColors.brand))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Report Content

    private func reportContent(data: ReportData) -> some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                let sections = visibleSections(data: data)

                ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                    section
                        .insightEntrance(index: idx)
                }

                reportFooter
                    .insightEntrance(index: sections.count)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    private func visibleSections(data: ReportData) -> [AnyView] {
        var sections: [AnyView] = []
        let days = data.context.days

        // Always
        sections.append(AnyView(ReportHeaderSection(data: data)))
        sections.append(AnyView(ExecutiveSummarySection(data: data)))

        // Stress
        if days.contains(where: { $0.stressScore != nil }) {
            sections.append(AnyView(StressDeepDiveSection(data: data)))
        }

        // Nutrition
        if days.contains(where: { $0.totalCalories != nil }) {
            sections.append(AnyView(NutritionSection(data: data)))
        }

        // Sleep
        if days.contains(where: { $0.sleepHours != nil }) {
            sections.append(AnyView(SleepSection(data: data)))
        }

        // Activity
        if days.contains(where: { $0.steps != nil || $0.activeCalories != nil }) {
            sections.append(AnyView(ActivitySection(data: data)))
        }

        // Vitals
        if !data.context.availableVitals.isEmpty {
            sections.append(AnyView(VitalsSection(data: data)))
        }

        // Hydration & Caffeine
        if days.contains(where: { ($0.waterGlasses ?? 0) > 0 || ($0.coffeeCups ?? 0) > 0 }) {
            sections.append(AnyView(HydrationCaffeineSection(data: data)))
        }

        // Symptoms
        if days.contains(where: { !$0.symptomNames.isEmpty }) {
            sections.append(AnyView(SymptomSection(data: data)))
        }

        // Supplements
        if days.contains(where: { $0.supplementAdherence != nil }) {
            sections.append(AnyView(SupplementSection(data: data)))
        }

        // Fasting
        if days.contains(where: { $0.fastingHours != nil }) {
            sections.append(AnyView(FastingSection(data: data)))
        }

        // Mood
        if days.contains(where: { $0.moodLabel != nil }) {
            sections.append(AnyView(MoodSection(data: data)))
        }

        // Cross-Domain
        if !data.context.crossCorrelations.isEmpty {
            sections.append(AnyView(CrossDomainSection(data: data)))
        }

        // Always
        sections.append(AnyView(ActionPlanSection(data: data)))

        return sections
    }

    // MARK: - Footer

    private var reportFooter: some View {
        VStack(spacing: 12) {
            if case .ready(let data) = viewModel.reportState {
                let f = DateFormatter()
                let _ = f.timeStyle = .short
                Text("Generated today at \(f.string(from: data.generatedAt))")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Button {
                HapticService.impact(.light)
                Task { await viewModel.clearAndRegenerate() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Regenerate")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(AppColors.brand)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(AppColors.brand.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}
