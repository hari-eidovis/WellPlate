# Implementation Checklist: Supplement / Medication Reminders

**Source Plan**: `Docs/02_Planning/Specs/260408-supplement-medication-plan-RESOLVED.md`
**Date**: 2026-04-08

---

## Pre-Implementation

- [ ] Read the resolved plan: `Docs/02_Planning/Specs/260408-supplement-medication-plan-RESOLVED.md`
- [ ] Verify affected files exist:
  - [ ] `WellPlate/App/WellPlateApp.swift` — model container with 11 models ending `SymptomEntry.self`
  - [ ] `WellPlate/Features + UI/Tab/ProfileView.swift` — `ProfileSheet` enum with 5 cases
  - [ ] `WellPlate/Core/Services/SymptomCorrelationEngine.swift` — 7-factor `computeCorrelations`
  - [ ] `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` — CSV with `symptomEntries` param
  - [ ] `WellPlate/Core/Services/FastingService.swift` — reference for notification pattern
- [ ] Verify no naming conflicts: `find WellPlate/ -name "Supplement*.swift" -o -name "Adherence*.swift"` — empty
- [ ] Create directory: `mkdir -p "WellPlate/Features + UI/Supplements/Views"`

---

## Phase 1: Data Layer

### 1.1 — Create SupplementEntry Model

- [ ] Create file `WellPlate/Models/SupplementEntry.swift`
- [ ] Define `enum SupplementCategory: String, CaseIterable, Identifiable, Codable` with 8 cases: `vitamin`, `mineral`, `omega`, `probiotic`, `herb`, `protein`, `medication`, `custom`
- [ ] Add computed properties on `SupplementCategory`: `label`, `icon` (SF Symbol), `color` (distinct per category)
- [ ] Define `@Model final class SupplementEntry` with fields:
  - `var id: UUID`
  - `var name: String`
  - `var dosage: String`
  - `var category: String` (raw value of SupplementCategory)
  - `var scheduledTimes: [Int]` (minutes from midnight — SwiftData supports `[Int]` natively)
  - `var activeDays: [Int]` (0=Sun..6=Sat; empty = every day)
  - `var isActive: Bool`
  - `var notificationsEnabled: Bool`
  - `var notes: String?`
  - `var startDate: Date`
  - `var createdAt: Date`
- [ ] Add init with defaults: `id = UUID()`, `createdAt = .now`, `startDate = .now`, `isActive = true`, `notificationsEnabled = true`, `scheduledTimes = [480]`, `activeDays = []`
- [ ] Add computed `var resolvedCategory: SupplementCategory?`
- [ ] Add computed `var formattedTimes: [String]` — converts each minute value to "h:mm AM/PM"
  - Verify: File compiles

### 1.2 — Create AdherenceLog Model

- [ ] Create file `WellPlate/Models/AdherenceLog.swift`
- [ ] Define `@Model final class AdherenceLog` with fields:
  - `var id: UUID`
  - `var supplementName: String` (denormalized for display/export)
  - `var supplementID: UUID` (FK to SupplementEntry)
  - `var day: Date` (Calendar.startOfDay)
  - `var scheduledMinute: Int` (which dose time)
  - `var status: String` ("taken", "skipped", "pending")
  - `var takenAt: Date?` (when marked taken)
  - `var createdAt: Date`
- [ ] Add init with defaults: `id = UUID()`, `createdAt = .now`, `status = "pending"`, `takenAt = nil`
  - Verify: File compiles

### 1.3 — Register Models in ModelContainer

- [ ] Edit `WellPlate/App/WellPlateApp.swift` — add `SupplementEntry.self, AdherenceLog.self` after `SymptomEntry.self`
  - Verify: Array now has 13 models
- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 2: Service Layer

### 2.1 — Create SupplementService

- [ ] Create file `WellPlate/Core/Services/SupplementService.swift`
- [ ] Add imports: `Foundation`, `SwiftUI`, `SwiftData`, `Combine`, `UserNotifications`
- [ ] Define `@MainActor final class SupplementService: ObservableObject` with:
  - `@Published var notificationsBlocked: Bool = false`

### 2.2 — Notification Permission

- [ ] Implement `func requestNotificationPermission() async`:
  - Get `UNUserNotificationCenter.current().notificationSettings()`
  - Switch on `authorizationStatus`: `.notDetermined` → request, `.denied` → blocked, `.authorized/.provisional/.ephemeral` → not blocked
  - Pattern: copy `FastingService.requestNotificationPermission()` (lines 187–206)
  - Verify: Method compiles

### 2.3 — Notification Scheduling

- [ ] Implement `func scheduleNotifications(for supplement: SupplementEntry)`:
  - Guard: `!notificationsBlocked && supplement.isActive && supplement.notificationsEnabled`
  - First call `clearNotifications(for: supplement)` to remove old ones
  - For each time in `supplement.scheduledTimes`:
    - `UNMutableNotificationContent()` with title `"Time for \(supplement.name)"`, body `supplement.dosage`, sound `.default`
    - `DateComponents(hour: time / 60, minute: time % 60)`
    - `UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)`
    - `center.add(UNNotificationRequest(identifier: "supplement_\(supplement.id.uuidString)_\(time)", content:, trigger:))`
- [ ] Implement `func clearNotifications(for supplement: SupplementEntry)`:
  - Build IDs array: `supplement.scheduledTimes.map { "supplement_\(supplement.id.uuidString)_\($0)" }`
  - `UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)`
  - Verify: Both methods compile

### 2.4 — Adherence Management

- [ ] Implement `func createPendingLogs(context: ModelContext, supplements: [SupplementEntry])`:
  - **Auto-resolve yesterday**: fetch all AdherenceLog where `status == "pending"` and `day < today`, set `status = "skipped"`
  - **Create today's entries**: for each active supplement, for each scheduledTime, check if AdherenceLog already exists for today + that minute. If not, insert one with status "pending"
  - `try? context.save()`
- [ ] Implement `func markDose(context: ModelContext, supplementID: UUID, supplementName: String, scheduledMinute: Int, status: String)`:
  - Find existing log for today + supplementID + scheduledMinute. If found, update status + takenAt. If not, create new.
  - `try? context.save()`
  - `HapticService.notify(.success)` on "taken"
- [ ] Implement `func todayAdherencePercent(logs: [AdherenceLog]) -> Double`:
  - Filter to today, count `status == "taken"` / total. Return 0.0–1.0. Guard empty = 0.
- [ ] Implement `func currentStreak(logs: [AdherenceLog]) -> Int`:
  - Walk backwards from yesterday. For each day: if all logs for that day are "taken", increment streak. Stop at first day with any non-taken.
- [ ] Implement `func adherenceByDay(logs: [AdherenceLog]) -> [Date: Double]`:
  - Group by day. Per day: taken / total. Return dictionary.
  - Verify: All methods compile

### 2.5 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 3: UI — Add Supplement Sheet

### 3.1 — Create AddSupplementSheet

- [ ] Create file `WellPlate/Features + UI/Supplements/Views/AddSupplementSheet.swift`
- [ ] Define `struct AddSupplementSheet: View` with:
  - `@Environment(\.modelContext)`, `@Environment(\.dismiss)`
  - `var editingSupplement: SupplementEntry?` (nil = add, non-nil = edit)
  - `@ObservedObject var service: SupplementService`
  - `@State` vars: `name`, `dosage`, `selectedCategory`, `scheduledTimes: [Int]`, `activeDays: [Int]`, `notificationsEnabled`, `notes`
- [ ] Build form layout:
  - Name `TextField`
  - Dosage `TextField`
  - Category: scrollable horizontal pills with icon + label, tap to select
  - Reminder Times: list of time pills + "Add time" button. Each time uses `DatePicker(selection:, displayedComponents: .hourAndMinute)` → convert to minutes from midnight
  - Active Days: 7-pill row (S M T W T F S), tap toggles day in array. Empty = "Every day" label
  - Notifications toggle
  - Optional notes `TextField`
- [ ] Toolbar: X dismiss (leading), Save button (trailing, disabled when name empty)
- [ ] Save action:
  - Create or update `SupplementEntry`
  - `modelContext.insert()` / update fields + `try modelContext.save()`
  - If notifications enabled: `Task { await service.requestNotificationPermission(); service.scheduleNotifications(for: entry) }`
  - `HapticService.notify(.success)` + `dismiss()`
  - `WPLogger.home.info("Supplement saved: \(name)")`
- [ ] If `editingSupplement` non-nil, populate `@State` vars from it in `.onAppear`
- [ ] Add `.presentationDetents([.large])` + `.presentationDragIndicator(.visible)`
- [ ] Add `#Preview`
  - Verify: Preview renders

---

## Phase 4: UI — Supplement List

### 4.1 — Create SupplementListView

- [ ] Create file `WellPlate/Features + UI/Supplements/Views/SupplementListView.swift`
- [ ] Define `struct SupplementListView: View` with:
  - `@Environment(\.modelContext)`
  - `@Query private var supplements: [SupplementEntry]`
  - `@Query(sort: \AdherenceLog.day, order: .reverse) private var allAdherenceLogs: [AdherenceLog]`
  - `@ObservedObject var service: SupplementService`
  - `@State private var showAddSheet = false`
  - `@State private var editingSupplement: SupplementEntry?`
- [ ] Add computed property (NOT @Query predicate — SwiftData can't filter by computed date):
  ```swift
  private var todayLogs: [AdherenceLog] {
      allAdherenceLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
  }
  ```
- [ ] Build layout:
  - Navigation title: "Health Regimen"
  - Summary header: adherence % bar + streak counter
  - List of today's doses grouped by supplement: status icon (✓ green / ○ gray / ✕ red) + name + dosage + time
  - Tap dose row → toggle taken/pending via `service.markDose()`
  - Swipe actions: edit (opens AddSupplementSheet in edit mode), delete (with notification clear)
  - "+" toolbar button → `showAddSheet = true`
  - Empty state: "Add your first supplement" CTA
- [ ] `.sheet` for AddSupplementSheet (can use local boolean since this is a standalone view, not Profile)
- [ ] Add `#Preview` with in-memory ModelContainer including `SupplementEntry.self, AdherenceLog.self`
  - Verify: Preview renders

### 4.2 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 5: UI — Supplement Detail

### 5.1 — Create SupplementDetailView

- [ ] Create file `WellPlate/Features + UI/Supplements/Views/SupplementDetailView.swift`
- [ ] Define `struct SupplementDetailView: View` with:
  - `let supplement: SupplementEntry`
  - `@Environment(\.modelContext)`
  - `@Query(sort: \AdherenceLog.day, order: .reverse) private var allLogs: [AdherenceLog]`
  - `@ObservedObject var service: SupplementService`
- [ ] Computed property to filter logs for this supplement:
  ```swift
  private var supplementLogs: [AdherenceLog] {
      allLogs.filter { $0.supplementID == supplement.id }
  }
  ```
- [ ] Build layout:
  - Header: name, dosage, category pill, formatted schedule times, active status
  - 30-day adherence grid: LazyVGrid of colored dots (green=taken, red=skipped, gray=pending/no data)
  - Stats card: adherence % (7d, 30d), current streak
  - Edit button → sheet with AddSupplementSheet in edit mode
  - Toggle active/inactive
  - Delete with confirmation alert
- [ ] Card styling: `.system()` fonts, `RoundedRectangle(cornerRadius: 20)`, `.appShadow()`
- [ ] Add `#Preview`
  - Verify: Preview renders

### 5.2 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 6: Profile Tab Integration

### 6.1 — Add addSupplement to ProfileSheet Enum

- [ ] Add `case addSupplement` to `ProfileSheet` enum in `WellPlate/Features + UI/Tab/ProfileView.swift`
- [ ] Add `case .addSupplement: return "addSupplement"` to `var id` switch
  - Verify: Enum compiles with 6 cases

### 6.2 — Add Supplement State Variables

- [ ] Add after existing symptom state variables:
  - `@State private var showSupplementList = false`
  - `@Query private var allSupplements: [SupplementEntry]`
  - `@Query(sort: \AdherenceLog.day, order: .reverse) private var allAdherenceLogs: [AdherenceLog]`
  - `@StateObject private var supplementService = SupplementService()`
- [ ] Add computed property:
  ```swift
  private var todayAdherenceLogs: [AdherenceLog] {
      allAdherenceLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
  }
  ```
  - Verify: No compiler errors

### 6.3 — Add Supplement Card to Profile Body

- [ ] Insert "Health Regimen" card between `symptomInsightsCard` (conditional) and `WidgetSetupCard` (~line 141):
- [ ] Build `supplementRegimenCard` computed property:
  - Header: pill icon + "Health Regimen" title + "+ Add" button (`activeSheet = .addSupplement`)
  - If supplements empty: "Add your first supplement" CTA
  - If supplements exist:
    - Today's adherence: "X/Y doses taken" + streak display
    - Progress bar: `GeometryReader` with filled portion = adherence %
    - "View All →" button (`showSupplementList = true`)
  - Card styling matching existing profile cards (`RoundedRectangle(cornerRadius: 20)`, `.appShadow(radius: 15, y: 5)`)
  - Verify: Card renders in body

### 6.4 — Add Sheet Case + Navigation

- [ ] Add to `.sheet(item: $activeSheet)` switch:
  ```swift
  case .addSupplement:
      AddSupplementSheet(service: supplementService)
  ```
- [ ] Add navigation destination:
  ```swift
  .navigationDestination(isPresented: $showSupplementList) {
      SupplementListView(service: supplementService)
  }
  ```
  - Verify: Tapping "View All" navigates; tapping "+ Add" opens sheet

### 6.5 — Create Pending Logs on Appear

- [ ] Add `.task {}` modifier (or extend existing `.onAppear`) to call:
  ```swift
  supplementService.createPendingLogs(context: modelContext, supplements: allSupplements)
  ```
  - Verify: Pending logs created on profile view appear

### 6.6 — Update ProfileView Preview

- [ ] Update preview ModelContainer to include all 4 model types:
  ```swift
  let container = try! ModelContainer(
      for: SymptomEntry.self, UserGoals.self, SupplementEntry.self, AdherenceLog.self,
      configurations: config
  )
  ```
  - Verify: Preview renders without crash

### 6.7 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 7: Correlation Extension

### 7.1 — Extend SymptomCorrelationEngine

- [ ] Edit `WellPlate/Core/Services/SymptomCorrelationEngine.swift`
- [ ] Add `adherenceByDay: [Date: Double] = [:]` parameter to `computeCorrelations` signature (after `sleepHours`)
- [ ] Add 8th factor to factors array (after Water):
  ```swift
  Factor(name: "Supplement adherence", icon: "pill.fill") { day in
      adherenceByDay.isEmpty ? nil : adherenceByDay[day]
  }
  ```
  - Note: `.isEmpty` guard skips factor entirely when no adherence data (backward compat)
  - Verify: Build compiles; no existing callers break (confirmed: none exist yet)

---

## Phase 8: CSV Export Extension

### 8.1 — Extend WellnessReportGenerator

- [ ] Edit `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift`
- [ ] Add `adherenceLogs: [AdherenceLog] = []` parameter to `generateCSV` signature
- [ ] Update CSV header: append `,supplement_adherence_pct`
- [ ] Add adherence grouping: `let adherenceByDay = Dictionary(grouping: adherenceLogs.filter { $0.day >= cutoff }) { $0.day }`
- [ ] Per day: compute adherence %:
  ```swift
  let dayAdherence = adherenceByDay[day] ?? []
  let adherencePct: String
  if dayAdherence.isEmpty {
      adherencePct = ""
  } else {
      let taken = dayAdherence.filter { $0.status == "taken" }.count
      adherencePct = String(Int(Double(taken) / Double(dayAdherence.count) * 100))
  }
  ```
- [ ] Append `adherencePct` to row string
  - Verify: Build compiles; existing caller uses default `[]`

---

## Post-Implementation

### Build All 4 Targets

- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`

### Functional Verification

- [ ] Add supplement: Profile → + Add → fill form → save → appears in list
- [ ] Notification scheduled: add supplement with time → notification appears at scheduled time
- [ ] Mark dose taken: supplement list → tap pending → "taken" with timestamp + haptic
- [ ] Mark dose skipped: supplement list → long-press or swipe → "skipped"
- [ ] Adherence %: log doses → profile card shows correct X/Y and bar
- [ ] Streak: consecutive 100% days counted correctly
- [ ] Auto-resolve: yesterday's pending logs become "skipped" on next app open
- [ ] Edit supplement: change times → old notifications cleared, new ones scheduled
- [ ] Delete supplement: notifications cleared, logs remain for history
- [ ] Profile card: shows adherence summary + streak; empty state when no supplements
- [ ] Supplement detail: 30-day grid, stats, edit, toggle active
- [ ] Correlation (≥7 days): 8th factor "Supplement adherence" appears in SymptomCorrelationView
- [ ] CSV export: `supplement_adherence_pct` column present and correct
- [ ] Notifications disabled: deny permission → supplements work without reminders
- [ ] ProfileView preview: renders without crash with all 4 model types
- [ ] Today filter: computed property correctly shows only today's logs

### Git Commit

- [ ] Stage all new and modified files
- [ ] Commit with message describing supplement/medication feature
