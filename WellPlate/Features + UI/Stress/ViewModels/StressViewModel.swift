//
//  StressViewModel.swift
//  WellPlate
//
//  Created on 21.02.2026.
//  Rewired for stress algorithm v3 (13-driver model).
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

    // MARK: - Published per-factor (backed from `allFactors` for legacy UI continuity)

    @Published var exerciseFactor: StressFactorResult  = .neutral(title: "Exercise",    icon: "figure.run", higherIsBetter: false, maxScore: StressScoring.Weights.exercise)
    @Published var sleepFactor: StressFactorResult     = .neutral(title: "Sleep",       icon: "moon.fill",  higherIsBetter: false, maxScore: StressScoring.Weights.sleep)
    @Published var dietFactor: StressFactorResult      = .neutral(title: "Diet",        icon: "leaf.fill",  higherIsBetter: false, maxScore: StressScoring.Weights.diet)
    @Published var screenTimeFactor: StressFactorResult = .neutral(title: "Screen Time", icon: "iphone",     higherIsBetter: false, maxScore: StressScoring.Weights.screenTime)
    @Published var isLoading = false
    @Published var isAuthorized = false
    @Published var errorMessage: String? = nil
    @Published var screenTimeSource: ScreenTimeSource = .none

    // MARK: - v3 Aggregate Result State

    /// Total stress score 0…100. Stored — set by `computeStress` orchestrator.
    @Published var totalScore: Double = 0
    /// Multiplicative HRV/RHR calibrator. 1.0 when no baseline (Watch-less).
    @Published var calibratorMultiplier: Double = 1.0
    /// Time-ramped engagement penalty 0…18.
    @Published var engagementPenaltyValue: Double = 0
    /// Multi-day pattern penalty 0…12.
    @Published var patternPenaltyValue: Double = 0
    /// All 13 factors in stable order (per `StressScoring.allFactors`).
    @Published var allFactors: [StressFactorResult] = []

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

    // MARK: - Circadian

    @Published var circadianResult: CircadianService.CircadianResult = CircadianService.CircadianResult(
        score: 0, regularityScore: 0, daylightScore: nil, level: .disrupted, tip: "", hasEnoughData: false
    )
    @Published var daylightHistory: [DailyMetricSample] = []

    // MARK: - Intraday Stress Readings (for charts)

    @Published var todayReadings: [StressReading] = []
    @Published var weekReadings: [StressReading] = []

    // MARK: - Diet Log Cache

    @Published var currentDayLogs: [FoodLogEntry] = []

    // MARK: - Computed

    var stressLevel: StressLevel { StressLevel(score: totalScore) }

    /// Top 5 factors contributing most to stress, ranked by stress contribution.
    var topStressors: [StressFactorResult] {
        allFactors.sorted { $0.stressContribution > $1.stressContribution }.prefix(5).map { $0 }
    }

    /// Number of factors that have valid input data for today (0–13 in v3).
    var factorCoverage: Int { allFactors.filter(\.hasValidData).count }

    /// Coverage-weighted confidence per formula spec §8.
    /// `high` ≥70%, `medium` 40–70%, `low` <40%.
    var stressConfidence: Confidence {
        let totalPossible: Double = 100   // sum of v3 driver weights
        let covered = allFactors.reduce(0.0) { $0 + ($1.hasValidData ? $1.maxScore : 0) }
        let coverage = covered / totalPossible
        switch coverage {
        case 0.70...:        return .high
        case 0.40..<0.70:    return .medium
        default:             return .low
        }
    }

    /// Honest mode: low confidence hides the score.
    var shouldHideScoreForLowConfidence: Bool { stressConfidence == .low }

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

    @Published var screenTimeDisplayHours: Double? = nil

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

    // MARK: - HK Cache (reused by `recompute()` so we don't re-hit HealthKit)

    private var lastSteps: Double? = nil
    private var lastEnergy: Double? = nil
    private var lastSleepSummary: DailySleepSummary? = nil
    private var lastHRVHistory: [DailyMetricSample] = []
    private var lastRHRHistory: [DailyMetricSample] = []
    private var lastDaylightToday: Double? = nil

    // MARK: - Combine

    private var tickerCancellable: AnyCancellable?
    private var manualInputCancellable: AnyCancellable?

    // MARK: - Init

    init(
        healthService: HealthKitServiceProtocol = HealthKitServiceFactory.shared,
        modelContext: ModelContext,
        mockSnapshot: StressMockSnapshot? = nil
    ) {
        self.healthService = healthService
        self.modelContext = modelContext
        self.mockSnapshot = mockSnapshot

        if mockSnapshot == nil, ScreenTimeManager.shared.currentAutoDetectedReading != nil {
            screenTimeSource = .auto
        }

        // Subscribe to engagement-ramp ticker so the score updates as the day progresses.
        tickerCancellable = StressTimerService.shared.$tickerPulse
            .dropFirst()
            .sink { [weak self] _ in self?.recompute() }
    }

    /// Wires this VM to a `DailyPromptCoordinator`. Called once after the
    /// environment object becomes available (P2 wires this from views).
    func bindManualInputUpdates(from coordinator: any ManualInputObservable) {
        manualInputCancellable = coordinator.manualInputSavedAtPublisher
            .dropFirst()
            .sink { [weak self] _ in self?.recompute() }
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

        // Exercise window: if it's before 3 AM, yesterday's full day has more
        // meaningful data than the handful of minutes since midnight.
        let hour = calendar.component(.hour, from: now)
        let exerciseStart: Date
        let exerciseEnd: Date
        if hour < 3 {
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

        // Fetch exercise + sleep in parallel
        async let stepsResult = fetchStepsSafely(for: exerciseInterval)
        async let energyResult = fetchEnergySafely(for: exerciseInterval)
        async let sleepResult = fetchSleepSafely(for: sleepInterval)

        let steps = await stepsResult
        let energy = await energyResult
        let sleepSummary = await sleepResult

        // Cache HK results so recompute() can skip these I/O hits.
        lastSteps = steps
        lastEnergy = energy
        lastSleepSummary = sleepSummary

        // Fetch 30-day histories for detail views, vitals display, and HRV/RHR baseline.
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
        async let daylightHist = fetchDaylightHistorySafely(range: thirtyDayRange)

        stepsHistory           = await stepsHist
        energyHistory          = await energyHist
        sleepHistory           = await sleepHist
        heartRateHistory       = await hrHist
        restingHRHistory       = await restHist
        hrvHistory             = await hrvHist
        systolicBPHistory      = await sysBPHist
        diastolicBPHistory     = await diasBPHist
        respiratoryRateHistory = await rrHist
        daylightHistory        = await daylightHist

        // Cache vitals history for recompute() reuse.
        lastHRVHistory = hrvHistory
        lastRHRHistory = restingHRHistory

        // Today's vitals (display-only — never feed into scoring path)
        todayHeartRate       = heartRateHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todayRestingHR       = restingHRHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todayHRV             = hrvHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todaySystolicBP      = systolicBPHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todayDiastolicBP     = diastolicBPHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        todayRespiratoryRate = respiratoryRateHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value

        // Today's daylight minutes (cached for recompute reuse)
        lastDaylightToday = daylightHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value

        // Compute Circadian Score from last 7 days of sleep + daylight
        let sevenDayStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let recentSleep = sleepHistory.filter { $0.date >= sevenDayStart }
        let recentDaylight = daylightHistory.filter { $0.date >= sevenDayStart }
        circadianResult = CircadianService.compute(sleepSummaries: recentSleep, daylightSamples: recentDaylight)

        // Currently logged food (display + diet factor)
        currentDayLogs = mockSnapshot?.currentDayLogs ?? fetchTodayFoodLogs()

        // Build StressInputs and run computeStress
        let inputs = usesMockData
            ? buildInputsFromMockSnapshot(mockSnapshot!, now: now)
            : buildInputs(now: now)
        let result = StressScoring.computeStress(inputs: inputs, now: now)
        applyResult(result)

        // Persist snapshot to WellnessDayLog so HomeView rings update
        persistTodayWellnessSnapshot(steps: steps, energy: energy)
        logCurrentStress(source: "auto")

        // Ensure weekReadings is populated (SwiftData doesn't need HK auth)
        loadReadings()
        // Push latest data to widget
        WidgetRefreshHelper.refreshStress(viewModel: self)
    }

    /// Re-fetches cheap SwiftData (mood/water/food/symptoms/journal/interventions/manual/recent
    /// wellness/active fast) and reuses cached HK from the most recent `loadData()`.
    /// Calls `computeStress` and republishes.
    func recompute() {
        let now = Date()
        currentDayLogs = mockSnapshot?.currentDayLogs ?? fetchTodayFoodLogs()
        let inputs = usesMockData
            ? buildInputsFromMockSnapshot(mockSnapshot!, now: now)
            : buildInputs(now: now)
        let result = StressScoring.computeStress(inputs: inputs, now: now)
        applyResult(result)
        WidgetRefreshHelper.refreshStress(viewModel: self)
    }

    func refreshDietFactor() {
        recompute()
    }

    func refreshDietFactorAndLogIfNeeded() {
        recompute()
        logCurrentStress(source: "auto")
    }

    func refreshScreenTimeOnly() {
        recompute()
        logCurrentStress(source: "auto")
    }

    // MARK: - Stress Reading Logging

    /// Persists the current computed stress score as a `StressReading` snapshot.
    /// Dedup guard: skips unless the latest reading from today has a different
    /// rounded score or level label.
    func logCurrentStress(source: String = "auto") {
        guard !usesMockData else { return }
        guard isAuthorized else { return }

        let scoreToLog = roundedLoggedStressScore(totalScore)
        if let latestReading = latestReadingForToday(),
           roundedLoggedStressScore(latestReading.score) == scoreToLog,
           latestReading.levelLabel == stressLevel.label {
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

        loadReadings()
    }

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

        let todayDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= startOfToday },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        todayReadings = (try? modelContext.fetch(todayDescriptor)) ?? []

        let weekDescriptor = FetchDescriptor<StressReading>(
            predicate: #Predicate { $0.timestamp >= startOfWeek },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        weekReadings = (try? modelContext.fetch(weekDescriptor)) ?? []
    }

    // MARK: - WellnessDayLog Sync

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

        wellnessLog.stressLevel = stressLevel.label

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
    }

    // MARK: - Apply v3 Result

    /// Publishes a `StressResult` into all the @Published vars. Maps the 13 factor
    /// indices to titles/icons (in stable order matching `StressScoring.allFactors`).
    private func applyResult(_ result: StressScoring.StressResult) {
        totalScore = result.score
        calibratorMultiplier = result.calibrator
        engagementPenaltyValue = result.engagementPenalty
        patternPenaltyValue = result.patternPenalty

        let mapped: [StressFactorResult] = result.factors.enumerated().map { idx, fp in
            StressFactorResult(
                from: fp,
                title: factorTitle(idx),
                icon: factorIcon(idx),
                higherIsBetter: false
            )
        }
        allFactors = mapped

        // Back legacy per-factor publisheds for callers that haven't migrated yet.
        exerciseFactor   = mapped.first(where: { $0.title == "Exercise"  }) ?? exerciseFactor
        sleepFactor      = mapped.first(where: { $0.title == "Sleep"     }) ?? sleepFactor
        dietFactor       = mapped.first(where: { $0.title == "Diet"      }) ?? dietFactor
        screenTimeFactor = mapped.first(where: { $0.title == "Screen Time" }) ?? screenTimeFactor

        // Update screen-time auto/manual source bookkeeping for the legacy display.
        if let screenInput = lastResolvedScreen {
            screenTimeSource = .auto
            screenTimeDisplayHours = screenInput.totalHours
        } else if let auto = ScreenTimeManager.shared.currentAutoDetectedReading {
            screenTimeSource = .auto
            screenTimeDisplayHours = auto.rawHours
        } else {
            screenTimeSource = .none
            screenTimeDisplayHours = nil
        }
    }

    // MARK: - Factor Index → Display Mapping

    /// Stable index → title mapping. Must match `StressScoring.allFactors` order.
    private func factorTitle(_ idx: Int) -> String {
        switch idx {
        case 0:  return "Sleep"
        case 1:  return "Exercise"
        case 2:  return "Caffeine"
        case 3:  return "Screen Time"
        case 4:  return "Diet"
        case 5:  return "Hydration"
        case 6:  return "Circadian"
        case 7:  return "Daylight"
        case 8:  return "Meal Timing"
        case 9:  return "Fasting"
        case 10: return "Eating Triggers"
        case 11: return "Mood"
        case 12: return "Symptoms"
        default: return "Unknown"
        }
    }

    private func factorIcon(_ idx: Int) -> String {
        switch idx {
        case 0:  return "moon.fill"
        case 1:  return "figure.run"
        case 2:  return "cup.and.saucer.fill"
        case 3:  return "iphone"
        case 4:  return "leaf.fill"
        case 5:  return "drop.fill"
        case 6:  return "clock.fill"
        case 7:  return "sun.max.fill"
        case 8:  return "fork.knife"
        case 9:  return "timer"
        case 10: return "exclamationmark.bubble"
        case 11: return "face.smiling"
        case 12: return "bandage"
        default: return "questionmark.circle"
        }
    }

    // MARK: - Build Inputs

    /// Tracks the resolved screen-time input from the latest build for legacy display.
    private var lastResolvedScreen: StressScoring.ScreenInput? = nil

    private func buildInputs(now: Date) -> StressScoring.StressInputs {
        let goals = UserGoals.current(in: modelContext)
        let manual = fetchTodayManualInput()
        let todayWellness = fetchTodayWellnessLog()
        let todayFoods = fetchTodayFoodLogs()
        let todaySymptoms = fetchTodaySymptoms()
        let todayJournal = fetchTodayJournal()
        let todayInterventions = fetchTodayInterventions().filter { $0.completed }
        let recentWellness = fetchRecentWellnessLogs()
        let recentFoodPresence = fetchRecentFoodLogPresence()
        let activeFast = fetchActiveFastingSession()
        let lastFastEnd = fetchLastCompletedFastEnd()
        let fastingConfigured = fetchFastingScheduleConfigured()

        // Sleep
        let sleepInput = resolveSleep(hk: lastSleepSummary, manual: manual)

        // Exercise
        let exerciseInput = resolveExercise(steps: lastSteps, energy: lastEnergy, manual: manual)

        // Caffeine — tied to today's WellnessDayLog row existence (per §0.1)
        let caffeineInput: StressScoring.CaffeineInput? = todayWellness.map { log in
            StressScoring.CaffeineInput(
                cups: log.coffeeCups,
                type: log.resolvedCoffeeType,
                hasWellnessRow: true
            )
        }

        // Screen time
        let autoHours: Double? = ScreenTimeManager.shared.currentAutoDetectedReading?.rawHours
        let screenInput = resolveScreen(autoHours: autoHours, manual: manual)
        lastResolvedScreen = screenInput

        // Diet
        let dietInput = makeDietInput(from: todayFoods)

        // Hydration — tied to today's WellnessDayLog row existence (per §0.1)
        let hydrationInput: StressScoring.HydrationInput? = todayWellness.map { log in
            StressScoring.HydrationInput(glasses: log.waterGlasses, hasWellnessRow: true)
        }

        // Circadian
        let manualHistory = fetchRecentManualInputHistory()
        let circadianInput = resolveCircadian(hkSummaries: sleepHistory, manualHistory: manualHistory)

        // Daylight
        let daylightInput = resolveDaylight(hkMinutes: lastDaylightToday, manual: manual)

        // Fasting
        let activeFastHours: Double? = {
            guard let s = activeFast else { return nil }
            return now.timeIntervalSince(s.startedAt) / 3600.0
        }()
        let fastingInput = StressScoring.FastingInput(
            activeFastHours: activeFastHours,
            isConfigured: fastingConfigured
        )

        // Mood
        let mood: MoodOption? = todayWellness.flatMap { log in
            log.moodRaw.flatMap(MoodOption.init(rawValue:))
        }

        // Recovery
        let recovery = StressScoring.RecoveryInput(
            completedInterventionsToday: todayInterventions.count,
            hasJournalToday: todayJournal != nil,
            hasMoodToday: mood != nil,
            hasMindfulSessionToday: !todayInterventions.isEmpty
        )

        // History
        let history = StressScoring.HistoryInput(
            recentWellnessLogs: recentWellness,
            foodLogPresenceByDay: recentFoodPresence,
            lastCompletedFastEnd: lastFastEnd
        )

        // Vitals
        let vitals = StressScoring.VitalsInput(
            todayHRV: todayHRV,
            hrvHistory: lastHRVHistory.isEmpty ? hrvHistory : lastHRVHistory,
            todayRHR: todayRestingHR,
            rhrHistory: lastRHRHistory.isEmpty ? restingHRHistory : lastRHRHistory
        )

        return StressScoring.StressInputs(
            sleep: sleepInput,
            exercise: exerciseInput,
            caffeine: caffeineInput,
            screen: screenInput,
            diet: dietInput,
            hydration: hydrationInput,
            circadian: circadianInput,
            daylight: daylightInput,
            mealLogs: todayFoods,
            fasting: fastingInput,
            triggerLogs: todayFoods,
            mood: mood,
            symptoms: todaySymptoms,
            recovery: recovery,
            history: history,
            vitals: vitals,
            goals: goals
        )
    }

    private func buildInputsFromMockSnapshot(_ snap: StressMockSnapshot, now: Date) -> StressScoring.StressInputs {
        let goals = UserGoals.current(in: modelContext)

        let sleepInput = StressScoring.SleepInput(
            totalHours: snap.sleepSummary.totalHours,
            deepHours: snap.sleepSummary.deepHours,
            source: .healthKit
        )

        let exerciseInput: StressScoring.ExerciseInput? = (snap.steps > 0 || snap.energy > 0)
            ? StressScoring.ExerciseInput(steps: snap.steps > 0 ? snap.steps : nil,
                                          energy: snap.energy > 0 ? snap.energy : nil,
                                          manualMinutes: nil,
                                          source: .healthKit)
            : nil

        // Mock caffeine reflects WellnessDayLog presence as `coffeeCups > 0 || coffeeType != nil`
        let hasWellnessProxy = (snap.coffeeCups > 0 || snap.coffeeType != nil || snap.waterGlasses > 0 || snap.mood != nil)
        let caffeineInput = StressScoring.CaffeineInput(
            cups: snap.coffeeCups,
            type: snap.coffeeType,
            hasWellnessRow: hasWellnessProxy
        )

        let screenInput: StressScoring.ScreenInput? = snap.screenTimeHours > 0
            ? StressScoring.ScreenInput(totalHours: snap.screenTimeHours, eveningHours: nil, source: .healthKit)
            : nil
        lastResolvedScreen = screenInput

        let dietInput = makeDietInput(from: snap.currentDayLogs)

        let hydrationInput = StressScoring.HydrationInput(
            glasses: snap.waterGlasses,
            hasWellnessRow: hasWellnessProxy
        )

        let circadianInput = resolveCircadian(hkSummaries: snap.sleepHistory, manualHistory: [])

        let daylightInput: StressScoring.DaylightInput? = {
            guard let today = snap.daylightHistory.first(where: { Calendar.current.isDateInToday($0.date) }),
                  today.value > 0 else { return nil }
            return StressScoring.DaylightInput(minutes: today.value, source: .healthKit)
        }()

        let fastingInput = StressScoring.FastingInput(
            activeFastHours: nil,
            isConfigured: snap.lastCompletedFastEnd != nil
        )

        let recovery = StressScoring.RecoveryInput(
            completedInterventionsToday: snap.todayInterventions.count,
            hasJournalToday: snap.todayJournal != nil,
            hasMoodToday: snap.mood != nil,
            hasMindfulSessionToday: !snap.todayInterventions.isEmpty
        )

        let recentFoodPresence: [Date: Bool] = Dictionary(
            grouping: snap.recentFoodLogs,
            by: { Calendar.current.startOfDay(for: $0.day) }
        ).mapValues { !$0.isEmpty }

        let history = StressScoring.HistoryInput(
            recentWellnessLogs: snap.recentWellnessLogs,
            foodLogPresenceByDay: recentFoodPresence,
            lastCompletedFastEnd: snap.lastCompletedFastEnd
        )

        let todayHRVValue = snap.hrvHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        let todayRHRValue = snap.restingHRHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
        let vitals = StressScoring.VitalsInput(
            todayHRV: todayHRVValue,
            hrvHistory: snap.hrvHistory,
            todayRHR: todayRHRValue,
            rhrHistory: snap.restingHRHistory
        )

        return StressScoring.StressInputs(
            sleep: sleepInput,
            exercise: exerciseInput,
            caffeine: caffeineInput,
            screen: screenInput,
            diet: dietInput,
            hydration: hydrationInput,
            circadian: circadianInput,
            daylight: daylightInput,
            mealLogs: snap.currentDayLogs,
            fasting: fastingInput,
            triggerLogs: snap.currentDayLogs,
            mood: snap.mood,
            symptoms: snap.todaySymptoms,
            recovery: recovery,
            history: history,
            vitals: vitals,
            goals: goals
        )
    }

    private func makeDietInput(from logs: [FoodLogEntry]) -> StressScoring.DietInput? {
        guard !logs.isEmpty else { return nil }
        let protein = logs.map(\.protein).reduce(0, +)
        let fiber = logs.map(\.fiber).reduce(0, +)
        let carbs = logs.map(\.carbs).reduce(0, +)
        let fat = logs.map(\.fat).reduce(0, +)
        return StressScoring.DietInput(
            protein: protein,
            fiber: fiber,
            carbs: carbs,
            fat: fat,
            hasLogs: true
        )
    }

    // MARK: - Resolution Helpers (HK first, manual second, silent third)

    private func resolveSleep(hk: DailySleepSummary?, manual: ManualDailyInput?) -> StressScoring.SleepInput? {
        if let s = hk {
            return StressScoring.SleepInput(
                totalHours: s.totalHours,
                deepHours: s.deepHours,
                source: .healthKit
            )
        }
        guard let m = manual, let h = m.sleepHours else { return nil }
        let derivedDeep: Double = {
            switch m.sleepQuality ?? 3 {
            case 1: return 0.25
            case 2: return 0.5
            case 3: return 0.75
            case 4: return 1.0
            case 5: return 1.33
            default: return 0.75
            }
        }()
        return StressScoring.SleepInput(totalHours: h, deepHours: derivedDeep, source: .manual)
    }

    private func resolveExercise(steps: Double?, energy: Double?, manual: ManualDailyInput?) -> StressScoring.ExerciseInput? {
        if let s = steps, s > 0 {
            return StressScoring.ExerciseInput(steps: s, energy: energy, manualMinutes: nil, source: .healthKit)
        }
        if let e = energy, e > 0 {
            return StressScoring.ExerciseInput(steps: steps, energy: e, manualMinutes: nil, source: .healthKit)
        }
        guard let m = manual, let mins = m.exerciseMinutes else { return nil }
        return StressScoring.ExerciseInput(steps: nil, energy: nil, manualMinutes: mins, source: .manual)
    }

    private func resolveScreen(autoHours: Double?, manual: ManualDailyInput?) -> StressScoring.ScreenInput? {
        if let h = autoHours {
            return StressScoring.ScreenInput(totalHours: h, eveningHours: nil, source: .healthKit)
        }
        guard let m = manual, let h = m.screenTimeHours else { return nil }
        let evening = (m.heavyEveningScreens == true) ? 2.0 : 0.0
        return StressScoring.ScreenInput(totalHours: h, eveningHours: evening, source: .manual)
    }

    private func resolveDaylight(hkMinutes: Double?, manual: ManualDailyInput?) -> StressScoring.DaylightInput? {
        if let m = hkMinutes, m > 0 {
            return StressScoring.DaylightInput(minutes: m, source: .healthKit)
        }
        guard let outside = manual?.amDaylightOutside else { return nil }
        return StressScoring.DaylightInput(minutes: outside ? 30 : 5, source: .manual)
    }

    private func resolveCircadian(hkSummaries: [DailySleepSummary], manualHistory: [ManualDailyInput]) -> StressScoring.CircadianInput? {
        let manualSummaries: [DailySleepSummary] = manualHistory.compactMap { input in
            guard let bt = input.bedtime, let wt = input.wakeTime, let h = input.sleepHours else { return nil }
            return DailySleepSummary(
                date: input.day,
                totalHours: h,
                coreHours: 0,
                remHours: 0,
                deepHours: 0,
                bedtime: bt,
                wakeTime: wt
            )
        }
        let combined = (hkSummaries + manualSummaries).sorted { $0.date < $1.date }
        let (score, hasData) = CircadianService.sleepRegularityIndex(from: combined)
        guard hasData else { return nil }
        return StressScoring.CircadianInput(regularityScore: score, hasEnoughData: true)
    }

    // MARK: - SwiftData fetchers (cheap; called by recompute and buildInputs)

    private func fetchTodayWellnessLog() -> WellnessDayLog? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == today }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchTodayFoodLogs() -> [FoodLogEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day == today }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchTodaySymptoms() -> [SymptomEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate { $0.day == today }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchTodayJournal() -> JournalEntry? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.day == today }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchTodayInterventions() -> [InterventionSession] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<InterventionSession>(
            predicate: #Predicate { $0.startedAt >= startOfToday }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchRecentWellnessLogs() -> [WellnessDayLog] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let threeDaysAgo = cal.date(byAdding: .day, value: -2, to: today) ?? today
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day >= threeDaysAgo && $0.day <= today }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchRecentFoodLogPresence() -> [Date: Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let threeDaysAgo = cal.date(byAdding: .day, value: -2, to: today) ?? today
        let descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day >= threeDaysAgo && $0.day <= today }
        )
        let logs = (try? modelContext.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: logs, by: { cal.startOfDay(for: $0.day) })
        var presence: [Date: Bool] = [:]
        for offset in 0...2 {
            if let day = cal.date(byAdding: .day, value: -offset, to: today) {
                presence[day] = !(grouped[day]?.isEmpty ?? true)
            }
        }
        return presence
    }

    private func fetchActiveFastingSession() -> FastingSession? {
        let descriptor = FetchDescriptor<FastingSession>(
            predicate: #Predicate { $0.actualEndAt == nil }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchLastCompletedFastEnd() -> Date? {
        var descriptor = FetchDescriptor<FastingSession>(
            predicate: #Predicate { $0.completed == true },
            sortBy: [SortDescriptor(\.actualEndAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.actualEndAt
    }

    private func fetchFastingScheduleConfigured() -> Bool {
        let descriptor = FetchDescriptor<FastingSchedule>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    private func fetchTodayManualInput() -> ManualDailyInput? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<ManualDailyInput>(
            predicate: #Predicate { $0.day == today }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchRecentManualInputHistory() -> [ManualDailyInput] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let descriptor = FetchDescriptor<ManualDailyInput>(
            predicate: #Predicate { $0.day >= sevenDaysAgo }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

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

    private func fetchDaylightHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
        (try? await healthService.fetchDaylight(for: range)) ?? []
    }

    // MARK: - Stress reading helpers

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
}

// MARK: - Confidence (typealias, owned by StressScoring)

extension StressViewModel {
    typealias Confidence = StressScoring.Confidence
}

// MARK: - Manual Input Observable

/// Hook-up surface for `DailyPromptCoordinator` (P2). Kept as a protocol so the
/// scoring core stays decoupled from coordinator internals.
@MainActor
protocol ManualInputObservable: AnyObject {
    var manualInputSavedAtPublisher: Published<Date>.Publisher { get }
}
