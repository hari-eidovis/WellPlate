# Implementation Plan: Comprehensive Mock Mode Toggle

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
- **Modified**: `AppConfig.swift` — remove `mockDataInjected`, fold into `mockMode`
- **Modified**: `MockDataInjector.swift` — add 4 new model types + update guards/cleanup
- **Modified**: `InsightEngine.swift` — use factory, remove mock shortcut
- **Modified**: 5 ViewModels — use factory instead of inline checks
- **Modified**: 4 Views — replace `mockDataInjected` references with `mockMode`
- **Modified**: `ProfileView.swift` + `MockDataDebugCard.swift` — single unified toggle

## Implementation Steps

### Phase 1: Foundation (Factory + Flag Merge)

#### Step 1. Create HealthKitServiceFactory
**File**: `WellPlate/Core/Services/HealthKitServiceFactory.swift` (NEW)

**Action**: Create a new file mirroring the pattern in `WellPlate/Networking/Real/APIClientFactory.swift`:

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
2. Remove the `mockInjectedWellnessLogDates` property (lines 127–139)
3. Remove the corresponding `Keys.mockDataInjected` and `Keys.mockInjectedWellnessLogDates` entries (lines 20–21)
4. Add a new `mockInjectedRecordIDs` property to track all injected SwiftData record UUIDs (for cleanup):

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

**Why**: Single flag (`mockMode`) now means "everything is mocked". Removes cognitive overhead of two separate flags.

**Dependencies**: Step 1
**Risk**: Low — straightforward property removal. Old `mockDataInjected` UserDefaults key is harmless if left in place.

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

**Why**: Removes scattered `mockDataInjected` checks. `MockHealthKitService.requestAuthorization()` is a no-op that sets `isAuthorized = true`, so the unified path works for both real and mock.

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

**Why**: This is the key change — InsightEngine now runs its real detection pipeline (trends, correlations, milestones, imbalances, sleep quality, reinforcements) against mock SwiftData + MockHealthKitService data. The `mockInsights()` fallback only triggers if SwiftData is empty (e.g., first launch before injection).

**Dependencies**: Step 1
**Risk**: Medium — if mock data is insufficient for the `domainsWith2Days >= 2` gate, the pipeline will return `insufficientData`. Mitigated by MockDataInjector providing 30 days across all domains.

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

### Phase 4: Expand MockDataInjector

#### Step 11. Add new model type injectors to MockDataInjector
**File**: `WellPlate/Core/Services/MockDataInjector.swift`

**Action**:
1. Change injection guard from `mockDataInjected` to `mockMode`:
   ```swift
   // Before:
   guard !AppConfig.shared.mockDataInjected else { return }
   // After:
   guard !AppConfig.shared.mockMode else { return }
   ```
   And on success:
   ```swift
   // Before:
   AppConfig.shared.mockDataInjected = true
   // After: (flag is now set by ProfileView before calling inject)
   // Just save context
   ```

2. Add 4 new injection methods:

   **`injectSymptomEntries`** — 30-day window, 2-3 symptoms per week:
   ```swift
   private static func injectSymptomEntries(into context: ModelContext, today: Date, cal: Calendar) {
       let symptoms: [(name: String, category: SymptomCategory, severityRange: ClosedRange<Int>)] = [
           ("Headache", .pain, 3...7),
           ("Bloating", .digestive, 2...5),
           ("Fatigue", .energy, 4...8),
           ("Brain Fog", .cognitive, 3...6),
       ]
       // Inject on ~10 of 30 days (every 3rd day)
       for offset in stride(from: 0, to: 30, by: 3) {
           let day = cal.date(byAdding: .day, value: -offset, to: today)!
           let symptom = symptoms[offset / 3 % symptoms.count]
           let severity = symptom.severityRange.lowerBound + (offset % (symptom.severityRange.upperBound - symptom.severityRange.lowerBound + 1))
           let ts = cal.date(bySettingHour: 9 + (offset % 8), minute: 0, second: 0, of: day) ?? day
           let entry = SymptomEntry(name: symptom.name, category: symptom.category, severity: severity, timestamp: ts)
           context.insert(entry)
       }
   }
   ```

   **`injectFastingSessions`** — 10-15 completed 16:8 sessions:
   ```swift
   private static func injectFastingSessions(into context: ModelContext, today: Date, cal: Calendar) {
       // Every other day, 16:8 fasting (completed)
       for offset in stride(from: 0, to: 30, by: 2) {
           let day = cal.date(byAdding: .day, value: -offset, to: today)!
           let startTime = cal.date(bySettingHour: 20, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: day)!)!
           let targetEnd = cal.date(byAdding: .hour, value: 16, to: startTime)!
           let session = FastingSession(startedAt: startTime, targetEndAt: targetEnd, scheduleType: .ratio16_8)
           session.actualEndAt = targetEnd
           session.completed = true
           context.insert(session)
       }
   }
   ```

   **`injectAdherenceLogs`** — 2 supplements, morning/evening, 30 days:
   ```swift
   private static func injectAdherenceLogs(into context: ModelContext, today: Date, cal: Calendar) {
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
           }
       }
   }
   ```

   **`injectJournalEntries`** — 10-15 entries across 30 days:
   ```swift
   private static func injectJournalEntries(into context: ModelContext, today: Date, cal: Calendar) {
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
       let moods = [3, 1, 4, 0, 4, 3, 4, 3, 3, 4]  // MoodOption raw values
       let stressScores: [Double?] = [28, 55, 32, 68, 22, 35, 18, 40, 30, 25]

       // Every 2-3 days
       for (i, offset) in stride(from: 0, to: 30, by: 3).enumerated() {
           guard i < texts.count else { break }
           let day = cal.date(byAdding: .day, value: -offset, to: today)!
           let startOfDay = cal.startOfDay(for: day)

           // Check for existing journal (unique per day)
           let descriptor = FetchDescriptor<JournalEntry>(
               predicate: #Predicate { $0.day == startOfDay }
           )
           guard (try? context.fetchCount(descriptor)) == 0 else { continue }

           let entry = JournalEntry(
               day: day,
               text: texts[i],
               moodRaw: moods[i],
               promptUsed: nil,
               stressScore: stressScores[i]
           )
           context.insert(entry)
       }
   }
   ```

3. Call all 4 new methods from `inject(into:)` (after existing calls):
   ```swift
   injectSymptomEntries(into: context, today: today, cal: cal)
   injectFastingSessions(into: context, today: today, cal: cal)
   injectAdherenceLogs(into: context, today: today, cal: cal)
   injectJournalEntries(into: context, today: today, cal: cal)
   ```

4. Update `deleteAll(from:)` to handle all new types:
   ```swift
   // Add after existing deletions:

   // SymptomEntry — delete all in 30-day window (mock entries have no tag)
   let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
   let symptomDescriptor = FetchDescriptor<SymptomEntry>(
       predicate: #Predicate { $0.createdAt >= thirtyDaysAgo }
   )
   // NOTE: This deletes ALL recent symptoms, not just mock ones.
   // Acceptable for DEBUG tool. For safety, could filter by known names.

   // FastingSession — delete completed sessions in 30-day window
   let fastingDescriptor = FetchDescriptor<FastingSession>(
       predicate: #Predicate { $0.startedAt >= thirtyDaysAgo && $0.completed == true }
   )

   // AdherenceLog — delete in 30-day window
   let adherenceDescriptor = FetchDescriptor<AdherenceLog>(
       predicate: #Predicate { $0.day >= thirtyDaysAgo }
   )

   // JournalEntry — delete by tracked dates (like WellnessDayLog)
   ```

   **Better approach for cleanup**: Track UUIDs of all injected records. Store them in `AppConfig.mockInjectedRecordIDs`. On delete, fetch by UUID predicate for each model type. This avoids accidentally deleting real records.

   Implementation: Collect all inserted record IDs during injection:
   ```swift
   var injectedIDs: [String] = []
   // In each inject method, after context.insert(entry):
   injectedIDs.append(entry.id.uuidString)  // for models with id: UUID
   // For models without UUID (FastingSession, JournalEntry), use persistentModelID or date tracking
   ```

   Since `FastingSession` and `JournalEntry` don't have a UUID `id` property, use date-range-based cleanup for those (same 30-day window approach as current `WellnessDayLog` deletion). For `SymptomEntry` and `AdherenceLog` which have `id: UUID`, track and delete by UUID.

**Why**: InsightEngine's `buildWellnessContext()` queries all these models. Without mock records, insight detection for symptoms, fasting, supplements, and journals produces nothing.

**Dependencies**: Step 2 (needs `mockInjectedRecordIDs`)
**Risk**: Medium — deletion strategy for models without UUID IDs requires care. Use date-range + "was mock mode on when created" heuristic.

---

### Phase 5: Profile UI Unification

#### Step 12. Update MockDataDebugCard to a unified toggle
**File**: `WellPlate/Features + UI/Tab/MockDataDebugCard.swift`

**Action**: Replace the inject/delete button card with a single toggle card:

```swift
#if DEBUG
import SwiftUI

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
2. Remove `showMockDataRestartAlert` state (line 99) — replace with `showMockModeRestartAlert`:
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
4. Remove the `onChange(of: mockModeEnabled)` handler (lines 205–208) — logic is now in `onToggle`.
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

**Why**: Single toggle replaces two separate controls. Toggle-on injects SwiftData + sets flag. Toggle-off clears SwiftData + clears flag. Restart required for factory-cached services to pick up change.

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

#### Step 15. Update StressView preview
**File**: `WellPlate/Features + UI/Stress/Views/StressView.swift`

**Action**: The preview on lines 887–896 already uses explicit `MockHealthKitService`. No change needed — it doesn't go through the factory and that's correct for previews.

However, check if there are any runtime references to `mockDataInjected` in this file:

Line 891 (from earlier grep): `healthService: MockHealthKitService(snapshot: snap)` — this is in the `#Preview` block, leave as-is.

Check for any other `mockDataInjected` references in the file and replace with `mockMode`.

**Dependencies**: Step 2
**Risk**: Low

---

#### Step 16. Remove `mockDataInjected` from InsightEngine guard
**File**: `WellPlate/Core/Services/InsightEngine.swift`

**Action**: Check if `buildWellnessContext()` has any `mockDataInjected` references. Currently it doesn't (it uses the health service via its init parameter). The only mock reference is the `mockMode` check at line 56, which we already handle in Step 6. No additional changes needed.

Verify by searching for `mockDataInjected` in the file — should find zero results after Step 6.

**Dependencies**: Step 6
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
   - Sleep: sleep summaries and charts show 30-day data (THIS IS NEW)
   - Wellness Calendar: tap any of last 30 days → see food, activity, stress data
   - Insights Hub: tap sparkles icon → insights generate from real pipeline (NOT hard-coded)

2. **Toggle OFF flow**:
   - Profile → flip toggle off → "Restart Required" → restart
   - All screens show empty/real data (no mock records)
   - SwiftData mock records deleted (verify via debug logs)

3. **Round-trip**: Toggle ON → restart → verify → Toggle OFF → restart → verify no mock data remains

4. **Real data safety**: If user has real food logs/wellness logs before enabling mock, verify they survive the toggle-on/off cycle.

## Risks & Mitigations

- **Risk**: InsightEngine `buildWellnessContext()` returns nil because mock data doesn't pass the `domainsWith2Days >= 2` gate.
  - **Mitigation**: MockDataInjector provides 30 days across 5+ domains (food, wellness, stress, sleep/HK, steps/HK). The gate will easily pass. Fallback to `mockInsights()` exists.

- **Risk**: Mixed real + mock data produces confusing insights.
  - **Mitigation**: Accept for V1 — this is a DEBUG tool. Document in the restart alert.

- **Risk**: JournalEntry `@Attribute(.unique) var day` causes conflict when injecting mock entries for days with real entries.
  - **Mitigation**: `injectJournalEntries` checks `fetchCount` before inserting and skips existing days.

- **Risk**: Deleting mock SymptomEntry/FastingSession records may accidentally delete real ones (no `source: "mock"` tag).
  - **Mitigation**: Track injected record IDs in `AppConfig.mockInjectedRecordIDs` for `SymptomEntry` and `AdherenceLog`. For `FastingSession` and `JournalEntry`, use date-range scoping combined with the fact that cleanup only runs when transitioning from mock-on to mock-off.

- **Risk**: Old `mockDataInjected` UserDefaults key lingers after code removal.
  - **Mitigation**: Harmless — unused key. Optionally clear in `MockDataInjector.deleteAll()`.

## Success Criteria

- [ ] Single "Mock Mode" toggle in Profile controls all mock behaviour
- [ ] `HealthKitServiceFactory.swift` exists and all VMs use it as default
- [ ] `AppConfig.mockDataInjected` property is removed
- [ ] SleepView shows 30-day mock sleep data when mock mode is on
- [ ] InsightEngine generates real insights (not hard-coded) from mock data
- [ ] BurnView, HomeView, WellnessCalendarView all use factory
- [ ] MockDataInjector creates SymptomEntry, FastingSession, AdherenceLog, JournalEntry
- [ ] All 4 build targets compile clean
- [ ] Toggle ON → restart → all features show data → Toggle OFF → restart → clean state
