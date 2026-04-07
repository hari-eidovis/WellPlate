# Implementation Plan: Supplement / Medication Reminders

**Date**: 2026-04-08
**Source**: `Docs/02_Planning/Specs/260408-supplement-medication-strategy.md`
**Status**: RESOLVED — Ready for Checklist

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| H1 — `@Query` cannot filter AdherenceLog by computed date | HIGH | **FIXED** — Steps 6 and 8 now use `@Query` for all logs + computed property filter for today |
| M1 — SupplementService missing `import UserNotifications` | MEDIUM | **FIXED** — Step 4 now lists all required imports including `UserNotifications` |
| M2 — ProfileView preview needs SupplementEntry + AdherenceLog | MEDIUM | **FIXED** — Step 8 now includes explicit preview update with all 4 model types |
| L1 — No notification permission description | LOW | **ACKNOWLEDGED** — Added note to Step 4 about pre-dialog explanation card in v2 |
| L2 — Adherence auto-resolve timing | LOW | **FIXED** — Step 4 `createPendingLogs` now includes auto-resolve logic for yesterday's pending → skipped |

---

## Overview

Add supplement and medication tracking with scheduled reminders, adherence logging, and symptom-correlation integration. Users add supplements via a form (name, dose, category, times), receive daily reminder notifications, and mark doses as taken/skipped. Profile tab gets a "Health Regimen" card showing today's adherence and streak. The `SymptomCorrelationEngine` is extended with an 8th factor (adherence %) to surface "did taking X correlate with fewer Y?" insights. CSV export extended with adherence column.

## Requirements

- R1: Add supplements/medications with name, dosage, category, and scheduled times
- R2: Daily local notifications at scheduled times (reuse `FastingService` pattern)
- R3: Adherence log — mark doses as taken or skipped; streak tracking
- R4: Profile tab "Health Regimen" card with today's status + navigation to detail
- R5: Extend `SymptomCorrelationEngine` with 8th factor (adherence %)
- R6: Export — add `supplement_adherence_pct` column to CSV
- R7: All data on-device (SwiftData); no medication database or dosing advice
- R8: Follow existing UI conventions (`.system()` fonts, card styling, haptics)

## Architecture Changes

| Type | File | Change |
|------|------|--------|
| **New** | `WellPlate/Models/SupplementEntry.swift` | SwiftData @Model — name, dosage, category, scheduledTimes, activeDays, isActive |
| **New** | `WellPlate/Models/AdherenceLog.swift` | SwiftData @Model — day, supplementID, scheduledMinute, status, takenAt |
| **New** | `WellPlate/Core/Services/SupplementService.swift` | Notification scheduling, adherence aggregation, permission handling |
| **New** | `WellPlate/Features + UI/Supplements/Views/SupplementListView.swift` | List of supplements with today's adherence, add/edit/delete |
| **New** | `WellPlate/Features + UI/Supplements/Views/SupplementDetailView.swift` | Single supplement: adherence calendar, stats, edit |
| **New** | `WellPlate/Features + UI/Supplements/Views/AddSupplementSheet.swift` | Add/edit form: name, dose, category, times, days |
| **Modify** | `WellPlate/App/WellPlateApp.swift` | Add `SupplementEntry.self`, `AdherenceLog.self` to model container |
| **Modify** | `WellPlate/Features + UI/Tab/ProfileView.swift` | Add `.addSupplement` to `ProfileSheet`, supplement card in body, preview update |
| **Modify** | `WellPlate/Core/Services/SymptomCorrelationEngine.swift` | Add `adherenceByDay` parameter + 8th factor |
| **Modify** | `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` | Add `supplement_adherence_pct` CSV column |

## Implementation Steps

### Phase 1: Data Layer

#### Step 1. Create `SupplementEntry` SwiftData Model
**File**: `WellPlate/Models/SupplementEntry.swift` (new)

```swift
import Foundation
import SwiftUI
import SwiftData

enum SupplementCategory: String, CaseIterable, Identifiable, Codable {
    case vitamin, mineral, omega, probiotic, herb, protein, medication, custom
    var id: String { rawValue }
    var label: String { ... }
    var icon: String { ... }   // SF Symbol per category
    var color: Color { ... }
}

@Model
final class SupplementEntry {
    var id: UUID
    var name: String              // "Magnesium", "Vitamin D3"
    var dosage: String            // "400mg", "5000 IU"
    var category: String          // Raw value of SupplementCategory
    var scheduledTimes: [Int]     // Minutes from midnight [480, 1200] = 8am, 8pm
    var activeDays: [Int]         // 0=Sun..6=Sat; empty = every day
    var isActive: Bool
    var notificationsEnabled: Bool
    var notes: String?
    var startDate: Date
    var createdAt: Date

    var resolvedCategory: SupplementCategory? { ... }
    var formattedTimes: [String] { ... }  // ["8:00 AM", "8:00 PM"]
}
```

SwiftData supports `[Int]` natively (proven by `FoodLogEntry.eatingTriggers: [String]?`).

- **Dependencies**: None
- **Risk**: Low

#### Step 2. Create `AdherenceLog` SwiftData Model
**File**: `WellPlate/Models/AdherenceLog.swift` (new)

```swift
@Model
final class AdherenceLog {
    var id: UUID
    var supplementName: String    // Denormalized for display/export
    var supplementID: UUID        // FK to SupplementEntry.id
    var day: Date                 // Calendar.startOfDay
    var scheduledMinute: Int      // Which dose time (480 = 8am)
    var status: String            // "taken", "skipped", "pending"
    var takenAt: Date?            // When marked taken (nil if skipped/pending)
    var createdAt: Date
}
```

- **Dependencies**: Step 1
- **Risk**: Low

#### Step 3. Register Models in ModelContainer
**File**: `WellPlate/App/WellPlateApp.swift` (line 34)

Add `SupplementEntry.self, AdherenceLog.self` after `SymptomEntry.self`. Container will have 13 models.

- **Dependencies**: Steps 1–2
- **Risk**: Low

---

### Phase 2: Service Layer

#### Step 4. Create `SupplementService`
**File**: `WellPlate/Core/Services/SupplementService.swift` (new)

<!-- RESOLVED: M1 — Explicit imports listed including UserNotifications -->

**Required imports:**
```swift
import Foundation
import SwiftUI
import SwiftData
import Combine
import UserNotifications
```

```swift
@MainActor
final class SupplementService: ObservableObject {
    @Published var notificationsBlocked: Bool = false

    // MARK: - Notification Permission (copy FastingService pattern)
    func requestNotificationPermission() async { ... }

    // MARK: - Schedule Notifications
    func scheduleNotifications(for supplement: SupplementEntry) { ... }

    // MARK: - Clear Notifications
    func clearNotifications(for supplement: SupplementEntry) { ... }

    // MARK: - Adherence
    func markDose(context: ModelContext, supplementID: UUID, supplementName: String, scheduledMinute: Int, status: String) { ... }
    func createPendingLogs(context: ModelContext, supplements: [SupplementEntry]) { ... }
    func todayAdherencePercent(logs: [AdherenceLog]) -> Double { ... }
    func currentStreak(logs: [AdherenceLog]) -> Int { ... }
    func adherenceByDay(logs: [AdherenceLog]) -> [Date: Double] { ... }
}
```

**Notification scheduling** — follows `FastingService.scheduleNotifications()` (lines 209–263):
- For each time in `supplement.scheduledTimes`:
  - Create `UNMutableNotificationContent()` with title: "Time for \(supplement.name)", body: "\(supplement.dosage)"
  - Create `DateComponents(hour: time / 60, minute: time % 60)`
  - Create `UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)`
  - Add with ID: `"supplement_\(supplement.id.uuidString)_\(time)"`
- Guard: skip if `notificationsBlocked` or `!supplement.isActive` or `!supplement.notificationsEnabled`

**clearNotifications** — build array of IDs from supplement's scheduledTimes, call `removePendingNotificationRequests(withIdentifiers:)`

<!-- RESOLVED: L2 — createPendingLogs now includes auto-resolve for yesterday's pending → skipped -->
**createPendingLogs** — called on app appear. Two responsibilities:
1. **Auto-resolve yesterday's pending**: query all `AdherenceLog` where `day < today` AND `status == "pending"`, update to `status = "skipped"`. This ensures streaks are honest.
2. **Create today's entries**: for each active supplement, for each `scheduledTime`, check if an `AdherenceLog` already exists for today + that minute. If not, create one with status "pending".

**todayAdherencePercent** — count logs where status == "taken" / total today logs. Returns 0.0–1.0.

**currentStreak** — walk backwards from yesterday (not today, which may be incomplete), counting consecutive days where all logs have status "taken".

**adherenceByDay** — aggregate logs into `[Date: Double]` dictionary (0.0–1.0 per day) for correlation engine. Per day: taken count / total count.

<!-- RESOLVED: L1 — Noted for v2: add pre-dialog explanation before system notification prompt -->
**Note for v2**: Before calling `requestNotificationPermission()` for the first time, show an in-app card explaining why notifications are useful. Not in MVP.

- **Dependencies**: Steps 1–3
- **Risk**: Low–Medium (notification management needs testing)

---

### Phase 3: UI — Add Supplement Sheet

#### Step 5. Create `AddSupplementSheet`
**File**: `WellPlate/Features + UI/Supplements/Views/AddSupplementSheet.swift` (new)

Form for adding/editing a supplement:

```
┌─────────────────────────────────────┐
│ ✕  Add Supplement          [Save]   │
│─────────────────────────────────────│
│                                     │
│ Name                                │
│ ┌─────────────────────────────────┐ │
│ │ Magnesium                       │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Dosage                              │
│ ┌─────────────────────────────────┐ │
│ │ 400mg                           │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Category                            │
│ [Vitamin] [Mineral●] [Omega] ...   │
│                                     │
│ Reminder Times                      │
│ ┌──────┐ ┌──────┐                  │
│ │ 8:00 │ │ + Add│                  │
│ │  AM  │ │ time │                  │
│ └──────┘ └──────┘                  │
│                                     │
│ Active Days                         │
│ [S] [M●] [T●] [W●] [T●] [F●] [S] │
│                                     │
│ ☐ Enable notifications             │
└─────────────────────────────────────┘
```

**State:**
```swift
struct AddSupplementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var editingSupplement: SupplementEntry?  // nil = add mode, non-nil = edit mode
    @ObservedObject var service: SupplementService

    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var selectedCategory: SupplementCategory = .vitamin
    @State private var scheduledTimes: [Int] = [480]  // Default 8:00 AM
    @State private var activeDays: [Int] = []         // Empty = every day
    @State private var notificationsEnabled: Bool = true
    @State private var notes: String = ""
}
```

**Time picker**: Use `DatePicker` with `.hourAndMinute` display, convert to minutes-from-midnight on save.

**Active days**: 7-pill row (S M T W T F S), tap to toggle. Empty = every day (displayed as "Every day" label).

**Save action**: Create or update `SupplementEntry`, call `service.scheduleNotifications(for:)` if notifications enabled, dismiss.

- **Dependencies**: Steps 1, 4
- **Risk**: Low

---

### Phase 4: UI — Supplement List

#### Step 6. Create `SupplementListView`
**File**: `WellPlate/Features + UI/Supplements/Views/SupplementListView.swift` (new)

<!-- RESOLVED: H1 — Uses @Query for all logs + computed property filter for today, not @Query predicate -->

Main supplement management view, presented as `navigationDestination` from Profile.

**Data — use `@Query` for all entries, filter today in computed property:**
```swift
@Query private var supplements: [SupplementEntry]
@Query(sort: \AdherenceLog.day, order: .reverse) private var allAdherenceLogs: [AdherenceLog]

private var todayLogs: [AdherenceLog] {
    allAdherenceLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
}
```

**Note**: SwiftData `@Query` does not support runtime-computed date predicates. The app's existing pattern (e.g., `HomeView.fetchTodayWellnessLog()`) uses `FetchDescriptor` for date-filtered queries. For views displaying today's data, the computed-property-filter approach is simpler and equivalent.

**Features:**
- Today's adherence percentage bar + streak counter at top
- List of all active supplements with today's dose statuses
- Tap dose row → toggle taken/pending via `service.markDose()`
- Swipe supplement → edit (opens `AddSupplementSheet` in edit mode) or delete (cascade clear notifications)
- "+" button opens `AddSupplementSheet`
- Inactive supplements shown at bottom (dimmed)

**Empty state**: "Add your first supplement" CTA

- **Dependencies**: Steps 1–5
- **Risk**: Low

---

### Phase 5: UI — Supplement Detail

#### Step 7. Create `SupplementDetailView`
**File**: `WellPlate/Features + UI/Supplements/Views/SupplementDetailView.swift` (new)

Detail view for a single supplement, showing adherence over time.

**Features:**
- Header: name, dosage, category pill, schedule times
- Adherence calendar: 30-day grid showing taken (green) / skipped (red) / pending (gray) per day
- Stats: adherence % (7d, 30d), current streak, longest streak
- Edit button → opens `AddSupplementSheet` in edit mode
- Toggle active/inactive
- Delete with confirmation

- **Dependencies**: Steps 1–2, 6
- **Risk**: Low

---

### Phase 6: Profile Tab Integration

#### Step 8. Add Supplement Card to ProfilePlaceholderView
**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`

**Add `.addSupplement` to `ProfileSheet` enum** (after `.symptomLog`):
```swift
case addSupplement
```

<!-- RESOLVED: H1 — Profile uses @Query for all adherence logs + computed property for today -->
**Add state variables:**
```swift
@State private var showSupplementList = false
@Query private var allSupplements: [SupplementEntry]
@Query(sort: \AdherenceLog.day, order: .reverse) private var allAdherenceLogs: [AdherenceLog]
@StateObject private var supplementService = SupplementService()
```

**Computed property for today's adherence:**
```swift
private var todayAdherenceLogs: [AdherenceLog] {
    allAdherenceLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
}
```

**Insert "Health Regimen" card** between `symptomInsightsCard` (conditional) and `WidgetSetupCard` (~line 141):

- "Add" button → `activeSheet = .addSupplement`
- "View All" → `showSupplementList = true`
- Shows today's adherence if supplements exist; empty state CTA otherwise
- Progress bar: filled portion = taken%, color = brand

**Add to sheet switch:**
```swift
case .addSupplement:
    AddSupplementSheet(service: supplementService)
```

**Add navigation destination:**
```swift
.navigationDestination(isPresented: $showSupplementList) {
    SupplementListView(service: supplementService)
}
```

**Create pending logs on appear**: In `.task {}` modifier, call `supplementService.createPendingLogs(context: modelContext, supplements: allSupplements)`.

<!-- RESOLVED: M2 — Preview explicitly updated with all 4 model types -->
**Update preview:**
```swift
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: SymptomEntry.self, UserGoals.self, SupplementEntry.self, AdherenceLog.self,
        configurations: config
    )
    return ProfilePlaceholderView()
        .modelContainer(container)
}
```

- **Dependencies**: Steps 1–7
- **Risk**: Medium (adding more @Query and @StateObject to already complex Profile view)

---

### Phase 7: Correlation Extension

#### Step 9. Extend SymptomCorrelationEngine with Adherence Factor
**File**: `WellPlate/Core/Services/SymptomCorrelationEngine.swift`

**Update `computeCorrelations` signature** — add new parameter:
```swift
func computeCorrelations(
    symptomName: String,
    symptomEntries: [SymptomEntry],
    foodLogs: [FoodLogEntry],
    wellnessLogs: [WellnessDayLog],
    stressReadings: [StressReading],
    sleepHours: [Date: Double],
    adherenceByDay: [Date: Double] = [:]   // ← add, 0.0–1.0 per day
) async
```

**Add 8th factor** to the factors array (after Water, ~line 73):
```swift
Factor(name: "Supplement adherence", icon: "pill.fill") { day in
    adherenceByDay.isEmpty ? nil : adherenceByDay[day]
}
```

The `.isEmpty` guard ensures the factor is skipped entirely when no adherence data is provided (backward compat with F5 callers using default `[:]`).

- **Dependencies**: Steps 1–4
- **Risk**: Low (additive change, backward compatible)

---

### Phase 8: CSV Export Extension

#### Step 10. Extend WellnessReportGenerator CSV
**File**: `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift`

**Update signature** — add adherence logs:
```swift
static func generateCSV(
    foodLogs: [FoodLogEntry],
    stressReadings: [StressReading],
    wellnessLogs: [WellnessDayLog],
    symptomEntries: [SymptomEntry] = [],
    adherenceLogs: [AdherenceLog] = []      // ← add
) -> Data
```

**Update CSV header**:
```
date,stress_score,calories,protein_g,carbs_g,fat_g,fiber_g,steps,water_glasses,mood,symptom,symptom_severity,supplement_adherence_pct
```

**Add adherence aggregation per day**: group logs by day, compute (taken count / total count) × 100. Days with no supplements: empty cell.

- **Dependencies**: Steps 1–3
- **Risk**: Low

---

### Phase 9: Build Verification

#### Step 11. Build All Targets
Run all 4 build commands. Fix any compilation errors.

- **Dependencies**: All previous steps
- **Risk**: Low

## Testing Strategy

### Build Verification
- All 4 targets compile cleanly

### Manual Verification Flows
1. **Add supplement**: Profile → + Add → fill form → save → supplement appears in list
2. **Schedule notifications**: Add supplement with times → verify notification scheduled
3. **Mark dose taken**: Supplement list → tap pending dose → status changes to "taken" with timestamp + haptic
4. **Adherence tracking**: Log multiple days → adherence % and streak update correctly
5. **Edit supplement**: Swipe → edit → change time → notifications rescheduled
6. **Delete supplement**: Swipe → delete → notifications cleared, adherence logs remain for history
7. **Profile card**: Shows today's adherence summary + streak
8. **Auto-resolve**: Yesterday's pending logs become "skipped" on app appear
9. **Correlation**: After ≥7 days of symptom + supplement data, 8th factor appears in `SymptomCorrelationView`
10. **CSV export**: Report contains `supplement_adherence_pct` column
11. **Empty states**: No supplements → "Add your first supplement" CTA
12. **Notifications disabled**: User denies notification permission → supplements still work, just no reminders
13. **ProfileView preview**: Renders without crash with all 4 model types
14. **Today filter**: `todayLogs` computed property correctly filters to current day

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Notification fatigue (many supplements × doses) | Medium | Per-supplement `notificationsEnabled` toggle; batch option in v2 |
| Profile view complexity | Medium | Supplement card is self-contained view; Profile just hosts it |
| SwiftData [Int] array behavior | Low | Proven by `FoodLogEntry.eatingTriggers: [String]?` |
| Adherence auto-resolve timing | Low | Runs in `createPendingLogs` on `.task {}` — marks previous-day pending as skipped |
| Many AdherenceLog entries over time | Low | @Query with computed property filter; ~300 entries/month |

## Success Criteria

- [ ] Add/edit/delete supplements with name, dose, category, times
- [ ] Daily notification reminders at scheduled times
- [ ] Mark doses as taken/skipped with timestamps
- [ ] Adherence % and streak on Profile card
- [ ] Supplement list with today's dose statuses (computed property filter, not @Query predicate)
- [ ] Detail view with 30-day adherence calendar
- [ ] 8th correlation factor (adherence) in SymptomCorrelationEngine
- [ ] CSV export includes `supplement_adherence_pct` column
- [ ] All 4 build targets compile cleanly
- [ ] ProfileView preview renders with all 4 model types
- [ ] Yesterday's pending logs auto-resolve to skipped
- [ ] No medication database or dosing advice anywhere
