# Implementation Plan: Mock Data Injection System (RESOLVED)

## Audit Resolution Summary

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| C1 | CRITICAL | `StressInsightService` not covered | Added to Phase 2 as Step 2.5; both creation sites addressed |
| H1 | HIGH | `HealthKitServiceFactory` as `#if DEBUG` is fragile | Dropped standalone factory file; inlined detection in VM inits |
| H2 | HIGH | `SleepView` is dead code, not navigated to | Removed from plan; sleep path covered by StressViewModel |
| H3 | HIGH | `mockDataInjected` behind `#if DEBUG` is noisy | Changed to Release-safe pattern matching existing `mockMode` |
| M1 | MEDIUM | WellnessDayLog collision handling underspecified | Added explicit fetch-before-insert step with date range predicate |
| M2 | MEDIUM | Mock data quantity and realism | Added meal template pool specification |
| M3 | MEDIUM | `logSource == "mock"` may not filter uniquely | Acknowledged; acceptable for DEBUG tool, added code comment note |
| M4 | MEDIUM | View refresh after inject/delete | Added restart-app alert step in Phase 3 |
| M5 | MEDIUM | `StressMockSnapshot` property addition | Clarified: extend `makeDefault()`, add properties with no call site changes |
| M6 | MEDIUM | BurnView navigation paths | Verified: only one creation site (HomeView) |
| L1 | LOW | Widget doesn't share mock state | Acknowledged as out of scope |
| L2 | LOW | No confirmation for delete | Added `.confirmationDialog` for Clear action |

---

## Overview

Add a developer-facing mock data injection system controllable from the Profile tab. When activated, it injects 30 days of realistic SwiftData records (`FoodLogEntry`, `WellnessDayLog`, `StressReading`) and all HealthKit-backed ViewModels auto-detect the flag to use `MockHealthKitService`. Two buttons on Profile — "Inject" and "Clear" — control the lifecycle. All mock infrastructure is gated so Release builds always return real data.

## Requirements

- Inject 30 days of mock SwiftData data (food logs, wellness logs, stress readings)
- Route all HK-backed screens (Burn, Stress, Home, History) through `MockHealthKitService` when active
- Profile screen has inject/delete controls in a debug card
- Delete only removes injected data (tracked via source tags + UserDefaults date list)
- No SwiftData schema migration required
- Release builds always return `false` for `mockDataInjected` (zero overhead)

## Architecture Changes

<!-- RESOLVED: H1 — Dropped HealthKitServiceFactory file; using inline VM detection instead -->
<!-- RESOLVED: H2 — Removed SleepView/SleepViewModel from affected files -->
<!-- RESOLVED: C1 — Added StressInsightService to affected files -->

| Component | Change |
|-----------|--------|
| `AppConfig.swift` | New `mockDataInjected` flag (Release-safe) + `mockInjectedWellnessLogDates` |
| New `MockDataInjector.swift` | Generates 30-day SwiftData records, tracks IDs, handles deletion |
| New `MockDataDebugCard.swift` | Profile UI with inject/delete buttons |
| `MainTabView.swift` | Pass mock snapshot to StressViewModel when `mockDataInjected` is on |
| `BurnView.swift` | Mock-aware `isAvailable` check in view body |
| `BurnViewModel.swift` | Auto-detect mock in init; mock-aware `requestPermissionAndLoad()` |
| `WellnessCalendarView.swift` | (No change needed — VM auto-detects) |
| `WellnessCalendarViewModel.swift` | Auto-detect mock in init; mock-aware HK guard |
| `HomeView.swift` | Guard HK mood calls behind `mockDataInjected` check |
| `StressInsightService.swift` | Auto-detect mock in init |
| `HomeAIInsightView.swift` | (No change needed — service auto-detects) |
| `StressMockSnapshot.swift` | Add water + exercise minutes data arrays |
| `MockHealthKitService.swift` | Implement `fetchWater` + `fetchExerciseMinutes` from snapshot |
| `ProfileView.swift` | Add `MockDataDebugCard` below `NutritionSourceDebugCard` |

---

## Implementation Steps

### Phase 1: Core Infrastructure (2 new files + 3 modified)

#### Step 1.1 — AppConfig: add `mockDataInjected` flag
**File**: `WellPlate/Core/AppConfig.swift`

<!-- RESOLVED: H3 — Using Release-safe pattern matching existing mockMode -->

**Action**: Add new keys and a Release-safe property (matching the existing `mockMode` pattern):

```swift
private enum Keys {
    // ... existing keys ...
    static let mockDataInjected = "app.mock.dataInjected"
    static let mockInjectedWellnessLogDates = "app.mock.wellnessLogDates"
}

/// Whether mock data has been injected into SwiftData + HealthKit layer.
/// Always returns false in Release builds (same pattern as mockMode).
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

/// ISO8601 date strings of WellnessDayLog records created by mock injection.
/// Used for targeted cleanup (WellnessDayLog has no source tag field).
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

**Why**: Release-safe means VMs can reference `AppConfig.shared.mockDataInjected` without `#if DEBUG` blocks.
**Dependencies**: None
**Risk**: Low

#### Step 1.2 — Extend StressMockSnapshot with water & exercise data
**File**: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`

<!-- RESOLVED: M5 — Add properties to struct and extend makeDefault(); no call site changes needed since .default is the only usage -->

**Action**: Add two new stored properties to the struct:
```swift
let waterHistory: [DailyMetricSample]
let exerciseMinutesHistory: [DailyMetricSample]
```

Extend `makeDefault()` with generation data:
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

Update the return statement to include:
```swift
waterHistory: waterHist,
exerciseMinutesHistory: exerciseHist
```

**Why**: `MockHealthKitService.fetchWater()` and `fetchExerciseMinutes()` currently return `[]`.
**Dependencies**: None
**Risk**: Low — struct memberwise init is internal; `.default` is the only public entry point.

#### Step 1.3 — Update MockHealthKitService
**File**: `WellPlate/Core/Services/MockHealthKitService.swift`

**Action**: Replace the two empty-array methods:
```swift
func fetchWater(for range: DateInterval) async throws -> [DailyMetricSample] {
    snapshot.waterHistory.filter { range.contains($0.date) }
}

func fetchExerciseMinutes(for range: DateInterval) async throws -> [DailyMetricSample] {
    snapshot.exerciseMinutesHistory.filter { range.contains($0.date) }
}
```

**Dependencies**: Step 1.2
**Risk**: Low

#### Step 1.4 — MockDataInjector
**File**: `WellPlate/Core/Services/MockDataInjector.swift` (NEW)

<!-- RESOLVED: M1 — Added explicit fetch-before-insert for WellnessDayLog -->
<!-- RESOLVED: M2 — Added meal template pool specification -->
<!-- RESOLVED: M3 — Acknowledged; logSource="mock" convention documented in code comments -->

**Action**: Create a `#if DEBUG`-gated service that generates and injects 30 days of SwiftData records.

**Injection method**:
```swift
#if DEBUG
import SwiftData
import Foundation

enum MockDataInjector {

    /// Inject 30 days of mock data into SwiftData.
    /// Guards against double-injection via AppConfig flag.
    static func inject(into context: ModelContext) {
        guard !AppConfig.shared.mockDataInjected else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 1. Generate FoodLogEntry records
        injectFoodLogs(into: context, today: today, cal: cal)

        // 2. Generate WellnessDayLog records (skip existing days)
        injectWellnessLogs(into: context, today: today, cal: cal)

        // 3. Generate StressReading records
        injectStressReadings(into: context, today: today, cal: cal)

        // 4. Save
        do {
            try context.save()
            AppConfig.shared.mockDataInjected = true
        } catch {
            WPLogger.app.error("Mock data injection failed: \(error.localizedDescription)")
        }
    }

    /// Remove all mock-injected data.
    static func deleteAll(from context: ModelContext) {
        // FoodLogEntry: delete where logSource == "mock"
        // StressReading: delete where source == "mock"
        // WellnessDayLog: delete by tracked date strings
        // ... (implementation details below)
        AppConfig.shared.mockDataInjected = false
        AppConfig.shared.mockInjectedWellnessLogDates = []
    }
}
#endif
```

**FoodLogEntry generation** — meal template pool (cycle across 30 days):
```swift
private static let mealTemplates: [(name: String, key: String, serving: String,
                                     cal: Int, protein: Double, carbs: Double,
                                     fat: Double, fiber: Double, meal: String)] = [
    // Breakfast options
    ("Oatmeal with Berries",      "oatmeal_berries",    "1 bowl",  310, 9, 52, 6, 7, "Breakfast"),
    ("Scrambled Eggs & Toast",    "eggs_toast",          "2 eggs",  350, 22, 28, 16, 2, "Breakfast"),
    ("Greek Yogurt Parfait",      "yogurt_parfait",      "1 cup",   280, 18, 35, 8, 3, "Breakfast"),
    ("Avocado Toast",             "avocado_toast",        "2 slices", 320, 10, 30, 18, 7, "Breakfast"),
    ("Banana Smoothie",           "banana_smoothie",      "1 glass", 260, 8, 45, 5, 4, "Breakfast"),
    // Lunch options
    ("Grilled Chicken Salad",     "chicken_salad",        "1 plate", 450, 38, 22, 14, 6, "Lunch"),
    ("Turkey Sandwich",           "turkey_sandwich",      "1 whole", 420, 30, 38, 12, 4, "Lunch"),
    ("Vegetable Stir Fry",        "veg_stirfry",          "1 bowl",  380, 15, 42, 16, 8, "Lunch"),
    ("Lentil Soup",               "lentil_soup",          "1 bowl",  340, 18, 45, 8, 12, "Lunch"),
    ("Quinoa Bowl",               "quinoa_bowl",          "1 bowl",  410, 16, 50, 14, 9, "Lunch"),
    // Dinner options
    ("Salmon with Rice",          "salmon_rice",          "1 plate", 520, 35, 45, 18, 3, "Dinner"),
    ("Pasta Primavera",           "pasta_primavera",      "1 plate", 480, 16, 62, 14, 6, "Dinner"),
    ("Chicken Tikka Masala",      "tikka_masala",         "1 serving", 550, 32, 40, 22, 4, "Dinner"),
    ("Grilled Fish & Vegetables", "fish_vegetables",      "1 plate", 420, 38, 25, 16, 7, "Dinner"),
    ("Dal with Roti",             "dal_roti",             "2 roti",  460, 18, 55, 12, 10, "Dinner"),
    // Snack options
    ("Greek Yogurt",              "greek_yogurt",         "1 cup",   130, 17, 10, 2, 0, "Snack"),
    ("Mixed Nuts",                "mixed_nuts",           "1 handful", 180, 5, 8, 16, 3, "Snack"),
    ("Apple with Peanut Butter",  "apple_pb",             "1 apple", 200, 6, 28, 10, 4, "Snack"),
    ("Protein Bar",               "protein_bar",          "1 bar",   220, 20, 24, 8, 3, "Snack"),
    ("Hummus & Carrots",          "hummus_carrots",       "1 cup",   160, 6, 18, 8, 5, "Snack"),
]
```

Per day: pick 1 breakfast (index 0-4), 1 lunch (5-9), 1 dinner (10-14), and optionally 1 snack (15-19). Rotate using `dayIndex % 5` within each group. Set `logSource = "mock"` on all entries.
<!-- RESOLVED: M3 — logSource="mock" convention; add code comment: "// Convention: logSource='mock' used for cleanup. Do not use for real entries." -->

**WellnessDayLog generation** — collision-safe insertion:
```swift
private static func injectWellnessLogs(into context: ModelContext, today: Date, cal: Calendar) {
    // Fetch existing WellnessDayLog dates in the 30-day range
    let start = cal.date(byAdding: .day, value: -29, to: today)!
    let descriptor = FetchDescriptor<WellnessDayLog>(
        predicate: #Predicate { $0.day >= start && $0.day <= today }
    )
    let existingDays = Set((try? context.fetch(descriptor))?.map { cal.startOfDay(for: $0.day) } ?? [])

    var injectedDates: [String] = []
    let formatter = ISO8601DateFormatter()

    for offset in 0..<30 {
        let day = cal.date(byAdding: .day, value: -offset, to: today)!
        let startOfDay = cal.startOfDay(for: day)
        guard !existingDays.contains(startOfDay) else { continue }

        let log = WellnessDayLog(
            day: startOfDay,
            moodRaw: offset % 5,           // cycles 0-4
            waterGlasses: 3 + (offset % 6), // 3-8
            exerciseMinutes: [0, 30, 45, 20, 60, 35, 50][offset % 7],
            caloriesBurned: [150, 280, 340, 200, 420, 310, 380][offset % 7],
            steps: [4200, 6800, 7500, 5100, 9300, 7200, 8400][offset % 7],
            stressLevel: ["Excellent", "Good", "Moderate", "Good", "High"][offset % 5],
            coffeeCups: offset % 4,        // 0-3
            coffeeType: ["Latte", "Americano", "Cappuccino", nil][offset % 4]
        )
        context.insert(log)
        injectedDates.append(formatter.string(from: startOfDay))
    }

    AppConfig.shared.mockInjectedWellnessLogDates = injectedDates
}
```

**StressReading generation** — 3-5 readings per day:
```swift
private static func injectStressReadings(into context: ModelContext, today: Date, cal: Calendar) {
    let hours = [7, 10, 13, 16, 20]  // reading times
    let baseScores: [[Double]] = [
        [18, 25, 32, 28, 22],  // pattern 1
        [22, 30, 38, 35, 25],  // pattern 2
        [15, 20, 28, 24, 18],  // pattern 3
        [25, 35, 45, 40, 30],  // pattern 4
        [20, 28, 35, 30, 24],  // pattern 5
    ]
    for offset in 0..<30 {
        let day = cal.date(byAdding: .day, value: -offset, to: today)!
        let pattern = baseScores[offset % 5]
        let readingCount = 3 + (offset % 3)  // 3, 4, or 5
        for i in 0..<readingCount {
            guard let ts = cal.date(bySettingHour: hours[i], minute: 0, second: 0, of: day) else { continue }
            let score = pattern[i]
            let reading = StressReading(
                timestamp: ts,
                score: score,
                levelLabel: StressLevel(score: score).label,
                source: "mock"  // Used for cleanup: delete where source == "mock"
            )
            context.insert(reading)
        }
    }
}
```

**Deletion method**:
```swift
static func deleteAll(from context: ModelContext) {
    // 1. FoodLogEntry — delete where logSource == "mock"
    let foodDescriptor = FetchDescriptor<FoodLogEntry>(
        predicate: #Predicate { $0.logSource == "mock" }
    )
    if let mockFoods = try? context.fetch(foodDescriptor) {
        mockFoods.forEach { context.delete($0) }
    }

    // 2. StressReading — delete where source == "mock"
    let stressDescriptor = FetchDescriptor<StressReading>(
        predicate: #Predicate { $0.source == "mock" }
    )
    if let mockReadings = try? context.fetch(stressDescriptor) {
        mockReadings.forEach { context.delete($0) }
    }

    // 3. WellnessDayLog — delete by tracked dates
    let formatter = ISO8601DateFormatter()
    let trackedDates = AppConfig.shared.mockInjectedWellnessLogDates.compactMap { formatter.date(from: $0) }
    for date in trackedDates {
        let start = date
        let end = Calendar.current.date(byAdding: .second, value: 1, to: start)!
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day >= start && $0.day < end }
        )
        if let logs = try? context.fetch(descriptor) {
            logs.forEach { context.delete($0) }
        }
    }

    // 4. Save + clear flag
    try? context.save()
    AppConfig.shared.mockDataInjected = false
    AppConfig.shared.mockInjectedWellnessLogDates = []
}
```

**Dependencies**: Step 1.1
**Risk**: Medium — WellnessDayLog unique constraint collision is now handled via fetch-before-insert.

---

### Phase 2: HealthKit Service Wiring (modify existing VMs + Views)

<!-- RESOLVED: H1 — No standalone factory file. Each VM checks AppConfig.shared.mockDataInjected in its init -->
<!-- RESOLVED: H2 — SleepView/SleepViewModel removed from plan -->
<!-- RESOLVED: H3 — mockDataInjected is Release-safe, so no #if DEBUG needed in VM inits -->

The pattern for each ViewModel is identical. Since `AppConfig.shared.mockDataInjected` returns `false` in Release builds (Step 1.1), VMs can reference it without `#if DEBUG`:

```swift
// Pattern applied to each VM init:
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

And the `requestPermissionAndLoad()` pattern:
```swift
func requestPermissionAndLoad() async {
    if AppConfig.shared.mockDataInjected {
        isLoading = true
        defer { isLoading = false }
        isAuthorized = true
        await loadData()
        return
    }
    guard HealthKitService.isAvailable else { return }
    // ... existing real authorization + load ...
}
```

#### Step 2.1 — BurnViewModel: auto-detect mock + mock-aware guard
**File**: `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`
**Action**:
1. Change init to accept optional service with auto-detect:
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
2. Add mock-aware guard in `requestPermissionAndLoad()` (before existing `guard HealthKitService.isAvailable`):
```swift
if AppConfig.shared.mockDataInjected {
    isLoading = true
    defer { isLoading = false }
    isAuthorized = true
    await loadData()
    return
}
```
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.2 — WellnessCalendarViewModel: auto-detect mock + mock-aware guard
**File**: `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`
**Action**: Same pattern as Step 2.1:
1. Change init default to auto-detect mock
2. Add mock-aware guard in `loadHealthKitActivity(for:)` (line 177, the private method):
```swift
private func loadHealthKitActivity(for day: Date) async {
    if !AppConfig.shared.mockDataInjected {
        guard HealthKitService.isAvailable else { return }
    }
    // ... rest of method uses self.healthService (already protocol-based) ...
}
```
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.3 — BurnView: mock-aware availability check
**File**: `WellPlate/Features + UI/Burn/Views/BurnView.swift`
**Action**: Replace the view-level `HealthKitService.isAvailable` check (line 28):
```swift
// Before:
if !HealthKitService.isAvailable {

// After:
if !HealthKitService.isAvailable && !AppConfig.shared.mockDataInjected {
```
**Why**: When mock data is injected, skip the "unavailable" view and show the main content even on Simulator.
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.4 — MainTabView: extend StressViewModel mock trigger
**File**: `WellPlate/Features + UI/Tab/MainTabView.swift`
**Action**: The existing code checks `AppConfig.shared.mockMode`. Extend to also check `mockDataInjected`:
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

<!-- RESOLVED: C1 — Added StressInsightService to plan -->

#### Step 2.5 — StressInsightService: auto-detect mock
**File**: `WellPlate/Core/Services/StressInsightService.swift`
**Action**: Change init to auto-detect mock (same pattern as other VMs):
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
**Why**: `StressInsightService` is created in two places:
- `HomeView.swift:61` — `@StateObject private var insightService = StressInsightService()`
- `HomeAIInsightView.swift:630` — `let svc = StressInsightService()`
Both use the default init, so the auto-detect pattern handles both without any call-site changes.
**Dependencies**: Step 1.1
**Risk**: Low

#### Step 2.6 — HomeView: guard HK mood calls
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`
**Action**: Two HK call sites need mock guards:

1. `fetchHealthMoodSuggestion()` (~line 693):
```swift
private func fetchHealthMoodSuggestion() {
    if AppConfig.shared.mockDataInjected { return }
    guard HealthKitService.isAvailable else { return }
    // ... existing code unchanged ...
}
```

2. `logMoodForTodayIfNeeded()` (~line 735, the HK write):
```swift
if HealthKitService.isAvailable && !AppConfig.shared.mockDataInjected {
    Task { try? await HealthKitService().writeMood(mood) }
}
```

**Why**: When mock data is injected, don't try to read from or write to a real HealthKit store.
**Dependencies**: Step 1.1
**Risk**: Low

---

### Phase 3: Profile UI

#### Step 3.1 — MockDataDebugCard
**File**: `WellPlate/Features + UI/Tab/Components/MockDataDebugCard.swift` (NEW)

<!-- RESOLVED: L2 — Added confirmationDialog for Clear action -->

**Action**: Create a card matching the `NutritionSourceDebugCard` style:
```swift
#if DEBUG
import SwiftUI

struct MockDataDebugCard: View {
    @Binding var isInjected: Bool
    let onInject: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "cylinder.split.1x2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text("Mock Data")
                    .font(.r(.headline, .semibold))
                Spacer()
                // Status badge
                Text(isInjected ? "Active" : "Inactive")
                    .font(.r(.caption2, .semibold))
                    .foregroundStyle(isInjected ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isInjected ? Color.green : Color.secondary).opacity(0.15))
                    )
            }

            Text("Inject 30 days of realistic food logs, wellness data, stress readings, and HealthKit metrics across all screens.")
                .font(.r(.caption, .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    onInject()
                } label: {
                    Label("Inject Data", systemImage: "plus.circle.fill")
                        .font(.r(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brand)
                .disabled(isInjected)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Clear", systemImage: "trash.fill")
                        .font(.r(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!isInjected)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
        .confirmationDialog(
            "Clear all mock data?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Mock Data", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will remove all injected food logs, wellness logs, and stress readings. Your real data is not affected.")
        }
    }
}
#endif
```

**Dependencies**: None
**Risk**: Low

#### Step 3.2 — ProfileView integration

<!-- RESOLVED: M4 — Added restart alert after inject/delete -->

**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`

**Action**:
1. Add state variables (inside the existing `#if DEBUG` block, after `mockModeEnabled` and `hasGroqAPIKey`):
```swift
@State private var mockDataInjected: Bool = AppConfig.shared.mockDataInjected
@State private var showMockDataRestartAlert = false
```

2. Add `MockDataDebugCard` below `NutritionSourceDebugCard` (~line 168, inside the existing `#if DEBUG` block):
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

3. Add restart alert (on the `ScrollView` or `NavigationStack`):
```swift
.alert("Mock Data Updated", isPresented: $showMockDataRestartAlert) {
    Button("OK") { }
} message: {
    Text(mockDataInjected
         ? "30 days of mock data injected. Restart the app for HealthKit-backed screens (Burn, Stress) to reflect changes."
         : "Mock data cleared. Restart the app for full cleanup of HealthKit-backed screens.")
}
```

**Why (M4 resolution)**: After inject/delete, already-instantiated VMs hold the old service instance. SwiftData `@Query` views refresh automatically (food logs, wellness logs appear/disappear immediately). But VMs with `@StateObject` (BurnViewModel, StressViewModel via MainTabView) keep their HealthKit service reference until re-created. Restarting the app ensures all VMs init fresh with the correct service. This is acceptable for a developer tool.

**Dependencies**: Steps 1.4, 3.1
**Risk**: Low

---

### Phase 4: Build Verification

#### Step 4.1 — Build main app
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```
Fix any compilation errors.

#### Step 4.2 — Build extension targets
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
1. **Inject flow**: Profile → tap "Inject 30-Day Data" → status shows "Active" → restart app
2. **Home tab**: Wellness rings show non-zero calories, water, exercise, stress. Meal log card shows mock food entries. AI Insight generates from mock data.
3. **Stress tab**: All vitals populated (HR, HRV, BP, RR), sleep and exercise factors filled, stress readings chart shows data
4. **History tab**: WellnessCalendar shows 30 days of colored dots. Day detail shows food logs + wellness metrics.
5. **Navigation to Burn** (from Home exercise ring tap): BurnView shows 30-day active energy + steps charts
6. **Delete flow**: Profile → tap "Clear" → confirmation dialog → "Clear Mock Data" → restart app → all screens show empty/real data only
7. **Real data safety**: Create a real WellnessDayLog for today before injection. After inject → real today log preserved. After clear → real today log still intact.
8. **App restart persistence**: After injecting and restarting, SwiftData records persist. HK-backed VMs re-create MockHealthKitService from persisted `mockDataInjected` flag.

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| WellnessDayLog collision (mock day overlaps real) | Medium | Fetch existing dates before insert; skip conflicts |
| VM holds stale service after inject/delete | Medium | Restart alert tells user to restart; acceptable for dev tool |
| User taps inject twice | Low | Guard clause + button disabled state |
| `logSource="mock"` used for real entries in future | Low | Code comment convention; DEBUG-only tool |
| StressMockSnapshot struct property addition breaks call sites | Low | Only `.default` static let is used; memberwise init is internal |

<!-- RESOLVED: M6 — Verified: BurnView only created from HomeView line 223 -->
<!-- RESOLVED: L1 — Acknowledged: widget mock state out of scope for DEBUG tool -->

## Success Criteria

- [ ] "Inject 30-Day Data" button on Profile populates all screens with data
- [ ] "Clear Mock Data" button removes only injected data, preserving real records
- [ ] Burn screen shows 30-day chart data when mock is active (after restart)
- [ ] Stress screen shows full vitals + readings when mock is active
- [ ] Home rings show non-zero values for all 4 metrics when mock is active
- [ ] Home AI Insight generates successfully with mock data
- [ ] History/WellnessCalendar shows 30 days of entries when mock is active
- [ ] All 4 build targets compile cleanly
- [ ] App restart preserves mock data state
- [ ] No mock infrastructure activates in Release builds
