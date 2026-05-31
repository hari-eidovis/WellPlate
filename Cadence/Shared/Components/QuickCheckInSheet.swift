import SwiftUI
import SwiftData

/// Bottom-sheet form presented globally when `DailyPromptCoordinator` detects
/// missing morning sleep data (≥11:00) or missing evening signals (≥19:00).
///
/// Three actions: **Save** (writes to `ManualDailyInput`), **Skip for today**
/// (marks askedAt so we don't pester again today), **Don't ask again**
/// (sets a UserDefaults flag).
struct QuickCheckInSheet: View {

    let kind: DailyPromptCoordinator.PromptKind
    let coordinator: DailyPromptCoordinator

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Morning fields
    @State private var sleepHours: Double = 7.0
    @State private var sleepQuality: Int = 3
    @State private var bedtime: Date = Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date()
    @State private var wakeTime: Date = Date()
    @State private var includeBedWake: Bool = false

    // Evening fields
    @State private var screenTimeHours: Double = 4.0
    @State private var heavyEveningScreens: Bool = false
    @State private var exerciseMinutes: Int = 0
    @State private var amDaylightOutside: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch kind {
                    case .morning:
                        morningForm
                    case .evening(let gaps):
                        eveningForm(gaps: gaps)
                    }
                }
                .padding(.horizontal, 20)
            }
            buttonRow
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .padding(.top, 16)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.r(.title3, .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle)
                .font(.r(.subheadline, .regular))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var title: String {
        switch kind {
        case .morning: return "Quick check-in"
        case .evening: return "Wrap-up your day"
        }
    }

    private var subtitle: String {
        switch kind {
        case .morning:
            return "We didn't see sleep data sync from Apple Health. Tell us roughly how last night went."
        case .evening:
            return "A few quick details so your stress score reflects today accurately."
        }
    }

    // MARK: - Morning form

    private var morningForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hours slept")
                    .font(.r(.subheadline, .semibold))
                Slider(value: $sleepHours, in: 4.0...12.0, step: 0.5) {
                    Text("Hours slept")
                }
                Text(String(format: "%.1f h", sleepHours))
                    .font(.r(.caption, .regular))
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Quality")
                    .font(.r(.subheadline, .semibold))
                Picker("Quality", selection: $sleepQuality) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                    Text("5").tag(5)
                }
                .pickerStyle(.segmented)
            }

            Toggle(isOn: $includeBedWake) {
                Text("Add bedtime / wake time").font(.r(.subheadline, .regular))
            }
            if includeBedWake {
                HStack {
                    DatePicker("Bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .font(.r(.caption, .regular))
                    DatePicker("Wake", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .font(.r(.caption, .regular))
                }
            }
        }
    }

    // MARK: - Evening form

    @ViewBuilder
    private func eveningForm(gaps: DailyPromptCoordinator.EveningGaps) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if gaps.needsScreen {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Screen time today")
                        .font(.r(.subheadline, .semibold))
                    Stepper(value: $screenTimeHours, in: 0...16, step: 0.5) {
                        Text(String(format: "%.1f h", screenTimeHours))
                            .font(.r(.subheadline, .regular))
                    }
                    Toggle(isOn: $heavyEveningScreens) {
                        Text("Heavy phone/TV after dinner")
                            .font(.r(.subheadline, .regular))
                    }
                }
            }
            if gaps.needsExercise {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Exercise minutes")
                        .font(.r(.subheadline, .semibold))
                    Stepper(value: $exerciseMinutes, in: 0...300, step: 5) {
                        Text("\(exerciseMinutes) min").font(.r(.subheadline, .regular))
                    }
                }
            }
            if gaps.needsDaylight {
                Toggle(isOn: $amDaylightOutside) {
                    VStack(alignment: .leading) {
                        Text("Got morning sunlight outside?")
                            .font(.r(.subheadline, .semibold))
                        Text("Even ~10 min counts")
                            .font(.r(.caption, .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        VStack(spacing: 8) {
            Button(action: handleSave) {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.brand)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .font(.r(.headline, .semibold))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Button(action: handleSkipToday) {
                    Text("Skip for today")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.r(.subheadline, .regular))
                }
                .buttonStyle(.plain)
                Button(action: handleDontAskAgain) {
                    Text("Don't ask again")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.r(.subheadline, .regular))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func handleSave() {
        let now = Date()
        var values = ManualValues()
        switch kind {
        case .morning:
            values.sleepHours = sleepHours
            values.sleepQuality = sleepQuality
            if includeBedWake {
                values.bedtime = bedtime
                values.wakeTime = wakeTime
            }
        case .evening(let gaps):
            if gaps.needsScreen {
                values.screenTimeHours = screenTimeHours
                values.heavyEveningScreens = heavyEveningScreens
            }
            if gaps.needsExercise {
                values.exerciseMinutes = exerciseMinutes
            }
            if gaps.needsDaylight {
                values.amDaylightOutside = amDaylightOutside
            }
        }
        coordinator.recordSave(kind, values: values, modelContext: modelContext, now: now)
        dismiss()
    }

    private func handleSkipToday() {
        coordinator.recordSkip(kind, modelContext: modelContext, now: Date())
        dismiss()
    }

    private func handleDontAskAgain() {
        coordinator.disableForever()
        dismiss()
    }
}
