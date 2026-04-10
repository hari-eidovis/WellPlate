# Implementation Checklist: Comprehensive Mock Mode Toggle

**Source Plan**: [260410-comprehensive-mock-mode-plan-RESOLVED.md](../02_Planning/Specs/260410-comprehensive-mock-mode-plan-RESOLVED.md)
**Date**: 2026-04-11

---

## Pre-Implementation

- [ ] Read the resolved plan fully
- [ ] Verify all referenced files exist:
  - [ ] `WellPlate/Core/AppConfig.swift`
  - [ ] `WellPlate/Core/Services/MockDataInjector.swift`
  - [ ] `WellPlate/Core/Services/MockHealthKitService.swift`
  - [ ] `WellPlate/Core/Services/InsightEngine.swift`
  - [ ] `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift`
  - [ ] `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`
  - [ ] `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`
  - [ ] `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - [ ] `WellPlate/Features + UI/Tab/MainTabView.swift`
  - [ ] `WellPlate/Features + UI/Home/Views/HomeView.swift`
  - [ ] `WellPlate/Features + UI/Burn/Views/BurnView.swift`
  - [ ] `WellPlate/Features + UI/Sleep/Views/SleepView.swift`
  - [ ] `WellPlate/Features + UI/Tab/MockDataDebugCard.swift`
  - [ ] `WellPlate/Features + UI/Tab/ProfileView.swift`
  - [ ] `WellPlate/Networking/Real/APIClientFactory.swift` (reference pattern)

---

## Phase 1: Foundation (Factory + Flag Merge)

### 1.1 — Create HealthKitServiceFactory (Plan Step 1)

- [ ] Create new file `WellPlate/Core/Services/HealthKitServiceFactory.swift`
  - [ ] `enum HealthKitServiceFactory` with cached `_shared` singleton returning `MockHealthKitService(snapshot: .default)` when `AppConfig.shared.mockMode` is true (inside `#if DEBUG`), else `HealthKitService()`
  - [ ] `static var shared: HealthKitServiceProtocol` — returns `_shared`
  - [ ] `static var isDataAvailable: Bool` — returns `true` if `mockMode` (inside `#if DEBUG`), else `HealthKitService.isAvailable`
  - [ ] `#if DEBUG` test support: `_testInstance`, `setTestInstance(_:)`, `testable`
  - [ ] Add `WPLogger.app.block` logging when mock path is taken
  - Verify: File compiles. `HealthKitServiceFactory.shared` returns `HealthKitServiceProtocol`. `HealthKitServiceFactory.isDataAvailable` compiles.

### 1.2 — Merge flags in AppConfig (Plan Step 2)

- [ ] In `WellPlate/Core/AppConfig.swift`, remove `Keys.mockDataInjected` (line 20: `static let mockDataInjected = "app.mock.dataInjected"`)
  - Verify: No compiler errors referencing the removed key within AppConfig itself
- [ ] Remove the `mockDataInjected` computed property (lines 110–124)
  - Verify: Property no longer exists in AppConfig (will cause compile errors in other files — expected, fixed in later steps)
- [ ] Rename `Keys.mockInjectedWellnessLogDates` → `Keys.mockInjectedDates` (line 21)
  - Verify: Key string changes to `"app.mock.injectedDates"`
- [ ] Rename property `mockInjectedWellnessLogDates` → `mockInjectedDates` (lines 127–139)
  - Verify: Property name and UserDefaults key both updated
- [ ] Add `Keys.mockInjectedRecordIDs = "app.mock.injectedRecordIDs"`
  - Verify: New key exists in Keys enum
- [ ] Add `mockInjectedRecordIDs: [String]` computed property (same pattern as `mockInjectedDates`)
  - Verify: Property compiles with `#if DEBUG` / `#else` branches
- [ ] Update `logCurrentMode()` — add line: `"Mock Data  : \(mockMode ? "INJECTED" : "NONE")"`
  - Verify: `logCurrentMode()` references `mockMode`, not `mockDataInjected`

---

## Phase 2: Wire Factory into ViewModels

### 2.1 — Update SleepViewModel (Plan Step 3)

- [ ] In `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift`, change init default:
  - `init(service: HealthKitServiceProtocol = HealthKitService())` → `init(service: HealthKitServiceProtocol = HealthKitServiceFactory.shared)`
  - Verify: `HealthKitService()` no longer appears in this file's init
- [ ] Replace `guard HealthKitService.isAvailable else { return }` in `requestPermissionAndLoad()` with `guard HealthKitServiceFactory.isDataAvailable else { return }`
  - Verify: `HealthKitService.isAvailable` no longer appears in this file

### 2.2 — Update BurnViewModel (Plan Step 4)

- [ ] In `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`, replace entire `init` body:
  - Change from `init(service: HealthKitServiceProtocol? = nil)` with 3-branch if/else → `init(service: HealthKitServiceProtocol = HealthKitServiceFactory.shared) { self.service = service }`
  - Verify: No `mockDataInjected` or `MockHealthKitService` references in init
- [ ] Replace entire `requestPermissionAndLoad()` method:
  - Remove `if AppConfig.shared.mockDataInjected { ... }` early-return branch
  - Replace `guard HealthKitService.isAvailable` with `guard HealthKitServiceFactory.isDataAvailable`
  - Unified path: guard → isLoading → requestAuthorization → isAuthorized → loadData
  - Verify: `mockDataInjected` no longer appears anywhere in this file. `HealthKitService.isAvailable` no longer appears.

### 2.3 — Update WellnessCalendarViewModel (Plan Step 5)

- [ ] In `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`, replace init:
  - Change from `init(healthService: HealthKitServiceProtocol? = nil)` with 3-branch if/else → `init(healthService: HealthKitServiceProtocol = HealthKitServiceFactory.shared) { self.healthService = healthService }`
  - Verify: No `mockDataInjected` or `MockHealthKitService` references in init
- [ ] In `loadHealthKitActivity(for:)`, replace the 3-line guard block:
  - `if !AppConfig.shared.mockDataInjected { guard HealthKitService.isAvailable else { return } }` → `guard HealthKitServiceFactory.isDataAvailable else { return }`
  - Verify: `mockDataInjected` no longer appears anywhere in this file

### 2.4 — Update InsightEngine (Plan Step 6)

- [ ] In `WellPlate/Core/Services/InsightEngine.swift`, change init default (line 34):
  - `HealthKitService()` → `HealthKitServiceFactory.shared`
  - Verify: `HealthKitService()` no longer appears in this file
- [ ] Remove the mock shortcut block in `generateInsights()` (lines 55–61):
  - Delete: `if AppConfig.shared.mockMode { let mocks = mockInsights(); insightCards = mocks; dailyInsight = mocks.first; return }`
  - Verify: No early return before `buildWellnessContext()` call
- [ ] Add `#if DEBUG` mock fallback in the `buildWellnessContext() == nil` guard:
  - After `guard let context = await buildWellnessContext() else {`, add: `#if DEBUG` block that calls `mockInsights()` if `AppConfig.shared.mockMode` is true, else sets `insufficientData = true`
  - Verify: The `mockInsights()` private method still exists (unchanged). The fallback path is `#if DEBUG`-gated.

### 2.5 — Update StressViewModel (Plan Step 7)

- [ ] In `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`, change init default (line 144):
  - `healthService: HealthKitServiceProtocol = HealthKitService()` → `healthService: HealthKitServiceProtocol = HealthKitServiceFactory.shared`
  - Verify: `HealthKitService()` no longer appears in the init signature of this file

---

## Phase 3: Wire Factory into Views

### 3.1 — Update MainTabView (Plan Step 8)

- [ ] In `WellPlate/Features + UI/Tab/MainTabView.swift`, simplify Stress tab VM creation:
  - Change `if AppConfig.shared.mockMode || AppConfig.shared.mockDataInjected` → `if AppConfig.shared.mockMode`
  - Remove `healthService: MockHealthKitService(snapshot: snap)` parameter from StressViewModel init — factory handles it
  - Keep `mockSnapshot: snap` parameter (still needed for stress-specific mock data)
  - Verify: `mockDataInjected` no longer appears in this file. `MockHealthKitService` no longer appears in this file.

### 3.2 — Update HomeView (Plan Step 9)

- [ ] In `WellPlate/Features + UI/Home/Views/HomeView.swift`, update `fetchHealthMoodSuggestion()`:
  - Replace `if AppConfig.shared.mockDataInjected { return }` with `if AppConfig.shared.mockMode { return }`
  - Replace `guard HealthKitService.isAvailable else { return }` with `guard HealthKitServiceFactory.isDataAvailable else { return }`
  - Replace `let service = HealthKitService()` with `let service = HealthKitServiceFactory.shared`
  - Verify: No `HealthKitService()` instantiation in this method
- [ ] Update `logMoodForTodayIfNeeded(_:)`:
  - Replace `if HealthKitService.isAvailable && !AppConfig.shared.mockDataInjected` with `if HealthKitServiceFactory.isDataAvailable && !AppConfig.shared.mockMode`
  - Replace `HealthKitService().writeMood(mood)` with `HealthKitServiceFactory.shared.writeMood(mood)`
  - Verify: `mockDataInjected` no longer appears anywhere in HomeView. `HealthKitService()` no longer instantiated anywhere in HomeView.

### 3.3 — Update BurnView (Plan Step 10)

- [ ] In `WellPlate/Features + UI/Burn/Views/BurnView.swift`, replace availability guard (line 28):
  - `if !HealthKitService.isAvailable && !AppConfig.shared.mockDataInjected` → `if !HealthKitServiceFactory.isDataAvailable`
  - Verify: `mockDataInjected` no longer appears in this file. `HealthKitService.isAvailable` no longer appears.

### 3.4 — Update SleepView (Plan Step 10b)

- [ ] In `WellPlate/Features + UI/Sleep/Views/SleepView.swift`, replace availability guard (line 29):
  - `if !HealthKitService.isAvailable` → `if !HealthKitServiceFactory.isDataAvailable`
  - Verify: `HealthKitService.isAvailable` no longer appears in this file

---

## Phase 4: Expand MockDataInjector

### 4.1 — Update injection guard and save logic (Plan Step 11, actions 1–2)

- [ ] In `WellPlate/Core/Services/MockDataInjector.swift`, replace the guard in `inject(into:)`:
  - Remove: `guard !AppConfig.shared.mockDataInjected else { return }`
  - Add: `FetchDescriptor<FoodLogEntry>` with `#Predicate { $0.logSource == "mock" }`, guard `fetchCount == 0`
  - Verify: The guard checks existing mock data, NOT the `mockMode` flag
- [ ] Remove `AppConfig.shared.mockDataInjected = true` from the success path
  - Verify: No `mockDataInjected` references remain in `inject(into:)`

### 4.2 — Update injectWellnessLogs signature

- [ ] Update `injectWellnessLogs` method signature to accept `injectedDates: inout [String]`
  - Replace the internal `AppConfig.shared.mockInjectedWellnessLogDates = injectedDates` at end of method → append to the `inout` parameter instead
  - Verify: `mockInjectedWellnessLogDates` no longer appears in this file

### 4.3 — Add injectSymptomEntries method

- [ ] Add `private static func injectSymptomEntries(into context: ModelContext, today: Date, cal: Calendar)`
  - 4 symptom templates: Headache (.pain), Bloating (.digestive), Fatigue (.energy), Brain Fog (.cognitive)
  - Inject on every 3rd day (10 entries), with `notes: "[mock]"` tag
  - Verify: Method compiles. `SymptomEntry` init accepts `notes` parameter.

### 4.4 — Add injectFastingSessions method

- [ ] Add `private static func injectFastingSessions(into context: ModelContext, today: Date, cal: Calendar, injectedDates: inout [String])`
  - 15 completed 16:8 sessions (every 2nd day), startTime 8pm previous day, 16h duration
  - Set `actualEndAt` and `completed = true`
  - Track start dates in `injectedDates`
  - Verify: Method compiles. `FastingSession` init matches.

### 4.5 — Add injectAdherenceLogs method

- [ ] Add `private static func injectAdherenceLogs(into context: ModelContext, today: Date, cal: Calendar, injectedIDs: inout [String])`
  - 2 supplements (Vitamin D at 8am, Omega-3 at 8pm), 30 days
  - Mix of "taken" (6/7 days) and "skipped" (every 7th day)
  - Track UUIDs in `injectedIDs`
  - Verify: Method compiles. `AdherenceLog` init matches.

### 4.6 — Add injectJournalEntries method

- [ ] Add `private static func injectJournalEntries(into context: ModelContext, today: Date, cal: Calendar, injectedDates: inout [String])`
  - 10 entries every 3rd day, with `promptUsed: "[mock]"` tag
  - Check `fetchCount` for existing JournalEntry on each day before inserting (unique constraint)
  - Track dates in `injectedDates`
  - Verify: Method compiles. `JournalEntry` init matches. `@Attribute(.unique) var day` conflict is handled by pre-check.

### 4.7 — Wire new methods into inject(into:)

- [ ] Update `inject(into:)` to:
  - Declare `var injectedDates: [String] = []` and `var injectedIDs: [String] = []`
  - Call `injectWellnessLogs(into:today:cal:injectedDates:)` with `&injectedDates`
  - Call `injectSymptomEntries(into:today:cal:)`
  - Call `injectFastingSessions(into:today:cal:injectedDates:)` with `&injectedDates`
  - Call `injectAdherenceLogs(into:today:cal:injectedIDs:)` with `&injectedIDs`
  - Call `injectJournalEntries(into:today:cal:injectedDates:)` with `&injectedDates`
  - After `context.save()`, set `AppConfig.shared.mockInjectedDates = injectedDates` and `AppConfig.shared.mockInjectedRecordIDs = injectedIDs`
  - Verify: All 7 inject methods are called. Dates and IDs are persisted.

### 4.8 — Update deleteAll(from:)

- [ ] Update `deleteAll(from:)` to handle all 7 model types:
  - [ ] FoodLogEntry: by `logSource == "mock"` predicate (existing)
  - [ ] StressReading: by `source == "mock"` predicate (existing)
  - [ ] SymptomEntry: by `notes == "[mock]"` predicate (new)
  - [ ] JournalEntry: by `promptUsed == "[mock]"` predicate (new)
  - [ ] WellnessDayLog: by tracked dates from `AppConfig.shared.mockInjectedDates` (existing, use renamed property)
  - [ ] FastingSession: by tracked dates + `.completed` filter (new)
  - [ ] AdherenceLog: by tracked UUIDs from `AppConfig.shared.mockInjectedRecordIDs` (new)
  - After save, clear: `AppConfig.shared.mockInjectedDates = []` and `AppConfig.shared.mockInjectedRecordIDs = []`
  - Verify: `mockDataInjected` no longer appears anywhere in this file. `mockInjectedWellnessLogDates` no longer appears.

---

## Phase 5: Profile UI Unification

### 5.1 — Rewrite MockDataDebugCard (Plan Step 12)

- [ ] In `WellPlate/Features + UI/Tab/MockDataDebugCard.swift`, replace entire contents:
  - Rename struct `MockDataDebugCard` → `MockModeDebugCard`
  - Properties: `@Binding var isMockMode: Bool`, `let hasGroqAPIKey: Bool`, `let onToggle: (Bool) -> Void`
  - Single `Toggle("Enable Mock Mode", isOn: $isMockMode)` with `onChange` calling `onToggle`
  - Active/Off status capsule badge
  - Mock-on description text, mock-off shows Groq API key status
  - Verify: Struct compiles. Uses `.r()` font, `.appShadow()`, `AppColors.brand`.

### 5.2 — Update ProfileView (Plan Steps 13–14)

- [ ] In `WellPlate/Features + UI/Tab/ProfileView.swift`, remove `@State private var mockDataInjected` (line 98)
  - Verify: No compiler error within ProfileView for this removal (yet — compile errors from card usage expected)
- [ ] Rename `showMockDataRestartAlert` → `showMockModeRestartAlert` (line 99)
  - Verify: State name updated
- [ ] Replace both `NutritionSourceDebugCard(...)` and `MockDataDebugCard(...)` blocks (lines 164–184) with single `MockModeDebugCard(isMockMode:hasGroqAPIKey:onToggle:)`:
  - `onToggle` closure: set `AppConfig.shared.mockMode = enabled`, call `MockDataInjector.inject` or `deleteAll`, set `showMockModeRestartAlert = true`
  - Verify: Only one debug card in the `#if DEBUG` block
- [ ] Remove `onChange(of: mockModeEnabled)` handler (lines 205–208)
  - Verify: No `.onChange(of: mockModeEnabled)` modifier in ProfileView
- [ ] Update alert to use `showMockModeRestartAlert` with "Restart Required" title
  - Verify: Alert message references mock mode (not mock data)
- [ ] Update `refreshDebugNutritionState()` — remove `mockDataInjected` line
  - Verify: Method only refreshes `mockModeEnabled` and `hasGroqAPIKey`
- [ ] Delete the `NutritionSourceDebugCard` struct definition (lines 1558–1603)
  - Verify: Struct no longer exists. No references to it remain.

---

## Phase 6: Cleanup & Verification

### 6.1 — Verify no stale references (Plan Steps 15–17)

- [ ] Run: `grep -r "mockDataInjected" WellPlate/ --include="*.swift"`
  - Verify: **Zero results**. If any remain, fix them.
- [ ] Run: `grep -r "mockInjectedWellnessLogDates" WellPlate/ --include="*.swift"`
  - Verify: **Zero results**. All references should use `mockInjectedDates`.
- [ ] Run: `grep -r "HealthKitService()" WellPlate/ --include="*.swift"`
  - Verify: Results only in:
    - `HealthKitServiceFactory.swift` (the factory creates it)
    - `#Preview` blocks
    - `HealthKitService.swift` itself (if any)
  - No results in ViewModel inits or View methods.
- [ ] Run: `grep -r "NutritionSourceDebugCard" WellPlate/ --include="*.swift"`
  - Verify: **Zero results**.
- [ ] Run: `grep -r "MockDataDebugCard" WellPlate/ --include="*.swift"`
  - Verify: **Zero results** (struct renamed to `MockModeDebugCard`).

---

## Post-Implementation

### Build all 4 targets

- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`

### Final check

- [ ] All 4 builds pass with zero errors
- [ ] Git commit with descriptive message
