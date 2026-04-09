# Implementation Checklist: APIClient Mock/Real Mode

**Plan Version**: 2.0 (Revised)
**Date Started**: _____________
**Date Completed**: _____________

## 📋 Quick Start Guide

1. Follow checklist in order (phases build on each other)
2. Check off ✅ each item as completed
3. Verify each phase before moving to next
4. Reference detailed plan: `260216-APIClient-Mock-Configuration-v2.md`

---

## Phase 0: Prerequisites (Optional)

### Test Infrastructure Setup
- [ ] **0a. Create Test Target** (Optional - can skip for now)
  - [ ] File → New → Target → Unit Testing Bundle
  - [ ] Name: WellPlateTests
  - [ ] Create directory structure
  - [ ] OR skip this and add tests later

**Phase 0 Complete**: ☐ (or skipped ☐)

---

## Phase 1: Foundation - Protocol & Configuration

### 1. Create APIClientProtocol.swift
- [ ] **Create file**: `WellPlate/Networking/APIClientProtocol.swift`
- [ ] Add `HTTPMethod` enum (move from APIClient.swift)
- [ ] Add `APIError` enum (move from APIClient.swift)
- [ ] Add `EmptyResponse` struct
- [ ] Define `APIClientProtocol` with:
  - [ ] `request<T: Decodable>` method
  - [ ] `requestVoid` method
  - [ ] GET, POST, PUT, DELETE, PATCH convenience methods
  - [ ] `deleteVoid` and `putVoid` methods
  - [ ] `encodeBody` helper
- [ ] Add file to Xcode project

### 2. Create AppConfig.swift
- [ ] **Create directory**: `WellPlate/Core/` (if doesn't exist)
- [ ] **Create file**: `WellPlate/Core/AppConfig.swift`
- [ ] Implement singleton pattern
- [ ] Add `mockMode` property with:
  - [ ] UserDefaults getter/setter
  - [ ] `#if DEBUG` guard
  - [ ] Default to `true` in DEBUG for convenience
- [ ] Add `logCurrentMode()` method
- [ ] Add file to Xcode project

### 3. Update APIClient.swift
- [ ] **Open file**: `WellPlate/Networking/APIClient.swift`
- [ ] Remove `enum HTTPMethod` (now in protocol file)
- [ ] Remove `enum APIError` (now in protocol file)
- [ ] Add `import Foundation` at top
- [ ] Add `: APIClientProtocol` to class declaration
- [ ] Add PATCH convenience method:
  ```swift
  func patch<T: Decodable>(url: URL, headers: [String: String]?, body: Data?, responseType: T.Type) async throws -> T
  ```
- [ ] Add void-returning variants:
  - [ ] `requestVoid` method
  - [ ] `deleteVoid` method
  - [ ] `putVoid` method
- [ ] Compile and verify no errors

**Phase 1 Verification**:
- [ ] ✅ Project compiles without errors
- [ ] ✅ APIClient conforms to APIClientProtocol
- [ ] ✅ All HTTP methods available

**Phase 1 Complete**: ☐

---

## Phase 2: Mock Infrastructure

### 4. Create MockResponseRegistry.swift
- [ ] **Create file**: `WellPlate/Networking/MockResponseRegistry.swift`
- [ ] Implement singleton pattern
- [ ] Add `URLPattern` struct
- [ ] Add `register` method for URL patterns
- [ ] Add `mockFile(for:method:)` lookup method
- [ ] Add `matchesPattern` for dynamic URLs
- [ ] Add `generateDefaultFilename` fallback
- [ ] Add `setupDefaultMappings` with examples:
  - [ ] `/api/health` → `mock_health_check`
  - [ ] `/api/users` → `mock_users_list`
  - [ ] `/api/users/{id}` → `mock_user_detail`
- [ ] Add file to Xcode project

### 5. Create MockDataLoader.swift
- [ ] **Create file**: `WellPlate/Networking/MockDataLoader.swift`
- [ ] Add `MockDataError` enum
- [ ] Implement `load<T: Decodable>` method with:
  - [ ] Bundle resource lookup
  - [ ] Better error messages with file paths
  - [ ] JSON decoding with ISO8601 dates
  - [ ] DEBUG logging
- [ ] Implement `loadRawData` method
- [ ] Add file to Xcode project

### 6. Create MockAPIClient.swift
- [ ] **Create file**: `WellPlate/Networking/MockAPIClient.swift`
- [ ] Implement singleton pattern
- [ ] Add `: APIClientProtocol` conformance
- [ ] Implement `request<T>` using:
  - [ ] MockResponseRegistry for filename lookup
  - [ ] MockDataLoader for file loading
  - [ ] 0.5s simulated network delay
- [ ] Implement `requestVoid` method
- [ ] Add all convenience methods (GET, POST, PUT, DELETE, PATCH)
- [ ] Add void variants (deleteVoid, putVoid)
- [ ] Add `encodeBody` helper
- [ ] Add file to Xcode project

### 7. Create APIClientFactory.swift
- [ ] **Create file**: `WellPlate/Networking/APIClientFactory.swift`
- [ ] Create enum (not class)
- [ ] Add private cached `_shared` static let:
  ```swift
  private static let _shared: APIClientProtocol = { ... }()
  ```
- [ ] Check `AppConfig.shared.mockMode` in closure
- [ ] Return `MockAPIClient.shared` or `APIClient.shared`
- [ ] Add public `shared` property returning `_shared`
- [ ] Add DEBUG-only test helpers:
  - [ ] `_testInstance` property
  - [ ] `setTestInstance` method
  - [ ] `testable` property
- [ ] Add file to Xcode project

**Phase 2 Verification**:
- [ ] ✅ Project compiles without errors
- [ ] ✅ MockAPIClient conforms to APIClientProtocol
- [ ] ✅ Factory returns cached instance (not new every time)

**Phase 2 Complete**: ☐

---

## Phase 3: Xcode Integration & Mock Data

### 8. Create MockData Directory
- [ ] **Terminal**: `mkdir -p WellPlate/Resources/MockData`
- [ ] **Terminal**: `touch WellPlate/Resources/MockData/.gitkeep`
- [ ] Verify directory exists in Finder

### 9. Add MockData to Xcode Project ⚠️ CRITICAL
- [ ] Open `WellPlate.xcodeproj` in Xcode
- [ ] Right-click `Resources` folder in Project Navigator
- [ ] Select "Add Files to WellPlate..."
- [ ] Navigate to `WellPlate/Resources/MockData`
- [ ] ⚠️ **IMPORTANT**: Select "Create folder references" (blue folder icon)
- [ ] ⚠️ **IMPORTANT**: Check "WellPlate" target under "Add to targets"
- [ ] Click "Add"
- [ ] **Verify**: Go to WellPlate target → Build Phases → Copy Bundle Resources
- [ ] **Verify**: MockData folder should appear in the list
- [ ] **If not visible**: Drag MockData from Project Navigator to Copy Bundle Resources

### 10. Create Sample Mock Files
- [ ] **Create**: `WellPlate/Resources/MockData/README.md`
  - [ ] Add naming conventions
  - [ ] Add instructions for adding new mocks
- [ ] **Create**: `mock_health_check.json`
  ```json
  {
    "status": "ok",
    "timestamp": "2026-02-16T12:00:00Z",
    "version": "1.0.0"
  }
  ```
- [ ] **Create**: `mock_users_list.json` (example with array)
- [ ] **Create**: `mock_user_detail.json` (example with object)
- [ ] Verify files appear in Xcode Project Navigator
- [ ] **If not visible**: Right-click MockData → Add Files to "MockData"

### 11. Add Build Phase Script
- [ ] Open Xcode project
- [ ] Select WellPlate target
- [ ] Go to "Build Phases" tab
- [ ] Click "+" → "New Run Script Phase"
- [ ] Rename to: "Strip Mock Data in Release"
- [ ] Paste script:
  ```bash
  if [ "${CONFIGURATION}" = "Release" ]; then
      echo "🗑️  Removing MockData from Release build"
      rm -rf "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/MockData"
      echo "✅ MockData removed from bundle"
  else
      echo "ℹ️  MockData preserved in ${CONFIGURATION} build"
  fi
  ```
- [ ] Drag script phase to AFTER "Copy Bundle Resources"
- [ ] Test: Build in Release configuration and verify script runs

### 12. Update WellPlateApp.swift
- [ ] **Open**: `WellPlate/App/WellPlateApp.swift`
- [ ] Add `init()` method with:
  - [ ] `AppConfig.shared.logCurrentMode()`
  - [ ] `_ = APIClientFactory.shared` to trigger init
  - [ ] Bundle verification for MockData folder
- [ ] Compile and verify no errors

**Phase 3 Verification**:
- [ ] ✅ MockData folder visible in Xcode (blue icon)
- [ ] ✅ MockData in Build Phases → Copy Bundle Resources
- [ ] ✅ Build script added after Copy Bundle Resources
- [ ] ✅ Run app and see mock mode log in console
- [ ] ✅ Run app and see "MockData folder found in bundle" message

**Phase 3 Complete**: ☐

---

## Phase 4: Documentation & Testing

### 13. Create README.md
- [ ] **Create**: `WellPlate/Networking/README.md`
- [ ] Document:
  - [ ] Architecture overview
  - [ ] How to use APIClientFactory
  - [ ] How to toggle mock mode
  - [ ] How to add new endpoints
  - [ ] How to add new mock files
  - [ ] Troubleshooting guide
- [ ] Add file to Xcode project

### 14. Create EXAMPLES.md
- [ ] **Create**: `WellPlate/Networking/EXAMPLES.md`
- [ ] Add examples:
  - [ ] Basic ViewModel with APIClient
  - [ ] Dependency injection
  - [ ] Error handling
  - [ ] Void responses (DELETE, PUT)
  - [ ] Adding mock mappings
- [ ] Add file to Xcode project

**Phase 4 Complete**: ☐

---

## Final Verification & Testing

### Build & Run Tests
- [ ] ✅ Clean build (Cmd+Shift+K)
- [ ] ✅ Build succeeds without warnings
- [ ] ✅ Run app in DEBUG mode
- [ ] ✅ Check console for mock mode status
- [ ] ✅ Verify MockData bundle verification message

### Mock Mode Testing
- [ ] Test with mockMode = true:
  - [ ] Launch app
  - [ ] Verify "Mock Mode: ENABLED ✅" in console
  - [ ] Verify "MockAPIClient" initialized
  - [ ] Make an API call (if endpoints exist)
  - [ ] Verify mock data loads successfully

- [ ] Test with mockMode = false:
  - [ ] Run: `defaults write com.yourapp.WellPlate app.networking.mockMode -bool false`
  - [ ] Restart app
  - [ ] Verify "Mock Mode: DISABLED ❌" in console
  - [ ] Verify "Real APIClient" initialized

### Release Build Testing
- [ ] Switch to Release scheme
- [ ] Build project
- [ ] Check build logs for "Removing MockData from Release build"
- [ ] Verify no MockData in built app bundle
- [ ] Verify mockMode is forced to false

### Error Handling Testing
- [ ] Test missing mock file:
  - [ ] Enable mock mode
  - [ ] Call endpoint without mock mapping
  - [ ] Verify helpful error message with file path
- [ ] Test malformed JSON:
  - [ ] Create invalid JSON file
  - [ ] Call endpoint
  - [ ] Verify decoding error message

**All Tests Passing**: ☐

---

## Optional: Unit Tests (If Phase 0 Completed)

### Test Files
- [ ] Create `APIClientProtocolTests.swift`
- [ ] Create `APIClientFactoryTests.swift`
- [ ] Create `MockAPIClientTests.swift`
- [ ] Create `MockDataLoaderTests.swift`
- [ ] Create `MockResponseRegistryTests.swift`
- [ ] Run all tests (Cmd+U)
- [ ] Verify all tests pass

**Unit Tests Complete**: ☐

---

## 🎉 Implementation Complete Checklist

### Core Functionality
- [ ] ✅ Protocol-based architecture implemented
- [ ] ✅ Both APIClient and MockAPIClient conform to protocol
- [ ] ✅ Factory returns cached singleton (verified by logging)
- [ ] ✅ Mock mode switchable via UserDefaults
- [ ] ✅ Mock data registry handles URL patterns
- [ ] ✅ Mock data loads from bundle successfully

### Xcode Integration
- [ ] ✅ MockData folder in Xcode project (folder reference)
- [ ] ✅ MockData in Copy Bundle Resources
- [ ] ✅ Build script strips MockData in Release
- [ ] ✅ Bundle verification at app startup

### Safety & Production
- [ ] ✅ Mock mode forced OFF in Release builds (#if DEBUG)
- [ ] ✅ MockData stripped from Release bundles
- [ ] ✅ No hardcoded mock mode values in code
- [ ] ✅ UserDefaults used for runtime config

### Documentation
- [ ] ✅ README.md created with usage guide
- [ ] ✅ EXAMPLES.md created with code samples
- [ ] ✅ MockData/README.md explains conventions
- [ ] ✅ Code comments explain key decisions

### Testing
- [ ] ✅ Manual testing completed
- [ ] ✅ Mock mode toggle tested
- [ ] ✅ Release build verified
- [ ] ✅ Error scenarios tested
- [ ] ✅ (Optional) Unit tests written and passing

---

## 📊 Progress Summary

- **Phase 0**: ☐ Complete (or ☐ Skipped)
- **Phase 1**: ☐ Complete
- **Phase 2**: ☐ Complete
- **Phase 3**: ☐ Complete
- **Phase 4**: ☐ Complete
- **Testing**: ☐ Complete

**Overall Status**: ☐ IN PROGRESS | ☐ COMPLETE

**Estimated Time**: 5-7 hours
**Actual Time**: _________ hours

---

## 🐛 Issues Encountered

*(Document any problems and solutions here)*

1. Issue: ___________________________
   - Solution: ___________________________

2. Issue: ___________________________
   - Solution: ___________________________

---

## 📝 Notes & Observations

*(Add any learnings or future improvements here)*

---

## Quick Commands Reference

### Toggle Mock Mode
```bash
# Enable mock mode
defaults write com.yourcompany.WellPlate app.networking.mockMode -bool true

# Disable mock mode
defaults write com.yourcompany.WellPlate app.networking.mockMode -bool false

# Check current value
defaults read com.yourcompany.WellPlate app.networking.mockMode

# Reset (will default to true in DEBUG)
defaults delete com.yourcompany.WellPlate app.networking.mockMode
```

### Verify Bundle Contents
```bash
# List files in simulator bundle (after running app)
find ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Bundle/Application/*/WellPlate.app -name "MockData" 2>/dev/null
```

### Clean Xcode
```bash
# Clean build folder
# Cmd+Shift+K in Xcode or:
xcodebuild clean -project WellPlate.xcodeproj -scheme WellPlate
```

---

## ✅ Sign-Off

- [ ] All critical issues from audit addressed
- [ ] All phases completed successfully
- [ ] All verification steps passed
- [ ] Documentation complete
- [ ] Code reviewed
- [ ] Ready for production use

**Implementer**: _________________
**Date**: _________________
**Reviewer**: _________________
**Date**: _________________

---

**Next Steps After Completion:**
1. Create first real API endpoint
2. Add corresponding mock data
3. Integrate into first ViewModel/Feature
4. Consider adding debug menu for mock toggle
5. Document common API patterns for team
