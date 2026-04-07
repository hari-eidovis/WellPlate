# Implementation Plan: Supplement / Medication Reminders

**Date**: 2026-04-08
**Source**: `Docs/02_Planning/Specs/260408-supplement-medication-strategy.md`
**Status**: Ready for Audit

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
| **Modify** | `WellPlate/Features + UI/Tab/ProfileView.swift` | Add `.addSupplement` to `ProfileSheet`, supplement card in body |
| **Modify** | `WellPlate/Core/Services/SymptomCorrelationEngine.swift` | Add `adherenceByDay` parameter + 8th factor |
| **Modify** | `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` | Add `supplement_adherence_pct` CSV column |

## Implementation Steps

### Phase 1: Data Layer

#### Step 1. Create `SupplementEntry` SwiftData Model
**File**: `WellPlate/Models/SupplementEntry.swift` (new)

```swift
import Foundation
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

**createPendingLogs** — called on app appear: for each active supplement, for today, create `AdherenceLog` entries with status "pending" for each scheduled dose that doesn't already have a log entry.

**todayAdherencePercent** — count taken / total today logs. Returns 0.0–1.0.

**currentStreak** — walk backwards from today, counting consecutive days where all scheduled doses were taken (no skipped or pending from previous days).

**adherenceByDay** — aggregate logs into `[Date: Double]` dictionary (0.0–1.0 per day) for correlation engine.

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

**Save action**: Create or update `SupplementEntry`, call `service.scheduleNotifications(for:)`, dismiss.

- **Dependencies**: Steps 1, 4
- **Risk**: Low

---

### Phase 4: UI — Supplement List

#### Step 6. Create `SupplementListView`
**File**: `WellPlate/Features + UI/Supplements/Views/SupplementListView.swift` (new)

Main supplement management view, presented as `navigationDestination` from Profile.

```
┌─────────────────────────────────────┐
│ ← Health Regimen            [+ Add] │
│─────────────────────────────────────│
│                                     │
│ Today's Adherence: 75% (3/4)       │
│ ████████████░░░░  Streak: 8 days   │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ ✓ Magnesium 400mg     8:00 AM  │ │
│ │   taken at 8:12 AM             │ │
│ ├─────────────────────────────────┤ │
│ │ ○ Vitamin D3 5000IU   8:00 AM  │ │
│ │   pending                      │ │
│ ├─────────────────────────────────┤ │
│ │ ✓ Omega-3 1000mg      8:00 PM  │ │
│ │   taken at 8:05 PM             │ │
│ ├─────────────────────────────────┤ │
│ │ ○ Probiotic           8:00 PM  │ │
│ │   pending                      │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**Data:**
```swift
@Query private var supplements: [SupplementEntry]
@Query private var todayLogs: [AdherenceLog]  // filtered to today in init
```

**Features:**
- Today's adherence percentage bar + streak counter at top
- List of all active supplements with today's dose statuses
- Tap dose row → toggle taken/pending
- Swipe supplement → edit (opens `AddSupplementSheet` in edit mode) or delete (with cascade clear of notifications)
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

**Add state variables:**
```swift
@State private var showSupplementList = false
@Query private var allSupplements: [SupplementEntry]
@Query private var todayAdherenceLogs: [AdherenceLog]
@StateObject private var supplementService = SupplementService()
```

**Insert "Health Regimen" card** between `symptomInsightsCard` (conditional) and `WidgetSetupCard` (~line 141):

```
┌─────────────────────────────────────┐
│ 💊 Health Regimen          [+ Add]  │
│                                     │
│ Today: 3/4 doses taken  Streak: 8d │
│ ████████████░░░░░                   │
│                                     │
│ [View All →]                        │
└─────────────────────────────────────┘
```

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

**Create pending logs on appear**: In `.onAppear` or `.task`, call `supplementService.createPendingLogs()` to ensure today's scheduled doses have AdherenceLog entries.

**Update preview** to include `SupplementEntry.self`, `AdherenceLog.self` alongside existing `SymptomEntry.self`, `UserGoals.self`.

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
    adherenceByDay[day]
}
```

Default `[:]` ensures existing callers (F5 symptom views) continue to work without changes.

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

**Add adherence aggregation per day**: group logs by day, compute taken/total × 100.

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
2. **Schedule notifications**: Add supplement with times → verify notification scheduled (check Settings → Notifications)
3. **Mark dose taken**: Supplement list → tap pending dose → status changes to "taken" with timestamp + haptic
4. **Adherence tracking**: Log multiple days → adherence % and streak update correctly
5. **Edit supplement**: Swipe → edit → change time → notifications rescheduled
6. **Delete supplement**: Swipe → delete → notifications cleared, adherence logs remain for history
7. **Profile card**: Shows today's adherence summary + streak
8. **Correlation**: After ≥7 days of symptom + supplement data, 8th factor appears in `SymptomCorrelationView`
9. **CSV export**: Report contains `supplement_adherence_pct` column
10. **Empty states**: No supplements → "Add your first supplement" CTA
11. **Notifications disabled**: User denies notification permission → supplements still work, just no reminders
12. **ProfileView preview**: Renders without crash

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Notification fatigue (many supplements × doses) | Medium | Per-supplement `notificationsEnabled` toggle; batch summary option in v2 |
| Profile view complexity | Medium | Supplement card is self-contained view; Profile just hosts it |
| SwiftData [Int] array behavior | Low | Proven by `FoodLogEntry.eatingTriggers: [String]?` |
| Adherence auto-resolve at midnight | Low | Use `createPendingLogs` on appear; mark yesterday's pending as skipped |
| Many AdherenceLog entries over time | Low | Query with date predicate; ~300 entries/month for 10 supplements |

## Success Criteria

- [ ] Add/edit/delete supplements with name, dose, category, times
- [ ] Daily notification reminders at scheduled times
- [ ] Mark doses as taken/skipped with timestamps
- [ ] Adherence % and streak on Profile card
- [ ] Supplement list with today's dose statuses
- [ ] Detail view with 30-day adherence calendar
- [ ] 8th correlation factor (adherence) in SymptomCorrelationEngine
- [ ] CSV export includes `supplement_adherence_pct` column
- [ ] All 4 build targets compile cleanly
- [ ] No medication database or dosing advice anywhere
