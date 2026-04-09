# Plan Audit Report: Symptom Tracking Correlated with Food/Sleep

**Audit Date**: 2026-04-08
**Plan Version**: `Docs/02_Planning/Specs/260408-symptom-tracking-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The plan is architecturally sound with well-designed correlation math (Spearman r + bootstrap CI) and a clean data model. However, source code verification reveals 1 HIGH issue (ProfileView preview crash), 3 MEDIUM issues (ProfileView sheet convention violation, header icon overflow, sleep data fetching gap), and 1 LOW item. All fixable without rethinking the architecture.

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

*None found.*

### HIGH (Should Fix Before Proceeding)

#### H1. ProfileView Preview Will Crash After Adding `@Query` for SymptomEntry
- **Location**: Plan Step 8 — adds `@Query private var allSymptomEntries: [SymptomEntry]` to `ProfilePlaceholderView`
- **Problem**: ProfileView's preview (line 1249) is a bare `ProfilePlaceholderView()` with no custom `ModelContainer`. Adding a `@Query` for `SymptomEntry` without providing a container will crash: `Fatal error: no ModelContainer found in the environment`. This is the same issue fixed in HomeView during the journal feature (H1 from `260407-journal-gratitude-plan-audit.md`).
- **Impact**: Preview becomes unusable; Xcode canvas crash
- **Recommendation**: Step 8 must include updating the ProfileView preview:
  ```swift
  #Preview {
      let config = ModelConfiguration(isStoredInMemoryOnly: true)
      let container = try! ModelContainer(
          for: SymptomEntry.self, UserGoals.self,
          configurations: config
      )
      return ProfilePlaceholderView()
          .modelContainer(container)
  }
  ```
  Include `UserGoals.self` since `ProfilePlaceholderView` already has `@Query private var userGoalsList: [UserGoals]`.

### MEDIUM (Fix During Implementation)

#### M1. ProfileView Has 4 Boolean `.sheet()` Modifiers — Adding a 5th Violates CLAUDE.md
- **Location**: Plan Step 8 — adds `.sheet(isPresented: $showSymptomLog)`
- **Problem**: ProfileView already has 4 `.sheet()` modifiers (lines 151, 156, 161, 166 — instructions, editName, editWeight, editHeight). CLAUDE.md states: "Feature sheets use a single enum driving one `.sheet(item:)` — do not add multiple `.sheet()` calls." Adding a 5th sheet worsens this.
- **Impact**: Potential SwiftUI sheet conflicts; violates documented convention
- **Recommendation**: Introduce a `ProfileSheet` enum (like `HomeSheet`) consolidating all sheets:
  ```swift
  enum ProfileSheet: Identifiable {
      case widgetInstructions
      case editName
      case editWeight
      case editHeight
      case symptomLog
      var id: String { ... }
  }
  ```
  Replace all 4 existing boolean `.sheet()` modifiers + the new symptom one with a single `.sheet(item: $activeSheet)`. This is a larger refactor but aligns with the codebase convention.

#### M2. HomeView Header Icon Overflow on Small Screens
- **Location**: Plan Step 9 — adds a 4th action icon (symptom) to `homeHeader`
- **Problem**: Header currently has 3 action buttons (AI 44pt, Calendar 44pt, Journal 44pt) + conditional mood badge (44pt). Adding a symptom icon makes 4 buttons + badge = 5 × 44pt + gaps ≈ 250pt minimum. iPhone SE screen is 375pt; after greeting text (~80pt) and spacer, available right-side space is ~280pt. This is tight and may overflow with the mood badge visible.
- **Impact**: Layout overflow or truncation on SE; compressed tap targets
- **Recommendation**: Two options:
  1. **Reduce icon size to 38pt** across all header buttons (saves ~30pt total)
  2. **Don't add symptom icon to Home header** — symptom logging is primarily a Profile feature. Users can log from Profile's "Log +" button. This keeps Home header clean. If keeping it, test on SE simulator first.

#### M3. Sleep Data Dictionary Construction Missing from Plan
- **Location**: Plan Step 4 — correlation engine requires `sleepHours: [Date: Double]`
- **Problem**: No `fetchSleepHours()` method exists in HealthKitService. The service has `fetchDailySleepSummaries(for:)` which returns `[DailySleepSummary]` with `date` and `totalHours` fields. The plan doesn't specify how to convert this to the `[Date: Double]` dictionary the engine expects.
- **Impact**: Implementer must decide where to do the conversion — in the engine, in Profile, or as a new HealthKit method
- **Recommendation**: Add a step to either:
  1. Add a convenience method to HealthKitService: `func fetchDailySleepHours(for range: DateInterval) async throws -> [Date: Double]`
  2. Or construct the dictionary in the Profile/correlation view's data-loading code using `fetchDailySleepSummaries` + `.reduce(into:)`. Option 2 is simpler for MVP.

### LOW (Consider for Future)

#### L1. Fiber Column Missing from Current CSV — Not Just Symptom Extension
- **Location**: Plan Step 10 — adds symptom columns but doesn't add fiber
- **Problem**: The correlation engine uses fiber as a factor, but the current CSV doesn't include a `fiber_g` column. If users export CSV to share with clinicians, fiber is missing context.
- **Impact**: Minor — fiber isn't critical for MVP export
- **Recommendation**: Consider adding `fiber_g` column alongside the symptom columns. Simple addition.

## Missing Elements

- [ ] ProfileView preview update with `SymptomEntry.self` + `UserGoals.self` in ModelContainer
- [ ] ProfileSheet enum to consolidate sheet modifiers
- [ ] Sleep data dictionary construction step
- [ ] iPhone SE header icon testing plan

## Unverified Assumptions

- [ ] Spearman rank correlation with N=7 produces meaningful results — Risk: Low (standard statistical minimum for rank correlation)
- [ ] 1000 bootstrap iterations for 7 factors completes in <100ms — Risk: Low (trivial computation)
- [ ] ProfilePlaceholderView can absorb 2 new sections without excessive scroll — Risk: Low (existing scroll view handles variable content)

## Questions for Clarification

1. Should the symptom icon go in the Home header at all, or should symptom logging be Profile-only with a quick path via tab switch?
2. Should the ProfileSheet enum refactor be part of this feature's scope, or a prerequisite cleanup?

## Recommendations

1. **Fix H1** — identical pattern to journal preview fix; straightforward
2. **Decide M1** early — ProfileSheet enum refactor touches existing edit sheet code, needs careful migration
3. **Decide M2** — test header on SE; if it overflows, drop the Home header icon and keep symptom logging Profile-only
4. **Add M3** — one line of clarification about sleep dictionary construction
5. Overall: plan is well-designed. The correlation engine (Spearman + bootstrap) is the right statistical approach. Issues are all integration-level, not architectural.
