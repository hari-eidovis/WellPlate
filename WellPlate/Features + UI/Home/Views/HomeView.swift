import SwiftUI
import SwiftData

// MARK: - HomeView
// Redesigned dashboard: header, wellness rings, quick log, mood check-in,
// hydration, activity, and stress insight sections.

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var userGoalsList: [UserGoals]

    // MARK: - State

    @State private var selectedMood: MoodOption?
    @State private var hasLoggedMoodToday = false
    @State private var hydrationGlasses: Int = 0
    @State private var showLogMeal = false
    @State private var showWellnessCalendar = false
    @State private var showProgressInsights = false
    @StateObject private var foodJournalViewModel = HomeViewModel()

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {

                    // 1. Header
                    homeHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // 2. Wellness Rings Card
                    WellnessRingsCard(
                        rings: wellnessRings,
                        completionPercent: 71,
                        onTap: { showWellnessCalendar = true }
                    )
                    .padding(.horizontal, 16)

                    // 3. Quick Log
                    QuickLogSection(
                        showsMoodLog: !hasLoggedMoodToday,
                        onLogMeal: {
                            showLogMeal = true
                        },
                        onLogWater: {
                            if hydrationGlasses < currentGoals.waterDailyCups { hydrationGlasses += 1 }
                        },
                        onExercise: { /* TODO: navigate to exercise log */ },
                        onMood:     { /* scroll handled by section below */ }
                    )
                    .padding(.horizontal, 16)

                    // 4. Mood Check-In
                    if !hasLoggedMoodToday {
                        MoodCheckInCard(selectedMood: $selectedMood)
                            .padding(.horizontal, 16)
                    }

                    // 5. Hydration
                    HydrationCard(
                        glassesConsumed: $hydrationGlasses,
                        totalGlasses: currentGoals.waterDailyCups,
                        cupSizeML: currentGoals.waterCupSizeML
                    )
                    .padding(.horizontal, 16)

                    // 6. Activity
                    ActivityCard.sample()
                        .padding(.horizontal, 16)

                    // 7. Stress Insight
                    StressInsightCard(
                        stressLevel: "Low",
                        tip: "Try a 5-min breathing exercise to stay centered 🧘",
                        onStart: { /* TODO: navigate to stress / breathing */ }
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollIndicators(.hidden)
            // Navigation destination for Log Meal
            .navigationDestination(isPresented: $showLogMeal) {
                FoodJournalView(viewModel: foodJournalViewModel)
            }
            .navigationDestination(isPresented: $showWellnessCalendar) {
                WellnessCalendarView()
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Inject the model context into the VM once the environment is available.
            foodJournalViewModel.bindContext(modelContext)
            refreshTodayMoodState()
            refreshTodayHydrationState()
        }
        .onChange(of: selectedMood) { _, mood in
            guard let mood else { return }
            logMoodForTodayIfNeeded(mood)
        }
        .onChange(of: hydrationGlasses) { _, cups in
            updateHydrationForToday(cups)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshTodayMoodState()
            refreshTodayHydrationState()
        }
    }

    // MARK: - Header

    private var homeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayString)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(greeting)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(motivationalSubtitle)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Avatar circle
            Button {
                HapticService.impact(.light)
                showProgressInsights = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: 0.40, saturation: 0.50, brightness: 0.84),
                                    Color(hue: 0.40, saturation: 0.40, brightness: 0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Text("A")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showProgressInsights) {
                ProgressInsightsView()
            }
        }
    }

    // MARK: - Wellness Rings Data

    private var wellnessRings: [WellnessRingItem] {
        let cupGoal = currentGoals.waterDailyCups
        let workoutGoal = currentGoals.todayWorkoutGoal

        return [
            WellnessRingItem(
                label: "Calories",
                sublabel: "/ \(currentGoals.calorieGoal)",
                value: "1420",
                progress: 0.71,
                color: .orange,
                emojiOrSymbol: nil
            ),
            WellnessRingItem(
                label: "Water",
                sublabel: "/ \(cupGoal) cups",
                value: "\(hydrationGlasses)",
                progress: cupGoal > 0 ? CGFloat(hydrationGlasses) / CGFloat(cupGoal) : 0,
                color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82),
                emojiOrSymbol: nil
            ),
            WellnessRingItem(
                label: "Exercise",
                sublabel: workoutGoal > 0 ? "/ \(workoutGoal) min" : "Rest day",
                value: "32",
                progress: 0.71,
                color: Color(hue: 0.40, saturation: 0.62, brightness: 0.70),
                emojiOrSymbol: nil
            ),
            WellnessRingItem(
                label: "Stress",
                sublabel: "Low",
                value: "",
                progress: 0.25,
                color: Color(hue: 0.76, saturation: 0.50, brightness: 0.75),
                emojiOrSymbol: "😌"
            )
        ]
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

    private var motivationalSubtitle: String {
        "Every mindful choice counts ✨"
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
            hasLoggedMoodToday = true
        } catch {
            hasLoggedMoodToday = false
            selectedMood = nil
            print("HomeView mood save failed: \(error.localizedDescription)")
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
            print("HomeView hydration save failed: \(error.localizedDescription)")
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
    return HomeView()
        .modelContainer(container)
}
