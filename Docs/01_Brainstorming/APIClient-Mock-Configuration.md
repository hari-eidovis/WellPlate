# Brainstorm: APIClient with Mock/Real Mode Switching

**Date**: 2026-02-16
**Status**: Draft

## Problem Statement
We need to enhance the existing APIClient to support a configurable mock mode that allows switching between real API calls and mock responses. This is essential for:
- Development without backend dependency
- Testing with predictable data
- Demo and presentation scenarios
- Offline development

## Core Requirements
- Support all HTTP methods (GET, POST, PUT, DELETE, PATCH) ✓ (already exists)
- Ability to switch between mock and real API calls via configuration
- Configuration should be easily changeable (ideally without recompiling)
- MockAPIClient should mimic the real APIClient interface
- Maintain type safety and async/await patterns
- Should integrate seamlessly with existing codebase

## Constraints
- Must work with SwiftUI and modern Swift concurrency
- Existing APIClient uses singleton pattern
- Should not require major refactoring of existing code
- Need to maintain clean architecture principles
- Mock data needs to be maintainable and realistic

---

## Approach 1: Protocol-Based Dependency Injection (RECOMMENDED)

**Summary**: Create an `APIClientProtocol` that both real and mock implementations conform to, use a factory to provide the appropriate instance based on configuration.

**Architecture**:
```swift
protocol APIClientProtocol {
    func request<T: Decodable>(...) async throws -> T
    func get<T: Decodable>(...) async throws -> T
    func post<T: Decodable>(...) async throws -> T
    // ... other methods
}

class APIClient: APIClientProtocol { /* existing implementation */ }
class MockAPIClient: APIClientProtocol { /* mock implementation */ }

class APIClientFactory {
    static func create() -> APIClientProtocol {
        return AppConfig.shared.mockMode ? MockAPIClient() : APIClient.shared
    }
}
```

**Configuration Setup**:
```swift
class AppConfig {
    static let shared = AppConfig()

    // Can be loaded from UserDefaults, plist, or environment
    var mockMode: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "mockMode")
        #else
        return false
        #endif
    }
}
```

**Pros**:
- Clean separation of concerns
- Highly testable - can inject mock in unit tests
- Follows Dependency Inversion Principle
- Easy to add new implementations (e.g., CachingAPIClient)
- Can switch at runtime via UserDefaults
- ViewModels depend on protocol, not concrete implementation

**Cons**:
- Requires refactoring existing code to use protocol instead of singleton
- More files to maintain (protocol, factory, config)
- Slightly more boilerplate
- Need to update all existing `APIClient.shared` references

**Complexity**: Medium
**Risk**: Low
**Testability**: Excellent

---

## Approach 2: Environment-Based Build Configuration

**Summary**: Use Xcode build configurations and conditional compilation to switch between implementations at compile time.

**Architecture**:
```swift
// AppConfig.swift
struct AppConfig {
    #if MOCK
    static let mockMode = true
    #else
    static let mockMode = false
    #endif
}

// APIClientProvider.swift
class APIClientProvider {
    static var shared: APIClientProtocol {
        #if MOCK
        return MockAPIClient.shared
        #else
        return APIClient.shared
        #endif
    }
}
```

**Configuration Setup**:
- Create build configurations: Debug, Debug-Mock, Release
- Add custom flags in build settings
- Use .xcconfig files for environment-specific settings

**Pros**:
- Zero runtime overhead - decided at compile time
- Simple to understand and implement
- Clear separation between environments
- No configuration files needed
- Works well with CI/CD pipelines

**Cons**:
- Cannot switch modes without recompiling
- Need to maintain multiple build configurations
- Less flexible for developers who want to toggle quickly
- Can't enable mock mode in production builds (even for debugging)
- Harder to test both modes in same test run

**Complexity**: Low
**Risk**: Low
**Testability**: Good

---

## Approach 3: Strategy Pattern with Runtime Switching

**Summary**: APIClient acts as a context that delegates to either a real or mock strategy, switchable at runtime.

**Architecture**:
```swift
protocol NetworkingStrategy {
    func execute<T: Decodable>(request: URLRequest) async throws -> T
}

class RealNetworkingStrategy: NetworkingStrategy { /* URLSession implementation */ }
class MockNetworkingStrategy: NetworkingStrategy { /* mock data implementation */ }

class APIClient {
    static let shared = APIClient()
    private var strategy: NetworkingStrategy

    init() {
        self.strategy = AppConfig.shared.mockMode
            ? MockNetworkingStrategy()
            : RealNetworkingStrategy()
    }

    func switchMode(mockMode: Bool) {
        self.strategy = mockMode ? MockNetworkingStrategy() : RealNetworkingStrategy()
    }

    func request<T: Decodable>(...) async throws -> T {
        return try await strategy.execute(request: urlRequest)
    }
}
```

**Pros**:
- Can switch at runtime without restarting app
- Useful for in-app settings/debug menu
- Maintains singleton pattern
- Minimal changes to existing call sites
- Great for manual testing and demos

**Cons**:
- Adds layer of indirection
- Strategy switching could cause inconsistent state mid-flow
- Not thread-safe without additional locking
- May confuse developers - which mode is active?

**Complexity**: Medium
**Risk**: Medium (potential for inconsistent state)
**Testability**: Good

---

## Approach 4: URLProtocol Interception

**Summary**: Use URLProtocol to intercept network requests at URLSession level and return mock data based on URL patterns.

**Architecture**:
```swift
class MockURLProtocol: URLProtocol {
    static var mockResponses: [String: (Data, HTTPURLResponse)] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        return AppConfig.shared.mockMode
    }

    override func startLoading() {
        if let mockResponse = MockURLProtocol.mockResponses[request.url?.absoluteString ?? ""] {
            client?.urlProtocol(self, didReceive: mockResponse.1, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mockResponse.0)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

// Register in AppDelegate or App init
URLProtocol.registerClass(MockURLProtocol.self)
```

**Pros**:
- Zero changes to APIClient code
- Can mock network layer for entire app
- Works with third-party networking libraries too
- Great for integration testing
- Can simulate network conditions (latency, errors)

**Cons**:
- More complex to set up and understand
- Harder to debug - interception is "invisible"
- Mock data management is less intuitive
- Requires URL-based routing of mocks
- Can interfere with other URLProtocols

**Complexity**: High
**Risk**: Medium
**Testability**: Excellent (for integration tests)

---

## Approach 5: Factory Pattern with Simple Configuration File

**Summary**: Use a simple factory with a plist or JSON configuration file to determine which client to use.

**Architecture**:
```swift
// Config.plist
// mockMode: true/false

class AppConfig {
    static let shared = AppConfig()
    let mockMode: Bool

    private init() {
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
            mockMode = dict["mockMode"] as? Bool ?? false
        } else {
            mockMode = false
        }
    }
}

enum APIClientFactory {
    static func makeClient() -> APIClientProtocol {
        return AppConfig.shared.mockMode ? MockAPIClient() : APIClient()
    }
}
```

**Pros**:
- Very simple to understand
- Configuration in one place
- No need for build configurations
- Easy to change by editing plist
- Works well for small teams

**Cons**:
- Configuration bundled in app (can't change without rebuild)
- Risk of committing wrong config value
- Not suitable for multiple environments (dev/staging/prod)
- Can't switch at runtime

**Complexity**: Low
**Risk**: Low
**Testability**: Good

---

## Configuration File Approaches

### Option A: UserDefaults (Runtime Configurable)
```swift
extension UserDefaults {
    var mockMode: Bool {
        get { bool(forKey: "app.mockMode") }
        set { set(newValue, forKey: "app.mockMode") }
    }
}
```
- ✅ Can change at runtime
- ✅ Persists between launches
- ✅ Can add debug menu to toggle
- ❌ Might accidentally persist in production

### Option B: Plist Configuration File
```swift
// Config.plist with mockMode key
let mockMode = Bundle.main.object(forInfoDictionaryKey: "MockMode") as? Bool ?? false
```
- ✅ Simple and standard iOS practice
- ✅ Different plists for different targets
- ❌ Requires rebuild to change
- ❌ Easy to commit wrong value

### Option C: Build Configuration + Launch Arguments
```swift
#if DEBUG
let mockMode = UserDefaults.standard.bool(forKey: "mockMode")
    || ProcessInfo.processInfo.arguments.contains("--mock")
#else
let mockMode = false
#endif
```
- ✅ Great for UI testing
- ✅ Can enable via Xcode scheme
- ✅ Forced off in production
- ❌ Only works with Xcode launch

### Option D: Environment Variables (12-Factor App Style)
```swift
let mockMode = ProcessInfo.processInfo.environment["MOCK_MODE"] == "true"
```
- ✅ Follows 12-factor app principles
- ✅ Easy in CI/CD
- ❌ Harder to set on iOS
- ❌ Not persistent

---

## Mock Data Management Strategies

### Strategy 1: Inline Mock Data
```swift
class MockAPIClient {
    func getUser(id: String) async throws -> User {
        return User(id: "123", name: "John Doe", email: "john@example.com")
    }
}
```
- Simple but not scalable

### Strategy 2: JSON Files in Bundle
```swift
class MockDataLoader {
    static func load<T: Decodable>(_ filename: String) throws -> T {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            throw MockError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
```
- Realistic data structure
- Easy to maintain and update
- Can share with backend team

### Strategy 3: Mock Data Generators
```swift
class MockDataGenerator {
    static func randomUser() -> User {
        User(
            id: UUID().uuidString,
            name: ["Alice", "Bob", "Charlie"].randomElement()!,
            email: "\(Int.random(in: 1000...9999))@example.com"
        )
    }
}
```
- Good for testing edge cases
- Dynamic data for stress testing

---

## Edge Cases to Consider

- [ ] What happens when switching modes mid-request?
- [ ] How to handle mock data versioning with API changes?
- [ ] Should mock mode be visible in UI (debug indicator)?
- [ ] How to mock error scenarios (network failures, timeouts)?
- [ ] What about authentication tokens in mock mode?
- [ ] How to ensure mock data stays in sync with real API contracts?
- [ ] Should we support partial mocking (some endpoints real, some mock)?
- [ ] How to handle mock data for paginated responses?
- [ ] What about file uploads/downloads in mock mode?
- [ ] Should mock responses have artificial delays to simulate network latency?

---

## Open Questions

- [ ] Do we need runtime switching or is compile-time enough?
- [ ] Should mock mode be available in production builds (for demos)?
- [ ] How do we prevent accidentally shipping with mockMode=true?
- [ ] Where should mock JSON files be stored? (Bundle, Documents, or generated?)
- [ ] Should we log/indicate when in mock mode for debugging?
- [ ] Do we need different mock datasets (empty state, error state, full state)?
- [ ] Should mock mode work with UITests out of the box?

---

## Recommendation

**Go with Approach 1: Protocol-Based Dependency Injection** combined with **Config Option A: UserDefaults (with DEBUG guard)**

**Rationale**:
1. **Best for testing**: Protocol-based design makes unit testing trivial
2. **Flexible**: Can switch at runtime via debug menu
3. **Safe**: Guard mockMode with #if DEBUG to prevent production issues
4. **Scalable**: Easy to add more implementations (caching, offline, etc.)
5. **Clean architecture**: Follows SOLID principles
6. **Future-proof**: As app grows, dependency injection will pay dividends

**Implementation Plan**:
1. Create `APIClientProtocol` extracting methods from existing `APIClient`
2. Make `APIClient` conform to protocol (minimal changes)
3. Create `AppConfig` with mockMode using UserDefaults (DEBUG only)
4. Create `MockAPIClient` conforming to protocol
5. Create `APIClientFactory` to provide appropriate instance
6. Update app initialization to use factory
7. Add debug menu toggle for mockMode (optional)
8. Create JSON mock data files in Resources/MockData/
9. Implement MockDataLoader utility

**Mock Data Strategy**: JSON files in bundle (Strategy 2)
- Easy to maintain
- Realistic data structure
- Version controlled
- Can be used for UITests

---

## Alternative: Quick Win Hybrid Approach

If we want something simpler to start with, combine:
- **Approach 2 (Build Config)** for environment selection
- **Strategy 2 (JSON Files)** for mock data
- Add **Approach 1 (Protocol)** later when needed

This gives us:
- ✅ Quick to implement
- ✅ Safe (compile-time only)
- ✅ Can evolve to full DI later
- ❌ Less flexible initially

---

## Research References
- Apple URLProtocol documentation for network interception
- Swift protocol-oriented programming best practices
- 12-factor app configuration methodology
- Existing APIClient.swift implementation at `/Users/hariom/Desktop/WellPlate/WellPlate/Networking/APIClient.swift`
