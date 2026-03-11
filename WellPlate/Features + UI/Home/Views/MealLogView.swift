import SwiftUI
import SwiftData

// MARK: - MealLogView
// Rich meal-logging form presented as a sheet from FoodJournalView when user taps the plus button.

struct MealLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MealLogViewModel

    let selectedDate: Date
    @FocusState private var isFoodFieldFocused: Bool
    @FocusState private var isReflectionFieldFocused: Bool

    private static var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        mealTypePicker
                        foodInputSection
                        quickActionRow
                        eatingTriggersSection
                        voiceNoteSection
                        addMoreContextSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                saveButton
            }

            if let state = viewModel.disambiguationState {
                disambiguationOverlay(state: state)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    HapticService.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.primary)
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.showError) { _, isError in
            if isError { HapticService.notify(.error) }
        }
        .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss {
                HapticService.notify(.success)
                SoundService.playConfirmation()
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Log a Meal")
                .font(.r(.headline, .semibold))
                .foregroundColor(AppColors.textPrimary)
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.r(.caption2, .medium))
                Text(Calendar.current.isDateInToday(selectedDate) ? "Today" : shortDate(selectedDate))
                    .font(.r(.caption, .regular))
                Text("•")
                Text(Self.timeFormatter.string(from: Date()))
                    .font(.r(.caption, .regular))
            }
            .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    // MARK: - Meal Type Picker

    private var mealTypePicker: some View {
        HStack(spacing: 10) {
            ForEach(MealType.allCases) { type in
                Button {
                    HapticService.selectionChanged()
                    viewModel.selectedMealType = type
                } label: {
                    Text(type.displayName)
                        .font(.r(.subheadline, .semibold))
                        .foregroundColor(viewModel.selectedMealType == type ? AppColors.onPrimary : AppColors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(viewModel.selectedMealType == type ? AppColors.primary : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(AppColors.borderSubtle, lineWidth: viewModel.selectedMealType == type ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Food Input

    private var foodInputSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppColors.primary.opacity(0.6))
            TextField("e.g. avocado toast, leftover pasta...", text: $viewModel.foodDescription)
                .font(.r(15, .regular))
                .textFieldStyle(.plain)
                .focused($isFoodFieldFocused)
                .disabled(viewModel.isLoading)
                .tint(AppColors.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Quick Action Row

    private var quickActionRow: some View {
        HStack(spacing: 16) {
            quickActionButton(icon: "camera.fill", label: "Add photo") { /* TODO */ }
            quickActionButton(icon: "barcode.viewfinder", label: "Scan barcode") { /* TODO */ }
            quickActionButton(icon: "mic.fill", label: "Voice note") { /* TODO */ }
        }
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticService.impact(.light)
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.r(.caption, .medium))
            }
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Eating Triggers

    private var eatingTriggersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("💛")
                Text("What brought you here?")
                    .font(.r(.title3, .semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(EatingTrigger.allCases) { trigger in
                    let isSelected = viewModel.selectedTriggers.contains(trigger)
                    Button {
                        HapticService.selectionChanged()
                        if viewModel.selectedTriggers.contains(trigger) {
                            viewModel.selectedTriggers.remove(trigger)
                        } else {
                            viewModel.selectedTriggers.insert(trigger)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(trigger.emoji)
                                .font(.system(size: 24))
                            Text(trigger.displayName)
                                .font(.r(.caption, .semibold))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected ? AppColors.primaryContainer : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? AppColors.primary : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(trigger.displayName), eating trigger")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Text("No judgment — this helps us spot your patterns over time.")
                .font(.r(.caption, .regular))
                .italic()
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Voice Note Section

    private var voiceNoteSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.primaryContainer)
                    .frame(width: 56, height: 56)
                Image(systemName: "mic.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.primary)
            }
            VStack(spacing: 2) {
                Text("Add a voice note")
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text("30 sec • Optional • Only you can hear this")
                    .font(.r(.caption2, .regular))
                    .foregroundColor(AppColors.textSecondary)
            }
            Button {
                HapticService.impact(.light)
                // TODO: voice recording v2
            } label: {
                Text("Coming soon")
                    .font(.r(.caption, .medium))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.top, 4)
            TextField("Or type a reflection...", text: $viewModel.reflection, axis: .vertical)
                .font(.r(15, .regular))
                .textFieldStyle(.plain)
                .focused($isReflectionFieldFocused)
                .lineLimit(3...6)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemFill))
                )
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Add More Context (Expandable)

    private var addMoreContextSection: some View {
        DisclosureGroup(isExpanded: $viewModel.showMoreContext) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hunger Level")
                        .font(.r(.subheadline, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    HStack {
                        Text("🙂")
                        Slider(value: $viewModel.hungerLevel, in: 0...1)
                            .tint(AppColors.primary)
                        Text("😩")
                    }
                    HStack {
                        Text("Not hungry")
                            .font(.r(.caption2, .regular))
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        Text("Starving")
                            .font(.r(.caption2, .regular))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue("\(Int(viewModel.hungerLevel * 100))% hungry")

                VStack(alignment: .leading, spacing: 8) {
                    Text("How present were you?")
                        .font(.r(.subheadline, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    HStack {
                        Text("🤦‍♀️")
                        Slider(value: $viewModel.presenceLevel, in: 0...1)
                            .tint(AppColors.primary)
                        Text("🧘‍♀️")
                    }
                    HStack {
                        Text("Distracted")
                            .font(.r(.caption2, .regular))
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        Text("Fully present")
                            .font(.r(.caption2, .regular))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue("\(Int(viewModel.presenceLevel * 100))% present")
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("+ Add more context")
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task {
                await viewModel.saveMeal(selectedDate: selectedDate)
            }
        } label: {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Save & Reflect")
                        .font(.btn)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isValid || viewModel.isLoading)
        .opacity(viewModel.isValid && !viewModel.isLoading ? 1 : AppOpacity.disabled)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    // MARK: - Disambiguation Overlay

    private func disambiguationOverlay(state: DisambiguationState) -> some View {
        DisambiguationChipsView(
            question: state.question,
            options: state.options,
            rawInput: state.rawInput,
            onSelect: { option in
                Task {
                    await viewModel.resolveWithOption(option, selectedDate: selectedDate)
                }
            },
            onAddAsTyped: {
                Task {
                    await viewModel.resolveWithRawInput(selectedDate: selectedDate)
                }
            }
        )
        .transition(.opacity)
        .zIndex(10)
    }
}

// MARK: - Sheet Content (creates ViewModel once per presentation)

struct MealLogSheetContent: View {
    let homeViewModel: HomeViewModel
    let selectedDate: Date
    var didSave: Binding<Bool>?
    @StateObject private var mealLogViewModel: MealLogViewModel

    init(homeViewModel: HomeViewModel, selectedDate: Date, didSave: Binding<Bool>? = nil) {
        self.homeViewModel = homeViewModel
        self.selectedDate = selectedDate
        self.didSave = didSave
        _mealLogViewModel = StateObject(wrappedValue: MealLogViewModel(homeViewModel: homeViewModel, selectedDate: selectedDate))
    }

    var body: some View {
        NavigationStack {
            MealLogView(viewModel: mealLogViewModel, selectedDate: selectedDate)
        }
        .onChange(of: mealLogViewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss {
                didSave?.wrappedValue = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Meal Log") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodLogEntry.self, configurations: config)
    let homeVM = HomeViewModel(modelContext: container.mainContext)
    let mealLogVM = MealLogViewModel(homeViewModel: homeVM, selectedDate: Date())
    return NavigationStack {
        MealLogView(viewModel: mealLogVM, selectedDate: Date())
    }
    .modelContainer(container)
}
