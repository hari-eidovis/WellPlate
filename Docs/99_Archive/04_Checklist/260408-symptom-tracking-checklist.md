# Implementation Checklist: Symptom Tracking Correlated with Food/Sleep

**Source Plan**: `Docs/02_Planning/Specs/260408-symptom-tracking-plan-RESOLVED.md`
**Date**: 2026-04-08

---

## Pre-Implementation

- [ ] Read the resolved plan: `Docs/02_Planning/Specs/260408-symptom-tracking-plan-RESOLVED.md`
- [ ] Verify affected files exist:
  - [ ] `WellPlate/App/WellPlateApp.swift` — contains `.modelContainer(for:)` with `JournalEntry.self` at end
  - [ ] `WellPlate/Features + UI/Tab/ProfileView.swift` — contains `ProfilePlaceholderView`
  - [ ] `WellPlate/Features + UI/Home/Views/HomeView.swift` — contains `HomeSheet` enum with `coffeeTypePicker`, `journalEntry`
  - [ ] `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` — contains `generateCSV`
  - [ ] `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift` — reference for bootstrap CI pattern
  - [ ] `WellPlate/Features + UI/Stress/Services/StressAnalyticsHelper.swift` — reference for `dailyAveragesByDate`
- [ ] Verify no naming conflicts: search for `SymptomEntry.swift`, `SymptomDefinition.swift`, `SymptomCorrelationEngine.swift`, `SymptomLogSheet.swift`, `SymptomHistoryView.swift`, `SymptomCorrelationView.swift` — none should exist
  - Verify: `find WellPlate/ -name "Symptom*.swift"` returns empty
- [ ] Create directory: `mkdir -p "WellPlate/Features + UI/Symptoms/Views"`

---

## Phase 1: Data Layer

### 1.1 — Create SymptomDefinition Library

- [ ] Create file `WellPlate/Models/SymptomDefinition.swift`
- [ ] Define `enum SymptomCategory: String, CaseIterable, Identifiable, Codable` with cases: `digestive`, `pain`, `energy`, `cognitive`
- [ ] Add computed properties on `SymptomCategory`:
  - `var label: String` — "Digestive", "Pain", "Energy", "Cognitive"
  - `var icon: String` — SF Symbols: `"stomach"`, `"bandage"`, `"bolt.fill"`, `"brain.head.profile"`
  - `var color: Color` — distinct accent color per category (warm orange, red, amber, purple)
- [ ] Define `struct SymptomDefinition: Identifiable, Hashable` with: `name`, `category`, `icon`, `isCustom`, `var id: String { name }`
- [ ] Add `static let library: [SymptomDefinition]` with 20 presets (5 per category):
  - Digestive: Bloating, Nausea, Acid reflux, Stomach pain, Irregular digestion
  - Pain: Headache, Migraine, Joint pain, Muscle soreness, Back pain
  - Energy: Fatigue, Energy crash, Brain fog, Dizziness, Insomnia
  - Cognitive: Anxiety, Irritability, Low mood, Difficulty concentrating, Restlessness
- [ ] Add `static func custom(name: String) -> SymptomDefinition` returning a definition with `isCustom: true` and `"plus.circle"` icon
- [ ] Add `static func forCategory(_ category: SymptomCategory) -> [SymptomDefinition]` filter helper
  - Verify: `SymptomDefinition.library.count == 20` and all 4 categories have 5 items each

### 1.2 — Create SymptomEntry SwiftData Model

- [ ] Create file `WellPlate/Models/SymptomEntry.swift`
- [ ] Define `@Model final class SymptomEntry` with fields:
  - `var id: UUID`
  - `var name: String`
  - `var category: String` (raw value of SymptomCategory)
  - `var severity: Int` (1–10)
  - `var timestamp: Date` (exact time)
  - `var day: Date` (Calendar.startOfDay)
  - `var notes: String?`
  - `var createdAt: Date`
- [ ] Add init: `init(name:category:severity:timestamp:notes:)` — `day` must use `Calendar.current.startOfDay(for: timestamp)`, `id = UUID()`, `createdAt = .now`
- [ ] Add computed `var resolvedCategory: SymptomCategory?` from category raw value
  - Verify: File compiles — run build

### 1.3 — Register SymptomEntry in ModelContainer

- [ ] Edit `WellPlate/App/WellPlateApp.swift` — add `SymptomEntry.self` after `JournalEntry.self` in `.modelContainer(for:)` array
  - Verify: Array now contains 11 models ending with `JournalEntry.self, SymptomEntry.self`
- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 2: Correlation Engine

### 2.1 — Create SymptomCorrelationEngine

- [ ] Create file `WellPlate/Core/Services/SymptomCorrelationEngine.swift`
- [ ] Add imports: `Foundation`, `SwiftUI`, `SwiftData`, `Combine`
- [ ] Define `struct SymptomCorrelation: Identifiable` with fields:
  - `let id: UUID` (init to `UUID()`)
  - `let symptomName: String`
  - `let factorName: String`
  - `let factorIcon: String` (SF Symbol)
  - `let spearmanR: Double` (−1 to +1)
  - `let ciLow: Double` (2.5th percentile)
  - `let ciHigh: Double` (97.5th percentile)
  - `let pairedDays: Int`
  - `let interpretation: String`
  - `let isSignificant: Bool` (CI doesn't span zero)
- [ ] Define `@MainActor final class SymptomCorrelationEngine: ObservableObject` with:
  - `@Published var correlations: [SymptomCorrelation] = []`
  - `@Published var isComputing: Bool = false`

### 2.2 — Implement Spearman Rank Correlation

- [ ] Add private static method `spearmanR(_ x: [Double], _ y: [Double]) -> Double`:
  - Convert both arrays to ranks (handle ties with average rank)
  - Compute Pearson r on ranks: `r = Σ((xi - x̄)(yi - ȳ)) / √(Σ(xi - x̄)² × Σ(yi - ȳ)²)`
  - Return r value
- [ ] Add private static method `ranks(of values: [Double]) -> [Double]`:
  - Sort with indices, assign ranks 1..N, average tied ranks
- [ ] Test edge: `spearmanR([1,2,3,4,5], [1,2,3,4,5])` should return `1.0`
- [ ] Test edge: `spearmanR([1,2,3,4,5], [5,4,3,2,1])` should return `-1.0`
  - Verify: Both test cases pass (can verify via unit test or debug print)

### 2.3 — Implement Bootstrap CI

- [ ] Add private static method `bootstrapCI(pairs: [(Double, Double)], iterations: Int) -> (low: Double, high: Double)`:
  - 1000 iterations
  - Each: resample `pairs` with replacement, compute `spearmanR` on sample
  - Sort all r values
  - Return 2.5th percentile (index `Int(1000 * 0.025)` = 25) and 97.5th percentile (index `Int(1000 * 0.975)` = 975)
  - Pattern follows `StressLabAnalyzer.bootstrapCI()` (lines 57–77)
  - Verify: CI for perfectly correlated data should be narrow and near 1.0

### 2.4 — Implement computeCorrelations Method

- [ ] Implement `func computeCorrelations(symptomName:symptomEntries:foodLogs:wellnessLogs:stressReadings:sleepHours:) async`:
  - Set `isComputing = true`, defer `isComputing = false`
  - Aggregate symptom entries by day: `Dictionary(grouping:) { startOfDay }` → max severity per day
  - Define 7 factors with name, icon, and daily-value extraction:
    1. Sleep hours — from `sleepHours` dict
    2. Stress score — from `StressAnalyticsHelper.dailyAveragesByDate(from: stressReadings)`
    3. Caffeine — from `wellnessLogs` `.coffeeCups`
    4. Calories — from `foodLogs` grouped by day, sum `.calories`
    5. Protein — from `foodLogs` grouped by day, sum `.protein`
    6. Fiber — from `foodLogs` grouped by day, sum `.fiber`
    7. Water — from `wellnessLogs` `.waterGlasses`
  - For each factor: build paired `[(symptomSeverity, factorValue)]` for days where both exist
  - If paired count < 7: create `SymptomCorrelation` with `interpretation: "Collecting data"`, `pairedDays: count`, `spearmanR: 0`, `isSignificant: false`
  - If paired count ≥ 7: compute `spearmanR`, `bootstrapCI`, `interpretationLabel`, `isSignificant`
  - Set `correlations` array sorted by `abs(spearmanR)` descending (strongest first)

### 2.5 — Implement Interpretation Label

- [ ] Add private method `interpretationLabel(r: Double, ciSpansZero: Bool) -> String`:
  - If `ciSpansZero`: return `"No clear pattern (yet)"`
  - Else: `"{weak|moderate|strong} {positive|negative} association"` based on `abs(r)` thresholds (0.3, 0.6)
  - Verify: `interpretationLabel(r: 0.52, ciSpansZero: false)` returns `"moderate positive association"`

### 2.6 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 3: UI — Symptom Log Sheet

### 3.1 — Create SymptomLogSheet

- [ ] Create file `WellPlate/Features + UI/Symptoms/Views/SymptomLogSheet.swift`
- [ ] Define `struct SymptomLogSheet: View` with:
  - `@Environment(\.modelContext)`, `@Environment(\.dismiss)`
  - `@State private var step: LogStep = .category` (enum: `.category`, `.symptom`, `.severity`)
  - `@State private var selectedCategory: SymptomCategory?`
  - `@State private var selectedSymptom: SymptomDefinition?`
  - `@State private var severity: Double = 5`
  - `@State private var notes: String = ""`
  - `@State private var customName: String = ""`
- [ ] Build Step 1 (Category picker):
  - Title "What kind of symptom?"
  - 2×2 `LazyVGrid` of category cards (icon + label + accent color)
  - Tap sets `selectedCategory` and advances to `.symptom` step
  - Haptics: `HapticService.impact(.light)` on tap
- [ ] Build Step 2 (Symptom picker):
  - Back button returns to `.category`
  - Filter `SymptomDefinition.forCategory(selectedCategory!)` — show as pills/chips
  - "Custom" pill at end — when tapped, show `TextField` for custom name
  - Tap sets `selectedSymptom` and advances to `.severity` step
- [ ] Build Step 3 (Severity + save):
  - Back button returns to `.symptom`
  - Symptom name in nav title
  - `Slider(value: $severity, in: 1...10, step: 1)` with severity label
  - Severity number colored by scale: 1–3 green, 4–6 amber, 7–10 red
  - Optional notes `TextField("Notes (optional)...", text: $notes, axis: .vertical).lineLimit(2...4)`
  - Save button (disabled when no symptom selected)
- [ ] Save action:
  - Create `SymptomEntry(name:category:severity:timestamp:notes:)` with `Date()` as timestamp
  - `modelContext.insert(entry)` + `try modelContext.save()`
  - `HapticService.notify(.success)`
  - `dismiss()`
  - Log: `WPLogger.home.info("Symptom logged: \(name) severity \(severity)")`
- [ ] Add `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`
- [ ] Add dismiss X button in toolbar leading
- [ ] Add `#Preview` block
  - Verify: Preview renders; 3-step flow works

---

## Phase 4: UI — Symptom History

### 4.1 — Create SymptomHistoryView

- [ ] Create file `WellPlate/Features + UI/Symptoms/Views/SymptomHistoryView.swift`
- [ ] Define `struct SymptomHistoryView: View` with:
  - `@Environment(\.modelContext)`
  - `@Query(sort: \SymptomEntry.timestamp, order: .reverse) private var entries: [SymptomEntry]`
- [ ] Build layout:
  - Navigation title: "Symptom History"
  - Group entries by relative date (Today, Yesterday, then formatted dates) — same pattern as `JournalHistoryView`
  - Each entry card: symptom icon + name, category colored pill, severity badge (1–3 green, 4–6 amber, 7–10 red), time, optional notes
  - Tap to expand notes (if present)
- [ ] Empty state: centered icon + "No symptoms logged yet" + subtitle text
- [ ] Swipe to delete: `.onDelete` with `modelContext.delete()` + `try modelContext.save()`
- [ ] Font: `.system(size:weight:design:.rounded)` throughout
- [ ] Add `#Preview` with in-memory ModelContainer including `SymptomEntry.self` + sample data
  - Verify: Preview renders; empty state shows when no entries

### 4.2 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 5: UI — Correlation View

### 5.1 — Create SymptomCorrelationView

- [ ] Create file `WellPlate/Features + UI/Symptoms/Views/SymptomCorrelationView.swift`
- [ ] Define `struct SymptomCorrelationView: View` with:
  - `let symptomName: String`
  - `@ObservedObject var engine: SymptomCorrelationEngine`
- [ ] Navigation title: `"\(symptomName) Insights"`
- [ ] Loading state: show `ProgressView` when `engine.isComputing`
- [ ] For each correlation in `engine.correlations`, render a card:

**Correlation card layout (for `isSignificant` or sufficient data):**
  - [ ] Header: factor icon + factor name
  - [ ] r value: `"r = X.XX"` + interpretation label (e.g. "moderate positive")
  - [ ] CI band visualization using `GeometryReader`:
    - Range: −1.0 to +1.0
    - Gray background capsule (full width)
    - Brand-colored band from `ciLow` to `ciHigh`
    - Dot at `spearmanR` position
    - Vertical zero-line at center
    - Follow `StressLabResultView` pattern (lines 122–164) but with range 2.0 instead of 80.0
  - [ ] Text: `"95% CI: [X.XX, X.XX]"`
  - [ ] N label: `"Based on N paired days"`
  - [ ] Disclaimer: `"Correlation does not imply causation. Track more days to strengthen confidence."`

**Collecting data card (for insufficient data):**
  - [ ] Factor icon + name + "Collecting data" label
  - [ ] Progress: `"X/7 days"` with subtle progress bar

- [ ] Add `#Preview` with mock correlations
  - Verify: Preview renders both sufficient-data and collecting-data card states

### 5.2 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 6: Profile Tab Integration

### 6.1 — Add ProfileSheet Enum

- [ ] Add `enum ProfileSheet: Identifiable` above `ProfilePlaceholderView` struct in `WellPlate/Features + UI/Tab/ProfileView.swift`:
  - Cases: `widgetInstructions`, `editName`, `editWeight`, `editHeight`, `symptomLog`
  - `var id: String` switch returning case name strings
  - Verify: Enum compiles, conforms to `Identifiable`

### 6.2 — Migrate Existing Sheets to ProfileSheet Enum

- [ ] Replace `@State private var showInstructions = false` with removal (will use `activeSheet`)
- [ ] Replace `@State private var showEditName = false` with removal
- [ ] Replace `@State private var showEditWeight = false` with removal
- [ ] Replace `@State private var showEditHeight = false` with removal
- [ ] Add `@State private var activeSheet: ProfileSheet?`
- [ ] Find ALL occurrences of `showInstructions = true` → replace with `activeSheet = .widgetInstructions`
- [ ] Find ALL occurrences of `showEditName = true` → replace with `activeSheet = .editName`
- [ ] Find ALL occurrences of `showEditWeight = true` → replace with `activeSheet = .editWeight`
- [ ] Find ALL occurrences of `showEditHeight = true` → replace with `activeSheet = .editHeight`
- [ ] Replace ALL 4 `.sheet(isPresented:)` modifiers (~lines 151–169) with single:
  ```swift
  .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .widgetInstructions:
          WidgetInstructionsSheet(size: selectedSize)
              .presentationDetents([.medium, .large])
              .presentationDragIndicator(.visible)
      case .editName: editNameSheet
      case .editWeight: editWeightSheet
      case .editHeight: editHeightSheet
      case .symptomLog: SymptomLogSheet()
      }
  }
  ```
  - Verify: Build compiles with no references to `showInstructions`, `showEditName`, `showEditWeight`, `showEditHeight`. Run: `grep -n "showInstructions\|showEditName\|showEditWeight\|showEditHeight" "WellPlate/Features + UI/Tab/ProfileView.swift"` — should return empty

### 6.3 — Add Symptom State Variables & Query

- [ ] Add after existing `@State` declarations:
  - `@State private var showSymptomHistory = false`
  - `@State private var showSymptomCorrelation = false`
  - `@State private var selectedSymptomForCorrelation: String?`
- [ ] Add `@Query(sort: \SymptomEntry.timestamp, order: .reverse) private var allSymptomEntries: [SymptomEntry]`
- [ ] Add `@StateObject private var correlationEngine = SymptomCorrelationEngine()`
  - Verify: No compiler errors

### 6.4 — Add Symptom Tracking Card to Profile Body

- [ ] Insert between `goalsSnapshotCard` and `WidgetSetupCard` (~line 108):
- [ ] Build "Symptom Tracking" card:
  - Header: stethoscope icon + "Symptom Tracking" title + "Log +" button (`activeSheet = .symptomLog`)
  - Body: last 2–3 symptom entries (from `allSymptomEntries.prefix(3)`) showing name, severity badge, relative time
  - Footer: "View History" button (`showSymptomHistory = true`)
  - Empty state: "Log your first symptom" with + icon CTA
  - Card styling: `RoundedRectangle(cornerRadius: 20)`, `.appShadow()` or matching profile card pattern

### 6.5 — Add Symptom Insights Card to Profile Body

- [ ] Insert after Symptom Tracking card (only visible when `uniqueSymptomDays >= 7`):
- [ ] Build "Symptom Insights" card:
  - Header: chart icon + "Symptom Insights"
  - Body: for top 3 tracked symptoms, show one-line summary: `"Headache → moderate link to caffeine"`
  - Footer: "See Details" button per symptom (sets `selectedSymptomForCorrelation` + `showSymptomCorrelation = true`)
  - Compute: trigger `correlationEngine.computeCorrelations()` in `.task {}` modifier, constructing `sleepHours` dict from `HealthKitService().fetchDailySleepSummaries()`
  - Verify: Card only appears when ≥7 days of data exist

### 6.6 — Add Navigation Destinations

- [ ] Add after existing `.navigationDestination` modifiers:
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
  - Verify: Tapping "View History" navigates; tapping "See Details" navigates

### 6.7 — Update ProfileView Preview

- [ ] Update preview to include `SymptomEntry.self` + `UserGoals.self`:
  ```swift
  #Preview {
      let config = ModelConfiguration(isStoredInMemoryOnly: true)
      let container = try! ModelContainer(
          for: SymptomEntry.self, UserGoals.self,
          configurations: config
      )
      return ProfilePlaceholderView()
          .modelContainer(container)
  }
  ```
  - Verify: Preview renders without crash

### 6.8 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 7: Home Integration

### 7.1 — Add symptomLog to HomeSheet Enum

- [ ] Add `case symptomLog` to `HomeSheet` enum in `WellPlate/Features + UI/Home/Views/HomeView.swift`
- [ ] Add `case .symptomLog: return "symptomLog"` to `var id` switch
- [ ] Add to `.sheet(item: $activeSheet)` switch:
  ```swift
  case .symptomLog:
      SymptomLogSheet()
  ```
  - Verify: Enum compiles with 3 cases

### 7.2 — Resize Header Icons to 38pt

- [ ] In `homeHeader`, change ALL `Circle().frame(width: 44, height: 44)` to `frame(width: 38, height: 38)` for:
  - AI Insights button (~line 361)
  - Calendar button (~line 384)
  - Journal button (~line 413)
- [ ] Change ALL `.shadow(...)` frame references from 44 to 38 if hardcoded
- [ ] Change ALL icon `.font(.system(size: 17, ...))` to `.font(.system(size: 15, ...))` for the 3 buttons above
- [ ] Also resize mood badge: Circle frames from 44pt to 38pt, emoji font from 22pt to 19pt
  - Verify: Build compiles; visually test header isn't broken

### 7.3 — Add Symptom Header Icon

- [ ] Insert symptom button in `homeHeader` BEFORE the journal book icon:
  ```swift
  // Symptom quick-log
  Button {
      HapticService.impact(.light)
      activeSheet = .symptomLog
  } label: {
      ZStack {
          Circle()
              .fill(
                  LinearGradient(
                      colors: [AppColors.brand.opacity(0.65), AppColors.brand.opacity(0.65)],
                      startPoint: .topLeading, endPoint: .bottomTrailing
                  )
              )
              .frame(width: 38, height: 38)
              .shadow(color: AppColors.brand.opacity(0.12), radius: 6, x: 0, y: 3)
          Image(systemName: "heart.text.square.fill")
              .font(.system(size: 15, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)
      }
  }
  .buttonStyle(.plain)
  ```
  - Verify: Header shows 4 icons (AI, Calendar, Symptom, Journal) + mood badge, all at 38pt

### 7.4 — Build Check

- [ ] Build: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 8: CSV Export Extension

### 8.1 — Extend WellnessReportGenerator

- [ ] Edit `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift`
- [ ] Add `symptomEntries: [SymptomEntry] = []` parameter to `generateCSV` signature
- [ ] Update CSV header to: `"date,stress_score,calories,protein_g,carbs_g,fat_g,fiber_g,steps,water_glasses,mood,symptom,symptom_severity"`
- [ ] Add fiber aggregation per day: `let fiber = food.reduce(0.0) { $0 + $1.fiber }`
- [ ] Add symptom grouping: `let symptomByDay = Dictionary(grouping: symptomEntries.filter { $0.day >= cutoff }) { $0.day }`
- [ ] Per day: find worst symptom: `let worstSymptom = (symptomByDay[day] ?? []).max(by: { $0.severity < $1.severity })`
- [ ] Update row string to include fiber, symptom name, symptom severity
  - Verify: Build compiles; existing caller in `WellnessReportShareSheet.swift` still works (uses default `[]`)

---

## Post-Implementation

### Build All 4 Targets

- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`

### Functional Verification

- [ ] Log symptom from Home: tap symptom icon → 3-step sheet → save → dismiss + haptic
- [ ] Log symptom from Profile: tap "Log +" → same sheet flow
- [ ] Custom symptom: tap Custom → enter name → severity → save
- [ ] Symptom history: Profile → View History → entries grouped by date with severity badges
- [ ] Delete symptom: swipe in history → entry removed
- [ ] Correlation view (≥7 days): Profile → See Details → cards with r, CI band, N, disclaimer
- [ ] Collecting data (<7 days): correlation cards show "Collecting data (X/7 days)"
- [ ] CSV export: generate report → CSV has fiber + symptom columns
- [ ] Empty states: no symptoms → "Log your first symptom" CTA; no correlations → "Track 7+ days"
- [ ] Header icons (38pt): test on iPhone SE simulator — 4 icons + mood badge fit
- [ ] ProfileSheet migration: edit name/weight/height, widget instructions all still work
- [ ] ProfileView preview: renders without crash in Xcode canvas
- [ ] No diagnostic or causal language anywhere in UI

### Git Commit

- [ ] Stage all new and modified files
- [ ] Commit with message describing symptom tracking feature
