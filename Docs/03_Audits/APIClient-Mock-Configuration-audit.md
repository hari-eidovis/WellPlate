# Plan Audit Report: APIClient with Mock/Real Mode Switching

**Audit Date**: 2026-02-16
**Plan Version**: Initial (260216-APIClient-Mock-Configuration.md)
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary

The implementation plan provides a solid foundation for protocol-based dependency injection with mock/real switching. However, several **critical** and **high-priority** issues must be addressed before implementation. The most significant concerns are: (1) APIClientFactory.shared creates new instances instead of returning singletons, (2) no test infrastructure exists despite plan assumptions, (3) Xcode project integration is not specified, and (4) mock filename mapping is too simplistic for real-world URLs.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### 1. **APIClientFactory.shared Breaks Singleton Pattern**
   - **Location**: Phase 2, Step 6 - APIClientFactory implementation
   - **Problem**:
     ```swift
     static var shared: APIClientProtocol {
         create()  // Creates NEW instance every access!
     }
     ```
     This computed property creates a new instance on every access, defeating the singleton pattern of both APIClient and MockAPIClient. If a ViewModel stores a reference and another component calls `APIClientFactory.shared`, they get different instances.

   - **Impact**:
     - State inconsistencies between components
     - Multiple network sessions created unnecessarily
     - Potential memory leaks
     - Makes debugging extremely difficult

   - **Recommendation**: Change to lazy static property that caches the result:
     ```swift
     private static let _shared: APIClientProtocol = {
         if AppConfig.shared.mockMode {
             return MockAPIClient.shared
         } else {
             return APIClient.shared
         }
     }()

     static var shared: APIClientProtocol {
         _shared
     }
     ```
     **OR** document that switching modes requires app restart and evaluate mockMode only once.

#### 2. **Test Infrastructure Doesn't Exist**
   - **Location**: Testing Strategy section, Appendix File Checklist
   - **Problem**: Plan assumes `WellPlateTests/` directory exists and references creating test files there. Current audit found NO test directories in the project.

   - **Impact**:
     - Test files cannot be created as specified
     - No test target exists in Xcode project
     - Unit tests won't run
     - Implementation cannot be verified

   - **Recommendation**: Add Phase 0 or prerequisite step:
     - Create WellPlateTests target in Xcode if it doesn't exist
     - Set up test directory structure
     - Configure test bundle settings
     - OR remove test file creation from plan and mark as post-implementation task

#### 3. **Xcode Project Integration Not Specified**
   - **Location**: Phase 3, Steps 7-8 - Mock Data Directory Creation
   - **Problem**: Plan only mentions creating filesystem directories and files, but doesn't specify adding them to Xcode project. Files not added to the project won't be included in the app bundle, causing `MockDataLoader` to fail with "file not found" errors.

   - **Impact**:
     - Mock data files won't be in bundle at runtime
     - MockAPIClient will always throw errors
     - MockDataLoader.load() will fail for all requests
     - Mock mode will be unusable

   - **Recommendation**: Add explicit steps:
     - After creating MockData directory, add to Xcode project via File → Add Files
     - Ensure "Copy items if needed" is checked
     - Ensure files are added to app target (not test target)
     - Verify in Build Phases → Copy Bundle Resources
     - Add validation step to check files appear in bundle

#### 4. **Mock Filename Mapping Is Too Simplistic**
   - **Location**: Phase 2, Step 5 - MockAPIClient.mockFileNameForURL()
   - **Problem**:
     ```swift
     private func mockFileNameForURL(_ url: URL, method: HTTPMethod) -> String {
         let path = url.path.replacingOccurrences(of: "/", with: "_")
         return "mock\(path)_\(method.rawValue.lowercased())"
     }
     ```
     This fails for:
     - URLs with query parameters: `/api/users?page=2&limit=10`
     - URLs with path parameters: `/api/users/123/posts/456`
     - URLs with special characters: `/api/search?q=hello world`
     - Different URLs that map to same path: `/api/users/1` and `/api/users/2`

   - **Impact**:
     - Cannot mock paginated endpoints
     - Cannot mock resource-specific endpoints
     - Hash collisions for similar URLs
     - Unusable for real-world API patterns

   - **Recommendation**: Implement more robust mapping:
     ```swift
     private func mockFileNameForURL(_ url: URL, method: HTTPMethod) -> String {
         // Option 1: Use URL hash
         let urlString = url.absoluteString
         let hash = abs(urlString.hashValue)
         return "mock_\(hash)_\(method.rawValue.lowercased())"

         // Option 2: Manual mapping dictionary
         // Option 3: Pattern-based matching with wildcards
         // Document the chosen approach
     }
     ```
     OR introduce a mock response registry pattern instead of file-based lookups.

---

### HIGH (Should Fix Before Proceeding)

#### 5. **HTTPMethod Already Has PATCH - Plan is Incorrect**
   - **Location**: Phase 1, Step 3 & Risk 4
   - **Problem**: Plan states "Missing PATCH method in current APIClient" and identifies it as Risk 4. However, audit confirms `HTTPMethod.patch` already exists in the enum (line 8 of APIClient.swift). The actual missing piece is the PATCH **convenience method** in APIClient class.

   - **Impact**:
     - Misleading plan could cause confusion
     - Risk assessment is inaccurate
     - Implementation might add duplicate enum case

   - **Recommendation**: Correct the plan to state: "Missing PATCH convenience method in APIClient class" and update Risk 4 accordingly.

#### 6. **No Specification for Excluding Mock Data from Release Builds**
   - **Location**: Risk 5 mitigation mentions it but no implementation steps
   - **Problem**: Plan mentions "Strip mock data in Release builds" and "Use build phase script to exclude MockData folder" but provides NO concrete implementation steps or script examples.

   - **Impact**:
     - Mock data ships to production, bloating app size
     - Potential data leakage if mock data contains sensitive examples
     - App Store rejection for unnecessary resource bloat

   - **Recommendation**: Add specific step with build phase script:
     ```bash
     # Run Script Phase: Strip Mock Data in Release
     if [ "${CONFIGURATION}" = "Release" ]; then
         echo "Removing MockData from Release build"
         rm -rf "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/MockData"
     fi
     ```
     Add this as Step 7b or document in Phase 3.

#### 7. **MockDataLoader Doesn't Handle Missing Files Gracefully**
   - **Location**: Phase 2, Step 4 - MockDataLoader implementation
   - **Problem**: When mock file doesn't exist, loader throws `MockDataError.fileNotFound`. MockAPIClient catches this but only prints a warning and throws `APIError.noData`. No guidance on:
     - How to discover which mock files are needed during development
     - How to provide helpful error messages to developers
     - Whether to fail fast or provide fallback responses

   - **Impact**:
     - Poor developer experience - cryptic errors
     - Time wasted debugging missing mock files
     - No clear path to identify required mocks

   - **Recommendation**:
     - Add detailed error messages including expected file path
     - Provide example mock data generator
     - Add DEBUG mode that lists all attempted file loads
     - Consider fallback to empty response for development

#### 8. **AppConfig.mockMode Default Behavior Is Ambiguous**
   - **Location**: Phase 1, Step 2 - AppConfig implementation
   - **Problem**: `UserDefaults.standard.bool(forKey:)` returns `false` by default when key doesn't exist. This means:
     - First launch: mockMode = false (not set)
     - Explicitly set to false: mockMode = false (set)
     - No way to distinguish between "never configured" and "explicitly disabled"
     - Developers might expect mockMode to default to TRUE in debug builds for development

   - **Impact**:
     - Confusing default behavior for new developers
     - Potential for developers to think mock mode is on when it's not
     - Need to remember to manually enable mock mode after fresh clone

   - **Recommendation**: Consider defaulting to true in DEBUG:
     ```swift
     var mockMode: Bool {
         get {
             #if DEBUG
             // Default to true in DEBUG if never set
             guard UserDefaults.standard.object(forKey: "app.networking.mockMode") != nil else {
                 return true  // Development-friendly default
             }
             return UserDefaults.standard.bool(forKey: "app.networking.mockMode")
             #else
             return false
             #endif
         }
     }
     ```
     OR document the default-to-false behavior clearly.

#### 9. **No Handling for Non-Decodable Responses**
   - **Location**: APIClientProtocol definition in Phase 1, Step 1
   - **Problem**: All methods require `T: Decodable` return type. Many APIs return:
     - 204 No Content (DELETE operations)
     - 201 Created with empty body
     - 202 Accepted with no immediate response
     - Plain text or non-JSON responses

   - **Impact**:
     - Cannot handle common HTTP response patterns
     - Delete operations will fail if no body returned
     - Need workarounds like `EmptyResponse` struct
     - Breaks API compliance for standard REST patterns

   - **Recommendation**: Add optional overloads:
     ```swift
     func request(url: URL, method: HTTPMethod, headers: [String: String]?, body: Data?) async throws -> Void
     func request<T: Decodable>(url: URL, method: HTTPMethod, ...) async throws -> T
     ```
     OR add Empty response type to protocol.

#### 10. **Core Directory Setup Not Specified**
   - **Location**: Phase 1, Step 2 - Create AppConfig in Core directory
   - **Problem**: Audit confirms Core directory exists but is empty. Plan doesn't specify:
     - Whether Core should be a group or folder reference in Xcode
     - What else belongs in Core (only AppConfig?)
     - How Core relates to other architecture (Features, Shared, etc.)

   - **Impact**:
     - Inconsistent project organization
     - Unclear architecture boundaries
     - Potential for Core to become a dumping ground

   - **Recommendation**:
     - Define purpose and scope of Core directory
     - List what types of files belong there
     - Consider if AppConfig should go in App/ instead since it's app-wide config
     - OR rename to Config/ for clarity

---

### MEDIUM (Fix During Implementation)

#### 11. **No Thread Safety for AppConfig**
   - **Problem**: AppConfig.mockMode getter/setter access UserDefaults without synchronization. If multiple threads read/write mockMode simultaneously, could cause race conditions.
   - **Recommendation**: UserDefaults is thread-safe, but document this assumption. If adding other config properties, consider using locks or actors.

#### 12. **URL Filename Mapping Doesn't Handle Special Characters**
   - **Problem**: URLs with spaces, unicode, or special chars will create invalid filenames.
   - **Recommendation**: Sanitize filename or use base64/hash-based naming.

#### 13. **Hardcoded Network Delay**
   - **Problem**: MockAPIClient has hardcoded 0.5s delay. Should be configurable.
   - **Recommendation**: Add `MockConfig.networkDelay: TimeInterval` for flexibility.

#### 14. **No Mock Data Organization Strategy**
   - **Problem**: All mock files in flat MockData/ directory. Large apps will have hundreds of files.
   - **Recommendation**: Organize by feature: `MockData/Users/`, `MockData/Posts/`, etc.

#### 15. **Missing Logging Infrastructure**
   - **Problem**: Plan uses `print()` statements. No structured logging, log levels, or filtering.
   - **Recommendation**: Consider using OSLog or custom logger protocol.

#### 16. **APIError Should Be Part of Protocol or Shared**
   - **Problem**: MockAPIClient throws `APIError.noData` but APIError is defined in APIClient.swift, creating coupling.
   - **Recommendation**: Move APIError and HTTPMethod to shared Networking file or protocol file.

#### 17. **No Provision for Testing Both Modes**
   - **Problem**: Factory caches result, making it hard to test both real and mock in same test run.
   - **Recommendation**: Add `APIClientFactory.reset()` or inject config for testing.

---

### LOW (Consider for Future)

#### 18. **Print Statements Instead of Proper Logging**
   - **Problem**: Using print() instead of os_log or unified logging.
   - **Recommendation**: Introduce proper logging framework.

#### 19. **No Support for HEAD, OPTIONS, CONNECT, TRACE**
   - **Problem**: HTTPMethod only includes common REST methods.
   - **Recommendation**: Add other HTTP methods as needed.

#### 20. **Mock Delay Uses sleep() Which Blocks**
   - **Problem**: `Task.sleep` is fine, but no cancellation handling mentioned.
   - **Recommendation**: Document that mock requests can be cancelled.

#### 21. **No Provision for Response Headers**
   - **Problem**: Mock responses only return decoded body, no headers or status codes.
   - **Recommendation**: Future enhancement for header-based testing.

---

## Missing Elements

- [ ] **Xcode project modification steps** - Critical for bundle resource inclusion
- [ ] **Test target setup** - Required before creating test files
- [ ] **Build phase script for stripping mock data** - Mentioned but not implemented
- [ ] **Example mock JSON file content** - Plan mentions creating files but not what's in them
- [ ] **Error recovery strategy** - What happens when mocks are missing in dev?
- [ ] **Mock data discovery/generation tool** - How to know what mocks to create?
- [ ] **Migration path for changing mock mode** - Does it require app restart?
- [ ] **Documentation for backend team** - How to export/share mock data format?
- [ ] **CI/CD integration** - How to run tests with/without mocks?
- [ ] **Validation that mock JSON matches model types** - Prevent runtime decode errors

---

## Unverified Assumptions

- [ ] **Assumption**: MockData files will automatically be included in bundle - **Risk: HIGH**
  - Reality: Must be explicitly added to Xcode project target

- [ ] **Assumption**: Test infrastructure exists - **Risk: HIGH**
  - Reality: No WellPlateTests directory or target found

- [ ] **Assumption**: All API responses return JSON decodable to model - **Risk: MEDIUM**
  - Reality: Many APIs return 204 No Content, plain text, or empty responses

- [ ] **Assumption**: URL paths uniquely identify endpoints - **Risk: MEDIUM**
  - Reality: Query params, path params, and dynamic IDs make this insufficient

- [ ] **Assumption**: UserDefaults is appropriate for configuration - **Risk: LOW**
  - Reality: Works for simple boolean, but doesn't support schemes or environments well

- [ ] **Assumption**: Factory.shared will always return same instance - **Risk: CRITICAL**
  - Reality: Current implementation creates new instance each time!

- [ ] **Assumption**: PATCH method is missing from APIClient - **Risk: LOW**
  - Reality: HTTPMethod.patch exists; only convenience method is missing

- [ ] **Assumption**: Developers will know which mock files to create - **Risk: MEDIUM**
  - Reality: No discovery mechanism or documentation of URL → filename mapping

---

## Security Considerations

- [x] **Mock mode forced off in production** - #if DEBUG guard provides this
- [ ] **Mock data doesn't contain real user data** - Should add warning in documentation
- [ ] **No secrets in mock JSON files** - Should add git-secrets or pre-commit hook
- [x] **UserDefaults key is namespaced** - "app.networking.mockMode" is well-namespaced
- [ ] **Mock data stripped from release builds** - Mentioned but not implemented
- [ ] **No accidental commit of mockMode=true** - Only in UserDefaults, not source code (good)

**Verdict**: Low security risk if mock data stripping is implemented properly.

---

## Performance Considerations

- [x] **Network delay simulation is reasonable** - 0.5s is acceptable
- [ ] **Factory creates new instances every call** - Critical performance bug!
- [x] **JSON decoding performance** - Using standard JSONDecoder is fine
- [ ] **Large mock files impact bundle size** - Need release build stripping
- [x] **Singleton pattern prevents multiple sessions** - Yes, IF factory is fixed
- [ ] **No consideration for caching** - Future enhancement, acceptable for MVP

**Verdict**: Factory instance creation is a critical performance issue.

---

## Questions for Clarification

1. **Should mock mode default to ON or OFF in DEBUG builds?**
   - Current plan: OFF (UserDefaults.bool default)
   - Alternative: ON for development convenience
   - Recommendation: Document clearly and consider defaulting to ON

2. **How should parametrized URLs be mocked?**
   - `/api/users/123` vs `/api/users/456` - same file or different?
   - Should we use pattern matching or manual mapping?
   - Recommendation: Provide registry-based solution

3. **What happens when switching mock mode at runtime?**
   - Does app need restart?
   - Do cached instances update?
   - Recommendation: Document that restart is required OR implement observable config

4. **Should MockData be in main bundle or test bundle?**
   - Main bundle: Available for manual testing in app
   - Test bundle: Only for unit tests
   - Current plan implies main bundle
   - Recommendation: Clarify and document

5. **How to handle DELETE/PUT with no response body?**
   - Should we require `EmptyResponse` struct?
   - Should we add non-generic overloads?
   - Recommendation: Add void-returning variants

6. **Should HTTPMethod and APIError be in protocol file or separate?**
   - Current: In APIClient.swift
   - Better: Shared file for both to use
   - Recommendation: Move to APIClientProtocol.swift or separate enums file

---

## Recommendations

### Before Implementation Starts

1. **FIX CRITICAL**: Rewrite APIClientFactory.shared to cache instance
2. **FIX CRITICAL**: Add Xcode project integration steps for MockData
3. **FIX CRITICAL**: Verify test infrastructure exists or remove test file creation
4. **FIX CRITICAL**: Redesign mock filename mapping strategy

### During Implementation

5. **Add**: Build phase script for stripping mock data in Release
6. **Correct**: Plan description about PATCH - it's the convenience method that's missing
7. **Add**: Void-returning variants for non-decodable responses
8. **Document**: Default mock mode behavior and how to change it
9. **Add**: Better error messages for missing mock files
10. **Consider**: Defaulting mockMode to TRUE in DEBUG builds

### Documentation Improvements

11. **Add**: Example mock JSON file with actual content
12. **Add**: Guide for determining which mock files are needed
13. **Add**: Xcode project setup checklist
14. **Clarify**: Whether runtime mode switching requires app restart

### Testing Improvements

15. **Add**: Factory reset mechanism for testing
16. **Add**: Validation that mock JSON matches expected model types
17. **Add**: Mock data generator script or guidelines

---

## Architectural Concerns

### Coupling Issues
- MockAPIClient depends on APIError from APIClient.swift
- Both clients depend on HTTPMethod enum in APIClient.swift
- **Recommendation**: Move shared types to protocol file or separate enums file

### Separation of Concerns
- AppConfig currently only has mockMode - will it grow?
- Is Core the right place for app-wide configuration?
- **Recommendation**: Consider Configuration/ directory or keep in App/

### Scalability
- Flat mock data directory won't scale to large apps
- Filename mapping strategy won't handle real-world API complexity
- **Recommendation**: Implement registry pattern or organize by feature

---

## Sign-off Checklist

- [ ] All CRITICAL issues resolved
  - Factory instance creation issue
  - Xcode project integration specified
  - Test infrastructure prerequisites added
  - Mock filename mapping redesigned

- [ ] All HIGH issues resolved or accepted
  - PATCH method description corrected
  - Release build stripping implemented
  - Missing mock file handling improved
  - mockMode default behavior documented
  - Non-decodable response handling added
  - Core directory purpose clarified

- [ ] Security review completed
  - ✅ Mock mode production safety verified
  - ⚠️ Mock data stripping implementation needed
  - ✅ UserDefaults key namespacing good

- [ ] Performance implications understood
  - ⚠️ Factory instance creation must be fixed
  - ✅ Singleton pattern appropriate
  - ⚠️ Bundle size impact needs stripping script

- [ ] Rollback strategy defined
  - ⚠️ No rollback strategy in plan
  - Recommendation: Since no existing code uses this, rollback is just removing new files

---

## Overall Assessment

**Strengths:**
- ✅ Solid protocol-oriented architecture
- ✅ Good separation of concerns
- ✅ Comprehensive documentation planned
- ✅ Production safety with #if DEBUG guards
- ✅ No breaking changes (no existing usage)

**Weaknesses:**
- ❌ Critical factory pattern bug (creates new instances)
- ❌ Missing Xcode project integration steps
- ❌ Assumes test infrastructure exists when it doesn't
- ❌ Oversimplified mock filename mapping
- ❌ No implementation for release build stripping

**Recommendation**: Address the 4 CRITICAL issues before implementation begins. The HIGH priority issues can be addressed during implementation with awareness. MEDIUM and LOW issues are acceptable to defer.

---

## Next Steps

1. **Revise plan** to fix CRITICAL issues 1-4
2. **Add prerequisite phase** for test infrastructure setup
3. **Add explicit Xcode steps** for bundle resource management
4. **Redesign mock mapping** strategy with concrete examples
5. **Add build phase script** for release stripping
6. **Review revised plan** before implementation

**Estimated Time to Address Issues**: 2-3 hours of plan revision

---

## References
- Implementation Plan: `/Users/hariom/Desktop/WellPlate/Docs/02_Planning/Specs/260216-APIClient-Mock-Configuration.md`
- Current APIClient: `/Users/hariom/Desktop/WellPlate/WellPlate/Networking/APIClient.swift`
- Xcode Project: `/Users/hariom/Desktop/WellPlate/WellPlate.xcodeproj`
