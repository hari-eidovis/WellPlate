import SwiftUI
import SwiftData

// MARK: - Models

struct StreakPeriod: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date

    var length: Int {
        let components = Calendar.current.dateComponents([.day], from: startDate, to: endDate)
        return (components.day ?? 0) + 1
    }

    var dateRangeString: String {
        let cal = Calendar.current
        let startYear = cal.component(.year, from: startDate)
        let endYear = cal.component(.year, from: endDate)
        let startFmt = DateFormatter()
        let endFmt = DateFormatter()
        if startYear == endYear {
            startFmt.dateFormat = "MMM d"
            endFmt.dateFormat = "MMM d, yyyy"
        } else {
            startFmt.dateFormat = "MMM d, yyyy"
            endFmt.dateFormat = "MMM d, yyyy"
        }
        return "\(startFmt.string(from: startDate)) – \(endFmt.string(from: endDate))"
    }
}

struct StreakData {
    let currentStreak: Int
    let longestStreak: Int
    let totalDays: Int
    let allPeriods: [StreakPeriod]
    let loggedDays: Set<Date>
    let isActiveToday: Bool
}

// MARK: - Calculator

private enum StreakCalculator {
    static func compute(loggedDays: Set<Date>) -> StreakData {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let sorted = loggedDays.sorted()

        guard !sorted.isEmpty else {
            return StreakData(
                currentStreak: 0,
                longestStreak: 0,
                totalDays: 0,
                allPeriods: [],
                loggedDays: loggedDays,
                isActiveToday: false
            )
        }

        var periods: [StreakPeriod] = []
        var periodStart = sorted[0]
        var periodEnd = sorted[0]

        for i in 1..<sorted.count {
            let day = sorted[i]
            let prev = sorted[i - 1]
            let diff = cal.dateComponents([.day], from: prev, to: day).day ?? 0
            if diff == 1 {
                periodEnd = day
            } else {
                periods.append(StreakPeriod(startDate: periodStart, endDate: periodEnd))
                periodStart = day
                periodEnd = day
            }
        }
        periods.append(StreakPeriod(startDate: periodStart, endDate: periodEnd))

        let longestStreak = periods.map { $0.length }.max() ?? 0

        var currentStreak = 0
        var isActiveToday = false
        if let last = periods.last {
            if last.endDate == today {
                currentStreak = last.length
                isActiveToday = true
            } else if last.endDate == yesterday {
                currentStreak = last.length
            }
        }

        return StreakData(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalDays: loggedDays.count,
            allPeriods: periods,
            loggedDays: loggedDays,
            isActiveToday: isActiveToday
        )
    }
}

// MARK: - StreakDetailView

struct StreakDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \FoodLogEntry.day, order: .reverse)
    private var allEntries: [FoodLogEntry]

    @State private var displayedMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()

    private var loggedDays: Set<Date> {
        Set(allEntries.map { Calendar.current.startOfDay(for: $0.day) })
    }

    private var streakData: StreakData {
        StreakCalculator.compute(loggedDays: loggedDays)
    }

    private var pastStreaks: [StreakPeriod] {
        let data = streakData
        guard data.currentStreak > 0 else {
            return data.allPeriods.sorted { $0.endDate > $1.endDate }
        }
        // allPeriods is ascending; last element is the active streak — exclude it
        return data.allPeriods.dropLast().sorted { $0.endDate > $1.endDate }
    }

    private var isCurrentMonth: Bool {
        let cal = Calendar.current
        let now = cal.dateComponents([.year, .month], from: Date())
        let displayed = cal.dateComponents([.year, .month], from: displayedMonth)
        return now.year == displayed.year && now.month == displayed.month
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    statsRow
                    calendarSection
                    pastStreaksSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Streaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.r(20, .regular))
                    }
                }
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            Text("\(streakData.currentStreak)")
                .font(.r(64, .bold))
                .foregroundColor(.primary)
                .monospacedDigit()

            Text("day streak")
                .font(.r(.headline, .regular))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                Circle()
                    .fill(streakData.isActiveToday ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(streakData.isActiveToday ? "Today logged" : "Log today to keep it going")
                    .font(.r(.caption, .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statPill(icon: "trophy.fill", iconColor: .yellow, label: "Best", value: "\(streakData.longestStreak) days")
            statPill(icon: "calendar", iconColor: .blue, label: "Total", value: "\(streakData.totalDays) days")
        }
    }

    private func statPill(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.r(.subheadline, .semibold))
                .foregroundColor(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.r(.caption, .regular))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Calendar")
                    .font(.r(.headline, .semibold))
                Spacer()
                HStack(spacing: 12) {
                    Button { navigateMonth(by: -1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.r(.subheadline, .medium))
                            .foregroundColor(.primary)
                    }
                    Text(monthYearString(displayedMonth))
                        .font(.r(.subheadline, .medium))
                        .frame(minWidth: 100)
                        .multilineTextAlignment(.center)
                    Button { navigateMonth(by: 1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.r(.subheadline, .medium))
                            .foregroundColor(isCurrentMonth ? Color.gray.opacity(0.3) : .primary)
                    }
                    .disabled(isCurrentMonth)
                }
            }

            let weekDayLabels = ["M", "T", "W", "T", "F", "S", "S"]
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekDayLabels[i])
                        .font(.r(.caption, .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let days = daysInMonth(for: displayedMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(0..<days.count, id: \.self) { i in
                    if let date = days[i] {
                        dayCellView(
                            date: date,
                            isLogged: loggedDays.contains(Calendar.current.startOfDay(for: date)),
                            isToday: Calendar.current.isDateInToday(date)
                        )
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func dayCellView(date: Date, isLogged: Bool, isToday: Bool) -> some View {
        let day = Calendar.current.component(.day, from: date)
        return ZStack {
            if isToday {
                Circle()
                    .stroke(Color.orange, lineWidth: 2)
                    .frame(width: 34, height: 34)
            }
            if isLogged {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 30, height: 30)
            } else if !isToday {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 30, height: 30)
            }
            Text("\(day)")
                .font(.r(.caption, .regular))
                .foregroundColor(isLogged ? .white : .primary)
        }
        .frame(height: 36)
    }

    // MARK: - Past Streaks

    private var pastStreaksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Streaks")
                .font(.r(.headline, .semibold))

            if pastStreaks.isEmpty {
                Text("No past streaks yet")
                    .font(.r(.subheadline, .regular))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                            .appShadow(radius: 15, y: 5)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pastStreaks.enumerated()), id: \.element.id) { idx, period in
                        HStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                                .font(.r(.subheadline, .regular))
                                .foregroundColor(.orange)
                            Text("\(period.length) day\(period.length == 1 ? "" : "s")")
                                .font(.r(.subheadline, .semibold))
                            Spacer()
                            Text(period.dateRangeString)
                                .font(.r(.caption, .regular))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        if idx < pastStreaks.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground))
                        .appShadow(radius: 15, y: 5)
                )
            }
        }
    }

    // MARK: - Helpers

    private func navigateMonth(by value: Int) {
        let cal = Calendar.current
        guard let newMonth = cal.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        if value > 0 {
            let currentMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            guard newMonth <= currentMonthStart else { return }
        }
        HapticService.selectionChanged()
        displayedMonth = newMonth
    }

    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func daysInMonth(for date: Date) -> [Date?] {
        let cal = Calendar.current
        guard
            let range = cal.range(of: .day, in: .month, for: date),
            let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: date))
        else { return [] }

        let weekday = cal.component(.weekday, from: firstDay)
        // Convert Gregorian weekday (Sun=1…Sat=7) to Monday-first offset (Mon=0…Sun=6)
        let offset = (weekday - 2 + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: offset)
        for dayNum in range {
            if let d = cal.date(byAdding: .day, value: dayNum - 1, to: firstDay) {
                days.append(d)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }
}
