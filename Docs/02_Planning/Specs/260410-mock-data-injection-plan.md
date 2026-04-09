# Implementation Plan: Mock Data Injection System

## Overview

Add a developer-facing mock data injection system controllable from the Profile tab. When activated, it injects 30 days of realistic SwiftData records (`FoodLogEntry`, `WellnessDayLog`, `StressReading`) and swaps all HealthKit-backed ViewModels to use `MockHealthKitService`. Two buttons on Profile — "Inject" and "Clear" — control the lifecycle. All infrastructure is `#if DEBUG` only.

## Requirements

- Inject 30 days of mock SwiftData data (food logs, wellness logs, stress readings)
- Route all HK-backed screens (Burn, Sleep, Stress, Home, History) through `MockHealthKitService` when active
- Profile screen has inject/delete controls in a debug card
- Delete only removes injected data (tracked via UserDefaults UUID list)
- No SwiftData schema migration required
- All new code gated behind `#if DEBUG`

## Architecture Changes

| Component | Change |
|-----------|--------|
| `AppConfig.swift` | New `mockDataInjected` flag + UUID tracking keys |
| New `HealthKitServiceFactory.swift` | Returns real or mock service; replaces all direct `HealthKitService()` creation |
| New `MockDataInjector.swift` | Generates 30-day SwiftData records, tracks IDs, handles deletion |
| New `MockDataDebugCard.swift` | Profile UI with inject/delete buttons |
| `MainTabView.swift` | Pass factory-created service to Burn/Sleep VMs |
| `BurnView.swift` + `BurnViewModel.swift` | Accept service via init; use factory `isAvailable` check |
| `SleepView.swift` + `SleepViewModel.swift` | Same pattern |
| `WellnessCalendarView.swift` + `WellnessCalendarViewModel.swift` | Same pattern |
| `HomeView.swift` | Guard HK mood calls behind factory check |
| `StressMockSnapshot.swift` | Add water + exercise minutes data |
| `MockHealthKitService.swift` | Implement `fetchWater` + `fetchExerciseMinutes` from snapshot |
| `ProfileView.swift` | Add `MockDataDebugCard` below `NutritionSourceDebugCard` |

---

## Implementation Steps

### Phase 1: Core Infrastructure (3 new files + 1 modified)

#### Step 1.1 — AppConfig additions
**File**: `WellPlate/Core/AppConfig.swift`
**Action**: Add new UserDefaults-backed properties inside `#if DEBUG`:
```swift
private enum Keys {
    // ... existing keys ...
    static let mockDataInjected = "app.mock.dataInjected"
    static let mockInjectedFoodLogIDs = "app.mock.foodLogIDs"
    static let mockInjectedWellnessLogDates = "app.mock.wellnessLogDates"
    static let mockInjectedStressReadingIDs = "app.mock.stressReadingIDs"
}

#if DEBUG
var mockDataInjected: Bool {
    get { UserDefaults.standard.bool(forKey: Keys.mockDataInjected) }
    set { UserDefaults.standard.set(newValue, forKey: Keys.mockDataInjected) }
}
var mockInjectedFoodLogIDs: [String] {
    get { UserDefaults.standard.stringArray(forKey: Keys.mockInjectedFoodLogIDs) ?? [] }
    set { UserDefaults.standard.set(newValue, forKey: Keys.mockInjectedFoodLogIDs) }
}
var mockInjectedWellnessLogDates: [String] {
    get { UserDefaults.standard.stringArray(forKey: Keys.mockInjectedWellnessLogDates) ?? [] }
    set { UserDefaults.standard.set(newValue, forKey: Keys.mockInjectedWellnessLogDates) }
}
var mockInjectedStressReadingIDs: [String] {
    get { UserDefaults.standard.stringArray(forKey: Keys.mockInjectedStressReadingIDs) ?? [] }
    set { UserDefaults.standard.set(newValue, forKey: Keys.mockInjectedStressReadingIDs) }
}
#endif
```
**Why**: Track injection state and IDs separately per model type so deletion can target precisely.
**Note**: `WellnessDayLog` uses `@Attribute(.unique) var day: Date` so we track the date strings (ISO8601) instead of UUIDs (the model has no UUID property).
**Dependencies**: None
**Risk**: Low

#### Step 1.2 — HealthKitServiceFactory
**File**: `WellPlate/Core/Services/HealthKitServiceFactory.swift` (NEW)
**Action**: Create a factory enum:
```swift
#if DEBUG
import Foundation

enum HealthKitServiceFactory {
    /// Returns MockHealthKitService when mock data is injected, real service otherwise.
    static func make() -> HealthKitServiceProtocol {
        if AppConfig.shared.mockDataInjected {
            return MockHealthKitService(snapshot: .default)
        }
        return HealthKitService()
    }

    /// Replacement for `HealthKitService.isAvailable` that respects mock injection.
    static var isDataAvailable: Bool {
        if AppConfig.shared.mockDataInjected { return true }
        return HealthKitService.isAvailable
    }
}
#endif
```
**Why**: Single point of swap for all VM creation. Avoids modifying `HealthKitService` itself.
**Dependencies**: Step 1.1
**Risk**: Low

**Important note on `#if DEBUG` usage**: Since `HealthKitServiceFactory` is DEBUG-only, call sites will use conditional compilation:
```swift
#if DEBUG
let service = HealthKitServiceFactory.make()
#else
let service = HealthKitService()
#endif
```
Or more concisely, ViewModels that already accept `HealthKitServiceProtocol` just need the caller to pass the factory result.

#### Step 1.3 — MockDataInjector
**File**: `WellPlate/Core/Services/MockDataInjector.swift` (NEW)
**Action**: Create a service that generates and injects 30 days of SwiftData records.

**Data to generate**:

**FoodLogEntry** (2-4 entries per day, 30 days = ~90 records):
```
Day N: Breakfast, Lunch, optional Snack, Dinner
- Varied food names, realistic macros
- mealType set, logSource = "mock"
- Realistic calorie range: 200-700 per meal
```

**WellnessDayLog** (1 per day, 30 records):
```
- moodRaw: cycle through 0-4
- waterGlasses: 3-8 range
- exerciseMinutes: 0-60
- caloriesBurned: 150-500
- steps: 4000-10000
- stressLevel: cycle through "Excellent", "Good", "Moderate", "High"
- coffeeCups: 0-3
- coffeeType: varied
```

**StressReading** (3-5 per day, 30 days = ~120 records):
```
- Spread across waking hours (7am-10pm)
- Scores: 15-55 range with intraday variation
- levelLabel: derived from StressLevel(score:)
- source: "mock"
```

**Injection method**:
```swift
static func inject(into context: ModelContext) {
    guard !AppConfig.shared.mockDataInjected else { return }
    // Generate records, insert, save
    // Store IDs/dates in AppConfig
    AppConfig.shared.mockDataInjected = true
}
```

**Deletion method**:
```swift
static func deleteAll(from context: ModelContext) {
    // Fetch FoodLogEntry by stored UUIDs, delete
    // Fetch WellnessDayLog by stored dates, delete
    // Fetch StressReading by stored UUIDs — StressReading has no UUID, use timestamp matching
    // Clear UserDefaults arrays
    AppConfig.shared.mockDataInjected = false
}
```

**StressReading deletion strategy**: StressReading has no UUID field. Options:
- Track timestamps as ISO8601 strings (most reliable)
- Or: delete all StressReading where `source == "mock"` (simplest, leveraging the existing `source` field)

**Chosen**: Use `source == "mock"` predicate for StressReading deletion. For FoodLogEntry use `logSource == "mock"`. For WellnessDayLog, use tracked date strings since it has no tagging field.

**Revised tracking strategy** (simpler):
- `FoodLogEntry`: delete where `logSource == "mock"` — no ID tracking needed
- `StressReading`: delete where `source == "mock"` — no ID tracking needed
- `WellnessDayLog`: track injected day date strings in UserDefaults (model has unique `day` field, no source tag)

This means we can simplify `AppConfig` to only need:
- `mockDataInjected: Bool`
- `mockInjectedWellnessLogDates: [String]` (ISO8601 dates for WellnessDayLog cleanup)

**Dependencies**: Step 1.1
**Risk**: Medium — need to handle collision with existing real WellnessDayLog records for "today". Strategy: skip injection for any day that already has a WellnessDayLog record.

#### Step 1.4 — Extend StressMockSnapshot with water & exercise data
**File**: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
**Action**: Add two new arrays to the snapshot:
```swift
let waterHistory: [DailyMetricSample]       // litres per day
let exerciseMinutesHistory: [DailyMetricSample]
```
Add generation in `makeDefault()`:
```swift
let waterBase: [Double] = [1.5, 2.0, 1.8, 2.2, 1.3, 1.9, 2.1, ...] // 30 values, litres
let exerciseBase: [Double] = [30, 45, 0, 60, 20, 35, 50, ...]       // 30 values, minutes
```
**Why**: `MockHealthKitService.fetchWater` and `fetchExerciseMinutes` currently return empty arrays.
**Dependencies**: None
**Risk**: Low

#### Step 1.5 — Update MockHealthKitService
**File**: `WellPlate/Core/Services/MockHealthKitService.swift`
**Action**: Implement the two empty methods:
```swift
func fetchWater(for range: DateInterval) async throws -> [DailyMetricSample] {
    snapshot.waterHistory.filter { range.contains($0.date) }
}

func fetchExerciseMinutes(for range: DateInterval) async throws -> [DailyMetricSample] {
    snapshot.exerciseMinutesHistory.filter { range.contains($0.date) }
}
```
**Dependencies**: Step 1.4
**Risk**: Low

---

### Phase 2: HealthKit Service Wiring (modify existing Views/VMs)

The pattern for each ViewModel is identical:
1. The VM already accepts `HealthKitServiceProtocol` via init — no change to the VM init signature.
2. Replace `guard HealthKitService.isAvailable else { return }` with a mock-aware guard.
3. The View that creates the VM passes `HealthKitServiceFactory.make()` when in debug mode.

#### Step 2.1 — BurnViewModel mock-aware guard
**File**: `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`
**Action**: Replace `requestPermissionAndLoad()` guard (line ~101):
```swift
// Before:
guard HealthKitService.isAvailable else { return }

// After:
#if DEBUG
if AppConfig.shared.mockDataInjected {
    isLoading = true
    defer { isLoading = false }
    isAuthorized = true
    await loadData()
    return
}
#endif
guard HealthKitService.isAvailable else { return }
```
**Why**: When mock data is injected, skip HK availability check and authorization, go straight to data fetch via the protocol (which will be MockHealthKitService).
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.2 — SleepViewModel mock-aware guard
**File**: `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift`
**Action**: Same pattern as Step 2.1 — replace guard at line ~90.
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.3 — WellnessCalendarViewModel mock-aware guard
**File**: `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`
**Action**: Same pattern at line ~177.
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.4 — BurnView: pass factory service
**File**: `WellPlate/Features + UI/Burn/Views/BurnView.swift`
**Action**:
1. Change `@StateObject` creation to accept a service:
```swift
// Add property to accept service
private let healthService: HealthKitServiceProtocol

init(healthService: HealthKitServiceProtocol = HealthKitService()) {
    self.healthService = healthService
    _viewModel = StateObject(wrappedValue: BurnViewModel(service: healthService))
}
```
**Problem**: `@StateObject` wrappedValue must be set in init — SwiftUI constraint. This is fine.

2. Replace `HealthKitService.isAvailable` view guard (line 28):
```swift
// Before:
if !HealthKitService.isAvailable {

// After:
#if DEBUG
let hkAvailable = HealthKitServiceFactory.isDataAvailable
#else
let hkAvailable = HealthKitService.isAvailable
#endif
if !hkAvailable {
```
**Dependencies**: Steps 1.2, 2.1
**Risk**: Medium — `@StateObject` init pattern needs care

#### Step 2.5 — SleepView: pass factory service
**File**: `WellPlate/Features + UI/Sleep/Views/SleepView.swift`
**Action**: Same pattern as Step 2.4.
**Dependencies**: Steps 1.2, 2.2
**Risk**: Medium

#### Step 2.6 — WellnessCalendarView: pass factory service
**File**: `WellPlate/Features + UI/Home/Views/WellnessCalendarView.swift`
**Action**: Same pattern — `WellnessCalendarViewModel()` at line 11 needs factory service passed through.
**Dependencies**: Steps 1.2, 2.3
**Risk**: Medium

#### Step 2.7 — MainTabView: wire factory service
**File**: `WellPlate/Features + UI/Tab/MainTabView.swift`
**Action**: Already handles StressView mock. Extend to Burn and Sleep:
```swift
// MARK: - Burn (inside Tab)
Tab(value: X) {
    BurnView(healthService: {
        #if DEBUG
        if AppConfig.shared.mockDataInjected {
            return MockHealthKitService(snapshot: .default)
        }
        #endif
        return HealthKitService()
    }())
}
```
Wait — BurnView is inside a NavigationStack (Stress tab → nav push to Burn? Actually, let me check where BurnView is used).

**Note**: Looking at MainTabView, Burn and Sleep are NOT separate tabs. The tabs are: Home (0), Stress (1), History (2), Profile (3). Burn and Sleep are likely accessed via navigation from Home or Stress. Let me re-check.

Actually, looking at `WellnessRingDestination` in HomeView — tapping the Exercise ring goes to BurnView, tapping Stress goes to StressView. These are navigation destinations from HomeView. And SleepView is accessed from Stress detail or another nav link.

So the service needs to be passed from HomeView navigation destinations or created inline. Since BurnView and SleepView create `@StateObject private var viewModel = BurnViewModel()` at the struct level, the cleanest approach is:

**Alternative approach**: Instead of passing service through View init (which requires changing every call site), make the VMs query the factory internally:

```swift
init(service: HealthKitServiceProtocol? = nil) {
    #if DEBUG
    if let service {
        self.service = service
    } else if AppConfig.shared.mockDataInjected {
        self.service = MockHealthKitService(snapshot: .default)
    } else {
        self.service = HealthKitService()
    }
    #else
    self.service = service ?? HealthKitService()
    #endif
}
```

This is simpler — VMs auto-detect mock mode without needing changes to every View. The Views don't need any init changes at all. The factory logic lives in the VM init default.

**Revised approach for Steps 2.4-2.6**: Modify VM inits to auto-detect mock mode. No View init changes needed.

#### Step 2.4 (REVISED) — BurnViewModel auto-detect mock
**File**: `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`
**Action**: Change init default:
```swift
init(service: HealthKitServiceProtocol? = nil) {
    #if DEBUG
    if let service {
        self.service = service
    } else if AppConfig.shared.mockDataInjected {
        self.service = MockHealthKitService(snapshot: .default)
    } else {
        self.service = HealthKitService()
    }
    #else
    self.service = service ?? HealthKitService()
    #endif
}
```
**Dependencies**: Steps 1.1, 1.2
**Risk**: Low

#### Step 2.5 (REVISED) — SleepViewModel auto-detect mock
**File**: `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift`
**Action**: Same pattern.
**Dependencies**: Steps 1.1, 1.2
**Risk**: Low

#### Step 2.6 (REVISED) — WellnessCalendarViewModel auto-detect mock
**File**: `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`
**Action**: Same pattern.
**Dependencies**: Steps 1.1, 1.2
**Risk**: Low

#### Step 2.7 (REVISED) — MainTabView StressViewModel update
**File**: `WellPlate/Features + UI/Tab/MainTabView.swift`
**Action**: The existing code already swaps StressViewModel's service when `AppConfig.shared.mockMode` is on. Change the condition to also check `mockDataInjected`:
```swift
#if DEBUG
if AppConfig.shared.mockMode || AppConfig.shared.mockDataInjected {
    let snap = StressMockSnapshot.default
    return StressViewModel(
        healthService: MockHealthKitService(snapshot: snap),
        modelContext: modelContext,
        mockSnapshot: snap
    )
}
#endif
```
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.8 — BurnView + SleepView: mock-aware availability guards
**File**: `WellPlate/Features + UI/Burn/Views/BurnView.swift` (line 28)
**File**: `WellPlate/Features + UI/Sleep/Views/SleepView.swift` (line 29)
**Action**: Replace the view-level `HealthKitService.isAvailable` checks:
```swift
// Before:
if !HealthKitService.isAvailable {

// After (in both files):
if !Self.isHealthDataAvailable {
```
Add a static helper to each View (or a shared extension pattern):
```swift
private static var isHealthDataAvailable: Bool {
    #if DEBUG
    if AppConfig.shared.mockDataInjected { return true }
    #endif
    return HealthKitService.isAvailable
}
```
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.9 — HomeView: mock-aware HK calls
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`
**Action**: Two HK call sites need guards:
1. `fetchHealthMoodSuggestion()` (line 708): Replace `guard HealthKitService.isAvailable` with mock-aware check. When mock data is injected, skip the HK mood fetch entirely (HomeView gets mood from WellnessDayLog).
2. `logMoodForTodayIfNeeded()` (line 735): Replace `if HealthKitService.isAvailable` with mock-aware check. When mock data is injected, skip the HK mood write.

```swift
private func fetchHealthMoodSuggestion() {
    #if DEBUG
    if AppConfig.shared.mockDataInjected { return }
    #endif
    guard HealthKitService.isAvailable else { return }
    // ... existing code ...
}
```
**Dependencies**: Step 1.1
**Risk**: Low

---

### Phase 3: Profile UI

#### Step 3.1 — MockDataDebugCard
**File**: `WellPlate/Features + UI/Tab/Components/MockDataDebugCard.swift` (NEW)
**Action**: Create a card matching the `NutritionSourceDebugCard` style:
```swift
#if DEBUG
struct MockDataDebugCard: View {
    @Binding var isInjected: Bool
    let onInject: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: icon + "Mock Data" title
            // Status badge: green "Active" or gray "Inactive"
            // Two buttons: "Inject 30-Day Data" / "Clear Mock Data"
            //   - Inject disabled when isInjected
            //   - Clear disabled when !isInjected
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }
}
#endif
```
**Dependencies**: None (independent UI)
**Risk**: Low

#### Step 3.2 — ProfileView integration
**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`
**Action**:
1. Add state variable:
```swift
#if DEBUG
@State private var mockDataInjected: Bool = AppConfig.shared.mockDataInjected
#endif
```
2. Add `MockDataDebugCard` below `NutritionSourceDebugCard` (around line 168):
```swift
MockDataDebugCard(
    isInjected: $mockDataInjected,
    onInject: { injectMockData() },
    onDelete: { deleteMockData() }
)
.padding(.horizontal, 16)
```
3. Add helper methods:
```swift
#if DEBUG
private func injectMockData() {
    MockDataInjector.inject(into: modelContext)
    mockDataInjected = true
}
private func deleteMockData() {
    MockDataInjector.deleteAll(from: modelContext)
    mockDataInjected = false
}
#endif
```
**Dependencies**: Steps 1.3, 3.1
**Risk**: Low

---

### Phase 4: Build Verification

#### Step 4.1 — Build all targets
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```
Fix any compilation errors.

#### Step 4.2 — Verify extension targets
```bash
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

---

## Testing Strategy

### Build Verification
- All 4 build targets compile without errors

### Manual Testing Flows
1. **Inject flow**: Profile → tap "Inject 30-Day Data" → button becomes disabled, status shows "Active"
2. **Home tab**: Wellness rings show calories, water, exercise, stress data. Meal log card shows mock food entries.
3. **Stress tab**: All vitals populated (HR, HRV, BP, RR), sleep and exercise factors filled, stress readings chart shows data
4. **History tab**: WellnessCalendar shows 30 days of colored dots. Day detail shows food logs + wellness metrics.
5. **Navigation to Burn**: BurnView shows 30-day active energy + steps charts (from MockHealthKitService)
6. **Navigation to Sleep**: SleepView shows 30-day sleep summaries with stage breakdowns
7. **Delete flow**: Profile → tap "Clear Mock Data" → data disappears from all screens, rings go to zero/empty
8. **Real data safety**: After clearing, any pre-existing real WellnessDayLog/FoodLogEntry records remain intact
9. **App restart**: After injecting and restarting, SwiftData records persist. HK-backed screens re-create MockHealthKitService from `mockDataInjected` flag.

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| WellnessDayLog collision (mock day overlaps real data) | Medium | `MockDataInjector.inject()` skips days that already have a WellnessDayLog record |
| VM created before flag is set (race on cold launch) | Low | `AppConfig.mockDataInjected` reads UserDefaults synchronously; VMs init on main thread |
| User taps inject twice | Low | Guard clause: `guard !AppConfig.shared.mockDataInjected else { return }` |
| `#if DEBUG` conditional compilation becomes messy | Medium | Keep the factory and injector as self-contained files; minimize inline `#if DEBUG` in VMs |
| StressViewModel `mockSnapshot != nil` check diverges from `mockDataInjected` flag | Medium | In MainTabView, check `mockDataInjected` alongside existing `mockMode` check |

## Success Criteria

- [ ] "Inject 30-Day Data" button on Profile populates all screens with data
- [ ] "Clear Mock Data" button removes only injected data, preserving real records
- [ ] Burn and Sleep screens show 30-day chart data when mock is active
- [ ] Stress screen shows full vitals + readings when mock is active
- [ ] Home rings show non-zero values for all 4 metrics when mock is active
- [ ] History/WellnessCalendar shows 30 days of entries when mock is active
- [ ] All 4 build targets compile cleanly
- [ ] App restart preserves mock data state (SwiftData records persist, HK mock auto-reactivates)
- [ ] No mock infrastructure appears in Release builds
