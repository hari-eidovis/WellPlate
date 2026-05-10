# Plan Audit Report: Stress Algorithm v3

**Audit Date:** 2026-05-09
**Plan Version:** [260509-stress-algorithm-v3-plan.md](../02_Planning/Specs/260509-stress-algorithm-v3-plan.md)
**Auditor:** audit agent
**Verdict:** **NEEDS REVISION**

---

## Executive Summary

The plan is structurally sound, well-phased, and grounded in a clear formula spec. However, it has **3 critical issues that block implementation as written**: a missing `sugar` field in `FoodLogEntry` that the formula depends on, a SwiftUI `@StateObject` initialization conflict in `RootView` that prevents the coordinator from accessing `modelContext`, and an underspecified `hasData` policy across factor functions that will create inconsistent score behavior. There are 9 high-priority issues, 12 medium, and 3 low. The plan also assumes a test target that exists but is not verified to be wired into a shared scheme.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. `FoodLogEntry` lacks a `sugar` field — `dietPoints` formula cannot be computed

- **Location:** Plan §1.3 (Tier A diet function); Formula spec §3.5
- **Problem:** Formula spec §3.5 computes `sugar_term` from `sugar_g / sugarGoal`. Verified via grep: `WellPlate/Models/Food Log Entry/FoodLogEntry.swift` has only `calories, protein, carbs, fat, fiber` — **no `sugar` field**. Same for `NutritionalInfo`. Historical food log entries cannot retroactively gain sugar values.
- **Impact:** As planned, `dietPoints` always reports `sugar_term = 0`. The factor reduces to "+3 if protein < 50% goal, else 0" — only 3 of 8 max points are reachable. Diet factor is silently neutered, and the plan claims it covers 8 pts of the budget.
- **Recommendation:** Pick one before P1:
  - **(A)** Drop sugar from the formula. Use carbs as proxy: replace `sugar_ratio` with `carb_ratio = carbs_g / carbsGoal` and re-tune the thresholds against `UserGoals.carbsGoalGrams = 220`. Documented in spec as a v3 limitation.
  - **(B)** Add `sugar: Double` field to `FoodLogEntry` with a SwiftData migration; update `NutritionalInfo` and `NutritionService` providers (Groq + mock) to populate it; old rows default to 0. ~1 day extra work, more accurate.
  - **(C)** Approximate sugar = `carbs × 0.30` for legacy rows; new rows could populate from API. Risky — average sugar/carbs ratio varies wildly by food type.

  **Recommended: (A)** — keeps P1 small, documents the limitation, defers the model migration to a future phase.

#### C2. `hasData` policy underspecified for ~7 factors — score behavior will be inconsistent

- **Location:** Plan §1.3–§1.5; Formula spec §3 (silent on `H_f` for most factors)
- **Problem:** The plan instructs implementing "factor functions returning `FactorPoints` with `hasData`" but neither the plan nor the formula spec specifies when `hasData = true` for several factors. Concrete ambiguities:
  - **Caffeine:** `WellnessDayLog.coffeeCups` defaults to 0 even on never-opened days. Is "0 cups" data ("no caffeine today") or absence ("user didn't engage with the coffee tile")? Affects coverage and confidence.
  - **Hydration:** Same issue — `waterGlasses` defaults to 0.
  - **Eating triggers:** No food logs → `hasData`? (No — but the plan doesn't say.)
  - **Meal timing:** No food logs → `hasData`?
  - **Symptoms:** Zero symptoms is good. Should be `hasData = true` (logged = "I have no symptoms today") or `hasData = false` (no signal)?
  - **Mood:** Easy — `hasData = (mood != nil)`.
  - **Fasting:** No active session → `hasData`? Probably true ("not fasting"), value 0.
- **Impact:** Inconsistent across factors, breaks coverage math, makes confidence opaque, makes "fully logged day" hard to reason about. UI will show some factors as "No data" when user actually behaved fine.
- **Recommendation:** Add a §3.14 **`hasData` policy table** to the formula spec before P1 starts. Suggested rules:

  | Factor | `hasData = true` when |
  |---|---|
  | Sleep | HK summary OR manual hours present |
  | Exercise | HK steps>0 OR HK energy>0 OR manual minutes present |
  | Caffeine | `WellnessDayLog` row exists for today (any user interaction) |
  | Screen time | ScreenTime auto reading OR manual hours present |
  | Diet | ≥1 `FoodLogEntry` today |
  | Hydration | `WellnessDayLog` row exists for today |
  | Circadian | `circadianResult.hasEnoughData` |
  | Daylight | HK minutes>0 OR manual toggle set |
  | Meal timing | ≥1 `FoodLogEntry` today |
  | Fasting | `FastingService.currentState != .notConfigured` |
  | Eating triggers | ≥1 `FoodLogEntry` today |
  | Mood | `WellnessDayLog.moodRaw != nil` |
  | Symptoms | always `true` (logging zero is meaningful) |

  This needs to land in the strategy or a `RESOLVED` plan revision before P1.

#### C3. `RootView` cannot inject `modelContext` into `DailyPromptCoordinator` `@StateObject` as written

- **Location:** Plan §2.5
- **Problem:** Plan specifies `@StateObject private var promptCoordinator = DailyPromptCoordinator(...)` initialized inline. `@StateObject` runs at `View` struct init, before `@Environment(\.modelContext)` is available. Verified: `RootView.swift` currently has zero `@Environment` declarations. The plan also says "init with `HealthKitServiceFactory.shared`, `modelContext`, `.standard`" — `modelContext` cannot be referenced at struct init time in a SwiftUI view.
- **Impact:** Implementation step 2.5 cannot be executed verbatim. Build will fail.
- **Recommendation:** Pick one:
  - **(A)** Move `@StateObject` ownership up to `WellPlateApp` (which is where `.modelContainer(...)` is defined; ModelContainer can be retrieved synchronously and passed in). Pass coordinator down as `.environmentObject(...)`.
  - **(B)** Initialize coordinator without context, and inject context via a method: `coordinator.attach(modelContext:)` called from `RootView.task { ... }` after `@Environment(\.modelContext)` is resolved.
  - **(C)** Make coordinator's methods take `modelContext` as a parameter; coordinator owns no SwiftData state itself.

  **Recommended: (A)** — cleanest scope, single owner of coordinator across both `RootView` and `MainTabView`.

---

### HIGH (Should Fix Before Proceeding)

#### H1. Caching policy contradiction in `recompute()` (§1.13 vs §1.14)

- **Location:** Plan §1.13 ("Build `StressInputs` from all sources"), §1.14 ("Cache the last-built `StressInputs`")
- **Problem:** §1.13 fetches everything fresh in `loadData()`. §1.14 says `recompute()` reuses a cached `StressInputs` — but mood, water, food, symptoms, journal, intervention sessions can all change outside the VM (via Home tab logging, Symptom sheets, etc.). A cached input bag goes stale immediately.
- **Impact:** Score won't update when user logs mood from Home tab; ticker recomputes use stale data.
- **Recommendation:** `recompute()` re-fetches the cheap SwiftData portions (mood, water, food, symptoms, journal, interventions) every call but reuses the most recent HK fetch (which is expensive and async). Document this split explicitly in §1.14.

#### H2. Engagement timer wired to `StressView` lifecycle, but Home tab also reads `totalScore`

- **Location:** Plan §1.15
- **Problem:** Plan attaches start/stop ticker to `StressView` `onAppear`/`onDisappear`. But `StressSparklineStrip` on Home tab consumes `viewModel.totalScore` (verified earlier in conversation). When user is on Home tab, ticker is stopped → engagement ramps don't update → Home sparkline is stale.
- **Impact:** Score on Home tab doesn't advance as time passes; user sees inconsistency between Home and Stress tabs.
- **Recommendation:** Wire ticker to `.scenePhase` in `WellPlateApp` or `RootView`, not `StressView`. Cancel on `.background` / `.inactive`, restart on `.active`. `StressViewModel` is already `@MainActor`; ticker can be on the VM lifecycle (deinit-cancel) with start/stop driven by scene phase.

#### H3. `StressFactorResult.id = UUID()` regenerated each rebuild — top-N reorder breaks SwiftUI animation

- **Location:** Plan §3.5; existing code at `WellPlate/Models/StressModels.swift:75`
- **Problem:** `StressFactorResult` has `let id = UUID()` generated at struct init. Every `recompute()` produces fresh structs with new UUIDs. SwiftUI's `ForEach` cannot identify factors across rebuilds → cards remount on every recompute → no smooth reorder animation when ranks change → flicker.
- **Impact:** P3 UX is degraded; the "top-5 driver cards reorder" success criterion fails visually.
- **Recommendation:** Change `StressFactorResult.id: String` (or use `Hashable` conformance) and derive `id` from `title` (factor name is unique). Update §1.12 to include this. Also audit existing `ForEach` usages in `StressView.swift` to ensure they use the new id.

#### H4. Test target verification missing — XCTest plan unverifiable

- **Location:** Plan §1.18, §2.9, §3.13, "Testing Strategy"
- **Problem:** Plan references creating `WellPlateTests/StressScoringTests.swift`. Verified: `WellPlateTests/` directory exists with `GeminiNutritionProviderTests.swift`, `MealLogViewModelTranscriptionTests.swift`, `MockNutritionProviderTests.swift`, `NutritionServiceTests.swift`. **The test target is not confirmed to be wired into a shared scheme.** CLAUDE.md mandates: "Verify via build-only. If test files exist but aren't wired into shared schemes, report as unverified automated coverage."
- **Impact:** XCTest cases written may not execute via `xcodebuild test`. Validation checklist (formula spec §14) becomes unverifiable.
- **Recommendation:** Before P1, run `xcodebuild test -project WellPlate.xcodeproj -scheme WellPlate -destination 'platform=iOS Simulator,name=iPhone 15'` to verify. If no test scheme exists, plan should add a step to either (a) wire `WellPlateTests` into a shared scheme, or (b) downgrade tests to mock-snapshot smoke checks executed in `MockDataDebugCard`. Update §1.18, §2.9, §3.13 accordingly.

#### H5. Onboarding 24h grace period requires a timestamp that doesn't exist

- **Location:** Plan §2.3 (`DailyPromptCoordinator.evaluateOnAppForeground`)
- **Problem:** Plan specifies "Suppress prompts within 24h of onboarding completion." Verified: `UserProfileManager.hasCompletedOnboarding` is a `Bool` only; no completion timestamp is persisted.
- **Impact:** Cannot implement the grace period as described. Day-1 users will be prompted minutes after finishing onboarding, breaking the "first launch ever" success criterion.
- **Recommendation:** Add `onboardingCompletedAt: Date?` to `UserProfileManager`, set when `hasCompletedOnboarding` flips true (in `OnboardingCompletionPage.swift`). Coordinator reads it; if `nil` (legacy users), treat as long-completed (no grace). Add this as a step in §2.3.

#### H6. `StressMockSnapshot` consumers extend beyond `StressViewModel`

- **Location:** Plan §1.17
- **Problem:** Verified: `MockHealthKitService` consumes `StressMockSnapshot`, and `MainTabView.swift:29` injects `StressMockSnapshot.default` into `MockHealthKitService` AND `StressViewModel`. Plan §1.17 only mentions extending mock for the new fields in the snapshot itself but doesn't enumerate downstream changes.
- **Impact:** `MockHealthKitService.fetchHRV()` etc. need to expose 14-day baselines (multiple days of samples), not just today's value. The plan's "add HRV/RHR baseline fields" to snapshot is not enough — `MockHealthKitService.fetchHRV(for: range)` must return data with sufficient density for `baseline14Day` to compute (≥5 valid days).
- **Recommendation:** Expand §1.17 to: (a) add multi-day HRV/RHR sample arrays to `StressMockSnapshot`, (b) update `MockHealthKitService` fetch methods to project these arrays, (c) verify `MockDataInjector` and any seeded `Resources/MockData/*.json` files don't break. Add explicit smoke check.

#### H7. `FastingService` does not expose elapsed-fast hours

- **Location:** Plan §1.4 (fasting factor); §1.13 ("Most recent completed `FastingSession.actualEndAt`")
- **Problem:** Verified: `FastingService` exposes `currentState` (`FastingState` enum), `progress`, `timeRemaining`. **No public `elapsedHours` for an active fast.** `currentSchedule` and `activeSession` are private. `FastingSession.actualEndAt` is set only when fast ends, so it can't tell us how long a *current* fast has been running.
- **Impact:** `p_fasting` cannot be computed without exposing more state from `FastingService` or fetching `FastingSession` directly from SwiftData and computing elapsed = `now - startedAt` for active sessions.
- **Recommendation:** Update §1.13 to fetch active `FastingSession` from SwiftData (`FetchDescriptor<FastingSession> { $0.actualEndAt == nil }`) and compute `activeFastHours = (now - startedAt) / 3600`. Avoids touching `FastingService` API.

#### H8. Engagement-gap CTAs route to non-modal components (`MoodCheckInCard` is embedded, not a sheet)

- **Location:** Plan §3.3 (CTAs route to "existing flows")
- **Problem:** Plan glosses over the routing. Verified: `MoodCheckInCard` is a component used inline in HomeView; it has no standalone presentation. Tapping "Log mood" from `EngagementGapsCard` on `StressView` cannot just present it — needs a wrapping sheet OR a tab switch + scroll to mood card.
- **Impact:** P3 acceptance criterion ("CTAs route to corresponding logger") cannot be implemented as described without additional infrastructure.
- **Recommendation:** Add an explicit step in §3.3 to wrap `MoodCheckInCard` in a `MoodCheckInSheet` view (just a sheet container) OR add a `StressSheet.mood` case that presents it inline. Same audit needed for "Log water" (currently `WaterDetailView` is a tab destination) and "Log food" (tab switch). Pre-decide each routing target.

#### H9. Caffeine factor `hasData` semantics for "0 cups today" undefined (subset of C2 but high-impact)

- **Location:** Plan §1.3
- **Problem:** Different from generic C2 because caffeine has the most user-visible behavior. If `hasData = (cups > 0)`, then a user who deliberately had no coffee gets penalized in coverage and confidence. If `hasData = true` always, a brand-new user with zero `WellnessDayLog` rows gets `+0` caffeine signal "for free" without ever opening the coffee UI.
- **Impact:** Confidence math is wrong either way.
- **Recommendation:** Tie `hasData` to existence of today's `WellnessDayLog` row, not to `cups > 0`. The row only exists if user opened the app and interacted with the wellness tracking. This is consistent with the C2 policy.

---

### MEDIUM (Fix During Implementation)

#### M1. Division-by-zero risk in `hydrationPoints` if `waterDailyCups = 0`

- **Location:** Formula spec §3.6
- **Recommendation:** Guard with `Double(max(goal, 1))` everywhere a goal is in the denominator (hydration, diet sugar/protein, exercise activity). Caffeine already uses `max` in the formula spec; align hydration and diet.

#### M2. `AppConfig.mockMode` flow not addressed in v3 pipeline

- **Location:** Plan §1.13
- **Problem:** Existing `StressViewModel` has dual paths: `if usesMockData { ... } else { ... }`. Plan §1.13 doesn't specify whether `computeStress` should run in both modes or whether mock mode bypasses the new pipeline. The `refreshDietFactor()` snippet in current code shows mock mode shortcuts.
- **Recommendation:** Mock mode should now build `StressInputs` from the snapshot (just like real mode builds from HK + SwiftData) and call the same `computeStress`. This single-pipeline approach is testable. Add a sub-step: `buildInputsFromMockSnapshot(_ snapshot:)`.

#### M3. `eveningHours` derivation from manual `heavyEveningScreens` toggle not specified

- **Location:** Plan §2.6 (`resolveScreen`)
- **Recommendation:** Specify: `eveningHours = heavyEveningScreens == true ? 2.0 : 0.0`. Document that manual evening signal is binary by design.

#### M4. `VitalsInput` and `HistoryInput` structs not fully specified

- **Location:** Plan §1.1
- **Problem:** Plan declares them as members of `StressInputs` but doesn't define their fields.
- **Recommendation:** Add explicit field lists:
  ```swift
  struct VitalsInput {
      let todayHRV: Double?
      let hrvHistory: [DailyMetricSample]
      let todayRHR: Double?
      let rhrHistory: [DailyMetricSample]
      var calibratorInputs: CalibratorInputs { ... }
  }
  struct HistoryInput {
      let recentWellnessLogs: [WellnessDayLog]      // last 3 days
      let foodLogPresenceByDay: [Date: Bool]        // last 3 days
      let lastCompletedFastEnd: Date?
  }
  ```

#### M5. Renaming `refreshDietFactor()` cascades to multiple Views

- **Location:** Plan §1.14 ("rename them to `recomputeAfter*Change`")
- **Problem:** `refreshDietFactor()`, `refreshScreenTimeOnly()` are called from non-stress views (e.g., HomeView when food logged). Plan claims "rename for clarity" but doesn't enumerate callsites or risk.
- **Recommendation:** Either keep the existing names and have them call `recompute()` internally (zero callsite churn), or grep all callsites and add to the affected-files list. Risk should be Medium not Low.

#### M6. `Confidence` enum migration callsite audit missing

- **Location:** Plan §1.10
- **Problem:** Plan moves `Confidence` from `StressViewModel.Confidence` to `StressScoring`. Existing `StressView` and possibly `Insight` views reference it.
- **Recommendation:** Add a step: grep `Confidence` callsites; add typealias `typealias Confidence = StressScoring.Confidence` in StressViewModel for source compatibility, OR update all callers.

#### M7. `ProfileView` settings list structure unverified

- **Location:** Plan §2.8
- **Problem:** Plan adds a row but doesn't reference the existing structure (Section/Form layout). `ProfileView.swift` has `@Query userGoalsList` and Section headers, but the toggle's specific section/landing position isn't decided.
- **Recommendation:** Specify: place the toggle in a "Notifications & Prompts" section (create if not present) below existing settings.

#### M8. Engagement gap `low_steps` — `nil` vs `0` handling unclear

- **Location:** Plan §1.7; Formula spec §5
- **Problem:** Spec table says `cond = (steps < 2000)`. If HK is silent (`nil`), is the cond true (no data → assume sedentary → penalize) or false (no signal → no penalty)?
- **Recommendation:** `cond = (steps != nil && steps! < 2000)`. If steps unavailable entirely, no penalty (manual-fallback or device-data lane handles it). Document explicitly.

#### M9. `low_mood_3d` predicate assumes mood enum mapping

- **Location:** Plan §1.8
- **Problem:** `MoodOption.awful = 0, .bad = 1, .okay = 2, .good = 3, .great = 4`. Predicate `moodRaw <= 1` correctly catches awful/bad. But if the enum is ever reordered, predicate silently breaks.
- **Recommendation:** Replace numeric predicate with `MoodOption(rawValue: moodRaw).map { $0 == .awful || $0 == .bad } ?? false`. Self-documenting and refactor-safe.

#### M10. `baseline14Day` doesn't defensively filter future-dated samples

- **Location:** Plan §1.9
- **Problem:** Clock skew or multi-device sync can produce sample timestamps in the future. `excludingToday` only guards "today's same-day."
- **Recommendation:** Add `&& $0.date < startOfToday` to the filter. Cheap defense.

#### M11. Caffeine type fallback when `coffeeType == nil` but `cups > 0`

- **Location:** Plan §1.3 (caffeine function); Formula spec §3.3
- **Problem:** Default 80mg is mentioned in formula spec but not pinned in the plan. Legacy `WellnessDayLog` rows may have cups but no type.
- **Recommendation:** Specify `let mgPerCup = type?.caffeineMg ?? 80` in `caffeinePoints`. Add a comment noting the fallback applies to legacy data.

#### M12. v3 announcement banner copy not drafted

- **Location:** Plan §3.11
- **Recommendation:** Draft 2 sentences before P3 implementation. Suggested: *"Your stress score now considers mood, hydration, symptoms, and more — 13 factors total. Vitals like HRV are used to calibrate accuracy against your personal baseline."*

---

### LOW (Consider for Future)

#### L1. `ManualDailyInput` vs absorbing fields into `WellnessDayLog`

- **Location:** Plan §2.1
- **Note:** Keeping them separate is cleaner (decouples HK fallback estimates from user logs) but doubles SwiftData fetches per recompute. Document the design call in the strategy. Not blocking.

#### L2. `engagementPenalty` purity vs timezone

- **Note:** Function uses `Calendar.current.component(.hour, from: now)` — pure modulo system timezone. Add a code comment for future maintainers.

#### L3. Step 3.5 mapping "factor title → sheet" is tightly coupled

- **Note:** Hardcoded switch on factor title is brittle if titles change. Long-term, factor functions should return an associated `sheet` value. Acceptable for v3.

---

## Missing Elements

- [ ] **`hasData` policy table** (per C2) — must land in formula spec or RESOLVED plan
- [ ] **Sugar/diet decision** (per C1) — pick A/B/C and update plan
- [ ] **Test target wiring verification** (per H4) — run `xcodebuild test` once before committing to XCTest path
- [ ] **`onboardingCompletedAt` timestamp addition** (per H5)
- [ ] **`activeFastHours` derivation step** in §1.13 (per H7)
- [ ] **CTA routing decisions** for engagement-gap card (per H8) — Mood, Water, Food, Steps
- [ ] **Mock service multi-day baseline data** (per H6) — extend `MockHealthKitService`
- [ ] **`AppConfig.mockMode` unification step** in §1.13 (per M2)
- [ ] **`StressFactorResult.id` change to stable identifier** (per H3)
- [ ] **Sub-struct field specifications** for `VitalsInput`, `HistoryInput`, `RecoveryInput`, `SleepInput`, `ExerciseInput`, etc. (per M4)
- [ ] **Engagement timer scope decision** — app-level vs view-level (per H2)
- [ ] **`refreshDietFactor()` rename strategy** (per M5) — keep names or update callsites?

---

## Unverified Assumptions

- [ ] **Hour-of-day extraction works correctly across DST transitions** for engagement ramps. Risk: Low — `Calendar.current.component(.hour, from: now)` handles DST.
- [ ] **`SymptomCorrelationEngine` correlations remain valid** with v3's increased symptom sensitivity. Risk: Low — engine consumes computed stress scores, not factor internals.
- [ ] **`InsightEngine` and `ReportDataBuilder` continue to work** with `totalScore` semantically richer (less unidirectional). Risk: Medium — `WellnessDaySummary.stressScore` is still 0–100, but narrative templates might be miscalibrated. Out of v3 scope per strategy non-goals; flag for a follow-up.
- [ ] **5-minute timer doesn't cause UI flicker** during `recompute()`. Risk: Low — `recompute()` mutates `@Published` props atomically; SwiftUI diffs.
- [ ] **`ManualDailyInput` SwiftData migration is purely additive** and doesn't disrupt existing rows. Risk: Low — adding a new `@Model` doesn't touch other models.
- [ ] **`MainTabView`'s mock injection still works** when `StressViewModel` builds `StressInputs` from snapshot. Risk: Medium — existing logic shortcircuits `loadData()` for mock; v3 pipeline must respect this.
- [ ] **Engagement penalty CTA navigation does not break tab state** when user is mid-task. Risk: Medium — surfaces in P3 testing.

---

## Questions for Clarification

1. **Sugar question (C1):** Drop, add field, or proxy from carbs? Recommend (A) drop.
2. **`hasData` question (C2):** Approve the proposed §3.14 policy table?
3. **Coordinator ownership (C3):** Approve moving `@StateObject` to `WellPlateApp`?
4. **`StressFactorResult.id` change (H3):** OK to switch from UUID to `title`-based id? It's a breaking change in struct API but no external consumers exist.
5. **Test target wiring (H4):** If `WellPlateTests` isn't in a shared scheme, do we (a) wire it now or (b) downgrade to mock-snapshot smoke checks?
6. **Engagement CTA targets (H8):** Pre-approve routes — Mood → modal sheet wrapping `MoodCheckInCard`; Water → tab switch + present `WaterDetailView`; Food → tab switch + `MealLogView`; Steps → tab switch (no logger, just go to Burn tab)?
7. **`refreshDietFactor()` rename (M5):** Keep names (zero-churn) or rename for clarity (cascades through HomeView)?
8. **`onboardingCompletedAt` field (H5):** Approve adding to `UserProfileManager`?

---

## Recommendations

1. **Run `/develop resolve` on this audit** before proceeding to checklist. Critical issues C1, C2, C3 require explicit decisions, not just clarifications.
2. **Land formula spec §3.14 (`hasData` policy table)** as a doc update in `Docs/01_Brainstorming/260509-stress-formula-spec.md` — single source of truth for factor behavior.
3. **Pre-decide the engagement-CTA routing matrix** before P3 starts so checklist steps are concrete.
4. **Verify the test target wiring once**, with a dry-run `xcodebuild test`, before committing the validation strategy. If the test target isn't ready, downgrade to smoke checks via `MockDataDebugCard`.
5. **Subdivide §1.13** in the eventual checklist — it's the largest single step and aggregates HK fetches, SwiftData fetches, resolution helpers, struct construction, and publishing. Break into 4–5 atomic checklist items.

---

## Verdict Reasoning

**NEEDS REVISION** because:

- 3 CRITICAL issues (C1, C2, C3) each independently block P1 implementation.
- 9 HIGH issues materially affect feasibility, correctness, or success criteria.
- The plan is otherwise well-scoped and ready to proceed once these are resolved.

After resolution (via `/develop resolve` producing a `260509-stress-algorithm-v3-plan-RESOLVED.md`), the plan should re-enter the checklist gate.

---

## Next step

→ `/develop resolve Docs/03_Audits/260509-stress-algorithm-v3-plan-audit.md` — fix CRITICAL and HIGH issues, produce `260509-stress-algorithm-v3-plan-RESOLVED.md`.
