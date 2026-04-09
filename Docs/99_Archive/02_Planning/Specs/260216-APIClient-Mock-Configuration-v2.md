# Implementation Plan: APIClient with Mock/Real Mode Switching (REVISED)

**Date**: 2026-02-16 (Revised after audit)
**Version**: 2.0
**Feature**: Protocol-based APIClient with configurable mock mode
**Target Directory**: `/Users/hariom/Desktop/WellPlate/WellPlate/Networking`
**Approach**: Protocol-Based Dependency Injection with UserDefaults Configuration

## Revision Notes

**Changes from v1.0:**
- ✅ **CRITICAL FIX**: Changed APIClientFactory.shared from computed property to cached static
- ✅ **CRITICAL FIX**: Added explicit Xcode project integration steps
- ✅ **CRITICAL FIX**: Made test infrastructure setup optional (Phase 0)
- ✅ **CRITICAL FIX**: Redesigned mock filename mapping with registry pattern
- ✅ **HIGH FIX**: Added build phase script for stripping mock data
- ✅ **HIGH FIX**: Corrected PATCH method description (convenience method missing, not enum)
- ✅ **HIGH FIX**: Added void-returning variants for non-Decodable responses
- ✅ **MEDIUM FIX**: Moved shared types (HTTPMethod, APIError) to protocol file

## Overview

Implement a flexible, testable networking layer that supports switching between real API calls and mock responses. The implementation uses protocol-oriented design to enable dependency injection, making the codebase more testable and maintainable while allowing developers to work without backend dependencies.

## Requirements

- ✅ Support all HTTP methods (GET, POST, PUT, DELETE, PATCH) - HTTPMethod enum already exists
- Add PATCH convenience method to APIClient (currently missing)
- Create protocol abstraction for APIClient interface
- Implement MockAPIClient conforming to same protocol
- Create AppConfig for managing mock mode flag
- Build APIClientFactory with cached singleton pattern
- Support JSON-based mock data loading from bundle with registry pattern
- Enable runtime switching via UserDefaults (DEBUG only, requires app restart)
- Maintain type safety and async/await patterns
- Support non-Decodable responses (204 No Content, etc.)
- Proper Xcode project integration for bundle resources
- Zero breaking changes (no existing APIClient.shared usage found)

## Architecture Changes

### New Files to Create

1. **WellPlate/Networking/APIClientProtocol.swift** - Protocol + shared types (HTTPMethod, APIError)
2. **WellPlate/Networking/MockAPIClient.swift** - Mock implementation of APIClientProtocol
3. **WellPlate/Networking/MockResponseRegistry.swift** - Registry for mapping URLs to mock files
4. **WellPlate/Networking/APIClientFactory.swift** - Factory with cached singleton
5. **WellPlate/Core/AppConfig.swift** - Application configuration manager
6. **WellPlate/Networking/MockDataLoader.swift** - Utility for loading mock JSON files
7. **WellPlate/Resources/MockData/** - Directory for JSON mock data files

### Files to Modify

1. **WellPlate/Networking/APIClient.swift** - Make conform to APIClientProtocol, add PATCH method
2. **WellPlate/App/WellPlateApp.swift** - Initialize configuration on app launch

### Xcode Project Changes

1. Add MockData folder to Xcode project as folder reference
2. Ensure MockData files are included in app target (not test target)
3. Add build phase script to strip MockData in Release builds
4. (Optional) Create WellPlateTests target if testing is desired

## Implementation Steps

### Phase 0: Prerequisites (Optional)

#### 0a. **Create Test Target** (Optional - Skip if testing deferred)
   - **Action**: Create WellPlateTests target in Xcode if unit testing is desired
   - **Why**: Enables unit test file creation in later phases
   - **Dependencies**: None
   - **Risk**: Low
   - **Note**: Can be skipped and added later without affecting main implementation

   **Steps**:
   1. File → New → Target → Unit Testing Bundle
   2. Name: WellPlateTests
   3. Create WellPlateTests directory structure
   4. Skip this step if deferring testing to post-MVP

---

### Phase 1: Foundation - Protocol & Configuration

#### 1. **Create APIClientProtocol with Shared Types** (File: WellPlate/Networking/APIClientProtocol.swift)
   - **Action**: Define protocol and move shared types (HTTPMethod, APIError) to this file
   - **Why**: Single source of truth for networking contract and shared types
   - **Dependencies**: None
   - **Risk**: Low

   **Details**:
   ```swift
   import Foundation

   // MARK: - HTTP Method Enum
   enum HTTPMethod: String {
       case get = "GET"
       case post = "POST"
       case put = "PUT"
       case delete = "DELETE"
       case patch = "PATCH"
   }

   // MARK: - API Error Types
   enum APIError: Error {
       case invalidURL
       case invalidResponse
       case noData
       case decodingError(Error)
       case serverError(statusCode: Int, message: String?)
       case networkError(Error)
   }

   // MARK: - Empty Response for 204 No Content
   struct EmptyResponse: Codable {}

   // MARK: - Protocol Definition
   protocol APIClientProtocol {
       // Generic request with decodable response
       func request<T: Decodable>(
           url: URL,
           method: HTTPMethod,
           headers: [String: String]?,
           body: Data?,
           responseType: T.Type
       ) async throws -> T

       // Request with no response (void)
       func requestVoid(
           url: URL,
           method: HTTPMethod,
           headers: [String: String]?,
           body: Data?
       ) async throws

       // Convenience methods
       func get<T: Decodable>(url: URL, headers: [String: String]?, responseType: T.Type) async throws -> T
       func post<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T
       func put<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T
       func delete<T: Decodable>(url: URL, headers: [String: String]?, responseType: T.Type) async throws -> T
       func patch<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T

       // Void variants for no-response operations
       func deleteVoid(url: URL, headers: [String: String]?) async throws
       func putVoid(url: URL, headers: [String: String]?, body: Data?) async throws

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
   import Foundation

   class AppConfig {
       static let shared = AppConfig()

       private init() {
           // Initialize with default settings
       }

       var mockMode: Bool {
           get {
               #if DEBUG
               // Check if value has been set, otherwise default to true for dev convenience
               guard UserDefaults.standard.object(forKey: "app.networking.mockMode") != nil else {
                   return true  // Development-friendly default
               }
               return UserDefaults.standard.bool(forKey: "app.networking.mockMode")
               #else
               return false  // Always false in production
               #endif
           }
           set {
               #if DEBUG
               UserDefaults.standard.set(newValue, forKey: "app.networking.mockMode")
               print("🔧 [AppConfig] Mock Mode changed to: \(newValue)")
               print("⚠️  App restart required for changes to take effect")
               #endif
           }
       }

       // Logging helper to track current mode
       func logCurrentMode() {
           #if DEBUG
           print("🔧 [AppConfig] Mock Mode: \(mockMode ? "ENABLED ✅" : "DISABLED ❌")")
           #endif
       }
   }
   ```

#### 3. **Update APIClient to Conform to Protocol** (File: WellPlate/Networking/APIClient.swift)
   - **Action**: Remove HTTPMethod and APIError, import from protocol file, add protocol conformance, add missing methods
   - **Why**: Makes existing implementation compatible with protocol-based approach
   - **Dependencies**: Requires step 1
   - **Risk**: Low

   **Changes**:
   1. Remove `enum HTTPMethod` (now in APIClientProtocol.swift)
   2. Remove `enum APIError` (now in APIClientProtocol.swift)
   3. Add `import APIClientProtocol` at top
   4. Add `: APIClientProtocol` to class declaration
   5. Add missing `patch` convenience method:
      ```swift
      func patch<T: Decodable>(
          url: URL,
          headers: [String: String]? = nil,
          body: Data? = nil,
          responseType: T.Type
      ) async throws -> T {
          try await request(url: url, method: .patch, headers: headers, body: body, responseType: responseType)
      }
      ```
   6. Add void-returning variants:
      ```swift
      func requestVoid(url: URL, method: HTTPMethod, headers: [String: String]?, body: Data?) async throws {
          let _: EmptyResponse = try await request(url: url, method: method, headers: headers, body: body, responseType: EmptyResponse.self)
      }

      func deleteVoid(url: URL, headers: [String: String]? = nil) async throws {
          try await requestVoid(url: url, method: .delete, headers: headers, body: nil)
      }

      func putVoid(url: URL, headers: [String: String]? = nil, body: Data? = nil) async throws {
          try await requestVoid(url: url, method: .put, headers: headers, body: body)
      }
      ```

---

### Phase 2: Mock Infrastructure

#### 4. **Create MockResponseRegistry** (File: WellPlate/Networking/MockResponseRegistry.swift)
   - **Action**: Create registry for mapping URL patterns to mock data filenames
   - **Why**: Handles complex URLs with query params, path params, and dynamic IDs
   - **Dependencies**: Requires step 1
   - **Risk**: Low

   **Details**:
   ```swift
   import Foundation

   /// Registry for mapping URL patterns to mock data files
   class MockResponseRegistry {
       static let shared = MockResponseRegistry()

       private var registry: [URLPattern: String] = [:]

       private init() {
           setupDefaultMappings()
       }

       struct URLPattern: Hashable {
           let path: String
           let method: HTTPMethod

           init(_ path: String, method: HTTPMethod) {
               self.path = path
               self.method = method
           }
       }

       /// Register a mock file for a URL pattern
       func register(path: String, method: HTTPMethod, mockFile: String) {
           let pattern = URLPattern(path, method: method)
           registry[pattern] = mockFile
       }

       /// Get mock filename for URL and method
       func mockFile(for url: URL, method: HTTPMethod) -> String? {
           // Try exact path match first
           let exactPattern = URLPattern(url.path, method: method)
           if let mockFile = registry[exactPattern] {
               return mockFile
           }

           // Try pattern matching (e.g., /api/users/{id})
           for (pattern, mockFile) in registry {
               if matchesPattern(pattern.path, actualPath: url.path) && pattern.method == method {
                   return mockFile
               }
           }

           // Fallback: generate filename from path
           return generateDefaultFilename(for: url, method: method)
       }

       // MARK: - Pattern Matching

       private func matchesPattern(_ pattern: String, actualPath: String) -> Bool {
           // Convert pattern like /api/users/{id} to regex
           let regexPattern = pattern
               .replacingOccurrences(of: "{id}", with: "[^/]+")
               .replacingOccurrences(of: "{", with: "\\{")
               .replacingOccurrences(of: "}", with: "\\}")

           guard let regex = try? NSRegularExpression(pattern: "^" + regexPattern + "$") else {
               return false
           }

           let range = NSRange(actualPath.startIndex..., in: actualPath)
           return regex.firstMatch(in: actualPath, range: range) != nil
       }

       private func generateDefaultFilename(for url: URL, method: HTTPMethod) -> String {
           // Sanitize path for filename
           let sanitized = url.path
               .replacingOccurrences(of: "/", with: "_")
               .replacingOccurrences(of: ".", with: "_")

           return "mock\(sanitized)_\(method.rawValue.lowercased())"
       }

       // MARK: - Default Mappings

       private func setupDefaultMappings() {
           // Example mappings - customize for your API
           register(path: "/api/health", method: .get, mockFile: "mock_health_check")
           register(path: "/api/users", method: .get, mockFile: "mock_users_list")
           register(path: "/api/users/{id}", method: .get, mockFile: "mock_user_detail")
           register(path: "/api/users/{id}", method: .delete, mockFile: "mock_user_delete")

           // Add your API endpoint mappings here
       }
   }
   ```

#### 5. **Create MockDataLoader Utility** (File: WellPlate/Networking/MockDataLoader.swift)
   - **Action**: Implement utility for loading and decoding JSON mock data from bundle
   - **Why**: Provides reusable mechanism for mock data management with better error messages
   - **Dependencies**: Requires step 1
   - **Risk**: Low

   **Details**:
   ```swift
   import Foundation

   enum MockDataError: Error {
       case fileNotFound(String)
       case decodingFailed(Error)

       var localizedDescription: String {
           switch self {
           case .fileNotFound(let filename):
               return "Mock data file not found: \(filename).json\n" +
                      "Expected location: Resources/MockData/\(filename).json\n" +
                      "Add this file to your Xcode project or register a different mapping."
           case .decodingFailed(let error):
               return "Failed to decode mock data: \(error.localizedDescription)"
           }
       }
   }

   class MockDataLoader {
       /// Load mock data from JSON file in bundle
       static func load<T: Decodable>(_ filename: String, bundle: Bundle = .main) throws -> T {
           #if DEBUG
           print("📦 [MockDataLoader] Loading: \(filename).json")
           #endif

           guard let url = bundle.url(forResource: filename, withExtension: "json") else {
               let error = MockDataError.fileNotFound(filename)
               #if DEBUG
               print("❌ [MockDataLoader] \(error.localizedDescription)")
               #endif
               throw error
           }

           let data = try Data(contentsOf: url)

           do {
               let decoder = JSONDecoder()
               // Configure decoder for common date formats
               decoder.dateDecodingStrategy = .iso8601
               let decoded = try decoder.decode(T.self, from: data)

               #if DEBUG
               print("✅ [MockDataLoader] Successfully loaded \(filename).json")
               #endif

               return decoded
           } catch {
               let mockError = MockDataError.decodingFailed(error)
               #if DEBUG
               print("❌ [MockDataLoader] \(mockError.localizedDescription)")
               #endif
               throw mockError
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

#### 6. **Create MockAPIClient** (File: WellPlate/Networking/MockAPIClient.swift)
   - **Action**: Implement mock version using registry pattern
   - **Why**: Enables offline development with realistic URL handling
   - **Dependencies**: Requires steps 1, 4, 5
   - **Risk**: Low

   **Details**:
   ```swift
   import Foundation

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
           #if DEBUG
           print("🎭 [MockAPIClient] \(method.rawValue) \(url.absoluteString)")
           #endif

           // Simulate network delay
           try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

           // Get mock filename from registry
           guard let mockFileName = MockResponseRegistry.shared.mockFile(for: url, method: method) else {
               print("⚠️ [MockAPIClient] No mock mapping found for \(url.path)")
               throw APIError.noData
           }

           do {
               return try MockDataLoader.load(mockFileName)
           } catch {
               print("⚠️ [MockAPIClient] Failed to load mock data: \(error.localizedDescription)")
               throw APIError.noData
           }
       }

       func requestVoid(url: URL, method: HTTPMethod, headers: [String: String]?, body: Data?) async throws {
           // For void responses, just simulate delay
           #if DEBUG
           print("🎭 [MockAPIClient] \(method.rawValue) \(url.absoluteString) (void)")
           #endif
           try await Task.sleep(nanoseconds: 500_000_000)
       }

       // MARK: - Convenience Methods

       func get<T: Decodable>(url: URL, headers: [String: String]?, responseType: T.Type) async throws -> T {
           try await request(url: url, method: .get, headers: headers, responseType: responseType)
       }

       func post<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T {
           try await request(url: url, method: .post, headers: headers, body: body, responseType: responseType)
       }

       func put<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T {
           try await request(url: url, method: .put, headers: headers, body: body, responseType: responseType)
       }

       func delete<T: Decodable>(url: URL, headers: [String: String]?, responseType: T.Type) async throws -> T {
           try await request(url: url, method: .delete, headers: headers, responseType: responseType)
       }

       func patch<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T {
           try await request(url: url, method: .patch, headers: headers, body: body, responseType: responseType)
       }

       func deleteVoid(url: URL, headers: [String: String]?) async throws {
           try await requestVoid(url: url, method: .delete, headers: headers, body: nil)
       }

       func putVoid(url: URL, headers: [String: String]?, body: Data?) async throws {
           try await requestVoid(url: url, method: .put, headers: headers, body: body)
       }

       // MARK: - Helper Methods

       func encodeBody<T: Encodable>(_ body: T) throws -> Data {
           try JSONEncoder().encode(body)
       }
   }
   ```

#### 7. **Create APIClientFactory with Cached Singleton** (File: WellPlate/Networking/APIClientFactory.swift)
   - **Action**: Implement factory pattern with cached static property
   - **Why**: Single source of truth with proper singleton behavior
   - **Dependencies**: Requires steps 1, 2, 3, 6
   - **Risk**: Low

   **Details**:
   ```swift
   import Foundation

   enum APIClientFactory {
       /// Cached singleton instance - evaluated once at first access
       private static let _shared: APIClientProtocol = {
           let client: APIClientProtocol

           if AppConfig.shared.mockMode {
               #if DEBUG
               print("🎭 [APIClientFactory] Creating MockAPIClient")
               #endif
               client = MockAPIClient.shared
           } else {
               #if DEBUG
               print("🌐 [APIClientFactory] Creating Real APIClient")
               #endif
               client = APIClient.shared
           }

           return client
       }()

       /// Shared instance - returns cached singleton
       static var shared: APIClientProtocol {
           _shared
       }

       /// For testing only - allows resetting the factory
       #if DEBUG
       private(set) static var _testInstance: APIClientProtocol?

       static func setTestInstance(_ instance: APIClientProtocol?) {
           _testInstance = instance
       }

       static var testable: APIClientProtocol {
           _testInstance ?? _shared
       }
       #endif
   }
   ```

   **Note**: Changing mockMode requires app restart since factory caches on first access.

---

### Phase 3: Xcode Project Integration & Mock Data

#### 8. **Create Mock Data Directory Structure** (Directory: WellPlate/Resources/MockData/)
   - **Action**: Create filesystem directory and initial files
   - **Why**: Organized storage for mock data
   - **Dependencies**: None
   - **Risk**: Low

   **Steps**:
   1. Create directory: `mkdir -p WellPlate/Resources/MockData`
   2. Create `.gitkeep`: `touch WellPlate/Resources/MockData/.gitkeep`
   3. Create README.md explaining structure

#### 9. **Add MockData to Xcode Project** (Xcode Project Modification)
   - **Action**: Add MockData folder as folder reference in Xcode
   - **Why**: Makes mock files available in app bundle at runtime
   - **Dependencies**: Requires step 8
   - **Risk**: Medium (manual Xcode step)

   **Steps**:
   1. Open Xcode project: `WellPlate.xcodeproj`
   2. Right-click on `Resources` folder in Project Navigator
   3. Select "Add Files to WellPlate..."
   4. Navigate to `WellPlate/Resources/MockData`
   5. **IMPORTANT**: Select "Create folder references" (NOT "Create groups")
   6. **IMPORTANT**: Ensure "WellPlate" target is checked under "Add to targets"
   7. Click "Add"
   8. Verify in Build Phases → Copy Bundle Resources that MockData appears

   **Verification**:
   ```swift
   // Add temporary test in WellPlateApp.init()
   #if DEBUG
   if let url = Bundle.main.url(forResource: "MockData", withExtension: nil) {
       print("✅ MockData folder found in bundle")
   } else {
       print("❌ MockData folder NOT in bundle - check Xcode project settings")
   }
   #endif
   ```

#### 10. **Create Sample Mock Data Files** (Files: WellPlate/Resources/MockData/*.json)
   - **Action**: Create example JSON files for testing
   - **Why**: Provides working examples and validates setup
   - **Dependencies**: Requires steps 8, 9
   - **Risk**: Low

   **Create `mock_health_check.json`**:
   ```json
   {
       "status": "ok",
       "timestamp": "2026-02-16T12:00:00Z",
       "version": "1.0.0"
   }
   ```

   **Create `mock_users_list.json`** (example):
   ```json
   [
       {
           "id": "1",
           "name": "John Doe",
           "email": "john@example.com"
       },
       {
           "id": "2",
           "name": "Jane Smith",
           "email": "jane@example.com"
       }
   ]
   ```

   **Create `mock_user_detail.json`**:
   ```json
   {
       "id": "123",
       "name": "John Doe",
       "email": "john@example.com",
       "createdAt": "2026-01-01T00:00:00Z"
   }
   ```

   **Create `README.md`** in MockData:
   ```markdown
   # Mock Data Files

   ## Naming Convention
   - Pattern: `mock_<description>_<method>.json` or just `mock_<description>.json`
   - Registered in `MockResponseRegistry.swift`

   ## Adding New Mocks
   1. Create JSON file in this directory
   2. Register URL pattern in `MockResponseRegistry.setupDefaultMappings()`
   3. Add file to Xcode project if not auto-detected

   ## Examples
   - `mock_health_check.json` - Health check endpoint
   - `mock_users_list.json` - List of users
   - `mock_user_detail.json` - Single user detail
   ```

#### 11. **Add Build Phase Script to Strip MockData** (Xcode Build Phase)
   - **Action**: Add Run Script phase to remove MockData in Release builds
   - **Why**: Prevents shipping mock data to production
   - **Dependencies**: Requires step 9
   - **Risk**: Low

   **Steps**:
   1. Open Xcode project
   2. Select WellPlate target
   3. Go to Build Phases tab
   4. Click "+" → "New Run Script Phase"
   5. Name it: "Strip Mock Data in Release"
   6. Add script:
      ```bash
      if [ "${CONFIGURATION}" = "Release" ]; then
          echo "🗑️  Removing MockData from Release build"
          rm -rf "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/MockData"
          echo "✅ MockData removed from bundle"
      else
          echo "ℹ️  MockData preserved in ${CONFIGURATION} build"
      fi
      ```
   7. Move script phase to AFTER "Copy Bundle Resources"
   8. Test by building in Release configuration

#### 12. **Initialize AppConfig on App Launch** (File: WellPlate/App/WellPlateApp.swift)
   - **Action**: Add initialization code to log configuration state
   - **Why**: Visibility into which mode the app is running in
   - **Dependencies**: Requires step 2
   - **Risk**: Low

   **Details**:
   ```swift
   import SwiftUI

   @main
   struct WellPlateApp: App {
       init() {
           // Log current configuration on app start
           AppConfig.shared.logCurrentMode()

           // Log which API client is being used
           _ = APIClientFactory.shared  // Trigger lazy initialization

           #if DEBUG
           // Verify MockData bundle inclusion
           if AppConfig.shared.mockMode {
               if Bundle.main.url(forResource: "MockData", withExtension: nil) != nil {
                   print("✅ MockData folder found in bundle")
               } else {
                   print("❌ WARNING: MockData folder NOT in bundle!")
                   print("   Add MockData to Xcode project via File → Add Files")
               }
           }
           #endif
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

#### 13. **Create Usage Documentation** (File: WellPlate/Networking/README.md)
   - **Action**: Document how to use the networking layer
   - **Why**: Onboarding for team members and future reference
   - **Dependencies**: All previous steps
   - **Risk**: Low

   **Content Outline**:
   - Overview of networking architecture
   - How to use APIClientFactory in ViewModels
   - How to toggle mock mode (UserDefaults command)
   - How to add new API endpoints
   - How to add new mock data files
   - Testing examples
   - Troubleshooting common issues
   - FAQ

#### 14. **Create Example Code** (File: WellPlate/Networking/EXAMPLES.md)
   - **Action**: Provide example ViewModel integration code
   - **Why**: Clear reference for implementing networking in features
   - **Dependencies**: All previous steps
   - **Risk**: Low

   **Include Examples**:
   - Basic ViewModel with APIClient
   - Dependency injection in tests
   - Error handling patterns
   - Void response handling (DELETE, PUT)
   - Adding new mock mappings

---

## Testing Strategy

### Unit Tests (Optional - Requires Phase 0)

**If test target was created**, create these tests:

- `WellPlateTests/Networking/APIClientProtocolTests.swift`
  - Test APIClient conforms to protocol
  - Test MockAPIClient conforms to protocol

- `WellPlateTests/Networking/APIClientFactoryTests.swift`
  - Test factory returns same instance on multiple calls
  - Test factory returns MockAPIClient when mockMode = true
  - Test factory returns APIClient when mockMode = false

- `WellPlateTests/Networking/MockDataLoaderTests.swift`
  - Test loading valid JSON file
  - Test error on missing file
  - Test error on malformed JSON

- `WellPlateTests/Networking/MockResponseRegistryTests.swift`
  - Test exact path matching
  - Test pattern matching with {id}
  - Test fallback filename generation

### Integration Tests

- Manual testing with mockMode on/off
- Verify mock data loads correctly
- Test error scenarios (missing files, malformed JSON)

### Manual Testing Checklist

1. ✅ Set `mockMode = true` via UserDefaults
2. ✅ Restart app
3. ✅ Verify mock data loads
4. ✅ Set `mockMode = false`
5. ✅ Restart app
6. ✅ Verify real network calls (if backend available)
7. ✅ Test missing mock file error handling
8. ✅ Build in Release and verify MockData is stripped
9. ✅ Verify no warnings or errors in console

### Testing Mock Mode Toggle

```swift
// In Xcode console or debug menu
#if DEBUG
// Enable mock mode
UserDefaults.standard.set(true, forKey: "app.networking.mockMode")

// Disable mock mode
UserDefaults.standard.set(false, forKey: "app.networking.mockMode")

// Restart app for changes to take effect
#endif
```

---

## Risks & Mitigations

### Risk 1: Mock data out of sync with real API
- **Severity**: Medium
- **Status**: ✅ Mitigated
- **Mitigation**: Registry pattern makes updates easier; document update process

### Risk 2: Accidentally shipping with mockMode enabled
- **Severity**: High
- **Status**: ✅ Mitigated
- **Mitigation**: `#if DEBUG` guard + UserDefaults (not source code) prevents this

### Risk 3: MockData not in bundle
- **Severity**: High
- **Status**: ✅ Mitigated
- **Mitigation**: Explicit Xcode integration steps + verification in app init

### Risk 4: Factory creating multiple instances
- **Severity**: Critical
- **Status**: ✅ FIXED in v2.0
- **Mitigation**: Changed to cached static let instead of computed property

### Risk 5: Large mock data files bloating bundle
- **Severity**: Low
- **Status**: ✅ Mitigated
- **Mitigation**: Build phase script strips MockData in Release builds

### Risk 6: Mock filename collisions
- **Severity**: Low
- **Status**: ✅ Mitigated
- **Mitigation**: Registry pattern with explicit mappings prevents collisions

### Risk 7: Missing PATCH method
- **Severity**: Low
- **Status**: ✅ Clarified
- **Mitigation**: HTTPMethod.patch exists; only convenience method needs adding

---

## Success Criteria

- [ ] APIClientProtocol created with all HTTP methods + void variants
- [ ] Shared types (HTTPMethod, APIError) moved to protocol file
- [ ] APIClient conforms to protocol with PATCH method added
- [ ] MockAPIClient fully implements protocol with registry
- [ ] MockResponseRegistry handles URL patterns correctly
- [ ] AppConfig manages mockMode with DEBUG guard
- [ ] APIClientFactory.shared returns cached singleton (not new instances)
- [ ] MockDataLoader provides helpful error messages
- [ ] Mock data directory created with examples
- [ ] MockData added to Xcode project and appears in bundle
- [ ] Build phase script strips MockData in Release
- [ ] Documentation written (README + EXAMPLES)
- [ ] App startup logs current mode
- [ ] Can toggle between mock/real mode (requires app restart)
- [ ] Mock mode forced OFF in Release builds
- [ ] No compilation errors or warnings
- [ ] Release build verified without MockData

---

## Implementation Order Summary

**Prerequisites** (Optional):
- Phase 0: Create test target (if testing desired)

**Critical Path** (Must be done in order):
1. Create APIClientProtocol with shared types
2. Create AppConfig
3. Update APIClient to conform
4. Create MockResponseRegistry
5. Create MockDataLoader
6. Create MockAPIClient
7. Create APIClientFactory (with cached singleton)

**Xcode Integration** (Critical for functionality):
8. Create MockData directory
9. Add MockData to Xcode project
10. Create sample mock files
11. Add build phase script

**Finalization**:
12. Initialize in WellPlateApp
13. Write documentation
14. Write examples
15. (Optional) Write tests

**Total Estimated Time**: 5-7 hours for full implementation and testing

---

## Future Enhancements

### Phase 2 Features (Post-MVP)
- Debug menu SwiftUI view to toggle mock mode
- Multiple mock scenarios (empty, error, full datasets)
- Configurable network delay
- Request/response logging
- Response recording from real API
- Partial mocking (some endpoints real, some mock)

### Advanced Features
- Caching layer (CachingAPIClient)
- Retry logic with exponential backoff
- Request interceptors for auth/logging
- Analytics integration
- Offline mode detection

---

## Appendix: Complete File Checklist

### ✅ New Files to Create

**Networking Layer:**
- [ ] `WellPlate/Networking/APIClientProtocol.swift` (with HTTPMethod, APIError)
- [ ] `WellPlate/Networking/MockResponseRegistry.swift`
- [ ] `WellPlate/Networking/MockDataLoader.swift`
- [ ] `WellPlate/Networking/MockAPIClient.swift`
- [ ] `WellPlate/Networking/APIClientFactory.swift`

**Configuration:**
- [ ] `WellPlate/Core/AppConfig.swift`

**Mock Data:**
- [ ] `WellPlate/Resources/MockData/.gitkeep`
- [ ] `WellPlate/Resources/MockData/README.md`
- [ ] `WellPlate/Resources/MockData/mock_health_check.json`
- [ ] `WellPlate/Resources/MockData/mock_users_list.json`
- [ ] `WellPlate/Resources/MockData/mock_user_detail.json`

**Documentation:**
- [ ] `WellPlate/Networking/README.md`
- [ ] `WellPlate/Networking/EXAMPLES.md`

### ✅ Files to Modify

- [ ] `WellPlate/Networking/APIClient.swift`
  - Remove HTTPMethod and APIError enums
  - Add protocol conformance
  - Add PATCH convenience method
  - Add void-returning variants

- [ ] `WellPlate/App/WellPlateApp.swift`
  - Add config initialization in init()
  - Add bundle verification logging

### ✅ Xcode Project Changes

- [ ] Add MockData folder to project as folder reference
- [ ] Verify MockData in Build Phases → Copy Bundle Resources
- [ ] Add "Strip Mock Data in Release" run script phase
- [ ] (Optional) Create WellPlateTests target

### ✅ Test Files to Create (Optional)

- [ ] `WellPlateTests/Networking/APIClientProtocolTests.swift`
- [ ] `WellPlateTests/Networking/MockAPIClientTests.swift`
- [ ] `WellPlateTests/Networking/APIClientFactoryTests.swift`
- [ ] `WellPlateTests/Networking/MockDataLoaderTests.swift`
- [ ] `WellPlateTests/Networking/MockResponseRegistryTests.swift`

---

## References

- Original Plan: `/Users/hariom/Desktop/WellPlate/Docs/02_Planning/Specs/260216-APIClient-Mock-Configuration.md`
- Audit Report: `/Users/hariom/Desktop/WellPlate/Docs/05_Audits/Code/APIClient-Mock-Configuration-audit.md`
- Current APIClient: `/Users/hariom/Desktop/WellPlate/WellPlate/Networking/APIClient.swift`
- Brainstorming Document: `/Users/hariom/Desktop/WellPlate/Docs/02_Planning/Brainstorming/APIClient-Mock-Configuration.md`
