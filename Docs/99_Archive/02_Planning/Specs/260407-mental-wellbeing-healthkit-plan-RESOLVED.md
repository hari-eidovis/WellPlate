# Implementation Plan: HealthKit Mental Wellbeing Integration (F2)

**Date**: 2026-04-07
**Strategy**: `Docs/02_Planning/Specs/260407-mental-wellbeing-healthkit-strategy.md`
**Brainstorm**: `Docs/01_Brainstorming/260407-mental-wellbeing-healthkit-brainstorm.md`
**Audit**: `Docs/03_Audits/260407-mental-wellbeing-healthkit-plan-audit.md`
**Status**: RESOLVED — Ready for Checklist

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| C1: onChange auto-save race condition | CRITICAL | **FIXED** — Redesigned prefill to use separate `healthSuggestedMood` state + `suggestion` parameter on MoodCheckInCard. `selectedMood` is never mutated during prefill, so onChange handler is never triggered. |
| H1: No HealthKit auth on Home tab | HIGH | **FIXED** — Added `requestAuthorization()` call inside `prefillMoodFromHealthIfNeeded()` before fetching. Idempotent — safe to call multiple times. |
| H2: HKStateOfMind API unverified | HIGH | **FIXED** — Added Step 0 (API Discovery) as mandatory first step. All code snippets marked with `// VERIFY:` comments. Included fallback patterns. |
| M1: Usage description strings | MEDIUM | **FIXED** — Added Step 4.1 to update both NSHealthShareUsageDescription and NSHealthUpdateUsageDescription in Xcode build settings. |
| M2: MoodCheckInCard redesign for suggestion | MEDIUM | **FIXED** — Flows from C1 fix. Phase 3 fully redesigned with `suggestion` parameter. |
| M3: HealthKitService instances lack auth state | MEDIUM | **ACKNOWLEDGED** — Documented as intentional fire-and-forget pattern. Auth is called in prefill path; write path uses `try?` to absorb failures. |
| M4: Existing users see new auth prompt | MEDIUM | **ACKNOWLEDGED** — Added test case to manual verification. Normal HealthKit behavior. |
| L1: Preview not updated | LOW | **FIXED** — Added preview variant in Step 3.4. |
| L2: No Siri/Shortcuts non-goal | LOW | **FIXED** — Added to non-goals. |

---

## Overview

Add bidirectional `HKStateOfMind` sync to WellPlate's existing mood check-in. When the user confirms a mood via `MoodCheckInCard`, write it to Apple Health as an `HKStateOfMind` sample. On page load, if today's mood hasn't been logged in SwiftData, show a suggestion from the latest `HKStateOfMind` sample in HealthKit. Show a "Suggested from Apple Health" badge when a Health suggestion is present. Five existing files modified, zero new files created.

---

## Requirements

- Write `MoodOption` → `HKStateOfMind` (valence + kind: `.dailyMood`) on mood confirmation
- Read today's latest `HKStateOfMind` → reverse-map to `MoodOption` for suggestion display
- Add `HKStateOfMind` to both read and share HealthKit authorization sets
- "Suggested from Apple Health" badge on `MoodCheckInCard` when a Health suggestion exists
- All HealthKit calls guarded by `HealthKitService.isAvailable`
- Fire-and-forget writes — HK failures never affect SwiftData mood logging
- Mock mode: `MockHealthKitService` stubs both methods (no-op write, nil read)
- HealthKit authorization requested lazily on Home tab before first mood HK operation <!-- RESOLVED: H1 — explicit about auth timing -->
- Usage descriptions updated to mention mood/State of Mind <!-- RESOLVED: M1 — new requirement -->

---

## Non-Goals

- PHQ-9/GAD-7 assessment display (requires `healthRecords` entitlement)
- 30-day mood trend chart from HealthKit
- Mood as stress factor (stress score formula change)
- Multiple-mood-per-day support
- Mood editing/deletion synced to HealthKit
- HKStateOfMind labels/associations/arousal (only valence + kind used)
- Siri Shortcuts for mood logging <!-- RESOLVED: L2 — added per audit -->

---

## Architecture Changes

| File | Change Summary |
|------|---------------|
| `WellPlate/Core/Services/HealthKitServiceProtocol.swift` | +2 protocol methods |
| `WellPlate/Core/Services/HealthKitService.swift` | +shareTypes, update auth, +2 method implementations |
| `WellPlate/Core/Services/MockHealthKitService.swift` | +2 stub methods |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | +1 state var (`healthSuggestedMood`), modify 2 functions, +1 helper, +auth call |
| `WellPlate/Shared/Components/MoodCheckInCard.swift` | +1 `suggestion` parameter, +suggestion highlighting in MoodPill, +badge UI, +preview variant |

---

## Implementation Steps

### Phase 0: API Discovery <!-- RESOLVED: H2 — new phase -->

#### Step 0.1: Verify HKStateOfMind API surface in Xcode

**Action**: Before writing any production code, open the WellPlate project in Xcode and create a temporary test (or use Xcode's "Jump to Definition" on `HKStateOfMind`) to verify:

1. **Sample type accessor**: Is it `HKStateOfMind.sampleType`, `HKSampleType.stateOfMindType()`, or something else? Record the exact expression.
2. **Initializer**: What are the exact parameter names and types for `HKStateOfMind(...)` ? Specifically: does it take `date`, `kind`, `valence`, `labels`, `associations`? Are labels/associations required or optional?
3. **Query predicate factory**: Is it `.stateOfMind(predicate)` on `HKSamplePredicate`? Or `.sample(type:predicate:)`? What generic type does the descriptor infer?
4. **Async save**: Does `store.save(_ object:)` have an async overload, or must we use `withCheckedThrowingContinuation` around the callback-based version?

**Deliverable**: A comment block at the top of the HealthKitService changes documenting the verified API signatures. All code snippets in subsequent steps use the verified signatures.

**Why**: The plan's code snippets are based on expected API patterns. iOS 18's `HKStateOfMind` is new and the exact Swift interface may differ. Spending 15 minutes on discovery prevents compile failures in Phase 1.

**Dependencies**: None.

**Risk**: If HKStateOfMind is unavailable on the project's minimum deployment target, the entire feature needs a conditional compilation guard. (Unlikely — app targets iOS 26, HKStateOfMind is iOS 18+.)

---

### Phase 1: Service Layer (Protocol + Real + Mock)

#### Step 1.1: Add protocol methods to `HealthKitServiceProtocol`

**File**: `WellPlate/Core/Services/HealthKitServiceProtocol.swift`

**Action**: Add two new methods to the protocol, after the existing `fetchRespiratoryRate` method (line 53):

```swift
// MARK: - State of Mind (Mood Sync)

/// Write a mood check-in to HealthKit as an HKStateOfMind sample.
func writeMood(_ mood: MoodOption) async throws

/// Fetch today's most recent HKStateOfMind sample and reverse-map to MoodOption.
/// Returns nil if no sample exists or HealthKit is unavailable.
func fetchTodayMood() async throws -> MoodOption?
```

**Why**: Protocol-first ensures both the real and mock services implement the same contract.

**Dependencies**: None — this is the starting point after Phase 0.

**Risk**: Low. Additive protocol change. Both conforming types must be updated before the project compiles.

---

#### Step 1.2: Implement `writeMood` and `fetchTodayMood` in `HealthKitService`

**File**: `WellPlate/Core/Services/HealthKitService.swift`

**Action — Part A**: Add a `shareTypes` computed property after `readTypes` (after line 49):

```swift
// VERIFY: Exact sampleType accessor from Step 0.1
private var shareTypes: Set<HKSampleType> {
    var types = Set<HKSampleType>()
    types.insert(HKStateOfMind.sampleType) // VERIFY: correct accessor
    return types
}
```

**Action — Part B**: Add `HKStateOfMind` to `readTypes` (inside the existing computed property, before the `return` on line 49):

```swift
types.insert(HKStateOfMind.sampleType) // VERIFY: correct accessor
```

**Action — Part C**: Update `requestAuthorization` (line 59) to include shareTypes:

Change:
```swift
store.requestAuthorization(toShare: [], read: readTypes)
```
To:
```swift
store.requestAuthorization(toShare: shareTypes, read: readTypes)
```

**Action — Part D**: Add `writeMood` implementation after the `fetchRespiratoryRate` method (after line 205), before the `// MARK: - Private Helpers` section:

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

    // VERIFY: Exact initializer from Step 0.1
    let sample = HKStateOfMind(
        date: .now,
        kind: .dailyMood,
        valence: valence,
        labels: [],
        associations: []
    )
    // VERIFY: Async save availability from Step 0.1
    try await store.save(sample)
}
```

**Action — Part E**: Add `fetchTodayMood` implementation right after `writeMood`:

```swift
func fetchTodayMood() async throws -> MoodOption? {
    let start = Calendar.current.startOfDay(for: .now)
    let end = Date.now
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

    // VERIFY: Exact predicate factory and descriptor type from Step 0.1
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

**Why**: The `HKSampleQueryDescriptor` API (iOS 15.4+) is the modern way to query HealthKit. Sort by `endDate` descending + limit 1 gives us the most recent sample.

**Dependencies**: Step 0.1 (API signatures verified), Step 1.1 (protocol methods declared).

**Risk**: Medium — reduced from original plan by Phase 0 discovery. If API doesn't match, adjust here using verified signatures.

<!-- RESOLVED: H2 — all code snippets marked with VERIFY comments, Phase 0 added -->

---

#### Step 1.3: Add stubs to `MockHealthKitService`

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

**Why**: Satisfies protocol conformance. Returns `nil` so mock mode behaves as "no Health data available."

**Dependencies**: Step 1.1.

**Risk**: Very Low.

---

#### Step 1.4: Build verification — service layer

**Action**: Run:
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```

**Why**: Confirm protocol conformance compiles and HKStateOfMind types resolve.

**Dependencies**: Steps 1.1–1.3 all complete.

---

### Phase 2: HomeView Integration

<!-- RESOLVED: C1 — entire phase redesigned to use healthSuggestedMood instead of mutating selectedMood -->

#### Step 2.1: Add `healthSuggestedMood` state to `HomeView`

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Add after `@State private var hasLoggedMoodToday = false` (line 20):

```swift
/// Mood suggestion from HealthKit — displayed visually but NOT written to selectedMood
/// to avoid triggering the onChange auto-save handler.
@State private var healthSuggestedMood: MoodOption?
```

**Why**: Separate from `selectedMood` so the existing `onChange(of: selectedMood)` handler is NOT triggered when a Health suggestion arrives. This prevents the critical race condition where prefilling `selectedMood` would auto-save to SwiftData and hide the card before the user sees it.

**Dependencies**: None.

**Risk**: Very Low.

---

#### Step 2.2: Modify `refreshTodayMoodState()` for HealthKit suggestion

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Replace the existing `refreshTodayMoodState()` (lines 478–492) with:

```swift
private func refreshTodayMoodState() {
    guard let log = fetchTodayWellnessLog() else {
        hasLoggedMoodToday = false
        selectedMood = nil
        healthSuggestedMood = nil
        fetchHealthMoodSuggestion()
        return
    }

    if let mood = log.mood {
        hasLoggedMoodToday = true
        selectedMood = mood
        healthSuggestedMood = nil  // Clear any stale suggestion
    } else {
        hasLoggedMoodToday = false
        selectedMood = nil
        healthSuggestedMood = nil
        fetchHealthMoodSuggestion()
    }
}
```

**Why**: When SwiftData has no mood for today, we fetch a Health suggestion. The suggestion is stored in `healthSuggestedMood`, NOT `selectedMood`, so the `onChange(of: selectedMood)` handler is not triggered.

**Dependencies**: Step 2.1, Step 2.3.

**Risk**: Low.

---

#### Step 2.3: Add `fetchHealthMoodSuggestion()` helper

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Add after `refreshTodayMoodState()`:

```swift
private func fetchHealthMoodSuggestion() {
    guard HealthKitService.isAvailable else { return }
    Task {
        let service = HealthKitService()
        do {
            // Ensure authorization before fetching — idempotent, only shows dialog once
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

<!-- RESOLVED: H1 — requestAuthorization() called before fetchTodayMood(). Idempotent call — shows dialog only on first invocation, no-op thereafter. -->
<!-- RESOLVED: M3 — documented: HealthKitService() is created per-call intentionally. Auth is called in this path; write path uses try? to absorb failures from unauthorized state. This is acceptable for fire-and-forget operations that run at most once per app launch. -->

**Why**: Requests HealthKit authorization before fetching (fixes H1). Sets `healthSuggestedMood` — not `selectedMood` — so the onChange auto-save is not triggered (fixes C1). Guarded by `isAvailable` to skip on Simulator.

**Dependencies**: Step 1.2 (HealthKitService must have `fetchTodayMood` and `requestAuthorization` must include State of Mind types).

**Risk**: Low. The `Task` runs on MainActor (view context), so state mutations are safe. `requestAuthorization` is idempotent — only shows the system dialog once.

---

#### Step 2.4: Add HealthKit write to `logMoodForTodayIfNeeded()`

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Replace the `logMoodForTodayIfNeeded` method (lines 494–515) with:

```swift
private func logMoodForTodayIfNeeded(_ mood: MoodOption) {
    guard !hasLoggedMoodToday else { return }

    let todayLog = fetchOrCreateTodayWellnessLog()
    if todayLog.moodRaw != nil {
        hasLoggedMoodToday = true
        selectedMood = todayLog.mood
        return
    }

    todayLog.moodRaw = mood.rawValue
    do {
        try modelContext.save()
        // Sync to Apple Health (fire-and-forget)
        if HealthKitService.isAvailable {
            Task { try? await HealthKitService().writeMood(mood) }
        }
        healthSuggestedMood = nil  // Clear suggestion after user confirms
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            hasLoggedMoodToday = true
        }
    } catch {
        hasLoggedMoodToday = false
        selectedMood = nil
        WPLogger.home.error("Mood save failed: \(error.localizedDescription)")
    }
}
```

**Why**: Write to HK only after SwiftData succeeds. `try?` ensures HK failure is silent. `healthSuggestedMood = nil` clears the suggestion since the user has now confirmed a mood (whether it was the suggested one or a different one).

**Dependencies**: Step 1.2 (HealthKitService must have `writeMood`).

**Risk**: Low. Fire-and-forget `Task` with `try?` — no error propagation.

---

#### Step 2.5: Pass `healthSuggestedMood` to `MoodCheckInCard`

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Action**: Update the `MoodCheckInCard` call site (line 87):

Change:
```swift
MoodCheckInCard(selectedMood: $selectedMood)
```
To:
```swift
MoodCheckInCard(selectedMood: $selectedMood, suggestion: healthSuggestedMood)
```

**Why**: Passes the Health suggestion to the card for visual highlighting and badge display.

**Dependencies**: Step 3.1 (MoodCheckInCard must accept the `suggestion` parameter).

**Risk**: Very Low.

---

#### Step 2.6: Build verification — HomeView integration

**Action**: Run the same xcodebuild command.

**Dependencies**: Steps 2.1–2.5 + Phase 3 all complete.

---

### Phase 3: MoodCheckInCard Suggestion UI

<!-- RESOLVED: C1 + M2 — entire phase redesigned. Uses suggestion parameter instead of isFromHealth boolean. MoodPill shows suggestion with distinct visual style. -->

#### Step 3.1: Add `suggestion` parameter to `MoodCheckInCard`

**File**: `WellPlate/Shared/Components/MoodCheckInCard.swift`

**Action**: Add parameter after `onConfirm` (line 51):

```swift
/// Mood suggested from Apple Health — shown with a visual hint but not committed until user taps.
var suggestion: MoodOption? = nil
```

Default `nil` ensures all existing call sites compile without changes.

**Why**: Allows the card to visually indicate a Health suggestion without interfering with the `selectedMood` binding.

**Dependencies**: None.

**Risk**: Very Low.

---

#### Step 3.2: Update MoodPill to show suggestion highlighting

**File**: `WellPlate/Shared/Components/MoodCheckInCard.swift`

**Action**: Pass a new `isSuggested` flag to `MoodPill` in the `ForEach` block (lines 67–74). Update the call:

Change:
```swift
MoodPill(
    mood: mood,
    isSelected: selectedMood == mood
) {
    handleTap(mood)
}
```
To:
```swift
MoodPill(
    mood: mood,
    isSelected: selectedMood == mood,
    isSuggested: suggestion == mood && selectedMood == nil
) {
    handleTap(mood)
}
```

Then update `MoodPill` to accept and use `isSuggested`:

**In `MoodPill` struct** (line 118), add parameter:

```swift
let isSuggested: Bool
```

**In `MoodPill.body`**, update the visual state to handle the suggestion. The selection ring (lines 130–136) should also appear for suggestions, with a lighter style:

Change the `if isSelected` block to:
```swift
if isSelected || isSuggested {
    Circle()
        .stroke(
            mood.accentColor.opacity(isSelected ? 0.45 : 0.25),
            style: StrokeStyle(lineWidth: isSelected ? 2.5 : 2, dash: isSuggested && !isSelected ? [4, 3] : [])
        )
        .frame(width: 54, height: 54)
        .shadow(color: mood.accentColor.opacity(isSelected ? 0.4 : 0.2), radius: 8, x: 0, y: 0)
        .transition(.scale.combined(with: .opacity))
}
```

And update the frosted pill background:
```swift
Circle()
    .fill(
        (isSelected || isSuggested)
            ? mood.accentColor.opacity(isSelected ? 0.12 : 0.06)
            : Color(uiColor: .systemBackground).opacity(0.6)
    )
    .frame(width: 50, height: 50)
```

And update the label style:
```swift
Text(mood.label)
    .font(.system(size: 12, weight: (isSelected || isSuggested) ? .semibold : .regular, design: .rounded))
    .foregroundStyle((isSelected || isSuggested) ? mood.accentColor : .secondary)
    .animation(.easeInOut(duration: 0.2), value: isSelected)
```

**Why**: The dashed ring + lower opacity distinguishes a suggestion from a user selection. The user can clearly see which mood was suggested but the UI communicates "this isn't committed yet."

**Dependencies**: Step 3.1.

**Risk**: Low. Visual change only — no binding or state mutation.

---

#### Step 3.3: Add "Suggested from Apple Health" badge to header

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
if suggestion != nil && selectedMood == nil {
    Label("Suggested from Apple Health", systemImage: "heart.fill")
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.pink.opacity(0.8))
} else {
    Text("Tap to check in with yourself")
        .font(.system(size: 14, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)
}
```

**Why**: Badge shows only when there's a Health suggestion AND the user hasn't selected anything yet. Once the user taps any emoji (`selectedMood` becomes non-nil), the badge disappears and the normal subtitle returns. Uses SF Symbol `heart.fill` and pink to match Apple Health's branding.

**Dependencies**: Step 3.1.

**Risk**: Low.

---

#### Step 3.4: Add preview variant for suggestion state <!-- RESOLVED: L1 — new step -->

**File**: `WellPlate/Shared/Components/MoodCheckInCard.swift`

**Action**: Add a second `#Preview` block after the existing one (after line 205):

```swift
#Preview("Mood — Health Suggestion") {
    struct PreviewWrapper: View {
        @State private var mood: MoodOption? = nil
        var body: some View {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                MoodCheckInCard(selectedMood: $mood, suggestion: .good)
                    .padding(.horizontal, 16)
            }
        }
    }
    return PreviewWrapper()
}
```

**Why**: Enables quick visual iteration on the suggestion badge and dashed-ring styling in Xcode Previews.

**Dependencies**: Steps 3.1–3.3.

**Risk**: Very Low.

---

### Phase 4: Usage Descriptions & Final Verification

<!-- RESOLVED: M1 — new phase for usage string updates -->

#### Step 4.1: Update HealthKit usage descriptions

**File**: Xcode build settings (or `WellPlate.xcodeproj/project.pbxproj`)

**Action**: In Xcode, navigate to WellPlate target → Build Settings → search "Health". Update:

| Key | Current Value | New Value |
|-----|---------------|-----------|
| `INFOPLIST_KEY_NSHealthShareUsageDescription` | "WellPlate reads your activity and health data to show Burn and Sleep insights alongside your nutrition." | "WellPlate reads your activity, health, and mood data to show wellness insights alongside your nutrition." |
| `INFOPLIST_KEY_NSHealthUpdateUsageDescription` | "Please allow this to fetch your health data in this app" | "WellPlate saves your daily mood check-in to Apple Health so it stays in sync with your other health data." |

**Why**: Apple requires accurate usage descriptions. The current write description says "fetch" which is misleading for a write operation. Updated descriptions specifically mention mood/State of Mind, which is what we're adding. This reduces App Store rejection risk.

**Dependencies**: None — can be done in parallel with other phases.

**Risk**: Very Low. Description-only change.

---

#### Step 4.2: Build verification — all targets

**Action**: Run all 4 build targets:

```bash
# Main app
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build

# Extension targets (should be unaffected but verify)
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

**Dependencies**: All previous steps complete.

---

## Data Flow (Revised)

<!-- RESOLVED: C1 — data flow diagram updated to show healthSuggestedMood -->

```
User taps mood → MoodCheckInCard binding → selectedMood changes
                                                │
                                                ├── onChange(of: selectedMood) fires
                                                │         │
                                                │         └── logMoodForTodayIfNeeded(mood)
                                                │               ├── SwiftData: todayLog.moodRaw = mood.rawValue (primary)
                                                │               ├── HealthKit: writeMood(mood) (fire-and-forget)
                                                │               └── healthSuggestedMood = nil (clear suggestion)
                                                │
                                                └── Card hides (hasLoggedMoodToday = true)

App load → HomeView.refreshTodayMoodState
              │
              ├── SwiftData: check moodRaw (authoritative)
              │     ├── non-nil → use it, done. healthSuggestedMood = nil
              │     └── nil → fall through to HealthKit
              │
              └── fetchHealthMoodSuggestion() [async Task]
                    ├── requestAuthorization() (idempotent)
                    └── fetchTodayMood()
                          ├── non-nil → healthSuggestedMood = mood
                          │              (selectedMood NOT touched — onChange NOT triggered)
                          └── nil → no suggestion
```

**Key invariant**: `selectedMood` is ONLY modified by user interaction (via `MoodCheckInCard` binding) or by restoring from SwiftData. It is NEVER set by HealthKit prefill. This guarantees the `onChange` handler only fires on deliberate user action.

---

## Testing Strategy

### Build Verification

```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

### Manual Verification (Physical Device)

1. **Authorization flow**: Open app → navigate to Home tab → verify HealthKit dialog appears requesting State of Mind read+write (dialog triggered by `fetchHealthMoodSuggestion` on first load)
2. **Write path**: Log mood in WellPlate → open Apple Health → State of Mind → verify entry appears with correct valence
3. **Suggestion path**: Log a State of Mind in Apple Health app → open WellPlate (without having logged mood today) → mood picker should show dashed ring around nearest MoodOption + "Suggested from Apple Health" badge
4. **Override path**: With Health suggestion showing → tap a DIFFERENT emoji → verify SwiftData saves the user's choice (not the suggestion), badge disappears, card hides
5. **Accept suggestion path**: With Health suggestion showing → tap the SUGGESTED emoji → verify it's saved to SwiftData, card hides normally
6. **No Health data path**: On fresh install with no Health data → mood card shows normally (no suggestion ring, no badge)
7. **Mock mode**: Enable mock mode → mood card works normally (no HK calls, no suggestion)
8. **Simulator**: Build and run on Simulator — mood logging works via SwiftData; HK calls silently skipped (`isAvailable` = false)
9. **Existing user re-authorization**: On a device with existing HK permissions → open app → verify incremental authorization dialog for State of Mind appears <!-- RESOLVED: M4 — added test case -->
10. **Usage description verification**: In Settings → Privacy → Health → WellPlate → verify the updated description text appears

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `HKStateOfMind` API doesn't match code snippets | Medium | Phase 0 discovery step verifies all signatures before implementation. VERIFY comments mark each assumption. |
| Authorization dialog on Home tab surprises users | Low | Dialog is system-standard, only shown once, and clearly labels "State of Mind." Users who decline still get full SwiftData-based mood logging. |
| Multiple `HKStateOfMind` samples from different apps | Low | Query uses `limit: 1` sorted by `endDate` descending — always gets most recent. |
| Existing users see new authorization prompt | Low | Normal HealthKit behavior for new data types. One-time dialog. <!-- RESOLVED: M4 --> |
| `HealthKitService()` created per-call in fire-and-forget paths | Very Low | HKHealthStore is documented as cheap to create. Auth is called in the suggestion path; write path uses `try?`. Acceptable for operations that run at most once per app launch. <!-- RESOLVED: M3 --> |

---

## Success Criteria

- [ ] Mood confirmation in WellPlate creates an `HKStateOfMind` sample in Apple Health
- [ ] Health suggestion shown (dashed ring + badge) when no SwiftData mood exists but HK data does
- [ ] Suggestion does NOT auto-save — user must tap to confirm
- [ ] "Suggested from Apple Health" badge appears with suggestion, disappears on user tap
- [ ] HealthKit authorization dialog includes "State of Mind" under read and write
- [ ] Usage descriptions updated to mention mood sync
- [ ] All 4 build targets compile clean
- [ ] Mood logging works identically on Simulator (HK calls silently skipped)
- [ ] Mock mode unaffected — no crashes, no suggestion, no HK calls
