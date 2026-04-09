# Implementation Checklist: Fasting Timer / IF Tracker

**Source Plan**: `Docs/02_Planning/Specs/260406-fasting-timer-plan-RESOLVED.md`
**Date**: 2026-04-06

---

## Pre-Implementation

- [ ] Read the resolved plan: `Docs/02_Planning/Specs/260406-fasting-timer-plan-RESOLVED.md`
- [ ] Verify affected files exist:
  - [ ] `WellPlate/App/WellPlateApp.swift` — model container (line 34)
  - [ ] `WellPlate/Features + UI/Stress/Views/StressView.swift` — `StressSheet` enum (line 12), toolbar menu (~line 73), sheet switch (~line 142)
  - [ ] `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift` — `private static func dailyAverages` (line 57)
  - Verify: All 3 files exist and line numbers match expected content

---

## Phase 1: Data Layer

### 1.1 — FastingSchedule model

- [ ] Create `WellPlate/Models/FastingSchedule.swift`
  - [ ] Define `FastingScheduleType` enum: `ratio16_8`, `ratio14_10`, `ratio18_6`, `ratio20_4`, `custom` — with `rawValue`, `label`, `defaultEatHours`, `defaultEatStartHour`, `icon` properties
  - [ ] Define `@Model final class FastingSchedule` with stored properties: `scheduleType: String`, `eatWindowStartHour: Int`, `eatWindowStartMinute: Int`, `eatWindowDurationHours: Double`, `isActive: Bool`, `caffeineCutoffEnabled: Bool`, `caffeineCutoffMinutesBefore: Int`, `createdAt: Date`
  - [ ] Add `init(scheduleType:eatWindowStartHour:eatWindowStartMinute:eatWindowDurationHours:isActive:caffeineCutoffEnabled:caffeineCutoffMinutesBefore:)` with defaults matching 16:8 (start 12, duration 8)
  - [ ] Add computed properties: `resolvedScheduleType`, `fastDurationHours`
  - Verify: File compiles in isolation (no external dependencies beyond Foundation + SwiftData)

### 1.2 — FastingSession model

- [ ] Create `WellPlate/Models/FastingSession.swift`
  - [ ] Define `@Model final class FastingSession` with stored properties: `startedAt: Date`, `targetEndAt: Date`, `actualEndAt: Date?`, `completed: Bool`, `scheduleType: String`, `createdAt: Date`
  - [ ] Add `init(startedAt:targetEndAt:scheduleType:)` — sets `completed = false`, `createdAt = .now`
  - [ ] Add computed properties: `isActive` (actualEndAt == nil), `actualDurationSeconds`, `targetDurationSeconds`, `progress` (0.0–1.0), `day` (startOfDay)
  - Verify: File compiles; `FastingScheduleType` from Step 1.1 is accessible (same module)

### 1.3 — Register models in WellPlateApp

- [ ] Edit `WellPlate/App/WellPlateApp.swift` line 34
  - [ ] Add `FastingSchedule.self, FastingSession.self` to the `.modelContainer(for:)` array
  - Final line: `.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self, InterventionSession.self, FastingSchedule.self, FastingSession.self])`
  - Verify: Build main target — `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

### 1.4 — Extract dailyAverages to shared utility

- [ ] Create `WellPlate/Features + UI/Stress/Services/StressAnalyticsHelper.swift`
  - [ ] Define `enum StressAnalyticsHelper` with two static methods:
    - `static func dailyAverages(from readings: [StressReading]) -> [Double]` — groups by `startOfDay`, returns array of per-day averages
    - `static func dailyAveragesByDate(from readings: [StressReading]) -> [Date: Double]` — groups by `startOfDay`, returns dictionary mapping day → average
  - Verify: File compiles (depends only on `StressReading` model)

- [ ] Edit `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift`
  - [ ] Remove `private static func dailyAverages(from readings: [StressReading]) -> [Double]` (lines 57–63)
  - [ ] Replace call on line 30: `dailyAverages(from: baselineReadings)` → `StressAnalyticsHelper.dailyAverages(from: baselineReadings)`
  - [ ] Replace call on line 31: `dailyAverages(from: experimentReadings)` → `StressAnalyticsHelper.dailyAverages(from: experimentReadings)`
  - Verify: Build main target — confirm `StressLabAnalyzer` compiles with external calls

### 1.5 — FastingService (timer + notifications)

- [ ] Create `WellPlate/Core/Services/FastingService.swift`
  - [ ] `import Foundation`, `import Combine`, `import UserNotifications`
  - [ ] Define `FastingState` enum: `.fasting(remaining: TimeInterval)`, `.eating(remaining: TimeInterval)`, `.notConfigured`
  - [ ] Define `@MainActor final class FastingService: ObservableObject`
  - [ ] Published properties:
    - `@Published private(set) var currentState: FastingState = .notConfigured`
    - `@Published private(set) var progress: Double = 0`
    - `@Published private(set) var timeRemaining: TimeInterval = 0`
    - `@Published private(set) var isCaffeineCutoffActive: Bool = false`
    - `@Published var notificationsBlocked: Bool = false`
  - [ ] `func configure(schedule: FastingSchedule, activeSession: FastingSession?)` — computes current state from schedule eat window times vs. `Date.now`, starts 1-second timer
  - [ ] Timer: `Timer.publish(every: 1, on: .main, in: .common).autoconnect()` — updates `timeRemaining`, `progress`, `currentState` each tick
  - [ ] `func stop()` — cancels timer subscription, sets state to `.notConfigured`
  - Verify: File compiles; no SwiftData imports (service has no ModelContext dependency)

- [ ] Add notification permission method to `FastingService`:
  - [ ] `func requestNotificationPermission() async` — checks `notificationSettings()`, calls `requestAuthorization(options: [.alert, .sound])` if `.notDetermined`, sets `notificationsBlocked` if denied
  - Verify: Method compiles with `UNUserNotificationCenter` API

- [ ] Add notification scheduling methods to `FastingService`:
  - [ ] `func scheduleNotifications(for schedule: FastingSchedule)` — clears existing fasting notifications, creates 3–4 `UNCalendarNotificationTrigger` requests (eat window closed, 1h warning, fast complete, optional caffeine cutoff) with `repeats: true`
  - [ ] `func clearNotifications()` — removes pending requests with IDs: `"wp.fasting.windowClosed"`, `"wp.fasting.oneHourLeft"`, `"wp.fasting.complete"`, `"wp.fasting.caffeineCutoff"`
  - [ ] Notification content: descriptive titles/bodies (e.g., "Fast Complete", "Your eating window is open.")
  - Verify: Build main target

### Phase 1 Gate

- [ ] Build all 4 targets after Phase 1:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: All 4 build with 0 errors

---

## Phase 2: UI Layer

### 2.1 — FastingScheduleEditor

- [ ] Create `WellPlate/Features + UI/Stress/Views/FastingScheduleEditor.swift`
  - [ ] `@Environment(\.modelContext) private var modelContext`
  - [ ] `@Environment(\.dismiss) private var dismiss`
  - [ ] `@ObservedObject var fastingService: FastingService`
  - [ ] `@State` properties for form: `selectedType: FastingScheduleType`, `eatWindowStart: Date`, `eatWindowEnd: Date`, `caffeineCutoffEnabled: Bool`, `cutoffHours: Int`
  - [ ] Optional binding for existing schedule (edit mode): `var existingSchedule: FastingSchedule?`
  - [ ] NavigationStack + Form layout:
    - Section "Schedule": picker/buttons for `FastingScheduleType.allCases` — selecting a preset auto-updates eat window times to defaults
    - Section "Eat Window": two `DatePicker` (`.hourAndMinute`), read-only "Fast duration: Xh" text
    - Section "Caffeine Cutoff": `Toggle` + conditional `Stepper` (1–4h before eat window ends)
  - [ ] Toolbar: Cancel (`.topBarLeading`, `AppColors.brand`), Save (`.topBarTrailing`, `.font(.r(.body, .semibold))`, `AppColors.brand`)
  - [ ] `.presentationDetents([.large])`
  - [ ] `save()` method:
    - If existing schedule: update properties in place
    - If new: `modelContext.insert(FastingSchedule(...))`
    - If active session exists and schedule changed: show alert "You have an active fast. End it and apply new schedule?" — "End Fast" / "Keep Current"
    - Call `await fastingService.requestNotificationPermission()` (first save)
    - Call `fastingService.scheduleNotifications(for: schedule)`
    - First-session creation: if current time falls in fasting window, create `FastingSession` with `startedAt` = most recent past eat window end time
    - `dismiss()`
  - Verify: Build main target

### 2.2 — FastingInsightChart

- [ ] Create `WellPlate/Features + UI/Stress/Views/FastingInsightChart.swift`
  - [ ] Accept params: `sessions: [FastingSession]`, `readings: [StressReading]`
  - [ ] Compute data:
    - Fast days set: `Set(sessions.filter { !$0.isActive }.map { Calendar.current.startOfDay(for: $0.startedAt) })`
    - Daily stress averages: `StressAnalyticsHelper.dailyAveragesByDate(from: readings)` (30-day window)
    - Partition into fast-day vs. non-fast-day groups
    - Compute mean per group
  - [ ] Gate: both groups need ≥3 days, otherwise show CTA text
  - [ ] Layout when sufficient data:
    - Title: `Text("Fasting & Stress").font(.r(.headline, .semibold))`
    - Two horizontal bars with labels: "Fast days" (`.orange`) and "Non-fast days" (`.secondary`)
    - Each bar: avg score label + "n = X days"
    - Footer: `Text("Correlation does not imply causation.").font(.r(.caption2, .regular)).foregroundColor(.secondary)`
  - [ ] Card background: `RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)`
  - [ ] Gate CTA: `Text("Log 7+ days to see your fasting × stress pattern.").font(.r(.footnote, .regular)).foregroundColor(.secondary)` — same card background
  - Verify: Build main target

### 2.3 — FastingView (main sheet)

- [ ] Create `WellPlate/Features + UI/Stress/Views/FastingView.swift`
  - [ ] Define `private enum FastingSheet: Identifiable` with case `.scheduleEditor` + `id` property
  - [ ] SwiftData queries (view-owned):
    - `@Query(sort: \FastingSchedule.createdAt, order: .reverse) private var schedules: [FastingSchedule]`
    - `@Query(sort: \FastingSession.startedAt, order: .reverse) private var sessions: [FastingSession]`
    - 30-day `StressReading` query with predicate (same pattern as `StressLabView` init)
  - [ ] `@Environment(\.modelContext) private var modelContext`
  - [ ] `@Environment(\.dismiss) private var dismiss`
  - [ ] `@StateObject private var fastingService = FastingService()`
  - [ ] `@State private var activeFastingSheet: FastingSheet?`
  - [ ] `@State private var showBreakFastAlert = false`
  - [ ] Computed helpers: `schedule` (schedules.first), `activeSession` (sessions.first where isActive), `completedSessions` (filter !isActive, limit 7)

- [ ] Timer card section:
  - [ ] Not configured state: "Set up your fasting schedule" CTA → `activeFastingSheet = .scheduleEditor`
  - [ ] Fasting state: circular progress ring (`.orange`), center "Xh Ym remaining"
  - [ ] Eating state: circular progress ring (`.green`), center "Xh Ym until fast"
  - [ ] Ring: `Circle().trim(from: 0, to: progress)` with `.stroke(lineWidth:)` + `.rotationEffect(.degrees(-90))`
  - [ ] Card background: standard card treatment

- [ ] Today info card:
  - [ ] Display eat window times (e.g., "Eat: 12:00 PM – 8:00 PM")
  - [ ] Caffeine cutoff indicator when active
  - [ ] "Break Fast" button (only when fasting): `HapticService.impact(.light)`, sets `showBreakFastAlert = true`

- [ ] Notification hint (conditional):
  - [ ] If `fastingService.notificationsBlocked`: show subtle card with "Enable notifications in Settings → WellPlate for fasting reminders."

- [ ] Insight chart:
  - [ ] Embed `FastingInsightChart(sessions: completedSessions, readings: stressReadings)`

- [ ] History section:
  - [ ] `ForEach` over `completedSessions` (last 7): date, formatted duration, checkmark (`completed = true`) or x-mark (`completed = false`)

- [ ] NavigationStack + ScrollView wrapper:
  - [ ] `.navigationTitle("Fasting")`, `.navigationBarTitleDisplayMode(.inline)`
  - [ ] Toolbar: "Done" button (`.topBarLeading`, `.font(.r(.body, .medium))`, `AppColors.brand`), gear button (`.topBarTrailing`) → `activeFastingSheet = .scheduleEditor`
  - [ ] `.sheet(item: $activeFastingSheet)` → switch → `.scheduleEditor`: `FastingScheduleEditor(fastingService: fastingService, existingSchedule: schedule)`
  - [ ] `.alert("End Fast?", isPresented: $showBreakFastAlert)` with "End Fast" (destructive) and "Cancel"
  - [ ] `.presentationDragIndicator(.visible)`
  - [ ] `.background(Color(.systemGroupedBackground))`
  - [ ] Padding: `.padding(.horizontal, 20)`, `.padding(.top, 16)`, `.padding(.bottom, 32)`

- [ ] Session lifecycle (in `.onAppear` / `.onChange`):
  - [ ] `.onAppear`: if schedule exists, call `fastingService.configure(schedule: schedule!, activeSession: activeSession)`
  - [ ] Observe `fastingService.currentState` changes:
    - `.eating` → `.fasting` transition: create `FastingSession` via `modelContext.insert()`
    - `.fasting` → `.eating` transition: mark active session `completed = true`, `actualEndAt = .now`
  - [ ] "Break fast" confirm action: `activeSession.completed = false; activeSession.actualEndAt = .now`
  - [ ] Toggle `schedule.isActive = false`: auto-end active session with `completed = false`, call `fastingService.clearNotifications()`

  - Verify: Build main target

### Phase 2 Gate

- [ ] Build main target after Phase 2:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: 0 errors

---

## Phase 3: Integration

### 3.1 — Wire into StressView

- [ ] Edit `WellPlate/Features + UI/Stress/Views/StressView.swift`

- [ ] Add `.fasting` case to `StressSheet` enum (~line 12):
  ```swift
  case fasting
  ```
  - Verify: Enum compiles

- [ ] Add `case .fasting: return "fasting"` to the `id` computed property (~line 21–31)
  - Verify: All `id` switch cases exhaustive

- [ ] Add "Fast" button to toolbar `Menu` (after "Resets" button, ~line 88):
  ```swift
  Button {
      HapticService.impact(.light)
      activeSheet = .fasting
  } label: {
      Label("Fast", systemImage: "fork.knife.circle")
  }
  ```
  - Verify: Button sits in the menu alongside "Lab" and "Resets"

- [ ] Add `case .fasting:` to `.sheet(item: $activeSheet)` switch (after `case .interventions:`, ~line 173):
  ```swift
  case .fasting:
      FastingView()
  ```
  - Verify: Switch is exhaustive, no compiler warnings

---

## Post-Implementation

- [ ] Build all 4 targets (final verification):
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: All 4 build with 0 errors

- [ ] Verify file count: 7 new files created, 3 existing files modified
  - New: `FastingSchedule.swift`, `FastingSession.swift`, `StressAnalyticsHelper.swift`, `FastingService.swift`, `FastingScheduleEditor.swift`, `FastingInsightChart.swift`, `FastingView.swift`
  - Modified: `WellPlateApp.swift`, `StressLabAnalyzer.swift`, `StressView.swift`

- [ ] Smoke test in Simulator:
  - [ ] Open Stress tab → toolbar menu shows "Fast" option
  - [ ] Tap "Fast" → FastingView opens with "not configured" state
  - [ ] Tap CTA → FastingScheduleEditor opens
  - [ ] Select 16:8 → verify defaults populate → Save
  - [ ] Verify timer shows fasting/eating state with correct countdown
  - [ ] Verify notification permission dialog appears (first time)
