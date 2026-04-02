import SwiftUI
import SwiftData

struct StressLabCreateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var hypothesis: String = ""
    @State private var selectedType: InterventionType = .caffeine
    @State private var durationDays: Int = 7

    var body: some View {
        NavigationStack {
            Form {
                Section("Intervention Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(InterventionType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: selectedType) { _ in
                        if name.isEmpty { name = selectedType.label }
                        if hypothesis.isEmpty { hypothesis = selectedType.suggestedHypothesis }
                    }
                }

                Section("Experiment Name") {
                    TextField("e.g. No caffeine after 2pm", text: $name)
                }

                Section {
                    TextField("Optional — what do you expect to happen?", text: $hypothesis, axis: .vertical)
                        .lineLimit(3...5)
                } header: {
                    Text("Hypothesis (optional)")
                } footer: {
                    Text("Keep it honest. The result will tell you what the data shows — not what you hoped.")
                        .font(.r(.caption2, .regular))
                }

                Section("Duration") {
                    Picker("Duration", selection: $durationDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("The app will compare your average stress score during this experiment against the 7 days before it started. Results need at least 3 days of data in each window.")
                        .font(.r(.caption, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .navigationTitle("New Experiment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.brand)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") { saveAndDismiss() }
                        .font(.r(.body, .semibold))
                        .foregroundColor(name.isEmpty ? .secondary : AppColors.brand)
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if name.isEmpty { name = selectedType.label }
                if hypothesis.isEmpty { hypothesis = selectedType.suggestedHypothesis }
            }
        }
        .presentationDetents([.large])
    }

    private func saveAndDismiss() {
        let exp = StressExperiment(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            hypothesis: hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : hypothesis,
            interventionType: selectedType.rawValue,
            startDate: Date(),
            durationDays: durationDays
        )
        modelContext.insert(exp)
        try? modelContext.save()
        HapticService.impact(.medium)
        dismiss()
    }
}
