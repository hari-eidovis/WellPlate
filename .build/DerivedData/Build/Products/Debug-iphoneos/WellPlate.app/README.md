# Mock Data Files

This directory contains JSON files used by `MockAPIClient` for offline development and testing.

## 📁 Directory Purpose

- Store mock API response data as JSON files
- Enable development without backend dependency
- Provide predictable data for testing
- Support offline demos and presentations

## 📝 Naming Convention

**Pattern**: `mock_<description>_<method>.json` or `mock_<description>.json`

**Examples**:
- `mock_health_check.json` - Health check endpoint
- `mock_users_list.json` - List of users (GET /api/users)
- `mock_user_detail.json` - Single user (GET /api/users/{id})
- `mock_user_create.json` - Created user response (POST /api/users)
- `mock_user_delete.json` - Delete confirmation (DELETE /api/users/{id})

## 🔧 How to Add New Mock Data

### 1. Create JSON File

Create a new `.json` file in this directory with valid JSON data:

```json
{
  "id": "123",
  "name": "John Doe",
  "email": "john@example.com",
  "createdAt": "2026-01-01T00:00:00Z"
}
```

### 2. Register URL Mapping

Open `MockResponseRegistry.swift` and add mapping in `setupDefaultMappings()`:

```swift
register(path: "/api/users/{id}", method: .get, mockFile: "mock_user_detail")
```

### 3. Add to Xcode Project

**IMPORTANT**: If Xcode doesn't auto-detect the file:
1. Right-click on `MockData` folder in Xcode
2. Select "Add Files to MockData..."
3. Select your new `.json` file
4. Ensure it's added to the WellPlate target

### 4. Verify Bundle Inclusion

- Build and run the app
- Check console logs for successful file loading
- If file not found, verify in:
  - Xcode → WellPlate target → Build Phases → Copy Bundle Resources
  - MockData folder should appear with all JSON files

## 📋 Current Mock Files

- `mock_health_check.json` - API health check response
- `mock_users_list.json` - Example user list
- `mock_user_detail.json` - Example single user
- `mock_user_create.json` - Example created user response
- `mock_user_delete.json` - Example delete confirmation

## ⚠️ Important Notes

1. **JSON Validity**: All files must contain valid JSON
2. **Model Matching**: JSON structure must match your Codable models
3. **Date Format**: Use ISO8601 format for dates: `"2026-01-01T00:00:00Z"`
4. **Xcode Integration**: Files must be in Copy Bundle Resources, not just filesystem
5. **Release Builds**: MockData is automatically stripped from Release builds

## 🧪 Testing Mock Data

```swift
// In your ViewModel or test
let url = URL(string: "https://api.example.com/users/123")!
let user = try await apiClient.get(url: url, headers: nil, responseType: User.self)
```

Console output will show:
```
🎭 [MockAPIClient] GET https://api.example.com/users/123
✅ [MockRegistry] Pattern match: /api/users/{id} matched /users/123 → mock_user_detail.json
📦 [MockDataLoader] Loading: mock_user_detail.json
✅ [MockDataLoader] Successfully loaded mock_user_detail.json
```

## 🔄 Syncing with Backend Team

1. Ask backend team for sample API responses
2. Save responses as `.json` files in this directory
3. Register mappings in `MockResponseRegistry.swift`
4. Update this README with new files

## 🐛 Troubleshooting

### "Mock data file not found"
- Verify file exists in filesystem
- Check file is added to Xcode project
- Verify file in Copy Bundle Resources
- Check filename matches registry mapping (without .json)

### "Failed to decode mock data"
- Validate JSON syntax using jsonlint.com
- Ensure JSON matches your Codable model structure
- Check date formats are ISO8601

### MockData folder not in bundle
- Ensure folder added as "folder reference" (blue icon, not yellow)
- Re-add folder to project if necessary
- Clean build folder (Cmd+Shift+K) and rebuild

## 📚 Related Files

- `MockAPIClient.swift` - Mock API client implementation
- `MockDataLoader.swift` - JSON file loading utility
- `MockResponseRegistry.swift` - URL → filename mapping
- `APIClientFactory.swift` - Factory for creating clients
- `AppConfig.swift` - Mock mode configuration
