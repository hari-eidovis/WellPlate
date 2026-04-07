# Implementation Plan: Fasting Timer / IF Tracker

**Date**: 2026-04-06
**Source**: `Docs/02_Planning/Specs/260406-fasting-timer-strategy.md`
**Status**: RESOLVED

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|---|---|---|
| H1: `dailyAverages` is `private static` | HIGH | Extract to new `StressAnalyticsHelper` shared utility; update `StressLabAnalyzer` to call it. New file added to architecture table. |
| H2: `UserNotifications` first-time setup missing | HIGH | Added Step 4a with full notification permission request flow, denied-state flag, and inline hint in `FastingView`. |
| H3: `FastingService` ModelContext injection | HIGH | Redesigned: `FastingService` is now a pure timer + notification coordinator. Views own `@Query` + `modelContext` CRUD. |
| M1: `FastingView` internal `.sheet()` | MEDIUM | Replaced with `FastingSheet` enum + single `.sheet(item:)`. |
| M2: `FastingScheduleType` enum location | MEDIUM | Kept in `FastingSchedule.swift` — acknowledged as acceptable (matches `InterventionType` in `StressExperiment.swift`). |
| M3: First-session creation edge case | MEDIUM | Added retroactive session creation logic when user configures schedule mid-fasting-window. |
| M4: `presentationDragIndicator` | MEDIUM | Explicitly listed as required modifier in Step 7. |
| L1: History limited to 7 sessions | LOW | Acknowledged as known MVP limitation. |
| L2: No mock mode mention | LOW | Acknowledged — no action needed, fasting is SwiftData-only. |
| Q1: "Break fast" confirmation | QUESTION | Resolved: Yes, show confirmation alert (consistent with mid-fast schedule change alert). |
| Q2: Disable schedule vs. active session | QUESTION | Resolved: Toggling `isActive = false` auto-ends any active session with `completed = false`. |

---

## Overview

Add an intermittent fasting timer to WellPlate, accessible from the Stress tab toolbar menu. Users configure an eat window (preset or custom), and the app tracks each fast as a session, fires notifications at key moments, and shows a "fasting vs. stress score" correlation chart. Two new SwiftData models, one shared analytics utility, one service, and three views. Two existing files modified, one existing file refactored.

---

## Requirements

1. User can select a fasting schedule (16:8, 14:10, 18:6, 20:4, custom)
2. Live countdown timer shows current fasting state + time remaining
3. Notifications fire at: eat window closed, 1h before fast ends, fast complete
4. Optional caffeine cutoff notification (relative to eat window end)
5. Each completed/broken fast is persisted as a `FastingSession`
6. Insight chart: "Fast days" vs "Non-fast days" average stress (≥7 days gate)
7. Entry point: Stress tab toolbar menu → "Fast" button → `FastingView` sheet

---

## Architecture Changes

| File | Change Type | Description |
|---|---|---|
| `WellPlate/Models/FastingSchedule.swift` | **NEW** | `@Model` — singleton schedule config + `FastingScheduleType` enum |
| `WellPlate/Models/FastingSession.swift` | **NEW** | `@Model` — one row per fasting session |
| `WellPlate/Features + UI/Stress/Services/StressAnalyticsHelper.swift` | **NEW** | Shared utility — `dailyAverages(from:)` extracted from `StressLabAnalyzer` |
| `WellPlate/Core/Services/FastingService.swift` | **NEW** | `@MainActor ObservableObject` — pure timer + notification coordinator (no SwiftData dependency) |
| `WellPlate/Features + UI/Stress/Views/FastingView.swift` | **NEW** | Main sheet — timer ring, schedule config, history, insight chart |
| `WellPlate/Features + UI/Stress/Views/FastingScheduleEditor.swift` | **NEW** | Sub-view — schedule type picker + time pickers |
| `WellPlate/Features + UI/Stress/Views/FastingInsightChart.swift` | **NEW** | Split-bar chart — fast days vs non-fast days avg stress |
| `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift` | **MODIFY** | Replace `private static func dailyAverages` with call to `StressAnalyticsHelper.dailyAverages` |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | **MODIFY** | Add `.fasting` to `StressSheet`; add toolbar button; add sheet case |
| `WellPlate/App/WellPlateApp.swift` | **MODIFY** | Add `FastingSchedule.self`, `FastingSession.self` to model container |

<!-- RESOLVED: H1 — Added StressAnalyticsHelper.swift to architecture table and StressLabAnalyzer.swift modification -->

---

## Implementation Steps

### Phase 1: Data Layer (Models + Shared Utility + Service)

#### Step 1. Create `FastingSchedule` model
**File**: `WellPlate/Models/FastingSchedule.swift` (NEW)

<!-- RESOLVED: M2 — Enum stays in this file, consistent with InterventionType in StressExperiment.swift -->

```swift
import Foundation
import SwiftData

/// Fasting schedule preset types.
enum FastingScheduleType: String, CaseIterable, Identifiable {
    case ratio16_8  = "16:8"
    case ratio14_10 = "14:10"
    case ratio18_6  = "18:6"
    case ratio20_4  = "20:4"
    case custom     = "Custom"

    var id: String { rawValue }

    var label: String { rawValue }

    /// Default eat window duration in hours for each preset.
    var defaultEatHours: Double {
        switch self {
        case .ratio16_8:  return 8
        case .ratio14_10: return 10
        case .ratio18_6:  return 6
        case .ratio20_4:  return 4
        case .custom:     return 8
        }
    }

    /// Default eat window start hour (24h format).
    var defaultEatStartHour: Int {
        switch self {
        case .ratio16_8:  return 12
        case .ratio14_10: return 10
        case .ratio18_6:  return 12
        case .ratio20_4:  return 12
        case .custom:     return 12
        }
    }

    var icon: String {
        switch self {
        case .ratio16_8:  return "clock"
        case .ratio14_10: return "clock.arrow.circlepath"
        case .ratio18_6:  return "clock.badge.checkmark"
        case .ratio20_4:  return "clock.badge.exclamationmark"
        case .custom:     return "slider.horizontal.3"
        }
    }
}

@Model
final class FastingSchedule {
    var scheduleType: String                     // FastingScheduleType.rawValue
    var eatWindowStartHour: Int                  // 0–23
    var eatWindowStartMinute: Int                // 0–59
    var eatWindowDurationHours: Double           // e.g. 8.0 for 16:8
    var isActive: Bool                           // toggle fasting on/off without deleting config
    var caffeineCutoffEnabled: Bool
    var caffeineCutoffMinutesBefore: Int          // minutes before eat window end (e.g. 120 = 2h)
    var createdAt: Date

    init(
        scheduleType: FastingScheduleType = .ratio16_8,
        eatWindowStartHour: Int = 12,
        eatWindowStartMinute: Int = 0,
        eatWindowDurationHours: Double = 8,
        isActive: Bool = true,
        caffeineCutoffEnabled: Bool = false,
        caffeineCutoffMinutesBefore: Int = 120
    ) {
        self.scheduleType = scheduleType.rawValue
        self.eatWindowStartHour = eatWindowStartHour
        self.eatWindowStartMinute = eatWindowStartMinute
        self.eatWindowDurationHours = eatWindowDurationHours
        self.isActive = isActive
        self.caffeineCutoffEnabled = caffeineCutoffEnabled
        self.caffeineCutoffMinutesBefore = caffeineCutoffMinutesBefore
        self.createdAt = .now
    }

    var resolvedScheduleType: FastingScheduleType {
        FastingScheduleType(rawValue: scheduleType) ?? .custom
    }

    /// Fast duration = 24 - eatWindowDurationHours
    var fastDurationHours: Double {
        24.0 - eatWindowDurationHours
    }
}
```

- **Action**: Create this file with the model and enum above
- **Why**: Data foundation for all fasting features; enum defines presets
- **Dependencies**: None
- **Risk**: Low

---

#### Step 2. Create `FastingSession` model
**File**: `WellPlate/Models/FastingSession.swift` (NEW)

```swift
import Foundation
import SwiftData

@Model
final class FastingSession {
    var startedAt: Date            // when the fast began (eat window closed)
    var targetEndAt: Date          // when the fast should end (eat window opens)
    var actualEndAt: Date?         // nil = in progress; set when user breaks or fast completes
    var completed: Bool            // true = hit target; false = broke early
    var scheduleType: String       // FastingScheduleType.rawValue for history context
    var createdAt: Date

    init(
        startedAt: Date,
        targetEndAt: Date,
        scheduleType: FastingScheduleType
    ) {
        self.startedAt = startedAt
        self.targetEndAt = targetEndAt
        self.completed = false
        self.scheduleType = scheduleType.rawValue
        self.createdAt = .now
    }

    /// Whether the fast is still in progress.
    var isActive: Bool { actualEndAt == nil }

    /// Actual fasted duration in seconds.
    var actualDurationSeconds: TimeInterval {
        let end = actualEndAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    /// Target fasted duration in seconds.
    var targetDurationSeconds: TimeInterval {
        targetEndAt.timeIntervalSince(startedAt)
    }

    /// Progress 0.0–1.0
    var progress: Double {
        guard targetDurationSeconds > 0 else { return 0 }
        return min(actualDurationSeconds / targetDurationSeconds, 1.0)
    }

    /// Calendar day of the fast start.
    var day: Date { Calendar.current.startOfDay(for: startedAt) }
}
```

- **Action**: Create this file
- **Why**: Session-level tracking enables insight chart and history list
- **Dependencies**: Step 1 (uses `FastingScheduleType`)
- **Risk**: Low

---

#### Step 3. Register models in `WellPlateApp.swift`
**File**: `WellPlate/App/WellPlateApp.swift` (MODIFY)

- **Action**: Add `FastingSchedule.self` and `FastingSession.self` to the `.modelContainer(for:)` array on line 34
- **Current**: `.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self, InterventionSession.self])`
- **After**: `.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self, InterventionSession.self, FastingSchedule.self, FastingSession.self])`
- **Why**: SwiftData requires all `@Model` types registered at container creation
- **Dependencies**: Steps 1–2
- **Risk**: Low — lightweight migration adds empty tables

---

#### Step 3a. Extract `dailyAverages` to shared utility
**File**: `WellPlate/Features + UI/Stress/Services/StressAnalyticsHelper.swift` (NEW)

<!-- RESOLVED: H1 — Extract dailyAverages from private static in StressLabAnalyzer to shared utility -->

```swift
import Foundation

/// Shared analytics utilities used by StressLabAnalyzer, FastingInsightChart,
/// and future correlation features.
enum StressAnalyticsHelper {

    /// Groups StressReading rows by calendar day and returns an array of daily
    /// average scores. Order is arbitrary (callers should not assume sorted).
    static func dailyAverages(from readings: [StressReading]) -> [Double] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: readings) { cal.startOfDay(for: $0.timestamp) }
        return grouped.values.map { day in
            day.map(\.score).reduce(0, +) / Double(day.count)
        }
    }

    /// Groups StressReading rows by calendar day and returns a dictionary mapping
    /// each day (start-of-day Date) to its average stress score.
    static func dailyAveragesByDate(from readings: [StressReading]) -> [Date: Double] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: readings) { cal.startOfDay(for: $0.timestamp) }
        return grouped.mapValues { day in
            day.map(\.score).reduce(0, +) / Double(day.count)
        }
    }
}
```

- **Action**: Create this file; then modify `StressLabAnalyzer.swift`:
  - Remove `private static func dailyAverages(from:)` (lines 57–63)
  - Replace the two call sites (lines 30–31) with `StressAnalyticsHelper.dailyAverages(from:)`
- **Why**: `dailyAverages` is needed by both `StressLabAnalyzer` and `FastingInsightChart`; `dailyAveragesByDate` variant is needed by the fasting insight chart to match days to fast/non-fast classification
- **Dependencies**: None (can be done in parallel with Steps 1–2)
- **Risk**: Low — pure function extraction, no behavior change

**Verify**: Build after this step to confirm `StressLabAnalyzer` still compiles with the external call.

---

#### Step 4. Create `FastingService`
**File**: `WellPlate/Core/Services/FastingService.swift` (NEW)

<!-- RESOLVED: H3 — FastingService is now a pure timer + notification coordinator with NO SwiftData dependency. Views own @Query + modelContext. -->

**Responsibilities** (scoped to timer + notifications only):
1. **Timer state**: `@Published var timeRemaining: TimeInterval`, `@Published var currentState: FastingState`, `@Published var progress: Double`
2. **Notification scheduling**: Schedule/reschedule/clear `UNUserNotificationCenter` notifications
3. **Notification permissions**: Request authorization on first schedule activation
4. **Caffeine cutoff**: `@Published var isCaffeineCutoffActive: Bool`

**What FastingService does NOT do** (owned by views instead):
- No SwiftData reads/writes — views own `@Query` and `modelContext`
- No `FastingSchedule` or `FastingSession` creation — views call `modelContext.insert()` / save

**Key design**:
- `@MainActor final class FastingService: ObservableObject`
- `func configure(schedule: FastingSchedule, activeSession: FastingSession?)` — called from `FastingView.onAppear` and when schedule/session changes. Computes `currentState` from schedule times vs. `Date.now`.
- `Timer.publish(every: 1, on: .main, in: .common)` drives `timeRemaining` updates
- `FastingState` enum:
  ```swift
  enum FastingState {
      case fasting(remaining: TimeInterval)
      case eating(remaining: TimeInterval)
      case notConfigured
  }
  ```

**Notification IDs** (static strings for cancel/reschedule):
- `"wp.fasting.windowClosed"` — eat window ended
- `"wp.fasting.oneHourLeft"` — 1h before fast ends
- `"wp.fasting.complete"` — fast complete
- `"wp.fasting.caffeineCutoff"` — caffeine cutoff (if enabled)

**Session lifecycle guidance for views**:
- Views observe `currentState` transitions. When state changes from `.eating` → `.fasting`, the view creates a new `FastingSession` via `modelContext.insert()`.
- When state changes from `.fasting` → `.eating` (target reached), the view marks the active session `completed = true`, `actualEndAt = .now`.
- "Break fast" button: view marks session `completed = false`, `actualEndAt = .now` (with confirmation alert — see Q1 resolution).

- **Action**: Create this file implementing the above
- **Why**: Pure timer/notification coordinator — thin, testable, no SwiftData coupling
- **Dependencies**: Step 1 (uses `FastingScheduleType` for notification content)
- **Risk**: Medium — notification scheduling and state reconstruction need careful testing

---

#### Step 4a. Notification permission request flow
**File**: `WellPlate/Core/Services/FastingService.swift` (part of Step 4)

<!-- RESOLVED: H2 — Full notification permission flow added as explicit sub-step -->

**Add to `FastingService`**:

```swift
import UserNotifications

// Published state for permission UI
@Published var notificationsBlocked = false

/// Request notification permission. Called when user first activates a schedule.
func requestNotificationPermission() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    
    switch settings.authorizationStatus {
    case .notDetermined:
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            notificationsBlocked = !granted
        } catch {
            notificationsBlocked = true
        }
    case .denied:
        notificationsBlocked = true
    case .authorized, .provisional, .ephemeral:
        notificationsBlocked = false
    @unknown default:
        notificationsBlocked = false
    }
}

/// Schedule all fasting notifications for the given schedule.
/// Clears existing fasting notifications first, then creates new ones.
func scheduleNotifications(for schedule: FastingSchedule) {
    let center = UNUserNotificationCenter.current()
    // Clear existing fasting notifications
    center.removePendingNotificationRequests(withIdentifiers: [
        "wp.fasting.windowClosed",
        "wp.fasting.oneHourLeft",
        "wp.fasting.complete",
        "wp.fasting.caffeineCutoff"
    ])
    
    guard !notificationsBlocked, schedule.isActive else { return }
    
    // Schedule repeating daily notifications using UNCalendarNotificationTrigger
    // ... (compute DateComponents from schedule times)
}

/// Clear all fasting notifications (called when schedule is deactivated).
func clearNotifications() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
        "wp.fasting.windowClosed",
        "wp.fasting.oneHourLeft",
        "wp.fasting.complete",
        "wp.fasting.caffeineCutoff"
    ])
}
```

**Flow**:
1. User saves first schedule in `FastingScheduleEditor`
2. View calls `await fastingService.requestNotificationPermission()`
3. iOS shows system permission dialog (first time only)
4. If granted → `scheduleNotifications(for:)` sets up repeating alerts
5. If denied → `notificationsBlocked = true` → `FastingView` shows inline hint:
   "Notifications are off. Enable in Settings → WellPlate → Notifications for fasting reminders."

- **Action**: Include this in `FastingService.swift` (Step 4)
- **Why**: App has never used `UserNotifications` — first-time permission is mandatory
- **Dependencies**: Step 4
- **Risk**: Low — standard `UNUserNotificationCenter` API

---

### Phase 2: UI Layer (Views)

#### Step 5. Create `FastingScheduleEditor`
**File**: `WellPlate/Features + UI/Stress/Views/FastingScheduleEditor.swift` (NEW)

**Layout** (follows `StressLabCreateView` Form pattern):
```
NavigationStack {
    Form {
        Section("Schedule") {
            // Horizontal scroll of schedule type buttons (16:8, 14:10, 18:6, 20:4, Custom)
            // Similar to how InterventionType picker works in StressLabCreateView
        }
        Section("Eat Window") {
            DatePicker("Starts at", selection: $eatWindowStart, displayedComponents: .hourAndMinute)
            DatePicker("Ends at", selection: $eatWindowEnd, displayedComponents: .hourAndMinute)
            // Read-only computed: "Fast duration: Xh"
        }
        Section("Caffeine Cutoff") {
            Toggle("Remind before cutoff", isOn: $caffeineCutoffEnabled)
            if caffeineCutoffEnabled {
                Stepper("Xh before eat window ends", value: $cutoffHours, in: 1...4)
            }
        }
    }
    .navigationTitle("Fasting Schedule")
    .toolbar {
        ToolbarItem(.topBarLeading) { Button("Cancel") { dismiss() } }
        ToolbarItem(.topBarTrailing) { Button("Save") { save() } }
    }
}
```

**Save action**: 
- If editing existing schedule: update properties on the existing `FastingSchedule` object
- If creating new schedule: `modelContext.insert(FastingSchedule(...))`
- If an active `FastingSession` exists and schedule changed: show confirmation alert "You have an active fast. End it and apply new schedule?" — "End Fast" (marks session `completed = false`) / "Keep Current" (discards schedule changes)
- After save: call `await fastingService.requestNotificationPermission()` (first time) then `fastingService.scheduleNotifications(for: schedule)`

<!-- RESOLVED: M3 — On save, if current time falls within fasting window, view creates a retroactive FastingSession with startedAt = most recent past eat window end time -->

**First-session creation**: After saving a new schedule, the view checks the service's `currentState`. If `.fasting(remaining:)`, the view creates a `FastingSession` with `startedAt` = the most recent past eat window end time (computed from schedule), not `Date.now`. This gives accurate duration tracking even when configuring mid-fast.

- **Action**: Create view with Form-based schedule editor
- **Why**: Separate sub-view keeps `FastingView` focused on the timer + history
- **Dependencies**: Steps 1, 4
- **Risk**: Low
- **Pattern**: Follow `StressLabCreateView` Form style — `.presentationDetents([.large])`, `.font(.r(...))`, `AppColors.brand` toolbar buttons

---

#### Step 6. Create `FastingInsightChart`
**File**: `WellPlate/Features + UI/Stress/Views/FastingInsightChart.swift` (NEW)

**Layout**:
```
VStack(alignment: .leading, spacing: 12) {
    Text("Fasting & Stress")
        .font(.r(.headline, .semibold))

    if hasSufficientData {
        HStack(spacing: 16) {
            // Bar 1: "Fast days" — colored bar (.orange), label "avg X.X", "n = Y days"
            // Bar 2: "Non-fast days" — colored bar (.secondary), label "avg X.X", "n = Y days"
        }
        Text("Correlation does not imply causation.")
            .font(.r(.caption2, .regular))
            .foregroundColor(.secondary)
    } else {
        // Gate CTA
        Text("Log 7+ days to see your fasting × stress pattern.")
            .font(.r(.footnote, .regular))
            .foregroundColor(.secondary)
    }
}
.padding(20)
.background(
    RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color(.systemBackground))
        .appShadow(radius: 15, y: 5)
)
```

**Data pipeline** (uses extracted shared utility):
<!-- RESOLVED: H1 — Uses StressAnalyticsHelper.dailyAveragesByDate instead of private StressLabAnalyzer method -->
- Query `FastingSession` (completed in last 30 days) → set of "fast days" (`startOfDay(for: startedAt)`)
- Query `StressReading` (last 30 days) → `StressAnalyticsHelper.dailyAveragesByDate(from:)` → `[Date: Double]`
- Partition daily averages into "fast day" vs "non-fast day" groups by checking if the date is in the fast-days set
- Compute mean for each group
- Gate: both groups must have ≥3 days

- **Action**: Create view + data pipeline
- **Why**: This is the WellPlate differentiator — not just a timer, but an insight
- **Dependencies**: Steps 1–3a
- **Risk**: Low — data pipeline uses extracted `StressAnalyticsHelper`

---

#### Step 7. Create `FastingView` (main sheet)
**File**: `WellPlate/Features + UI/Stress/Views/FastingView.swift` (NEW)

<!-- RESOLVED: M1 — Uses FastingSheet enum + single .sheet(item:) instead of .sheet(isPresented:) -->
<!-- RESOLVED: M4 — presentationDragIndicator(.visible) explicitly required -->
<!-- RESOLVED: Q1 — "Break fast" requires confirmation alert -->
<!-- RESOLVED: Q2 — Toggling isActive = false auto-ends active session with completed = false -->

**Internal sheet enum** (follows `StressLabSheet` pattern from `StressLabView.swift:5-15`):
```swift
private enum FastingSheet: Identifiable {
    case scheduleEditor

    var id: String {
        switch self {
        case .scheduleEditor: return "scheduleEditor"
        }
    }
}
```

**Layout structure** (follows `StressLabView` NavigationStack + ScrollView pattern):
```
NavigationStack {
    ScrollView {
        VStack(spacing: 20) {
            // 1. Timer Section (always visible)
            timerCard      // circular ring or no-schedule CTA

            // 2. Today Info Card
            todayInfoCard  // eat window times, caffeine cutoff status, "Break fast" button

            // 3. Notification hint (conditional)
            if fastingService.notificationsBlocked {
                notificationHint  // "Enable notifications in Settings..."
            }

            // 4. Insight Chart (gated)
            FastingInsightChart(sessions: completedSessions, readings: stressReadings)

            // 5. History Section
            historySection // list of past 7 sessions with completion status
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Fasting")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
                .font(.r(.body, .medium))
                .foregroundColor(AppColors.brand)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { activeFastingSheet = .scheduleEditor } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.brand)
            }
        }
    }
    .sheet(item: $activeFastingSheet) { sheet in
        switch sheet {
        case .scheduleEditor:
            FastingScheduleEditor(...)
        }
    }
    .alert("End Fast?", isPresented: $showBreakFastAlert) {
        Button("End Fast", role: .destructive) { breakCurrentFast() }
        Button("Cancel", role: .cancel) { }
    } message: {
        Text("This will end your current fast early.")
    }
}
.presentationDragIndicator(.visible)
```

**SwiftData queries** (view-owned, per H3 resolution):
```swift
@Environment(\.modelContext) private var modelContext
@Query(sort: \FastingSchedule.createdAt, order: .reverse) private var schedules: [FastingSchedule]
@Query(sort: \FastingSession.startedAt, order: .reverse) private var sessions: [FastingSession]
```
- `schedule`: `schedules.first` (singleton — only one active schedule)
- `activeSession`: `sessions.first(where: { $0.isActive })`
- `completedSessions`: `sessions.filter { !$0.isActive }`

**Timer card states**:
1. **Not configured**: "Set up your fasting schedule" CTA button → opens `FastingScheduleEditor`
2. **Fasting**: Circular progress ring (0–100% of fast), center text "Xh Ym remaining", accent color `.orange`
3. **Eating**: Circular progress ring (0–100% of eat window), center text "Xh Ym until fast", accent color `.green`

**Timer ring implementation**: Custom `Shape` with `trim(from:to:)` on a `Circle()`. Progress = `FastingSession.progress` (for fasting) or computed from eat window elapsed (for eating).

**Session lifecycle** (view responsibilities):
- Observe `fastingService.currentState`. On `.eating` → `.fasting` transition: `modelContext.insert(FastingSession(startedAt: eatWindowEndTime, targetEndAt: ..., scheduleType: ...))`.
- On `.fasting` → `.eating` transition (target reached): `activeSession.completed = true; activeSession.actualEndAt = .now`.
- "Break fast" button: show confirmation alert (Q1). On confirm: `activeSession.completed = false; activeSession.actualEndAt = .now`.
- Toggle `schedule.isActive = false`: auto-end active session with `completed = false` (Q2).

**History section**: `ForEach` over last 7 completed `FastingSession` rows. Each row: date, duration, checkmark/x icon for completed/broken.

**Known limitation**: History shows last 7 sessions only. "See All" deferred to post-MVP (L1).

- **Action**: Create main sheet view with timer, today info, notification hint, insight chart, history
- **Why**: Primary user-facing surface
- **Dependencies**: Steps 4–6
- **Risk**: Medium — timer ring animation + state transitions need polish

---

### Phase 3: Integration (Wire into StressView)

#### Step 8. Add `.fasting` to `StressSheet` and wire toolbar + sheet
**File**: `WellPlate/Features + UI/Stress/Views/StressView.swift` (MODIFY)

**Change 1 — StressSheet enum** (line 12):
Add new case:
```swift
case fasting
```
Add to `id` computed property:
```swift
case .fasting: return "fasting"
```

**Change 2 — Toolbar Menu** (after the "Resets" button, ~line 88):
Add new button:
```swift
Button {
    HapticService.impact(.light)
    activeSheet = .fasting
} label: {
    Label("Fast", systemImage: "fork.knife.circle")
}
```

**Change 3 — Sheet switch** (in `.sheet(item: $activeSheet)`, after `case .interventions:`, ~line 173):
```swift
case .fasting:
    FastingView()
```

- **Action**: Add enum case, toolbar button, and sheet routing
- **Why**: Entry point — without this, users can't reach the feature
- **Dependencies**: Step 7
- **Risk**: Low — follows exact pattern of existing Lab/Interventions integration

---

## Testing Strategy

### Build Verification
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```
All 3 extension targets should also still build clean:
```bash
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

### Manual Verification Flows

1. **Schedule setup flow**:
   - Open Stress tab → toolbar menu → "Fast"
   - See "not configured" state → tap CTA → `FastingScheduleEditor` opens
   - Select 16:8 → verify defaults (12pm–8pm) → Save
   - Verify notification permission dialog appears (first time)
   - Verify timer shows current state (fasting or eating based on current time)

2. **First-session retroactive creation** (M3 fix):
   - Configure a 16:8 schedule at 9pm (past the 8pm eat window end)
   - Verify: timer shows "Fasting", and a `FastingSession` exists with `startedAt` = 8pm (not 9pm)
   - Verify: time remaining = fastEnd - now (correct countdown, not from 9pm)

3. **Timer accuracy**:
   - Set eat window to end 2 min from now → verify countdown ticks correctly
   - Verify state transitions: eating → fasting → eating (may need to adjust schedule)

4. **Session persistence**:
   - Kill and relaunch app during an active fast → verify timer reconstructs from persisted `startedAt`
   - "Break fast" → verify confirmation alert → confirm → session saved with `completed = false`
   - Wait for fast to complete → verify session saved with `completed = true`

5. **Notifications**:
   - Enable schedule → verify notification permission dialog (first time)
   - If granted: verify notification content at each trigger point
   - Disable fasting (toggle `isActive = false`) → verify notifications are cleared and active session ends
   - Deny permission → verify `notificationsBlocked` hint appears in FastingView
   - Timer still works without notifications

6. **Insight chart**:
   - With <7 days of data → verify gate CTA is shown
   - Seed test data (≥7 days with mixed fast/non-fast) → verify split bar renders with correct averages and n-counts

7. **Caffeine cutoff**:
   - Enable caffeine cutoff → verify "Caffeine cutoff active" indicator displays at correct time
   - Verify notification fires at cutoff time (if permissions granted)

8. **Edge cases**:
   - Midnight-spanning fast (e.g., 20:4 with eat window 12pm–4pm) → verify 4pm → 12pm next day works
   - Change schedule while fast is active → verify confirmation alert → "End Fast" ends session, applies new schedule
   - No notification permission → verify timer still works, hint shown
   - StressLabAnalyzer still works after `dailyAverages` extraction (build verification in Step 3a)

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Notification permissions not granted | Medium | Timer works without notifications; `notificationsBlocked` flag drives inline hint in FastingView. Permission requested on first schedule save. |
| Timer drift when app is backgrounded | Low | Not an issue — timer reconstructs from `Date.now` vs. persisted `startedAt` on foreground. No background timer needed. |
| SwiftData lightweight migration for new models | Low | Adding new `@Model` types is forward-compatible; SwiftData handles this automatically |
| Midnight-spanning fasts | Medium | All date calculations use full `Date` timestamps, never time-of-day components alone. `targetEndAt` can be the next calendar day. |
| User changes schedule mid-fast | Medium | Confirmation alert: "End Fast?" with destructive action. Active session marked `completed = false`. |
| `dailyAverages` extraction breaks `StressLabAnalyzer` | Low | Build verification immediately after Step 3a. Function body is identical — only access level and location change. |

---

## Success Criteria

- [ ] User can configure a fasting schedule (preset or custom eat window)
- [ ] Live timer displays current state (fasting/eating) with correct countdown
- [ ] Sessions persist across app kills — timer rebuilds from saved dates
- [ ] Notification permission requested on first schedule activation
- [ ] Notifications fire at eat window close, 1h warning, and fast complete (when permitted)
- [ ] Blocked notifications show inline hint in FastingView
- [ ] Caffeine cutoff toggle and notification work when enabled
- [ ] "Break fast" shows confirmation alert, then ends session with `completed = false`
- [ ] Toggling schedule `isActive = false` auto-ends active session
- [ ] Configuring schedule mid-fasting-window creates retroactive session with correct `startedAt`
- [ ] Insight chart shows "fast days vs. non-fast days" avg stress when ≥7 days of data exist
- [ ] `StressLabAnalyzer` still works after `dailyAverages` extraction
- [ ] History section shows last 7 sessions with completion status
- [ ] Accessible from Stress tab toolbar menu → "Fast"
- [ ] Build succeeds on all 4 targets (WellPlate, ScreenTimeMonitor, ScreenTimeReport, WellPlateWidget)
