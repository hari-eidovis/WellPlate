import SwiftUI
import SwiftData
import UIKit

// MARK: - MealLogView

struct MealLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: MealLogViewModel

    let selectedDate: Date
    @FocusState private var isFoodFieldFocused: Bool
    @FocusState private var isQuantityFieldFocused: Bool

    // MARK: Claude palette (inline — view-scoped to avoid touching shared tokens)
    private let cBackground = Color(red: 0.957, green: 0.953, blue: 0.933) // Pampas  #F4F3EE
    private let cSurface    = Color.white                                  // White   #FFFFFF
    private let cMuted      = Color(red: 0.694, green: 0.678, blue: 0.631) // Cloudy  #B1ADA1
    private let cInk        = Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
    private let cDivider    = Color(red: 0.894, green: 0.886, blue: 0.859)

    var body: some View {
        ZStack {
            cBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    mealTypePicker
                    foodInputCard
                    quantityCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)

            if let state = viewModel.disambiguationState {
                disambiguationOverlay(state: state)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .toolbarBackground(cBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Something went wrong", isPresented: $viewModel.showError) {
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
            Text("Cadence needs microphone and speech recognition access to transcribe your meal. Enable both in Settings → Privacy.")
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Log a meal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(cInk)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                isFoodFieldFocused = false
                isQuantityFieldFocused = false
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
                Task { await viewModel.saveMeal(selectedDate: selectedDate) }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: cInk))
                } else {
                    Text("Save")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(saveEnabled ? cInk : cMuted)
                }
            }
            .disabled(!saveEnabled)
        }
    }

    private var saveEnabled: Bool {
        viewModel.isValid && !viewModel.isLoading && !viewModel.isTranscribing
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What did you eat?")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundColor(cInk)
                .tracking(-0.4)
            Text("A few words is enough. We'll figure out the rest.")
                .font(.system(size: 14))
                .foregroundColor(cMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Meal Type Picker

    private var mealTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MealType.allCases) { type in
                    let isSelected = viewModel.selectedMealType == type
                    Button {
                        HapticService.selectionChanged()
                        viewModel.selectedMealType = type
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(type.displayName)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(isSelected ? cSurface : cInk.opacity(0.75))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSelected ? cInk : cSurface)
                        )
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : cDivider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Food Input Card

    private var foodInputCard: some View {
        TextField("", text: $viewModel.foodDescription, prompt: Text("e.g. Avocado toast").foregroundColor(cMuted), axis: .vertical)
            .font(.system(size: 17, weight: .regular))
            .foregroundColor(cInk)
            .textFieldStyle(.plain)
            .focused($isFoodFieldFocused)
            .disabled(viewModel.isLoading)
            .tint(cInk)
            .lineLimit(1...4)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cDivider, lineWidth: 1)
                    )
            )
    }

    // MARK: - Quantity Card

    private var quantityCard: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.quantityUnit == .millilitres ? "drop" : "scalemass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(cMuted)
                .frame(width: 18)

            TextField("", text: $viewModel.quantity, prompt: Text("Amount").foregroundColor(cMuted))
                .font(.system(size: 16))
                .foregroundColor(cInk)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .focused($isQuantityFieldFocused)
                .disabled(viewModel.isLoading)
                .tint(cInk)

            unitToggle
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cDivider, lineWidth: 1)
                )
        )
    }

    private var unitToggle: some View {
        HStack(spacing: 0) {
            ForEach(QuantityUnit.allCases) { unit in
                let isSelected = viewModel.quantityUnit == unit
                Button {
                    HapticService.selectionChanged()
                    viewModel.quantityUnit = unit
                } label: {
                    Text(unit.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? cSurface : cInk.opacity(0.7))
                        .frame(width: 32, height: 26)
                        .background(
                            Capsule().fill(isSelected ? cInk : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
        }
        .padding(2)
        .background(
            Capsule().fill(cBackground)
        )
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
                        selectedDate: selectedDate
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
        .sheet(item: $mealLogViewModel.beverageVariantPrompt) { prompt in
            switch prompt {
            case .coffee:
                CoffeeTypePickerSheet { type in
                    Task {
                        await mealLogViewModel.resolveBeverageVariant(
                            variantName: type.displayName,
                            selectedDate: selectedDate
                        )
                    }
                }
            case .tea:
                TeaTypePickerSheet { type in
                    Task {
                        await mealLogViewModel.resolveBeverageVariant(
                            variantName: type.displayName,
                            selectedDate: selectedDate
                        )
                    }
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
        .onChange(of: mealLogViewModel.beverageVariantPrompt) { _, prompt in
            // Belt-and-braces: even if the Save button forgot to dismiss focus
            // (or save was triggered from the voice flow), force the keyboard
            // down before the variant picker presents.
            if prompt != nil {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
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
