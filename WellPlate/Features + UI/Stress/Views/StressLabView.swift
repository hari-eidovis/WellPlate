import SwiftUI
import SwiftData

// Single enum drives all sheets in this view (CLAUDE.md: no multiple .sheet() calls)
private enum StressLabSheet: Identifiable {
    case create
    case result(StressExperiment)

    var id: String {
        switch self {
        case .create:        return "create"
        case .result(let e): return "result_\(e.persistentModelID)"
        }
    }
}

struct StressLabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StressExperiment.createdAt, order: .reverse) private var experiments: [StressExperiment]
    @Query private var allReadings: [StressReading]

    @State private var activeLabSheet: StressLabSheet? = nil

    // 30-day predicate — only readings needed for analysis (M1 audit fix)
    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        _allReadings = Query(
            filter: #Predicate<StressReading> { $0.timestamp >= cutoff },
            sort: \.timestamp,
            order: .forward
        )
    }

    private var activeExperiment: StressExperiment? {
        experiments.first { !$0.isComplete }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let active = activeExperiment {
                        activeCard(active)
                    } else {
                        emptyActiveCard
                    }

                    let past = experiments.filter { $0.isComplete }
                    if !past.isEmpty {
                        pastExperimentsSection(past)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stress Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.r(.body, .medium))
                        .foregroundColor(AppColors.brand)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if activeExperiment == nil {
                        Button {
                            HapticService.impact(.light)
                            activeLabSheet = .create
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                        }
                    }
                }
            }
            .sheet(item: $activeLabSheet) { sheet in
                switch sheet {
                case .create:
                    StressLabCreateView()
                case .result(let exp):
                    StressLabResultView(experiment: exp, allReadings: allReadings)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Active Card

    private func activeCard(_ exp: StressExperiment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: exp.resolvedInterventionType.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exp.name)
                        .font(.r(.headline, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(exp.resolvedInterventionType.label)
                        .font(.r(.caption, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(exp.daysRemaining)")
                        .font(.r(.title2, .bold))
                        .foregroundColor(AppColors.brand)
                    Text("days left")
                        .font(.r(.caption2, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            let progress = min(1.0, Double(exp.daysElapsed) / Double(exp.durationDays))
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.brand.opacity(0.15))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.brand)
                            .frame(width: geo.size.width * progress, height: 6)
                    }
                }
                .frame(height: 6)
                Text("Day \(exp.daysElapsed) of \(exp.durationDays)")
                    .font(.r(.caption2, .regular))
                    .foregroundColor(AppColors.textSecondary)
            }

            if let hypothesis = exp.hypothesis, !hypothesis.isEmpty {
                Text("\u{201C}\(hypothesis)\u{201D}")
                    .font(.r(.caption, .regular))
                    .foregroundColor(AppColors.textSecondary)
                    .italic()
            }

            Button(role: .destructive) {
                modelContext.delete(exp)
                try? modelContext.save()
            } label: {
                Label("Delete experiment", systemImage: "trash")
                    .font(.r(.caption, .regular))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private var emptyActiveCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "flask.fill")
                .font(.system(size: 36))
                .foregroundColor(AppColors.brand.opacity(0.4))
            Text("No active experiment")
                .font(.r(.headline, .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text("Pick a micro-intervention, run it for 7–14 days, and see if your stress score changes.")
                .font(.r(.subheadline, .regular))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                HapticService.impact(.light)
                activeLabSheet = .create
            } label: {
                Text("Start an Experiment")
                    .font(.r(.body, .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    // MARK: - Past Experiments

    private func pastExperimentsSection(_ past: [StressExperiment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Experiments")
                .font(.r(.subheadline, .semibold))
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 4)
            ForEach(past) { exp in
                pastRow(exp)
            }
        }
    }

    private func pastRow(_ exp: StressExperiment) -> some View {
        Button {
            activeLabSheet = .result(exp)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: exp.resolvedInterventionType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exp.name)
                        .font(.r(.subheadline, .medium))
                        .foregroundColor(AppColors.textPrimary)
                    Text("\(exp.durationDays)-day experiment")
                        .font(.r(.caption, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                if let delta = exp.cachedDelta {
                    deltaLabel(delta)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private func deltaLabel(_ delta: Double) -> some View {
        let improved = delta < 0
        let text = improved ? "\(String(format: "%.1f", delta))" : "+\(String(format: "%.1f", delta))"
        let color: Color = improved ? .green : .red
        return Text(text)
            .font(.r(.caption, .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
