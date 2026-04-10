# Checklist Audit Report: 15-Day AI Insights Report

**Audit Date**: 2026-04-11
**Checklist Version**: `Docs/04_Checklist/260410-ai-insights-15day-report-checklist.md`
**Plan Version**: `Docs/02_Planning/Specs/260410-ai-insights-15day-report-plan-RESOLVED.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The checklist is comprehensive and well-ordered — every plan phase has corresponding items, all file paths are valid, dependencies are respected, and build checks are placed after each major phase. However, there is 1 critical issue (`@Generable` struct placement will cause a compile error), 1 high issue (missing `async let` tuple destructuring update), and a few medium items around `#Predicate` limitations and missing edge-case handling.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1: `@Generable` private structs in `ReportModels.swift` are inaccessible from `ReportNarrativeGenerator.swift`

- **Location**: Step 1.2 places `@Generable private struct _ReportExecutiveSummary` etc. in `ReportModels.swift`. Step 3.2 uses them in `ReportNarrativeGenerator.swift` via `session.respond(to:, generating: _ReportExecutiveSummary.self)`.
- **Problem**: `private struct` is file-scoped in Swift. A `private` type in `ReportModels.swift` cannot be referenced from `ReportNarrativeGenerator.swift`. This will produce a compile error: `'_ReportExecutiveSummary' is inaccessible due to 'private' protection level`.
- **Evidence**: Every existing `@Generable` struct in the codebase is `private` and lives in the **same file** as the service that calls it:
  - `_InsightNarrativeSchema` → `InsightEngine.swift` (line 819)
  - `_JournalPromptSchema` → `JournalPromptService.swift` (line 136)
  - `_FoodExtractionSchema` → `MealCoachService.swift` (line 129)
- **Impact**: Compile error in Phase 3. Blocks all implementation after Phase 3.
- **Recommendation**: Move Step 1.2 (`@Generable` schemas) from `ReportModels.swift` to `ReportNarrativeGenerator.swift` (the file that uses them). Place them at the bottom of the file inside the `#if canImport(FoundationModels)` block, matching the existing pattern exactly.

---

### HIGH (Should Fix Before Proceeding)

#### H1: Step 8.1 adds 6 new `async let` fetches but doesn't update the existing tuple `await`

- **Location**: Step 8.1 says "add `async let` for restingHRFetch, hrvFetch, systolicFetch, diastolicFetch, respiratoryFetch, daylightFetch" and "Await them alongside existing tuple"
- **Problem**: The existing code at line 159 destructures exactly 5 values:
  ```swift
  let (sleepSummaries, stepsData, energyData, heartRateData, exerciseData) = await (sleepFetch, stepsFetch, energyFetch, heartRateFetch, exerciseFetch)
  ```
  Adding 6 more `async let`s requires either expanding this tuple to 11 values (unwieldy but works) or awaiting the new ones in a separate tuple. The checklist says "await them alongside existing tuple" but doesn't specify the concrete syntax change.
- **Impact**: Implementer may get confused about how to restructure the await. A Swift tuple with 11 elements is technically valid but hard to read.
- **Recommendation**: Add a concrete instruction: "Add a second `await` tuple for the new vitals:
  ```swift
  let (restingHRData, hrvData, systolicData, diastolicData, respiratoryData, daylightData) = await (restingHRFetch, hrvFetch, systolicFetch, diastolicFetch, respiratoryFetch, daylightFetch)
  ```
  This keeps both tuples manageable at 5-6 elements each."

---

### MEDIUM (Fix During Implementation)

#### M1: `#Predicate` may not support `Bool` property filtering for `InterventionSession.completed`

- **Location**: Step 2.1 — "InterventionSession where `startedAt >= windowStart`, then filter `completed == true`"
- **Problem**: The checklist correctly says "filter `completed == true` after fetch" (in-memory). However, `FastingSession` uses `.isActive` which is a computed property (`var isActive: Bool { actualEndAt == nil }`), and the checklist says "filter `!isActive`" — computed properties cannot be used in `#Predicate`. The step already handles this correctly by post-filtering, but the wording "then filter" could be misread as "add to `#Predicate`".
- **Impact**: Low — the intent is correct, but explicitly note "in-memory filter, NOT in `#Predicate`" to prevent mistakes.
- **Recommendation**: Clarify wording: "Fetch all `FastingSession` where `startedAt >= windowStart`. Then **in-memory** filter: `.filter { !$0.isActive }` (cannot use computed property in `#Predicate`)."

#### M2: Step 2.2 `eatingTriggers` aggregation needs `[String]` to `[String: Int]` conversion

- **Location**: Step 2.2 — "aggregate `dayFood.flatMap { $0.eatingTriggers ?? [] }` into `[String: Int]` count dict"
- **Problem**: `FoodLogEntry.eatingTriggers` is `[String]?`. The `flatMap` produces a `[String]` of all trigger strings for the day. Converting to a count dict requires `Dictionary(grouping:by:).mapValues(\.count)` or a manual reduce. The step doesn't specify the conversion pattern.
- **Impact**: Low — any Swift developer would figure this out, but specifying the pattern avoids ambiguity.
- **Recommendation**: Add: "Use `Dictionary(dayFood.flatMap { $0.eatingTriggers ?? [] }.map { ($0, 1) }, uniquingKeysWith: +)` or equivalent reduce."

#### M3: Phase 6 section views have no build check between them

- **Location**: Steps 6.1-6.14 — 14 section view files created with a single build check only at the end of Phase 6
- **Problem**: If an error is introduced in 6.3 (StressDeepDiveSection), the implementer won't discover it until after creating all 14 files. This makes debugging harder.
- **Impact**: Low — each file is independent so errors are localized, but early detection is better.
- **Recommendation**: Add an intermediate build check after 6.4 (NutritionSection) — the two most complex sections. This catches issues in the heaviest code early.

#### M4: Missing `journalLogged` field in per-day summary construction (Step 2.2)

- **Location**: Step 2.2 lists all fields to populate but omits `journalLogged`
- **Problem**: `WellnessDaySummary` has a `let journalLogged: Bool` field (line 155 of InsightModels.swift). The existing `InsightEngine` sets this from `JournalEntry` data. The resolved plan says journal entries are excluded from the report, but the field still exists on the struct and must be populated in the memberwise init.
- **Impact**: Compile error if `journalLogged` is not passed to the memberwise init. Since it's a `let` with no default, it's required.
- **Recommendation**: Add `journalLogged: false` (or fetch journal entries and check) to the per-day summary construction in Step 2.2. The simplest approach: always pass `journalLogged: false` since journal is excluded from this report. Or fetch `JournalEntry` and check for presence (costs one query but is accurate).

#### M5: Step 7.2 entrance index offset incomplete

- **Location**: Step 7.2 — "Offset ForEach entrance indices by +1"
- **Problem**: Currently the ForEach uses `idx + 1` for entrance animation. Adding a "Full Report" card at index 1 means ForEach items should be `idx + 2`. The footer also needs its index offset. The step says "offset by +1" but doesn't specify the exact change.
- **Impact**: Low — animation timing slightly off, no functional impact.
- **Recommendation**: Specify: "Change `insightEntrance(index: idx + 1)` to `insightEntrance(index: idx + 2)` in the ForEach. Change footer's index from `engine.insightCards.count + 1` to `+ 2`."

---

### LOW (Consider for Future)

#### L1: No `#Preview` macro specified for section views

- **Location**: Steps 6.1-6.14
- **Problem**: Each step says "Verify: Renders in Preview" but doesn't mention adding `#Preview` macros. The existing codebase consistently adds `#Preview` blocks to views.
- **Impact**: Preview-based verification won't work without `#Preview` blocks.
- **Recommendation**: Each section view step should include "Add `#Preview` with mock `ReportData`". The mock data from Step 4.1 (ViewModel mock mode) can be extracted into a static helper for previews.

#### L2: Checklist doesn't specify `@Guide` description strings for `@Generable` fields

- **Location**: Step 1.2 (now moving to 3.1)
- **Problem**: The `@Guide(description:)` strings are critical for FM output quality. The checklist says "with `@Guide` annotated fields" but doesn't specify the description text.
- **Impact**: Low — the plan has the descriptions. But the implementer may write generic descriptions.
- **Recommendation**: Copy the exact `@Guide` descriptions from the plan into the checklist, e.g., `@Guide(description: "3-4 sentence narrative summary of the 15-day period. Reference specific numbers. Use 'may suggest' framing.")`

---

## Completeness Check

| Plan Phase | Checklist Coverage | Notes |
|---|---|---|
| Phase 1: Models | Steps 1.1, 1.2, 1.3 | Complete |
| Phase 2: Data Builder | Steps 2.1-2.9 | Complete (M4: missing `journalLogged`) |
| Phase 3: Narrative Gen | Steps 3.1-3.4 | Complete (C1: schema file location) |
| Phase 4: ViewModel | Step 4.1 | Complete |
| Phase 5: Charts | Step 5.1 | Complete |
| Phase 6: Section Views | Steps 6.1-6.14 | Complete (L1: no `#Preview`) |
| Phase 7: Main View + Nav | Steps 7.1-7.2 | Complete |
| Phase 8: InsightEngine | Step 8.1 | Complete (H1: tuple await) |
| Phase 9: Mock + Build | Post-Implementation | Complete |

All plan phases are covered. No steps are missing.

---

## Dependency Order Verification

| Step | Depends On | Correct? |
|---|---|---|
| 1.1 (ReportModels) | Nothing | Yes |
| 1.2 (@Generable) | 1.1 | Yes (but wrong file — C1) |
| 1.3 (InsightModels) | Nothing | Yes |
| 2.1-2.9 (DataBuilder) | 1.1, 1.3 | Yes |
| 3.1-3.4 (NarrativeGen) | 1.1 (types), 1.2 (schemas) | Yes |
| 4.1 (ViewModel) | 2.x, 3.x | Yes |
| 5.1 (Charts) | 1.1 (types only) | Yes — could be parallel with Phase 2-3 |
| 6.x (Sections) | 4.1, 5.1 | Yes |
| 7.x (Main View) | 6.x | Yes |
| 8.1 (InsightEngine) | 1.3 | Yes — could be earlier, but order is safe |

Dependencies are correctly ordered. Phase 5 could run in parallel with Phases 2-4 for faster implementation.

---

## Recommendations

1. **Fix C1 immediately**: Move `@Generable` schemas from `ReportModels.swift` to `ReportNarrativeGenerator.swift`. Update Step 1.2 to say "will be created in Phase 3" and move the actual items to Step 3.1.
2. **Fix H1**: Add explicit second `await` tuple instruction in Step 8.1.
3. **Fix M4**: Add `journalLogged` to Step 2.2 per-day summary.
4. **Add intermediate build check** after Step 6.4.
5. **Note for implementer**: Phase 5 (Charts) can be implemented in parallel with Phases 2-4 since it only depends on type definitions from Phase 1.
