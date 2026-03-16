import SwiftUI
import SwiftData
import UIKit

// MARK: - MealLogView

struct MealLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: MealLogViewModel

    let selectedDate: Date
    var onBarcodeTap: (() -> Void)? = nil
    @FocusState private var isFoodFieldFocused: Bool
    @FocusState private var isReflectionFieldFocused: Bool
    @FocusState private var isQuantityFieldFocused: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        mealTypePicker
                        foodInputCard
                        triggersSection
                        reflectionField
                        moreContextSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)

                saveButton
            }

            if let state = viewModel.disambiguationState {
                disambiguationOverlay(state: state)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Microphone Access Required", isPresented: $viewModel.showTranscriptionPermissionAlert) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WellPlate needs microphone and speech recognition access to transcribe your meal. Enable both in Settings > Privacy.")
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
        .onDisappear {
            if viewModel.isTranscribing {
                viewModel.stopMealTranscription()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Log a meal")
                .font(.r(.title3, .semibold))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                Text(Calendar.current.isDateInToday(selectedDate) ? "Today" : shortDate(selectedDate))
                Text("·")
                Text(Self.timeFormatter.string(from: Date()))
            }
            .font(.r(.footnote, .regular))
            .foregroundColor(AppColors.textSecondary)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    // MARK: - Meal Type Picker

    private var mealTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(MealType.allCases) { type in
                let isSelected = viewModel.selectedMealType == type
                Button {
                    HapticService.selectionChanged()
                    viewModel.selectedMealType = type
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: type.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(type.displayName)
                            .font(.r(.caption, .semibold))
                    }
                    .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(isSelected
                                  ? AppColors.primaryContainer
                                  : Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
        }
    }

    // MARK: - Food Input Card

    private var foodInputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Food description field with trailing actions
            HStack(alignment: .center, spacing: 10) {
                TextField("What did you eat?", text: $viewModel.foodDescription, axis: .vertical)
                    .font(.r(16, .regular))
                    .textFieldStyle(.plain)
                    .focused($isFoodFieldFocused)
                    .disabled(viewModel.isLoading)
                    .tint(AppColors.primary)
                    .lineLimit(1...3)

                HStack(spacing: 2) {
                    micButton
                    barcodeButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Live transcript hint
            if viewModel.isTranscribing {
                Divider().padding(.horizontal, 16)
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.primary)
                    Text(viewModel.liveTranscript.isEmpty
                         ? "Listening…"
                         : viewModel.liveTranscript)
                        .font(.r(.caption, .regular))
                        .foregroundColor(viewModel.liveTranscript.isEmpty
                                         ? AppColors.textSecondary
                                         : AppColors.textPrimary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().padding(.horizontal, 16)

            // Quantity row
            HStack(spacing: 10) {
                Image(systemName: viewModel.quantityUnit == .millilitres ? "drop" : "scalemass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 16)

                TextField("Amount", text: $viewModel.quantity)
                    .font(.r(15, .regular))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .focused($isQuantityFieldFocused)
                    .disabled(viewModel.isLoading)
                    .tint(AppColors.primary)
                    .foregroundColor(AppColors.textPrimary)

                Picker("", selection: $viewModel.quantityUnit) {
                    ForEach(QuantityUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 84)
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.isTranscribing)
        .animation(.easeInOut(duration: 0.15), value: viewModel.liveTranscript)
    }

    private var micButton: some View {
        Button {
            HapticService.impact(.light)
            viewModel.startMealTranscription()
        } label: {
            micIcon
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(viewModel.isTranscribing
                              ? AppColors.primaryContainer
                              : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isTranscribing)
        .accessibilityLabel(viewModel.isTranscribing ? "Stop recording" : "Speak meal")
    }

    @ViewBuilder
    private var micIcon: some View {
        let color = viewModel.isTranscribing ? AppColors.primary : AppColors.textSecondary
        if #available(iOS 17, *) {
            Image(systemName: viewModel.isTranscribing ? "waveform" : "mic")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(color)
                .symbolEffect(.variableColor.iterative, isActive: viewModel.isTranscribing)
        } else {
            Image(systemName: viewModel.isTranscribing ? "waveform" : "mic")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(color)
        }
    }

    private var barcodeButton: some View {
        Button {
            HapticService.impact(.light)
            onBarcodeTap?()
        } label: {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel("Scan barcode")
    }

    // MARK: - Eating Triggers

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What brought you here?")
                .font(.r(.caption, .semibold))
                .foregroundColor(AppColors.textSecondary)
                .textCase(.uppercase)
                .kerning(0.4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EatingTrigger.allCases) { trigger in
                        let isSelected = viewModel.selectedTriggers.contains(trigger)
                        Button {
                            HapticService.selectionChanged()
                            if isSelected {
                                viewModel.selectedTriggers.remove(trigger)
                            } else {
                                viewModel.selectedTriggers.insert(trigger)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(trigger.emoji)
                                    .font(.system(size: 13))
                                Text(trigger.displayName)
                                    .font(.r(.caption, .medium))
                            }
                            .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isSelected
                                          ? AppColors.primaryContainer
                                          : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isSelected ? AppColors.primary.opacity(0.35) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                        .accessibilityLabel("\(trigger.displayName)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Reflection Field

    private var reflectionField: some View {
        TextField("Any thoughts or feelings? (optional)", text: $viewModel.reflection, axis: .vertical)
            .font(.r(15, .regular))
            .textFieldStyle(.plain)
            .focused($isReflectionFieldFocused)
            .lineLimit(2...5)
            .foregroundColor(AppColors.textPrimary)
            .tint(AppColors.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 12, y: 4)
            )
    }

    // MARK: - More Context (Expandable)

    private var moreContextSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showMoreContext.toggle()
                }
                HapticService.impact(.light)
            } label: {
                HStack {
                    Text("More context")
                        .font(.r(.subheadline, .medium))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .rotationEffect(.degrees(viewModel.showMoreContext ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if viewModel.showMoreContext {
                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 20) {
                    sliderRow(
                        label: "Hunger",
                        leftEmoji: "🙂", rightEmoji: "😩",
                        leftLabel: "Not hungry", rightLabel: "Starving",
                        value: $viewModel.hungerLevel
                    )
                    .accessibilityValue("\(Int(viewModel.hungerLevel * 100))% hungry")

                    sliderRow(
                        label: "Mindfulness",
                        leftEmoji: "🤦‍♀️", rightEmoji: "🧘‍♀️",
                        leftLabel: "Distracted", rightLabel: "Fully present",
                        value: $viewModel.presenceLevel
                    )
                    .accessibilityValue("\(Int(viewModel.presenceLevel * 100))% present")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func sliderRow(
        label: String,
        leftEmoji: String, rightEmoji: String,
        leftLabel: String, rightLabel: String,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.r(.footnote, .semibold))
                .foregroundColor(AppColors.textSecondary)
                .textCase(.uppercase)
                .kerning(0.4)

            HStack(spacing: 8) {
                Text(leftEmoji).font(.system(size: 14))
                Slider(value: value, in: 0...1)
                    .tint(AppColors.primary)
                Text(rightEmoji).font(.system(size: 14))
            }

            HStack {
                Text(leftLabel)
                Spacer()
                Text(rightLabel)
            }
            .font(.r(.caption2, .regular))
            .foregroundColor(AppColors.textSecondary.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
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
                    Text("Save")
                        .font(.btn)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColors.brand)
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isValid || viewModel.isLoading || viewModel.isTranscribing)
        .opacity(viewModel.isValid && !viewModel.isLoading && !viewModel.isTranscribing ? 1 : AppOpacity.disabled)
        .padding(.horizontal, 20)
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

// MARK: - Entry Mode

enum MealLogEntryMode: Hashable {
    case notepad
    case mic
    case barcode
}

// MARK: - Mode Picker

struct MealLogModePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (MealLogEntryMode) -> Void

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Log a meal")
                        .font(.r(.title2, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("How would you like to log?")
                        .font(.r(.subheadline, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 36)

                HStack(spacing: 12) {
                    modeButton(mode: .notepad, icon: "square.and.pencil", label: "Type")
                    modeButton(mode: .mic,     icon: "mic",               label: "Voice")
                    modeButton(mode: .barcode, icon: "barcode.viewfinder", label: "Barcode")
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticService.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(7)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
            }
        }
    }

    private func modeButton(mode: MealLogEntryMode, icon: String, label: String) -> some View {
        Button {
            HapticService.selectionChanged()
            onSelect(mode)
        } label: {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(AppColors.primary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle().fill(AppColors.primaryContainer)
                    )
                Text(label)
                    .font(.r(.footnote, .semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet Content (creates ViewModel once per presentation)

struct MealLogSheetContent: View {
    let homeViewModel: HomeViewModel
    let selectedDate: Date
    var didSave: Binding<Bool>?
    @StateObject private var mealLogViewModel: MealLogViewModel
    @State private var navigationPath = NavigationPath()
    @Environment(\.dismiss) private var dismiss

    init(homeViewModel: HomeViewModel, selectedDate: Date, didSave: Binding<Bool>? = nil) {
        self.homeViewModel = homeViewModel
        self.selectedDate = selectedDate
        self.didSave = didSave
        _mealLogViewModel = StateObject(wrappedValue: MealLogViewModel(homeViewModel: homeViewModel, selectedDate: selectedDate))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            MealLogModePickerView { mode in
                navigationPath.append(mode)
            }
            .navigationDestination(for: MealLogEntryMode.self) { mode in
                switch mode {
                case .notepad:
                    MealLogView(
                        viewModel: mealLogViewModel,
                        selectedDate: selectedDate,
                        onBarcodeTap: { navigationPath.append(MealLogEntryMode.barcode) }
                    )
                case .mic:
                    VoiceMealLogView(viewModel: mealLogViewModel, selectedDate: selectedDate)
                case .barcode:
                    BarcodeScanView(
                        viewModel: mealLogViewModel,
                        homeViewModel: homeViewModel,
                        selectedDate: selectedDate
                    )
                }
            }
        }
        .onChange(of: mealLogViewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss {
                didSave?.wrappedValue = true
                mealLogViewModel.resetDismissState()
                dismiss()
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
