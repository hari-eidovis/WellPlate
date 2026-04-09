# Implementation Plan: Symptom Tracking Correlated with Food/Sleep

**Date**: 2026-04-08
**Source**: `Docs/02_Planning/Specs/260408-symptom-tracking-strategy.md`
**Status**: Ready for Audit

## Overview

Add symptom tracking with transparent statistical correlations. Users log symptoms in a 3-tap sheet (category → symptom → severity → save) accessible from both HomeView header and Profile tab. Profile tab evolves from placeholder to a "Know Yourself" hub with symptom history and correlation cards. Correlation engine computes Spearman rank correlation with bootstrapped 95% CI, shown only after ≥7 paired days. CSV export extended with symptom columns.

## Requirements

- R1: Log symptoms with name, category, severity (1–10), and timestamp
- R2: 20 preset symptoms in 4 categories + custom symptoms
- R3: Spearman rank correlation against 7 daily factors (sleep, stress, caffeine, calories, protein, fiber, water)
- R4: Effect sizes + CI bands + N on every correlation card; "correlation ≠ causation" language
- R5: Correlation only surfaces after ≥7 paired days
- R6: Symptom history view with severity badges and delete
- R7: Extend CSV export with `symptom_name`, `symptom_max_severity` columns
- R8: Follow existing UI conventions (`.system()` fonts, card styling, haptics)

## Architecture Changes

| Type | File | Change |
|------|------|--------|
| **New** | `WellPlate/Models/SymptomEntry.swift` | SwiftData `@Model` for symptom log entries |
| **New** | `WellPlate/Models/SymptomDefinition.swift` | Symptom library (20 presets, 4 categories) + custom |
| **New** | `WellPlate/Core/Services/SymptomCorrelationEngine.swift` | Spearman r + bootstrapped 95% CI |
| **New** | `WellPlate/Features + UI/Symptoms/Views/SymptomLogSheet.swift` | 3-tap quick-log sheet |
| **New** | `WellPlate/Features + UI/Symptoms/Views/SymptomHistoryView.swift` | Past entries with severity badges |
| **New** | `WellPlate/Features + UI/Symptoms/Views/SymptomCorrelationView.swift` | Correlation cards + CI band visualization |
| **Modify** | `WellPlate/App/WellPlateApp.swift` | Add `SymptomEntry.self` to model container |
| **Modify** | `WellPlate/Features + UI/Tab/ProfileView.swift` | Add symptom sections to `ProfilePlaceholderView` |
| **Modify** | `WellPlate/Features + UI/Home/Views/HomeView.swift` | Add `.symptomLog` to `HomeSheet` enum, header icon, state |
| **Modify** | `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` | Add symptom columns to CSV |

## Implementation Steps

### Phase 1: Data Layer

#### Step 1. Create `SymptomDefinition` Library
**File**: `WellPlate/Models/SymptomDefinition.swift` (new)

Plain struct (not @Model) defining the symptom catalog:

```swift
enum SymptomCategory: String, CaseIterable, Identifiable, Codable {
    case digestive, pain, energy, cognitive
    var id: String { rawValue }

    var label: String { ... }   // "Digestive", "Pain", etc.
    var icon: String { ... }    // SF Symbol per category
    var color: Color { ... }    // Accent color per category
}

struct SymptomDefinition: Identifiable, Hashable {
    let name: String
    let category: SymptomCategory
    let icon: String            // SF Symbol
    let isCustom: Bool

    var id: String { name }
}
```

Include `static let library: [SymptomDefinition]` with 20 presets:
- **Digestive (5)**: Bloating, Nausea, Acid reflux, Stomach pain, Irregular digestion
- **Pain (5)**: Headache, Migraine, Joint pain, Muscle soreness, Back pain
- **Energy (5)**: Fatigue, Energy crash, Brain fog, Dizziness, Insomnia
- **Cognitive (5)**: Anxiety, Irritability, Low mood, Difficulty concentrating, Restlessness

Include `static func custom(name: String) -> SymptomDefinition` for user-defined symptoms.

- **Dependencies**: None
- **Risk**: Low

#### Step 2. Create `SymptomEntry` SwiftData Model
**File**: `WellPlate/Models/SymptomEntry.swift` (new)

```swift
@Model
final class SymptomEntry {
    var id: UUID
    var name: String              // Symptom name (e.g. "Headache")
    var category: String          // Raw value of SymptomCategory
    var severity: Int             // 1–10
    var timestamp: Date           // Exact time of logging
    var day: Date                 // Calendar.startOfDay — for daily aggregation
    var notes: String?
    var createdAt: Date

    init(name:category:severity:timestamp:notes:)
    var resolvedCategory: SymptomCategory? { ... }
}
```

Follow `StressReading` pattern: store enum raw values, compute resolved property.

- **Dependencies**: Step 1
- **Risk**: Low

#### Step 3. Register `SymptomEntry` in ModelContainer
**File**: `WellPlate/App/WellPlateApp.swift` (line 34)

Add `SymptomEntry.self` after `JournalEntry.self` in `.modelContainer(for:)`.

- **Dependencies**: Step 2
- **Risk**: Low

---

### Phase 2: Correlation Engine

#### Step 4. Create `SymptomCorrelationEngine`
**File**: `WellPlate/Core/Services/SymptomCorrelationEngine.swift` (new)

**Result struct:**
```swift
struct SymptomCorrelation: Identifiable {
    let id = UUID()
    let symptomName: String
    let factorName: String
    let factorIcon: String      // SF Symbol
    let spearmanR: Double       // −1 to +1
    let ciLow: Double           // 2.5th percentile
    let ciHigh: Double          // 97.5th percentile
    let pairedDays: Int
    let interpretation: String  // Auto-generated label
    let isSignificant: Bool     // CI doesn't span zero
}
```

**Engine class:**
```swift
@MainActor
final class SymptomCorrelationEngine: ObservableObject {
    @Published var correlations: [SymptomCorrelation] = []
    @Published var isComputing: Bool = false

    func computeCorrelations(
        symptomName: String,
        symptomEntries: [SymptomEntry],
        foodLogs: [FoodLogEntry],
        wellnessLogs: [WellnessDayLog],
        stressReadings: [StressReading],
        sleepHours: [Date: Double]    // From HealthKit, keyed by day
    ) async { ... }
}
```

**Spearman rank correlation implementation:**
1. Aggregate symptom entries by day: max severity per day
2. For each of 7 factors, build paired arrays `[(symptomSeverity, factorValue)]`
3. Require ≥7 paired days; skip factor if insufficient
4. Convert both arrays to ranks (handle ties with average rank)
5. Compute Pearson r on ranks = Spearman r
6. Bootstrap 95% CI: 1000 iterations, resample pairs with replacement, recompute Spearman r, extract 2.5th/97.5th percentiles (NOT 5th/95th — use 95% CI to match medical convention, unlike the stress lab's 90%)

**7 factors to correlate against:**
| Factor | Source | Aggregation |
|--------|--------|-------------|
| Sleep hours | HealthKit (passed in) | Daily total |
| Stress score | `StressReading` | Daily avg |
| Caffeine | `WellnessDayLog.coffeeCups` | Daily count |
| Calories | `FoodLogEntry` | Daily sum |
| Protein | `FoodLogEntry` | Daily sum |
| Fiber | `FoodLogEntry` | Daily sum |
| Water | `WellnessDayLog.waterGlasses` | Daily count |

**Interpretation label generation:**
```swift
func interpretationLabel(r: Double, ciSpansZero: Bool) -> String {
    if ciSpansZero { return "No clear pattern (yet)" }
    let direction = r > 0 ? "positive" : "negative"
    let strength: String
    switch abs(r) {
    case 0..<0.3: strength = "weak"
    case 0.3..<0.6: strength = "moderate"
    default: strength = "strong"
    }
    return "\(strength) \(direction) association"
}
```

**Performance**: Run `computeCorrelations()` off the main actor in a `Task.detached` with `@Sendable` parameters. 7 factors × 1000 bootstrap iterations = 7000 random resamples — completes in <100ms.

- **Dependencies**: Steps 1–3
- **Risk**: Medium (statistical correctness must be verified)

---

### Phase 3: UI — Symptom Log Sheet

#### Step 5. Create `SymptomLogSheet`
**File**: `WellPlate/Features + UI/Symptoms/Views/SymptomLogSheet.swift` (new)

3-step flow in a single sheet:

**Step 1 — Category picker:**
```
┌─────────────────────────────────────┐
│ ✕  Log Symptom                      │
│                                     │
│ What kind of symptom?               │
│                                     │
│ ┌──────────┐  ┌──────────┐         │
│ │ 🫄        │  │ 🤕        │         │
│ │ Digestive │  │ Pain      │         │
│ └──────────┘  └──────────┘         │
│ ┌──────────┐  ┌──────────┐         │
│ │ ⚡        │  │ 🧠        │         │
│ │ Energy   │  │ Cognitive │         │
│ └──────────┘  └──────────┘         │
└─────────────────────────────────────┘
```

**Step 2 — Symptom picker:**
5 symptom pills per category + "Custom" pill at end. Custom triggers a `TextField` for name entry.

**Step 3 — Severity + save:**
```
┌─────────────────────────────────────┐
│ ← Back        Headache      [Save]  │
│                                     │
│ How severe?                         │
│                                     │
│ 1 ───────────●──────────── 10       │
│            Severity: 6              │
│                                     │
│ Notes (optional)                    │
│ ┌─────────────────────────────────┐ │
│ │ Started after lunch...          │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**State management:**
```swift
struct SymptomLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var step: LogStep = .category
    @State private var selectedCategory: SymptomCategory?
    @State private var selectedSymptom: SymptomDefinition?
    @State private var severity: Double = 5
    @State private var notes: String = ""
    @State private var customName: String = ""

    enum LogStep { case category, symptom, severity }
}
```

Save creates `SymptomEntry` and calls `modelContext.save()`. Dismiss on save with `HapticService.notify(.success)`.

Presentation: `.presentationDetents([.medium, .large])` with `.presentationDragIndicator(.visible)`.

- **Dependencies**: Steps 1–2
- **Risk**: Low

---

### Phase 4: UI — Symptom History

#### Step 6. Create `SymptomHistoryView`
**File**: `WellPlate/Features + UI/Symptoms/Views/SymptomHistoryView.swift` (new)

Chronological list of past symptom entries. Presented as a `navigationDestination` from Profile.

**Layout:**
- Navigation title: "Symptom History"
- Entries grouped by relative date (Today, Yesterday, then date)
- Each entry: symptom icon + name, category pill, severity badge (color-coded 1–10), time, optional notes
- Swipe to delete with confirmation
- Empty state: "No symptoms logged yet"

**Severity color scale:** 1–3 green, 4–6 amber, 7–10 red.

**Data source:**
```swift
@Query(sort: \SymptomEntry.timestamp, order: .reverse) private var entries: [SymptomEntry]
```

- **Dependencies**: Steps 1–2
- **Risk**: Low

---

### Phase 5: UI — Correlation View

#### Step 7. Create `SymptomCorrelationView`
**File**: `WellPlate/Features + UI/Symptoms/Views/SymptomCorrelationView.swift` (new)

Scrollable list of correlation cards for a specific symptom. Accessible from Profile tab.

**Layout:**
```
┌─────────────────────────────────────┐
│ ← Headache Insights       N=14     │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ ↔ Caffeine                      │ │
│ │ r = 0.52 moderate positive      │ │
│ │ [=====■=====] CI band           │ │
│ │ 95% CI: [0.18, 0.79]           │ │
│ │ ⚠ Correlation ≠ causation      │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ ↔ Sleep hours                   │ │
│ │ r = -0.38 moderate negative     │ │
│ │ [===■=======] CI band           │ │
│ │ 95% CI: [-0.65, -0.04]         │ │
│ │ ⚠ Correlation ≠ causation      │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─ Collecting data ─────────────┐  │
│ │ ↔ Fiber        3/7 days       │  │
│ └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Props:**
```swift
struct SymptomCorrelationView: View {
    let symptomName: String
    @ObservedObject var engine: SymptomCorrelationEngine
}
```

**Correlation card component** (inline or separate private view):
- Header: factor icon + name
- r value + interpretation label
- CI band: `GeometryReader` visualization following `StressLabResultView` pattern (lines 122–164) — gray background capsule, brand-colored CI range band, dot at r value, zero-line reference
- Range: −1.0 to +1.0 (not ±40 like stress lab)
- "95% CI: [X, Y]" text
- Disclaimer footer: "Correlation does not imply causation. Track more days to strengthen confidence."
- "Collecting data" card when pairedDays < 7: shows progress "X/7 days"

- **Dependencies**: Steps 4, 6
- **Risk**: Low–Medium (CI band rendering needs testing)

---

### Phase 6: Profile Tab Integration

#### Step 8. Add Symptom Sections to ProfilePlaceholderView
**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`

**Add new state variables:**
```swift
@State private var showSymptomLog = false
@State private var showSymptomHistory = false
@State private var showSymptomCorrelation = false
@State private var selectedSymptomForCorrelation: String?
@Query(sort: \SymptomEntry.timestamp, order: .reverse) private var allSymptomEntries: [SymptomEntry]
@StateObject private var correlationEngine = SymptomCorrelationEngine()
```

**Insert between goalsSnapshotCard and WidgetSetupCard** (around line 108 in current body order):

**Section A — "Symptom Tracking" card:**
```
┌─────────────────────────────────────┐
│ 🩺 Symptom Tracking        [Log +] │
│                                     │
│ Recent: Headache (6/10) 2h ago     │
│         Fatigue (4/10) today       │
│                                     │
│ [View History →]                    │
└─────────────────────────────────────┘
```
- Shows last 2–3 entries with severity + relative time
- "Log +" button opens `SymptomLogSheet` (sheet)
- "View History →" navigates to `SymptomHistoryView`

**Section B — "Symptom Insights" card** (only shows when ≥7 days of symptom data):
```
┌─────────────────────────────────────┐
│ 📊 Symptom Insights                │
│                                     │
│ Headache → moderate link to caffeine│
│ Fatigue  → weak link to sleep      │
│                                     │
│ [See Details →]                     │
└─────────────────────────────────────┘
```
- Summary of strongest correlations per tracked symptom
- "See Details →" navigates to `SymptomCorrelationView` for that symptom

**Add navigation destinations:**
```swift
.navigationDestination(isPresented: $showSymptomHistory) {
    SymptomHistoryView()
}
.navigationDestination(isPresented: $showSymptomCorrelation) {
    if let name = selectedSymptomForCorrelation {
        SymptomCorrelationView(symptomName: name, engine: correlationEngine)
    }
}
```

**Add sheet for SymptomLogSheet** — use new ProfileSheet enum or boolean:
```swift
.sheet(isPresented: $showSymptomLog) {
    SymptomLogSheet()
}
```

**Compute correlations on appear** for top-tracked symptoms (limit to top 3 by entry count).

- **Dependencies**: Steps 1–7
- **Risk**: Medium (Profile restructure touches a 700+ line file)

---

### Phase 7: Home Integration

#### Step 9. Add Symptom Quick-Log to HomeView
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Add `.symptomLog` case to `HomeSheet` enum** (around line 5):
```swift
enum HomeSheet: Identifiable {
    case coffeeTypePicker
    case journalEntry
    case symptomLog       // ← add

    var id: String {
        switch self {
        case .coffeeTypePicker: return "coffeeTypePicker"
        case .journalEntry: return "journalEntry"
        case .symptomLog: return "symptomLog"
        }
    }
}
```

**Add symptom log to sheet switch** (in `.sheet(item: $activeSheet)`):
```swift
case .symptomLog:
    SymptomLogSheet()
```

**Add header icon** — insert in `homeHeader` before the journal book icon (to keep consistent ordering: AI, Calendar, Symptom, Journal, Mood badge):
```swift
// Symptom quick-log button
Button {
    HapticService.impact(.light)
    activeSheet = .symptomLog
} label: {
    ZStack {
        Circle()
            .fill(LinearGradient(...))
            .frame(width: 44, height: 44)
            .shadow(...)
        Image(systemName: "heart.text.square.fill")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}
.buttonStyle(.plain)
```

**Note on header icon count**: After this change, header will have 4 icons (AI, Calendar, Symptom, Journal) + mood badge. On iPhone SE (375pt), this is tight. If it overflows, fall back to showing symptom icon only when mood badge is hidden (i.e. mood not logged yet), or reduce icon sizes to 38pt. Test on SE simulator.

- **Dependencies**: Steps 5, 8
- **Risk**: Low–Medium (header space constraint on small screens)

---

### Phase 8: CSV Export Extension

#### Step 10. Extend WellnessReportGenerator CSV
**File**: `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift`

**Update `generateCSV` signature** to accept symptom entries:
```swift
static func generateCSV(
    foodLogs: [FoodLogEntry],
    stressReadings: [StressReading],
    wellnessLogs: [WellnessDayLog],
    symptomEntries: [SymptomEntry] = []   // ← add, default empty for backward compat
) -> Data
```

**Update CSV header** (line 37):
```
date,stress_score,calories,protein_g,carbs_g,fat_g,steps,water_glasses,mood,symptom,symptom_severity
```

**Add symptom aggregation per day:**
```swift
let symptomByDay = Dictionary(grouping: symptomEntries.filter { $0.day >= cutoff }) { $0.day }
```

**Per day row:** find highest-severity symptom for the day:
```swift
let daySymptoms = symptomByDay[day] ?? []
let worstSymptom = daySymptoms.max(by: { $0.severity < $1.severity })
let symptomName = worstSymptom?.name ?? ""
let symptomSev = worstSymptom.map { String($0.severity) } ?? ""
```

Append to row string: `...,\(symptomName),\(symptomSev)`

**Update all callers** of `generateCSV` to pass symptom entries (or rely on default `[]`).

- **Dependencies**: Steps 1–3
- **Risk**: Low

---

### Phase 9: Build Verification

#### Step 11. Build All Targets
Run all 4 build commands from CLAUDE.md. Fix any compilation errors.

- **Dependencies**: All previous steps
- **Risk**: Low

## Testing Strategy

### Build Verification
- All 4 targets compile cleanly

### Manual Verification Flows
1. **Log symptom from Home**: Tap symptom icon in header → sheet opens → pick category → pick symptom → slide severity → save → sheet dismisses, success haptic
2. **Log symptom from Profile**: Tap "Log +" on symptom card → same sheet flow
3. **Custom symptom**: In step 2, tap "Custom" → type name → proceed to severity → save
4. **Symptom history**: Profile → "View History" → see entries grouped by date with severity badges
5. **Delete symptom**: Swipe to delete in history → entry removed
6. **Correlation view**: Profile → "See Details" on symptom → correlation cards for each factor
7. **Collecting data state**: With <7 days, correlation cards show "Collecting data (X/7 days)"
8. **Sufficient data**: With ≥7 days, cards show r value, CI band, N, interpretation, disclaimer
9. **CSV export**: Generate wellness report → CSV contains symptom columns
10. **Empty states**: No symptoms → Profile shows "Log your first symptom" CTA; no correlations → "Track for 7+ days"
11. **Header icon spacing**: Test on iPhone SE simulator — 4 icons + mood badge fit

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Spearman implementation correctness | Medium | Verify against known test vectors (e.g., perfectly ranked data → r=1.0) |
| Profile view complexity (700+ lines) | Medium | New symptom sections are self-contained views; Profile only hosts them |
| Header icon overflow on SE | Low–Medium | Test on SE; fall back to 38pt icons or hide symptom when mood badge shows |
| Bootstrap CI performance | Low | 7000 resamples completes in <100ms; cache results in engine |
| Small N variance | Low | CI band visually communicates uncertainty; "Track more days" language |

## Success Criteria

- [ ] 3-tap symptom logging from both Home and Profile
- [ ] 20 preset symptoms in 4 categories + custom support
- [ ] Symptom history view with severity badges and delete
- [ ] Correlation cards with Spearman r, CI band, N, interpretation, and disclaimer
- [ ] "Collecting data" state when <7 paired days
- [ ] CSV export includes symptom columns
- [ ] All 4 build targets compile cleanly
- [ ] Profile tab has symptom tracking and insights sections
- [ ] No diagnostic or causal language anywhere
