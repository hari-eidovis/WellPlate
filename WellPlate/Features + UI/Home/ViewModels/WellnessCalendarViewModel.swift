import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class WellnessCalendarViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedDate: Date = Date()
    @Published var currentMonth: Date = Date()
    @Published var dayLog: WellnessDayLog?
    @Published var foodEntries: [FoodLogEntry] = []

    private var modelContext: ModelContext?

    // MARK: - Init

    func bind(_ context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context
        seedSampleDataIfNeeded()
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
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == startOfDay }
        )
        return ((try? ctx.fetchCount(descriptor)) ?? 0) > 0
    }

    // MARK: - Sample Data (Demo)

    private func seedSampleDataIfNeeded() {
        guard let ctx = modelContext else { return }

        // Check if we already have data
        let count = (try? ctx.fetchCount(FetchDescriptor<WellnessDayLog>())) ?? 0
        guard count == 0 else { return }

        let cal = Calendar.current
        let moods: [Int] = [4, 3, 2, 3, 4, 1, 3, 4, 2, 3, 4, 3, 2, 4]
        let waters: [Int] = [6, 7, 5, 8, 4, 3, 7, 6, 8, 5, 7, 6, 4, 7]
        let exercises: [Int] = [30, 45, 0, 60, 20, 0, 35, 50, 15, 40, 25, 0, 55, 32]
        let cals: [Int] = [220, 340, 0, 450, 150, 0, 260, 380, 100, 300, 180, 0, 420, 280]
        let stepsList: [Int] = [6200, 8400, 3200, 10200, 5600, 2100, 7800, 9200, 4300, 7100, 5900, 2800, 8900, 6430]
        let stresses: [String?] = ["Low", "Medium", "High", "Low", "Medium", nil, "Low", "Low", "High", "Medium", "Low", nil, "Medium", "Low"]

        for i in 0..<14 {
            guard let date = cal.date(byAdding: .day, value: -(13 - i), to: Date()) else { continue }
            let log = WellnessDayLog(
                day: date,
                moodRaw: moods[i],
                waterGlasses: waters[i],
                exerciseMinutes: exercises[i],
                caloriesBurned: cals[i],
                steps: stepsList[i],
                stressLevel: stresses[i]
            )
            ctx.insert(log)
        }

        try? ctx.save()
    }
}
