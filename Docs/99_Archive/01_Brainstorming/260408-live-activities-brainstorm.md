# Brainstorm: F7 — Live Activities (ActivityKit)

**Date**: 2026-04-08
**Status**: Ready for Planning

---

## Problem Statement

WellPlate tracks fasting, breathing interventions, hydration, and stress — but all of this disappears the moment the user locks their phone. ActivityKit fills the gap: keeping time-sensitive wellness states visible on the Lock Screen and in the Dynamic Island without requiring the app to be open. F7's value proposition is "glanceable wellness continuity" — the user is in a 14-hour fast, a 10-minute breathing session, or needs to know they've hit their water goal, and they shouldn't need to unlock their phone to know that.

The roadmap scopes this to three surfaces: **fasting window countdown**, **breathing session progress**, and **optional hydration streak**. The fasting countdown is the anchor (F1 is the explicit dependency). The breathing and hydration surfaces are extensions.

---

## Core Requirements

- Fasting window countdown visible on Lock Screen + Dynamic Island during an active fast
- Breathing/intervention session progress shown during Stress Lab breathing exercises
- Live Activity starts automatically when a fast begins (eat window closes) or a breathing session starts
- Live Activity ends automatically when the session ends (fast complete, broken, or session finished)
- Dynamic Island presents compact (leading + trailing), minimal, and expanded layouts
- Lock Screen widget shows a rich summary: progress ring, time remaining, contextual label
- Graceful degradation on devices without Dynamic Island (older iPhones)
- No duplicate Live Activities — if one is already running, update it rather than spawning a new one
- Hydration streak is optional/additive — ship only if it doesn't complicate the fasting implementation

---

## Constraints

- **iOS 16.2+ required** for ActivityKit (Dynamic Island: iPhone 14 Pro+; all other devices get Lock Screen only)
- **New entitlement**: `NSSupportsLiveActivities` key in Info.plist + ActivityKit capability in the target
- **No background push needed for MVP**: WellPlate can update the activity from the foreground or via scheduled background task; push-based remote updates (ActivityKit push tokens) are Phase 4 complexity
- **5 Live Activity limit** per app — not an issue for MVP (WellPlate will have at most 2 types running sequentially)
- **ActivityAttributes content must be `Codable + Sendable`** — no SwiftData models, no HealthKit types, no UIKit images in content state
- **Simulator gap**: Live Activities don't run correctly in the Simulator; device testing is required
- **Widget extension target**: Live Activities and WidgetKit share the same extension target. The existing `WellPlateWidget` target already has WidgetKit; add ActivityKit to the same target — no new app extension needed
- **F1 must be implemented first**: `FastingService`, `FastingSession`, and `FastingSchedule` models are prerequisites
- **Intervention sessions** exist via `InterventionSession` (SwiftData) and `InterventionTimer` — breathing is one intervention type, already trackable

---

## How ActivityKit Works (Reference)

```
ActivityAttributes          → static data (doesn't change during the activity)
ActivityAttributes.ContentState → dynamic data (updated via activity.update())

Activity<T>.request(attributes:content:pushType:) → starts the activity
await activity.update(ActivityContent(state: newState, staleDate: ...)) → updates
await activity.end(ActivityContent(state: finalState), dismissalPolicy: .default) → ends
```

The Live Activity widget views are defined in the widget extension using `ActivityConfiguration<T>`. Four presentation contexts:
- `.compact` — Dynamic Island collapsed (split: leading view + trailing view)
- `.minimal` — Dynamic Island when two activities compete (pill-shaped icon)
- `.expanded` — Dynamic Island tapped/long-pressed
- `.lockScreen` — shown on Lock Screen as a banner

---

## Approach 1: Fasting-Only MVP

**Summary**: Ship a single `FastingActivityAttributes` type for the fasting countdown. Breathing and hydration are deferred to the next iteration.

**How it works**:
- `FastingActivityAttributes` — static: schedule label ("16:8 Fast")
- `FastingActivityAttributes.ContentState` — dynamic: `fastState` (fasting/eating), `progress` (0.0–1.0), `targetEndAt: Date`, `label: String`
- `FastingActivityManager` embedded in or coordinated alongside `FastingService`
- When `FastingService` transitions to `.fasting`: call `Activity<FastingActivityAttributes>.request(...)`
- On each `FastingSession.progress` tick: call `activity.update(...)` — but only on meaningful intervals (every 5 min), not every second (Live Activity views use `timerInterval` from a `Date` range, not polled values)
- Key insight: use SwiftUI's `Text(.now ..< targetEndAt, countsDown: true)` timer syntax — the OS handles the countdown display without any app-side updates
- When fast ends/broken: `await activity.end(..., dismissalPolicy: .after(30s))`

**Dynamic Island**:
```
Compact leading:  fork.knife SF Symbol (accent orange)
Compact trailing: Text(targetEndAt, style: .timer) — e.g. "4:22"
Minimal:          fork.knife icon
Expanded:         Circular trim arc (progress) + "Fasting" label + time + schedule type
```

**Lock Screen**:
```
HStack {
  CircleProgressView(progress: contentState.progress, color: .orange)
  VStack(alignment: .leading) {
    Text("Fasting · 16:8")
    Text(contentState.targetEndAt, style: .timer) // "4h 22m"
    Text("Eat window opens at 12:00 PM")
  }
}
```

**Pros**:
- Lowest risk — one `ActivityAttributes` type, one manager
- Fasting is the highest-value use case (users are most invested in tracking a multi-hour fast)
- `timerInterval` / `.timer` style text means zero app-side update polling — only one update needed per state transition
- Clear start/end lifecycle tied to existing `FastingService` state machine

**Cons**:
- Breathing sessions get no Live Activity benefit (missed opportunity for engagement during 10-min sessions)
- Hydration tracking completely deferred

**Complexity**: Low | **Risk**: Low

---

## Approach 2: Multi-Type — Fasting + Breathing Sessions

**Summary**: Two `ActivityAttributes` conforming types: `FastingActivityAttributes` and `BreathingActivityAttributes`. An `ActivityManager` service tracks both independently.

**How it works**:
- `BreathingActivityAttributes` — static: session name (e.g., "Box Breathing"), total duration
- `BreathingActivityAttributes.ContentState` — dynamic: `breathPhase` (inhale/hold/exhale/rest), `cyclesRemaining: Int`, `progress: Double`, `phaseEndAt: Date`
- `ActivityManager` is a new `@MainActor ObservableObject` that holds references to both `Activity<FastingActivityAttributes>?` and `Activity<BreathingActivityAttributes>?`
- Breathing session: started from `InterventionTimer` when session type is `.breathing`. When `InterventionSession` starts → request breathing activity. Phase transitions → update activity. Session completes → end activity with celebration state.
- Fasting Live Activity and Breathing Live Activity are independent; either can be active simultaneously

**Dynamic Island — Breathing Expanded**:
```
VStack {
  Text(breathPhase.label)   // "Inhale" / "Hold" / "Exhale"
  Text(phaseEndAt, style: .timer)  // e.g. "0:04"
  Text("Cycle 3 of 10")
  ProgressView(value: progress)
}
```

**Pros**:
- Breathing Live Activity is high-value for guided breathwork: users glance at the island to know what phase they're in (hands on belly, eyes closed)
- Natural extension of existing `InterventionTimer` state machine
- Both activities have clean start/end lifecycles

**Cons**:
- Two attribute types = 2× the view code in the widget extension
- Breathing session is 5–15 min; Live Activity overhead is more significant per minute of value compared to the fasting case
- `InterventionTimer` phase changes are rapid (seconds), meaning more frequent activity updates — care needed to avoid `ActivityKit` rate limiting (iOS limits updates to a budget)
- More complex `ActivityManager` — must handle the case where both are active simultaneously

**Complexity**: Medium | **Risk**: Medium (ActivityKit update budget for breathing phases)

---

## Approach 3: Unified "Wellness Live Activity" (Single Attributes Type)

**Summary**: One `WellnessActivityAttributes` conforming type covers all session types via a discriminated enum in the content state.

**How it works**:
- `WellnessActivityAttributes` — static: `sessionType: WellnessSessionType` enum, `sessionTitle: String`
- `WellnessActivityAttributes.ContentState` — dynamic: `WellnessSessionState` enum with associated values:
  ```swift
  enum WellnessSessionState: Codable, Sendable {
      case fasting(progress: Double, targetEndAt: Date, label: String)
      case breathing(phase: String, phaseEndAt: Date, cycle: Int, totalCycles: Int)
      case hydration(oz: Double, goalOz: Double)
  }
  ```
- One `ActivityConfiguration<WellnessActivityAttributes>` block handles all three cases via a `switch` on `contentState.state`
- One `ActivityManager` handles `Activity<WellnessActivityAttributes>?`

**Pros**:
- Single `ActivityAttributes` type = one widget view to maintain
- Hydration can be included without a third code path
- Conceptually elegant: WellPlate has "one active wellness context"

**Cons**:
- The widget view becomes a big `switch` statement — harder to read, harder to test individual layouts
- Enum with associated values in `ContentState` works (it's `Codable`) but adds complexity and testing surface
- If breathing and fasting are both active, you can only show one (single activity instance) — need a priority/preemption policy
- ActivityKit's Swift API doesn't natively support "replace this type" — you'd end up ending the old activity and starting a new one, which causes a flash
- The unified model doesn't actually reduce entitlement requirements (still need one entitlement for ActivityKit)

**Complexity**: Medium | **Risk**: Medium (priority conflicts, complex state enum)

---

## Approach 4: Phased — Fasting MVP, Then Breathing Polish (Recommended)

**Summary**: Ship Approach 1 (fasting only) as the F7 MVP. Add `BreathingActivityAttributes` in a fast-follow polish pass within the same feature branch, before shipping. Hydration is optional Phase 3+ addition.

**Execution**:
1. **MVP (F7.0)**: `FastingActivityAttributes` + `FastingActivityManager` + Lock Screen / DI views. Zero breathing changes.
2. **Polish (F7.1)**: Add `BreathingActivityAttributes`, wire to `InterventionTimer`. Breathing sessions get compact DI presence (phase + countdown). Lock Screen shows breath progress bar.
3. **Optional (F7.2)**: `HydrationActivityAttributes` — shows `oz / goalOz` on Lock Screen. Minimal DI presence (water droplet + progress). Only triggered when user taps the water log and has a goal set.

**Why this order**:
- Fasting is the clearest start/end lifecycle, easiest to validate on device
- Breathing adds update-budget risk (rapid phase changes) — better addressed after the fasting path is solid
- Hydration is stateless (no countdown) — simpler but lower urgency

**Pros**:
- Delivers shippable value in MVP while preserving the extension path
- Breathing update-budget risk is isolated to F7.1 — failures don't block fasting
- Each phase is independently testable

**Cons**:
- If polish pass doesn't happen, breathing never gets a Live Activity
- Two code reviews (one per phase) vs. one

**Complexity**: Low (MVP) → Medium (complete) | **Risk**: Low

---

## Architecture Proposal

### New Files

| File | Purpose |
|---|---|
| `WellPlate/Core/Services/ActivityManager.swift` | `@MainActor ObservableObject` — starts/updates/ends `Activity<T>` instances; observes `FastingService` and `InterventionTimer` |
| `WellPlateWidget/LiveActivities/FastingActivityAttributes.swift` | `ActivityAttributes` type + `ContentState` for fasting. Shared between app target (writes) and widget target (reads) — place in a shared group or duplicate struct |
| `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift` | Lock Screen and Dynamic Island views for fasting |
| `WellPlateWidget/LiveActivities/BreathingActivityAttributes.swift` | (F7.1) `ActivityAttributes` for breathing sessions |
| `WellPlateWidget/LiveActivities/BreathingLiveActivityView.swift` | (F7.1) DI and Lock Screen views for breathing |

### Modified Files

| File | Change |
|---|---|
| `WellPlateWidget/WellPlateWidgetBundle.swift` | Add `ActivityConfiguration<FastingActivityAttributes>` block |
| `WellPlate/Core/Services/FastingService.swift` | Inject `ActivityManager` reference; call `activityManager.startFastingActivity(...)` on state transition to `.fasting` |
| `WellPlate/App/WellPlateApp.swift` | Create and inject `ActivityManager` as `@StateObject` |
| `WellPlate/Core/AppConfig.swift` | Add `NSSupportsLiveActivities` to Info.plist; add ActivityKit capability to `WellPlate.entitlements` |

### Key Design Decisions

1. **Shared ActivityAttributes location**: `ActivityAttributes` structs must be visible to both the main app target (to call `Activity.request(...)`) and the widget extension target (to render views). Options:
   - **Option A**: Duplicate the struct in both targets — simple but fragile
   - **Option B**: Place in a Swift Package (internal framework) — clean but adds a target dependency
   - **Option C**: Add the file to both targets via `Target Membership` in Xcode — standard WidgetKit pattern, what the existing stress widget likely does already
   - **Recommendation**: Option C — follows the existing widget extension pattern

2. **Timer display**: Use `Text(targetEndAt, style: .timer)` and `Text(dateInterval, countsDown: true)` — the OS renders the countdown without any app updates. The only activity updates needed are on state transitions (not per-second ticks).

3. **ActivityManager lifetime**: `ActivityManager` is a long-lived `@StateObject` in `WellPlateApp.swift`, injected as `@EnvironmentObject` to `FastingView` and `StressLabView` (for intervention sessions).

4. **Stale date**: Always set `staleDate` to `targetEndAt + 30s`. After stale date, iOS shows a default "Activity ended" UI. For breathing sessions (< 15 min), stale date = session end.

---

## Dynamic Island Layout Sketch

```
┌─────────────────────────────────────────┐
│          COMPACT (collapsed)            │
│  [fork.knife]          [4:22]           │
│   leading               trailing        │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│          EXPANDED (tapped)              │
│                                         │
│   ○───────────────────────────○         │
│   ●●●●●●●●●●●●●●●●○○○○○○○○○○○           │  ← arc progress
│              🍴                          │
│         Fasting · 16:8                  │
│          4h 22m left                    │
│     Eat window: 12:00–8:00 PM           │
│                                         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│          LOCK SCREEN                    │
│  ┌────┐  Fasting · 16:8                 │
│  │ ◐  │  4h 22m remaining              │
│  │    │  Eat window opens at 12:00 PM  │
│  └────┘                                 │
└─────────────────────────────────────────┘
```

---

## Edge Cases to Consider

- [ ] Live Activity starts when app is in foreground and fast begins; what if fast was already in progress when app launches? → `ActivityManager.onAppear` should check `FastingService.currentState` and resume/reconnect to any existing activity via `Activity<FastingActivityAttributes>.activities` (the OS keeps running activities even if the app was killed)
- [ ] ActivityKit is unavailable on older iOS (<16.2) or if device has insufficient memory — wrap all `Activity.request(...)` calls in an `if ActivityAuthorizationInfo().areActivitiesEnabled` guard
- [ ] User kills the app during an active fast — the Live Activity continues to display on Lock Screen (OS-managed), but the countdown is static once stale date passes. On next app launch, `ActivityManager` reconnects to the existing activity and resumes updates
- [ ] Fast is broken ("End Fast" button) — `ActivityManager.endFastingActivity()` should end with a completion state showing "Fast ended early" + duration, then `.default` dismissal policy (30s display)
- [ ] Fast completes on time — end with "Fast complete ✓" state + `.default` dismissal
- [ ] User has no Dynamic Island (iPhone 13 or older) — Lock Screen banner still shows; app receives no errors — no special handling needed
- [ ] Multiple starts (e.g., user configures a new schedule while an activity is running) — `ActivityManager` must check `Activity<FastingActivityAttributes>.activities.isEmpty` before requesting a new one; if not empty, update the existing one or end-then-restart
- [ ] iOS limits: if the app has hit its Live Activity budget (unlikely with 1–2 types), `Activity.request(...)` throws an `ActivityKit` error — catch and log silently; the app falls back to notifications (already implemented in `FastingService`)
- [ ] Breathing phase updates happen every 4–6 seconds — ActivityKit has a rate budget. Use the `timerInterval` property (`Text(phaseInterval, countsDown: true)`) to handle per-second display natively; only send explicit updates on phase transitions (~every 4–6s), not per-second
- [ ] App is uninstalled while a Live Activity is running — iOS automatically ends it; no cleanup needed
- [ ] User disables Live Activities in iOS Settings → Notifications → WellPlate → `areActivitiesEnabled` returns false; `ActivityManager` should surface this in `FastingView` alongside the existing `notificationsBlocked` hint

---

## Open Questions

- [ ] Should the fasting Live Activity show the **current phase** (fasting/eating) or always be in the "fasting" phase only? (i.e., do we also show a Live Activity during the *eating window*?) → Likely fasting-phase only; eating window countdown adds less urgency and extends the activity for 8+ hours
- [ ] Should the breathing Live Activity start automatically when the user taps "Start" in `StressLabView`, or only on an explicit opt-in toggle? → Auto-start is more natural for an exercise; user can dismiss from Dynamic Island
- [ ] Do we need a `FeedbackGenerator` haptic when the Live Activity starts/ends? (Existing app uses `HapticService.impact(.light)` on key interactions)
- [ ] How does the `ActivityAttributes` struct get shared between the app target and widget extension? → Option C (Target Membership) preferred — verify existing widget struct sharing pattern first
- [ ] Should `ActivityManager` be injected as `@EnvironmentObject` or accessed as a singleton? → `@EnvironmentObject` is cleaner (consistent with app architecture); `FastingService` is already a `@StateObject` in the view hierarchy

---

## Recommendation

**Approach 4: Phased — Fasting MVP first, Breathing in polish pass.**

**F7.0 (MVP)**:
1. `FastingActivityAttributes` + `ContentState` (shared via Target Membership)
2. `ActivityManager` — observes `FastingService.currentState`, manages `Activity<FastingActivityAttributes>` lifecycle
3. `FastingLiveActivityView` — Lock Screen banner + Dynamic Island (compact / minimal / expanded)
4. Wire `ActivityManager` into `FastingService` transitions (`.eating` → `.fasting` → start activity, `.fasting` → `.eating` / broken → end activity)
5. `NSSupportsLiveActivities` in Info.plist + ActivityKit capability
6. Reconnect to existing activities on app launch (for kill/relaunch resilience)

**F7.1 (Polish — ship in same feature):**
7. `BreathingActivityAttributes` + `BreathingLiveActivityView` — compact DI phase display
8. Wire to `InterventionTimer` — start on breathing session begin, update on phase transitions, end on complete

**F7.2 (Optional / Future):**
- Hydration streak: simple Lock Screen progress bar, triggered from the hydration log

Rationale: Fasting is the highest-value case, has the cleanest start/end lifecycle, and avoids ActivityKit rate-limit risk. The phased approach ensures we can ship and validate device behavior before adding the breathing complexity.

---

## Research References

- Roadmap: `Docs/02_Planning/260406-10-feature-roadmap.md` (F7)
- F1 Fasting plan (RESOLVED): `Docs/02_Planning/Specs/260406-fasting-timer-plan-RESOLVED.md`
- F1 Brainstorm: `Docs/01_Brainstorming/260406-fasting-timer-brainstorm.md`
- Stress widget plan: `Docs/02_Planning/Specs/260405-stress-widget-plan-RESOLVED.md` (WidgetKit sharing pattern)
- Apple Developer: ActivityKit documentation — `developer.apple.com/documentation/activitykit`
- Apple Developer: Displaying Live Activities on the Lock Screen and in the Dynamic Island
- `WellPlate/Core/Services/FastingService.swift` — `FastingState` enum, timer/notification coordinator
- `WellPlateWidget/WellPlateWidgetBundle.swift` — existing widget bundle (add `ActivityConfiguration` here)
- `WellPlate/Core/Services/WidgetRefreshHelper.swift` — existing widget/app data bridge pattern
