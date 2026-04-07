# Checklist Audit Report: Stress Lab (n-of-1 Experiments)

**Audit Date**: 2026-04-02
**Checklist Audited**: `Docs/04_Checklist/260402-stress-lab-checklist.md`
**Source Plan**: `Docs/02_Planning/Specs/260402-stress-lab-plan-RESOLVED.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The checklist is well-structured and covers all 7 plan steps across all 6 phases. Three issues require attention before implementation: the `Services/` subdirectory under `Stress/` does not exist and the checklist has no step to create it; `StressLabResultView` is missing a `.presentationDetents([.large])` verify step; and the "only one active experiment at a time" requirement has no manual verification gate. All issues are medium-to-low severity and do not block implementation if the implementer is aware of them.

---

## Issues Found

### MEDIUM

#### M1: `Stress/Services/` directory does not exist — no creation step in checklist

- **Location**: Pre-Implementation section; Phase 2 step 2.1
- **Problem**: Glob of `WellPlate/Features + UI/Stress/` confirms three subdirectories exist (`Views/`, `ViewModels/`, `Support/`) but `Services/` does **not** exist. Phase 2 step 2.1 instructs creation of `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift` without first creating the directory. When using Claude Code's Write tool this is handled automatically, but a human implementer following the checklist mechanically will get a filesystem error.
- **Impact**: Implementation friction; a confused implementer may place the file elsewhere (e.g. `Support/`) and break the architectural boundary.
- **Recommendation**: Add to the Pre-Implementation section:
  ```
  - [ ] Create directory `WellPlate/Features + UI/Stress/Services/` if it does not exist
    - Command: `mkdir -p "WellPlate/Features + UI/Stress/Services"`
    - Verify: directory exists before creating StressLabAnalyzer.swift
  ```

#### M2: `StressLabResultView` missing `.presentationDetents([.large])` verify step

- **Location**: Phase 5, step 5.1
- **Problem**: The RESOLVED plan (Step 6 code block) shows `StressLabResultView` has `.presentationDetents([.large])` applied. The checklist step 5.1 lists required `@State`, `@Environment`, `.task` block, and caching behavior, but never mentions `.presentationDetents([.large])`. An implementer checking off 5.1 could omit this and the result view would present at system-default detent (half-screen), inconsistent with all other Lab sheets.
- **Impact**: UX regression — result view presents at half height, cutting off the CI band and interpretation card.
- **Recommendation**: Add to step 5.1's verify:
  ```
  - Verify: `.presentationDetents([.large])` is applied to the outer NavigationStack (same as StressLabView and StressLabCreateView)
  ```

---

### LOW

#### L1: "Only one active experiment at a time" — no manual verification gate

- **Location**: Manual Verification section
- **Problem**: One of the plan's explicit requirements is "Only one active experiment at a time." The `StressLabView`'s `activeExperiment` computed var returns only the first non-complete experiment, and the "+" toolbar button is hidden when an active experiment exists. However, the manual verification checklist has no step confirming this guard actually works (e.g. "with an active experiment present, the '+' button is absent and 'Start an Experiment' button in the empty card is not shown").
- **Impact**: Low — the guard is enforced in code, but without a verify step it can silently regress.
- **Recommendation**: Add to Manual Verification:
  ```
  - [ ] With an active experiment present: "+" toolbar button is absent from StressLabView; tapping "Done" and re-entering confirms experiment persists
    - Verify: No way to create a second active experiment through the UI
  ```

#### L2: `onChange(of: selectedType)` closure style — CLAUDE.md prefers single-value form

- **Location**: Phase 4, step 4.1
- **Problem**: CLAUDE.md states "`onChange(of:)` uses old single-value closure style for consistency with existing code." The RESOLVED plan shows `onChange(of: selectedType) { ... }` using the zero-argument closure (iOS 17+ style). Existing `StressView` uses `onChange(of: scenePhase) { phase in ... }` (single-value). The plan's zero-argument form compiles correctly on iOS 26 but is inconsistent with the project pattern.
- **Impact**: Style inconsistency only — no functional impact.
- **Recommendation**: Add to step 4.1's verify:
  ```
  - Verify: onChange uses single-value closure: `.onChange(of: selectedType) { _ in ... }` or `.onChange(of: selectedType) { newType in ... }` — not zero-argument `{ }` — for consistency with StressView pattern
  ```
  Note: This is a style preference. If the plan's zero-argument form is intentional, this can be ignored.

#### L3: Pre-Implementation section has no explicit check that existing `StressSheet` cases compile after adding `.stressLab`

- **Location**: Pre-Implementation section
- **Problem**: The `StressSheet` enum `var id: String` switch is exhaustive. If the implementer adds `case stressLab` to the enum but forgets to add `case .stressLab: return "stressLab"` to the `id` switch, the compiler will error. The checklist step 6.1 does mention both edits, but the pre-implementation check doesn't mention reading the current enum to count existing cases.
- **Impact**: Compile error caught immediately — zero runtime risk. Just a time cost if overlooked.
- **Recommendation**: Step 6.1's verify already covers this ("Enum now has 6 cases" and the `id` addition). No change needed beyond the existing verify step.

---

## Verification of Coverage (Plan Step → Checklist Item)

| Plan Step | Description | Checklist Section | Status |
|-----------|-------------|-------------------|--------|
| Step 1 | `StressExperiment.swift` | 1.1 | ✅ Covered |
| Step 2 | Register in `WellPlateApp.swift` | 1.2 | ✅ Covered |
| Step 3 | `StressLabAnalyzer.swift` | 2.1 | ✅ Covered |
| Step 4 | `StressLabView.swift` | 3.1, 3.2 | ✅ Covered |
| Step 5 | `StressLabCreateView.swift` | 4.1 | ✅ Covered |
| Step 6 | `StressLabResultView.swift` | 5.1, 5.2 | ⚠️ Missing `.presentationDetents` (M2) |
| Step 7 Edit A | Add `.stressLab` to `StressSheet` | 6.1 | ✅ Covered |
| Step 7 Edit B | Toolbar "Lab" button | 6.2 | ✅ Covered |
| Step 7 Edit C | Sheet switch case | 6.3 | ✅ Covered |
| Build all 4 targets | Post-implementation build | Post-Implementation | ✅ Covered |
| Git commit | Staging and commit | Post-Implementation | ✅ Covered |

---

## Missing Elements

- [ ] `Stress/Services/` directory creation step in Pre-Implementation (M1)
- [ ] `.presentationDetents([.large])` verify in step 5.1 (M2)
- [ ] "Only one active experiment" manual verification gate (L1)

---

## Recommendations

1. **(Should fix)** Add `mkdir -p "WellPlate/Features + UI/Stress/Services"` as a pre-implementation step with a verify.
2. **(Should fix)** Add `.presentationDetents([.large])` to step 5.1's verify list.
3. **(Optional)** Add single-experiment gate to manual verification.
4. **(Optional)** Clarify `onChange` closure style preference in step 4.1 verify.
5. Proceed to RESOLVE then IMPLEMENT — no blocking issues found.
