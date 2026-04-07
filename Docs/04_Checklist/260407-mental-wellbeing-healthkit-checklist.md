# Implementation Checklist: HealthKit Mental Wellbeing Integration (F2)

**Source Plan**: `Docs/02_Planning/Specs/260407-mental-wellbeing-healthkit-plan-RESOLVED.md`
**Date**: 2026-04-07

---

## Pre-Implementation

- [ ] Read the RESOLVED plan fully
- [ ] Verify all 5 affected files exist:
  - [ ] `WellPlate/Core/Services/HealthKitServiceProtocol.swift`
  - [ ] `WellPlate/Core/Services/HealthKitService.swift`
  - [ ] `WellPlate/Core/Services/MockHealthKitService.swift`
  - [ ] `WellPlate/Features + UI/Home/Views/HomeView.swift`
  - [ ] `WellPlate/Shared/Components/MoodCheckInCard.swift`
- [ ] Confirm clean build before starting:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```

---

## Phase 0: API Discovery

### 0.1 — Verify HKStateOfMind API surface

- [ ] Open the WellPlate project in Xcode
- [ ] In `HealthKitService.swift`, type `HKStateOfMind.` and check autocomplete for the sample type accessor
  - Verify: Record the exact expression (e.g., `HKStateOfMind.sampleType` or another form). If it doesn't autocomplete, search HealthKit headers via "Jump to Definition" on `HKStateOfMind`.
- [ ] Check the `HKStateOfMind` initializer — type `HKStateOfMind(` and record exact parameter names and types
  - Verify: Confirm parameters include `date`, `kind` (`.dailyMood`), `valence` (Double). Note if `labels` and `associations` are required or optional.
- [ ] Check the query predicate — type `HKSamplePredicate.stateOfMind` or `HKSamplePredicate<HKStateOfMind>` and verify the factory method
  - Verify: Record the exact predicate expression for use in `fetchTodayMood`.
- [ ] Check `HKHealthStore.save` — verify async overload exists for `HKStateOfMind`
  - Verify: If no async overload, plan to use `withCheckedThrowingContinuation` wrapper.
- [ ] Document all verified API signatures as a comment block (will be placed in code in Step 1.2)
  - Verify: You have 4 confirmed signatures: sample type accessor, initializer, query predicate, save method.

---

## Phase 1: Service Layer

### 1.1 — Protocol methods

- [ ] In `WellPlate/Core/Services/HealthKitServiceProtocol.swift`, add two methods after `fetchRespiratoryRate` (after line 53):
  ```swift
  // MARK: - State of Mind (Mood Sync)

  /// Write a mood check-in to HealthKit as an HKStateOfMind sample.
  func writeMood(_ mood: MoodOption) async throws

  /// Fetch today's most recent HKStateOfMind sample and reverse-map to MoodOption.
  /// Returns nil if no sample exists or HealthKit is unavailable.
  func fetchTodayMood() async throws -> MoodOption?
  ```
  - Verify: File has 2 new method signatures. Project won't compile yet (expected — conforming types need updating).

### 1.2 — HealthKitService implementation

- [ ] In `WellPlate/Core/Services/HealthKitService.swift`, add `shareTypes` computed property after `readTypes` (after line 50):
  ```swift
  private var shareTypes: Set<HKSampleType> {
      var types = Set<HKSampleType>()
      types.insert(/* verified sample type from Step 0.1 */)
      return types
  }
  ```
  - Verify: New computed property exists, uses the verified sample type accessor from Phase 0.

- [ ] In the same file, add `HKStateOfMind` sample type to `readTypes` — insert before the `return types` line (line 49):
  ```swift
  types.insert(/* verified sample type from Step 0.1 */)
  ```
  - Verify: `readTypes` now returns a set that includes the State of Mind type alongside existing quantity + sleep types.

- [ ] Update `requestAuthorization` (line 59) — change `toShare: []` to `toShare: shareTypes`:
  ```swift
  store.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
  ```
  - Verify: The `toShare` parameter is `shareTypes` (not empty array).

- [ ] Add `writeMood` method after `fetchRespiratoryRate` (after line 205), before `// MARK: - Private Helpers`:
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

      let sample = HKStateOfMind(/* verified init from Step 0.1 */)
      try await store.save(sample)  // or withCheckedThrowingContinuation if needed
  }
  ```
  - Verify: Method compiles with verified API from Phase 0. Valence mapping: awful=-1.0, bad=-0.5, okay=0.0, good=0.5, great=1.0.

- [ ] Add `fetchTodayMood` method right after `writeMood`:
  ```swift
  func fetchTodayMood() async throws -> MoodOption? {
      let start = Calendar.current.startOfDay(for: .now)
      let end = Date.now
      let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

      let descriptor = HKSampleQueryDescriptor(
          predicates: [/* verified predicate from Step 0.1 */],
          sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
          limit: 1
      )

      let results = try await descriptor.result(for: store)
      guard let latest = results.first else { return nil }

      let index = Int(round((latest.valence + 1.0) * 2.0))
      let clamped = min(max(index, 0), 4)
      return MoodOption(rawValue: clamped)
  }
  ```
  - Verify: Method compiles. Reverse-mapping math: -1.0→0(awful), -0.5→1(bad), 0.0→2(okay), 0.5→3(good), 1.0→4(great).

### 1.3 — MockHealthKitService stubs

- [ ] In `WellPlate/Core/Services/MockHealthKitService.swift`, add after `fetchRespiratoryRate` (after line 72):
  ```swift
  func writeMood(_ mood: MoodOption) async throws {
      // No-op in mock mode.
  }

  func fetchTodayMood() async throws -> MoodOption? {
      nil
  }
  ```
  - Verify: MockHealthKitService conforms to HealthKitServiceProtocol without errors.

### 1.4 — Build verification (service layer)

- [ ] Run:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: Build succeeds with 0 errors. All 3 service files compile cleanly.

---

## Phase 2: HomeView Integration

### 2.1 — Add healthSuggestedMood state

- [ ] In `WellPlate/Features + UI/Home/Views/HomeView.swift`, add after `@State private var hasLoggedMoodToday = false` (line 20):
  ```swift
  @State private var healthSuggestedMood: MoodOption?
  ```
  - Verify: New `@State` property exists. It is separate from `selectedMood` — this is critical for avoiding the onChange race condition.

### 2.2 — Replace refreshTodayMoodState()

- [ ] In the same file, replace `refreshTodayMoodState()` (lines 478–492) with:
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
          healthSuggestedMood = nil
      } else {
          hasLoggedMoodToday = false
          selectedMood = nil
          healthSuggestedMood = nil
          fetchHealthMoodSuggestion()
      }
  }
  ```
  - Verify: Function calls `fetchHealthMoodSuggestion()` when no SwiftData mood exists. `healthSuggestedMood` is always reset. `selectedMood` is only set from SwiftData (never from HealthKit).

### 2.3 — Add fetchHealthMoodSuggestion()

- [ ] Add new method directly after `refreshTodayMoodState()`:
  ```swift
  private func fetchHealthMoodSuggestion() {
      guard HealthKitService.isAvailable else { return }
      Task {
          let service = HealthKitService()
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
  - Verify: Method is guarded by `HealthKitService.isAvailable`. Calls `requestAuthorization()` before fetching (idempotent). Sets `healthSuggestedMood` — NOT `selectedMood`. Uses `WPLogger.healthKit` for error logging.

### 2.4 — Modify logMoodForTodayIfNeeded()

- [ ] Replace `logMoodForTodayIfNeeded` (lines 494–515) with:
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
          if HealthKitService.isAvailable {
              Task { try? await HealthKitService().writeMood(mood) }
          }
          healthSuggestedMood = nil
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
  - Verify: HK write is fire-and-forget (`try?`) and only runs if `isAvailable`. `healthSuggestedMood = nil` clears the suggestion on save. SwiftData save happens first — HK write is a side-effect.

### 2.5 — Pass healthSuggestedMood to MoodCheckInCard

- [ ] Update the `MoodCheckInCard` call site (line 87). Change:
  ```swift
  MoodCheckInCard(selectedMood: $selectedMood)
  ```
  To:
  ```swift
  MoodCheckInCard(selectedMood: $selectedMood, suggestion: healthSuggestedMood)
  ```
  - Verify: `suggestion` parameter passes `healthSuggestedMood`. The existing `selectedMood` binding is unchanged.

---

## Phase 3: MoodCheckInCard Suggestion UI

### 3.1 — Add suggestion parameter

- [ ] In `WellPlate/Shared/Components/MoodCheckInCard.swift`, add after `var onConfirm` (line 50):
  ```swift
  var suggestion: MoodOption? = nil
  ```
  - Verify: Default is `nil`. Existing call sites (if any besides HomeView) compile without changes.

### 3.2 — Pass isSuggested to MoodPill

- [ ] In the `ForEach` block (lines 67–74), update the `MoodPill` call. Change:
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
  - Verify: `isSuggested` is only `true` when the mood matches the suggestion AND the user hasn't selected anything yet.

### 3.3 — Add isSuggested to MoodPill struct

- [ ] In `MoodPill` struct (line 117), add property after `let isSelected: Bool` (line 120):
  ```swift
  let isSuggested: Bool
  ```
  - Verify: `MoodPill` now has 4 stored properties: `mood`, `isSelected`, `isSuggested`, `onTap`.

- [ ] Update the selection ring (lines 130–136). Change:
  ```swift
  if isSelected {
      Circle()
          .stroke(mood.accentColor.opacity(0.45), lineWidth: 2.5)
          .frame(width: 54, height: 54)
          .shadow(color: mood.accentColor.opacity(0.4), radius: 8, x: 0, y: 0)
          .transition(.scale.combined(with: .opacity))
  }
  ```
  To:
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
  - Verify: Selected mood shows solid ring (existing). Suggested mood shows dashed ring with lower opacity. Both show the glow shadow.

- [ ] Update the frosted pill background (lines 139–145). Change:
  ```swift
  Circle()
      .fill(
          isSelected
              ? mood.accentColor.opacity(0.12)
              : Color(uiColor: .systemBackground).opacity(0.6)
      )
      .frame(width: 50, height: 50)
  ```
  To:
  ```swift
  Circle()
      .fill(
          (isSelected || isSuggested)
              ? mood.accentColor.opacity(isSelected ? 0.12 : 0.06)
              : Color(uiColor: .systemBackground).opacity(0.6)
      )
      .frame(width: 50, height: 50)
  ```
  - Verify: Suggested pill has lighter tint (0.06) than selected (0.12).

- [ ] Update the label style (lines 161–164). Change:
  ```swift
  Text(mood.label)
      .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
      .foregroundStyle(isSelected ? mood.accentColor : .secondary)
      .animation(.easeInOut(duration: 0.2), value: isSelected)
  ```
  To:
  ```swift
  Text(mood.label)
      .font(.system(size: 12, weight: (isSelected || isSuggested) ? .semibold : .regular, design: .rounded))
      .foregroundStyle((isSelected || isSuggested) ? mood.accentColor : .secondary)
      .animation(.easeInOut(duration: 0.2), value: isSelected)
  ```
  - Verify: Suggested and selected moods both show semibold + accent color label.

### 3.4 — Add "Suggested from Apple Health" badge

- [ ] In the header VStack (lines 60–63), replace the subtitle. Change:
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
  - Verify: Badge shows when `suggestion != nil` and `selectedMood == nil`. Disappears once user taps any emoji. Uses pink + heart.fill to match Apple Health branding.

### 3.5 — Add preview variant

- [ ] Add a second `#Preview` block after the existing one (after line 205):
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
  - Verify: Preview shows the "Good" emoji with dashed ring + "Suggested from Apple Health" badge.

---

## Phase 4: Usage Descriptions

### 4.1 — Update HealthKit usage strings

- [ ] In Xcode: WellPlate target → Build Settings → search "Health" → update both keys (in both Debug and Release configurations):
  - `INFOPLIST_KEY_NSHealthShareUsageDescription`:
    - **From**: "WellPlate reads your activity and health data to show Burn and Sleep insights alongside your nutrition."
    - **To**: "WellPlate reads your activity, health, and mood data to show wellness insights alongside your nutrition."
  - `INFOPLIST_KEY_NSHealthUpdateUsageDescription`:
    - **From**: "Please allow this to fetch your health data in this app"
    - **To**: "WellPlate saves your daily mood check-in to Apple Health so it stays in sync with your other health data."
  - Verify: Both strings updated in Xcode build settings. Grep the pbxproj to confirm:
    ```bash
    grep "NSHealthShareUsageDescription\|NSHealthUpdateUsageDescription" WellPlate.xcodeproj/project.pbxproj
    ```

---

## Post-Implementation

- [ ] Build all 4 targets:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  ```
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  ```
  ```bash
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: All 4 targets build with 0 errors.

- [ ] Verify no regressions in existing mood flow:
  - Run on Simulator → tap a mood emoji → confirm card hides → mood badge appears in header
  - Verify: Existing mood UX unchanged when no Health suggestion is present.

- [ ] Git commit with descriptive message
