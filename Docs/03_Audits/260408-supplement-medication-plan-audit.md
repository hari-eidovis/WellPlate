# Plan Audit Report: Supplement / Medication Reminders

**Audit Date**: 2026-04-08
**Plan Version**: `Docs/02_Planning/Specs/260408-supplement-medication-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The plan is well-structured and correctly leverages the `FastingService` notification pattern, F5's `SymptomCorrelationEngine`, and the `ProfileSheet` enum. Source code verification confirms all backward-compatible parameter additions work (no existing callers break). One HIGH issue found (`@Query` cannot filter by computed dates), one MEDIUM issue (missing `import UserNotifications`), and one MEDIUM issue (preview needs new models). All are straightforward fixes.

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

*None found.*

### HIGH (Should Fix Before Proceeding)

#### H1. `@Query` Cannot Filter AdherenceLog by Computed Date
- **Location**: Plan Step 6 (SupplementListView) — `@Query private var todayLogs: [AdherenceLog]  // filtered to today in init`
- **Problem**: SwiftData's `@Query` macro does not support runtime-computed values like `Calendar.current.startOfDay(for: Date())` in its predicate. The `#Predicate` in `@Query` requires values determinable at compile time. The app's existing pattern for date-filtered queries uses `FetchDescriptor` in private methods (e.g., `HomeView.fetchTodayWellnessLog()` at line 655).
- **Impact**: Code will not compile as specified
- **Recommendation**: Use one of two approaches:
  1. **Filter in computed property** (simpler): `@Query(sort: \AdherenceLog.day, order: .reverse) private var allAdherenceLogs: [AdherenceLog]` + `private var todayLogs: [AdherenceLog] { allAdherenceLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) } }`
  2. **FetchDescriptor in method** (more explicit): like `HomeView.fetchTodayWellnessLog()` pattern. Use in `.onAppear` or `.task`.
  
  Option 1 is recommended for consistency with how `JournalHistoryView` and `SymptomHistoryView` handle dated queries. Apply this fix in both `SupplementListView` (Step 6) and `ProfilePlaceholderView` (Step 8) wherever `todayAdherenceLogs` is used.

### MEDIUM (Fix During Implementation)

#### M1. SupplementService Missing `import UserNotifications`
- **Location**: Plan Step 4 — `SupplementService` class structure doesn't list imports
- **Problem**: `UNUserNotificationCenter`, `UNMutableNotificationContent`, and `UNCalendarNotificationTrigger` require `import UserNotifications`. SwiftUI does NOT auto-import this. `FastingService.swift` explicitly imports it at line 3.
- **Impact**: Compile error if omitted
- **Recommendation**: Add to Step 4: "Add imports: `Foundation`, `SwiftUI`, `Combine`, `UserNotifications`"

#### M2. ProfileView Preview Needs SupplementEntry + AdherenceLog
- **Location**: Plan Step 8 mentions "Update preview" but doesn't specify exact code
- **Problem**: The current preview (lines 1464–1469) includes `SymptomEntry.self, UserGoals.self`. Adding `@Query private var allSupplements: [SupplementEntry]` and adherence logs without adding them to the preview's `ModelContainer` will crash it. Same pattern as H1 from both journal and symptom audits.
- **Impact**: Preview crash
- **Recommendation**: Step 8 must include explicit preview update:
  ```swift
  let container = try! ModelContainer(
      for: SymptomEntry.self, UserGoals.self, SupplementEntry.self, AdherenceLog.self,
      configurations: config
  )
  ```

### LOW (Consider for Future)

#### L1. No Mention of Notification Permission Description
- **Location**: Entire plan
- **Problem**: While iOS doesn't require an Info.plist key for local notifications, the UX of the permission dialog could be jarring. The plan doesn't mention explaining to the user *why* WellPlate wants to send notifications before the system dialog appears.
- **Impact**: Minor UX concern — users may deny notification permission without understanding
- **Recommendation**: Show a brief in-app explanation card before triggering the system notification dialog (e.g., "WellPlate would like to remind you about your supplements at the times you set"). Not blocking for MVP.

#### L2. Adherence Auto-Resolve Timing Not Specified
- **Location**: Plan Step 4 mentions `createPendingLogs` but doesn't specify when yesterday's pending logs become "skipped"
- **Problem**: Strategy says "use 2am cutoff, not midnight" but the plan doesn't include this logic
- **Recommendation**: Add to `createPendingLogs` or a separate method: when creating today's pending logs, also mark any previous-day logs still in "pending" status as "skipped". Trigger on `.onAppear` / `.task` in ProfileView.

## Missing Elements

- [ ] `import UserNotifications` in SupplementService
- [ ] Exact preview update code for ProfileView with all 4 model types
- [ ] Clarification that `todayAdherenceLogs` uses `@Query` + computed property filter, not `@Query` predicate
- [ ] Auto-resolve logic for yesterday's pending → skipped

## Unverified Assumptions

- [ ] SwiftData handles non-optional `[Int]` arrays — Risk: Very Low (optional `[String]?` proven; non-optional should also work)
- [ ] Dynamic notification IDs (`supplement_<UUID>_<time>`) properly clear when supplement is deleted — Risk: Low (pattern is standard iOS)
- [ ] No callers of `computeCorrelations` exist yet — Risk: None (confirmed by grep)

## Questions for Clarification

None — all questions resolved via source code verification.

## Recommendations

1. **Fix H1** — use `@Query` for all logs + filter in computed property for today. Apply in both SupplementListView and ProfileView.
2. **Fix M1** — add `import UserNotifications` to the SupplementService file spec
3. **Fix M2** — specify exact preview ModelContainer contents in Step 8
4. Overall: plan is solid and well-integrated with existing F5 patterns. Issues are all compile-level fixes, not architectural.
