//
//  HealthKitService.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import HealthKit

// MARK: - Error Type

enum HealthKitError: LocalizedError {
    case notAvailable
    case typeNotAvailable

    var errorDescription: String? {
        switch self {
        case .notAvailable:     return "HealthKit is not available on this device."
        case .typeNotAvailable: return "This health data type is not supported."
        }
    }
}

// MARK: - Concrete Service

final class HealthKitService: HealthKitServiceProtocol {

    /// Call this before constructing the service to guard against Simulator.
    static let isAvailable: Bool = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()
    private(set) var isAuthorized = false

    // MARK: - Types

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned, .appleExerciseTime, .heartRate, .dietaryWater,
            .restingHeartRate, .heartRateVariabilitySDNN,
            .bloodPressureSystolic, .bloodPressureDiastolic, .respiratoryRate,
            .timeInDaylight
        ]
        quantityIDs.compactMap { HKQuantityType.quantityType(forIdentifier: $0) }
                   .forEach { types.insert($0) }

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKSampleType.stateOfMindType())
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        types.insert(HKSampleType.stateOfMindType())
        return types
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    self?.isAuthorized = success
                    cont.resume()
                }
            }
        }
    }

    // MARK: - Public Fetch Methods

    func fetchSteps(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailySum(type: type, unit: .count(), range: range)
    }

    func fetchHeartRate(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailyAvg(type: type, unit: HKUnit(from: "count/min"), range: range)
    }

    func fetchActiveEnergy(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailySum(type: type, unit: .kilocalorie(), range: range)
    }

    func fetchExerciseMinutes(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailySum(type: type, unit: .minute(), range: range)
    }

    func fetchWater(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailySum(type: type, unit: .liter(), range: range)
    }

    func fetchSleep(for range: DateInterval) async throws -> [SleepSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await withCheckedThrowingContinuation { cont in
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start, end: range.end, options: .strictStartDate
            )
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }

                let stageMap: [Int: SleepStage] = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue:        .core,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue:         .rem,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue:        .deep,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: .unspecified
                ]
                let result = (samples as? [HKCategorySample] ?? [])
                    .compactMap { s -> SleepSample? in
                        guard let stage = stageMap[s.value] else { return nil }
                        let hours = s.endDate.timeIntervalSince(s.startDate) / 3600
                        return SleepSample(date: s.startDate, value: hours, stage: stage)
                    }
                cont.resume(returning: result)
            }
            store.execute(query)
        }
    }

    func fetchDailySleepSummaries(for range: DateInterval) async throws -> [DailySleepSummary] {
        let samples = try await fetchSleep(for: range)
        let cal = Calendar.current

        // Group by wake-up calendar date (endDate ≈ startDate + value hours).
        // This ensures an overnight session (11 PM–7 AM) belongs to the morning date.
        var grouped: [Date: [SleepSample]] = [:]
        for s in samples {
            let wakeUp = s.date.addingTimeInterval(s.value * 3600)
            let day = cal.startOfDay(for: wakeUp)
            grouped[day, default: []].append(s)
        }

        return grouped.map { day, daySamples in
            let core = daySamples.filter { $0.stage == .core }.map(\.value).reduce(0, +)
            let rem  = daySamples.filter { $0.stage == .rem  }.map(\.value).reduce(0, +)
            let deep = daySamples.filter { $0.stage == .deep }.map(\.value).reduce(0, +)
            let unspec = daySamples.filter { $0.stage == .unspecified }.map(\.value).reduce(0, +)
            let total = core + rem + deep + unspec

            // Bedtime = earliest sample start; WakeTime = latest sample end
            let bedtime = daySamples.map(\.date).min()
            let wakeTime = daySamples.map { $0.date.addingTimeInterval($0.value * 3600) }.max()

            return DailySleepSummary(
                date: day,
                totalHours: total,
                coreHours: core,
                remHours: rem,
                deepHours: deep,
                bedtime: total >= 3.0 ? bedtime : nil,
                wakeTime: total >= 3.0 ? wakeTime : nil
            )
        }
        .sorted { $0.date < $1.date }
    }

    func fetchRestingHeartRate(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailyAvg(type: type, unit: HKUnit(from: "count/min"), range: range)
    }

    func fetchHRV(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailyAvg(type: type, unit: HKUnit(from: "ms"), range: range)
    }

    func fetchBloodPressureSystolic(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailyAvg(type: type, unit: .millimeterOfMercury(), range: range)
    }

    func fetchBloodPressureDiastolic(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailyAvg(type: type, unit: .millimeterOfMercury(), range: range)
    }

    func fetchRespiratoryRate(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailyAvg(type: type, unit: HKUnit(from: "count/min"), range: range)
    }

    // MARK: - Daylight

    func fetchDaylight(for range: DateInterval) async throws -> [DailyMetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else {
            throw HealthKitError.typeNotAvailable
        }
        return try await fetchDailySum(type: type, unit: .minute(), range: range)
    }

    // MARK: - State of Mind (Mood Sync)

    func writeMood(_ mood: MoodOption) async throws {
        let valence: Double = switch mood {
        case .awful: -1.0
        case .bad:   -0.5
        case .okay:   0.0
        case .good:   0.5
        case .great:  1.0
        }

        let sample = HKStateOfMind(
            date: .now,
            kind: .dailyMood,
            valence: valence,
            labels: [],
            associations: []
        )
        try await store.save(sample)
    }

    func fetchTodayMood() async throws -> MoodOption? {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Date.now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.stateOfMind(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )

        let results = try await descriptor.result(for: store)
        guard let latest = results.first else { return nil }

        // Reverse-map valence → MoodOption: snap to nearest of 5 levels
        let index = Int(round((latest.valence + 1.0) * 2.0))
        let clamped = min(max(index, 0), 4)
        return MoodOption(rawValue: clamped)
    }

    // MARK: - Private Helpers

    private func fetchDailySum(
        type: HKQuantityType,
        unit: HKUnit,
        range: DateInterval
    ) async throws -> [DailyMetricSample] {
        return try await fetchCollection(type: type, unit: unit, options: .cumulativeSum, range: range) { stat in
            stat.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
    }

    private func fetchDailyAvg(
        type: HKQuantityType,
        unit: HKUnit,
        range: DateInterval
    ) async throws -> [DailyMetricSample] {
        return try await fetchCollection(type: type, unit: unit, options: .discreteAverage, range: range) { stat in
            stat.averageQuantity()?.doubleValue(for: unit) ?? 0
        }
    }

    private func fetchCollection(
        type: HKQuantityType,
        unit: HKUnit,
        options: HKStatisticsOptions,
        range: DateInterval,
        valueExtractor: @escaping (HKStatistics) -> Double
    ) async throws -> [DailyMetricSample] {
        return try await withCheckedThrowingContinuation { cont in
            var interval = DateComponents()
            interval.day = 1

            let predicate = HKQuery.predicateForSamples(
                withStart: range.start, end: range.end, options: .strictStartDate
            )
            let anchor = Calendar.current.startOfDay(for: range.start)

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error = error { cont.resume(throwing: error); return }
                var samples: [DailyMetricSample] = []
                results?.enumerateStatistics(from: range.start, to: range.end) { stat, _ in
                    samples.append(DailyMetricSample(date: stat.startDate, value: valueExtractor(stat)))
                }
                cont.resume(returning: samples)
            }
            store.execute(query)
        }
    }
}
