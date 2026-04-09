# Strategy: F7 — Live Activities (ActivityKit)

**Date**: 2026-04-08
**Source**: `Docs/01_Brainstorming/260408-live-activities-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**Phased delivery — Fasting Live Activity MVP (F7.0), then Breathing Session Live Activity polish (F7.1).**

Ship a `FastingActivityAttributes`-based Live Activity that shows the fasting countdown on Lock Screen and Dynamic Island. The `ActivityManager` service observes `FastingService.currentState` transitions and manages the `Activity<FastingActivityAttributes>` lifecycle. Breathing session Live Activity (via `InterventionTimer`) follows as a same-branch polish pass. Hydration is deferred entirely.

---

## Rationale

**Why Approach 4 (Phased) over alternatives:**

- **Over fasting-only (Approach 1)**: Breathing sessions are high-value for guided breathwork (user glances at DI while eyes closed), but they carry ActivityKit update-budget risk. Phasing lets us validate the fasting path first and add breathing once the ActivityKit infrastructure is proven. No code is wasted — the `ActivityManager` designed for fasting naturally extends to a second `ActivityAttributes` type.

- **Over multi-type simultaneous (Approach 2)**: Shipping both types at once doubles the view surface in the widget extension before we've validated any device behavior. The phased approach achieves the same end state with lower risk per step.

- **Over unified single type (Approach 3)**: A discriminated union `ContentState` enum with associated values is more complex to maintain and prevents two activities from running simultaneously (e.g., user could be fasting AND doing a breathing session). Two separate `ActivityAttributes` types are cleaner and match ActivityKit's intended design.

**Key trade-off accepted**: If the polish pass (F7.1) doesn't happen, breathing sessions don't get a Live Activity. This is acceptable — breathing sessions already have a full-screen timer UI (`SighSessionView`, `PMRSessionView`), so the Live Activity is enhancement, not essential.

---

## Affected Files & Components

### New Files

| File | Description |
|---|---|
| `WellPlate/Widgets/FastingActivityAttributes.swift` | `ActivityAttributes` struct + `ContentState`. Shared between main app and widget extension via **dual target membership** (follows `SharedStressData.swift` pattern) |
| `WellPlate/Core/Services/ActivityManager.swift` | `@MainActor ObservableObject` — observes `FastingService.currentState`, starts/updates/ends `Activity<FastingActivityAttributes>`. Reconnects on app launch via `Activity<T>.activities` |
| `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift` | Lock Screen banner + Dynamic Island layouts (compact leading/trailing, minimal, expanded) |

### F7.1 New Files (Breathing — polish pass)

| File | Description |
|---|---|
| `WellPlate/Widgets/BreathingActivityAttributes.swift` | `ActivityAttributes` for breathing sessions (dual target membership) |
| `WellPlateWidget/LiveActivities/BreathingLiveActivityView.swift` | DI and Lock Screen views for breathing |

### Modified Files

| File | Change |
|---|---|
| `WellPlateWidget/WellPlateWidgetBundle.swift` | Add `ActivityConfiguration<FastingActivityAttributes>` (and later `BreathingActivityAttributes`) to the widget bundle body |
| `WellPlate/Core/Services/FastingService.swift` | Add `onStateTransition` callback (or delegate) that `ActivityManager` hooks into for `.eating → .fasting` and `.fasting → .eating` transitions |
| `WellPlate/Features + UI/Stress/Views/FastingView.swift` | Inject `ActivityManager` to handle session-lifecycle-triggered activity start/end calls |
| `WellPlate/App/WellPlateApp.swift` | Create `ActivityManager` as `@StateObject`, inject as `@EnvironmentObject` |
| `Info.plist` (or build settings) | Add `NSSupportsLiveActivities = YES` |

### F7.1 Modified Files

| File | Change |
|---|---|
| `WellPlate/Core/Services/InterventionTimer.swift` | Add `onComplete`/`onPhaseStart` hooks for `ActivityManager` to observe phase transitions |
| `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` | Start/end breathing Live Activity on session start/completion |
| `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` | Same as SighSessionView |

---

## Architectural Direction

### ActivityAttributes Sharing

`FastingActivityAttributes.swift` lives in `WellPlate/Widgets/` — the same directory as `SharedStressData.swift`. It gets **dual target membership** (main app + WellPlateWidget extension) in Xcode, exactly as `SharedStressData.swift` does today. This is the project's established pattern for cross-target types. No shared framework, no duplication.

### ActivityManager Design

```
ActivityManager (@MainActor ObservableObject)
├── @Published activeFastingActivity: Activity<FastingActivityAttributes>?
├── @Published activeBreathingActivity: Activity<BreathingActivityAttributes>?  (F7.1)
│
├── startFastingActivity(schedule:targetEndAt:)
│   → Activity<FastingActivityAttributes>.request(attributes:content:pushType: nil)
│
├── endFastingActivity(completed:)
│   → await activity.end(content:dismissalPolicy: .default)
│
├── reconnectOnLaunch()
│   → for activity in Activity<FastingActivityAttributes>.activities { ... }
│
└── (F7.1) startBreathingActivity / endBreathingActivity
```

`ActivityManager` does **NOT** hold a reference to `FastingService`. Instead, `FastingView` (which already observes both `FastingService` and `modelContext`) calls `ActivityManager` methods when it detects state transitions. This keeps the same "views own lifecycle" pattern established in the F1 plan (H3 resolution).

### Timer Display Strategy

The critical insight: **never poll from the app to update the countdown display**. Use SwiftUI's built-in timer text:

```swift
// In the Live Activity view:
Text(timerInterval: startDate...targetEndAt, countsDown: true)
```

The OS renders the countdown natively on Lock Screen and Dynamic Island without any app-side `activity.update()` calls. The only updates needed are on **state transitions**:
1. Fast begins → `startFastingActivity()`
2. Fast completes on time → `endFastingActivity(completed: true)`
3. Fast broken early → `endFastingActivity(completed: false)`
4. Schedule changed during active fast → end old activity, optionally start new one

This means `ActivityManager` sends **at most 3 updates per fasting session** (start, optional mid-session, end) — well within ActivityKit's rate budget.

### Widget Bundle Integration

```swift
// WellPlateWidgetBundle.swift (after change)
@main
struct WellPlateWidgetBundle: WidgetBundle {
    var body: some Widget {
        StressWidget()
        FastingLiveActivity()   // ActivityConfiguration<FastingActivityAttributes>
        // BreathingLiveActivity() — F7.1
    }
}
```

`ActivityConfiguration` is a `Widget` conformer, so it slots naturally into the existing `WidgetBundle`.

### Entitlement / Info.plist

Add `NSSupportsLiveActivities = YES` to the app's `Info.plist`. No new entitlement file key needed — ActivityKit uses the Info.plist key, not an entitlement. The widget extension does NOT need this key (only the main app that calls `Activity.request(...)` does).

---

## Design Constraints

1. **`FastingActivityAttributes` must be `Codable`, `Hashable`, and `Sendable`** — no SwiftData models, HealthKit types, or UIKit/SwiftUI types in the struct. Use primitives only (`String`, `Double`, `Date`, `Bool`).

2. **No per-second activity updates** — use `Text(timerInterval:countsDown:)` for countdown display. Only call `activity.update()` on state transitions.

3. **Guard `areActivitiesEnabled`** before calling `Activity.request(...)` — wrap in `ActivityAuthorizationInfo().areActivitiesEnabled` check. If disabled, fall back silently to the existing notification-based flow (already implemented in `FastingService`).

4. **Reconnect on launch** — `ActivityManager.reconnectOnLaunch()` must iterate `Activity<FastingActivityAttributes>.activities` on app foreground to reconnect to any live activity that persisted across an app kill.

5. **Dynamic Island layouts must degrade gracefully** — devices without Dynamic Island (< iPhone 14 Pro) only see the Lock Screen banner. Both are defined in the same `ActivityConfiguration` view builder with `context.isStale` handling.

6. **Follow existing visual language** — Lock Screen views use the app's accent colors (`.orange` for fasting state, `.green` for eating state). Dynamic Island expanded view uses a circular progress arc consistent with `FastingView`'s timer ring.

7. **`FastingView` remains the lifecycle owner** — `ActivityManager` is a service that executes start/end; `FastingView` decides WHEN to call those methods (same "views own SwiftData + lifecycle" pattern from F1 plan).

8. **F7.1 breathing updates must respect ActivityKit rate limits** — breathing phases change every 4–6 seconds. Use `timerInterval` for phase countdown display and only call `activity.update()` on phase transitions (not per-tick). `InterventionTimer` fires `onPhaseStart` ~10–20 times per session — this is within budget.

---

## Non-Goals

- **No hydration Live Activity** — deferred indefinitely. Hydration is a counter, not a countdown; the Live Activity value is lower than fasting/breathing.
- **No push-based ActivityKit updates** — no APNs token registration, no remote push updates. All updates happen from the app process. Remote updates are Phase 4 complexity.
- **No Apple Watch integration** — F8 scope. `ActivityManager` stays on the phone.
- **No "eating window" Live Activity** — only the fasting phase gets a Live Activity. Eating window countdown is lower urgency and would extend the activity for 8+ hours, which is user-annoying.
- **No `FastingService` refactoring** — `ActivityManager` is additive; `FastingService` retains its current interface. The only change is adding a callback hook for state transitions.
- **No shared Swift Package** — dual target membership (established pattern) is sufficient for 1–2 small `ActivityAttributes` files.

---

## Open Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **ActivityKit not available on iOS < 16.2** | Low | `if #available(iOS 16.2, *)` guard. App targets iOS 16+, so only a narrow window of users miss it. Fallback = existing notifications. |
| **Device testing required** | Medium | Simulator doesn't render Live Activities. Must test on physical device. All layout/interaction testing needs device runs. |
| **Breathing phase update budget (F7.1)** | Medium | Use `timerInterval` for per-second display. Only explicit `activity.update()` on phase transitions (~10–20 per session). Apple's budget is ~once per second, so ~15 updates over 10 min is safe. |
| **Dual target membership requires manual Xcode step** | Low | Document the Target Membership checkbox step clearly in the plan. Same step was done for `SharedStressData.swift`. |
| **`WellPlateWidgetBundle` must remain under 5 `Widget` entries** | Low | Currently 1 (StressWidget). Adding 2 (fasting + breathing) = 3 total. Well under limit. |
| **User disables Live Activities in Settings** | Low | `ActivityAuthorizationInfo().areActivitiesEnabled` check before request. Silent fallback — no error UI needed (notifications still work). |
