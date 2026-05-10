# Plan Audit Report: Stress Score Change Log ("Activity")

**Audit Date**: 2026-05-10
**Plan Version**: `Docs/02_Planning/Specs/260510-stress-change-log-plan.md` (Status: Awaiting audit)
**Auditor**: audit agent
**Verdict**: NEEDS REVISION

## Executive Summary

The plan is structurally sound, additive (no schema migration on existing models, no signing/entitlements impact), and correctly identifies the major risks (cold-launch noise, day-rollover noise, calibrator drift). However, several details around the diff algorithm, source-enum threading, the "30s ticker" claim, the `pendingReason` stash mechanism, the engagement-breakdown extraction, and the storage estimate are wrong or under-specified in ways that will produce incorrect change rows or break the build if implemented verbatim. The most serious issues are (a) a calibrator threshold formula that produces *false-positive* calibrator rows whenever any factor moves, (b) a per-recompute volume estimate that is off by ~2 orders of magnitude (inflated), and (c) a source-attribution table missing several real call sites (notably the 5-minute `StressTimerService` ticker and the Stress tab `.task`/`.refreshable`/`.onChange(scenePhase)` triggers).

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. Calibrator-impact formula in §6.2 produces false positives whenever ANY factor moves

- **Location**: §6.2, lines 281–292 of the plan.
- **Problem**: The formula

  ```
  let calibImpact = abs((next.score - next.raw) - (prev.score - prev.raw))
  ```

  does **not** isolate the calibrator's contribution. Per `StressScoring.computeStress` (`StressScoring.swift:742-743`):

  ```
  raw = max(0, driverSum + recovery + engagement + patterns)
  score = max(0, min(100, raw * calib))
  ```

  So `score - raw == raw * (calib - 1.0)` (modulo the clamp). When `calib` is unchanged but `raw` changes from 50 → 60 with `calib = 1.10`, then `(score - raw)` goes from `5.0 → 6.0` — a delta of 1.0 — even though the *calibrator itself did not move*. Combined with the `calibratorChanged` flag (which uses `0.001` tolerance against the calibrator multiplier itself, *not* its impact), if HRV/RHR baselines or today's HRV/RHR shift even slightly between recomputes (which they will, because `lastHRVHistory` and `todayHRV` are re-read by `loadData()` and the `baseline14Day` value is recomputed each call), `abs(next.calibrator - prev.calibrator) > 0.001` will frequently be true, and a fictitious calibrator row will be emitted any time a factor moves enough to scale the multiplicative gap by ≥1 pt.
- **Impact**: Calibrator row spam. Defeats the entire purpose of the ≥1pt threshold. Users will see "Calibration adjusted" rows attached to every meaningful factor move.
- **Recommendation**: Compute the calibrator-only impact by holding `raw` constant:

  ```swift
  // Impact attributable purely to the multiplier change, evaluated at the *current* raw.
  let calibOnlyImpact = next.raw * (next.calibrator - prev.calibrator)
  ```

  Or, equivalently, compute both `raw * prevCalib` and `raw * nextCalib` at the *same* raw and take the diff. Then the row is triggered only when *the multiplier itself* moved enough to shift the score by ≥1pt at today's raw. Update the threshold rule table (§6.3) and the row's `deltaPoints` field to use this isolated quantity.

#### C2. Source-attribution table in §8.1 is missing real call sites

- **Location**: §8.1 table.
- **Problem**: `grep` confirms `recompute()` is also invoked from sources the plan does not enumerate:
  - `StressTimerService` (5-minute pulse) → `StressViewModel.swift:185-187` (`tickerCancellable`). This is **not** the same as `StressView.swift:141`'s 30 s `refreshTicker`. The plan only mentions the latter.
  - `StressView.swift:141-144` `.onReceive(refreshTicker)` (30 s) → `refreshScreenTimeOnly()` → `recompute()`.
  - `StressView.swift:145-148` `.onChange(of: scenePhase)` → `await viewModel.loadData()` → `applyResult` (full reload, not `recompute`). Same for `StressView.swift:122-133` `.task`.
  - `StressView.swift:349-353` `.refreshable` → `loadData()` + `refreshScreenTimeOnly()`.
  - `StressView.swift:130, 137` initial-load + onAppear paths invoke `refreshScreenTimeOnly()`.
  - The audit prompt itself flags "ScreenTimeManager" as a caller of `refreshScreenTimeOnly()` — `grep` returns no such reference, suggesting either the plan's claim is aspirational ("if added later") or the integration is missing. Either way, the plan should not list a call site that doesn't exist yet.
- **Impact**: As written, *every* `loadData()` path will use whatever stale `pendingReason` was last set (default `.autoTicker`), labelling a pull-to-refresh and a scenePhase-active resume both as "30s refresh" entries. The user-facing source filter chip becomes meaningless.
- **Recommendation**: Audit every `applyResult` entry point and emit one explicit reason per path:
  - `loadData()` initial app launch → `.autoAppOpen`
  - `loadData()` from scenePhase active or `.refreshable` → `.autoScenePhase`
  - `recompute()` from 30 s ticker → `.autoTicker`
  - `recompute()` from `StressTimerService` 5-min pulse → reuse `.autoTicker` (or add `.autoEngagementTick`) — but document the choice.
  - `recompute()` from `manualInputCancellable.sink` → `.manualOther` (and consider passing finer granularity from `DailyPromptCoordinator.recordSave` since it knows what changed).
  - Each `refreshScreenTimeOnly`, `refreshDietFactor`, `refreshDietFactorAndLogIfNeeded` should take an explicit `reason:` argument with no default (or a default that documents the auto-fallback).
  Add a §8.1.1 sub-table covering all four `loadData()` triggers and both ticker services. The current `recompute(reason:)` signature with default `.autoTicker` will silently mask bugs.

#### C3. `pendingReason` stash is racy and lossy when `loadData()` is in-flight

- **Location**: §6.1, §11.1.
- **Problem**: `pendingReason` is a `private var` set by callers immediately before `recompute()`. `applyResult` reads it *after* the synchronous `computeStress`. Two concrete loss patterns exist on a `@MainActor`-isolated VM:
  1. **`loadData()` is `async`.** Between the time a caller sets `pendingReason = .autoScenePhase` and the time `await loadData()`'s 14+ async-let HK fetches resolve and reach `applyResult` (line 312), the 30s ticker can fire on the same actor (it interleaves at suspension points), set `pendingReason = .autoTicker`, then `recompute()` synchronously runs through `applyResult`, consumes `.autoTicker`, *and* clobbers `pendingReason` for the next caller. When the original `loadData()` finally resumes and calls `applyResult`, it'll read whatever was set last — frequently the wrong reason.
  2. The caller-then-call pattern is non-transactional. Even though MainActor prevents true threading races, async suspension points create logical races. `loadData()` runs ~10+ awaits before `applyResult`.
- **Impact**: Source attribution is unreliable for any path that goes through `loadData()`. The activity log will mislabel rows, and the source filter chip will be misleading.
- **Recommendation**: Pass `reason` as an explicit argument all the way down to `applyResult`. Refactor:

  ```swift
  func loadData(reason: StressChangeSource = .autoAppOpen) async {
      ...
      let result = StressScoring.computeStress(...)
      applyResult(result, reason: reason)
      ...
  }

  func recompute(reason: StressChangeSource) {
      ...
      applyResult(result, reason: reason)
  }

  private func applyResult(_ result: StressScoring.StressResult, reason: StressChangeSource) {
      let prev = lastResult ?? loadPersistedLastResult()
      emitChangeEntries(prev: prev, next: result, reason: reason)
      ...
  }
  ```

  This eliminates the stash, makes the dependency explicit, and surfaces missing-reason call sites at compile time. The current proposal's defaulted-parameter approach hides bugs.

#### C4. 30s ticker × 1–3 rows × 16h estimate is wildly inflated

- **Location**: §9.8, §14 ("30s ticker generates row floods").
- **Problem**: The plan estimates "**2,000–6,000 rows/day**" from a 30 s ticker × 1–3 rows × 16 hours. But:
  - 30 s × 16 h = 1,920 ticker fires/day.
  - The diff is gated by `abs(delta) ≥ 0.01` per factor. The 30 s `refreshScreenTimeOnly()` only re-reads SwiftData (food, mood, water, manual input, recent wellness) and the **cached** HK results — see `StressViewModel.swift:325-336` ("reuses cached HK from the most recent `loadData()`"). HK does *not* re-poll on the 30 s tick. Cached HK + cached vitals + cached HK history → factor scores are deterministic of inputs; if no SwiftData write landed and no hour boundary was crossed, every factor's points will be **identical** between ticks (sub-`0.01` movement only on the engagement penalty's time ramp).
  - Engagement penalty ramps are continuous: `5 * ramp(start: 17, end: 21)` increases by `5 * 30/(4*3600) ≈ 0.0104` per 30s tick — barely above the 0.01 threshold. *Some* engagement decomposition keys will tick over the threshold most cycles, but that's still bounded at 1 row per tick during ramp windows.
  - Realistic estimate: **30–80 rows/day** under normal use, with bursts on user actions. Calling 6,000 the upper bound makes paging feel mandatory when it's actually optional.
- **Impact**: Twofold:
  - Drives over-engineering of the UI (mandatory paging for what is realistically <100 rows/day).
  - **Underestimates** the *real* risk: engagement-penalty rows trickling at 0.01 / 30s during the ramp windows (17:00–21:00, 14:00–18:00, etc.) will produce ~1–3 row clusters per minute of ramp time when *no user-visible event happened*. This is the actual UX problem.
- **Recommendation**:
  - Re-estimate row volume against the actual recompute invariants (cached HK, only SwiftData re-fetches at 30 s).
  - Raise the engagement-gap delta threshold to `0.5` (or even `1.0`) to suppress ramp-tick noise. Document that engagement rows during the ramp windows need a higher threshold than other kinds.
  - Re-evaluate whether infinite-scroll paging is needed for v1 (it likely isn't at the real volume).

### HIGH (Should Fix Before Proceeding)

#### H1. Engagement breakdown extraction is partial scope creep that the plan under-specifies

- **Location**: §7, §15 ("Modified" list).
- **Problem**: The plan asks `StressScoring.engagementPenalty(inputs:now:)` to be replaced (or supplemented) by a `engagementBreakdown(inputs:) -> [String: Double]` that returns the per-key contribution. But:
  - The current implementation (`StressScoring.swift:570-610`) couples the breakdown to *time* via `ramp(start:end:)`. The breakdown helper signature in §7 omits `now:`, which would either change behavior or require a separate signature.
  - The plan also asks `EngagementGapsCard` (`EngagementGapsCard.swift:66-84`) to "adopt" the helper — but `EngagementGapsCard` doesn't currently consume per-key values; it derives gap presence from `viewModel.allFactors` (factor titles + `hasValidData`). Adopting the new helper means changing the card's data source and re-deriving its activeGaps logic. That's a real behavior change in a UI surface, not just a refactor.
  - The plan's sub-cause keys (`mood_gap`, `symptom_gap`, `meal_gap`, `water_gap`, `sleep_gap`) **don't match** `engagementPenalty`'s actual keys. The real keys per `StressScoring.swift:587-606` are: `no_mood`, `no_food`, `no_water`, `low_steps`, `no_reflection`. There is no `symptom_gap`, no `sleep_gap`, no `meal_gap` distinct from `no_food`.
- **Impact**: The plan's listed engagement keys will not align with what the helper can return; sub-cause rows will be mislabeled. Calling this "small" scope creep underestimates the diff vs. `EngagementGapsCard`'s current code path.
- **Recommendation**:
  - Update §7's table to use the actual keys: `no_mood`, `no_food`, `no_water`, `low_steps`, `no_reflection`.
  - Add `now:` to the `engagementBreakdown` signature so behaviour matches `engagementPenalty`.
  - Carve out the `EngagementGapsCard` adoption as an *optional* follow-up step — it's not required for the change-log feature to function, and it's not a literal refactor. v1 should ship the helper used only by the change log; the card can adopt it later.

#### H2. `lastResult` persistence vs. semantic staleness across scoring changes

- **Location**: §6.4, §14 ("Persisted `lastResult` decode fails after future scoring change" — Risk: Low).
- **Problem**: The plan says decode failure is the only risk and is handled by the anchor-row fallback. But Codable conformance is auto-synthesized — if a future scoring change *adds* a property to `StressResult` or `FactorPoints` with a default, decode will *succeed* on the old payload (Codable will use the default value), not fail. That makes `lastResult` "valid" but semantically stale. The diff will then attribute the new property's apparent change to whatever `pendingReason` is set, fabricating a row that has no real cause.
  Worse: the 13-factor list relies on positional indexing (per `StressViewModel.factorTitle(_:)`). If the factor order ever changes (e.g., Tier B reorder, or a new factor inserted), `zip(prev.factors, next.factors)` (§6.2) will silently align the wrong indices and generate garbage rows.
- **Impact**: Silent data corruption in the activity log after any scoring change.
- **Recommendation**:
  - Add a version sentinel to the persisted blob: `struct StressLastResultEnvelope: Codable { let version: Int; let result: StressResult }`. On version mismatch, treat as missing and emit an anchor row.
  - Consider keying factors by name (or stable ID), not by index. This is a larger refactor — at minimum, add a `let factorKey: String` to `FactorPoints` and persist by-key in the change log. Alternative: snapshot the factor order alongside the result and refuse to diff if the order ever differs.
  - Document the upgrade path in §6.4 and bump the sentinel whenever `StressResult`/`FactorPoints` shape changes.

#### H3. Plan claims "no entitlements / signing changes" without verifying — also no `ModelContainer` impact assessment

- **Location**: §5.3, §13.
- **Problem**: The signing/entitlements claim is correct (verified: no pbxproj signing edits, no .entitlements changes, no bundle ID changes — adding a SwiftData @Model in a synchronized group does not require any of these). Per repo memory file `feedback_signing_entitlements.md`, this should be explicitly confirmed *with a one-line verification* in the plan, not just asserted.
  Additionally, the plan does not evaluate whether adding `StressChangeEntry.self` to the `ModelContainer` types in `WellPlateApp.swift:39` triggers a SwiftData migration. SwiftData lightweight migration handles additive schema changes, but the project also has the `WellPlateWidget` extension (which may have its own ModelContainer); the plan doesn't address whether the widget extension needs the new type registered too. The Activity log isn't widgetised, but the *container schema* must be consistent across all targets opening the same store.
- **Impact**: If the widget's ModelContainer is configured with a subset of types and the main app's ModelContainer adds a type the widget doesn't know about, you can hit "missing class" errors when SwiftData opens the store. (This depends on the widget's actual configuration; needs verification.)
- **Recommendation**:
  - Confirm in plan: "Signing/entitlements verified: no edits to *.entitlements, pbxproj signing fields, or bundle IDs."
  - Add a step to inspect every target that opens the SwiftData store (`WellPlateWidget`, `ScreenTimeMonitor`, `ScreenTimeReport` if any of them open the App Group store) and either register `StressChangeEntry.self` everywhere or confirm it's only in the main-app schema with no shared store conflict.

#### H4. `@Query` vs. paged `FetchDescriptor` mix in §9.7 — write-amplification problem

- **Location**: §9.7.
- **Problem**: `@Query` re-fires on *every* SwiftData change in its predicate range. With `emitChangeEntries` saving inside `applyResult`, *and* `StressActivityView` open, every recompute that emits even one row will re-fetch the today section's `@Query` and re-render. With a 30s ticker firing in the background while the sheet is open, that's a re-render every 30s minimum (more if engagement ramps tick over thresholds). Combined with C4's revised volume estimate, this is fine for performance — but it means animations on the today section will re-trigger continuously, and `LazyVStack`/`List` row identity may flicker.
  Separate concern: the plan proposes `@Query` for today and `FetchDescriptor` for older days. SwiftData `@Query` requires the predicate be known at view-construction time; the proposed dynamic source-filter chip changes the predicate. Either the chip filters *post-query* in memory (defeats the indexed predicate) or the view is re-built when the chip changes (filter chip becomes a state holder + `@Query(filter:)` projection). Either is implementable; the plan doesn't specify which.
- **Impact**: Either UI thrash (re-fetch on every save while sheet open) or an under-performing in-memory filter that defeats the predicate. Minor at expected volumes but worth resolving in the plan.
- **Recommendation**: Use `FetchDescriptor` exclusively, manually re-fetched on chip change and on a `.onChange(of: viewModel.totalScore)` (or an explicit `@Published var changeEntryCount`) trigger. This decouples the activity sheet's fetch policy from SwiftData's reactivity.

#### H5. `emitChangeEntries` early-returns on `usesMockData` AND `!isAuthorized` — but mock mode can still need rows

- **Location**: §6.2 first two `guard`s, §12.
- **Problem**: The plan early-returns from `emitChangeEntries` when `usesMockData == true` (correct: mock mode reads `StressMockSnapshot.changeEntries` directly per §12) and when `!isAuthorized` (correct for live mode). But:
  - `requestPermissionAndLoad()` sets `isAuthorized = true` for mock mode (`StressViewModel.swift:204`). So the second guard never fires in mock. Fine.
  - `StressActivityView` initialised with `mockSnapshot: StressMockSnapshot?` must check if mock mode is active to choose the data path (snapshot vs. SwiftData). The plan's wording in §12 ("a new `StressActivityView` initializer for mock mode") is vague — it doesn't specify the DI shape (init takes a snapshot? takes a `usesMockData: Bool`? reads `AppConfig.shared.mockMode` directly?). Without spec, the implementer might accidentally read SwiftData even in mock mode (returning *real* rows from a previous live session — there is no SwiftData reset between mock-toggle changes).
  - **Mock + live data leak**: if a user runs the app in live mode for a day (writing real rows), then toggles `AppConfig.mockMode` to true via the debug screen and opens the Activity sheet, real rows will be visible if `StressActivityView` falls back to a SwiftData query. Or, if it always reads the snapshot in mock mode, fine — but the plan must specify this behavior unambiguously.
- **Impact**: Mode-dependent data leak. Probably hits during dev/QA with `AppConfig.mockMode` toggled.
- **Recommendation**:
  - Specify `StressActivityView`'s decision: explicitly take `viewModel: StressViewModel` (or just `usesMockData: Bool`) and route to either `mockSnapshot.changeEntries` or a `FetchDescriptor`. Never both.
  - Document that toggling `AppConfig.mockMode` does not clear existing SwiftData rows — that's expected, but the Activity view should not surface them in mock.

### MEDIUM (Fix During Implementation)

#### M1. `prev.timestamp` read in §6.2 day-rollover guard but `prev` is `StressScoring.StressResult`, which has no `timestamp`

- **Location**: §6.2 line 229: `if prev == nil || !Calendar.current.isDate(prev.timestamp, inSameDayAs: now)`.
- **Problem**: `StressScoring.StressResult` (`StressScoring.swift:141-151`) has fields `score, factors, driverSum, recovery, engagementPenalty, patternPenalty, calibrator, confidence, raw` — and no timestamp. The plan implicitly assumes `prev` is augmented with a timestamp on persistence. Either:
  - Persist a wrapper `(timestamp: Date, result: StressResult)` to UserDefaults — currently un-mentioned.
  - Or compare against a separately-tracked `lastEmissionDay: Date` — currently un-mentioned.
- **Impact**: Compile-time error if implemented as written.
- **Recommendation**: Make §6.4's persistence shape explicit: either persist `StressLastResultEnvelope { version, capturedAt, result }` and compare `capturedAt`, or store `lastEmissionDay` in UserDefaults separately. Update §6.2 accordingly.

#### M2. Anchor row schema mismatch with `StressChangeEntry` non-optional fields

- **Location**: §6.2 line 230, §5.1.
- **Problem**: `anchorRow(group: group, totalBefore: 0, totalAfter: next.score)` is mentioned but the model's init (§5.1) requires `prevValue`, `nextValue`, `subjectKey`, `subjectIcon`, `deltaPoints`, etc., all non-optional. An anchor row has no factor subject. Plan §5.2 lists `.anchor` in the enum, but the row's fields aren't documented.
- **Impact**: Implementer will guess at sentinel values (`prevValue = 0`, `nextValue = next.score`, `deltaPoints = 0`, `subjectKey = "anchor"`?). Inconsistent guesses across implementation and view filtering will cause display bugs.
- **Recommendation**: Add a §5.1.a "Anchor row conventions" sub-section: `kind = .anchor`, `subjectKey = "anchor"`, `subjectIcon = "circle.dashed"`, `deltaPoints = 0`, `prevValue = totalBefore`, `nextValue = totalAfter`. Empty `detailText` falls back to a localised "Day started" / "First reading" string in the view layer.

#### M3. `purgeOldChangeEntries()` predicate captures a `let cutoff` — SwiftData `#Predicate` macro limitations

- **Location**: §11.1.
- **Problem**: `#Predicate { $0.timestamp < cutoff }` works in SwiftData iOS 17+, but only if `cutoff` is a constant (it is here, computed via `Calendar.date(byAdding:value:to:)`). The plan's snippet is technically correct, but the SwiftData `#Predicate` macro is finicky about non-trivial captures. Worth a build-verify call-out.
- **Impact**: Possible compiler diagnostic ("predicate not supported") on edge Swift/SwiftData versions. Low risk but specific to this project (Xcode 26 / iOS 26.1).
- **Recommendation**: Verify on iOS 26.1 toolchain. If problematic, use `FetchDescriptor` with `.fetchAll()` and filter in Swift (acceptable at retention scale of <30×daily-row-count rows).

#### M4. §11.3 retention purge timing relative to Activity sheet open

- **Location**: §11.3.
- **Problem**: Plan says purge runs "once per app launch" via `loadData()` with a UserDefaults timestamp guard. But:
  - `loadData()` is called from the Stress tab's `.task` (`StressView.swift:128`) — *not* from app launch directly. If the user opens the app to a non-Stress tab, the purge does not run.
  - The Activity sheet opens from the Stress toolbar — so by definition, the user is on the Stress tab and `loadData()` will have completed (via `.task` ordering before `.toolbar` interaction). So in practice there's no race.
  - Edge case: scenePhase becomes `.active` triggers `loadData()` (`StressView.swift:147`) — purge guard ensures it runs at most 1×/day, OK.
  - Real risk: SwiftData's data dump for a user who never opens the Stress tab. Without the tab being opened, `loadData()` never runs, and rows accumulate indefinitely. (Granted, no rows are written either, since `applyResult` only fires from the same flow — so this is moot.)
  - Confirm by tracing every `applyResult` callsite: all roots back through Stress tab paths or shared `StressViewModel` triggers. Home reads `totalScore` only and doesn't call recompute. So purge timing tied to `loadData()` is fine.
- **Impact**: Likely none in practice, but reliance on tab-tied lifecycle for storage cleanup is fragile if `StressViewModel`'s recompute triggers ever expand.
- **Recommendation**: Move purge to `StressViewModel.init` (or a one-shot at MainTabView-level `.task`), not coupled to Stress-tab `.task`. The 1×/day guard makes init-time safe. Update §11.3 and §17 step 6.

#### M5. Hidden coupling: `WidgetRefreshHelper.refreshStress(viewModel: self)` runs after `applyResult` — does it observe the new per-row writes?

- **Location**: `StressViewModel.swift:321, 335` (current code). Plan does not mention.
- **Problem**: The widget refresh helper publishes the latest stress score. Adding row writes inside `applyResult` doesn't break this, but the widget extension reads SwiftData; if `WellPlateWidget` registers `StressChangeEntry` it must include the new model in its container (see H3). If it doesn't, opening the same App Group store from the widget side will fail when the model class is referenced anywhere.
- **Impact**: Build verification on `WellPlateWidget` scheme will catch this if it occurs.
- **Recommendation**: Per plan §13.1, run `xcodebuild -scheme WellPlateWidget` as part of Verification, not just `WellPlate`. The current §13.1 only runs the main-app build. Update.

#### M6. `StressMockSnapshot.changeEntries` — type must be `[StressChangeEntry]`, but @Model classes can't easily be created standalone

- **Location**: §12.
- **Problem**: `StressChangeEntry` is `@Model`, and per SwiftData conventions, instances should be created in a `ModelContext`. Building `[StressChangeEntry]` for mock fixtures *outside* a context is technically allowed, but:
  - The plan in §12 says "pre-baked rows" and mentions a `MockChangeEntry` type ("`var changeEntries: [MockChangeEntry] = []`"). Then later "reads `mockSnapshot.changeEntries` directly (bypasses SwiftData query)". Two different shapes referenced — `MockChangeEntry` (sibling struct?) vs. `[StressChangeEntry]` (the @Model class)? The plan doesn't pick one.
  - Using `[StressChangeEntry]` mock instances may keep them in memory uninserted into a context, which is fine for read-only display, but `@Model` classes are normally bound to a context. Test thoroughly.
- **Impact**: Implementer will pick one and may or may not match what the View expects. Inconsistency between §12 and §9 (which assumes SwiftData-fetched `StressChangeEntry`).
- **Recommendation**: Define an explicit DTO, e.g. `struct MockChangeEntry { /* mirrors StressChangeEntry fields */ }`, and have `StressActivityView` accept either `[StressChangeEntry]` or `[MockChangeEntry]` via a small protocol. Spec it in §5 or §12.

### LOW (Consider for Future)

#### L1. `Confidence` enum already lacks `Codable` rawValue serialization friction — but its `String` raw value uses lowercase, conflicting with future locale-aware labels

- **Location**: `StressScoring.swift:155-173`.
- **Problem**: Adding `Codable` to `Confidence` is mechanical (it's already `String` raw-valued). Just call out that `JSONEncoder` will serialize via `RawRepresentable` automatically.
- **Recommendation**: Just confirm "RawRepresentable enums encode their rawValue" in the plan, no action needed.

#### L2. Filter chip taxonomy in §9.5 may not match `StressChangeSource.CaseIterable` ordering

- **Location**: §9.5.
- **Problem**: Chip values "All / Auto / Logs / Mood / Symptoms / Screen Time / Food / Calibration" are nice display groupings, but `StressChangeSource.allCases` from §5.2 has a different shape (per-source, not category). The plan shouldn't assume the chip set maps 1:1 to enum cases.
- **Recommendation**: Add a `StressChangeFilter` view-state enum mapping each chip to a `Set<StressChangeSource>` (plus an "Auto" → all `.autoX` cases, "Logs" → all `.manualX` cases). Add to §9.5.

#### L3. Day-rollover anchor row doesn't suppress other rows in the same group when prev *also* exists with stale day

- **Location**: §6.2 line 229–233, §6.3 last row.
- **Problem**: Plan says day-rollover anchor row "skips all other emissions." Code shows a `persistAndReturn(rowsToInsert)` early return — fine. But if the user crosses midnight at a moment when a major user action also fires (e.g., logging a meal at 00:00:30), the anchor row absorbs the meal-log delta and the "Logged a meal" attribution is lost. This may or may not be desirable.
- **Recommendation**: Consider emitting the anchor row + the full delta set (since prev was yesterday, today's delta is the entire raw score). Or add an explicit "skip-only-when-no-explicit-reason" carve-out. Document the choice in §6.3.

#### L4. `engagementPenalty` activation guard means engagement rows can flicker on/off

- **Location**: `StressScoring.swift:572-573`.
- **Problem**: `engagementPenalty` returns 0 when no factors have data. So at app first-launch, `engagementPenalty == 0`. Once a single factor lights up (e.g., HK steps land), `engagementPenalty` jumps to its full ramp-position value. The diff will treat this as a giant engagement-penalty delta, potentially > 5 pts, attributed to whatever source fired.
- **Recommendation**: Treat the activation transition as an anchor-style event (the change log has no prior context). Add to §6.2 logic: if `prev.engagementPenalty == 0 && next.engagementPenalty > 0` and `prev` was the anchor row, suppress all engagement-gap rows in this group (use a single "Engagement scoring activated" row if anything).

### INFO

#### I1. Plan correctly does not modify pbxproj, .entitlements, or signing fields

- Verified: §13 explicitly disclaims these. The repo memory file `feedback_signing_entitlements.md` flag is satisfied. No action.

#### I2. PBXFileSystemSynchronizedRootGroup means new files auto-include — confirmed for `WellPlate/` paths

- Verified: both `WellPlate/Models/StressChangeEntry.swift` and `WellPlate/Features + UI/Stress/Views/StressActivityView.swift` paths are inside the synchronized group. No `pbxproj` edit required.

#### I3. `@MainActor` isolation correctly assumed throughout

- `StressViewModel` is `@MainActor final class` — confirmed at `StressViewModel.swift:21-22`. SwiftData inserts on Main thread are correct.

#### I4. Plan correctly identifies that `StressReading` is unaffected

- Verified — `StressReading` (line 12 of `Models/StressReading.swift`) has 4 fields and is consumed by `StressDayChartView`/`StressWeekChartView` independently. No change required.

---

## Missing Elements

- [ ] Explicit definition of `StressLastResultEnvelope` (or equivalent) to carry timestamp + version alongside `StressResult` for persistence (M1, H2).
- [ ] Anchor-row field defaults / sentinel conventions (M2).
- [ ] Explicit `StressActivityView` initializer signature for mock-vs-live data routing (H5).
- [ ] Verification that `WellPlateWidget` (and any other extension that opens the SwiftData store) builds with `StressChangeEntry` registered (M5, H3).
- [ ] Build-verify command must include `WellPlateWidget` scheme, not just `WellPlate` (M5).
- [ ] §6.2 algorithm: what happens when `prev.factors.count != next.factors.count`? (`zip` silently truncates — would lose factors.) Add a guard or explicit handling (H2 partly covers this via versioning).
- [ ] §8.1 sub-table for non-`recompute` paths (`loadData()`, `.refreshable`, scenePhase, `.task`) — see C2.
- [ ] Filter-chip-to-source mapping (L2).
- [ ] Day-rollover behavior when a user action coincides (L3).
- [ ] Engagement-penalty activation transition handling (L4).
- [ ] Calibrator-impact formula corrected to isolate calibrator-only contribution (C1).

---

## Unverified Assumptions

- [ ] *Adding `Codable` to `StressScoring.StressResult` / `FactorPoints` / `Confidence` is mechanical.* — Risk: **Low**. Verified: all field types are `Double`, `Bool`, `String`, `[FactorPoints]`, and a `String`-rawValue enum. Codable synthesis will work. (Caveat: `StressInputs` is *not* Codable — but the plan correctly persists only `StressResult`.)
- [ ] *5-minute `StressTimerService` and 30s `refreshTicker` will not collide.* — Risk: **Low** (both run on MainActor, recompute is synchronous). However, see C3 for the async-suspend-point race in `loadData()`.
- [ ] *`engagementBreakdown(inputs:)` helper extraction does not change scoring output.* — Risk: **Medium**. The current `engagementPenalty` aggregates with a `min(Weights.engagementCap, sum)` clamp at the end; a per-key breakdown won't naturally expose how the clamp distributes when the sum exceeds 18. Document the clamp distribution policy (proportional? truncate last? track raw?) in §7.
- [ ] *Activity sheet closes when ScreenTimeMonitor fires off-screen.* — Risk: **Low**, no change.
- [ ] *Mock mode `changeEntries` fixtures don't drift from production schema.* — Risk: **Medium**. If real `StressChangeEntry` adds fields, mock fixtures must update. Worth a `// MARK: keep in sync with StressChangeEntry` comment in `StressMockSnapshot`.
- [ ] *Widget extension shares `ModelContainer` schema with main app.* — Risk: **Medium-High**. Needs verification (M5/H3).

---

## Questions for Clarification

1. **C1**: Is the intent that calibrator rows should fire when the multiplier itself moves (delta in `calib`), or when the calibrator-attributable score impact moves (delta in `score - raw`)? The plan implies the latter; the formula encodes the former. Which is correct?
2. **C2**: Should the 5-minute `StressTimerService` ticker have a distinct `StressChangeSource` case, or fold into `.autoTicker`? (User-facing label implication: chip says "30s refresh" but actual fires include 5-min cadence too.)
3. **H1**: Should `EngagementGapsCard` adoption of `engagementBreakdown` ship in this PR or be carved out? (Plan says "in same PR for consistency"; auditor recommends carving out.)
4. **H4**: Should the source filter chip be a `@Query`-rebuild trigger, or use a manually-driven `FetchDescriptor`? Affects performance characteristics.
5. **H5**: Concrete `StressActivityView` init signature — `init(viewModel: StressViewModel)`, or `init(modelContext: ModelContext, mockEntries: [MockChangeEntry]? = nil)`?
6. **L3**: At day rollover during a user action, prefer single anchor row (loses attribution) or anchor + full delta (preserves attribution at cost of one extra row)?
7. **§14 Risk table**: "30s ticker generates row floods" is rated Medium with mitigation "no row is written if no factor moved." But §9.8 estimates 2,000–6,000 rows/day. Which is the real expectation?

---

## Recommendations (priority-ordered)

1. **Fix C1 first.** The calibrator formula is wrong as written and will produce visible row spam. Replace with `next.raw * (next.calibrator - prev.calibrator)` (or equivalent isolated quantity) and update §6.3.
2. **Redesign source threading per C3.** Pass `reason:` explicitly through `recompute(reason:)` → `applyResult(_:reason:)`. Eliminate the `pendingReason` stash. This is a 1-hour refactor but prevents a class of bugs.
3. **Re-table all `applyResult` triggers per C2.** The current §8.1 misses 4–5 real call sites; the table should be exhaustive before implementation.
4. **Re-estimate row volume per C4.** Re-derive based on cached HK + per-tick threshold = ~30–80 rows/day under normal use. Then re-examine whether infinite-scroll paging is needed.
5. **Add envelope versioning per H2.** `StressLastResultEnvelope { version: Int; capturedAt: Date; result: StressResult }`. This also resolves M1 and partially L4.
6. **Carve out engagement-breakdown card adoption per H1.** Ship the helper for change-log consumption only. `EngagementGapsCard` change is a separate PR. Use real keys (`no_mood`, `no_food`, `no_water`, `low_steps`, `no_reflection`).
7. **Verify widget container per H3/M5.** Add `xcodebuild -scheme WellPlateWidget` to §13.1.
8. **Specify mock routing per H5/M6.** Pick one DTO shape and one routing decision in `StressActivityView`. Document.
9. **Anchor-row conventions per M2.** Add §5.1.a.
10. **Filter chip mapping per L2.** Add `StressChangeFilter` view-state enum.

After C1–C4, H1–H5, and M1–M6 are addressed, this plan should be ready for the checklist phase. The architecture is sound; the diff-emission edge cases need tightening.
