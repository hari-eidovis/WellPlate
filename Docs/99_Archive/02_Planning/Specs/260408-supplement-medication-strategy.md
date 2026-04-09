# Strategy: Supplement / Medication Reminders

**Date**: 2026-04-08
**Source**: `Docs/01_Brainstorming/260408-supplement-medication-brainstorm.md`
**Status**: Ready for Planning

## Chosen Approach

**Unified Tracker (Approach 3 from brainstorm) with supplement-first framing**

One `SupplementEntry` @Model handles both supplements and medications via a `category` field. `AdherenceLog` @Model tracks daily dose status (taken/skipped/pending). Notifications use the proven `FastingService.swift` pattern (`UNCalendarNotificationTrigger`, on-demand permission). Extends `SymptomCorrelationEngine` with an 8th factor (adherence %) to surface "did taking X correlate with fewer Y?" insights. Profile tab gets a new "Health Regimen" card. HealthKit Medications API read is optional via an "Import from Health" button.

## Rationale

- **Unified model avoids bifurcation**: A single `SupplementEntry` with `.medication` category is cleaner than two parallel models. The code, UI, and notifications all treat them identically.
- **`FastingService` pattern is copy-ready**: Lines 186–273 implement the full notification lifecycle (permission request, calendar trigger scheduling, batch clear). The same pattern applies with `supplement_\(id)_\(time)` notification IDs.
- **F5 correlation synergy is the differentiator**: The `SymptomCorrelationEngine` already computes Spearman r with bootstrap CI against 7 factors. Adding `adherenceByDay` as an 8th factor requires ~15 lines of code in the engine + passing the data through. The payoff — "Your headaches are 40% less frequent on days you take magnesium (r=−0.43, N=18)" — is what no basic reminder app delivers.
- **Profile card pattern proven**: F5 added `symptomTrackingCard` + `symptomInsightsCard` to ProfileView. A `supplementCard` follows the identical pattern (recent entries, quick-log, navigation to detail).
- **HealthKit import is a delight, not a dependency**: Most users will enter supplements manually. HealthKit import reads existing medications for those who have them — zero data entry for that subset.

### Trade-offs accepted
- No medication database or dosing lookup — user enters free-text names and doses
- No smart drug interaction checking — out of scope forever (clinical liability)
- HealthKit Medications API is iOS 16+ and may not be available on all devices — feature works fully without it
- Adherence correlation requires both symptom data (F5) AND supplement data (F6) for ≥7 paired days — surface only when available

## Affected Files & Components

### New Files (~6)
| File | Purpose |
|---|---|
| `WellPlate/Models/SupplementEntry.swift` | SwiftData @Model — name, dosage, category, scheduledTimes, activeDays, isActive |
| `WellPlate/Models/AdherenceLog.swift` | SwiftData @Model — day, supplementID, scheduledTime, status (taken/skipped), takenAt |
| `WellPlate/Core/Services/SupplementService.swift` | Notification scheduling, adherence tracking, adherence aggregation |
| `WellPlate/Features + UI/Supplements/Views/SupplementListView.swift` | List of supplements with adherence status, add/edit/delete |
| `WellPlate/Features + UI/Supplements/Views/SupplementDetailView.swift` | Detail view for one supplement: schedule, adherence calendar, correlation |
| `WellPlate/Features + UI/Supplements/Views/AddSupplementSheet.swift` | Add/edit supplement form (name, dose, category, times, days) |

### Modified Files (~4)
| File | Change |
|---|---|
| `WellPlate/App/WellPlateApp.swift` | Add `SupplementEntry.self`, `AdherenceLog.self` to model container |
| `WellPlate/Features + UI/Tab/ProfileView.swift` | Add supplement card + `.supplementSetup` to `ProfileSheet` enum |
| `WellPlate/Core/Services/SymptomCorrelationEngine.swift` | Add 8th factor (adherence %) + new parameter `adherenceByDay: [Date: Double]` |
| `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` | Add `supplement_adherence_pct` column to CSV |

### Untouched (explicitly)
- `HomeView.swift` — No home header icon for supplements (already 4 icons + badge; Profile tab is the right home)
- `HealthKitService.swift` — HealthKit medication import deferred to v2 or done in `SupplementService` separately
- `FastingService.swift` — referenced as pattern but not modified

## Architectural Direction

### Data Models

```
SupplementEntry (@Model)
├── id: UUID
├── name: String              // "Magnesium", "Vitamin D3", "Metformin"
├── dosage: String            // "400mg", "5000 IU", "500mg"
├── category: String          // Raw value of SupplementCategory enum
├── scheduledTimes: [Int]     // Minutes from midnight, e.g. [480, 1200] = 8:00 AM, 8:00 PM
├── activeDays: [Int]         // 0=Sun..6=Sat; empty = every day
├── isActive: Bool
├── notes: String?
├── startDate: Date
├── createdAt: Date
```

```
AdherenceLog (@Model)
├── id: UUID
├── supplementName: String    // Denormalized for query simplicity
├── supplementID: UUID        // Links to SupplementEntry.id
├── day: Date                 // Calendar.startOfDay
├── scheduledMinute: Int      // Which dose (480 = 8am dose)
├── status: String            // "taken", "skipped", "pending"
├── takenAt: Date?            // When the user tapped "taken"
├── createdAt: Date
```

Using denormalized `supplementName` in `AdherenceLog` avoids cross-model lookups for display and export. `supplementID` maintains the FK link for integrity.

### Supplement Category
```swift
enum SupplementCategory: String, CaseIterable, Identifiable, Codable {
    case vitamin, mineral, omega, probiotic, herb, protein, medication, custom
    var label: String { ... }
    var icon: String { ... }    // SF Symbol
    var color: Color { ... }
}
```

### SupplementService
```swift
@MainActor
final class SupplementService: ObservableObject {
    @Published var todayAdherence: [AdherenceLog] = []
    @Published var notificationsBlocked: Bool = false

    func scheduleNotifications(for supplement: SupplementEntry) async { ... }
    func clearNotifications(for supplement: SupplementEntry) { ... }
    func markDose(supplementID: UUID, scheduledMinute: Int, status: String) { ... }
    func todayAdherencePercent(context: ModelContext) -> Double { ... }
    func adherenceByDay(entries: [AdherenceLog]) -> [Date: Double] { ... }
}
```

Follows `FastingService` pattern: request permission on-demand, use `UNCalendarNotificationTrigger(dateMatching:repeats:true)`, manage IDs as `"supplement_\(id)_\(minute)"`.

### Notification Flow
```
User adds "Magnesium 400mg" at 8:00 AM, 8:00 PM, every day
→ SupplementService.scheduleNotifications() creates:
    - ID "supplement_<uuid>_480"  → trigger 08:00 daily → "Time for Magnesium (400mg)"
    - ID "supplement_<uuid>_1200" → trigger 20:00 daily → "Time for Magnesium (400mg)"
→ User taps notification → opens app → AdherenceLog status = "taken"
→ End of day: unfulfilled logs auto-marked "pending" (user can mark next morning)
```

### Correlation Extension
Add to `SymptomCorrelationEngine.computeCorrelations()`:
```swift
// 8th factor: supplement adherence
func computeCorrelations(
    ...existing params...,
    adherenceByDay: [Date: Double] = [:]   // 0.0–1.0 per day
) async
```

New factor in the array:
```swift
Factor(name: "Supplement adherence", icon: "pill.fill") { day in adherenceByDay[day] }
```

This allows questions like "On days you took all your supplements, were your headaches less severe?"

### UI Flow
```
Profile tab → "Health Regimen" card → SupplementListView (navigationDestination)
    ├── List of supplements with today's adherence (✓ taken, ○ pending, ✕ skipped)
    ├── Tap supplement → SupplementDetailView (adherence calendar + stats)
    └── + button → AddSupplementSheet (sheet via ProfileSheet enum)

Profile "Health Regimen" card:
    ├── Today's adherence: "3/4 doses taken"
    ├── Streak: "12 days" (consecutive 100% days)
    └── Quick-mark pending doses
```

### CSV Export
Add to `WellnessReportGenerator.swift` header:
```
...,supplement_adherence_pct
```
Per day: percentage of scheduled doses taken (0–100). Days with no supplements: empty.

## Design Constraints

1. **`SupplementEntry` framing, not `MedicationEntry`** — less clinical, broader audience
2. **Notification IDs: `"supplement_\(id.uuidString)_\(scheduledMinute)"`** — unique per supplement per dose time
3. **No drug interaction or dosing advice** — pure logging and correlation
4. **Permission request on-demand** — when user enables first supplement, not on app launch
5. **Profile tab only** — no Home header icon (already 4 + badge)
6. **End-of-day handling**: `pending` status persists until user acts or next day starts; auto-resolve to `skipped` at midnight+1h to keep streaks honest
7. **Adherence correlation minimum**: Same ≥7 paired days as symptom correlations

## Non-Goals

- **Drug interaction checking**: Never — clinical liability
- **Dosing recommendations**: Never — user enters their own
- **HealthKit Medications write-back**: Read-only if implemented
- **HealthKit Medications import in MVP**: Defer to v2 — manual entry is sufficient
- **Push notifications**: Local only — no backend
- **Prescription refill tracking**: Out of scope
- **Supplement database/autocomplete**: User types free-text names
- **Home header icon**: Profile tab is sufficient; header already full

## Open Risks

- **Notification fatigue**: 5 supplements × 2 doses = 10 daily notifications. Mitigation: per-supplement notification toggle, batch "morning reminders" option in v2
- **SwiftData performance with many AdherenceLog entries**: ~30 entries/month per supplement. At 10 supplements = ~300/month. Mitigation: query with date predicate, not full scan
- **SupplementEntry.scheduledTimes as [Int]**: Array of primitives in SwiftData works with `@Attribute(.transformable)` or by storing as JSON-encoded string. Need to verify SwiftData handles `[Int]` natively — if not, store as comma-separated string.
- **Midnight adherence auto-resolve**: Timer or `.onChange(of: scenePhase)` to mark yesterday's pending as skipped. Risk: user opens app at 11:59pm, pending items flip to skipped a minute later. Mitigation: use 2am cutoff, not midnight.
