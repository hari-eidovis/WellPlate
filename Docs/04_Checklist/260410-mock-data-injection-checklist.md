# Implementation Checklist: Mock Data Injection System

**Source Plan**: [260410-mock-data-injection-plan-RESOLVED.md](../02_Planning/Specs/260410-mock-data-injection-plan-RESOLVED.md)
**Date**: 2026-04-10

---

## Pre-Implementation

- [ ] Read and understand the RESOLVED plan
- [ ] Verify all referenced files exist:
  - `WellPlate/Core/AppConfig.swift`
  - `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
  - `WellPlate/Core/Services/MockHealthKitService.swift`
  - `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`
  - `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`
  - `WellPlate/Features + UI/Tab/MainTabView.swift`
  - `WellPlate/Core/Services/StressInsightService.swift`
  - `WellPlate/Features + UI/Burn/Views/BurnView.swift`
  - `WellPlate/Features + UI/Home/Views/HomeView.swift`
  - `WellPlate/Features + UI/Tab/ProfileView.swift`
  - `WellPlate/Features + UI/Home/Views/HomeAIInsightView.swift`

---

## Phase 1: Core Infrastructure

### 1.1 — AppConfig: add `mockDataInjected` flag

**File**: `WellPlate/Core/AppConfig.swift`

- [ ] Add new key constants inside `private enum Keys`:
  ```
  static let mockDataInjected = "app.mock.dataInjected"
  static let mockInjectedWellnessLogDates = "app.mock.wellnessLogDates"
  ```
  - Verify: keys are inside the existing `Keys` enum alongside `mockMode`, `groqModel`, etc.

- [ ] Add `mockDataInjected` property (Release-safe, matching `mockMode` pattern):
  ```swift
  var mockDataInjected: Bool {
      get {
          #if DEBUG
          return UserDefaults.standard.bool(forKey: Keys.mockDataInjected)
          #else
          return false
          #endif
      }
      set {
          #if DEBUG
          UserDefaults.standard.set(newValue, forKey: Keys.mockDataInjected)
          WPLogger.app.info("Mock Data Injection → \(newValue ? "ACTIVE" : "CLEARED")")
          #endif
      }
  }
  ```
  - Verify: property structure matches existing `mockMode` pattern (get/set with `#if DEBUG` inside, not around)

- [ ] Add `mockInjectedWellnessLogDates` property:
  ```swift
  var mockInjectedWellnessLogDates: [String] {
      get {
          #if DEBUG
          return UserDefaults.standard.stringArray(forKey: Keys.mockInjectedWellnessLogDates) ?? []
          #else
          return []
          #endif
      }
      set {
          #if DEBUG
          UserDefaults.standard.set(newValue, forKey: Keys.mockInjectedWellnessLogDates)
          #endif
      }
  }
  ```
  - Verify: both properties compile without errors when referenced from non-`#if DEBUG` code

### 1.2 — Extend StressMockSnapshot with water & exercise data

**File**: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`

- [ ] Add two new stored properties to the `StressMockSnapshot` struct (after `daylightHistory`):
  ```swift
  let waterHistory: [DailyMetricSample]
  let exerciseMinutesHistory: [DailyMetricSample]
  ```
  - Verify: properties are declared alongside the other `let ...History` arrays

- [ ] Add generation arrays in `makeDefault()` (after `daylightBase` array):
  ```swift
  let waterBase: [Double] = [
      1.5, 2.0, 1.8, 2.2, 1.3, 1.9, 2.1,
      1.7, 2.1, 2.4, 1.2, 1.8, 2.0, 1.6,
      2.3, 1.5, 1.4, 2.2, 1.9, 2.0,
      1.6, 2.1, 2.2, 1.3, 1.8, 2.3, 1.7,
      1.9, 2.1, 1.8
  ]
  let exerciseBase: [Double] = [
      30, 45, 0, 60, 20, 35, 50,
      25, 40, 55, 0, 30, 45, 15,
      50, 20, 10, 60, 35, 40,
      0, 45, 50, 15, 30, 55, 25,
      35, 45, 30
  ]
  let waterHist = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: waterBase[$0]) }
  let exerciseHist = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: exerciseBase[$0]) }
  ```
  - Verify: arrays have exactly 30 elements each

- [ ] Update the `return StressMockSnapshot(...)` call in `makeDefault()` to include the new fields:
  ```
  waterHistory: waterHist,
  exerciseMinutesHistory: exerciseHist
  ```
  - Verify: no compiler errors from memberwise init — all existing call sites use `.default` so only `makeDefault()` needs updating

### 1.3 — Update MockHealthKitService

**File**: `WellPlate/Core/Services/MockHealthKitService.swift`

- [ ] Replace the `fetchWater` method body (currently returns `[]`):
  ```swift
  func fetchWater(for range: DateInterval) async throws -> [DailyMetricSample] {
      snapshot.waterHistory.filter { range.contains($0.date) }
  }
  ```
  - Verify: matches the pattern of `fetchSteps`, `fetchHeartRate`, etc. in the same file

- [ ] Replace the `fetchExerciseMinutes` method body (currently returns `[]`):
  ```swift
  func fetchExerciseMinutes(for range: DateInterval) async throws -> [DailyMetricSample] {
      snapshot.exerciseMinutesHistory.filter { range.contains($0.date) }
  }
  ```
  - Verify: both methods now reference snapshot properties, not returning empty arrays

### 1.4 — Create MockDataInjector

**File**: `WellPlate/Core/Services/MockDataInjector.swift` (NEW)

- [ ] Create the file at `WellPlate/Core/Services/MockDataInjector.swift`
  - Verify: file is inside `WellPlate/` directory (auto-included in build via `PBXFileSystemSynchronizedRootGroup`)

- [ ] Wrap entire file in `#if DEBUG ... #endif`

- [ ] Implement `enum MockDataInjector` with:
  - `static func inject(into context: ModelContext)` — generates and inserts 30 days of data
  - `static func deleteAll(from context: ModelContext)` — removes mock data only
  - Verify: `import SwiftData` and `import Foundation` at top

- [ ] Implement `inject(into:)`:
  - [ ] Guard: `guard !AppConfig.shared.mockDataInjected else { return }`
  - [ ] Call `injectFoodLogs(into:today:cal:)`
  - [ ] Call `injectWellnessLogs(into:today:cal:)`
  - [ ] Call `injectStressReadings(into:today:cal:)`
  - [ ] Call `try context.save()`
  - [ ] Set `AppConfig.shared.mockDataInjected = true`
  - Verify: guard prevents double-injection

- [ ] Implement `injectFoodLogs(into:today:cal:)`:
  - [ ] Define meal template pool (~20 templates: 5 breakfast, 5 lunch, 5 dinner, 5 snack) with realistic names, macros, serving sizes
  - [ ] Loop 30 days: for each day, pick 1 breakfast, 1 lunch, 1 dinner, optionally 1 snack (using `dayIndex % 5` rotation within each group)
  - [ ] Set `logSource = "mock"` on every entry
  - [ ] Set `confidence = 0.90` on all entries
  - [ ] Insert each `FoodLogEntry` into context
  - Verify: entries have varied food names across days, `logSource` is consistently `"mock"`

- [ ] Implement `injectWellnessLogs(into:today:cal:)`:
  - [ ] Fetch existing `WellnessDayLog` records in 30-day range using `FetchDescriptor` with predicate
  - [ ] Build set of existing dates
  - [ ] Loop 30 days: skip days with existing records
  - [ ] For each new day, create `WellnessDayLog` with:
    - `moodRaw`: cycle 0-4
    - `waterGlasses`: 3-8 range
    - `exerciseMinutes`: varied (0, 30, 45, 20, 60, 35, 50)
    - `caloriesBurned`: varied (150-420)
    - `steps`: varied (4200-9300)
    - `stressLevel`: cycle "Excellent", "Good", "Moderate", "Good", "High"
    - `coffeeCups`: 0-3
    - `coffeeType`: varied with nil option
  - [ ] Track injected dates as ISO8601 strings in `AppConfig.shared.mockInjectedWellnessLogDates`
  - Verify: no crash from `@Attribute(.unique)` on `day` — existing days are skipped

- [ ] Implement `injectStressReadings(into:today:cal:)`:
  - [ ] Define 5 score patterns and reading hours `[7, 10, 13, 16, 20]`
  - [ ] Loop 30 days × 3-5 readings per day
  - [ ] Set `source = "mock"` on every reading
  - [ ] Derive `levelLabel` from `StressLevel(score:).label`
  - Verify: readings have realistic intraday patterns (lower morning, peak afternoon)

- [ ] Implement `deleteAll(from:)`:
  - [ ] Fetch and delete `FoodLogEntry` where `logSource == "mock"` using `#Predicate`
  - [ ] Fetch and delete `StressReading` where `source == "mock"` using `#Predicate`
  - [ ] Fetch and delete `WellnessDayLog` by tracked ISO8601 dates from `AppConfig.shared.mockInjectedWellnessLogDates`
  - [ ] Call `try? context.save()`
  - [ ] Set `AppConfig.shared.mockDataInjected = false`
  - [ ] Clear `AppConfig.shared.mockInjectedWellnessLogDates = []`
  - Verify: deletion targets only mock records; real data untouched

### 1.5 — Checkpoint build

- [ ] Build main target to catch early errors:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: build succeeds with no errors

---

## Phase 2: HealthKit Service Wiring

### 2.1 — BurnViewModel: auto-detect mock + mock-aware guard

**File**: `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`

- [ ] Change init signature from `init(service: HealthKitServiceProtocol = HealthKitService())` to:
  ```swift
  init(service: HealthKitServiceProtocol? = nil) {
      if let service {
          self.service = service
      } else if AppConfig.shared.mockDataInjected {
          self.service = MockHealthKitService(snapshot: .default)
      } else {
          self.service = HealthKitService()
      }
  }
  ```
  - Verify: `self.service` is the existing `private let service: HealthKitServiceProtocol` — no type change needed

- [ ] Add mock-aware early return at the top of `requestPermissionAndLoad()` (before the existing `guard HealthKitService.isAvailable`):
  ```swift
  if AppConfig.shared.mockDataInjected {
      isLoading = true
      defer { isLoading = false }
      isAuthorized = true
      await loadData()
      return
  }
  ```
  - Verify: pattern matches `StressViewModel.requestPermissionAndLoad()` lines 160-166

### 2.2 — WellnessCalendarViewModel: auto-detect mock + mock-aware guard

**File**: `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`

- [ ] Change init signature from `init(healthService: HealthKitServiceProtocol = HealthKitService())` to:
  ```swift
  init(healthService: HealthKitServiceProtocol? = nil) {
      if let healthService {
          self.healthService = healthService
      } else if AppConfig.shared.mockDataInjected {
          self.healthService = MockHealthKitService(snapshot: .default)
      } else {
          self.healthService = HealthKitService()
      }
  }
  ```
  - Verify: `self.healthService` is the existing `private let healthService: HealthKitServiceProtocol`

- [ ] In `loadHealthKitActivity(for:)` (private method), replace the guard:
  ```swift
  // Before:
  guard HealthKitService.isAvailable else { return }
  // After:
  if !AppConfig.shared.mockDataInjected {
      guard HealthKitService.isAvailable else { return }
  }
  ```
  - Verify: when `mockDataInjected` is true, the method proceeds to use `self.healthService` (which is now MockHealthKitService)

### 2.3 — BurnView: mock-aware availability check

**File**: `WellPlate/Features + UI/Burn/Views/BurnView.swift`

- [ ] Change the view-body availability check:
  ```swift
  // Before:
  if !HealthKitService.isAvailable {
  // After:
  if !HealthKitService.isAvailable && !AppConfig.shared.mockDataInjected {
  ```
  - Verify: this is in the `Group { ... }` inside the `body` computed property

### 2.4 — MainTabView: extend StressViewModel mock trigger

**File**: `WellPlate/Features + UI/Tab/MainTabView.swift`

- [ ] Change the `#if DEBUG` condition in the Stress tab (currently `if AppConfig.shared.mockMode`):
  ```swift
  // Before:
  if AppConfig.shared.mockMode {
  // After:
  if AppConfig.shared.mockMode || AppConfig.shared.mockDataInjected {
  ```
  - Verify: when `mockDataInjected` is true, `StressViewModel` receives `MockHealthKitService` + `StressMockSnapshot`

### 2.5 — StressInsightService: auto-detect mock

**File**: `WellPlate/Core/Services/StressInsightService.swift`

- [ ] Change init signature from `init(healthService: HealthKitServiceProtocol = HealthKitService())` to:
  ```swift
  @MainActor
  init(healthService: HealthKitServiceProtocol? = nil) {
      if let healthService {
          self.healthService = healthService
      } else if AppConfig.shared.mockDataInjected {
          self.healthService = MockHealthKitService(snapshot: .default)
      } else {
          self.healthService = HealthKitService()
      }
  }
  ```
  - Verify: both call sites (`HomeView.swift:61` `@StateObject private var insightService = StressInsightService()` and `HomeAIInsightView.swift` `let svc = StressInsightService()`) use default init — no call-site changes needed

### 2.6 — HomeView: guard HK mood calls

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

- [ ] In `fetchHealthMoodSuggestion()`, add mock guard before the existing `guard HealthKitService.isAvailable`:
  ```swift
  private func fetchHealthMoodSuggestion() {
      if AppConfig.shared.mockDataInjected { return }
      guard HealthKitService.isAvailable else { return }
      // ... rest unchanged ...
  }
  ```
  - Verify: when mock is active, no HealthKit mood fetch is attempted

- [ ] In `logMoodForTodayIfNeeded()`, update the HK write guard:
  ```swift
  // Before:
  if HealthKitService.isAvailable {
      Task { try? await HealthKitService().writeMood(mood) }
  }
  // After:
  if HealthKitService.isAvailable && !AppConfig.shared.mockDataInjected {
      Task { try? await HealthKitService().writeMood(mood) }
  }
  ```
  - Verify: when mock is active, mood is saved to SwiftData only (no HK write)

### 2.7 — Checkpoint build

- [ ] Build main target:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: build succeeds — all VM init changes and guard changes compile cleanly

---

## Phase 3: Profile UI

### 3.1 — Create MockDataDebugCard

**File**: `WellPlate/Features + UI/Tab/MockDataDebugCard.swift` (NEW)

- [ ] Create file at `WellPlate/Features + UI/Tab/MockDataDebugCard.swift`
  - Verify: file is in `WellPlate/` directory (auto-included in build)

- [ ] Wrap entire file in `#if DEBUG ... #endif`

- [ ] Implement `struct MockDataDebugCard: View` with:
  - `@Binding var isInjected: Bool`
  - `let onInject: () -> Void`
  - `let onDelete: () -> Void`
  - `@State private var showDeleteConfirmation = false`

- [ ] Build the card body matching `NutritionSourceDebugCard` style:
  - Header: orange icon (`cylinder.split.1x2.fill`) + "Mock Data" title + status badge capsule (green "Active" / gray "Inactive")
  - Description text explaining what it does
  - Two buttons in HStack: "Inject Data" (`.borderedProminent`, tint `AppColors.brand`, disabled when `isInjected`) + "Clear" (`.bordered`, tint `.red`, disabled when `!isInjected`)
  - `.confirmationDialog` on the Clear button ("Clear all mock data?" with destructive action)
  - Card background: `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)`
  - Verify: fonts use `.r(.headline, .semibold)` and `.r(.subheadline, .semibold)` etc. (project convention)

### 3.2 — ProfileView integration

**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`

- [ ] Add state variables inside the existing `#if DEBUG` block (after `hasGroqAPIKey` at ~line 98):
  ```swift
  @State private var mockDataInjected: Bool = AppConfig.shared.mockDataInjected
  @State private var showMockDataRestartAlert = false
  ```
  - Verify: these are alongside the existing `mockModeEnabled` and `hasGroqAPIKey` debug state vars

- [ ] Add `MockDataDebugCard` in the body, inside the existing `#if DEBUG` block, after `NutritionSourceDebugCard` (~line 168):
  ```swift
  MockDataDebugCard(
      isInjected: $mockDataInjected,
      onInject: {
          MockDataInjector.inject(into: modelContext)
          mockDataInjected = AppConfig.shared.mockDataInjected
          showMockDataRestartAlert = true
      },
      onDelete: {
          MockDataInjector.deleteAll(from: modelContext)
          mockDataInjected = AppConfig.shared.mockDataInjected
          showMockDataRestartAlert = true
      }
  )
  .padding(.horizontal, 16)
  ```
  - Verify: card appears below the NutritionSourceDebugCard in the `VStack`

- [ ] Add restart alert on the `ScrollView` (or in the `.alert` chain), inside `#if DEBUG`:
  ```swift
  .alert("Mock Data Updated", isPresented: $showMockDataRestartAlert) {
      Button("OK") { }
  } message: {
      Text(mockDataInjected
           ? "30 days of mock data injected. Restart the app for HealthKit-backed screens (Burn, Stress) to reflect changes."
           : "Mock data cleared. Restart the app for full cleanup of HealthKit-backed screens.")
  }
  ```
  - Verify: alert text varies based on whether data was just injected or cleared

- [ ] Refresh debug state on appear — add `mockDataInjected = AppConfig.shared.mockDataInjected` inside the existing `refreshDebugNutritionState()` method or in `.onAppear`:
  - Verify: state stays in sync if user toggles mock data and returns to Profile

---

## Post-Implementation

### Build all 4 targets

- [ ] Main app:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
- [ ] ScreenTimeMonitor extension:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  ```
- [ ] ScreenTimeReport extension:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  ```
- [ ] Widget extension:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```
- Verify: all 4 targets build with zero errors

### Summary of files changed

**New files (2)**:
- `WellPlate/Core/Services/MockDataInjector.swift`
- `WellPlate/Features + UI/Tab/MockDataDebugCard.swift`

**Modified files (10)**:
- `WellPlate/Core/AppConfig.swift`
- `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
- `WellPlate/Core/Services/MockHealthKitService.swift`
- `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`
- `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`
- `WellPlate/Features + UI/Tab/MainTabView.swift`
- `WellPlate/Core/Services/StressInsightService.swift`
- `WellPlate/Features + UI/Burn/Views/BurnView.swift`
- `WellPlate/Features + UI/Home/Views/HomeView.swift`
- `WellPlate/Features + UI/Tab/ProfileView.swift`
