# Implementation Plan: Stress Algorithm v3 (RESOLVED)

**Date:** 2026-05-09
**Original plan:** [260509-stress-algorithm-v3-plan.md](./260509-stress-algorithm-v3-plan.md)
**Audit report:** [260509-stress-algorithm-v3-plan-audit.md](../../03_Audits/260509-stress-algorithm-v3-plan-audit.md)
**Strategy:** [260509-stress-algorithm-v3-strategy.md](./260509-stress-algorithm-v3-strategy.md)
**Brainstorm:** [260509-stress-algorithm-v3-brainstorm.md](../../01_Brainstorming/260509-stress-algorithm-v3-brainstorm.md)
**Formula:** [260509-stress-formula-spec.md](../../01_Brainstorming/260509-stress-formula-spec.md)
**Status:** Ready for Checklist

---

## Audit Resolution Summary

| ID | Severity | Resolution | Where |
|---|---|---|---|
| **C1** | CRITICAL | Sugar dropped; use carbs as proxy. Re-tune thresholds against `UserGoals.carbsGoalGrams=220`. Documented as v3 limitation. | §1.3 (diet) |
| **C2** | CRITICAL | Proposed `hasData` policy table approved verbatim and embedded as §0.1 (`hasData` policy). Resolves H9 too. | §0.1 |
| **C3** | CRITICAL | Coordinator owned by `WellPlateApp` (single source); injected into RootView and downstream via `.environmentObject(...)`. | §2.5 |
| **H1** | HIGH | `recompute()` always re-fetches cheap SwiftData (mood/water/food/symptoms/journal/interventions); reuses last HK fetch only. Documented in §1.14. | §1.14 |
| **H2** | HIGH | Engagement ticker wired at app/scene level (`WellPlateApp`/`RootView` `.scenePhase`), not `StressView`. | §1.15 |
| **H3** | HIGH | `StressFactorResult.id: String = title`. Stable identity across recomputes. | §1.12 |
| **H4** | HIGH | Verify test scheme wiring before P1; add `StressScoringTests.swift` with validation cases. | §1.18b (new) |
| **H5** | HIGH | Add `onboardingCompletedAt: Date?` to `UserProfileManager`; set in `OnboardingCompletionPage`. Legacy users (nil) get no grace. | §2.0 (new) |
| **H6** | HIGH | Extend `MockHealthKitService` to project multi-day HRV/RHR samples; verify `MockDataInjector` and seeded JSON unaffected. | §1.17 |
| **H7** | HIGH | `activeFastHours` derived via direct SwiftData fetch (`FastingSession` where `actualEndAt == nil`); no `FastingService` API change. | §1.13 |
| **H8** | HIGH | Approved CTA routing matrix: Mood → modal `MoodCheckInSheet` wrapping existing card; Water → tab + `WaterDetailView`; Food → tab + `MealLogView`; Steps → tab to Burn. | §3.3 |
| **H9** | HIGH | Resolved by C2 — caffeine `hasData` tied to today's `WellnessDayLog` row existence. | §0.1 |
| M1 | MEDIUM | Apply `max(goal, 1)` guard to hydration, diet (carbs/protein), exercise activity ratios. | §1.3, §1.4 |
| M2 | MEDIUM | Mock mode unified — add `buildInputsFromMockSnapshot(_:)` so `computeStress` runs through one pipeline. | §1.13 |
| M3 | MEDIUM | `eveningHours = heavyEveningScreens == true ? 2.0 : 0.0` in `resolveScreen`. | §2.6 |
| M4 | MEDIUM | Sub-struct field lists for `VitalsInput`, `HistoryInput`, `SleepInput`, etc. specified inline in §1.1. | §1.1 |
| M5 | MEDIUM | Keep existing names; `refreshDietFactor()` etc. become thin shims calling `recompute()`. Zero callsite churn. | §1.14 |
| M6 | MEDIUM | Move `Confidence` to `StressScoring`; add `typealias Confidence = StressScoring.Confidence` in `StressViewModel` for source compat. | §1.10 |
| M7 | MEDIUM | Toggle placed in a "Notifications & Prompts" section (create if absent) below existing Goals. | §2.8 |
| M8 | MEDIUM | `low_steps` cond = `steps != nil && steps! < 2000`. Nil HK → no penalty. | §1.7 |
| M9 | MEDIUM | `low_mood_3d` predicate uses `MoodOption` enum cases (refactor-safe), not raw value. | §1.8 |
| M10 | MEDIUM | `baseline14Day` adds defensive `$0.date < startOfToday` filter. | §1.9 |
| M11 | MEDIUM | `caffeinePoints` uses `mgPerCup = type?.caffeineMg ?? 80` with comment for legacy data. | §1.3 |
| M12 | MEDIUM | Banner copy drafted: *"Your stress score now considers mood, hydration, symptoms, and more — 13 factors total. Vitals like HRV are used to calibrate accuracy against your personal baseline."* | §3.11 |
| L1 | LOW | `ManualDailyInput` separate from `WellnessDayLog` — accepted; design rationale noted. | §2.1 |
| L2 | LOW | Engagement function timezone note added as code comment. | §1.7 |
| L3 | LOW | Factor `title → sheet` mapping switch accepted for v3. | §3.5 |

**Verdict:** ALL RESOLVED — 12 high-priority and 12 medium issues fixed inline.

---

## Overview

Replace the 4-factor v1 stress algorithm with a 13-driver v3 model that includes engagement penalties, multi-day pattern penalties, and a multiplicative HRV/RHR calibrator. Add `ManualDailyInput` SwiftData model with two daily overlays (morning/evening) so HK-denied or Watch-less users can fully populate the model. Surface the richer signal set in `StressView` via top-N driver cards, an engagement-gaps card, and a calibrator chip. Ship in three sequential phases, each independently buildable.

---

## §0.1 `hasData` Policy Table <!-- RESOLVED: C2 — embedded approved policy -->

This policy is the **single source of truth** for `H_f` per factor. Every factor function must follow it.

| Factor | `hasData = true` when |
|---|---|
| Sleep | HK summary present OR `manual.sleepHours != nil` |
| Exercise | (HK steps>0 OR HK energy>0) OR `manual.exerciseMinutes != nil` |
| Caffeine | Today's `WellnessDayLog` row exists (any user interaction) |
| Screen time | ScreenTime auto-detected reading present OR `manual.screenTimeHours != nil` |
| Diet | ≥1 `FoodLogEntry` today |
| Hydration | Today's `WellnessDayLog` row exists |
| Circadian | `circadianResult.hasEnoughData == true` |
| Daylight | HK minutes>0 OR `manual.amDaylightOutside != nil` |
| Meal timing | ≥1 `FoodLogEntry` today |
| Fasting | `FastingSchedule` exists for user (configured ≠ `.notConfigured`) |
| Eating triggers | ≥1 `FoodLogEntry` today |
| Mood | `WellnessDayLog.moodRaw != nil` |
| Symptoms | always `true` (zero is meaningful — "I have no symptoms today") |

This policy is also added to formula spec as §3.14.

---

## Requirements

- Pure `computeStress(inputs:now:)` function — no I/O, no side effects
- 13 driver factors covering Tier A / B / C
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
| Stress VM | `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | Build `StressInputs`, call `computeStress`, store published results, 5-min ticker, resolution priority |
| Factor display struct | `WellPlate/Models/StressModels.swift` | `StressFactorResult` consumes `FactorPoints`; `id: String = title` <!-- RESOLVED: H3 --> |
| Mock | `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` | Extend with v3 inputs + multi-day baselines |
| Mock HK service | `WellPlate/Core/Services/MockHealthKitService.swift` | Project multi-day HRV/RHR series from snapshot <!-- RESOLVED: H6 --> |
| Manual model | `WellPlate/Models/ManualDailyInput.swift` | NEW `@Model` |
| App entry | `WellPlate/App/WellPlateApp.swift` | Register `ManualDailyInput.self`; own `DailyPromptCoordinator` `@StateObject`; wire engagement ticker via scenePhase <!-- RESOLVED: C3, H2 --> |
| Coordinator | `WellPlate/Core/Services/DailyPromptCoordinator.swift` | NEW `@MainActor ObservableObject`; passed via `.environmentObject` <!-- RESOLVED: C3 --> |
| Overlay sheet | `WellPlate/Shared/Components/QuickCheckInSheet.swift` | NEW bottom sheet view |
| Root view | `WellPlate/App/RootView.swift` | Read coordinator via `@EnvironmentObject`; observe scenePhase; present sheet |
| Profile + onboarding | `WellPlate/Features + UI/Tab/ProfileView.swift`, `WellPlate/Features + UI/Onboarding/OnboardingCompletionPage.swift` | Toggle in "Notifications & Prompts" section <!-- RESOLVED: M7 -->; persist `onboardingCompletedAt` <!-- RESOLVED: H5 --> |
| User profile | `WellPlate/Core/Services/UserProfileManager.swift` | Add `onboardingCompletedAt: Date?` <!-- RESOLVED: H5 --> |
| Stress view | `WellPlate/Features + UI/Stress/Views/StressView.swift` | Rebuild header (calibrator chip), top-5 driver cards, engagement-gaps card, all-factors disclosure, Quick Log button |
| Factor card | `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift` | Show signed `points` + tier badge |
| Stress sheet enum | `WellPlate/Features + UI/Stress/Views/StressView.swift:12` | Add `.allFactors`, `.manualLog`, `.mood` cases |
| New components | `EngagementGapsCard.swift`, `CalibratorChip.swift`, `MoodCheckInSheet.swift` | NEW (last one wraps existing card for modal use) <!-- RESOLVED: H8 --> |
| Tests | `WellPlateTests/StressScoringTests.swift` | NEW — verify scheme wiring first <!-- RESOLVED: H4 --> |
| Banner flag | `UserDefaults` key `wp.stress.v3AnnouncementShown` | One-time banner |

---

## Implementation Steps

### Phase 1 — Scoring Core (3–4 days)

#### 1.1 Define data structs (File: `WellPlate/Core/Services/StressScoring.swift`)

<!-- RESOLVED: M4 — sub-struct fields specified inline -->

- **Action:** At the top of the rewritten file, declare:
  ```swift
  struct FactorPoints {
      let points: Double
      let maxPoints: Double
      let hasData: Bool
      let detail: String
      static let none = FactorPoints(points: 0, maxPoints: 0, hasData: false, detail: "No data")
  }

  struct SleepInput { let totalHours: Double; let deepHours: Double; let source: Source }
  struct ExerciseInput { let steps: Double?; let energy: Double?; let manualMinutes: Int?; let source: Source }
  struct CaffeineInput { let cups: Int; let type: CoffeeType?; let hasWellnessRow: Bool }
  struct ScreenInput { let totalHours: Double; let eveningHours: Double?; let source: Source }
  struct DietInput { let protein: Double; let fiber: Double; let carbs: Double; let fat: Double; let hasLogs: Bool }
  struct HydrationInput { let glasses: Int; let hasWellnessRow: Bool }
  struct CircadianInput { let regularityScore: Double; let hasEnoughData: Bool }
  struct DaylightInput { let minutes: Double; let source: Source }
  struct FastingInput { let activeFastHours: Double?; let isConfigured: Bool }
  struct RecoveryInput {
      let completedInterventionsToday: Int
      let hasJournalToday: Bool
      let hasMoodToday: Bool
      let hasMindfulSessionToday: Bool
  }
  struct VitalsInput {
      let todayHRV: Double?
      let hrvHistory: [DailyMetricSample]   // 30 days (we'll filter to 14 internally)
      let todayRHR: Double?
      let rhrHistory: [DailyMetricSample]
  }
  struct HistoryInput {
      let recentWellnessLogs: [WellnessDayLog]      // last 3 days incl. today
      let foodLogPresenceByDay: [Date: Bool]        // last 3 days
      let lastCompletedFastEnd: Date?
  }
  enum Source { case healthKit, manual }

  struct StressInputs {
      var sleep: SleepInput?
      var exercise: ExerciseInput?
      var caffeine: CaffeineInput?
      var screen: ScreenInput?
      var diet: DietInput?
      var hydration: HydrationInput?
      var circadian: CircadianInput?
      var daylight: DaylightInput?
      var mealLogs: [FoodLogEntry]
      var fasting: FastingInput?
      var triggerLogs: [FoodLogEntry]
      var mood: MoodOption?
      var symptoms: [SymptomEntry]
      var recovery: RecoveryInput
      var history: HistoryInput
      var vitals: VitalsInput
      var goals: UserGoals
  }

  struct StressResult {
      let score: Double
      let factors: [FactorPoints]
      let driverSum: Double
      let recovery: Double
      let engagementPenalty: Double
      let patternPenalty: Double
      let calibrator: Double
      let confidence: Confidence
      let raw: Double
  }

  struct CalibratorInputs {
      let todayHRV: Double?
      let hrvBaseline: Double?
      let todayRHR: Double?
      let rhrBaseline: Double?
  }
  ```
- **Why:** Single source-of-truth for the formula's input/output shapes.
- **Dependencies:** None.
- **Risk:** Low.

#### 1.2 Replace `Weights` enum (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Replace existing `Weights` with v3 weight table:
  ```swift
  enum Weights {
      // Tier A
      static let sleep: Double = 20
      static let exercise: Double = 12
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
      static let mood: Double = 8
      static let symptoms: Double = 7
      // Caps
      static let recoveryCap: Double = -10
      static let engagementCap: Double = 18
      static let patternCap: Double = 12
  }
  ```
- **Why:** Tier-A 60 / B 25 / C 15 = 100 driver budget.
- **Dependencies:** 1.1 complete.
- **Risk:** Low. Audit `Weights.` callsites; UI strings showing "/35" must not survive.

#### 1.3 Implement Tier A factor functions (File: `WellPlate/Core/Services/StressScoring.swift`)

<!-- RESOLVED: C1 — sugar dropped, use carbs ratio -->
<!-- RESOLVED: M1 — max(goal, 1) guard -->
<!-- RESOLVED: M11 — mgPerCup default 80 with comment -->

- **Action:** Implement per formula spec §3.1–§3.5 with these v3 corrections:
  - `dietPoints`:
    ```swift
    let carbsGoal = max(goals.carbsGoalGrams, 1)
    let proteinGoal = max(goals.proteinGoalGrams, 1)
    let carbRatio = input.carbs / Double(carbsGoal)
    let proteinRatio = input.protein / Double(proteinGoal)
    // carb excess (proxy for sugar load — FoodLogEntry has no sugar field as of v3)
    let carbTerm: Double
    switch carbRatio {
    case ..<0.8: carbTerm = 0
    case 0.8..<1.0: carbTerm = 1
    case 1.0..<1.5: carbTerm = lerp(1, 4, x: carbRatio, lo: 1.0, hi: 1.5)
    default: carbTerm = 5
    }
    let proteinTerm = proteinRatio < 0.5 ? 3.0 : 0.0
    return FactorPoints(points: min(8, carbTerm + proteinTerm), maxPoints: 8, hasData: true, detail: ...)
    ```
  - `caffeinePoints`:
    ```swift
    let mgPerCup = input.type?.caffeineMg ?? 80   // legacy rows may have nil type
    let mg = Double(input.cups * mgPerCup)
    // (late_bonus deferred — needs cup timestamps; pass 0 for v3)
    ```
  - `exercisePoints`: `activity = max((steps ?? 0) / 7000.0, (energy ?? 0) / 400.0)`. If both nil and `manualMinutes != nil`, use `Double(manualMinutes! * 100) / 7000.0`.
  - `sleepPoints`, `screenTimePoints` per formula spec §3.1, §3.4 unchanged.
- **Why:** Foundational drivers; sugar replaced with carb proxy keeps P1 small.
- **Dependencies:** 1.1, 1.2 complete.
- **Risk:** Medium. Threshold edge cases — use `<` consistently for upper bounds.

#### 1.4 Implement Tier B factor functions (File: `WellPlate/Core/Services/StressScoring.swift`)

<!-- RESOLVED: M1 — hydration guard -->

- **Action:** Implement per formula spec §3.6–§3.11. Apply guards:
  - `hydrationPoints`: `let goalSafe = max(goal, 1); let r = Double(glasses) / Double(goalSafe)`
  - `mealTimingPoints`: sort by `createdAt` first; check pairs for >5h gap with `m_{i+1}.calories > 600`
  - `fastingPoints`: take `activeFastHours` from `FastingInput`; `hasData = isConfigured` (per §0.1)
- **Dependencies:** 1.3 complete.
- **Risk:** Low.

#### 1.5 Implement Tier C factor functions (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §3.12–§3.13. `symptomPoints` dedupes by `name` taking max severity.
- **Dependencies:** 1.4 complete.
- **Risk:** Low.

#### 1.6 Implement recovery functions (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Implement per formula spec §4. `recoveryTotal(_:)` caps at `Weights.recoveryCap` (−10).
- **Dependencies:** 1.1 complete.
- **Risk:** Low.

#### 1.7 Implement engagement penalty (File: `WellPlate/Core/Services/StressScoring.swift`)

<!-- RESOLVED: M8 — low_steps nil-safe -->
<!-- RESOLVED: L2 — timezone note in code comment -->

- **Action:**
  ```swift
  // Note: hour-of-day is taken from Calendar.current → user's local timezone.
  // DST transitions handled correctly by Calendar; no special-case needed.
  static func engagementPenalty(inputs: StressInputs, now: Date) -> Double {
      let hasAnyDriver = ...  // per §0.1 — at least one factor has hasData
      guard hasAnyDriver else { return 0 }
      let hour = Double(Calendar.current.component(.hour, from: now))
              + Double(Calendar.current.component(.minute, from: now)) / 60.0

      func ramp(start: Double, end: Double) -> Double {
          guard end > start else { return 0 }
          return min(1, max(0, (hour - start) / (end - start)))
      }

      var sum: Double = 0
      // no_mood: max 5, 17→21
      if inputs.mood == nil { sum += 5 * ramp(start: 17, end: 21) }
      // no_food: max 4, 17→20
      if inputs.mealLogs.isEmpty { sum += 4 * ramp(start: 17, end: 20) }
      // no_water: max 4, 14→18
      if (inputs.hydration?.glasses ?? 0) == 0 { sum += 4 * ramp(start: 14, end: 18) }
      // low_steps: max 3, 16→20 — only if HK steps known
      if let steps = inputs.exercise?.steps, steps < 2000 { sum += 3 * ramp(start: 16, end: 20) }
      // no_reflection: max 2, 18→21
      if !inputs.recovery.hasJournalToday && inputs.mood == nil
         && !inputs.recovery.hasMindfulSessionToday {
          sum += 2 * ramp(start: 18, end: 21)
      }
      return min(Weights.engagementCap, sum)
  }
  ```
- **Why:** Time-ramped penalty. `low_steps` returns 0 when HK steps absent (manual lane handles that case differently).
- **Dependencies:** 1.3–1.5 complete.
- **Risk:** Medium. Test 16:59 vs 17:01 boundary.

#### 1.8 Implement pattern penalty (File: `WellPlate/Core/Services/StressScoring.swift`)

<!-- RESOLVED: M9 — use enum cases instead of raw values -->

- **Action:** Implement per formula spec §6. Use enum case predicate for mood:
  ```swift
  let mood = MoodOption(rawValue: log.moodRaw ?? -1)
  let isLowMood = mood == .awful || mood == .bad
  ```
  Predicates: `noFood3d` (3 days zero `FoodLogEntry`), `lowMood3d` (3 days `isLowMood`), `highCoffee3d` (3 days `coffeeCups ≥ 4`), `noFast14d` (`lastCompletedFastEnd < now − 14 days` OR nil).
- **Dependencies:** 1.1 complete.
- **Risk:** Low.

#### 1.9 Implement calibrator + baseline (File: `WellPlate/Core/Services/StressScoring.swift`)

<!-- RESOLVED: M10 — defensive future-date filter -->

- **Action:** Implement per formula spec §7:
  ```swift
  static func baseline14Day(_ samples: [DailyMetricSample], excludingToday now: Date) -> Double? {
      let cal = Calendar.current
      let startOfToday = cal.startOfDay(for: now)
      let cutoff = cal.date(byAdding: .day, value: -14, to: startOfToday) ?? startOfToday
      let valid = samples.filter {
          $0.date >= cutoff
          && $0.date < startOfToday          // exclude today AND future
          && $0.value > 0
      }
      guard valid.count >= 5 else { return nil }
      return valid.map(\.value).reduce(0, +) / Double(valid.count)
  }

  static func calibrator(_ inputs: CalibratorInputs) -> Double {
      var delta = 0.0
      var present = false
      if let t = inputs.todayHRV, let b = inputs.hrvBaseline, b > 0 {
          delta += ((b - t) / b) * 0.5
          present = true
      }
      if let t = inputs.todayRHR, let b = inputs.rhrBaseline, b > 0 {
          delta += ((t - b) / b) * 0.3
          present = true
      }
      return present ? max(0.90, min(1.15, 1.0 + delta)) : 1.0
  }
  ```
- **Dependencies:** 1.1 complete.
- **Risk:** Low.

#### 1.10 Implement confidence (File: `WellPlate/Core/Services/StressScoring.swift`)

<!-- RESOLVED: M6 — typealias for back-compat -->

- **Action:**
  - Define `enum Confidence { case low, medium, high }` inside `StressScoring`
  - Implement `static func confidence(factors: [FactorPoints]) -> Confidence` per formula spec §8
  - In `StressViewModel.swift`, replace the existing `extension StressViewModel { enum Confidence ... }` with `typealias Confidence = StressScoring.Confidence` for source compatibility
  - Audit `Confidence` callsites with grep before removing the extension
- **Dependencies:** 1.3–1.5 complete.
- **Risk:** Low.

#### 1.11 Implement `computeStress` orchestrator (File: `WellPlate/Core/Services/StressScoring.swift`)

- **Action:** Pure function combining all factors, recovery, engagement, patterns, calibrator. Returns `StressResult`. Per formula spec §1 final equation.
- **Dependencies:** 1.3–1.10 complete.
- **Risk:** Low.

#### 1.12 Refactor `StressFactorResult` (File: `WellPlate/Models/StressModels.swift`)

<!-- RESOLVED: H3 — id is now title-based String -->

- **Action:**
  - Change `let id = UUID()` to `var id: String { title }`
  - Add init `StressFactorResult(from: FactorPoints, title: String, icon: String, higherIsBetter: Bool)`
  - Simplify `stressContribution`: with v3 signed `points`, `stressContribution = hasValidData ? max(0, points) : 0` (recovery factors don't contribute to stress; their negative points are captured separately via `RecoveryInput`)
  - Update `.neutral(...)` factory: `static func neutral(title:, icon:, higherIsBetter:, maxScore: Double)` — no more hardcoded `25`
  - Audit existing `.neutral(...)` callsites at `StressViewModel.swift:25-28` and update with `maxScore: StressScoring.Weights.{factor}`
- **Why:** Stable id for SwiftUI list animations; correct `stressContribution` for signed points.
- **Dependencies:** 1.1 complete.
- **Risk:** Medium. Grep `.neutral(` and update all callers.

#### 1.13 Refactor `StressViewModel.loadData()` (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

<!-- RESOLVED: H7 — direct SwiftData fetch for active fast -->
<!-- RESOLVED: M2 — mock mode unified via buildInputsFromMockSnapshot -->

- **Action:**
  - Add new `@Published` props: `var calibratorMultiplier: Double = 1.0`, `var engagementPenaltyValue: Double = 0`, `var patternPenaltyValue: Double = 0`, `var allFactors: [StressFactorResult] = []`
  - Convert `totalScore` from computed to stored: `@Published var totalScore: Double = 0`
  - Add new fetches (cheap SwiftData):
    - Today's `[SymptomEntry]`
    - Today's `JournalEntry` (presence)
    - Today's completed `[InterventionSession]`
    - Last-3-day `[WellnessDayLog]`
    - Last-3-day `[FoodLogEntry]` grouped by day
    - **Active `FastingSession`** (`actualEndAt == nil`) → compute `activeFastHours = (now − startedAt) / 3600`
    - Most recent completed `FastingSession.actualEndAt` (for `noFast14d`)
    - Today's `ManualDailyInput` (P2 populates; P1 always nil)
  - Add resolution helpers (private): `resolveSleep`, `resolveExercise`, `resolveScreen`, `resolveDaylight`, `resolveCircadian`
  - Add `private func buildInputs(now: Date) -> StressInputs` that assembles `StressInputs` from already-fetched HK + cheap SwiftData refetch
  - Add `private func buildInputsFromMockSnapshot(_ snapshot: StressMockSnapshot, now: Date) -> StressInputs` for mock mode
  - Call `let result = StressScoring.computeStress(inputs: inputs, now: Date())`
  - Publish: `totalScore = result.score`, `calibratorMultiplier = result.calibrator`, `engagementPenaltyValue = result.engagementPenalty`, `patternPenaltyValue = result.patternPenalty`
  - Build `allFactors` by mapping `result.factors` → `StressFactorResult` (using existing per-factor titles/icons)
  - Update `topStressors`: `prefix(5)` instead of `prefix(2)` (verified no external consumers)
- **Why:** Wire pure compute to published state; unified mock pipeline.
- **Dependencies:** 1.1–1.12 complete.
- **Risk:** High. Largest single change.

#### 1.14 Add `recompute()` and refresh shims (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

<!-- RESOLVED: H1 — recompute() always re-fetches cheap SwiftData; reuses last HK fetch -->
<!-- RESOLVED: M5 — keep existing names; thin shims call recompute() -->

- **Action:**
  - Cache last HK results in private vars (`lastSteps`, `lastEnergy`, `lastSleepSummary`, `lastHRVHistory`, `lastRHRHistory`, etc.)
  - `func recompute()`:
    - Re-fetches cheap SwiftData (mood, water, food, symptoms, journal, interventions, manual input, recent wellness logs, active fast)
    - Reuses cached HK values (do NOT re-hit HealthKit)
    - Calls `buildInputs(now: Date())` → `computeStress` → publishes
  - Keep existing `refreshDietFactor()`, `refreshScreenTimeOnly()`, `refreshDietFactorAndLogIfNeeded()` — make them thin shims:
    ```swift
    func refreshDietFactor() { recompute() }
    func refreshScreenTimeOnly() { recompute() }
    func refreshDietFactorAndLogIfNeeded() { recompute(); logCurrentStress(source: "auto") }
    ```
  - Update `logCurrentStress(source:)` to log `totalScore` (the new stored property)
- **Why:** Zero callsite churn (HomeView, MealLogView keep working). Cheap SwiftData refetch ensures fresh user data.
- **Dependencies:** 1.13 complete.
- **Risk:** Medium.

#### 1.15 Wire engagement ticker at app/scene level (File: `WellPlate/App/WellPlateApp.swift`, `WellPlate/App/RootView.swift`)

<!-- RESOLVED: H2 — ticker at app/scene level, not StressView -->

- **Action:**
  - In `WellPlateApp.swift`, declare `@StateObject private var promptCoordinator = DailyPromptCoordinator()` (will own ticker for cross-tab consistency)
  - In `RootView.swift`, observe `@Environment(\.scenePhase) private var scenePhase`
  - Pass scenePhase changes to a singleton `StressTimerService` or directly to the visible `StressViewModel` via `EnvironmentObject` if it's hoisted; simplest: the ViewModel checks for ticker start/stop in response to scene phase
  - Implementation: add a `StressTimerService.shared` (or extend `DailyPromptCoordinator`) that keeps a `Timer.publish(every: 300, on: .main, in: .common).autoconnect()` running while `.active`; emit a notification or a `@Published var tickerPulse: Date` that the active `StressViewModel` observes via Combine and reacts with `recompute()`
- **Why:** Ticker must run regardless of which tab is foregrounded so Home tab's `StressSparklineStrip` stays current.
- **Dependencies:** 1.14 complete.
- **Risk:** Medium. Cross-cutting plumbing.

#### 1.16 Drop scoring contributions from vitals (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

- **Action:** Verify (mostly) — remove any code paths where `heartRateHistory`, `bp*History`, `respiratoryRateHistory` feed into scoring. Confirm `hrvHistory` and `restingHRHistory` only flow through `baseline14Day(...)`. Vitals card still displays.
- **Dependencies:** 1.13 complete.
- **Risk:** Low.

#### 1.17 Extend mock snapshot + mock HK service (Files: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`, `WellPlate/Core/Services/MockHealthKitService.swift`)

<!-- RESOLVED: H6 — mock service projects multi-day baselines -->

- **Action:**
  - Add fields to `StressMockSnapshot`: `mood: MoodOption?`, `todaySymptoms: [SymptomEntry]`, `todayJournal: JournalEntry?`, `todayInterventions: [InterventionSession]`, `recentWellnessLogs: [WellnessDayLog]`, `recentFoodLogs: [FoodLogEntry]`, `lastCompletedFastEnd: Date?`, `hrvSamples: [DailyMetricSample]` (≥7 days for baseline), `rhrSamples: [DailyMetricSample]` (≥7 days)
  - Add 4 mock variants: `.fullyLoggedBalancedDay`, `.fullyLoggedBadDay`, `.disengagedBadDay21h`, `.dayOneNoData` (override the existing `default`/`sparse` if helpful)
  - In `MockHealthKitService`: update `fetchHRV(for:)`, `fetchRestingHeartRate(for:)` to project `snapshot.hrvSamples` / `rhrSamples` filtered by `range`. Same for `fetchSteps`, `fetchActiveEnergy`, `fetchDailySleepSummaries`, `fetchDaylight` for the multi-day variants
  - Verify `MockDataInjector` still operates correctly; verify any `Resources/MockData/*.json` fixtures still load
- **Why:** Calibrator needs ≥5 valid days to engage; mock must satisfy.
- **Dependencies:** 1.1 complete.
- **Risk:** Medium.

#### 1.18 P1 build verification

- **Action:** Build all 4 targets per CLAUDE.md commands.
- **Dependencies:** 1.17 complete.
- **Risk:** Low.

#### 1.18b Test target verification + StressScoringTests <!-- RESOLVED: H4 -->

- **Action:**
  - Run `xcodebuild -project WellPlate.xcodeproj -list` to confirm `WellPlate` scheme exists and lists `WellPlateTests` as a test target
  - If missing: open Xcode, edit scheme, enable `WellPlateTests` under Test action, mark scheme as Shared
  - Run `xcodebuild test -project WellPlate.xcodeproj -scheme WellPlate -destination 'platform=iOS Simulator,name=iPhone 15'` to confirm baseline tests pass
  - Create `WellPlateTests/StressScoringTests.swift` with cases mapping to formula spec §14:
    - `testZeroInputReturnsLowConfidence()`
    - `testPerfectDayReturnsZero()`
    - `testWorstLoggedDayClampsTo100()`
    - `testMoodGreatStrictlyReducesScore()`
    - `testWaterEightStrictlyReducesScore()`
    - `testManualSleepEqualsHKEquivalent()`
    - `testCalibratorCollapsesWithoutBaseline()`
    - `testEngagementZeroBeforeStartHour()`
    - `testPatternPenaltyStableAcrossRecomputes()`
- **Why:** Validation strategy must execute, not just exist as `.swift` files.
- **Dependencies:** 1.18 complete.
- **Risk:** Medium. If scheme can't be wired in CLI, fall back to `MockDataDebugCard` smoke checks and document as "unverified automated coverage" per CLAUDE.md.

---

### Phase 2 — Manual Fallback + Daily Overlays (3–4 days)

#### 2.0 Add `onboardingCompletedAt` timestamp <!-- RESOLVED: H5 -->

- **Action:**
  - In `WellPlate/Core/Services/UserProfileManager.swift`:
    - Add `case onboardingCompletedAt` to the `Key` enum
    - Add `var onboardingCompletedAt: Date? { get/set }` reading/writing as `Date` to defaults
  - In `WellPlate/Features + UI/Onboarding/OnboardingCompletionPage.swift`:
    - Find the existing flip of `hasCompletedOnboarding = true`; immediately after, set `UserProfileManager.shared.onboardingCompletedAt = .now`
- **Why:** Coordinator's 24h grace period needs this timestamp.
- **Dependencies:** None (file-local change).
- **Risk:** Low. Legacy users have `nil` → coordinator treats as long-completed (no grace, no harm).

#### 2.1 Create `ManualDailyInput` model (File: `WellPlate/Models/ManualDailyInput.swift` — NEW)

<!-- RESOLVED: L1 — keeping separate from WellnessDayLog accepted; rationale below -->

- **Rationale (L1):** `WellnessDayLog` is the truth of what the user logged. `ManualDailyInput` is the truth of what the user *typed when sensors didn't speak*. Mixing them in one model would entangle "ground truth user behavior" with "fallback estimates." Keep separate; cost is one extra fetch per recompute (cheap).
- **Action:** Per audit recommendation:
  ```swift
  import Foundation
  import SwiftData

  @Model final class ManualDailyInput {
      @Attribute(.unique) var day: Date
      var sleepHours: Double?
      var sleepQuality: Int?
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
- **Dependencies:** None.
- **Risk:** Low.

#### 2.2 Register in ModelContainer (File: `WellPlate/App/WellPlateApp.swift:34`)

- **Action:** Append `ManualDailyInput.self` to the `.modelContainer(for: [...])` array.
- **Dependencies:** 2.1 complete.
- **Risk:** Low.

#### 2.3 Implement `DailyPromptCoordinator` (File: `WellPlate/Core/Services/DailyPromptCoordinator.swift` — NEW)

<!-- RESOLVED: H5 — uses onboardingCompletedAt -->

- **Action:**
  ```swift
  @MainActor
  final class DailyPromptCoordinator: ObservableObject {
      enum PromptKind: Identifiable {
          case morning(MorningGaps)
          case evening(EveningGaps)
          var id: String { self == .morning ? "morning" : "evening" }   // simplified
      }
      struct MorningGaps { let needsSleep: Bool }
      struct EveningGaps { let needsScreen: Bool; let needsExercise: Bool; let needsDaylight: Bool }

      @Published var pendingPrompt: PromptKind? = nil

      func evaluateOnAppForeground(now: Date,
                                   modelContext: ModelContext,
                                   healthService: HealthKitServiceProtocol) async {
          // 1. Don't-ask-again UserDefaults
          if UserDefaults.standard.bool(forKey: "wp.stress.dontAskAgain") { return }

          // 2. 24h post-onboarding grace
          if let completedAt = UserProfileManager.shared.onboardingCompletedAt,
             now.timeIntervalSince(completedAt) < 24 * 3600 { return }

          // 3. Resolve today's ManualDailyInput
          let today = Calendar.current.startOfDay(for: now)
          let manual = (try? modelContext.fetch(FetchDescriptor<ManualDailyInput>(
              predicate: #Predicate { $0.day == today }))?.first

          let hour = Calendar.current.component(.hour, from: now)

          // 4. Morning prompt
          if hour >= 11 && manual?.morningAskedAt == nil && manual?.sleepHours == nil {
              let hkSleep = (try? await healthService.fetchDailySleepSummaries(for: ...)) ?? []
              if hkSleep.isEmpty {
                  pendingPrompt = .morning(MorningGaps(needsSleep: true))
                  return
              }
          }

          // 5. Evening prompt
          if hour >= 19 && manual?.eveningAskedAt == nil {
              // check HK screen / exercise / daylight; if any silent and corresponding manual nil → present
              ...
          }
      }

      func recordSkip(_ kind: PromptKind, modelContext: ModelContext, now: Date) { /* set askedAt */ }
      func recordSave(_ kind: PromptKind, values: ManualValues, modelContext: ModelContext, now: Date) { /* upsert */ }
      func disableForever() { UserDefaults.standard.set(true, forKey: "wp.stress.dontAskAgain") }
  }
  ```
- **Why:** Methods take `modelContext` per call (resolution C3 chosen path uses `.environmentObject` ownership but coordinator stays SwiftData-state-free for testability).
- **Dependencies:** 2.0, 2.1, 2.2 complete.
- **Risk:** Medium.

#### 2.4 Implement `QuickCheckInSheet` (File: `WellPlate/Shared/Components/QuickCheckInSheet.swift` — NEW)

- **Action:** Bottom sheet view bound to `PromptKind` and coordinator. Morning/evening forms; Save/Skip/Don't-ask-again buttons; uses `.r(...)`, `.appShadow(...)`. `.presentationDetents([.medium])`.
- **Dependencies:** 2.3 complete.
- **Risk:** Medium.

#### 2.5 Wire coordinator + scene observation (Files: `WellPlate/App/WellPlateApp.swift`, `WellPlate/App/RootView.swift`)

<!-- RESOLVED: C3 — coordinator owned by WellPlateApp via @StateObject; passed via .environmentObject -->

- **Action:**
  - In `WellPlateApp.swift`:
    - Add `@StateObject private var promptCoordinator = DailyPromptCoordinator()`
    - Inject into root view: `RootView().environmentObject(promptCoordinator)`
  - In `RootView.swift`:
    - Add `@EnvironmentObject private var promptCoordinator: DailyPromptCoordinator`
    - Add `@Environment(\.modelContext) private var modelContext`
    - Add `@Environment(\.scenePhase) private var scenePhase`
    - In the `MainTabView` branch only:
      ```swift
      MainTabView(pendingDeepLink: $pendingDeepLink)
          .sheet(item: $promptCoordinator.pendingPrompt) { kind in
              QuickCheckInSheet(kind: kind, coordinator: promptCoordinator)
          }
          .onChange(of: scenePhase) { _, newPhase in
              guard newPhase == .active, !showSplash, !showOnboarding else { return }
              Task {
                  await promptCoordinator.evaluateOnAppForeground(
                      now: Date(),
                      modelContext: modelContext,
                      healthService: HealthKitServiceFactory.shared
                  )
              }
          }
      ```
- **Why:** Single global presenter; `.environmentObject` flow avoids the @StateObject init-time conflict.
- **Dependencies:** 2.3, 2.4 complete.
- **Risk:** Medium.

#### 2.6 Add resolution priority to `StressViewModel` (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

<!-- RESOLVED: M3 — eveningHours derivation specified -->

- **Action:**
  - In `loadData()`, after HK fetches, fetch today's `ManualDailyInput`
  - Implement private resolvers:
    ```swift
    private func resolveSleep(hk: DailySleepSummary?, manual: ManualDailyInput?) -> SleepInput? {
        if let s = hk { return SleepInput(totalHours: s.totalHours, deepHours: s.deepHours, source: .healthKit) }
        guard let m = manual, let h = m.sleepHours else { return nil }
        let derivedDeep: Double = {
            switch m.sleepQuality ?? 3 {
            case 1: return 0.25; case 2: return 0.5
            case 3: return 0.75; case 4: return 1.0
            case 5: return 1.33; default: return 0.75
            }
        }()
        return SleepInput(totalHours: h, deepHours: derivedDeep, source: .manual)
    }

    private func resolveScreen(autoHours: Double?, manual: ManualDailyInput?) -> ScreenInput? {
        if let h = autoHours { return ScreenInput(totalHours: h, eveningHours: nil, source: .healthKit) }
        guard let m = manual, let h = m.screenTimeHours else { return nil }
        let evening = (m.heavyEveningScreens == true) ? 2.0 : 0.0
        return ScreenInput(totalHours: h, eveningHours: evening, source: .manual)
    }

    private func resolveExercise(steps: Double?, energy: Double?, manual: ManualDailyInput?) -> ExerciseInput? {
        if steps != nil || energy != nil {
            return ExerciseInput(steps: steps, energy: energy, manualMinutes: nil, source: .healthKit)
        }
        guard let m = manual, let mins = m.exerciseMinutes else { return nil }
        return ExerciseInput(steps: nil, energy: nil, manualMinutes: mins, source: .manual)
    }

    private func resolveDaylight(hkMinutes: Double?, manual: ManualDailyInput?) -> DaylightInput? {
        if let m = hkMinutes, m > 0 { return DaylightInput(minutes: m, source: .healthKit) }
        guard let mi = manual?.amDaylightOutside else { return nil }
        return DaylightInput(minutes: mi ? 30 : 5, source: .manual)
    }
    ```
- **Dependencies:** 2.1, 1.13 complete.
- **Risk:** Medium.

#### 2.7 Observe ManualDailyInput changes (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)

- **Action:** When coordinator's `recordSave` writes a `ManualDailyInput`, the active `StressViewModel` should `recompute()`. Use Combine: `DailyPromptCoordinator` exposes `@Published var manualInputSavedAt: Date = .distantPast`, set on save. `StressViewModel` subscribes (in init or `.onAppear`) and calls `recompute()` on change. Use `[weak self]`.
- **Dependencies:** 2.3, 2.6 complete.
- **Risk:** Low.

#### 2.8 Add Profile toggle (File: `WellPlate/Features + UI/Tab/ProfileView.swift`)

<!-- RESOLVED: M7 — placement specified -->

- **Action:**
  - Find or create a "Notifications & Prompts" `Section` (place below existing Goals section)
  - Add row: "Daily check-in prompts" with `Toggle` bound to inverse of `UserDefaults.standard.bool(forKey: "wp.stress.dontAskAgain")`
  - When user re-enables (toggles ON): also clear today's `ManualDailyInput.morningAskedAt` and `eveningAskedAt` so prompts can re-fire today
- **Dependencies:** 2.3 complete.
- **Risk:** Low.

#### 2.9 P2 build + smoke verification

- **Action:** Build all 4 targets. Manual smoke per original plan §2.9.
- **Dependencies:** 2.0–2.8 complete.
- **Risk:** Low.

---

### Phase 3 — UI Surfacing (3–4 days)

#### 3.1 Add new `StressSheet` cases (File: `WellPlate/Features + UI/Stress/Views/StressView.swift:12`)

<!-- RESOLVED: H8 — sheet cases for engagement CTA targets -->

- **Action:** Add `.allFactors`, `.manualLog`, `.mood`, `.water`, `.foodLog`, `.burnTab` cases. (Tab-switch cases use a closure handler to switch tabs rather than open a sheet — implementation detail at the sheet handler level.)
- **Dependencies:** Phase 2 complete.
- **Risk:** Low.

#### 3.2 Build `CalibratorChip` (File: `WellPlate/Features + UI/Stress/Components/CalibratorChip.swift` — NEW)

- **Action:** Pill view with 4 modes: vitals-good (cal < 1.0) / vitals-strain (cal > 1.0) / vitals-normal (cal == 1.0 with baseline) / no-baseline (Watch-less or insufficient days). Use `.r(.caption, .semibold)`, adaptive blue tint.
- **Dependencies:** 1.13 complete.
- **Risk:** Low.

#### 3.3 Build `EngagementGapsCard` + `MoodCheckInSheet` wrapper <!-- RESOLVED: H8 -->

- **Action:**
  - New `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift`: card visible when `engagementPenaltyValue > 0`. Lists active gaps + CTAs:
    - **Mood gap CTA** → opens `StressSheet.mood` (modal sheet wrapping existing `MoodCheckInCard`)
    - **Water gap CTA** → switches to Home tab and presents `WaterDetailView` (use a tab-switch callback + deep link)
    - **Food gap CTA** → switches to Home tab + presents `MealLogView`
    - **Steps gap CTA** → switches to Burn tab (no logger, just navigation)
    - **Reflection gap CTA** → opens `StressSheet.mood` (mood doubles as reflection)
  - New `WellPlate/Shared/Components/MoodCheckInSheet.swift`: thin wrapper presenting `MoodCheckInCard` in a sheet with bind-back behavior — saves to today's `WellnessDayLog.moodRaw` on selection
  - Use existing `pendingDeepLink` mechanism in `RootView` for tab switches if simpler
- **Why:** CTAs are concrete; routes pre-decided.
- **Dependencies:** 3.1, 3.2 complete.
- **Risk:** Medium.

#### 3.4 Refactor `StressView` header (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:** Below the score gauge, horizontal row with `CalibratorChip` + confidence badge. Update confidence text: "X of 13 factors logged" using new weight-weighted formula.
- **Dependencies:** 3.2 complete.
- **Risk:** Low.

#### 3.5 Replace fixed 4-card grid with top-N drivers (File: `WellPlate/Features + UI/Stress/Views/StressView.swift:809`)

<!-- RESOLVED: L3 — title→sheet switch accepted for v3 -->

- **Action:**
  - Replace hardcoded `[exerciseFactor, sleepFactor, dietFactor, screenTimeFactor]` array with:
    ```swift
    viewModel.allFactors
        .filter(\.hasValidData)
        .sorted { $0.stressContribution > $1.stressContribution }
        .prefix(5)
    ```
  - Map factor `title` → sheet via switch in card's `onTap`. Acceptable v3 coupling per L3.
- **Dependencies:** 3.1, 1.12 (id stability) complete.
- **Risk:** Medium. Sheet routing for v3-only factors (mood/symptoms/hydration) — use new `StressSheet` cases.

#### 3.6 Add Recovery section (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:** Below top-5 drivers, "Recovery" section. Shows intervention/journal/mindful with "−X stress avoided" framing.
- **Dependencies:** 1.13 complete.
- **Risk:** Low.

#### 3.7 Add Engagement Gaps section (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:** Insert `EngagementGapsCard` between drivers and Recovery. Hidden when `engagementPenaltyValue == 0`.
- **Dependencies:** 3.3 complete.
- **Risk:** Low.

#### 3.8 Add "All factors" disclosure (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:** Footer button opens `StressSheet.allFactors`. Sheet groups factors by tier (A/B/C); rows show `points / maxPoints` bars with sign.
- **Dependencies:** 3.1 complete.
- **Risk:** Low.

#### 3.9 Add Quick Log button (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)

- **Action:** Anchored button at bottom of scroll opening `StressSheet.manualLog` → `QuickCheckInSheet` re-used from P2.
- **Dependencies:** 2.4, 3.1 complete.
- **Risk:** Low.

#### 3.10 Update `StressFactorCardView` (File: `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift`)

- **Action:** Show signed `points` (e.g., "+8" red, "−2" green); add tier badge (A/B/C) top-right. Keep existing layout.
- **Dependencies:** 1.12 complete.
- **Risk:** Low.

#### 3.11 One-time announcement banner <!-- RESOLVED: M12 -->

- **Action:** On `StressView.onAppear`, if `UserDefaults.standard.bool(forKey: "wp.stress.v3AnnouncementShown") == false`, show dismissible top banner:
  > **Your stress score now considers mood, hydration, symptoms, and more — 13 factors total. Vitals like HRV are used to calibrate accuracy against your personal baseline.**

  On dismiss → set flag true. Optional: tap opens info sheet listing all factors.
- **Dependencies:** None.
- **Risk:** Low.

#### 3.12 Verify Home + Widget integration (Files: `WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift`, `WellPlate/Widgets/SharedStressData.swift`)

- **Action:** Confirm both still read `viewModel.totalScore` correctly post-conversion to stored property. Verify ticker (1.15) keeps Home sparkline current.
- **Dependencies:** 1.13, 1.15 complete.
- **Risk:** Low.

#### 3.13 P3 build + visual verification

- **Action:** Build all 4 targets; toggle 4 mock variants; verify reorder, engagement card visibility, calibrator chip, quick log, banner.
- **Dependencies:** 3.1–3.12 complete.
- **Risk:** Low.

---

## Testing Strategy

### Build verification

After each phase, build all 4 targets per CLAUDE.md.

### Automated tests <!-- RESOLVED: H4 -->

- Verify `WellPlateTests` is wired into shared `WellPlate` scheme (step 1.18b)
- Run validation cases from formula spec §14 as XCTest in `StressScoringTests.swift`
- If scheme can't be wired in CLI, downgrade to `MockDataDebugCard` smoke checks and document as "unverified automated coverage" per CLAUDE.md

### Manual verification flows

(Same as original plan §Testing Strategy.)

---

## Risks & Mitigations

(Original risks preserved; H1–H8 resolutions reduce most.)

| Risk | Status |
|---|---|
| `StressFactorResult.id` change to title | Pre-resolved — H3 fix |
| Coordinator init-time context | Pre-resolved — C3 via `.environmentObject` |
| Sugar field absent | Pre-resolved — C1 carbs proxy |
| Test scheme wiring | Pre-resolved with verify-or-fallback path — H4 |
| Mock multi-day baselines | Pre-resolved — H6 expansion |
| FastingService API gap | Pre-resolved — H7 direct fetch |
| Onboarding timestamp | Pre-resolved — H5 add field |
| Engagement timer scope | Pre-resolved — H2 app-level |
| Engagement CTA routing | Pre-resolved — H8 routing matrix |
| `recompute()` cache staleness | Pre-resolved — H1 fresh SwiftData each call |
| Cross-tab Home sparkline staleness | Mitigated by H2 ticker |
| Mock-mode pipeline divergence | Pre-resolved — M2 unified pipeline |

---

## Success Criteria

(Same as original plan; all preserved.)

---

## Next step

→ `/develop checklist Docs/02_Planning/Specs/260509-stress-algorithm-v3-plan-RESOLVED.md` — generate step-by-step actionable checklist with verify steps.
