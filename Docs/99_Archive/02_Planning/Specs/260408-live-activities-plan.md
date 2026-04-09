# Implementation Plan: F7 — Live Activities (ActivityKit)

**Date**: 2026-04-08
**Source**: `Docs/02_Planning/Specs/260408-live-activities-strategy.md`
**Status**: Draft

---

## Overview

Add Live Activities to WellPlate so fasting countdowns appear on Lock Screen and Dynamic Island. A new `ActivityManager` service (app-scoped) manages `Activity<FastingActivityAttributes>` lifecycle. `FastingView` calls `ActivityManager` methods on fasting state transitions. F7.1 adds breathing session Live Activities via `BreathingActivityAttributes` + integration with `InterventionTimer`. Three new files for MVP, two more for F7.1, three existing files modified.

---

## Requirements

1. Fasting countdown visible on Lock Screen + Dynamic Island during an active fast
2. Dynamic Island: compact (fork.knife icon + timer), minimal (icon), expanded (progress arc + labels)
3. Lock Screen: progress ring + schedule label + time remaining + eat window time
4. Live Activity starts automatically when fasting state begins (`eating → fasting` transition)
5. Live Activity ends when fast completes, is broken, or schedule is deactivated
6. Reconnect to existing Live Activities on app relaunch (kill-resilience)
7. Graceful degradation: `areActivitiesEnabled` guard, silent fallback to notifications
8. (F7.1) Breathing session Live Activity shows phase name + countdown during Sigh/PMR sessions

---

## Architecture Changes

### New Files (MVP — F7.0)

| File | Description |
|---|---|
| `WellPlate/Widgets/FastingActivityAttributes.swift` | `ActivityAttributes` + `ContentState` struct. Dual target membership (main app + WellPlateWidget) — same pattern as `SharedStressData.swift` |
| `WellPlate/Core/Services/ActivityManager.swift` | `@MainActor ObservableObject` — manages `Activity<FastingActivityAttributes>` lifecycle (start/end/reconnect) |
| `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift` | `ActivityConfiguration<FastingActivityAttributes>` — Lock Screen banner + Dynamic Island (compact, minimal, expanded) |

### New Files (F7.1 — Breathing)

| File | Description |
|---|---|
| `WellPlate/Widgets/BreathingActivityAttributes.swift` | `ActivityAttributes` + `ContentState` for breathing sessions. Dual target membership |
| `WellPlateWidget/LiveActivities/BreathingLiveActivityView.swift` | `ActivityConfiguration<BreathingActivityAttributes>` — DI compact + Lock Screen |

### Modified Files

| File | Change |
|---|---|
| `WellPlateWidget/WellPlateWidgetBundle.swift` | Add `FastingLiveActivity()` (MVP) and `BreathingLiveActivity()` (F7.1) to widget bundle body |
| `WellPlateWidget/Info.plist` | Add `NSSupportsLiveActivities = YES` key |
| `WellPlate/Features + UI/Stress/Views/FastingView.swift` | Accept `ActivityManager` via `@EnvironmentObject`; call `startFastingActivity()` / `endFastingActivity()` in `handleStateTransition()` and `breakCurrentFast()` |
| `WellPlate/App/WellPlateApp.swift` | Create `ActivityManager` as `@StateObject`; inject as `.environmentObject()` on `RootView` |
| `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` | (F7.1) Accept `ActivityManager` via `@EnvironmentObject`; start/end breathing activity on session start/complete |
| `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` | (F7.1) Same as SighSessionView |

---

## Implementation Steps

### Phase 1: Configuration

#### Step 1. Add `NSSupportsLiveActivities` to widget Info.plist
**File**: `WellPlateWidget/Info.plist` (MODIFY)

**Action**: Add the following key-value pair inside the top-level `<dict>`:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

**Also required (manual Xcode step)**:
- Open the **WellPlate** main app target in Xcode → General tab → check "Supports Live Activities"
- This adds `INFOPLIST_KEY_NSSupportsLiveActivities = YES` to the build settings (the main app uses `GENERATE_INFOPLIST_FILE = YES`, so there's no physical Info.plist to edit)

- **Why**: ActivityKit requires this key in both the main app (to call `Activity.request()`) and the widget extension (to render `ActivityConfiguration`). The widget has a physical Info.plist; the main app uses auto-generated.
- **Dependencies**: None
- **Risk**: Low

---

### Phase 2: Shared Data Types

#### Step 2. Create `FastingActivityAttributes`
**File**: `WellPlate/Widgets/FastingActivityAttributes.swift` (NEW)

```swift
import ActivityKit
import Foundation

struct FastingActivityAttributes: ActivityAttributes {

    // Static data — set once at activity start, never changes
    var scheduleLabel: String       // e.g. "16:8 Fast"

    // Dynamic data — updated on state transitions only
    struct ContentState: Codable, Hashable, Sendable {
        var fastStartDate: Date     // when the fast began
        var targetEndDate: Date     // when the fast should end (eat window opens)
        var progress: Double        // 0.0–1.0
        var isCompleted: Bool       // true = fast ended naturally
        var isBroken: Bool          // true = user broke the fast early
    }
}
```

**Key design decisions**:
- `fastStartDate` + `targetEndDate` are full `Date` values — Live Activity views use `Text(timerInterval: fastStartDate...targetEndDate, countsDown: true)` for OS-managed countdown rendering
- `progress` is included for the circular arc in the expanded/Lock Screen view — computed from elapsed time, but passed explicitly so the view doesn't recompute
- `isCompleted` and `isBroken` are terminal states used in the "ending" view (shown for ~30s before dismissal)
- All fields are `Codable`, `Hashable`, and `Sendable` — no SwiftData, HealthKit, or SwiftUI types

**Target membership**: After creating this file, open Xcode → select the file → File Inspector → check both **WellPlate** and **WellPlateWidget** targets. This is the same pattern used for `SharedStressData.swift` (file ref `AB100005` is in the WellPlateWidget Sources build phase `AB100011`).

- **Why**: ActivityKit requires the same `ActivityAttributes` type in both the app (which calls `Activity.request()`) and the widget extension (which renders `ActivityConfiguration`)
- **Dependencies**: None
- **Risk**: Low

---

### Phase 3: ActivityManager Service

#### Step 3. Create `ActivityManager`
**File**: `WellPlate/Core/Services/ActivityManager.swift` (NEW)

```swift
import Foundation
import ActivityKit

@MainActor
final class ActivityManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isFastingActivityActive = false
    @Published private(set) var liveActivitiesDisabled = false

    // MARK: - Private

    private var fastingActivity: Activity<FastingActivityAttributes>?

    // MARK: - Init

    init() {
        reconnectFastingActivity()
    }

    // MARK: - Fasting Activity

    /// Start a fasting Live Activity. Called when FastingView detects eating → fasting transition.
    func startFastingActivity(
        scheduleLabel: String,
        fastStartDate: Date,
        targetEndDate: Date
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveActivitiesDisabled = true
            return
        }
        liveActivitiesDisabled = false

        // End any existing fasting activity before starting a new one
        if fastingActivity != nil {
            Task {
                await endFastingActivityInternal(completed: false, broken: false)
            }
        }

        let attributes = FastingActivityAttributes(scheduleLabel: scheduleLabel)
        let now = Date()
        let elapsed = now.timeIntervalSince(fastStartDate)
        let total = targetEndDate.timeIntervalSince(fastStartDate)
        let progress = total > 0 ? min(elapsed / total, 1.0) : 0

        let state = FastingActivityAttributes.ContentState(
            fastStartDate: fastStartDate,
            targetEndDate: targetEndDate,
            progress: progress,
            isCompleted: false,
            isBroken: false
        )

        let content = ActivityContent(state: state, staleDate: targetEndDate.addingTimeInterval(60))

        do {
            fastingActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            isFastingActivityActive = true
        } catch {
            // Silently fail — notifications are the fallback
            isFastingActivityActive = false
        }
    }

    /// End the fasting Live Activity. Called when fast completes or is broken.
    func endFastingActivity(completed: Bool) {
        Task {
            await endFastingActivityInternal(completed: completed, broken: !completed)
        }
    }

    private func endFastingActivityInternal(completed: Bool, broken: Bool) async {
        guard let activity = fastingActivity else { return }

        var finalState = activity.content.state
        finalState.isCompleted = completed
        finalState.isBroken = broken
        finalState.progress = completed ? 1.0 : finalState.progress

        let content = ActivityContent(state: finalState, staleDate: .now)
        await activity.end(content, dismissalPolicy: .default)

        fastingActivity = nil
        isFastingActivityActive = false
    }

    /// Reconnect to any live fasting activity that survived an app kill.
    private func reconnectFastingActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveActivitiesDisabled = true
            return
        }

        let activities = Activity<FastingActivityAttributes>.activities
        if let existing = activities.first {
            fastingActivity = existing
            isFastingActivityActive = true

            // If the activity's target end date has passed, end it
            if existing.content.state.targetEndDate < Date() {
                Task {
                    await endFastingActivityInternal(completed: true, broken: false)
                }
            }
        }
    }
}
```

**Key design decisions**:
- `@MainActor` — consistent with all ViewModels and services in the project
- `reconnectFastingActivity()` called from `init()` — catches activities that persisted across app kills
- `startFastingActivity()` checks `areActivitiesEnabled` before requesting — silent no-op if disabled
- No SwiftData dependency — just like `FastingService`, `ActivityManager` is a pure coordinator
- `pushType: nil` — no remote push updates for MVP
- `staleDate: targetEndDate + 60s` — iOS shows "stale" UI 60s after target end, then auto-dismisses
- `endFastingActivity(completed:)` has a public sync interface that dispatches async work internally
- Error handling is silent — `Activity.request()` throws if budget exhausted; existing notification flow is the fallback

- **Why**: App-scoped service that manages Live Activity lifecycle. Must survive across sheet presentations (unlike `FastingService` which is `@StateObject` in `FastingView`).
- **Dependencies**: Step 2 (`FastingActivityAttributes`)
- **Risk**: Medium — ActivityKit APIs are async and can throw; device testing required

---

### Phase 4: Live Activity Views (Widget Extension)

#### Step 4. Create `FastingLiveActivityView`
**File**: `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift` (NEW)

```swift
import ActivityKit
import WidgetKit
import SwiftUI

struct FastingLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            // LOCK SCREEN view
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED — tapped/long-pressed
                DynamicIslandExpandedRegion(.leading) {
                    fastingProgressRing(progress: context.state.progress)
                        .frame(width: 52, height: 52)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.scheduleLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        if context.state.isCompleted {
                            Text("Fast complete")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        } else if context.state.isBroken {
                            Text("Fast ended early")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                        } else {
                            Text(timerInterval: Date.now...context.state.targetEndDate,
                                 countsDown: true)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 24)
                }
            } compactLeading: {
                // COMPACT — collapsed, leading pill
                Image(systemName: "fork.knife")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            } compactTrailing: {
                // COMPACT — collapsed, trailing pill
                if context.state.isCompleted || context.state.isBroken {
                    Image(systemName: context.state.isCompleted ? "checkmark" : "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(context.state.isCompleted ? .green : .red)
                } else {
                    Text(timerInterval: Date.now...context.state.targetEndDate,
                         countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.orange)
                        .frame(width: 40)
                }
            } minimal: {
                // MINIMAL — when competing with another Live Activity
                Image(systemName: "fork.knife")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<FastingActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            // Progress ring
            fastingProgressRing(progress: context.state.progress)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.scheduleLabel)
                    .font(.system(size: 14, weight: .semibold))

                if context.state.isCompleted {
                    Text("Fast complete ✓")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.green)
                } else if context.state.isBroken {
                    Text("Fast ended early")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.red)
                } else {
                    Text(timerInterval: Date.now...context.state.targetEndDate,
                         countsDown: true)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    let formatter = Date.FormatStyle.dateTime.hour().minute()
                    Text("Eat window opens at \(context.state.targetEndDate.formatted(formatter))")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.7))
    }

    // MARK: - Progress Ring

    @ViewBuilder
    private func fastingProgressRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 4)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange.gradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.orange)
        }
    }
}
```

**Layout rationale**:
- **Lock Screen**: mirrors `FastingView`'s timer card layout (ring on left, text stack on right). Uses `.activityBackgroundTint` for dark background.
- **Compact**: fork.knife icon (leading) + countdown timer (trailing). Matches the minimal "fasting → time left" glance pattern.
- **Expanded**: progress ring (leading) + schedule label + large countdown (center). Visible when user taps the island.
- **Minimal**: just the icon — shown when competing with another Live Activity (e.g., music playback).
- Timer uses `Text(timerInterval:countsDown:)` — the OS renders the countdown without any app updates.
- Terminal states (`isCompleted` / `isBroken`) show static text instead of timer — displayed for ~30s before dismissal via `.default` policy.

- **Why**: This is the user-visible widget surface — the reason F7 exists
- **Dependencies**: Step 2 (`FastingActivityAttributes`)
- **Risk**: Medium — Dynamic Island layouts require device testing; Simulator does not render them

---

#### Step 5. Register Live Activity in Widget Bundle
**File**: `WellPlateWidget/WellPlateWidgetBundle.swift` (MODIFY)

**Current** (line 4–9):
```swift
@main
struct WellPlateWidgetBundle: WidgetBundle {
    var body: some Widget {
        StressWidget()
    }
}
```

**After**:
```swift
import ActivityKit

@main
struct WellPlateWidgetBundle: WidgetBundle {
    var body: some Widget {
        StressWidget()
        FastingLiveActivity()
    }
}
```

- **Action**: Add `import ActivityKit` at the top; add `FastingLiveActivity()` to the widget bundle body
- **Why**: `ActivityConfiguration` conforms to `Widget` and must be declared in the `WidgetBundle` for iOS to discover it
- **Dependencies**: Step 4
- **Risk**: Low

**Verify**: Build the widget extension target after this step:
```bash
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

---

### Phase 5: Integration (Wire into FastingView)

#### Step 6. Inject `ActivityManager` from `WellPlateApp`
**File**: `WellPlate/App/WellPlateApp.swift` (MODIFY)

**Add `@StateObject` and inject as `@EnvironmentObject`**:

**Current** (lines 1–2, 30–36):
```swift
import SwiftUI
import SwiftData
...
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [...])
    }
```

**After**:
```swift
import SwiftUI
import SwiftData
import ActivityKit
...
    @StateObject private var activityManager = ActivityManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(activityManager)
        }
        .modelContainer(for: [...])
    }
```

- **Action**: Add `import ActivityKit`, create `ActivityManager` as `@StateObject`, inject via `.environmentObject()`
- **Why**: `ActivityManager` must be app-scoped (survives across sheet opens/closes) to reconnect to existing Live Activities on app launch. `@EnvironmentObject` makes it available to any descendant view without manual threading.
- **Dependencies**: Step 3
- **Risk**: Low — `@EnvironmentObject` is a well-established SwiftUI pattern

---

#### Step 7. Hook `ActivityManager` into `FastingView`
**File**: `WellPlate/Features + UI/Stress/Views/FastingView.swift` (MODIFY)

**Change 1 — Add `@EnvironmentObject`** (after line 22, below `@StateObject private var fastingService`):
```swift
@EnvironmentObject private var activityManager: ActivityManager
```

**Change 2 — Update `handleStateTransition()`** (lines 331–349):

**Current**:
```swift
private func handleStateTransition(from oldState: FastingState, to newState: FastingState) {
    guard let schedule else { return }

    // Eating → Fasting: create new session
    if oldState.isEating && newState.isFasting && activeSession == nil {
        let fastStart = fastingService.mostRecentEatWindowEnd(for: schedule)
        let fastEnd = fastingService.nextEatWindowStart(for: schedule)
        let session = FastingSession(startedAt: fastStart, targetEndAt: fastEnd,
                                     scheduleType: schedule.resolvedScheduleType)
        modelContext.insert(session)
    }

    // Fasting → Eating: complete active session
    if oldState.isFasting && newState.isEating, let session = activeSession {
        session.completed = true
        session.actualEndAt = .now
        HapticService.notify(.success)
    }
}
```

**After**:
```swift
private func handleStateTransition(from oldState: FastingState, to newState: FastingState) {
    guard let schedule else { return }

    // Eating → Fasting: create new session + start Live Activity
    if oldState.isEating && newState.isFasting && activeSession == nil {
        let fastStart = fastingService.mostRecentEatWindowEnd(for: schedule)
        let fastEnd = fastingService.nextEatWindowStart(for: schedule)
        let session = FastingSession(startedAt: fastStart, targetEndAt: fastEnd,
                                     scheduleType: schedule.resolvedScheduleType)
        modelContext.insert(session)

        activityManager.startFastingActivity(
            scheduleLabel: schedule.resolvedScheduleType.label + " Fast",
            fastStartDate: fastStart,
            targetEndDate: fastEnd
        )
    }

    // Fasting → Eating: complete active session + end Live Activity
    if oldState.isFasting && newState.isEating, let session = activeSession {
        session.completed = true
        session.actualEndAt = .now
        HapticService.notify(.success)
        activityManager.endFastingActivity(completed: true)
    }
}
```

**Change 3 — Update `breakCurrentFast()`** (lines 351–355):

**Current**:
```swift
private func breakCurrentFast() {
    guard let session = activeSession else { return }
    session.completed = false
    session.actualEndAt = .now
}
```

**After**:
```swift
private func breakCurrentFast() {
    guard let session = activeSession else { return }
    session.completed = false
    session.actualEndAt = .now
    activityManager.endFastingActivity(completed: false)
}
```

**Change 4 — Start Live Activity on first configure if already fasting** (in `configureService()`, lines 324–329):

**Current**:
```swift
private func configureService() {
    if let schedule {
        fastingService.configure(schedule: schedule, activeSession: activeSession)
        previousState = fastingService.currentState
    }
}
```

**After**:
```swift
private func configureService() {
    if let schedule {
        fastingService.configure(schedule: schedule, activeSession: activeSession)
        previousState = fastingService.currentState

        // If fasting and no Live Activity running, start one (e.g. after app relaunch)
        if fastingService.currentState.isFasting && !activityManager.isFastingActivityActive {
            if let session = activeSession {
                activityManager.startFastingActivity(
                    scheduleLabel: schedule.resolvedScheduleType.label + " Fast",
                    fastStartDate: session.startedAt,
                    targetEndDate: session.targetEndAt
                )
            }
        }
    }
}
```

- **Why**: This ensures a Live Activity is started when the user opens `FastingView` during an active fast that was started before `ActivityManager` was created (e.g., app was reinstalled, or first use after F7 update)
- **Dependencies**: Steps 3, 6
- **Risk**: Medium — must avoid double-starting activities. `startFastingActivity()` already checks for and ends existing activities before creating new ones, so this is safe.

**Verify**: Build after this step:
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```

---

### Phase 6: F7.1 — Breathing Session Live Activity

#### Step 8. Create `BreathingActivityAttributes`
**File**: `WellPlate/Widgets/BreathingActivityAttributes.swift` (NEW)

```swift
import ActivityKit
import Foundation

struct BreathingActivityAttributes: ActivityAttributes {

    // Static data
    var sessionName: String          // e.g. "Physiological Sigh", "PMR"
    var totalCycles: Int             // e.g. 3 for sigh, varies for PMR

    // Dynamic data — updated on phase transitions
    struct ContentState: Codable, Hashable, Sendable {
        var phaseName: String        // e.g. "First inhale", "Long exhale", "Tense shoulders"
        var phaseEndDate: Date       // when the current phase ends
        var currentCycle: Int        // 1-based
        var totalProgress: Double    // 0.0–1.0 across all phases
        var isCompleted: Bool        // session finished
    }
}
```

**Target membership**: Same dual-target pattern — add to both WellPlate and WellPlateWidget targets in Xcode.

- **Why**: Separate `ActivityAttributes` type (not a unified enum) so breathing and fasting can run simultaneously
- **Dependencies**: None
- **Risk**: Low

---

#### Step 9. Create `BreathingLiveActivityView`
**File**: `WellPlateWidget/LiveActivities/BreathingLiveActivityView.swift` (NEW)

```swift
import ActivityKit
import WidgetKit
import SwiftUI

struct BreathingLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreathingActivityAttributes.self) { context in
            // LOCK SCREEN
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: context.state.totalProgress)
                        .stroke(Color.indigo.gradient,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "wind")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.indigo)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.sessionName)
                        .font(.system(size: 13, weight: .semibold))

                    if context.state.isCompleted {
                        Text("Session complete")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Text(context.state.phaseName)
                            .font(.system(size: 17, weight: .bold))

                        Text("Cycle \(context.state.currentCycle) of \(context.attributes.totalCycles)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 6) {
                        Text(context.state.phaseName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .contentTransition(.opacity)

                        if !context.state.isCompleted {
                            Text(timerInterval: Date.now...context.state.phaseEndDate,
                                 countsDown: true)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Text("Cycle \(context.state.currentCycle)/\(context.attributes.totalCycles)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            } compactLeading: {
                Image(systemName: "wind")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.indigo)
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.phaseEndDate,
                     countsDown: true)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.indigo)
                    .frame(width: 36)
            } minimal: {
                Image(systemName: "wind")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.indigo)
            }
        }
    }
}
```

**Design notes**:
- Uses `.indigo` accent (matches `SighSessionView`'s existing color scheme)
- Phase name displayed prominently — the key info for a user with eyes closed during breathwork
- Phase countdown uses `Text(timerInterval:countsDown:)` — OS-managed, no app updates per second
- `contentTransition(.opacity)` on phase name for smooth animation when `activity.update()` changes the phase

- **Dependencies**: Step 8
- **Risk**: Medium — phase transitions every 4–6s mean ~10–20 `activity.update()` calls per session. iOS allows frequent updates but may throttle. Testing on device required.

---

#### Step 10. Add breathing to `ActivityManager`
**File**: `WellPlate/Core/Services/ActivityManager.swift` (MODIFY — add below fasting methods)

Add:
```swift
// MARK: - Breathing Activity

private var breathingActivity: Activity<BreathingActivityAttributes>?

func startBreathingActivity(sessionName: String, totalCycles: Int, firstPhaseName: String, firstPhaseEndDate: Date) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    let attributes = BreathingActivityAttributes(sessionName: sessionName, totalCycles: totalCycles)
    let state = BreathingActivityAttributes.ContentState(
        phaseName: firstPhaseName,
        phaseEndDate: firstPhaseEndDate,
        currentCycle: 1,
        totalProgress: 0,
        isCompleted: false
    )
    let content = ActivityContent(state: state, staleDate: nil)

    do {
        breathingActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
    } catch {
        breathingActivity = nil
    }
}

func updateBreathingActivity(phaseName: String, phaseEndDate: Date, currentCycle: Int, totalProgress: Double) {
    guard let activity = breathingActivity else { return }
    let state = BreathingActivityAttributes.ContentState(
        phaseName: phaseName,
        phaseEndDate: phaseEndDate,
        currentCycle: currentCycle,
        totalProgress: totalProgress,
        isCompleted: false
    )
    Task {
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }
}

func endBreathingActivity() {
    guard let activity = breathingActivity else { return }
    Task {
        var finalState = activity.content.state
        finalState.isCompleted = true
        finalState.totalProgress = 1.0
        await activity.end(ActivityContent(state: finalState, staleDate: .now), dismissalPolicy: .default)
        breathingActivity = nil
    }
}
```

- **Dependencies**: Step 8
- **Risk**: Low

---

#### Step 11. Update `WellPlateWidgetBundle` for breathing
**File**: `WellPlateWidget/WellPlateWidgetBundle.swift` (MODIFY)

Add `BreathingLiveActivity()` to the body:
```swift
var body: some Widget {
    StressWidget()
    FastingLiveActivity()
    BreathingLiveActivity()
}
```

- **Dependencies**: Step 9
- **Risk**: Low

---

#### Step 12. Wire breathing into `SighSessionView`
**File**: `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` (MODIFY)

**Change 1 — Add `@EnvironmentObject`** (after line 14):
```swift
@EnvironmentObject private var activityManager: ActivityManager
```

**Change 2 — Start breathing activity in `.onAppear`** (after `timer.start(phases: phases)` at line 87):
```swift
// Start Live Activity
let firstPhase = phases[0]
activityManager.startBreathingActivity(
    sessionName: "Physiological Sigh",
    totalCycles: 3,
    firstPhaseName: firstPhase.name,
    firstPhaseEndDate: Date().addingTimeInterval(firstPhase.duration)
)
```

**Change 3 — Update activity on phase transitions** — add to `.onAppear`, before `timer.start(phases:)`:
```swift
timer.onPhaseStart = { [phases] phase in
    let cycleNumber = (timer.currentPhaseIndex / 3) + 1
    activityManager.updateBreathingActivity(
        phaseName: phase.name,
        phaseEndDate: Date().addingTimeInterval(phase.duration),
        currentCycle: cycleNumber,
        totalProgress: timer.totalProgress
    )
}
```

**Change 4 — End activity on complete** — modify the existing `timer.onComplete` closure (line 82–84):

**Current**:
```swift
timer.onComplete = {
    saveSession(completed: true)
    withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
}
```

**After**:
```swift
timer.onComplete = {
    saveSession(completed: true)
    activityManager.endBreathingActivity()
    withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
}
```

**Change 5 — End activity on cancel** — modify the Cancel button action (line 72–74):

**Current**:
```swift
Button("Cancel") {
    saveSession(completed: false)
    dismiss()
}
```

**After**:
```swift
Button("Cancel") {
    saveSession(completed: false)
    activityManager.endBreathingActivity()
    dismiss()
}
```

- **Dependencies**: Steps 10, 3
- **Risk**: Low — additive changes only

---

#### Step 13. Wire breathing into `PMRSessionView`
**File**: `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` (MODIFY)

Apply the same 5 changes as Step 12, with:
- `sessionName: "PMR"` instead of `"Physiological Sigh"`
- `totalCycles` = number of PMR cycles (check the PMR phase array for the correct count)
- Cycle calculation adjusted for PMR phase grouping (check `PMRSessionView` phase structure — likely different from sigh's 3-phase-per-cycle)

- **Dependencies**: Steps 10, 3
- **Risk**: Low

---

## Testing Strategy

### Build Verification

All 4 targets must build clean:
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

### Manual Verification Flows (Device Required)

1. **Fasting Live Activity start**:
   - Configure a fasting schedule → wait for eating → fasting transition
   - Verify: Live Activity appears on Lock Screen with progress ring, schedule label, countdown
   - Verify: Dynamic Island shows fork.knife icon (leading) + countdown (trailing) in compact mode
   - Lock phone → check Lock Screen banner shows the countdown updating

2. **Fasting Live Activity end (completed)**:
   - Wait for fast to complete (or set a short schedule for testing)
   - Verify: Live Activity shows "Fast complete ✓" state for ~30s then dismisses
   - Verify: Dynamic Island shows checkmark icon

3. **Fasting Live Activity end (broken)**:
   - Open FastingView → tap "Break Fast" → confirm
   - Verify: Live Activity shows "Fast ended early" for ~30s then dismisses

4. **App kill resilience**:
   - Start a fast → Live Activity appears → kill the app
   - Verify: Lock Screen Live Activity continues showing countdown (OS-managed timer)
   - Relaunch app → open FastingView
   - Verify: `ActivityManager` reconnects to the existing activity (no duplicate)
   - If fast completed while app was killed → `ActivityManager.reconnectFastingActivity()` ends it

5. **Live Activities disabled**:
   - Go to Settings → WellPlate → Live Activities → toggle off
   - Start a new fast
   - Verify: no Live Activity appears, no error shown, notifications still work
   - Verify: `activityManager.liveActivitiesDisabled == true`

6. **No Dynamic Island device** (iPhone 13 or older):
   - Start a fast
   - Verify: Lock Screen banner appears correctly
   - Verify: no crash or error from Dynamic Island code paths

7. **(F7.1) Breathing Live Activity**:
   - Open Stress tab → toolbar menu → Interventions → start Sigh session
   - Verify: Dynamic Island shows "wind" icon + phase countdown
   - Verify: Phase name updates when phases transition ("First inhale" → "Second inhale" → "Long exhale")
   - Cancel session → verify Live Activity ends
   - Complete session → verify Live Activity shows "Session complete" then dismisses

8. **Concurrent fasting + breathing**:
   - Start a fast (Live Activity running) → start a breathing session
   - Verify: both Live Activities exist — iOS shows one in compact DI, other in minimal
   - End breathing → fasting Live Activity returns to compact DI

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Live Activities not testable in Simulator | Medium | All Live Activity layout testing requires device runs. Build verification still works in Simulator. |
| ActivityKit rate limiting for breathing phase updates | Medium | Use `Text(timerInterval:countsDown:)` for per-second countdown. Only explicit `activity.update()` on phase transitions (~10–20 per session). Well within budget. |
| `areActivitiesEnabled` returns false | Low | Silent fallback — existing notification flow from `FastingService` handles all alerts. No error UI needed. |
| Dual target membership requires manual Xcode step | Low | Same step was done for `SharedStressData.swift`. Document clearly in implementation instructions. |
| `Activity.request()` throws when budget exhausted | Low | Catch error silently. Budget is 5 concurrent activities — WellPlate uses at most 2. |
| `WellPlateApp` `@StateObject` creation before SwiftData ready | Low | `ActivityManager.init()` only accesses ActivityKit (not SwiftData). No ordering conflict. |
| `@EnvironmentObject` crash if not provided | Low | `ActivityManager` is injected at `WellPlateApp` level — all descendant views have access. Only risk: Xcode previews must inject it manually. |

---

## Success Criteria

### MVP (F7.0)
- [ ] Fasting Live Activity appears on Lock Screen when fasting state begins
- [ ] Dynamic Island shows compact (fork.knife + countdown), minimal (icon), and expanded (ring + labels) layouts
- [ ] Countdown uses `Text(timerInterval:countsDown:)` — no per-second app updates
- [ ] Live Activity ends with "complete" state when fast finishes on time
- [ ] Live Activity ends with "broken" state when user taps "Break Fast"
- [ ] `ActivityManager` reconnects to existing activities on app relaunch
- [ ] `areActivitiesEnabled` guard prevents crashes when user disables Live Activities
- [ ] `NSSupportsLiveActivities = YES` in both main app and widget extension Info.plist
- [ ] Build succeeds on all 4 targets

### F7.1 (Breathing)
- [ ] Breathing Live Activity starts when Sigh or PMR session begins
- [ ] Phase name updates on Dynamic Island with each phase transition
- [ ] Phase countdown uses `Text(timerInterval:countsDown:)` — no per-second updates
- [ ] Live Activity ends on session complete or cancel
- [ ] Fasting + Breathing can run simultaneously without conflict
- [ ] Widget bundle registers both `FastingLiveActivity` and `BreathingLiveActivity`
