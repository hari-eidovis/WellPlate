# Implementation Checklist: Stress Lab (n-of-1 Experiments)

**Source Plan**: `Docs/02_Planning/Specs/260402-stress-lab-plan-RESOLVED.md`
**Date**: 2026-04-02

---

## Pre-Implementation

- [ ] Read the RESOLVED plan at `Docs/02_Planning/Specs/260402-stress-lab-plan-RESOLVED.md`
  - Verify: All 7 implementation steps understood (Steps 1–7 across 6 phases)
- [ ] Confirm `WellPlate/Models/` directory exists
  - Verify: `WellPlate/Models/StressExperiment.swift` does NOT yet exist (new file)
- [ ] Confirm `WellPlate/Features + UI/Stress/Views/` exists
  - Verify: `StressLabView.swift`, `StressLabCreateView.swift`, `StressLabResultView.swift` do NOT yet exist
- [ ] Confirm `WellPlate/Features + UI/Stress/Services/` exists
  - Verify: `StressLabAnalyzer.swift` does NOT yet exist
- [ ] Confirm `StressView.swift` currently has exactly 2 `.sheet()` modifiers (lines 108 and 112)
  - Verify: grep for `.sheet(` in StressView.swift returns exactly 2 hits

---

## Phase 1: Data Model

### 1.1 — Create `StressExperiment.swift`

- [ ] Create new file `WellPlate/Models/StressExperiment.swift`
  - Content: `InterventionType` enum (6 cases: `.caffeine`, `.screenCurfew`, `.sleep`, `.exercise`, `.diet`, `.custom`) with `id`, `label`, `icon`, `suggestedHypothesis` properties
  - Content: `@Model final class StressExperiment` with properties: `name`, `hypothesis?`, `interventionType`, `startDate`, `durationDays`, `cachedBaselineAvg?`, `cachedExperimentAvg?`, `cachedDelta?`, `cachedCILow?`, `cachedCIHigh?`, `completedAt?`, `createdAt`
  - Content: computed vars `endDate`, `isComplete`, `daysRemaining`, `daysElapsed`, `resolvedInterventionType`
  - Verify: File compiles — no `import SwiftUI` needed (only `Foundation` + `SwiftData`)

### 1.2 — Register `StressExperiment` in `WellPlateApp.swift`

- [ ] Edit `WellPlate/App/WellPlateApp.swift` line 34: add `StressExperiment.self` to the modelContainer array
  - From: `.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self])`
  - To: `.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self])`
  - Verify: Line 34 now includes `StressExperiment.self` as 6th element

---

## Phase 2: Analytics Engine

### 2.1 — Create `StressLabAnalyzer.swift`

- [ ] Create new file `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift`
  - Content: `struct StressLabResult` with fields: `baselineAvg`, `experimentAvg`, `delta`, `ciLow`, `ciHigh`, `baselineDayCount`, `experimentDayCount`
  - Content: `struct StressLabAnalyzer` with `static let minimumDays = 3`
  - Content: `static func analyze(experiment:allReadings:) -> StressLabResult?` — filters readings into 7-day baseline window and experiment window, calls `dailyAverages`, guards `>= minimumDays`, computes averages and delta, calls `bootstrapCI`
  - Content: `private static func dailyAverages(from:) -> [Double]` — groups by `startOfDay`, averages scores per day
  - Content: `private static func bootstrapCI(baseline:experiment:iterations:)` — 1000-iteration bootstrap; uses `randomElement() ?? 0` (NOT force-unwrap)
  - Verify: No `import SwiftUI` — only `import Foundation`; no `@MainActor` annotation anywhere in this file

---

## Phase 3: UI — Lab Main Screen

### 3.1 — Create `StressLabView.swift`

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/StressLabView.swift`
  - Content: `private enum StressLabSheet: Identifiable` with cases `.create` and `.result(StressExperiment)`, `id` returning `"create"` or `"result_\(e.persistentModelID)"`
  - Content: `struct StressLabView: View` with:
    - `@Environment(\.modelContext)`, `@Environment(\.dismiss)`
    - `@Query(sort: \StressExperiment.createdAt, order: .reverse) private var experiments`
    - `@Query private var allReadings: [StressReading]`
    - `@State private var activeLabSheet: StressLabSheet? = nil`
    - `init()` with 30-day `#Predicate<StressReading>` on `allReadings` query
    - `private var activeExperiment: StressExperiment?` — first non-complete experiment
    - Body: `NavigationStack` → `ScrollView` → `VStack` with active card or empty card, plus past experiments section
    - Toolbar: `.topBarLeading` "Done" button, `.topBarTrailing` "+" button (visible only when no active experiment)
    - **Single** `.sheet(item: $activeLabSheet)` switch handling `.create` → `StressLabCreateView()` and `.result` → `StressLabResultView(experiment:allReadings:)`
    - `.presentationDetents([.large])` on the outer `NavigationStack`
  - Verify: Only ONE `.sheet()` modifier in this file

### 3.2 — Verify `StressLabView` sub-views

- [ ] Confirm `activeCard(_:)` renders: SF Symbol icon, name, intervention type label, days-remaining countdown, progress bar `GeometryReader`, optional hypothesis quote, and a destructive Delete button calling `modelContext.delete(exp)` + `try? modelContext.save()`
  - Verify: Uses `.appShadow(radius: 12, y: 4)` on card background
- [ ] Confirm `emptyActiveCard` renders: `flask.fill` icon, explanatory text, "Start an Experiment" button setting `activeLabSheet = .create`
  - Verify: Uses `.appShadow(radius: 12, y: 4)` on card background
- [ ] Confirm `pastRow(_:)` taps set `activeLabSheet = .result(exp)` and show cached delta pill when `exp.cachedDelta != nil`
  - Verify: `deltaLabel(_:)` colors negative delta green, positive red

---

## Phase 4: Create Experiment Form

### 4.1 — Create `StressLabCreateView.swift`

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/StressLabCreateView.swift`
  - Content: `struct StressLabCreateView: View` with:
    - `@Environment(\.modelContext)`, `@Environment(\.dismiss)`
    - `@State` vars: `name`, `hypothesis`, `selectedType: InterventionType = .caffeine`, `durationDays: Int = 7`
    - Body: `NavigationStack` → `Form` with sections: Intervention Type (`.pickerStyle(.navigationLink)`), Experiment Name (`TextField`), Hypothesis (multiline `TextField` with `axis: .vertical`), Duration (`Picker` segmented: 7 or 14 days), info `Section`
    - `onChange(of: selectedType)` pre-fills `name` and `hypothesis` if empty
    - `onAppear` pre-fills `name` and `hypothesis` if empty
    - Toolbar: "Cancel" (`topBarLeading`) and "Start" (`topBarTrailing`, disabled if `name.isEmpty`)
    - `saveAndDismiss()`: creates `StressExperiment`, inserts into modelContext, saves, triggers `.medium` haptic, dismisses
  - Verify: `.presentationDetents([.large])` on the `NavigationStack`

---

## Phase 5: Result View

### 5.1 — Create `StressLabResultView.swift`

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/StressLabResultView.swift`
  - Content: `struct StressLabResultView: View` with:
    - `let experiment: StressExperiment` and `let allReadings: [StressReading]`
    - `@State private var result: StressLabResult? = nil`
    - `@State private var isComputing = true`
    - `@Environment(\.dismiss)`, `@Environment(\.modelContext)`
    - Body: `NavigationStack` → `ScrollView` → conditional on `isComputing` / `result` / nil
    - `.task { }` block: runs `StressLabAnalyzer.analyze` in `Task.detached(priority: .userInitiated)`, sets `result` and `isComputing = false`, then caches fields on `experiment` and calls `try? modelContext.save()`
  - Verify: `try? modelContext.save()` is called after caching `cachedBaselineAvg`, `cachedExperimentAvg`, `cachedDelta`, `cachedCILow`, `cachedCIHigh`, and (conditionally) `completedAt`

### 5.2 — Verify result sub-views

- [ ] Confirm `scoreComparisonCard(_:)` shows "Before" / arrow + delta / "During" columns with `largeTitle` bold score values and colored arrow
  - Verify: Uses `.appShadow(radius: 12, y: 4)` on card background
- [ ] Confirm `confidenceCard(_:)` renders a `GeometryReader`-based CI band: background track, colored band from `ciLow` to `ciHigh`, filled circle at `delta`, center zero line
  - Verify: Explanatory text mentions "band entirely below zero suggests a real improvement"
- [ ] Confirm `interpretationCard(_:)` calls `interpretation(for:)` which checks `ciSpansZero`, `delta < 0`, and `delta >= 0` — all three text paths use non-causal language ("your average stress was", not "the intervention reduced")
  - Verify: "This is an observation, not a proof." disclaimer is present
- [ ] Confirm `dataCoverageNote(_:)` shows baseline and experiment day counts
- [ ] Confirm `notEnoughDataView` shows chart icon and explains 3-day minimum requirement (no crash when returned nil from analyzer)

---

## Phase 6: Wire Into StressView

### 6.1 — Add `.stressLab` to `StressSheet` enum

- [ ] Edit `WellPlate/Features + UI/Stress/Views/StressView.swift` lines 12–28: add `case stressLab` to `StressSheet` enum
  - After the `case screenTimeDetail` line, add: `case stressLab`
  - In the `var id: String` switch, add: `case .stressLab: return "stressLab"`
  - Verify: Enum now has 6 cases: `exercise`, `sleep`, `diet`, `screenTimeDetail`, `vital`, `stressLab`

### 6.2 — Add "Lab" toolbar button

- [ ] Edit `WellPlate/Features + UI/Stress/Views/StressView.swift`: inside the existing `.toolbar { }` block (around line 66), add a new `ToolbarItem(placement: .topBarLeading)` before the existing `.topBarTrailing` item
  - Content: Same visibility guard as trailing button (`isAvailable || usesMockData` && `isAuthorized` && `!isLoading`)
  - Button action: `HapticService.impact(.light)` then `activeSheet = .stressLab`
  - Label: `Label("Lab", systemImage: "flask.fill")` with `.font(.system(size: 14, weight: .semibold))` and `.foregroundStyle(viewModel.stressLevel.color)`
  - Verify: Existing `.topBarTrailing` Insights button is untouched

### 6.3 — Handle `.stressLab` in existing sheet switch

- [ ] Edit `WellPlate/Features + UI/Stress/Views/StressView.swift`: in the `.sheet(item: $activeSheet)` switch (around line 112), add a new case after `case .vital`:
  ```swift
  case .stressLab:
      StressLabView()
  ```
  - Verify: The switch now handles 6 cases and still compiles exhaustively
- [ ] Verify `StressView.swift` still has exactly 2 `.sheet()` modifiers total (lines ~108 and ~112) — grep confirms no new `.sheet(` was added
  - Verify: `grep -c "\.sheet(" StressView.swift` returns `2`

---

## Post-Implementation

### Build Verification

- [ ] Build main app target:
  - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **` with 0 errors
- [ ] Build ScreenTimeMonitor extension:
  - `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **` with 0 errors
- [ ] Build ScreenTimeReport extension:
  - `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **` with 0 errors
- [ ] Build WellPlateWidget extension:
  - `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **` with 0 errors

### Manual Verification

- [ ] Stress tab → "Lab" (flask) button appears in top-left toolbar when authorized
  - Verify: Button is absent during loading and permission screens
- [ ] Tap "Lab" → `StressLabView` opens as large detent sheet
  - Verify: Empty state card with `flask.fill` icon and "Start an Experiment" button shown
- [ ] Tap "Start an Experiment" → `StressLabCreateView` opens
  - Verify: Selecting intervention type pre-fills name and hypothesis fields
  - Verify: "Start" button disabled until name is non-empty
  - Verify: Tap "Start" → experiment saved, active card appears in `StressLabView`
- [ ] Active card shows progress bar, days remaining countdown, hypothesis text (if set)
  - Verify: "Day X of Y" label updates correctly
- [ ] Tap "Delete experiment" → experiment removed, empty state card returns
- [ ] (With sufficient data) Tap a past experiment → `StressLabResultView` opens
  - Verify: Score comparison card, CI band, interpretation card, data coverage note all rendered
  - Verify: Interpretation text is non-causal ("your average stress was…", not "the intervention reduced…")
- [ ] (With insufficient data) → "Not enough data yet" view shown; no crash
- [ ] Past experiment row shows colored delta pill after result viewed once
  - Verify: Negative delta = green pill, positive = red pill

### Success Criteria Checklist

- [ ] All 4 build targets compile cleanly with 0 errors
- [ ] "Lab" button visible in `StressView` top-left toolbar when authorized
- [ ] `StressView` has exactly 2 `.sheet()` modifiers after implementation
- [ ] Creating an experiment persists across app restart (SwiftData)
- [ ] Active card shows correct day count and progress bar
- [ ] Result view shows score comparison + CI band + interpretation
- [ ] Insufficient data → "Not enough data yet" (no crash)
- [ ] Past experiments list shows cached delta pills after first result view
- [ ] All result text avoids causal language

### Git Commit

- [ ] Stage and commit all new and modified files:
  - New: `WellPlate/Models/StressExperiment.swift`
  - New: `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift`
  - New: `WellPlate/Features + UI/Stress/Views/StressLabView.swift`
  - New: `WellPlate/Features + UI/Stress/Views/StressLabCreateView.swift`
  - New: `WellPlate/Features + UI/Stress/Views/StressLabResultView.swift`
  - Modified: `WellPlate/App/WellPlateApp.swift`
  - Modified: `WellPlate/Features + UI/Stress/Views/StressView.swift`
  - Verify: `git status` shows all 7 files staged; no unintended files included
