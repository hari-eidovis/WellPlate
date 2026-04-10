# Testing — WellPlate

## Current State

Tests live in `WellPlateTests/` with 4 test files covering nutrition services and speech transcription. Test infrastructure exists but is not yet wired into a dedicated test scheme — tests run through the main `WellPlate` scheme's Test action with auto-created test plans.

**Build verification** is the primary gate: `xcodebuild build` must pass. Automated test coverage is supplementary and growing.

## Test Location

All test files live under `WellPlateTests/`. Never create a separate `Tests/` directory at the project root.

```
WellPlateTests/
├── MealLogViewModelTranscriptionTests.swift
├── NutritionServiceTests.swift
├── GeminiNutritionProviderTests.swift
└── MockNutritionProviderTests.swift
```

Current layout is flat. Place new test files directly in `WellPlateTests/`.

**Classification**:
- Pure logic, no simulator needed → Unit test
- Requires HealthKit/SwiftData/network → Integration test (can still run on simulator)
- Drives UI via XCUITest → UI test

## Test Patterns (from existing codebase)

### Mock Services via Protocols

Implement the service protocol with configurable behavior and call tracking:

```swift
@MainActor
private final class MockSpeechTranscriptionService: SpeechTranscriptionServiceProtocol {
    var mockHasPermission: Bool = true
    var shouldThrowOnPermissions: Bool = false
    private(set) var requestPermissionsCalled = false

    func requestPermissions() async throws {
        requestPermissionsCalled = true
        if shouldThrowOnPermissions {
            throw SpeechTranscriptionError.permissionDenied
        }
    }
}
```

### Stub Providers for Simple Cases

When you only need a fixed return value, use a lightweight stub:

```swift
private final class StubProvider: NutritionProvider {
    let output: NutritionalInfo
    init(output: NutritionalInfo) { self.output = output }

    func analyze(_ request: NutritionAnalysisRequest) async throws -> NutritionalInfo {
        output
    }
}

private final class ThrowingProvider: NutritionProvider {
    let error: Error
    init(error: Error) { self.error = error }

    func analyze(_ request: NutritionAnalysisRequest) async throws -> NutritionalInfo {
        throw error
    }
}
```

### ViewModel Tests

Inject mocks via constructor, use `async setUp/tearDown`, test state transitions:

```swift
@MainActor
final class MealLogViewModelTranscriptionTests: XCTestCase {
    private var mock: MockSpeechTranscriptionService!
    private var viewModel: MealLogViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mock = MockSpeechTranscriptionService()
        viewModel = MealLogViewModel(homeViewModel: nil, speechService: mock)
    }

    override func tearDown() async throws {
        mock = nil
        viewModel = nil
        try await super.tearDown()
    }

    func test_startMealTranscription_setsIsTranscribing() async throws {
        viewModel.startMealTranscription()
        await Task.yield()
        XCTAssertTrue(viewModel.isTranscribing)
    }
}
```

### UserDefaults Cleanup

Tests that toggle `AppConfig` flags via UserDefaults must clean up in `tearDown`:

```swift
override func tearDown() {
    super.tearDown()
    UserDefaults.standard.removeObject(forKey: "app.networking.mockMode")
}
```

### Async Test Yielding

When testing code that spawns internal `Task {}` blocks, use `await Task.yield()` to let the task execute before asserting:

```swift
viewModel.startMealTranscription()
await Task.yield()
XCTAssertTrue(viewModel.isTranscribing)
```

For tasks with multiple async hops, yield multiple times:

```swift
viewModel.startMealTranscription()
await Task.yield()
await Task.yield()  // extra yield for nested async calls
XCTAssertTrue(viewModel.showTranscriptionPermissionAlert)
```

## Build & Test Commands

**Deployment target**: iOS 18.6

```bash
# Build verification (primary gate)
xcodebuild -project WellPlate.xcodeproj \
  -scheme WellPlate \
  -destination 'generic/platform=iOS Simulator' \
  build

# Run tests
xcodebuild test -project WellPlate.xcodeproj \
  -scheme WellPlate \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -parallel-testing-enabled YES -quiet 2>&1 \
  | grep -E "error:|warning:|TEST SUCCEEDED|TEST FAILED|Executed|BUILD"
```

## What to Test

**Priority order** (highest value first):

1. **Service logic** — provider selection, fallback behavior, error mapping (e.g., `NutritionService` mock/live switching, 429 fallback)
2. **ViewModel state transitions** — loading states, error display, data binding (e.g., transcription start/stop, permission denial flows)
3. **Domain model computed properties** — stress score calculations, date helpers, nutrient aggregation
4. **Edge cases** — empty input, whitespace-only strings, nil coalescing paths

**Lower priority** (defer until coverage is mature):
- SwiftUI view layout (use previews instead)
- HealthKit data fetching (requires entitlements + simulator support)
- SwiftData persistence (requires ModelContainer setup in tests)

## Writing New Tests

1. **Identify the protocol** — if the dependency doesn't have a protocol yet, create one before writing the test
2. **Write a mock/stub** — implement the protocol with configurable behavior
3. **Inject via constructor** — use the ViewModel/service's existing DI init parameter
4. **Test behavior, not implementation** — assert on published state changes, not internal method calls
5. **One logical assertion per test** — name tests descriptively: `test_actionName_expectedOutcome`

## Test Naming Convention

```
test_[action]_[condition]_[expectedResult]
```

Examples from the codebase:
- `test_startMealTranscription_setsIsTranscribing`
- `test_onFinal_appendsToExistingText`
- `test_permissionDenied_showsPermissionAlert`
- `testAnalyzeFoodFallsBackToMockWhenLiveProviderReturns429`

## Mock Data Infrastructure

The app has a full mock layer for development and testing:

- `MockAPIClient` — returns bundled JSON with configurable delay
- `MockResponseRegistry` — maps URL patterns to fixture files
- `MockDataLoader` — decodes JSON from `Resources/MockData/`
- `MockHealthKitService` — returns synthetic HealthKit data
- `MockNutritionProvider` — keyword-based food matching

Toggle mock mode: `AppConfig.shared.mockMode` (backed by UserDefaults key `app.networking.mockMode`).

For tests, inject mocks directly via constructor — don't rely on `AppConfig.shared.mockMode` unless testing the toggle behavior itself.

## Best Practices

- Mock external dependencies via protocols — every service should have a protocol
- Use `@MainActor` on test classes that test `@MainActor` ViewModels
- Clean up UserDefaults/global state in `tearDown`
- Keep tests fast — mock all network and HealthKit calls
- If a class is hard to test, it needs a protocol + constructor injection
- Prefer stub providers (fixed output) over full mocks (configurable behavior) when the test only needs a return value
