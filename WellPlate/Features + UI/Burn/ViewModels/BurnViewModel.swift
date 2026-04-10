//
//  BurnViewModel.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import Foundation
import Combine

@MainActor
final class BurnViewModel: ObservableObject {

    // MARK: - Published State

    @Published var activeEnergySamples: [DailyMetricSample] = []
    @Published var stepsSamples: [DailyMetricSample] = []
    @Published var isAuthorized = false
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    // MARK: - Dependencies

    private let service: HealthKitServiceProtocol

    init(service: HealthKitServiceProtocol = HealthKitServiceFactory.shared) {
        self.service = service
    }

    // MARK: - Computed — Today

    var todayActiveEnergy: Double {
        activeEnergySamples.first { Calendar.current.isDateInToday($0.date) }?.value ?? 0
    }

    var todaySteps: Double {
        stepsSamples.first { Calendar.current.isDateInToday($0.date) }?.value ?? 0
    }

    // MARK: - Computed — Summaries

    var weekAvgEnergy: String {
        let week = last7Days(for: .activeEnergy)
        guard !week.isEmpty else { return "—" }
        let avg = week.map(\.value).reduce(0, +) / Double(week.count)
        return "\(Int(avg))"
    }

    var bestDayEnergy: String {
        let best = last7Days(for: .activeEnergy).map(\.value).max() ?? 0
        return best > 0 ? "\(Int(best))" : "—"
    }

    @Published var activeEnergyGoal: Double = 500
    @Published var dailyStepsGoal: Double = 10_000

    var activeEnergyProgress: Double {
        guard activeEnergyGoal > 0 else { return 0 }
        return min(todayActiveEnergy / activeEnergyGoal, 1.0)
    }

    // MARK: - Data Access

    func samplesFor(_ metric: BurnMetric) -> [DailyMetricSample] {
        switch metric {
        case .activeEnergy: return activeEnergySamples
        case .steps:        return stepsSamples
        }
    }

    func last7Days(for metric: BurnMetric) -> [DailyMetricSample] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return samplesFor(metric).filter { $0.date >= cutoff }
    }

    func last30Days(for metric: BurnMetric) -> [DailyMetricSample] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return samplesFor(metric).filter { $0.date >= cutoff }
    }

    func todayValue(for metric: BurnMetric) -> Double {
        switch metric {
        case .activeEnergy: return todayActiveEnergy
        case .steps:        return todaySteps
        }
    }

    func stats(for metric: BurnMetric) -> (min: Double, max: Double, avg: Double) {
        let values = last30Days(for: metric).map(\.value)
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
            async let energy = service.fetchActiveEnergy(for: range)
            async let steps  = service.fetchSteps(for: range)
            let (e, s) = try await (energy, steps)
            activeEnergySamples = e
            stepsSamples        = s
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
