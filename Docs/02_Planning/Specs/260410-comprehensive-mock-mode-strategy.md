# Strategy: Comprehensive Mock Mode Toggle

**Date**: 2026-04-10
**Source**: [Brainstorm](../../01_Brainstorming/260410-comprehensive-mock-mode-brainstorm.md)
**Prior work**: [Mock Data Injection Strategy](260410-mock-data-injection-strategy.md) (partially implemented)
**Status**: Ready for Planning

## Chosen Approach

**Unified Mock Mode: Single Flag + HealthKitServiceFactory + Expanded MockDataInjector + Real InsightEngine Pipeline**

Merge the existing `mockMode` (API) and `mockDataInjected` (data) flags into a single `mockMode` toggle. Introduce a `HealthKitServiceFactory` (mirroring the existing `APIClientFactory` pattern) so all ViewModels get the correct HealthKit service from one place. Expand `MockDataInjector` to cover all SwiftData model types (`SymptomEntry`, `FastingSession`, `AdherenceLog`, `JournalEntry`). Remove `InsightEngine`'s hard-coded `mockInsights()` shortcut so it runs its real detection pipeline (trends, correlations, milestones, imbalances, sleep quality, reinforcements) against mock data — producing dynamic, realistic insights.

This is Approach 4 from the brainstorm. It builds on the partial implementation from the prior mock data injection work.

## Rationale

- **Why not keep two flags**: Users expect one toggle. The current split creates confusion — some features respond to `mockMode`, others to `mockDataInjected`, some to both, and SleepView/InsightEngine respond to neither. A single flag is the only way to guarantee consistent behaviour.
- **Why factory over scattered checks**: The current codebase has 6+ places doing `if AppConfig.shared.mockDataInjected { MockHealthKitService(...) } else { HealthKitService() }`. A factory centralises this, matches the existing `APIClientFactory` pattern, and means new ViewModels get mock support automatically.
- **Why run InsightEngine's real pipeline**: The current `mockInsights()` returns 6 hard-coded cards that never change. This doesn't test the insight detection logic and gives a misleading demo experience. Running the real pipeline against mock SwiftData + MockHealthKitService data produces dynamic insights that actually exercise the code paths.
- **Why expand MockDataInjector**: `InsightEngine.buildWellnessContext()` queries `SymptomEntry`, `FastingSession`, `AdherenceLog`, `JournalEntry`. Without mock records for these, the engine's multi-domain gate may fail or produce thin insights.

## Affected Files & Components

### New File

| File | Purpose |
|---|---|
| `WellPlate/Core/Services/HealthKitServiceFactory.swift` | `enum HealthKitServiceFactory` — cached singleton (like `APIClientFactory`). Returns `MockHealthKitService(snapshot: .default)` when `mockMode` is on, `HealthKitService()` otherwise. Includes `isDataAvailable` static helper. |

### Modified Files

| File | Change |
|---|---|
| `WellPlate/Core/AppConfig.swift` | Remove `mockDataInjected` and `mockInjectedWellnessLogDates` properties. The `mockMode` flag now implies both API mocking AND data injection. Add `mockInjectedModelIDs` (replaces `mockInjectedWellnessLogDates`) to track all injected SwiftData record IDs for cleanup. |
| `WellPlate/Core/Services/MockDataInjector.swift` | (1) Change injection guard from `mockDataInjected` → `mockMode`. (2) Add injection methods for `SymptomEntry`, `FastingSession`, `AdherenceLog`, `JournalEntry`. (3) Update `deleteAll` to handle all new model types. (4) Tag new records with identifiable markers for cleanup. |
| `WellPlate/Core/Services/InsightEngine.swift` | (1) Change default init to use `HealthKitServiceFactory.shared` instead of `HealthKitService()`. (2) Remove the `if AppConfig.shared.mockMode { mockInsights() }` shortcut at line 56 — let the real pipeline run. (3) Keep `mockInsights()` as a private fallback only if SwiftData has zero records (empty state). |
| `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift` | Change default init from `HealthKitService()` → `HealthKitServiceFactory.shared`. |
| `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift` | Remove inline `if AppConfig.shared.mockDataInjected` check. Change default init to use `HealthKitServiceFactory.shared`. Remove `HealthKitServiceFactory.isDataAvailable` → `isAvailable` swap in `loadData()`. |
| `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift` | Remove inline `if AppConfig.shared.mockDataInjected` check. Change default init to use `HealthKitServiceFactory.shared`. |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | Already accepts protocol via init. Change default parameter from `HealthKitService()` → `HealthKitServiceFactory.shared`. |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | (1) Replace `HealthKitService()` at line 716 with `HealthKitServiceFactory.shared`. (2) Replace `HealthKitService()` at line 742 (mood write) with factory. (3) Replace `AppConfig.shared.mockDataInjected` checks with `AppConfig.shared.mockMode`. |
| `WellPlate/Features + UI/Home/Views/InsightsHubView.swift` | Replace `InsightEngine()` at line 167 — ensure it uses factory (happens automatically once `InsightEngine.init` default changes). |
| `WellPlate/Features + UI/Home/Views/InsightDetailSheet.swift` | Same as above — `InsightEngine()` at line 151 gets factory by default. |
| `WellPlate/Features + UI/Tab/MainTabView.swift` | Remove inline `MockHealthKitService(snapshot:)` creation. Use `HealthKitServiceFactory.shared` instead. Replace `AppConfig.shared.mockDataInjected` with `AppConfig.shared.mockMode`. |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | Remove inline `MockHealthKitService(snapshot:)` creation. StressViewModel now gets the correct service from factory by default. |
| `WellPlate/Features + UI/Burn/Views/BurnView.swift` | Replace `AppConfig.shared.mockDataInjected` with `AppConfig.shared.mockMode` in the `isAvailable` guard. |
| `WellPlate/Features + UI/Tab/ProfileView.swift` | (1) Remove `mockDataInjected` state and `MockDataDebugCard` (inject/delete buttons). (2) Update the mock mode toggle to also inject/delete SwiftData records when toggled. (3) Single `NutritionSourceDebugCard`-style card with one toggle that controls everything. (4) Show restart alert after toggle. |

### Unchanged but Verified

| File | Why |
|---|---|
| `MockHealthKitService.swift` | Already fully implements `HealthKitServiceProtocol`. No changes needed — factory routes to it. |
| `StressMockSnapshot.swift` | Already has comprehensive 30-day data. No changes needed. |
| `APIClientFactory.swift` | Already checks `mockMode` for API layer. No changes — just benefits from the unified flag. |

## Architectural Direction

### 1. HealthKitServiceFactory (New — mirrors APIClientFactory)

```swift
enum HealthKitServiceFactory {
    private static let _shared: HealthKitServiceProtocol = {
        if AppConfig.shared.mockMode {
            return MockHealthKitService(snapshot: .default)
        }
        return HealthKitService()
    }()

    static var shared: HealthKitServiceProtocol { _shared }

    static var isDataAvailable: Bool {
        if AppConfig.shared.mockMode { return true }
        return HealthKitService.isAvailable
    }
}
```

All ViewModel default inits change: `init(healthService: HealthKitServiceProtocol = HealthKitServiceFactory.shared)`.

### 2. Unified Flag Semantics

When `AppConfig.shared.mockMode == true`:
- `APIClientFactory.shared` → `MockAPIClient` (already works)
- `HealthKitServiceFactory.shared` → `MockHealthKitService` (new)
- SwiftData contains mock records (injected on toggle-on)
- `InsightEngine` runs real pipeline against mock SwiftData + MockHealthKitService data

When `AppConfig.shared.mockMode == false`:
- Everything is real. No mock data, no mock services.

### 3. InsightEngine Pipeline Change

**Before** (current):
```swift
func generateInsights() async {
    if AppConfig.shared.mockMode {
        insightCards = mockInsights()  // 6 hard-coded cards, skips everything
        return
    }
    // ... real pipeline
}
```

**After**:
```swift
func generateInsights() async {
    // Real pipeline always runs — mock data comes from SwiftData + MockHealthKitService
    guard let context = await buildWellnessContext() else {
        // Fallback: if no SwiftData records at all, use canned cards
        if AppConfig.shared.mockMode {
            insightCards = mockInsights()
            dailyInsight = insightCards.first
        } else {
            insufficientData = true
        }
        return
    }
    // ... detect trends, correlations, milestones, etc. — same as today
}
```

### 4. MockDataInjector Expansion

New injection methods (following existing patterns):

| Model | Tag Strategy | Data Shape (30 days) |
|---|---|---|
| `SymptomEntry` | Tracked via stored UUIDs | 2-3 symptoms per week, severity 2-8, categories: digestive, pain, energy, cognitive |
| `FastingSession` | Tracked via stored UUIDs | 10-15 completed sessions (16:8 schedule), spread across 30 days |
| `AdherenceLog` | Tracked via stored UUIDs | Daily supplement logs (2 supplements, morning/evening), mix of "taken"/"skipped" |
| `JournalEntry` | Tracked via stored dates (unique per day) | 10-15 entries across 30 days, varied text + mood + stress snapshots |

Deletion: fetch by tracked IDs/dates, bulk delete, clear tracking arrays.

### 5. Profile UI Change

**Before**: Two separate controls:
1. "Use Mock Nutrition" toggle → sets `mockMode`
2. "Inject Mock Data" / "Clear Mock Data" buttons → sets `mockDataInjected`

**After**: Single control:
1. "Mock Mode" toggle → on toggle-on: sets `mockMode` + injects SwiftData. On toggle-off: clears `mockMode` + deletes mock SwiftData. Shows restart alert either way.

## Design Constraints

1. **Single flag**: `AppConfig.shared.mockMode` is the ONLY mock flag. Remove `mockDataInjected` entirely.
2. **Factory pattern**: Never create `HealthKitService()` directly in Views or ViewModels. Always go through `HealthKitServiceFactory.shared`.
3. **Cached singleton**: Factory evaluates once on first access (like `APIClientFactory`). Toggle requires app restart.
4. **DEBUG only**: `HealthKitServiceFactory` returns `HealthKitService()` unconditionally in Release builds. `MockDataInjector` is `#if DEBUG` gated.
5. **Real pipeline**: `InsightEngine` must NOT shortcut to `mockInsights()` when mock mode is on. The canned insights are fallback-only for when SwiftData is empty.
6. **Tag all mock records**: Every injected SwiftData record must be identifiable for cleanup (via `logSource: "mock"`, `source: "mock"`, or tracked UUID arrays).
7. **No schema changes**: All tracking metadata lives in `UserDefaults`, not SwiftData model columns.

## Non-Goals

- **Hot-swap without restart**: The factory caches on first access. Users restart after toggling. This is a DEBUG-only developer tool — restart is acceptable.
- **Widget/extension support**: Mock mode is app-only. Extensions continue to use real data.
- **ScreenTime mock data**: `ScreenTimeManager` uses DeviceActivity framework, not a protocol. Out of scope.
- **Release build mock mode**: No App Store demo mode. `#if DEBUG` only.
- **Editable mock data**: All-or-nothing inject/delete. No per-record editing.

## Open Risks

1. **Mixed real + mock data in InsightEngine**: When mock mode is on and user already has real SwiftData records, InsightEngine will aggregate both. This could produce confusing insights mixing real and mock data.
   - **Mitigation**: Accept as-is for V1 — it's a DEBUG tool. Could add a `logSource` filter in V2.
2. **JournalEntry unique constraint**: `JournalEntry` has `@Attribute(.unique) var day`. Injecting mock entries for days that already have real entries will fail/replace.
   - **Mitigation**: Check for existing entries before injecting; skip days with existing real entries.
3. **Foundation Models latency**: With mock data providing 30 days across all domains, `InsightEngine` will detect more insights and make more Foundation Models calls for narrative generation.
   - **Mitigation**: The engine's existing prioritization + batch prompting handles this. Template fallback available for iOS < 26.
4. **Stale `mockDataInjected` in UserDefaults**: After removing the property, old keys may linger harmlessly. No migration needed — they're just ignored.
