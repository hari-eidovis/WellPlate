import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class WellnessCalendarViewModel: ObservableObject {

    struct DailyActivitySnapshot {
        let day: Date
        let exerciseMinutes: Int
        let caloriesBurned: Int
        let steps: Int
    }

    // MARK: - Published State

    @Published var selectedDate: Date = Date()
    @Published var currentMonth: Date = Date()
    @Published var dayLog: WellnessDayLog?
    @Published var foodEntries: [FoodLogEntry] = []
    @Published private(set) var healthKitActivity: DailyActivitySnapshot?
    @Published private(set) var isLoadingActivity: Bool = false
    @Published private(set) var stressScore: Double?

    private var modelContext: ModelContext?
    private var activityTask: Task<Void, Never>?
    private let healthService: HealthKitServiceProtocol

    init(healthService: HealthKitServiceProtocol? = nil) {
        if let healthService {
            self.healthService = healthService
        } else if AppConfig.shared.mockDataInjected {
            self.healthService = MockHealthKitService(snapshot: .default)
        } else {
            self.healthService = HealthKitService()
        }
    }

    // MARK: - Init

    func bind(_ context: ModelContext) {
        if modelContext == nil {
            modelContext = context
        }
        loadData(for: selectedDate)
    }

    // MARK: - Data Loading

    func loadData(for date: Date) {
        selectedDate = date
        let startOfDay = Calendar.current.startOfDay(for: date)

        guard let ctx = modelContext else { return }

        // Fetch WellnessDayLog
        let logDescriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == startOfDay }
        )
        dayLog = try? ctx.fetch(logDescriptor).first

        // Fetch FoodLogEntries
        let foodDescriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day == startOfDay },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        foodEntries = (try? ctx.fetch(foodDescriptor)) ?? []

        // Fetch last StressReading for the day
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let stressDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= startOfDay && $0.timestamp < nextDay },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        stressScore = (try? ctx.fetch(stressDescriptor))?.first?.score

        activityTask?.cancel()
        healthKitActivity = nil
        isLoadingActivity = true
        activityTask = Task { [weak self] in
            await self?.loadHealthKitActivity(for: startOfDay)
        }
    }

    // MARK: - Computed

    var totalCalories: Int {
        foodEntries.reduce(0) { $0 + $1.calories }
    }

    var totalProtein: Double {
        foodEntries.reduce(0.0) { $0 + $1.protein }
    }

    var totalCarbs: Double {
        foodEntries.reduce(0.0) { $0 + $1.carbs }
    }

    var totalFat: Double {
        foodEntries.reduce(0.0) { $0 + $1.fat }
    }

    var hasHealthKitActivityData: Bool {
        guard let snapshot = healthKitActivity,
              Calendar.current.isDate(snapshot.day, inSameDayAs: selectedDate)
        else { return false }
        return snapshot.exerciseMinutes > 0 || snapshot.caloriesBurned > 0 || snapshot.steps > 0
    }

    func resolvedActivity(for log: WellnessDayLog?) -> (exerciseMinutes: Int, caloriesBurned: Int, steps: Int) {
        let logExercise = log?.exerciseMinutes ?? 0
        let logCalories = log?.caloriesBurned ?? 0
        let logSteps = log?.steps ?? 0

        guard let snapshot = healthKitActivity,
              Calendar.current.isDate(snapshot.day, inSameDayAs: selectedDate)
        else {
            return (logExercise, logCalories, logSteps)
        }

        return (
            snapshot.exerciseMinutes > 0 ? snapshot.exerciseMinutes : logExercise,
            snapshot.caloriesBurned > 0 ? snapshot.caloriesBurned : logCalories,
            snapshot.steps > 0 ? snapshot.steps : logSteps
        )
    }

    // MARK: - Calendar Helpers

    /// All days in the current displayed month.
    var daysInMonth: [Date] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: currentMonth),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))
        else { return [] }

        return range.compactMap { day in
            cal.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
    }

    /// The weekday index (0 = Sunday) for the first day of current month.
    var firstWeekdayOffset: Int {
        let cal = Calendar.current
        guard let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))
        else { return 0 }
        // weekday is 1-based (1 = Sunday)
        return cal.component(.weekday, from: firstOfMonth) - 1
    }

    var monthYearString: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: currentMonth)
    }

    func advanceMonth(by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    /// Returns true if we have a `WellnessDayLog` for the given date.
    func hasData(for date: Date) -> Bool {
        guard let ctx = modelContext else { return false }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let logDescriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == startOfDay }
        )
        if ((try? ctx.fetchCount(logDescriptor)) ?? 0) > 0 {
            return true
        }

        let foodDescriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day == startOfDay }
        )
        return ((try? ctx.fetchCount(foodDescriptor)) ?? 0) > 0
    }

    // MARK: - HealthKit Activity Fallback

    private func loadHealthKitActivity(for day: Date) async {
        if !AppConfig.shared.mockDataInjected {
            guard HealthKitService.isAvailable else { return }
        }
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
        let range = DateInterval(start: day, end: endOfDay)

        do {
            async let stepsTask = healthService.fetchSteps(for: range)
            async let caloriesTask = healthService.fetchActiveEnergy(for: range)
            async let exerciseTask = healthService.fetchExerciseMinutes(for: range)

            let (stepsSamples, caloriesSamples, exerciseSamples) = try await (stepsTask, caloriesTask, exerciseTask)
            guard !Task.isCancelled else { return }

            let snapshot = DailyActivitySnapshot(
                day: day,
                exerciseMinutes: Int(value(on: day, from: exerciseSamples).rounded()),
                caloriesBurned: Int(value(on: day, from: caloriesSamples).rounded()),
                steps: Int(value(on: day, from: stepsSamples).rounded())
            )

            guard Calendar.current.isDate(selectedDate, inSameDayAs: day) else { return }
            healthKitActivity = snapshot
            isLoadingActivity = false
        } catch {
            guard Calendar.current.isDate(selectedDate, inSameDayAs: day) else { return }
            healthKitActivity = nil
            isLoadingActivity = false
        }
    }

    private func value(on day: Date, from samples: [DailyMetricSample]) -> Double {
        samples.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) })?.value ?? 0
    }
}
