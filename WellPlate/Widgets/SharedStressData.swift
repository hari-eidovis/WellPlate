import Foundation

// Shared data container written by the main app, read by the widget extension.
// Uses AppGroup UserDefaults — pure Foundation, no SwiftData dependency.

struct WidgetStressData: Codable {
    var totalScore: Double          // 0–100
    var levelRaw: String            // StressLevel raw value ("Excellent", "Good", etc.)
    var encouragement: String
    var factors: [WidgetStressFactor]  // always 4
    var restingHR: Double?
    var hrv: Double?
    var respiratoryRate: Double?
    var weeklyScores: [WidgetDayScore] // last 7 days
    var yesterdayScore: Double?
    var lastUpdated: Date

    var hasAnyValidData: Bool {
        factors.contains { $0.hasValidData }
    }

    static let appGroupID  = "group.com.hariom.wellplate"
    static let defaultsKey = "widgetStressData"

    // MARK: - Persistence

    static func load() -> WidgetStressData {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let raw      = defaults.data(forKey: defaultsKey),
            let decoded  = try? JSONDecoder().decode(WidgetStressData.self, from: raw),
            Calendar.current.isDateInToday(decoded.lastUpdated)
        else { return .empty }
        return decoded
    }

    func save() {
        guard
            let defaults = UserDefaults(suiteName: Self.appGroupID),
            let encoded  = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(encoded, forKey: Self.defaultsKey)
    }

    // MARK: - Presets

    static var empty: WidgetStressData {
        WidgetStressData(
            totalScore:     0,
            levelRaw:       "Excellent",
            encouragement:  "Open WellPlate to get started",
            factors:        [],
            restingHR:      nil,
            hrv:            nil,
            respiratoryRate: nil,
            weeklyScores:   [],
            yesterdayScore:  nil,
            lastUpdated:    .now
        )
    }

    static var placeholder: WidgetStressData {
        WidgetStressData(
            totalScore:     32,
            levelRaw:       "Good",
            encouragement:  "Keep up the good work!",
            factors: [
                WidgetStressFactor(title: "Exercise",    icon: "figure.run", score: 20, maxScore: 25, contribution: 5,  hasValidData: true),
                WidgetStressFactor(title: "Sleep",       icon: "moon.fill",  score: 17, maxScore: 25, contribution: 8,  hasValidData: true),
                WidgetStressFactor(title: "Diet",        icon: "leaf.fill",  score: 13, maxScore: 25, contribution: 12, hasValidData: true),
                WidgetStressFactor(title: "Screen Time", icon: "iphone",     score: 7,  maxScore: 25, contribution: 7,  hasValidData: true)
            ],
            restingHR:      62,
            hrv:            42,
            respiratoryRate: 16,
            weeklyScores: {
                let cal = Calendar.current
                let today = cal.startOfDay(for: Date())
                return (0..<7).reversed().map { daysAgo in
                    let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
                    let scores: [Double] = [28, 35, 42, 30, 48, 38, 32]
                    return WidgetDayScore(date: date, score: scores[6 - daysAgo])
                }
            }(),
            yesterdayScore:  38,
            lastUpdated:    .now
        )
    }
}

struct WidgetStressFactor: Codable {
    let title: String
    let icon: String
    let score: Double           // 0–25 (factor score, not stress contribution)
    let maxScore: Double        // 25
    let contribution: Double    // stress contribution 0–25 (= stressContribution from StressFactorResult)
    let hasValidData: Bool
}

struct WidgetDayScore: Codable {
    let date: Date
    let score: Double?          // nil = no data for this day
}
