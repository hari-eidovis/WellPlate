import Foundation

/// Shared analytics utilities used by StressLabAnalyzer, FastingInsightChart,
/// and future correlation features.
enum StressAnalyticsHelper {

    /// Groups StressReading rows by calendar day and returns an array of daily
    /// average scores. Order is arbitrary (callers should not assume sorted).
    static func dailyAverages(from readings: [StressReading]) -> [Double] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: readings) { cal.startOfDay(for: $0.timestamp) }
        return grouped.values.map { day in
            day.map(\.score).reduce(0, +) / Double(day.count)
        }
    }

    /// Groups StressReading rows by calendar day and returns a dictionary mapping
    /// each day (start-of-day Date) to its average stress score.
    static func dailyAveragesByDate(from readings: [StressReading]) -> [Date: Double] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: readings) { cal.startOfDay(for: $0.timestamp) }
        return grouped.mapValues { day in
            day.map(\.score).reduce(0, +) / Double(day.count)
        }
    }
}
