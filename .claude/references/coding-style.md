# Coding Style — WellPlate

## Immutability

Prefer structs (value types) over classes. Use classes only for SwiftData `@Model` types and `ObservableObject` ViewModels. Never mutate shared state — create new values instead.

## File Organization

- 200-400 lines typical, 800 max
- Organize by feature/domain under `Features + UI/`
- One type per file (exceptions: small related enums, extensions in the same domain)
- All files under `WellPlate/` are auto-included in the build (`PBXFileSystemSynchronizedRootGroup`) — no pbxproj edits needed

```
WellPlate/
├── App/                    # Entry point, RootView
├── Core/
│   ├── AppConfig.swift     # Debug toggles, API config
│   ├── WPLogger.swift      # Logging channels
│   └── Services/           # HealthKit, Nutrition, Speech, etc.
├── Features + UI/
│   └── FeatureName/
│       ├── ViewModels/     # @MainActor ObservableObject classes
│       ├── Views/          # SwiftUI views
│       └── Components/     # Feature-scoped reusable views
├── Models/                 # SwiftData @Model classes + domain enums
├── Networking/
│   ├── Real/               # Groq LLM API client
│   └── Mock/               # MockAPIClient + registry + loader
└── Shared/
    ├── Color/              # AppColors, AppOpacity, appShadow
    ├── Components/         # App-wide reusable views
    └── Extensions/         # Font, text, normalization helpers
```

## Function Size

- Keep functions under 50 lines
- Extract helper functions for readability
- Use early returns (`guard`) to flatten nesting
- Maximum 4 levels of nesting

## Error Handling

Use typed error enums that conform to `LocalizedError`:

```swift
enum APIError: Error {
    case invalidURL, invalidResponse, noData
    case decodingError(Error)
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)
}
```

In ViewModels, surface errors via `@Published var errorMessage: String?` and `@Published var showError = false`. Use `defer { isLoading = false }` to guarantee cleanup:

```swift
func loadData() async {
    isLoading = true
    defer { isLoading = false }

    do {
        let result = try await service.fetchData()
        self.data = result
    } catch {
        errorMessage = error.localizedDescription
        showError = true
    }
}
```

For non-critical fetches, use `try?` with a fallback:

```swift
let logs = (try? modelContext.fetch(descriptor)) ?? []
```

## Input Validation

Validate user input at system boundaries (text fields, API responses). Use `guard` with early return:

```swift
let rawInput = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
guard !rawInput.isEmpty else {
    showErrorMessage("Please enter a food description")
    return
}
```

## Naming Conventions

- **Types**: PascalCase (`StressViewModel`, `FoodLogEntry`)
- **Protocols**: PascalCase + `Protocol` suffix (`HealthKitServiceProtocol`, `NutritionProvider`)
- **Properties/Methods**: camelCase (`isLoading`, `fetchSteps()`)
- **Constants**: lowerCamelCase (`let maxRetries = 3`)
- **Files**: PascalCase, matching the primary type (`StressViewModel.swift`)
- **Booleans**: `is/has/should` prefix (`isAuthorized`, `hasValidData`)
- **Sheet enums**: `FeatureName + Sheet` (`StressSheet`, `HomeSheet`)
- **UserDefaults keys**: Nested `Keys` enum with dot-separated strings

```swift
private enum Keys {
    static let mockMode = "app.networking.mockMode"
    static let apiTimeout = "app.networking.apiTimeout"
}
```

## ViewModel Pattern

ViewModels use `@MainActor` + `ObservableObject` + `@Published`. Constructor injection with protocol types and convenience defaults:

```swift
@MainActor
final class StressViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let healthService: HealthKitServiceProtocol
    private let modelContext: ModelContext

    init(
        healthService: HealthKitServiceProtocol = HealthKitService(),
        modelContext: ModelContext
    ) {
        self.healthService = healthService
        self.modelContext = modelContext
    }

    func loadData() async { ... }
}
```

**Late binding** for `ModelContext` when `@StateObject` requires a zero-arg init:

```swift
@MainActor
init() {
    self.nutritionService = NutritionService()
}

func bindContext(_ context: ModelContext) {
    self.modelContext = context
}
```

## Dependency Injection

Decouple through protocols. Constructor injection with defaults for production convenience:

| Layer | DI Mechanism | Example |
|-------|-------------|---------|
| ViewModels | Constructor injection (protocol) | `init(service: HealthKitServiceProtocol = HealthKitService())` |
| Services | Constructor injection (protocol) | `init(liveProvider: NutritionProvider, mockProvider: NutritionProvider)` |
| Views | `@StateObject` / `@EnvironmentObject` | `@StateObject private var viewModel = HomeViewModel()` |
| App Entry | Composition root | `ModelContainer` setup in `WellPlateApp.swift` |

**Protocol naming**: `[TypeName]Protocol` for DI abstractions (e.g., `HealthKitServiceProtocol`), capability-based names for domain contracts (e.g., `NutritionProvider`).

**Where DI does NOT apply**: Pure value types, static utilities, extensions, `@State` view-local state.

### Factory Pattern for Networking

```swift
enum APIClientFactory {
    static var shared: APIClientProtocol {
        AppConfig.shared.mockMode ? MockAPIClient.shared : APIClient.shared
    }
}
```

## `@MainActor` Discipline

- Apply `@MainActor` at the **class level** on all ViewModels and UI-bound services
- Never apply `@MainActor` to pure computation structs or data models
- Tasks spawned inside a `@MainActor` type inherit isolation — no redundant `await MainActor.run {}`

```swift
// WRONG: redundant MainActor.run inside @MainActor class
@MainActor final class MyViewModel: ObservableObject {
    func load() {
        Task {
            await MainActor.run { self.data = result }  // already on MainActor
        }
    }
}

// CORRECT: direct assignment
@MainActor final class MyViewModel: ObservableObject {
    func load() {
        Task {
            self.data = result
        }
    }
}
```

## Async Concurrency

Use `async let` with private helper methods for parallel fetches:

```swift
async let stepsResult = fetchStepsSafely(for: range)
async let sleepResult = fetchSleepSafely(for: range)
async let hrResult = fetchHRSafely(for: range)

stepsHistory = await stepsResult
sleepHistory = await sleepResult
heartRateHistory = await hrResult
```

**Safety wrappers** — return nil on failure instead of throwing:

```swift
private func fetchStepsSafely(for range: DateInterval) async -> Double? {
    guard let samples = try? await healthService.fetchSteps(for: range) else {
        return nil
    }
    return samples.map(\.value).reduce(0, +)
}
```

## UI Conventions

### Typography (SF Pro Rounded)

Use the `.r()` font extension — never call `.system()` directly for text:

```swift
Text("Title").font(.r(.title3, .semibold))
Text("Body").font(.r(.subheadline, .regular))
Text("123").font(.r(34, .bold)).monospacedDigit()
```

Semantic roles (defined in `Font.swift`):
- `.metric` — big KPI numbers (34pt bold)
- `.title` — screen titles (title2 semibold)
- `.section` — section headers (title3 semibold)
- `.row` — card titles (headline semibold)
- `.sub` — secondary text (subheadline regular)
- `.hint` — placeholders (callout regular)
- `.cap` — metadata (caption regular)
- `.tiny` — small metadata (caption2 medium)
- `.btn` — button labels (headline semibold)
- `.chip` — pills/badges (subheadline semibold)
- `.tab` — tab bar labels (caption semibold)

### Colors (`AppColors`)

```swift
AppColors.brand          // primary brand green
AppColors.primary        // alias for brand
AppColors.primaryContainer  // soft green background
AppColors.onPrimary      // text/icons on primary
AppColors.cream          // warm background (#FFF9E6)
AppColors.surface        // card backgrounds
AppColors.borderSubtle   // subtle border color
AppColors.textPrimary    // main text
AppColors.textSecondary  // secondary text
AppColors.success / .warning / .error  // status colors
```

### Shadows

```swift
.appShadow(radius: 8, y: 2)    // subtle card shadow
.appShadow(radius: 15, y: 5)   // prominent card shadow
```

### Card Pattern

```swift
RoundedRectangle(cornerRadius: 20)
    .fill(Color(.systemBackground))
    .appShadow(radius: 15, y: 5)
```

### Disabled State

```swift
.appDisabled(isLoading)  // dims to 0.38 opacity + disables interaction
```

## Navigation

### Enum-based Sheets (one `.sheet(item:)` per view)

```swift
enum StressSheet: Identifiable {
    case exercise, sleep, diet, screenTimeDetail
    case vital(VitalMetric)
    case stressLab, interventions, fasting, circadian

    var id: String {
        switch self {
        case .exercise: "exercise"
        case .vital(let m): "vital_\(m.id)"
        ...
        }
    }
}

@State private var activeSheet: StressSheet?

.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .exercise: ExerciseDetailView()
    ...
    }
}
```

Never add multiple `.sheet()` modifiers to the same view — use a single enum.

### Tab Navigation

`MainTabView` uses `TabView(selection:)` with the iOS 18+ `Tab` API. Pass `$selectedTab` binding to children for programmatic tab switching.

## Logging

Use `WPLogger` channels — never use `print()` in production code:

```swift
WPLogger.app.info("Bootstrap complete")
WPLogger.network.debug("Request sent to \(url)")
WPLogger.stress.warning("Missing HRV data for range")
WPLogger.nutrition.error("Provider failed: \(error)")
```

Available channels: `app`, `network`, `nutrition`, `barcode`, `home`, `stress`, `healthKit`, `ui`, `speech`.

For structured output, use `.block()`:

```swift
WPLogger.network.block(emoji: "📤", title: "REQUEST", id: reqId, lines: [
    "URL: \(url)",
    "Method: POST"
])
```

All logging is `#if DEBUG` guarded — zero cost in release builds.

## SwiftData

Models use `@Model` with optional `@Attribute(.unique)`:

```swift
@Model
final class StressReading {
    @Attribute(.unique) var id: UUID?
    var timestamp: Date
    var score: Double
    var levelLabel: String
    var source: String = "auto"

    init(timestamp: Date = .now, score: Double, levelLabel: String, source: String = "auto") { ... }
}
```

Fetch with `FetchDescriptor` + `#Predicate`:

```swift
let descriptor = FetchDescriptor<FoodLogEntry>(
    predicate: #Predicate<FoodLogEntry> { $0.day == today },
    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
)
let logs = (try? modelContext.fetch(descriptor)) ?? []
```

Access `ModelContext` via `@Environment(\.modelContext)` in views, pass to ViewModels via init or `bindContext()`.

## Code Quality Checklist

Before marking work complete:
- [ ] Code is readable and well-named
- [ ] Functions are small (<50 lines)
- [ ] Files are focused (<800 lines)
- [ ] No deep nesting (>4 levels)
- [ ] Proper error handling
- [ ] No `print()` statements (use `WPLogger.channel`)
- [ ] No hardcoded values
- [ ] Dependencies injected via protocols
- [ ] New services have a corresponding protocol
- [ ] Sheet navigation uses single enum pattern
- [ ] Fonts use `.r()` extension, not `.system()` directly
- [ ] Colors use `AppColors`, shadows use `.appShadow()`
