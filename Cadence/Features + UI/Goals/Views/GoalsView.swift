import SwiftUI
import Combine
import SwiftData

struct GoalsView: View {

    @ObservedObject var viewModel: GoalsViewModel
    @State private var showResetAlert = false
    @State private var nutritionTab: NutritionTab = .macros

    private var goals: UserGoals { viewModel.goals }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hydrationSection
                nutritionSection
                exerciseSection
                sleepSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticService.impact(.light)
                    showResetAlert = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Reset to defaults")
            }
        }
        .alert("Reset to Defaults?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                HapticService.impact(.medium)
                viewModel.resetToDefaults()
            }
        } message: {
            Text("All goals will be restored to their default values.")
        }
    }

    // MARK: - Hydration Section

    private var hydrationSection: some View {
        GoalCard(
            eyebrow: "HYDRATION",
            title: "Water",
            icon: "drop.fill"
        ) {
            VStack(alignment: .leading, spacing: 14) {

                // Cup Size — preset chip picker
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "Cup Size", value: "\(goals.waterCupSizeML) mL")
                    ChipPickerRow(
                        options: [150, 200, 250, 330, 500],
                        selection: Binding(
                            get: { goals.waterCupSizeML },
                            set: { goals.waterCupSizeML = $0; viewModel.save() }
                        ),
                        format: { "\($0)" }
                    )
                }

                // Daily Cups — visual cup row
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "Daily Cups", value: "\(goals.waterDailyCups)")
                    CupRow(
                        value: Binding(
                            get: { goals.waterDailyCups },
                            set: { goals.waterDailyCups = $0; viewModel.save() }
                        ),
                        max: 10
                    )
                }

                // Total summary chip
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Daily target: \(goals.waterDailyCups * goals.waterCupSizeML) mL")
                        .font(.r(.caption, .semibold))
                }
                .foregroundStyle(AppColors.brand)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.tertiarySystemFill).opacity(0.7)))
            }
        }
    }

    // MARK: - Nutrition Section

    private enum NutritionTab: String, CaseIterable, Identifiable {
        case macros = "Macros"
        case limits = "Limits"
        var id: String { rawValue }
    }

    private var nutritionSection: some View {
        GoalCard(
            eyebrow: "FUEL",
            title: "Nutrition",
            icon: "flame.fill"
        ) {
            VStack(alignment: .leading, spacing: 14) {

                // Calories — feature row
                CalorieFeatureRow(
                    value: Binding(
                        get: { goals.calorieGoal },
                        set: { goals.calorieGoal = $0; viewModel.save() }
                    ),
                    range: 500...10_000
                )

                // Tab switcher between macros & limits
                Picker("", selection: $nutritionTab) {
                    ForEach(NutritionTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch nutritionTab {
                case .macros: macrosBlock
                case .limits: limitsBlock
                }
            }
        }
    }

    private var macrosBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacroSliderRow(
                label: "Protein",
                value: Binding(
                    get: { goals.proteinGoalGrams },
                    set: { goals.proteinGoalGrams = $0; viewModel.save() }
                ),
                range: 0...300,
                step: 5,
                unit: "g"
            )
            MacroSliderRow(
                label: "Carbs",
                value: Binding(
                    get: { goals.carbsGoalGrams },
                    set: { goals.carbsGoalGrams = $0; viewModel.save() }
                ),
                range: 0...500,
                step: 5,
                unit: "g"
            )
            MacroSliderRow(
                label: "Fat",
                value: Binding(
                    get: { goals.fatGoalGrams },
                    set: { goals.fatGoalGrams = $0; viewModel.save() }
                ),
                range: 0...200,
                step: 5,
                unit: "g"
            )

            MacroBalanceBar(
                protein: goals.proteinGoalGrams,
                carbs: goals.carbsGoalGrams,
                fat: goals.fatGoalGrams
            )
            .padding(.top, 4)
        }
    }

    private var limitsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacroSliderRow(
                label: "Sugar",
                value: Binding(
                    get: { goals.sugarGoalGrams },
                    set: { goals.sugarGoalGrams = $0; viewModel.save() }
                ),
                range: 0...200,
                step: 5,
                unit: "g"
            )
            MacroSliderRow(
                label: "Fiber",
                value: Binding(
                    get: { goals.fiberGoalGrams },
                    set: { goals.fiberGoalGrams = $0; viewModel.save() }
                ),
                range: 0...100,
                step: 1,
                unit: "g"
            )
            MacroSliderRow(
                label: "Sodium",
                value: Binding(
                    get: { goals.sodiumGoalMG },
                    set: { goals.sodiumGoalMG = $0; viewModel.save() }
                ),
                range: 0...5000,
                step: 100,
                unit: "mg"
            )
        }
    }

    // MARK: - Exercise Section

    private var exerciseSection: some View {
        GoalCard(
            eyebrow: "MOVEMENT",
            title: "Exercise",
            icon: "figure.run"
        ) {
            VStack(alignment: .leading, spacing: 14) {

                // Active Energy — slider
                MacroSliderRow(
                    label: "Active Energy",
                    value: Binding(
                        get: { goals.activeEnergyGoalKcal },
                        set: { goals.activeEnergyGoalKcal = $0; viewModel.save() }
                    ),
                    range: 100...1500,
                    step: 50,
                    unit: "kcal"
                )

                // Daily Steps — preset chips
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(
                        title: "Daily Steps",
                        value: stepsLabel(goals.dailyStepsGoal)
                    )
                    ChipPickerRow(
                        options: [5_000, 7_500, 10_000, 12_500, 15_000, 20_000],
                        selection: Binding(
                            get: { goals.dailyStepsGoal },
                            set: { goals.dailyStepsGoal = $0; viewModel.save() }
                        ),
                        format: { stepsLabel($0) }
                    )
                }

                // Workout Duration — per-day sliders
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout Duration")
                        .font(.r(.subheadline, .semibold))
                    Text("Slide to set each day. 0 = rest.")
                        .font(.r(.caption2, .regular))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)

                workoutWeek
            }
        }
    }

    private func stepsLabel(_ value: Int) -> String {
        if value >= 1000 {
            let k = Double(value) / 1000
            if k.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(k))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(value)"
    }

    private var workoutWeek: some View {
        let weekdays: [(label: String, weekday: Int)] = [
            ("Sun", 1), ("Mon", 2), ("Tue", 3), ("Wed", 4),
            ("Thu", 5), ("Fri", 6), ("Sat", 7)
        ]

        return VStack(spacing: 8) {
            ForEach(weekdays, id: \.weekday) { day in
                WorkoutDaySliderRow(
                    label: day.label,
                    minutes: Binding(
                        get: { goals.workoutMinutes(for: day.weekday) },
                        set: { goals.setWorkoutMinutes($0, for: day.weekday); viewModel.save() }
                    )
                )
            }
        }
    }

    // MARK: - Sleep Section

    private var sleepSection: some View {
        GoalCard(
            eyebrow: "RECOVERY",
            title: "Sleep",
            icon: "moon.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", goals.sleepGoalHours))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.brand)
                        .monospacedDigit()
                    Text("hrs / night")
                        .font(.r(.footnote, .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Slider(
                    value: Binding(
                        get: { goals.sleepGoalHours },
                        set: { goals.sleepGoalHours = $0; viewModel.save() }
                    ),
                    in: 3.0...12.0,
                    step: 0.5
                )
                .tint(AppColors.brand)

                HStack {
                    Text("3 hrs").font(.r(.caption2, .regular)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("12 hrs").font(.r(.caption2, .regular)).foregroundStyle(.tertiary)
                }
            }
        }
    }

}

// MARK: - GoalCard

private struct GoalCard<Content: View>: View {
    let eyebrow: String
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(
        eyebrow: String,
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.tertiarySystemFill).opacity(0.6))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow)
                        .font(.r(10, .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.r(16, .bold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - SectionLabel

private struct SectionLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.r(.subheadline, .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.r(.subheadline, .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - ChipPickerRow

private struct ChipPickerRow: View {
    let options: [Int]
    @Binding var selection: Int
    let format: (Int) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection
                    Button {
                        HapticService.selectionChanged()
                        selection = option
                    } label: {
                        Text(format(option))
                            .font(.r(.subheadline, .semibold))
                            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(isSelected ? AppColors.brand : Color(.tertiarySystemFill).opacity(0.7))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - CupRow (visual tappable cups)

private struct CupRow: View {
    @Binding var value: Int
    let max: Int

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let count = CGFloat(max)
            let cupSize = min(28, (geo.size.width - spacing * (count - 1)) / count)
            HStack(spacing: spacing) {
                ForEach(1...max, id: \.self) { idx in
                    let filled = idx <= value
                    Image(systemName: filled ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: cupSize * 0.7, weight: .regular))
                        .foregroundStyle(filled ? AppColors.brand : .secondary.opacity(0.4))
                        .frame(width: cupSize, height: cupSize)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticService.selectionChanged()
                            if value == idx {
                                value = Swift.max(idx - 1, 1)
                            } else {
                                value = idx
                            }
                        }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 30)
    }
}

// MARK: - CalorieFeatureRow

private struct CalorieFeatureRow: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    @State private var isEditing = false
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Calories")
                    .font(.r(.subheadline, .semibold))
                Spacer()
                if isEditing {
                    TextField("", text: $draft)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.brand)
                        .frame(maxWidth: 100)
                        .submitLabel(.done)
                        .onSubmit { commit() }
                    Button("Done") { commit() }
                        .font(.r(.footnote, .semibold))
                        .foregroundStyle(AppColors.brand)
                } else {
                    Button {
                        HapticService.selectionChanged()
                        draft = String(value)
                        isEditing = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(value)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.brand)
                                .monospacedDigit()
                            Text("kcal")
                                .font(.r(.footnote, .medium))
                                .foregroundStyle(.secondary)
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Quick adjustment chips
            HStack(spacing: 6) {
                ForEach([-100, -50, 50, 100], id: \.self) { delta in
                    Button {
                        HapticService.selectionChanged()
                        let newVal = value + delta
                        value = min(Swift.max(newVal, range.lowerBound), range.upperBound)
                    } label: {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .font(.r(.caption, .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.tertiarySystemFill).opacity(0.7))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func commit() {
        if let parsed = Int(draft) {
            value = min(Swift.max(parsed, range.lowerBound), range.upperBound)
        }
        isEditing = false
    }
}

// MARK: - MacroSliderRow

private struct MacroSliderRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.r(.subheadline, .medium))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(value)")
                        .font(.r(.subheadline, .bold))
                        .foregroundStyle(AppColors.brand)
                        .monospacedDigit()
                    Text(unit)
                        .font(.r(.caption, .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { newVal in
                        let snapped = (Int(newVal.rounded()) / step) * step
                        let clamped = min(Swift.max(snapped, range.lowerBound), range.upperBound)
                        if clamped != value {
                            HapticService.selectionChanged()
                            value = clamped
                        }
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(AppColors.brand)
        }
    }
}

// MARK: - MacroBalanceBar

private struct MacroBalanceBar: View {
    let protein: Int
    let carbs: Int
    let fat: Int

    // Convert grams → kcal: protein/carbs = 4 kcal/g, fat = 9 kcal/g
    private var pCal: Double { Double(protein) * 4 }
    private var cCal: Double { Double(carbs) * 4 }
    private var fCal: Double { Double(fat) * 9 }
    private var total: Double { Swift.max(pCal + cCal + fCal, 1) }

    private var pPct: Int { Int((pCal / total * 100).rounded()) }
    private var cPct: Int { Int((cCal / total * 100).rounded()) }
    private var fPct: Int { Int((fCal / total * 100).rounded()) }

    private var proteinShade: Color { AppColors.brand }
    private var carbShade:    Color { AppColors.brand.opacity(0.55) }
    private var fatShade:     Color { AppColors.brand.opacity(0.28) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Energy Split")
                .font(.r(.caption, .semibold))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 2) {
                    Rectangle().fill(proteinShade).frame(width: w * pCal / total)
                    Rectangle().fill(carbShade).frame(width: w * cCal / total)
                    Rectangle().fill(fatShade).frame(width: w * fCal / total)
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)

            HStack(spacing: 12) {
                legend(color: proteinShade, label: "P", pct: pPct)
                legend(color: carbShade,    label: "C", pct: cPct)
                legend(color: fatShade,     label: "F", pct: fPct)
                Spacer()
                Text("\(Int(total)) kcal")
                    .font(.r(.caption, .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func legend(color: Color, label: String, pct: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(pct)%")
                .font(.r(.caption2, .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - WorkoutDaySliderRow

private struct WorkoutDaySliderRow: View {
    let label: String
    @Binding var minutes: Int

    private let snapSteps = [0, 15, 30, 45, 60, 90, 120, 150, 180]
    private var isRestDay: Bool { minutes == 0 }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.r(.footnote, .semibold))
                .foregroundStyle(isRestDay ? .secondary : .primary)
                .frame(width: 30, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(minutes) },
                    set: { newVal in
                        let snapped = nearestSnap(Int(newVal.rounded()))
                        if snapped != minutes {
                            HapticService.selectionChanged()
                            minutes = snapped
                        }
                    }
                ),
                in: 0...180
            )
            .tint(AppColors.brand)

            Group {
                if isRestDay {
                    Text("Rest")
                        .font(.r(.caption2, .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(formatMinutes(minutes))
                        .font(.r(.caption, .semibold))
                        .foregroundStyle(AppColors.brand)
                        .monospacedDigit()
                }
            }
            .frame(width: 44, alignment: .trailing)
        }
    }

    private func nearestSnap(_ value: Int) -> Int {
        snapSteps.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    private func formatMinutes(_ m: Int) -> String {
        if m >= 60 {
            let h = m / 60
            let rem = m % 60
            return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
        }
        return "\(m)m"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GoalsView(
            viewModel: {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try! ModelContainer(for: UserGoals.self, configurations: config)
                return GoalsViewModel(modelContext: container.mainContext)
            }()
        )
    }
}
