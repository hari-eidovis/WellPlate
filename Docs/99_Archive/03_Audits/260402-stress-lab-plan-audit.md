# Plan Audit Report: Stress Lab (n-of-1 Experiments)

**Audit Date**: 2026-04-02
**Plan Audited**: `Docs/02_Planning/Specs/260402-stress-lab-plan.md`
**Auditor**: audit agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan is architecturally sound and the analytics approach is correct, but Step 7 violates an explicit CLAUDE.md constraint: it adds a third `.sheet()` call to `StressView`, which already has two — and CLAUDE.md states "do not add multiple `.sheet()` calls." The fix is to add a `.stressLab` case to the existing `StressSheet` enum and present `StressLabView` through the existing `activeSheet` mechanism. A second medium-severity issue addresses the `StressLabView`'s own two internal `.sheet()` calls, which should use a single enum for the same reason. One additional medium issue flags an unguarded `@Query` fetching all `StressReading` rows with no predicate, when only the last ~30 days are ever needed.

---

## Issues Found

### CRITICAL

#### C1: Step 7 adds a third `.sheet()` to `StressView` — violates CLAUDE.md architectural constraint

- **Location**: Step 7, action item 3 — adds `.sheet(isPresented: $showStressLab) { StressLabView() }` to `StressView`
- **Problem**: `CLAUDE.md` (line 61) explicitly states: *"Feature sheets use a single enum (e.g., `StressSheet`) driving one `.sheet(item:)` — do not add multiple `.sheet()` calls."* `StressView` already has two sheet modifiers (`showInsights` at line 108, `activeSheet` at line 112). Adding a third `.sheet(isPresented: $showStressLab)` directly violates this constraint. Additionally, multiple concurrent `.sheet()` modifiers on the same view hierarchy can cause iOS presentation conflicts where only one sheet is reliably presented.
- **Impact**: Architecture violation. On iOS, the system may silently ignore a third `.sheet()` if another is already presented or queued. The app could appear broken (Lab button tapped → nothing happens).
- **Recommendation**: Add a `.stressLab` case to the existing `StressSheet` enum, and present `StressLabView` through the existing `.sheet(item: $activeSheet)` switch. This means:

  1. Add to `StressSheet` enum in `StressView.swift`:
     ```swift
     case stressLab
     ```
     with `var id: String { case .stressLab: return "stressLab" }` in the id switch.

  2. Change Step 7 action item 1 from adding `@State private var showStressLab = false` to setting `activeSheet = .stressLab` in the toolbar button action.

  3. Change Step 7 action item 2 (toolbar button) to set `activeSheet = .stressLab` instead of `showStressLab = true`.

  4. Change Step 7 action item 3 to add a new `case .stressLab:` branch inside the existing `.sheet(item: $activeSheet)` switch (after the `.vital` case) that presents `StressLabView()`.

  This eliminates the new `.sheet()` modifier entirely — `StressLabView` is presented via the existing mechanism.

---

### HIGH

#### H1: `StressLabView` itself has two `.sheet()` calls — same CLAUDE.md constraint applies

- **Location**: Step 4 (`StressLabView.swift`), body:
  ```swift
  .sheet(isPresented: $showCreate) {
      StressLabCreateView()
  }
  .sheet(item: $selectedExperiment) { exp in
      StressLabResultView(...)
  }
  ```
- **Problem**: Same CLAUDE.md rule — two `.sheet()` modifiers on the same view. On iOS, when `showCreate` becomes true while `selectedExperiment` is also set (or vice versa), only one sheet will present. More importantly, the pattern is explicitly called out as wrong in the project conventions.
- **Impact**: Potential silent presentation failure; architecture inconsistency.
- **Recommendation**: Introduce a `StressLabSheet` enum inside `StressLabView.swift`:
  ```swift
  private enum StressLabSheet: Identifiable {
      case create
      case result(StressExperiment)
      var id: String {
          switch self {
          case .create:          return "create"
          case .result(let e):   return "result_\(e.persistentModelID)"
          }
      }
  }
  ```
  Replace `@State private var showCreate = false` and `@State private var selectedExperiment: StressExperiment? = nil` with `@State private var activeSheet: StressLabSheet? = nil`. Replace both `.sheet()` calls with a single `.sheet(item: $activeSheet)` switch. Update all callsites (`showCreate = true` → `activeSheet = .create`, `selectedExperiment = exp` → `activeSheet = .result(exp)`).

---

### MEDIUM

#### M1: `@Query private var allReadings: [StressReading]` in `StressLabView` has no predicate — fetches entire table

- **Location**: Step 4 (`StressLabView.swift`), property declaration:
  ```swift
  @Query private var allReadings: [StressReading]
  ```
- **Problem**: This fetches every `StressReading` ever persisted, with no date filter. The analyzer only ever needs readings from the last 21–30 days (7-day baseline + up to 14-day experiment window). As the user accumulates months of data, this query grows unboundedly. The `allFoodLogs` query in `ProgressInsightsView` uses a 90-day predicate as a model for this pattern.
- **Impact**: Unnecessary memory allocation and SwiftData fetch overhead. Negligible today, noticeable after 6–12 months of daily use.
- **Recommendation**: Add a 30-day predicate:
  ```swift
  init() {
      let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
      _allReadings = Query(
          filter: #Predicate<StressReading> { $0.timestamp >= cutoff },
          sort: \.timestamp,
          order: .forward
      )
  }
  ```
  Note: Since `StressLabView` doesn't currently have a custom `init()`, adding one is required (same pattern as `ProgressInsightsView.init()`).

---

### LOW

#### L1: `flask.fill` SF Symbol — verify availability

- **Location**: `InterventionType.icon` for `.custom` case, and the "Lab" toolbar button in Step 7
- **Problem**: `flask.fill` was introduced in SF Symbols 4 (iOS 16). Since the app targets iOS 26, this is fine. However, no other view in the project currently uses `flask.fill` — worth confirming it renders correctly in the project's iOS 26 Simulator.
- **Impact**: Zero risk for the iOS 26 target. Informational only.
- **Recommendation**: No change needed. Noted for completeness.

#### L2: `StressLabResultView` caches results on `StressExperiment` model properties but never saves the context

- **Location**: Step 6 (`StressLabResultView.swift`), `.task` block:
  ```swift
  experiment.cachedBaselineAvg = r.baselineAvg
  experiment.cachedDelta       = r.delta
  // ... etc
  if experiment.completedAt == nil && experiment.isComplete {
      experiment.completedAt = experiment.endDate
  }
  ```
- **Problem**: The plan mutates `@Model` properties but never calls `try? modelContext.save()`. SwiftData's autosave will eventually persist these, but the delta pill in the past experiments list may not appear until the next autosave cycle (typically on scene transitions). If the user taps "Done" immediately after viewing results, the cached delta may not persist to disk.
- **Impact**: Low — autosave will catch up, but on first view the list row may still show no delta pill until next launch.
- **Recommendation**: After mutating the cached fields in `.task`, add:
  ```swift
  try? modelContext.save()
  ```
  The `modelContext` can be injected via `@Environment(\.modelContext)` in `StressLabResultView`.

#### L3: `bootstrapCI` uses `randomElement()!` force-unwrap

- **Location**: Step 3 (`StressLabAnalyzer.swift`), `bootstrapCI` function:
  ```swift
  let bSample = (0..<baseline.count).map { _ in baseline.randomElement()! }
  ```
- **Problem**: `randomElement()` returns `Optional` and is force-unwrapped. This is safe only if `baseline` is non-empty — which is guaranteed by the `minimumDays` guard before `bootstrapCI` is called. However, if someone calls `bootstrapCI` directly with an empty array (e.g. in a future test), it will crash.
- **Impact**: Zero risk in the current call path. Style/safety concern only.
- **Recommendation**: Replace `randomElement()!` with `randomElement() ?? 0` to be crash-safe regardless of caller. This does not change the behavior when arrays are non-empty.

---

## Verification of Key Assumptions

- [x] `StressSheet` enum exists in `StressView.swift` (lines 12–28) with `exercise`, `sleep`, `diet`, `screenTimeDetail`, `vital(VitalMetric)` cases — adding `.stressLab` is straightforward — **confirmed**
- [x] `activeSheet: StressSheet?` drives a single `.sheet(item:)` at line 112 — **confirmed**
- [x] `StressView` already has `.topBarTrailing` toolbar item; adding `.topBarLeading` is valid and won't conflict — **confirmed** (line 67, only trailing item present)
- [x] `HapticService.impact(.light)` and `.impact(.medium)` exist and are used in `StressView` — **confirmed**
- [x] `AppColors.brand`, `.textPrimary`, `.textSecondary` all exist — **confirmed**
- [x] `.r()` font extension available — **confirmed** (used throughout `StressView`)
- [x] `.appShadow(radius:y:)` modifier available — **confirmed** (defined in `AppColor.swift`)
- [x] `WellPlateApp.swift` modelContainer is at line 34 with 5 existing types — **confirmed**; adding `StressExperiment.self` is additive
- [x] `StressView` has exactly 2 existing `.sheet()` modifiers (lines 108, 112) — plan adds a 3rd — **this is the C1 violation**
- [x] `StressLabAnalyzer` `minimumDays = 3` guard fires before `bootstrapCI` is called — bootstrap arrays always non-empty in production path — **confirmed by code logic**
- [x] `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — `StressLabResultView` is implicitly `@MainActor`; `await Task.detached { }.value` resumes on main actor — cache mutations are safe — **confirmed**

---

## Missing Elements

- [ ] `StressExperiment.persistentModelID` usage in `StressLabSheet.result(let e)` id — `StressExperiment` is an `@Model` so it has `persistentModelID` automatically. No missing element.
- [ ] No `@Environment(\.modelContext)` in `StressLabResultView` for saving cache — needed for L2 fix.

---

## Recommendations

1. **(Blocking)** Fix C1: Add `.stressLab` to `StressSheet` enum; set `activeSheet = .stressLab` in the toolbar button; handle in the existing `.sheet(item: $activeSheet)` switch. Remove `showStressLab: Bool` and the new `.sheet(isPresented:)`.
2. **(Should fix)** Fix H1: Replace `StressLabView`'s two `.sheet()` calls with a single `StressLabSheet` enum + `activeSheet: StressLabSheet?` pattern.
3. Fix M1: Add `init()` with 30-day predicate to `StressLabView`'s `allReadings` query.
4. Fix L2: Add `@Environment(\.modelContext)` to `StressLabResultView` and call `try? modelContext.save()` after caching result fields.
5. Fix L3: Replace `randomElement()!` with `randomElement() ?? 0` in `bootstrapCI`.
6. Proceed to RESOLVE then CHECKLIST — no architectural blockers beyond the sheet pattern fix.
