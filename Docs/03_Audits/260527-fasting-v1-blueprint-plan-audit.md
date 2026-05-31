# Plan Audit Report: Fasting v1 Blueprint

**Audit Date:** 2026-05-27
**Plan Path:** `Docs/02_Planning/Specs/260527-fasting-v1-blueprint-plan.md`
**Source audit informing plan:** `Docs/03_Audits/260527-fasting-blueprint-gap-audit.md`
**Auditor:** audit agent (in-process, plan author is current model — confirmation-bias mitigation: load-bearing claims cross-verified against source)
**Verdict:** **NEEDS REVISION** — 3 critical issues + 5 high. Foundation is sound, but several Phase 2/6/1 details would silently fail at runtime or in production builds.

---

## Executive Summary

The plan correctly sequences work by safety priority and respects the audit §9 resolutions. However, source-code verification surfaces three blocking issues that the plan didn't anticipate: (1) a pre-existing Debug-vs-Release App Group ID mismatch that breaks the Phase 6 `LiveActivityIntent` reconciliation path in Release builds; (2) Phase 2's 24h-cap notification has no call-site that fires when a new session starts (only on schedule save); (3) Phase 1's eligibility check can't distinguish "user not yet onboarded" from "user blocked by SCOFF." High-severity items center on SwiftData `[Bool]?` storage (not natively supported), Phase 5 HRV/sleep fetch duplication with `StressViewModel`, and unverified `FastingActivityAttributes` target membership patterns the Phase 6 intent must inherit.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. App Group ID mismatch between Debug and Release entitlements will break Phase 6 in production
- **Location:** Plan Phase 6 (steps 25–27); not addressed in §Risks
- **Problem:** `Cadence.xcodeproj/project.pbxproj` line 773 binds Debug config to `Cadence/CadenceDebug.entitlements`, which declares App Group `group.com.hariom.cadence`. Line 826 binds Release config to `Cadence/Cadence.entitlements`, which declares `group.com.hariom.cadence.dev`. The widget target uses `CadenceWidget/CadenceWidget.entitlements` with `group.com.hariom.cadence` (no `.dev` suffix). All existing shared-data code (`SharedStressData.swift:22`, `ScreenTimeManager.swift:39, 181`) hardcodes the non-`.dev` ID.
- **Impact:** In Debug builds the app and widget share the same App Group (works fine — that's why this hasn't been noticed). In Release builds the main app reads/writes the `.dev` suite while the widget reads/writes the non-`.dev` suite. The Phase 6 `BreakFastIntent` flow (widget writes pending-break flag → app reads on foreground) would silently fail in TestFlight and App Store builds. Existing shared-stress-data widget might already be silently broken in Release, but Phase 6 is the first feature that surfaces it as a user-visible bug ("End Fast button does nothing").
- **Recommendation:** Before Phase 6 (ideally before Phase 0 to remove the foot-gun for all later work), fix the entitlements to use the same App Group across both Debug and Release builds. **Per `MEMORY.md` `feedback-signing-entitlements` rule, this requires explicit user approval before any *.entitlements edit.** The audit should flag this as a required user-approval gate, not a silent fix.
- **Workaround if user defers:** Test Phase 6 in Release/TestFlight build before declaring it shippable. Do not rely on Debug behavior.

#### C2. Phase 2 cap24h notification has no scheduling call site for new sessions
- **Location:** Plan Phase 2 step 10
- **Problem:** Plan says "In `scheduleNotifications(for:)`, when an `activeSession` is provided, additionally schedule…" But `FastingService.scheduleNotifications(for:)` is only called from `FastingScheduleEditor.swift:215-218, 230-233` when the user saves a schedule. It is **not** called when a new `FastingSession` is created. Session creation happens in `FastingView.handleStateTransition` (line 615-628) on the eating→fasting auto-transition, and in `FastingView.startFastNow` (line 649-670) on manual start.
- **Impact:** As specified, the cap-24h notification only fires for sessions whose schedule was modified after creation (rare). The default flow — schedule once, session created via state transition — never schedules the cap notification. The entire forgotten-stop guard is non-functional.
- **Recommendation:** Add an explicit `func schedule24hCapNotification(for session: FastingSession)` to `FastingService`. Call it from BOTH session-creation sites in `FastingView`. Also cancel it in `breakCurrentFast()` and on `actualEndAt` being set (via the edit sheet from step 13). Update `clearNotifications` to include `wp.fasting.cap24h`.

#### C3. Eligibility check cannot distinguish "not onboarded" from "blocked by SCOFF"
- **Location:** Plan Phase 1 step 8 (and downstream usage in Phase 7 step 31)
- **Problem:** `FastingEligibility.canInitiate` is defined as `cleared && age18Plus && notPregnant && notLactating && scoffCleared`. For a brand-new user (no row in the DB), the query returns `nil`, so `eligibility?.canInitiate ?? false` evaluates to `false`. The plan's routing then sends the user to `FastingCareInterventionView` — but the correct destination is `FastingOnboardingFlow` (they've never been screened).
- **Impact:** Every first-time user lands on the soft-block care screen instead of the onboarding flow. They can never start a fast. This is feature-killing on day one.
- **Recommendation:** Define three routing states explicitly:
  - `eligibility == nil` → `FastingOnboardingFlow` (never screened)
  - `eligibility != nil && !canInitiate` → `FastingCareInterventionView` (screened, blocked)
  - `eligibility != nil && canInitiate` → `FastingView` (cleared)
  
  Introduce an enum `FastingAccessState` returned by a single helper to centralize this logic. Update all three call sites (Home launcher, Stress factor, FastingView entry).

---

### HIGH (Should Fix Before Proceeding)

#### H1. `scoffAnswers: [Bool]?` is not a native SwiftData stored type
- **Location:** Plan Phase 0 step 3 (`FastingEligibility` model definition)
- **Problem:** SwiftData (as of iOS 17/18) does not auto-persist `[Bool]` as a stored property of an `@Model`. Grep of `Cadence/Models/*.swift` finds no existing `[Bool]` or `[String]` stored attributes — the codebase has no precedent for handling this. The plan does not specify the storage mechanism.
- **Impact:** Compilation may succeed but persistence will silently drop the field, or the model won't compile depending on Swift Macros version. Either way, SCOFF answers won't round-trip.
- **Recommendation:** Pick one:
  - **Cleanest:** Five separate stored `Bool` properties: `scoffAnswerSick`, `scoffAnswerControl`, `scoffAnswerOneStone`, `scoffAnswerFat`, `scoffAnswerFood`. Verbose but explicit and queryable.
  - **Alt:** Single `scoffAnswersJSON: String?` storing JSON-encoded `[Bool]`, with a computed `scoffAnswers: [Bool]?` doing decode/encode.
  - Update the plan to specify which.

#### H2. Phase 5 HRV/sleep fetch duplication risk is unresolved
- **Location:** Plan Phase 5 step 22; mentioned in §Risks but no mechanism specified
- **Problem:** `StressViewModel` already exposes `todayHRV: Double?`, `hrvHistory: [DailyMetricSample]`, and `sleepHistory: [DailySleepSummary]` as `@Published` fields (lines 52, 64, 61 of StressViewModel.swift). It also has a `lastHRVHistory` cache (line 160). But `StressViewModel` is instantiated per-View (`@StateObject`), not as a shared singleton. The plan says "do not parallel-fetch the same data" but doesn't specify how `FastingContextProvider` (a new ObservableObject) would access the already-fetched data.
- **Impact:** If `FastingContextProvider` independently calls `HealthKitService.fetchHRV(...)`, every Fasting view open triggers a duplicate HealthKit query. HealthKit queries are not cheap (multi-100ms common) and contribute to the "app feels slow" experience the plan otherwise tries to avoid.
- **Recommendation:** Either:
  - (a) Extract HRV/sleep fetching into a shared `@MainActor` service injected via environment (small refactor — would also benefit `StressViewModel`).
  - (b) Cache results in `UserDefaults` (or `SharedStressData.swift` pattern) on a per-day basis; both `StressViewModel` and `FastingContextProvider` read from cache, only one writes after a fresh fetch.
  - Specify which in the plan before Phase 5 begins.

#### H3. Phase 6 step 25 wording misleads about cross-process state access
- **Location:** Plan Phase 6 step 25, second-to-last sentence
- **Problem:** Plan says: "In `perform()`: write a 'pending break fast' timestamp to `UserDefaults(suiteName:)`, then call `ActivityManager.shared.endFastingActivity(completed: ...)` directly if possible from the intent process." The "if possible" hedge is correct, but an implementer skimming the step will see "call ActivityManager.shared" and assume the singleton is shared. It isn't — widget extension and app are separate processes; each has its own singleton instance with empty state.
- **Impact:** Bug pattern: implementer calls `ActivityManager.shared.endFastingActivity(...)` from the intent, observes nothing happens (the widget's singleton has no `fastingActivity` reference), then debugs cross-process state for hours.
- **Recommendation:** Rewrite step 25 to remove the "call directly if possible" hedge. State unambiguously: "The intent writes a pending-break payload (timestamp + reason) to `UserDefaults(suiteName: <appGroupID>)` and returns. No direct call to `ActivityManager`. The app reads the pending payload on next foreground (step 27) and closes the SwiftData session + ends the Live Activity. End-of-activity from the intent process can call `Activity<FastingActivityAttributes>.activities.first?.end(...)` directly — that *is* cross-process safe because ActivityKit owns its own shared state." This last detail (ending the Activity directly is OK even though SwiftData mutation isn't) is important.

#### H4. Phase 7 DigestiveStateCard integration with HomeLayoutEditor is hand-waved
- **Location:** Plan Phase 7 steps 30–31; §Risks mentions but doesn't resolve
- **Problem:** Verified `HomeLayoutEditor.swift` (120 lines) uses a `HomeCardID` enum-based registration: the layout stores a `cardOrder: [HomeCardID]` and `hiddenCards: Set<HomeCardID>`. The plan never mentions `HomeCardID` and doesn't specify:
  - Adding a new `HomeCardID.fasting` case (or whatever slug)
  - Default position in `HomeLayoutConfig.reset()`
  - `displayName`, `iconName`, `subElements` (if any)
  - How the new card renders inside HomeView's actual layout (the file consuming `cardOrder`)
- **Impact:** Implementer may add the card with hardcoded placement, breaking the customization system or being overwritten by user re-orderings.
- **Recommendation:** Before Phase 7 starts, read `HomeLayoutConfig` (location TBD — should be in same area as `HomeLayoutEditor`) and the consumer in `HomeView`. Update plan step 30 to specifically:
  - Add `case fasting` to `HomeCardID`
  - Add `displayName: "Fasting"`, `iconName: "fork.knife.circle"`, `subElements: []`
  - Insert into default `cardOrder` at index N (specify)
  - Render branch in HomeView's `ForEach(layout.cardOrder)` body

#### H5. Phase 4 ↔ Phase 6 interaction is unspecified for Live Activity overachieving state
- **Location:** Plan Phase 4 step 21 and Phase 6 step 26 in combination
- **Problem:** Phase 4 introduces `isOverachieving` state shown only in `FastingView`. Phase 6 step 26 places the End Fast button in the Live Activity's bottom region "only when !isCompleted && !isBroken". But overachieving sessions have `isCompleted = false` *and* `progress = 1.0` (per Phase 4). Need to specify: does the Live Activity also render an overachieving state (soft pulse / bonus copy)? Does the End button label change? What about the Watch view?
- **Impact:** Live Activity will keep showing "Eat window opens at HH:MM" while the app shows "BONUS TIME +5m" — confusing inconsistency between surfaces.
- **Recommendation:** Add a Phase 4/6 cross-cut step: extend `FastingActivityAttributes.ContentState` with `isOverachieving: Bool` (along with the `isCapped24h` from Phase 2 — group these schema changes into a single attributes update to avoid cascade). Render: phone view shows "+Xm bonus" instead of "ends in HH:MM"; Dynamic Island compactTrailing shows the bonus count instead of timer; the End button copy reads "End fast" in both states (cap and bonus).

---

### MEDIUM (Fix During Implementation)

#### M1. Care Intervention copy assumes US resources
- **Location:** Plan Phase 1 step 5
- **Problem:** "National Alliance for Eating Disorders" and "988" are US-only. If Cadence ships internationally, these are wrong or inaccessible for non-US users.
- **Recommendation:** Either (a) add a locale-aware resource map (small JSON keyed by country code), or (b) ship US-only links in v1 with a "this is US-only; international resources coming" caveat. Either is acceptable but the plan should decide.

#### M2. Accessibility is under-specified across new surfaces
- **Location:** Plan does not address VoiceOver, Dynamic Type, or accessibility labels for: SCOFF questionnaire, soft pulse animation (Phase 4), bonus-time count, weekly grid, Live Activity interactive button, Care Intervention view.
- **Recommendation:** Add an accessibility checklist to §Success Criteria. SCOFF in particular needs explicit accessibility: each answer must be a clearly labeled Toggle with semantic value; "I prefer not to answer" is not currently an option — verify with user (per blueprint, SCOFF mandates a yes/no answer).

#### M3. SCOFF intervention rate (regulatory KPI) has no instrumentation plan
- **Location:** Plan does not address how to log SCOFF outcomes
- **Problem:** Blueprint defines SCOFF Intervention Rate as a safety KPI: "While a high rate is not a 'product engagement success,' it is a massive success in institutional risk mitigation." The plan persists individual answers to `FastingEligibility` but doesn't surface aggregate metrics anywhere.
- **Recommendation:** At minimum, log SCOFF outcome (cleared vs blocked, anonymized) to whatever analytics surface Cadence already uses (verify if one exists; Cadence appears to have none today — flag for product decision). Or persist count in a privacy-respecting way.

#### M4. Plan claims "Phase 3 zero engineering risk" — overstates
- **Location:** Plan Phase 3 intro line
- **Problem:** Phase 3 step 16 modifies the Live Activity widget which has its own iOS rate limits and view-archive constraints (per memory: `WatchLogoRing` uses `UIImage(named:)` because the watch view archive can't resolve asset names). Color changes are minor risk, but copy changes that affect Watch family rendering need explicit watch verification.
- **Recommendation:** Soften to "low engineering risk" and add a verification: open Live Activity on Apple Watch after Phase 3 to confirm Watch family still renders correctly with updated copy.

#### M5. SCOFF back-navigation policy is ambiguous
- **Location:** Plan Phase 1 step 6 and §Risks
- **Problem:** Risk table says "allow Back navigation within the flow (but not after a disqualifying answer is submitted — that triggers Care immediately)." But the user might have miss-tapped a Toggle. Once they hit "Submit" and Care appears, returning to "fix" the answer feels like a bypass attempt.
- **Recommendation:** Explicit policy: Within the SCOFF step (before Submit), Toggles are freely editable. After Submit with ≥2 positives → Care view. From Care view, "Re-take screening" returns to step 3 fresh — answers are not pre-filled. This protects against gaming but allows correction.

#### M6. Phase 0 step 4 doesn't address legacy `20:4` `eatWindowDurationHours = 4` migration math
- **Location:** Plan Phase 0 step 4 and §Risks (mentioned but math not specified)
- **Problem:** Existing user with `FastingSchedule(scheduleType: "20:4", eatWindowDurationHours: 4)` opens the app after upgrade. `resolvedScheduleType` falls back to `.custom` (correct). `displayLabel = "20h fast"` (correct via `FastingScheduleType.formatDuration(20)`). `FastingScheduleEditor.syncTypeFromWindow` reads the window and computes preset — for 4h eat = 20h fast = `.custom`. All fine. **But:** `FastingSchedule.applyFastDuration(_:)` (line 135-138) maps `FastingScheduleType.preset(forFastDurationHours:)` — after removing `ratio20_4`, calling this with `hours: 20` returns `.custom`. The user's preset is correctly preserved as Custom 20h. No data corruption.
- **Status:** This is verified-safe. No plan change needed but the plan should mention this verification was done.

---

### LOW (Consider for Future)

#### L1. Notification count after this plan: ~6 daily + 1 per-session
- **Location:** Phase 2 + Phase 8 additions
- **Problem:** iOS limit is 64 pending notifications per app. Cadence has 4 existing fasting notifs + adds cap24h (per-session, one-shot) + startReminder (daily) = ~6. Plus other Cadence features may use notifications. Well within budget but worth a one-line acknowledgment.

#### L2. No localization (i18n) for new copy
- **Location:** All new copy (Phases 1, 3, 5, 7, 8) is raw English strings, not wrapped in `String(localized:)` or string catalog
- **Problem:** Unknown if Cadence is internationalized. Existing code in `FastingView.swift` is also un-localized, so plan is consistent — but if i18n is a future direction, this widens the gap.

#### L3. `FastingActivityAttributes` target-membership pattern unverified for `BreakFastIntent`
- **Location:** Plan Phase 6 step 25
- **Problem:** Verified `FastingActivityAttributes.swift` is at `Cadence/Widgets/` (per pbxproj, in the main app target's Sources). With `PBXFileSystemSynchronizedRootGroup`, files in `Cadence/Widgets/` are auto-included in the Cadence target. The widget compiles against this file — presumably via membership in both targets, or by being in a shared sync-group. Without reading the widget target's membership rules, can't verify `BreakFastIntent.swift` placed at `Cadence/Widgets/BreakFastIntent.swift` will automatically be visible to both.
- **Recommendation:** When implementing, verify by adding the file and confirming both `xcodebuild -workspace ... -scheme Cadence build` and `xcodebuild -project ... -target CadenceWidget build` succeed.

---

## Missing Elements

- [ ] Specification of the SwiftData storage shape for SCOFF answers (H1)
- [ ] Eligibility routing state machine (C3)
- [ ] Cap-24h notification scheduling call site (C2)
- [ ] App Group entitlement reconciliation pre-Phase 6 (C1)
- [ ] HomeLayoutConfig and `HomeCardID.fasting` integration steps (H4)
- [ ] Live Activity overachieving + capped state schema and rendering (H5)
- [ ] Accessibility checklist for new surfaces (M2)
- [ ] Localization decision (L2 / M1)
- [ ] SCOFF outcome instrumentation/telemetry decision (M3)
- [ ] Verification that pre-existing `SharedStressData.save()` works in Release builds (related to C1 — may already be broken)

## Unverified Assumptions

- [ ] `BreakFastIntent.swift` at `Cadence/Widgets/` will be visible to both app and widget targets via existing sync-group convention — Risk: Medium. Verify by adding the file.
- [ ] `LiveActivityIntent` can directly call `Activity<FastingActivityAttributes>.activities.first?.end(...)` from widget process — Risk: Low. This is the documented Apple pattern.
- [ ] Cadence has no existing analytics surface to plumb SCOFF intervention rate into — Risk: Low. Plan author confirms grep finds no `Mixpanel`, `Amplitude`, `Firebase Analytics` patterns in Cadence/. Telemetry decision is therefore deferred to product.
- [ ] HealthKit sleep authorization is already requested on first launch — Risk: Low. Verified: `HealthKitService.swift:47-48` adds `.sleepAnalysis` to the requested types. Phase 8 bedtime heuristic is unblocked.
- [ ] Existing 4 daily notifications don't conflict with the new startReminder identifier `wp.fasting.startReminder` — Risk: Low. Grep confirms no existing identifier match.

## Questions for Clarification

1. **App Group reconciliation (C1)**: Should we fix the Debug/Release App Group mismatch as part of this work (requires user approval per memory rule), or scope Phase 6 to "Debug-only" until a future entitlements pass? *Plan author leans toward fixing — Phase 6 isn't shippable without it.*
2. **Care resources scope (M1)**: US-only v1 with international caveat, or locale-aware resource map?
3. **SCOFF answer storage (H1)**: Five separate `Bool` fields, or `scoffAnswersJSON: String?`?
4. **Phase 5 fetch sharing (H2)**: Extract a shared HRV/sleep service, or use App-Group-cached values?
5. **Telemetry (M3)**: Add a minimal analytics surface for SCOFF intervention rate, or defer to a future analytics initiative?

## Recommendations

1. **Resolve C1 first.** Decision needed: fix App Group mismatch (user approval gate) or defer Phase 6 until a separate entitlements pass. Cannot ship Phase 6 to TestFlight without this.
2. **Patch C2 in-place.** Add `schedule24hCapNotification(for: session)` method and two call sites. Small but blocking.
3. **Refactor `FastingEligibility.canInitiate` into a 3-state enum return** (C3). One change, three call sites updated, eliminates the day-one feature-killer.
4. **Settle H1 storage shape** before Phase 0 step 3 starts. Five `Bool` fields is the safer recommendation given the codebase's lack of precedent for transformable arrays.
5. **Read `HomeLayoutConfig` source** before Phase 7. Update plan step 30 with concrete `HomeCardID.fasting` integration steps.
6. **Group the Live Activity attribute changes from Phases 2, 4, and 6 into one schema update.** Three separate ContentState changes risks bugs; one consolidated change is cleaner.
7. **Run `/develop resolve`** on this audit to produce a RESOLVED plan that incorporates these fixes, then proceed to `/develop checklist`.

---

## Verdict Detail

**NEEDS REVISION.** The plan's structure, sequencing, and resolution mapping from the blueprint audit are sound. But the C1/C2/C3 trio would each silently break the feature in production. H1 is a Swift compile/runtime issue. H2–H5 are specification gaps that would surface as bugs during implementation. Total revision cost is small (likely 30 minutes of plan editing) but mandatory before checklisting.
