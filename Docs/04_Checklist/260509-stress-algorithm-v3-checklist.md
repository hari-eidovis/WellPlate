# Implementation Checklist: Stress Algorithm v3

**Source Plan:** [260509-stress-algorithm-v3-plan-RESOLVED.md](../02_Planning/Specs/260509-stress-algorithm-v3-plan-RESOLVED.md)
**Audit:** [260509-stress-algorithm-v3-plan-audit.md](../03_Audits/260509-stress-algorithm-v3-plan-audit.md)
**Brainstorm:** [260509-stress-algorithm-v3-brainstorm.md](../01_Brainstorming/260509-stress-algorithm-v3-brainstorm.md)
**Formula:** [260509-stress-formula-spec.md](../01_Brainstorming/260509-stress-formula-spec.md)
**Date:** 2026-05-09

---

## Pre-Implementation

- [ ] Read the resolved plan end-to-end; skim brainstorm + formula spec for context
- [ ] Create a feature branch: `git checkout -b feat/stress-algorithm-v3`
- [ ] Verify all referenced files exist:
  - [ ] `WellPlate/Core/Services/StressScoring.swift`
  - [ ] `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - [ ] `WellPlate/Models/StressModels.swift`
  - [ ] `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
  - [ ] `WellPlate/Core/Services/MockHealthKitService.swift`
  - [ ] `WellPlate/App/WellPlateApp.swift`
  - [ ] `WellPlate/App/RootView.swift`
  - [ ] `WellPlate/Features + UI/Tab/ProfileView.swift`
  - [ ] `WellPlate/Features + UI/Onboarding/OnboardingCompletionPage.swift`
  - [ ] `WellPlate/Core/Services/UserProfileManager.swift`
  - [ ] `WellPlate/Features + UI/Stress/Views/StressView.swift`
  - [ ] `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift`
- [ ] Confirm baseline build is green:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build` exits 0
- [ ] Note: per CLAUDE.md, no pbxproj edits needed for new files under `WellPlate/`

---

## Phase 1 — Scoring Core

### 1.1 — Define data structs in `StressScoring.swift`

- [ ] Open `WellPlate/Core/Services/StressScoring.swift`
- [ ] Replace file contents with new structure starting with `import Foundation`
- [ ] Add `struct FactorPoints { points; maxPoints; hasData; detail; static let none }`
  - Verify: `grep "struct FactorPoints" WellPlate/Core/Services/StressScoring.swift` returns one match
- [ ] Add input sub-structs: `SleepInput`, `ExerciseInput`, `CaffeineInput`, `ScreenInput`, `DietInput`, `HydrationInput`, `CircadianInput`, `DaylightInput`, `FastingInput`, `RecoveryInput`, `VitalsInput`, `HistoryInput`
  - Verify: `grep -c "^    struct .*Input " WellPlate/Core/Services/StressScoring.swift` returns 12
- [ ] Add `enum Source { case healthKit, manual }`
- [ ] Add `struct StressInputs` containing all sub-structs + raw arrays per plan §1.1
- [ ] Add `struct StressResult { score; factors; driverSum; recovery; engagementPenalty; patternPenalty; calibrator; confidence; raw }`
- [ ] Add `struct CalibratorInputs { todayHRV; hrvBaseline; todayRHR; rhrBaseline }`
- [ ] Add `enum Confidence { case low, medium, high }` (per plan §1.10)
- [ ] Compile-check: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30`
  - Verify: only StressViewModel-side errors expected (its old `Confidence` extension still references things); proceed

### 1.2 — Replace `Weights` enum

- [ ] In `StressScoring.swift`, replace existing `Weights` with v3 weight table from plan §1.2 (sleep 20, exercise 12, caffeine 10, screenTime 10, diet 8, hydration 5, circadian 5, daylight 3, mealTiming 4, fasting 3, eatingTriggers 5, mood 8, symptoms 7, recoveryCap −10, engagementCap 18, patternCap 12)
  - Verify: `grep "static let sleep: Double = 20" WellPlate/Core/Services/StressScoring.swift` returns one match

### 1.3 — Implement Tier A factor functions

- [ ] Implement `static func sleepPoints(input: SleepInput?) -> FactorPoints` per formula spec §3.1 (hours_term + deep_term, cap 20)
  - Verify: `grep "static func sleepPoints" WellPlate/Core/Services/StressScoring.swift` returns one match
- [ ] Implement `static func exercisePoints(input: ExerciseInput?) -> FactorPoints` per formula spec §3.2; `activity = max(steps/7000, energy/400)`; if both nil and `manualMinutes != nil`, use `Double(manualMinutes! * 100) / 7000.0`
- [ ] Implement `static func caffeinePoints(input: CaffeineInput?) -> FactorPoints` with `mgPerCup = type?.caffeineMg ?? 80`; comment notes legacy data fallback
  - Verify: `grep "?? 80" WellPlate/Core/Services/StressScoring.swift` returns at least one match
- [ ] Implement `static func screenTimePoints(input: ScreenInput?) -> FactorPoints` per formula spec §3.4; evening multiplier no-op when `eveningHours == nil`
- [ ] Implement `static func dietPoints(input: DietInput?, goals: UserGoals) -> FactorPoints` using **carbs proxy** (no sugar field): `let carbsGoal = max(goals.carbsGoalGrams, 1)`; `carbRatio = input.carbs / Double(carbsGoal)`; thresholds 0.8/1.0/1.5 → 0/1/lerp/5
  - Verify: `grep "carbsGoalGrams" WellPlate/Core/Services/StressScoring.swift` returns at least one match (no `sugarGoalGrams` reference in StressScoring)
- [ ] Add file-level comment near `dietPoints` documenting the v3 limitation: "Sugar dropped from formula in v3 (FoodLogEntry has no sugar field). Carbs ratio acts as proxy."

### 1.4 — Implement Tier B factor functions

- [ ] Implement `static func hydrationPoints(input: HydrationInput?, goal: Int) -> FactorPoints` with `goalSafe = max(goal, 1)`
  - Verify: `grep "max(goal, 1)" WellPlate/Core/Services/StressScoring.swift` returns at least one match
- [ ] Implement `static func circadianPoints(input: CircadianInput?) -> FactorPoints`; `hasData = input.hasEnoughData`
- [ ] Implement `static func daylightPoints(input: DaylightInput?) -> FactorPoints` per formula spec §3.8
- [ ] Implement `static func mealTimingPoints(logs: [FoodLogEntry]) -> FactorPoints`; sort by `createdAt` first
- [ ] Implement `static func fastingPoints(input: FastingInput?) -> FactorPoints`; `hasData = input.isConfigured`
- [ ] Implement `static func eatingTriggerPoints(logs: [FoodLogEntry]) -> FactorPoints`

### 1.5 — Implement Tier C factor functions

- [ ] Implement `static func moodPoints(mood: MoodOption?) -> FactorPoints` (range −2…+8)
- [ ] Implement `static func symptomPoints(entries: [SymptomEntry]) -> FactorPoints`; dedupe by `name` taking max severity; weights {.cognitive, .pain}=1.0, .energy=0.7, .digestive=0.5; `hasData = true` always

### 1.6 — Implement recovery functions

- [ ] Implement `static func interventionBonus(sessions: [InterventionSession]) -> Double` (cap −6)
- [ ] Implement `static func journalBonus(hasEntry: Bool) -> Double` (−2 / 0)
- [ ] Implement `static func mindfulBonus(hasMoodToday: Bool, hasMindfulSession: Bool) -> Double` (−2 / 0)
- [ ] Implement `static func recoveryTotal(_ inputs: RecoveryInput) -> Double` capping at `Weights.recoveryCap`

### 1.7 — Implement engagement penalty

- [ ] Implement `static func engagementPenalty(inputs: StressInputs, now: Date) -> Double` per plan §1.7
- [ ] Activation guard: `guard inputs.factors.contains(where: \.hasData) else { return 0 }` (use the per-§0.1 hasData policy)
  - Verify: `grep "hasAnyDriver" WellPlate/Core/Services/StressScoring.swift` returns at least one match
- [ ] `low_steps` cond: `if let steps = inputs.exercise?.steps, steps < 2000 { ... }` (nil-safe)
- [ ] Linear ramp helper: `func ramp(start: Double, end: Double) -> Double { ... clamp ... }`
- [ ] Add code comment: "// hour-of-day uses Calendar.current → user's local TZ; DST handled by Calendar"
- [ ] Cap at `Weights.engagementCap` (18)

### 1.8 — Implement pattern penalty

- [ ] Implement `static func patternPenalty(history: HistoryInput) -> Double` per formula spec §6
- [ ] `lowMood3d` predicate uses enum cases: `MoodOption(rawValue: log.moodRaw ?? -1) == .awful || ... == .bad`
  - Verify: `grep "MoodOption(rawValue:" WellPlate/Core/Services/StressScoring.swift` returns at least one match
- [ ] Cap at `Weights.patternCap` (12)

### 1.9 — Implement calibrator + baseline

- [ ] Implement `static func baseline14Day(_ samples: [DailyMetricSample], excludingToday now: Date) -> Double?`
- [ ] Defensive filter: `$0.date >= cutoff && $0.date < startOfToday && $0.value > 0`
  - Verify: `grep "< startOfToday" WellPlate/Core/Services/StressScoring.swift` returns at least one match
- [ ] Require ≥5 valid days: `guard valid.count >= 5 else { return nil }`
- [ ] Implement `static func calibrator(_ inputs: CalibratorInputs) -> Double`; clamp [0.90, 1.15]; collapse to 1.0 when no baseline

### 1.10 — Implement confidence + typealias

- [ ] Implement `static func confidence(factors: [FactorPoints]) -> Confidence` per formula spec §8
- [ ] Open `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
- [ ] Replace existing `extension StressViewModel { enum Confidence ... }` with `typealias Confidence = StressScoring.Confidence`
- [ ] Grep for `Confidence` callsites: `grep -rn "StressViewModel.Confidence\|\.Confidence\b" WellPlate --include="*.swift"`
  - Verify: list inspected; UI views (`StressView.swift`) compile after typealias
- [ ] Optionally keep `var label: String { ... }` and `var systemImage: String { ... }` as extension properties on the typealiased enum

### 1.11 — Implement `computeStress` orchestrator

- [ ] Implement `static func computeStress(inputs: StressInputs, now: Date) -> StressResult` per plan §1.11
- [ ] Build `factors: [FactorPoints]` array (13 entries)
- [ ] `driverSum = factors.filter(\.hasData).reduce(0) { $0 + $1.points }`
- [ ] Sum driver + recovery + engagement + pattern; floor at 0
- [ ] Apply calibrator; clamp final to [0, 100]
- [ ] Return `StressResult` with all sub-fields populated
  - Verify: `grep "static func computeStress" WellPlate/Core/Services/StressScoring.swift` returns one match
- [ ] Compile-check: `xcodebuild ... build` — `StressScoring.swift` should compile clean (errors only in StressViewModel callers expected)

### 1.12 — Refactor `StressFactorResult`

- [ ] Open `WellPlate/Models/StressModels.swift`
- [ ] Change `let id = UUID()` to `var id: String { title }`
  - Verify: `grep "var id: String" WellPlate/Models/StressModels.swift` returns at least one match
- [ ] Add init: `init(from points: FactorPoints, title: String, icon: String, higherIsBetter: Bool)`
- [ ] Update `stressContribution`: `return hasValidData ? max(0, score) : 0` (signed `points` already correct; recovery captured separately via `RecoveryInput`)
- [ ] Update `.neutral(...)` factory signature to take `maxScore: Double` parameter; remove hardcoded `25`
- [ ] Grep all `.neutral(` callsites: `grep -rn "\.neutral(" WellPlate --include="*.swift"`
  - Verify: lists 4 callsites at `StressViewModel.swift:25-28`
- [ ] Update each `.neutral(...)` call with `maxScore: StressScoring.Weights.{factor}`

### 1.13a — `StressViewModel`: add new published properties

- [ ] Open `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
- [ ] Add: `@Published var calibratorMultiplier: Double = 1.0`
- [ ] Add: `@Published var engagementPenaltyValue: Double = 0`
- [ ] Add: `@Published var patternPenaltyValue: Double = 0`
- [ ] Add: `@Published var allFactors: [StressFactorResult] = []`
- [ ] Convert `var totalScore: Double { ... }` (computed) to `@Published var totalScore: Double = 0` (stored)
  - Verify: `grep "@Published var totalScore" WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` returns one match
- [ ] Update `topStressors` to `prefix(5)` instead of `prefix(2)`

### 1.13b — `StressViewModel`: add new SwiftData fetches

- [ ] In `loadData()`, after existing fetches, add fetch for today's `[SymptomEntry]` (predicate: `entry.day == today`)
- [ ] Add fetch for today's `JournalEntry` (presence): `FetchDescriptor<JournalEntry>` with `day == today`
- [ ] Add fetch for today's completed `[InterventionSession]`: predicate `completed == true && startedAt >= startOfToday`
- [ ] Add fetch for last-3-day `[WellnessDayLog]`: predicate `day >= threeDaysAgo && day <= today`
- [ ] Add fetch for last-3-day `[FoodLogEntry]` grouped by day for `noFood3d` predicate
- [ ] Add fetch for active `FastingSession`: `FetchDescriptor<FastingSession>` predicate `actualEndAt == nil` (per H7 resolution)
  - Compute: `let activeFastHours = activeSession.map { Date().timeIntervalSince($0.startedAt) / 3600 }`
- [ ] Add fetch for most recent completed `FastingSession`: predicate `completed == true`, sort `actualEndAt` desc, prefix(1) → `lastCompletedFastEnd`
- [ ] Add fetch for today's `ManualDailyInput` (P2 will populate; P1 always nil)

### 1.13c — `StressViewModel`: implement resolution helpers

- [ ] Add private `resolveSleep(hk:manual:) -> SleepInput?` per plan §2.6
- [ ] Add private `resolveExercise(steps:energy:manual:) -> ExerciseInput?`
- [ ] Add private `resolveScreen(autoHours:manual:) -> ScreenInput?` with `eveningHours = (m.heavyEveningScreens == true) ? 2.0 : 0.0`
- [ ] Add private `resolveDaylight(hkMinutes:manual:) -> DaylightInput?`
- [ ] Add private `resolveCircadian(hkSummaries:manualHistory:) -> CircadianInput?`
  - Verify: `grep "private func resolve" WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` returns 5 matches

### 1.13d — `StressViewModel`: build `StressInputs` and call `computeStress`

- [ ] Add private `buildInputs(now: Date) -> StressInputs` assembling sub-inputs from cached HK + cheap SwiftData
- [ ] Add private `buildInputsFromMockSnapshot(_ snapshot: StressMockSnapshot, now: Date) -> StressInputs`
  - Verify: `grep "buildInputsFromMockSnapshot" WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` returns one match
- [ ] In `loadData()`, replace existing factor builders with:
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

### 1.13e — `StressViewModel`: drop indicator scoring

- [ ] Verify (mostly): `grep "heartRateHistory\|systolicBPHistory\|diastolicBPHistory\|respiratoryRateHistory" WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` shows only display usages, no scoring path
- [ ] Confirm `hrvHistory` and `restingHRHistory` are used only by `baseline14Day` calls

### 1.14 — Add `recompute()` and refresh shims

- [ ] Add private cache vars: `lastSteps: Double?`, `lastEnergy: Double?`, `lastSleepSummary: DailySleepSummary?`, `lastHRVHistory: [DailyMetricSample]`, `lastRHRHistory: [DailyMetricSample]`, etc.
- [ ] In `loadData()`, populate cache after HK fetches complete
- [ ] Add `func recompute()` that:
  - Re-fetches cheap SwiftData (mood/water/food/symptoms/journal/interventions/manual/recent wellness/active fast)
  - Reuses cached HK
  - Calls `buildInputs(now: Date())` → `computeStress` → publishes
  - Verify: `grep "func recompute" WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` returns one match
- [ ] Convert existing methods to thin shims:
  - `func refreshDietFactor() { recompute() }`
  - `func refreshScreenTimeOnly() { recompute() }`
  - `func refreshDietFactorAndLogIfNeeded() { recompute(); logCurrentStress(source: "auto") }`
- [ ] Update `logCurrentStress(source:)` to log `totalScore` (now stored)

### 1.15 — Wire engagement ticker at scene level

- [ ] Decide ticker host: extend `DailyPromptCoordinator` (clean ownership) OR add `StressTimerService.shared`
- [ ] Implementation: add `@Published var tickerPulse: Date = .distantPast` on chosen host
- [ ] Use `Timer.publish(every: 300, on: .main, in: .common).autoconnect()` while `.scenePhase == .active`; cancel on `.background` / `.inactive`
- [ ] In `StressViewModel`, observe `tickerPulse` via Combine and call `recompute()` on change
- [ ] Test: change system clock by 5 minutes in simulator; verify score updates without input change
  - Verify: `grep "tickerPulse" WellPlate/Core/Services/DailyPromptCoordinator.swift` (or `StressTimerService.swift`) returns at least one match

### 1.16 — Verify indicator drop (scoring side)

- [ ] Run `grep -n "todayHeartRate\|todaySystolicBP\|todayDiastolicBP\|todayRespiratoryRate" WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - Verify: still published for display, but never appear in `buildInputs` or factor functions

### 1.17 — Extend mock snapshot + mock HK service

- [ ] Open `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
- [ ] Add fields: `mood: MoodOption?`, `todaySymptoms: [SymptomEntry]`, `todayJournal: JournalEntry?`, `todayInterventions: [InterventionSession]`, `recentWellnessLogs: [WellnessDayLog]`, `recentFoodLogs: [FoodLogEntry]`, `lastCompletedFastEnd: Date?`, `hrvSamples: [DailyMetricSample]` (≥7 days), `rhrSamples: [DailyMetricSample]` (≥7 days)
- [ ] Add 4 mock variants: `.fullyLoggedBalancedDay`, `.fullyLoggedBadDay`, `.disengagedBadDay21h`, `.dayOneNoData`
  - Verify: `grep -c "static let fullyLogged\|static let disengaged\|static let dayOne" WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` returns 4
- [ ] Open `WellPlate/Core/Services/MockHealthKitService.swift`
- [ ] Update `fetchHRV(for:)` to project `snapshot.hrvSamples` filtered by range
- [ ] Update `fetchRestingHeartRate(for:)` to project `snapshot.rhrSamples`
- [ ] Verify other fetch methods still align with snapshot fields
- [ ] Verify `MockDataInjector` and `Resources/MockData/*.json` still load:
  - Open mock data debug card in simulator → toggle each variant → confirm score changes

### 1.18 — P1 build verification

- [ ] Build all 4 targets:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - All exit code 0

### 1.18b — Test target verification + StressScoringTests

- [ ] Run `xcodebuild -project WellPlate.xcodeproj -list` and confirm `WellPlate` scheme exists
- [ ] Run `xcodebuild test -project WellPlate.xcodeproj -scheme WellPlate -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -20`
  - If existing nutrition tests run → scheme is wired; proceed
  - If "Scheme is not configured for testing" → open Xcode, edit scheme, mark `WellPlateTests` test action enabled, mark scheme Shared, rerun
  - If still unwired → fall back to `MockDataDebugCard` smoke checks; document as "unverified automated coverage" per CLAUDE.md
- [ ] Create `WellPlateTests/StressScoringTests.swift` with cases:
  - [ ] `testZeroInputReturnsLowConfidence()` — `computeStress` on empty inputs → `confidence == .low`
  - [ ] `testPerfectDayReturnsZero()` — fully-balanced day → score ≤ 5
  - [ ] `testWorstLoggedDayClampsTo100()` — maxed-out bad day → score == 100
  - [ ] `testMoodGreatStrictlyReducesScore()` — same inputs with mood=nil vs mood=.great → great is lower
  - [ ] `testWaterEightStrictlyReducesScore()` — same inputs with water=0 vs water=8 (after 18:00) → 8 is lower
  - [ ] `testManualSleepEqualsHKEquivalent()` — manual SleepInput with same hours/deep as HK → identical p_sleep
  - [ ] `testCalibratorCollapsesWithoutBaseline()` — `CalibratorInputs(nil, nil, nil, nil)` → 1.0
  - [ ] `testEngagementZeroBeforeStartHour()` — `engagementPenalty(at 10:00)` → 0
  - [ ] `testPatternPenaltyStableAcrossRecomputes()` — same `HistoryInput` on consecutive calls → identical result
- [ ] Run tests:
  - [ ] `xcodebuild test -project WellPlate.xcodeproj -scheme WellPlate -destination 'platform=iOS Simulator,name=iPhone 15'` exits 0

### 1.19 — Phase 1 commit

- [ ] `git add -A && git status` (review)
- [ ] `git commit -m "feat(stress): scoring core v3 - 13 driver factors, calibrator, engagement+pattern penalties"`

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
  - Verify: `grep "onboardingCompletedAt" WellPlate/Core/Services/UserProfileManager.swift` returns at least 3 matches (case + getter + setter context)
- [ ] Open `WellPlate/Features + UI/Onboarding/OnboardingCompletionPage.swift`
- [ ] Find existing `UserProfileManager.shared.hasCompletedOnboarding = true`; immediately after, add: `UserProfileManager.shared.onboardingCompletedAt = .now`
  - Verify: `grep "onboardingCompletedAt = .now" WellPlate/Features + UI/Onboarding/OnboardingCompletionPage.swift` returns one match

### 2.1 — Create `ManualDailyInput` model

- [ ] Create new file `WellPlate/Models/ManualDailyInput.swift` with `@Model` class per plan §2.1
- [ ] Fields: `day`, `sleepHours`, `sleepQuality`, `bedtime`, `wakeTime`, `screenTimeHours`, `heavyEveningScreens`, `exerciseMinutes`, `amDaylightOutside`, `morningAskedAt`, `eveningAskedAt`, `createdAt`
- [ ] `@Attribute(.unique) var day: Date`
  - Verify: `ls WellPlate/Models/ManualDailyInput.swift` exists; `grep "@Attribute(.unique)" WellPlate/Models/ManualDailyInput.swift` returns one match

### 2.2 — Register in ModelContainer

- [ ] Open `WellPlate/App/WellPlateApp.swift`
- [ ] At line 34 (or current `.modelContainer(for: [...])` array), append `ManualDailyInput.self`
  - Verify: `grep "ManualDailyInput.self" WellPlate/App/WellPlateApp.swift` returns one match

### 2.3 — Implement `DailyPromptCoordinator`

- [ ] Create new file `WellPlate/Core/Services/DailyPromptCoordinator.swift`
- [ ] Add `@MainActor final class DailyPromptCoordinator: ObservableObject` with `@Published var pendingPrompt: PromptKind?`
- [ ] Add `enum PromptKind: Identifiable { case morning(MorningGaps); case evening(EveningGaps) }`
- [ ] Add `@Published var manualInputSavedAt: Date = .distantPast` for VM observation
- [ ] Implement `evaluateOnAppForeground(now:modelContext:healthService:) async`:
  - [ ] Check `UserDefaults.standard.bool(forKey: "wp.stress.dontAskAgain")` → return early
  - [ ] Check `UserProfileManager.shared.onboardingCompletedAt`; if within 24h → return early
  - [ ] Resolve today's `ManualDailyInput`
  - [ ] Hour ≥ 11 + sleep gaps → set `.morning(MorningGaps(needsSleep: true))`
  - [ ] Hour ≥ 19 + screen/exercise/daylight gaps → set `.evening(...)`
  - Verify: `grep "evaluateOnAppForeground" WellPlate/Core/Services/DailyPromptCoordinator.swift` returns one match
- [ ] Implement `recordSkip(_:modelContext:now:)` setting `morningAskedAt`/`eveningAskedAt`
- [ ] Implement `recordSave(_:values:modelContext:now:)` upserting `ManualDailyInput` and bumping `manualInputSavedAt`
- [ ] Implement `disableForever()` setting `wp.stress.dontAskAgain` true

### 2.4 — Implement `QuickCheckInSheet`

- [ ] Create new file `WellPlate/Shared/Components/QuickCheckInSheet.swift`
- [ ] Bottom-sheet `View` taking `kind: PromptKind` and `coordinator: DailyPromptCoordinator`
- [ ] Morning form: hours `Slider` 4.0–12.0; quality segmented 1–5; optional bedtime/wake `DatePicker`
- [ ] Evening form: screen hours `Stepper` (0.5 step); heavy-evening `Toggle`; exercise minutes `Stepper`; AM daylight `Toggle`. Hide fields where corresponding HK data already populated.
- [ ] Three buttons:
  - [ ] **Save** → calls `coordinator.recordSave(...)`
  - [ ] **Skip for today** → calls `coordinator.recordSkip(...)`
  - [ ] **Don't ask again** → calls `coordinator.disableForever()` and `recordSkip(...)`
- [ ] Use `.r(.headline, .semibold)` font and `.appShadow(...)` per CLAUDE.md
- [ ] `.presentationDetents([.medium])`
  - Verify: `ls WellPlate/Shared/Components/QuickCheckInSheet.swift` exists; `grep "presentationDetents" WellPlate/Shared/Components/QuickCheckInSheet.swift` returns one match

### 2.5 — Wire coordinator + scene observation

- [ ] Open `WellPlate/App/WellPlateApp.swift`
- [ ] Add `@StateObject private var promptCoordinator = DailyPromptCoordinator()`
- [ ] Inject into root: `RootView().environmentObject(promptCoordinator)`
  - Verify: `grep "promptCoordinator" WellPlate/App/WellPlateApp.swift` returns at least 2 matches
- [ ] Open `WellPlate/App/RootView.swift`
- [ ] Add `@EnvironmentObject private var promptCoordinator: DailyPromptCoordinator`
- [ ] Add `@Environment(\.modelContext) private var modelContext`
- [ ] Add `@Environment(\.scenePhase) private var scenePhase`
- [ ] In the `MainTabView` branch, attach:
  - `.sheet(item: $promptCoordinator.pendingPrompt) { kind in QuickCheckInSheet(kind: kind, coordinator: promptCoordinator) }`
  - `.onChange(of: scenePhase) { _, newPhase in if newPhase == .active && !showSplash && !showOnboarding { Task { await promptCoordinator.evaluateOnAppForeground(now: Date(), modelContext: modelContext, healthService: HealthKitServiceFactory.shared) } } }`
  - Verify: `grep "evaluateOnAppForeground" WellPlate/App/RootView.swift` returns one match

### 2.6 — Add resolution priority to `StressViewModel`

- [ ] Re-open `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
- [ ] In `loadData()`, after HK fetches, fetch today's `ManualDailyInput` via `FetchDescriptor<ManualDailyInput>(predicate: #Predicate { $0.day == startOfToday }).first`
- [ ] In `buildInputs(now:)`, pass manual input through `resolveSleep`, `resolveExercise`, `resolveScreen`, `resolveDaylight`, `resolveCircadian` (helpers added in 1.13c)
  - For `resolveCircadian`, fetch last 7 days of `ManualDailyInput` history if HK insufficient

### 2.7 — Observe ManualDailyInput changes in `StressViewModel`

- [ ] In `StressViewModel.init(...)`, add Combine subscription to `coordinator.$manualInputSavedAt` (pass coordinator as init parameter or via `EnvironmentObject` accessed on first appearance)
- [ ] On change, call `recompute()` with `[weak self]`
  - Verify: `grep "manualInputSavedAt" WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` returns at least one match

### 2.8 — Add Profile toggle

- [ ] Open `WellPlate/Features + UI/Tab/ProfileView.swift`
- [ ] Find existing Section structure; create or locate "Notifications & Prompts" `Section` below Goals section
- [ ] Add row:
  ```swift
  Toggle("Daily check-in prompts", isOn: Binding(
      get: { !UserDefaults.standard.bool(forKey: "wp.stress.dontAskAgain") },
      set: { newValue in
          UserDefaults.standard.set(!newValue, forKey: "wp.stress.dontAskAgain")
          if newValue {
              // Re-enable: clear today's askedAt to allow re-prompting
              clearTodayManualAskedFlags()
          }
      }
  ))
  ```
- [ ] Implement `clearTodayManualAskedFlags()` that fetches today's `ManualDailyInput` and sets `morningAskedAt = nil; eveningAskedAt = nil`
  - Verify: open simulator → Profile → toggle off then on → next morning prompt re-fires after restart

### 2.9 — P2 build + smoke

- [ ] Build all 4 targets (commands as in 1.18)
- [ ] On simulator, deny HK auth in Settings:
  - [ ] Set system time to 11:30 → reopen app → morning prompt fires
  - [ ] Save 6h sleep + quality 3 → close sheet
  - [ ] Verify: stress score includes sleep contribution; debug logs show `source=manual`
- [ ] Set system time to 19:30:
  - [ ] Reopen app → evening prompt fires
  - [ ] Tap "Skip for today" → close → reopen → no prompt
- [ ] Tap "Don't ask again" → reopen → no prompt
- [ ] In Profile, toggle ON → restart app at 11:30 → prompt returns

### 2.10 — Phase 2 commit

- [ ] `git add -A && git status`
- [ ] `git commit -m "feat(stress): manual fallback model + daily check-in overlays"`

---

## Phase 3 — UI Surfacing

### 3.1 — Add new `StressSheet` cases

- [ ] Open `WellPlate/Features + UI/Stress/Views/StressView.swift` at line 12 (`StressSheet` enum)
- [ ] Add cases: `.allFactors`, `.manualLog`, `.mood`, `.water`, `.foodLog`, `.burnTab`
- [ ] Add `Identifiable` `id` impls for each new case
- [ ] In the `.sheet(item: $activeSheet)` switch (around line 143), add handlers for each new case
  - Verify: `grep -c "case \." WellPlate/Features + UI/Stress/Views/StressView.swift` shows the enum has 6+ new cases

### 3.2 — Build `CalibratorChip`

- [ ] Create new file `WellPlate/Features + UI/Stress/Components/CalibratorChip.swift`
- [ ] Pill `View` with 4 modes based on `(calibrator: Double, hasBaseline: Bool)`:
  - [ ] cal < 1.0 + baseline → "HRV {X}% above baseline" (green-tinted)
  - [ ] cal > 1.0 + baseline → "Vitals strain {X}%" (warm-tinted)
  - [ ] cal == 1.0 + baseline → "Vitals normal"
  - [ ] no baseline → "Calibration in {N} days" or "Watch-less"
- [ ] Use `.r(.caption, .semibold)`, adaptive blue tint matching app theme
  - Verify: `ls WellPlate/Features + UI/Stress/Components/CalibratorChip.swift` exists

### 3.3 — Build `EngagementGapsCard` + `MoodCheckInSheet` wrapper

- [ ] Create new file `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift`
- [ ] Card visible when `viewModel.engagementPenaltyValue > 0`
- [ ] List active gaps with: icon + label + current penalty value + CTA button
  - [ ] Mood gap CTA → `activeSheet = .mood`
  - [ ] Water gap CTA → trigger tab switch to Home + `WaterDetailView` (use deep-link mechanism in `RootView`)
  - [ ] Food gap CTA → tab switch + `MealLogView`
  - [ ] Steps gap CTA → tab switch to Burn tab
  - [ ] Reflection gap CTA → `activeSheet = .mood`
- [ ] Create new file `WellPlate/Shared/Components/MoodCheckInSheet.swift`
- [ ] Thin wrapper presenting `MoodCheckInCard` in a sheet; on selection, write `WellnessDayLog.moodRaw` and dismiss
  - Verify: `ls WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift WellPlate/Shared/Components/MoodCheckInSheet.swift` both exist

### 3.4 — Refactor `StressView` header

- [ ] In `StressView.body`, below the score gauge, add horizontal `HStack` with `CalibratorChip` + confidence badge
- [ ] Update confidence badge text to show "X of 13 factors logged" using new weight-weighted coverage

### 3.5 — Replace fixed 4-card grid with top-N drivers

- [ ] In `StressView.swift` around line 809–828 (existing fixed array), replace with:
  ```swift
  let topFactors = viewModel.allFactors
      .filter(\.hasValidData)
      .sorted { $0.stressContribution > $1.stressContribution }
      .prefix(5)
  ```
- [ ] In each card's `onTap`, use `switch factor.title` to map to `StressSheet` case (per L3 acceptance):
  - "Sleep" → `.sleep`
  - "Exercise" → `.exercise`
  - "Diet" → `.diet`
  - "Screen Time" → `.screenTimeDetail`
  - "Mood" → `.mood`
  - "Hydration" → `.water`
  - "Symptoms" → existing symptom history sheet
  - …etc
  - Verify: `grep "switch factor.title\|switch.*title" WellPlate/Features + UI/Stress/Views/StressView.swift` returns at least one match

### 3.6 — Add Recovery section

- [ ] Below top-5 driver cards in `StressView`, add "Recovery" `VStack` showing:
  - "−6 from 2 reset sessions" (when `interventionBonus < 0`)
  - "−2 journal written"
  - "−2 mindful check-in"
- [ ] Hide section when total recovery == 0

### 3.7 — Add Engagement Gaps section

- [ ] Insert `EngagementGapsCard` between top-5 drivers and Recovery section
- [ ] Hidden when `viewModel.engagementPenaltyValue == 0`

### 3.8 — Add "All factors" disclosure

- [ ] Add footer button in `StressView`: "View all factors" → sets `activeSheet = .allFactors`
- [ ] In sheet handler for `.allFactors`, render full `viewModel.allFactors` grouped by tier:
  - Tier A — Foundational
  - Tier B — Modulators
  - Tier C — Subjective
- [ ] Each row shows `points / maxPoints` bar (with sign)

### 3.9 — Add Quick Log button

- [ ] Add anchored button at bottom of `StressView` scroll content: "Quick Log" → sets `activeSheet = .manualLog`
- [ ] In sheet handler, present `QuickCheckInSheet(kind: ..., coordinator: ...)` from P2

### 3.10 — Update `StressFactorCardView`

- [ ] Open `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift`
- [ ] Show signed `points` (e.g., "+8" with red tint, "−2" with green tint, "0" neutral)
- [ ] Add small tier badge (A/B/C) in top-right corner
- [ ] Keep existing layout otherwise

### 3.11 — One-time announcement banner

- [ ] In `StressView.onAppear`, check `UserDefaults.standard.bool(forKey: "wp.stress.v3AnnouncementShown") == false`
- [ ] If false, show dismissible banner at top with text:
  > **Your stress score now considers mood, hydration, symptoms, and more — 13 factors total. Vitals like HRV are used to calibrate accuracy against your personal baseline.**
- [ ] On dismiss, set `UserDefaults.standard.set(true, forKey: "wp.stress.v3AnnouncementShown")`

### 3.12 — Verify Home + Widget integration

- [ ] Open `WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift`
- [ ] Verify it reads `viewModel.totalScore` (now `@Published var`); compile-check
- [ ] Open `WellPlate/Widgets/SharedStressData.swift`
- [ ] Verify widget receives latest `totalScore` via `WidgetRefreshHelper.refreshStress(viewModel:)` after every recompute
  - Verify: `grep "totalScore" WellPlate/Widgets/SharedStressData.swift WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift` returns matches in both
- [ ] Visual check on simulator: open Home tab, confirm sparkline; open widget gallery in WidgetKit preview

### 3.13 — P3 build + visual verification

- [ ] Build all 4 targets (commands as in 1.18)
- [ ] On simulator, toggle through 4 mock variants via `MockDataDebugCard`:
  - [ ] `.fullyLoggedBalancedDay` → score "Excellent"; calibrator chip shows "Vitals normal"
  - [ ] `.fullyLoggedBadDay` → "Very High"; calibrator chip shows strain
  - [ ] `.disengagedBadDay21h` → "High" with engagement gaps card visible; CTAs route correctly
  - [ ] `.dayOneNoData` → score hidden, "Log to see your stress"
- [ ] Verify top-5 driver cards reorder when toggling variants
- [ ] Verify "All factors" disclosure groups by tier
- [ ] Verify Quick Log button opens `QuickCheckInSheet` outside auto-prompt windows
- [ ] Verify announcement banner shows once on first launch after build; dismisses cleanly

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
- [ ] **Water logging changes score:** Log 8 glasses → hydration factor shows 0 pts and engagement gap closed
- [ ] **Symptom logging changes score:** Log 3 symptoms severity 7+ → score moves to High/Very High range
- [ ] **HK-denied user:** Deny HK in Settings → reopen at 11:30 → morning prompt → save sleep → score reflects manual sleep
- [ ] **Day-1 user:** Fresh install → no prompts for 24h → score hidden until first driver logged
- [ ] **Pattern penalty:** Use mock to seed 3 days no food → re-open → engagement card or all-factors view shows pattern penalty
- [ ] **Calibrator effect:** Mock with HRV 25% below baseline → calibrator chip reflects "+12% strain"
- [ ] **Ticker effect:** Open app at 16:30, leave on Home tab, advance system clock to 21:00, switch to Stress tab → engagement penalty visibly higher than at 16:30

### Validation checklist verification (formula spec §14)

- [ ] All 9 XCTests in `StressScoringTests.swift` pass

### Final commit / branch

- [ ] Confirm working tree clean: `git status`
- [ ] Final branch state: `git log --oneline main..HEAD` shows 3 commits (P1 / P2 / P3)
- [ ] Open PR (when user asks) — do NOT push or open PR autonomously
