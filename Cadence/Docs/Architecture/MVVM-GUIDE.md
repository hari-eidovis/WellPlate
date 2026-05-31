# WellPlate MVVM Architecture Guide

**Version:** 1.0

**Last Updated:** February 16, 2026

**Target Audience:** iOS Developers (Junior to Senior)

---

## Table of Contents

1. [What is MVVM?](#1-what-is-mvvm)
2. [WellPlate Project Structure](#2-wellplate-project-structure)
3. [The Three Layers Explained](#3-the-three-layers-explained)
4. [Dependency Injection Explained](#4-dependency-injection-explained)
5. [Repository Pattern](#5-repository-pattern)
6. [Complete Feature Example: FoodScanner](#6-complete-feature-example-foodscanner)
7. [Real-World Examples from WellPlate](#7-real-world-examples-from-wellplate)
8. [Best Practices Checklist](#8-best-practices-checklist)
9. [Testing Your MVVM Architecture](#9-testing-your-mvvm-architecture)
10. [Code Review Checklist](#10-code-review-checklist)
11. [Migration Guide](#11-migration-guide)
12. [Common Pitfalls & Solutions](#12-common-pitfalls--solutions)
13. [Advanced Topics](#13-advanced-topics)
14. [Resources & Further Reading](#14-resources--further-reading)

---

## 1. What is MVVM?

### Definition

**MVVM (Model-View-ViewModel)** is a software architectural pattern that separates an application into three interconnected components:

- **Model:** Pure data structures representing your app's data
- **View:** User interface components that display information
- **ViewModel:** Business logic layer that prepares data for the View

### Why MVVM?

Coming from traditional iOS development with MVC (Model-View-Controller), you might have experienced "Massive View Controllers" where business logic, UI code, and data manipulation all mix together. MVVM solves this by:

1. **Separation of Concerns:** Each layer has a single, clear responsibility
2. **Testability:** ViewModels can be unit tested without UI
3. **Reusability:** ViewModels can be shared across different Views
4. **Maintainability:** Changes in one layer rarely affect others
5. **SwiftUI Compatibility:** MVVM is the natural pattern for SwiftUI's reactive paradigm

### MVVM Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                          USER                                │
└────────────────────────┬────────────────────────────────────┘
                         │ Interactions
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                         VIEW                                 │
│  • SwiftUI Views                                            │
│  • Presentation Logic                                       │
│  • @StateObject / @ObservedObject                           │
│  • NO Business Logic                                        │
└────────────────────────┬────────────────────────────────────┘
                         │ Binds to @Published properties
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                       VIEWMODEL                              │
│  • ObservableObject                                         │
│  • @Published properties                                    │
│  • Business Logic                                           │
│  • State Management                                         │
│  • Calls Repository                                         │
└────────────────────────┬────────────────────────────────────┘
                         │ Requests data
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      REPOSITORY                              │
│  • Data abstraction layer                                   │
│  • Calls API / Database                                     │
│  • Caching logic                                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                         MODEL                                │
│  • Pure data structures                                     │
│  • Codable/Decodable                                        │
│  • NO logic                                                 │
└─────────────────────────────────────────────────────────────┘
```

### MVVM vs MVC vs VIPER

| Pattern   | Complexity | Testability | Best For                                  |
| --------- | ---------- | ----------- | ----------------------------------------- |
| **MVC**   | Low        | Poor        | Simple apps, prototypes                   |
| **MVVM**  | Medium     | Excellent   | Most iOS apps, SwiftUI projects           |
| **VIPER** | High       | Excellent   | Large enterprise apps, complex navigation |

**For WellPlate:** MVVM is ideal because it provides excellent testability and clean separation without the overhead of VIPER's 5 layers.

---

## 2. WellPlate Project Structure

### Directory Layout

```
WellPlate/
├── App/
│   ├── WellPlateApp.swift          # App entry point
│   ├── ContentView.swift            # Root container
│   └── SplashScreenView.swift       # Splash screen
│
├── Features/                        # Feature-based modules
│   ├── FoodScanner/
│   │   ├── ViewModels/
│   │   │   └── FoodScannerViewModel.swift
│   │   └── Views/
│   │       └── FoodScannerView.swift
│   ├── Home/
│   │   ├── ViewModels/
│   │   │   └── HomeViewModel.swift
│   │   └── Views/
│   │       └── HomeView.swift
│   ├── Onboarding/
│   └── Tab/
│
├── Core/                            # Core business logic
│   ├── Repositories/
│   │   └── NutritionRepository.swift
│   └── Services/
│
├── Networking/
│   └── APIClient.swift              # Network layer
│
├── Shared/
│   ├── Models/
│   │   └── NutritionalInfo.swift   # Data models
│   └── Components/
│       ├── CustomProgressView.swift
│       └── LoadingScreenView.swift
│
└── Resources/
    └── Assets.xcassets
```

### Feature-Based Organization

WellPlate uses **feature-based organization** where each feature (FoodScanner, Home, etc.) contains its own ViewModels and Views. This approach:

- **Scales well:** New features don't clutter existing ones
- **Clear ownership:** Each feature is self-contained
- **Easy navigation:** Related files are grouped together

### File Naming Conventions

| Component      | Example                      | Location                           |
| -------------- | ---------------------------- | ---------------------------------- |
| **Model**      | `NutritionalInfo.swift`      | `Shared/Models/`                   |
| **View**       | `FoodScannerView.swift`      | `Features/FoodScanner/Views/`      |
| **ViewModel**  | `FoodScannerViewModel.swift` | `Features/FoodScanner/ViewModels/` |
| **Repository** | `NutritionRepository.swift`  | `Core/Repositories/`               |
| **API Client** | `APIClient.swift`            | `Networking/`                      |

**Naming Rules:**

- Models: Noun (e.g., `User`, `Recipe`, `NutritionalInfo`)
- Views: Noun + "View" (e.g., `FoodScannerView`, `HomeView`)
- ViewModels: Feature + "ViewModel" (e.g., `FoodScannerViewModel`)
- Repositories: Domain + "Repository" (e.g., `NutritionRepository`)

---

## 3. The Three Layers Explained

### 3.1 Models

**Definition:** Pure data structures that represent your application's data.

**Rules:**

1. ✅ Use `struct` (value types) for immutability
2. ✅ Conform to `Codable` for API serialization
3. ✅ Use `let` for immutable properties
4. ❌ NO business logic or calculations
5. ❌ NO UI-related code
6. ❌ NO dependencies on other layers

**Example: Good Model (from WellPlate)**

```swift
// File: Shared/Models/NutritionalInfo.swift

import Foundation

struct NutritionalInfo {
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double

    init(calories: Int, protein: Double, carbs: Double, fat: Double, fiber: Double = 0) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
    }
}
```

**Why This is Correct:**

- ✅ Pure data structure with no logic
- ✅ Immutable (`let` properties)
- ✅ Simple initializer
- ✅ No dependencies on Views or ViewModels

**Example: Bad Model (Anti-pattern)**

```swift
// ❌ WRONG - DON'T DO THIS
struct NutritionalInfo {
    var calories: Int
    var protein: Double

    // ❌ Business logic in Model
    func isHighProtein() -> Bool {
        return protein > 20
    }

    // ❌ UI formatting logic in Model
    var displayText: String {
        return "\(calories) cal"
    }

    // ❌ API call in Model
    func fetchFromServer() async { ... }
}
```

**Why This is Wrong:**

- ❌ Contains business logic (`isHighProtein`)
- ❌ Contains UI formatting (`displayText`)
- ❌ Contains networking logic (`fetchFromServer`)

These belong in the **ViewModel**, not the Model!

---

### 3.2 Views

**Definition:** SwiftUI components responsible for displaying information and capturing user input.

**Responsibilities:**

1. ✅ Display data from ViewModel
2. ✅ Handle user interactions (button taps, gestures)
3. ✅ Define layout and visual styling
4. ✅ Use `@StateObject` to own ViewModels
5. ✅ Use `@ObservedObject` for passed ViewModels

**What Views SHOULD NOT Do:**

1. ❌ NO business logic or calculations
2. ❌ NO direct API calls
3. ❌ NO Timer or DispatchQueue management
4. ❌ NO complex state management (use ViewModel)
5. ❌ NO data transformation logic

**State Management in Views:**

| Property Wrapper     | Use Case                          | Example                                |
| -------------------- | --------------------------------- | -------------------------------------- |
| `@State`             | Simple local UI state             | Toggle switch, text field input        |
| `@StateObject`       | Create and own ViewModel          | Main feature view creates ViewModel    |
| `@ObservedObject`    | Receive ViewModel from parent     | Child view receives parent's ViewModel |
| `@EnvironmentObject` | Share global state                | Theme, user session                    |
| `@Binding`           | Two-way communication with parent | Child modifies parent's state          |

**Example: Good View**

```swift
// ✅ CORRECT
struct FoodScannerView: View {
    @StateObject private var viewModel = FoodScannerViewModel()

    var body: some View {
        VStack {
            if viewModel.isAnalyzing {
                ProgressView("Analyzing food...")
            } else if let nutritionalInfo = viewModel.nutritionalInfo {
                NutritionDetailView(info: nutritionalInfo)
            } else {
                Button("Scan Food") {
                    viewModel.analyzeFood()
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}
```

**Why This is Correct:**

- ✅ Uses `@StateObject` to create ViewModel
- ✅ Only displays data from ViewModel
- ✅ Delegates actions to ViewModel (`analyzeFood()`)
- ✅ No business logic in View

---

### 3.3 ViewModels

**Definition:** The business logic layer that prepares data for Views and handles user actions.

**Responsibilities:**

1. ✅ Conform to `ObservableObject`
2. ✅ Expose `@Published` properties for UI binding
3. ✅ Contain all business logic
4. ✅ Handle API calls through Repositories
5. ✅ Manage state (loading, error, success)
6. ✅ Transform Model data for display
7. ✅ Validate user input

**ViewModel Template:**

```swift
import Foundation
import Combine

class FeatureViewModel: ObservableObject {
    // MARK: - Published Properties (UI State)
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var showError = false

    // MARK: - Private Properties
    private let repository: RepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization (Dependency Injection)
    init(repository: RepositoryProtocol = DefaultRepository()) {
        self.repository = repository
    }

    // MARK: - Public Methods (Called by View)
    func performAction() {
        isLoading = true

        Task {
            do {
                let result = try await repository.fetchData()
                // Process result
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    // MARK: - Lifecycle
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}
```

**Key Points:**

- All UI state uses `@Published` for reactive updates
- Dependencies are injected (Repository)
- Async operations update state on `MainActor`
- Cleanup happens in `deinit`

---

## 4. Dependency Injection Explained

### What is Dependency Injection?

**Simple Definition:** Instead of creating dependencies inside a class, you **pass them in** from outside.

**Why?** It makes your code:

1. **Testable:** You can inject mock dependencies for testing
2. **Flexible:** Easy to swap implementations
3. **Loosely Coupled:** Classes don't depend on concrete implementations

### Without Dependency Injection (❌ Bad)

```swift
// ❌ WRONG - Tight coupling
class FoodScannerViewModel: ObservableObject {
    private let apiClient = APIClient.shared // ❌ Hard-coded dependency

    func analyzeFood() {
        // Can't test this without making real API calls!
        apiClient.post(...)
    }
}
```

**Problems:**

- ❌ Can't unit test without network
- ❌ Hard to change API implementation
- ❌ Tightly coupled to `APIClient`

### With Dependency Injection (✅ Good)

```swift
// ✅ CORRECT - Dependency Injection
protocol NutritionRepositoryProtocol {
    func analyzeFood(image: UIImage) async throws -> NutritionalInfo
}

class FoodScannerViewModel: ObservableObject {
    private let repository: NutritionRepositoryProtocol

    // Inject dependency through initializer
    init(repository: NutritionRepositoryProtocol = NutritionRepository()) {
        self.repository = repository
    }

    func analyzeFood() {
        Task {
            do {
                let info = try await repository.analyzeFood(image: capturedImage)
                // Handle success
            } catch {
                // Handle error
            }
        }
    }
}
```

**Benefits:**

- ✅ Can inject mock repository for testing
- ✅ Easy to swap implementations
- ✅ Loosely coupled to abstraction (protocol)

### How to Use Dependency Injection

#### Step 1: Define a Protocol

```swift
protocol NutritionRepositoryProtocol {
    func analyzeFood(image: UIImage) async throws -> NutritionalInfo
}
```

#### Step 2: Create Implementation

```swift
class NutritionRepository: NutritionRepositoryProtocol {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func analyzeFood(image: UIImage) async throws -> NutritionalInfo {
        // Real API implementation
        let url = URL(string: "https://api.wellplate.com/analyze")!
        return try await apiClient.post(url: url, body: imageData, responseType: NutritionalInfo.self)
    }
}
```

#### Step 3: Create Mock for Testing

```swift
class MockNutritionRepository: NutritionRepositoryProtocol {
    var shouldFail = false
    var mockData: NutritionalInfo?

    func analyzeFood(image: UIImage) async throws -> NutritionalInfo {
        if shouldFail {
            throw APIError.serverError(statusCode: 500, message: "Server error")
        }
        return mockData ?? NutritionalInfo(calories: 250, protein: 20, carbs: 30, fat: 10, fiber: 5)
    }
}
```

#### Step 4: Inject in Production

```swift
// In View
struct FoodScannerView: View {
    @StateObject private var viewModel = FoodScannerViewModel()
    // Uses default NutritionRepository()
}
```

#### Step 5: Inject in Tests

```swift
func testFoodAnalysis() {
    let mockRepo = MockNutritionRepository()
    mockRepo.mockData = NutritionalInfo(calories: 300, protein: 25, carbs: 35, fat: 12, fiber: 6)

    let viewModel = FoodScannerViewModel(repository: mockRepo)
    // Test viewModel with mock data
}
```

---

## 5. Repository Pattern

### What is the Repository Pattern?

**Definition:** An abstraction layer between your ViewModel and data sources (API, Database, Cache).

**Without Repository:**

```
View → ViewModel → APIClient
```

**With Repository:**

```
View → ViewModel → Repository → APIClient
```

### Why Use Repository Pattern?

1. **Abstraction:** ViewModel doesn't know if data comes from API, database, or cache
2. **Testability:** Easy to mock repositories
3. **Flexibility:** Can switch data sources without changing ViewModel
4. **Caching:** Centralized place for caching logic
5. **Offline Support:** Can return cached data when offline

### Repository Implementation

#### Step 1: Create Protocol

```swift
// File: Core/Repositories/NutritionRepositoryProtocol.swift

import UIKit

protocol NutritionRepositoryProtocol {
    func analyzeFood(image: UIImage) async throws -> NutritionalInfo
    func getFoodHistory() async throws -> [NutritionalInfo]
    func saveFoodEntry(_ info: NutritionalInfo) async throws
}
```

#### Step 2: Implement Repository

```swift
// File: Core/Repositories/NutritionRepository.swift

import UIKit

class NutritionRepository: NutritionRepositoryProtocol {
    private let apiClient: APIClient
    private var cache: [NutritionalInfo] = []

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func analyzeFood(image: UIImage) async throws -> NutritionalInfo {
        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw APIError.invalidURL
        }

        // Create request
        let url = URL(string: "https://api.wellplate.com/analyze")!
        let response: NutritionAPIResponse = try await apiClient.post(
            url: url,
            body: imageData,
            responseType: NutritionAPIResponse.self
        )

        // Map API response to Model
        let nutritionalInfo = NutritionalInfo(
            calories: response.calories,
            protein: response.protein,
            carbs: response.carbohydrates,
            fat: response.fat,
            fiber: response.fiber
        )

        // Cache the result
        cache.append(nutritionalInfo)

        return nutritionalInfo
    }

    func getFoodHistory() async throws -> [NutritionalInfo] {
        // Return cached data (or fetch from database)
        return cache
    }

    func saveFoodEntry(_ info: NutritionalInfo) async throws {
        // Save to database or API
        cache.append(info)
    }
}

// API Response Model (separate from domain Model)
struct NutritionAPIResponse: Codable {
    let calories: Int
    let protein: Double
    let carbohydrates: Double
    let fat: Double
    let fiber: Double
}
```

#### Step 3: Use Repository in ViewModel

```swift
class FoodScannerViewModel: ObservableObject {
    @Published var nutritionalInfo: NutritionalInfo?
    @Published var isAnalyzing = false
    @Published var errorMessage = ""
    @Published var showError = false

    private let repository: NutritionRepositoryProtocol

    init(repository: NutritionRepositoryProtocol = NutritionRepository()) {
        self.repository = repository
    }

    func analyzeFood(image: UIImage) {
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
    }
}
```

---

## 6. Complete Feature Example: FoodScanner

Let's build a complete feature following MVVM with Repository pattern.

### Step 1: Model

```swift
// File: Shared/Models/NutritionalInfo.swift

import Foundation

struct NutritionalInfo: Codable, Identifiable {
    let id: UUID
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let timestamp: Date

    init(
        id: UUID = UUID(),
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.timestamp = timestamp
    }
}
```

### Step 2: Repository Protocol

```swift
// File: Core/Repositories/NutritionRepositoryProtocol.swift

import UIKit

protocol NutritionRepositoryProtocol {
    func analyzeFood(image: UIImage) async throws -> NutritionalInfo
}
```

### Step 3: Repository Implementation

```swift
// File: Core/Repositories/NutritionRepository.swift

import UIKit

class NutritionRepository: NutritionRepositoryProtocol {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func analyzeFood(image: UIImage) async throws -> NutritionalInfo {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw APIError.invalidURL
        }

        let url = URL(string: "https://api.wellplate.com/analyze")!

        struct Response: Decodable {
            let calories: Int
            let protein: Double
            let carbohydrates: Double
            let fat: Double
            let fiber: Double
        }

        let response: Response = try await apiClient.post(
            url: url,
            body: imageData,
            responseType: Response.self
        )

        return NutritionalInfo(
            calories: response.calories,
            protein: response.protein,
            carbs: response.carbohydrates,
            fat: response.fat,
            fiber: response.fiber
        )
    }
}
```

### Step 4: ViewModel

```swift
// File: Features/FoodScanner/ViewModels/FoodScannerViewModel.swift

import UIKit
import Combine

class FoodScannerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var capturedImage: UIImage?
    @Published var nutritionalInfo: NutritionalInfo?
    @Published var isAnalyzing = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showImagePicker = false

    // MARK: - Private Properties
    private let repository: NutritionRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(repository: NutritionRepositoryProtocol = NutritionRepository()) {
        self.repository = repository
    }

    // MARK: - Public Methods
    func analyzeFood() {
        guard let image = capturedImage else {
            showError(message: "Please capture an image first")
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
            } catch let error as APIError {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.showError(message: self.errorDescription(for: error))
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.showError(message: "An unexpected error occurred")
                }
            }
        }
    }

    func reset() {
        capturedImage = nil
        nutritionalInfo = nil
        showError = false
        errorMessage = ""
    }

    func openImagePicker() {
        showImagePicker = true
    }

    // MARK: - Private Helpers
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    private func errorDescription(for error: APIError) -> String {
        switch error {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid server response"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Failed to process server response"
        case .serverError(let statusCode, _):
            return "Server error (\(statusCode))"
        case .networkError:
            return "Network connection failed"
        }
    }

    // MARK: - Cleanup
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}
```

### Step 5: View

```swift
// File: Features/FoodScanner/Views/FoodScannerView.swift

import SwiftUI

struct FoodScannerView: View {
    @StateObject private var viewModel = FoodScannerViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let image = viewModel.capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 300)
                        .cornerRadius(12)
                } else {
                    placeholderView
                }

                if viewModel.isAnalyzing {
                    ProgressView("Analyzing food...")
                        .padding()
                } else if let info = viewModel.nutritionalInfo {
                    nutritionResultsView(info: info)
                } else {
                    actionButtonsView
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Food Scanner")
            .sheet(isPresented: $viewModel.showImagePicker) {
                ImagePicker(selectedImage: $viewModel.capturedImage) {
                    viewModel.analyzeFood()
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Subviews

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.2))
            .frame(height: 300)
            .overlay(
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
            )
    }

    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            Button(action: { viewModel.openImagePicker() }) {
                Label("Capture Food", systemImage: "camera")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            if viewModel.capturedImage != nil {
                Button(action: { viewModel.analyzeFood() }) {
                    Label("Analyze", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }

    private func nutritionResultsView(info: NutritionalInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutritional Information")
                .font(.headline)

            NutritionRow(label: "Calories", value: "\(info.calories) kcal")
            NutritionRow(label: "Protein", value: String(format: "%.1f g", info.protein))
            NutritionRow(label: "Carbs", value: String(format: "%.1f g", info.carbs))
            NutritionRow(label: "Fat", value: String(format: "%.1f g", info.fat))
            NutritionRow(label: "Fiber", value: String(format: "%.1f g", info.fiber))

            Button("Reset") {
                viewModel.reset()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(12)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct NutritionRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}
```

### Step 6: Unit Tests

```swift
// File: WellPlateTests/FoodScannerViewModelTests.swift

import XCTest
@testable import WellPlate

class FoodScannerViewModelTests: XCTestCase {
    var viewModel: FoodScannerViewModel!
    var mockRepository: MockNutritionRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockNutritionRepository()
        viewModel = FoodScannerViewModel(repository: mockRepository)
    }

    override func tearDown() {
        viewModel = nil
        mockRepository = nil
        super.tearDown()
    }

    func testAnalyzeFoodSuccess() async {
        // Given
        let testImage = UIImage(systemName: "photo")!
        viewModel.capturedImage = testImage

        let expectedInfo = NutritionalInfo(
            calories: 300,
            protein: 25,
            carbs: 35,
            fat: 12,
            fiber: 6
        )
        mockRepository.mockData = expectedInfo

        // When
        viewModel.analyzeFood()

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Then
        XCTAssertEqual(viewModel.nutritionalInfo?.calories, 300)
        XCTAssertEqual(viewModel.isAnalyzing, false)
        XCTAssertEqual(viewModel.showError, false)
    }

    func testAnalyzeFoodFailure() async {
        // Given
        let testImage = UIImage(systemName: "photo")!
        viewModel.capturedImage = testImage
        mockRepository.shouldFail = true

        // When
        viewModel.analyzeFood()

        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNil(viewModel.nutritionalInfo)
        XCTAssertEqual(viewModel.isAnalyzing, false)
        XCTAssertEqual(viewModel.showError, true)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)
    }

    func testReset() {
        // Given
        viewModel.capturedImage = UIImage(systemName: "photo")
        viewModel.nutritionalInfo = NutritionalInfo(
            calories: 100,
            protein: 10,
            carbs: 20,
            fat: 5
        )

        // When
        viewModel.reset()

        // Then
        XCTAssertNil(viewModel.capturedImage)
        XCTAssertNil(viewModel.nutritionalInfo)
        XCTAssertFalse(viewModel.showError)
        XCTAssertEqual(viewModel.errorMessage, "")
    }
}

// Mock Repository for Testing
class MockNutritionRepository: NutritionRepositoryProtocol {
    var shouldFail = false
    var mockData: NutritionalInfo?

    func analyzeFood(image: UIImage) async throws -> NutritionalInfo {
        if shouldFail {
            throw APIError.serverError(statusCode: 500, message: "Mock error")
        }
        return mockData ?? NutritionalInfo(
            calories: 250,
            protein: 20,
            carbs: 30,
            fat: 10,
            fiber: 5
        )
    }
}
```

---

## 7. Real-World Examples from WellPlate

### Example 1: ❌ WRONG - SplashScreenView (Current Implementation)

**File:** `WellPlate/App/SplashScreenView.swift`

**Problem:** Business logic and timer management in View

```swift
struct SplashScreenView: View {
    @State private var bouncingOffset: [CGFloat] = Array(repeating: 0, count: 7)

    var body: some View {
        // ... UI code ...
    }
    .onAppear {
        startBouncing() // ❌ Timer logic in View
    }

    // ❌ VIOLATION: Business logic in View
    private func startBouncing() {
        for index in 0..<7 {
            let delay = Double(index) * 0.2
            let duration = 1.5 + Double.random(in: -0.2...0.2)

            // ❌ Timer management in View
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                withAnimation(...) {
                    bouncingOffset[index] = CGFloat.random(in: -8...8)
                }
            }
        }
    }
}
```

**Why This is Wrong:**

1. ❌ **Timers in View:** Timer lifecycle isn't properly managed (memory leak risk)
2. ❌ **Business Logic:** Animation calculations belong in ViewModel
3. ❌ **Not Testable:** Can't unit test animation timing logic
4. ❌ **@State Explosion:** Multiple state variables for complex animations
5. ❌ **Hard to Reuse:** Can't reuse this animation logic elsewhere

---

### Example 2: ✅ CORRECT - Refactored SplashScreenView

**Create ViewModel:**

```swift
// File: App/ViewModels/SplashScreenViewModel.swift

import Foundation
import Combine
import SwiftUI

class SplashScreenViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isAnimating = false
    @Published var bouncingOffsets: [CGFloat] = Array(repeating: 0, count: 7)

    // MARK: - Private Properties
    private var timers: [Timer] = []
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public Methods
    func startAnimations() {
        isAnimating = true
        startBouncing()
    }

    func stopAnimations() {
        isAnimating = false
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    // MARK: - Private Methods
    private func startBouncing() {
        for index in 0..<7 {
            let delay = Double(index) * 0.2
            let duration = 1.5 + Double.random(in: -0.2...0.2)

            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    withAnimation(
                        .easeInOut(duration: duration)
                        .repeatForever(autoreverses: true)
                    ) {
                        self.bouncingOffsets[index] = CGFloat.random(in: -8...8)
                    }
                }
            }
            timers.append(timer)
        }
    }

    // MARK: - Cleanup
    deinit {
        stopAnimations()
        cancellables.forEach { $0.cancel() }
    }
}
```

**Refactored View:**

```swift
// File: App/SplashScreenView.swift (Refactored)

import SwiftUI

struct SplashScreenView: View {
    @StateObject private var viewModel = SplashScreenViewModel()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 50) {
                // Title
                titleView

                Spacer()

                // Animated characters
                charactersView
            }
        }
        .onAppear {
            viewModel.startAnimations() // ✅ Delegate to ViewModel
        }
        .onDisappear {
            viewModel.stopAnimations() // ✅ Proper cleanup
        }
    }

    // MARK: - Subviews

    private var titleView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                Text("Well")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                Text("Plate")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
            }
            .opacity(viewModel.isAnimating ? 1 : 0)
        }
    }

    private var charactersView: some View {
        GeometryReader { geometry in
            ForEach(0..<7, id: \.self) { index in
                characterView(imageName: characterNames[index], index: index)
                    .position(characterPosition(index: index, width: geometry.size.width))
                    .offset(y: viewModel.bouncingOffsets[index]) // ✅ Use ViewModel state
            }
        }
    }

    private func characterView(imageName: String, index: Int) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
            .opacity(viewModel.isAnimating ? 1 : 0)
    }

    // MARK: - Helpers

    private let characterNames = ["Group 11", "Today", "Group 18", "Group 10", "Group 16", "Group 17", "Group 9"]

    private func characterPosition(index: Int, width: CGFloat) -> CGPoint {
        // Position calculation logic
        return CGPoint(x: width * 0.5, y: 100)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.12) : .white
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.2, green: 0.2, blue: 0.2)
    }

    private var accentColor: Color {
        Color(red: 1.0, green: 0.45, blue: 0.25)
    }
}
```

**Benefits of Refactored Version:**

1. ✅ **Separation of Concerns:** Animation logic in ViewModel, UI in View
2. ✅ **Testable:** Can unit test animation timing
3. ✅ **Memory Safe:** Timers properly cleaned up in `deinit`
4. ✅ **Reusable:** ViewModel can be used by different Views
5. ✅ **Maintainable:** Clear responsibilities

---

### Example 3: ✅ CORRECT - NutritionalInfo Model

**File:** `WellPlate/Shared/Models/NutritionalInfo.swift`

```swift
import Foundation

struct NutritionalInfo {
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double

    init(calories: Int, protein: Double, carbs: Double, fat: Double, fiber: Double = 0) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
    }
}
```

**Why This is Correct:**

- ✅ Pure data structure
- ✅ No business logic
- ✅ Immutable (`let` properties)
- ✅ Simple initializer with default value
- ✅ Perfect example of MVVM Model layer

---

### Example 4: ✅ CORRECT - APIClient

**File:** `WellPlate/Networking/APIClient.swift`

The existing APIClient is well-structured:

```swift
class APIClient {
    static let shared = APIClient()

    private init() { ... } // ✅ Singleton pattern

    func request<T: Decodable>(...) async throws -> T {
        // ✅ Generic async/await implementation
        // ✅ Proper error handling
        // ✅ Clean separation of concerns
    }
}
```

**Best Practices Demonstrated:**

- ✅ Singleton with private init
- ✅ Generic method with Decodable
- ✅ Async/await for modern Swift
- ✅ Comprehensive error handling with custom `APIError` enum
- ✅ Timeout configuration

**Next Step:** Add Repository layer to abstract APIClient from ViewModels.

---

## 8. Best Practices Checklist

### ✅ DO These Things

#### Models

- ✅ Use `struct` for value semantics
- ✅ Make properties immutable with `let`
- ✅ Conform to `Codable` for API responses
- ✅ Keep models pure (no logic)

#### Views

- ✅ Use `@StateObject` to create and own ViewModels
- ✅ Use `@ObservedObject` for passed ViewModels
- ✅ Keep Views "dumb" (presentation only)
- ✅ Delegate all actions to ViewModel
- ✅ Use `@State` only for simple local UI state (toggle, text input)

#### ViewModels

- ✅ Conform to `ObservableObject`
- ✅ Use `@Published` for all UI-bound properties
- ✅ Inject dependencies through initializers
- ✅ Use protocols for dependencies
- ✅ Update UI on `MainActor` after async operations
- ✅ Cancel subscriptions in `deinit`
- ✅ Handle all error cases
- ✅ Provide default values in initializers for production use

#### Testing

- ✅ Write unit tests for ViewModels
- ✅ Create mock repositories for testing
- ✅ Test success and failure cases
- ✅ Test edge cases (empty data, network errors)

---

### ❌ DON'T Do These Things

#### Models

- ❌ Add business logic to Models
- ❌ Add UI formatting logic
- ❌ Make API calls from Models
- ❌ Use `var` unless truly necessary

#### Views

- ❌ Put business logic in Views
- ❌ Create timers or DispatchQueue in Views
- ❌ Make API calls directly from Views
- ❌ Use `@State` for complex state management
- ❌ Perform calculations or data transformations
- ❌ Access UIKit directly (use ViewModel as abstraction)

#### ViewModels

- ❌ Import UIKit (except for UIImage/UIColor when necessary)
- ❌ Create singleton ViewModels
- ❌ Hard-code dependencies (use DI)
- ❌ Forget to update UI on MainActor
- ❌ Forget to clean up timers/subscriptions
- ❌ Expose mutable state directly (use private(set) or methods)

#### General

- ❌ Skip writing tests
- ❌ Use force unwrapping (`!`)
- ❌ Ignore errors with `try?` everywhere
- ❌ Create "God" ViewModels (split into smaller ones)

---

## 9. Testing Your MVVM Architecture

### Why MVVM Makes Testing Easy

**Traditional MVC:**

```
❌ Can't test without UI
❌ Business logic mixed with view controller
❌ Need UI testing for everything
```

**MVVM:**

```
✅ Test ViewModels in isolation
✅ No UI required for business logic tests
✅ Mock dependencies easily
✅ Fast unit tests
```

### Testing Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                     Testing Pyramid                          │
└─────────────────────────────────────────────────────────────┘

                       UI Tests (Slow)
                  ═══════════════════════
              ╱                              ╲
             ╱         Integration Tests      ╲
            ╱      ═════════════════════       ╲
           ╱     ╱                       ╲      ╲
          ╱     ╱   ViewModel Unit Tests  ╲      ╲
         ╱     ╱   ══════════════════════   ╲      ╲
        ╱     ╱  ╱                        ╲  ╲      ╲
       ╱     ╱  ╱     Model Unit Tests     ╲  ╲      ╲
      ╱_____╱__╱__══════════════════════════╲__╲______╲

      Most tests here (Fast, Reliable)
```

**Focus:** 70% ViewModel tests, 20% Integration, 10% UI

### Unit Testing ViewModels

#### Test File Structure

```swift
import XCTest
@testable import WellPlate

class FoodScannerViewModelTests: XCTestCase {
    // System Under Test
    var viewModel: FoodScannerViewModel!

    // Dependencies
    var mockRepository: MockNutritionRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockNutritionRepository()
        viewModel = FoodScannerViewModel(repository: mockRepository)
    }

    override func tearDown() {
        viewModel = nil
        mockRepository = nil
        super.tearDown()
    }

    // Test methods...
}
```

#### Testing Success Cases

```swift
func testAnalyzeFoodSuccess() async {
    // GIVEN: Prepare test data
    let testImage = UIImage(systemName: "photo")!
    viewModel.capturedImage = testImage

    let expectedInfo = NutritionalInfo(
        calories: 300,
        protein: 25,
        carbs: 35,
        fat: 12,
        fiber: 6
    )
    mockRepository.mockData = expectedInfo

    // WHEN: Execute action
    viewModel.analyzeFood()

    // Wait for async operation
    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

    // THEN: Assert results
    XCTAssertEqual(viewModel.nutritionalInfo?.calories, 300)
    XCTAssertEqual(viewModel.nutritionalInfo?.protein, 25)
    XCTAssertFalse(viewModel.isAnalyzing)
    XCTAssertFalse(viewModel.showError)
}
```

#### Testing Failure Cases

```swift
func testAnalyzeFoodNetworkError() async {
    // GIVEN
    let testImage = UIImage(systemName: "photo")!
    viewModel.capturedImage = testImage
    mockRepository.shouldFail = true
    mockRepository.errorToThrow = .networkError(NSError(domain: "", code: -1))

    // WHEN
    viewModel.analyzeFood()

    try? await Task.sleep(nanoseconds: 200_000_000)

    // THEN
    XCTAssertNil(viewModel.nutritionalInfo)
    XCTAssertFalse(viewModel.isAnalyzing)
    XCTAssertTrue(viewModel.showError)
    XCTAssertTrue(viewModel.errorMessage.contains("Network"))
}
```

#### Testing Edge Cases

```swift
func testAnalyzeFoodWithoutImage() {
    // GIVEN: No image captured
    viewModel.capturedImage = nil

    // WHEN
    viewModel.analyzeFood()

    // THEN: Should show error
    XCTAssertTrue(viewModel.showError)
    XCTAssertEqual(viewModel.errorMessage, "Please capture an image first")
    XCTAssertFalse(viewModel.isAnalyzing)
}

func testResetClearsAllState() {
    // GIVEN: ViewModel with data
    viewModel.capturedImage = UIImage(systemName: "photo")
    viewModel.nutritionalInfo = NutritionalInfo(
        calories: 100,
        protein: 10,
        carbs: 20,
        fat: 5
    )
    viewModel.showError = true
    viewModel.errorMessage = "Test error"

    // WHEN
    viewModel.reset()

    // THEN: All state cleared
    XCTAssertNil(viewModel.capturedImage)
    XCTAssertNil(viewModel.nutritionalInfo)
    XCTAssertFalse(viewModel.showError)
    XCTAssertTrue(viewModel.errorMessage.isEmpty)
}
```

### Creating Mock Objects

```swift
class MockNutritionRepository: NutritionRepositoryProtocol {
    // Configuration
    var shouldFail = false
    var errorToThrow: APIError?
    var mockData: NutritionalInfo?
    var callCount = 0

    func analyzeFood(image: UIImage) async throws -> NutritionalInfo {
        callCount += 1

        if shouldFail {
            throw errorToThrow ?? APIError.networkError(NSError(domain: "", code: -1))
        }

        return mockData ?? NutritionalInfo(
            calories: 250,
            protein: 20,
            carbs: 30,
            fat: 10,
            fiber: 5
        )
    }
}
```

### Testing Async Code

```swift
func testAsyncOperation() async {
    // Option 1: Use async/await
    viewModel.performAction()
    try? await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertTrue(viewModel.isComplete)

    // Option 2: Use XCTestExpectation
    let expectation = expectation(description: "Async operation")
    viewModel.performAction()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        XCTAssertTrue(self.viewModel.isComplete)
        expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 1.0)
}
```

### XCTest Best Practices

1. **Use descriptive test names:**

   ```swift
   ❌ func testAnalyze() { }
   ✅ func testAnalyzeFoodSuccess() { }
   ✅ func testAnalyzeFoodNetworkError() { }
   ```
1. **Follow Given-When-Then pattern:**

   ```swift
   // GIVEN: Setup test conditions
   // WHEN: Execute the action
   // THEN: Assert the results
   ```
1. **Test one thing per test:**

   ```swift
   ❌ func testEverything() { /* tests 10 things */ }
   ✅ func testAnalyzeFoodSuccess() { /* tests success case only */ }
   ✅ func testAnalyzeFoodFailure() { /* tests failure case only */ }
   ```
1. **Use XCTAssert variants:**

   ```swift
   XCTAssertEqual(actual, expected)
   XCTAssertTrue(condition)
   XCTAssertFalse(condition)
   XCTAssertNil(optional)
   XCTAssertNotNil(optional)
   XCTAssertThrowsError(try expression)
   ```

---

## 10. Code Review Checklist

Use this checklist when reviewing MVVM code in pull requests:

### Model Review

- [ ] Model is a `struct` (not `class`)
- [ ] All properties use `let` (immutable)
- [ ] Conforms to `Codable` if used with API
- [ ] Contains zero business logic
- [ ] No dependencies on other layers

### View Review

- [ ] Uses `@StateObject` to own ViewModels
- [ ] Uses `@ObservedObject` for passed ViewModels
- [ ] Contains zero business logic
- [ ] No timers or DispatchQueue usage
- [ ] No direct API calls
- [ ] All user actions delegate to ViewModel
- [ ] `@State` only used for simple local UI state

### ViewModel Review

- [ ] Conforms to `ObservableObject`
- [ ] Uses `@Published` for all UI-bound properties
- [ ] Dependencies injected through initializer
- [ ] Uses protocol types for dependencies
- [ ] Async operations update UI on `MainActor`
- [ ] Proper error handling (no force-unwrapping)
- [ ] Timers/subscriptions cancelled in `deinit`
- [ ] No UIKit imports (except UIImage/UIColor if needed)
- [ ] No hard-coded singletons (except for truly global state)

### Repository Review

- [ ] Defined as protocol
- [ ] Concrete implementation injected via DI
- [ ] Abstracts data source (API, database, cache)
- [ ] Proper error handling
- [ ] No business logic (that belongs in ViewModel)

### Testing Review

- [ ] ViewModels have unit tests
- [ ] Success cases tested
- [ ] Failure cases tested
- [ ] Edge cases tested
- [ ] Mock repositories used
- [ ] Tests are fast (no real network calls)
- [ ] Tests follow Given-When-Then pattern

### General Architecture

- [ ] Clear separation of concerns
- [ ] No circular dependencies
- [ ] Follows project naming conventions
- [ ] Files in correct directories
- [ ] No "God" objects (split large ViewModels)

---

## 11. Migration Guide

### Step-by-Step: Refactoring Existing Code to MVVM

#### Step 1: Extract Business Logic to ViewModel

**Before (Bad):**

```swift
struct ProfileView: View {
    @State private var user: User?
    @State private var isLoading = false

    var body: some View {
        // View code
    }

    // ❌ Business logic in View
    private func loadUser() {
        isLoading = true

        Task {
            do {
                let response = try await APIClient.shared.get(
                    url: URL(string: "https://api.wellplate.com/user")!,
                    responseType: User.self
                )
                user = response
                isLoading = false
            } catch {
                print("Error: \(error)")
                isLoading = false
            }
        }
    }
}
```

**After (Good):**

```swift
// Create ViewModel
class ProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage = ""

    private let repository: UserRepositoryProtocol

    init(repository: UserRepositoryProtocol = UserRepository()) {
        self.repository = repository
    }

    func loadUser() {
        isLoading = true

        Task {
            do {
                let user = try await repository.fetchUser()
                await MainActor.run {
                    self.user = user
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// Refactored View
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        // View code using viewModel.user, viewModel.isLoading
    }
    .onAppear {
        viewModel.loadUser()
    }
}
```

#### Step 2: Create Repository Abstraction

```swift
// Protocol
protocol UserRepositoryProtocol {
    func fetchUser() async throws -> User
}

// Implementation
class UserRepository: UserRepositoryProtocol {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchUser() async throws -> User {
        let url = URL(string: "https://api.wellplate.com/user")!
        return try await apiClient.get(url: url, responseType: User.self)
    }
}
```

#### Step 3: Add Dependency Injection

```swift
// Before: Hard-coded dependency
class ViewModel: ObservableObject {
    let apiClient = APIClient.shared // ❌ Hard-coded
}

// After: Injected dependency
class ViewModel: ObservableObject {
    private let repository: RepositoryProtocol

    init(repository: RepositoryProtocol = DefaultRepository()) { // ✅ Injected
        self.repository = repository
    }
}
```

#### Step 4: Write Tests

```swift
class ProfileViewModelTests: XCTestCase {
    func testLoadUserSuccess() async {
        // Given
        let mockRepo = MockUserRepository()
        mockRepo.mockUser = User(id: 1, name: "Test")
        let viewModel = ProfileViewModel(repository: mockRepo)

        // When
        viewModel.loadUser()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(viewModel.user?.name, "Test")
        XCTAssertFalse(viewModel.isLoading)
    }
}
```

#### Step 5: Verify Architecture

- [ ] Model has no logic
- [ ] View has no business logic
- [ ] ViewModel handles all logic
- [ ] Repository abstracts data source
- [ ] Dependencies injected
- [ ] Tests written

---

## 12. Common Pitfalls & Solutions

### Pitfall 1: "My View Needs Multiple ViewModels"

**Problem:**

```swift
struct ComplexView: View {
    @StateObject var viewModel1 = ViewModel1()
    @StateObject var viewModel2 = ViewModel2()
    @StateObject var viewModel3 = ViewModel3()
    // This is getting messy...
}
```

**Solution 1: Create a Parent ViewModel**

```swift
class ComplexViewModel: ObservableObject {
    @Published var state1: State1
    @Published var state2: State2

    private let repository1: Repository1Protocol
    private let repository2: Repository2Protocol

    init(...) {
        // Initialize
    }

    func performAction() {
        // Coordinate between repositories
    }
}

struct ComplexView: View {
    @StateObject var viewModel = ComplexViewModel()
    // Single source of truth
}
```

**Solution 2: Split into Smaller Views**

```swift
struct ComplexView: View {
    var body: some View {
        VStack {
            SubView1()
            SubView2()
            SubView3()
        }
    }
}

struct SubView1: View {
    @StateObject var viewModel = ViewModel1()
    // Each subview manages its own ViewModel
}
```

---

### Pitfall 2: "Passing Data Between ViewModels"

**Problem:** ViewModels need to communicate

**Solution 1: Parent-Child Relationship**

```swift
class ParentViewModel: ObservableObject {
    @Published var sharedData: Data

    func updateData(_ newData: Data) {
        sharedData = newData
    }
}

class ChildViewModel: ObservableObject {
    weak var parent: ParentViewModel?

    func sendDataToParent(_ data: Data) {
        parent?.updateData(data)
    }
}
```

**Solution 2: Shared Repository**

```swift
class SharedRepository: ObservableObject {
    @Published var globalState: State
}

class ViewModel1: ObservableObject {
    private let sharedRepo: SharedRepository

    init(sharedRepo: SharedRepository) {
        self.sharedRepo = sharedRepo
    }
}

class ViewModel2: ObservableObject {
    private let sharedRepo: SharedRepository

    init(sharedRepo: SharedRepository) {
        self.sharedRepo = sharedRepo
    }
}

// In App
@main
struct WellPlateApp: App {
    @StateObject var sharedRepo = SharedRepository()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sharedRepo)
        }
    }
}
```

---

### Pitfall 3: "ViewModel Needs to Navigate"

**Problem:** ViewModels shouldn't know about navigation

**Solution: Use Published Flags**

```swift
class ViewModel: ObservableObject {
    @Published var shouldNavigateToDetail = false
    @Published var selectedItem: Item?

    func selectItem(_ item: Item) {
        selectedItem = item
        shouldNavigateToDetail = true
    }
}

struct ListView: View {
    @StateObject var viewModel = ViewModel()

    var body: some View {
        NavigationView {
            List {
                // List items
            }
            .navigationDestination(isPresented: $viewModel.shouldNavigateToDetail) {
                if let item = viewModel.selectedItem {
                    DetailView(item: item)
                }
            }
        }
    }
}
```

---

### Pitfall 4: "Sharing State Across Features"

**Problem:** Multiple features need access to global state (user session, theme)

**Solution: Use EnvironmentObject**

```swift
// Global state manager
class AppState: ObservableObject {
    @Published var currentUser: User?
    @Published var theme: Theme = .light

    func logout() {
        currentUser = nil
    }
}

// In App
@main
struct WellPlateApp: App {
    @StateObject var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// In ViewModels
class FeatureViewModel: ObservableObject {
    @Published var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func performAction() {
        guard let user = appState.currentUser else { return }
        // Use user
    }
}

// In Views
struct FeatureView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var viewModel: FeatureViewModel

    init() {
        // Can't access @EnvironmentObject in init
        // Pass it after initialization
    }

    var body: some View {
        Text("User: \(appState.currentUser?.name ?? "Guest")")
            .onAppear {
                viewModel.appState = appState
            }
    }
}
```

---

## 13. Advanced Topics

### 13.1 Coordinator Pattern for Navigation

The Coordinator pattern can work alongside MVVM to handle complex navigation flows.

```swift
protocol Coordinator {
    func start()
}

class AppCoordinator: Coordinator {
    func start() {
        // Start app flow
    }

    func showFoodScanner() {
        // Navigate to food scanner
    }
}
```

**When to use:** Large apps with complex navigation requirements.

---

### 13.2 Combining MVVM with Redux/TCA

For apps requiring centralized state management, MVVM can coexist with patterns like Redux or The Composable Architecture (TCA).

**Hybrid Approach:**

- Use MVVM for feature-level logic
- Use Redux/TCA for global state management

---

### 13.3 SwiftUI Environment Objects vs ViewModels

**Environment Objects:** Best for global state (theme, user session, app configuration)

**ViewModels:** Best for feature-specific business logic

```swift
// Global state
@EnvironmentObject var appState: AppState

// Feature logic
@StateObject var viewModel = FoodScannerViewModel()
```

---

### 13.4 When to Break the Rules

MVVM is a guideline, not a law. Sometimes it's okay to:

1. **Use @State for simple UI:** Expandable sections, show/hide toggles
2. **Skip ViewModel for trivial views:** Pure presentation views with no logic
3. **Combine ViewModels:** When features are tightly coupled

**Rule of thumb:** If violating MVVM makes the code simpler and doesn't hurt testability, it's probably fine.

---

## 14. Resources & Further Reading

### Apple Documentation

- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Combine Framework](https://developer.apple.com/documentation/combine)
- [Swift Concurrency (async/await)](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)

### Books

- **"SwiftUI Views Mastery"** by Mark Moeykens
- **"Combine: Asynchronous Programming with Swift"** by raywenderlich.com
- **"Swift Design Patterns"** by Paul Hudson

### Online Resources

- [Swift by Sundell - MVVM](https://www.swiftbysundell.com/articles/different-flavors-of-mvvm-in-swift/)
- [Hacking with Swift - SwiftUI](https://www.hackingwithswift.com/quick-start/swiftui)
- [raywenderlich.com - iOS Tutorials](https://www.raywenderlich.com/ios)

### Community

- [Swift Forums](https://forums.swift.org/)
- [r/iOSProgramming](https://www.reddit.com/r/iOSProgramming/)
- [Stack Overflow - SwiftUI](https://stackoverflow.com/questions/tagged/swiftui)

---

## Conclusion

MVVM is the foundation of WellPlate's architecture. By following the principles outlined in this guide:

1. **Models** remain pure data structures
2. **Views** focus solely on presentation
3. **ViewModels** handle all business logic
4. **Repositories** abstract data sources
5. **Dependency Injection** enables testing

This architecture ensures WellPlate remains:

- ✅ **Testable:** Unit tests for all business logic
- ✅ **Maintainable:** Clear separation of concerns
- ✅ **Scalable:** Easy to add new features
- ✅ **Reliable:** Fewer bugs, better code quality

**Remember:** Architecture is a means to an end. The goal is to write code that works well, is easy to understand, and is a joy to maintain.

---

**Questions or Suggestions?**

This guide is a living document. As the WellPlate project evolves, update this guide to reflect new patterns and learnings.

**Last Updated:** February 16, 2026

**Version:** 1.0

**Maintainer:** WellPlate Development Team