//
//  HealthKitServiceProtocol.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import Foundation

/// Defines the HealthKit data-fetching contract.
/// Mirrors the pattern established by `NutritionServiceProtocol`.
protocol HealthKitServiceProtocol {
    /// Whether the user has granted Health permissions this session.
    var isAuthorized: Bool { get }

    /// Presents the system HealthKit permission sheet.
    func requestAuthorization() async throws

    /// Daily step count sums over the given interval.
    func fetchSteps(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Daily average heart rate (BPM) over the given interval.
    func fetchHeartRate(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Daily active energy burned (kcal) sums over the given interval.
    func fetchActiveEnergy(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Daily Apple Exercise Time (minutes) sums over the given interval.
    func fetchExerciseMinutes(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Sleep sessions (hours) over the given interval.
    func fetchSleep(for range: DateInterval) async throws -> [SleepSample]

    /// Aggregated per-night sleep summaries with stage breakdowns.
    func fetchDailySleepSummaries(for range: DateInterval) async throws -> [DailySleepSummary]

    /// Daily dietary water (litres) sums over the given interval.
    func fetchWater(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Daily resting heart rate (BPM) over the given interval.
    func fetchRestingHeartRate(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Daily HRV (SDNN, ms) over the given interval.
    func fetchHRV(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Daily systolic blood pressure (mmHg) over the given interval.
    func fetchBloodPressureSystolic(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Daily diastolic blood pressure (mmHg) over the given interval.
    func fetchBloodPressureDiastolic(for range: DateInterval) async throws -> [DailyMetricSample]

    /// Daily respiratory rate (breaths/min) over the given interval.
    func fetchRespiratoryRate(for range: DateInterval) async throws -> [DailyMetricSample]
}
