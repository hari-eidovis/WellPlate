import XCTest
@testable import WellPlate

/// Unit tests for the v3 `StressScoring` core (formula spec §14 validation checklist).
/// Note: The `WellPlateTests` target is not currently wired into the `WellPlate` shared
/// scheme — these cases require manual scheme configuration (Edit Scheme → Test action →
/// enable WellPlateTests → mark Shared) before they will run via `xcodebuild test`.
final class StressScoringTests: XCTestCase {

    // MARK: - Helpers

    private func defaultGoals() -> UserGoals { UserGoals.defaults() }

    private func emptyHistory() -> StressScoring.HistoryInput {
        StressScoring.HistoryInput(recentWellnessLogs: [],
                                   foodLogPresenceByDay: [:],
                                   lastCompletedFastEnd: nil)
    }

    private func emptyVitals() -> StressScoring.VitalsInput {
        StressScoring.VitalsInput(todayHRV: nil, hrvHistory: [],
                                  todayRHR: nil, rhrHistory: [])
    }

    private func emptyRecovery() -> StressScoring.RecoveryInput {
        StressScoring.RecoveryInput(completedInterventionsToday: 0,
                                    hasJournalToday: false,
                                    hasMoodToday: false,
                                    hasMindfulSessionToday: false)
    }

    private func emptyInputs(goals: UserGoals? = nil) -> StressScoring.StressInputs {
        StressScoring.StressInputs(
            sleep: nil, exercise: nil, caffeine: nil, screen: nil,
            diet: nil, hydration: nil, circadian: nil, daylight: nil,
            mealLogs: [], fasting: StressScoring.FastingInput(activeFastHours: nil, isConfigured: false),
            triggerLogs: [], mood: nil, symptoms: [],
            recovery: emptyRecovery(),
            history: emptyHistory(),
            vitals: emptyVitals(),
            goals: goals ?? defaultGoals()
        )
    }

    private func morningTime(hour: Int = 8) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // MARK: - §14 validation cases

    /// Score should be 0 with low confidence when no driver has data.
    func testZeroInputReturnsLowConfidence() {
        let inputs = emptyInputs()
        let result = StressScoring.computeStress(inputs: inputs, now: morningTime())
        XCTAssertEqual(result.driverSum, 0, accuracy: 0.01)
        XCTAssertEqual(result.engagementPenalty, 0, accuracy: 0.01)   // activation guard
        XCTAssertEqual(result.score, 0, accuracy: 0.01)
        XCTAssertEqual(result.confidence, .low)
    }

    /// Perfect day → 0 score (drivers good, recovery in play).
    func testPerfectDayReturnsZero() {
        var inputs = emptyInputs()
        inputs.sleep = .init(totalHours: 8, deepHours: 1.5, source: .healthKit)
        inputs.exercise = .init(steps: 7000, energy: 400, manualMinutes: nil, source: .healthKit)
        inputs.caffeine = .init(cups: 0, type: nil, hasWellnessRow: true)
        inputs.screen = .init(totalHours: 1.0, eveningHours: 0, source: .healthKit)
        inputs.diet = .init(protein: 100, fiber: 25, carbs: 150, fat: 60, hasLogs: true)
        inputs.hydration = .init(glasses: 8, hasWellnessRow: true)
        inputs.circadian = .init(regularityScore: 100, hasEnoughData: true)
        inputs.daylight = .init(minutes: 60, source: .healthKit)
        inputs.fasting = .init(activeFastHours: 14, isConfigured: true)
        inputs.mood = .great
        inputs.recovery = .init(completedInterventionsToday: 1, hasJournalToday: true,
                                hasMoodToday: true, hasMindfulSessionToday: true)
        let result = StressScoring.computeStress(inputs: inputs, now: morningTime(hour: 12))
        XCTAssertLessThanOrEqual(result.score, 5, "Perfect day should land near 0")
    }

    /// Worst-logged day clamps to 100.
    func testWorstLoggedDayClampsTo100() {
        var inputs = emptyInputs()
        inputs.sleep = .init(totalHours: 3.0, deepHours: 0.1, source: .healthKit)
        inputs.exercise = .init(steps: 50, energy: 5, manualMinutes: nil, source: .healthKit)
        inputs.caffeine = .init(cups: 6, type: .coldBrew, hasWellnessRow: true)
        inputs.screen = .init(totalHours: 12, eveningHours: 6, source: .healthKit)
        inputs.diet = .init(protein: 10, fiber: 1, carbs: 600, fat: 200, hasLogs: true)
        inputs.hydration = .init(glasses: 0, hasWellnessRow: true)
        inputs.daylight = .init(minutes: 0, source: .healthKit)
        inputs.fasting = .init(activeFastHours: 30, isConfigured: true)
        inputs.mood = .awful
        let result = StressScoring.computeStress(inputs: inputs, now: morningTime(hour: 22))
        XCTAssertLessThanOrEqual(result.score, 100)
        XCTAssertGreaterThanOrEqual(result.score, 70, "Worst day should be at least High")
    }

    /// Logging mood `.great` strictly reduces score vs not logged after 21:00 with otherwise sparse data.
    func testMoodGreatStrictlyReducesScore() {
        var base = emptyInputs()
        base.sleep = .init(totalHours: 5.0, deepHours: 0.5, source: .healthKit)
        let now = morningTime(hour: 21)
        let scoreNoMood = StressScoring.computeStress(inputs: base, now: now).score
        var withMood = base
        withMood.mood = .great
        withMood.recovery = .init(completedInterventionsToday: 0, hasJournalToday: false,
                                  hasMoodToday: true, hasMindfulSessionToday: false)
        let scoreGreat = StressScoring.computeStress(inputs: withMood, now: now).score
        XCTAssertLessThan(scoreGreat, scoreNoMood, "Logging great mood should reduce S")
    }

    /// Logging 8 glasses of water strictly reduces score vs zero after 18:00.
    func testWaterEightStrictlyReducesScore() {
        var base = emptyInputs()
        base.sleep = .init(totalHours: 6.0, deepHours: 0.5, source: .healthKit)
        base.hydration = .init(glasses: 0, hasWellnessRow: true)
        let now = morningTime(hour: 19)
        let scoreNo = StressScoring.computeStress(inputs: base, now: now).score
        var withWater = base
        withWater.hydration = .init(glasses: 8, hasWellnessRow: true)
        let scoreYes = StressScoring.computeStress(inputs: withWater, now: now).score
        XCTAssertLessThan(scoreYes, scoreNo, "Logging full hydration should reduce S")
    }

    /// Manual sleep entry produces same `p_sleep` as HK with equivalent values.
    func testManualSleepEqualsHKEquivalent() {
        let hk = StressScoring.SleepInput(totalHours: 6.5, deepHours: 0.75, source: .healthKit)
        let manual = StressScoring.SleepInput(totalHours: 6.5, deepHours: 0.75, source: .manual)
        let hkPts = StressScoring.sleepPoints(input: hk).points
        let mPts = StressScoring.sleepPoints(input: manual).points
        XCTAssertEqual(hkPts, mPts, accuracy: 0.001)
    }

    /// Calibrator collapses to 1.0 with no baseline.
    func testCalibratorCollapsesWithoutBaseline() {
        let c = StressScoring.calibrator(.init(todayHRV: 40, hrvBaseline: nil,
                                               todayRHR: 60, rhrBaseline: nil))
        XCTAssertEqual(c, 1.0, accuracy: 0.001)
    }

    /// Engagement penalty = 0 before its t_start hour (gates at 14:00 minimum).
    func testEngagementZeroBeforeStartHour() {
        var inputs = emptyInputs()
        inputs.sleep = .init(totalHours: 6.0, deepHours: 0.5, source: .healthKit)
        let earlyMorning = morningTime(hour: 8)
        let pen = StressScoring.engagementPenalty(inputs: inputs, now: earlyMorning)
        XCTAssertEqual(pen, 0, accuracy: 0.001)
    }

    /// Pattern penalty is stable across recompute cycles within the same day.
    func testPatternPenaltyStableAcrossRecomputes() {
        let history = StressScoring.HistoryInput(
            recentWellnessLogs: [],
            foodLogPresenceByDay: [:],
            lastCompletedFastEnd: nil
        )
        let p1 = StressScoring.patternPenalty(history: history)
        let p2 = StressScoring.patternPenalty(history: history)
        XCTAssertEqual(p1, p2, accuracy: 0.001)
    }
}
