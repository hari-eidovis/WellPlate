//
//  StressViewModel.swift
//  WellPlate
//
//  Created on 21.02.2026.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - Screen Time Source

enum ScreenTimeSource {
    case auto        // from DeviceActivity threshold
    case none        // no data for today
}

@MainActor
final class StressViewModel: ObservableObject {

    // MARK: - Published State

    @Published var exerciseFactor: StressFactorResult  = .neutral(title: "Exercise",    icon: "figure.run", higherIsBetter: true)
    @Published var sleepFactor: StressFactorResult      = .neutral(title: "Sleep",       icon: "moon.fill",  higherIsBetter: true)
    @Published var dietFactor: StressFactorResult       = .neutral(title: "Diet",        icon: "leaf.fill",  higherIsBetter: true)
    @Published var screenTimeFactor: StressFactorResult = .neutral(title: "Screen Time", icon: "iphone",     higherIsBetter: false)
    @Published var isLoading = false
    @Published var isAuthorized = false
    @Published var errorMessage: String? = nil
    @Published var screenTimeSource: ScreenTimeSource = .none

    // MARK: - Today's Vitals (display-only)

    @Published var todayHeartRate: Double? = nil
    @Published var todayRestingHR: Double? = nil
    @Published var todayHRV: Double? = nil
    @Published var todaySystolicBP: Double? = nil
    @Published var todayDiastolicBP: Double? = nil
    @Published var todayRespiratoryRate: Double? = nil

    // MARK: - 30-Day History

    @Published var stepsHistory: [DailyMetricSample] = []
    @Published var energyHistory: [DailyMetricSample] = []
    @Published var sleepHistory: [DailySleepSummary] = []
    @Published var heartRateHistory: [DailyMetricSample] = []
    @Published var restingHRHistory: [DailyMetricSample] = []
    @Published var hrvHistory: [DailyMetricSample] = []
    @Published var systolicBPHistory: [DailyMetricSample] = []
    @Published var diastolicBPHistory: [DailyMetricSample] = []
    @Published var respiratoryRateHistory: [DailyMetricSample] = []

    // MARK: - Intraday Stress Readings (for charts)

    /// All `StressReading` rows captured today — drives the day chart.
    @Published var todayReadings: [StressReading] = []

    /// `StressReading` rows from the last 7 days — drives the week trend chart.
    @Published var weekReadings: [StressReading] = []

    // MARK: - Diet Log Cache

    @Published var currentDayLogs: [FoodLogEntry] = []

    // MARK: - Computed

    /// Stress total 0–100.
    /// Exercise / sleep / diet contribute (25 - score) each — more activity = less stress.
    /// Screen time contributes its score directly — more usage = more stress.
    var totalScore: Double {
        exerciseFactor.stressContribution
        + sleepFactor.stressContribution
        + dietFactor.stressContribution
        + screenTimeFactor.stressContribution
    }

    var stressLevel: StressLevel { StressLevel(score: totalScore) }

    var allFactors: [StressFactorResult] {
        [exerciseFactor, sleepFactor, dietFactor, screenTimeFactor]
    }

    /// Top 2 factors contributing most to stress, ranked by stress contribution.
    var topStressors: [StressFactorResult] {
        allFactors.sorted { $0.stressContribution > $1.stressContribution }.prefix(2).map { $0 }
    }

    /// Returns the 30-day history array for a given vital metric.
    func vitalHistory(for metric: VitalMetric) -> [DailyMetricSample] {
        switch metric {
        case .heartRate:        return heartRateHistory
        case .restingHeartRate: return restingHRHistory
        case .hrv:              return hrvHistory
        case .systolicBP:       return systolicBPHistory
        case .diastolicBP:      return diastolicBPHistory
        case .respiratoryRate:  return respiratoryRateHistory
        }
    }

    /// Min / max / avg total sleep hours over the 30-day history.
    var sleepStats: (min: Double, max: Double, avg: Double) {
        let values = sleepHistory.map(\.totalHours)
        guard !values.isEmpty else { return (0, 0, 0) }
        return (
            values.min()!,
            values.max()!,
            values.reduce(0, +) / Double(values.count)
        )
    }

    // MARK: - Screen Time Display (view-model-owned, avoids direct singleton reads in views)

    /// The hours value currently used by the screen-time factor — nil when source is .none.
    @Published var screenTimeDisplayHours: Double? = nil

    /// Auto-detected hours only; nil when source is .none.
    var screenTimeAutoDetectedHours: Double? {
        screenTimeSource == .auto ? screenTimeDisplayHours : nil
    }

    // MARK: - Dependencies

    private let healthService: HealthKitServiceProtocol
    private let modelContext: ModelContext

    /// Non-nil when running in mock mode — drives all mock data paths.
    private let mockSnapshot: StressMockSnapshot?

    /// True when this view model is running with mock data injected.
    var usesMockData: Bool { mockSnapshot != nil }

    // MARK: - Init

    init(
        healthService: HealthKitServiceProtocol = HealthKitService(),
        modelContext: ModelContext,
        mockSnapshot: StressMockSnapshot? = nil
    ) {
        self.healthService = healthService
        self.modelContext = modelContext
        self.mockSnapshot = mockSnapshot

        if mockSnapshot == nil, ScreenTimeManager.shared.currentAutoDetectedReading != nil {
            screenTimeSource = .auto
        }
    }

    // MARK: - Actions

    func requestPermissionAndLoad() async {
        if usesMockData {
            isLoading = true
            defer { isLoading = false }
            isAuthorized = true
            await loadData()
            return
        }
        guard HealthKitService.isAvailable else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await healthService.requestAuthorization()
            isAuthorized = healthService.isAuthorized
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadData() async {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        // Exercise window: if it's before 9 AM, yesterday's full day has more
        // meaningful data than the handful of minutes since midnight.
        let hour = calendar.component(.hour, from: now)
        let exerciseStart: Date
        let exerciseEnd: Date
        if hour < 3 {
            // Early morning — show yesterday's full-day activity
            exerciseStart = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            exerciseEnd   = startOfToday
        } else {
            exerciseStart = startOfToday
            exerciseEnd   = now
        }
        let exerciseInterval = DateInterval(start: exerciseStart, end: exerciseEnd)

        // Sleep: look back 1 day to capture last night
        let sleepStart = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let sleepInterval = DateInterval(start: sleepStart, end: now)

        #if DEBUG
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log("🔄 loadData() started  (hour=\(hour))")
        log("   Exercise window : \(fmt.string(from: exerciseStart)) → \(fmt.string(from: exerciseEnd))\(hour < 3 ? " [yesterday fallback]" : "")")
        log("   Sleep window    : \(fmt.string(from: sleepStart)) → \(fmt.string(from: now))")
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif

        // Fetch exercise + sleep in parallel
        async let stepsResult = fetchStepsSafely(for: exerciseInterval)
        async let energyResult = fetchEnergySafely(for: exerciseInterval)
        async let sleepResult = fetchSleepSafely(for: sleepInterval)

        let steps = await stepsResult
        let energy = await energyResult
        let sleepSummary = await sleepResult

        #if DEBUG
        log("📦 HealthKit raw fetch results:")
        log("   Steps  : \(steps.map { String(format: "%.0f", $0) } ?? "nil (no data)")")
        log("   Energy : \(energy.map { String(format: "%.1f kcal", $0) } ?? "nil (no data)")")
        if let s = sleepSummary {
            log("   Sleep  : totalHours=\(String(format: "%.2f", s.totalHours))h  deepHours=\(String(format: "%.2f", s.deepHours))h")
        } else {
            log("   Sleep  : nil (no data for last night)")
        }
        #endif

        // Compute exercise factor
        let exerciseScore = computeExerciseScore(steps: steps, energy: energy)
        exerciseFactor = buildExerciseFactor(score: exerciseScore, steps: steps, energy: energy)

        #if DEBUG
        log("🏃 Exercise  → score=\(fmt2(exerciseScore))/25  stressContrib=\(fmt2(exerciseFactor.stressContribution))/25  [\(exerciseFactor.detailText)]")
        #endif

        // Compute sleep factor
        let sleepScore = computeSleepScore(summary: sleepSummary)
        sleepFactor = buildSleepFactor(score: sleepScore, summary: sleepSummary)

        #if DEBUG
        log("🌙 Sleep     → score=\(fmt2(sleepScore))/25  stressContrib=\(fmt2(sleepFactor.stressContribution))/25  [\(sleepFactor.detailText)]")
        #endif

        // Refresh diet synchronously from SwiftData
        refreshDietFactor()

        // Refresh screen time from persisted value
        refreshScreenTimeFactor()

        // ── Persist snapshot to WellnessDayLog so HomeView rings update ──
        persistTodayWellnessSnapshot(steps: steps, energy: energy)
        logCurrentStress(source: "auto")

        #if DEBUG
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log("📊 Stress summary:")
        log("   Exercise  score=\(fmt2(exerciseFactor.score))  contrib=\(fmt2(exerciseFactor.stressContribution))")
        log("   Sleep     score=\(fmt2(sleepFactor.score))  contrib=\(fmt2(sleepFactor.stressContribution))")
        log("   Diet      score=\(fmt2(dietFactor.score))  contrib=\(fmt2(dietFactor.stressContribution))")
        log("   ScrnTime  score=\(fmt2(screenTimeFactor.score))  contrib=\(fmt2(screenTimeFactor.stressContribution))")
        log("   ─────────────────────────────────────")
        log("   Total stress : \(fmt2(totalScore))/100  → Level: \(stressLevel.label)")
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif

        // Fetch 30-day histories for detail views and vitals display
        let thirtyDayStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let thirtyDayRange = DateInterval(start: thirtyDayStart, end: now)

        async let stepsHist  = fetchStepsHistorySafely(range: thirtyDayRange)
        async let energyHist = fetchEnergyHistorySafely(range: thirtyDayRange)
        async let sleepHist  = fetchSleepHistorySafely(range: thirtyDayRange)
        async let hrHist     = fetchHRHistorySafely(range: thirtyDayRange)
        async let restHist   = fetchRestingHRHistorySafely(range: thirtyDayRange)
        async let hrvHist    = fetchHRVHistorySafely(range: thirtyDayRange)
        async let sysBPHist  = fetchSysBPHistorySafely(range: thirtyDayRange)
        async let diasBPHist = fetchDiasBPHistorySafely(range: thirtyDayRange)
        async let rrHist     = fetchRRHistorySafely(range: thirtyDayRange)

        stepsHistory           = await stepsHist
        energyHistory          = await energyHist
        sleepHistory           = await sleepHist
        heartRateHistory       = await hrHist
        restingHRHistory       = await restHist
        hrvHistory             = await hrvHist
        systolicBPHistory      = await sysBPHist
        diastolicBPHistory     = await diasBPHist
        respiratoryRateHistory = await rrHist

        // Extract today's vitals values
        todayHeartRate       = heartRateHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todayRestingHR       = restingHRHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todayHRV             = hrvHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todaySystolicBP      = systolicBPHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todayDiastolicBP     = diastolicBPHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todayRespiratoryRate = respiratoryRateHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
    }

    func refreshDietFactor() {
        if let snap = mockSnapshot {
            currentDayLogs = snap.currentDayLogs
            let score = computeDietScore(logs: snap.currentDayLogs)
            dietFactor = buildDietFactor(score: score, logs: snap.currentDayLogs)
            return
        }
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate<FoodLogEntry> { entry in
                entry.day == today
            }
        )
        let logs = (try? modelContext.fetch(descriptor)) ?? []
        currentDayLogs = logs
        let score = computeDietScore(logs: logs)
        dietFactor = buildDietFactor(score: score, logs: logs)

        #if DEBUG
        if logs.isEmpty {
            log("🥗 Diet      → no food logged today  score=\(fmt2(score))/25  stressContrib=\(fmt2(dietFactor.stressContribution))/25")
        } else {
            let protein = logs.map(\.protein).reduce(0, +)
            let fiber   = logs.map(\.fiber).reduce(0, +)
            let fat     = logs.map(\.fat).reduce(0, +)
            let carbs   = logs.map(\.carbs).reduce(0, +)
            log("🥗 Diet      → \(logs.count) entries  protein=\(fmt1(protein))g  fiber=\(fmt1(fiber))g  fat=\(fmt1(fat))g  carbs=\(fmt1(carbs))g")
            log("             → score=\(fmt2(score))/25  stressContrib=\(fmt2(dietFactor.stressContribution))/25  [\(dietFactor.detailText)]")
        }
        #endif
    }

    func refreshDietFactorAndLogIfNeeded() {
        refreshDietFactor()
        logCurrentStress(source: "auto")
    }

    func refreshScreenTimeOnly() {
        refreshScreenTimeFactor()
        logCurrentStress(source: "auto")
    }

    // MARK: - Stress Reading Logging

    /// Persists the current computed stress score as a `StressReading` snapshot.
    /// Dedup guard: skips unless the latest reading from today has a different
    /// rounded score or level label.
    func logCurrentStress(source: String = "auto") {
        guard !usesMockData else { return }
        guard isAuthorized else {
            #if DEBUG
            log("[skip] logCurrentStress(\(source)) — HealthKit not authorized yet")
            #endif
            return
        }

        let scoreToLog = roundedLoggedStressScore(totalScore)
        if let latestReading = latestReadingForToday(),
           roundedLoggedStressScore(latestReading.score) == scoreToLog,
           latestReading.levelLabel == stressLevel.label {
            #if DEBUG
            log("[skip] logCurrentStress(\(source)) — latest reading already matches score=\(fmt2(scoreToLog)) level=\(stressLevel.label)")
            #endif
            return
        }

        let reading = StressReading(
            timestamp: Date(),
            score: scoreToLog,
            levelLabel: stressLevel.label,
            source: source
        )
        modelContext.insert(reading)
        try? modelContext.save()

        // Refresh published arrays so charts update immediately.
        loadReadings()

        #if DEBUG
        log("[log] StressReading saved -> score=\(fmt2(scoreToLog))  level=\(stressLevel.label)  source=\(source)")
        #endif
    }

    /// Fetches `StressReading` rows from SwiftData for today and the last 7 days.
    func loadReadings() {
        if let snap = mockSnapshot {
            todayReadings = snap.todayReadings
            weekReadings  = snap.weekReadings
            return
        }
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        // Today's readings
        let todayDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= startOfToday },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        todayReadings = (try? modelContext.fetch(todayDescriptor)) ?? []

        // Last 7 days readings
        let weekDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= startOfWeek },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        weekReadings = (try? modelContext.fetch(weekDescriptor)) ?? []
    }

    // MARK: - WellnessDayLog Sync

    /// Writes the current stress level and computed exercise minutes into today's
    /// `WellnessDayLog` so that HomeView's wellness rings stay in sync without
    /// requiring any shared ViewModel state.
    private func persistTodayWellnessSnapshot(steps: Double?, energy: Double?) {
        guard !usesMockData else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == today }
        )
        let wellnessLog: WellnessDayLog
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            wellnessLog = existing
        } else {
            let newLog = WellnessDayLog(day: Date())
            modelContext.insert(newLog)
            wellnessLog = newLog
        }

        // Stress level — derive from the just-computed totalScore.
        wellnessLog.stressLevel = stressLevel.label

        // Exercise minutes — estimate from active energy (~10 kcal per minute
        // of moderate-intensity exercise). Falls back to a steps-based estimate
        // (100 steps ≈ 1 min of walking) when energy data is unavailable.
        let estimatedMinutes: Int
        if let kcal = energy, kcal > 0 {
            estimatedMinutes = max(0, Int(kcal / 10.0))
        } else if let s = steps, s > 0 {
            estimatedMinutes = max(0, Int(s / 100.0))
        } else {
            estimatedMinutes = 0
        }
        wellnessLog.exerciseMinutes = estimatedMinutes
        wellnessLog.steps = Int(steps ?? 0)
        wellnessLog.caloriesBurned = Int(energy ?? 0)

        try? modelContext.save()

        #if DEBUG
        log_debug("💾 WellnessDayLog synced → stressLevel='\(stressLevel.label)'  exerciseMinutes=\(estimatedMinutes)")
        #endif
    }

    #if DEBUG
    private func log_debug(_ message: String) {
        WPLogger.stress.debug(message)
    }
    #endif


    // MARK: - Private: Safe Fetchers (return nil on error)

    private func fetchStepsSafely(for range: DateInterval) async -> Double? {
        guard let samples = try? await healthService.fetchSteps(for: range) else { return nil }
        let total = samples.map(\.value).reduce(0, +)
        return total > 0 ? total : nil
    }

    private func fetchEnergySafely(for range: DateInterval) async -> Double? {
        guard let samples = try? await healthService.fetchActiveEnergy(for: range) else { return nil }
        let total = samples.map(\.value).reduce(0, +)
        return total > 0 ? total : nil
    }

    private func fetchSleepSafely(for range: DateInterval) async -> DailySleepSummary? {
        try? await healthService.fetchDailySleepSummaries(for: range).last
    }

    // MARK: - 30-Day History Fetchers

    private func fetchStepsHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchSteps(for: range)) ?? []
    }

    private func fetchEnergyHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchActiveEnergy(for: range)) ?? []
    }

    private func fetchSleepHistorySafely(range: DateInterval) async -> [DailySleepSummary] {
        (try? await healthService.fetchDailySleepSummaries(for: range)) ?? []
    }

    private func fetchHRHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchHeartRate(for: range)) ?? []
    }

    private func fetchRestingHRHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchRestingHeartRate(for: range)) ?? []
    }

    private func fetchHRVHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchHRV(for: range)) ?? []
    }

    private func fetchSysBPHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchBloodPressureSystolic(for: range)) ?? []
    }

    private func fetchDiasBPHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchBloodPressureDiastolic(for: range)) ?? []
    }

    private func fetchRRHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchRespiratoryRate(for: range)) ?? []
    }

    // MARK: - Score Engines

    // Higher score = more activity = better (green).
    private func computeExerciseScore(steps: Double?, energy: Double?) -> Double {
        guard steps != nil || energy != nil else { return 12.5 }

        var scores: [Double] = []

        if let s = steps {
            scores.append(25.0 * clamp(s / 10_000.0))   // 10k steps → 25
        }
        if let e = energy {
            scores.append(25.0 * clamp(e / 600.0))      // 600 kcal  → 25
        }

        return scores.reduce(0, +) / Double(scores.count)
    }

    // Higher score = better sleep quality = better (green).
    private func computeSleepScore(summary: DailySleepSummary?) -> Double {
        guard let s = summary else { return 12.5 }
        let h = s.totalHours

        // Base quality from total hours (0–20 pts) — peaks at 7–9 h
        let baseScore: Double
        switch h {
        case ..<4:     baseScore = 0
        case 4..<5:    baseScore = lerp(from: 0,  to: 5,  t: (h - 4) / 1)
        case 5..<6:    baseScore = lerp(from: 5,  to: 12, t: (h - 5) / 1)
        case 6..<7:    baseScore = lerp(from: 12, to: 18, t: (h - 6) / 1)
        case 7..<9:    baseScore = lerp(from: 18, to: 20, t: (h - 7) / 2)
        case 9..<10:   baseScore = lerp(from: 20, to: 16, t: (h - 9) / 1)
        default:       baseScore = 14
        }

        // Deep sleep bonus (0–5 pts) — more deep sleep = higher score
        let deepBonus: Double
        if h > 0 {
            let deepRatio = s.deepHours / h
            deepBonus = clamp(deepRatio / 0.18) * 5
        } else {
            deepBonus = 2.5 // neutral
        }

        return min(25, baseScore + deepBonus)
    }

    private func computeDietScore(logs: [FoodLogEntry]) -> Double {
        guard !logs.isEmpty else { return 12.5 }

        let totalProtein = logs.map(\.protein).reduce(0, +)
        let totalFiber   = logs.map(\.fiber).reduce(0, +)
        let totalFat     = logs.map(\.fat).reduce(0, +)
        let totalCarbs   = logs.map(\.carbs).reduce(0, +)

        let proteinRatio = clamp(totalProtein / 60.0)
        let fiberRatio   = clamp(totalFiber / 25.0)
        let balancedScore = proteinRatio * 0.55 + fiberRatio * 0.45

        let fatRatio  = clamp(totalFat / 65.0)
        let carbRatio = clamp(totalCarbs / 225.0)
        let excessScore = fatRatio * 0.45 + carbRatio * 0.55

        let netBalance = clamp((balancedScore - excessScore * 0.6 + 0.5) / 1.0)

        // Higher netBalance = better diet = higher score (green).
        return 25.0 * netBalance
    }

    private func computeScreenTimeScore(hours: Double?) -> Double {
        guard let h = hours else { return 0 }
        // 2 points per hour, capped at 25
        return min(25, h * 2.0)
    }

    // MARK: - Factor Builders

    private func buildExerciseFactor(score: Double, steps: Double?, energy: Double?) -> StressFactorResult {
        let hasData = steps != nil || energy != nil
        let stepsStr = steps.map { NumberFormatter.localizedString(from: NSNumber(value: Int($0)), number: .decimal) } ?? "—"
        let energyStr = energy.map { "\(Int($0)) kcal" } ?? "—"

        let status: String
        if !hasData {
            status = "No data"
        } else if steps != nil && energy != nil {
            status = "\(stepsStr) steps · \(energyStr)"
        } else if let _ = steps {
            status = "\(stepsStr) steps"
        } else {
            status = energyStr
        }

        let detail: String
        if !hasData { detail = "No activity data yet" }
        else if score >= 18 { detail = "Great activity level!" }
        else if score >= 10 { detail = "Moderate activity today" }
        else { detail = "Try to move more today" }

        return StressFactorResult(title: "Exercise", score: hasData ? score : 0, maxScore: 25, icon: "figure.run",
                                  statusText: status, detailText: detail, higherIsBetter: true, hasValidData: hasData)
    }

    private func buildSleepFactor(score: Double, summary: DailySleepSummary?) -> StressFactorResult {
        let hasData = summary != nil
        let status: String
        if let s = summary {
            status = String(format: "%.1fh total · %.1fh deep", s.totalHours, s.deepHours)
        } else {
            status = "No data"
        }

        let detail: String
        if !hasData { detail = "No sleep data yet" }
        else if score >= 18 { detail = "Well rested!" }
        else if score >= 10 { detail = "Decent sleep" }
        else { detail = "Try to sleep more tonight" }

        return StressFactorResult(title: "Sleep", score: hasData ? score : 0, maxScore: 25, icon: "moon.fill",
                                  statusText: status, detailText: detail, higherIsBetter: true, hasValidData: hasData)
    }

    private func buildDietFactor(score: Double, logs: [FoodLogEntry]) -> StressFactorResult {
        let hasData = !logs.isEmpty
        let status: String
        if !hasData {
            status = "No food logged"
        } else {
            let protein = Int(logs.map(\.protein).reduce(0, +))
            let fiber   = Int(logs.map(\.fiber).reduce(0, +))
            status = "\(protein)g protein · \(fiber)g fiber"
        }

        let detail: String
        if !hasData { detail = "No diet data yet" }
        else if score >= 18 { detail = "Balanced diet today!" }
        else if score >= 10 { detail = "Fair nutritional balance" }
        else { detail = "Consider healthier choices" }

        return StressFactorResult(title: "Diet", score: hasData ? score : 0, maxScore: 25, icon: "leaf.fill",
                                  statusText: status, detailText: detail, higherIsBetter: true, hasValidData: hasData)
    }

    private func refreshScreenTimeFactor() {
        if let snap = mockSnapshot {
            screenTimeSource = .auto
            screenTimeDisplayHours = snap.screenTimeHours
            let score = computeScreenTimeScore(hours: snap.screenTimeHours)
            let detail = score < 8 ? "Low screen time 👍" : score < 16 ? "Moderate screen usage" : "Consider reducing screen time"
            screenTimeFactor = StressFactorResult(
                title: "Screen Time", score: score, maxScore: 25, icon: "iphone",
                statusText: String(format: "%.1fh (mock)", snap.screenTimeHours),
                detailText: detail, higherIsBetter: false, hasValidData: true
            )
            return
        }

        if let reading = ScreenTimeManager.shared.currentAutoDetectedReading {
            screenTimeSource = .auto
            screenTimeDisplayHours = reading.rawHours
            let score = computeScreenTimeScore(hours: reading.rawHours)
            let detail = score < 8 ? "Low screen time 👍" : score < 16 ? "Moderate screen usage" : "Consider reducing screen time"
            screenTimeFactor = StressFactorResult(
                title: "Screen Time", score: score, maxScore: 25, icon: "iphone",
                statusText: "\(reading.displayRoundedHours)h detected (±15m)",
                detailText: detail, higherIsBetter: false, hasValidData: true
            )
            #if DEBUG
            log("📱 ScrnTime  → rawHours=\(String(format: "%.3f h", reading.rawHours))  source=auto")
            log("             → score=\(fmt2(score))/25  stressContrib=\(fmt2(screenTimeFactor.stressContribution))/25  [\(detail)]")
            #endif
        } else {
            screenTimeSource = .none
            screenTimeDisplayHours = nil
            screenTimeFactor = StressFactorResult(
                title: "Screen Time", score: 0, maxScore: 25, icon: "iphone",
                statusText: "Under 15 min today",
                detailText: "No screen time detected yet", higherIsBetter: false, hasValidData: false
            )
            #if DEBUG
            log("📱 ScrnTime  → rawHours=nil  source=none (< 15 min)")
            #endif
        }
    }

    private func latestReadingForToday() -> StressReading? {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= startOfToday },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? modelContext.fetch(descriptor))?.last
    }

    private func roundedLoggedStressScore(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    // MARK: - Helpers

    private func clamp(_ value: Double, min lo: Double = 0, max hi: Double = 1) -> Double {
        Swift.min(hi, Swift.max(lo, value))
    }

    private func lerp(from a: Double, to b: Double, t: Double) -> Double {
        a + (b - a) * clamp(t)
    }

    // MARK: - Debug Logging

    #if DEBUG
    private func log(_ message: String) {
        WPLogger.stress.debug(message)
    }
    private func fmt2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }
    #endif
}
