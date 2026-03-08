import SwiftUI
import Combine
import SwiftData

struct GoalsView: View {

    @ObservedObject var viewModel: GoalsViewModel
    @State private var showResetAlert = false

    private var goals: UserGoals { viewModel.goals }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                hydrationSection
                nutritionSection
                exerciseSection
                sleepSection

                resetButton
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.large)
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
        GoalCard(icon: "drop.fill", iconColor: Color(hue: 0.58, saturation: 0.65, brightness: 0.82), title: "Hydration") {
            VStack(spacing: 16) {
                GoalStepperRow(
                    label: "Cup Size",
                    value: Binding(
                        get: { goals.waterCupSizeML },
                        set: { goals.waterCupSizeML = $0; viewModel.save() }
                    ),
                    range: 50...1000,
                    step: 50,
                    unit: "mL"
                )
                GoalStepperRow(
                    label: "Daily Cups",
                    value: Binding(
                        get: { goals.waterDailyCups },
                        set: { goals.waterDailyCups = $0; viewModel.save() }
                    ),
                    range: 1...20,
                    step: 1,
                    unit: "cups"
                )

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("Daily target: \(goals.waterDailyCups * goals.waterCupSizeML) mL")
                        .font(.r(.caption, .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Nutrition Section

    private var nutritionSection: some View {
        GoalCard(icon: "flame.fill", iconColor: .orange, title: "Nutrition") {
            VStack(spacing: 16) {
                GoalStepperRow(
                    label: "Calories",
                    value: Binding(
                        get: { goals.calorieGoal },
                        set: { goals.calorieGoal = $0; viewModel.save() }
                    ),
                    range: 500...10000,
                    step: 50,
                    unit: "kcal"
                )
                GoalStepperRow(
                    label: "Protein",
                    value: Binding(
                        get: { goals.proteinGoalGrams },
                        set: { goals.proteinGoalGrams = $0; viewModel.save() }
                    ),
                    range: 0...1000,
                    step: 5,
                    unit: "g"
                )
                GoalStepperRow(
                    label: "Carbs",
                    value: Binding(
                        get: { goals.carbsGoalGrams },
                        set: { goals.carbsGoalGrams = $0; viewModel.save() }
                    ),
                    range: 0...1000,
                    step: 5,
                    unit: "g"
                )
                GoalStepperRow(
                    label: "Fat",
                    value: Binding(
                        get: { goals.fatGoalGrams },
                        set: { goals.fatGoalGrams = $0; viewModel.save() }
                    ),
                    range: 0...500,
                    step: 5,
                    unit: "g"
                )
                GoalStepperRow(
                    label: "Sugar",
                    value: Binding(
                        get: { goals.sugarGoalGrams },
                        set: { goals.sugarGoalGrams = $0; viewModel.save() }
                    ),
                    range: 0...500,
                    step: 5,
                    unit: "g"
                )
                GoalStepperRow(
                    label: "Fiber",
                    value: Binding(
                        get: { goals.fiberGoalGrams },
                        set: { goals.fiberGoalGrams = $0; viewModel.save() }
                    ),
                    range: 0...200,
                    step: 5,
                    unit: "g"
                )
                GoalStepperRow(
                    label: "Sodium",
                    value: Binding(
                        get: { goals.sodiumGoalMG },
                        set: { goals.sodiumGoalMG = $0; viewModel.save() }
                    ),
                    range: 0...10000,
                    step: 100,
                    unit: "mg"
                )
            }
        }
    }

    // MARK: - Exercise Section

    private var exerciseSection: some View {
        GoalCard(icon: "figure.run", iconColor: .green, title: "Exercise") {
            VStack(spacing: 16) {
                GoalStepperRow(
                    label: "Active Energy",
                    value: Binding(
                        get: { goals.activeEnergyGoalKcal },
                        set: { goals.activeEnergyGoalKcal = $0; viewModel.save() }
                    ),
                    range: 50...5000,
                    step: 50,
                    unit: "kcal"
                )
                GoalStepperRow(
                    label: "Daily Steps",
                    value: Binding(
                        get: { goals.dailyStepsGoal },
                        set: { goals.dailyStepsGoal = $0; viewModel.save() }
                    ),
                    range: 1000...50000,
                    step: 500,
                    unit: "steps"
                )

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Workout Duration")
                        .font(.r(.subheadline, .semibold))
                        .foregroundStyle(.primary)

                    Text("Set per day. 0 min = rest day.")
                        .font(.r(.caption, .regular))
                        .foregroundStyle(.secondary)

                    workoutWeekGrid
                }
            }
        }
    }

    private var workoutWeekGrid: some View {
        let weekdays: [(label: String, weekday: Int)] = [
            ("Sun", 1), ("Mon", 2), ("Tue", 3), ("Wed", 4),
            ("Thu", 5), ("Fri", 6), ("Sat", 7)
        ]

        return VStack(spacing: 10) {
            ForEach(weekdays, id: \.weekday) { day in
                WorkoutDayRow(
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
        GoalCard(icon: "moon.fill", iconColor: .indigo, title: "Sleep") {
            VStack(spacing: 12) {
                HStack {
                    Text("Sleep Goal")
                        .font(.r(.subheadline, .medium))
                    Spacer()
                    Text(String(format: "%.1f hrs", goals.sleepGoalHours))
                        .font(.r(.subheadline, .semibold))
                        .foregroundStyle(.indigo)
                }

                Slider(
                    value: Binding(
                        get: { goals.sleepGoalHours },
                        set: { goals.sleepGoalHours = $0; viewModel.save() }
                    ),
                    in: 3.0...14.0,
                    step: 0.5
                )
                .tint(.indigo)

                HStack {
                    Text("3 hrs")
                        .font(.r(.caption2, .regular))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("14 hrs")
                        .font(.r(.caption2, .regular))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button {
            showResetAlert = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset to Defaults")
            }
            .font(.r(.subheadline, .medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.red.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GoalCard

private struct GoalCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.r(.headline, .semibold))
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 15, x: 0, y: 5)
        )
    }
}

// MARK: - GoalStepperRow

private struct GoalStepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.r(.subheadline, .medium))

            Spacer()

            HStack(spacing: 12) {
                Button {
                    HapticService.selectionChanged()
                    let new = value - step
                    value = max(new, range.lowerBound)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(value <= range.lowerBound ? Color.gray.opacity(0.3) : .orange)
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)

                Text("\(value)")
                    .font(.r(16, .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 48, alignment: .center)

                Button {
                    HapticService.selectionChanged()
                    let new = value + step
                    value = min(new, range.upperBound)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(value >= range.upperBound ? Color.gray.opacity(0.3) : .orange)
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)

                Text(unit)
                    .font(.r(.caption, .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
            }
        }
    }
}

// MARK: - WorkoutDayRow

private struct WorkoutDayRow: View {
    let label: String
    @Binding var minutes: Int

    private var isRestDay: Bool { minutes == 0 }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.r(.subheadline, .semibold))
                .foregroundStyle(isRestDay ? .secondary : .primary)
                .frame(width: 36, alignment: .leading)

            if isRestDay {
                Text("Rest")
                    .font(.r(.caption, .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            } else {
                Text("\(minutes) min")
                    .font(.r(.subheadline, .medium))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    HapticService.selectionChanged()
                    minutes = max(minutes - 5, 0)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isRestDay ? Color.gray.opacity(0.3) : .orange)
                }
                .buttonStyle(.plain)
                .disabled(isRestDay)

                Button {
                    HapticService.selectionChanged()
                    minutes = min(minutes + 5, 480)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(minutes >= 480 ? Color.gray.opacity(0.3) : .orange)
                }
                .buttonStyle(.plain)
                .disabled(minutes >= 480)
            }
        }
        .padding(.vertical, 4)
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
