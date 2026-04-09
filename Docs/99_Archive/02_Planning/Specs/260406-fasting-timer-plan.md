# Implementation Plan: Fasting Timer / IF Tracker

**Date**: 2026-04-06
**Source**: `Docs/02_Planning/Specs/260406-fasting-timer-strategy.md`
**Status**: Ready for Audit

---

## Overview

Add an intermittent fasting timer to WellPlate, accessible from the Stress tab toolbar menu. Users configure an eat window (preset or custom), and the app tracks each fast as a session, fires notifications at key moments, and shows a "fasting vs. stress score" correlation chart. Two new SwiftData models, one service, and three views. Two existing files modified.

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
| `WellPlate/Models/FastingSchedule.swift` | **NEW** | `@Model` — singleton schedule config |
| `WellPlate/Models/FastingSession.swift` | **NEW** | `@Model` — one row per fasting session |
| `WellPlate/Core/Services/FastingService.swift` | **NEW** | `@MainActor ObservableObject` — timer, session lifecycle, notifications |
| `WellPlate/Features + UI/Stress/Views/FastingView.swift` | **NEW** | Main sheet — timer ring, schedule config, history, insight chart |
| `WellPlate/Features + UI/Stress/Views/FastingScheduleEditor.swift` | **NEW** | Sub-view — schedule type picker + time pickers |
| `WellPlate/Features + UI/Stress/Views/FastingInsightChart.swift` | **NEW** | Split-bar chart — fast days vs non-fast days avg stress |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | **MODIFY** | Add `.fasting` to `StressSheet`; add toolbar button; add sheet case |
| `WellPlate/App/WellPlateApp.swift` | **MODIFY** | Add `FastingSchedule.self`, `FastingSession.self` to model container |

---

## Implementation Steps

### Phase 1: Data Layer (Models + Service)

#### Step 1. Create `FastingSchedule` model
**File**: `WellPlate/Models/FastingSchedule.swift` (NEW)

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

#### Step 4. Create `FastingService`
**File**: `WellPlate/Core/Services/FastingService.swift` (NEW)

**Responsibilities**:
1. **Schedule CRUD**: Create/update/toggle the singleton `FastingSchedule`
2. **Session lifecycle**: Start a new session when eat window closes; end session when target reached or user breaks early
3. **Timer state**: `@Published var timeRemaining: TimeInterval`, `@Published var currentState: FastingState` (.fasting, .eating, .notConfigured), `@Published var activeSession: FastingSession?`
4. **Notification scheduling**: Schedule/reschedule `UNUserNotificationCenter` notifications when schedule changes
5. **Caffeine cutoff**: `@Published var isCaffeineCutoffActive: Bool` computed from current time vs. cutoff time

**Key design decisions**:
- `@MainActor final class FastingService: ObservableObject` — consistent with project patterns
- Takes `ModelContext` as init param (injected from view or environment)
- On `init` / `scenePhase == .active`: loads schedule from SwiftData, reconstructs timer from persisted dates
- `Timer.publish(every: 1, on: .main, in: .common)` drives `timeRemaining` updates while fasting
- `FastingState` enum: `.fasting(remaining: TimeInterval)`, `.eating(remaining: TimeInterval)`, `.notConfigured`

**Notification IDs** (static strings for cancel/reschedule):
- `"wp.fasting.windowClosed"` — eat window ended
- `"wp.fasting.oneHourLeft"` — 1h before fast ends
- `"wp.fasting.complete"` — fast complete
- `"wp.fasting.caffeineCutoff"` — caffeine cutoff (if enabled)

**Auto-session creation logic**:
- When `currentState` transitions from `.eating` → `.fasting`, auto-create a new `FastingSession` with `startedAt = now` and `targetEndAt = now + fastDurationHours * 3600`
- When `currentState` transitions from `.fasting` → `.eating` (target reached), mark session `completed = true`, `actualEndAt = now`
- "Break fast" button: mark session `completed = false`, `actualEndAt = now`

- **Action**: Create this file implementing the above
- **Why**: Central coordinator — views are thin, service owns all logic
- **Dependencies**: Steps 1–3
- **Risk**: Medium — notification scheduling and state reconstruction need careful testing

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
            // Bar 1: "Fast days" — colored bar, label "avg X.X", "n = Y days"
            // Bar 2: "Non-fast days" — colored bar, label "avg X.X", "n = Y days"
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

**Data pipeline**:
- Query `FastingSession` (completed in last 30 days) → set of "fast days" (`startOfDay(for: startedAt)`)
- Query `StressReading` (last 30 days) → compute daily averages (reuse `StressLabAnalyzer.dailyAverages` pattern)
- Partition daily averages into "fast day" vs "non-fast day" groups
- Compute mean for each group
- Gate: both groups must have ≥3 days

- **Action**: Create view + data pipeline
- **Why**: This is the WellPlate differentiator — not just a timer, but an insight
- **Dependencies**: Steps 1–4
- **Risk**: Low — data pipeline follows existing `StressLabAnalyzer` pattern

---

#### Step 7. Create `FastingView` (main sheet)
**File**: `WellPlate/Features + UI/Stress/Views/FastingView.swift` (NEW)

**Layout structure** (follows `StressLabView` NavigationStack + ScrollView pattern):
```
NavigationStack {
    ScrollView {
        VStack(spacing: 20) {
            // 1. Timer Section (always visible)
            timerCard      // circular ring or no-schedule CTA

            // 2. Today Info Card
            todayInfoCard  // eat window times, caffeine cutoff status, "Break fast" button

            // 3. Insight Chart (gated)
            FastingInsightChart(sessions: completedSessions, readings: stressReadings)

            // 4. History Section
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
            Button { showScheduleEditor = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.brand)
            }
        }
    }
    .sheet(isPresented: $showScheduleEditor) {
        FastingScheduleEditor(service: fastingService)
    }
}
.presentationDragIndicator(.visible)
```

**Timer card states**:
1. **Not configured**: "Set up your fasting schedule" CTA button → opens `FastingScheduleEditor`
2. **Fasting**: Circular progress ring (0–100% of fast), center text "Xh Ym remaining", accent color `.orange`
3. **Eating**: Circular progress ring (0–100% of eat window), center text "Xh Ym until fast", accent color `.green`

**Timer ring implementation**: Custom `Shape` with `trim(from:to:)` on a `Circle()` — same technique used across iOS timer apps. Progress = `FastingSession.progress` (for fasting) or computed from eat window elapsed (for eating).

**History section**: `ForEach` over last 7 `FastingSession` rows (query: `.sort(\FastingSession.startedAt, order: .reverse)`). Each row: date, duration, checkmark/x for completed/broken.

- **Action**: Create main sheet view with timer, today info, insight chart, history
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
All 3 extension targets should also still build clean.

### Manual Verification Flows

1. **Schedule setup flow**:
   - Open Stress tab → toolbar menu → "Fast"
   - See "not configured" state → tap CTA → `FastingScheduleEditor` opens
   - Select 16:8 → verify defaults (12pm–8pm) → Save
   - Verify timer shows current state (fasting or eating based on current time)

2. **Timer accuracy**:
   - Set eat window to end 2 min from now → verify countdown ticks correctly
   - Verify state transitions: eating → fasting → eating (may need to adjust schedule)

3. **Session persistence**:
   - Kill and relaunch app during an active fast → verify timer reconstructs from persisted `startedAt`
   - "Break fast" → verify session saved with `completed = false`
   - Wait for fast to complete → verify session saved with `completed = true`

4. **Notifications**:
   - Enable schedule → check Settings → WellPlate → Notifications are requested
   - Verify notification content text at each trigger point
   - Disable fasting → verify notifications are cleared

5. **Insight chart**:
   - With <7 days of data → verify gate CTA is shown
   - Seed test data (≥7 days with mixed fast/non-fast) → verify split bar renders with correct averages and n-counts

6. **Caffeine cutoff**:
   - Enable caffeine cutoff → verify "Caffeine cutoff active" indicator displays at correct time
   - Verify notification fires at cutoff time

7. **Edge cases**:
   - Midnight-spanning fast (e.g., 20:4 with eat window 12pm–4pm) → verify 4pm → 12pm next day works
   - Change schedule while fast is active → verify prompt / graceful handling
   - No notification permission → verify timer still works, hint shown

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Notification permissions not granted | Medium | Timer works without notifications; show subtle "Enable notifications for reminders" hint in `FastingView` if `UNUserNotificationCenter.current().settings.authorizationStatus != .authorized` |
| Timer drift when app is backgrounded | Low | Not an issue — timer reconstructs from `Date.now` vs. persisted `startedAt` on foreground. No background timer needed. |
| SwiftData lightweight migration for new models | Low | Adding new `@Model` types is forward-compatible; SwiftData handles this automatically |
| Midnight-spanning fasts | Medium | All date calculations use full `Date` timestamps, never time-of-day components alone. `targetEndAt` can be the next calendar day. |
| User changes schedule mid-fast | Medium | Show confirmation alert: "You have an active fast. End it and apply new schedule?" Options: "End Fast" / "Keep Current" |

---

## Success Criteria

- [ ] User can configure a fasting schedule (preset or custom eat window)
- [ ] Live timer displays current state (fasting/eating) with correct countdown
- [ ] Sessions persist across app kills — timer rebuilds from saved dates
- [ ] Notifications fire at eat window close, 1h warning, and fast complete
- [ ] Caffeine cutoff toggle and notification work when enabled
- [ ] "Break fast" ends session early with `completed = false`
- [ ] Insight chart shows "fast days vs. non-fast days" avg stress when ≥7 days of data exist
- [ ] History section shows last 7 sessions with completion status
- [ ] Accessible from Stress tab toolbar menu → "Fast"
- [ ] Build succeeds on all 4 targets (WellPlate, ScreenTimeMonitor, ScreenTimeReport, WellPlateWidget)
