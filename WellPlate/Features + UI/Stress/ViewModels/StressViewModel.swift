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
    case auto        // from DeviceActivity report / threshold resolver
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

    // MARK: - Dependencies

    private let healthService: HealthKitServiceProtocol
    private let modelContext: ModelContext

    // MARK: - Init

    init(healthService: HealthKitServiceProtocol = HealthKitService(), modelContext: ModelContext) {
        self.healthService = healthService
        self.modelContext = modelContext

        if ScreenTimeManager.shared.currentAutoDetectedReading != nil {
            self.screenTimeSource = .auto
        }
    }

    // MARK: - Actions

    func requestPermissionAndLoad() async {
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
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()
        let todayInterval = DateInterval(start: startOfDay, end: now)

        // Sleep: look back 1 day to capture last night
        let sleepStart = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let sleepInterval = DateInterval(start: sleepStart, end: now)

        #if DEBUG
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log("🔄 loadData() started")
        log("   Today window : \(fmt.string(from: startOfDay)) → \(fmt.string(from: now))")
        log("   Sleep window : \(fmt.string(from: sleepStart)) → \(fmt.string(from: now))")
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif

        // Fetch exercise + sleep in parallel
        async let stepsResult = fetchStepsSafely(for: todayInterval)
        async let energyResult = fetchEnergySafely(for: todayInterval)
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
    }

    func refreshDietFactor() {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate<FoodLogEntry> { entry in
                entry.day == today
            }
        )
        let logs = (try? modelContext.fetch(descriptor)) ?? []
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

    func refreshScreenTimeOnly() {
        refreshScreenTimeFactor()
    }

    // MARK: - Private: Safe Fetchers (return nil on error)

    private func fetchStepsSafely(for range: DateInterval) async -> Double? {
        try? await healthService.fetchSteps(for: range).first?.value
    }

    private func fetchEnergySafely(for range: DateInterval) async -> Double? {
        try? await healthService.fetchActiveEnergy(for: range).first?.value
    }

    private func fetchSleepSafely(for range: DateInterval) async -> DailySleepSummary? {
        try? await healthService.fetchDailySleepSummaries(for: range).last
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
        let stepsStr = steps.map { NumberFormatter.localizedString(from: NSNumber(value: Int($0)), number: .decimal) } ?? "—"
        let energyStr = energy.map { "\(Int($0)) kcal" } ?? "—"

        let status: String
        if steps != nil && energy != nil {
            status = "\(stepsStr) steps · \(energyStr)"
        } else if let _ = steps {
            status = "\(stepsStr) steps"
        } else if let _ = energy {
            status = energyStr
        } else {
            status = "No data"
        }

        let detail: String
        if score >= 18 { detail = "Great activity level!" }
        else if score >= 10 { detail = "Moderate activity today" }
        else { detail = "Try to move more today" }

        return StressFactorResult(title: "Exercise", score: score, maxScore: 25, icon: "figure.run",
                                  statusText: status, detailText: detail, higherIsBetter: true)
    }

    private func buildSleepFactor(score: Double, summary: DailySleepSummary?) -> StressFactorResult {
        let status: String
        if let s = summary {
            status = String(format: "%.1fh total · %.1fh deep", s.totalHours, s.deepHours)
        } else {
            status = "No data"
        }

        let detail: String
        if score >= 18 { detail = "Well rested!" }
        else if score >= 10 { detail = "Decent sleep" }
        else { detail = "Try to sleep more tonight" }

        return StressFactorResult(title: "Sleep", score: score, maxScore: 25, icon: "moon.fill",
                                  statusText: status, detailText: detail, higherIsBetter: true)
    }

    private func buildDietFactor(score: Double, logs: [FoodLogEntry]) -> StressFactorResult {
        let status: String
        if logs.isEmpty {
            status = "No food logged"
        } else {
            let protein = Int(logs.map(\.protein).reduce(0, +))
            let fiber   = Int(logs.map(\.fiber).reduce(0, +))
            status = "\(protein)g protein · \(fiber)g fiber"
        }

        let detail: String
        if logs.isEmpty { detail = "Log meals for an accurate score" }
        else if score >= 18 { detail = "Balanced diet today!" }
        else if score >= 10 { detail = "Fair nutritional balance" }
        else { detail = "Consider healthier choices" }

        return StressFactorResult(title: "Diet", score: score, maxScore: 25, icon: "leaf.fill",
                                  statusText: status, detailText: detail, higherIsBetter: true)
    }

    private func refreshScreenTimeFactor() {
        let reading = ScreenTimeManager.shared.currentAutoDetectedReading
        let scoreHours = reading?.rawHours

        screenTimeSource = reading != nil ? .auto : .none

        let score = computeScreenTimeScore(hours: scoreHours)

        let status: String
        let detail: String
        if let reading {
            status = "\(reading.displayRoundedHours)h detected (±15m)"
            if score < 8 { detail = "Low screen time 👍" }
            else if score < 16 { detail = "Moderate screen usage" }
            else { detail = "Consider reducing screen time" }
        } else {
            status = "Under 4h today"
            detail = "Score adds 2pts per hour above 4h"
        }

        screenTimeFactor = StressFactorResult(title: "Screen Time", score: score, maxScore: 25, icon: "iphone",
                                              statusText: status, detailText: detail, higherIsBetter: false)

        #if DEBUG
        let rawHoursStr = scoreHours.map { String(format: "%.3f h", $0) } ?? "nil"
        let sourceStr   = reading != nil ? "auto (DeviceActivity threshold)" : "none (< threshold)"
        log("📱 ScrnTime  → rawHours=\(rawHoursStr)  source=\(sourceStr)")
        log("             → score=\(fmt2(score))/25  stressContrib=\(fmt2(screenTimeFactor.stressContribution))/25  [\(detail)]")
        #endif
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
        print("[StressVM] \(message)")
    }
    private func fmt2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }
    #endif
}
