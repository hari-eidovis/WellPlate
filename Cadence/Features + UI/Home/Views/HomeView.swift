import SwiftUI
import SwiftData

// MARK: - HomeSheet

enum HomeSheet: Identifiable, Equatable {
    case changeMood
    case insights
    case fasting

    var id: String {
        switch self {
        case .changeMood:   return "changeMood"
        case .insights:     return "insights"
        case .fasting:      return "fasting"
        }
    }
}

// MARK: - HomeView
// Fixed "bento" dashboard: header, Today's Focus hero, a 2×2 grid of equal
// metric tiles (stress, water, calories, move), then the mood check-in card.
// The bottom ContextualActionBar (meal action) is preserved.

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var userGoalsList: [UserGoals]
    @Query(sort: \FoodLogEntry.createdAt, order: .forward) private var allFoodLogs: [FoodLogEntry]
    @Query private var allWellnessDayLogs: [WellnessDayLog]
    @Query(sort: \StressReading.timestamp) private var allStressReadings: [StressReading]

    @Binding var selectedTab: Int
    /// Shared instance from MainTabView. HomeView observes `totalScore` /
    /// `stressLevel` directly so the stress ring stays in sync with the Stress
    /// tab even when the user is logging mood/water/food/etc.
    @ObservedObject var stressViewModel: StressViewModel

    // MARK: - State

    @State private var selectedMood: MoodOption?
    @State private var hasLoggedMoodToday = false
    @State private var healthSuggestedMood: MoodOption?
    @State private var hydrationGlasses: Int = 0
    @State private var showLogMeal = false
    @State private var showWaterDetail = false
    // TODO: F-next — re-home WellnessCalendarView to Profile tab. Kept as dead
    // navigation state to avoid touching the nav chain; remove with that move.
    @State private var showWellnessCalendar = false
    @State private var activeSheet: HomeSheet?
    /// Celebration when the user hits their daily water goal. Fires at most
    /// once per calendar day (guarded by `waterGoalCelebratedDay`).
    @State private var showWaterGoalCelebration = false
    /// Stores yyyy-MM-dd of the last day we celebrated the water goal so the
    /// alert doesn't fire again after dropping/re-hitting the cup count.
    @AppStorage("waterGoalCelebratedDay") private var waterGoalCelebratedDay: String = ""
    /// Guards against onChange(of: hydrationGlasses) firing during initial state restoration.
    @State private var hasHydrationStateLoaded = false
    @State private var showBurnView = false
    @StateObject private var foodJournalViewModel = HomeViewModel()
    @StateObject private var insightEngine = InsightEngine()

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    // MARK: - Home Scroll Content

    private var homeScrollContent: some View {
        LazyVStack(spacing: 16) {
            homeHeader
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // Today's Focus — insight card with floral artwork
            DailyInsightCard(
                card: insightEngine.dailyInsight,
                isGenerating: insightEngine.isGenerating,
                onTap: { activeSheet = .insights },
                insufficientData: insightEngine.insufficientData,
                daysRemaining: insightEngine.daysRemaining
            )
            .padding(.horizontal, 16)

            // Today's stress score — big "NN /100" headline + context pills.
            // Tapping jumps to the Stress tab for the full breakdown.
            HomeStressScoreCard(
                viewModel: stressViewModel,
                onTap: { selectedTab = 1 }
            )
            .padding(.horizontal, 16)

            // Bento grid: four equal tiles — calories + water (top),
            // screen time + move (bottom).
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    HomeMetricTile(
                        .calories(
                            current: todayCalories,
                            goal: currentGoals.calorieGoal
                        ),
                        onTap: { showLogMeal = true }
                    )
                    HomeMetricTile(
                        .screenTime(hours: stressViewModel.screenTimeDisplayHours),
                        onTap: { selectedTab = 1 }
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    HomeMetricTile(
                        .water(
                            current: hydrationGlasses,
                            goal: currentGoals.waterDailyCups,
                            behind: expectedCupsDeficit()
                        ),
                        onTap: { showWaterDetail = true }
                    )
                    HomeMetricTile(
                        .move(
                            steps: todayWellnessLog?.steps ?? 0,
                            goal: currentGoals.dailyStepsGoal
                        ),
                        onTap: { showBurnView = true }
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)

            // Mood check-in — prompts until a mood is logged for today
            if !hasLoggedMoodToday {
                MoodCheckInCard(selectedMood: $selectedMood, suggestion: healthSuggestedMood)
                    .padding(.horizontal, 16)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            }

            // Footnote: Cadence's scores are estimates, not medical advice.
            medicalDisclaimer
        }
        .padding(.bottom, 32)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: hasLoggedMoodToday)
    }

    // MARK: - Medical Disclaimer

    /// Footer note clarifying that Cadence's scores and insights are estimates,
    /// not medical advice. Stress, calorie, hydration, and activity figures are
    /// derived from device sensors, Health data, and what the user logs — all of
    /// which external factors can skew.
    private var medicalDisclaimer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Important:")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Cadence is not a medical device. Your stress score, insights, and nutrition, hydration, and activity figures are estimates drawn from your device sensors, Health data, and what you log. External factors can affect their accuracy. Use them only as a reference and seek professional medical advice if you're unsure.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Contextual Action Bar

    private var contextualActionBar: some View {
        ContextualActionBar(
            state: contextualBarState,
            onLogMeal: { showLogMeal = true },
            onStressTab: { selectedTab = 1 },
            onSeeInsight: {
                activeSheet = .insights
            },
            onFasting: { activeSheet = .fasting }
        )
        .padding(.bottom, 4)
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: HomeSheet) -> some View {
        switch sheet {
        case .changeMood:
            MoodCheckInSheet(onSaved: { stressViewModel.recompute(reason: .manualMood) })
        case .insights:
            NavigationStack {
                InsightsHubView(engine: insightEngine)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
            }
        case .fasting:
            FastingView()
        }
    }

    // MARK: - Navigation Content

    private var navigationContent: some View {
        ScrollView {
            homeScrollContent
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let hAmt = value.translation.width
                    let vAmt = abs(value.translation.height)
                    if hAmt > 80 && hAmt > vAmt * 1.5 {
                        HapticService.impact(.medium)
                        showLogMeal = true
                    }
                }
        )
        .safeAreaInset(edge: .bottom) {
            contextualActionBar
        }
        .background(HomePalette.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationDestination(isPresented: $showLogMeal) {
            FoodJournalView(viewModel: foodJournalViewModel)
        }
        .navigationDestination(isPresented: $showWaterDetail) {
            WaterDetailView(totalGlasses: currentGoals.waterDailyCups, cupSizeML: currentGoals.waterCupSizeML)
        }
        .navigationDestination(isPresented: $showBurnView) { BurnView() }
        .navigationDestination(isPresented: $showWellnessCalendar) { WellnessCalendarView() }
        .navigationBarHidden(true)
    }

    // MARK: - Body

    var body: some View {
        bodyPart1
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshTodayMoodState()
                refreshTodayHydrationState()
                refreshTodayActivityFromHealthKit()
            }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
            .alert("Nice work! 🎉", isPresented: $showWaterGoalCelebration) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You hit your daily water goal.")
            }
    }

    private var bodyPart1: some View {
        NavigationStack {
            navigationContent
        }
        .onAppear {
            foodJournalViewModel.bindContext(modelContext)
            insightEngine.bindContext(modelContext)
            Task { await insightEngine.generateInsights() }
            refreshTodayMoodState()
            refreshTodayHydrationState()
            // Defer flipping the hydration guard to the next runloop so the
            // initial 0 → restored-value onChange fires while the guard is
            // still false. Otherwise SwiftUI batches the @State writes and the
            // celebration trips on launch, burning waterGoalCelebratedDay.
            DispatchQueue.main.async {
                hasHydrationStateLoaded = true
            }
            foodJournalViewModel.loadYesterdayStats()
            refreshTodayActivityFromHealthKit()
        }
        .onChange(of: showWaterDetail) { _, showing in
            if !showing { refreshTodayHydrationState() }
        }
        .onChange(of: selectedMood) { _, mood in
            guard let mood else { return }
            logMoodForTodayIfNeeded(mood)
        }
        .onChange(of: hydrationGlasses) { oldCups, cups in
            updateHydrationForToday(cups)
            handleWaterGoalCrossing(from: oldCups, to: cups)
        }
        .onChange(of: activeSheet) { old, new in
            if old == .changeMood && new == nil {
                // Sheet's `onSaved` already triggered recompute(); just refresh
                // the badge emoji from the persisted log here.
                refreshTodayMoodState()
            }
        }
    }

    // MARK: - Header

    private var homeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayString)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)

                if userName.isEmpty {
                    Text(greetingPrefix)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    HStack(spacing: 4) {
                        Text("\(greetingPrefix),")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(userName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .background(alignment: .top) {
                                LottieLoopView(name: "hiddencat")
                                    .frame(width: 60, height: 60)
                                    .offset(y: -60)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                    }
                }
            }

            Spacer()

            // AI Insights button
            Button {
                HapticService.impact(.light)
                activeSheet = .insights
            } label: {
                headerIcon("sparkles")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Insights")

            // Mood button — emoji badge when logged, subtle face icon otherwise
            Button {
                HapticService.impact(.light)
                activeSheet = .changeMood
            } label: {
                if hasLoggedMoodToday, let mood = selectedMood {
                    moodBadge(mood)
                } else {
                    headerIcon("face.smiling")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasLoggedMoodToday ? "Change today's mood" : "Log your mood")
        }
    }

    // MARK: - Header Helpers

    /// Circular header button — black circle + white glyph with a soft shadow.
    @ViewBuilder
    private func headerIcon(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: 40, height: 40)
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func moodBadge(_ mood: MoodOption) -> some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 40, height: 40)
                .shadow(color: mood.accentColor.opacity(0.25), radius: 6, x: 0, y: 3)

            Circle()
                .stroke(mood.accentColor.opacity(0.35), lineWidth: 1.5)
                .frame(width: 40, height: 40)

            Text(mood.emoji)
                .font(.system(size: 20))
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: - Date Helpers

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todayWellnessLog: WellnessDayLog? {
        allWellnessDayLogs.first { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
    }

    // MARK: - Stress Data

    private var todayStressReadings: [StressReading] {
        allStressReadings.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    /// Live score from the shared StressViewModel. Nil until the first
    /// successful load so the ring can fall back to the latest persisted reading.
    private var liveStressScore: Double? {
        guard stressViewModel.isAuthorized || stressViewModel.usesMockData else { return nil }
        guard stressViewModel.totalScore > 0 else { return nil }
        return stressViewModel.totalScore
    }

    // MARK: - Nutrition Data

    private var todayCalories: Int {
        allFoodLogs.filter { $0.day == todayStart }.reduce(0) { $0 + $1.calories }
    }

    /// Today's food log entries, filtered from the `@Query` result.
    private var todayFoodLogs: [FoodLogEntry] {
        allFoodLogs.filter { $0.day == todayStart }
    }

    // MARK: - Contextual Bar State

    /// Pure computed property. Evaluated on every body call.
    /// Priority: goalsCelebration > stressActionable > logNextMeal > defaultActions
    private var contextualBarState: ContextualBarState {
        if wellnessCompletionPercent >= 100 {
            return .goalsCelebration
        }
        if let level = effectiveStressLevel?.lowercased(),
           level == "high" || level == "very high" {
            return .stressActionable(level: effectiveStressLevel ?? "High")
        }
        if let mealLabel = nextMealLabel() {
            return .logNextMeal(mealLabel: mealLabel)
        }
        return .defaultActions
    }

    /// Returns how many cups behind the user is vs. expected pace (wake 07:00, sleep 22:00).
    private func expectedCupsDeficit() -> Int {
        let target = currentGoals.waterDailyCups
        guard target > 0 else { return 0 }

        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        let wakeComponents = DateComponents(hour: 7, minute: 0)
        let sleepComponents = DateComponents(hour: 22, minute: 0)
        guard let wake = cal.date(byAdding: wakeComponents, to: dayStart),
              let sleep = cal.date(byAdding: sleepComponents, to: dayStart) else { return 0 }

        let total = sleep.timeIntervalSince(wake)
        guard total > 0 else { return 0 }
        let elapsed = max(0, min(now.timeIntervalSince(wake), total))
        let fraction = elapsed / total
        let expected = Int(ceil(fraction * Double(target)))
        let behind = expected - hydrationGlasses
        return max(0, behind)
    }

    /// Returns the contextual meal label based on time-of-day and today's logs.
    private func nextMealLabel() -> String? {
        let hour = Calendar.current.component(.hour, from: Date())

        // Breakfast window: 05:00–10:59
        if (5..<11).contains(hour) {
            let hasBreakfast = todayFoodLogs.contains {
                let h = Calendar.current.component(.hour, from: $0.createdAt)
                return (5..<11).contains(h)
            }
            return hasBreakfast ? nil : "Breakfast"
        }

        // Lunch window: 11:00–13:59
        if (11..<14).contains(hour) {
            let hasLunch = todayFoodLogs.contains {
                let h = Calendar.current.component(.hour, from: $0.createdAt)
                return (11..<14).contains(h)
            }
            return hasLunch ? nil : "Lunch"
        }

        // Dinner window: 17:00–20:59
        if (17..<21).contains(hour) {
            let hasDinner = todayFoodLogs.contains {
                let h = Calendar.current.component(.hour, from: $0.createdAt)
                return (17..<21).contains(h)
            }
            return hasDinner ? nil : "Dinner"
        }

        return nil
    }

    /// Resolves today's stress level from the first available source:
    ///  1. Persisted `WellnessDayLog.stressLevel`.
    ///  2. The shared StressViewModel's live `totalScore`.
    ///  3. The most recent `StressReading` for today.
    private var effectiveStressLevel: String? {
        if let level = todayWellnessLog?.stressLevel, !level.isEmpty {
            return level
        }
        if let score = liveStressScore {
            return StressLevel(score: score).label
        }
        if let latest = todayStressReadings.last {
            return latest.levelLabel
        }
        return nil
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
        let stressProgress = stressProgressFromLevel(effectiveStressLevel)

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

    // MARK: - Greeting Helpers

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }

    private var userName: String {
        UserProfileManager.shared.userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Mood Logging

    private func refreshTodayMoodState() {
        guard let log = fetchTodayWellnessLog() else {
            hasLoggedMoodToday = false
            selectedMood = nil
            healthSuggestedMood = nil
            fetchHealthMoodSuggestion()
            return
        }

        if let mood = log.mood {
            hasLoggedMoodToday = true
            selectedMood = mood
            healthSuggestedMood = nil
        } else {
            hasLoggedMoodToday = false
            selectedMood = nil
            healthSuggestedMood = nil
            fetchHealthMoodSuggestion()
        }
    }

    private func fetchHealthMoodSuggestion() {
        guard HealthKitServiceFactory.isDataAvailable else { return }
        if AppConfig.shared.mockMode { return }
        Task {
            let service = HealthKitServiceFactory.shared
            do {
                try await service.requestAuthorization()
                if let mood = try await service.fetchTodayMood() {
                    healthSuggestedMood = mood
                }
            } catch {
                WPLogger.healthKit.error("Mood suggestion from Health failed: \(error.localizedDescription)")
            }
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
            if HealthKitServiceFactory.isDataAvailable && !AppConfig.shared.mockMode {
                Task { try? await HealthKitServiceFactory.shared.writeMood(mood) }
            }
            healthSuggestedMood = nil
            // Mood feeds the stress score. Trigger the shared VM to recompute so
            // the Stress ring reflects the new mood immediately.
            stressViewModel.recompute(reason: .manualMood)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                hasLoggedMoodToday = true
            }
        } catch {
            hasLoggedMoodToday = false
            selectedMood = nil
            WPLogger.home.error("Mood save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Hydration & Activity

    private func refreshTodayHydrationState() {
        hydrationGlasses = fetchTodayWellnessLog()?.waterGlasses ?? 0
    }

    /// Pulls today's active energy + steps from HealthKit and persists them into
    /// the today `WellnessDayLog` so the Move tile reads non-zero even before the
    /// user visits the Stress tab.
    private func refreshTodayActivityFromHealthKit() {
        guard HealthKitServiceFactory.isDataAvailable else { return }

        Task {
            let service = HealthKitServiceFactory.shared
            do {
                try await service.requestAuthorization()
                guard service.isAuthorized else { return }

                let cal = Calendar.current
                let startOfDay = cal.startOfDay(for: Date())
                let now = Date()
                guard now > startOfDay else { return }
                let range = DateInterval(start: startOfDay, end: now)

                async let energySamples = service.fetchActiveEnergy(for: range)
                async let stepSamples = service.fetchSteps(for: range)
                let (energy, steps) = try await (energySamples, stepSamples)

                let burnedKcal = Int((energy.first { cal.isDateInToday($0.date) }?.value ?? 0).rounded())
                let stepCount = Int((steps.first { cal.isDateInToday($0.date) }?.value ?? 0).rounded())

                let log = fetchOrCreateTodayWellnessLog()
                var didChange = false
                if burnedKcal > 0, log.caloriesBurned != burnedKcal {
                    log.caloriesBurned = burnedKcal
                    didChange = true
                }
                if stepCount > 0, log.steps != stepCount {
                    log.steps = stepCount
                    didChange = true
                }
                if didChange {
                    try? modelContext.save()
                }
            } catch {
                WPLogger.healthKit.error("Home activity refresh failed: \(error.localizedDescription)")
            }
        }
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

    /// Fires the celebration alert the first time today's hydration crosses the
    /// daily goal. Skips if state hasn't loaded, already celebrated, or goal <= 0.
    private func handleWaterGoalCrossing(from oldCups: Int, to newCups: Int) {
        guard hasHydrationStateLoaded else { return }
        let goal = currentGoals.waterDailyCups
        guard goal > 0, oldCups < goal, newCups >= goal else { return }
        let todayKey = Self.dayKey(for: Date())
        guard waterGoalCelebratedDay != todayKey else { return }
        waterGoalCelebratedDay = todayKey
        HapticService.notify(.success)
        showWaterGoalCelebration = true
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
        for: FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self,
        configurations: config
    )
    return HomeView(
        selectedTab: .constant(0),
        stressViewModel: StressViewModel(modelContext: container.mainContext)
    )
    .modelContainer(container)
}
