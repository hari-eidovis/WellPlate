# Implementation Plan: APIClient with Mock/Real Mode Switching

**Date**: 2026-02-16
**Feature**: Protocol-based APIClient with configurable mock mode
**Target Directory**: `/Users/hariom/Desktop/WellPlate/WellPlate/Networking`
**Approach**: Protocol-Based Dependency Injection with UserDefaults Configuration

## Overview

Implement a flexible, testable networking layer that supports switching between real API calls and mock responses. The implementation uses protocol-oriented design to enable dependency injection, making the codebase more testable and maintainable while allowing developers to work without backend dependencies.

## Requirements

- ✅ Support all HTTP methods (GET, POST, PUT, DELETE, PATCH) - already exists
- Create protocol abstraction for APIClient interface
- Implement MockAPIClient conforming to same protocol
- Create AppConfig for managing mock mode flag
- Build APIClientFactory for providing appropriate client instance
- Support JSON-based mock data loading from bundle
- Enable runtime switching via UserDefaults (DEBUG only)
- Maintain type safety and async/await patterns
- Zero breaking changes (no existing APIClient.shared usage found)

## Architecture Changes

### New Files to Create

1. **WellPlate/Networking/APIClientProtocol.swift** - Protocol defining networking interface
2. **WellPlate/Networking/MockAPIClient.swift** - Mock implementation of APIClientProtocol
3. **WellPlate/Networking/APIClientFactory.swift** - Factory for providing correct client instance
4. **WellPlate/Core/AppConfig.swift** - Application configuration manager
5. **WellPlate/Networking/MockDataLoader.swift** - Utility for loading mock JSON files
6. **WellPlate/Resources/MockData/** - Directory for JSON mock data files

### Files to Modify

1. **WellPlate/Networking/APIClient.swift** - Make conform to APIClientProtocol
2. **WellPlate/App/WellPlateApp.swift** - Initialize configuration on app launch

## Implementation Steps

### Phase 1: Foundation - Protocol & Configuration

#### 1. **Create APIClientProtocol** (File: WellPlate/Networking/APIClientProtocol.swift)
   - **Action**: Define protocol with all HTTP method signatures from existing APIClient
   - **Why**: Establishes contract that both real and mock implementations must follow
   - **Dependencies**: None
   - **Risk**: Low

   **Details**:
   ```swift
   protocol APIClientProtocol {
       // Generic request method
       func request<T: Decodable>(
           url: URL,
           method: HTTPMethod,
           headers: [String: String]?,
           body: Data?,
           responseType: T.Type
       ) async throws -> T

       // Convenience methods
       func get<T: Decodable>(url: URL, headers: [String: String]?, responseType: T.Type) async throws -> T
       func post<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T
       func put<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T
       func delete<T: Decodable>(url: URL, headers: [String: String]?, responseType: T.Type) async throws -> T
       func patch<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T

       // Helper method
       func encodeBody<T: Encodable>(_ body: T) throws -> Data
   }
   ```

#### 2. **Create AppConfig** (File: WellPlate/Core/AppConfig.swift)
   - **Action**: Create singleton configuration manager with mockMode property
   - **Why**: Centralized configuration that's safe for production (DEBUG-guarded)
   - **Dependencies**: None
   - **Risk**: Low

   **Details**:
   ```swift
   class AppConfig {
       static let shared = AppConfig()

       private init() {}

       var mockMode: Bool {
           get {
               #if DEBUG
               return UserDefaults.standard.bool(forKey: "app.networking.mockMode")
               #else
               return false
               #endif
           }
           set {
               #if DEBUG
               UserDefaults.standard.set(newValue, forKey: "app.networking.mockMode")
               #endif
           }
       }

       // Logging helper to track current mode
       func logCurrentMode() {
           #if DEBUG
           print("🔧 [AppConfig] Mock Mode: \(mockMode ? "ENABLED" : "DISABLED")")
           #endif
       }
   }
   ```

#### 3. **Update APIClient to Conform to Protocol** (File: WellPlate/Networking/APIClient.swift)
   - **Action**: Add protocol conformance to existing APIClient class, add PATCH method
   - **Why**: Makes existing implementation compatible with protocol-based approach
   - **Dependencies**: Requires step 1
   - **Risk**: Low

   **Details**:
   - Add `: APIClientProtocol` to class declaration
   - Add missing `patch` method to match protocol
   - No changes to existing implementation needed

---

### Phase 2: Mock Infrastructure

#### 4. **Create MockDataLoader Utility** (File: WellPlate/Networking/MockDataLoader.swift)
   - **Action**: Implement utility for loading and decoding JSON mock data from bundle
   - **Why**: Provides reusable mechanism for mock data management
   - **Dependencies**: None
   - **Risk**: Low

   **Details**:
   ```swift
   enum MockDataError: Error {
       case fileNotFound(String)
       case decodingFailed(Error)
   }

   class MockDataLoader {
       /// Load mock data from JSON file in bundle
       static func load<T: Decodable>(_ filename: String, bundle: Bundle = .main) throws -> T {
           guard let url = bundle.url(forResource: filename, withExtension: "json") else {
               throw MockDataError.fileNotFound(filename)
           }

           let data = try Data(contentsOf: url)

           do {
               let decoder = JSONDecoder()
               // Configure decoder if needed (e.g., date formats)
               return try decoder.decode(T.self, from: data)
           } catch {
               throw MockDataError.decodingFailed(error)
           }
       }

       /// Load raw data from JSON file
       static func loadRawData(_ filename: String, bundle: Bundle = .main) throws -> Data {
           guard let url = bundle.url(forResource: filename, withExtension: "json") else {
               throw MockDataError.fileNotFound(filename)
           }
           return try Data(contentsOf: url)
       }
   }
   ```

#### 5. **Create MockAPIClient** (File: WellPlate/Networking/MockAPIClient.swift)
   - **Action**: Implement mock version of APIClient that returns predefined data
   - **Why**: Enables offline development and predictable testing
   - **Dependencies**: Requires steps 1, 4
   - **Risk**: Low

   **Details**:
   ```swift
   class MockAPIClient: APIClientProtocol {
       static let shared = MockAPIClient()

       private init() {}

       // MARK: - Generic Request Method

       func request<T: Decodable>(
           url: URL,
           method: HTTPMethod = .get,
           headers: [String: String]? = nil,
           body: Data? = nil,
           responseType: T.Type
       ) async throws -> T {
           // Log the mock request
           print("🎭 [MockAPIClient] \(method.rawValue) \(url.absoluteString)")

           // Simulate network delay (optional but realistic)
           try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

           // Determine mock file based on URL pattern
           let mockFileName = mockFileNameForURL(url, method: method)

           do {
               return try MockDataLoader.load(mockFileName)
           } catch {
               print("⚠️ [MockAPIClient] Failed to load mock data for \(mockFileName)")
               throw APIError.noData
           }
       }

       // MARK: - Convenience Methods

       func get<T: Decodable>(
           url: URL,
           headers: [String: String]? = nil,
           responseType: T.Type
       ) async throws -> T {
           try await request(url: url, method: .get, headers: headers, responseType: responseType)
       }

       func post<T: Decodable>(
           url: URL,
           headers: [String: String]? = nil,
           body: Data? = nil,
           responseType: T.Type
       ) async throws -> T {
           try await request(url: url, method: .post, headers: headers, body: body, responseType: responseType)
       }

       func put<T: Decodable>(
           url: URL,
           headers: [String: String]? = nil,
           body: Data? = nil,
           responseType: T.Type
       ) async throws -> T {
           try await request(url: url, method: .put, headers: headers, body: body, responseType: responseType)
       }

       func delete<T: Decodable>(
           url: URL,
           headers: [String: String]? = nil,
           responseType: T.Type
       ) async throws -> T {
           try await request(url: url, method: .delete, headers: headers, responseType: responseType)
       }

       func patch<T: Decodable>(
           url: URL,
           headers: [String: String]? = nil,
           body: Data? = nil,
           responseType: T.Type
       ) async throws -> T {
           try await request(url: url, method: .patch, headers: headers, body: body, responseType: responseType)
       }

       // MARK: - Helper Methods

       func encodeBody<T: Encodable>(_ body: T) throws -> Data {
           try JSONEncoder().encode(body)
       }

       // MARK: - Private Helpers

       /// Map URL to mock data filename
       private func mockFileNameForURL(_ url: URL, method: HTTPMethod) -> String {
           // Example: /api/users/123 -> mock_users_get
           let path = url.path.replacingOccurrences(of: "/", with: "_")
           return "mock\(path)_\(method.rawValue.lowercased())"
       }
   }
   ```

#### 6. **Create APIClientFactory** (File: WellPlate/Networking/APIClientFactory.swift)
   - **Action**: Implement factory pattern to provide correct client based on configuration
   - **Why**: Single source of truth for which client implementation to use
   - **Dependencies**: Requires steps 1, 2, 3, 5
   - **Risk**: Low

   **Details**:
   ```swift
   enum APIClientFactory {
       /// Creates and returns appropriate APIClient based on current configuration
       static func create() -> APIClientProtocol {
           let client: APIClientProtocol

           if AppConfig.shared.mockMode {
               print("🎭 [APIClientFactory] Creating MockAPIClient")
               client = MockAPIClient.shared
           } else {
               print("🌐 [APIClientFactory] Creating Real APIClient")
               client = APIClient.shared
           }

           return client
       }

       /// Convenience property for cleaner access
       static var shared: APIClientProtocol {
           create()
       }
   }
   ```

---

### Phase 3: Integration & Mock Data Setup

#### 7. **Create Mock Data Directory Structure** (Directory: WellPlate/Resources/MockData/)
   - **Action**: Create directory and initial example mock JSON files
   - **Why**: Organized storage for mock data with clear naming convention
   - **Dependencies**: None
   - **Risk**: Low

   **Details**:
   - Create `WellPlate/Resources/MockData/` directory
   - Add `.gitkeep` file to track directory
   - Create example file: `mock_api_user_get.json`
   - Create README.md with naming conventions

   **Naming Convention**:
   - Pattern: `mock_<endpoint_path>_<method>.json`
   - Example: `mock_api_users_get.json` for `GET /api/users`
   - Example: `mock_api_user_123_get.json` for `GET /api/user/123`

#### 8. **Create Sample Mock Data Files** (Files: WellPlate/Resources/MockData/*.json)
   - **Action**: Create example JSON files demonstrating mock data structure
   - **Why**: Provides template and reference for future mock data
   - **Dependencies**: Requires step 7
   - **Risk**: Low

   **Details**:
   - Create `mock_api_health_get.json` - Simple health check example
   - Create README.md documenting mock data conventions
   - Add example showing success and error response formats

#### 9. **Initialize AppConfig on App Launch** (File: WellPlate/App/WellPlateApp.swift)
   - **Action**: Add initialization code to log configuration state
   - **Why**: Visibility into which mode the app is running in
   - **Dependencies**: Requires step 2
   - **Risk**: Low

   **Details**:
   ```swift
   @main
   struct WellPlateApp: App {
       init() {
           // Log current configuration on app start
           AppConfig.shared.logCurrentMode()
       }

       var body: some Scene {
           WindowGroup {
               ContentView()
           }
       }
   }
   ```

---

### Phase 4: Documentation & Examples

#### 10. **Create Usage Documentation** (File: WellPlate/Networking/README.md)
   - **Action**: Document how to use the networking layer
   - **Why**: Onboarding for team members and future reference
   - **Dependencies**: All previous steps
   - **Risk**: Low

   **Content**:
   - How to use APIClientFactory in ViewModels
   - How to toggle mock mode for development
   - How to add new mock data files
   - Testing examples
   - Troubleshooting common issues

#### 11. **Add Example ViewModel Integration** (File: WellPlate/Networking/EXAMPLES.md)
   - **Action**: Create example code showing ViewModel integration
   - **Why**: Clear reference for implementing networking in features
   - **Dependencies**: All previous steps
   - **Risk**: Low

   **Examples**:
   ```swift
   // Example ViewModel using APIClient
   class UserViewModel: ObservableObject {
       private let apiClient: APIClientProtocol
       @Published var user: User?

       init(apiClient: APIClientProtocol = APIClientFactory.shared) {
           self.apiClient = apiClient
       }

       func fetchUser(id: String) async {
           do {
               let url = URL(string: "https://api.example.com/users/\(id)")!
               let user = try await apiClient.get(
                   url: url,
                   headers: nil,
                   responseType: User.self
               )
               await MainActor.run {
                   self.user = user
               }
           } catch {
               print("Error: \(error)")
           }
       }
   }
   ```

---

## Testing Strategy

### Unit Tests
Create `WellPlateTests/Networking/APIClientTests.swift`:
- Test APIClient conforms to protocol
- Test MockAPIClient conforms to protocol
- Test factory returns correct instance based on config
- Test mock data loading with valid/invalid files
- Test error handling in both implementations

### Integration Tests
- Test real APIClient with actual network calls (optional, requires test server)
- Test MockAPIClient returns expected data for known URLs
- Test configuration switching

### Manual Testing
1. Set `mockMode = false` → verify real network calls (if backend available)
2. Set `mockMode = true` → verify mock data loading
3. Toggle mode at runtime via UserDefaults
4. Test error scenarios (missing mock files, malformed JSON)

### Test Mock Mode Toggle
```swift
// In debug menu or test
#if DEBUG
AppConfig.shared.mockMode = true  // Enable mock mode
AppConfig.shared.mockMode = false // Disable mock mode
#endif
```

---

## Risks & Mitigations

### Risk 1: Mock data out of sync with real API
- **Severity**: Medium
- **Mitigation**:
  - Document mock data update process
  - Use same model types for mock and real responses
  - Consider generating mocks from OpenAPI/Swagger specs
  - Regular sync with backend team

### Risk 2: Accidentally shipping with mockMode enabled
- **Severity**: High
- **Mitigation**:
  - `#if DEBUG` guard ensures production always uses real client
  - Add build script to verify UserDefaults is clear
  - Code review checklist item

### Risk 3: Mock file naming conflicts
- **Severity**: Low
- **Mitigation**:
  - Document clear naming convention
  - Implement better URL → filename mapping if needed
  - Consider using URL hash for unique filenames

### Risk 4: Missing PATCH method in current APIClient
- **Severity**: Low
- **Mitigation**:
  - Add in step 3 as part of protocol conformance
  - Simple copy of PUT method with different HTTP verb

### Risk 5: Large mock data files bloating bundle size
- **Severity**: Low
- **Mitigation**:
  - Strip mock data in Release builds
  - Use build phase script to exclude MockData folder
  - Keep mock responses minimal (only necessary fields)

---

## Success Criteria

- [ ] APIClientProtocol created with all HTTP methods
- [ ] APIClient conforms to protocol without breaking changes
- [ ] MockAPIClient fully implements protocol
- [ ] AppConfig manages mockMode with DEBUG guard
- [ ] APIClientFactory provides correct client based on config
- [ ] MockDataLoader can load JSON files from bundle
- [ ] Mock data directory structure created with examples
- [ ] Documentation written (README + EXAMPLES)
- [ ] Unit tests pass for all components
- [ ] Can toggle between mock/real mode at runtime (DEBUG only)
- [ ] Mock mode forced OFF in Release builds
- [ ] No compilation errors or warnings

---

## Implementation Order Summary

**Critical Path** (Must be done in order):
1. Create APIClientProtocol (foundation)
2. Create AppConfig (configuration)
3. Update APIClient to conform (compatibility)
4. Create MockDataLoader (mock infrastructure)
5. Create MockAPIClient (mock implementation)
6. Create APIClientFactory (integration)

**Parallel Work** (Can be done simultaneously after critical path):
- Create mock data directory & files
- Write documentation
- Write tests
- Add app initialization logging

**Total Estimated Time**: 4-6 hours for full implementation and testing

---

## Future Enhancements

### Phase 2 Features (Post-MVP)
- **Debug Menu**: SwiftUI view to toggle mock mode at runtime
- **Mock Scenarios**: Multiple mock datasets (empty, error, full)
- **Network Delay Simulation**: Configurable latency for mock responses
- **Request Logging**: Comprehensive logging of all requests
- **Response Recording**: Capture real responses as mock files
- **Partial Mocking**: Some endpoints real, some mock

### Advanced Features
- **Caching Layer**: Implement CachingAPIClient conforming to protocol
- **Retry Logic**: Add retry mechanism with exponential backoff
- **Request Interceptors**: Middleware pattern for auth tokens, logging
- **Analytics Integration**: Track API call metrics
- **Offline Mode**: Detect network status and use cached data

---

## Migration Guide

### For New Code
```swift
// ✅ Correct - Use factory
class MyViewModel {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClientFactory.shared) {
        self.apiClient = apiClient
    }
}
```

### For Existing Code (None currently)
No migration needed - no existing `APIClient.shared` usage found in codebase.

### For Tests
```swift
// ✅ Inject mock directly in tests
func testViewModel() {
    let mockClient = MockAPIClient.shared
    let viewModel = MyViewModel(apiClient: mockClient)
    // Test with predictable mock data
}
```

---

## Appendix: File Checklist

### New Files to Create
- [ ] `WellPlate/Networking/APIClientProtocol.swift`
- [ ] `WellPlate/Core/AppConfig.swift`
- [ ] `WellPlate/Networking/MockDataLoader.swift`
- [ ] `WellPlate/Networking/MockAPIClient.swift`
- [ ] `WellPlate/Networking/APIClientFactory.swift`
- [ ] `WellPlate/Networking/README.md`
- [ ] `WellPlate/Networking/EXAMPLES.md`
- [ ] `WellPlate/Resources/MockData/.gitkeep`
- [ ] `WellPlate/Resources/MockData/README.md`
- [ ] `WellPlate/Resources/MockData/mock_api_health_get.json`

### Files to Modify
- [ ] `WellPlate/Networking/APIClient.swift` (add protocol conformance + PATCH method)
- [ ] `WellPlate/App/WellPlateApp.swift` (add config initialization)

### Test Files to Create
- [ ] `WellPlateTests/Networking/APIClientProtocolTests.swift`
- [ ] `WellPlateTests/Networking/MockAPIClientTests.swift`
- [ ] `WellPlateTests/Networking/APIClientFactoryTests.swift`
- [ ] `WellPlateTests/Networking/MockDataLoaderTests.swift`

---

## References
- Brainstorming Document: `/Users/hariom/Desktop/WellPlate/Docs/02_Planning/Brainstorming/APIClient-Mock-Configuration.md`
- Current APIClient: `/Users/hariom/Desktop/WellPlate/WellPlate/Networking/APIClient.swift`
- Swift Protocol-Oriented Programming: https://developer.apple.com/videos/play/wwdc2015/408/
- Dependency Injection in Swift: https://www.swiftbysundell.com/articles/dependency-injection-using-factories-in-swift/
