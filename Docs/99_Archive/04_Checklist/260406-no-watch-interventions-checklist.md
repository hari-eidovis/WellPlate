# Implementation Checklist: No-Watch Stress Interventions — Phase 1 (Micro-PMR + Somatic Sigh)

**Source Plan**: `Docs/02_Planning/Specs/260405-no-watch-interventions-plan-RESOLVED.md`
**Date**: 2026-04-06

---

## Pre-Implementation

- [ ] Read and understand `Docs/02_Planning/Specs/260405-no-watch-interventions-plan-RESOLVED.md`
- [ ] Verify `WellPlate/Core/Services/HapticService.swift` exists and exposes `impact(_:)` and `notify(_:)`
- [ ] Verify `WellPlate/Features + UI/Stress/Views/StressView.swift` exists and contains `StressSheet` enum + `mainScrollView`
- [ ] Verify `WellPlate/App/WellPlateApp.swift` exists and contains `.modelContainer(for: [...])`
- [ ] Confirm no file named `ResetType.swift`, `InterventionSession.swift`, `InterventionTimer.swift`, `InterventionsView.swift`, `PMRSessionView.swift`, `SighSessionView.swift`, or `SessionCompleteView.swift` already exists

---

## Phase 1: Models & Services Foundation

### 1.1 — `ResetType` enum

- [ ] Create new file `WellPlate/Models/ResetType.swift`
  - Content: `import Foundation`, `import SwiftUI`, enum with `.pmr` and `.sigh` cases, `CaseIterable`, `Identifiable`, `Codable`, with `id`, `title`, `subtitle`, `icon`, `accentColor: Color` properties per plan Step 1
  - Verify: File exists; `ResetType.pmr.accentColor` returns `Color.teal`; `ResetType.sigh.accentColor` returns `Color.indigo`
- [ ] Build the main app target:
  - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds; no compile errors in `ResetType.swift`

### 1.2 — `InterventionSession` SwiftData model

- [ ] Create new file `WellPlate/Models/InterventionSession.swift`
  - Content: `import Foundation`, `import SwiftData`, `@Model final class InterventionSession` with `resetType: String`, `startedAt: Date`, `durationSeconds: Int`, `completed: Bool`, optional biometric fields (`preHeartRate`, `postHeartRate`, `preHRV`, `postHRV`), init(resetType: ResetType, ...), and `resolvedResetType` computed property per plan Step 2
  - Verify: File compiles; `@Model` annotation present; all nullable biometric fields declared as `Double?`

### 1.3 — Register model with the app's ModelContainer

- [ ] Edit `WellPlate/App/WellPlateApp.swift`
  - Add `InterventionSession.self` to the array in `.modelContainer(for: [...])` (line ~34)
  - Verify: Schema array now contains `FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self, InterventionSession.self`
- [ ] Build the main app target:
  - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds; SwiftData schema migrates cleanly

### 1.4 — `InterventionTimer` engine

- [ ] Create new file `WellPlate/Core/Services/InterventionTimer.swift`
  - Content: `import Foundation`, `InterventionPhase` struct, `HapticPattern` enum (`.rise`, `.snap`, `.softPulse(count:interval:)`), `final class InterventionTimer: ObservableObject` per plan Step 4
  - All state properties marked `@Published private(set) var` (currentPhaseIndex, phaseProgress, totalProgress, currentPhaseName, isRunning, isComplete)
  - **H1 fix**: Use `ObservableObject` + `@Published` (NOT `@Observable` / `import Observation`)
  - **H2 fix**: Include `private var isCancelled: Bool = false`; set `true` in `cancel()`, reset to `false` in `start()`
  - **H2 fix**: Guard every dispatched `asyncAfter` closure (both `.rise` and `.softPulse` branches) with `[weak self] in guard let self, !self.isCancelled else { return }`
  - Verify: `grep "@Observable" WellPlate/Core/Services/InterventionTimer.swift` returns no matches
  - Verify: `grep "import Observation" WellPlate/Core/Services/InterventionTimer.swift` returns no matches
  - Verify: `grep "ObservableObject" WellPlate/Core/Services/InterventionTimer.swift` returns 1 match
  - Verify: Both `asyncAfter` closures contain `!self.isCancelled` guard
- [ ] Build the main app target:
  - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds

---

## Phase 2: Session Views

### 2.1 — `SessionCompleteView` (shared, build first since session views reference it)

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/SessionCompleteView.swift`
  - Content: per plan Step 9 — takes `type: ResetType`, `durationSeconds: Int`, `onDone: () -> Void`, optional `preHeartRate/postHeartRate`, animated checkmark, HR delta section nil-gated
  - **M1 fix**: Use `type.accentColor` directly (no local accentColor computed property)
  - **L1 fix**: `onAppear` does NOT call `HapticService.notify(.success)` — only runs the checkmark spring animation
  - Verify: `grep "notify(.success)" WellPlate/Features\ +\ UI/Stress/Views/SessionCompleteView.swift` returns no matches
  - Verify: `grep "type.accentColor" WellPlate/Features\ +\ UI/Stress/Views/SessionCompleteView.swift` returns matches (≥3 usages)

### 2.2 — `PMRSessionView`

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift`
  - Content: per plan Step 7 — 8 muscle groups, tense/release phase builder, sessionContent view, progressDots, saveSession helper
  - **H1 fix**: Use `@StateObject private var timer = InterventionTimer()` (NOT `@State`)
  - Set `UIApplication.shared.isIdleTimerDisabled = true` on appear; reset to `false` on disappear
  - On complete: save session with `completed: true`, transition to `SessionCompleteView`
  - Cancel button: save session with `completed: false`, dismiss
  - Verify: `grep "@StateObject" WellPlate/Features\ +\ UI/Stress/Views/PMRSessionView.swift` returns 1 match for timer
  - Verify: `grep "@State private var timer" WellPlate/Features\ +\ UI/Stress/Views/PMRSessionView.swift` returns no matches

### 2.3 — `SighSessionView`

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/SighSessionView.swift`
  - Content: per plan Step 8 — 3 cycles × 3 phases, breathing circle with scaleEffect, cycle counter, total progress bar, saveSession helper
  - **H1 fix**: Use `@StateObject private var timer = InterventionTimer()`
  - Dark navy background (`Color(hue: 0.67, saturation: 0.15, brightness: 0.08)`)
  - Verify: `@StateObject` used for timer; scaleEffect binds to `circleScale` computed property

### 2.4 — Build verification

- [ ] Build the main app target:
  - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds; all 3 session view files compile

---

## Phase 3: Interventions Sheet Entry

### 3.1 — `InterventionsView`

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/InterventionsView.swift`
  - Content: per plan Step 6 — NavigationStack with headerSection, resetCards ForEach, Done toolbar button, `sessionView(for:)` @ViewBuilder, private `ResetCardRow` struct
  - **M3 fix**: All text uses `.r()` font convention:
    - Header title: `.font(.r(.title2, .bold))`
    - Header subtitle: `.font(.r(.footnote, .regular))`
    - Card title: `.font(.r(.body, .semibold))`
    - Card subtitle: `.font(.r(.caption, .regular))`
  - **M1 fix**: `ResetCardRow` reads `type.accentColor` directly (no private accentColor property)
  - Verify: `grep ".r(" WellPlate/Features\ +\ UI/Stress/Views/InterventionsView.swift` returns ≥4 matches
  - Verify: `grep "private var accentColor" WellPlate/Features\ +\ UI/Stress/Views/InterventionsView.swift` returns no matches
- [ ] Build the main app target:
  - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds

---

## Phase 4: StressView Integration

### 4.1 — Extend `StressSheet` enum

- [ ] Edit `WellPlate/Features + UI/Stress/Views/StressView.swift` (lines 12–30)
  - Add `case interventions` to `StressSheet` enum
  - Add `case .interventions: return "interventions"` to the `id` computed var
  - Verify: Enum compiles; `.interventions` case accessible

### 4.2 — Replace leading toolbar Button with Menu

- [ ] Edit `WellPlate/Features + UI/Stress/Views/StressView.swift` (leading ToolbarItem, ~lines 69–80)
  - Replace lone Lab button with `Menu` containing:
    - Lab button (HealthKit-gated): shown only when `(HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized`
    - Resets button (always available): sets `activeSheet = .interventions`
  - Outer guard changes to `if !viewModel.isLoading`
  - Menu label: `Image(systemName: "ellipsis.circle")` with stress-level accent color
  - **Q1 fix**: Resets button is NOT HealthKit-gated
  - Verify: Menu shows both items when authorized; Resets still visible when HealthKit is NOT authorized

### 4.3 — Handle `.interventions` in sheet switch

- [ ] Edit `WellPlate/Features + UI/Stress/Views/StressView.swift` (`.sheet(item: $activeSheet)` switch, ~lines 127–157)
  - Add `case .interventions: InterventionsView()` to the switch
  - Verify: Switch is exhaustive; no compile warning

### 4.4 — Fix advice section padding + add contextual reset card

- [ ] Edit `WellPlate/Features + UI/Stress/Views/StressView.swift` advice section in `mainScrollView`
  - **M2 fix**: Remove `.padding(.bottom, 40)` from the advice section VStack
  - Verify: Advice VStack no longer has a `.padding(.bottom, 40)` modifier
- [ ] Append new conditional section after the advice section (still inside `mainScrollView`):
  - `if viewModel.stressLevel == .high || viewModel.stressLevel == .veryHigh { ... VStack with sectionLabel("QUICK RESET") + resetRecommendationCard ... .padding(.top, 28).padding(.bottom, 40) } else { Spacer().frame(height: 40) }`
  - Verify: `stressLevel == .low` → 40pt bottom padding via Spacer; `stressLevel == .high` → reset card with 40pt bottom padding
- [ ] Add `resetRecommendationCard` computed property to `StressView` (per plan Step 5d)
  - Button with teal icon, "Try a Quick Reset" title, subtitle, chevron, card background with `.appShadow(radius: 15, y: 5)`
  - Tap action: `HapticService.impact(.light)` + `activeSheet = .interventions`
  - Verify: Tapping the card sets `activeSheet = .interventions`

### 4.5 — Build verification

- [ ] Build the main app target:
  - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds with no warnings introduced

---

## Phase 5: Manual Verification (Simulator)

- [ ] Launch app in iOS Simulator; navigate to Stress tab
- [ ] Tap leading `...` menu — verify "Resets" appears
- [ ] Tap "Resets" — verify `InterventionsView` sheet opens with PMR + Sigh cards using `.r()` fonts
- [ ] Tap "Muscle Release" — verify PMR session pushes into NavigationStack (dark background, "TENSE"/"RELEASE" labels, progress dots)
- [ ] Wait for PMR session to complete — verify `SessionCompleteView` appears with single (not doubled) haptic
- [ ] Tap "Done" — verify dismiss
- [ ] Repeat flow for "Physiological Sigh" — verify breathing circle animates through 3 cycles
- [ ] Start PMR session → immediately tap Cancel during a "Tense" phase — verify no phantom haptics fire after dismiss (H2)
- [ ] Force `stressLevel = .high` (mock or debug override) — verify contextual reset card appears below advice
- [ ] Measure bottom spacing: `stressLevel == .low` shows 40pt below advice; `stressLevel == .high` shows 28pt gap + reset card + 40pt below (M2 verification)
- [ ] Screen always-on: start a session, leave idle — verify screen does not lock; dismiss — verify idle timer resets

---

## Post-Implementation

- [ ] Build all 4 targets:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
- [ ] Review new files for unused imports, dead code, print statements
- [ ] Confirm no `@Observable` or `import Observation` anywhere in new files
- [ ] Confirm all session views use `@StateObject private var timer`
- [ ] Git commit with message: `feat: no-watch stress interventions (PMR + Sigh)`
