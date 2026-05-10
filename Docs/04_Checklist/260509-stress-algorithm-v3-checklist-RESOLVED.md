# Implementation Checklist: Stress Algorithm v3 (RESOLVED)

**Original checklist:** [260509-stress-algorithm-v3-checklist.md](./260509-stress-algorithm-v3-checklist.md)
**Audit:** [260509-stress-algorithm-v3-checklist-audit.md](../03_Audits/260509-stress-algorithm-v3-checklist-audit.md)
**Source plan:** [260509-stress-algorithm-v3-plan-RESOLVED.md](../02_Planning/Specs/260509-stress-algorithm-v3-plan-RESOLVED.md)
**Date:** 2026-05-09

---

## Audit Resolution Summary

| ID | Severity | Resolution | Where |
|---|---|---|---|
| **C1** | CRITICAL | `ManualDailyInput` model + ModelContainer registration moved to start of P1 (§1.0a, §1.0b). Type now exists when 1.13b's fetch lands. | §1.0a, §1.0b |
| **H1** | HIGH | Ticker forced to use `StressTimerService.shared` (new singleton). P1 self-contained. | §1.15 |
| **H2** | HIGH | Per-factor `hasData` verify steps added under each factor. New §1.5z policy checkpoint. | §1.3, §1.4, §1.5, §1.5z |
| **H3** | HIGH | `guard healthService.isAuthorized` early-return added to coordinator. | §2.3 |
| **H4** | HIGH | §1.13d gains explicit deletion list for `buildExerciseFactor`/`buildSleepFactor`/`buildDietFactor`/`refreshScreenTimeFactor` + their callsites. | §1.13d |
| **H5** | HIGH | §1.18b adds `PBXFileSystemSynchronizedRootGroup` check + Target Membership step + `-only-testing:` invocation. | §1.18b |
| **H6** | HIGH | §3.5 routing table now lists all 13 drivers; Caffeine + Eating Triggers marked non-tappable; new `.symptoms` and `.fasting` sheet cases added in §3.1. | §3.1, §3.5 |
| **H7** | HIGH | New `TabSelector` `EnvironmentObject` added (§2.0b); §3.3 CTAs use it; tab-switch verified in post-impl. | §2.0b, §3.3 |
| M1 | MEDIUM | Weights verify checks ≥13 constants. | §1.2 |
| M2 | MEDIUM | Per-gap thresholds enumerated in §1.7; per-pattern in §1.8. | §1.7, §1.8 |
| M3 | MEDIUM | Confidence typealias folded into §1.13a (no separate §1.10 file edit). | §1.10, §1.13a |
| M4 | MEDIUM | `manualInputCancellable: AnyCancellable?` storage specified. | §2.7 |
| M5 | MEDIUM | Enumerated mock fetch fns + per-variant verify. | §1.17 |
| M6 | MEDIUM | Circadian manual-history verify (5+ nights → hasEnoughData=true). | §2.6 |
| M7 | MEDIUM | Banner dismiss-persistence verify added. | §3.11 |
| M8 | MEDIUM | New-files preview list added in Pre-Implementation. | Pre |
| M9 | MEDIUM | Less-fragile grep using literal struct names. | §1.1 |
| M10 | MEDIUM | §1.16 specifies fail action ("remove if found in scoring path"). | §1.16 |
| L1 | LOW | Formula §10 reactivity examples added to post-impl smoke. | Post |
| L2 | LOW | Commit message footer convention noted (optional). | §1.19, §2.10, §3.14 |
| L3 | LOW | Cross-tab CTA smoke added to post-impl. | Post |

**Verdict:** ALL RESOLVED — 1 CRITICAL, 7 HIGH, 10 MEDIUM, 3 LOW addressed inline.

---

## Pre-Implementation

- [ ] Read the resolved plan end-to-end; skim brainstorm + formula spec for context
- [ ] Create a feature branch: `git checkout -b feat/stress-algorithm-v3`
- [ ] Verify all referenced existing files exist:
  - [ ] `WellPlate/Core/Services/StressScoring.swift`
  - [ ] `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - [ ] `WellPlate/Models/StressModels.swift`
  - [ ] `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
  - [ ] `WellPlate/Core/Services/MockHealthKitService.swift`
  - [ ] `WellPlate/App/WellPlateApp.swift`
  - [ ] `WellPlate/App/RootView.swift`
  - [ ] `WellPlate/Features + UI/Tab/MainTabView.swift`
  - [ ] `WellPlate/Features + UI/Tab/ProfileView.swift`
  - [ ] `WellPlate/Features + UI/Onboarding/OnboardingCompletionPage.swift`
  - [ ] `WellPlate/Core/Services/UserProfileManager.swift`
  - [ ] `WellPlate/Features + UI/Stress/Views/StressView.swift`
  - [ ] `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift`
- [ ] **Files to be created during implementation** <!-- RESOLVED: M8 -->:
  - [ ] `WellPlate/Models/ManualDailyInput.swift` (§1.0a)
  - [ ] `WellPlate/Core/Services/StressTimerService.swift` (§1.15)
  - [ ] `WellPlate/Core/Services/DailyPromptCoordinator.swift` (§2.3)
  - [ ] `WellPlate/Core/Services/TabSelector.swift` (§2.0b)
  - [ ] `WellPlate/Shared/Components/QuickCheckInSheet.swift` (§2.4)
  - [ ] `WellPlate/Shared/Components/MoodCheckInSheet.swift` (§3.3)
  - [ ] `WellPlate/Features + UI/Stress/Components/CalibratorChip.swift` (§3.2)
  - [ ] `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift` (§3.3)
  - [ ] `WellPlateTests/StressScoringTests.swift` (§1.18b)
- [ ] Confirm baseline build is green:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build` exits 0
- [ ] Note: per CLAUDE.md, no pbxproj edits needed for new files under `WellPlate/`. `WellPlateTests/` membership requires verification (see §1.18b).

---

## Phase 1 — Scoring Core

### 1.0a — Create `ManualDailyInput` model EARLY <!-- RESOLVED: C1 — moved from §2.1 -->

- [ ] Create new file `WellPlate/Models/ManualDailyInput.swift`:
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
  - Verify: `ls WellPlate/Models/ManualDailyInput.swift` exists; `grep "@Attribute(.unique)" WellPlate/Models/ManualDailyInput.swift` returns 1 match

### 1.0b — Register ManualDailyInput in ModelContainer EARLY <!-- RESOLVED: C1 — moved from §2.2 -->

- [ ] Open `WellPlate/App/WellPlateApp.swift`
- [ ] At the existing `.modelContainer(for: [...])` array (~line 34), append `ManualDailyInput.self`
  - Verify: `grep "ManualDailyInput.self" WellPlate/App/WellPlateApp.swift` returns 1 match
- [ ] Compile-check baseline still builds (no scoring logic referenced yet)

### 1.1 — Define data structs in `StressScoring.swift`

- [ ] Open `WellPlate/Core/Services/StressScoring.swift`
- [ ] Replace file contents starting with `import Foundation`
- [ ] Add `struct FactorPoints { points; maxPoints; hasData; detail; static let none }`
  - Verify: `grep "struct FactorPoints" WellPlate/Core/Services/StressScoring.swift` returns 1 match
- [ ] Add input sub-structs: `SleepInput`, `ExerciseInput`, `CaffeineInput`, `ScreenInput`, `DietInput`, `HydrationInput`, `CircadianInput`, `DaylightInput`, `FastingInput`, `RecoveryInput`, `VitalsInput`, `HistoryInput`
  - Verify <!-- RESOLVED: M9 -->: `grep -c "^    struct \(SleepInput\|ExerciseInput\|CaffeineInput\|ScreenInput\|DietInput\|HydrationInput\|CircadianInput\|DaylightInput\|FastingInput\|RecoveryInput\|VitalsInput\|HistoryInput\) " WellPlate/Core/Services/StressScoring.swift` returns 12
- [ ] Add `enum Source { case healthKit, manual }`
- [ ] Add `struct StressInputs` containing all sub-structs + raw arrays per plan §1.1
- [ ] Add `struct StressResult { score; factors; driverSum; recovery; engagementPenalty; patternPenalty; calibrator; confidence; raw }`
- [ ] Add `struct CalibratorInputs { todayHRV; hrvBaseline; todayRHR; rhrBaseline }`
- [ ] Add `enum Confidence { case low, medium, high }` (with `var label: String` and `var systemImage: String`)
- [ ] Compile-check: `xcodebuild ... build 2>&1 | tail -30` — only StressViewModel-side errors expected

### 1.2 — Replace `Weights` enum

- [ ] In `StressScoring.swift`, replace `Weights` with v3 weight table per plan §1.2 (sleep 20, exercise 12, caffeine 10, screenTime 10, diet 8, hydration 5, circadian 5, daylight 3, mealTiming 4, fasting 3, eatingTriggers 5, mood 8, symptoms 7, recoveryCap −10, engagementCap 18, patternCap 12)
  - Verify <!-- RESOLVED: M1 -->: `grep -c "static let \(sleep\|exercise\|caffeine\|screenTime\|diet\|hydration\|circadian\|daylight\|mealTiming\|fasting\|eatingTriggers\|mood\|symptoms\): Double" WellPlate/Core/Services/StressScoring.swift` returns ≥ 13

### 1.3 — Implement Tier A factor functions

- [ ] Implement `static func sleepPoints(input: SleepInput?) -> FactorPoints` per formula spec §3.1
  - Verify: `grep "static func sleepPoints" WellPlate/Core/Services/StressScoring.swift` returns 1 match
  - Verify <!-- RESOLVED: H2 -->: `hasData = (input != nil)` (per plan §0.1: HK summary OR manual hours)
- [ ] Implement `static func exercisePoints(input: ExerciseInput?) -> FactorPoints` per formula spec §3.2
  - Verify <!-- RESOLVED: H2 -->: `hasData = (input != nil)` (per §0.1: HK steps>0 OR HK energy>0 OR manual minutes)
- [ ] Implement `static func caffeinePoints(input: CaffeineInput?) -> FactorPoints` with `mgPerCup = type?.caffeineMg ?? 80`; comment notes legacy data fallback
  - Verify: `grep "?? 80" WellPlate/Core/Services/StressScoring.swift` returns ≥ 1 match
  - Verify <!-- RESOLVED: H2 -->: `hasData = input.hasWellnessRow` (per §0.1: today's WellnessDayLog row exists)
- [ ] Implement `static func screenTimePoints(input: ScreenInput?) -> FactorPoints` per formula spec §3.4; evening multiplier no-op when `eveningHours == nil`
  - Verify <!-- RESOLVED: H2 -->: `hasData = (input != nil)` (auto reading OR manual)
- [ ] Implement `static func dietPoints(input: DietInput?, goals: UserGoals) -> FactorPoints` using **carbs proxy** (no sugar field)
  - Verify: `grep "carbsGoalGrams" WellPlate/Core/Services/StressScoring.swift` returns ≥ 1 match (no `sugarGoalGrams`)
  - Verify <!-- RESOLVED: H2 -->: `hasData = input.hasLogs` (per §0.1: ≥1 FoodLogEntry today)
- [ ] Add file-level comment near `dietPoints`: "Sugar dropped from formula in v3 (FoodLogEntry has no sugar field). Carbs ratio acts as proxy."

### 1.4 — Implement Tier B factor functions

- [ ] Implement `static func hydrationPoints(input: HydrationInput?, goal: Int) -> FactorPoints` with `goalSafe = max(goal, 1)`
  - Verify: `grep "max(goal, 1)" WellPlate/Core/Services/StressScoring.swift` returns ≥ 1 match
  - Verify <!-- RESOLVED: H2 -->: `hasData = input.hasWellnessRow` (per §0.1)
- [ ] Implement `static func circadianPoints(input: CircadianInput?) -> FactorPoints`
  - Verify <!-- RESOLVED: H2 -->: `hasData = input.hasEnoughData` (per §0.1)
- [ ] Implement `static func daylightPoints(input: DaylightInput?) -> FactorPoints` per formula spec §3.8
  - Verify <!-- RESOLVED: H2 -->: `hasData = (input != nil)` (HK minutes>0 OR manual toggle)
- [ ] Implement `static func mealTimingPoints(logs: [FoodLogEntry]) -> FactorPoints`; sort by `createdAt` first
  - Verify <!-- RESOLVED: H2 -->: `hasData = !logs.isEmpty`
- [ ] Implement `static func fastingPoints(input: FastingInput?) -> FactorPoints`
  - Verify <!-- RESOLVED: H2 -->: `hasData = input.isConfigured` (per §0.1)
- [ ] Implement `static func eatingTriggerPoints(logs: [FoodLogEntry]) -> FactorPoints`
  - Verify <!-- RESOLVED: H2 -->: `hasData = !logs.isEmpty`

### 1.5 — Implement Tier C factor functions

- [ ] Implement `static func moodPoints(mood: MoodOption?) -> FactorPoints` (range −2…+8)
  - Verify <!-- RESOLVED: H2 -->: `hasData = (mood != nil)`
- [ ] Implement `static func symptomPoints(entries: [SymptomEntry]) -> FactorPoints`; dedupe by `name` taking max severity; weights {.cognitive, .pain}=1.0, .energy=0.7, .digestive=0.5
  - Verify <!-- RESOLVED: H2 -->: `hasData = true` always (per §0.1: zero is meaningful)

### 1.5z — `hasData` policy checkpoint <!-- RESOLVED: H2 -->

- [ ] Re-read plan §0.1 (`hasData` policy table)
- [ ] Confirm every factor implementation matches §0.1 by grepping the function bodies:
  - [ ] `grep -A 5 "func caffeinePoints" StressScoring.swift` shows `hasData = input.hasWellnessRow` (not `cups > 0`)
  - [ ] `grep -A 5 "func symptomPoints" StressScoring.swift` shows `hasData = true` (or unconditional `true`)
  - [ ] `grep -A 5 "func hydrationPoints" StressScoring.swift` shows `hasData = input.hasWellnessRow` (not `glasses > 0`)
  - [ ] `grep -A 5 "func fastingPoints" StressScoring.swift` shows `hasData = input.isConfigured`

### 1.6 — Implement recovery functions

- [ ] Implement `static func interventionBonus(sessions: [InterventionSession]) -> Double` (cap −6)
- [ ] Implement `static func journalBonus(hasEntry: Bool) -> Double` (−2 / 0)
- [ ] Implement `static func mindfulBonus(hasMoodToday: Bool, hasMindfulSession: Bool) -> Double` (−2 / 0)
- [ ] Implement `static func recoveryTotal(_ inputs: RecoveryInput) -> Double` capping at `Weights.recoveryCap`

### 1.7 — Implement engagement penalty <!-- RESOLVED: M2 — per-gap enumeration -->

- [ ] Implement `static func engagementPenalty(inputs: StressInputs, now: Date) -> Double`
- [ ] Activation guard: `guard inputs.factors.contains(where: \.hasData) else { return 0 }`
  - Verify: `grep "hasAnyDriver\|contains(where:.*hasData" WellPlate/Core/Services/StressScoring.swift` returns ≥ 1
- [ ] Linear ramp helper: `func ramp(start: Double, end: Double) -> Double`
- [ ] Add gap: **no_mood** — max 5, 17:00→21:00, cond: `inputs.mood == nil`
- [ ] Add gap: **no_food** — max 4, 17:00→20:00, cond: `inputs.mealLogs.isEmpty`
- [ ] Add gap: **no_water** — max 4, 14:00→18:00, cond: `(inputs.hydration?.glasses ?? 0) == 0`
- [ ] Add gap: **low_steps** — max 3, 16:00→20:00, cond: `if let s = inputs.exercise?.steps, s < 2000` (nil-safe)
- [ ] Add gap: **no_reflection** — max 2, 18:00→21:00, cond: `!hasJournal && mood == nil && !hasMindful`
- [ ] Add code comment: "// hour-of-day uses Calendar.current → user's local TZ; DST handled by Calendar"
- [ ] Cap at `Weights.engagementCap` (18)

### 1.8 — Implement pattern penalty <!-- RESOLVED: M2 — per-pattern enumeration -->

- [ ] Implement `static func patternPenalty(history: HistoryInput) -> Double`
- [ ] Add pattern: **no_food_3d** — +4 if all 3 of {today, yesterday, 2-days-ago} have no FoodLogEntry
- [ ] Add pattern: **low_mood_3d** — +3 if all 3 days have `MoodOption(rawValue:) == .awful || .bad`
  - Verify: `grep "MoodOption(rawValue:" WellPlate/Core/Services/StressScoring.swift` returns ≥ 1
- [ ] Add pattern: **high_coffee_3d** — +3 if all 3 days have `coffeeCups ≥ 4`
- [ ] Add pattern: **no_fast_14d** — +2 if `lastCompletedFastEnd == nil || lastCompletedFastEnd < now − 14d`
- [ ] Cap at `Weights.patternCap` (12)

### 1.9 — Implement calibrator + baseline

- [ ] Implement `static func baseline14Day(_ samples: [DailyMetricSample], excludingToday now: Date) -> Double?`
- [ ] Defensive filter: `$0.date >= cutoff && $0.date < startOfToday && $0.value > 0`
  - Verify: `grep "< startOfToday" WellPlate/Core/Services/StressScoring.swift` returns ≥ 1 match
- [ ] Require ≥5 valid days
- [ ] Implement `static func calibrator(_ inputs: CalibratorInputs) -> Double`; clamp [0.90, 1.15]; collapse to 1.0 when no baseline

### 1.10 — Implement confidence (typealias deferred to §1.13a) <!-- RESOLVED: M3 -->

- [ ] Implement `static func confidence(factors: [FactorPoints]) -> Confidence` per formula spec §8 (weighted coverage)
  - Note: `typealias Confidence = StressScoring.Confidence` will be added inside `StressViewModel.swift` in §1.13a alongside other VM changes; do NOT touch `StressViewModel.swift` here.

### 1.11 — Implement `computeStress` orchestrator

- [ ] Implement `static func computeStress(inputs: StressInputs, now: Date) -> StressResult` per plan §1.11
- [ ] Build `factors: [FactorPoints]` array (13 entries)
- [ ] `driverSum = factors.filter(\.hasData).reduce(0) { $0 + $1.points }`
- [ ] Sum driver + recovery + engagement + pattern; floor at 0
- [ ] Apply calibrator; clamp final to [0, 100]
  - Verify: `grep "static func computeStress" WellPlate/Core/Services/StressScoring.swift` returns 1 match
- [ ] Compile-check: `StressScoring.swift` should compile clean (errors only in StressViewModel callers expected)

### 1.12 — Refactor `StressFactorResult`

- [ ] Open `WellPlate/Models/StressModels.swift`
- [ ] Change `let id = UUID()` to `var id: String { title }`
  - Verify: `grep "var id: String" WellPlate/Models/StressModels.swift` returns ≥ 1
- [ ] Add init: `init(from points: FactorPoints, title: String, icon: String, higherIsBetter: Bool)`
- [ ] Update `stressContribution`: `return hasValidData ? max(0, score) : 0`
- [ ] Update `.neutral(...)` factory signature: `static func neutral(title:, icon:, higherIsBetter:, maxScore: Double)` — remove hardcoded `25`
- [ ] Grep `.neutral(` callsites: `grep -rn "\.neutral(" WellPlate --include="*.swift"`
  - Verify: lists 4 callsites at `StressViewModel.swift:25-28`
- [ ] Update each `.neutral(...)` call with `maxScore: StressScoring.Weights.{factor}`

### 1.13a — `StressViewModel`: published properties + Confidence typealias <!-- RESOLVED: M3 -->

- [ ] Open `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
- [ ] Add `@Published var calibratorMultiplier: Double = 1.0`
- [ ] Add `@Published var engagementPenaltyValue: Double = 0`
- [ ] Add `@Published var patternPenaltyValue: Double = 0`
- [ ] Add `@Published var allFactors: [StressFactorResult] = []`
- [ ] Convert `var totalScore: Double { ... }` (computed) to `@Published var totalScore: Double = 0`
  - Verify: `grep "@Published var totalScore" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift` returns 1 match
  - Verify: no leftover computed `var totalScore: Double {` definition (should fail to compile if duplicate)
- [ ] Update `topStressors` to `prefix(5)`
- [ ] Replace existing `extension StressViewModel { enum Confidence ... }` with `typealias Confidence = StressScoring.Confidence`
- [ ] Grep `Confidence` callsites: `grep -rn "StressViewModel.Confidence\|\.Confidence\b" WellPlate --include="*.swift"`
  - Verify: list inspected; UI views compile after typealias

### 1.13b — `StressViewModel`: new SwiftData fetches

- [ ] In `loadData()`, after existing fetches, add:
  - [ ] Today's `[SymptomEntry]`: `FetchDescriptor<SymptomEntry>` with `entry.day == today`
  - [ ] Today's `JournalEntry` (presence): `FetchDescriptor<JournalEntry>` with `day == today`
  - [ ] Today's completed `[InterventionSession]`: predicate `completed == true && startedAt >= startOfToday`
  - [ ] Last-3-day `[WellnessDayLog]`: `day >= threeDaysAgo && day <= today`
  - [ ] Last-3-day `[FoodLogEntry]` grouped by day for `noFood3d`
  - [ ] Active `FastingSession`: `actualEndAt == nil`; compute `activeFastHours = (Date() − session.startedAt) / 3600`
  - [ ] Most recent completed `FastingSession`: `completed == true`, sort `actualEndAt` desc, prefix(1) → `lastCompletedFastEnd`
  - [ ] **Today's `ManualDailyInput`** (`@Model` from §1.0a): `FetchDescriptor<ManualDailyInput>(predicate: #Predicate { $0.day == today })` → first <!-- RESOLVED: C1 — type now exists -->

### 1.13c — `StressViewModel`: resolution helpers

- [ ] Add private `resolveSleep(hk:manual:) -> SleepInput?`:
  ```swift
  if let s = hk { return SleepInput(totalHours: s.totalHours, deepHours: s.deepHours, source: .healthKit) }
  guard let m = manual, let h = m.sleepHours else { return nil }
  let derivedDeep: Double = { switch m.sleepQuality ?? 3 { case 1: 0.25; case 2: 0.5; case 3: 0.75; case 4: 1.0; case 5: 1.33; default: 0.75 } }()
  return SleepInput(totalHours: h, deepHours: derivedDeep, source: .manual)
  ```
- [ ] Add private `resolveExercise(steps:energy:manual:) -> ExerciseInput?`
- [ ] Add private `resolveScreen(autoHours:manual:) -> ScreenInput?` with `eveningHours = (m.heavyEveningScreens == true) ? 2.0 : 0.0`
- [ ] Add private `resolveDaylight(hkMinutes:manual:) -> DaylightInput?` (HK minutes>0 → .healthKit; manual toggle → 30 or 5 min)
- [ ] Add private `resolveCircadian(hkSummaries:manualHistory:) -> CircadianInput?`
  - Verify: `grep "private func resolve" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift` returns 5 matches

### 1.13d — `StressViewModel`: build inputs, call computeStress, DELETE old builders <!-- RESOLVED: H4 -->

- [ ] Add private `buildInputs(now: Date) -> StressInputs` assembling sub-inputs
- [ ] Add private `buildInputsFromMockSnapshot(_ snapshot: StressMockSnapshot, now: Date) -> StressInputs`
  - Verify: `grep "buildInputsFromMockSnapshot" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift` returns 1 match
- [ ] In `loadData()`, replace existing factor-building code with:
  ```swift
  let inputs = usesMockData ? buildInputsFromMockSnapshot(mockSnapshot!, now: Date()) : buildInputs(now: Date())
  let result = StressScoring.computeStress(inputs: inputs, now: Date())
  totalScore = result.score
  calibratorMultiplier = result.calibrator
  engagementPenaltyValue = result.engagementPenalty
  patternPenaltyValue = result.patternPenalty
  allFactors = result.factors.enumerated().map { idx, fp in
      StressFactorResult(from: fp, title: factorTitle(idx), icon: factorIcon(idx), higherIsBetter: factorHigherIsBetter(idx))
  }
  ```
- [ ] **DELETE** the following private functions from `StressViewModel.swift`:
  - [ ] `private func buildExerciseFactor(...)` (currently ~line 565)
  - [ ] `private func buildSleepFactor(...)` (currently ~line 593)
  - [ ] `private func buildDietFactor(...)` (currently ~line 613)
  - [ ] `private func refreshScreenTimeFactor()` (currently ~line 635)
- [ ] **DELETE** the now-orphaned callsites in `loadData()` and `refreshDietFactor()` that assigned to `exerciseFactor`/`sleepFactor`/`dietFactor`/`screenTimeFactor` directly (currently lines ~251, 259, 269, 345, 361, 379)
  - Verify: `grep "buildExerciseFactor\|buildSleepFactor\|buildDietFactor\|refreshScreenTimeFactor" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift` returns **0 matches**
  - Verify: `grep "exerciseFactor =\|sleepFactor =\|dietFactor =\|screenTimeFactor =" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift` returns 0 *assignment* matches (the `@Published var exerciseFactor` declarations stay, but any `=` reassignments in `loadData()` must be gone)
- [ ] Optionally remove the per-factor `@Published var exerciseFactor`/`sleepFactor`/`dietFactor`/`screenTimeFactor` if no UI consumer needs them (StressView will read `allFactors` instead)
  - Audit consumers: `grep -rn "viewModel\.\(exerciseFactor\|sleepFactor\|dietFactor\|screenTimeFactor\)" WellPlate --include="*.swift"` — if any remain, keep the published vars and back them with `allFactors.first(where: { $0.title == ... })`

### 1.13e — `StressViewModel`: indicator drop verification <!-- RESOLVED: M10 -->

- [ ] Run `grep "heartRateHistory\|systolicBPHistory\|diastolicBPHistory\|respiratoryRateHistory" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift`
- [ ] **If any match appears inside `buildInputs(...)`, `loadData()` scoring path, or any factor function: REMOVE it** — these histories are display-only.
  - Verify: matches only appear in `@Published var ... History` declarations and history-fetch assignments (display path), never on the scoring path
- [ ] Confirm `hrvHistory` and `restingHRHistory` are passed only to `StressScoring.baseline14Day(...)` calls inside `buildInputs(...)`, never as direct factor inputs

### 1.14 — Add `recompute()` and refresh shims

- [ ] Add private cache vars: `lastSteps: Double?`, `lastEnergy: Double?`, `lastSleepSummary: DailySleepSummary?`, `lastHRVHistory: [DailyMetricSample] = []`, `lastRHRHistory: [DailyMetricSample] = []`, etc.
- [ ] In `loadData()`, populate cache after HK fetches complete
- [ ] Add `func recompute()`:
  - Re-fetches cheap SwiftData (mood/water/food/symptoms/journal/interventions/manual/recent wellness/active fast)
  - Reuses cached HK
  - Calls `buildInputs(now: Date())` → `computeStress` → publishes
  - Verify: `grep "func recompute" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift` returns 1 match
- [ ] Convert existing methods to thin shims:
  - `func refreshDietFactor() { recompute() }`
  - `func refreshScreenTimeOnly() { recompute() }`
  - `func refreshDietFactorAndLogIfNeeded() { recompute(); logCurrentStress(source: "auto") }`
- [ ] Update `logCurrentStress(source:)` to log `totalScore` (now stored)

### 1.15 — Wire engagement ticker via `StressTimerService` <!-- RESOLVED: H1 — forced StressTimerService.shared in P1 -->

- [ ] Create new file `WellPlate/Core/Services/StressTimerService.swift`:
  ```swift
  import Foundation
  import Combine

  @MainActor
  final class StressTimerService: ObservableObject {
      static let shared = StressTimerService()
      @Published var tickerPulse: Date = .distantPast
      private var cancellable: AnyCancellable?

      func start() {
          stop()
          cancellable = Timer.publish(every: 300, on: .main, in: .common)
              .autoconnect()
              .sink { [weak self] now in self?.tickerPulse = now }
      }

      func stop() {
          cancellable?.cancel()
          cancellable = nil
      }
  }
  ```
  - Verify: `ls WellPlate/Core/Services/StressTimerService.swift` exists; `grep "static let shared" WellPlate/Core/Services/StressTimerService.swift` returns 1
- [ ] In `WellPlate/App/RootView.swift`, observe `@Environment(\.scenePhase)` and call `StressTimerService.shared.start() / .stop()` on transitions
- [ ] In `StressViewModel.init(...)`, subscribe via Combine: store `private var tickerCancellable: AnyCancellable?` set to `StressTimerService.shared.$tickerPulse.sink { [weak self] _ in self?.recompute() }`
- [ ] Test: simulator at 16:30 → close app, advance system clock to 21:00 → reopen → engagement penalty visibly higher
  - Verify: `grep "tickerPulse\|StressTimerService" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift WellPlate/App/RootView.swift` returns matches in both files

### 1.16 — Indicator drop final check <!-- RESOLVED: M10 -->

- [ ] Already covered by §1.13e. As a final guard, run:
  - `grep -n "todayHeartRate\|todaySystolicBP\|todayDiastolicBP\|todayRespiratoryRate" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift`
  - **If any match appears inside `buildInputs`, factor calls, or `computeStress` invocation context — REMOVE.** Display-only properties may remain.

### 1.17 — Extend mock snapshot + mock HK service <!-- RESOLVED: M5 — enumerated -->

- [ ] Open `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
- [ ] Add fields: `mood: MoodOption?`, `todaySymptoms: [SymptomEntry]`, `todayJournal: JournalEntry?`, `todayInterventions: [InterventionSession]`, `recentWellnessLogs: [WellnessDayLog]`, `recentFoodLogs: [FoodLogEntry]`, `lastCompletedFastEnd: Date?`, `hrvSamples: [DailyMetricSample]` (≥7 days), `rhrSamples: [DailyMetricSample]` (≥7 days)
- [ ] Add 4 mock variants: `.fullyLoggedBalancedDay`, `.fullyLoggedBadDay`, `.disengagedBadDay21h`, `.dayOneNoData`
  - Verify: `grep -c "static let \(fullyLoggedBalancedDay\|fullyLoggedBadDay\|disengagedBadDay21h\|dayOneNoData\)" WellPlate/Features\ +\ UI/Stress/Support/StressMockSnapshot.swift` returns 4
- [ ] Open `WellPlate/Core/Services/MockHealthKitService.swift`
- [ ] Update each fetch method to project from new snapshot fields:
  - [ ] `fetchHRV(for:)` projects `snapshot.hrvSamples` filtered by range
  - [ ] `fetchRestingHeartRate(for:)` projects `snapshot.rhrSamples`
  - [ ] `fetchSteps(for:)` continues to project from existing snapshot fields
  - [ ] `fetchActiveEnergy(for:)` continues to project
  - [ ] `fetchDailySleepSummaries(for:)` continues to project
  - [ ] `fetchDaylight(for:)` continues to project
- [ ] Per-mock-variant smoke (in simulator via `MockDataDebugCard`):
  - [ ] `.fullyLoggedBalancedDay` → score range 0–20 ("Excellent")
  - [ ] `.fullyLoggedBadDay` → score 81–100 ("Very High")
  - [ ] `.disengagedBadDay21h` → score 61–80 ("High") with engagement penalty > 0
  - [ ] `.dayOneNoData` → score hidden (confidence low)
- [ ] Verify `MockDataInjector` and `Resources/MockData/*.json` still load (no exceptions in console)

### 1.18 — P1 build verification

- [ ] Build all 4 targets:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - All exit code 0

### 1.18b — Test target verification + StressScoringTests <!-- RESOLVED: H5 -->

- [ ] Run `xcodebuild -project WellPlate.xcodeproj -list` and confirm `WellPlate` scheme exists
- [ ] **Verify `WellPlateTests/` group is auto-syncing:**
  - [ ] `grep -A 3 "WellPlateTests" WellPlate.xcodeproj/project.pbxproj | grep "PBXFileSystemSynchronizedRootGroup"` returns ≥ 1 match → auto-syncing; new files included automatically
  - [ ] If 0 matches → not auto-syncing. Open Xcode, select `StressScoringTests.swift` (after creation), File Inspector → Target Membership → check `WellPlateTests`
- [ ] Run baseline tests:
  - [ ] `xcodebuild test -project WellPlate.xcodeproj -scheme WellPlate -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -20`
  - If "Scheme is not configured for testing" → open Xcode → Edit Scheme → Test action → enable `WellPlateTests` → mark scheme Shared → re-run
  - If still unwired → fall back to smoke checks via `MockDataDebugCard`; document as "unverified automated coverage" per CLAUDE.md
- [ ] Create `WellPlateTests/StressScoringTests.swift` with cases:
  - [ ] `testZeroInputReturnsLowConfidence()`
  - [ ] `testPerfectDayReturnsZero()`
  - [ ] `testWorstLoggedDayClampsTo100()`
  - [ ] `testMoodGreatStrictlyReducesScore()`
  - [ ] `testWaterEightStrictlyReducesScore()`
  - [ ] `testManualSleepEqualsHKEquivalent()`
  - [ ] `testCalibratorCollapsesWithoutBaseline()`
  - [ ] `testEngagementZeroBeforeStartHour()`
  - [ ] `testPatternPenaltyStableAcrossRecomputes()`
- [ ] **Confirm new test file is compiled:**
  - [ ] `xcodebuild test -project WellPlate.xcodeproj -scheme WellPlate -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WellPlateTests/StressScoringTests 2>&1 | tail -20` shows ≥ 1 test executed (not "no tests found")

### 1.19 — Phase 1 commit <!-- RESOLVED: L2 — optional doc footer -->

- [ ] `git add -A && git status` (review)
- [ ] `git commit -m "$(cat <<'EOF'
feat(stress): scoring core v3 - 13 driver factors, calibrator, engagement+pattern penalties

Plan: Docs/02_Planning/Specs/260509-stress-algorithm-v3-plan-RESOLVED.md
Checklist: Docs/04_Checklist/260509-stress-algorithm-v3-checklist-RESOLVED.md
EOF
)"`

---

## Phase 2 — Manual Fallback + Daily Overlays

### 2.0 — Add `onboardingCompletedAt` timestamp

- [ ] Open `WellPlate/Core/Services/UserProfileManager.swift`
- [ ] Add `case onboardingCompletedAt` to `Key` enum
- [ ] Add property:
  ```swift
  var onboardingCompletedAt: Date? {
      get { defaults.object(forKey: Key.onboardingCompletedAt.rawValue) as? Date }
      set { defaults.set(newValue, forKey: Key.onboardingCompletedAt.rawValue) }
  }
  ```
  - Verify: `grep "onboardingCompletedAt" WellPlate/Core/Services/UserProfileManager.swift` returns ≥ 3
- [ ] Open `WellPlate/Features + UI/Onboarding/OnboardingCompletionPage.swift`
- [ ] After existing `UserProfileManager.shared.hasCompletedOnboarding = true`, add: `UserProfileManager.shared.onboardingCompletedAt = .now`
  - Verify: `grep "onboardingCompletedAt = .now" WellPlate/Features\ +\ UI/Onboarding/OnboardingCompletionPage.swift` returns 1 match

### 2.0b — Create `TabSelector` EnvironmentObject <!-- RESOLVED: H7 -->

- [ ] Create new file `WellPlate/Core/Services/TabSelector.swift`:
  ```swift
  import SwiftUI

  enum TabKind: String { case home, burn, stress, profile }
  enum TabSheetKind: String, Identifiable { case water, foodLog
      var id: String { rawValue }
  }

  @MainActor
  final class TabSelector: ObservableObject {
      @Published var selectedTab: TabKind = .home
      @Published var presentedSheet: TabSheetKind? = nil

      func switchTo(_ tab: TabKind, andPresent sheet: TabSheetKind? = nil) {
          selectedTab = tab
          presentedSheet = sheet
      }
  }
  ```
- [ ] In `WellPlate/App/WellPlateApp.swift`, add `@StateObject private var tabSelector = TabSelector()` and inject via `.environmentObject(tabSelector)` alongside `promptCoordinator`
- [ ] In `WellPlate/Features + UI/Tab/MainTabView.swift`:
  - [ ] Add `@EnvironmentObject private var tabSelector: TabSelector`
  - [ ] Bind tab selection to `tabSelector.selectedTab` (existing iOS 18 `Tab` API supports `selection:` binding)
  - [ ] On selected tab's view, present sheet via `.sheet(item: $tabSelector.presentedSheet)` mapping to existing `WaterDetailView` / `MealLogView`
  - Verify: `grep "TabSelector" WellPlate/Features\ +\ UI/Tab/MainTabView.swift WellPlate/App/WellPlateApp.swift` returns ≥ 2 matches

### 2.1 — `ManualDailyInput` model — already created in §1.0a <!-- RESOLVED: C1 -->

- [ ] (Skipped — completed in §1.0a)

### 2.2 — ManualDailyInput registration — already done in §1.0b <!-- RESOLVED: C1 -->

- [ ] (Skipped — completed in §1.0b)

### 2.3 — Implement `DailyPromptCoordinator` <!-- RESOLVED: H3 — HK auth guard -->

- [ ] Create new file `WellPlate/Core/Services/DailyPromptCoordinator.swift`
- [ ] Add `@MainActor final class DailyPromptCoordinator: ObservableObject`
- [ ] Add `@Published var pendingPrompt: PromptKind?`
- [ ] Add `@Published var manualInputSavedAt: Date = .distantPast`
- [ ] Add `enum PromptKind: Identifiable` with morning/evening cases + gaps structs
- [ ] Implement `evaluateOnAppForeground(now:modelContext:healthService:) async`:
  - [ ] **Guard 1 (HK auth):** `guard healthService.isAuthorized else { return }` <!-- RESOLVED: H3 -->
    - Verify: `grep "isAuthorized" WellPlate/Core/Services/DailyPromptCoordinator.swift` returns ≥ 1
  - [ ] **Guard 2 (don't ask again):** `guard !UserDefaults.standard.bool(forKey: "wp.stress.dontAskAgain") else { return }`
  - [ ] **Guard 3 (24h grace):** `if let completedAt = UserProfileManager.shared.onboardingCompletedAt, now.timeIntervalSince(completedAt) < 24*3600 { return }`
  - [ ] **Resolve today's `ManualDailyInput`** via FetchDescriptor
  - [ ] **Hour ≥ 11 + sleep gaps:** if HK sleep silent and `manual?.sleepHours == nil` and `manual?.morningAskedAt == nil` → set `.morning(MorningGaps(needsSleep: true))`
  - [ ] **Hour ≥ 19 + evening gaps:** check HK screen/exercise/daylight; for each silent + corresponding manual nil → include in `EveningGaps`; if any → set `.evening(...)`
  - Verify: `grep "evaluateOnAppForeground" WellPlate/Core/Services/DailyPromptCoordinator.swift` returns 1 match
- [ ] Implement `recordSkip(_:modelContext:now:)` setting `morningAskedAt`/`eveningAskedAt`
- [ ] Implement `recordSave(_:values:modelContext:now:)` upserting `ManualDailyInput` and bumping `manualInputSavedAt`
- [ ] Implement `disableForever()` setting `wp.stress.dontAskAgain` true

### 2.4 — Implement `QuickCheckInSheet`

- [ ] Create new file `WellPlate/Shared/Components/QuickCheckInSheet.swift`
- [ ] Bottom-sheet `View` taking `kind: PromptKind` and `coordinator: DailyPromptCoordinator`
- [ ] Morning form: hours `Slider` 4.0–12.0; quality segmented 1–5; optional bedtime/wake `DatePicker`
- [ ] Evening form: screen hours `Stepper` (0.5 step); heavy-evening `Toggle`; exercise minutes `Stepper`; AM daylight `Toggle`; hide already-populated fields
- [ ] Three buttons: **Save** / **Skip for today** / **Don't ask again** wired to coordinator methods
- [ ] Use `.r(.headline, .semibold)` font and `.appShadow(...)` per CLAUDE.md
- [ ] `.presentationDetents([.medium])`
  - Verify: `ls WellPlate/Shared/Components/QuickCheckInSheet.swift` exists; `grep "presentationDetents" WellPlate/Shared/Components/QuickCheckInSheet.swift` returns 1

### 2.5 — Wire coordinator + scene observation

- [ ] Open `WellPlate/App/WellPlateApp.swift`
- [ ] Add `@StateObject private var promptCoordinator = DailyPromptCoordinator()`
- [ ] Inject into root: `RootView().environmentObject(promptCoordinator).environmentObject(tabSelector)`
  - Verify: `grep "promptCoordinator\|tabSelector" WellPlate/App/WellPlateApp.swift` returns ≥ 4 matches (state + 2 inject)
- [ ] Open `WellPlate/App/RootView.swift`
- [ ] Add `@EnvironmentObject private var promptCoordinator: DailyPromptCoordinator`
- [ ] Add `@Environment(\.modelContext) private var modelContext`
- [ ] Add `@Environment(\.scenePhase) private var scenePhase`
- [ ] In the `MainTabView` branch, attach:
  - `.sheet(item: $promptCoordinator.pendingPrompt) { kind in QuickCheckInSheet(kind: kind, coordinator: promptCoordinator) }`
  - `.onChange(of: scenePhase) { _, newPhase in ... }` calling `evaluateOnAppForeground` and `StressTimerService.shared.start()` / `.stop()` on transitions
  - Verify: `grep "evaluateOnAppForeground" WellPlate/App/RootView.swift` returns 1 match

### 2.6 — Add resolution priority in `StressViewModel` <!-- RESOLVED: M6 — circadian verify -->

- [ ] (Resolution helpers were added in §1.13c; here we wire manual data flow)
- [ ] Confirm `loadData()` already fetches today's `ManualDailyInput` (per §1.13b)
- [ ] In `buildInputs(now:)`, pass manual through `resolveSleep`, `resolveExercise`, `resolveScreen`, `resolveDaylight`, `resolveCircadian`
- [ ] For `resolveCircadian`: fetch last 7 days of `ManualDailyInput` (predicate `day >= sevenDaysAgo`); pass `manualHistory` array
  - Verify: smoke test on simulator — seed 5+ manual nights with bedtime/wakeTime → `circadianResult.hasEnoughData == true`; reduce to 3 → `false`

### 2.7 — Observe ManualDailyInput changes <!-- RESOLVED: M4 — cancellable storage -->

- [ ] In `StressViewModel`, add `private var manualInputCancellable: AnyCancellable?`
- [ ] In `init(...)`, accept `coordinator: DailyPromptCoordinator?` (optional for backwards compat)
- [ ] Subscribe: `manualInputCancellable = coordinator?.$manualInputSavedAt.dropFirst().sink { [weak self] _ in self?.recompute() }`
  - Verify: `grep "manualInputCancellable" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift` returns ≥ 1
- [ ] Confirm cancellation on deinit (implicit when AnyCancellable is set to nil or the holder deallocates)

### 2.8 — Add Profile toggle <!-- RESOLVED: M7 — also reset askedAt on re-enable -->

- [ ] Open `WellPlate/Features + UI/Tab/ProfileView.swift`
- [ ] Locate Section structure; create or position "Notifications & Prompts" `Section` below Goals
- [ ] Add row:
  ```swift
  Toggle("Daily check-in prompts", isOn: Binding(
      get: { !UserDefaults.standard.bool(forKey: "wp.stress.dontAskAgain") },
      set: { newValue in
          UserDefaults.standard.set(!newValue, forKey: "wp.stress.dontAskAgain")
          if newValue { clearTodayManualAskedFlags() }
      }
  ))
  ```
- [ ] Implement `clearTodayManualAskedFlags()` fetching today's `ManualDailyInput` and setting `morningAskedAt = nil; eveningAskedAt = nil`
  - Verify: simulator → toggle off then on → restart at 11:30 → morning prompt re-fires

### 2.9 — P2 build + smoke

- [ ] Build all 4 targets (commands as in 1.18)
- [ ] Simulator: deny HK auth in Settings:
  - [ ] System time 11:30 → reopen → morning prompt fires → save 6h sleep + quality 3 → score includes sleep contribution; logs show `source=manual`
- [ ] System time 19:30:
  - [ ] Reopen → evening prompt → "Skip for today" → close → reopen → no prompt
- [ ] "Don't ask again" → reopen → no prompt
- [ ] Profile toggle ON → restart at 11:30 → prompt returns

### 2.10 — Phase 2 commit

- [ ] `git add -A && git status`
- [ ] `git commit -m "feat(stress): manual fallback model + daily check-in overlays + tab selector"`

---

## Phase 3 — UI Surfacing

### 3.1 — Add new `StressSheet` cases <!-- RESOLVED: H6 — added .symptoms, .fasting -->

- [ ] Open `WellPlate/Features + UI/Stress/Views/StressView.swift` at line 12 (`StressSheet` enum)
- [ ] Add cases: `.allFactors`, `.manualLog`, `.mood`, `.symptoms`, `.fasting`
- [ ] Add `Identifiable` `id` impl for each
- [ ] In `.sheet(item: $activeSheet)` switch (~line 143), add handlers for each
  - Verify: `grep -c "case \.\(allFactors\|manualLog\|mood\|symptoms\|fasting\)" WellPlate/Features\ +\ UI/Stress/Views/StressView.swift` returns 5

### 3.2 — Build `CalibratorChip`

- [ ] Create new file `WellPlate/Features + UI/Stress/Components/CalibratorChip.swift`
- [ ] Pill `View` with 4 modes based on `(calibrator: Double, hasBaseline: Bool)`
- [ ] Use `.r(.caption, .semibold)`, adaptive blue tint
  - Verify: `ls WellPlate/Features + UI/Stress/Components/CalibratorChip.swift` exists

### 3.3 — Build `EngagementGapsCard` + `MoodCheckInSheet` <!-- RESOLVED: H7 — uses TabSelector -->

- [ ] Create new file `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift`
- [ ] Read `@EnvironmentObject var tabSelector: TabSelector`
- [ ] Card visible when `viewModel.engagementPenaltyValue > 0`
- [ ] CTAs:
  - [ ] **Mood gap CTA** → `activeSheet = .mood`
  - [ ] **Water gap CTA** → `tabSelector.switchTo(.home, andPresent: .water)`
  - [ ] **Food gap CTA** → `tabSelector.switchTo(.home, andPresent: .foodLog)`
  - [ ] **Steps gap CTA** → `tabSelector.switchTo(.burn)` (no sheet)
  - [ ] **Reflection gap CTA** → `activeSheet = .mood`
- [ ] Create new file `WellPlate/Shared/Components/MoodCheckInSheet.swift` — wraps existing `MoodCheckInCard` in sheet; on selection writes `WellnessDayLog.moodRaw`, dismisses
  - Verify: `ls WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift WellPlate/Shared/Components/MoodCheckInSheet.swift` both exist

### 3.4 — Refactor `StressView` header

- [ ] Below score gauge, horizontal `HStack` with `CalibratorChip` + confidence badge
- [ ] Confidence text: "X of 13 factors logged" using new weight-weighted formula

### 3.5 — Replace fixed 4-card grid with top-N drivers <!-- RESOLVED: H6 — full routing table -->

- [ ] In `StressView.swift` ~line 809, replace hardcoded array with:
  ```swift
  let topFactors = viewModel.allFactors
      .filter(\.hasValidData)
      .sorted { $0.stressContribution > $1.stressContribution }
      .prefix(5)
  ```
- [ ] In each card's `onTap`, switch on `factor.title` per this complete table:

  | Factor title | Sheet / Action |
  |---|---|
  | "Sleep" | `.sleep` |
  | "Exercise" | `.exercise` |
  | "Caffeine" | (non-tappable) |
  | "Screen Time" | `.screenTimeDetail` |
  | "Diet" | `.diet` |
  | "Hydration" | `tabSelector.switchTo(.home, andPresent: .water)` |
  | "Circadian" | `.sleep` (shared detail) |
  | "Daylight" | `.sleep` |
  | "Meal Timing" | `.diet` |
  | "Fasting" | `.fasting` |
  | "Eating Triggers" | (non-tappable) |
  | "Mood" | `.mood` |
  | "Symptoms" | `.symptoms` |

  - For non-tappable factors, omit the `onTap` handler (or pass nil)
  - Verify: `grep "switch factor.title\|switch.*\.title" WellPlate/Features\ +\ UI/Stress/Views/StressView.swift` returns ≥ 1

### 3.6 — Add Recovery section

- [ ] Below top-5 driver cards, "Recovery" `VStack` showing intervention/journal/mindful with "−X stress avoided" framing
- [ ] Hide section when total recovery == 0

### 3.7 — Add Engagement Gaps section

- [ ] Insert `EngagementGapsCard` between drivers and Recovery
- [ ] Hidden when `viewModel.engagementPenaltyValue == 0`

### 3.8 — Add "All factors" disclosure

- [ ] Footer button: "View all factors" → `activeSheet = .allFactors`
- [ ] Sheet handler renders `viewModel.allFactors` grouped by tier (A/B/C); rows show `points / maxPoints` bars with sign

### 3.9 — Add Quick Log button

- [ ] Anchored button at bottom of scroll: "Quick Log" → `activeSheet = .manualLog` → presents `QuickCheckInSheet`

### 3.10 — Update `StressFactorCardView`

- [ ] Show signed `points` (e.g., "+8" red, "−2" green)
- [ ] Add tier badge (A/B/C) top-right corner

### 3.11 — One-time announcement banner <!-- RESOLVED: M7 — dismiss persistence verify -->

- [ ] On `StressView.onAppear`, check `UserDefaults.standard.bool(forKey: "wp.stress.v3AnnouncementShown") == false`
- [ ] If false, show dismissible banner:
  > **Your stress score now considers mood, hydration, symptoms, and more — 13 factors total. Vitals like HRV are used to calibrate accuracy against your personal baseline.**
- [ ] On dismiss, set `UserDefaults.standard.set(true, forKey: "wp.stress.v3AnnouncementShown")`
- [ ] **Verify dismiss persistence:**
  - [ ] First launch → banner shown → dismiss → kill app → relaunch → banner does NOT re-appear
  - [ ] (Debug only — to reset for testing) `UserDefaults.standard.removeObject(forKey: "wp.stress.v3AnnouncementShown")`

### 3.12 — Verify Home + Widget integration

- [ ] Open `WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift`
- [ ] Verify it reads `viewModel.totalScore` (now `@Published var`)
- [ ] Open `WellPlate/Widgets/SharedStressData.swift`
- [ ] Verify widget receives latest `totalScore` via `WidgetRefreshHelper.refreshStress(viewModel:)` after recompute
  - Verify: `grep "totalScore" WellPlate/Widgets/SharedStressData.swift WellPlate/Features\ +\ UI/Home/Components/StressSparklineStrip.swift` returns matches in both
- [ ] Visual check: open Home tab → confirm sparkline; open widget gallery in WidgetKit preview

### 3.13 — P3 build + visual verification

- [ ] Build all 4 targets
- [ ] Toggle 4 mock variants via `MockDataDebugCard`:
  - [ ] `.fullyLoggedBalancedDay` → "Excellent"; calibrator chip "Vitals normal"
  - [ ] `.fullyLoggedBadDay` → "Very High"; calibrator chip strain
  - [ ] `.disengagedBadDay21h` → "High" with engagement-gaps card; CTAs route correctly
  - [ ] `.dayOneNoData` → score hidden, "Log to see your stress"
- [ ] Verify top-5 cards reorder when toggling
- [ ] Verify "All factors" disclosure groups by tier
- [ ] Verify Quick Log button opens `QuickCheckInSheet`
- [ ] Verify announcement banner shows once on first launch; dismisses cleanly

### 3.14 — Phase 3 commit

- [ ] `git add -A && git status`
- [ ] `git commit -m "feat(stress): UI v3 - top-N drivers, calibrator chip, engagement gaps card"`

---

## Post-Implementation

### Final build verification

- [ ] Build all 4 targets:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
- [ ] Run tests:
  - [ ] `xcodebuild test -project WellPlate.xcodeproj -scheme WellPlate -destination 'platform=iOS Simulator,name=iPhone 15'`

### Cross-cutting smoke checks

- [ ] **Mood logging changes score:** Log mood `awful` after 21:00 → score increases vs not logged; log mood `great` → score decreases visibly (~10 points)
- [ ] **Water logging changes score:** Log 8 glasses → hydration factor 0 pts; engagement gap closed
- [ ] **Symptom logging changes score:** Log 3 symptoms severity 7+ → score moves to High/Very High
- [ ] **HK-denied user:** Deny HK in Settings → reopen at 11:30 → morning prompt → save sleep → score reflects manual sleep
- [ ] **Day-1 user:** Fresh install → no prompts for 24h → score hidden until first driver logged
- [ ] **Pattern penalty:** Mock seed 3 days no food → re-open → engagement card or all-factors view shows pattern penalty
- [ ] **Calibrator effect:** Mock with HRV 25% below baseline → calibrator chip "+12% strain"
- [ ] **Ticker effect:** 16:30 → close → advance system clock to 21:00 → reopen → engagement penalty visibly higher

### Cross-tab CTA navigation smoke <!-- RESOLVED: L3 -->

- [ ] Engagement card visible → tap **Water** CTA → app switches to Home tab and presents `WaterDetailView` → back → returns to Stress tab
- [ ] Engagement card visible → tap **Food** CTA → app switches to Home + `MealLogView` → back → Stress tab
- [ ] Engagement card visible → tap **Steps** CTA → app switches to Burn tab → back → Stress tab
- [ ] Engagement card visible → tap **Mood** CTA → modal `MoodCheckInSheet` → save → score updates
- [ ] Top-5 driver card → tap **Symptoms** → opens `.symptoms` sheet
- [ ] Top-5 driver card → tap **Fasting** → opens `.fasting` sheet

### Formula §10 reactivity examples <!-- RESOLVED: L1 -->

Use mock variant `.disengagedBadDay21h` (sleep 5h/30min deep, water 0, no other inputs, time 21:00, vitals normal):

- [ ] Initial S ≈ 36 ("Good" bordering "Moderate")
- [ ] Log mood `awful` → S decreases by ~1 (engagement closes more than mood factor adds)
- [ ] Reset; log mood `great` → S decreases by ~10–11
- [ ] Reset; log water 1 glass → S increases by ~1 (driver +5 vs engagement −4)
- [ ] Mock with HRV 25% below baseline → S increases by ~5

Allow ±2 points tolerance for floating-point/threshold variance.

### Validation checklist verification (formula spec §14)

- [ ] All 9 XCTests in `StressScoringTests.swift` pass

### Final commit / branch

- [ ] Confirm working tree clean: `git status`
- [ ] Final branch state: `git log --oneline main..HEAD` shows 3 commits (P1 / P2 / P3)
- [ ] Open PR (when user asks) — do NOT push or open PR autonomously
