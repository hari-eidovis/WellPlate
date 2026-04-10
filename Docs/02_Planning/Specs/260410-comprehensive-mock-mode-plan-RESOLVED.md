# Implementation Plan: Comprehensive Mock Mode Toggle (RESOLVED)

## Audit Resolution Summary

| Issue | Severity | Resolution |
|---|---|---|
| C1: inject() guard always fails after flag merge | CRITICAL | Changed guard to check existing mock records instead of flag. ProfileView sets flag then calls inject(); inject checks for existing `logSource == "mock"` FoodLogEntries. |
| H1: SleepView.swift missing `isDataAvailable` guard | HIGH | Added new Step 10b to update SleepView's `isAvailable` check, same pattern as BurnView. |
| H2: WellnessDayLog deletion breaks after removing tracked dates | HIGH | Kept `mockInjectedDates` in AppConfig (renamed from `mockInjectedWellnessLogDates`). Also used for JournalEntry cleanup. |
| M1: Inconsistent deletion strategy | MEDIUM | Standardised on tag-based deletion where possible: SymptomEntry.notes="[mock]", JournalEntry.promptUsed="[mock]". AdherenceLog tracked by UUID. FastingSession tracked by dates. |
| M2: InsightEngine isAuthorized assumption unverified | MEDIUM | Added verification note in Step 6 confirming MockHealthKitService.isAuthorized is true. |
| M3: MockModeDebugCard double-trigger risk | MEDIUM | Documented constraint: ProfileView must NOT have separate onChange handler. Added comment in Step 12. |
| L1: No final grep verification step | LOW | Added Step 17 — final verification grep. |
| L2: No runtime mock mode indicator | LOW | Deferred to V2. Acknowledged. |
| L3: No test instance support in factory | LOW | Added `#if DEBUG` test support in Step 1 factory code. |

---

## Overview

Unify the existing `mockMode` and `mockDataInjected` flags into a single `mockMode` toggle in Profile that activates comprehensive mock data across every feature: food logging, stress, burn, sleep, wellness calendar, AI insights, and home activity. Introduce `HealthKitServiceFactory` (mirroring `APIClientFactory`) as the single source of truth for HealthKit service resolution. Expand `MockDataInjector` with 4 additional SwiftData model types. Remove `InsightEngine`'s hard-coded `mockInsights()` shortcut so it runs the real detection pipeline against mock data.

## Requirements

- Single "Mock Mode" toggle in Profile (DEBUG only) that controls all mock behaviour
- All features show realistic data when mock mode is on
- No HealthKit authorization or API keys required when mock is active
- SwiftData mock data persists across app restarts
- Zero risk to real user data — all mock records are tagged for cleanup
- App restart required after toggle (acceptable for DEBUG tool)

## Architecture Changes

- **New**: `WellPlate/Core/Services/HealthKitServiceFactory.swift` — cached singleton factory
- **Modified**: `AppConfig.swift` — remove `mockDataInjected`, fold into `mockMode`; rename `mockInjectedWellnessLogDates` → `mockInjectedDates`
- **Modified**: `MockDataInjector.swift` — add 4 new model types + update guards/cleanup
- **Modified**: `InsightEngine.swift` — use factory, remove mock shortcut
- **Modified**: 5 ViewModels — use factory instead of inline checks
- **Modified**: 5 Views — replace `mockDataInjected` references with `mockMode` (including SleepView)
- **Modified**: `ProfileView.swift` + `MockDataDebugCard.swift` — single unified toggle

## Implementation Steps

### Phase 1: Foundation (Factory + Flag Merge)

#### Step 1. Create HealthKitServiceFactory
**File**: `WellPlate/Core/Services/HealthKitServiceFactory.swift` (NEW)

**Action**: Create a new file mirroring the pattern in `WellPlate/Networking/Real/APIClientFactory.swift`:

<!-- RESOLVED: L3 — Added #if DEBUG test instance support matching APIClientFactory pattern -->
```swift
//
//  HealthKitServiceFactory.swift
//  WellPlate
//
//  Factory for providing the appropriate HealthKitServiceProtocol implementation.
//  Returns MockHealthKitService or real HealthKitService based on AppConfig.mockMode.
//
//  IMPORTANT: This factory caches the service instance on first access.
//  Changing mockMode requires app restart for changes to take effect.
//

import Foundation

enum HealthKitServiceFactory {

    /// Cached singleton — evaluated once at first access.
    private static let _shared: HealthKitServiceProtocol = {
        #if DEBUG
        if AppConfig.shared.mockMode {
            WPLogger.app.block(emoji: "🎭", title: "HEALTHKIT · MOCK", lines: [
                "Mode: Offline — serving StressMockSnapshot data",
                "Toggle: AppConfig.shared.mockMode = false → restart"
            ])
            return MockHealthKitService(snapshot: .default)
        }
        #endif
        return HealthKitService()
    }()

    /// Shared instance — returns cached singleton.
    static var shared: HealthKitServiceProtocol { _shared }

    /// Whether health data is available (real HK or mock).
    /// Use this instead of `HealthKitService.isAvailable` everywhere.
    static var isDataAvailable: Bool {
        #if DEBUG
        if AppConfig.shared.mockMode { return true }
        #endif
        return HealthKitService.isAvailable
    }

    // MARK: - Testing Support

    #if DEBUG
    private(set) static var _testInstance: HealthKitServiceProtocol?

    static func setTestInstance(_ instance: HealthKitServiceProtocol?) {
        _testInstance = instance
    }

    static var testable: HealthKitServiceProtocol {
        _testInstance ?? _shared
    }
    #endif
}
```

**Why**: Centralises mock/real decision. All ViewModels use `HealthKitServiceFactory.shared` as their default, eliminating scattered `if mockDataInjected` checks. Mirrors the existing `APIClientFactory` pattern.

**Dependencies**: None (first step)
**Risk**: Low

---

#### Step 2. Merge flags in AppConfig
**File**: `WellPlate/Core/AppConfig.swift`

**Action**:
1. Remove the `mockDataInjected` computed property (lines 110–124)
2. Remove the corresponding `Keys.mockDataInjected` entry (line 20)
3. **Rename** `mockInjectedWellnessLogDates` → `mockInjectedDates` (keep the property, rename for generality):
<!-- RESOLVED: H2 — Kept tracked dates property, renamed for generality. Used for WellnessDayLog + JournalEntry cleanup. -->
   ```swift
   // In Keys enum:
   // REMOVE: static let mockDataInjected = "app.mock.dataInjected"
   // RENAME:
   static let mockInjectedDates = "app.mock.injectedDates"  // was mockInjectedWellnessLogDates

   // Renamed property:
   var mockInjectedDates: [String] {
       get {
           #if DEBUG
           return UserDefaults.standard.stringArray(forKey: Keys.mockInjectedDates) ?? []
           #else
           return []
           #endif
       }
       set {
           #if DEBUG
           UserDefaults.standard.set(newValue, forKey: Keys.mockInjectedDates)
           #endif
       }
   }
   ```
4. Add `mockInjectedRecordIDs` for UUID-tracked models (AdherenceLog):
   ```swift
   // In Keys enum:
   static let mockInjectedRecordIDs = "app.mock.injectedRecordIDs"

   // New property:
   var mockInjectedRecordIDs: [String] {
       get {
           #if DEBUG
           return UserDefaults.standard.stringArray(forKey: Keys.mockInjectedRecordIDs) ?? []
           #else
           return []
           #endif
       }
       set {
           #if DEBUG
           UserDefaults.standard.set(newValue, forKey: Keys.mockInjectedRecordIDs)
           #endif
       }
   }
   ```
5. Update `logCurrentMode()` to include mock data status:
   ```swift
   "Mock Data  : \(mockMode ? "INJECTED" : "NONE")",
   ```

**Why**: Single flag (`mockMode`) now means "everything is mocked". `mockInjectedDates` retained for safe WellnessDayLog + JournalEntry cleanup.

**Dependencies**: Step 1
**Risk**: Low — straightforward property removal + rename. Old `mockDataInjected` UserDefaults key is harmless if left in place.

---

### Phase 2: Wire Factory into All ViewModels

#### Step 3. Update SleepViewModel
**File**: `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift`

**Action**:
1. Change line 25 default parameter:
   ```swift
   // Before:
   init(service: HealthKitServiceProtocol = HealthKitService()) {
   // After:
   init(service: HealthKitServiceProtocol = HealthKitServiceFactory.shared) {
   ```
2. Update `requestPermissionAndLoad()` (line 90) — replace `HealthKitService.isAvailable` guard:
   ```swift
   // Before:
   guard HealthKitService.isAvailable else { return }
   // After:
   guard HealthKitServiceFactory.isDataAvailable else { return }
   ```

**Why**: SleepViewModel currently has zero mock awareness. This is the biggest gap.

**Dependencies**: Step 1
**Risk**: Low

---

#### Step 4. Update BurnViewModel
**File**: `WellPlate/Features + UI/Burn/ViewModels/BurnViewModel.swift`

**Action**:
1. Simplify the `init` (lines 26–34) — remove inline mock check:
   ```swift
   // Before:
   init(service: HealthKitServiceProtocol? = nil) {
       if let service {
           self.service = service
       } else if AppConfig.shared.mockDataInjected {
           self.service = MockHealthKitService(snapshot: .default)
       } else {
           self.service = HealthKitService()
       }
   }
   // After:
   init(service: HealthKitServiceProtocol = HealthKitServiceFactory.shared) {
       self.service = service
   }
   ```
2. Simplify `requestPermissionAndLoad()` (lines 106–124) — replace mock-specific branch:
   ```swift
   // Before:
   func requestPermissionAndLoad() async {
       if AppConfig.shared.mockDataInjected {
           isLoading = true
           defer { isLoading = false }
           isAuthorized = true
           await loadData()
           return
       }
       guard HealthKitService.isAvailable else { return }
       ...
   }
   // After:
   func requestPermissionAndLoad() async {
       guard HealthKitServiceFactory.isDataAvailable else { return }
       isLoading = true
       defer { isLoading = false }
       do {
           try await service.requestAuthorization()
           isAuthorized = service.isAuthorized
           await loadData()
       } catch {
           errorMessage = error.localizedDescription
       }
   }
   ```

**Why**: Removes scattered `mockDataInjected` checks. `MockHealthKitService.requestAuthorization()` is a no-op and `isAuthorized` is `true` by default, so the unified path works for both real and mock.

**Dependencies**: Step 1
**Risk**: Low

---

#### Step 5. Update WellnessCalendarViewModel
**File**: `WellPlate/Features + UI/Home/ViewModels/WellnessCalendarViewModel.swift`

**Action**:
1. Simplify `init` (lines 30–37):
   ```swift
   // Before:
   init(healthService: HealthKitServiceProtocol? = nil) {
       if let healthService {
           self.healthService = healthService
       } else if AppConfig.shared.mockDataInjected {
           self.healthService = MockHealthKitService(snapshot: .default)
       } else {
           self.healthService = HealthKitService()
       }
   }
   // After:
   init(healthService: HealthKitServiceProtocol = HealthKitServiceFactory.shared) {
       self.healthService = healthService
   }
   ```
2. Simplify `loadHealthKitActivity` guard (lines 191–194):
   ```swift
   // Before:
   if !AppConfig.shared.mockDataInjected {
       guard HealthKitService.isAvailable else { return }
   }
   // After:
   guard HealthKitServiceFactory.isDataAvailable else { return }
   ```

**Why**: Same pattern as BurnViewModel — centralise through factory.

**Dependencies**: Step 1
**Risk**: Low

---

#### Step 6. Update InsightEngine
**File**: `WellPlate/Core/Services/InsightEngine.swift`

**Action**:
1. Change default init parameter (line 34):
   ```swift
   // Before:
   init(healthService: HealthKitServiceProtocol = HealthKitService()) {
   // After:
   init(healthService: HealthKitServiceProtocol = HealthKitServiceFactory.shared) {
   ```
2. Remove the mock shortcut in `generateInsights()` (lines 55–61):
   ```swift
   // REMOVE these lines:
   // Mock mode
   if AppConfig.shared.mockMode {
       let mocks = mockInsights()
       insightCards = mocks
       dailyInsight = mocks.first
       return
   }
   ```
3. Add a fallback in the `buildWellnessContext() == nil` path to use `mockInsights()` only when mock mode is on AND SwiftData has no records:
   ```swift
   guard let context = await buildWellnessContext() else {
       #if DEBUG
       if AppConfig.shared.mockMode {
           // Fallback: mock data not yet injected or SwiftData empty
           let mocks = mockInsights()
           insightCards = mocks
           dailyInsight = mocks.first
           return
       }
       #endif
       insufficientData = true
       return
   }
   ```
4. Keep `mockInsights()` as a private method (no deletion) — it serves as fallback.

<!-- RESOLVED: M2 — Verified: MockHealthKitService.isAuthorized is true by default (line 16 of MockHealthKitService.swift). The quality note check at InsightEngine.swift:244 (`if !healthService.isAuthorized`) is safe — mock service passes. -->

**Why**: This is the key change — InsightEngine now runs its real detection pipeline (trends, correlations, milestones, imbalances, sleep quality, reinforcements) against mock SwiftData + MockHealthKitService data. The `mockInsights()` fallback only triggers if SwiftData is empty (e.g., first launch before injection).

**Dependencies**: Step 1
**Risk**: Medium — if mock data is insufficient for the `domainsWith2Days >= 2` gate, the pipeline will return `insufficientData`. Mitigated by MockDataInjector providing 30 days across all domains. Verified: `MockHealthKitService.isAuthorized` is `true` by default, so the quality note check at line 244 is safe.

---

#### Step 7. Update StressViewModel default parameter
**File**: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`

**Action**: Change default parameter on line 144:
```swift
// Before:
init(
    healthService: HealthKitServiceProtocol = HealthKitService(),
    modelContext: ModelContext,
    mockSnapshot: StressMockSnapshot? = nil
)
// After:
init(
    healthService: HealthKitServiceProtocol = HealthKitServiceFactory.shared,
    modelContext: ModelContext,
    mockSnapshot: StressMockSnapshot? = nil
)
```

**Why**: Consistency — all VMs use factory. The `mockSnapshot` parameter remains for StressView's specialized mock data needs.

**Dependencies**: Step 1
**Risk**: Low

---

### Phase 3: Wire Factory into Views

#### Step 8. Update MainTabView
**File**: `WellPlate/Features + UI/Tab/MainTabView.swift`

**Action**: Simplify the Stress tab VM creation (lines 26–38):
```swift
// Before:
StressView(viewModel: {
    #if DEBUG
    if AppConfig.shared.mockMode || AppConfig.shared.mockDataInjected {
        let snap = StressMockSnapshot.default
        return StressViewModel(
            healthService: MockHealthKitService(snapshot: snap),
            modelContext: modelContext,
            mockSnapshot: snap
        )
    }
    #endif
    return StressViewModel(modelContext: modelContext)
}())
// After:
StressView(viewModel: {
    #if DEBUG
    if AppConfig.shared.mockMode {
        let snap = StressMockSnapshot.default
        return StressViewModel(
            modelContext: modelContext,
            mockSnapshot: snap
        )
    }
    #endif
    return StressViewModel(modelContext: modelContext)
}())
```

Note: `healthService` is no longer passed explicitly — the default `HealthKitServiceFactory.shared` handles it. The `mockSnapshot` is still needed because `StressViewModel` uses it for specialized stress-specific mock data beyond HealthKit (e.g., screen time, today's readings chart).

**Why**: Remove `mockDataInjected` reference. Remove explicit `MockHealthKitService` creation — factory handles it.

**Dependencies**: Steps 1, 7
**Risk**: Low

---

#### Step 9. Update HomeView
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**:
1. `fetchHealthMoodSuggestion()` (lines 712–726) — replace mock check + raw HealthKitService:
   ```swift
   // Before:
   private func fetchHealthMoodSuggestion() {
       if AppConfig.shared.mockDataInjected { return }
       guard HealthKitService.isAvailable else { return }
       Task {
           let service = HealthKitService()
           ...
       }
   }
   // After:
   private func fetchHealthMoodSuggestion() {
       guard HealthKitServiceFactory.isDataAvailable else { return }
       if AppConfig.shared.mockMode { return }  // Mock HK service returns nil for mood
       Task {
           let service = HealthKitServiceFactory.shared
           do {
               try await service.requestAuthorization()
               if let mood = try await service.fetchTodayMood() {
                   healthSuggestedMood = mood
               }
           } catch {
               WPLogger.healthKit.error("Mood suggestion from Health failed: \(error.localizedDescription)")
           }
       }
   }
   ```
2. `logMoodForTodayIfNeeded` (line 741) — replace guard:
   ```swift
   // Before:
   if HealthKitService.isAvailable && !AppConfig.shared.mockDataInjected {
       Task { try? await HealthKitService().writeMood(mood) }
   }
   // After:
   if HealthKitServiceFactory.isDataAvailable && !AppConfig.shared.mockMode {
       Task { try? await HealthKitServiceFactory.shared.writeMood(mood) }
   }
   ```

**Why**: HomeView is the last place creating raw `HealthKitService()`. Uses factory for reads, skips writes in mock mode.

**Dependencies**: Step 1
**Risk**: Low

---

#### Step 10. Update BurnView
**File**: `WellPlate/Features + UI/Burn/Views/BurnView.swift`

**Action**: Replace guard on line 28:
```swift
// Before:
if !HealthKitService.isAvailable && !AppConfig.shared.mockDataInjected {
// After:
if !HealthKitServiceFactory.isDataAvailable {
```

**Why**: Uses centralized availability check.

**Dependencies**: Step 1
**Risk**: Low

---

<!-- RESOLVED: H1 — Added Step 10b for SleepView isAvailable guard, same pattern as BurnView Step 10 -->
#### Step 10b. Update SleepView
**File**: `WellPlate/Features + UI/Sleep/Views/SleepView.swift`

**Action**: Replace guard on line 29:
```swift
// Before:
if !HealthKitService.isAvailable {
    unavailableView
// After:
if !HealthKitServiceFactory.isDataAvailable {
    unavailableView
```

**Why**: Without this fix, the Sleep tab shows "HealthKit unavailable" on Simulator even when mock mode is on. SleepViewModel (Step 3) has mock data ready but the View blocks it from being shown. Same pattern as BurnView (Step 10).

**Dependencies**: Step 1
**Risk**: Low

---

### Phase 4: Expand MockDataInjector

#### Step 11. Add new model type injectors to MockDataInjector
**File**: `WellPlate/Core/Services/MockDataInjector.swift`

**Action**:

<!-- RESOLVED: C1 — Changed inject() guard from flag-based to data-based. Checks for existing mock FoodLogEntries instead of mockMode flag. This prevents the deadlock where ProfileView sets mockMode=true then calls inject(), which would immediately bail out on a flag-based guard. -->

1. **Change injection guard** to check existing mock records instead of the flag:
   ```swift
   // Before:
   guard !AppConfig.shared.mockDataInjected else { return }
   // After:
   // Guard against double-injection by checking for existing mock data
   let existingMockFood = FetchDescriptor<FoodLogEntry>(
       predicate: #Predicate { $0.logSource == "mock" }
   )
   guard (try? context.fetchCount(existingMockFood)) == 0 else {
       WPLogger.app.info("Mock data already exists — skipping injection")
       return
   }
   ```

2. **Remove** the `AppConfig.shared.mockDataInjected = true` on success (line 31). The flag is now `mockMode`, set by ProfileView before calling inject. After save, just log success:
   ```swift
   do {
       try context.save()
       WPLogger.app.info("Mock data injection complete")
   } catch {
       WPLogger.app.error("Mock data injection failed: \(error.localizedDescription)")
   }
   ```

3. **Add 4 new injection methods** (called from `inject(into:)` after existing calls):

<!-- RESOLVED: M1 — Using tag-based deletion: SymptomEntry.notes="[mock]", JournalEntry.promptUsed="[mock]". AdherenceLog tracked by UUID. FastingSession + JournalEntry tracked by dates. -->

   **`injectSymptomEntries`** — 30-day window, ~10 entries, tagged via `notes`:
   ```swift
   private static func injectSymptomEntries(into context: ModelContext, today: Date, cal: Calendar) {
       let symptoms: [(name: String, category: SymptomCategory, severityRange: ClosedRange<Int>)] = [
           ("Headache", .pain, 3...7),
           ("Bloating", .digestive, 2...5),
           ("Fatigue", .energy, 4...8),
           ("Brain Fog", .cognitive, 3...6),
       ]
       for offset in stride(from: 0, to: 30, by: 3) {
           let day = cal.date(byAdding: .day, value: -offset, to: today)!
           let symptom = symptoms[offset / 3 % symptoms.count]
           let severity = symptom.severityRange.lowerBound + (offset % (symptom.severityRange.upperBound - symptom.severityRange.lowerBound + 1))
           let ts = cal.date(bySettingHour: 9 + (offset % 8), minute: 0, second: 0, of: day) ?? day
           let entry = SymptomEntry(name: symptom.name, category: symptom.category, severity: severity, timestamp: ts, notes: "[mock]")
           context.insert(entry)
       }
   }
   ```

   **`injectFastingSessions`** — 15 completed 16:8 sessions, tracked by dates:
   ```swift
   private static func injectFastingSessions(into context: ModelContext, today: Date, cal: Calendar, injectedDates: inout [String]) {
       let formatter = ISO8601DateFormatter()
       for offset in stride(from: 0, to: 30, by: 2) {
           let day = cal.date(byAdding: .day, value: -offset, to: today)!
           let prevDay = cal.date(byAdding: .day, value: -1, to: day)!
           let startTime = cal.date(bySettingHour: 20, minute: 0, second: 0, of: prevDay)!
           let targetEnd = cal.date(byAdding: .hour, value: 16, to: startTime)!
           let session = FastingSession(startedAt: startTime, targetEndAt: targetEnd, scheduleType: .ratio16_8)
           session.actualEndAt = targetEnd
           session.completed = true
           context.insert(session)
           // Track the start date for cleanup
           injectedDates.append(formatter.string(from: cal.startOfDay(for: startTime)))
       }
   }
   ```

   **`injectAdherenceLogs`** — 2 supplements, 30 days, tracked by UUID:
   ```swift
   private static func injectAdherenceLogs(into context: ModelContext, today: Date, cal: Calendar, injectedIDs: inout [String]) {
       let supplements: [(name: String, id: UUID, minute: Int)] = [
           ("Vitamin D", UUID(), 480),   // 8am
           ("Omega-3", UUID(), 1200),     // 8pm
       ]
       for offset in 0..<30 {
           let day = cal.date(byAdding: .day, value: -offset, to: today)!
           for supp in supplements {
               let status = offset % 7 == 0 ? "skipped" : "taken"
               let takenAt = status == "taken" ? cal.date(bySettingHour: supp.minute / 60, minute: supp.minute % 60, second: 0, of: day) : nil
               let log = AdherenceLog(supplementName: supp.name, supplementID: supp.id, day: day, scheduledMinute: supp.minute, status: status, takenAt: takenAt)
               context.insert(log)
               injectedIDs.append(log.id.uuidString)
           }
       }
   }
   ```

   **`injectJournalEntries`** — 10 entries, tagged via `promptUsed`, tracked by dates:
   ```swift
   private static func injectJournalEntries(into context: ModelContext, today: Date, cal: Calendar, injectedDates: inout [String]) {
       let texts = [
           "Felt energized today after morning walk. Good sleep last night.",
           "Stressful day at work. Tried deep breathing exercises.",
           "Meal prep went well. Hit protein goal for the first time this week.",
           "Slept poorly. Need to cut caffeine after 2pm.",
           "Great workout session. Recovery shake tasted amazing.",
           "Practiced mindfulness for 10 minutes. Noticed less anxiety.",
           "Weekend hike with friends. Perfect weather.",
           "Tried a new recipe — lentil soup turned out great.",
           "Journaling before bed helps me wind down.",
           "Feeling grateful for small wins this week.",
       ]
       let moods = [3, 1, 4, 0, 4, 3, 4, 3, 3, 4]
       let stressScores: [Double?] = [28, 55, 32, 68, 22, 35, 18, 40, 30, 25]
       let formatter = ISO8601DateFormatter()

       for (i, offset) in stride(from: 0, to: 30, by: 3).enumerated() {
           guard i < texts.count else { break }
           let day = cal.date(byAdding: .day, value: -offset, to: today)!
           let startOfDay = cal.startOfDay(for: day)

           // Skip days with existing journal entries (unique constraint)
           let descriptor = FetchDescriptor<JournalEntry>(
               predicate: #Predicate { $0.day == startOfDay }
           )
           guard (try? context.fetchCount(descriptor)) == 0 else { continue }

           let entry = JournalEntry(
               day: day,
               text: texts[i],
               moodRaw: moods[i],
               promptUsed: "[mock]",  // Tag for cleanup
               stressScore: stressScores[i]
           )
           context.insert(entry)
           injectedDates.append(formatter.string(from: startOfDay))
       }
   }
   ```

4. **Update `inject(into:)`** to call all new methods and track IDs/dates:
   ```swift
   static func inject(into context: ModelContext) {
       // Guard: check for existing mock data (not the flag — flag is set before this call)
       let existingMockFood = FetchDescriptor<FoodLogEntry>(
           predicate: #Predicate { $0.logSource == "mock" }
       )
       guard (try? context.fetchCount(existingMockFood)) == 0 else {
           WPLogger.app.info("Mock data already exists — skipping injection")
           return
       }

       let cal = Calendar.current
       let today = cal.startOfDay(for: Date())
       var injectedDates: [String] = []
       var injectedIDs: [String] = []

       // Existing injectors
       injectFoodLogs(into: context, today: today, cal: cal)
       injectWellnessLogs(into: context, today: today, cal: cal, injectedDates: &injectedDates)
       injectStressReadings(into: context, today: today, cal: cal)

       // New injectors
       injectSymptomEntries(into: context, today: today, cal: cal)
       injectFastingSessions(into: context, today: today, cal: cal, injectedDates: &injectedDates)
       injectAdherenceLogs(into: context, today: today, cal: cal, injectedIDs: &injectedIDs)
       injectJournalEntries(into: context, today: today, cal: cal, injectedDates: &injectedDates)

       do {
           try context.save()
           AppConfig.shared.mockInjectedDates = injectedDates
           AppConfig.shared.mockInjectedRecordIDs = injectedIDs
           WPLogger.app.info("Mock data injection complete")
       } catch {
           WPLogger.app.error("Mock data injection failed: \(error.localizedDescription)")
       }
   }
   ```

   Note: `injectWellnessLogs` needs a minor signature update to accept `injectedDates: inout [String]` and append to it (replacing the current `AppConfig.shared.mockInjectedWellnessLogDates = injectedDates` at the end of the method).

5. **Update `deleteAll(from:)`** to handle all types:
   ```swift
   static func deleteAll(from context: ModelContext) {
       // 1. FoodLogEntry — by tag
       let foodDescriptor = FetchDescriptor<FoodLogEntry>(
           predicate: #Predicate { $0.logSource == "mock" }
       )
       if let mockFoods = try? context.fetch(foodDescriptor) {
           mockFoods.forEach { context.delete($0) }
       }

       // 2. StressReading — by tag
       let stressDescriptor = FetchDescriptor<StressReading>(
           predicate: #Predicate { $0.source == "mock" }
       )
       if let mockReadings = try? context.fetch(stressDescriptor) {
           mockReadings.forEach { context.delete($0) }
       }

       // 3. SymptomEntry — by tag (notes == "[mock]")
       let symptomDescriptor = FetchDescriptor<SymptomEntry>(
           predicate: #Predicate { $0.notes == "[mock]" }
       )
       if let mockSymptoms = try? context.fetch(symptomDescriptor) {
           mockSymptoms.forEach { context.delete($0) }
       }

       // 4. JournalEntry — by tag (promptUsed == "[mock]")
       let journalDescriptor = FetchDescriptor<JournalEntry>(
           predicate: #Predicate { $0.promptUsed == "[mock]" }
       )
       if let mockJournals = try? context.fetch(journalDescriptor) {
           mockJournals.forEach { context.delete($0) }
       }

       // 5. WellnessDayLog + FastingSession — by tracked dates
       let formatter = ISO8601DateFormatter()
       let trackedDates = AppConfig.shared.mockInjectedDates.compactMap { formatter.date(from: $0) }
       for date in trackedDates {
           let start = date
           let end = Calendar.current.date(byAdding: .second, value: 1, to: start)!

           // WellnessDayLog
           let wellnessDescriptor = FetchDescriptor<WellnessDayLog>(
               predicate: #Predicate { $0.day >= start && $0.day < end }
           )
           if let logs = try? context.fetch(wellnessDescriptor) {
               logs.forEach { context.delete($0) }
           }

           // FastingSession (by startedAt date)
           let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: start)!
           let fastingDescriptor = FetchDescriptor<FastingSession>(
               predicate: #Predicate { $0.startedAt >= start && $0.startedAt < nextDay }
           )
           if let sessions = try? context.fetch(fastingDescriptor) {
               sessions.filter { $0.completed }.forEach { context.delete($0) }
           }
       }

       // 6. AdherenceLog — by tracked UUIDs
       let trackedIDs = Set(AppConfig.shared.mockInjectedRecordIDs)
       if !trackedIDs.isEmpty {
           let adherenceDescriptor = FetchDescriptor<AdherenceLog>()
           if let allLogs = try? context.fetch(adherenceDescriptor) {
               allLogs.filter { trackedIDs.contains($0.id.uuidString) }.forEach { context.delete($0) }
           }
       }

       // 7. Save + clear tracking
       try? context.save()
       AppConfig.shared.mockInjectedDates = []
       AppConfig.shared.mockInjectedRecordIDs = []
   }
   ```

**Why**: InsightEngine's `buildWellnessContext()` queries all these models. Without mock records, insight detection for symptoms, fasting, supplements, and journals produces nothing.

**Deletion strategy summary**:
| Model | Strategy | Safe for real data? |
|---|---|---|
| FoodLogEntry | Tag: `logSource == "mock"` | Yes |
| StressReading | Tag: `source == "mock"` | Yes |
| SymptomEntry | Tag: `notes == "[mock]"` | Yes |
| JournalEntry | Tag: `promptUsed == "[mock]"` | Yes |
| WellnessDayLog | Tracked dates | Yes |
| FastingSession | Tracked dates + `completed` filter | Yes |
| AdherenceLog | Tracked UUIDs | Yes |

**Dependencies**: Step 2 (needs `mockInjectedDates` + `mockInjectedRecordIDs`)
**Risk**: Low — all deletion is tag-based or ID-tracked. No date-range heuristics that could hit real data.

---

### Phase 5: Profile UI Unification

#### Step 12. Update MockDataDebugCard to a unified toggle
**File**: `WellPlate/Features + UI/Tab/MockDataDebugCard.swift`

**Action**: Replace the inject/delete button card with a single toggle card:

<!-- RESOLVED: M3 — Documented: ProfileView must NOT have a separate onChange(of: mockModeEnabled) handler. The onToggle callback handles everything. -->
```swift
#if DEBUG
import SwiftUI

/// Unified mock mode card. Replaces both NutritionSourceDebugCard and MockDataDebugCard.
/// IMPORTANT: ProfileView must NOT have a separate onChange(of: mockModeEnabled) handler —
/// the onToggle callback is the single source of truth for flag + data changes.
struct MockModeDebugCard: View {
    @Binding var isMockMode: Bool
    let hasGroqAPIKey: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text("Mock Mode")
                    .font(.r(.headline, .semibold))
                Spacer()
                Text(isMockMode ? "Active" : "Off")
                    .font(.r(.caption2, .semibold))
                    .foregroundStyle(isMockMode ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isMockMode ? Color.green : Color.secondary).opacity(0.15))
                    )
            }

            Toggle("Enable Mock Mode", isOn: $isMockMode)
                .font(.r(.subheadline, .semibold))
                .tint(AppColors.brand)
                .onChange(of: isMockMode) { _, newValue in
                    onToggle(newValue)
                }

            if isMockMode {
                Text("All features use mock data. 30 days of food logs, wellness data, stress readings, HealthKit metrics, symptoms, fasting sessions, supplements, and journal entries.")
                    .font(.r(.caption, .medium))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(hasGroqAPIKey ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(hasGroqAPIKey ? "GROQ_API_KEY detected" : "GROQ_API_KEY missing — nutrition AI unavailable")
                        .font(.r(.caption, .medium))
                        .foregroundStyle(hasGroqAPIKey ? Color.green : Color.orange)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }
}
#endif
```

**Why**: Merges `NutritionSourceDebugCard` (toggle) + `MockDataDebugCard` (inject/delete) into one unified card with a single toggle.

**Dependencies**: None (UI only)
**Risk**: Low

---

#### Step 13. Update ProfileView to use unified card
**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`

**Action**:
1. Remove `mockDataInjected` state (line 98):
   ```swift
   // REMOVE:
   @State private var mockDataInjected: Bool = AppConfig.shared.mockDataInjected
   ```
2. Rename `showMockDataRestartAlert` → `showMockModeRestartAlert` (line 99):
   ```swift
   @State private var showMockModeRestartAlert = false
   ```
3. Replace both debug cards (lines 164–184) with one:
   ```swift
   #if DEBUG
   MockModeDebugCard(
       isMockMode: $mockModeEnabled,
       hasGroqAPIKey: hasGroqAPIKey,
       onToggle: { enabled in
           AppConfig.shared.mockMode = enabled
           if enabled {
               MockDataInjector.inject(into: modelContext)
           } else {
               MockDataInjector.deleteAll(from: modelContext)
           }
           showMockModeRestartAlert = true
       }
   )
   .padding(.horizontal, 16)
   #endif
   ```
4. **Remove** the `onChange(of: mockModeEnabled)` handler (lines 205–208) — logic is now in `onToggle`.
5. Update the alert (lines 209–215):
   ```swift
   .alert("Restart Required", isPresented: $showMockModeRestartAlert) {
       Button("OK") { }
   } message: {
       Text(mockModeEnabled
            ? "Mock mode enabled. Restart the app for all screens to use mock data."
            : "Mock mode disabled. Restart the app to use real data.")
   }
   ```
6. Update `refreshDebugNutritionState()` (lines 1056–1061) — remove `mockDataInjected` line:
   ```swift
   private func refreshDebugNutritionState() {
       mockModeEnabled = AppConfig.shared.mockMode
       hasGroqAPIKey = AppConfig.shared.hasGroqAPIKey
   }
   ```

**Why**: Single toggle replaces two separate controls. Toggle-on sets flag + injects SwiftData. Toggle-off clears SwiftData + clears flag. Restart required for factory-cached services to pick up change.

**Dependencies**: Steps 2, 11, 12
**Risk**: Low

---

#### Step 14. Delete old NutritionSourceDebugCard
**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`

**Action**: Remove the `NutritionSourceDebugCard` struct definition (lines 1558–1603). It's now merged into `MockModeDebugCard`.

**Why**: Avoids dead code. The new unified card handles both API mock and data display.

**Dependencies**: Step 13
**Risk**: Low

---

### Phase 6: Cleanup Remaining References

#### Step 15. Cleanup StressView references
**File**: `WellPlate/Features + UI/Stress/Views/StressView.swift`

**Action**: Verify no `mockDataInjected` references exist (confirmed: none found). The `#Preview` block uses explicit `MockHealthKitService` which is correct for previews — no change needed.

**Dependencies**: Step 2
**Risk**: None

---

#### Step 16. Verify InsightEngine cleanup
**File**: `WellPlate/Core/Services/InsightEngine.swift`

**Action**: Verify no `mockDataInjected` references exist after Step 6 changes. Currently the only mock reference is the `mockMode` check which we replace. No additional changes needed.

**Dependencies**: Step 6
**Risk**: None

---

<!-- RESOLVED: L1 — Added Step 17 for final grep verification -->
#### Step 17. Final verification grep
**Action**: Run a project-wide search to confirm zero `mockDataInjected` references remain:
```bash
grep -r "mockDataInjected" WellPlate/ --include="*.swift"
```
Expected: zero results.

Also verify all `HealthKitService()` direct instantiations have been replaced:
```bash
grep -r "HealthKitService()" WellPlate/ --include="*.swift"
```
Expected: zero results in non-preview, non-protocol files. The only acceptable occurrences are:
- Inside `HealthKitServiceFactory.swift` (the factory itself creates `HealthKitService()`)
- Inside `#Preview` blocks
- Inside `HealthKitService.swift` itself (if any)

**Dependencies**: All prior steps
**Risk**: None

---

## Testing Strategy

### Build Verification
```bash
# All 4 targets must build clean:
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

### Manual Verification Flows

1. **Toggle ON flow**:
   - Open Profile → flip Mock Mode toggle → see "Restart Required" alert → restart app
   - Home: activity rings show data, food log entries visible, daily insight card appears
   - Stress: stress score, vitals, factor cards all populated
   - Burn: energy and steps charts show 30-day data
   - **Sleep: sleep summaries and charts show 30-day data (THIS IS NEW — Step 10b)**
   - Wellness Calendar: tap any of last 30 days → see food, activity, stress data
   - Insights Hub: tap sparkles icon → insights generate from real pipeline (NOT hard-coded)

2. **Toggle OFF flow**:
   - Profile → flip toggle off → "Restart Required" → restart
   - All screens show empty/real data (no mock records)
   - SwiftData mock records deleted (verify via debug logs)

3. **Round-trip**: Toggle ON → restart → verify → Toggle OFF → restart → verify no mock data remains

4. **Real data safety**: If user has real food logs/wellness logs before enabling mock, verify they survive the toggle-on/off cycle.

5. **Double-injection guard**: Toggle ON → restart → go to Profile → verify toggle shows "Active" → flip off and back on → verify no duplicate data (inject guard checks existing records).

## Risks & Mitigations

- **Risk**: InsightEngine `buildWellnessContext()` returns nil because mock data doesn't pass the `domainsWith2Days >= 2` gate.
  - **Mitigation**: MockDataInjector provides 30 days across 7+ domains (food, wellness, stress, symptoms, fasting, supplements, journals + HK sleep, steps, energy, HR, exercise). The gate will easily pass. Fallback to `mockInsights()` exists.

- **Risk**: Mixed real + mock data produces confusing insights.
  - **Mitigation**: Accept for V1 — this is a DEBUG tool. Document in the restart alert.

- **Risk**: JournalEntry `@Attribute(.unique) var day` causes conflict when injecting mock entries for days with real entries.
  - **Mitigation**: `injectJournalEntries` checks `fetchCount` before inserting and skips existing days.

- **Risk**: Old `mockDataInjected` UserDefaults key lingers after code removal.
  - **Mitigation**: Harmless — unused key. Optionally clear in `MockDataInjector.deleteAll()`.

<!-- RESOLVED: L2 — Mock mode visual indicator deferred to V2 polish. Acceptable for DEBUG-only tool. -->

## Success Criteria

- [ ] Single "Mock Mode" toggle in Profile controls all mock behaviour
- [ ] `HealthKitServiceFactory.swift` exists and all VMs use it as default
- [ ] `AppConfig.mockDataInjected` property is removed
- [ ] SleepView shows 30-day mock sleep data when mock mode is on
- [ ] InsightEngine generates real insights (not hard-coded) from mock data
- [ ] BurnView, HomeView, WellnessCalendarView, SleepView all use factory
- [ ] MockDataInjector creates SymptomEntry, FastingSession, AdherenceLog, JournalEntry
- [ ] All mock records are safely deletable (tag-based or ID-tracked)
- [ ] All 4 build targets compile clean
- [ ] `grep -r "mockDataInjected" WellPlate/ --include="*.swift"` returns zero results
- [ ] Toggle ON → restart → all features show data → Toggle OFF → restart → clean state
