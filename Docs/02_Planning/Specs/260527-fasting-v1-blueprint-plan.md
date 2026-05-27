# Implementation Plan: Fasting v1 Blueprint

**Date:** 2026-05-27
**Slug:** `fasting-v1-blueprint`
**Source audit:** `Docs/03_Audits/260527-fasting-blueprint-gap-audit.md` (read §3 violations, §9 resolutions for binding decisions)
**Constraint:** Blueprint v1 boundary is **binding** — features that violate the v1 exclusion list must be removed/hidden even if currently implemented.

---

## Overview

Bring the existing fasting feature into compliance with the v1 blueprint. The v0 feature has solid bones (SwiftData models, three-state machine, working Live Activity, schedule editor, insight chart, celebration overlay). v1 adds the regulatory/safety floor (SCOFF screening, 24h cap, demographic gate, wellness disclaimer), the contextual intelligence layer (HRV/sleep-aware insights and recommendations), the calm-tone copy/color rework, the Lock Screen interactive `LiveActivityIntent`, and the missing 12:12 beginner preset.

---

## Requirements

Sourced from blueprint + audit §9 resolutions. Each requirement is binding for v1.

### Safety / Regulatory (non-negotiable)
- R1. **SCOFF screening** with ≥2 positives soft-blocking initiation (audit §2.1)
- R2. **Age (≥18) + pregnancy/lactation gate** as a one-time fasting-specific flow (audit §9.3)
- R3. **24h hard cap** with auto-pause + "did you forget?" push, no auto-end (audit §9.7)
- R4. **Wellness disclaimer** un-skippable in onboarding (audit §2.3)
- R5. **Soft block** when ineligible: hide initiation surfaces (Home launcher, Get Started, Stress factor → fast), keep retrospective surfaces (insight chart, reports) (audit §9.6)
- R6. **Care Intervention view** routing for SCOFF/eligibility failures, including National Alliance for Eating Disorders resource link (audit §9.6)

### v1 boundary compliance
- R7. **Remove `ratio20_4`** preset entirely (audit §3.1)
- R8. **Add `ratio12_12`** preset; make it the default for new schedules (audit §9.1, §5)
- R9. **Keep `ratio18_6`** but reorder it last among presets (audit §9.1)
- R10. **No red colors** in active timer ring or Live Activity (audit §3.3, §3.4)
- R11. **Replace punitive copy** ("BROKEN" → "Ended early"; "won't count as a completed fast" → forgiving phrasing; "FASTING"/"EATING" pill → "RESTING"/"EATING WINDOW") (audit §3.3, §3.5)

### Contextual intelligence (differentiator)
- R12. **Contextual HRV/sleep insight** under timer ("Your HRV is optimal today...") (audit §2.4)
- R13. **Stress-responsive recommendation banner** when recent stress is high ("consider a shorter window today") (audit §2.5)
- R14. **Bedtime-derived start reminder** using HealthKit sleep history (no CLLocation in v1) (audit §9.4)
- R15. **Home "Digestive State" card** showing current state + readiness context (audit §6.1)

### Schema (additive only — no VersionedSchema)
- R16. **Add optional fields** to `FastingSession`: `completionStatus: String?`, `contextualHRV: Double?`, `contextualSleepScore: Int?` (audit §9.2, §4)
- R17. **New `FastingEligibility` @Model** with SCOFF + demographic flags (audit §9.3)
- R18. **No replacement of existing `completed: Bool`** — keep both, derive resolvedStatus (audit §9.2)

### UX deltas
- R19. **Soft pulse + bonus-time count** at target hit; celebration overlay only on explicit "End Fast" (audit §9.5)
- R20. **`LiveActivityIntent` "End Fast"** button on Lock Screen / Dynamic Island (audit §2.6)
- R21. **Retroactive edit previous fast** UI (tap a history row → edit sheet) (audit §2.7)
- R22. **Weekly 7-day calendar grid** replacing/augmenting the current flat history list (audit §5)

### Out of scope for v1 (do not implement)
- ❌ Biological-phase tracking (autophagy, ketosis)
- ❌ Weight-loss projections
- ❌ Community / leaderboards
- ❌ AI food scanning
- ❌ Fasts longer than 24h
- ❌ CLLocation / sunset reminders (defer to v1.1)
- ❌ HealthKit writes (no `mindfulSession` abuse — current code is clean, keep it that way)

---

## Architecture Changes

### New files
| Path | Purpose |
|---|---|
| `Cadence/Models/FastingEligibility.swift` | @Model storing SCOFF + demographic results |
| `Cadence/Models/FastingCompletionStatus.swift` | Enum `completed \| endedEarly \| overachieved` + extension on FastingSession to derive `resolvedStatus` |
| `Cadence/Features + UI/Stress/Views/FastingOnboardingFlow.swift` | Multi-step flow: disclaimer → demographics → SCOFF → schedule selection |
| `Cadence/Features + UI/Stress/Views/FastingCareInterventionView.swift` | Soft-block landing view with NAED link + "Re-take screening" CTA |
| `Cadence/Features + UI/Stress/Views/FastingEditSessionSheet.swift` | Edit-previous-fast sheet (retroactive start/end correction) |
| `Cadence/Features + UI/Stress/Views/FastingWeeklyGridView.swift` | 7-day consistency grid |
| `Cadence/Features + UI/Stress/Services/FastingContextProvider.swift` | Loads HRV + sleep score per day; binds to active session at end-of-fast |
| `Cadence/Features + UI/Stress/Services/FastingBedtimeHeuristic.swift` | Computes user's avg bedtime from HealthKit sleep over past 14 days |
| `Cadence/Features + UI/Home/Components/DigestiveStateCard.swift` | Home dashboard card showing current fasting state |
| `Cadence/Widgets/BreakFastIntent.swift` | `LiveActivityIntent` for Lock Screen end-fast button |

### Modified files
| Path | Change summary |
|---|---|
| `Cadence/App/CadenceApp.swift` | Register `FastingEligibility.self` in modelContainer list (line 43) |
| `Cadence/Models/FastingSession.swift` | Add 3 optional fields; add `resolvedStatus` computed property |
| `Cadence/Models/FastingSchedule.swift` | Drop `ratio20_4`; add `ratio12_12`; reorder presets; change default to `ratio12_12` |
| `Cadence/Core/Services/FastingService.swift` | Add 24h-cap notification (`wp.fasting.cap24h`); add bedtime-heuristic start reminder; cap progress display at 24h; new `isOverachieving` flag in state |
| `Cadence/Core/Services/ActivityManager.swift` | Clamp Live Activity progress at 24h; integrate end-fast intent state path |
| `Cadence/Widgets/FastingActivityAttributes.swift` | Add `isOverachieving: Bool` to ContentState; verify target-membership covers app + widget |
| `CadenceWidget/LiveActivities/FastingLiveActivityView.swift` | Drop red colors; add interactive Button(intent:) bound to BreakFastIntent; render overachieving state |
| `Cadence/Features + UI/Stress/Views/FastingView.swift` | Route Get Started via FastingOnboardingFlow; eligibility-gated initiation; new copy/colors; soft pulse + bonus time + explicit End Fast; HRV/sleep insight banner; stress-responsive recommendation; weekly grid integration; tappable history rows |
| `Cadence/Features + UI/Stress/Views/FastingScheduleEditor.swift` | Default to `ratio12_12`; reordered preset list; updated subtitle copy |
| `Cadence/Features + UI/Stress/Components/FastingCelebrationOverlay.swift` | (Minimal change) trigger only via explicit user action; no copy churn |
| `Cadence/Features + UI/Home/Views/HomeView.swift` | Replace launcher button with `DigestiveStateCard`; eligibility-gated tap handler |
| `Cadence/Features + UI/Stress/Views/StressView.swift` | Eligibility-gated routing on `.fasting` factor card |
| `Cadence/Features + UI/Home/Views/ReportSections/FastingSection.swift` | Copy review only; verify no punitive language |

### Inter-target wiring
- `BreakFastIntent` must be in a target both app and widget can compile against. `FastingActivityAttributes.swift` lives at `Cadence/Widgets/` and is already shared — place `BreakFastIntent.swift` alongside it and verify target membership at implementation time.
- App Group already provisioned (per memory: bundle IDs + App Group renamed). Intent writes a "pending break" flag to UserDefaults(suiteName:); app reads on next foreground and closes the active session.

---

## Implementation Steps

Sequenced for **independent shippability** — each phase is testable in isolation. Phases 0–2 form the v1 safety floor and must ship together. Phases 3–8 can ship as separate releases.

### Phase 0 — Schema & preset foundation (no user-visible UI change)

**Goal:** Lay the data foundation. Independent of all UI work. Ships first because everything else builds on it.

1. **Add CompletionStatus enum** (File: `Cadence/Models/FastingCompletionStatus.swift` — NEW)
   - Action: `enum FastingCompletionStatus: String, Codable { case completed, endedEarly, overachieved, autoCappedAt24h }`. Add an extension on `FastingSession` exposing `var resolvedStatus: FastingCompletionStatus` that derives from `(completionStatus, completed)` with legacy fallback.
   - Why: New status taxonomy without breaking the legacy `completed: Bool`. The `autoCappedAt24h` case is added now so it's available for Phase 2 work.
   - Dependencies: none
   - Risk: Low

2. **Add optional fields to FastingSession** (File: `Cadence/Models/FastingSession.swift`)
   - Action: Add three stored properties — `var completionStatus: String?`, `var contextualHRV: Double?`, `var contextualSleepScore: Int?`. All optional, default `nil`. Do **not** remove `completed: Bool`. Add to `init` parameters with defaults so existing call sites compile unchanged.
   - Why: Additive optional fields auto-migrate in SwiftData without VersionedSchema overhead.
   - Dependencies: none
   - Risk: Low — but verify on app launch with existing data that no crash occurs. Build + run once.

3. **Register FastingEligibility model** (File: `Cadence/Models/FastingEligibility.swift` — NEW; `Cadence/App/CadenceApp.swift`)
   - Action: New `@Model final class FastingEligibility` with: `cleared: Bool`, `clearedAt: Date?`, `age18Plus: Bool`, `notPregnant: Bool`, `notLactating: Bool`, `scoffCleared: Bool`, `scoffAnswers: [Bool]?`, `lastScreenedAt: Date?`, plus computed `var canInitiate: Bool { cleared && age18Plus && notPregnant && notLactating && scoffCleared }`. Register in `CadenceApp.swift:43` modelContainer list.
   - Why: Single source of truth for "can the user start a fast." All initiation surfaces query this.
   - Dependencies: none
   - Risk: Low — adding a model to `modelContainer(for:)` should be safe (it just provisions storage). Verify launch.

4. **Preset reshuffle** (File: `Cadence/Models/FastingSchedule.swift`)
   - Action: Remove `case ratio20_4` from `FastingScheduleType` enum entirely. Add `case ratio12_12 = "12:12"` at the top of the enum with `defaultEatHours = 12`, `defaultEatStartHour = 8` (eat 8am–8pm), icon `"sunrise"`, setupSubtitle `"Beginner-friendly 12h eating window"`. Reorder enum cases to: `ratio12_12, ratio14_10, ratio16_8, ratio18_6, custom`. Change `FastingSchedule` init default from `.ratio16_8` to `.ratio12_12`.
   - Why: Blueprint requires 12:12 as beginner default; 20:4 nudges Anxious Beginners into Endurance territory which v1 explicitly de-prioritizes.
   - Dependencies: step 1 (status enum is referenced nowhere yet, so order is independent)
   - Risk: Medium — `ratio20_4` raw value `"20:4"` may exist in production `FastingSchedule.scheduleType` strings. Add a migration helper in `FastingScheduleType(rawValue:)` callers: if a row has `"20:4"`, treat as `.custom`. `FastingSession.scheduleType` is just a label string — no breakage there.

**Phase 0 verification:** Build all 4 targets (`Cadence`, `ScreenTimeMonitor`, `ScreenTimeReport`, `CadenceWidget`). Launch app with existing seed data; confirm no SwiftData crashes and existing fasts display.

---

### Phase 1 — Safety core (SCOFF + eligibility + soft block)

**Goal:** Regulatory floor. Block initiation for at-risk users.

5. **Care Intervention view** (File: `Cadence/Features + UI/Stress/Views/FastingCareInterventionView.swift` — NEW)
   - Action: SwiftUI view that displays a non-clinical care message ("Fasting may not be the best fit for your current wellness journey right now…"), three resource links (National Alliance for Eating Disorders, plus 988 mental health line, plus a "talk to a healthcare provider" reminder), and a "Re-take screening" button. Reuse `AppColors.brand`, `.appShadow`, `.r()` font helpers.
   - Why: Single destination for any failed eligibility check. Reused across SCOFF positive, demographic block, and the Settings re-screening flow.
   - Dependencies: step 3
   - Risk: Low. Editorial note: copy must be reviewed by user before ship (it's the most legally-sensitive surface in v1).

6. **Fasting onboarding flow** (File: `Cadence/Features + UI/Stress/Views/FastingOnboardingFlow.swift` — NEW)
   - Action: 4-step `TabView(selection:)` paged flow:
     - **Step 1 — Disclaimer**: full-screen text "Cadence is for general wellness, not medical advice. Talk to a licensed provider before changing dietary habits." Un-skippable "I understand" button required to advance.
     - **Step 2 — Demographics**: three yes/no toggles + Next button. Questions: "Are you 18 or older?" / "Are you currently pregnant?" / "Are you currently lactating?" Any disqualifying answer → present `FastingCareInterventionView` and abort.
     - **Step 3 — SCOFF**: five yes/no toggles using blueprint's exact phrasing (audit §2.1 lists them). Count "yes" answers. ≥2 → present Care view and abort.
     - **Step 4 — Schedule**: re-uses `FastingScheduleEditor` UI but presented inline (no nav push); save creates both `FastingSchedule` AND a `FastingEligibility` row with `cleared = true`.
   - Why: One flow, one outcome — either user is eligible with a schedule, or routed to Care.
   - Dependencies: steps 3, 5
   - Risk: Medium — multi-step navigation has many edge cases (back button mid-flow, app backgrounding mid-SCOFF, accidental disqualification). Add `@Environment(\.dismiss)` handling and persist scratch state across backgrounds.

7. **Replace FastingView Get Started CTA** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
   - Action: Change the "Get Started" button (currently at lines 203-228) to present `FastingOnboardingFlow` as a sheet instead of jumping straight to `FastingScheduleEditor`. The schedule editor still works as the post-onboarding "Edit Fast" entry point (gear icon in toolbar, line 78-87) — but for first-time users, the gate is the onboarding flow.
   - Why: Funnels every new user through disclaimer + demographic + SCOFF.
   - Dependencies: step 6
   - Risk: Low

8. **Eligibility-gated routing across surfaces** (Files: `Cadence/Features + UI/Home/Views/HomeView.swift`, `Cadence/Features + UI/Stress/Views/StressView.swift`)
   - Action: In HomeView (around the fasting launcher at line 593-601), query `FastingEligibility` via `@Query` and conditionally route: if no row exists → onboarding flow; if `canInitiate == true` → FastingView; if `canInitiate == false` (i.e. row exists but blocked) → `FastingCareInterventionView`. Same conditional in StressView at line 198 for the `.fasting` factor case.
   - Why: A single user-action surface must never bypass the eligibility check.
   - Dependencies: steps 3, 5, 6, 7
   - Risk: Low

9. **Settings entry point for re-screening** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
   - Action: In the toolbar (next to the existing gear icon), add a secondary menu option "Re-take wellness screening" that re-presents `FastingOnboardingFlow` starting at step 3 (SCOFF). Persists results to the existing `FastingEligibility` row (no new row created).
   - Why: Users' situations change. Blueprint doesn't mandate this but it's the obvious UX fix to make the soft block dignified.
   - Dependencies: step 6
   - Risk: Low

**Phase 1 verification:** Manual test the three branches — pass-through (eligible), SCOFF fail (≥2 yes), demographic fail (age <18). Confirm soft block hides initiation but keeps insight chart visible. Build all 4 targets.

---

### Phase 2 — 24h cap + forgotten-stop guard

**Goal:** Prevent runaway fasts; recover gracefully when a user forgets to end one.

10. **24h cap notification + state clamp** (File: `Cadence/Core/Services/FastingService.swift`)
    - Action: In `scheduleNotifications(for:)`, when an `activeSession` is provided, additionally schedule a one-shot `UNTimeIntervalNotificationTrigger` firing at `(activeSession.startedAt + 24*3600 - now)` seconds. Identifier: `wp.fasting.cap24h`. Add to the `clearNotifications` removal list. Body copy per blueprint: *"You've been fasting for 24h. Did you forget to end your fast? Tap to adjust the end time."*
    - In `updateState(...)`, after computing elapsed time, if `activeSession != nil && session.actualDurationSeconds > 24*3600`, clamp the displayed `progress` at 1.0 and `timeRemaining` at 0. Add a new `@Published var isCapped24h: Bool` to surface this in UI.
    - Why: Auto-pause per audit §9.7 — preserves user agency, doesn't auto-end.
    - Dependencies: step 2 (uses new `completionStatus` field) — only if we choose to write `.autoCappedAt24h` status on detection. Acceptable to defer status write to the edit sheet (step 13).
    - Risk: Medium — `scheduleNotifications` currently re-runs on schedule changes; the cap notification has a per-session unique fire time, not a daily one. Must NOT re-fire on subsequent days. One-shot `UNTimeIntervalNotificationTrigger(timeInterval:repeats: false)` solves this.

11. **Live Activity progress clamp** (Files: `Cadence/Widgets/FastingActivityAttributes.swift`, `Cadence/Core/Services/ActivityManager.swift`)
    - Action: In `ContentState`, add `var isCapped24h: Bool = false`. In `ActivityManager.updateFastingActivity(progress:)`, if elapsed > 24h, clamp `progress` to 1.0 and set `isCapped24h = true`. Update `FastingLiveActivityView.swift` to render a "Paused at 24h" subtitle when `isCapped24h`.
    - Why: Lock Screen must reflect the same paused state.
    - Dependencies: step 10
    - Risk: Low

12. **FastingView shows capped banner** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: When `fastingService.isCapped24h == true`, show a banner above `todayInfoCard` with: "Fast paused at 24h. End it now or edit the end time." with two buttons: "End Fast" and "Edit". "Edit" opens the edit-previous-fast sheet from step 13 pre-targeting the active session.
    - Why: User who opens the app to a capped fast needs an obvious next action.
    - Dependencies: steps 10, 13
    - Risk: Low

13. **Edit previous fast sheet** (File: `Cadence/Features + UI/Stress/Views/FastingEditSessionSheet.swift` — NEW)
    - Action: Sheet with two `DatePicker`s for `startedAt` and `actualEndAt`, validates `end > start`, validates `end <= now`, validates `(end - start) <= 24h` (consistent with the cap). On save: persist to the bound `FastingSession`, write `completionStatus` per the new derived rule (if `actualEndAt < targetEndAt` → `.endedEarly`; if `actualEndAt >= targetEndAt` → `.completed`; if originally capped → `.autoCappedAt24h`).
    - Why: Audit §2.7 — users forget; correction must be one-tap accessible.
    - Dependencies: step 1, step 2
    - Risk: Medium — validation rules must be tight; allowing inverted dates corrupts the insight chart math (`FastingInsightChart` reads `actualDurationSeconds`).

14. **Wire history rows to edit sheet** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: Wrap each `fastHistoryRow` (line 553-587) in a `Button { editingSession = session }`. Add `@State private var editingSession: FastingSession?` and a corresponding `.sheet(item: $editingSession) { session in FastingEditSessionSheet(session: session) }`.
    - Why: Tap-to-edit pattern is what blueprint specifies.
    - Dependencies: step 13
    - Risk: Low

**Phase 2 verification:** Set device clock forward to simulate a 24h+ fast (or seed a session with `startedAt = now - 25h`). Confirm: notification fires, FastingView shows capped banner, Live Activity shows paused state, edit sheet correctly updates the session.

---

### Phase 3 — Copy / color / lexicon pass (pure UI)

**Goal:** Strip punitive language and urgent colors across all fasting surfaces. Zero engineering risk.

15. **FastingView copy + colors** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action:
      - `stateLabel` (line 692-698): `"FASTING"` → `"RESTING"`, `"EATING"` → `"EATING WINDOW"`.
      - `idleHeaderLabel` (line 702-704): `"READY TO FAST"` → `"READY WHEN YOU ARE"`.
      - `ringColor` (line 706-712): return `heroAccent` for `.fasting`, `Color(hue: 0.40, saturation: 0.62, brightness: 0.72)` (existing green) for `.eating`. **Drop `.orange` entirely.**
      - `breakFastAlertMessage` (line 131-137): rephrase to *"Listening to your body is always the right choice. You've fasted for [duration] so far."*
      - Alert title (line 99): `"Break Fast Early?"` → `"End your fast?"`
      - "Break Fast" button (line 423): label `"Break Fast"` → `"End Fast"`. Keep the muted-red style (it's a destructive action), but the *copy* shifts.
      - History row label (line 574): `"Broken"` → `"Ended early"`. Color stays muted red for visual distinction.
      - Empty state subtitle (line 196-200): rewrite to circadian framing: *"Rest your digestive system and align eating with your body clock."*
    - Why: Audit §3.3, §3.5. Calm/forgiving lexicon is the v1 positioning.
    - Dependencies: none (cosmetic)
    - Risk: Low

16. **Live Activity color + copy** (File: `CadenceWidget/LiveActivities/FastingLiveActivityView.swift`)
    - Action:
      - `ringColor(for:)` (line 277-281): broken state → `.white.opacity(0.55)` instead of `.red`. Active state → `.orange` is acceptable per Apple HIG for time-elapsed UI, but blueprint says no warning-orange — switch to a calmer accent matching the app (`Color(hue: 0.07, saturation: 0.78, brightness: 0.95)` — the `heroAccent` orange-amber, already used in `FastingView`).
      - Lock Screen broken-state copy (line 128): `"Fast ended early"` keep, change color from `.red` to `.white.opacity(0.7)`.
      - Watch view (line 167): same color swap.
      - Dynamic Island expanded center (line 46): same color swap.
      - Title copy in expanded center (line 42): `"Fast complete"` → `"Rest complete"`.
    - Why: Audit §3.4. Live Activity must not display alarm colors per blueprint.
    - Dependencies: none
    - Risk: Low

17. **Notification copy review** (File: `Cadence/Core/Services/FastingService.swift`)
    - Action: Update notification bodies (lines 222-263):
      - `"Eating Window Closed"` / `"Your 16:8 fast has begun"` → keep title, body: *"Your \(scheduleLabel) rest has begun. Hydrate well."*
      - `"1 Hour Left"` / `"Your fast ends in 1 hour"` → `"Eating window opens in 1 hour. Plan something nourishing."*
      - `"Fast Complete"` / `"Your eating window is open"` → `"Rest complete. Break your fast whenever you feel ready."* (matches blueprint Table 7)
      - `"Caffeine Cutoff"` / `"Last call for caffeine — cutoff is now."` → keep as-is, it's already neutral.
    - Why: Audit §3.6. Blueprint notification table.
    - Dependencies: none
    - Risk: Low

18. **Onboarding + schedule editor copy** (File: `Cadence/Features + UI/Stress/Views/FastingScheduleEditor.swift`)
    - Action: Update preset subtitles in `FastingScheduleType.setupSubtitle` (`Models/FastingSchedule.swift:25-38`):
      - `.ratio12_12`: "Beginner-friendly 12h eating window"
      - `.ratio14_10`: "Gentle plan with a 10h eating window" (already close; keep)
      - `.ratio16_8`: "Common plan with an 8h eating window" (drop "most" superlative)
      - `.ratio18_6`: "Focused plan with a 6h eating window" (keep — neutral)
      - `.custom`: "Choose your own eating window" (drop "fine tune" jargon)
    - Why: Audit §3 alignment — no superlatives, no "advanced," beginner-first language.
    - Dependencies: step 4
    - Risk: Low

**Phase 3 verification:** Manual UI walkthrough of FastingView all states, Live Activity all states, notifications fired in simulator, schedule editor. Confirm no instance of "FASTING", "BROKEN", "Break Fast", neon red, or warning orange.

---

### Phase 4 — Soft completion + bonus time

**Goal:** Remove anxiety-inducing hard cutoff at target time. Celebrate on explicit user action.

19. **isOverachieving state** (Files: `Cadence/Core/Services/FastingService.swift`, `Cadence/Models/FastingSession.swift`)
    - Action: Add `@Published var isOverachieving: Bool = false` to `FastingService`. In `updateState`, if `activeSession != nil` AND elapsed > targetDuration AND elapsed <= 24h (so cap takes precedence), set `isOverachieving = true`. Also set `progress = 1.0` and compute `var bonusElapsed: TimeInterval` (new `@Published`).
    - Why: Drives the soft-pulse UI without changing the underlying state machine.
    - Dependencies: step 2, step 10 (24h cap must take precedence over overachieving)
    - Risk: Low

20. **Timer ring pulse + bonus label** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: In `activeTimerCard` (line 246-353), when `fastingService.isOverachieving == true`:
      - Ring stays at full but pulses with `.repeatForever(autoreverses: true)` opacity animation between 0.85 and 1.0.
      - Time label switches from `formattedTimeRemaining` to `"+\(formattedDuration(bonusElapsed))"`.
      - Subtitle changes from `"REMAINING"` to `"BONUS TIME"`.
      - Percentage line hides.
      - Soft single haptic at first transition (track previous state).
    - Why: Audit §9.5. Calm signal, not alarm.
    - Dependencies: step 19
    - Risk: Low

21. **Decouple celebration from auto-transition** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: In `handleStateTransition` (line 611-644), the `fasting → eating` block currently auto-completes the session AND fires the celebration. Split this:
      - If `activeSession != nil` AND transition is `fasting → eating` AND user has NOT explicitly ended (track via `@State private var didUserExplicitlyEnd: Bool`):
        - Mark `completionStatus = .overachieved`, set `actualEndAt = .now`, mark `completed = true` (legacy field), but do NOT show celebration overlay.
      - Celebration overlay now only fires from `breakCurrentFast()` (line 682-688) when user tapped "End Fast" while overachieving (so `completionStatus = .completed`).
      - Reset `didUserExplicitlyEnd` on new session start.
    - Why: User explicitly chose to complete → reward. User just let the timer roll over → silent close.
    - Dependencies: steps 19, 20
    - Risk: Medium — state interaction is subtle. Walk through the four scenarios on paper before coding: (a) user ends before target = endedEarly + no celebration; (b) user ends after target = completed + celebration; (c) timer rolls into new eat window without user action = overachieved + silent close; (d) 24h cap triggers first = autoCappedAt24h, follow Phase 2 banner flow.

**Phase 4 verification:** Seed a session with `targetEndAt = now - 5min`. Open FastingView, confirm bonus time displays + ring pulses + no celebration. Tap "End Fast" → celebration fires. Restart, let scheduled eat window arrive → silent close in history with `.overachieved` status.

---

### Phase 5 — Contextual intelligence (the differentiator)

**Goal:** Surface HRV + sleep context to make the fasting decision physiologically informed. This is the blueprint's core differentiator vs Zero/Fastic.

22. **FastingContextProvider** (File: `Cadence/Features + UI/Stress/Services/FastingContextProvider.swift` — NEW)
    - Action: `@MainActor final class FastingContextProvider: ObservableObject` with `@Published var todayHRV: Double?`, `@Published var lastNightSleepScore: Int?`, `@Published var sevenDayStressAvg: Double?`. Method `async loadContext()` calls existing `HealthKitService` methods (do not duplicate fetch logic — find the existing daily-avg HRV fetch in `HealthKitService.swift` and reuse). Sleep score: derive from existing sleep data the way `StressViewModel` already does. 7-day stress avg: query `StressReading` directly via `ModelContext` (or expose helper on `StressAnalyticsHelper`).
    - Why: Single point of fasting-relevant context to keep `FastingView` and the insight banner clean.
    - Dependencies: none (uses existing services)
    - Risk: Medium — coordinating with `StressViewModel`'s existing fetch patterns. **Do not parallel-fetch the same data** — if `StressViewModel` is already running, sharing the cached values is preferable. Verify before duplicating.

23. **Insight banner under timer** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: New private view `insightBanner` placed between `activeTimerCard` and `todayInfoCard`. Renders one of:
      - HRV high (today > 30-day baseline + 5ms): *"Your HRV is strong today. A \(scheduleHours)h rest aligns well with your recovery."*
      - HRV low (today < baseline - 5ms): *"Your autonomic nervous system shows elevated stress today. Consider a shorter rest (12h) to support recovery."* (this is also R13)
      - Sleep score low (< 70): *"Sleep was light last night. Listen to your body — it's okay to end your fast early today."*
      - No data: hide banner entirely (no empty-state copy).
    - Why: Audit §2.4 + §2.5. Dynamic, physiologically grounded text — exactly the missing differentiator.
    - Dependencies: step 22
    - Risk: Medium — copy variants depend on data thresholds that need user/medical review. Default to conservative thresholds for v1; expose as constants for easy tweaking.

24. **Bind context to FastingSession on end** (Files: `Cadence/Features + UI/Stress/Views/FastingView.swift`, `Cadence/Models/FastingSession.swift`)
    - Action: At fast-end (both explicit "End Fast" and silent overachieving close from step 21), pull current values from `FastingContextProvider` and write `session.contextualHRV = ...`, `session.contextualSleepScore = ...` before save.
    - Why: Enables future v1.x correlations and reinforces the insight chart's data foundation.
    - Dependencies: steps 2, 22
    - Risk: Low

**Phase 5 verification:** Mock HRV/sleep values via debug controls if available; otherwise test in a real account. Confirm banner copy matches data state. Verify ended sessions have non-nil `contextualHRV`/`contextualSleepScore`.

---

### Phase 6 — LiveActivityIntent "End Fast"

**Goal:** Lock Screen / Dynamic Island interactive button to end a fast without unlocking.

25. **BreakFastIntent** (File: `Cadence/Widgets/BreakFastIntent.swift` — NEW)
    - Action: `struct BreakFastIntent: LiveActivityIntent`. `static let title: LocalizedStringResource = "End Fast"`. In `perform()`: write a "pending break fast" timestamp to `UserDefaults(suiteName: <AppGroupID>)`, then call `ActivityManager.shared.endFastingActivity(completed: ...)` directly if possible from the intent process. Returns `.result()`.
    - **Critical:** must target both the app and widget. Mirror `FastingActivityAttributes.swift` target membership.
    - Why: Audit §2.6. Required for blueprint UX.
    - Dependencies: none (independent feature)
    - Risk: High — `LiveActivityIntent` runs in the widget process. Cross-process state writes via App Group UserDefaults are the safe pattern. The app then reads the pending-break flag on next foreground (`scenePhase == .active`) and closes the SwiftData session. **Do not** assume SwiftData is writable from the widget process.

26. **Wire intent into Live Activity UI** (File: `CadenceWidget/LiveActivities/FastingLiveActivityView.swift`)
    - Action: Add a `Button(intent: BreakFastIntent())` to:
      - Lock Screen `phoneView` (line 109-146): inline at bottom-right as a small pill labeled "End".
      - Dynamic Island expanded `.bottom` region (line 60-71): replace the static "Eat window opens" caption with both — caption on the left, End button on the right.
      - Compact / minimal: not feasible (no space) — those remain display-only.
      - Watch (`.small` family): skip — Apple Watch interactive buttons in Live Activities have additional constraints; defer to a separate ticket.
    - Why: Surface the intent where it's reachable.
    - Dependencies: step 25
    - Risk: Medium — Apple's intent rate limits + state-update race when intent fires while app is foregrounded. Test both foreground and backgrounded intent invocation.

27. **App handles pending-break on foreground** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift` + new helper in `FastingService`)
    - Action: In `FastingView.configureService()` (line 591-609), check `UserDefaults(suiteName:)` for the pending-break flag. If present, find the active session, set its `actualEndAt` and `completionStatus`, clear the flag, end the Live Activity.
    - Why: The intent process may not be able to mutate SwiftData reliably. App-side reconciliation closes the loop.
    - Dependencies: steps 25, 26
    - Risk: Medium — race condition if user opens the app simultaneously with the intent firing. Idempotency: check active session still exists before closing.

**Phase 6 verification:** With device locked, swipe to Lock Screen Live Activity → tap End. Unlock app, confirm FastingView shows the fast as ended in history. Repeat from Dynamic Island. Repeat with app already foregrounded.

---

### Phase 7 — Weekly grid + Home Digestive State card

**Goal:** Visual habit-formation framing + Home dashboard integration.

28. **Weekly grid component** (File: `Cadence/Features + UI/Stress/Views/FastingWeeklyGridView.swift` — NEW)
    - Action: `View` taking `sessions: [FastingSession]`. Renders a horizontal 7-column grid (Sun–Sat or Mon–Sun based on `Calendar.current.firstWeekday`). Each cell shows: day-of-week abbreviation, a colored square (filled `heroAccent` if a fast completed that day, hatched if partial/endedEarly, empty if no fast), and a small duration label. Highlight today with a ring.
    - Why: Audit §5. Habit visualization > flat list.
    - Dependencies: step 1 (uses `resolvedStatus`)
    - Risk: Low

29. **Integrate grid into FastingView** (File: `Cadence/Features + UI/Stress/Views/FastingView.swift`)
    - Action: Replace the existing `historySection` (line 510-551) `ForEach(completedSessions)` with `FastingWeeklyGridView(sessions: sessions)`. Keep the recent-row list below as a secondary "Recent" section, still tappable for editing (step 14).
    - Why: Grid is the primary visualization; rows are the edit affordance.
    - Dependencies: step 28
    - Risk: Low

30. **Home Digestive State card** (File: `Cadence/Features + UI/Home/Components/DigestiveStateCard.swift` — NEW)
    - Action: Compact card showing: current state (`Resting` / `Eating Window`) with `heroAccent` color, current time remaining (mini circular progress), most recent fast result, and the readiness layer (one-line sleep + stress + nutrition summary). Tap → routes through eligibility check (step 8) → FastingView or Care view.
    - Why: Audit §6.1. Persistent dashboard presence vs the current launcher-only integration.
    - Dependencies: steps 8, 19, 22
    - Risk: Medium — fits into the existing Home layout (`HomeView.swift`) which already has its own customizable card system (see `HomeLayoutEditor`). Verify integration with that system.

31. **Replace Home launcher with card** (File: `Cadence/Features + UI/Home/Views/HomeView.swift`)
    - Action: Replace the `headerAssetIcon("fasting_icon")` Button (line 593-601) with `DigestiveStateCard` placement. May need to relocate from header to the main scroll body depending on `HomeLayoutEditor` conventions. Preserve the eligibility-gated tap handler from step 8.
    - Why: Card-based integration is what the blueprint specifies.
    - Dependencies: step 30
    - Risk: Medium — Home layout has multiple cards and a customization system. Don't break existing card ordering for current users.

**Phase 7 verification:** Build all 4 targets. Seed varied session history (some completed, some endedEarly, some no-fast days). Confirm grid renders correctly. Open Home → confirm card shows correct state and routes correctly.

---

### Phase 8 — Bedtime-derived start reminder

**Goal:** Circadian-aware start reminder using existing HealthKit sleep data, no new permissions.

32. **Bedtime heuristic** (File: `Cadence/Features + UI/Stress/Services/FastingBedtimeHeuristic.swift` — NEW)
    - Action: `func computeAverageBedtime(over days: Int = 14) async -> DateComponents?`. Queries HealthKit sleep samples (reuse existing `HealthKitService` patterns), groups by sleep onset, returns median time-of-day. If <3 nights of data, return nil.
    - Why: Audit §9.4. No CLLocation in v1.
    - Dependencies: none
    - Risk: Low

33. **Schedule start-reminder** (File: `Cadence/Core/Services/FastingService.swift`)
    - Action: In `scheduleNotifications(for:)`, call the bedtime heuristic asynchronously; if it returns a bedtime, schedule a new daily `UNCalendarNotificationTrigger` for `bedtime - 3h` with copy: *"Your usual bedtime is around \(formattedTime). A great time to start your rest is now."* Identifier: `wp.fasting.startReminder`. If no bedtime data, do not schedule (silent fallback).
    - Why: Circadian alignment is the blueprint's positioning thesis.
    - Dependencies: step 32, step 17 (notification copy review)
    - Risk: Low

**Phase 8 verification:** With ≥3 nights of HealthKit sleep data, force notification re-scheduling, confirm the start reminder fires at bedtime - 3h. With <3 nights of data, confirm no notification is scheduled.

---

## Testing Strategy

Per CLAUDE.md: testing = build-only verification (4 targets via xcodebuild). No automated test suite is wired into shared schemes for this codebase.

**After each phase:**
```bash
xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build
```

**Manual verification flows per phase** (the golden path matters; tests don't cover this):

- **Phase 0**: Launch app cold with existing seed data; no SwiftData crash; existing fasts visible.
- **Phase 1**: Three branches — eligible / SCOFF fail (≥2) / demographic fail. Soft block hides initiation, keeps reports/insight chart.
- **Phase 2**: Seed session 25h old → cap notification fires; UI shows paused state; edit sheet corrects.
- **Phase 3**: Visual walkthrough — no "FASTING"/"BROKEN"/"Break Fast"/neon red/warning orange anywhere.
- **Phase 4**: Target hit → soft pulse, no celebration. "End Fast" tap → celebration. Auto-rollover to eat window → silent close.
- **Phase 5**: Banner copy matches HRV/sleep state. Ended session writes context fields.
- **Phase 6**: Lock Screen End button → fast closes correctly. Test foreground, background, and locked states.
- **Phase 7**: Grid renders 7 days correctly. Home card routes through eligibility check.
- **Phase 8**: Bedtime heuristic schedules start reminder when ≥3 nights of sleep exist.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **SwiftData additive migration silently corrupts existing rows** | Phase 0 step 2 verification: launch app with existing data, query an old `FastingSession`, confirm no crash and all legacy fields readable. If issue: roll back additive changes and reconsider VersionedSchema. |
| **`ratio20_4` removal breaks existing user schedules** | `FastingSchedule.scheduleType` is a raw String. The `resolvedScheduleType` computed (line 123-125) already falls back to `.custom` when the rawValue is unknown — but the enum case is being removed. Verify the fallback path handles legacy `"20:4"` strings. If a user has 20:4 saved, on next FastingView open they'll see "Custom fast" with correct durations — acceptable per audit §3.1. |
| **`LiveActivityIntent` can't write SwiftData from widget process** | Phase 6 architecture uses App Group UserDefaults as a pending-action flag; app reconciles on next foreground. Tested pattern across many iOS apps; safe. |
| **Soft block has too much surface area; one missed entry point lets a SCOFF-positive user start a fast** | Step 8 centralizes the eligibility check; every initiation surface routes through `FastingEligibility.canInitiate`. Add a single private extension `View.fastingEligibilityGated(...)` to make accidental bypass harder. |
| **Schedule conflict between cap-24h notification and the existing eat-window-closed daily notification** | Different identifiers (`wp.fasting.cap24h` vs `wp.fasting.windowClosed`), different trigger types (`UNTimeIntervalNotificationTrigger` one-shot vs `UNCalendarNotificationTrigger` daily). No collision. Add cap-24h to `clearNotifications` removal list to prevent stale captures. |
| **Soft completion (Phase 4) breaks the existing celebration flow tests** | No automated tests exist for this. Manual walkthrough of all 4 completion scenarios is the verification. Document scenarios in the verification section. |
| **Onboarding flow accidentally disqualifies a user via miss-tap** | Use `.toggle` style not `Button` style for SCOFF answers; require explicit "Submit" on each step; allow Back navigation within the flow (but not after a disqualifying answer is submitted — that triggers Care immediately). |
| **Phase 5's `FastingContextProvider` duplicates `StressViewModel`'s HealthKit fetches** | Before implementing: inspect `StressViewModel.loadData()` and `HealthKitService` to find a shared cache or query helper. Reuse rather than parallel-fetch. If no cache exists, consider extracting one in this phase (small refactor). |
| **Home `DigestiveStateCard` placement conflicts with `HomeLayoutEditor` customization** | Read `HomeLayoutEditor.swift` before Phase 7 step 30 to understand how cards register themselves. The card should slot into the existing customization system. |
| **Live Activity interactive button rate limiting** | iOS rate-limits Live Activity updates. The intent itself isn't rate-limited the same way, but the resulting state update via `update(:)` is. This is fine for a one-shot End Fast (no rapid-fire). |
| **Bedtime heuristic returns wrong time for shift workers** | Explicitly out of scope for v1 (audit §7 open question 1 is unresolved — but it was a planning-level question, not an implementation blocker). Graceful: if heuristic returns no data, no notification scheduled. v1.1 can add shift-worker mode. |

---

## Success Criteria

- [ ] All 4 targets build clean.
- [ ] New users walk through Disclaimer → Demographics → SCOFF → Schedule before any fast can start.
- [ ] SCOFF ≥2 positives routes to Care Intervention; no fast-initiation surfaces are reachable.
- [ ] Underage / pregnant / lactating users routed to Care Intervention.
- [ ] No fasting session exceeds 24h displayed time; cap notification fires at exactly 24h.
- [ ] Live Activity displays paused-at-24h state and offers an interactive End button.
- [ ] No instance of "FASTING", "BROKEN", "Break Fast", neon red, or warning orange in any fasting surface.
- [ ] Schedule presets: 12:12 (default), 14:10, 16:8, 18:6, Custom. No 20:4.
- [ ] Target hit triggers soft pulse + bonus-time counter; celebration only fires on explicit "End Fast" tap.
- [ ] HRV/sleep insight banner under the timer shows contextually-relevant copy when data exists.
- [ ] Ended sessions persist `contextualHRV` and `contextualSleepScore`.
- [ ] Weekly grid replaces flat list as primary history visualization.
- [ ] Home dashboard shows persistent Digestive State card (not just a launcher button).
- [ ] Bedtime-derived start reminder schedules when ≥3 nights of HealthKit sleep data exist; silently does nothing otherwise.
- [ ] No CLLocation permission added to Info.plist.
- [ ] No writes to HealthKit `HKCategoryTypeIdentifier.mindfulSession` (current code is clean; verify no regression).
- [ ] First-time user with existing data sees no SwiftData crash and existing fasts still display.

---

## Suggested implementation sequencing

Ship in this order; each is independently shippable to the App Store:

1. **Phases 0 + 1 + 2 + 3** as v1.0.0 — safety floor + copy compliance. This is the minimum-viable-blueprint-compliant release.
2. **Phase 4** as v1.0.1 — completion UX rework.
3. **Phase 5** as v1.1.0 — contextual intelligence (the differentiator).
4. **Phase 6** as v1.2.0 — Lock Screen interactivity.
5. **Phases 7 + 8** as v1.3.0 — weekly grid + Home card + bedtime reminder.

This sequence prioritizes regulatory exposure first, then differentiation, then polish.
