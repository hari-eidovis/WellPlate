import SwiftUI
import SwiftData

// MARK: - FoodJournalView
// Previously HomeView — opened when the user taps "Log Meal" in the Quick Log section.

struct FoodJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var mealLogViewModel: MealLogViewModel
    @Query private var userGoalsList: [UserGoals]

    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var showProgressInsights = false
    @State private var showStreak = false
    @State private var fabExpanded = false
    @State private var showNotepad = false
    @State private var showVoice = false
    @State private var showBarcode = false
    @FocusState private var isTextEditorFocused: Bool

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        _mealLogViewModel = StateObject(wrappedValue: MealLogViewModel(homeViewModel: viewModel))
    }

    /// Static query — no dynamic predicate in init to avoid re-render loops.
    @Query(sort: \FoodLogEntry.createdAt, order: .reverse) private var foodLogs: [FoodLogEntry]

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    // MARK: - Computed Properties

    private var aggregatedNutrition: NutritionalInfo? {
        let targetDay = Calendar.current.startOfDay(for: selectedDate)
        let filteredLogs = foodLogs.filter { $0.day == targetDay }
        guard !filteredLogs.isEmpty else { return nil }

        return NutritionalInfo(
            foodName: "\(filteredLogs.count) item\(filteredLogs.count == 1 ? "" : "s")",
            servingSize: nil,
            calories: min(filteredLogs.reduce(0) { $0 + $1.calories }, 999999),
            protein: filteredLogs.reduce(0.0) { $0 + $1.protein },
            carbs: filteredLogs.reduce(0.0) { $0 + $1.carbs },
            fat: filteredLogs.reduce(0.0) { $0 + $1.fat },
            fiber: filteredLogs.reduce(0.0) { $0 + $1.fiber },
            confidence: nil
        )
    }

    private var navDateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selectedDate)
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        let loggedDays = Set(foodLogs.map { cal.startOfDay(for: $0.day) })
        var start = cal.startOfDay(for: Date())
        if !loggedDays.contains(start) {
            start = cal.date(byAdding: .day, value: -1, to: start) ?? start
        }
        var streak = 0
        var current = start
        while loggedDays.contains(current) {
            streak += 1
            current = cal.date(byAdding: .day, value: -1, to: current) ?? current
        }
        return streak
    }

    private var foodLogsForSelectedDate: [FoodLogEntry] {
        let targetDay = Calendar.current.startOfDay(for: selectedDate)
        return foodLogs.filter { $0.day == targetDay }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 1. Calorie Hero Card
                    CalorieHeroCard(
                        currentNutrition: aggregatedNutrition,
                        dailyGoals: DailyGoals(from: currentGoals)
                    )

                    // 3. Quick-Add Input
//                    QuickAddCard(
//                        foodDescription: $viewModel.foodDescription,
//                        isLoading: viewModel.isLoading,
//                        isFocused: $isTextEditorFocused,
//                        onSubmit: triggerAnalysis
//                    )

                    // 4. Today's Meals
                    MealLogCard(
                        foodLogs: foodLogsForSelectedDate,
                        isToday: Calendar.current.isDateInToday(selectedDate),
                        onDelete: deleteFoodEntry,
                        onAddAgain: addAgain
                    )
                }
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        let hAmt = abs(value.translation.width)
                        let vAmt = abs(value.translation.height)
                        let isHorizontal = hAmt > vAmt * 1.8 && hAmt > 70

                        if isHorizontal {
                            HapticService.selectionChanged()
                            changeDate(by: value.translation.width > 0 ? -1 : 1)
                        }
                    }
            )

            // FAB menu — expands 3 action buttons on tap
            if !isTextEditorFocused {
                fabMenuOverlay
            }

            // Disambiguation overlay
            if let state = viewModel.disambiguationState {
                DisambiguationChipsView(
                    question: state.question,
                    options: state.options,
                    rawInput: state.rawInput,
                    onSelect: { option in
                        viewModel.disambiguationState = nil
                        Task {
                            await viewModel.logFood(on: selectedDate, coachOverride: option.label)
                            await MainActor.run {
                                if !viewModel.showError {
                                    HapticService.notify(.success)
                                    viewModel.foodDescription = ""
                                }
                            }
                        }
                    },
                    onAddAsTyped: {
                        viewModel.disambiguationState = nil
                        Task {
                            await viewModel.logFood(on: selectedDate, coachOverride: state.rawInput)
                            await MainActor.run {
                                if !viewModel.showError {
                                    HapticService.notify(.success)
                                    viewModel.foodDescription = ""
                                }
                            }
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: {
                    HapticService.impact(.light)
                    showDatePicker = true
                }) {
                    HStack(spacing: 4) {
                        Text(navDateText)
                            .font(.r(.headline, .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    HapticService.impact(.light)
                    showStreak = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.brand)
                        Text("\(currentStreak)")
                            .font(.r(15, .semibold))
                            .foregroundColor(.primary)
                    }
                }
                Button(action: {
                    HapticService.impact(.light)
                    showProgressInsights = true
                }) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.brand)
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
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .sheet(isPresented: $showStreak) {
            StreakDetailView()
        }
        .fullScreenCover(isPresented: $showProgressInsights) {
            ProgressInsightsView()
        }
        .navigationDestination(isPresented: $showNotepad) {
            MealLogView(
                viewModel: mealLogViewModel,
                selectedDate: selectedDate,
                onBarcodeTap: { showBarcode = true }
            )
        }
        .navigationDestination(isPresented: $showVoice) {
            VoiceMealLogView(viewModel: mealLogViewModel, selectedDate: selectedDate)
        }
        .navigationDestination(isPresented: $showBarcode) {
            BarcodeScanView(
                viewModel: mealLogViewModel,
                homeViewModel: viewModel,
                selectedDate: selectedDate
            )
        }
    }

    // MARK: - Actions

    private func deleteFoodEntry(_ entry: FoodLogEntry) {
        withAnimation {
            modelContext.delete(entry)
            do {
                try modelContext.save()
            } catch {
                print("Error deleting food entry: \(error)")
            }
        }
    }

    private func changeDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = newDate
            }
        }
    }

    private func addAgain(_ entry: FoodLogEntry) {
        viewModel.foodDescription = entry.foodName
        Task {
            await viewModel.logFood(on: selectedDate)
            await MainActor.run {
                viewModel.foodDescription = ""
            }
        }
    }

    private func triggerAnalysis() {
        isTextEditorFocused = false
        let foodInput = viewModel.foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !foodInput.isEmpty else { return }

        Task {
            await viewModel.logFood(on: selectedDate)
            await MainActor.run {
                if !viewModel.showError {
                    HapticService.notify(.success)
                }
                viewModel.foodDescription = ""
            }
        }
    }

    // MARK: - FAB Menu

    private struct FABAction {
        let icon: String
        let label: String
        let color: Color
    }

    private let fabActions: [FABAction] = [
        FABAction(icon: "square.and.pencil",   label: "Type",    color: Color(hue: 0.62, saturation: 0.55, brightness: 0.80)),
        FABAction(icon: "mic.fill",             label: "Voice",   color: Color(hue: 0.76, saturation: 0.45, brightness: 0.78)),
        FABAction(icon: "barcode.viewfinder",   label: "Barcode", color: AppColors.brand),
    ]

    private var fabMenuOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 14) {
                    // Action buttons fan up (Type at top, Barcode at bottom)
                    ForEach(Array(fabActions.enumerated()), id: \.offset) { idx, action in
                        HStack(spacing: 10) {
                            // Label pill
                            Text(action.label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
                                )

                            // Icon circle
                            Button {
                                HapticService.impact(.medium)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    fabExpanded = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    switch idx {
                                    case 0: showNotepad = true
                                    case 1: showVoice = true
                                    default: showBarcode = true
                                    }
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(action.color)
                                        .frame(width: 46, height: 46)
                                        .shadow(color: action.color.opacity(0.35), radius: 8, x: 0, y: 4)
                                    Image(systemName: action.icon)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .opacity(fabExpanded ? 1 : 0)
                        .offset(y: fabExpanded ? 0 : 24)
                        // Stagger: Barcode (idx 2) first, Type (idx 0) last
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.7)
                                .delay(fabExpanded
                                       ? Double(fabActions.count - 1 - idx) * 0.07
                                       : Double(idx) * 0.04),
                            value: fabExpanded
                        )
                    }

                    // Main FAB
                    Button {
                        HapticService.impact(.medium)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            fabExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle().fill(
                                    LinearGradient(
                                        colors: [AppColors.brand, AppColors.brand.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            )
                            .shadow(color: AppColors.brand.opacity(0.35), radius: 10, x: 0, y: 5)
                            .rotationEffect(.degrees(fabExpanded ? 45 : 0))
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: fabExpanded)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 8)
            }
        }
        // Dim overlay behind the buttons — tap to dismiss
        .background(
            fabExpanded
                ? Color.black.opacity(0.25).ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            fabExpanded = false
                        }
                    }
                : nil
        )
        .animation(.easeInOut(duration: 0.2), value: fabExpanded)
    }

    // MARK: - Date Picker Sheet

    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(AppColors.brand)
                .padding()

                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Today") {
                        selectedDate = Date()
                    }
                    .foregroundColor(AppColors.brand)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("Food Journal") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodLogEntry.self, configurations: config)
    return NavigationStack {
        FoodJournalView(viewModel: HomeViewModel(modelContext: container.mainContext))
    }
    .modelContainer(container)
}
