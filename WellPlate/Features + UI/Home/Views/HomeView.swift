import SwiftUI
import SwiftData

// MARK: - HomeView
// Redesigned dashboard: header, wellness rings, quick log, mood check-in,
// hydration, activity, and stress insight sections.

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var userGoalsList: [UserGoals]
    @Query(sort: \FoodLogEntry.createdAt, order: .forward) private var allFoodLogs: [FoodLogEntry]
    @Query private var allWellnessDayLogs: [WellnessDayLog]

    @Binding var selectedTab: Int

    // MARK: - State

    @State private var selectedMood: MoodOption?
    @State private var hasLoggedMoodToday = false
    @State private var hydrationGlasses: Int = 0
    @State private var coffeeCups: Int = 0
    @State private var showLogMeal = false
    @State private var showWaterDetail = false
    @State private var showCoffeeDetail = false
    @State private var showWellnessCalendar = false
    @State private var showCoffeeTypePicker = false
    @State private var showCoffeeWaterAlert = false
    /// Handoff variable for the sheet→alert race-safe pattern.
    /// Set by the picker closure, read by onChange(of: showCoffeeTypePicker).
    @State private var pendingCoffeeType: CoffeeType? = nil
    @State private var showAIInsight = false
    @State private var dragLogProgress: CGFloat = 0
    @StateObject private var foodJournalViewModel = HomeViewModel()
    @StateObject private var insightService = StressInsightService()

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
              ScrollView {
                LazyVStack(spacing: 16) {

                    // 1. Header
                    homeHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // 2. Wellness Rings Card
                    WellnessRingsCard(
                        rings: wellnessRings,
                        completionPercent: wellnessCompletionPercent,
                        onRingTap: { destination in
                            switch destination {
                            case .calories: showLogMeal = true
                            case .water:    showWaterDetail = true
                            case .exercise: selectedTab = 1
                            case .stress:   selectedTab = 2
                            }
                        }
                    )
                    .padding(.horizontal, 16)

                    // 3. Quick Log
//                    QuickLogSection(
//                        showsMoodLog: !hasLoggedMoodToday,
//                        waterGoalReached: hydrationGlasses >= currentGoals.waterDailyCups,
//                        onLogMeal: {
//                            showLogMeal = true
//                        },
//                        onLogWater: {
//                            if hydrationGlasses < currentGoals.waterDailyCups { hydrationGlasses += 1 }
//                        },
//                        onExercise: { /* TODO: navigate to exercise log */ },
//                        onMood:     { /* scroll handled by section below */ }
//                    )
//                    .padding(.horizontal, 16)

                    // 4. Mood Check-In
                    if !hasLoggedMoodToday {
                        MoodCheckInCard(selectedMood: $selectedMood)
                            .padding(.horizontal, 16)
                    }

                    // 5. Hydration
                    HydrationCard(
                        glassesConsumed: $hydrationGlasses,
                        totalGlasses: currentGoals.waterDailyCups,
                        cupSizeML: currentGoals.waterCupSizeML,
                        onTap: { showWaterDetail = true }
                    )
                    .padding(.horizontal, 16)

                    // 6. Coffee
                    CoffeeCard(
                        cupsConsumed: $coffeeCups,
                        totalCups: currentGoals.coffeeDailyCups,
                        coffeeType: todayWellnessLog?.resolvedCoffeeType,
                        onTap: { showCoffeeDetail = true }
                    )
                    .padding(.horizontal, 16)

                    // 7. Activity
//                    ActivityCard.sample()
//                        .padding(.horizontal, 16)

                    // 7. Stress Insight
//                    StressInsightCard(
//                        stressLevel: "Low",
//                        tip: "Try a 5-min breathing exercise to stay centered 🧘",
//                        onStart: { /* TODO: navigate to stress / breathing */ }
//                    )
//                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 32)
              }
              .blur(radius: dragLogProgress * 14)
              .overlay(
                  Color.black.opacity(dragLogProgress * 0.25)
                      .ignoresSafeArea()
                      .allowsHitTesting(false)
              )
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let hAmt = value.translation.width
                        let vAmt = abs(value.translation.height)
                        // Right swipe: clearly horizontal and to the right
                        if hAmt > 80 && hAmt > vAmt * 1.5 {
                            HapticService.impact(.medium)
                            showLogMeal = true
                        }
                    }
            )
            .safeAreaInset(edge: .bottom) {
                DragToLogOverlay(onTrigger: {
                    showLogMeal = true
                }, dragProgress: $dragLogProgress)
                .padding(.bottom, 4)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollIndicators(.hidden)
            // Navigation destination for Log Meal
            .navigationDestination(isPresented: $showLogMeal) {
                FoodJournalView(viewModel: foodJournalViewModel)
            }
            .navigationDestination(isPresented: $showWaterDetail) {
                WaterDetailView(
                    totalGlasses: currentGoals.waterDailyCups,
                    cupSizeML: currentGoals.waterCupSizeML
                )
            }
            .navigationDestination(isPresented: $showCoffeeDetail) {
                CoffeeDetailView(
                    totalCups: currentGoals.coffeeDailyCups,
                    coffeeType: todayWellnessLog?.resolvedCoffeeType
                )
            }
            .navigationDestination(isPresented: $showWellnessCalendar) {
                WellnessCalendarView()
            }
            .navigationDestination(isPresented: $showAIInsight) {
                HomeAIInsightView(insightService: insightService)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Inject the model context into the VM once the environment is available.
            foodJournalViewModel.bindContext(modelContext)
            insightService.bindContext(modelContext)
            refreshTodayMoodState()
            refreshTodayHydrationState()
            refreshTodayCoffeeState()
        }
        .onChange(of: showWaterDetail) { _, showing in
            if !showing { refreshTodayHydrationState() }
        }
        .onChange(of: showCoffeeDetail) { _, showing in
            if !showing { refreshTodayCoffeeState() }
        }
        .onChange(of: selectedMood) { _, mood in
            guard let mood else { return }
            logMoodForTodayIfNeeded(mood)
        }
        .onChange(of: hydrationGlasses) { _, cups in
            updateHydrationForToday(cups)
        }
        .onChange(of: coffeeCups) { oldCups, newCups in
            if newCups > oldCups {
                // Addition path
                if newCups == 1 && todayWellnessLog?.coffeeType == nil {
                    // First cup, no type chosen — show picker.
                    // Cup count is saved optimistically; type saved after picker selection.
                    updateCoffeeForToday(cups: newCups, type: nil)
                    showCoffeeTypePicker = true
                    // Water alert fires in onChange(of: showCoffeeTypePicker) after sheet closes.
                } else {
                    // Subsequent cup or type already known.
                    updateCoffeeForToday(cups: newCups, type: todayWellnessLog?.resolvedCoffeeType)
                    showCoffeeWaterAlert = true
                }
            } else {
                // Decrement — persist only, no water alert.
                updateCoffeeForToday(cups: newCups, type: todayWellnessLog?.resolvedCoffeeType)
            }
        }
        // Race-safe: alert fires only after the sheet animation has fully completed.
        .onChange(of: showCoffeeTypePicker) { _, isShowing in
            guard !isShowing else { return }
            if let type = pendingCoffeeType {
                // User selected a type — save it and show the water alert.
                pendingCoffeeType = nil
                updateCoffeeForToday(cups: coffeeCups, type: type)
                showCoffeeWaterAlert = true
            } else {
                // User swiped picker away without selecting — revert the cup increment.
                coffeeCups = max(0, coffeeCups - 1)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshTodayMoodState()
            refreshTodayHydrationState()
            refreshTodayCoffeeState()
        }
        // Coffee type picker sheet
        .sheet(isPresented: $showCoffeeTypePicker) {
            CoffeeTypePickerSheet { type in
                pendingCoffeeType = type
                showCoffeeTypePicker = false
            }
        }
        // Water nudge alert after every coffee addition
        .alert("Stay Hydrated!", isPresented: $showCoffeeWaterAlert) {
            Button("Log Water") {
                if hydrationGlasses < currentGoals.waterDailyCups {
                    hydrationGlasses += 1
                }
            }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("Coffee can cause dehydration. Want to log a glass of water too?")
        }
    }

    // MARK: - Header

    private var homeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayString)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(greeting)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // AI Insights pill
            Button {
                HapticService.impact(.light)
                showAIInsight = true
                Task { await insightService.generateInsight() }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.brand.opacity(0.65),
                                    AppColors.brand.opacity(0.65)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: AppColors.brand.opacity(0.12), radius: 6, x: 0, y: 3)

                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            // Calendar button
            Button {
                HapticService.impact(.light)
                showWellnessCalendar = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.brand.opacity(0.65),
                                    AppColors.brand.opacity(0.65)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: AppColors.brand.opacity(0.12), radius: 6, x: 0, y: 3)

                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            // Mood badge — visible only when mood is logged today
            if hasLoggedMoodToday, let mood = selectedMood {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 44, height: 44)
                        .shadow(color: mood.accentColor.opacity(0.25), radius: 6, x: 0, y: 3)

                    Circle()
                        .stroke(mood.accentColor.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 44, height: 44)

                    Text(mood.emoji)
                        .font(.system(size: 22))
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    // MARK: - Wellness Rings Data

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todayWellnessLog: WellnessDayLog? {
        allWellnessDayLogs.first { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
    }

    private var todayCalories: Int {
        allFoodLogs.filter { $0.day == todayStart }.reduce(0) { $0 + $1.calories }
    }

    private var wellnessRings: [WellnessRingItem] {
        let cupGoal = currentGoals.waterDailyCups
        let energyGoal = currentGoals.activeEnergyGoalKcal
        let calorieGoal = currentGoals.calorieGoal
        let log = todayWellnessLog

        let calorieProgress: CGFloat = calorieGoal > 0
            ? min(1.0, CGFloat(todayCalories) / CGFloat(calorieGoal))
            : 0
        let waterProgress = cupGoal > 0 ? min(1.0, CGFloat(hydrationGlasses) / CGFloat(cupGoal)) : 0
        let burnedKcal = log?.caloriesBurned ?? 0
        let exerciseProgress: CGFloat = energyGoal > 0
            ? min(1.0, CGFloat(burnedKcal) / CGFloat(energyGoal))
            : 0
        let stressProgress = stressProgressFromLevel(log?.stressLevel)

        return [
            WellnessRingItem(
                label: "Calories",
                sublabel: "/ \(calorieGoal)",
                value: "\(todayCalories)",
                progress: calorieProgress,
                color: AppColors.brand,
                emojiOrSymbol: nil,
                inlineLabel: nil,
                destination: .calories
            ),
            WellnessRingItem(
                label: "Water",
                sublabel: "/ \(cupGoal) cups",
                value: "\(hydrationGlasses)",
                progress: waterProgress,
                color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82),
                emojiOrSymbol: nil,
                inlineLabel: nil,
                destination: .water
            ),
            WellnessRingItem(
                label: "Exercise",
                sublabel: "/ \(energyGoal) kcal",
                value: "\(burnedKcal)",
                progress: exerciseProgress,
                color: Color(hue: 0.50, saturation: 0.62, brightness: 0.70),
                emojiOrSymbol: nil,
                inlineLabel: nil,
                destination: .exercise
            ),
            WellnessRingItem(
                label: "Stress",
                sublabel: "Today",
                value: "",
                progress: stressProgress,
                color: Color(hue: 0.76, saturation: 0.50, brightness: 0.75),
                emojiOrSymbol: stressEmojiFromLevel(log?.stressLevel),
                inlineLabel: log?.stressLevel,
                destination: .stress
            )
        ]
    }

    private var wellnessCompletionPercent: Int {
        let cupGoal = currentGoals.waterDailyCups
        let energyGoal = currentGoals.activeEnergyGoalKcal
        let calorieGoal = currentGoals.calorieGoal
        let log = todayWellnessLog

        let calorieProgress = calorieGoal > 0 ? min(1.0, CGFloat(todayCalories) / CGFloat(calorieGoal)) : 0
        let waterProgress = cupGoal > 0 ? min(1.0, CGFloat(hydrationGlasses) / CGFloat(cupGoal)) : 0
        let burnedKcal = log?.caloriesBurned ?? 0
        let exerciseProgress = energyGoal > 0 ? min(1.0, CGFloat(burnedKcal) / CGFloat(energyGoal)) : 0
        let stressProgress = stressProgressFromLevel(log?.stressLevel)

        let average = (calorieProgress + waterProgress + exerciseProgress + stressProgress) / 4
        return min(100, Int(round(average * 100)))
    }

    private func stressProgressFromLevel(_ level: String?) -> CGFloat {
        switch level?.lowercased() {
        case "excellent": return 0.05
        case "good":      return 0.25
        case "moderate":  return 0.50
        case "high":      return 0.75
        case "very high": return 1.0
        default:          return 0
        }
    }

    private func stressEmojiFromLevel(_ level: String?) -> String? {
        switch level?.lowercased() {
        case "excellent": return "😄"
        case "good":      return "😌"
        case "moderate":  return "😐"
        case "high":      return "😣"
        case "very high": return "😰"
        default:          return "—"
        }
    }

    // MARK: - Helpers

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good Morning, Alex"
        case 12..<17: return "Good Afternoon, Alex"
        default:      return "Good Evening, Alex"
        }
    }

    // MARK: - Mood Logging

    private func refreshTodayMoodState() {
        guard let log = fetchTodayWellnessLog() else {
            hasLoggedMoodToday = false
            selectedMood = nil
            return
        }

        if let mood = log.mood {
            hasLoggedMoodToday = true
            selectedMood = mood
        } else {
            hasLoggedMoodToday = false
            selectedMood = nil
        }
    }

    private func logMoodForTodayIfNeeded(_ mood: MoodOption) {
        guard !hasLoggedMoodToday else { return }

        let todayLog = fetchOrCreateTodayWellnessLog()
        if todayLog.moodRaw != nil {
            hasLoggedMoodToday = true
            selectedMood = todayLog.mood
            return
        }

        todayLog.moodRaw = mood.rawValue
        do {
            try modelContext.save()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                hasLoggedMoodToday = true
            }
        } catch {
            hasLoggedMoodToday = false
            selectedMood = nil
            WPLogger.home.error("Mood save failed: \(error.localizedDescription)")
        }
    }

    private func refreshTodayHydrationState() {
        hydrationGlasses = fetchTodayWellnessLog()?.waterGlasses ?? 0
    }

    private func updateHydrationForToday(_ cups: Int) {
        let safeCups = max(cups, 0)
        let todayLog = fetchOrCreateTodayWellnessLog()
        guard todayLog.waterGlasses != safeCups else { return }

        todayLog.waterGlasses = safeCups
        do {
            try modelContext.save()
        } catch {
            WPLogger.home.error("Hydration save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Coffee Logging

    private func refreshTodayCoffeeState() {
        coffeeCups = fetchTodayWellnessLog()?.coffeeCups ?? 0
    }

    private func updateCoffeeForToday(cups: Int, type: CoffeeType?) {
        let log = fetchOrCreateTodayWellnessLog()
        log.coffeeCups = max(0, cups)
        if let type { log.coffeeType = type.rawValue }
        do {
            try modelContext.save()
        } catch {
            WPLogger.home.error("Coffee save failed: \(error.localizedDescription)")
        }
    }

    private func fetchTodayWellnessLog() -> WellnessDayLog? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == today }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchOrCreateTodayWellnessLog() -> WellnessDayLog {
        if let existing = fetchTodayWellnessLog() {
            return existing
        }

        let newLog = WellnessDayLog(day: Date())
        modelContext.insert(newLog)
        return newLog
    }
}

// MARK: - Preview

#Preview("Home Dashboard") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: FoodLogEntry.self, WellnessDayLog.self, UserGoals.self,
        configurations: config
    )
    return HomeView(selectedTab: .constant(0))
        .modelContainer(container)
}
