# Checklist Audit Report: F7 — Live Activities (ActivityKit)

**Audit Date**: 2026-04-08
**Checklist**: `Docs/04_Checklist/260408-live-activities-checklist.md`
**Plan**: `Docs/02_Planning/Specs/260408-live-activities-plan-RESOLVED.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The checklist is well-structured, covers all 12 plan steps (Steps 1–12), and the ordering of operations correctly respects dependencies. Build verification is included at all critical checkpoints. Source code inspection against `FastingView.swift`, `SighSessionView.swift`, `PMRSessionView.swift`, `WellPlateWidgetBundle.swift`, and `Info.plist` confirms all insertion points are accurate. Three issues require attention before implementation proceeds: a potential race condition in `startFastingActivity` when ending an existing activity asynchronously, an unsafe array subscript in both session view patches, and a gap in the Post-Implementation file inventory check (the main app `NSSupportsLiveActivities` build setting is never formally re-verified at the end).

---

## Plan-to-Checklist Coverage

| Plan Step | Checklist Section | Covered? |
|---|---|---|
| Step 1: NSSupportsLiveActivities | Phase 1 (1.1, 1.2) | Yes |
| Step 2: FastingActivityAttributes | Phase 2 (2.1, 2.2) | Yes |
| Step 3: ActivityManager | Phase 3 (3.1–3.5) | Yes |
| Step 4: FastingLiveActivityView | Phase 4 (4.2) | Yes |
| Step 5: Register in WidgetBundle | Phase 4 (4.3, 4.4) | Yes |
| Step 6: Hook into FastingView | Phase 5 (5.1–5.4) | Yes |
| Step 7: BreathingActivityAttributes | Phase 6 (6.1, 6.2) | Yes |
| Step 8: BreathingLiveActivityView | Phase 6 (6.4) | Yes |
| Step 9: Add breathing to ActivityManager | Phase 6 (6.3) | Yes |
| Step 10: Update WidgetBundle for breathing | Phase 6 (6.5) | Yes |
| Step 11: Wire breathing into SighSessionView | Phase 6 (6.6) | Yes |
| Step 12: Wire breathing into PMRSessionView | Phase 6 (6.7) | Yes |

All plan steps have corresponding checklist items. No plan step is omitted.

---

## Issues Found

### HIGH (Should Fix Before Proceeding)

#### H1: Async race condition in `startFastingActivity` not surfaced in checklist

- **Location**: Checklist step 3.2 (ActivityManager.startFastingActivity implementation spec)
- **Problem**: The checklist spec for `startFastingActivity()` states "Ends any existing fasting activity before starting a new one" via `Task { await endFastingActivityInternal(...) }`. However, `Task { await ... }` is non-blocking — execution immediately falls through to create the new `Activity.request()` call while `endFastingActivityInternal` is still running asynchronously. This creates a window where two `Activity<FastingActivityAttributes>` instances exist simultaneously, which Apple's budget system may penalize (iOS limits to one active Live Activity per `ActivityAttributes` type per app). The resolution table in the plan notes "Ends any existing fasting activity before starting new one" as a synchronous guarantee — the async Task makes this guarantee false.
- **Impact**: On second fast start (e.g., user skips eating window), both activities may exist briefly. Apple may throw an `ActivityKit` error on the second `Activity.request()`, leaving `fastingActivity` pointing at the old (being-ended) instance.
- **Recommendation**: Add an explicit note to checklist step 3.2 that the implementer should handle this by `await`-ing the end before requesting a new activity. The simplest fix is to restructure `startFastingActivity` as `async`, or use a sequential pattern: store a flag `isEndingExistingActivity` and skip the new request until the old one ends. Alternatively, verify that Apple's docs confirm `Activity.request()` can succeed while a prior activity is being ended — if confirmed safe, document that assumption in the checklist.

---

### MEDIUM (Fix During Implementation)

#### M1: Unsafe `phases[0]` subscript in both session view patches

- **Location**: Checklist steps 6.6 (SighSessionView) and 6.7 (PMRSessionView)
- **Problem**: Both checklist steps include `let firstPhase = phases[0]` without a guard. While `phases` in `SighSessionView` always returns 9 elements (verified: 3 cycles × 3 phases, hardcoded), and `PMRSessionView.phases` always returns 16 elements (8 groups × 2 phases via `flatMap`), the subscript is technically unsafe. More critically, `phases` is a computed property in both views — it's evaluated twice: once for `phases.map(\.duration).reduce(0, +)` and again for `phases[0]`. This is fine for correctness but wasteful and creates a subtle discrepancy with the `timer.start(phases: phases)` call which evaluates it a third time.
- **Impact**: No runtime crash given current implementation, but fragile. If phases ever becomes conditionally empty (e.g., future guard or configuration), this crashes silently.
- **Recommendation**: Add a checklist sub-item: capture `phases` in a local `let` constant before the three uses (`totalDuration`, `firstPhase`, and `timer.start`). Example: `let phases = self.phases`. This also makes the three reads consistent (single evaluation).

#### M2: Post-Implementation file inventory does not verify the main app `NSSupportsLiveActivities` setting

- **Location**: Post-Implementation > Manual Xcode Verification section
- **Problem**: The Post-Implementation section verifies `WellPlateWidget/Info.plist` contains `NSSupportsLiveActivities` (correct) and that `FastingActivityAttributes.swift`/`BreathingActivityAttributes.swift` have dual target membership (correct). However, the main app Live Activities setting (Step 1.2, build setting `INFOPLIST_KEY_NSSupportsLiveActivities = YES`) is listed under "Manual Xcode Verification" but the grep verify command from step 1.2 is not repeated. Without this check, the build succeeds (the build setting doesn't block compilation) but Live Activities silently fail at runtime when `Activity.request()` is called on a device.
- **Impact**: F7.0 MVP appears functional via build verification but fails at runtime on device. The missing key causes `Activity.request()` to throw `ActivityKit.ActivityAuthorizationError` at launch.
- **Recommendation**: Add a verify step to the Post-Implementation section: `grep INFOPLIST_KEY_NSSupportsLiveActivities WellPlate.xcodeproj/project.pbxproj | grep YES` and mark it as required before device testing.

#### M3: Phase 6 ordering — `BreathingLiveActivityView` created (6.4) after it is registered in WidgetBundle (6.5), but plan Step 9 (ActivityManager breathing methods) is before Step 8 (view) and Step 10 (bundle)

- **Location**: Checklist Phase 6 step ordering (6.3, 6.4, 6.5)
- **Problem**: The checklist orders Phase 6 as: 6.1 (attributes) → 6.2 (dual membership) → 6.3 (ActivityManager methods) → 6.4 (BreathingLiveActivityView) → 6.5 (register in bundle). This is correct for build dependency order. However, step 6.3 (ActivityManager breathing methods) references `BreathingActivityAttributes` which must be dual-target-compiled before the widget target builds. The issue: step 6.2 adds dual membership for the attributes file (manual Xcode step with no build to confirm it worked), and then step 6.3 modifies the main app `ActivityManager.swift`. The widget target build isn't triggered until step 6.5's implied build at step 6.5 (no explicit build command). There is no intermediate build after 6.3 to confirm `BreathingActivityAttributes` compiled correctly in the main target before proceeding to the widget view file.
- **Impact**: Low — compilation errors would surface at the final build verification. But without a mid-Phase-6 build, errors could be hard to isolate (was it the attributes, the ActivityManager, or the view?).
- **Recommendation**: Add an intermediate build check after step 6.3: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build` to confirm the main app compiles with breathing methods before proceeding to widget-side files.

#### M4: `reconnnectBreathingActivity()` is intentionally absent but the checklist gives no rationale

- **Location**: Checklist step 6.3 (breathing ActivityManager methods)
- **Problem**: The fasting `ActivityManager` has `reconnectFastingActivity()` called from `init()` so the app reconnects to existing fasting activities after relaunch. The breathing methods have no equivalent. The checklist step 6.3 lists three methods (`startBreathingActivity`, `updateBreathingActivity`, `endBreathingActivity`) with no mention of reconnect. This is intentional (breathing sessions are transient, ~33–60 seconds, so a killed-app scenario is unlikely and the activity auto-dismisses quickly), but the checklist doesn't explain this. An implementer reading the checklist in isolation would wonder if reconnect was forgotten.
- **Impact**: No functional impact. The omission is correct by design.
- **Recommendation**: Add a checklist comment in step 6.3: "Note: No `reconnectBreathingActivity()` needed — sessions are 33–60s and self-terminate. Stale activities auto-dismiss via `staleDate`."

---

### LOW (Consider for Future)

#### L1: Checklist step 1.2 verify command uses a relative path

- **Location**: Phase 1, step 1.2
- **Problem**: The verify command is `grep INFOPLIST_KEY_NSSupportsLiveActivities WellPlate.xcodeproj/project.pbxproj`. This is a relative path. The CLAUDE.md instructions and project memory indicate build commands use relative paths from the working directory (`/Users/hariom/Desktop/WellPlate`). This is consistent with all other checklist grep commands, so it is fine in context — but if an implementer runs this from a different directory, it fails.
- **Impact**: Cosmetic — the implementer must `cd` to the project root first.
- **Recommendation**: No change needed; this matches the existing checklist style for all other verify commands.

#### L2: No checklist item for `WellPlate/Widgets/` directory existence check

- **Location**: Pre-Implementation verification
- **Problem**: The Pre-Implementation section verifies `WellPlate/Widgets/SharedStressData.swift` exists (confirming the dual-target pattern), but does not explicitly verify the `WellPlate/Widgets/` directory exists before the new `FastingActivityAttributes.swift` and `BreathingActivityAttributes.swift` files are created there. Source code inspection confirms the directory exists (glob returned `WellPlate/Widgets/SharedStressData.swift`), but the checklist doesn't verify this explicitly.
- **Impact**: No impact in practice — directory exists. But a Pre-Implementation check that fails silently if the directory was moved would mask file creation failures.
- **Recommendation**: Add: `ls WellPlate/Widgets/` to Pre-Implementation verify steps. Low priority since SharedStressData.swift check implicitly confirms it.

#### L3: `SighSessionView` cancel button — `dismiss()` called before `endBreathingActivity()` cleanup completes

- **Location**: Checklist step 6.6, cancel button patch
- **Problem**: The cancel button patch adds `ActivityManager.shared.endBreathingActivity()` before `dismiss()`. `endBreathingActivity()` wraps the async `activity.end()` call in a `Task { }`, meaning the end is dispatched but not awaited. `dismiss()` is called synchronously right after. The view will disappear and `onDisappear { timer.cancel() }` runs before the `Task` completes. This is correct behavior (the Task runs independently), but an implementer might incorrectly think the activity is ended synchronously before dismissal.
- **Impact**: No functional bug — the async Task completes independently of view lifecycle. The activity ends correctly.
- **Recommendation**: Add a checklist comment: "Note: `endBreathingActivity()` dispatches an async Task internally — `dismiss()` can safely be called immediately after."

---

## Source Code Verification

### FastingView.swift

- `handleStateTransition(from:to:)` method confirmed at lines 331–349. Checklist insertion points are accurate.
- `breakCurrentFast()` confirmed at lines 351–355. The checklist insertion point (`after session.actualEndAt = .now`) is correct.
- `configureService()` confirmed at lines 324–329. The checklist step to add code "after `previousState = fastingService.currentState`" is correct — both lines are inside the `if let schedule { }` block. The addition stays inside that block.
- `activeSession` computed property confirmed (line 43): `sessions.first(where: { $0.isActive })`. The `isActive` property is used; `breakCurrentFast()` never sets `session.isActive = false` — this is a pre-existing behavior not introduced by F7. No checklist item needed.
- **No `import ActivityKit` needed** in `FastingView.swift` — calls only go to `ActivityManager.shared` which is in the same module. Checklist correctly omits this.

### SighSessionView.swift

- `.onAppear` block confirmed at lines 79–87. `timer.onComplete` is set at line 82, `timer.start(phases: phases)` at line 86. The checklist correctly orders: (1) start Live Activity, (2) set `onPhaseStart`, (3) set `onComplete`, (4) `timer.start()`.
- `cycleNumber` is already computed as `(timer.currentPhaseIndex / 3) + 1` at line 48 — this is a property. The checklist reproduces this formula inline in the `onPhaseStart` closure, which is correct.
- Cancel button confirmed at lines 70–74: `saveSession(completed: false)` then `dismiss()`. Checklist insertion is correct.
- **Critical observation**: The plan's `onPhaseStart` callback fires for phase 0 immediately when `timer.start(phases:)` is called (confirmed: `InterventionTimer.beginPhase()` calls `onPhaseStart?()` at line 89 before starting the timer). Since `startBreathingActivity()` is called BEFORE `timer.start()` in the checklist ordering, phase 0's `onPhaseStart` correctly updates an already-existing activity. This matches M1 resolution in the RESOLVED plan.

### PMRSessionView.swift

- `.onAppear` block confirmed at lines 71–78. Same structure as Sigh. Checklist ordering is correct.
- `muscleGroups` property confirmed as array of 8 strings (lines 21–30). `muscleGroups.count` = 8. The `/ 2` formula for `groupNumber` is correct: 16 phases ÷ 2 phases/group = 8 groups.
- Cancel button confirmed at lines 62–64.
- `phases` computed property uses `flatMap` (lines 32–37) — always returns 16 non-empty elements.

### WellPlateWidgetBundle.swift

- Current content confirmed: `StressWidget()` only (lines 1–9). Checklist step 4.3 and 6.5 correctly describe adding `FastingLiveActivity()` then `BreathingLiveActivity()` in sequence.

### WellPlateWidget/Info.plist

- Current content confirmed: no `NSSupportsLiveActivities` key present. Checklist step 1.1 is needed and correct.

### WellPlate/Widgets/

- Directory confirmed exists (`WellPlate/Widgets/SharedStressData.swift` found). New attributes files can be placed here without directory creation.

---

## Missing Elements

- [ ] No mid-Phase-6 intermediate build verification (see M3)
- [ ] No Post-Implementation verify grep for main app `INFOPLIST_KEY_NSSupportsLiveActivities` (see M2)
- [ ] No rationale comment for absent `reconnectBreathingActivity()` (see M4)
- [ ] Potential race condition in `startFastingActivity` when ending existing activity (see H1) — not acknowledged in checklist

---

## Unverified Assumptions

- [ ] `Activity.request()` succeeds while a prior async `activity.end()` Task is in-flight — Risk: **Medium** (not documented by Apple; see H1)
- [ ] `phases[0]` in both session views is always non-empty — Risk: Low (confirmed by source inspection, but no runtime guard)
- [ ] `ActivityKit.framework` auto-links in WellPlateWidget from `import ActivityKit` — Risk: Low (checklist step 4.4 correctly handles this as a "if build fails" contingency)
- [ ] `InterventionTimer.onPhaseStart` fires on main thread — Risk: Low (confirmed: `Timer.scheduledTimer` callbacks run on main RunLoop; `@MainActor ActivityManager` is safe to call)

---

## Recommendations

1. **Address H1** — Add a note to checklist step 3.2 clarifying the async race window in `startFastingActivity` when ending an existing activity. Either document the assumption that Apple's ActivityKit handles this gracefully, or propose a sequential await pattern.
2. **Address M2** — Add a verify grep to the Post-Implementation section confirming `INFOPLIST_KEY_NSSupportsLiveActivities = YES` in `project.pbxproj`. This is the most consequential missing check because build succeeds but device behavior fails silently.
3. **Address M1** — Change both 6.6 and 6.7 to capture `phases` in a local `let` before the three uses, avoiding triple evaluation of the computed property and removing the implicit `phases[0]` crash risk.
4. **Address M3** — Insert an intermediate main-app build step after checklist step 6.3 to confirm `BreathingActivityAttributes` + ActivityManager breathing methods compile before moving to widget-extension files.
5. **Address M4** — Add a brief comment in step 6.3 explaining why `reconnectBreathingActivity()` is intentionally absent.
