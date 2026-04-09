# Implementation Plan: Stress View Mock Mode Data

## Overview
When `AppConfig.shared.mockMode` is enabled in `DEBUG`, the Stress tab should render a fully populated mock experience instead of trying to read live HealthKit and Screen Time data. The implementation should inject a stress-specific mock data source at view-model construction time, bypass live authorization and platform gating in mock mode, and keep fake stress data out of the user's real persisted wellness history unless explicitly required later.

## Inputs
- User request: "make a plan to feed the mock data in stress view when mock mode is on"
- Brainstorm artifact: none; workflow skipped and plan derived from repository context

## Impacted Targets
- `WellPlate`

## Impacted Files
- `WellPlate/Core/AppConfig.swift` - existing mock-mode source of truth; reused by Stress tab injection
- `WellPlate/Features + UI/Tab/MainTabView.swift` - choose live vs mock StressViewModel at tab construction
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` - add a mock-data mode and stop assuming all data comes from live services
- `WellPlate/Features + UI/Stress/Views/StressView.swift` - bypass HealthKit unavailable/permission flow when using mock data and remove direct screen-time singleton dependencies from UI-only paths
- `WellPlate/Features + UI/Stress/Views/ScreenTimeDetailView.swift` - stop re-reading `ScreenTimeManager.shared` so the detail sheet matches the injected mock state
- `WellPlate/Core/Services/HealthKitServiceProtocol.swift` - reused by the mock service so the view model can stay service-driven
- `WellPlate/Core/Services/MockHealthKitService.swift` - new live-shape mock service that returns deterministic 30-day stress inputs
- `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` - new mock fixture model/factory holding screen time, charts, vitals, and optional mock food/readings

## Requirements
- Mock mode must affect StressView even though stress data does not use the networking `MockAPIClient`
- StressView must render on simulator / non-HealthKit environments when mock mode is on
- All main Stress tab surfaces must be populated in mock mode:
  - total score
  - factor cards
  - today's pattern chart
  - week chart
  - vitals cards
  - factor detail sheets
- Mock mode must not request HealthKit or Screen Time authorization
- Mock mode must not write fake `StressReading` or `WellnessDayLog` rows into the user's real SwiftData history
- Live mode behavior must remain unchanged when mock mode is off

## Assumptions
- `AppConfig.shared.mockMode` is a `DEBUG`-only **compile-time `let` constant**; it cannot be mutated at runtime and toggling requires a new build. Add a `// ⚠️ Set to false before release` comment at its declaration site.
- The user wants mock stress data isolated to the Stress tab, not propagated into Home/Burn/Sleep unless separately requested
- Source-code fixtures are acceptable for the first version; JSON-backed stress fixtures are optional, not required
- Manual screen-time entry in mock mode can be session-scoped only unless the user asks to edit the fixture
- No UI surface, Profile toggle, launch argument, or test hook may set `mockMode` at runtime; the constant is the sole entry point

## Implementation Steps
1. **Define a stress-specific mock snapshot**
   - Files: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
   - Action: Create a `StressMockSnapshot` type plus a default factory for deterministic sample data. Include fields for:
     - daily steps/energy/sleep inputs used by scoring
     - current screen-time hours and source
     - 30-day histories for steps, energy, sleep, HR, resting HR, HRV, blood pressure, respiratory rate
     - today's and week's `StressReading` arrays for charts
     - current-day food logs for diet detail
   - Why: The Stress tab needs more than a mock API payload; it needs a complete, display-ready state surface for charts and detail sheets.
   - Dependencies: None
   - Risk: Low

2. **Add a HealthKit-shaped mock service**
   - Files: `WellPlate/Core/Services/MockHealthKitService.swift`, `WellPlate/Core/Services/HealthKitServiceProtocol.swift`
   - Action: Implement `MockHealthKitService: HealthKitServiceProtocol` that returns the histories and summaries from `StressMockSnapshot`, reports `isAuthorized = true`, and no-ops authorization requests.
   - Why: `StressViewModel` is already designed around `HealthKitServiceProtocol`; reusing that seam keeps the live scoring code intact and limits branching.
   - Dependencies: Step 1
   - Risk: Low

3. **Introduce an explicit StressViewModel data mode**
   - Files: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
   - Action: Add a small injected mode such as:
     - `.live(healthService: HealthKitServiceProtocol, modelContext: ModelContext)`
     - `.mock(snapshot: StressMockSnapshot, healthService: HealthKitServiceProtocol, modelContext: ModelContext)`
     Also add a simple `usesMockData` computed property.
   - Why: The view model currently mixes live HealthKit, `ScreenTimeManager.shared`, and SwiftData reads/writes. A mode flag makes those decisions explicit and testable.
   - Dependencies: Steps 1-2
   - Risk: Medium

4. **Teach StressViewModel to apply mock state without touching live persistence**
   - Files: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
   - Action: In mock mode:
     - `requestPermissionAndLoad()` should set `isAuthorized = true` and skip HealthKit permission requests
     - `loadData()` should use mock service outputs plus mock snapshot values
     - `refreshDietFactor()` should use mock logs instead of fetching `FoodLogEntry` from `modelContext`
     - `refreshScreenTimeFactor()` should use snapshot screen-time values instead of `ScreenTimeManager.shared`
     - `loadReadings()` should publish mock `todayReadings` / `weekReadings` without querying SwiftData
     - `persistTodayWellnessSnapshot()` and `logCurrentStress()` should be no-ops in mock mode
   - Why: This is the minimum change set that fills the Stress UI while preventing fake data from leaking into real persistence.
   - Dependencies: Step 3
   - Risk: High

5. **Move screen-time display data behind the view model**
   - Files: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`, `WellPlate/Features + UI/Stress/Views/StressView.swift`, `WellPlate/Features + UI/Stress/Views/ScreenTimeDetailView.swift`
   - Action: Add view-model-owned properties for the current screen-time display state, for example:
     - `screenTimeDisplayHours: Double?`
     - `screenTimeAutoDetectedDisplayHours: Double?`
     - existing `screenTimeSource`
     Then update:
     - `ScreenTimeInputSheet(autoDetectedHours:)` call sites to read from the view model, not `ScreenTimeManager.shared`
     - `ScreenTimeDetailView` to accept `currentHours` as an input instead of reading the singleton
   - Why: Mock mode will otherwise break the sheet because `ScreenTimeDetailView` currently re-reads live manager state and will show `—` even when the factor card is mocked.
   - Dependencies: Step 4
   - Risk: Medium

6. **Bypass live availability and authorization gates in StressView**
   - Files: `WellPlate/Features + UI/Stress/Views/StressView.swift`
   - Action: Update the top-level state machine so mock mode is treated as renderable content even when `HealthKitService.isAvailable == false`. In `.task` and refresh paths:
     - skip `ScreenTimeManager.shared.requestAuthorization()`
     - skip `ScreenTimeManager.shared.startMonitoring()`
     - rely on `viewModel.requestPermissionAndLoad()`
   - Why: Without this, mock mode still gets blocked by `HealthKit Unavailable` on simulator and still tries to start live screen-time monitoring.
   - Dependencies: Steps 3-5
   - Risk: Medium

7. **Inject the correct StressViewModel from MainTabView**
   - Files: `WellPlate/Features + UI/Tab/MainTabView.swift`
   - Action: Replace the unconditional `StressViewModel(modelContext: modelContext)` construction with a small factory:
     - when `AppConfig.shared.mockMode == false`, keep the current live model
     - when `true`, inject `MockHealthKitService` and the default `StressMockSnapshot`
   - Why: This keeps mock selection at the composition root, matching how the rest of the app chooses real vs mock behavior.
   - Dependencies: Steps 1-6
   - Risk: Low

8. **Make the preview deterministic**
   - Files: `WellPlate/Features + UI/Stress/Views/StressView.swift`
   - Action: Update the `#Preview` to instantiate `StressViewModel` with the mock snapshot/service.
   - Why: The preview should always render a populated Stress screen without HealthKit or Screen Time dependencies.
   - Dependencies: Step 7
   - Risk: Low

## Testing Strategy
- Required scheme or target builds: `WellPlate`
- Manual verification:
  - Run with `mockMode = true` in `DEBUG` and confirm Stress tab renders populated content on simulator
  - Confirm no HealthKit permission UI appears in mock mode
  - Confirm Screen Time detail sheet and input sheet show values consistent with the mocked factor
  - Rebuild the target with `mockMode = false` (in `AppConfig.swift`) and confirm live Stress behavior still requests permissions and loads real data
  - Confirm entering/leaving Stress tab in mock mode does not create `StressReading` or `WellnessDayLog` rows in persistent storage
- Automated tests, if any:
  - Add `StressViewModel` tests covering live vs mock mode branches if the project's test target is already configured for the shared scheme
  - If not, fall back to build verification plus manual checks because current repo guidance is build-first

## Unresolved Decisions
- [ ] Should mock stress data remain isolated to the Stress tab, or should HomeView wellness rings also reflect the same fake stress state when mock mode is on?
- [ ] Should mock stress fixtures live in Swift source for speed, or be moved into `WellPlate/Resources/MockData/` JSON files for easier iteration by design/product?
- [ ] In mock mode, should manual screen-time edits mutate the session's mock state, or should the mock state remain fixed and read-only?

## Success Criteria
- [ ] Stress tab shows fully populated mock content whenever `AppConfig.shared.mockMode` is `true`
- [ ] Stress tab no longer blocks on `HealthKitService.isAvailable` in mock mode
- [ ] No live HealthKit or Screen Time authorization is requested in mock mode
- [ ] Screen Time detail UI matches the mocked factor state
- [ ] Mock mode does not pollute real SwiftData stress history
- [ ] Live mode remains unchanged when mock mode is `false`
