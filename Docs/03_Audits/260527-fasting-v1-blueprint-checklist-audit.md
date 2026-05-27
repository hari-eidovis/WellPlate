# Checklist Audit Report: Fasting v1 Blueprint

**Audit Date:** 2026-05-27
**Checklist Path:** `Docs/04_Checklist/260527-fasting-v1-blueprint-checklist.md`
**Source Plan:** `Docs/02_Planning/Specs/260527-fasting-v1-blueprint-plan-RESOLVED.md`
**Auditor:** audit agent (in-process; checklist-author confirmation-bias mitigation: code snippets cross-verified against actual source)
**Verdict:** **NEEDS REVISION** — 1 CRITICAL + 5 HIGH. Coverage of plan steps is complete and ordering is dependency-safe, but several code snippets reference APIs that don't exist (DailySleepSummary fields, HealthKitService.shared), and Phase 1↔Phase 7 do duplicate work on the same HomeView lines.

---

## Executive Summary

The checklist correctly maps every plan step to one or more checkable items, includes per-phase build verification, and respects dependency order. However, source-code verification uncovers four code snippets that won't compile as written — `DailySleepSummary.computedScore`/`.startTime` don't exist (real fields: `totalHours`, `quality`, `bedtime`, `wakeTime`), and `HealthKitService.shared` doesn't exist (the factory pattern is `HealthKitServiceFactory.shared`). Phase 1 also modifies HomeView lines that Phase 7 deletes, creating wasted effort and merge-conflict risk between staged PRs. A few verify steps reference test infrastructure that doesn't exist in this repo.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### CC1. Phase 1 step 1.4 modifies HomeView lines that Phase 7 step 7.5 deletes
- **Location:** Checklist 1.4 ("Edit `HomeView.swift` lines 593-601 — fasting launcher button — about to be replaced in Phase 7") vs 7.5 ("Remove the old `headerAssetIcon(\"fasting_icon\")` launcher button (lines 593-601)")
- **Problem:** Phase 1 adds access-state routing to the launcher button. Phase 7 deletes the entire button and replaces it with `DigestiveStateCard`. If Phases 0–3 ship as v1.0.0 and Phase 7 ships later as v1.3.0 (per plan §Suggested sequencing), the Phase 1 work is correct and needed for v1.0.0. But it's then thrown away in v1.3.0, and the access-state logic must be re-implemented inside `DigestiveStateCard`. If the implementer reads Phase 7 first they may skip the Phase 1 launcher edit, leaving v1.0.0 with no Home access gating at all.
- **Impact:** Two real risks: (a) v1.0.0 ships with the launcher button updated, but Phase 7 deletion creates a merge conflict during v1.3.0 if any other PR has touched the same lines. (b) An implementer working from this checklist linearly may not realize the Phase 1 work is throwaway and over-engineer the launcher button.
- **Recommendation:** Add a note in Checklist 1.4 explicitly stating: "This launcher button is replaced by `DigestiveStateCard` in Phase 7 (step 7.5). The access-state routing logic added here will move into `DigestiveStateCard.swift` (step 7.4) at that time. For v1.0.0 ship, this remains the only Home entry point." Also add a forward-reference in Checklist 7.4 noting that the access-state routing logic from `HomeView.swift` should be copied into the new card. Alternative: defer Phase 1.4 Home edits entirely and route via the gear icon menu or empty-state CTA only in v1.0.0, picking up Home routing in v1.3.0 with the card.

---

### HIGH (Should Fix Before Proceeding)

#### CH1. Checklist 5.2 references `sleepHistory.last?.computedScore` — no such field exists
- **Location:** Checklist 5.2 ("StressViewModel writes to cache")
- **Problem:** `DailySleepSummary` (verified at `Cadence/Models/HealthModels.swift:92-110`) has fields: `date`, `totalHours`, `coreHours`, `remHours`, `deepHours`, `bedtime?`, `wakeTime?`, plus computed `quality: SleepQuality`. There is no `computedScore` property anywhere.
- **Impact:** Code snippet won't compile. Implementer must invent a sleep score derivation, may make inconsistent choices each time it's referenced (5.2, 5.3, 5.4 banner thresholds).
- **Recommendation:** Pick one derivation up front and use it consistently. Suggested: map `SleepQuality` enum to an Int (`.excellent → 95`, `.good → 80`, `.fair → 60`, `.poor → 35`) via a small extension in `SharedHealthMetrics.swift`. Update all three checklist sites to use this helper. Alternative: derive from totalHours linearly (e.g. `Int(min(100, max(0, totalHours * 12.5)))` — 8h = 100).

#### CH2. Checklist 5.3 and 8.1 reference `summary.startTime` — wrong field name
- **Location:** Checklist 5.3 ("FastingContextProvider") and 8.1 ("Bedtime heuristic")
- **Problem:** The bedtime/sleep-onset field on `DailySleepSummary` is `bedtime: Date?`, not `startTime`. Checklist 8.1 even adds a TBD comment ("locate the actual onset field") — meaning the author knew this was unverified but shipped anyway.
- **Impact:** Won't compile. The TBD wastes implementer time forcing them to discover what should have been resolved at planning.
- **Recommendation:** Update both snippets to use `summary.bedtime`. Add explicit nil-handling (the field is optional — a sleep summary with no bedtime can't contribute to the median).

#### CH3. Checklist 8.2 references `HealthKitService.shared` — doesn't exist
- **Location:** Checklist 8.2 ("Schedule start-reminder")
- **Problem:** Verified pattern in repo: `HealthKitServiceFactory.shared` (typed as `HealthKitServiceProtocol`) — see `HealthKitServiceFactory.swift:17, 31` and the consumers in `InsightEngine.swift:38`, `WellnessCalendarViewModel.swift:30`. There is no `HealthKitService.shared` singleton.
- **Impact:** Won't compile. Implementer must discover the factory pattern.
- **Recommendation:** Update Checklist 8.2 code snippet: `let heuristic = FastingBedtimeHeuristic(healthKit: HealthKitServiceFactory.shared)`. Update Checklist 5.3's `FastingContextProvider.loadContext(...)` signature to take `HealthKitServiceProtocol` (not concrete `HealthKitService`) and document the call site as `await contextProvider.loadContext(healthKit: HealthKitServiceFactory.shared, modelContext: modelContext)`.

#### CH4. Checklist 2.5 specifies "when elapsed > 24h" in `updateFastingActivity(progress:)` — but the method has no access to elapsed time
- **Location:** Checklist 2.5 ("Live Activity capped-state rendering")
- **Problem:** Existing `ActivityManager.updateFastingActivity(progress: Double)` (lines 85-98) only takes the progress value as a parameter. It has access to `activity.content.state` which holds `fastStartDate: Date` — so elapsed CAN be computed (`Date().timeIntervalSince(state.fastStartDate)`), but the checklist instruction "when elapsed > 24h" doesn't specify the source.
- **Impact:** Implementer might either (a) pass elapsed in as a new parameter (breaking change for callers, including the new throttled-update code in FastingView), or (b) compute it correctly inside but spend time figuring it out.
- **Recommendation:** Be explicit. Update Checklist 2.5 with: "In `updateFastingActivity(progress:)`, compute `let elapsed = Date().timeIntervalSince(state.fastStartDate)` and set `state.isCapped24h = elapsed > 24*3600`. Clamp `state.progress = isCapped24h ? 1.0 : clamped`."

#### CH5. Checklist 4.3 leaves `FastingCompletionEvent(...)` init params as `(...)` placeholder
- **Location:** Checklist 4.3 ("Decouple celebration from auto-transition") — code snippet has `celebration = FastingCompletionEvent(...)` with literal ellipsis
- **Problem:** The actual init signature is `FastingCompletionEvent(durationHours: Double, scheduleLabel: String)` per `FastingCelebrationOverlay.swift:5-9`. Existing call site at `FastingView.swift:638-641`: `FastingCompletionEvent(durationHours: elapsedHours, scheduleLabel: schedule.displayLabel)`.
- **Impact:** Implementer must read the existing call site to find the right params. Minor but a real friction point in a critical state-transition refactor.
- **Recommendation:** Replace the placeholder with the explicit call: `FastingCompletionEvent(durationHours: session.actualDurationHours, scheduleLabel: schedule.displayLabel)`.

---

### MEDIUM (Fix During Implementation)

#### CM1. Verify steps in several places are loose ("works", "renders correctly", "routes correctly")
- **Location:** Multiple — Checklist 1.4 ("each of the 3 states routes correctly"), 7.4 ("card renders in SwiftUI preview"), 7.6 ("DigestiveStateCard tap routes correctly for each access state (test all 3)")
- **Problem:** "Test all 3" without specifying how to seed each access state forces the implementer to invent a debug seeding mechanism. CLAUDE.md says testing = build-only verification — there's no test runner. Manual seeding via debug console is undocumented.
- **Recommendation:** Add a small reusable "debug seed FastingEligibility" snippet in a `#if DEBUG` section that the implementer can call from a debug menu or via lldb. Concrete suggestion: `lldb> e let elig = FastingEligibility(); elig.cleared = true; elig.scoffCleared = true; ...; try? modelContext.save()`. Or, even simpler, add a debug toggle in `AppConfig` (already exists per CLAUDE.md: "mockMode, groqModel, API timeouts") to force each access state.

#### CM2. Checklist Post-Implementation walkthrough has 20 items vs plan §Success Criteria's 23
- **Location:** Plan §Success Criteria has 23 distinct checkboxes; Checklist Post-Implementation success-criteria walkthrough has 20
- **Problem:** Missed items:
  - Plan: "Three access state branches verified: not-onboarded → onboarding, blocked → care, granted → fasting view" (one bullet → three branches each needs verifying)
  - Plan: separate accessibility line items for SCOFF, weekly grid, button, reduceMotion (4 distinct things) → checklist consolidates into 1 line
  - Plan: "HRV/sleep data shared via SharedHealthMetrics cache; no duplicate HealthKit queries" — checklist has this but only one item, not the parent + verify
- **Impact:** Reviewer marking the checklist as complete may sign off without actually testing each branch.
- **Recommendation:** Expand the success-criteria walkthrough to 1:1 match the plan's bullets. Three access state branches → three sub-checks. Accessibility → 4 sub-checks.

#### CM3. Checklist 6.5 TestFlight verification is partially redundant with Phase −1.4
- **Location:** Checklist 6.5 ("Phase 6 verification (REQUIRES TESTFLIGHT)")
- **Problem:** Both Phase −1.4 and Phase 6.5 require TestFlight builds. Phase −1 already proved App Group works; Phase 6 needs to prove the intent flow specifically. They're testing different things but the checklist doesn't clarify what NEW must be verified in 6.5 beyond what −1.4 already covered.
- **Recommendation:** Add explicit "NEW in Phase 6.5 vs Phase −1.4" framing: "Phase −1.4 verified App Group UserDefaults works in Release. Phase 6.5 additionally verifies that (a) the `LiveActivityIntent` runs in the widget process and (b) the pending-break payload is correctly reconciled by the app on foreground."

#### CM4. Checklist 7.3 verify step describes a unit-test pattern that's not actionable in this repo
- **Location:** Checklist 7.3 ("Verify existing users' layouts auto-migrate")
- **Problem:** "Seed an existing layout with old `cardOrder` (no `.fasting`); Call `reconcile()`; Confirm `.fasting` appears at end of `cardOrder`" — there's no test target wired in the project, no unit-test infrastructure for `HomeLayoutConfig`. The implementer can't run this as a unit test.
- **Recommendation:** Convert to a manual verification: "In simulator with a pre-existing `HomeLayoutConfig` (e.g. one saved before this build), launch the app — the `.fasting` card should appear at the end of the Home layout (visible cards section) without requiring a layout reset. If it doesn't, `reconcileWithCurrentCards()` isn't being called during decode — verify the call site in the config loader." This makes the verify step real and points the implementer at the likely failure mode.

#### CM5. Checklist 3.4 ("Schedule editor preset subtitles") is redundant with 0.5
- **Location:** Checklist 3.4 explicitly says "update per Phase 0 step 0.5 if not already done"
- **Problem:** Phase 0.5 already added these updates. Step 3.4 is dead-letter unless 0.5 was somehow skipped — but the dependency chain doesn't allow skipping 0.5 (other Phase 0 work depends on the enum reshuffle).
- **Recommendation:** Replace 3.4 with a verification check only: "Confirm subtitles from step 0.5 are still correct after any merge conflicts." Or just delete 3.4 and add the subtitle work explicitly to 0.5's checklist (it already is mentioned parenthetically). Currently the redundancy invites confusion ("did I do this twice?").

#### CM6. Phase 1.2 step 4 ("inline FastingScheduleEditor") doesn't address NavigationStack stripping
- **Location:** Checklist 1.2 step 4 ("Schedule: inline FastingScheduleEditor")
- **Problem:** `FastingScheduleEditor.swift:22` wraps its content in `NavigationStack { Form { ... } }`. Embedding it inline inside the onboarding flow's `TabView` will create a nested NavigationStack, which produces a double nav bar and broken Cancel/Save toolbar buttons. Either FastingScheduleEditor needs an `embedded: Bool` flag to skip the NavigationStack, or the onboarding flow needs to render only the `Form` content from FastingScheduleEditor.
- **Recommendation:** Add an explicit checklist step: "Add `var embedded: Bool = false` to `FastingScheduleEditor.swift`. When `embedded == true`, omit the NavigationStack + toolbar, and surface Save action via the onboarding flow's bottom button instead. Verify: no double nav bar when the editor renders inline."

#### CM7. Checklist 7.4 — DigestiveStateCard runtime configuration not addressed
- **Location:** Checklist 7.4 ("DigestiveStateCard")
- **Problem:** Snippet shows `@StateObject private var fastingService = FastingService()`. But `FastingService` is `.notConfigured` by default — it requires `configure(schedule:activeSession:)` to be called before any state is meaningful. The checklist doesn't address this.
- **Impact:** Card will permanently display the empty/default state on Home, never reflecting the actual fasting state.
- **Recommendation:** Add to the snippet: `.onAppear { if let s = schedules.first { fastingService.configure(schedule: s, activeSession: sessions.first(where: \.isActive)) } }`. Same `.onChange(of: scenePhase)` handler as FastingView (line 117-120) for re-configuration on foregrounding.

---

### LOW (Consider for Future)

#### CL1. Several code snippets use `...` placeholders or pseudo-Swift
- **Location:** Checklist 5.3 ("compute sleep score from summary — helper"), 8.1 ("adjust field name"), 5.2 ("derive however existing logic does")
- **Problem:** Each `...` or "helper" without definition forces the implementer to invent something — increasing inconsistency between phases.
- **Recommendation:** Per CH1/CH2 above, resolve concretely. The remaining "helper" references should either inline the logic or extract to a shared file at first use.

#### CL2. Checklist phase commit messages are suggested, not enforced
- **Location:** End of each phase ("git commit -m \"Phase N: ...\"")
- **Problem:** Free-text commits can drift. Not a real issue for this checklist but the project might want a convention.
- **Recommendation:** Acceptable as-is; project doesn't appear to enforce commit message format (per recent commits).

#### CL3. `BreakFastIntent` target-membership verification deferred to runtime
- **Location:** Checklist 6.1 ("Confirm target membership: file is in Cadence/Widgets/ ... Verify: xcodebuild succeeds")
- **Problem:** PBXFileSystemSynchronizedRootGroup membership for the CadenceWidget target is not explicitly verified before this point. If the widget target doesn't auto-include `Cadence/Widgets/`, the file won't be visible to it.
- **Recommendation:** Add a pre-check in 6.1: "Before adding BreakFastIntent.swift, verify by grep: `grep -A3 'CadenceWidget' Cadence.xcodeproj/project.pbxproj | grep -i synchroniz` — confirms whether the widget target uses sync groups. If not, add the file to both targets explicitly via Xcode UI." This catches the failure mode before the implementer wastes time writing the intent.

---

## Missing Elements

- [ ] Concrete sleep-score derivation helper (CH1)
- [ ] Correct field names for sleep onset (`bedtime`) and removal of `startTime` (CH2)
- [ ] HealthKitServiceFactory.shared injection wiring (CH3)
- [ ] Elapsed-time computation source for cap detection (CH4)
- [ ] Explicit FastingCompletionEvent init call (CH5)
- [ ] Debug-seed helper for testing access states (CM1)
- [ ] Three sub-checkboxes for access-state branches in success criteria walkthrough (CM2)
- [ ] FastingScheduleEditor `embedded: Bool` flag (CM6)
- [ ] DigestiveStateCard configure-on-appear (CM7)
- [ ] BreakFastIntent target-membership pre-check (CL3)
- [ ] Forward-reference note in Phase 1.4 about Phase 7 deletion (CC1)

## Unverified Assumptions

- [ ] `PBXFileSystemSynchronizedRootGroup` actually includes `Cadence/Widgets/` in the CadenceWidget target — Risk: Medium. CL3 mitigation: grep check before Phase 6.1.
- [ ] `FastingEligibility` `@Query` returns rows in deterministic order such that `rows.first` is consistently the singleton row — Risk: Low. There's only ever one row per user; even if `@Query` returns multiple due to race conditions, `rows.first` returning ANY of them is correct. But worth a verify step in 0.3.
- [ ] `UNCalendarNotificationTrigger` with `DateComponents(hour: x, minute: y)` and `repeats: true` fires daily — Risk: Low. This is the documented Apple pattern; existing fasting notifications use it (FastingService.swift:226-228).
- [ ] Existing Watch Live Activity rendering (with `WatchLogoRing` UIImage pattern) survives the color/copy changes in Phase 3.2 — Risk: Low. Phase 3.5 includes explicit Watch verification, so this is caught.

## Questions for Clarification

1. **Sleep score derivation (CH1):** SleepQuality-enum mapping (`excellent → 95`, `good → 80`, etc.) or linear from `totalHours`? Recommend the enum mapping — already a domain concept; aligns with existing `SleepQuality` semantics.
2. **Phase 1.4 strategy (CC1):** Do the Home routing work in Phase 1 (then re-do in Phase 7), or defer all Home routing to Phase 7 with v1.0.0 having no Home access (only via Stress factor sheet and FastingView empty-state CTA)?
3. **Debug-seed mechanism (CM1):** Add a debug menu toggle to AppConfig for forcing access states, or rely on lldb expression evaluation for testing?

## Recommendations

1. **Patch the 5 HIGH code-snippet errors in one pass** — all in Phases 5/8 and 2 and 4. Together they fix the "won't compile" surface. Total checklist edit cost: ~15 minutes.
2. **Decide CC1 strategy** before implementation starts. Recommend: defer Phase 1.4 Home routing entirely; v1.0.0 ships with FastingView empty-state CTA and Stress factor sheet as the only entry points. Phase 7 introduces the Home card with routing built-in. Eliminates duplicate work and merge risk.
3. **Add the `embedded: Bool` flag step** to Phase 1.2 (CM6) — without it, the onboarding flow's schedule step will visibly break.
4. **Add a single debug-seed helper** for FastingEligibility states (CM1). Even a 10-line debug-only function in `FastingEligibility.swift` makes 4 manual verify steps actionable.
5. **Expand success-criteria walkthrough** to 1:1 map plan criteria (CM2).
6. **Run `/develop resolve`** on this audit to produce a RESOLVED checklist, then proceed to `/develop implement`.

---

## Verdict Detail

**NEEDS REVISION.** Coverage of plan steps is complete; ordering is dependency-safe; per-phase build verification is included; the new Phase −1 user-approval gate is correctly placed. But the four wrong-API code snippets (CH1–CH4) would block compilation in three different phases, and CC1's duplicate-work issue creates real merge risk between staged PRs. Each fix is small (most are one-line). Cost to resolve: 30–60 minutes of checklist editing.
