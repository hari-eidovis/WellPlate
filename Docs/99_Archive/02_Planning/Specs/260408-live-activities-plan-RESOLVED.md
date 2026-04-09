# Implementation Plan: F7 — Live Activities (ActivityKit)

**Date**: 2026-04-08
**Source**: `Docs/02_Planning/Specs/260408-live-activities-strategy.md`
**Status**: RESOLVED

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|---|---|---|
| H1: `@EnvironmentObject` is novel — use singleton | HIGH | Replaced with `ActivityManager.shared` singleton. Removed `WellPlateApp.swift` modification (Step 6 deleted). All views use `ActivityManager.shared` directly. Consistent with `AppConfig.shared` pattern. |
| H2: iOS 16.2 availability guard is dead code | HIGH | Removed all `if #available(iOS 16.2, *)` references. Deployment target is 18.6 — ActivityKit is unconditionally available. Only `areActivitiesEnabled` check retained (user Settings toggle). |
| M1: Breathing `onPhaseStart` fires before activity exists | MEDIUM | Reordered: `startBreathingActivity()` now called *before* `timer.start(phases:)`. First `onPhaseStart` safely updates the already-existing activity. |
| M2: PMR cycle calculation unspecified | MEDIUM | Added explicit formula: `totalSteps = muscleGroups.count` (8), `currentStep = (timer.currentPhaseIndex / 2) + 1`. |
| M3: `totalCycles` naming is Sigh-specific | MEDIUM | Renamed to `totalSteps` / `currentStep`. Added `stepLabel: String` field ("Cycle" for Sigh, "Group" for PMR). View displays `"\(stepLabel) \(current)/\(total)"`. |
| M4: Unnecessary `import ActivityKit` in `WellPlateApp.swift` | MEDIUM | Removed — Step 6 deleted entirely (H1 resolution). No `WellPlateApp.swift` changes needed. |
| L1: No Xcode preview compatibility | LOW | Resolved by H1 — singleton has no `@EnvironmentObject` propagation concern. |
| L2: Inconsistent `staleDate` for breathing | LOW | Added `staleDate` for breathing: session start + total session duration + 30s. Ensures cleanup on crash. |
| L3: `endFastingActivityInternal` on already-ended activity | LOW | Acknowledged — safe per Apple docs. `Activity.end()` on ended activity is a no-op. No change. |
| Missing: Info.plist key for main app | — | Added explicit build setting key: `INFOPLIST_KEY_NSSupportsLiveActivities = YES` via Xcode GUI. |
| Missing: Widget ActivityKit framework linking | — | Acknowledged — modern Xcode auto-links from `import`. Noted as verify-during-build. |
| Missing: Live Activity tap deep link | — | Deferred to polish. Added note in non-goals. |
| Q1: Deep link on tap | QUESTION | Deferred — `wellplate://fasting` deep link is a polish item, not MVP. |
| Q2: PMR label | QUESTION | Resolved via M3 — `stepLabel` field distinguishes "Cycle" vs "Group". |

---

## Overview

Add Live Activities to WellPlate so fasting countdowns appear on Lock Screen and Dynamic Island. A new `ActivityManager` singleton service manages `Activity<FastingActivityAttributes>` lifecycle. `FastingView` calls `ActivityManager.shared` methods on fasting state transitions. F7.1 adds breathing session Live Activities via `BreathingActivityAttributes` + integration with `InterventionTimer`. Three new files for MVP, two more for F7.1, two existing files modified.

<!-- RESOLVED: H1 — Changed from "app-scoped @StateObject" to "singleton service". Removed "three existing files modified" → now two (no WellPlateApp.swift change). -->

---

## Requirements

1. Fasting countdown visible on Lock Screen + Dynamic Island during an active fast
2. Dynamic Island: compact (fork.knife icon + timer), minimal (icon), expanded (progress arc + labels)
3. Lock Screen: progress ring + schedule label + time remaining + eat window time
4. Live Activity starts automatically when fasting state begins (`eating → fasting` transition)
5. Live Activity ends when fast completes, is broken, or schedule is deactivated
6. Reconnect to existing Live Activities on app relaunch (kill-resilience)
7. Graceful degradation: `areActivitiesEnabled` guard prevents crashes when user disables Live Activities in Settings
8. (F7.1) Breathing session Live Activity shows phase name + countdown during Sigh/PMR sessions

<!-- RESOLVED: H2 — Requirement 7 no longer mentions iOS 16.2 availability. Only areActivitiesEnabled check. -->

---

## Architecture Changes

### New Files (MVP — F7.0)

| File | Description |
|---|---|
| `WellPlate/Widgets/FastingActivityAttributes.swift` | `ActivityAttributes` + `ContentState` struct. Dual target membership (main app + WellPlateWidget) — same pattern as `SharedStressData.swift` |
| `WellPlate/Core/Services/ActivityManager.swift` | Singleton (`ActivityManager.shared`) — manages `Activity<FastingActivityAttributes>` lifecycle (start/end/reconnect) |
| `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift` | `ActivityConfiguration<FastingActivityAttributes>` — Lock Screen banner + Dynamic Island (compact, minimal, expanded) |

<!-- RESOLVED: H1 — ActivityManager is now a singleton, not @MainActor ObservableObject injected via @EnvironmentObject -->

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
| `WellPlate/Features + UI/Stress/Views/FastingView.swift` | Call `ActivityManager.shared` methods in `handleStateTransition()`, `breakCurrentFast()`, and `configureService()` |
| `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` | (F7.1) Call `ActivityManager.shared` to start/update/end breathing activity on session lifecycle |
| `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` | (F7.1) Same as SighSessionView |

<!-- RESOLVED: H1 — Removed WellPlateApp.swift from modified files. No @StateObject or @EnvironmentObject injection needed. -->
<!-- RESOLVED: M4 — No import ActivityKit in WellPlateApp.swift. -->

---

## Implementation Steps

### Phase 1: Configuration

#### Step 1. Add `NSSupportsLiveActivities` to both targets
**File**: `WellPlateWidget/Info.plist` (MODIFY)

**Action**: Add the following key-value pair inside the top-level `<dict>`:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

**Main app target (manual Xcode step)**:
<!-- RESOLVED: Missing element — specified exact build setting key -->
- Open **WellPlate** target in Xcode → Build Settings → search "Supports Live Activities"
- Set `Supports Live Activities` to `YES`
- This adds `INFOPLIST_KEY_NSSupportsLiveActivities = YES` to the build settings (the main app uses `GENERATE_INFOPLIST_FILE = YES`, so this is the correct approach — no physical Info.plist to edit)

**Verify**: The widget extension may auto-link `ActivityKit.framework` from the `import ActivityKit` statement. If the build fails with a missing framework error, manually add `ActivityKit.framework` to WellPlateWidget → Build Phases → Link Binary With Libraries.

- **Why**: ActivityKit requires this key in both the main app (to call `Activity.request()`) and the widget extension (to render `ActivityConfiguration`)
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
- `progress` is included for the circular arc in the expanded/Lock Screen view
- `isCompleted` and `isBroken` are terminal states used in the "ending" view (shown for ~30s before dismissal)
- All fields are `Codable`, `Hashable`, and `Sendable` — no SwiftData, HealthKit, or SwiftUI types

**Target membership**: After creating this file, open Xcode → select the file → File Inspector → check both **WellPlate** and **WellPlateWidget** targets. This is the same pattern used for `SharedStressData.swift` (file ref `AB100005` is in the WellPlateWidget Sources build phase `AB100011`).

- **Why**: ActivityKit requires the same `ActivityAttributes` type in both the app (which calls `Activity.request()`) and the widget extension (which renders `ActivityConfiguration`)
- **Dependencies**: None
- **Risk**: Low

---

### Phase 3: ActivityManager Service

#### Step 3. Create `ActivityManager` (singleton)
**File**: `WellPlate/Core/Services/ActivityManager.swift` (NEW)

<!-- RESOLVED: H1 — Redesigned as singleton (ActivityManager.shared) instead of @MainActor ObservableObject injected via @EnvironmentObject. Consistent with AppConfig.shared pattern. No WellPlateApp.swift changes needed. -->
<!-- RESOLVED: H2 — Removed all if #available(iOS 16.2, *) guards. Deployment target is 18.6. Only areActivitiesEnabled check retained. -->

```swift
import Foundation
import ActivityKit

@MainActor
final class ActivityManager {

    // MARK: - Singleton

    static let shared = ActivityManager()

    // MARK: - State

    private(set) var isFastingActivityActive = false

    // MARK: - Private

    private var fastingActivity: Activity<FastingActivityAttributes>?

    // MARK: - Init

    private init() {
        reconnectFastingActivity()
    }

    // MARK: - Fasting Activity

    /// Start a fasting Live Activity. Called when FastingView detects eating → fasting transition.
    func startFastingActivity(
        scheduleLabel: String,
        fastStartDate: Date,
        targetEndDate: Date
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

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
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

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
- **Singleton** (`static let shared`, `private init()`) — consistent with `AppConfig.shared`, `APIClientFactory.shared`. Eliminates `@EnvironmentObject` propagation concerns and `WellPlateApp.swift` changes.
- `@MainActor` — consistent with all ViewModels and services in the project
- `reconnectFastingActivity()` called from `init()` — catches activities that persisted across app kills
- `areActivitiesEnabled` is the only guard (no iOS version check — deployment target is 18.6)
- `pushType: nil` — no remote push updates for MVP
- `staleDate: targetEndDate + 60s` — iOS shows "stale" UI 60s after target end, then auto-dismisses
- Error handling is silent — `Activity.request()` throws if budget exhausted; existing notification flow is the fallback

- **Why**: Manages Live Activity lifecycle across sheet opens/closes. Singleton survives the full app lifecycle and reconnects on launch.
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
                    Text("Fast complete")
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

- **Why**: This is the user-visible widget surface — the reason F7 exists
- **Dependencies**: Step 2 (`FastingActivityAttributes`)
- **Risk**: Medium — Dynamic Island layouts require device testing; Simulator does not render them

---

#### Step 5. Register Live Activity in Widget Bundle
**File**: `WellPlateWidget/WellPlateWidgetBundle.swift` (MODIFY)

**Current** (lines 1–9):
```swift
import WidgetKit
import SwiftUI

@main
struct WellPlateWidgetBundle: WidgetBundle {
    var body: some Widget {
        StressWidget()
    }
}
```

**After**:
```swift
import WidgetKit
import SwiftUI
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

<!-- RESOLVED: H1 — Step 6 (WellPlateApp.swift @StateObject + @EnvironmentObject injection) deleted entirely. ActivityManager.shared singleton eliminates the need for any WellPlateApp changes. -->

#### Step 6. Hook `ActivityManager.shared` into `FastingView`
**File**: `WellPlate/Features + UI/Stress/Views/FastingView.swift` (MODIFY)

<!-- RESOLVED: H1 — No @EnvironmentObject. Views call ActivityManager.shared directly. -->

**Change 1 — Update `handleStateTransition()`** (lines 331–349):

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

        ActivityManager.shared.startFastingActivity(
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
        ActivityManager.shared.endFastingActivity(completed: true)
    }
}
```

**Change 2 — Update `breakCurrentFast()`** (lines 351–355):

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
    ActivityManager.shared.endFastingActivity(completed: false)
}
```

**Change 3 — Start Live Activity on first configure if already fasting** (in `configureService()`, lines 324–329):

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

        // If fasting and no Live Activity running, start one (e.g. after app relaunch or first F7 use)
        if fastingService.currentState.isFasting && !ActivityManager.shared.isFastingActivityActive {
            if let session = activeSession {
                ActivityManager.shared.startFastingActivity(
                    scheduleLabel: schedule.resolvedScheduleType.label + " Fast",
                    fastStartDate: session.startedAt,
                    targetEndDate: session.targetEndAt
                )
            }
        }
    }
}
```

- **Why**: Ensures a Live Activity is started when the user opens `FastingView` during an active fast that was started before `ActivityManager` was created (e.g., first use after F7 update). The `!isFastingActivityActive` guard prevents double-starting. `startFastingActivity()` also checks for and ends existing activities before creating new ones, providing a second safety layer.
- **Dependencies**: Step 3
- **Risk**: Low

**Verify**: Build after this step:
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```

---

### Phase 6: F7.1 — Breathing Session Live Activity

#### Step 7. Create `BreathingActivityAttributes`
**File**: `WellPlate/Widgets/BreathingActivityAttributes.swift` (NEW)

<!-- RESOLVED: M3 — Renamed totalCycles/currentCycle to totalSteps/currentStep. Added stepLabel field for "Cycle" (Sigh) vs "Group" (PMR). -->

```swift
import ActivityKit
import Foundation

struct BreathingActivityAttributes: ActivityAttributes {

    // Static data
    var sessionName: String          // e.g. "Physiological Sigh", "PMR"
    var totalSteps: Int              // 3 for Sigh (cycles), 8 for PMR (muscle groups)
    var stepLabel: String            // "Cycle" for Sigh, "Group" for PMR

    // Dynamic data — updated on phase transitions
    struct ContentState: Codable, Hashable, Sendable {
        var phaseName: String        // e.g. "First inhale", "Long exhale", "Tense — Shoulders"
        var phaseEndDate: Date       // when the current phase ends
        var currentStep: Int         // 1-based — cycle number (Sigh) or muscle group number (PMR)
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

#### Step 8. Create `BreathingLiveActivityView`
**File**: `WellPlateWidget/LiveActivities/BreathingLiveActivityView.swift` (NEW)

<!-- RESOLVED: M3 — View uses stepLabel from attributes for display ("Cycle 2/3" or "Group 5/8") -->

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

                        Text("\(context.attributes.stepLabel) \(context.state.currentStep) of \(context.attributes.totalSteps)")
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

                        Text("\(context.attributes.stepLabel) \(context.state.currentStep)/\(context.attributes.totalSteps)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            } compactLeading: {
                Image(systemName: "wind")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.indigo)
            } compactTrailing: {
                if !context.state.isCompleted {
                    Text(timerInterval: Date.now...context.state.phaseEndDate,
                         countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.indigo)
                        .frame(width: 36)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                }
            } minimal: {
                Image(systemName: "wind")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.indigo)
            }
        }
    }
}
```

- **Dependencies**: Step 7
- **Risk**: Medium — phase transitions every 4–6s mean ~10–20 `activity.update()` calls per session. iOS allows frequent updates but may throttle. Testing on device required.

---

#### Step 9. Add breathing to `ActivityManager`
**File**: `WellPlate/Core/Services/ActivityManager.swift` (MODIFY — add below fasting methods)

<!-- RESOLVED: L2 — Added staleDate for breathing: session start + total duration + 30s -->
<!-- RESOLVED: M3 — Uses totalSteps/currentStep/stepLabel naming -->

Add:
```swift
// MARK: - Breathing Activity

private var breathingActivity: Activity<BreathingActivityAttributes>?

func startBreathingActivity(
    sessionName: String,
    totalSteps: Int,
    stepLabel: String,
    firstPhaseName: String,
    firstPhaseEndDate: Date,
    totalSessionDuration: TimeInterval
) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    let attributes = BreathingActivityAttributes(
        sessionName: sessionName,
        totalSteps: totalSteps,
        stepLabel: stepLabel
    )
    let state = BreathingActivityAttributes.ContentState(
        phaseName: firstPhaseName,
        phaseEndDate: firstPhaseEndDate,
        currentStep: 1,
        totalProgress: 0,
        isCompleted: false
    )
    let staleDate = Date().addingTimeInterval(totalSessionDuration + 30)
    let content = ActivityContent(state: state, staleDate: staleDate)

    do {
        breathingActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
    } catch {
        breathingActivity = nil
    }
}

func updateBreathingActivity(phaseName: String, phaseEndDate: Date, currentStep: Int, totalProgress: Double) {
    guard let activity = breathingActivity else { return }
    let state = BreathingActivityAttributes.ContentState(
        phaseName: phaseName,
        phaseEndDate: phaseEndDate,
        currentStep: currentStep,
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

- **Dependencies**: Step 7
- **Risk**: Low

---

#### Step 10. Update `WellPlateWidgetBundle` for breathing
**File**: `WellPlateWidget/WellPlateWidgetBundle.swift` (MODIFY)

Add `BreathingLiveActivity()` to the body:
```swift
var body: some Widget {
    StressWidget()
    FastingLiveActivity()
    BreathingLiveActivity()
}
```

- **Dependencies**: Step 8
- **Risk**: Low

---

#### Step 11. Wire breathing into `SighSessionView`
**File**: `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` (MODIFY)

<!-- RESOLVED: M1 — Reordered: startBreathingActivity() now called BEFORE timer.start(phases:). First onPhaseStart safely updates the already-existing activity. -->
<!-- RESOLVED: H1 — Uses ActivityManager.shared, not @EnvironmentObject -->

**Change 1 — Start breathing activity and set phase callback in `.onAppear`**:

**Current** (lines 79–87):
```swift
.onAppear {
    UIApplication.shared.isIdleTimerDisabled = true
    sessionStart = .now
    timer.onComplete = {
        saveSession(completed: true)
        withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
    }
    timer.start(phases: phases)
}
```

**After**:
```swift
.onAppear {
    UIApplication.shared.isIdleTimerDisabled = true
    sessionStart = .now

    // Start Live Activity BEFORE timer.start (so onPhaseStart can update it)
    let totalDuration = phases.map(\.duration).reduce(0, +)
    let firstPhase = phases[0]
    ActivityManager.shared.startBreathingActivity(
        sessionName: "Physiological Sigh",
        totalSteps: 3,
        stepLabel: "Cycle",
        firstPhaseName: firstPhase.name,
        firstPhaseEndDate: Date().addingTimeInterval(firstPhase.duration),
        totalSessionDuration: totalDuration
    )

    // Update Live Activity on each phase transition
    timer.onPhaseStart = { phase in
        let cycleNumber = (timer.currentPhaseIndex / 3) + 1
        ActivityManager.shared.updateBreathingActivity(
            phaseName: phase.name,
            phaseEndDate: Date().addingTimeInterval(phase.duration),
            currentStep: cycleNumber,
            totalProgress: timer.totalProgress
        )
    }

    timer.onComplete = {
        saveSession(completed: true)
        ActivityManager.shared.endBreathingActivity()
        withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
    }

    timer.start(phases: phases)
}
```

**Change 2 — End activity on cancel** (lines 72–74):

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
    ActivityManager.shared.endBreathingActivity()
    dismiss()
}
```

- **Dependencies**: Steps 9, 3
- **Risk**: Low — additive changes only

---

#### Step 12. Wire breathing into `PMRSessionView`
**File**: `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` (MODIFY)

<!-- RESOLVED: M2 — Explicit PMR formula: totalSteps = muscleGroups.count (8), currentStep = (timer.currentPhaseIndex / 2) + 1 -->
<!-- RESOLVED: M3 — stepLabel = "Group" for PMR (vs "Cycle" for Sigh) -->
<!-- RESOLVED: M1 — startBreathingActivity() called before timer.start() -->
<!-- RESOLVED: H1 — Uses ActivityManager.shared -->

Apply the same pattern as Step 11, with PMR-specific values:

**Change 1 — `.onAppear`** (lines 71–78):

**Current**:
```swift
.onAppear {
    UIApplication.shared.isIdleTimerDisabled = true
    sessionStart = .now
    timer.onComplete = {
        saveSession(completed: true)
        withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
    }
    timer.start(phases: phases)
}
```

**After**:
```swift
.onAppear {
    UIApplication.shared.isIdleTimerDisabled = true
    sessionStart = .now

    // Start Live Activity BEFORE timer.start
    let totalDuration = phases.map(\.duration).reduce(0, +)
    let firstPhase = phases[0]
    ActivityManager.shared.startBreathingActivity(
        sessionName: "PMR",
        totalSteps: muscleGroups.count,     // 8
        stepLabel: "Group",
        firstPhaseName: firstPhase.name,
        firstPhaseEndDate: Date().addingTimeInterval(firstPhase.duration),
        totalSessionDuration: totalDuration
    )

    // Update Live Activity on each phase transition
    // PMR: 2 phases per muscle group (tense + release), so group = index / 2 + 1
    timer.onPhaseStart = { phase in
        let groupNumber = (timer.currentPhaseIndex / 2) + 1
        ActivityManager.shared.updateBreathingActivity(
            phaseName: phase.name,
            phaseEndDate: Date().addingTimeInterval(phase.duration),
            currentStep: groupNumber,
            totalProgress: timer.totalProgress
        )
    }

    timer.onComplete = {
        saveSession(completed: true)
        ActivityManager.shared.endBreathingActivity()
        withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
    }

    timer.start(phases: phases)
}
```

**Change 2 — Cancel button** (lines 62–64):

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
    ActivityManager.shared.endBreathingActivity()
    dismiss()
}
```

- **Dependencies**: Steps 9, 3
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
   - Verify: Live Activity shows "Fast complete" state for ~30s then dismisses
   - Verify: Dynamic Island shows checkmark icon

3. **Fasting Live Activity end (broken)**:
   - Open FastingView → tap "Break Fast" → confirm
   - Verify: Live Activity shows "Fast ended early" for ~30s then dismisses

4. **App kill resilience**:
   - Start a fast → Live Activity appears → kill the app
   - Verify: Lock Screen Live Activity continues showing countdown (OS-managed timer)
   - Relaunch app → open FastingView
   - Verify: `ActivityManager.shared` reconnects to the existing activity (no duplicate)
   - If fast completed while app was killed → `reconnectFastingActivity()` ends it

5. **Live Activities disabled**:
   - Go to Settings → WellPlate → Live Activities → toggle off
   - Start a new fast
   - Verify: no Live Activity appears, no error shown, notifications still work

6. **No Dynamic Island device** (iPhone 13 or older):
   - Start a fast
   - Verify: Lock Screen banner appears correctly
   - Verify: no crash or error from Dynamic Island code paths

7. **(F7.1) Breathing Live Activity — Sigh**:
   - Open Stress tab → toolbar menu → Interventions → start Sigh session
   - Verify: Dynamic Island shows "wind" icon + phase countdown
   - Verify: Phase name updates when phases transition ("First inhale" → "Second inhale" → "Long exhale")
   - Verify: Lock Screen shows "Cycle 1 of 3" → "Cycle 2 of 3" → "Cycle 3 of 3"
   - Cancel session → verify Live Activity ends
   - Complete session → verify Live Activity shows "Session complete" then dismisses

8. **(F7.1) Breathing Live Activity — PMR**:
   - Start PMR session
   - Verify: Lock Screen shows "Group 1 of 8" (not "Cycle")
   - Verify: Phase names show "Tense — Hands & Forearms" / "Release" correctly
   - Complete or cancel → verify Live Activity ends

9. **Concurrent fasting + breathing**:
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
| Singleton `init()` accesses ActivityKit before UI setup | Low | `ActivityAuthorizationInfo()` and `Activity<T>.activities` are system APIs available at any point in app lifecycle. No ordering concern. |

<!-- RESOLVED: H1 — Replaced @EnvironmentObject crash risk with singleton note. No propagation concerns. -->
<!-- RESOLVED: L3 — Calling activity.end() on already-ended activity is a documented no-op. Safe. -->

---

## Non-Goals

- **No hydration Live Activity** — deferred indefinitely
- **No push-based ActivityKit updates** — no APNs token registration
- **No Apple Watch integration** — F8 scope
- **No "eating window" Live Activity** — only the fasting phase
- **No deep link on Live Activity tap** — `wellplate://fasting` deferred to polish. Tapping opens the app's main view (default iOS behavior).
- **No `FastingService` refactoring** — `ActivityManager.shared` is additive; `FastingService` retains its current interface
- **No shared Swift Package** — dual target membership (established pattern) is sufficient

<!-- RESOLVED: Missing element — Added deep link to non-goals as deferred item -->

---

## Success Criteria

### MVP (F7.0)
- [ ] Fasting Live Activity appears on Lock Screen when fasting state begins
- [ ] Dynamic Island shows compact (fork.knife + countdown), minimal (icon), and expanded (ring + labels) layouts
- [ ] Countdown uses `Text(timerInterval:countsDown:)` — no per-second app updates
- [ ] Live Activity ends with "complete" state when fast finishes on time
- [ ] Live Activity ends with "broken" state when user taps "Break Fast"
- [ ] `ActivityManager.shared` reconnects to existing activities on app relaunch
- [ ] `areActivitiesEnabled` guard prevents errors when user disables Live Activities
- [ ] `NSSupportsLiveActivities = YES` in both main app build settings and widget extension Info.plist
- [ ] Build succeeds on all 4 targets

### F7.1 (Breathing)
- [ ] Breathing Live Activity starts when Sigh or PMR session begins
- [ ] Phase name updates on Dynamic Island with each phase transition
- [ ] Sigh displays "Cycle X of 3"; PMR displays "Group X of 8"
- [ ] Phase countdown uses `Text(timerInterval:countsDown:)` — no per-second updates
- [ ] Stale date set to session duration + 30s — ensures cleanup on app crash
- [ ] Live Activity ends on session complete or cancel
- [ ] Fasting + Breathing can run simultaneously without conflict
- [ ] Widget bundle registers both `FastingLiveActivity` and `BreathingLiveActivity`
