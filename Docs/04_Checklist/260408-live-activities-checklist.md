# Implementation Checklist: F7 — Live Activities (ActivityKit)

**Source Plan**: `Docs/02_Planning/Specs/260408-live-activities-plan-RESOLVED.md`
**Date**: 2026-04-08

---

## Pre-Implementation

- [ ] Read and understand the RESOLVED plan
- [ ] Verify affected files exist:
  - [ ] `WellPlateWidget/Info.plist` — widget Info.plist (will add `NSSupportsLiveActivities`)
  - [ ] `WellPlate/Widgets/SharedStressData.swift` — confirms dual-target membership pattern
  - [ ] `WellPlateWidget/WellPlateWidgetBundle.swift` — will add `FastingLiveActivity()`
  - [ ] `WellPlate/Core/Services/FastingService.swift` — reference for state machine (no changes)
  - [ ] `WellPlate/Features + UI/Stress/Views/FastingView.swift` — will add `ActivityManager.shared` calls
  - [ ] `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` — F7.1 breathing integration
  - [ ] `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` — F7.1 breathing integration
  - [ ] `WellPlate/Core/Services/InterventionTimer.swift` — reference for `onPhaseStart` callback

---

## Phase 1: Configuration (Plan Step 1)

### 1.1 — Add `NSSupportsLiveActivities` to widget Info.plist

- [ ] Edit `WellPlateWidget/Info.plist`: add `<key>NSSupportsLiveActivities</key><true/>` inside the top-level `<dict>`, before the closing `</dict>`
  - Verify: `grep NSSupportsLiveActivities WellPlateWidget/Info.plist` returns a match

### 1.2 — Enable Live Activities for main app target (manual Xcode step)

- [ ] Open `WellPlate.xcodeproj` in Xcode
- [ ] Select **WellPlate** target → Build Settings → search "Supports Live Activities" → set to **YES**
  - Verify: `grep INFOPLIST_KEY_NSSupportsLiveActivities WellPlate.xcodeproj/project.pbxproj` returns `YES`

---

## Phase 2: Shared Data Types (Plan Step 2)

### 2.1 — Create `FastingActivityAttributes`

- [ ] Create file `WellPlate/Widgets/FastingActivityAttributes.swift` with:
  - `import ActivityKit` and `import Foundation`
  - `struct FastingActivityAttributes: ActivityAttributes` with `scheduleLabel: String`
  - Nested `struct ContentState: Codable, Hashable, Sendable` with fields: `fastStartDate: Date`, `targetEndDate: Date`, `progress: Double`, `isCompleted: Bool`, `isBroken: Bool`
  - Verify: File exists at `WellPlate/Widgets/FastingActivityAttributes.swift`

### 2.2 — Add dual target membership (manual Xcode step)

- [ ] In Xcode, select `FastingActivityAttributes.swift` → File Inspector → Target Membership → check **both** `WellPlate` and `WellPlateWidget`
  - Verify: `grep -c FastingActivityAttributes WellPlate.xcodeproj/project.pbxproj` returns at least 2 (one `PBXBuildFile` per target, plus file reference)

---

## Phase 3: ActivityManager Service (Plan Step 3)

### 3.1 — Create `ActivityManager` singleton

- [ ] Create file `WellPlate/Core/Services/ActivityManager.swift` with:
  - `import Foundation` and `import ActivityKit`
  - `@MainActor final class ActivityManager` with `static let shared = ActivityManager()` and `private init()`
  - `private(set) var isFastingActivityActive = false`
  - `private var fastingActivity: Activity<FastingActivityAttributes>?`
  - `init()` calls `reconnectFastingActivity()`
  - Verify: File exists at `WellPlate/Core/Services/ActivityManager.swift`

### 3.2 — Implement `startFastingActivity()`

- [ ] Add method: `func startFastingActivity(scheduleLabel: String, fastStartDate: Date, targetEndDate: Date)`
  - Guards `ActivityAuthorizationInfo().areActivitiesEnabled`
  - Ends any existing fasting activity before starting new one
  - Computes `progress` from elapsed time
  - Creates `FastingActivityAttributes` and `ContentState`
  - Sets `staleDate: targetEndDate.addingTimeInterval(60)`
  - Calls `Activity.request(attributes:content:pushType: nil)` in a do/catch (silent failure)
  - Sets `isFastingActivityActive = true` on success
  - Verify: Method compiles (checked via full build later)

### 3.3 — Implement `endFastingActivity()`

- [ ] Add public method: `func endFastingActivity(completed: Bool)` that dispatches to private async `endFastingActivityInternal(completed:broken:)`
- [ ] Implement `private func endFastingActivityInternal(completed: Bool, broken: Bool) async`:
  - Guards `fastingActivity` is non-nil
  - Creates `finalState` from current activity state, sets `isCompleted`/`isBroken`/`progress`
  - Calls `await activity.end(content, dismissalPolicy: .default)`
  - Sets `fastingActivity = nil` and `isFastingActivityActive = false`
  - Verify: Method compiles

### 3.4 — Implement `reconnectFastingActivity()`

- [ ] Add `private func reconnectFastingActivity()`:
  - Guards `areActivitiesEnabled`
  - Checks `Activity<FastingActivityAttributes>.activities`
  - If existing activity found: store reference, set `isFastingActivityActive = true`
  - If `targetEndDate < Date()`: end the stale activity with `completed: true`
  - Verify: Method compiles

### 3.5 — Verify build

- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds with no errors

---

## Phase 4: Live Activity Views (Plan Steps 4–5)

### 4.1 — Create `LiveActivities` directory

- [ ] Create directory: `WellPlateWidget/LiveActivities/`
  - Verify: `ls WellPlateWidget/LiveActivities/` succeeds

### 4.2 — Create `FastingLiveActivityView`

- [ ] Create file `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift` with:
  - `import ActivityKit`, `import WidgetKit`, `import SwiftUI`
  - `struct FastingLiveActivity: Widget` with `ActivityConfiguration(for: FastingActivityAttributes.self)`
  - **Lock Screen view**: `HStack` with progress ring (Circle + trim + orange gradient) + VStack (schedule label, timer countdown, eat window time). Uses `.activityBackgroundTint(.black.opacity(0.7))`
  - **Dynamic Island compact leading**: fork.knife SF Symbol in orange
  - **Dynamic Island compact trailing**: `Text(timerInterval:countsDown:)` in orange, or checkmark/xmark for terminal states
  - **Dynamic Island minimal**: fork.knife icon
  - **Dynamic Island expanded**: progress ring (leading) + schedule label + large countdown (center) + "left" label (trailing)
  - Terminal states (`isCompleted` / `isBroken`): show "Fast complete" (green) or "Fast ended early" (red) instead of timer
  - All timer displays use `Text(timerInterval: Date.now...context.state.targetEndDate, countsDown: true)` — no app-side polling
  - Verify: File exists at `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift`

### 4.3 — Register in Widget Bundle

- [ ] Edit `WellPlateWidget/WellPlateWidgetBundle.swift`:
  - Add `import ActivityKit` at the top
  - Add `FastingLiveActivity()` after `StressWidget()` in the body
  - Verify: File contains both `StressWidget()` and `FastingLiveActivity()`

### 4.4 — Verify widget target build

- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds. If it fails with "missing framework", manually add `ActivityKit.framework` to WellPlateWidget → Build Phases → Link Binary With Libraries, then rebuild.

---

## Phase 5: Integration — FastingView (Plan Step 6)

### 5.1 — Hook `ActivityManager.shared` into `handleStateTransition()`

- [ ] Edit `WellPlate/Features + UI/Stress/Views/FastingView.swift` → `handleStateTransition(from:to:)` method:
  - In the `eating → fasting` branch (after `modelContext.insert(session)`), add:
    ```swift
    ActivityManager.shared.startFastingActivity(
        scheduleLabel: schedule.resolvedScheduleType.label + " Fast",
        fastStartDate: fastStart,
        targetEndDate: fastEnd
    )
    ```
  - In the `fasting → eating` branch (after `HapticService.notify(.success)`), add:
    ```swift
    ActivityManager.shared.endFastingActivity(completed: true)
    ```
  - Verify: Both calls appear in the method body

### 5.2 — Hook into `breakCurrentFast()`

- [ ] Edit `FastingView.swift` → `breakCurrentFast()` method:
  - After `session.actualEndAt = .now`, add:
    ```swift
    ActivityManager.shared.endFastingActivity(completed: false)
    ```
  - Verify: Call appears after `actualEndAt` assignment

### 5.3 — Start activity on first configure if already fasting

- [ ] Edit `FastingView.swift` → `configureService()` method:
  - After `previousState = fastingService.currentState`, add:
    ```swift
    if fastingService.currentState.isFasting && !ActivityManager.shared.isFastingActivityActive {
        if let session = activeSession {
            ActivityManager.shared.startFastingActivity(
                scheduleLabel: schedule.resolvedScheduleType.label + " Fast",
                fastStartDate: session.startedAt,
                targetEndDate: session.targetEndAt
            )
        }
    }
    ```
  - Verify: Guard `!ActivityManager.shared.isFastingActivityActive` prevents double-starting

### 5.4 — Verify MVP build (all 4 targets)

- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds
- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds
- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds
- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds

**MVP (F7.0) is complete after this phase.**

---

## Phase 6: F7.1 — Breathing Live Activity (Plan Steps 7–12)

### 6.1 — Create `BreathingActivityAttributes`

- [ ] Create file `WellPlate/Widgets/BreathingActivityAttributes.swift` with:
  - `import ActivityKit` and `import Foundation`
  - `struct BreathingActivityAttributes: ActivityAttributes` with fields: `sessionName: String`, `totalSteps: Int`, `stepLabel: String`
  - Nested `struct ContentState: Codable, Hashable, Sendable` with fields: `phaseName: String`, `phaseEndDate: Date`, `currentStep: Int`, `totalProgress: Double`, `isCompleted: Bool`
  - Verify: File exists

### 6.2 — Add dual target membership for breathing attributes (manual Xcode step)

- [ ] In Xcode, select `BreathingActivityAttributes.swift` → File Inspector → Target Membership → check **both** `WellPlate` and `WellPlateWidget`
  - Verify: `grep -c BreathingActivityAttributes WellPlate.xcodeproj/project.pbxproj` returns at least 2

### 6.3 — Add breathing methods to `ActivityManager`

- [ ] Edit `WellPlate/Core/Services/ActivityManager.swift` — add below fasting methods:
  - `private var breathingActivity: Activity<BreathingActivityAttributes>?`
  - `func startBreathingActivity(sessionName:totalSteps:stepLabel:firstPhaseName:firstPhaseEndDate:totalSessionDuration:)`:
    - Guards `areActivitiesEnabled`
    - Creates attributes with `sessionName`, `totalSteps`, `stepLabel`
    - Creates initial content state with phase 0 info
    - Sets `staleDate: Date().addingTimeInterval(totalSessionDuration + 30)`
    - Calls `Activity.request()` with silent error handling
  - `func updateBreathingActivity(phaseName:phaseEndDate:currentStep:totalProgress:)`:
    - Guards `breathingActivity` non-nil
    - Creates updated content state
    - Calls `await activity.update()` in a Task
  - `func endBreathingActivity()`:
    - Guards `breathingActivity` non-nil
    - Sets `isCompleted = true`, `totalProgress = 1.0`
    - Calls `await activity.end(dismissalPolicy: .default)` in a Task
    - Sets `breathingActivity = nil`
  - Verify: Three new methods compile

### 6.4 — Create `BreathingLiveActivityView`

- [ ] Create file `WellPlateWidget/LiveActivities/BreathingLiveActivityView.swift` with:
  - `struct BreathingLiveActivity: Widget` with `ActivityConfiguration(for: BreathingActivityAttributes.self)`
  - **Lock Screen**: HStack with indigo progress ring + session name + phase name + step label ("`\(stepLabel) \(currentStep) of \(totalSteps)`")
  - **DI compact leading**: wind icon in indigo
  - **DI compact trailing**: `Text(timerInterval:countsDown:)` in indigo, or checkmark for completed
  - **DI expanded center**: large phase name + phase countdown + step indicator
  - Phase countdown uses `Text(timerInterval: Date.now...context.state.phaseEndDate, countsDown: true)`
  - Completed state shows "Session complete" in green
  - Uses `.contentTransition(.opacity)` on phase name for smooth animation
  - Verify: File exists

### 6.5 — Register breathing in Widget Bundle

- [ ] Edit `WellPlateWidget/WellPlateWidgetBundle.swift`:
  - Add `BreathingLiveActivity()` after `FastingLiveActivity()` in the body
  - Verify: Body contains `StressWidget()`, `FastingLiveActivity()`, `BreathingLiveActivity()`

### 6.6 — Wire breathing into `SighSessionView`

- [ ] Edit `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` → `.onAppear` block:
  - **Before** `timer.start(phases: phases)`, add Live Activity start:
    ```swift
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
    ```
  - **Before** `timer.start(phases: phases)`, set phase transition callback:
    ```swift
    timer.onPhaseStart = { phase in
        let cycleNumber = (timer.currentPhaseIndex / 3) + 1
        ActivityManager.shared.updateBreathingActivity(
            phaseName: phase.name,
            phaseEndDate: Date().addingTimeInterval(phase.duration),
            currentStep: cycleNumber,
            totalProgress: timer.totalProgress
        )
    }
    ```
  - In existing `timer.onComplete` closure, add `ActivityManager.shared.endBreathingActivity()` before the `withAnimation` call
  - Verify: `startBreathingActivity` call appears before `timer.start(phases: phases)` in the `.onAppear` block

- [ ] Edit `SighSessionView.swift` → Cancel button action:
  - After `saveSession(completed: false)`, add `ActivityManager.shared.endBreathingActivity()`
  - Verify: `endBreathingActivity()` call appears in cancel action

### 6.7 — Wire breathing into `PMRSessionView`

- [ ] Edit `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` → `.onAppear` block:
  - **Before** `timer.start(phases: phases)`, add Live Activity start:
    ```swift
    let totalDuration = phases.map(\.duration).reduce(0, +)
    let firstPhase = phases[0]
    ActivityManager.shared.startBreathingActivity(
        sessionName: "PMR",
        totalSteps: muscleGroups.count,
        stepLabel: "Group",
        firstPhaseName: firstPhase.name,
        firstPhaseEndDate: Date().addingTimeInterval(firstPhase.duration),
        totalSessionDuration: totalDuration
    )
    ```
  - **Before** `timer.start(phases: phases)`, set phase transition callback:
    ```swift
    timer.onPhaseStart = { phase in
        let groupNumber = (timer.currentPhaseIndex / 2) + 1
        ActivityManager.shared.updateBreathingActivity(
            phaseName: phase.name,
            phaseEndDate: Date().addingTimeInterval(phase.duration),
            currentStep: groupNumber,
            totalProgress: timer.totalProgress
        )
    }
    ```
    Note: PMR uses `/ 2` (2 phases per muscle group: tense + release) vs Sigh's `/ 3`
  - In existing `timer.onComplete` closure, add `ActivityManager.shared.endBreathingActivity()` before `withAnimation`
  - Verify: `totalSteps: muscleGroups.count` (should be 8), `stepLabel: "Group"`, cycle formula uses `/ 2`

- [ ] Edit `PMRSessionView.swift` → Cancel button action:
  - After `saveSession(completed: false)`, add `ActivityManager.shared.endBreathingActivity()`
  - Verify: `endBreathingActivity()` call appears in cancel action

---

## Post-Implementation

### Final Build Verification

- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds
- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds
- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds
- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds

### File Inventory Check

- [ ] Verify all new files exist:
  - [ ] `WellPlate/Widgets/FastingActivityAttributes.swift`
  - [ ] `WellPlate/Core/Services/ActivityManager.swift`
  - [ ] `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift`
  - [ ] `WellPlate/Widgets/BreathingActivityAttributes.swift`
  - [ ] `WellPlateWidget/LiveActivities/BreathingLiveActivityView.swift`
- [ ] Verify modified files are correct:
  - [ ] `WellPlateWidget/Info.plist` contains `NSSupportsLiveActivities`
  - [ ] `WellPlateWidget/WellPlateWidgetBundle.swift` contains `FastingLiveActivity()` and `BreathingLiveActivity()`
  - [ ] `WellPlate/Features + UI/Stress/Views/FastingView.swift` contains `ActivityManager.shared` calls in 3 methods
  - [ ] `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` contains breathing Live Activity start/update/end
  - [ ] `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` contains breathing Live Activity start/update/end

### Manual Xcode Verification

- [ ] Confirm `FastingActivityAttributes.swift` has target membership for **both** WellPlate and WellPlateWidget
- [ ] Confirm `BreathingActivityAttributes.swift` has target membership for **both** WellPlate and WellPlateWidget
- [ ] Confirm WellPlate target Build Settings shows `Supports Live Activities = YES`

### Git Commit

- [ ] Stage all new and modified files
- [ ] Commit with message describing F7 Live Activities feature
