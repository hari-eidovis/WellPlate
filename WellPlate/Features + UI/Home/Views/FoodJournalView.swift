import SwiftUI
import SwiftData

// MARK: - FoodJournalView
// Previously HomeView — opened when the user taps "Log Meal" in the Quick Log section.

struct FoodJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: HomeViewModel
    @Query private var userGoalsList: [UserGoals]

    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var showProgressInsights = false
    @State private var showStreak = false
    @FocusState private var isTextEditorFocused: Bool

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
                    // 1. Header
                    HomeHeaderView(
                        selectedDate: selectedDate,
                        currentStreak: currentStreak,
                        onDateTap: { showDatePicker = true },
                        onStreakTap: { showStreak = true },
                        onChartTap: { showProgressInsights = true }
                    )

                    // 2. Calorie Hero Card
                    CalorieHeroCard(
                        currentNutrition: aggregatedNutrition,
                        dailyGoals: DailyGoals(from: currentGoals)
                    )

                    // 3. Quick-Add Input
                    QuickAddCard(
                        foodDescription: $viewModel.foodDescription,
                        isLoading: viewModel.isLoading,
                        isFocused: $isTextEditorFocused,
                        onSubmit: triggerAnalysis
                    )

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

            // Expandable FAB
            if !isTextEditorFocused {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ExpandableFAB(
                            onMicTap: { /* TODO */ },
                            onCameraTap: { /* TODO */ },
                            onNotepadTap: { isTextEditorFocused = true }
                        )
                        .padding(.trailing, 20)
                        .padding(.bottom, 8)
                    }
                }
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
        .navigationTitle("Food Journal")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Date Picker Sheet

    private var datePickerSheet: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
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
                    .foregroundColor(.orange)
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
