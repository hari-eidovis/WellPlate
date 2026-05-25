//
//  SleepViewModel.swift
//  WellPlate
//
//  Created by Hari's Mac on 21.02.2026.
//

import Foundation
import Combine

@MainActor
final class SleepViewModel: ObservableObject {

    // MARK: - Published State

    @Published var sleepSummaries: [DailySleepSummary] = []
    @Published var isAuthorized = false
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    // MARK: - Dependencies

    private let service: HealthKitServiceProtocol

    init(service: HealthKitServiceProtocol = HealthKitServiceFactory.shared) {
        self.service = service
    }

    // MARK: - Computed — Last Night

    var lastNightSleep: DailySleepSummary? {
        // Most recent summary ≈ "last night"
        sleepSummaries.last
    }

    var totalHoursLastNight: Double {
        lastNightSleep?.totalHours ?? 0
    }

    var deepHoursLastNight: Double {
        lastNightSleep?.deepHours ?? 0
    }

    // MARK: - Computed — Summaries

    @Published var sleepGoal: Double = 8.0

    var sleepGoalProgress: Double {
        guard sleepGoal > 0 else { return 0 }
        return min(totalHoursLastNight / sleepGoal, 1.0)
    }

    var weekAvgHours: String {
        let week = last7Days
        guard !week.isEmpty else { return "—" }
        let avg = week.map(\.totalHours).reduce(0, +) / Double(week.count)
        return String(format: "%.1f", avg)
    }

    var bestNightHours: String {
        let best = last7Days.map(\.totalHours).max() ?? 0
        return best > 0 ? String(format: "%.1f", best) : "—"
    }

    // MARK: - Data Access

    var last7Days: [DailySleepSummary] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sleepSummaries.filter { $0.date >= cutoff }
    }

    var last30Days: [DailySleepSummary] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return sleepSummaries.filter { $0.date >= cutoff }
    }

    func stats() -> (min: Double, max: Double, avg: Double) {
        let values = last30Days.map(\.totalHours)
        guard !values.isEmpty else { return (0, 0, 0) }
        return (
            values.min() ?? 0,
            values.max() ?? 0,
            values.reduce(0, +) / Double(values.count)
        )
    }

    // MARK: - Actions

    func requestPermissionAndLoad() async {
        guard HealthKitServiceFactory.isDataAvailable else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.requestAuthorization()
            isAuthorized = service.isAuthorized
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadData() async {
        let end   = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        let range = DateInterval(start: start, end: end)

        do {
            sleepSummaries = try await service.fetchDailySleepSummaries(for: range)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
