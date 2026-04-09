# Strategy: Fasting Timer / IF Tracker

**Date**: 2026-04-06
**Source**: `Docs/01_Brainstorming/260406-fasting-timer-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**Approach 3: Stress toolbar sheet** — a full-screen `FastingView` sheet accessed from the existing `StressView` toolbar `Menu` (same pattern as Stress Lab and Interventions). New `StressSheet.fasting` case routes the sheet. Two new SwiftData models (`FastingSchedule` + `FastingSession`) persist configuration and history. A fasting × stress split-bar insight chart is embedded in the sheet, requiring ≥7 days of data.

Phase 1 deliberately does **not** add a Home tab glance card or modify the stress score formula. Fasting is a correlation insight companion, not a new factor input.

---

## Rationale

- **Approach 3 over Approach 1 (Home card)**: Home tab scroll is already content-dense (meal log, activity rings, calendar, mood, water). Adding another persistent card without first proving the feature's value is premature. The Stress toolbar sheet is the established "power feature" entry point — Lab and Interventions already live here.
- **Approach 3 over Approach 2 (5th factor card)**: Making fasting a stress factor requires changing the score formula, introducing regression risk on the app's core metric. Correlation insight (side-by-side comparison) is safer and more honest — users see "fasting days avg stress = X vs non-fast days = Y" without implying causation.
- **Approach 3 over Approach 4 (Hybrid)**: Cross-tab deep linking is unnecessary complexity for MVP. Two entry points (toolbar menu + future Home card) can be added independently later without architecture changes.
- **Approach 3 over Approach 5 (Profile-only)**: Profile-only has no visible timer state — defeats the purpose for users who want real-time feedback during a fast.

---

## Affected Files & Components

### New Files

| File | Purpose |
|---|---|
| `WellPlate/Models/FastingSchedule.swift` | `@Model` — stores eat window config (schedule type, start time, duration, caffeine cutoff toggle) |
| `WellPlate/Models/FastingSession.swift` | `@Model` — one row per fasting session (start, target end, actual end, completed flag) |
| `WellPlate/Core/Services/FastingService.swift` | `@MainActor ObservableObject` — owns schedule CRUD, session lifecycle (start/end/break), active timer state, notification scheduling |
| `WellPlate/Features + UI/Stress/Views/FastingView.swift` | Main sheet — 3 sections: live timer ring, schedule configurator, history + insight chart |
| `WellPlate/Features + UI/Stress/Views/FastingScheduleEditor.swift` | Sub-view — schedule type picker (16:8, 14:10, 18:6, 20:4, custom), eat window time pickers, caffeine cutoff toggle |
| `WellPlate/Features + UI/Stress/Views/FastingInsightChart.swift` | Split-bar chart — "Fast days" avg stress vs "Non-fast days" avg stress, with n-count and causation caveat |

### Modified Files

| File | Change |
|---|---|
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | Add `.fasting` case to `StressSheet` enum; add "Fast" button to toolbar `Menu`; add `FastingView()` case in `.sheet(item:)` switch |
| `WellPlate/App/WellPlateApp.swift` | Add `FastingSchedule.self` and `FastingSession.self` to `.modelContainer(for:)` array |

---

## Architectural Direction

### Timer Model

`FastingService` holds a `@Published var activeFastingSession: FastingSession?` and a `Timer.publish(every: 1, ...)` that ticks while a session is active. On app launch / `scenePhase == .active`, the service rebuilds timer state from the persisted `FastingSession.startedAt` — no background task needed, just date math.

The `InterventionTimer` class is **not reused** — it's phase-array-based (breath cycles, muscle groups) and designed for 30–60 second sessions. Fasting timers run 14–20 hours. A simple `Date`-diff countdown is the right tool.

### Notification Strategy

`FastingService` schedules 3 repeating `UNCalendarNotificationTrigger` notifications daily when a schedule is configured:
1. **Eat window closed** — fires at `eatWindowEnd` time
2. **1 hour before fast ends** — fires at `fastEnd - 1h`
3. **Fast complete** — fires at `fastEnd`
4. (Optional) **Caffeine cutoff** — fires at cutoff time if enabled

Notifications are rescheduled whenever the schedule changes. All are cleared when fasting is disabled.

### Insight Chart Data Pipeline

`FastingInsightChart` queries `FastingSession` (completed sessions from last 30 days) and `StressReading` (daily stress scores). For each day:
- Classify as "fast day" (completed session that day) or "non-fast day"
- Compute mean stress score per group
- Display as a horizontal split-bar with "n = X days" labels

Gate: chart is hidden with a CTA ("Log 7+ days to see your pattern") until ≥7 days of data exist across both groups.

### Schedule Model

`FastingSchedule` is a singleton-style record — only one active schedule at a time. The `isActive` flag allows toggling fasting on/off without deleting the configuration. Schedule types are:

| Type | Fast : Eat | Eat Window |
|---|---|---|
| 16:8 | 16h : 8h | Default 12pm–8pm |
| 14:10 | 14h : 10h | Default 10am–8pm |
| 18:6 | 18h : 6h | Default 12pm–6pm |
| 20:4 | 20h : 4h | Default 12pm–4pm |
| Custom | User-defined | User-defined |

All schedule types store an eat window start time and eat duration — the "type" is just a preset convenience.

### Caffeine Cutoff Integration

Ties into existing `WellnessDayLog.coffeeCups` tracking. `FastingService` exposes a computed `isCaffeineCutoffActive: Bool` based on current time vs. cutoff time. The `FastingView` displays a subtle "Caffeine cutoff active" indicator when true. This is display-only in Phase 1 — no enforcement or blocking.

---

## Design Constraints

1. **Follow the card + sheet visual language**: Timer ring uses same `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)` card treatment
2. **Font**: `.r(.headline, .semibold)` etc. — custom extension, not system fonts
3. **Haptics**: `HapticService.impact(.light)` on button taps, `HapticService.notify(.success)` on fast complete
4. **One `.sheet(item:)`**: All sheets in StressView route through the single `StressSheet` enum — no additional `.sheet()` modifiers
5. **SwiftData context**: `@Environment(\.modelContext)` in views, not passed as init params
6. **`@MainActor` on service class**: Consistent with `StressViewModel` and other services
7. **No background tasks**: Timer state reconstructs from persisted `Date` values on foreground — notifications handle the background story

---

## Non-Goals

- **Live Activities / Lock Screen widget**: Planned as F7 (Phase 3) — not in this scope
- **Home tab glance card**: Deferred to Phase 1 polish — not blocking MVP
- **Stress score formula change**: Fasting does NOT become a factor in the composite stress score
- **Apple Watch fasting complication**: Planned as F8 (Phase 3)
- **Weekly report integration**: Deferred to Phase 1 polish
- **Fasting streak / gamification**: Not in MVP — keep it informational, not motivational
- **Per-day schedule variation (weekday vs. weekend)**: Not in MVP — one schedule applies to all days

---

## Open Risks

- **Notification permissions**: App may not have notification permissions yet. `FastingService` must request `UNUserNotificationCenter.requestAuthorization()` the first time user enables a schedule. If denied, timer still works but without alerts — show a subtle "Notifications disabled" hint.
- **Midnight-spanning fasts**: All `Date` math must use full timestamps, not time-of-day components. A 16:8 with eat window 12pm–8pm means fasting 8pm → 12pm next day — `FastingSession.startedAt` and `targetEndAt` are `Date`, not `DateComponents`.
- **SwiftData model migration**: Adding 2 new `@Model` types is a lightweight schema addition, but if existing users have a persisted store, SwiftData's automatic lightweight migration should handle it. No manual migration code expected.
