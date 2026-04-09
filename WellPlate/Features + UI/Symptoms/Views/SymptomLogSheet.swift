import SwiftUI
import SwiftData

// MARK: - SymptomLogSheet
//
// 3-step quick-log flow: category → symptom → severity + save.
// Presented as a sheet from Home or Profile.

struct SymptomLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: LogStep = .category
    @State private var selectedCategory: SymptomCategory?
    @State private var selectedSymptom: SymptomDefinition?
    @State private var severity: Double = 5
    @State private var notes: String = ""
    @State private var customName: String = ""
    @State private var isShowingCustomField = false
    @FocusState private var customFieldFocused: Bool

    enum LogStep { case category, symptom, severity }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .category: categoryStep
                case .symptom:  symptomStep
                case .severity: severityStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        switch step {
                        case .category: dismiss()
                        case .symptom:
                            step = .category
                            selectedSymptom = nil
                            isShowingCustomField = false
                        case .severity:
                            step = .symptom
                        }
                    } label: {
                        Image(systemName: step == .category ? "xmark" : "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if step == .severity {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveSymptom()
                        }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(saveIsDisabled ? AppColors.brand.opacity(0.4) : AppColors.brand)
                        .disabled(saveIsDisabled)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Step 1: Category

    private var categoryStep: some View {
        VStack(spacing: 24) {
            Text("What kind of symptom?")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(SymptomCategory.allCases) { category in
                    categoryCard(category)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 8)
    }

    private func categoryCard(_ category: SymptomCategory) -> some View {
        Button {
            HapticService.impact(.light)
            selectedCategory = category
            isShowingCustomField = false
            step = .symptom
        } label: {
            VStack(spacing: 12) {
                category.iconImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(category.color)

                Text(category.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Symptom Picker

    private var symptomStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let cat = selectedCategory {
                    HStack(spacing: 8) {
                        cat.iconImage
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundStyle(cat.color)
                        Text(cat.label)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(cat.color)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                Text("Select symptom")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)

                // Symptom pills
                let symptoms = SymptomDefinition.forCategory(selectedCategory ?? .pain)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(symptoms) { symptom in
                        symptomPill(symptom)
                    }
                    // Custom pill
                    customPill
                }
                .padding(.horizontal, 20)

                // Custom text field (shows when custom is tapped)
                if isShowingCustomField {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Symptom name")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Hives, Palpitations...", text: $customName)
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .focused($customFieldFocused)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )

                        Button {
                            guard !customName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            HapticService.impact(.light)
                            let trimmed = customName.trimmingCharacters(in: .whitespaces)
                            selectedSymptom = SymptomDefinition.custom(name: trimmed)
                            step = .severity
                        } label: {
                            Text("Continue →")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(customName.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.brand.opacity(0.4) : AppColors.brand)
                        }
                        .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func symptomPill(_ symptom: SymptomDefinition) -> some View {
        Button {
            HapticService.impact(.light)
            selectedSymptom = symptom
            step = .severity
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symptom.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedCategory?.color ?? AppColors.brand)
                Text(symptom.name)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var customPill: some View {
        Button {
            HapticService.impact(.light)
            isShowingCustomField = true
            customFieldFocused = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Custom")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Severity + Save

    private var severityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Symptom name header
                if let symptom = selectedSymptom {
                    HStack(spacing: 8) {
                        Image(systemName: symptom.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(selectedCategory?.color ?? AppColors.brand)
                        Text(symptom.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                // Severity section
                VStack(alignment: .leading, spacing: 14) {
                    Text("How severe?")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    // Severity value display
                    HStack {
                        Spacer()
                        Text("\(Int(severity))")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(severityColor)
                        Text("/ 10")
                            .font(.system(size: 20, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                        Spacer()
                    }

                    // Severity label
                    Text(severityLabel)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(severityColor)
                        .frame(maxWidth: .infinity)

                    Slider(value: $severity, in: 1...10, step: 1)
                        .tint(severityColor)
                        .padding(.horizontal, 20)

                    HStack {
                        Text("Mild")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Severe")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
                )
                .padding(.horizontal, 16)

                // Notes (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes (optional)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("When did it start? Any triggers?", text: $notes, axis: .vertical)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .lineLimit(2...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Helpers

    private var saveIsDisabled: Bool {
        selectedSymptom == nil
    }

    private var severityColor: Color {
        switch Int(severity) {
        case 1...3: return Color(hue: 0.38, saturation: 0.58, brightness: 0.72) // green
        case 4...6: return Color(hue: 0.14, saturation: 0.72, brightness: 0.95) // amber
        default:    return Color(hue: 0.00, saturation: 0.72, brightness: 0.85) // red
        }
    }

    private var severityLabel: String {
        switch Int(severity) {
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        case 7...8: return "Severe"
        default:    return "Very severe"
        }
    }

    private func saveSymptom() {
        guard let symptom = selectedSymptom else { return }
        let cat = symptom.isCustom ? (selectedCategory ?? .cognitive) : (symptom.category)
        let entry = SymptomEntry(
            name: symptom.name,
            category: cat,
            severity: Int(severity),
            timestamp: Date(),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        )
        modelContext.insert(entry)
        do {
            try modelContext.save()
            HapticService.notify(.success)
            WPLogger.home.info("Symptom logged: \(symptom.name) severity \(Int(severity))")
        } catch {
            WPLogger.home.error("Symptom save failed: \(error.localizedDescription)")
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview("Symptom Log Sheet") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SymptomEntry.self, configurations: config)
    return SymptomLogSheet()
        .modelContainer(container)
}
