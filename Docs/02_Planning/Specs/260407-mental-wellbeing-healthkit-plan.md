# Implementation Plan: HealthKit Mental Wellbeing Integration (F2)

**Date**: 2026-04-07
**Strategy**: `Docs/02_Planning/Specs/260407-mental-wellbeing-healthkit-strategy.md`
**Brainstorm**: `Docs/01_Brainstorming/260407-mental-wellbeing-healthkit-brainstorm.md`
**Status**: Ready for Audit

---

## Overview

Add bidirectional `HKStateOfMind` sync to WellPlate's existing mood check-in. When the user confirms a mood via `MoodCheckInCard`, write it to Apple Health as an `HKStateOfMind` sample. On page load, if today's mood hasn't been logged in SwiftData, prefill from the latest `HKStateOfMind` sample in HealthKit. Show a "From Health" badge when prefilled. Five existing files modified, zero new files created.

---

## Requirements

- Write `MoodOption` → `HKStateOfMind` (valence + kind: `.dailyMood`) on mood confirmation
- Read today's latest `HKStateOfMind` → reverse-map to `MoodOption` for prefill
- Add `HKStateOfMind` to both read and share HealthKit authorization sets
- "From Health" badge on `MoodCheckInCard` when mood was prefilled from HealthKit
- All HealthKit calls guarded by `HealthKitService.isAvailable`
- Fire-and-forget writes — HK failures never affect SwiftData mood logging
- Mock mode: `MockHealthKitService` stubs both methods (no-op write, nil read)

---

## Architecture Changes

| File | Change Summary |
|------|---------------|
| `WellPlate/Core/Services/HealthKitServiceProtocol.swift` | +2 protocol methods |
| `WellPlate/Core/Services/HealthKitService.swift` | +shareTypes, update auth, +2 method implementations |
| `WellPlate/Core/Services/MockHealthKitService.swift` | +2 stub methods |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | +1 state var, modify 2 functions, +1 helper |
| `WellPlate/Shared/Components/MoodCheckInCard.swift` | +1 parameter, +badge UI |

---

## Implementation Steps

### Phase 1: Service Layer (Protocol + Real + Mock)

#### Step 1.1: Add protocol methods to `HealthKitServiceProtocol`

**File**: `WellPlate/Core/Services/HealthKitServiceProtocol.swift`

**Action**: Add two new methods to the protocol, after the existing `fetchRespiratoryRate` method (line 53):

```swift
/// Write a mood check-in to HealthKit as an HKStateOfMind sample.
func writeMood(_ mood: MoodOption) async throws

/// Fetch today's most recent HKStateOfMind sample and reverse-map to MoodOption.
/// Returns nil if no sample exists or HealthKit is unavailable.
func fetchTodayMood() async throws -> MoodOption?
```

**Why**: Protocol-first ensures both the real and mock services implement the same contract.

**Dependencies**: None — this is the starting point.

**Risk**: Low. Additive protocol change. Both conforming types (`HealthKitService`, `MockHealthKitService`) must be updated before the project compiles.

---

#### Step 1.2: Add `import` for `MoodCheckInCard.swift`'s `MoodOption` to the protocol file

**File**: `WellPlate/Core/Services/HealthKitServiceProtocol.swift`

**Action**: No action needed — `MoodOption` is defined in `MoodCheckInCard.swift` which is in the same target. Swift's module-level visibility means it's already accessible. Verify by building after Step 1.1.

**Why**: Confirming no import is needed avoids unnecessary changes.

---

#### Step 1.3: Implement `writeMood` and `fetchTodayMood` in `HealthKitService`

**File**: `WellPlate/Core/Services/HealthKitService.swift`

**Action — Part A**: Add `import HealthKit` is already present (line 8). No change needed.

**Action — Part B**: Add a `shareTypes` computed property after `readTypes` (after line 49):

```swift
private var shareTypes: Set<HKSampleType> {
    var types = Set<HKSampleType>()
    types.insert(HKStateOfMind.sampleType)
    return types
}
```

**Action — Part C**: Add `HKStateOfMind.sampleType` to `readTypes` (inside the existing computed property, before the `return` on line 49):

```swift
types.insert(HKStateOfMind.sampleType)
```

**Action — Part D**: Update `requestAuthorization` (line 59) to include shareTypes:

Change:
```swift
store.requestAuthorization(toShare: [], read: readTypes)
```
To:
```swift
store.requestAuthorization(toShare: shareTypes, read: readTypes)
```

**Action — Part E**: Add `writeMood` implementation after the `fetchRespiratoryRate` method (after line 205), before the `// MARK: - Private Helpers` section:

```swift
// MARK: - State of Mind (Mood Sync)

func writeMood(_ mood: MoodOption) async throws {
    let valence: Double = switch mood {
    case .awful: -1.0
    case .bad:   -0.5
    case .okay:   0.0
    case .good:   0.5
    case .great:  1.0
    }

    let sample = HKStateOfMind(
        date: .now,
        kind: .dailyMood,
        valence: valence,
        labels: [],
        associations: []
    )
    try await store.save(sample)
}
```

**Action — Part F**: Add `fetchTodayMood` implementation right after `writeMood`:

```swift
func fetchTodayMood() async throws -> MoodOption? {
    let start = Calendar.current.startOfDay(for: .now)
    let end = Date.now
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

    let descriptor = HKSampleQueryDescriptor(
        predicates: [.stateOfMind(predicate)],
        sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
        limit: 1
    )

    let results = try await descriptor.result(for: store)
    guard let latest = results.first else { return nil }

    // Reverse-map valence → MoodOption: snap to nearest of 5 levels
    let index = Int(round((latest.valence + 1.0) * 2.0))
    let clamped = min(max(index, 0), 4)
    return MoodOption(rawValue: clamped)
}
```

**Why**: The `HKSampleQueryDescriptor` API (iOS 15.4+) is the modern way to query HealthKit — avoids callback-based `HKSampleQuery`. Sort by `endDate` descending + limit 1 gives us the most recent sample.

**Dependencies**: Step 1.1 (protocol must have the methods declared first for the compiler).

**Risk**: Medium. `HKStateOfMind` initializer and `HKSampleQueryDescriptor` predicate syntax must match the actual iOS 18+ API. **Verify exact API surface via Xcode autocomplete during implementation.** The `.stateOfMind()` predicate factory and `HKStateOfMind(date:kind:valence:labels:associations:)` init are the expected signatures but may differ slightly.

---

#### Step 1.4: Add stubs to `MockHealthKitService`

**File**: `WellPlate/Core/Services/MockHealthKitService.swift`

**Action**: Add after the existing `fetchRespiratoryRate` method (after line 72):

```swift
func writeMood(_ mood: MoodOption) async throws {
    // No-op in mock mode.
}

func fetchTodayMood() async throws -> MoodOption? {
    nil
}
```

**Why**: Satisfies the protocol conformance. Returns `nil` so mock mode behaves as "no Health data available" — the mood card shows normally without prefill.

**Dependencies**: Step 1.1.

**Risk**: Very Low.

---

#### Step 1.5: Build verification — service layer

**Action**: Run:
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```

**Why**: Confirm protocol conformance compiles. `HKStateOfMind` types compile on Simulator even though runtime calls will fail (guarded by `isAvailable`).

**Dependencies**: Steps 1.1–1.4 all complete.

**Risk**: If `HKStateOfMind` API doesn't match expectations, this build will fail and we'll need to adjust in Step 1.3.

---

### Phase 2: HomeView Integration

#### Step 2.1: Add `isMoodFromHealth` state to `HomeView`

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Add after `@State private var hasLoggedMoodToday = false` (line 20):

```swift
@State private var isMoodFromHealth = false
```

**Why**: Tracks whether the current `selectedMood` was prefilled from HealthKit. Passed to `MoodCheckInCard` to control badge visibility.

**Dependencies**: None.

**Risk**: Very Low.

---

#### Step 2.2: Modify `refreshTodayMoodState()` for HealthKit prefill

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Replace the existing `refreshTodayMoodState()` (lines 478–492) with:

```swift
private func refreshTodayMoodState() {
    guard let log = fetchTodayWellnessLog() else {
        hasLoggedMoodToday = false
        selectedMood = nil
        isMoodFromHealth = false
        prefillMoodFromHealthIfNeeded()
        return
    }

    if let mood = log.mood {
        hasLoggedMoodToday = true
        selectedMood = mood
        isMoodFromHealth = false
    } else {
        hasLoggedMoodToday = false
        selectedMood = nil
        isMoodFromHealth = false
        prefillMoodFromHealthIfNeeded()
    }
}
```

**Why**: When SwiftData has no mood for today, we fall through to HealthKit prefill. The `isMoodFromHealth` flag is reset on every refresh to avoid stale state.

**Dependencies**: Step 2.1, Step 2.3.

**Risk**: Low.

---

#### Step 2.3: Add `prefillMoodFromHealthIfNeeded()` helper

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Add after `refreshTodayMoodState()`:

```swift
private func prefillMoodFromHealthIfNeeded() {
    guard HealthKitService.isAvailable else { return }
    Task {
        do {
            if let mood = try await HealthKitService().fetchTodayMood() {
                selectedMood = mood
                isMoodFromHealth = true
            }
        } catch {
            WPLogger.healthKit.error("Mood prefill from Health failed: \(error.localizedDescription)")
        }
    }
}
```

**Why**: Async HealthKit query wrapped in a `Task` since `refreshTodayMoodState` is synchronous. Guarded by `isAvailable` to skip on Simulator. Creates a new `HealthKitService()` instance — this is lightweight (just wraps `HKHealthStore`) and matches the fire-and-forget pattern.

**Dependencies**: Step 1.3 (HealthKitService must have `fetchTodayMood`).

**Risk**: Low. The `Task` runs on MainActor (view context), so state mutations are safe.

---

#### Step 2.4: Add HealthKit write to `logMoodForTodayIfNeeded()`

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: After the successful `modelContext.save()` and before the animation block (between lines 506–508), add the HealthKit write:

```swift
todayLog.moodRaw = mood.rawValue
do {
    try modelContext.save()
    // Sync to Apple Health (fire-and-forget)
    if HealthKitService.isAvailable {
        Task { try? await HealthKitService().writeMood(mood) }
    }
    isMoodFromHealth = false
    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
        hasLoggedMoodToday = true
    }
} catch {
    hasLoggedMoodToday = false
    selectedMood = nil
    WPLogger.home.error("Mood save failed: \(error.localizedDescription)")
}
```

**Why**: Write to HK only after SwiftData succeeds. `try?` ensures HK failure is silent. `isMoodFromHealth = false` clears the badge since the user confirmed the mood (even if it was prefilled).

**Dependencies**: Step 1.3 (HealthKitService must have `writeMood`).

**Risk**: Low. Fire-and-forget `Task` with `try?` — no error propagation.

---

#### Step 2.5: Pass `isMoodFromHealth` to `MoodCheckInCard`

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Update the `MoodCheckInCard` call site (line 87):

Change:
```swift
MoodCheckInCard(selectedMood: $selectedMood)
```
To:
```swift
MoodCheckInCard(selectedMood: $selectedMood, isFromHealth: isMoodFromHealth)
```

**Dependencies**: Step 3.1 (MoodCheckInCard must accept the parameter).

**Risk**: Very Low.

---

#### Step 2.6: Build verification — HomeView integration

**Action**: Run the same xcodebuild command.

**Dependencies**: Steps 2.1–2.5 + Phase 3 all complete.

---

### Phase 3: MoodCheckInCard Badge UI

#### Step 3.1: Add `isFromHealth` parameter to `MoodCheckInCard`

**File**: `WellPlate/Shared/Components/MoodCheckInCard.swift`

**Action**: Add parameter after `onConfirm` (line 51):

```swift
var isFromHealth: Bool = false
```

Default `false` ensures all existing call sites compile without changes.

**Why**: Controls visibility of the "From Health" badge.

**Dependencies**: None.

**Risk**: Very Low.

---

#### Step 3.2: Add "From Health" badge to header

**File**: `WellPlate/Shared/Components/MoodCheckInCard.swift`

**Action**: Modify the header `VStack` (lines 54–63) to include a conditional badge. Replace the subtitle text:

Change:
```swift
Text("Tap to check in with yourself")
    .font(.system(size: 14, weight: .regular, design: .rounded))
    .foregroundStyle(.secondary)
```
To:
```swift
if isFromHealth {
    Label("Suggested from Apple Health", systemImage: "heart.fill")
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.pink.opacity(0.8))
} else {
    Text("Tap to check in with yourself")
        .font(.system(size: 14, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)
}
```

**Why**: When mood is prefilled from Health, the subtitle changes to indicate the source. Uses SF Symbol `heart.fill` to match Apple Health's branding. Pink color matches Health app's accent. Disappears when user confirms (because `isMoodFromHealth` resets to `false` in Step 2.4, and the card hides once `hasLoggedMoodToday` is `true`).

**Dependencies**: Step 3.1.

**Risk**: Low. The badge only shows transiently when mood is prefilled and the card is visible (before confirmation). Subtle, non-disruptive.

---

## Testing Strategy

### Build Verification

```bash
# Main app
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build

# Extension targets (should be unaffected but verify)
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

### Manual Verification (Physical Device)

1. **Fresh authorization flow**: Delete app → reinstall → onboarding should now request State of Mind read+write (verify dialog mentions "State of Mind")
2. **Write path**: Log mood in WellPlate → open Apple Health → State of Mind → verify entry appears with correct valence
3. **Read/prefill path**: Log a State of Mind in Apple Health app → open WellPlate (without having logged mood today) → mood picker should prefill with the nearest MoodOption + show "Suggested from Apple Health" badge
4. **Override path**: With prefilled mood from Health → tap a different emoji → confirm → verify SwiftData saves the user's choice (not the prefilled one) and badge disappears
5. **No Health data path**: On fresh install with no Health data → mood card should behave identically to today (no badge, no prefill)
6. **Mock mode**: Enable mock mode → mood card should work normally (no HK calls, no badge)
7. **Simulator**: Build and run on Simulator — mood logging should work via SwiftData; HK calls silently skipped (guarded by `isAvailable`)

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `HKStateOfMind` init or query API doesn't match expected signature | Medium | Verify via Xcode autocomplete in Step 1.3. The implementation may need adjustment to the actual API (e.g., different parameter names, factory methods). Build step 1.5 catches this early. |
| Authorization dialog now mentions "State of Mind" — some users might decline all Health access | Low | The dialog is shown once at onboarding. Users who decline HealthKit entirely already don't get activity/sleep data. Mood logging still works via SwiftData. |
| Multiple `HKStateOfMind` samples per day from different apps cause confusing prefill | Low | We query with `limit: 1` sorted by `endDate` descending — always get the most recent. This is the correct behavior. |
| `HealthKitService()` instantiation on every mood log/refresh is wasteful | Very Low | `HealthKitService` is a lightweight wrapper around `HKHealthStore`. `HKHealthStore()` itself is documented as cheap to create. No performance concern at the frequency of mood logging (once per day). |

---

## Success Criteria

- [ ] Mood confirmation in WellPlate creates an `HKStateOfMind` sample in Apple Health
- [ ] Mood prefilled from HealthKit when no SwiftData mood exists for today
- [ ] "Suggested from Apple Health" badge appears on prefilled mood, disappears on confirm
- [ ] HealthKit authorization dialog includes "State of Mind" under read and write
- [ ] All 4 build targets compile clean
- [ ] Mood logging works identically on Simulator (HK calls silently skipped)
- [ ] Mock mode unaffected — no crashes, no badge, no HK calls
