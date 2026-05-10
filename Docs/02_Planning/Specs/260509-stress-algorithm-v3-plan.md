# Implementation Plan: Stress Algorithm v3

**Date:** 2026-05-09
**Strategy:** [260509-stress-algorithm-v3-strategy.md](./260509-stress-algorithm-v3-strategy.md)
**Brainstorm:** [260509-stress-algorithm-v3-brainstorm.md](../../01_Brainstorming/260509-stress-algorithm-v3-brainstorm.md)
**Formula:** [260509-stress-formula-spec.md](../../01_Brainstorming/260509-stress-formula-spec.md)
**Status:** Ready for Audit

---

## Overview

Replace the 4-factor v1 stress algorithm with a 13-driver v3 model that includes engagement penalties, multi-day pattern penalties, and a multiplicative HRV/RHR calibrator. Add `ManualDailyInput` SwiftData model with two daily overlays (morning/evening) so HK-denied or Watch-less users can fully populate the model. Surface the richer signal set in `StressView` via top-N driver cards, an engagement-gaps card, and a calibrator chip. Ship in three sequential phases, each independently buildable.

---

## Requirements

- Pure `computeStress(inputs:now:)` function — no I/O, no side effects
- 13 driver factors covering Tier A (foundational) / B (modulators) / C (subjective)
- Recovery bonuses (intervention, journal, mindful) capped at −10
- Tier D engagement penalty with linear time-of-day ramps (0–18 pts)
- Tier E multi-day pattern penalty (0–12 pts)
- Multiplicative calibrator [0.90, 1.15] using 14-day HRV/RHR baseline (≥5 valid days)
- Source priority: HK → ManualDailyInput → silent (factor `hasData: false`)
- Two daily overlays (morning ≥11:00 sleep; evening ≥19:00 screen/exercise/daylight)
- Activation guard — engagement penalty only applies when ≥1 driver has data
- Coverage-weighted confidence — replace `factorCoverage < 2` with weight-weighted formula
- 5-minute timer in foreground for engagement-ramp recompute
- No `StressReading` schema migration

---

## Architecture Changes

| Component | Path | Change |
|---|---|---|
| Scoring core | `WellPlate/Core/Services/StressScoring.swift` | Full rewrite — pure module with `StressInputs`, `StressResult`, `FactorPoints`, 13 driver fns, recovery, engagement, patterns, calibrator |
| Stress VM | `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | Build `StressInputs`, call `computeStress`, store `totalScore`/`calibratorMultiplier`/`engagementPenalty`/`patternPenalty` as published; add 5-min ticker; resolution priority for device factors |
| Factor display struct | `WellPlate/Models/StressModels.swift` | `StressFactorResult` consumes `FactorPoints`; `stressContribution` simplified (signed `points` already correct) |
| Mock | `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` | Extend to populate all v3 input fields + history bags + vitals baselines |
| Manual model | `WellPlate/Models/ManualDailyInput.swift` | NEW `@Model` |
| App entry | `WellPlate/App/WellPlateApp.swift` | Register `ManualDailyInput.self` in ModelContainer |
| Overlay coordinator | `WellPlate/Core/Services/DailyPromptCoordinator.swift` | NEW `@MainActor ObservableObject` |
| Overlay sheet | `WellPlate/Shared/Components/QuickCheckInSheet.swift` | NEW bottom sheet view |
| Root view | `WellPlate/App/RootView.swift` | Inject coordinator; `.scenePhase` observation; present sheet |
| Profile | `WellPlate/Features + UI/Tab/ProfileView.swift` | Add "Reset 'Don't ask again'" toggle |
| Stress view | `WellPlate/Features + UI/Stress/Views/StressView.swift` | Rebuild header (calibrator chip), top-5 driver cards, engagement-gaps card, all-factors disclosure, Quick Log button |
| Factor card | `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift` | Show signed `points` + tier badge |
| Stress sheet enum | (defined in `StressView.swift:12`) | Add `.allFactors` case |
| New components | `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift`, `.../CalibratorChip.swift` | NEW |
| Banner flag | `UserDefaults` key `wp.stress.v3AnnouncementShown` | One-time banner |

---

## Implementation Steps

### Phase 1 — Scoring Core (3–4 days)

#### 1.1 Define data structs (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** At the top of the rewritten file, declare:
  - `struct FactorPoints { let points: Double; let maxPoints: Double; let hasData: Bool; let detail: String; static let none = FactorPoints(points: 0, maxPoints: 0, hasData: false, detail: "No data") }`
  - `struct StressInputs` with sub-structs: `SleepInput`, `ExerciseInput`, `CaffeineInput`, `ScreenInput`, `DietInput`, `HydrationInput`, `CircadianInput`, `DaylightInput`, `FastingInput`, `RecoveryInput`, `HistoryInput`, `VitalsInput`, plus raw arrays (`mealLogs: [FoodLogEntry]`, `triggerLogs: [FoodLogEntry]`, `mood: MoodOption?`, `symptoms: [SymptomEntry]`, `goals: UserGoals`)
  - `struct StressResult { let score: Double; let factors: [FactorPoints]; let driverSum: Double; let recovery: Double; let engagementPenalty: Double; let patternPenalty: Double; let calibrator: Double; let confidence: Confidence; let raw: Double }`
  - `struct CalibratorInputs { let todayHRV: Double?; let hrvBaseline: Double?; let todayRHR: Double?; let rhrBaseline: Double? }`
- **Why:** Single source-of-truth for the formula's input/output shapes. Sub-types live next to the math, so adding a factor means updating one file.
- **Dependencies:** None.
- **Risk:** Low.

#### 1.2 Replace `Weights` enum (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Replace the existing `Weights` enum (sleep/exercise/diet/screenTime 35/25/20/20) with the v3 weight table:
  ```swift
  enum Weights {
      // Tier A
      static let sleep: Double = 20
      static let exercise: Double = 12        // can produce −3..+12
      static let caffeine: Double = 10
      static let screenTime: Double = 10
      static let diet: Double = 8
      // Tier B
      static let hydration: Double = 5
      static let circadian: Double = 5
      static let daylight: Double = 3
      static let mealTiming: Double = 4
      static let fasting: Double = 3
      static let eatingTriggers: Double = 5
      // Tier C
      static let mood: Double = 8             // −2..+8
      static let symptoms: Double = 7
      // Caps
      static let recoveryCap: Double = -10
      static let engagementCap: Double = 18
      static let patternCap: Double = 12
  }
  ```
- **Why:** Tier-A 60 / Tier-B 25 / Tier-C 15 = 100 driver budget per formula spec §1–§3.
- **Dependencies:** 1.1 complete.
- **Risk:** Low. Audit all `Weights.` usages — UI strings "/35" must not appear after this change.

#### 1.3 Implement Tier A factor functions (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §3.1–§3.5:
  - `static func sleepPoints(input: SleepInput?) -> FactorPoints`
  - `static func exercisePoints(input: ExerciseInput?) -> FactorPoints`
  - `static func caffeinePoints(input: CaffeineInput?) -> FactorPoints`
  - `static func screenTimePoints(input: ScreenInput?) -> FactorPoints`
  - `static func dietPoints(input: DietInput?, goals: UserGoals) -> FactorPoints`
- **Why:** Foundational drivers, 60% of the budget. Each is a pure piecewise function.
- **Dependencies:** 1.1, 1.2 complete.
- **Risk:** Medium. Threshold edge cases (e.g., `h == 7.0` exactly). Use `<` consistently for upper bounds.

#### 1.4 Implement Tier B factor functions (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §3.6–§3.11:
  - `static func hydrationPoints(input: HydrationInput?, goal: Int) -> FactorPoints`
  - `static func circadianPoints(input: CircadianInput?) -> FactorPoints`
  - `static func daylightPoints(input: DaylightInput?) -> FactorPoints`
  - `static func mealTimingPoints(logs: [FoodLogEntry]) -> FactorPoints`
  - `static func fastingPoints(input: FastingInput?) -> FactorPoints`
  - `static func eatingTriggerPoints(logs: [FoodLogEntry]) -> FactorPoints`
- **Why:** Modulators; 25% of the budget.
- **Dependencies:** 1.3 complete.
- **Risk:** Low. `mealTimingPoints` requires sorting logs by `createdAt`.

#### 1.5 Implement Tier C factor functions (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §3.12–§3.13:
  - `static func moodPoints(mood: MoodOption?) -> FactorPoints`
  - `static func symptomPoints(entries: [SymptomEntry]) -> FactorPoints`
- **Why:** Subjective tier; 15% of the budget.
- **Dependencies:** 1.4 complete.
- **Risk:** Low. `symptomPoints` must dedupe by `name` taking max severity per name.

#### 1.6 Implement recovery functions (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §4:
  - `static func interventionBonus(sessions: [InterventionSession]) -> Double`
  - `static func journalBonus(hasEntry: Bool) -> Double`
  - `static func mindfulBonus(hasMoodToday: Bool, hasMindfulSession: Bool) -> Double`
  - `static func recoveryTotal(_ inputs: RecoveryInput) -> Double` (caps at −10)
- **Why:** Recovery actions reduce stress; cap −10 prevents over-reward.
- **Dependencies:** 1.1 complete.
- **Risk:** Low.

#### 1.7 Implement engagement penalty (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §5:
  - `static func engagementPenalty(inputs: StressInputs, now: Date) -> Double`
  - Internally: define `Gap` struct with `max`, `tStart`, `tEnd`, `cond`; iterate the 5 gaps; apply linear `ramp(t, tStart, tEnd)`; cap sum at 18
  - Activation guard: return 0 if no Tier A–C factor has `hasData == true`
- **Why:** Time-ramped penalty for skipped logs. Must be smooth in `t`.
- **Dependencies:** 1.3–1.5 complete.
- **Risk:** Medium. Time-of-day extraction must use `Calendar.current.component(.hour, from:)`. Test at 16:59 vs 17:01 boundary.

#### 1.8 Implement pattern penalty (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §6:
  - `static func patternPenalty(history: HistoryInput) -> Double`
  - 4 predicates: `noFood3d`, `lowMood3d`, `highCoffee3d`, `noFast14d`
  - Each contributes its weight if true; cap at 12
- **Why:** Multi-day chronic patterns. Discrete by design.
- **Dependencies:** 1.1 complete.
- **Risk:** Low. `HistoryInput` must include 3 days of `WellnessDayLog`, 3 days of `[FoodLogEntry]` grouped by day, and `lastCompletedFastEnd: Date?`.

#### 1.9 Implement calibrator + baseline (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §7:
  - `static func baseline14Day(_ samples: [DailyMetricSample], excludingToday: Date) -> Double?` — returns `nil` if `< 5` valid days where `value > 0`
  - `static func calibrator(_ inputs: CalibratorInputs) -> Double` — `clamp(1 + 0.5·δ_HRV + 0.3·δ_RHR, 0.90, 1.15)`; returns 1.0 when both baselines are `nil`
- **Why:** Multiplicative calibration against personal baseline. Must collapse cleanly when no data.
- **Dependencies:** 1.1 complete.
- **Risk:** Low. Excluding today is `!Calendar.current.isDate($0.date, inSameDayAs: excludingToday)`.

#### 1.10 Implement confidence (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §8:
  - `static func confidence(factors: [FactorPoints]) -> Confidence`
  - `enum Confidence { case low, medium, high }` (move from `StressViewModel.Confidence` extension to here)
  - Coverage = Σ(maxPoints where hasData) / 100
- **Why:** Replaces v1's `factorCoverage < 2` with weighted coverage.
- **Dependencies:** 1.3–1.5 complete.
- **Risk:** Low.

#### 1.11 Implement `computeStress` orchestrator (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:**
  ```swift
  static func computeStress(inputs: StressInputs, now: Date) -> StressResult {
      let factors: [FactorPoints] = [
          sleepPoints(input: inputs.sleep),
          exercisePoints(input: inputs.exercise),
          caffeinePoints(input: inputs.caffeine),
          screenTimePoints(input: inputs.screen),
          dietPoints(input: inputs.diet, goals: inputs.goals),
          hydrationPoints(input: inputs.hydration, goal: inputs.goals.waterDailyCups),
          circadianPoints(input: inputs.circadian),
          daylightPoints(input: inputs.daylight),
          mealTimingPoints(logs: inputs.mealLogs),
          fastingPoints(input: inputs.fasting),
          eatingTriggerPoints(logs: inputs.triggerLogs),
          moodPoints(mood: inputs.mood),
          symptomPoints(entries: inputs.symptoms),
      ]
      let driverSum = factors.filter(\.hasData).reduce(0) { $0 + $1.points }
      let recovery = recoveryTotal(inputs.recovery)
      let engagement = engagementPenalty(inputs: inputs, now: now)
      let pattern = patternPenalty(history: inputs.history)
      let raw = max(0, driverSum + recovery + engagement + pattern)
      let cal = calibrator(inputs.vitals.calibratorInputs)
      let score = min(100, max(0, raw * cal))
      return StressResult(score: score, factors: factors, driverSum: driverSum,
                          recovery: recovery, engagementPenalty: engagement,
                          patternPenalty: pattern, calibrator: cal,
                          confidence: confidence(factors: factors), raw: raw)
  }
  ```
- **Why:** Single pure entry point.
- **Dependencies:** 1.3–1.10 complete.
- **Risk:** Low.

#### 1.12 Refactor `StressFactorResult` (File: `WellPlate/Models/StressModels.swift`)

- **Action:**
  - Add init `StressFactorResult(from: FactorPoints, title: String, icon: String, higherIsBetter: Bool)` that maps `FactorPoints.points` → `score`, `FactorPoints.maxPoints` → `maxScore`
  - Simplify `stressContribution`: with v3, `points` is already signed; `stressContribution = hasValidData ? points : 0`
  - Update `.neutral(...)` factory to take `maxScore: Double` parameter (no more hardcoded 25)
  - Keep `accentColor` and `progress` computed properties (they still work on `score / maxScore`)
- **Why:** Display struct now driven by formula's signed `points`. Removes the `higherIsBetter` flip ambiguity.
- **Dependencies:** 1.1 complete.
- **Risk:** Medium — every callsite of `.neutral(...)` and `stressContribution` must be audited. Use `grep`.

#### 1.13 Refactor `StressViewModel.loadData()` (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

- **Action:**
  - Add new `@Published` props: `var calibratorMultiplier: Double = 1.0`, `var engagementPenaltyValue: Double = 0`, `var patternPenaltyValue: Double = 0`
  - Convert `totalScore` from computed to stored `@Published var totalScore: Double = 0`
  - Add new fetches in `loadData()`:
    - Today's `[SymptomEntry]` (start of today predicate)
    - Today's `JournalEntry` (presence check)
    - Today's completed `[InterventionSession]` (`completed == true && startedAt >= startOfToday`)
    - Last-3-day `[WellnessDayLog]` (for patterns)
    - Last-3-day `[FoodLogEntry]` grouped by day (for `noFood3d`)
    - Most recent completed `FastingSession.actualEndAt` (for `noFast14d`)
    - Today's `ManualDailyInput` (P2 will populate; in P1 always nil)
  - Add resolution helpers: `resolveSleep`, `resolveExercise`, `resolveScreen`, `resolveDaylight`, `resolveCircadian` returning the input sub-structs from HK or manual
  - Build `StressInputs` from all sources
  - Call `let result = StressScoring.computeStress(inputs: inputs, now: Date())`
  - Publish: `totalScore = result.score`, `calibratorMultiplier = result.calibrator`, etc.
  - Build `StressFactorResult` array from `result.factors` for UI; expose as `@Published var allFactors: [StressFactorResult] = []`
  - Update `topStressors` computation to sort by `factor.stressContribution` desc and take prefix(5) (was 2)
- **Why:** Wire the pure `computeStress` to the published UI state.
- **Dependencies:** Phase 1.1–1.12 complete.
- **Risk:** High. Largest single change. Subdivide commits if needed.

#### 1.14 Add `recompute()` and 5-minute ticker (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

- **Action:**
  - Cache the last-built `StressInputs` (excluding `now`-dependent values)
  - `func recompute()` — rebuild `StressInputs` from cached HK + fresh SwiftData fetches (mood, water, food, symptoms — cheap), call `computeStress`, publish
  - Add `private var tickerCancellable: AnyCancellable?`
  - `func startEngagementTicker()` — `Timer.publish(every: 300, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.recompute() }`
  - `func stopEngagementTicker()` — cancel
  - `recompute()` is called by existing `refreshDietFactor()`, `refreshScreenTimeOnly()`, etc. (rename them to `recomputeAfter*Change` for clarity)
  - Update `loadCurrentStress(source:)` to log `result.score` not the deprecated computed property
- **Why:** Engagement-ramp `E(t)` advances even when no input changes. Timer keeps the displayed score honest.
- **Dependencies:** 1.13 complete.
- **Risk:** Medium. Timer must cancel on `.scenePhase != .active` to avoid background battery drain.

#### 1.15 Wire ticker lifecycle (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:**
  - In `StressView.body`, observe `@Environment(\.scenePhase)` and call `viewModel.startEngagementTicker()` / `stopEngagementTicker()` on transitions
  - Alternative: hook into `onAppear` / `onDisappear` for simpler scope
- **Why:** Battery hygiene.
- **Dependencies:** 1.14 complete.
- **Risk:** Low.

#### 1.16 Drop scoring contributions from vitals (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

- **Action:**
  - Remove any usage of `heartRateHistory`/`bp*History`/`respiratoryRateHistory` in scoring path (none should exist per current code, verify)
  - Confirm `hrvHistory` and `restingHRHistory` are used only by `baseline14Day(...)` and not in `computeStress` directly
- **Why:** Indicators must not be drivers (formula spec §1).
- **Dependencies:** 1.13 complete.
- **Risk:** Low (mostly verification).

#### 1.17 Extend mock snapshot (File: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`)

- **Action:**
  - Add fields for: `mood: MoodOption?`, `todaySymptoms: [SymptomEntry]`, `todayJournal: JournalEntry?`, `todayInterventions: [InterventionSession]`, `recentWellnessLogs: [WellnessDayLog]`, `recentFoodLogs: [FoodLogEntry]`, `lastCompletedFastEnd: Date?`, `hrv14DayBaseline: Double?`, `rhr14DayBaseline: Double?`
  - Add 4 mock variants: `.fullyLoggedBalancedDay`, `.fullyLoggedBadDay`, `.disengagedBadDay21h`, `.dayOneNoData`
  - Each must populate enough of `StressInputs` to satisfy the validation checklist
- **Why:** Without mock parity, P1 exit gate fails.
- **Dependencies:** 1.1 complete.
- **Risk:** Medium. Easy to forget a field; guard with a unit test that runs all variants through `computeStress`.

#### 1.18 P1 build + smoke verification

- **Action:**
  - Run all 4 build targets: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Repeat for `ScreenTimeMonitor`, `ScreenTimeReport`, `WellPlateWidget`
  - On simulator, manually toggle mock variants via debug card; verify scores match validation checklist (formula spec §14)
- **Why:** P1 exit gate.
- **Dependencies:** 1.17 complete.
- **Risk:** Low. Failing this gate means re-fix before P2.

---

### Phase 2 — Manual Fallback + Daily Overlays (3–4 days)

#### 2.1 Create `ManualDailyInput` model (File: `WellPlate/Models/ManualDailyInput.swift` — NEW)

- **Action:** Create file with:
  ```swift
  import Foundation
  import SwiftData

  @Model final class ManualDailyInput {
      @Attribute(.unique) var day: Date
      var sleepHours: Double?
      var sleepQuality: Int?            // 1–5
      var bedtime: Date?
      var wakeTime: Date?
      var screenTimeHours: Double?
      var heavyEveningScreens: Bool?
      var exerciseMinutes: Int?
      var amDaylightOutside: Bool?
      var morningAskedAt: Date?
      var eveningAskedAt: Date?
      var createdAt: Date

      init(day: Date) {
          self.day = Calendar.current.startOfDay(for: day)
          self.createdAt = .now
      }
  }
  ```
- **Why:** Persistence layer for manual fallback.
- **Dependencies:** None.
- **Risk:** Low.

#### 2.2 Register in ModelContainer (File: `WellPlate/App/WellPlateApp.swift:34`)

- **Action:** Append `ManualDailyInput.self` to the `.modelContainer(for: [...])` array.
- **Why:** SwiftData must know the schema.
- **Dependencies:** 2.1 complete.
- **Risk:** Low. Existing models continue working.

#### 2.3 Implement `DailyPromptCoordinator` (File: `WellPlate/Core/Services/DailyPromptCoordinator.swift` — NEW)

- **Action:** Create:
  ```swift
  @MainActor final class DailyPromptCoordinator: ObservableObject {
      enum PromptKind: Identifiable {
          case morning(MorningGaps)
          case evening(EveningGaps)
          var id: String { ... }
      }
      struct MorningGaps { let needsSleep: Bool }
      struct EveningGaps { let needsScreen: Bool; let needsExercise: Bool; let needsDaylight: Bool }

      @Published var pendingPrompt: PromptKind? = nil

      private let healthService: HealthKitServiceProtocol
      private let modelContext: ModelContext
      private let userDefaults: UserDefaults

      func evaluateOnAppForeground(now: Date) async {
          // 1. Check "don't ask again" UserDefaults
          // 2. Suppress prompts within 24h of onboarding completion
          // 3. Resolve today's ManualDailyInput
          // 4. If now >= 11:00 and !morningAsked && hk_sleep == nil && manual.sleepHours == nil → set .morning
          // 5. Else if now >= 19:00 && !eveningAsked && (any of hk_screen/exercise/daylight nil and corresponding manual nil) → set .evening
      }
      func recordSkip(_ kind: PromptKind) { ... }
      func recordSave(_ kind: PromptKind, values: ManualValues) { ... }
      func disableForever() { userDefaults.set(true, forKey: "wp.stress.dontAskAgain") }
  }
  ```
- **Why:** Centralizes overlay decision logic; ViewModel doesn't need to know about prompts.
- **Dependencies:** 2.1, 2.2 complete.
- **Risk:** Medium. Time-of-day comparison must use `Calendar.current.component(.hour, ...)`.

#### 2.4 Implement `QuickCheckInSheet` (File: `WellPlate/Shared/Components/QuickCheckInSheet.swift` — NEW)

- **Action:** Create a `View` taking a binding to `PromptKind?` and a coordinator. Render:
  - Morning form: hours `Slider` (4.0–12.0), quality `Picker.segmented` (1–5), optional bedtime/wake `DatePicker`
  - Evening form: screen hours `Stepper`, heavy-evening `Toggle`, exercise minutes `Stepper`, AM daylight `Toggle` — fields hidden when corresponding HK populated
  - Three buttons: Save · Skip for today · Don't ask again
  - Use `.r(.headline, .semibold)` font and `.appShadow(...)` per CLAUDE.md
  - `.presentationDetents([.medium])`
- **Why:** Single bottom-sheet UI, time-of-day variant chosen by `PromptKind`.
- **Dependencies:** 2.3 complete.
- **Risk:** Medium. SwiftUI form state binding for partial fields. Use `@State` locally; only persist on Save.

#### 2.5 Wire coordinator into RootView (File: `WellPlate/App/RootView.swift`)

- **Action:**
  - Add `@StateObject private var promptCoordinator = DailyPromptCoordinator(...)` (init with `HealthKitServiceFactory.shared`, `modelContext`, `.standard`)
  - Add `@Environment(\.scenePhase) private var scenePhase`
  - In `MainTabView` branch only, attach:
    ```swift
    .sheet(item: $promptCoordinator.pendingPrompt) { kind in
        QuickCheckInSheet(kind: kind, coordinator: promptCoordinator)
    }
    .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .active && !showSplash && !showOnboarding {
            Task { await promptCoordinator.evaluateOnAppForeground(now: Date()) }
        }
    }
    ```
- **Why:** Single global presenter. Per CLAUDE.md, only one `.sheet(item:)` per feature; coordinator owns it.
- **Dependencies:** 2.3, 2.4 complete.
- **Risk:** Medium. `RootView` currently has no `@Environment(\.modelContext)`. Add it. Also confirm `scenePhase` doesn't fire during onboarding.

#### 2.6 Add resolution priority to `StressViewModel` (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

- **Action:**
  - In `loadData()`, after fetching HK summaries, fetch today's `ManualDailyInput`
  - Implement helpers (private):
    ```swift
    private func resolveSleep(hk: DailySleepSummary?, manual: ManualDailyInput?) -> SleepInput?
    private func resolveScreen(autoHours: Double?, manual: ManualDailyInput?) -> ScreenInput?
    private func resolveExercise(steps: Double?, energy: Double?, manual: ManualDailyInput?) -> ExerciseInput?
    private func resolveDaylight(hkMinutes: Double?, manual: ManualDailyInput?) -> DaylightInput?
    private func resolveCircadian(hkSummaries: [DailySleepSummary], manualHistory: [ManualDailyInput]) -> CircadianInput?
    ```
  - For sleep manual: derive `deepHours` from `sleepQuality` (1→0.25h, 3→0.75h, 5→1.33h)
  - For exercise manual: convert `exerciseMinutes` to step-equivalent `Double(minutes * 100)` for the `activity = max(steps/7000, energy/400)` calculation; or expose a separate `manualMinutes` field on `ExerciseInput` and treat in `exercisePoints`
- **Why:** HK > Manual > silent priority chain (formula spec §3).
- **Dependencies:** 2.1, 1.13 complete.
- **Risk:** Medium. Test all 8 combinations of HK-present/absent + manual-present/absent for each factor.

#### 2.7 Observe ManualDailyInput changes (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

- **Action:** When coordinator saves a `ManualDailyInput` row, the ViewModel must `recompute()`. Two options:
  - (a) Add a `@Published` notification on `DailyPromptCoordinator` that `StressViewModel` observes via Combine
  - (b) Re-trigger `loadData()` on `.scenePhase = .active` (which already happens in `StressView.onAppear`)
  - **Pick (a)** — cleaner separation; coordinator emits `.manualInputSaved`; ViewModel listens and calls `recompute()`
- **Why:** Score must update immediately after manual entry.
- **Dependencies:** 2.3, 2.6 complete.
- **Risk:** Low.

#### 2.8 Add Profile toggle for "Reset prompts" (File: `WellPlate/Features + UI/Tab/ProfileView.swift`)

- **Action:** Add a row in the settings list:
  - Label: "Daily check-in prompts"
  - Toggle backed by `UserDefaults.standard.bool(forKey: "wp.stress.dontAskAgain")` inverted
  - When toggled OFF → ON, also clear today's `morningAskedAt`/`eveningAskedAt` so prompts can re-fire
- **Why:** Recoverability if user accidentally hits "Don't ask again."
- **Dependencies:** 2.3 complete.
- **Risk:** Low.

#### 2.9 P2 build + smoke verification

- **Action:**
  - Build all 4 targets
  - On simulator: deny HK; open app at simulated time 11:30 → morning prompt fires; save 6h sleep + quality 3; verify `p_sleep` > 0 in stress score
  - Open app at 19:30 with no manual data → evening prompt fires
  - Tap "Skip for today" → close → reopen at 20:00 → no prompt
  - Tap "Don't ask again" → reopen → no prompt; toggle in Profile to re-enable → prompt returns next day
- **Why:** P2 exit gate.
- **Dependencies:** 2.1–2.8 complete.
- **Risk:** Low.

---

### Phase 3 — UI Surfacing (3–4 days)

#### 3.1 Add new `StressSheet` cases (File: `WellPlate/Features + UI/Stress/Views/StressView.swift:12`)

- **Action:**
  - Add `.allFactors` case (opens disclosure sheet)
  - Add `.manualLog` case (opens `QuickCheckInSheet` outside auto-prompt times)
- **Why:** Users want to access their full factor list and re-enter manual data on demand.
- **Dependencies:** Phase 2 complete.
- **Risk:** Low.

#### 3.2 Build `CalibratorChip` component (File: `WellPlate/Features + UI/Stress/Components/CalibratorChip.swift` — NEW)

- **Action:** A small pill view showing:
  - "HRV +X% above baseline" (calibrator < 1.0, vitals good)
  - "Vitals strain detected (+Y%)" (calibrator > 1.0)
  - "Vitals normal" (calibrator == 1.0 with baseline present)
  - "Watch-less" or "Calibration ready in N days" (no baseline)
  - Use `.r(.caption, .semibold)` and adaptive blue tint
- **Why:** Surfaces the calibrator's effect, otherwise invisible.
- **Dependencies:** 1.13 complete.
- **Risk:** Low.

#### 3.3 Build `EngagementGapsCard` component (File: `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift` — NEW)

- **Action:** Card visible when `viewModel.engagementPenaltyValue > 0`. Lists active gaps with:
  - Icon + label ("Mood not logged", "0 glasses of water", etc.)
  - Current penalty value ("+3 pts")
  - CTA button per gap that opens the appropriate logger (Mood sheet, Water detail, Food log)
- **Why:** Direct call-to-action to close gaps. Users see exactly what's costing them.
- **Dependencies:** 1.13 complete.
- **Risk:** Medium. CTAs must navigate to existing flows (mood: `MoodCheckInCard`; water: `WaterDetailView`; food: tab switch + meal log).

#### 3.4 Refactor `StressView` header (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:**
  - Below the score gauge, add a horizontal row containing `CalibratorChip` + confidence badge
  - Update confidence text to use new weight-weighted bands ("X of 13 factors logged")
- **Why:** Header is the user's anchor for understanding the score.
- **Dependencies:** 3.2 complete.
- **Risk:** Low.

#### 3.5 Replace fixed 4-card grid with top-N drivers (File: `WellPlate/Features + UI/Stress/Views/StressView.swift:809`)

- **Action:**
  - Replace the hardcoded `[exerciseFactor, sleepFactor, dietFactor, screenTimeFactor]` array with `viewModel.allFactors.filter(\.hasValidData).sorted { $0.stressContribution > $1.stressContribution }.prefix(5)`
  - Each card opens an appropriate detail sheet — for v3-only factors (mood, symptoms, hydration, etc.) the sheet routes to existing detail views (e.g., `WaterDetailView`, `SymptomHistoryView`, `MoodCheckInCard` modal)
  - Map factor `title` → sheet via a switch in the card's `onTap`
- **Why:** Top contributors change daily; static 4 cards waste space.
- **Dependencies:** 3.1 complete.
- **Risk:** High. Many sheet routes to wire. Use a `switch factor.title` mapping to existing `StressSheet` cases.

#### 3.6 Add Recovery section (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:** Below the top-5 drivers, add a "Recovery" section showing:
  - "−6 from 2 reset sessions" (if `interventionBonus < 0`)
  - "−2 journal written" (if applicable)
  - "−2 mindful check-in"
- **Why:** Visible recovery rewards reinforce the behavior loop.
- **Dependencies:** 1.13 complete.
- **Risk:** Low.

#### 3.7 Add Engagement Gaps section (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:** Insert `EngagementGapsCard` between top-5 drivers and Recovery section. Hidden when `engagementPenaltyValue == 0`.
- **Why:** Per strategy §3.3.
- **Dependencies:** 3.3 complete.
- **Risk:** Low.

#### 3.8 Add "All factors" disclosure sheet (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:**
  - Footer button "View all factors" opens `StressSheet.allFactors`
  - Sheet renders `viewModel.allFactors` grouped by tier (Tier A — Foundational, Tier B — Modulators, Tier C — Subjective)
  - Each row shows `points / maxPoints` bar (with sign)
- **Why:** Deep view for power users.
- **Dependencies:** 3.1 complete.
- **Risk:** Low.

#### 3.9 Add persistent Quick Log button (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:** Floating or anchored button at the bottom of the scroll content opening `StressSheet.manualLog`. Sheet routes to `QuickCheckInSheet` (re-using P2's view).
- **Why:** Users who dismissed overlays still need a way in.
- **Dependencies:** 2.4, 3.1 complete.
- **Risk:** Low.

#### 3.10 Update `StressFactorCardView` (File: `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift`)

- **Action:**
  - Show signed `points` (e.g., "+8" red, "−2" green, "0" neutral)
  - Add a small tier badge (A / B / C) in top-right corner
  - Keep existing layout otherwise
- **Why:** Signed points are more honest than abstract progress bars.
- **Dependencies:** 1.12 complete.
- **Risk:** Low.

#### 3.11 One-time "Algorithm updated" banner (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:**
  - Read `UserDefaults.standard.bool(forKey: "wp.stress.v3AnnouncementShown")`
  - If false on `onAppear`, show a dismissible banner at top: "Stress score now considers mood, symptoms, hydration, and 9 other signals. Tap to learn more."
  - On dismiss, set flag to `true`
  - Optional: tapping opens an info sheet with the factor list
- **Why:** Soften the v1→v3 step change for existing users.
- **Dependencies:** None (UI-only flag).
- **Risk:** Low.

#### 3.12 Verify Home + Widget integration (Files: `WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift`, `WellPlate/Widgets/SharedStressData.swift`)

- **Action:**
  - Confirm `StressSparklineStrip` reads `viewModel.totalScore` (now stored, not computed) and renders correctly
  - Confirm `WidgetRefreshHelper.refreshStress(viewModel:)` extracts the same field; no widget code changes expected
- **Why:** Defensive — refactoring `totalScore` from computed to stored could miss a binding.
- **Dependencies:** 1.13 complete.
- **Risk:** Low (mostly verification).

#### 3.13 P3 build + visual verification

- **Action:**
  - Build all 4 targets
  - On simulator with mock data, toggle through all 4 mock variants and visually verify:
    - Top-5 driver cards reorder
    - Engagement-gaps card appears/disappears
    - Calibrator chip reflects vitals state
    - "View all factors" disclosure shows tier groupings
    - Quick Log button works outside auto-prompt windows
  - Check `StressSparklineStrip` and Widget render correctly
- **Why:** P3 exit gate.
- **Dependencies:** 3.1–3.12 complete.
- **Risk:** Low.

---

## Testing Strategy

### Build verification

After each phase, build all 4 targets per CLAUDE.md:

```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

### Manual verification flows

| Flow | Expected outcome | Phase |
|---|---|---|
| Mock "fully-logged-balanced-day" | Score = "Excellent", calibrator ≤ 1 | P1 |
| Mock "fully-logged-bad-day" | Score = "Very High" | P1 |
| Mock "disengaged-day-21h" | Score = "High", engagement penalty visible (P3) | P1 + P3 |
| Mock "day-one-no-data" | Score hidden, "Log to see your stress" message | P1 |
| Log mood `awful` after 21:00 in real flow | Score increases by 1–3 | P1 |
| Log mood `great` after 21:00 in real flow | Score decreases by 9–11 | P1 |
| HK denied + simulated time 11:30 | Morning prompt fires | P2 |
| HK denied + simulated time 19:30 | Evening prompt fires | P2 |
| Skip for today → reopen later | No re-prompt | P2 |
| Don't ask again → toggle in Profile | Prompt returns next day | P2 |
| First launch within 24h of onboarding | No prompts fire | P2 |
| Mock with HRV 25% below baseline | Calibrator chip shows "+12% vitals strain" | P3 |
| Tap engagement gap CTA | Routes to corresponding logger | P3 |
| First app open after v3 ships | Banner shown once; dismissible | P3 |

### Validation checklist (formula spec §14)

Implement as XCTest cases in a new `WellPlateTests/StressScoringTests.swift` (verify if test target exists; if not, report as unverified per CLAUDE.md):

- [ ] `S(zero_input, t)` returns confidence `.low` (score hidden)
- [ ] `S(perfect_day, t) ≤ 5` (drivers good, recovery max)
- [ ] `S(worst_logged_day, t) == 100` (clamping)
- [ ] Logging mood `great` strictly reduces `S` vs `nil`
- [ ] Logging water 8 strictly reduces `S` vs `0` after 18:00
- [ ] Manual sleep entry produces same `p_sleep` as HK with equivalent values
- [ ] `calibrator(emptyVitals)` returns 1.0
- [ ] `engagementPenalty` returns 0 before `tStart`
- [ ] `patternPenalty` stable across consecutive `recompute()` calls within same day

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `StressFactorResult` callsites broken by `.neutral(...)` signature change | High | Step 1.12 — grep all `.neutral(` callsites and update before building |
| `totalScore` becoming stored breaks `WidgetRefreshHelper` snapshot timing | Medium | Step 3.12 — verify widget snapshot reads new published value |
| Engagement timer drains battery in foreground | Low | 5-min interval; auto-cancel on `.scenePhase != .active` (1.15) |
| `Calendar.current` locale issues on `component(.hour, from:)` | Low | Use `Calendar.current` with system timezone — matches user's expected day boundary |
| `ManualDailyInput` schema added to existing app breaks SwiftData migration | Medium | Pure additive change; SwiftData handles automatically. Verify on simulator with existing data |
| `RootView` `@Environment(\.modelContext)` not yet present | Medium | Step 2.5 — add it; coordinator init takes context as argument |
| HK auth race condition — coordinator queries before auth completes | Medium | Coordinator's `evaluateOnAppForeground` checks `healthService.isAuthorized`; if false, skip prompts entirely (HK might populate later) |
| Mock snapshot drift between scoring and view | Medium | Step 1.17 — single source struct; refactor incrementally with build checks |
| P3 sheet routing for v3-only factors (mood, hydration) lacking detail views | Medium | Step 3.5 — pre-audit which `StressSheet` cases need to be added; use existing detail views where possible |
| `Combine` observation between coordinator and ViewModel creates retain cycle | Low | Use `[weak self]` in sink; cancel on deinit |

---

## Success Criteria

### Phase 1 (Scoring core)

- [ ] All 4 build targets green
- [ ] All 4 mock snapshot variants produce expected score ranges
- [ ] Logging mood/water/symptoms in real app changes the score within seconds
- [ ] Existing `StressReading` rows load without migration error
- [ ] No `.neutral(...)` usage with hardcoded `25` remains

### Phase 2 (Manual + overlays)

- [ ] All 4 build targets green
- [ ] HK-denied user can complete morning prompt → score uses manual sleep
- [ ] HK-denied user can complete evening prompt → score uses manual screen/exercise/daylight
- [ ] "Skip for today" prevents re-prompt until next day
- [ ] "Don't ask again" persists; settings toggle reverses it
- [ ] First-launch grace period (24h post-onboarding) honored
- [ ] Watch-equipped user with full HK never sees overlays

### Phase 3 (UI)

- [ ] All 4 build targets green
- [ ] Top-5 driver cards reorder on input change
- [ ] Engagement-gaps card appears with active gaps; CTAs route correctly
- [ ] Calibrator chip reflects vitals state (4 modes)
- [ ] "View all factors" disclosure groups by tier
- [ ] Persistent Quick Log button accessible
- [ ] One-time announcement banner shown on first open after v3
- [ ] `StressSparklineStrip` and Widget render correctly

### Cumulative

- [ ] User logging mood `awful` after 21:00 strictly raises stress vs not logging
- [ ] User logging water 8/8 strictly lowers stress vs not logging
- [ ] User with 5 logged symptoms (severity 6+) sees "High" or "Very High"
- [ ] HK-denied user can fully populate the model via 2 daily overlays
- [ ] Watch-less user sees calibrator collapse to 1.0, no error state
- [ ] Day-1 user (no data, no history) does not see a stress score (low confidence)

---

## Next step

→ `/develop audit Docs/02_Planning/Specs/260509-stress-algorithm-v3-plan.md` — review for issues, loopholes, and risks before checklist generation.
