# 

Implementation Plan: Configuration-Based API System for WellPlate

**Version**: 2.0 (Audited & Fixed)

**Date**: 2026-02-16

**Status**: ✅ Ready for Implementation

**Estimated Time**: 20-24 hours over 7-10 days

---

## Context

The WellPlate iOS app currently has a basic networking layer (`APIClient.swift`) but lacks configuration management and mock support. To enable efficient development without backend dependencies and support multiple environments (dev/staging/production), we need to implement a configuration-driven system where:

- **Mock Mode ON** → Returns instant on-device mock data (no network calls)
- **Mock Mode OFF** → Makes real API calls via URLSession
- Configuration controls environment (dev/staging/prod), timeouts, logging, and mock mode
- ViewModels remain agnostic to mock vs real implementations (clean architecture)

This change is necessary because:

1. Backend APIs may not be ready during feature development
2. UI testing requires predictable, instant responses
3. Different environments need different base URLs
4. Unit tests need mockable dependencies

The implementation follows the Repository pattern documented in `Docs/Architecture/MVVM-GUIDE.md` and uses protocol-based dependency injection for testability.

---

## Architecture Overview

```
WellPlateApp → DependencyContainer → Repositories → APIClient/MockAPIClient
                      ↓
              @EnvironmentObject
                      ↓
                   Views → ViewModels (inject repositories)
```

**Key Principle**: ViewModels depend on `RepositoryProtocol`, not concrete implementations. DependencyContainer decides which implementation (real or mock) based on `AppConfig.mockMode`.

---

## Critical Files

### New Files to Create

1. **`Core/Config/AppConfig.swift`**

   - Struct with `environment: Environment`, `mockMode: Bool`, `enableLogging: Bool`, `apiTimeout: TimeInterval`, `mockResponseDelay: TimeInterval`
   - Computed property `baseURL: String` based on environment
   - Factory methods: `loadFromFile()`, `development(mockMode:)`, `staging(mockMode:)`, `production()`
   - Loads from `Resources/Config.plist` with fallback to defaults
1. **`Core/Config/Environment.swift`**

   - Enum: `development`, `staging`, `production`
   - Each case returns appropriate `baseURL` (e.g., "https://dev-api.wellplate.com")
1. **`Resources/Config.plist`**

   - Dictionary with keys: `environment` (String), `mockMode` (Boolean), `enableLogging` (Boolean), `apiTimeout` (Number), `mockResponseDelay` (Number)
   - Example: `environment=development, mockMode=true`
   - Should be `.gitignore`d to avoid committing sensitive production values
1. **`Networking/APIClientProtocol.swift`**

   - Protocol defining: `request<T: Decodable>()`, `get<T>()`, `post<T>()`, `put<T>()`, `delete<T>()`
   - Enables swapping real vs mock implementations
1. **`Networking/Mock/MockAPIClient.swift`**

   - Conforms to `APIClientProtocol`
   - Returns instant mock data from `MockData` files
   - Simulates network delay (configurable via `AppConfig.mockResponseDelay`)
   - Logs requests if `config.enableLogging == true`
1. **`Networking/Mock/MockData/NutritionMockData.swift`**

   - Static structs with sample `NutritionalInfo` responses
   - Example: `sampleResponse`, `highProteinResponse`, `lowCarbResponse`
   - Codable structs matching API response format
1. **`Core/DependencyContainer.swift`**

   - `ObservableObject` holding `@Published var config: AppConfig`
   - Property `apiClient: APIClientProtocol` (creates `MockAPIClient` or `APIClient` based on `config.mockMode`)
   - Factory methods: `makeNutritionRepository()`, `makeFoodScannerViewModel()`
   - Method: `toggleMockMode()` to switch at runtime
1. **`Core/Repositories/Protocols/NutritionRepositoryProtocol.swift`**

   - Protocol: `func analyzeFood(image: UIImage) async throws -> NutritionalInfo`
   - Protocol: `func getFoodHistory() async throws -> [NutritionalInfo]`
1. **`Core/Repositories/NutritionRepository.swift`**

   - Conforms to `NutritionRepositoryProtocol`
   - Holds `apiClient: APIClientProtocol` and `config: AppConfig` (injected via init)
   - Implements methods by calling `apiClient.post()` with `config.baseURL + path`
   - Maps API responses to `NutritionalInfo` models
1. **`Core/Repositories/Mock/MockNutritionRepository.swift`**

   - Conforms to `NutritionRepositoryProtocol`
   - Returns hardcoded `NutritionalInfo` objects instantly
   - Simulates delay: `try await Task.sleep(nanoseconds: 800_000_000)`
   - Logs to console if `config.enableLogging == true`
1. **`Features/Debug/DebugMenuView.swift`** (optional but recommended)

   - SwiftUI view with `Toggle("Mock Mode")` bound to `container.config.mockMode`
   - `Picker("Environment")` to switch between dev/staging/prod
   - Shows current `baseURL`, `mockMode`, `enableLogging`
   - Only available in `#if DEBUG` builds

### Files to Modify

12. **`Networking/APIClient.swift`**

    - Add `extension APIClient: APIClientProtocol` (existing methods already match)
    - Add private property `private let config: AppConfig`
    - Change `static let shared = APIClient()` to `static let shared = APIClient(config: .development())`
    - Add public init: `init(config: AppConfig)` (uses `config.apiTimeout`, `config.enableLogging`)
    - Update `request()` method to log if `config.enableLogging == true`
13. **`App/WellPlateApp.swift`**

    - Add `@StateObject private var container: DependencyContainer`
    - In `init()`: Load config via `AppConfig.loadFromFile()` or use `AppConfig.development(mockMode: true)` for debug builds
    - Create `DependencyContainer(config: config)`
    - Pass to views: `.environmentObject(container)`
14. **`Shared/Models/NutritionalInfo.swift`**

    - Add `extension NutritionalInfo: Decodable` with `CodingKeys` and `init(from decoder:)`
    - Ensures model can be decoded from JSON (needed for repository implementations)

---

## Implementation Steps

### Phase 1: Configuration Foundation (Day 1-2)

**⚠️ IMPORTANT: Xcode Project Integration**

After creating each new Swift file:

1. Drag file from Finder into appropriate Xcode group in Project Navigator
2. Check "Add to targets: WellPlate" checkbox
3. Click "Finish"

Alternatively, create files directly in Xcode:

1. Right-click group in Project Navigator → New File → Swift File
2. Name file and save to appropriate directory

---

1. **Create directory structure**

   - `mkdir -p Core/Config`
   - `mkdir -p Core/Repositories/Protocols`
   - `mkdir -p Core/Repositories/Mock`
   - `mkdir -p Networking/Mock/MockData`
   - `mkdir -p Features/Debug`
1. **Create `Core/Config/Environment.swift`**

   - Define `enum Environment: String, Codable` with cases: `development`, `staging`, `production`
   - Add computed property `baseURL: String` returning appropriate URL per case
1. **Create `Core/Config/AppConfig.swift`**

   - Define `struct AppConfig` with properties: `environment`, `mockMode`, `enableLogging`, `apiTimeout`, `mockResponseDelay`
   - Add computed property `baseURL` delegating to `environment.baseURL`
   - Add `init()` with default values: `mockResponseDelay: TimeInterval = 0.8`
   - Implement `static func loadFromFile() -> AppConfig` (loads from `Config.plist`, falls back to defaults)
   - Add factory methods: `development(mockMode:)`, `staging(mockMode:)`, `production()`
1. **Create `Resources/Config.plist`**

   - Add XML plist with keys: `environment`, `mockMode`, `enableLogging`, `apiTimeout`, `mockResponseDelay`
   - Set defaults: `environment=development, mockMode=true, enableLogging=true, apiTimeout=30, mockResponseDelay=0.8`
   - Add `Config.plist` to `.gitignore` in project root at `/Users/hariom/Desktop/WellPlate/.gitignore`
   - If `.gitignore` doesn't exist, create it with:

     ```
     # Configuration files with sensitive values
     WellPlate/Resources/Config.plist

     # Build files
     *.xcuserstate
     *.xcuserdatad/
     ```

**Verification**: Run app, check that `AppConfig.loadFromFile()` returns expected values. Log config on app launch.

---

### Phase 2: Protocol-Based Network Layer (Day 3-4)

5. **Create `Networking/APIClientProtocol.swift`**

   - Define protocol with method signatures matching existing `APIClient` methods
   - Include: `request<T>()`, `get<T>()`, `post<T>()`, `put<T>()`, `delete<T>()`
6. **Modify `Networking/APIClient.swift`**

   - First, verify existing method signatures match `APIClientProtocol`:
       - Check parameter names match exactly
       - Check default parameter values are compatible
       - Adjust signatures if needed for protocol conformance
   - Add `private let config: AppConfig` property
   - Add new `init(config: AppConfig)` and use `config.apiTimeout` for `URLSessionConfiguration`
   - Update `static let shared` to `APIClient(config: .development())`
   - Add `extension APIClient: APIClientProtocol` (if signatures match)
   - Add logging in `request()` method: `if config.enableLogging { print("[API] \(method) \(url)") }`
7. **Create `Networking/Mock/MockData/NutritionMockData.swift`**

   - Define `struct NutritionMockData` with static properties
   - Example: `static let sampleResponse = NutritionalInfo(calories: 320, protein: 25.5, ...)`
   - Add 3-5 different mock scenarios (low-calorie, high-protein, vegetarian, etc.)
8. **Create `Networking/Mock/MockAPIClient.swift`**

   - Conform to `APIClientProtocol`
   - Add `private let config: AppConfig` and `init(config:)`
   - Implement `request()` to simulate delay: `try await Task.sleep(nanoseconds: UInt64(config.mockResponseDelay * 1_000_000_000))`
   - Return mock data from `NutritionMockData` based on URL path pattern matching
   - Log if `config.enableLogging == true`: `print("[MockAPI] \(method) \(path) → returning mock data")`

**Verification**: Create test `APIClient(config: .development(mockMode: false))` and `MockAPIClient(config: .development(mockMode: true))`, call `get()` methods, verify real makes network call and mock returns instantly.

---

### Phase 3: Repository Layer (Day 5-6)

9. **Update `Shared/Models/NutritionalInfo.swift`**

   - Keep existing struct definition with custom `init()` unchanged
   - Add `Decodable` conformance in separate extension below:

   ```swift
   // Existing struct - DO NOT MODIFY
   struct NutritionalInfo {
       let calories: Int
       // ... existing properties and init
   }

   // NEW: Decodable conformance
   extension NutritionalInfo: Decodable {
       enum CodingKeys: String, CodingKey {
           case calories, protein, carbs, fat, fiber
       }

       init(from decoder: Decoder) throws {
           let container = try decoder.container(keyedBy: CodingKeys.self)
           self.calories = try container.decode(Int.self, forKey: .calories)
           self.protein = try container.decode(Double.self, forKey: .protein)
           self.carbs = try container.decode(Double.self, forKey: .carbs)
           self.fat = try container.decode(Double.self, forKey: .fat)
           self.fiber = try container.decodeIfPresent(Double.self, forKey: .fiber) ?? 0
       }
   }
   ```
10. **Create `Core/Repositories/Protocols/NutritionRepositoryProtocol.swift`**

    - Define protocol with methods: `analyzeFood(image: UIImage) async throws -> NutritionalInfo`
    - Add method: `getFoodHistory() async throws -> [NutritionalInfo]`
11. **Create `Core/Repositories/NutritionRepository.swift`**

    - Add properties: `private let apiClient: APIClientProtocol`, `private let config: AppConfig`
    - Init: `init(apiClient: APIClientProtocol, config: AppConfig)`
    - Implement `analyzeFood()`: Convert image to JPEG data, call `apiClient.post(url: "\(config.baseURL)/api/nutrition/analyze", body: imageData)`, decode response to `NutritionalInfo`
    - Implement `getFoodHistory()`: Call `apiClient.get(url: "\(config.baseURL)/api/nutrition/history")`, return array
12. **Create `Core/Repositories/Mock/MockNutritionRepository.swift`**

    - Conform to `NutritionRepositoryProtocol`
    - Add `private let config: AppConfig` and `init(config:)`
    - Implement `analyzeFood()`: Sleep using `config.mockResponseDelay` to simulate network, return `NutritionMockData.sampleResponse`, log if enabled
    - Implement `getFoodHistory()`: Sleep 0.5s, return array of 3-5 mock items

**Verification**: Create instances of both repositories, call methods, verify mock returns instantly and real would make network calls (or throws if backend not ready).

---

### Phase 4: Dependency Injection Container (Day 7)

13. **Create `Core/DependencyContainer.swift`**

    - Define `class DependencyContainer: ObservableObject`
    - Add `@Published private(set) var config: AppConfig`
    - Add property: `private var apiClient: APIClientProtocol` (NOT lazy - will be recreated)
    - In `init(config: AppConfig)`: Initialize `apiClient` based on `config.mockMode`
    - Add factory method: `func makeNutritionRepository() -> NutritionRepositoryProtocol` (returns mock or real based on `config.mockMode`)
    - Add convenience: `func makeFoodScannerViewModel() -> FoodScannerViewModel` (creates repository, injects into ViewModel)
    - Add method: `func updateConfig(_ newConfig: AppConfig)` that:
        - Sets `self.config = newConfig`
        - Recreates `apiClient` (important: lazy won't reinitialize)
    - Add method: `func toggleMockMode()` (creates new config with flipped `mockMode`, calls `updateConfig()`)

**Verification**: Create container with `mockMode=true`, call `makeNutritionRepository()`, verify it returns `MockNutritionRepository`. Toggle mode, verify it returns `NutritionRepository`.

---

### Phase 5: App Integration (Day 8)

14. **Modify `App/WellPlateApp.swift`**

    - Add `@StateObject private var container: DependencyContainer`
    - In `init()`:

      ```swift
      #if DEBUG
      let config = AppConfig.development(mockMode: true)
      #else
      let config = AppConfig.loadFromFile()
      #endif
      _container = StateObject(wrappedValue: DependencyContainer(config: config))
      ```
    - Update `body`:

      ```swift
      ContentView()
          .environmentObject(container)
      ```
15. **Create example ViewModel**: `Features/FoodScanner/ViewModels/FoodScannerViewModel.swift`

    - Add imports: `import Foundation`, `import SwiftUI`, `import UIKit`
    - Add `@MainActor` decorator to class
    - Add `@Published var capturedImage: UIImage?`, `@Published var nutritionalInfo: NutritionalInfo?`, `@Published var isAnalyzing = false`
    - Add `@Published var errorMessage = ""`, `@Published var showError = false`
    - Add `private let repository: NutritionRepositoryProtocol`
    - Init: `init(repository: NutritionRepositoryProtocol)`
    - Implement `func analyzeFood()`:

      ```swift
      guard let image = capturedImage else {
          errorMessage = "Please capture an image first"
          showError = true
          return
      }

      isAnalyzing = true
      Task {
          do {
              let info = try await repository.analyzeFood(image: image)
              await MainActor.run {
                  self.nutritionalInfo = info
                  self.isAnalyzing = false
              }
          } catch {
              await MainActor.run {
                  self.isAnalyzing = false
                  self.errorMessage = error.localizedDescription
                  self.showError = true
              }
          }
      }
      ```
16. **Create example Views**: Two-view factory pattern

    **A. Container/Router View**: `Features/FoodScanner/Views/FoodScannerContainerView.swift`

    ```swift
    import SwiftUI

    struct FoodScannerContainerView: View {
        @EnvironmentObject var container: DependencyContainer

        var body: some View {
            FoodScannerView(viewModel: container.makeFoodScannerViewModel())
        }
    }
    ```

    **B. Actual View**: `Features/FoodScanner/Views/FoodScannerView.swift`

    ```swift
    import SwiftUI

    struct FoodScannerView: View {
        @ObservedObject var viewModel: FoodScannerViewModel  // NOT @StateObject

        var body: some View {
            VStack {
                if viewModel.isAnalyzing {
                    ProgressView("Analyzing food...")
                } else if let info = viewModel.nutritionalInfo {
                    nutritionResults(info: info)
                } else {
                    Button("Scan Food") {
                        viewModel.analyzeFood()
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { viewModel.showError = false }
            } message: {
                Text(viewModel.errorMessage)
            }
        }

        private func nutritionResults(info: NutritionalInfo) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Calories: \(info.calories)")
                Text("Protein: \(String(format: "%.1f", info.protein))g")
                Text("Carbs: \(String(format: "%.1f", info.carbs))g")
                Text("Fat: \(String(format: "%.1f", info.fat))g")
            }
        }
    }
    ```

    **Why this pattern?** `@EnvironmentObject` is not available in View's `init()`, so we use a container view that has access to the environment and passes the ViewModel as a regular parameter.

**Verification**: Run app, tap scan button, verify:

- With `mockMode=true`: Instant results (~0.8s delay), no network call
- With `mockMode=false`: Real network call (or error if backend unavailable)

---

### Phase 6: Debug Menu (Day 9 - Optional)

17. **Create `Features/Debug/DebugMenuView.swift`**

    - Add `@EnvironmentObject var container: DependencyContainer`
    - Add `Toggle("Mock Mode")` bound to `Binding(get: { container.config.mockMode }, set: { _ in container.toggleMockMode() })`
    - Add `Picker("Environment")` to switch between dev/staging/prod
    - Display current `baseURL`, `mockMode`, `enableLogging` in read-only labels
    - Wrap entire view in `#if DEBUG ... #endif`
18. **Add debug menu button to app**

    - In `ContentView.swift`, add toolbar item: `ToolbarItem { Button { showDebugMenu.toggle() } label: { Image(systemName: "wrench") } }`
    - Show `DebugMenuView()` in sheet when `showDebugMenu == true`

**Verification**: Tap debug button, toggle mock mode, verify ViewModel calls return different data (mock vs real). Change environment, verify base URL updates.

---

### Phase 7: Testing & Documentation (Day 10)

19a. **Create Test Target** (prerequisite)

- Open Xcode project
- File → New → Target → Unit Testing Bundle
- Name: `WellPlateTests`
- Language: Swift
- Project: WellPlate
- Target to be tested: WellPlate
- Click "Finish"
- Delete auto-generated `WellPlateTests.swift` placeholder
- Create directory structure: `Tests/ViewModels/`, `Tests/Repositories/`

19. **Write unit test example**: `Tests/ViewModels/FoodScannerViewModelTests.swift`

    - Create test: `testAnalyzeFoodSuccess()`
    - Setup: `let mockRepo = MockNutritionRepository(config: .development(mockMode: true))`
    - Create ViewModel: `let vm = FoodScannerViewModel(repository: mockRepo)`
    - Call: `vm.analyzeFood()`, wait for completion
    - Assert: `XCTAssertNotNil(vm.nutritionalInfo)`
20. **Update documentation**

    - Add section to `Docs/Architecture/MVVM-GUIDE.md` explaining config system
    - Document how to add new repositories (copy pattern from `NutritionRepository`)
    - Document how to add mock data (add to `MockData` files)
    - Create quick start guide: "How to toggle mock mode", "How to add new environment"

**Verification**: Run unit tests with `cmd+U`, verify all pass. Read documentation, ensure clarity.

---

## Testing Strategy

### End-to-End Verification

1. **Launch app with mock mode enabled**

   - Set `Config.plist` → `mockMode=true`
   - Launch app, navigate to FoodScanner
   - Tap "Scan Food" button
   - **Expected**: Results appear in ~0.8 seconds, console shows `[MockAPI]` logs, no network activity in Network Inspector
1. **Launch app with mock mode disabled**

   - Set `Config.plist` → `mockMode=false`
   - Launch app, navigate to FoodScanner
   - Tap "Scan Food" button
   - **Expected**: Network call visible in Xcode Network Inspector, console shows `[API]` logs, real response (or error if backend unavailable)
1. **Toggle mock mode at runtime**

   - Launch app, open Debug Menu (tap wrench icon)
   - Toggle "Mock Mode" switch
   - Go back to FoodScanner, tap "Scan Food"
   - **Expected**: First tap uses initial mode, after toggle uses opposite mode
1. **Switch environments**

   - Open Debug Menu, change environment from "Development" to "Staging"
   - Verify base URL updates in UI (shown in debug menu)
   - Make API call, verify request goes to staging URL (check Network Inspector)
1. **Unit tests**

   - Run `cmd+U` to execute all tests
   - Verify `FoodScannerViewModelTests` passes with mock repository
   - Verify ViewModel receives expected mock data

---

## Trade-offs & Design Decisions

### Decision 1: Injected Config vs Singleton

**Chosen**: Injected via `DependencyContainer`

**Rationale**: Better testability, runtime switching support, no global mutable state

**Trade-off**: Slightly more verbose (need `@EnvironmentObject`), but worth it for flexibility

### Decision 2: Two-Level Mocking (APIClient + Repository)

**Chosen**: Mock both `APIClient` and `Repository` layers

**Rationale**: Repository mocks are faster (no JSON encoding), more control over returned data

**Trade-off**: More files to maintain, but cleaner separation of concerns

### Decision 3: Config File Location

**Chosen**: `Resources/Config.plist` loaded at runtime

**Rationale**: Can change config without recompiling, supports CI/CD workflows

**Trade-off**: Need to handle missing file gracefully (fallback to defaults)

### Decision 4: Dependency Injection Pattern

**Chosen**: Factory methods in `DependencyContainer`

**Rationale**: Centralized DI logic, easy to understand, supports `@EnvironmentObject`

**Trade-off**: Slight coupling to container, but acceptable for app-level DI

---

## Success Criteria

✅ Mock mode returns instant data (<1s) without network calls

✅ Real mode makes actual URLSession requests

✅ Config can be toggled at runtime via debug menu

✅ ViewModels are testable with mock repositories

✅ Multiple environments supported (dev/staging/prod)

✅ Logging can be enabled/disabled via config

✅ No breaking changes to existing `APIClient` usage

✅ Unit tests pass for ViewModels with mock dependencies

---

## Common Pitfalls to Avoid

1. **@StateObject with @EnvironmentObject**:

   - ❌ Can't access `@EnvironmentObject` in View's `init()`
   - ✅ Use factory view pattern (ContainerView + ActualView)
1. **Lazy properties don't reinitialize**:

   - ❌ `lazy var apiClient` won't update when config changes
   - ✅ Use manual recreation in `updateConfig()`
1. **Forgetting to add files to Xcode**:

   - ❌ Creating files in Finder doesn't add to project
   - ✅ Drag into Xcode or create files via Xcode directly
1. **Missing test target**:

   - ❌ Can't write tests without target
   - ✅ Create Unit Testing Bundle target first (Phase 7a)
1. **Config.plist in version control**:

   - ❌ Committing with production keys is security risk
   - ✅ Add to `.gitignore` immediately

---

## Rollback Strategy

If implementation encounters blocking issues:

**Phase 1-2 Issues**:

- Delete new Config files
- Revert `APIClient.swift` to original
- Impact: Zero (no dependencies yet)

**Phase 3-4 Issues**:

- Keep config system (it's useful standalone)
- Remove repository layer
- Use `APIClient` directly in ViewModels
- Impact: Lose mock/real abstraction but config works

**Phase 5+ Issues**:

- Disable `DependencyContainer` in WellPlateApp
- Fall back to `APIClient.shared` singleton
- Keep repository layer for future
- Impact: No runtime switching but architecture intact

**Recovery Time**: 30-60 minutes per phase

---

## Time Estimates

| Phase     | Description                    | Estimated Hours |
| --------- | ------------------------------ | --------------- |
| 1         | Configuration Foundation       | 2-3 hours       |
| 2         | Protocol-Based Network Layer   | 3-4 hours       |
| 3         | Repository Layer               | 4-5 hours       |
| 4         | Dependency Injection Container | 2-3 hours       |
| 5         | App Integration                | 3-4 hours       |
| 6         | Debug Menu (Optional)          | 1-2 hours       |
| 7         | Testing & Documentation        | 2-3 hours       |
| **Total** | **All Phases**                 | **20-24 hours** |

**Suggested Schedule**: 2-3 hours/day over 7-10 days

---

## Future Enhancements

- Add feature flags to `AppConfig` (enable/disable features remotely)
- Network condition simulation (slow 3G, offline mode)
- Mock response randomization (test edge cases)
- Integration with CI/CD (load config from environment variables)
- Analytics tracking (log API call patterns in mock vs real mode)
- Automatic mock data generation from OpenAPI spec

---

**Plan Status**: ✅ Audited and Ready for Implementation

**Audit Report**: See `/Users/hariom/Desktop/WellPlate/WellPlate/Docs/Audit/config-api-system-audit.md` for detailed audit findings

**Next Step**: Begin Phase 1 - Configuration Foundation