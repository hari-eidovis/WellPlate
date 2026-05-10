# Checklist Audit Report: Stress Algorithm v3

**Audit Date:** 2026-05-09
**Checklist Version:** [260509-stress-algorithm-v3-checklist.md](../04_Checklist/260509-stress-algorithm-v3-checklist.md)
**Source Plan:** [260509-stress-algorithm-v3-plan-RESOLVED.md](../02_Planning/Specs/260509-stress-algorithm-v3-plan-RESOLVED.md)
**Auditor:** audit agent
**Verdict:** **NEEDS REVISION**

---

## Executive Summary

The checklist comprehensively covers the resolved plan and includes verify steps for nearly every action. However, it has **1 CRITICAL ordering issue** (P1 references a SwiftData type only created in P2 — won't compile), **1 HIGH ordering issue** (engagement ticker depends on a P2 component but is wired in P1), and a handful of HIGH gaps where verify steps are loose enough to let real bugs slip through (HK auth guard missing, `hasData` policy not enforced, factor-title routing not enumerated). After these fixes the checklist should be ready for `/develop implement`.

---

## Issues Found

### CRITICAL (Must Fix Before Implementing)

#### C1. `ManualDailyInput` type is referenced in P1 (1.13b) but created in P2 (2.1) — P1 will not compile

- **Location:** Checklist §1.13b, line 169 — "Add fetch for today's `ManualDailyInput` (P2 will populate; P1 always nil)" vs §2.1, line 299 — "Create new file `WellPlate/Models/ManualDailyInput.swift`"
- **Problem:** `FetchDescriptor<ManualDailyInput>(...)` won't compile in P1 because the `@Model` type doesn't exist yet. The plan §1.13 contains the same instruction. The intent ("P1 always nil") cannot be expressed by *trying to fetch* a non-existent type.
- **Impact:** P1 build target fails immediately at the first attempt. Checklist becomes non-executable.
- **Recommendation:**
  - **Either** move §2.1 (create `ManualDailyInput` model) into P1, executed before §1.13b. The model can exist with no UI; only `WellPlateApp.swift` needs to register it (also move §2.2 forward). This is the cleanest fix.
  - **Or** remove the fetch from §1.13b entirely. Pass `manual: nil` to `buildInputs(...)` in P1. Add the fetch in P2 §2.6.
  - Recommended: **move §2.1 + §2.2 into P1** (renumber as §1.0a, §1.0b before §1.1) so the type exists from the start. Smaller diff than splitting the fetch logic.

---

### HIGH (Should Fix Before Implementing)

#### H1. §1.15 engagement ticker depends on `DailyPromptCoordinator` from P2 — host decision creates a P1/P2 entanglement

- **Location:** Checklist §1.15, line 220 — "Decide ticker host: extend `DailyPromptCoordinator` (clean ownership) OR add `StressTimerService.shared`"
- **Problem:** `DailyPromptCoordinator` is created in P2 §2.3. If implementer picks "extend `DailyPromptCoordinator`" in P1, the host doesn't exist. The verify step (`grep "tickerPulse" .../DailyPromptCoordinator.swift`) explicitly references the P2 file.
- **Impact:** P1 step appears valid but cannot be executed cleanly with the first option; ticker cannot land in P1 if it depends on coordinator.
- **Recommendation:** Force the choice now: use `StressTimerService.shared` in P1 (independent of coordinator). Replace §1.15 first bullet with: "Create `WellPlate/Core/Services/StressTimerService.swift` — `@MainActor final class StressTimerService: ObservableObject { static let shared = ...; @Published var tickerPulse: Date = .distantPast; func start(); func stop() }`". Update verify step accordingly. P2 doesn't need to touch the ticker.

#### H2. `hasData` policy table (plan §0.1) is not enforced by any verify step

- **Location:** Checklist §1.3, §1.4, §1.5 — factor function implementations
- **Problem:** Plan §0.1 defines exact `hasData = true` rules per factor (caffeine ↔ today's `WellnessDayLog` row exists; symptoms always true; etc.). Checklist verifies function existence and weight constants, but never asserts that the function follows the §0.1 policy. An implementer who reads only the checklist could implement `caffeine.hasData = (cups > 0)` (wrong) or `symptoms.hasData = !entries.isEmpty` (wrong).
- **Impact:** Coverage math becomes inconsistent across factors; confidence/engagement guard misbehaves; bugs are silent (no compile error).
- **Recommendation:** Add a sub-step under each factor function:
  - 1.3 caffeine: "Verify `hasData = input.hasWellnessRow` (per plan §0.1)"
  - 1.4 hydration: "Verify `hasData = input.hasWellnessRow`"
  - 1.4 fasting: "Verify `hasData = input.isConfigured`"
  - 1.4 mealTiming, eatingTriggers: "Verify `hasData = !logs.isEmpty`"
  - 1.5 symptoms: "Verify `hasData = true` always"
  - 1.5 mood: "Verify `hasData = (mood != nil)`"
  - 1.4 circadian: "Verify `hasData = input.hasEnoughData`"
  - 1.4 daylight: "Verify `hasData = (HK minutes>0 OR manual toggle != nil)`"

  Add a checkpoint at end of §1.5: "Re-read plan §0.1 and confirm every factor's `hasData` matches the policy table".

#### H3. `DailyPromptCoordinator.evaluateOnAppForeground` missing HK auth guard

- **Location:** Checklist §2.3, line 320 — implementation sub-bullets
- **Problem:** Resolved plan unverified-assumption #6 ("HK auth race condition — coordinator queries before auth completes"). Plan §2.3 has it implicitly via `healthService.isAuthorized` check. Checklist's sub-bullets list 5 conditions but not the HK auth guard.
- **Impact:** Coordinator may attempt `await healthService.fetchDailySleepSummaries(for: ...)` while HK auth hasn't been granted/completed → throws → the catch-less `try?` hides the error → coordinator decides HK is silent → fires the morning prompt to a Watch user who simply hasn't finished auth flow yet.
- **Recommendation:** Add to §2.3 implementation list:
  - "Add early-return: `guard healthService.isAuthorized else { return }`"
  - Verify: `grep "isAuthorized" WellPlate/Core/Services/DailyPromptCoordinator.swift` returns at least one match.

#### H4. §1.13d doesn't delete the existing private factor builders that conflict with new flow

- **Location:** Checklist §1.13d, line 188
- **Problem:** Verified by grep: `StressViewModel.swift` currently has private functions `buildExerciseFactor` (line 565), `buildSleepFactor` (line 593), `buildDietFactor` (line 613), `refreshScreenTimeFactor` (line 635). After §1.13d wires `result.factors → allFactors`, these functions are dead code. Worse, the old `loadData()` calls them (lines 251, 259, 345, 361, 269, 379). Checklist replaces "factor builders" but doesn't enumerate them or say "delete".
- **Impact:** If implementer adds the new pipeline but leaves old builders + their callsites in place, build fails with double-write to `exerciseFactor`/`sleepFactor`/etc. or with unused-warning chaos. Subtle bugs possible if old assignments override new ones.
- **Recommendation:** Add to §1.13d an explicit deletion list:
  - "Delete `private func buildExerciseFactor(...)`, `buildSleepFactor(...)`, `buildDietFactor(...)`, `refreshScreenTimeFactor()`"
  - "Remove all callsites in `loadData()` and `refreshDietFactor()` that assign to `exerciseFactor`, `sleepFactor`, `dietFactor`, `screenTimeFactor` directly"
  - "Keep only the `allFactors` array population from `result.factors`"
  - Verify: `grep -n "buildExerciseFactor\|buildSleepFactor\|buildDietFactor" WellPlate/Features\ +\ UI/Stress/ViewModels/StressViewModel.swift` returns 0 matches.

#### H5. §1.18b doesn't ensure new test file is added to `WellPlateTests` target membership

- **Location:** Checklist §1.18b
- **Problem:** Per CLAUDE.md, the project uses `PBXFileSystemSynchronizedRootGroup` — files in `WellPlate/` auto-include. But `WellPlateTests/` may or may not use the same mechanism. Adding `StressScoringTests.swift` to disk doesn't guarantee it's compiled by the test target.
- **Impact:** New test file may silently not run. The `xcodebuild test` step appears to pass (no failures), but the coverage we wanted is absent.
- **Recommendation:** Add to §1.18b after creating the test file:
  - "Verify `WellPlateTests/` group is also a `PBXFileSystemSynchronizedRootGroup` by checking the group block in `WellPlate.xcodeproj/project.pbxproj` for `PBXFileSystemSynchronizedRootGroup` and `WellPlateTests`"
  - "If yes → file auto-included. If no → open Xcode and add `StressScoringTests.swift` to the `WellPlateTests` test target via File Inspector → Target Membership"
  - "Run `xcodebuild test ... -only-testing:WellPlateTests/StressScoringTests` and verify ≥1 test executes (not 'no tests found')"

#### H6. §3.5 title→sheet routing switch is not enumerated for all 13 factor titles

- **Location:** Checklist §3.5
- **Problem:** Lists ~8 routes but the v3 model has 13 drivers + recovery context. Implementer may forget Symptoms, Eating Triggers, Meal Timing, Fasting, Circadian, Daylight, Caffeine. A missing case in `switch factor.title` could either crash (if exhaustive switch) or silently no-op.
- **Impact:** Tapping less-common factor cards does nothing; user reports broken UI.
- **Recommendation:** Replace §3.5 routing bullets with a complete table:
  | Factor title | Sheet |
  |---|---|
  | Sleep | `.sleep` |
  | Exercise | `.exercise` |
  | Caffeine | `.diet` (or new `.caffeine` if drillable) |
  | Screen Time | `.screenTimeDetail` |
  | Diet | `.diet` |
  | Hydration | `.water` |
  | Circadian | `.sleep` (shares sleep detail) |
  | Daylight | `.sleep` |
  | Meal Timing | `.foodLog` |
  | Fasting | new `.fasting` (or existing fasting view) |
  | Eating Triggers | `.foodLog` |
  | Mood | `.mood` |
  | Symptoms | new `.symptoms` (route to existing `SymptomHistoryView`) |
  Add: "If a factor has no detail view, the card should be non-tappable (no `onTap` handler)."

#### H7. §3.3 CTA tab-switch mechanism is vague

- **Location:** Checklist §3.3 — "trigger tab switch to Home + present `WaterDetailView`" and Steps gap CTA
- **Problem:** Plan §3.3 says "use existing `pendingDeepLink` mechanism in `RootView`" but checklist doesn't show what URL or what notification triggers the switch. `MainTabView` selection state isn't accessible from inside `StressView` directly.
- **Impact:** Implementer may build CTAs that don't navigate, or duplicate the deep-link plumbing.
- **Recommendation:** Add a sub-step before §3.3 implementation:
  - "Audit existing `pendingDeepLink: URL?` flow in `RootView.swift` and `MainTabView.swift` — list what URL schemes are already routed (e.g., `wellplate://home/water`, `wellplate://burn`). If none for the targets we need (water, food, burn), add a small `TabSelector` `EnvironmentObject` exposing `selectedTab: TabKind` and a `presentedSheet: SheetKind?`"
  - Specify per-CTA: Mood → `activeSheet = .mood`; Water → `tabSelector.selectedTab = .home; tabSelector.presentedSheet = .water`; Food → `.home + .foodLog`; Steps → `.burn` (no presented sheet); Reflection → `.mood`.
  - Verify: each CTA on simulator routes correctly and returns to Stress tab via back nav.

---

### MEDIUM (Fix During Implementation)

#### M1. §1.2 weights table verify checks only one constant

- **Location:** Checklist §1.2
- **Recommendation:** Strengthen verify: `grep -c "static let \(sleep\|exercise\|caffeine\|screenTime\|diet\|hydration\|circadian\|daylight\|mealTiming\|fasting\|eatingTriggers\|mood\|symptoms\): Double" StressScoring.swift` should return ≥ 13.

#### M2. §1.7 / §1.8 don't enumerate per-gap or per-pattern thresholds

- **Location:** Checklist §1.7, §1.8
- **Recommendation:** Add explicit bullets per gap (mood max=5 17→21, food max=4 17→20, water max=4 14→18, steps max=3 16→20, reflection max=2 18→21) and per pattern (no_food_3d=4, low_mood_3d=3, high_coffee_3d=3, no_fast_14d=2). Each becomes its own verify-able sub-step.

#### M3. §1.10 typealias conflicts with §1.13a in the same file

- **Location:** Checklist §1.10 vs §1.13a
- **Problem:** Both modify `StressViewModel.swift`. §1.10 happens before §1.13, increasing the risk of merging two large diffs and missing the typealias deletion when §1.13 reorganizes the class.
- **Recommendation:** Move §1.10's `typealias` insertion into §1.13a (which is already touching the same file). Keep `Confidence` enum inside `StressScoring` as planned.

#### M4. §2.7 Combine subscription teardown not specified

- **Location:** Checklist §2.7
- **Problem:** "Add Combine subscription to `coordinator.$manualInputSavedAt`" without saying where to store the `AnyCancellable` or how it's cancelled on deinit.
- **Recommendation:** Add: "Store as `private var manualInputCancellable: AnyCancellable?` set in init; cancelled implicitly on deinit." Verify with `grep "manualInputCancellable\|cancellables" StressViewModel.swift`.

#### M5. §1.17 mock service updates underspecified

- **Location:** Checklist §1.17 — "Verify other fetch methods still align with snapshot fields"
- **Recommendation:** Enumerate: "Confirm `fetchSteps`, `fetchActiveEnergy`, `fetchDailySleepSummaries`, `fetchDaylight` continue to project from the new snapshot variants for each of the 4 mock cases." Add a verify per mock variant.

#### M6. §2.6 "fetch last 7 days of `ManualDailyInput`" has no verify

- **Location:** Checklist §2.6, last bullet
- **Recommendation:** Add "Verify: `resolveCircadian(...)` returns a `CircadianInput` with `hasEnoughData = true` when 5+ manual nights with `bedtime`/`wakeTime` exist, false otherwise. Smoke-test via mock with 7 manual nights."

#### M7. §3.11 banner — no verify of dismiss persistence

- **Location:** Checklist §3.11
- **Recommendation:** Add "Verify: dismiss banner → kill app → relaunch → banner does not re-appear. Reset by deleting `UserDefaults.standard.removeObject(forKey: 'wp.stress.v3AnnouncementShown')` (debug only)."

#### M8. Pre-implementation doesn't list new files to be created

- **Location:** "Pre-Implementation"
- **Recommendation:** Add a "Files to be created during implementation" sub-list so implementer knows what's coming:
  - `WellPlate/Models/ManualDailyInput.swift`
  - `WellPlate/Core/Services/DailyPromptCoordinator.swift`
  - `WellPlate/Core/Services/StressTimerService.swift` (per H1 fix)
  - `WellPlate/Shared/Components/QuickCheckInSheet.swift`
  - `WellPlate/Shared/Components/MoodCheckInSheet.swift`
  - `WellPlate/Features + UI/Stress/Components/CalibratorChip.swift`
  - `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift`
  - `WellPlateTests/StressScoringTests.swift`

#### M9. §1.1 grep verify is fragile to indentation

- **Location:** Checklist §1.1 — `grep -c "^    struct .*Input " ...`
- **Recommendation:** Replace with a less brittle check: `grep -c "^    struct \(SleepInput\|ExerciseInput\|CaffeineInput\|ScreenInput\|DietInput\|HydrationInput\|CircadianInput\|DaylightInput\|FastingInput\|RecoveryInput\|VitalsInput\|HistoryInput\) " StressScoring.swift` returns 12.

#### M10. §1.16 verify just greps but doesn't say what to do if matches found

- **Location:** Checklist §1.16
- **Recommendation:** Add explicit fail action: "If matches found inside `buildInputs(...)` or any factor function, remove them — these histories are display-only."

---

### LOW (Consider for Future)

#### L1. Checklist doesn't include a final manual smoke pass against formula spec §10 reactivity examples

- **Location:** Post-Implementation, "Cross-cutting smoke checks"
- **Note:** Formula spec §10 has 4 numeric examples (mood awful → −1; mood great → −11; water 1 → +1; HRV 25% below baseline → +5). These are precise enough to be checked manually with mock data. Adding them as smoke checks would catch off-by-one threshold bugs.

#### L2. `git commit` messages don't link to plan/checklist/audit docs

- **Location:** §1.19, §2.10, §3.14 commit messages
- **Note:** Including a footer like `Plan: Docs/02_Planning/Specs/260509-stress-algorithm-v3-plan-RESOLVED.md` makes future archaeology easier. Optional.

#### L3. Manual cross-tab smoke (engagement card → Home/Burn navigation) not in post-impl

- **Location:** Post-Implementation
- **Note:** "Cross-cutting smoke checks" lists score-effect verifications but not "tap engagement-gaps CTA → land on the right tab + sheet."

---

## Missing Elements

- [ ] **Move `ManualDailyInput` model creation into P1** (per C1) — critical sequencing
- [ ] **Force `StressTimerService.shared` decision** (per H1) — no choice for implementer
- [ ] **Add `hasData` policy verification per factor** (per H2) — must enforce §0.1
- [ ] **HK `isAuthorized` guard in coordinator** (per H3)
- [ ] **Explicit deletion list of old factor builders** (per H4)
- [ ] **Test target membership confirmation** (per H5)
- [ ] **Complete title→sheet routing table for all 13 drivers** (per H6)
- [ ] **Concrete tab-switch mechanism** (per H7) — `TabSelector` EnvironmentObject or explicit deep-link URLs
- [ ] **Per-gap and per-pattern threshold sub-steps** (per M2)
- [ ] **Combine subscription teardown** (per M4)
- [ ] **Mock variant smoke per fetch function** (per M5)
- [ ] **`ManualDailyInput` 7-day history verify for circadian** (per M6)
- [ ] **Banner dismiss persistence verify** (per M7)
- [ ] **New-files preview list in Pre-Implementation** (per M8)
- [ ] **Formula §10 reactivity examples in post-impl smoke** (per L1)

---

## Unverified Assumptions

- [ ] **`PBXFileSystemSynchronizedRootGroup` covers the test target** — Risk: Medium. If the test group is a regular `PBXGroup`, new `.swift` files require pbxproj edits. Mitigated by H5.
- [ ] **`StressTimerService.shared` singleton is acceptable** — Risk: Low. Other singletons exist in the codebase (`UserProfileManager.shared`, `ScreenTimeManager.shared`, `HealthKitServiceFactory.shared`).
- [ ] **`MainTabView` exposes a way to programmatically change selected tab** — Risk: Medium. Plan assumes yes; verify before P3 starts.
- [ ] **`xcodebuild test` works without specifying a destination scheme** — Risk: Low. iOS 26 simulator should be present; if not, fallback to a different simulator name.
- [ ] **`MockHealthKitService` already wired into `HealthKitServiceFactory.shared` mock branch** — Risk: Low. Pre-existing.

---

## Questions for Clarification

1. **C1 fix preference:** Move §2.1+§2.2 into P1, or remove the fetch from §1.13b and only add it in P2? (Audit recommends moving forward.)
2. **H1 ticker host:** Use `StressTimerService.shared` (independent) or wait until P2 and extend coordinator? Recommends `StressTimerService.shared` to keep P1 self-contained.
3. **H7 tab-switch infra:** Build a small `TabSelector` `EnvironmentObject` now, or extend the existing `pendingDeepLink: URL?` mechanism? Recommends the former — clearer separation, no string parsing.
4. **H6 sheet routes:** Should less-common factor cards (Caffeine, Daylight, Circadian) link to existing detail views or be non-tappable? Affects how many new `StressSheet` cases we add.

---

## Recommendations

1. **Run `/develop resolve` on this checklist audit** to address the 1 CRITICAL and 7 HIGH issues. Critical and high blockers are concrete (no design ambiguity), so resolution should be mechanical.
2. **Apply MEDIUM fixes inline** to the checklist as part of resolve — they're cheap.
3. **Once resolved, the checklist will be ready for `/develop implement`** with high confidence. The current `-RESOLVED.md` plan is solid; only checklist mechanics need tightening.

---

## Verdict Reasoning

**NEEDS REVISION** because:

- 1 CRITICAL ordering bug (C1) makes P1 non-executable as written.
- 7 HIGH issues span verifiability, completeness, and runtime correctness.
- Otherwise the checklist is detailed, well-ordered, and proportional to the plan.

After resolution, the checklist should pass a re-audit and proceed to implement.

---

## Next step

→ `/develop resolve Docs/03_Audits/260509-stress-algorithm-v3-checklist-audit.md` — fix CRITICAL and HIGH issues, produce `260509-stress-algorithm-v3-checklist-RESOLVED.md`.
