# Plan Audit Report: Fasting Timer / IF Tracker

**Audit Date**: 2026-04-06
**Plan Audited**: `Docs/02_Planning/Specs/260406-fasting-timer-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The plan is well-structured, follows established architectural patterns (toolbar menu → sheet, SwiftData models, single-enum sheet routing), and correctly scopes the MVP. Three HIGH issues need resolution before implementation: (1) `dailyAverages` in `StressLabAnalyzer` is `private static` — the plan says to "reuse" it but can't without changing its access level or extracting it; (2) `UserNotifications` framework has never been used anywhere in the app — the plan assumes notification infrastructure exists but it doesn't, requiring a first-time `UNUserNotificationCenter` permission request flow; (3) `FastingService` takes `ModelContext` as init param but the project pattern is `@Environment(\.modelContext)` in views — the service needs a different injection pattern. Two MEDIUM issues address `FastingView`'s internal `.sheet()` and the missing `FastingScheduleType` enum file location.

---

## Issues Found

### CRITICAL

None.

---

### HIGH

#### H1: `StressLabAnalyzer.dailyAverages` is `private static` — cannot be reused as described

- **Location**: Step 6, data pipeline — "reuse `StressLabAnalyzer.dailyAverages` pattern"
- **Problem**: `dailyAverages(from:)` at `StressLabAnalyzer.swift:57` is declared `private static func`. The plan says to "reuse" it for the insight chart, but it's not accessible outside `StressLabAnalyzer`.
- **Impact**: Build error if `FastingInsightChart` tries to call `StressLabAnalyzer.dailyAverages(from:)`.
- **Recommendation**: Two options:
  - **(A) Extract to shared utility**: Move `dailyAverages(from:)` to a new top-level function or a shared `StressAnalyticsHelper` struct with `static func dailyAverages(from readings: [StressReading]) -> [Double]`. Update both `StressLabAnalyzer` and `FastingInsightChart` to call it. Simple refactor, low risk.
  - **(B) Duplicate locally**: Copy the ~6-line function into `FastingInsightChart`. Pragmatic but creates duplication.
  - Recommendation: Option A — the function is pure and generic, and will likely be needed by future features (Phase 2 symptom correlations).

---

#### H2: `UserNotifications` framework not yet used anywhere in the app — first-time setup required

- **Location**: Step 4 (FastingService), notification scheduling
- **Problem**: No file in `WellPlate/` imports `UserNotifications` or calls `UNUserNotificationCenter`. The plan lists 4 notification IDs and scheduling logic but doesn't account for the fact that this is the app's first-ever use of local notifications. First-time notification setup requires:
  1. `import UserNotifications` in the service
  2. `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])` — must be called before any notification can be scheduled
  3. A user-facing prompt explaining why notifications are needed (iOS shows the system permission dialog)
  4. Graceful handling when permission is denied (the plan's risk table mentions this but the implementation steps don't include the permission request flow)
- **Impact**: Notifications will silently fail if `requestAuthorization` is never called. Users see no reminders, defeating a core feature value.
- **Recommendation**: Add an explicit sub-step in Step 4:
  - `FastingService.requestNotificationPermission()` — called when user first enables a schedule
  - If authorization is `.denied`, set a `@Published var notificationsBlocked = true` flag
  - `FastingView` reads this flag and shows an inline hint: "Enable notifications in Settings for fasting reminders"
  - Add `import UserNotifications` to `FastingService.swift`

---

#### H3: `FastingService` ModelContext injection doesn't match project pattern

- **Location**: Step 4 — "Takes `ModelContext` as init param"
- **Problem**: The established project pattern is that **views** access `@Environment(\.modelContext)` and pass data to services/VMs, or VMs are `@StateObject`/`@ObservedObject` in views. No existing service in the codebase takes `ModelContext` as an init parameter — `StressViewModel` uses `@Published` properties and receives data from views or HealthKit. Passing `ModelContext` through init couples the service to SwiftData directly and makes it harder to test.
- **Impact**: Architectural inconsistency. Also, `ModelContext` is not `Sendable`, which could cause issues if the service does any async work.
- **Recommendation**: Two options:
  - **(A) View-side CRUD**: `FastingView` owns `@Query` for schedules/sessions and calls `modelContext.insert()` / `modelContext.delete()` directly. `FastingService` becomes a pure timer + notification coordinator (no SwiftData dependency). Views pass `FastingSchedule` to the service for timer calculations.
  - **(B) Environment injection**: `FastingService` receives `ModelContext` lazily via a `configure(context:)` method called from `FastingView.onAppear`.
  - Recommendation: Option A — keeps the service thin and follows the `StressLabView` pattern where `@Query` + `modelContext` live in the view.

---

### MEDIUM

#### M1: `FastingView` uses `.sheet(isPresented: $showScheduleEditor)` — potential CLAUDE.md conflict

- **Location**: Step 7, FastingView layout — `.sheet(isPresented: $showScheduleEditor)`
- **Problem**: CLAUDE.md states "Feature sheets use a single enum driving one `.sheet(item:)` — do not add multiple `.sheet()` calls." If `FastingView` adds a `.sheet(isPresented:)`, it follows the same anti-pattern flagged in prior audits (C1 in stress-lab-plan-audit). However, `FastingView` is itself already a sheet (presented from `StressView`), and it only has one internal sheet, so the conflict is minor.
- **Impact**: Low — single sheet is fine. But for consistency, and if future sub-sheets are added (e.g., session detail), an enum is safer.
- **Recommendation**: Use a `FastingSheet` enum with a `.scheduleEditor` case, following the `StressLabSheet` pattern established in `StressLabView.swift:5-15`. This is future-proof for when history row taps might need a detail sheet.

---

#### M2: `FastingScheduleType` enum lives inside `FastingSchedule.swift` — consider separate file for reuse

- **Location**: Step 1 — `FastingScheduleType` enum defined in `FastingSchedule.swift`
- **Problem**: `FastingScheduleType` is referenced by `FastingSession.swift` (Step 2: init takes `FastingScheduleType`), `FastingScheduleEditor.swift` (Step 5: picker), `FastingView.swift` (Step 7: display), and `FastingService.swift` (Step 4: schedule logic). Putting it inside the model file works but may cause import-order confusion since it's a top-level enum, not nested in the class.
- **Impact**: Low — it compiles fine either way since all files are in the same module.
- **Recommendation**: Keep the enum in `FastingSchedule.swift` as proposed (it's the model file where it semantically belongs). This is consistent with how `InterventionType` lives in `StressExperiment.swift` and `ResetType` has its own file. Either pattern works; the plan's choice is acceptable.

---

#### M3: Auto-session creation timing edge case

- **Location**: Step 4 — "When `currentState` transitions from `.eating` → `.fasting`, auto-create a new `FastingSession`"
- **Problem**: If the user configures a schedule at 3pm and the eat window ends at 8pm, the first session auto-creates at 8pm. But if the user configures at 9pm (already past eat window end), the app should recognize they're already in a fasting state and either: (a) create a session retroactively starting at 8pm, or (b) create a session starting at 9pm (now). The plan doesn't specify this "first session" behavior.
- **Impact**: Medium — user configures schedule, sees "Fasting" state but no session is tracked until the next eat window transition.
- **Recommendation**: On schedule creation/activation, `FastingService` should determine current state from the schedule and, if currently in a fasting window, create a session with `startedAt = eatWindowEndTime` (the most recent past eat window end). This gives immediate history tracking.

---

#### M4: Missing `presentationDragIndicator(.visible)` spec on `FastingView`

- **Location**: Step 7, `FastingView` layout
- **Problem**: The plan shows `.presentationDragIndicator(.visible)` in the layout snippet but doesn't call it out as a required modifier. `InterventionsView` uses it (line 37), `StressLabView` does not. Inconsistency.
- **Impact**: Minor UX inconsistency.
- **Recommendation**: Include `.presentationDragIndicator(.visible)` on `FastingView` to match `InterventionsView`. Add it explicitly to the step description.

---

### LOW

#### L1: History section limited to 7 sessions — no "See All" path

- **Location**: Step 7, history section — "last 7 `FastingSession` rows"
- **Problem**: After a few weeks, users will have 20+ sessions. No "Show all" or pagination is planned.
- **Impact**: Low — 7 is fine for MVP. Users can still see insight chart for aggregate view.
- **Recommendation**: Defer to post-MVP. Note in plan as known limitation.

---

#### L2: No mock mode support mentioned

- **Location**: Entire plan
- **Problem**: The app has `AppConfig.shared.mockMode` for development. The plan doesn't mention mock data support for fasting. `StressLabView` gates Lab behind HealthKit but fasting doesn't need HealthKit, so this is less critical.
- **Impact**: Low — fasting doesn't depend on HealthKit data, only on SwiftData (which works in mock mode).
- **Recommendation**: No action needed for MVP. Fasting works the same in mock and real mode.

---

## Missing Elements

- [ ] **Notification permission request flow** — Step 4 must include `UNUserNotificationCenter.requestAuthorization()` call and denied-state handling (see H2)
- [ ] **First-session creation logic** when user configures schedule mid-fasting-window (see M3)
- [ ] **`dailyAverages` extraction** — plan needs to specify whether to extract or duplicate (see H1)

---

## Unverified Assumptions

- [ ] SwiftData lightweight migration handles adding 2 new `@Model` types to an existing store — **Risk: Low** (standard SwiftData behavior for additive schema changes)
- [ ] `UNCalendarNotificationTrigger` with `repeats: true` fires daily at the same time — **Risk: Low** (documented Apple behavior)
- [ ] `Timer.publish(every: 1, ...)` is sufficient for countdown display — **Risk: Low** (1-second precision is standard for timer UIs)

---

## Questions for Clarification

1. Should the "Break fast" action require a confirmation alert (like "Are you sure? This will end your current fast") or fire immediately on tap?
2. When the user toggles `isActive = false` on their schedule, should any active session be auto-ended, or should it be allowed to complete?

---

## Recommendations

1. **Resolve H1** by extracting `dailyAverages` to a shared utility — this benefits both the fasting insight chart and future features (symptom correlations in Phase 2)
2. **Resolve H2** by adding a `requestNotificationPermission()` method to `FastingService` and calling it on first schedule activation
3. **Resolve H3** by using view-side `@Query` + `modelContext` pattern (Option A) — keeps `FastingService` as a pure timer/notification coordinator
4. **Resolve M1** by using a `FastingSheet` enum for internal sheets
5. **Resolve M3** by adding first-session retroactive creation logic
