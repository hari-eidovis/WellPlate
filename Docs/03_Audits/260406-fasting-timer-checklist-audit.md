# Checklist Audit Report: Fasting Timer / IF Tracker

**Audit Date**: 2026-04-06
**Checklist Audited**: `Docs/04_Checklist/260406-fasting-timer-checklist.md`
**Source Plan**: `Docs/02_Planning/Specs/260406-fasting-timer-plan-RESOLVED.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The checklist is thorough and maps well to the resolved plan. Every plan step has corresponding checklist items with verify steps. Three issues found: (1) HIGH — the StressView `.sheet(item:)` switch line reference is wrong (checklist says ~line 173 but actual is line 172–174, and the new case goes after line 173 `InterventionsView()` — needs to be between `}` on line 174 and the closing `}` on line 175); (2) MEDIUM — the checklist step 2.3 session lifecycle uses force-unwrap `schedule!` which will crash if schedule is nil; (3) MEDIUM — missing `scenePhase` observation in FastingView for timer reconstruction on foreground return.

---

## Issues Found

### CRITICAL

None.

---

### HIGH

#### H1: StressView sheet switch line numbers need precision

- **Location**: Step 3.1 — "Add `case .fasting:` to `.sheet(item: $activeSheet)` switch (after `case .interventions:`, ~line 173)"
- **Problem**: Verified line numbers:
  - Line 170: `case .stressLab:`
  - Line 171: `StressLabView()`
  - Line 172: `case .interventions:`
  - Line 173: `InterventionsView()`
  - Line 174: `}`  (closes the switch)
  - Line 175: `}`  (closes the `.sheet`)
  The new `case .fasting: FastingView()` must go after line 173 (after `InterventionsView()`) and before line 174 (closing `}`). The checklist says "after `case .interventions:`, ~line 173" which is ambiguous — it could be read as replacing line 173.
- **Impact**: Implementer could insert the case in the wrong position, breaking the switch.
- **Recommendation**: Change to: "Add after line 173 (`InterventionsView()`), before the closing `}` on line 174"

---

### MEDIUM

#### M1: Force-unwrap `schedule!` in FastingView `.onAppear`

- **Location**: Step 2.3, session lifecycle — "`.onAppear`: if schedule exists, call `fastingService.configure(schedule: schedule!, activeSession: activeSession)`"
- **Problem**: The checklist uses `schedule!` (force-unwrap). Even though it's guarded by "if schedule exists", the implementer might write `if schedule != nil { ... schedule! ... }` instead of `if let schedule { ... }`. Force-unwraps are fragile and can mask bugs.
- **Recommendation**: Specify the safe pattern explicitly: `if let schedule { fastingService.configure(schedule: schedule, activeSession: activeSession) }`

---

#### M2: Missing `scenePhase` observation for timer reconstruction

- **Location**: Step 2.3, session lifecycle
- **Problem**: The plan specifies that the timer should reconstruct from persisted dates on `scenePhase == .active` (foreground return). The checklist only mentions `.onAppear` for calling `fastingService.configure(...)`. `.onAppear` fires once when the view first appears — it does NOT fire when the user returns from background. The timer will show stale `timeRemaining` until the next 1-second tick (which may not fire if the `Timer.publish` subscription was suspended in background).
- **Impact**: After returning from background, the timer could show a stale value for up to 1 second, or the state transition (eating→fasting) could be missed if it happened while backgrounded.
- **Recommendation**: Add a checklist item: "Add `@Environment(\.scenePhase) private var scenePhase` and `.onChange(of: scenePhase)` — when `.active`, re-call `fastingService.configure(schedule:activeSession:)` to reconstruct timer state from persisted dates." This matches the existing pattern in `StressView.swift` lines 133–136.

---

### LOW

#### L1: Phase 2 Gate only builds main target, not all 4

- **Location**: Phase 2 Gate — only `WellPlate` scheme
- **Problem**: Phase 1 Gate builds all 4 targets, but Phase 2 Gate only builds the main target. While the extension targets don't depend on Stress views, consistency is better.
- **Impact**: Low — extension targets won't be affected by Phase 2 changes.
- **Recommendation**: Acceptable as-is. The final Post-Implementation step builds all 4.

---

## Plan Coverage Check

| Plan Step | Checklist Items | Covered? |
|---|---|---|
| Step 1 (FastingSchedule model) | 1.1 | Yes |
| Step 2 (FastingSession model) | 1.2 | Yes |
| Step 3 (Register in WellPlateApp) | 1.3 | Yes |
| Step 3a (Extract dailyAverages) | 1.4 | Yes |
| Step 4 (FastingService) | 1.5 | Yes |
| Step 4a (Notification permissions) | 1.5 (sub-items) | Yes |
| Step 5 (FastingScheduleEditor) | 2.1 | Yes |
| Step 6 (FastingInsightChart) | 2.2 | Yes |
| Step 7 (FastingView) | 2.3 | Yes |
| Step 8 (StressView integration) | 3.1 | Yes |
| Build verification | Phase gates + Post | Yes |
| Smoke test | Post-Implementation | Yes |

All plan steps are covered. No gaps.

---

## Recommendations

1. **Resolve H1** by specifying exact insertion point: "after line 173 (`InterventionsView()`), before closing `}` on line 174"
2. **Resolve M1** by replacing `schedule!` with `if let schedule { ... }` pattern
3. **Resolve M2** by adding `scenePhase` observation item to Step 2.3
