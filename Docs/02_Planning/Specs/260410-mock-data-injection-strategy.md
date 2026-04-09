# Strategy: Mock Data Injection System

**Date**: 2026-04-10
**Source**: [Brainstorm](../../01_Brainstorming/260410-mock-data-injection-brainstorm.md)
**Status**: Ready for Planning

## Chosen Approach

**Hybrid: SwiftData Injection (UUID-tracked) + Extended MockHealthKitService swap via `HealthKitServiceFactory`**

Inject real SwiftData records (`FoodLogEntry`, `WellnessDayLog`, `StressReading`) into the persistent store, tracking injected IDs in UserDefaults for safe cleanup. For HealthKit data, extend the existing `MockHealthKitService` (already has 30-day data via `StressMockSnapshot`) and route all ViewModels through a `HealthKitServiceFactory` that swaps real/mock based on a new `AppConfig.mockDataInjected` flag. Profile gets inject/delete buttons in a new DEBUG card.

## Rationale

- **Why not separate ModelContainer (Approach 2 from brainstorm)**: Swapping `@Environment(\.modelContext)` at runtime would require a view-tree rebuild and is fragile with SwiftUI. Rejected.
- **Why not pure in-memory overlay (Approach 3)**: Data doesn't survive app restart, making demo/testing unreliable. Rejected.
- **Why not direct HK writes (Approach 4)**: Requires HK write entitlements on real device, Simulator-only limitation. Rejected.
- **Why this hybrid works**:
  - The existing `HealthKitServiceProtocol` seam + `MockHealthKitService` are already fully implemented. `StressMockSnapshot.default` has comprehensive 30-day data for all vitals, sleep, steps, energy, daylight, HR, HRV, BP, respiratory rate.
  - All 4 affected ViewModels (`StressViewModel`, `BurnViewModel`, `SleepViewModel`, `WellnessCalendarViewModel`) already accept `HealthKitServiceProtocol` via init. The only gap is that their views create them with the default `HealthKitService()`.
  - SwiftData injection is straightforward — create records, save, track IDs. No schema change needed.
  - `StressView` already demonstrates the `usesMockData` + `HealthKitService.isAvailable` bypass pattern — just replicate to Burn, Sleep, Home.

## Affected Files & Components

### New Files

| File | Purpose |
|------|---------|
| `WellPlate/Core/Services/MockDataInjector.swift` | Service: generates & injects 30-day SwiftData records, tracks IDs, handles deletion |
| `WellPlate/Core/Services/HealthKitServiceFactory.swift` | Factory: returns `MockHealthKitService` or `HealthKitService()` based on `AppConfig.mockDataInjected` |
| `WellPlate/Features + UI/Tab/Components/MockDataDebugCard.swift` | Profile UI: inject/delete buttons with status |

### Modified Files

| File | Change |
|------|--------|
| `WellPlate/Core/AppConfig.swift` | Add `mockDataInjected: Bool` + `mockDataIDs` (tracked UUIDs) keys |
| `WellPlate/Features + UI/Tab/MainTabView.swift` | Use `HealthKitServiceFactory` for StressView VM creation; pass factory to BurnView/SleepView |
| `WellPlate/Features + UI/Burn/Views/BurnView.swift` | Accept `HealthKitServiceProtocol` param instead of creating default `BurnViewModel()` |
| `WellPlate/Features + UI/Sleep/Views/SleepView.swift` | Accept `HealthKitServiceProtocol` param instead of creating default `SleepViewModel()` |
| `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift` | Replace `HealthKitService.isAvailable` guard with protocol-aware check |
| `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift` | Replace `HealthKitService.isAvailable` guard with protocol-aware check |
| `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift` | Replace `HealthKitService.isAvailable` guard with protocol-aware check |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | Replace direct `HealthKitService()` creation (lines 730, 736) with factory; bypass `isAvailable` guard |
| `WellPlate/Features + UI/Tab/ProfileView.swift` | Add `MockDataDebugCard` below existing `NutritionSourceDebugCard` |
| `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` | Add missing mock data: water history, exercise minutes history (currently return empty) |

### Unchanged but Verified

| File | Why |
|------|-----|
| `StressViewModel.swift` | Already accepts `HealthKitServiceProtocol`; already handles `usesMockData` pattern |
| `StressView.swift` | Already demonstrates the `isAvailable || usesMockData` pattern we'll replicate |
| `MockHealthKitService.swift` | Already fully implements protocol; just needs `StressMockSnapshot` to have more data |

## Architectural Direction

### 1. HealthKitServiceFactory

```swift
enum HealthKitServiceFactory {
    static func make() -> HealthKitServiceProtocol {
        #if DEBUG
        if AppConfig.shared.mockDataInjected {
            return MockHealthKitService(snapshot: .default)
        }
        #endif
        return HealthKitService()
    }
}
```

All VM creation sites switch from `HealthKitService()` to `HealthKitServiceFactory.make()`.

### 2. `isAvailable` Guard Pattern

The existing `guard HealthKitService.isAvailable else { return }` in ViewModels blocks mock data on Simulator. Two approaches:

- **Option A**: Add a protocol property `var isHealthDataAvailable: Bool` and check that instead of the static.
- **Option B** (simpler): Add a helper `static var shouldFetchData: Bool` in a factory extension that returns `true` if mock-injected.

**Choice: Option B** — minimal changes, no protocol change needed.

```swift
extension HealthKitServiceFactory {
    static var isDataAvailable: Bool {
        #if DEBUG
        if AppConfig.shared.mockDataInjected { return true }
        #endif
        return HealthKitService.isAvailable
    }
}
```

Replace all `HealthKitService.isAvailable` calls with `HealthKitServiceFactory.isDataAvailable`.

### 3. MockDataInjector

```swift
final class MockDataInjector {
    static func inject(into context: ModelContext)    // creates records, saves IDs
    static func deleteAll(from context: ModelContext)  // fetches by tracked IDs, deletes
    static var isInjected: Bool { AppConfig.shared.mockDataInjected }
}
```

**Data generated** (30 days):
- `FoodLogEntry` — 2-3 meals/day with varied macros (breakfast, lunch, dinner, snacks)
- `WellnessDayLog` — mood, water, exercise, calories, steps, stress level, coffee
- `StressReading` — 3-5 readings/day with realistic intraday patterns

**ID tracking**: Store array of UUID strings in `UserDefaults` under key `app.mock.injectedIDs`. On delete, fetch by predicate, bulk-delete, clear the key.

### 4. Profile UI

A `MockDataDebugCard` (#if DEBUG) shows:
- Status badge: "Mock data active" or "No mock data"
- "Inject Mock Data" button (disabled when already injected)
- "Clear Mock Data" button (disabled when not injected)
- Inject action: calls `MockDataInjector.inject()`, sets `AppConfig.mockDataInjected = true`
- Clear action: calls `MockDataInjector.deleteAll()`, sets `AppConfig.mockDataInjected = false`

Placed below the existing `NutritionSourceDebugCard` in ProfileView.

## Design Constraints

1. **All new files gated behind `#if DEBUG`** — no mock infrastructure in Release builds
2. **No SwiftData schema changes** — UUID tracking lives in UserDefaults, not model columns
3. **Follow StressView's existing pattern** for `usesMockData` / `isAvailable` bypass
4. **Use `HealthKitServiceFactory`** everywhere — never create `HealthKitService()` directly in Views
5. **Mock data uses realistic ranges** matching what `StressMockSnapshot.default` already provides for consistency
6. **The `mockMode` flag (API mock) and `mockDataInjected` flag (data mock) are independent** — user can toggle either independently
7. **FoodLogEntry mock data includes `logSource: "mock"`** for additional identifiability

## Non-Goals

- **HealthKit write**: We are NOT writing actual HK samples. The `MockHealthKitService` serves data purely from `StressMockSnapshot`.
- **Widget/Extension support**: Mock data flag is app-only. Extensions continue to read real HealthKit data.
- **Release mode mock**: No App Store demo mode. This is DEBUG-only.
- **Editable mock data**: Users cannot modify individual mock records. It's all-or-nothing inject/delete.
- **ScreenTime mock data**: `ScreenTimeManager` uses Device Activity framework, not HealthKit. Out of scope.

## Open Risks

1. **View refresh on inject/delete**: After injecting or deleting SwiftData records, views using `@Query` will auto-refresh. But HealthKit-backed views (Burn, Sleep) need the HealthKit service to be swapped — this requires either re-creating the VM or the VM detecting the flag change.
   - **Mitigation**: Use `NotificationCenter` post after inject/delete; VMs observe and re-fetch.
2. **HomeView direct HK usage** (lines 730, 736): `HealthKitService()` created inline for mood write. Mock mode should skip this entirely.
   - **Mitigation**: Guard mood-write behind `HealthKitServiceFactory.isDataAvailable && !AppConfig.shared.mockDataInjected`.
3. **Duplicate injection**: User taps inject twice → double records.
   - **Mitigation**: Button disabled when `mockDataInjected` is true; `inject()` checks flag before proceeding.
