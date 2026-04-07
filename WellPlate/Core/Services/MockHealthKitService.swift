//
//  MockHealthKitService.swift
//  WellPlate
//
//  HealthKitServiceProtocol implementation that returns deterministic data
//  from a StressMockSnapshot without requiring a real device or HealthKit
//  authorization. Used by StressViewModel when AppConfig.shared.mockMode is on.
//

import Foundation

final class MockHealthKitService: HealthKitServiceProtocol {

    private let snapshot: StressMockSnapshot

    private(set) var isAuthorized: Bool = true

    init(snapshot: StressMockSnapshot = .default) {
        self.snapshot = snapshot
    }

    func requestAuthorization() async throws {
        // No-op — mock is always authorized.
    }

    func fetchSteps(for range: DateInterval) async throws -> [DailyMetricSample] {
        snapshot.stepsHistory.filter { range.contains($0.date) }
    }

    func fetchHeartRate(for range: DateInterval) async throws -> [DailyMetricSample] {
        snapshot.heartRateHistory.filter { range.contains($0.date) }
    }

    func fetchActiveEnergy(for range: DateInterval) async throws -> [DailyMetricSample] {
        snapshot.energyHistory.filter { range.contains($0.date) }
    }

    func fetchExerciseMinutes(for range: DateInterval) async throws -> [DailyMetricSample] {
        []
    }

    func fetchSleep(for range: DateInterval) async throws -> [SleepSample] {
        []
    }

    func fetchDailySleepSummaries(for range: DateInterval) async throws -> [DailySleepSummary] {
        snapshot.sleepHistory.filter { range.contains($0.date) }
    }

    func fetchWater(for range: DateInterval) async throws -> [DailyMetricSample] {
        []
    }

    func fetchRestingHeartRate(for range: DateInterval) async throws -> [DailyMetricSample] {
        snapshot.restingHRHistory.filter { range.contains($0.date) }
    }

    func fetchHRV(for range: DateInterval) async throws -> [DailyMetricSample] {
        snapshot.hrvHistory.filter { range.contains($0.date) }
    }

    func fetchBloodPressureSystolic(for range: DateInterval) async throws -> [DailyMetricSample] {
        snapshot.systolicBPHistory.filter { range.contains($0.date) }
    }

    func fetchBloodPressureDiastolic(for range: DateInterval) async throws -> [DailyMetricSample] {
        snapshot.diastolicBPHistory.filter { range.contains($0.date) }
    }

    func fetchRespiratoryRate(for range: DateInterval) async throws -> [DailyMetricSample] {
        snapshot.respiratoryRateHistory.filter { range.contains($0.date) }
    }

    func writeMood(_ mood: MoodOption) async throws {
        // No-op in mock mode.
    }

    func fetchTodayMood() async throws -> MoodOption? {
        nil
    }
}
