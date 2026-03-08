import SwiftUI
import SwiftData

// MARK: - HomeView
// Redesigned dashboard: header, wellness rings, quick log, mood check-in,
// hydration, activity, and stress insight sections.

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var selectedMood: MoodOption?
    @State private var hydrationGlasses: Int = 5
    @State private var showLogMeal = false
    @State private var showWellnessCalendar = false
    @State private var showProgressInsights = false
    @StateObject private var foodJournalViewModel = HomeViewModel()

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
                        onLogMeal: {
                            showLogMeal = true
                        },
                        onLogWater: {
                            HapticService.impact(.light)
                            if hydrationGlasses < 8 { hydrationGlasses += 1 }
                        },
                        onExercise: { /* TODO: navigate to exercise log */ },
                        onMood:     { /* scroll handled by section below */ }
                    )
                    .padding(.horizontal, 16)

                    // 4. Mood Check-In
                    MoodCheckInCard(selectedMood: $selectedMood)
                        .padding(.horizontal, 16)

                    // 5. Hydration
                    HydrationCard(
                        glassesConsumed: $hydrationGlasses,
                        totalGlasses: 8
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
        [
            WellnessRingItem(
                label: "Calories",
                sublabel: "/ 2000",
                value: "1420",
                progress: 0.71,
                color: .orange,
                emojiOrSymbol: nil
            ),
            WellnessRingItem(
                label: "Water",
                sublabel: "/ 8 cups",
                value: "\(hydrationGlasses)",
                progress: CGFloat(hydrationGlasses) / 8.0,
                color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82),
                emojiOrSymbol: nil
            ),
            WellnessRingItem(
                label: "Exercise",
                sublabel: "/ 45 min",
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
}

// MARK: - Preview

#Preview("Home Dashboard") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodLogEntry.self, configurations: config)
    return HomeView()
        .modelContainer(container)
}
