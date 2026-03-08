# Networking Layer - Code Examples

Practical examples for using the WellPlate networking layer.

## 📚 Table of Contents

- [Basic GET Request](#basic-get-request)
- [POST with Request Body](#post-with-request-body)
- [PUT/PATCH Updates](#putpatch-updates)
- [DELETE Operations](#delete-operations)
- [Error Handling](#error-handling)
- [Custom Headers](#custom-headers)
- [ViewModel Integration](#viewmodel-integration)
- [SwiftUI Integration](#swiftui-integration)
- [Testing](#testing)
- [Adding New Mock Endpoints](#adding-new-mock-endpoints)

---

## Basic GET Request

### Fetch Single Resource

```swift
import Foundation

func fetchUser(id: String) async throws -> User {
    let url = URL(string: "https://api.example.com/users/\(id)")!

    let user = try await APIClientFactory.shared.get(
        url: url,
        headers: nil,
        responseType: User.self
    )

    return user
}
```

### Fetch List of Resources

```swift
func fetchAllUsers() async throws -> [User] {
    let url = URL(string: "https://api.example.com/users")!

    let users = try await APIClientFactory.shared.get(
        url: url,
        headers: nil,
        responseType: [User].self
    )

    return users
}
```

---

## POST with Request Body

### Create New Resource

```swift
struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

func createUser(name: String, email: String) async throws -> User {
    let url = URL(string: "https://api.example.com/users")!

    let request = CreateUserRequest(name: name, email: email)
    let body = try APIClientFactory.shared.encodeBody(request)

    let createdUser = try await APIClientFactory.shared.post(
        url: url,
        headers: nil,
        body: body,
        responseType: User.self
    )

    return createdUser
}
```

### POST with JSON Dictionary

```swift
func login(email: String, password: String) async throws -> AuthResponse {
    let url = URL(string: "https://api.example.com/auth/login")!

    let credentials = ["email": email, "password": password]
    let body = try JSONEncoder().encode(credentials)

    let response = try await APIClientFactory.shared.post(
        url: url,
        headers: nil,
        body: body,
        responseType: AuthResponse.self
    )

    return response
}
```

---

## PUT/PATCH Updates

### Full Update (PUT)

```swift
struct UpdateUserRequest: Codable {
    let name: String
    let email: String
    let phone: String
}

func updateUser(id: String, name: String, email: String, phone: String) async throws -> User {
    let url = URL(string: "https://api.example.com/users/\(id)")!

    let update = UpdateUserRequest(name: name, email: email, phone: phone)
    let body = try APIClientFactory.shared.encodeBody(update)

    let updated = try await APIClientFactory.shared.put(
        url: url,
        headers: nil,
        body: body,
        responseType: User.self
    )

    return updated
}
```

### Partial Update (PATCH)

```swift
struct PatchUserRequest: Codable {
    let name: String?
    let phone: String?
}

func patchUser(id: String, name: String? = nil, phone: String? = nil) async throws -> User {
    let url = URL(string: "https://api.example.com/users/\(id)")!

    let patch = PatchUserRequest(name: name, phone: phone)
    let body = try APIClientFactory.shared.encodeBody(patch)

    let updated = try await APIClientFactory.shared.patch(
        url: url,
        headers: nil,
        body: body,
        responseType: User.self
    )

    return updated
}
```

### PUT with No Response (void)

```swift
func updateSettings(_ settings: Settings) async throws {
    let url = URL(string: "https://api.example.com/settings")!
    let body = try APIClientFactory.shared.encodeBody(settings)

    // Use void variant when no response expected
    try await APIClientFactory.shared.putVoid(
        url: url,
        headers: nil,
        body: body
    )
}
```

---

## DELETE Operations

### DELETE with Response

```swift
struct DeleteResponse: Codable {
    let success: Bool
    let message: String
}

func deleteUser(id: String) async throws -> DeleteResponse {
    let url = URL(string: "https://api.example.com/users/\(id)")!

    let response = try await APIClientFactory.shared.delete(
        url: url,
        headers: nil,
        responseType: DeleteResponse.self
    )

    return response
}
```

### DELETE with No Response (204 No Content)

```swift
func deleteUser(id: String) async throws {
    let url = URL(string: "https://api.example.com/users/\(id)")!

    // Use void variant for 204 No Content responses
    try await APIClientFactory.shared.deleteVoid(
        url: url,
        headers: nil
    )
}
```

---

## Error Handling

### Comprehensive Error Handling

```swift
func fetchUserWithErrorHandling(id: String) async -> Result<User, String> {
    let url = URL(string: "https://api.example.com/users/\(id)")!

    do {
        let user = try await APIClientFactory.shared.get(
            url: url,
            headers: nil,
            responseType: User.self
        )
        return .success(user)

    } catch APIError.serverError(let statusCode, let message) {
        switch statusCode {
        case 404:
            return .failure("User not found")
        case 401:
            return .failure("Unauthorized - please log in")
        case 500...599:
            return .failure("Server error: \(message ?? "Unknown")")
        default:
            return .failure("Request failed with status \(statusCode)")
        }

    } catch APIError.networkError(let error) {
        return .failure("Network error: \(error.localizedDescription)")

    } catch APIError.decodingError(let error) {
        return .failure("Invalid response format: \(error.localizedDescription)")

    } catch {
        return .failure("Unknown error: \(error.localizedDescription)")
    }
}
```

### Retry Logic

```swift
func fetchWithRetry<T: Decodable>(
    url: URL,
    maxRetries: Int = 3,
    responseType: T.Type
) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxRetries {
        do {
            return try await APIClientFactory.shared.get(
                url: url,
                headers: nil,
                responseType: responseType
            )
        } catch {
            lastError = error
            if attempt < maxRetries {
                // Wait before retrying (exponential backoff)
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000 // nanoseconds
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    throw lastError ?? APIError.noData
}
```

---

## Custom Headers

### Authentication Token

```swift
func fetchProtectedResource(token: String) async throws -> Resource {
    let url = URL(string: "https://api.example.com/protected")!

    let headers = [
        "Authorization": "Bearer \(token)"
    ]

    let resource = try await APIClientFactory.shared.get(
        url: url,
        headers: headers,
        responseType: Resource.self
    )

    return resource
}
```

### Multiple Custom Headers

```swift
func fetchWithCustomHeaders() async throws -> Response {
    let url = URL(string: "https://api.example.com/data")!

    let headers = [
        "Authorization": "Bearer \(token)",
        "X-API-Version": "2.0",
        "X-Client-Platform": "iOS",
        "X-Request-ID": UUID().uuidString
    ]

    let response = try await APIClientFactory.shared.get(
        url: url,
        headers: headers,
        responseType: Response.self
    )

    return response
}
```

---

## ViewModel Integration

### Complete ViewModel Example

```swift
import Foundation
import Combine

@MainActor
class UserListViewModel: ObservableObject {
    // MARK: - Properties

    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: APIClientProtocol

    // MARK: - Initialization

    init(apiClient: APIClientProtocol = APIClientFactory.shared) {
        self.apiClient = apiClient
    }

    // MARK: - Methods

    func loadUsers() async {
        isLoading = true
        errorMessage = nil

        do {
            let url = URL(string: "https://api.example.com/users")!
            let fetchedUsers = try await apiClient.get(
                url: url,
                headers: nil,
                responseType: [User].self
            )

            self.users = fetchedUsers
            self.isLoading = false

        } catch {
            self.errorMessage = "Failed to load users: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    func createUser(name: String, email: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let url = URL(string: "https://api.example.com/users")!
            let request = CreateUserRequest(name: name, email: email)
            let body = try apiClient.encodeBody(request)

            let newUser = try await apiClient.post(
                url: url,
                headers: nil,
                body: body,
                responseType: User.self
            )

            self.users.append(newUser)
            self.isLoading = false

        } catch {
            self.errorMessage = "Failed to create user: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    func deleteUser(_ user: User) async {
        guard let url = URL(string: "https://api.example.com/users/\(user.id)") else {
            errorMessage = "Invalid user ID"
            return
        }

        do {
            try await apiClient.deleteVoid(url: url, headers: nil)
            self.users.removeAll { $0.id == user.id }
        } catch {
            self.errorMessage = "Failed to delete user: \(error.localizedDescription)"
        }
    }
}
```

---

## SwiftUI Integration

### List View

```swift
import SwiftUI

struct UserListView: View {
    @StateObject private var viewModel = UserListViewModel()

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading users...")
                } else if let error = viewModel.errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await viewModel.loadUsers()
                            }
                        }
                    }
                } else {
                    List {
                        ForEach(viewModel.users) { user in
                            UserRow(user: user)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let user = viewModel.users[index]
                                Task {
                                    await viewModel.deleteUser(user)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Users")
            .task {
                await viewModel.loadUsers()
            }
            .refreshable {
                await viewModel.loadUsers()
            }
        }
    }
}
```

---

## Testing

### Mock Client for Testing

```swift
import XCTest
@testable import WellPlate

class UserListViewModelTests: XCTestCase {

    func testLoadUsers() async throws {
        // Use MockAPIClient for predictable testing
        let mockClient = MockAPIClient.shared
        let viewModel = UserListViewModel(apiClient: mockClient)

        // Load users (will use mock data)
        await viewModel.loadUsers()

        // Assertions
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertGreaterThan(viewModel.users.count, 0)
    }

    func testCreateUser() async throws {
        let mockClient = MockAPIClient.shared
        let viewModel = UserListViewModel(apiClient: mockClient)

        let initialCount = viewModel.users.count
        await viewModel.createUser(name: "Test User", email: "test@example.com")

        XCTAssertEqual(viewModel.users.count, initialCount + 1)
        XCTAssertNil(viewModel.errorMessage)
    }
}
```

### Custom Test Client

```swift
class TestAPIClient: APIClientProtocol {
    var mockData: Any?
    var shouldFail: Bool = false
    var errorToThrow: Error = APIError.noData

    func get<T: Decodable>(url: URL, headers: [String: String]?, responseType: T.Type) async throws -> T {
        if shouldFail {
            throw errorToThrow
        }
        guard let data = mockData as? T else {
            throw APIError.decodingError(NSError(domain: "Test", code: 0))
        }
        return data
    }

    // Implement other protocol methods similarly...
}

// In tests:
func testErrorHandling() async {
    let testClient = TestAPIClient()
    testClient.shouldFail = true
    testClient.errorToThrow = APIError.serverError(statusCode: 404, message: "Not found")

    let viewModel = UserListViewModel(apiClient: testClient)
    await viewModel.loadUsers()

    XCTAssertNotNil(viewModel.errorMessage)
    XCTAssertTrue(viewModel.errorMessage!.contains("404"))
}
```

---

## Adding New Mock Endpoints

### Step 1: Create Mock JSON File

Create `Resources/MockData/mock_posts_list.json`:

```json
[
  {
    "id": "1",
    "title": "First Post",
    "body": "This is the first post",
    "createdAt": "2026-01-01T00:00:00Z"
  },
  {
    "id": "2",
    "title": "Second Post",
    "body": "This is the second post",
    "createdAt": "2026-01-02T00:00:00Z"
  }
]
```

### Step 2: Register URL Mapping

Edit `MockResponseRegistry.swift`, add in `setupDefaultMappings()`:

```swift
register(path: "/api/posts", method: .get, mockFile: "mock_posts_list")
register(path: "/api/posts/{id}", method: .get, mockFile: "mock_post_detail")
```

### Step 3: Use in Code

```swift
func fetchPosts() async throws -> [Post] {
    let url = URL(string: "https://api.example.com/api/posts")!

    let posts = try await APIClientFactory.shared.get(
        url: url,
        headers: nil,
        responseType: [Post].self
    )

    return posts
}
```

### Step 4: Verify

Run the app with mock mode enabled and check console:

```
🎭 [MockAPIClient] GET https://api.example.com/api/posts
✅ [MockRegistry] Exact match: GET /api/posts → mock_posts_list.json
📦 [MockDataLoader] Loading: mock_posts_list.json
✅ [MockDataLoader] Successfully loaded mock_posts_list.json
✅ [MockAPIClient] Request completed successfully
```

---

## 💡 Tips & Best Practices

1. **Always use dependency injection** - Pass `APIClientProtocol` to ViewModels for testability
2. **Handle all error cases** - Don't just catch generic errors
3. **Use void variants** - For 204 No Content or when response body isn't needed
4. **Add loading states** - Always show user when requests are in progress
5. **Implement retry logic** - For transient network failures
6. **Cache responses** - Consider caching frequently accessed data
7. **Use async/await** - Avoid completion handlers, embrace Swift concurrency
8. **Test with mock data** - Use MockAPIClient for predictable tests
9. **Document endpoints** - Keep README updated when adding new endpoints
10. **Version your API** - Use headers or URL versioning for API changes

---

## 📚 Related Documentation

- `README.md` - Full networking layer documentation
- `Resources/MockData/README.md` - Mock data guidelines
- `APIClientProtocol.swift` - Protocol definition
- `CHECKLIST-APIClient-Implementation.md` - Implementation checklist
