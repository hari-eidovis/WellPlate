import Foundation
import WidgetKit

enum WidgetRefreshHelper {

    @MainActor
    static func refreshStress(viewModel: StressViewModel) {
        // Map factors
        let factors = viewModel.allFactors.map { factor in
            WidgetStressFactor(
                title:       factor.title,
                icon:        factor.icon,
                score:       factor.score,
                maxScore:    factor.maxScore,
                contribution: factor.stressContribution,
                hasValidData: factor.hasValidData
            )
        }

        // Build weekly scores (last 7 days)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeklyScores: [WidgetDayScore] = (0..<7).reversed().map { daysAgo in
            let dayDate = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayStart = calendar.startOfDay(for: dayDate)
            let readings = viewModel.weekReadings.filter {
                calendar.isDate($0.timestamp, inSameDayAs: dayStart)
            }
            if readings.isEmpty {
                return WidgetDayScore(date: dayDate, score: nil)
            }
            let avg = readings.map(\.score).reduce(0, +) / Double(readings.count)
            return WidgetDayScore(date: dayDate, score: avg)
        }

        // Yesterday's score
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let yesterdayScore = weeklyScores.first(where: {
            calendar.isDate($0.date, inSameDayAs: yesterday)
        })?.score

        let widgetData = WidgetStressData(
            totalScore:      viewModel.totalScore,
            levelRaw:        viewModel.stressLevel.rawValue,
            encouragement:   viewModel.stressLevel.encouragementText,
            factors:         factors,
            restingHR:       viewModel.todayRestingHR,
            hrv:             viewModel.todayHRV,
            respiratoryRate: viewModel.todayRespiratoryRate,
            weeklyScores:    weeklyScores,
            yesterdayScore:   yesterdayScore,
            lastUpdated:     .now
        )
        widgetData.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "com.hariom.wellplate.stressWidget")
    }
}
