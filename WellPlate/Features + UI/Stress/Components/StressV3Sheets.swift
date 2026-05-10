import SwiftUI

// MARK: - AllFactorsSheet

/// Disclosure sheet showing all 13 v3 factors grouped by tier.
struct AllFactorsSheet: View {
    @ObservedObject var viewModel: StressViewModel
    @Environment(\.dismiss) private var dismiss

    private var tierA: [StressFactorResult] {
        viewModel.allFactors.filter { tierAtitles.contains($0.title) }
    }
    private var tierB: [StressFactorResult] {
        viewModel.allFactors.filter { tierBtitles.contains($0.title) }
    }
    private var tierC: [StressFactorResult] {
        viewModel.allFactors.filter { tierCtitles.contains($0.title) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Foundational (Tier A)", factors: tierA)
                    section("Modulators (Tier B)", factors: tierB)
                    section("Subjective (Tier C)", factors: tierC)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("All factors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, factors: [StressFactorResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            VStack(spacing: 8) {
                ForEach(factors, id: \.id) { f in
                    factorRow(f)
                }
            }
        }
    }

    private func factorRow(_ f: StressFactorResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: f.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(f.accentColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(f.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title)
                    .font(.r(.subheadline, .semibold))
                Text(f.statusText)
                    .font(.r(.caption, .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(formattedPoints(f))
                    .font(.r(.caption, .semibold))
                    .foregroundStyle(f.hasValidData ? f.accentColor : .secondary)
                Text("of \(Int(f.maxScore))")
                    .font(.r(.caption2, .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
        )
    }

    private func formattedPoints(_ f: StressFactorResult) -> String {
        guard f.hasValidData else { return "—" }
        let v = f.score
        if v < 0 { return String(format: "%.0f", v) }
        return "+\(Int(v.rounded()))"
    }

    private let tierAtitles: Set<String> = ["Sleep", "Exercise", "Caffeine", "Screen Time", "Diet"]
    private let tierBtitles: Set<String> = ["Hydration", "Circadian", "Daylight", "Meal Timing", "Fasting", "Eating Triggers"]
    private let tierCtitles: Set<String> = ["Mood", "Symptoms"]
}

// MARK: - QuickLogManualSheet

/// Opens an evening-style manual log so the user can volunteer data anytime.
/// Wraps `QuickCheckInSheet` with a synthetic prompt where all evening gaps
/// are requested.
struct QuickLogManualSheet: View {
    @EnvironmentObject private var promptCoordinator: DailyPromptCoordinator

    var body: some View {
        let kind = DailyPromptCoordinator.PromptKind.evening(
            DailyPromptCoordinator.EveningGaps(
                needsScreen: true,
                needsExercise: true,
                needsDaylight: true
            )
        )
        QuickCheckInSheet(kind: kind, coordinator: promptCoordinator)
    }
}
