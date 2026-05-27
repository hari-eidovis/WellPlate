# Implementation Plan: Fasting v1 Blueprint — RESOLVED

**Date:** 2026-05-27
**Slug:** `fasting-v1-blueprint`
**Source plan:** `Docs/02_Planning/Specs/260527-fasting-v1-blueprint-plan.md`
**Source audit:** `Docs/03_Audits/260527-fasting-v1-blueprint-plan-audit.md`
**Constraint:** Blueprint v1 boundary is **binding** — features that violate the v1 exclusion list must be removed/hidden even if currently implemented.

---

## Audit Resolution Summary

| ID | Severity | Verdict | Resolution |
|---|---|---|---|
| **C1** | CRITICAL | ✅ Resolved | New Phase −1 (Pre-flight) aligns Release entitlements to `group.com.hariom.cadence` (drops `.dev` suffix). User-approved decision. Also unblocks pre-existing `SharedStressData` Release-build risk. |
| **C2** | CRITICAL | ✅ Resolved | New `FastingService.schedule24hCapNotification(for: session)` method + 2 call sites in `FastingView` (session creation paths) + cancellation in break/edit paths. Phase 2 step 10 rewritten. |
| **C3** | CRITICAL | ✅ Resolved | New `FastingAccessState` enum (`onboarding \| careBlocked \| granted`) + single helper. All 3 routing sites use it. Phase 1 step 8 rewritten. |
| **H1** | HIGH | ✅ Resolved | Five separate Bool stored properties on `FastingEligibility`: `scoffSick`, `scoffControl`, `scoffOneStone`, `scoffFat`, `scoffFood` (per user decision). Phase 0 step 3 updated. |
| **H2** | HIGH | ✅ Resolved | New `SharedHealthMetrics` struct following `SharedStressData.swift:22-43` pattern: App-Group-cached per-day values (HRV, sleep score). Both `StressViewModel` and `FastingContextProvider` read; whichever fetches first writes. Phase 5 step 22 rewritten. |
| **H3** | HIGH | ✅ Resolved | Phase 6 step 25 wording rewritten. Explicitly: intent writes payload to UserDefaults + ends `Activity` directly (ActivityKit is cross-process safe); app reconciles SwiftData on next foreground. No misleading `ActivityManager.shared` call. |
| **H4** | HIGH | ✅ Resolved | Phase 7 step 30 rewritten with concrete `HomeCardID.fasting` integration: add case to enum, define `displayName`/`iconName`, no sub-elements; `HomeLayoutConfig.reconcileWithCurrentCards()` auto-migrates existing users; HomeView `cardView(for:)` gets new branch. |
| **H5** | HIGH | ✅ Resolved | Live Activity attribute schema changes from Phases 2/4/6 consolidated into single update done at Phase 2 step 11. ContentState gains `isCapped24h: Bool` AND `isOverachieving: Bool` AND `acceptsEndIntent: Bool` in one pass. |
| **M1** | MEDIUM | ✅ Resolved | US-only v1 with footer caveat (per user decision). Phase 1 step 5 specifies the exact footer copy. |
| **M2** | MEDIUM | ✅ Resolved | Accessibility checklist added to §Success Criteria + per-phase verification notes for SCOFF, soft pulse, weekly grid, Live Activity button. |
| **M3** | MEDIUM | ✅ Acknowledged | No Cadence analytics surface exists (verified). SCOFF outcome persisted to `FastingEligibility` for future surfacing. Deferred to future analytics initiative; flagged in §Open Items. |
| **M4** | MEDIUM | ✅ Resolved | Phase 3 risk wording softened to "low" + Watch verification step added. |
| **M5** | MEDIUM | ✅ Resolved | SCOFF back-nav policy specified in Phase 1 step 6: Toggles editable before Submit; after Care view, re-take screening starts fresh (no pre-filled answers) to prevent gaming while allowing correction. |
| **M6** | MEDIUM | ✅ Acknowledged | Verified safe (audit confirmed). Inline note added to Phase 0 step 4. |
| **L1** | LOW | ✅ Acknowledged | Notification count post-plan: ~6 daily + 1 per-session. Well within iOS 64-notification limit. Note in §Risks. |
| **L2** | LOW | ✅ Acknowledged | No localization for new copy. Consistent with rest of app (un-localized). Flagged as future concern in §Open Items. |
| **L3** | LOW | ✅ Acknowledged | `BreakFastIntent.swift` target-membership verified at implementation time. Build-clean verification covers it. |

**Verdict: ALL RESOLVED.** Plan is ready for `/develop checklist`.

---

## Overview

Bring the existing fasting feature into compliance with the v1 blueprint. The v0 feature has solid bones (SwiftData models, three-state machine, working Live Activity, schedule editor, insight chart, celebration overlay). v1 adds the regulatory/safety floor (SCOFF screening, 24h cap, demographic gate, wellness disclaimer), the contextual intelligence layer (HRV/sleep-aware insights and recommendations), the calm-tone copy/color rework, the Lock Screen interactive `LiveActivityIntent`, and the missing 12:12 beginner preset.

---

## Requirements

(Unchanged from original plan — all R1–R22 carry forward verbatim. Out-of-scope list unchanged.)

### Safety / Regulatory (non-negotiable)
- R1. **SCOFF screening** with ≥2 positives soft-blocking initiation
- R2. **Age (≥18) + pregnancy/lactation gate** as a one-time fasting-specific flow
- R3. **24h hard cap** with auto-pause + "did you forget?" push, no auto-end
- R4. **Wellness disclaimer** un-skippable in onboarding
- R5. **Soft block** when ineligible: hide initiation surfaces, keep retrospective surfaces
- R6. **Care Intervention view** routing with NAED + 988 + US caveat footer <!-- RESOLVED: M1 — US-only with caveat -->

### v1 boundary compliance
- R7. **Remove `ratio20_4`** preset entirely
- R8. **Add `ratio12_12`** preset; make it the default for new schedules
- R9. **Keep `ratio18_6`** but reorder it last among presets
- R10. **No red colors** in active timer ring or Live Activity
- R11. **Replace punitive copy**

### Contextual intelligence (differentiator)
- R12. **Contextual HRV/sleep insight** under timer
- R13. **Stress-responsive recommendation banner** when recent stress is high
- R14. **Bedtime-derived start reminder** using HealthKit sleep history (no CLLocation in v1)
- R15. **Home "Digestive State" card** showing current state + readiness context

### Schema (additive only — no VersionedSchema)
- R16. **Add optional fields** to `FastingSession`: `completionStatus: String?`, `contextualHRV: Double?`, `contextualSleepScore: Int?`
- R17. **New `FastingEligibility` @Model** with 5 SCOFF answers as separate Bool fields <!-- RESOLVED: H1 — 5 Bool fields, not [Bool]? -->
- R18. **No replacement of existing `completed: Bool`**

### UX deltas
- R19. **Soft pulse + bonus-time count** at target hit; celebration overlay only on explicit "End Fast"
- R20. **`LiveActivityIntent` "End Fast"** button on Lock Screen / Dynamic Island
- R21. **Retroactive edit previous fast** UI
- R22. **Weekly 7-day calendar grid**

### Out of scope for v1
- ❌ Biological-phase tracking, weight projections, community, AI food scan, fasts >24h, CLLocation, HealthKit writes

---

## Architecture Changes

### New files
| Path | Purpose |
|---|---|
| `Cadence/Models/FastingEligibility.swift` | @Model storing 5 SCOFF Bool fields + demographic flags <!-- RESOLVED: H1 --> |
| `Cadence/Models/FastingCompletionStatus.swift` | Enum + extension on FastingSession |
| `Cadence/Models/FastingAccessState.swift` | Enum `onboarding \| careBlocked \| granted` + helper <!-- RESOLVED: C3 --> |
| `Cadence/Widgets/SharedHealthMetrics.swift` | App-Group-cached daily HRV + sleep score (per-day key) <!-- RESOLVED: H2 --> |
| `Cadence/Features + UI/Stress/Views/FastingOnboardingFlow.swift` | 4-step paged flow with back-nav policy <!-- RESOLVED: M5 --> |
| `Cadence/Features + UI/Stress/Views/FastingCareInterventionView.swift` | Care landing view with US-caveat footer <!-- RESOLVED: M1 --> |
| `Cadence/Features + UI/Stress/Views/FastingEditSessionSheet.swift` | Edit-previous-fast sheet |
| `Cadence/Features + UI/Stress/Views/FastingWeeklyGridView.swift` | 7-day consistency grid |
| `Cadence/Features + UI/Stress/Services/FastingContextProvider.swift` | Reads from `SharedHealthMetrics` cache <!-- RESOLVED: H2 --> |
| `Cadence/Features + UI/Stress/Services/FastingBedtimeHeuristic.swift` | Bedtime computation from HealthKit sleep |
| `Cadence/Features + UI/Home/Components/DigestiveStateCard.swift` | Home dashboard card |
| `Cadence/Widgets/BreakFastIntent.swift` | `LiveActivityIntent` (no cross-process singleton call) <!-- RESOLVED: H3 --> |

### Modified files
| Path | Change summary |
|---|---|
| `Cadence/Cadence.entitlements` | **Release entitlement edit:** App Group `group.com.hariom.cadence.dev` → `group.com.hariom.cadence`. Requires user approval at impl time. <!-- RESOLVED: C1 --> |
| `Cadence/App/CadenceApp.swift` | Register `FastingEligibility.self` in modelContainer list (line 43) |
| `Cadence/Models/FastingSession.swift` | Add 3 optional fields; add `resolvedStatus` computed property |
| `Cadence/Models/FastingSchedule.swift` | Drop `ratio20_4`; add `ratio12_12`; reorder presets; default `ratio12_12` |
| `Cadence/Models/HomeLayoutConfig.swift` | Add `case fasting` to `HomeCardID` enum; define displayName + iconName <!-- RESOLVED: H4 --> |
| `Cadence/Core/Services/FastingService.swift` | New `schedule24hCapNotification(for: session)` <!-- RESOLVED: C2 -->; bedtime-heuristic start reminder; cap progress display at 24h; `isOverachieving` flag |
| `Cadence/Core/Services/ActivityManager.swift` | Clamp Live Activity progress at 24h; render `isOverachieving` + `isCapped24h` |
| `Cadence/Widgets/FastingActivityAttributes.swift` | **Single schema update** adds `isCapped24h: Bool`, `isOverachieving: Bool`, `acceptsEndIntent: Bool` to ContentState (consolidated from Phases 2/4/6) <!-- RESOLVED: H5 --> |
| `CadenceWidget/LiveActivities/FastingLiveActivityView.swift` | Drop red colors; add `Button(intent: BreakFastIntent())`; render cap + overachieving states |
| `Cadence/Features + UI/Stress/Views/FastingView.swift` | Route via `FastingAccessState` helper <!-- RESOLVED: C3 -->; new copy/colors; soft pulse + bonus + explicit End; HRV/sleep insight; weekly grid; tappable history rows; 24h-cap banner |
| `Cadence/Features + UI/Stress/Views/FastingScheduleEditor.swift` | Default to `ratio12_12`; reordered preset list |
| `Cadence/Features + UI/Stress/Components/FastingCelebrationOverlay.swift` | (Trigger gating only) |
| `Cadence/Features + UI/Home/Views/HomeView.swift` | New `cardView(for:)` branch for `.fasting` rendering `DigestiveStateCard`; access-state-gated tap handler <!-- RESOLVED: H4, C3 --> |
| `Cadence/Features + UI/Stress/Views/StressView.swift` | Access-state-gated routing on `.fasting` factor card <!-- RESOLVED: C3 --> |

### Inter-target wiring
- `BreakFastIntent.swift` placed at `Cadence/Widgets/` alongside `FastingActivityAttributes.swift`. Target membership inherited from existing sync-group convention. Verify both `Cadence` and `CadenceWidget` schemes build clean after adding. <!-- RESOLVED: L3 -->
- App Group ID after C1 fix: `group.com.hariom.cadence` in both Debug and Release. All shared-data code (SharedStressData, ScreenTimeManager, new SharedHealthMetrics, BreakFastIntent payload) uses this single ID.

---

## Implementation Steps

Sequenced for **independent shippability**. Phase −1 is a one-shot pre-flight (entitlements). Phases 0–2 form the v1 safety floor. Phases 3–8 ship as separate releases.

### Phase −1 — Pre-flight: App Group entitlement alignment <!-- RESOLVED: C1 -->

**Goal:** Eliminate the Debug-vs-Release App Group mismatch so the LiveActivityIntent in Phase 6 works in production. Also unblocks pre-existing `SharedStressData` Release behavior.

**Requires explicit user approval at implementation time** per `MEMORY.md` `feedback-signing-entitlements` rule.

0. **Align Release App Group ID** (File: `Cadence/Cadence.entitlements`)
   - Action: Change `<string>group.com.hariom.cadence.dev</string>` (line 15) → `<string>group.com.hariom.cadence</string>`. Verify `CadenceWidget/CadenceWidget.entitlements` (line 7) and `Cadence/CadenceDebug.entitlements` (line 11) already use the non-`.dev` value (they do).
   - Why: Phase 6 cross-process state via `UserDefaults(suiteName:)` requires matching App Groups. Existing widget code (`SharedStressData.swift:22`) hardcodes the non-`.dev` ID and is silently broken in Release today.
   - Dependencies: none
   - Risk: Medium — touching entitlements requires Apple provisioning profile to include the `group.com.hariom.cadence` App Group capability for the Release-signed certificate. Verify in Apple Developer console before merging. If the App Group is not registered in the Release profile, the build will fail signing. Prep before the entitlement edit.
   - User approval: **mandatory** at implementation time.

**Phase −1 verification:** TestFlight build with Release signing → install on device → confirm Stress widget shows live data (proves App Group + UserDefaults round-trips in Release). Existing functionality, just newly verified.

---

### Phase 0 — Schema & preset foundation (no user-visible UI change)

**Goal:** Lay the data foundation.

1. **Add CompletionStatus enum** (File: `Cadence/Models/FastingCompletionStatus.swift` — NEW)
   - Action: `enum FastingCompletionStatus: String, Codable { case completed, endedEarly, overachieved, autoCappedAt24h }`. Extension on `FastingSession` exposing `var resolvedStatus: FastingCompletionStatus` deriving from `(completionStatus, completed)` with legacy fallback (`nil` → `completed ? .completed : .endedEarly`).
   - Dependencies: none
   - Risk: Low

2. **Add optional fields to FastingSession** (File: `Cadence/Models/FastingSession.swift`)
   - Action: Add stored properties — `var completionStatus: String?`, `var contextualHRV: Double?`, `var contextualSleepScore: Int?`. All optional, default `nil`. Do **not** remove `completed: Bool`. Add to `init` parameters with defaults.
   - Dependencies: none
   - Risk: Low — verify on first launch with existing data (no crash, all legacy fields readable).

3. **FastingEligibility model with 5 separate SCOFF Bool fields** (File: `Cadence/Models/FastingEligibility.swift` — NEW; `Cadence/App/CadenceApp.swift`) <!-- RESOLVED: H1 -->
   - Action: New `@Model final class FastingEligibility` with:
     ```swift
     var cleared: Bool = false
     var clearedAt: Date?
     var age18Plus: Bool = false
     var notPregnant: Bool = false
     var notLactating: Bool = false
     var scoffCleared: Bool = false      // computed at submit time
     var scoffSick: Bool = false         // Q1 — vomiting
     var scoffControl: Bool = false      // Q2 — lost control
     var scoffOneStone: Bool = false     // Q3 — 14lb in 3mo
     var scoffFat: Bool = false          // Q4 — body image
     var scoffFood: Bool = false         // Q5 — food dominates life
     var lastScreenedAt: Date?
     var scoffPositiveCount: Int { [scoffSick, scoffControl, scoffOneStone, scoffFat, scoffFood].filter { $0 }.count }
     var canInitiate: Bool { cleared && age18Plus && notPregnant && notLactating && scoffCleared }
     ```
   - Register in `CadenceApp.swift:43` modelContainer list.
   - Why: Individual Bool fields are SwiftData-native, queryable, and serve the SCOFF Intervention Rate KPI in §M3.
   - Dependencies: none
   - Risk: Low

4. **Define FastingAccessState helper** (File: `Cadence/Models/FastingAccessState.swift` — NEW) <!-- RESOLVED: C3 -->
   - Action:
     ```swift
     enum FastingAccessState { case onboarding, careBlocked, granted }
     extension FastingEligibility {
         static func accessState(from rows: [FastingEligibility]) -> FastingAccessState {
             guard let row = rows.first else { return .onboarding }
             return row.canInitiate ? .granted : .careBlocked
         }
     }
     ```
   - Why: Single source of truth for routing. `nil` row → onboarding; row exists but blocked → care; row clear → granted. Eliminates the day-one feature-killer from C3.
   - Dependencies: step 3
   - Risk: Low

5. **Preset reshuffle** (File: `Cadence/Models/FastingSchedule.swift`)
   - Action: Remove `case ratio20_4`. Add `case ratio12_12 = "12:12"` at top with `defaultEatHours = 12`, `defaultEatStartHour = 8`, icon `"sunrise"`, setupSubtitle `"Beginner-friendly 12h eating window"`. Reorder enum cases to: `ratio12_12, ratio14_10, ratio16_8, ratio18_6, custom`. Change `FastingSchedule` init default from `.ratio16_8` to `.ratio12_12`.
   - **Legacy `"20:4"` data**: Audit verified safe — `resolvedScheduleType` falls back to `.custom` for unknown raw values, `displayLabel` correctly shows "20h fast", `applyFastDuration(20)` correctly returns `.custom`. No data corruption. <!-- RESOLVED: M6 — verified safe -->
   - Dependencies: step 1
   - Risk: Medium → reduced to Low after legacy verification.

**Phase 0 verification:** Build all 4 targets. Launch with existing seed data; no SwiftData crashes. Seed a legacy `"20:4"` schedule → confirm it renders as "20h fast" (Custom) without breakage.

---

### Phase 1 — Safety core (SCOFF + eligibility + soft block)

**Goal:** Regulatory floor.

6. **Care Intervention view with US-caveat footer** (File: `Cadence/Features + UI/Stress/Views/FastingCareInterventionView.swift` — NEW) <!-- RESOLVED: M1 -->
   - Action: SwiftUI view with:
     - Non-clinical care message ("Fasting may not be the best fit for your current wellness journey right now…")
     - Three resource links: **National Alliance for Eating Disorders** (allianceforeatingdisorders.com/find-help), **988 Suicide & Crisis Lifeline** (988lifeline.org), "talk to a healthcare provider" reminder
     - Footer (small print): *"Resources listed are US-based. If you're outside the US, please contact your local mental health services or healthcare provider."*
     - "Re-take screening" CTA (routes to step 7 flow starting at SCOFF, fresh state — see M5 resolution).
   - **Accessibility:** All resource links must have explicit `.accessibilityLabel` describing target ("Opens National Alliance for Eating Disorders website"). Footer text uses `.accessibilityLabel` matching visible text. <!-- RESOLVED: M2 -->
   - Dependencies: step 4
   - Risk: Low (copy review by user before ship is mandatory — this is the most legally-sensitive surface).

7. **Fasting onboarding flow with explicit back-nav policy** (File: `Cadence/Features + UI/Stress/Views/FastingOnboardingFlow.swift` — NEW) <!-- RESOLVED: M5 -->
   - Action: 4-step `TabView(selection:)` paged flow:
     - **Step 1 — Disclaimer**: full-screen text "Cadence is for general wellness, not medical advice. Talk to a licensed provider before changing dietary habits." Un-skippable "I understand" button.
     - **Step 2 — Demographics**: three yes/no questions (`Toggle` style). "Are you 18 or older?" / "Are you currently pregnant?" / "Are you currently lactating?" Next button enables when all answered. Any disqualifying answer → present `FastingCareInterventionView` and abort onboarding (persist eligibility row with disqualifying flag set).
     - **Step 3 — SCOFF**: five yes/no `Toggle`s, freely editable before Submit. "Submit" button computes `scoffPositiveCount`. ≥2 → persist all 5 answers + `scoffCleared = false` + `lastScreenedAt = .now` + present Care view (abort). <2 → persist with `scoffCleared = true` and advance.
     - **Step 4 — Schedule**: reuse `FastingScheduleEditor` UI inline. Save creates `FastingSchedule` + sets `eligibility.cleared = true`, `clearedAt = .now`.
   - **Back-nav policy:** Within SCOFF step (before Submit), Toggles are freely editable. After Submit with ≥2 positives → Care. From Care, "Re-take screening" returns to step 3 with **fresh blank state** (no pre-fill) to prevent gaming while allowing correction.
   - **Mid-flow abandonment:** App backgrounding mid-flow → onboarding state is per-session, not persisted. Reopening the app returns to FastingView empty state; tapping Get Started restarts flow from step 1.
   - **Accessibility:** Each SCOFF Toggle gets `.accessibilityLabel` matching the question. Submit button has `.accessibilityHint("Submit your answers and continue.")`. <!-- RESOLVED: M2 -->
   - Dependencies: steps 3, 4, 6
   - Risk: Medium — multi-step nav has edge cases; back-nav policy above defines them explicitly.

8. **Replace FastingView Get Started CTA** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
   - Action: Get Started button (lines 203-228) presents `FastingOnboardingFlow` as sheet instead of jumping to `FastingScheduleEditor`. Gear icon (lines 78-87) remains the post-onboarding "Edit Fast" path.
   - Dependencies: step 7
   - Risk: Low

9. **Access-state-gated routing across surfaces** (Files: `Cadence/Features + UI/Home/Views/HomeView.swift`, `Cadence/Features + UI/Stress/Views/StressView.swift`) <!-- RESOLVED: C3 -->
   - Action: At each fasting entry point, query `FastingEligibility` via `@Query` and route via `FastingEligibility.accessState(from:)`:
     - `.onboarding` → present `FastingOnboardingFlow`
     - `.careBlocked` → present `FastingCareInterventionView`
     - `.granted` → present `FastingView`
   - Three call sites: HomeView fasting launcher (line 593-601, becoming `DigestiveStateCard` tap handler in Phase 7), StressView `.fasting` sheet (line 198), FastingView Get Started (covered in step 8 but uses access state to skip onboarding for already-granted users).
   - Dependencies: steps 4, 6, 7, 8
   - Risk: Low — central helper means one source of truth.

10. **Settings entry point for re-screening** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: Toolbar menu (next to gear icon) gains "Re-take wellness screening" option. Re-presents `FastingOnboardingFlow` from step 3 (SCOFF). Updates the existing `FastingEligibility` row (no new row).
    - Dependencies: step 7
    - Risk: Low

**Phase 1 verification:** Manual test 4 branches — never-screened (→ onboarding), demographic fail, SCOFF fail (≥2), pass. Each lands on correct destination. Soft block hides initiation; insight chart still visible. Build all 4 targets. VoiceOver pass through onboarding flow.

---

### Phase 2 — 24h cap + forgotten-stop guard

**Goal:** Prevent runaway fasts.

11. **Consolidated Live Activity ContentState schema update** (File: `Cadence/Widgets/FastingActivityAttributes.swift`) <!-- RESOLVED: H5 -->
    - Action: Add three Bools to `ContentState` in one pass (so Phases 2, 4, and 6 don't each emit a schema change):
      ```swift
      var isCapped24h: Bool = false        // Phase 2
      var isOverachieving: Bool = false    // Phase 4
      var acceptsEndIntent: Bool = false   // Phase 6 — used to conditionally render the End button
      ```
    - Why: Single schema change avoids three cascading Live Activity updates and the bugs that come with mid-flight state migrations.
    - Dependencies: none
    - Risk: Low — fields default to false; existing logic unaffected.

12. **24h cap notification: new method + 2 call sites** (Files: `Cadence/Core/Services/FastingService.swift`, `Cadence/Features + UI/Stress/Views/FastingView.swift`) <!-- RESOLVED: C2 -->
    - Action — `FastingService`:
      ```swift
      private static let notifCap24h = "wp.fasting.cap24h"

      func schedule24hCapNotification(for session: FastingSession) {
          let center = UNUserNotificationCenter.current()
          guard !notificationsBlocked else { return }
          let secondsUntilCap = (session.startedAt + 24*3600).timeIntervalSinceNow
          guard secondsUntilCap > 0 else { return }
          let content = UNMutableNotificationContent()
          content.title = "Fast paused at 24h"
          content.body = "You've been fasting for 24h. Did you forget to end your fast? Tap to adjust the end time."
          content.sound = .default
          let trigger = UNTimeIntervalNotificationTrigger(timeInterval: secondsUntilCap, repeats: false)
          center.add(UNNotificationRequest(identifier: Self.notifCap24h, content: content, trigger: trigger))
      }

      func cancel24hCapNotification() {
          UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notifCap24h])
      }
      ```
      Also add `notifCap24h` to existing `clearNotifications()` removal list.
    - Action — `FastingView`:
      - In `handleStateTransition` after creating session (line 620 area): `fastingService.schedule24hCapNotification(for: session)`
      - In `startFastNow` after `modelContext.insert(session)` (line 655 area): same call
      - In `breakCurrentFast` (line 682): `fastingService.cancel24hCapNotification()`
      - In `FastingEditSessionSheet` save handler (step 16): cancel cap notif if user set `actualEndAt` before now+24h
    - In `FastingService.updateState`, if `activeSession != nil && session.actualDurationSeconds > 24*3600`, set new `@Published var isCapped24h: Bool = true`, clamp `progress = 1.0`, `timeRemaining = 0`.
    - Dependencies: step 11
    - Risk: Medium → reduced. Per-session one-shot trigger has unique fire time, no collision with the daily eat-window notifications.

13. **Live Activity capped-state rendering** (Files: `Cadence/Core/Services/ActivityManager.swift`, `CadenceWidget/LiveActivities/FastingLiveActivityView.swift`)
    - Action: `ActivityManager.updateFastingActivity` — when elapsed > 24h, set `state.isCapped24h = true`, clamp `progress = 1.0`. In `FastingLiveActivityView` Lock Screen phone view, when `isCapped24h`, replace timer with "Paused at 24h" subtitle.
    - Dependencies: steps 11, 12
    - Risk: Low

14. **FastingView 24h-cap banner** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: When `fastingService.isCapped24h`, banner above `todayInfoCard` with two buttons: "End Fast" (calls existing break flow) and "Edit" (opens FastingEditSessionSheet pre-targeting the active session).
    - Dependencies: steps 12, 16
    - Risk: Low

15. **Edit previous fast sheet** (File: `Cadence/Features + UI/Stress/Views/FastingEditSessionSheet.swift` — NEW)
    - Action: Sheet with two `DatePicker`s for `startedAt` and `actualEndAt`. Validation: `end > start`, `end <= .now`, `(end - start) <= 24*3600`. On save: persist, set `completionStatus`: if `actualEndAt < targetEndAt` → `.endedEarly`; if `actualEndAt >= targetEndAt && actualEndAt - startedAt < 24h` → `.completed`; if `actualEndAt - startedAt == 24h` (or capped) → `.autoCappedAt24h`. Set legacy `completed` for compatibility. Cancel cap notification if applicable.
    - Dependencies: steps 1, 2, 12
    - Risk: Medium — validation must be tight.

16. **Wire history rows to edit sheet** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: Wrap each `fastHistoryRow` (lines 553-587) in `Button { editingSession = session }`. Add `@State editingSession: FastingSession?` + `.sheet(item: $editingSession) { FastingEditSessionSheet(session: $0) }`.
    - Dependencies: step 15
    - Risk: Low

**Phase 2 verification:** Seed session 25h old → cap notification fires, FastingView shows capped banner, Live Activity shows paused. Edit sheet rejects invalid date ranges. Validate audit trail: capped sessions resolve as `.autoCappedAt24h`. Build all 4 targets.

---

### Phase 3 — Copy / color / lexicon pass (low engineering risk)

<!-- RESOLVED: M4 — softened from "zero" to "low" + Watch verification added -->

**Goal:** Strip punitive language and urgent colors. Low engineering risk — but Live Activity changes need Watch-family verification.

17. **FastingView copy + colors** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action:
      - `stateLabel` (lines 692-698): `"FASTING"` → `"RESTING"`, `"EATING"` → `"EATING WINDOW"`.
      - `idleHeaderLabel` (lines 702-704): `"READY TO FAST"` → `"READY WHEN YOU ARE"`.
      - `ringColor` (lines 706-712): return `heroAccent` for `.fasting`, existing green for `.eating`. **Drop `.orange` entirely.**
      - `breakFastAlertMessage` (lines 131-137): *"Listening to your body is always the right choice. You've fasted for [duration] so far."*
      - Alert title (line 99): `"Break Fast Early?"` → `"End your fast?"`
      - "Break Fast" button (line 423): `"Break Fast"` → `"End Fast"`. Keep muted-red style.
      - History row label (line 574): `"Broken"` → `"Ended early"`.
      - Empty state subtitle (lines 196-200): *"Rest your digestive system and align eating with your body clock."*
    - Dependencies: none
    - Risk: Low

18. **Live Activity color + copy + Watch verification** (File: `CadenceWidget/LiveActivities/FastingLiveActivityView.swift`)
    - Action:
      - `ringColor(for:)` (lines 277-281): broken state → `.white.opacity(0.55)` instead of `.red`. Active state → keep `.orange` (Apple HIG-acceptable for time-elapsed; matches `heroAccent` family).
      - Broken-state text colors (lines 128, 167, 46): `.red` → `.white.opacity(0.7)`.
      - "Fast complete" → "Rest complete" in expanded center (line 42).
    - **Watch-family verification:** After change, run app on Apple Watch (or simulator pair) and confirm Live Activity renders text correctly on Watch via `.small` activityFamily path (lines 150-186). The `WatchLogoRing` and explicit `UIImage(named: "Cadence_Logo")` pattern (line 263) must still resolve. <!-- RESOLVED: M4 -->
    - Dependencies: none
    - Risk: Low (raised slightly above zero due to Watch surface).

19. **Notification copy** (File: `Cadence/Core/Services/FastingService.swift`)
    - Action: Update notification bodies (lines 222-263):
      - `"Eating Window Closed"` body → *"Your \(scheduleLabel) rest has begun. Hydrate well."*
      - `"1 Hour Left"` body → *"Eating window opens in 1 hour. Plan something nourishing."*
      - `"Fast Complete"` body → *"Rest complete. Break your fast whenever you feel ready."*
      - Caffeine cutoff: keep.
    - Dependencies: none
    - Risk: Low

20. **Onboarding + schedule editor copy** (File: `Cadence/Models/FastingSchedule.swift`)
    - Action: Update `setupSubtitle` per audit recommendation (lines 25-38).
    - Dependencies: step 5
    - Risk: Low

**Phase 3 verification:** Manual UI walkthrough on iPhone + Apple Watch. No "FASTING"/"BROKEN"/"Break Fast"/neon red/warning orange in any surface.

---

### Phase 4 — Soft completion + bonus time

21. **isOverachieving state** (Files: `Cadence/Core/Services/FastingService.swift`, `Cadence/Models/FastingSession.swift`)
    - Action: `@Published var isOverachieving: Bool = false` and `@Published var bonusElapsed: TimeInterval = 0` on `FastingService`. In `updateState`, if `activeSession != nil && elapsed > targetDuration && elapsed <= 24*3600`, set `isOverachieving = true`, `progress = 1.0`, compute `bonusElapsed = elapsed - targetDuration`. 24h cap from step 12 takes precedence (`isCapped24h` and `isOverachieving` are mutually exclusive).
    - Dependencies: step 2, step 12
    - Risk: Low

22. **Timer ring pulse + bonus label** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: In `activeTimerCard` when `isOverachieving`:
      - Ring at full, pulses opacity 0.85 ↔ 1.0 via `.repeatForever(autoreverses: true)`.
      - Time label: `"+\(formattedDuration(bonusElapsed))"`.
      - Subtitle: `"BONUS TIME"`.
      - Percentage line hidden.
      - One soft haptic at first transition to overachieving state (track via previous-state @State).
    - **Accessibility:** Pulse must respect `accessibilityReduceMotion`; when reduced, just hold static at full opacity. Time label needs `.accessibilityLabel("Bonus time: \(spokenDuration)")`. <!-- RESOLVED: M2 -->
    - Dependencies: step 21
    - Risk: Low

23. **Decouple celebration from auto-transition** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: In `handleStateTransition` (lines 611-644), split the `fasting → eating` block:
      - If `activeSession != nil` AND user has NOT explicitly ended (`@State didUserExplicitlyEnd = false`):
        - Mark `completionStatus = .overachieved`, `actualEndAt = .now`, `completed = true`. **No celebration.**
      - Celebration only fires in `breakCurrentFast()` (line 682) when `completionStatus = .completed`.
      - Reset `didUserExplicitlyEnd = false` on new session start.
    - **Four-scenario walkthrough** (must verify each in QA):
      - (a) User ends before target → `.endedEarly` + no celebration ✓
      - (b) User ends after target (during bonus) → `.completed` + celebration ✓
      - (c) Timer rolls into eat window without user action → `.overachieved` + silent close ✓
      - (d) 24h cap → `.autoCappedAt24h` + banner flow ✓
    - Dependencies: steps 21, 22
    - Risk: Medium — state interactions subtle.

**Phase 4 verification:** Seed sessions at each of the 4 scenarios. Walk through each. Confirm correct status, correct UI, correct celebration trigger.

---

### Phase 5 — Contextual intelligence

**Goal:** HRV + sleep insight under timer. Differentiator vs Zero/Fastic.

24. **SharedHealthMetrics App-Group cache** (File: `Cadence/Widgets/SharedHealthMetrics.swift` — NEW) <!-- RESOLVED: H2 -->
    - Action: New struct following the existing `SharedStressData` pattern:
      ```swift
      struct SharedHealthMetrics: Codable {
          var date: Date              // start-of-day key
          var hrvMs: Double?
          var sleepScore: Int?
          var lastUpdated: Date

          static let appGroupID  = "group.com.hariom.cadence"
          static let defaultsKey = "sharedHealthMetrics"

          static func loadForToday() -> SharedHealthMetrics? {
              guard let d = UserDefaults(suiteName: appGroupID),
                    let raw = d.data(forKey: defaultsKey),
                    let decoded = try? JSONDecoder().decode(SharedHealthMetrics.self, from: raw),
                    Calendar.current.isDate(decoded.date, inSameDayAs: Date()) else { return nil }
              return decoded
          }

          func save() {
              guard let d = UserDefaults(suiteName: Self.appGroupID),
                    let data = try? JSONEncoder().encode(self) else { return }
              d.set(data, forKey: Self.defaultsKey)
          }
      }
      ```
    - StressViewModel writes when it fetches HRV/sleep (small addition to existing fetch completion handler).
    - FastingContextProvider reads via `SharedHealthMetrics.loadForToday()`.
    - Cache invalidates at midnight (date check). On nil read, FastingContextProvider falls back to fetching directly (cold-start case).
    - Dependencies: Phase −1 (App Group must be aligned for Release behavior to work)
    - Risk: Low — proven pattern in this codebase.

25. **FastingContextProvider** (File: `Cadence/Features + UI/Stress/Services/FastingContextProvider.swift` — NEW)
    - Action: `@MainActor final class FastingContextProvider: ObservableObject` with `@Published var todayHRV: Double?`, `@Published var lastNightSleepScore: Int?`, `@Published var sevenDayStressAvg: Double?`. Method `async loadContext()`:
      1. Try `SharedHealthMetrics.loadForToday()` first — if hit, use it.
      2. On miss, call `HealthKitService.fetchHRV(for:)` (line 194) for today + `fetchDailySleepSummaries(for:)` (line 150) for last night.
      3. Write fresh values back to `SharedHealthMetrics`.
      4. Query StressReading via `@Environment(\.modelContext)` for 7-day average (helper on StressAnalyticsHelper).
    - Dependencies: step 24
    - Risk: Low — leverages existing services without duplicating queries.

26. **Insight banner under timer** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: New private view `insightBanner` between `activeTimerCard` and `todayInfoCard`. One of:
      - HRV high (today > baseline + 5ms): *"Your HRV is strong today. A \(scheduleHours)h rest aligns well with your recovery."*
      - HRV low (today < baseline - 5ms): *"Your autonomic nervous system shows elevated stress today. Consider a shorter rest (12h) to support recovery."*
      - Sleep score low (<70): *"Sleep was light last night. Listen to your body — it's okay to end your fast early today."*
      - No data: hide banner entirely.
    - Thresholds as constants at file top for easy tuning.
    - **Accessibility:** Banner uses `.accessibilityLabel` matching visible text + `.accessibilityHint("Personal recommendation based on your recent recovery metrics.")`. <!-- RESOLVED: M2 -->
    - Dependencies: step 25
    - Risk: Medium — thresholds may need medical review; defaults are conservative.

27. **Bind context to FastingSession on end** (Files: `Cadence/Features + UI/Stress/Views/FastingView.swift`, `Cadence/Models/FastingSession.swift`)
    - Action: At fast-end (both explicit "End Fast" and silent overachieving close), pull from `FastingContextProvider`, write `session.contextualHRV = ...`, `session.contextualSleepScore = ...` before save.
    - Dependencies: steps 2, 25
    - Risk: Low

**Phase 5 verification:** Mock HRV/sleep values via debug controls; confirm banner copy matches data state. Ended sessions persist context fields.

---

### Phase 6 — LiveActivityIntent "End Fast"

**Goal:** Lock Screen / Dynamic Island interactive End button. **Requires Phase −1 (App Group fix) to work in Release builds.**

28. **BreakFastIntent — explicit cross-process pattern** (File: `Cadence/Widgets/BreakFastIntent.swift` — NEW) <!-- RESOLVED: H3 -->
    - Action: 
      ```swift
      struct BreakFastIntent: LiveActivityIntent {
          static let title: LocalizedStringResource = "End Fast"
          func perform() async throws -> some IntentResult {
              // 1. Persist pending-break payload to App Group UserDefaults.
              //    This is the SwiftData mutation handoff — the widget process
              //    cannot mutate SwiftData reliably.
              let payload = PendingBreakPayload(timestamp: .now, reason: .userExplicit)
              if let d = UserDefaults(suiteName: "group.com.hariom.cadence"),
                 let data = try? JSONEncoder().encode(payload) {
                  d.set(data, forKey: "pendingBreakFast")
              }
              // 2. End the Live Activity directly. This IS safe cross-process —
              //    ActivityKit owns shared state. Do NOT call ActivityManager.shared.
              if let activity = Activity<FastingActivityAttributes>.activities.first {
                  var finalState = activity.content.state
                  finalState.acceptsEndIntent = false
                  await activity.end(ActivityContent(state: finalState, staleDate: .now),
                                     dismissalPolicy: .default)
              }
              return .result()
          }
      }
      ```
    - Place at `Cadence/Widgets/BreakFastIntent.swift` to inherit `FastingActivityAttributes`'s target-membership pattern.
    - Verify build-clean on both `Cadence` and `CadenceWidget` schemes after adding. <!-- RESOLVED: L3 -->
    - Dependencies: Phase −1, step 11
    - Risk: Medium — cross-process state needs care; the explicit `ActivityKit-direct vs SwiftData-via-app` split is the safe pattern.

29. **Wire intent button into Live Activity** (File: `CadenceWidget/LiveActivities/FastingLiveActivityView.swift`)
    - Action: Add `Button(intent: BreakFastIntent()) { Text("End") ... }` to:
      - Lock Screen phone view (lines 109-146): inline bottom-right when `acceptsEndIntent && (!isCompleted && !isBroken)`.
      - Dynamic Island expanded `.bottom` region (lines 60-71): right-side End button alongside the "Eat window opens" caption.
      - Skip compact/minimal (no space) and Watch (`.small` family) for v1 — defer Watch interactive button to a separate ticket.
    - Button visibility gated by `context.state.acceptsEndIntent` (defaults true while fasting, false on completion).
    - **Accessibility:** Button has `.accessibilityLabel("End Fast")` + `.accessibilityHint("Ends your current fast and opens the eating window.")`. <!-- RESOLVED: M2 -->
    - Dependencies: step 28
    - Risk: Medium — test foreground, background, and locked invocation paths.

30. **App reconciles pending-break on foreground** (Files: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: In `configureService()` (lines 591-609), read `UserDefaults(suiteName: "group.com.hariom.cadence").data(forKey: "pendingBreakFast")`. If decoded payload exists:
      1. Find active session; if found, set `actualEndAt = payload.timestamp`, `completionStatus` per same rules as step 23 (during bonus → `.completed`; before target → `.endedEarly`).
      2. Bind context (HRV/sleep) per step 27.
      3. Cancel cap24h notification.
      4. Clear the UserDefaults key.
      5. End Live Activity if still running (idempotent — intent may have already done it).
    - Idempotency: if no active session is found (intent already processed by a previous foreground), silently clear the key.
    - Dependencies: step 28, step 27
    - Risk: Medium — race conditions when intent + foreground happen simultaneously; idempotency guard above handles it.

**Phase 6 verification:** Lock device, tap End on Live Activity, unlock, confirm fast is closed and history shows correctly. Repeat with Dynamic Island. Repeat with app foregrounded. **Must verify in TestFlight/Release build** (Phase −1 dependency).

---

### Phase 7 — Weekly grid + Home Digestive State card

31. **Weekly grid component** (File: `Cadence/Features + UI/Stress/Views/FastingWeeklyGridView.swift` — NEW)
    - Action: View taking `sessions: [FastingSession]`. Horizontal 7-column grid using `Calendar.current.firstWeekday`. Each cell: day-of-week abbreviation, colored square (filled `heroAccent` if `.completed`/`.overachieved` that day, hatched if `.endedEarly`, empty if no fast), small duration label. Highlight today with ring.
    - **Accessibility:** Each cell `.accessibilityElement(children: .combine)` with label like "Tuesday, 14h fast, completed". <!-- RESOLVED: M2 -->
    - Dependencies: step 1
    - Risk: Low

32. **Integrate grid into FastingView** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: Replace `historySection`'s `ForEach(completedSessions)` (lines 538-542) with `FastingWeeklyGridView(sessions: sessions)`. Keep the recent-row list below as a secondary "Recent" tappable section (step 16).
    - Dependencies: step 31, step 16
    - Risk: Low

33. **Home DigestiveStateCard + HomeCardID integration** (Files: `Cadence/Models/HomeLayoutConfig.swift`, `Cadence/Features + UI/Home/Components/DigestiveStateCard.swift` — NEW, `Cadence/Features + UI/Home/Views/HomeView.swift`) <!-- RESOLVED: H4 -->
    - Action — `HomeLayoutConfig.swift`:
      ```swift
      // Add to HomeCardID enum:
      case fasting           // Position 2c — after wellnessRings
      
      // displayName:
      case .fasting: return "Fasting"
      
      // iconName:
      case .fasting: return "fork.knife.circle"
      
      // hasSubElements: false (default)
      // subElements: [] (default)
      ```
      **Existing users:** `HomeLayoutConfig.reconcileWithCurrentCards()` (line 187-195) automatically appends new `HomeCardID` cases on next decode. No migration code needed — existing users see the card appear in their layout at the end of `cardOrder` (they can reorder via `HomeLayoutEditor`). <!-- RESOLVED: H4 — verified via reconcile helper -->
    - Action — `DigestiveStateCard.swift`: Compact card showing current `FastingState`, mini circular progress, most recent fast result, one-line readiness summary (sleep + stress). Tap routes via `FastingEligibility.accessState(from:)` from step 4.
    - Action — `HomeView.swift`: New branch in `cardView(for:)` (line 130): `case .fasting: DigestiveStateCard()`. Remove the old `headerAssetIcon("fasting_icon")` launcher button (lines 593-601) — the card replaces it.
    - Dependencies: steps 4, 9, 21
    - Risk: Low → reduced (HomeLayoutConfig auto-migration is clean).

**Phase 7 verification:** Build all 4 targets. Seed varied history. Grid renders. Open Home → DigestiveStateCard renders in correct state, routes correctly per access state. Existing users see card auto-added to layout.

---

### Phase 8 — Bedtime-derived start reminder

34. **Bedtime heuristic** (File: `Cadence/Features + UI/Stress/Services/FastingBedtimeHeuristic.swift` — NEW)
    - Action: `func computeAverageBedtime(over days: Int = 14) async -> DateComponents?`. Queries `HealthKitService.fetchDailySleepSummaries(for:)` (line 150) for past 14 days, extracts sleep-onset times, returns median time-of-day. If <3 nights, return nil.
    - Dependencies: none
    - Risk: Low — sleep authorization already requested (HealthKitService line 47-48, verified in audit).

35. **Schedule start-reminder** (File: `Cadence/Core/Services/FastingService.swift`)
    - Action: In `scheduleNotifications(for:)`, call bedtime heuristic; if non-nil, schedule daily `UNCalendarNotificationTrigger` for `bedtime - 3h`. Identifier: `wp.fasting.startReminder`. Body: *"Your usual bedtime is around \(formattedTime). A great time to start your rest is now."* If nil bedtime, silent fallback (no notification). Add to `clearNotifications` removal list.
    - Dependencies: step 34, step 19
    - Risk: Low

**Phase 8 verification:** With ≥3 nights HealthKit sleep data, force re-scheduling, confirm reminder fires at bedtime-3h. With insufficient data, no notification scheduled.

---

## Testing Strategy

Per CLAUDE.md: testing = build-only verification (4 targets via xcodebuild). No automated test suite is wired into shared schemes.

**After each phase:**
```bash
xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build
```

**Manual verification per phase** (unchanged from original) + accessibility verification per phase (new): VoiceOver pass on SCOFF flow, soft pulse with reduceMotion on, weekly grid cell labels, Live Activity End button label. <!-- RESOLVED: M2 -->

**Phase −1 special verification:** TestFlight build (Release signing) → install on device → confirm Stress widget shows live data (proves App Group works in Release end-to-end, both pre-existing and new shared-data paths). <!-- RESOLVED: C1 -->

---

## Risks & Mitigations

(Original risks preserved + new entries for audit findings.)

| Risk | Mitigation |
|---|---|
| **App Group entitlement edit may break Release signing if provisioning profile lacks `group.com.hariom.cadence` capability** <!-- RESOLVED: C1 --> | Before merging Phase −1: verify in Apple Developer console that the Release distribution certificate's provisioning profile includes the App Group. If not, add it before merging entitlement change. Requires user with developer-account access. |
| **SwiftData additive migration silently corrupts existing rows** | Phase 0 step 2 verification: launch app with existing data, confirm no crash. |
| **`ratio20_4` removal breaks existing user schedules** | Audit verified: fallback to `.custom` works, no corruption. |
| **`LiveActivityIntent` can't write SwiftData from widget process** <!-- RESOLVED: H3 --> | Phase 6 step 28 uses explicit cross-process pattern: intent writes UserDefaults payload + ends `Activity` directly (ActivityKit-safe), app reconciles SwiftData on foreground. Never calls `ActivityManager.shared` cross-process. |
| **Soft block has too much surface area; one missed entry point lets a SCOFF-positive user start a fast** <!-- RESOLVED: C3 --> | Step 9 centralizes via `FastingEligibility.accessState(from:)`. All 3 initiation surfaces route through it. Adding a 4th surface in future requires reusing the same helper. |
| **Cap-24h notification not scheduled for new sessions** <!-- RESOLVED: C2 --> | Phase 2 step 12 adds explicit `schedule24hCapNotification(for:)` calls at both session-creation paths (`handleStateTransition`, `startFastNow`) + cancellation paths. |
| **`scoffAnswers: [Bool]?` not natively storable in SwiftData** <!-- RESOLVED: H1 --> | Phase 0 step 3 uses 5 separate Bool fields. Native, queryable, no encoding overhead. |
| **Phase 5 HRV/sleep fetch duplication with StressViewModel** <!-- RESOLVED: H2 --> | Phase 5 step 24 introduces `SharedHealthMetrics` App-Group cache (per-day-keyed). Both StressViewModel and FastingContextProvider read from cache; first-fetcher writes. Cold-start cache miss falls back to direct fetch. |
| **Phase 7 DigestiveStateCard breaks existing Home layout** <!-- RESOLVED: H4 --> | `HomeLayoutConfig.reconcileWithCurrentCards()` auto-appends new HomeCardID cases on decode — existing users see the card at end of order, can reorder via editor. No migration code needed. |
| **Phase 4 ↔ Phase 6 Live Activity state mismatch** <!-- RESOLVED: H5 --> | Phase 2 step 11 consolidates all 3 ContentState additions (`isCapped24h`, `isOverachieving`, `acceptsEndIntent`) into one schema update. Subsequent phases just set the bools — no schema churn. |
| **Onboarding flow miss-tap disqualifies user** <!-- RESOLVED: M5 --> | Step 7 specifies: Toggles freely editable before Submit. After Care, re-take screening starts fresh (no pre-fill) — protects against gaming, allows correction. |
| **iOS 64-notification limit** <!-- RESOLVED: L1 --> | Post-plan: ~6 daily + 1 per-session = well within limit. |
| **Care resources are US-only** <!-- RESOLVED: M1 --> | Phase 1 step 6 adds explicit footer caveat. Locale-aware resource map deferred to v1.1. |
| **Bedtime heuristic wrong for shift workers** | Graceful fallback: no data → no notification. v1.1 can add shift-worker mode. |
| **Live Activity color/copy changes affect Watch family** <!-- RESOLVED: M4 --> | Phase 3 step 18 explicit Watch verification after change. |

---

## Success Criteria

- [ ] All 4 targets build clean.
- [ ] Phase −1 verified in TestFlight: Stress widget displays live data in Release build (proves App Group fix). <!-- RESOLVED: C1 -->
- [ ] First-time user routed to `FastingOnboardingFlow` (NOT Care view) on first Get Started tap. <!-- RESOLVED: C3 -->
- [ ] Three access-state branches verified: not-onboarded → onboarding, blocked → care, granted → fasting view.
- [ ] SCOFF ≥2 positives routes to Care; individual answers persisted to 5 Bool fields. <!-- RESOLVED: H1 -->
- [ ] Underage / pregnant / lactating users routed to Care.
- [ ] No fasting session displays >24h elapsed; cap notification fires for session created at noon when device reaches noon+24h. <!-- RESOLVED: C2 -->
- [ ] Live Activity displays paused-at-24h state and offers interactive End button (tested in Release build). <!-- RESOLVED: C1, H5 -->
- [ ] No instance of "FASTING", "BROKEN", "Break Fast", neon red, or warning orange in any fasting surface.
- [ ] Live Activity color/copy changes render correctly on Apple Watch. <!-- RESOLVED: M4 -->
- [ ] Schedule presets: 12:12 (default), 14:10, 16:8, 18:6, Custom. No 20:4.
- [ ] Target hit triggers soft pulse + bonus-time counter; celebration only on explicit End. Four scenarios verified.
- [ ] HRV/sleep insight banner shows contextually-relevant copy when data exists.
- [ ] Ended sessions persist `contextualHRV` and `contextualSleepScore`.
- [ ] HRV/sleep data shared via `SharedHealthMetrics` cache; no duplicate HealthKit queries when both Stress + Fasting views opened consecutively. <!-- RESOLVED: H2 -->
- [ ] Weekly grid replaces flat list as primary history visualization.
- [ ] Home `DigestiveStateCard` auto-appears in existing users' layouts via `reconcileWithCurrentCards`. <!-- RESOLVED: H4 -->
- [ ] Bedtime-derived start reminder schedules when ≥3 nights HealthKit sleep data; silently no-ops otherwise.
- [ ] No CLLocation permission in Info.plist.
- [ ] No HealthKit `mindfulSession` writes.
- [ ] First-time user with existing data sees no SwiftData crash.
- [ ] **Accessibility:** VoiceOver navigates SCOFF flow, weekly grid cells have combined labels, Live Activity End button has clear label + hint, soft pulse respects `accessibilityReduceMotion`. <!-- RESOLVED: M2 -->
- [ ] Care Intervention view footer notes US-only resources. <!-- RESOLVED: M1 -->

---

## Open Items (Deferred — Not Blocking)

These were surfaced by the audit but explicitly deferred:

- **Telemetry / SCOFF Intervention Rate KPI** (M3): No Cadence analytics surface exists today (verified). Phase 0 step 3 persists individual SCOFF answers + `scoffPositiveCount` to `FastingEligibility` so the data exists for future surfacing. When an analytics surface is added (separate initiative), aggregate from this model.
- **Localization (i18n) for new copy** (L2): All new copy is raw English, consistent with existing un-localized code. Deferred to a future i18n initiative.
- **Locale-aware Care resources** (M1 alternative): US-only with caveat for v1. v1.1 can add resource map keyed by `Locale.current.region`.
- **Shift-worker bedtime heuristic** (audit §7 Q1): Bedtime heuristic returns nil for irregular sleepers; v1.1 can add shift-worker mode.
- **CLLocation-based sunset reminders** (audit §9.4 → §9.4): Bedtime heuristic is v1; CLLocation/sunset deferred to v1.1.
- **Apple Watch interactive End button** (audit §6 step 29): Skipped for v1; Watch Live Activity rendering is read-only.

---

## Suggested implementation sequencing

(Updated from original plan — Phase −1 prepended.)

1. **Phase −1** as a discrete entitlements-only PR. User approval gate. Verify Release behavior in TestFlight.
2. **Phases 0 + 1 + 2 + 3** as v1.0.0 — safety floor + copy compliance + Phase −1 dependency. Minimum-viable-blueprint-compliant release.
3. **Phase 4** as v1.0.1 — completion UX rework.
4. **Phase 5** as v1.1.0 — contextual intelligence (the differentiator).
5. **Phase 6** as v1.2.0 — Lock Screen interactivity (depends on Phase −1 having shipped).
6. **Phases 7 + 8** as v1.3.0 — weekly grid + Home card + bedtime reminder.
