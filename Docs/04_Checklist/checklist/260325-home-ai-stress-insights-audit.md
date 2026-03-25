# Plan Audit Report: Home AI Stress Insights

**Audit Date**: 2026-03-25
**Plan Location**: `/Users/hariom/.claude/plans/enchanted-mapping-clover.md`
**Brainstorm Reference**: `Docs/02_Planning/Brainstorming/260325-home-ai-stress-insights-brainstorm.md`
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan is architecturally sound and follows established codebase patterns well. However, it has one critical duplication risk (factor scoring logic already exists in `StressViewModel`), two high-priority flexibility gaps (no service protocol, opaque context struct), and several medium issues around state clarity and future extensibility. Resolving these will make the feature significantly easier to debug and extend to weekly/monthly recaps.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### 1. Factor Scoring Logic Duplicated from StressViewModel
- **Location**: Step 2, "Template fallback" section
- **Problem**: The plan describes a new deterministic ranking pipeline ("find highest-score day → identify worst metric") inside `StressInsightService`. `StressViewModel` already contains `computeExerciseScore()`, `computeSleepScore()`, `computeDietScore()`, `computeScreenTimeScore()`, `buildExerciseFactor()`, `buildSleepFactor()` etc. These are private methods on the VM, making them inaccessible to the service. The plan proposes reinventing this logic in parallel.
- **Impact**: Two separate scoring implementations will diverge. A tweak to sleep scoring in `StressViewModel` won't automatically apply to the insight report. Future debugging will involve comparing two code paths.
- **Recommendation**: Extract the four scoring functions (`computeExerciseScore`, `computeSleepScore`, `computeDietScore`, `computeScreenTimeScore`) and their `StressFactorResult` builder calls into a standalone `StressScoring.swift` (pure functions, no dependencies). Both `StressViewModel` and `StressInsightService` call into the same file. This also makes unit testing the scoring trivial.

---

### HIGH (Should Fix Before Proceeding)

#### 2. No Protocol for StressInsightService
- **Location**: Step 2 service definition
- **Problem**: Every other injectable service in the codebase has a protocol (`NutritionServiceProtocol`, `HealthKitServiceProtocol`). `StressInsightService` is planned as a concrete `final class` only. This means:
  - Mock mode must be handled inside the concrete class (runtime `if` branch), not at injection site
  - `HomeAIInsightView` is tightly coupled to the concrete type
  - A future "StressInsightServiceMock" for Previews requires duplicating the class
- **Impact**: Limits testability, makes mock-mode harder to reason about, and blocks the widget/notification use cases mentioned in the brainstorm (they'd need a different injection).
- **Recommendation**: Add `StressInsightServiceProtocol` with `isGenerating`, `report`, `insufficientData`, `generateInsight()`, `clearAndRegenerate()`. `HomeAIInsightView` should receive the protocol type. Concrete class and mock conform to it. This is a 15-line addition that unlocks all future flexibility.

#### 3. StressInsightContext Is Invisible to Debugging
- **Location**: Step 1, internal types; Step 2, prompt construction
- **Problem**: `StressInsightContext` is an internal struct used to build the model prompt. It is the single most important diagnostic artifact — when the model produces a wrong insight, you need to know exactly what context was sent. The plan makes it private with no logging or debug exposure.
- **Impact**: Debugging wrong or hallucinated insights requires adding logging after the fact. When Phase 2 adds more data sources, tracing what was included is impossible without code changes.
- **Recommendation**: In `DEBUG` builds, log the full serialized context to `WPLogger` after it is built (before the model call). Optionally, expose `@Published var lastContext: StressInsightContext?` in DEBUG so the insight view can show a "Debug: data used" sheet. This costs nothing in release builds.

#### 4. `[String]` Array in @Generable May Not Be Supported
- **Location**: Step 2, `@Generable` schema — `suggestions: [String]`
- **Problem**: The existing `MealCoachService` never uses `[String]` directly in a `@Generable` struct. It uses a nested `@Generable` struct (`_FoodOptionsSchema` containing `[_FoodOptionSchema]`). Apple's `@Generable` macro has documented limitations with plain `[String]` — generation reliability is lower than with nested typed arrays.
- **Impact**: The model may fail to produce a valid structured array, causing the `try?` to return `nil` and falling back to template every time — defeating the purpose of Foundation Models.
- **Recommendation**: Either (a) wrap suggestions in a nested `@Generable` struct:
  ```swift
  @Generable private struct _SuggestionList {
      var items: [_Suggestion]
  }
  @Generable private struct _Suggestion {
      var text: String
  }
  ```
  Or (b) use two separate `suggestion1: String` / `suggestion2: String` fields with sentinel `""` for absent ones, then filter before returning. Verify against `MealCoachService` pattern — nested structs are the proven approach.

---

### MEDIUM (Fix During Implementation)

#### 5. `bindContext()` Silent Failure Looks Like "No Data"
- **Problem**: If `generateInsight()` is called before `bindContext()` (e.g., the button is tapped faster than `.onAppear`), `modelContext` is `nil`. `buildContext()` returns `nil`. The service sets `insufficientData = true`. The user sees "Not Enough Data" — but the real cause is a programmer error (missing context bind). This is hard to debug.
- **Recommendation**: Add a `precondition(modelContext != nil, "StressInsightService: bindContext must be called before generateInsight")` in DEBUG, and a `WPLogger` warning in release. The `.task` modifier (not `.onAppear`) should be used in `HomeView` to ensure context is bound before any user interaction fires.

#### 6. `clearAndRegenerate()` Flow Not Specified
- **Problem**: The plan lists `clearAndRegenerate()` as the Regenerate button's target but does not specify whether it (a) sets `report = nil` and `insufficientData = false` before calling `generateInsight()`, or (b) has its own flow. If `insufficientData` is not explicitly cleared, the loading state will flash and immediately return to the empty state.
- **Recommendation**: Specify: `clearAndRegenerate()` sets `report = nil`, `insufficientData = false`, then calls `generateInsight()`. This must bypass the same-day cache check (since the user is explicitly requesting a refresh). Confirm that the cache check in `generateInsight()` is not hit when called from `clearAndRegenerate()`.

#### 7. Data Window Hardcoded — Should Be a Named Constant
- **Problem**: The plan hardcodes 3 days throughout. The brainstorm explicitly noted "dynamically use 3 to 5 days when enough data exists" as a deferred open question. With 3 days as a magic number scattered in `buildContext()`, extending to 5 days later requires hunting down every occurrence.
- **Recommendation**: Define `private let lookbackDays: Int = 3` at the top of `StressInsightService`. A future change to 5 days is a single-line edit. Additionally, the `DateInterval` construction for HealthKit queries should be derived from this constant.

#### 8. `StressInsightDaySummary.avgCalories` Is Misnamed
- **Problem**: `avgCalories: Int?` is described as "aggregated from FoodLogEntry for that day" — which is a sum, not an average. The name `avg` implies a per-meal average.
- **Recommendation**: Rename to `totalCalories: Int?`. Similarly, `avgProteinG` and `avgFiberG` should be `totalProteinG` and `totalFiberG` if they are day-level sums.

#### 9. Foundation Models Availability Check Missing
- **Problem**: The plan guards with `#available(iOS 26, *)` and relies on `try?` to silently swallow failures. However, on iOS 26+, Apple Intelligence can be disabled by the user or unsupported on that device/locale. The recommended pattern (from WWDC25/286) is to check `SystemLanguageModel.default.availability` before creating a session.
- **Recommendation**: In `generateWithFoundationModels()`, add:
  ```swift
  guard case .available = SystemLanguageModel.default.availability else {
      throw InsightError.modelUnavailable
  }
  ```
  This makes the availability path explicit rather than relying on a silent `try?` nil result, and will produce cleaner fallback behavior.

#### 10. Template Fallback Is Underspecified
- **Problem**: "Hardcoded suggestion map keyed by identified factors" is vague. With 4 factor types (exercise, sleep, diet, screen time) each potentially being a positive or negative driver, there are 8+ text branches. Written inline, this becomes a maintenance burden when copy needs updating.
- **Recommendation**: Define a private `TemplateSuggestions` enum or dictionary in the service with named entries per factor, making copy updates a single-location change. This also makes the template fallback unit-testable.

#### 11. `isTemplateGenerated = false` for Mock Mode Is Misleading
- **Problem**: The plan sets `isTemplateGenerated = false` for mock-generated reports because "it's mock, not a fallback." But in debug mode, a developer looking at the report cannot distinguish a real Foundation Models result from a hardcoded mock fixture. This obscures whether the model path was actually exercised.
- **Recommendation**: Add a separate `isMockGenerated: Bool` field to `StressInsightReport`, or set `isTemplateGenerated = true` in mock mode (mock data is not an AI result). In DEBUG, render a small "Mock" badge on the report so the state is immediately visible.

---

### LOW (Consider for Future)

#### 12. StressInsightReport File Placement May Need to Move
- **Problem**: The plan places `StressInsightReport` at `WellPlate/Features + UI/Home/StressInsightReport.swift` (feature-local, following `FoodOption.swift`). If Phase 2 adds a widget teaser or notification that references the same type, it must be moved to `WellPlate/Models/` or a Shared layer at that time.
- **Recommendation**: Note in a comment at the top of the file: `// Phase 2: move to WellPlate/Models/ if consumed outside the Home feature`. This costs nothing now and prevents confusion later.

#### 13. No Timeout on Foundation Models Generation
- **Problem**: If the on-device model is slow (first-run, cold start), `isGenerating` stays `true` indefinitely. The user taps Regenerate; nothing appears to happen.
- **Recommendation**: Wrap the Foundation Models call in a `Task` with a timeout (e.g., 15 seconds). On timeout, fall back to `templateReport()` and log a warning. Not critical for V1 but worth planning.

#### 14. HealthKit Authorization Not Checked in Service
- **Problem**: `StressInsightService` calls `fetchSleep`, `fetchSteps`, `fetchActiveEnergy` via `HealthKitServiceProtocol`, but never checks `healthService.isAuthorized` or calls `requestAuthorization()`. If the user has not granted HealthKit access, all three calls return empty arrays silently — the insight omits sleep/activity with only a `cautionNote`.
- **Recommendation**: Check `healthService.isAuthorized` before HealthKit queries. If not authorized, populate `dataQualityNote` immediately. Do not call `requestAuthorization()` from the insight service (that is `StressView`'s job) — just read the flag.

---

## Missing Elements

- [ ] `StressInsightServiceProtocol` — no protocol defined; required for Preview support and future mock injection
- [ ] Shared `StressScoring.swift` — factor scoring functions are not extracted; both VM and service will re-implement them
- [ ] Debug logging for `StressInsightContext` — no observability into what data was sent to the model
- [ ] `lookbackDays` named constant — 3-day window is not parameterized
- [ ] `SystemLanguageModel.default.availability` check — explicit model availability guard not specified
- [ ] Specification of `clearAndRegenerate()` internal flow relative to `generateInsight()`

---

## Unverified Assumptions

- [ ] `[String]` works reliably as a `@Generable` field — **Risk: High** (not used elsewhere in codebase; nested struct is the proven pattern)
- [ ] `bindContext()` is always called before the first user tap — **Risk: Medium** (no guard specified; `.task` vs `.onAppear` ordering matters)
- [ ] HealthKit 3-day `DateInterval` queries are fast enough to not block the loading state — **Risk: Low** (HealthKit queries are async and typically fast for short windows)
- [ ] `WellnessDayLog` rows exist for recent days (users may not have visited the Stress tab recently) — **Risk: Medium** (stress label is only persisted by `StressViewModel.persistTodayWellnessSnapshot()`)

---

## Security Considerations

- [ ] No user-identifiable data is sent to Foundation Models (on-device only) — confirmed by architecture; no network call
- [ ] Prompt construction must not interpolate raw food names or user reflections from `FoodLogEntry` — confirm that only numeric aggregates are included in the day summary text block

---

## Performance Considerations

- [ ] HealthKit 3-day queries (`fetchSleep`, `fetchSteps`, `fetchActiveEnergy`) should be run concurrently with `async let` — not sequentially
- [ ] SwiftData queries for `StressReading`, `WellnessDayLog`, `FoodLogEntry` over 3 days are small and pose no performance risk
- [ ] Foundation Models cold-start latency on first generation: plan for a visible loading state of 2–8 seconds

---

## Recommendations Summary

1. **Extract `StressScoring.swift`** — pure functions shared by `StressViewModel` and `StressInsightService`. Single source of truth for all factor scoring logic.
2. **Add `StressInsightServiceProtocol`** — enables Preview mocking, future widget/notification injection, and cleaner separation from `HomeAIInsightView`.
3. **Replace `[String] suggestions` with nested `@Generable` struct** — follow the proven `MealCoachService` pattern.
4. **Add `lookbackDays` constant** and derive all date math from it.
5. **Log `StressInsightContext` in DEBUG** — minimum viable observability for wrong insight debugging.
6. **Specify `clearAndRegenerate()` explicitly** — ensure cache bypass and state reset are both documented.

---

## Sign-off Checklist

- [ ] CRITICAL #1 resolved: scoring logic extracted to shared file
- [ ] HIGH #2 resolved: `StressInsightServiceProtocol` added
- [ ] HIGH #3 resolved: debug logging for context specified
- [ ] HIGH #4 resolved: `[String]` in `@Generable` replaced with nested struct
- [ ] MEDIUM #5–#11 reviewed and accepted or resolved
- [ ] Security review completed: no PII in prompt
- [ ] Performance: HealthKit queries confirmed concurrent
