# Plan Audit Report: No-Watch Stress Interventions — Phase 1

**Audit Date**: 2026-04-05
**Plan Audited**: `Docs/02_Planning/Specs/260405-no-watch-interventions-plan.md`
**Auditor**: audit agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan is well-structured and the navigation approach (`.interventions` case in `StressSheet`, `NavigationStack` inside the sheet) correctly follows the Stress Lab precedent. However, it introduces `@Observable` / `import Observation` for the first time in a codebase that exclusively uses `ObservableObject` + `@StateObject` + `@Published`, creating a pattern split. Additionally, the `rise` haptic pattern has a cancellation bug the plan acknowledges but doesn't fix in the actual code. Two medium-severity issues relate to dead code in `ResetType.accentColor` and a double-bottom-padding gap when the contextual reset card is present.

---

## Issues Found

### CRITICAL

*None.*

---

### HIGH

#### H1: `InterventionTimer` uses `@Observable` / `import Observation` — codebase uses `ObservableObject` exclusively

- **Location**: Step 4 (`InterventionTimer.swift`) — `@Observable final class InterventionTimer`
- **Problem**: The entire project uses the `ObservableObject` + `@StateObject` + `@Published` pattern. Key example: `StressViewModel: ObservableObject` (consumed via `@StateObject var viewModel: StressViewModel` in `StressView`). No file in the project imports `Observation` or uses `@Observable`. Introducing it here creates an inconsistent pattern split, making the codebase harder to reason about. Session views then use `@State private var timer = InterventionTimer()` which is the Observation-framework pattern for holding `@Observable` classes — again a convention no other view follows.
- **Impact**: New developers (or future-you) must understand two different observable patterns coexisting. Could also cause subtle bugs if someone wraps `InterventionTimer` in `@StateObject` by analogy with other ViewModels, which would silently fail to observe changes.
- **Recommendation**: Convert `InterventionTimer` to use `ObservableObject` + `@Published` for consistency:

  ```swift
  final class InterventionTimer: ObservableObject {
      @Published private(set) var currentPhaseIndex: Int = 0
      @Published private(set) var phaseProgress: Double = 0
      @Published private(set) var totalProgress: Double = 0
      @Published private(set) var currentPhaseName: String = ""
      @Published private(set) var isRunning: Bool = false
      @Published private(set) var isComplete: Bool = false
      // ...
  }
  ```

  In session views, use `@StateObject`:
  ```swift
  @StateObject private var timer = InterventionTimer()
  ```

  Remove `import Observation`. This aligns with every other observable in the project.

---

#### H2: `rise` haptic cancellation bug acknowledged but not fixed in the code

- **Location**: Step 4, `fireHaptic(.rise, duration:)` method; also flagged in plan's own Risks table
- **Problem**: The `rise` pattern schedules up to ~14 `DispatchQueue.main.asyncAfter` closures at once (one every 280ms for a 4-second tense phase). When the user taps Cancel mid-phase, `timer.cancel()` stops the `Timer` tick but the already-dispatched haptic closures keep firing. This means after cancel, the user still feels 2–3 seconds of phantom haptic pulses — a broken UX during a stress-relief exercise.
- **Impact**: Phantom haptics after cancel feel buggy. The plan's Risks table says "Guard with `[weak self]` or a `cancelled` flag" but the actual code in the plan doesn't implement either guard.
- **Recommendation**: Add a `cancelled` flag to `InterventionTimer`:

  ```swift
  private var isCancelled: Bool = false

  func cancel() {
      isCancelled = true
      timer?.invalidate()
      timer = nil
      isRunning = false
  }

  func start(phases: [InterventionPhase]) {
      cancel()
      isCancelled = false
      // ... rest of start
  }
  ```

  And in `fireHaptic`, guard every async closure:
  ```swift
  case .rise:
      let interval = 0.28
      let count = max(1, Int(duration / interval) - 1)
      for i in 0..<count {
          DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
              guard let self, !self.isCancelled else { return }
              HapticService.impact(.heavy)
          }
      }
  ```

  Same guard for `.softPulse`.

---

### MEDIUM

#### M1: `ResetType.accentColor` property returns `String` but is never used — dead code

- **Location**: Step 1 (`ResetType.swift`), `accentColor` computed property
- **Problem**: Returns a `String` ("teal", "indigo") but no code in the plan references `type.accentColor`. Instead, `ResetCardRow` has its own `private var accentColor: Color` computed property, and `SessionCompleteView` has its own switch-based `accentColor`. The `ResetType.accentColor` string is dead code that could mislead developers into thinking there's a centralized color mapping when there isn't.
- **Impact**: Code confusion; no runtime issue.
- **Recommendation**: Either:
  - **A**: Remove `accentColor` from `ResetType` entirely (CLAUDE.md says "if unused, delete it completely").
  - **B**: Change it to return `Color` directly and use it everywhere, removing the duplicate color switches in `ResetCardRow` and `SessionCompleteView`:
    ```swift
    var accentColor: Color {
        switch self {
        case .pmr:  return .teal
        case .sigh: return .indigo
        }
    }
    ```
    Then reference `type.accentColor` in `ResetCardRow`, `SessionCompleteView`, etc.

  Option B is cleaner — centralizes the color mapping.

---

#### M2: Double bottom padding gap when contextual reset card is present

- **Location**: Step 5d (mainScrollView modification)
- **Problem**: The current advice section has `.padding(.bottom, 40)`. The plan adds the reset card section below it with `.padding(.top, 28).padding(.bottom, 40)`. When both are present, the gap between advice and reset is 40 + 28 = 68pt — visually oversized compared to the 28pt gap between all other sections. The plan's own note acknowledges this but doesn't resolve it.
- **Impact**: Visual inconsistency when stress is high vs. low.
- **Recommendation**: Remove `.padding(.bottom, 40)` from the advice section's VStack. Instead, add the bottom padding conditionally:
  ```swift
  // Advice section — remove .padding(.bottom, 40)
  // ── ADVICE ────
  VStack(...) { ... }
  .padding(.horizontal, 20)
  .padding(.top, 28)
  // no .padding(.bottom) here

  // ── RESET RECOMMENDATION (conditional) ──
  if viewModel.stressLevel == .high || viewModel.stressLevel == .veryHigh {
      VStack(...) { ... }
      .padding(.horizontal, 20)
      .padding(.top, 28)
      .padding(.bottom, 40)
  } else {
      Spacer().frame(height: 40)
  }
  ```
  This ensures exactly 28pt between sections and 40pt at the bottom regardless of which section is last.

---

#### M3: `InterventionsView` mixes `.r()` and `.system()` font conventions

- **Location**: Step 6 (`InterventionsView.swift`)
- **Problem**: The Done button uses `.font(.r(.body, .medium))` (project custom font extension) while the header uses `.font(.system(size: 22, weight: .bold, design: .rounded))`. Within the Stress feature, detail/lab views (`StressLabView`, `StressLabCreateView`, `VitalDetailView`, etc.) consistently use `.r()` for text, while `StressView.swift` itself uses `.system()`. Since `InterventionsView` is a sheet like `StressLabView`, it should follow the `.r()` convention for consistency with peer sheets.
- **Impact**: Visual inconsistency in font rendering between sheets.
- **Recommendation**: Convert all fonts in `InterventionsView` and `ResetCardRow` to use `.r()`:
  ```swift
  // Header
  .font(.r(.title2, .bold))
  // Subtitle
  .font(.r(.footnote, .regular))
  // Card title
  .font(.r(.body, .semibold))
  // Card subtitle
  .font(.r(.caption, .regular))
  ```
  The immersive session views (`PMRSessionView`, `SighSessionView`, `SessionCompleteView`) can keep `.system(..., design: .rounded)` — they're full-screen dark overlays with deliberately different visual language. But `InterventionsView` is a standard sheet and should match `StressLabView`.

---

### LOW

#### L1: `SessionCompleteView` fires duplicate success haptic

- **Location**: Step 9, `SessionCompleteView.onAppear` calls `HapticService.notify(.success)`
- **Problem**: The `InterventionTimer.fireHaptic(.snap)` in the last release phase of PMR already fires `HapticService.notify(.success)`. When the session completes and transitions to `SessionCompleteView`, `onAppear` fires another `.success` notification. The user gets two success haptics within ~0.3 seconds. For Sigh, the last phase fires `.softPulse` followed by the completion `.success` — less noticeable but still double.
- **Impact**: Minor UX roughness — not broken, but feels like a stutter rather than a clean completion.
- **Recommendation**: Remove the `HapticService.notify(.success)` from `SessionCompleteView.onAppear`. The timer's final phase already provides the haptic cue. Alternatively, if the completion haptic is desired, add a small delay: `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { HapticService.notify(.success) }`.

---

#### L2: Session views don't handle `scenePhase` changes during session

- **Location**: Steps 7-8 (`PMRSessionView`, `SighSessionView`)
- **Problem**: If the user backgrounds the app during a session and returns, the `InterventionTimer` continues ticking (Foundation `Timer` fires on `.common` run loop mode by default, which pauses when backgrounded). When the user returns, the timer may have "caught up" by calculating elapsed time from `phaseStartTime` relative to `Date()`. This could cause a visible jump in progress. Additionally, `UIApplication.shared.isIdleTimerDisabled` may be cleared by the system when backgrounded.
- **Impact**: Minor visual glitch on return from background; timer self-corrects since it uses wall-clock time.
- **Recommendation**: Accept for Phase 1. If polish is desired later, add `.onChange(of: scenePhase)` to pause/resume the timer or reset the session on return.

---

## Missing Elements

- [ ] No Preview for any of the new views (PMRSessionView, SighSessionView, InterventionsView, SessionCompleteView). While not blocking, previews aid development speed — at minimum add one for `InterventionsView` and `SessionCompleteView`.

---

## Unverified Assumptions

- [ ] `figure.mind.and.body` SF Symbol exists on iOS 26 — **Risk: Low** (introduced iOS 16.0, safe for iOS 26 target)
- [ ] `bolt.heart.fill` SF Symbol exists on iOS 26 — **Risk: Low** (introduced iOS 16.0, safe)
- [ ] `Timer.scheduledTimer` callback executes on main thread when timer is created on main thread — **Risk: Low** (documented Foundation behavior)
- [ ] `InterventionTimer` as `@State` (or `@StateObject` after H1 fix) in a NavigationLink destination is preserved during the push animation — **Risk: Low** (standard SwiftUI lifecycle)

---

## Questions for Clarification

1. Should the Interventions toolbar menu be gated behind HealthKit authorization? The plan gates it identically to the Lab button, but interventions don't require HealthKit. A user who hasn't granted HealthKit access can't reach the Resets menu at all. Is this intentional?

---

## Recommendations

1. **Fix H1** (use `ObservableObject` instead of `@Observable`) to maintain codebase consistency.
2. **Fix H2** (add `isCancelled` guard to haptic closures) — this is a real bug in the plan's code.
3. **Fix M1** (centralize `ResetType.accentColor` as `Color` or delete it) — removes dead code.
4. **Fix M2** (conditional bottom padding) — clean up the double-padding gap.
5. **Fix M3** (use `.r()` fonts in `InterventionsView`) — matches peer sheet conventions.
6. **Consider Q1** (ungating Interventions from HealthKit auth) — interventions are useful without HealthKit.
