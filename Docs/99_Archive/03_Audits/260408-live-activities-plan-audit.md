# Plan Audit Report: F7 — Live Activities (ActivityKit)

**Audit Date**: 2026-04-08
**Plan Version**: `Docs/02_Planning/Specs/260408-live-activities-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The plan is technically sound and well-structured with clear phases, correct ActivityKit API usage, and a smart timer strategy (`Text(timerInterval:countsDown:)` avoids polling). Two HIGH issues need resolution: the `@EnvironmentObject` injection pattern is completely novel in this codebase (zero existing usage — verified via grep), and the iOS availability guards reference iOS 16.2 while the deployment target is 18.6. Four MEDIUM issues affect F7.1 breathing integration ordering and naming. No blockers.

---

## Issues Found

### HIGH (Should Fix Before Proceeding)

#### H1: `@EnvironmentObject` is a novel pattern — consider singleton instead
- **Location**: Steps 6, 7, 12, 13 (all `@EnvironmentObject` usages)
- **Problem**: Grep confirms **zero `@EnvironmentObject` usage** anywhere in `WellPlate/`. The plan introduces this pattern for `ActivityManager` injection from `WellPlateApp` → `RootView` → sheets → session views. While technically correct (SwiftUI propagates environment through sheets and NavigationLinks), this introduces a new paradigm that:
  - Adds a crash risk: any view accessing `@EnvironmentObject` without it being provided in the ancestor chain crashes at runtime (not a compile-time error)
  - Requires future Xcode previews to manually inject the object
  - Is inconsistent with how other app-wide services are accessed (`AppConfig.shared`, `APIClientFactory.shared`, `HapticService` static methods)
- **Impact**: Runtime crash if any path to `FastingView`, `SighSessionView`, or `PMRSessionView` doesn't have `ActivityManager` in its environment
- **Recommendation**: Replace with singleton pattern: `ActivityManager.shared`. This is consistent with `AppConfig.shared`, eliminates propagation concerns, and removes the `WellPlateApp.swift` modification entirely. The `ActivityManager` is inherently a singleton (one set of system Live Activities per app).

#### H2: iOS 16.2 availability check is dead code
- **Location**: Step 3 (`ActivityManager`), strategy doc, brainstorm
- **Problem**: The deployment target is `IPHONEOS_DEPLOYMENT_TARGET = 18.6` (verified in pbxproj). The plan's strategy references `if #available(iOS 16.2, *)` guards and the brainstorm says "iOS 16.2+ required". On 18.6, ActivityKit is unconditionally available — availability checks are dead code that adds unnecessary noise.
- **Impact**: Low (dead code, not a bug), but misleading for implementers and makes the plan look unverified
- **Recommendation**: Remove all iOS version availability guards from the plan. Only `ActivityAuthorizationInfo().areActivitiesEnabled` is needed (checks whether the user has disabled Live Activities in Settings). The `import ActivityKit` is unconditional.

---

### MEDIUM (Fix During Implementation)

#### M1: Breathing activity start/`onPhaseStart` ordering conflict (F7.1)
- **Location**: Step 12, Changes 2 and 3
- **Problem**: The plan sets `timer.onPhaseStart` *before* `timer.start(phases:)` (Change 3), but calls `startBreathingActivity()` *after* `timer.start(phases:)` (Change 2). However, `InterventionTimer.start(phases:)` synchronously calls `beginPhase()` which fires `onPhaseStart?(phase)` for the first phase. This means:
  1. `onPhaseStart` fires for phase 0 → calls `updateBreathingActivity()` → `breathingActivity` is nil → guard returns (no-op)
  2. `startBreathingActivity()` then creates the activity with phase 0 info

  The result is functionally correct (phase 0 info is set by `startBreathingActivity`), but the ordering is confusing and the first `onPhaseStart` is a wasted no-op call.
- **Impact**: No bug, but confusing implementation. If someone later removes the nil guard in `updateBreathingActivity`, it would crash.
- **Recommendation**: Reorder: call `startBreathingActivity()` *before* `timer.start(phases:)`. Then `onPhaseStart` for phase 0 updates the already-existing activity (redundant but safe), and all subsequent phases update correctly.

#### M2: PMR cycle calculation unspecified (F7.1)
- **Location**: Step 13
- **Problem**: Step 13 says "Cycle calculation adjusted for PMR phase grouping" but doesn't specify the formula. PMR has 8 muscle groups × 2 phases each (tense + release) = 16 phases total (verified in `PMRSessionView.swift:32-36`). The correct calculation is:
  - `totalCycles: 8` (muscle groups, not phases)
  - `currentCycle: (timer.currentPhaseIndex / 2) + 1`
- **Impact**: Implementer must guess the calculation, risk of off-by-one or wrong grouping
- **Recommendation**: Add explicit formula to Step 13: `totalCycles = muscleGroups.count` (8), `currentCycle = (timer.currentPhaseIndex / 2) + 1`

#### M3: `BreathingActivityAttributes.totalCycles` naming is Sigh-specific (F7.1)
- **Location**: Step 8 (`BreathingActivityAttributes`), Steps 9, 12, 13
- **Problem**: The field `totalCycles` maps cleanly to Sigh (3 cycles) but not to PMR (8 muscle groups). The Live Activity view in Step 9 displays `"Cycle \(context.state.currentCycle)/\(context.attributes.totalCycles)"` — for PMR this shows "Cycle 5/8" which is semantically wrong (it should be "Group 5/8").
- **Impact**: Incorrect display text for PMR sessions
- **Recommendation**: Either:
  - (A) Rename to `totalSteps` / `currentStep` (generic) and have the view display just "5/8" without a label word, OR
  - (B) Add a `stepLabel: String` to `BreathingActivityAttributes` (e.g., "Cycle" for Sigh, "Group" for PMR) and display `"\(stepLabel) \(current)/\(total)"`

#### M4: Unnecessary `import ActivityKit` in `WellPlateApp.swift`
- **Location**: Step 6
- **Problem**: The plan adds `import ActivityKit` to `WellPlateApp.swift`. But `WellPlateApp` only creates an `ActivityManager` instance (or `ActivityManager.shared` if H1 is resolved). `ActivityManager` is defined in the same module — no import needed. The import is in `ActivityManager.swift`, which is the correct location.
- **Impact**: Unused import — minor code noise
- **Recommendation**: Remove `import ActivityKit` from Step 6. Only `ActivityManager.swift` and the widget extension files need `import ActivityKit`.

---

### LOW (Consider for Future)

#### L1: No Xcode preview compatibility strategy
- **Location**: All views that gain `@EnvironmentObject` (Steps 7, 12, 13)
- **Problem**: No Xcode previews exist for `FastingView`, `SighSessionView`, or `PMRSessionView` currently (verified via grep). However, if previews are added later, they will crash without injecting `ActivityManager`. This is moot if H1 is resolved (singleton eliminates the issue).
- **Impact**: Future developer friction, not a current bug
- **Recommendation**: If keeping `@EnvironmentObject`, add a note about preview injection. If using singleton (H1), this is automatically resolved.

#### L2: Inconsistent `staleDate` strategy between fasting and breathing
- **Location**: Steps 3 and 10
- **Problem**: Fasting activity uses `staleDate: targetEndDate.addingTimeInterval(60)` (sensible — 60s after the fast should end). Breathing activity uses `staleDate: nil` (no staleness). Since breathing sessions are short (33s for Sigh, ~60s for PMR), not setting a stale date means iOS won't auto-mark them as stale if the app crashes mid-session. The activity would persist on the Lock Screen indefinitely until the OS cleans it up (typically 8 hours).
- **Impact**: If the app crashes mid-breathing-session, the Live Activity lingers
- **Recommendation**: Set `staleDate` for breathing to `firstPhaseEndDate + totalSessionDuration + 30`. For Sigh (~33s session), this would be ~63s from now. Ensures cleanup even on crash.

#### L3: `endFastingActivityInternal` could be called on already-ended activity
- **Location**: Step 3 (`reconnectFastingActivity`)
- **Problem**: If the app was killed and relaunched after the fast's `targetEndDate` passed AND the stale date passed AND iOS already dismissed the activity, `Activity<T>.activities` would be empty — `reconnectFastingActivity()` would find nothing and skip. If the activity is stale but not yet dismissed (within the ~8 hour window), `activity.end()` on a stale activity is a documented no-op. Either way, this is safe.
- **Impact**: None — behavior is correct in all cases
- **Recommendation**: No change needed. Documenting for completeness.

---

## Missing Elements

- [ ] **Info.plist key for main app target**: Step 1 describes modifying `WellPlateWidget/Info.plist` and notes a "manual Xcode step" for the main app. Since the main app uses `GENERATE_INFOPLIST_FILE = YES`, the plan should specify the exact build setting key: `INFOPLIST_KEY_NSSupportsLiveActivities = YES`. This can be set via Xcode GUI (Target → Build Settings → search "Supports Live Activities") or via `xcconfig`.
- [ ] **Widget extension `ActivityKit` framework linking**: The widget extension may need `ActivityKit.framework` added to its "Link Binary With Libraries" build phase. The plan doesn't mention this. Modern Xcode auto-links frameworks from `import` statements, so this may be automatic — but should be verified during implementation.
- [ ] **`activitySystemActionForegroundURL`**: The plan doesn't mention handling taps on the Live Activity. When a user taps the Lock Screen Live Activity, iOS opens the app. The default URL is the app's URL scheme. Consider adding a deep link (e.g., `wellplate://fasting`) to navigate directly to `FastingView`. The existing `wellplate://stress` deep link pattern (from the stress widget plan) can be extended.

---

## Unverified Assumptions

- [ ] `Activity.request()` works from `@MainActor` context — Risk: Low (Apple's examples commonly call from main thread)
- [ ] `Text(timerInterval:countsDown:)` works correctly in `ActivityConfiguration` views — Risk: Low (documented API, but device-only verification needed)
- [ ] `PBXFileSystemSynchronizedRootGroup` allows dual target membership via manual `PBXBuildFile` entry — Risk: Low (confirmed: `SharedStressData.swift` already uses this pattern, pbxproj ref `AB100002` in `WellPlateWidget` Sources `AB100011`)
- [ ] Calling `Activity.end()` from `reconnectFastingActivity()` on an already-stale activity is a no-op — Risk: Low (documented behavior)

---

## Questions for Clarification

1. **Q1**: Should tapping the fasting Live Activity on Lock Screen deep-link to `FastingView` (via `wellplate://fasting`)? The existing stress widget uses `wellplate://stress`. If yes, this requires adding a new URL handler case.

2. **Q2**: For PMR breathing sessions, should the Live Activity display "Group 5/8" or "Step 5/8" or just "5/8"? The current plan shows "Cycle" which is Sigh-specific. (See M3)

---

## Recommendations

1. **Resolve H1** by switching to `ActivityManager.shared` singleton — eliminates `WellPlateApp.swift` modification, removes `@EnvironmentObject` novelty risk, consistent with existing service patterns
2. **Resolve H2** by removing all `if #available(iOS 16.2, *)` references — only keep `areActivitiesEnabled` check
3. **Resolve M1** by reordering `startBreathingActivity()` before `timer.start(phases:)` in Steps 12 and 13
4. **Resolve M2** by adding explicit PMR formula: `totalCycles = 8`, `currentCycle = (timer.currentPhaseIndex / 2) + 1`
5. **Resolve M3** by adding `stepLabel: String` to `BreathingActivityAttributes` — "Cycle" for Sigh, "Group" for PMR
6. Consider adding `wellplate://fasting` deep link for Live Activity taps (Q1) — can be deferred to polish
