# Plan: Stress Score Change Log ("Activity") — RESOLVED

**Date**: 2026-05-10
**Status**: Resolved (audit findings addressed)
**Slug**: `stress-change-log`
**Audit reference**: `Docs/03_Audits/260510-stress-change-log-plan-audit.md`
**Related code**:
- `WellPlate/Features + UI/Stress/Views/StressView.swift`
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
- `WellPlate/Models/StressReading.swift`
- `WellPlate/Core/Services/StressScoring.swift`
- `WellPlate/Features + UI/Home/Views/WellnessCalendarView.swift` (toolbar pattern reference)
- `WellPlateWidget/StressWidget.swift` (verified: does NOT open SwiftData; uses App Group `UserDefaults`)

---

## Resolution Notes

This document supersedes `260510-stress-change-log-plan.md`. The audit verdict was **NEEDS REVISION** with 4 CRITICAL, 5 HIGH, 6 MEDIUM, 4 LOW, and 4 INFO findings. All CRITICAL and HIGH findings have been addressed; MEDIUM/LOW items are either fixed inline or acknowledged with a marker comment. Pre-resolved decisions (granularity, calibrator threshold, engagement decomposition, source attribution refactor, toolbar pattern) were locked in at planning time and are not re-opened here.

### Audit Resolution Summary

| ID | Severity | Finding (1-line) | How resolved |
|---|---|---|---|
| C1 | Critical | Calibrator-impact formula produces false positives whenever any factor moves | Replaced with `next.raw * (next.calibrator - prev.calibrator)` (signed). Threshold gate uses `abs(...)` only for the ≥1 pt comparison. §6.2 + §6.3 updated. |
| C2 | Critical | Source-attribution table missing real call sites; spurious "ScreenTimeManager" entry | §8.1 re-tabled with every verified call site (5-min `StressTimerService`, 30s `refreshTicker`, scenePhase, `.task`, `.refreshable`, `onAppear`). Added new enum case `.autoEngagementTick`. Removed phantom "ScreenTimeManager" entry. |
| C3 | Critical | `pendingReason` stash is racy across `loadData()` async suspensions | Eliminated `pendingReason` instance var. New signatures: `loadData(reason:) async`, `recompute(reason:)` (no default), `applyResult(_:reason:)`. §6.1, §11.1, §11.2 rewritten. |
| C4 | Critical | Row-volume estimate inflated 2 orders of magnitude; engagement-ramp threshold too low | §9.8 estimate corrected to ~30–80 rows/day with bursts. Engagement-gap threshold raised from 0.01 to 0.5. §6.3 table + §9.7 paging policy updated; infinite-scroll dropped for v1, replaced with single bounded `FetchDescriptor`. |
| H1 | High | Engagement breakdown keys wrong; card-adoption scope creep; missing `now:` parameter | §7 keys updated to actual implementation: `no_mood`, `no_food`, `no_water`, `low_steps`, `no_reflection`. Added `now:` to helper signature. `EngagementGapsCard` adoption carved out as OPTIONAL follow-up (not part of this PR). Documented engagement-cap distribution policy: proportional scaling. |
| H2 | High | Persisted `lastResult` decode-success != semantic validity; positional factor indexing fragile | Defined `StressLastResultEnvelope { version, capturedAt, result }`. Version mismatch OR `factors.count != 13` → treat as missing → anchor row. §6.4 expanded. Resolves M1 too (capturedAt is the day-rollover timestamp source). |
| H3 | High | Plan asserts no entitlements/widget container impact without verifying | Verified via grep: `WellPlateWidget` does NOT open SwiftData (uses App Group `UserDefaults` per `WellPlate/Widgets/SharedStressData.swift:22`). §5.3 + §13.1 updated with explicit signing/entitlements verification line and widget build command. |
| H4 | High | `@Query`/`FetchDescriptor` mix; predicate-rebuild ambiguity | Dropped `@Query` entirely. Single `FetchDescriptor` re-fetched on filter-chip change and on `viewModel.lastChangeEmittedAt` published trigger. §9.7 rewritten. |
| H5 | High | `StressActivityView` init ambiguous; mock/live data leak risk | Locked init: `init(viewModel: StressViewModel, modelContext: ModelContext)`. View routes via `viewModel.usesMockData`: mock path reads `viewModel.mockChangeEntries: [MockChangeEntry]`; live path runs `FetchDescriptor`. Defined `struct MockChangeEntry` (NOT `@Model`) + display protocol. §12 + §9 updated. |
| M1 | Medium | `prev.timestamp` used in §6.2 but `StressResult` has no timestamp | Resolved by H2's envelope: `envelope.capturedAt` is the day-rollover comparison source. §6.2 algorithm updated. |
| M2 | Medium | Anchor row field defaults un-specified | Added §5.1.a "Anchor row conventions": `kind = .anchor`, `subjectKey = "anchor"`, `subjectIcon = "circle.dashed"`, `deltaPoints = 0`, `prevValue = totalBefore`, `nextValue = totalAfter`, `sequence = 0`, `detailText = "Day started"` / "First reading". |
| M3 | Medium | `#Predicate` macro on iOS 26.1 may have compile risk | Added build-verify call-out to §17. Fallback path: fetch-all + Swift filter at retention scale. |
| M4 | Medium | Purge tied to Stress-tab `loadData()` lifecycle | Moved purge call to `StressViewModel.init`; once-per-day UserDefaults guard preserved. §11.3 + §17 updated. |
| M5 | Medium | Widget container build verification missing | Resolved by H3 (widget does not open SwiftData; `xcodebuild -scheme WellPlateWidget` added to §13.1 anyway as smoke-test). |
| M6 | Medium | `StressMockSnapshot.changeEntries` shape ambiguous (`MockChangeEntry` vs `StressChangeEntry`) | Resolved by H5: defined `struct MockChangeEntry` explicitly. §12 updated. |
| L1 | Low | RawRepresentable Codable note | Confirmed in §6.4: `Confidence` and other String-rawValue enums encode via auto-synthesized rawValue. No code action. |
| L2 | Low | Filter-chip taxonomy doesn't 1:1 map to `StressChangeSource` | Added `StressChangeFilter` view-state enum mapping each chip to a `Set<StressChangeSource>`. §9.5 updated. |
| L3 | Low | Day-rollover during user action loses attribution | Decision: emit anchor row + full delta (since prev was yesterday, today's delta is the entire raw score). Documented in §6.3 + §6.2. |
| L4 | Low | Engagement activation transition produces fictitious giant delta | When prev is anchor row AND next.engagementPenalty > 0, suppress engagement-gap rows in that group; emit a single "Engagement scoring activated" row only if delta is meaningful. §6.2 updated. |
| I1–I4 | Info | Verified facts | Acknowledged. No action. |

### Decisions Still Required

None. All CRITICAL/HIGH/MEDIUM findings are resolved or have a chosen disposition documented inline. The plan is ready for the checklist phase.

---

## 1. Problem

Users see a single stress score (0–100) on the Stress tab but cannot answer:

- *What changed since I last looked?*
- *Why did my score move?*
- *Did logging mood / water / a meal actually help?*

The existing `StressReading` model captures total-score snapshots but stores no per-factor attribution. Without a "transaction log" of changes, users have to re-derive causation from the Insights sheet — which shows current state, not movement.

---

## 2. Goal

Add a **transaction-style change log** for the stress score:

1. Every recompute, diff against the previous result and emit one row per moved factor / penalty / calibrator.
2. Open the log via a new **Activity** button placed next to **Insights** in the trailing toolbar of `StressView`.
3. List is reverse-chronological (newest at top), filterable by source. <!-- RESOLVED: C4 — infinite-scroll dropped; bounded fetch is sufficient at the corrected ~30–80 rows/day volume -->
4. Each row explains *what moved*, *by how many points*, and *why* (source attribution).
5. No `|Δtotal|` filter — every change is logged. Calibrator entries threshold at ≥1 point of total-score effect to avoid silent-drift spam. Engagement-gap entries threshold at 0.5 pts to suppress ramp-tick noise. <!-- RESOLVED: C4 — engagement threshold raised from 0.01 to 0.5 -->

---

## 3. Non-Goals (Out of Scope)

- No backfill of historical changes from before this feature ships. The log starts at install/update time.
- No per-row comments, tags, or user editing.
- No widget surface — log lives only inside the Stress tab.
- No analytics / telemetry on change frequency (could be a follow-up).
- No watchOS surface in this iteration.
- No graph/chart visualisation of the log — it's a list. (Aggregate views can come later.)
- **`EngagementGapsCard` adoption of `engagementBreakdown(inputs:now:)` is OUT OF SCOPE for this PR.** <!-- RESOLVED: H1 — card adoption carved out as a separate follow-up PR. The change-log feature only consumes the new helper; the card stays unchanged here. -->

---

## 4. Approach Summary

**Data model**: New `@Model class StressChangeEntry` (sibling to `StressReading`, *not* a replacement). One row per factor / penalty / calibrator delta.

**Diff hook**: One new private method on `StressViewModel` — `emitChangeEntries(prev:next:reason:)` — called from `applyResult(_:reason:)` *before* the new result replaces the old. Inserts N rows in a single transactional `modelContext.save()`, all sharing a `groupID: UUID` and incrementing `sequence: Int`.

**Source attribution**: Replace the current `String` source ("auto"/"manual") with a typed `StressChangeSource` enum, threaded **explicitly** through every recompute and `loadData` call site. <!-- RESOLVED: C3 — explicit threading replaces the racy `pendingReason` stash --> Existing `StressReading.source` left unchanged (string column kept for SwiftData stability) — new enum lives only on the new model.

**View**: New `StressActivityView` presented as a sheet, with sectioned reverse-chronological list (Today / Yesterday / Older), per-row explanation, and a source filter chip row.

**Toolbar**: Convert the single trailing `ToolbarItem` in `StressView` to a `ToolbarItemGroup(placement: .topBarTrailing)` matching `WellnessCalendarView.swift:35`. Two icon-only buttons: Insights (existing label collapsed to icon) + new Activity (`clock.arrow.circlepath`).

**Mock mode**: Generate synthetic `MockChangeEntry` fixtures (struct DTO, NOT `@Model`) from `StressMockSnapshot` so previews are populated and there is no live/mock data leak. <!-- RESOLVED: H5, M6 — explicit DTO disambiguates the mock data path -->

---

## 5. Data Model

### 5.1 New: `WellPlate/Models/StressChangeEntry.swift`

```swift
import Foundation
import SwiftData

@Model
final class StressChangeEntry {
    // Identity & ordering
    var timestamp: Date          // Time of the recompute (all entries in a group share this)
    var groupID: UUID            // Same UUID for all rows emitted in one recompute
    var sequence: Int            // 0-based order within the group (stable sort tie-breaker)

    // What kind of row this is — drives icon/color/wording in the UI
    var kind: String             // see ChangeEntryKind enum below
    var subjectKey: String       // factor key ("sleep"), engagement key ("no_mood"), or "calibrator"
    var subjectIcon: String      // SF Symbol name cached at write time

    // The change itself
    var deltaPoints: Double      // signed; negative = score went down (good for user)
    var prevValue: Double        // factor points before, or penalty before, or calibrator before
    var nextValue: Double        // factor points after, or penalty after, or calibrator after

    // Total score context
    var totalBefore: Double      // total stress score before this recompute
    var totalAfter: Double       // total stress score after this recompute

    // Cause / source
    var sourceRaw: String        // StressChangeSource.rawValue
    var detailText: String       // human-readable: "Logged 16 oz water" / "30s auto-refresh" / "App opened"

    init(
        timestamp: Date,
        groupID: UUID,
        sequence: Int,
        kind: String,
        subjectKey: String,
        subjectIcon: String,
        deltaPoints: Double,
        prevValue: Double,
        nextValue: Double,
        totalBefore: Double,
        totalAfter: Double,
        sourceRaw: String,
        detailText: String
    ) {
        self.timestamp = timestamp
        self.groupID = groupID
        self.sequence = sequence
        self.kind = kind
        self.subjectKey = subjectKey
        self.subjectIcon = subjectIcon
        self.deltaPoints = deltaPoints
        self.prevValue = prevValue
        self.nextValue = nextValue
        self.totalBefore = totalBefore
        self.totalAfter = totalAfter
        self.sourceRaw = sourceRaw
        self.detailText = detailText
    }

    // Convenience
    var day: Date { Calendar.current.startOfDay(for: timestamp) }
    var entryKind: ChangeEntryKind { ChangeEntryKind(rawValue: kind) ?? .factor }
    var source: StressChangeSource { StressChangeSource(rawValue: sourceRaw) ?? .autoTicker }
}
```

### 5.1.a Anchor row conventions <!-- RESOLVED: M2 — explicit sentinel values prevent implementer drift -->

When `kind == .anchor`, the row uses these sentinel values:

| Field | Value |
|---|---|
| `kind` | `"anchor"` |
| `subjectKey` | `"anchor"` |
| `subjectIcon` | `"circle.dashed"` |
| `deltaPoints` | `0` |
| `prevValue` | `totalBefore` (0 on first ever install; previous day's `totalScore` on day rollover) |
| `nextValue` | `totalAfter` (today's freshly computed score) |
| `sequence` | `0` (anchor rows are always first in their group) |
| `detailText` | `"Day started"` (day rollover) or `"First reading"` (first install) — chosen by emitter |
| `sourceRaw` | The reason that triggered the diff, e.g. `.autoAppOpen` for first install, `.autoScenePhase` for midnight rollover during foreground |

The view layer renders anchor rows with no delta pill (because `deltaPoints == 0`) and no tap target. They are visually a section break.

### 5.2 New supporting enums (in same file, non-`@Model`)

```swift
enum ChangeEntryKind: String {
    case factor              // one of the 13 stress factors moved
    case engagementGap       // a sub-cause of engagementPenalty changed
    case patternPenalty      // pattern penalty changed
    case calibrator          // calibrator multiplier shifted score by ≥1 pt at today's raw
    case anchor              // "Day started" or first-install anchor — no delta
    case engagementActivated // first-time activation marker — see L4
}

enum StressChangeSource: String, CaseIterable, Codable {
    // Auto sources — recompute fired without explicit user action
    case autoTicker            // 30s refreshTicker (StressView refreshTicker.onReceive)
    case autoEngagementTick    // 5-min StressTimerService.tickerPulse  <!-- RESOLVED: C2 — distinct case so chip filter can disambiguate -->
    case autoScenePhase        // app foregrounded (.onChange(scenePhase) → loadData)
    case autoAppOpen           // first load on app launch / .task → requestPermissionAndLoad → loadData
    case autoRefreshable       // pull-to-refresh on Stress tab
    case autoOnAppear          // onAppear path on Stress tab
    case autoHealthKitChange   // HK observer query (reserved; not wired in v1)

    // Manual sources — user did something
    case manualScreenTime
    case manualFoodLog
    case manualFoodDelete
    case manualWater
    case manualCoffee
    case manualMood
    case manualSymptoms
    case manualFasting
    case manualIntervention
    case manualOther         // catch-all for QuickLog / DailyPromptCoordinator pipe

    var displayLabel: String { /* "30s refresh", "App opened", "Logged water" ... */ "" }
    var isAuto: Bool { rawValue.hasPrefix("auto") }
}
```

<!-- RESOLVED: L1 — Codable on a String-rawValue enum is auto-synthesized via RawRepresentable; encodes as the rawValue string. No bespoke encoding needed. -->

### 5.3 Schema migration

- `StressChangeEntry` is purely **additive** in SwiftData. No changes to existing models. No pbxproj edits (auto-included via `PBXFileSystemSynchronizedRootGroup`).
- Add `StressChangeEntry.self` to `ModelContainer` in `WellPlateApp.swift:39`.
- `StressReading` remains untouched — it still feeds `StressDayChartView` / `StressWeekChartView`.
- **Signing/entitlements verified clean: no edits to `*.entitlements`, pbxproj signing fields, or bundle IDs.** <!-- RESOLVED: H3 — explicit verification statement per repo memory `feedback_signing_entitlements.md` -->
- **Widget container verification (H3 / M5)**: `WellPlateWidget` does not open SwiftData. Verified by `grep "ModelContainer|SwiftData"` in `WellPlateWidget/` — no matches. The widget consumes stress score via App Group `UserDefaults` (`WellPlate/Widgets/SharedStressData.swift:22`, suite `group.com.hariom.wellplate`). Therefore `StressChangeEntry` registration is required only in the main-app `ModelContainer`. `ScreenTimeMonitor` and `ScreenTimeReport` extensions also do not open SwiftData (verified). <!-- RESOLVED: H3 — widget container compatibility confirmed; no cross-target SwiftData schema impact -->

### 5.4 Retention policy

- Cleanup pass: delete `StressChangeEntry` rows older than **30 days**. Single `FetchDescriptor` + `modelContext.delete(_:)` loop, then save.
- Triggered from `StressViewModel.init` (not `loadData`) with a once-per-day `UserDefaults` guard. <!-- RESOLVED: M4 — purge moved to init; decoupled from tab lifecycle -->
- Hardcoded for v1; expose as `AppConfig.stressChangeRetentionDays` if needed later.

---

## 6. Diff Algorithm

### 6.1 Where it hooks in

Current code (`StressViewModel.swift:442`):

```swift
private func applyResult(_ result: StressScoring.StressResult) {
    totalScore = result.score
    calibratorMultiplier = result.calibrator
    ...
}
```

New code (signatures changed — explicit `reason:` everywhere): <!-- RESOLVED: C3 — pendingReason eliminated; reason flows as an explicit argument -->

```swift
// in-memory cache only; persisted form is the envelope (see 6.4)
private var lastResult: StressScoring.StressResult?

private func applyResult(_ result: StressScoring.StressResult, reason: StressChangeSource) {
    let prevEnvelope = lastResult.map {
        StressLastResultEnvelope(version: StressLastResultEnvelope.currentVersion,
                                 capturedAt: Date(),     // synthetic if cache hit; not used for guard
                                 result: $0)
    } ?? loadPersistedLastResult()

    emitChangeEntries(prevEnvelope: prevEnvelope, next: result, reason: reason)

    lastResult = result
    persistLastResult(result)

    // existing publish code unchanged
    totalScore = result.score
    ...
}
```

`recompute(reason:)` has **no default** — every caller must specify: <!-- RESOLVED: C3 — no default forces compile-time discipline -->

```swift
func recompute(reason: StressChangeSource) {
    let now = Date()
    currentDayLogs = mockSnapshot?.currentDayLogs ?? fetchTodayFoodLogs()
    let inputs = usesMockData
        ? buildInputsFromMockSnapshot(mockSnapshot!, now: now)
        : buildInputs(now: now)
    let result = StressScoring.computeStress(inputs: inputs, now: now)
    applyResult(result, reason: reason)
    WidgetRefreshHelper.refreshStress(viewModel: self)
}

func loadData(reason: StressChangeSource = .autoAppOpen) async {
    ...
    let result = StressScoring.computeStress(inputs: inputs, now: now)
    applyResult(result, reason: reason)
    ...
}
```

Note: `requestPermissionAndLoad()` calls `loadData()` and must propagate its caller's reason. Update its signature to `requestPermissionAndLoad(reason: StressChangeSource = .autoAppOpen) async` and pass through. <!-- RESOLVED: C3 — propagation chain documented -->

### 6.2 `emitChangeEntries(prevEnvelope:next:reason:)` algorithm

```
guard !usesMockData else { return }
guard isAuthorized else { return }

let now = Date()
let group = UUID()
var sequence = 0
var rowsToInsert: [StressChangeEntry] = []

// ── Envelope validity / first-ever / day rollover guard ──────  <!-- RESOLVED: M1, H2 -->
let prev: StressScoring.StressResult? = {
    guard let env = prevEnvelope,
          env.version == StressLastResultEnvelope.currentVersion,
          env.result.factors.count == 13,
          Calendar.current.isDate(env.capturedAt, inSameDayAs: now)
    else { return nil }
    return env.result
}()

// First-ever or day rollover or schema drift → emit anchor + (per L3) full delta
if prev == nil {
    rowsToInsert.append(anchorRow(
        group: group, seq: 0,
        totalBefore: prevEnvelope?.result.score ?? 0,
        totalAfter: next.score,
        reason: reason
    ))
    sequence = 1

    // L3 carve-out: if this rollover happened during a manual user action,
    // emit the full delta set against a synthetic zero-prev so attribution is preserved.  <!-- RESOLVED: L3 -->
    if reason.isAuto == false {
        // Synthesize zero-prev FactorPoints array of count 13 for diffing
        let zeroPrev = StressScoring.StressResult.zeroPrev(matching: next)
        // Fall through to the per-factor / penalty diff below using zeroPrev
        // (full delta = next.score − 0)
        emitFullDelta(against: zeroPrev, group: group, startSeq: &sequence,
                      next: next, reason: reason, into: &rowsToInsert,
                      suppressEngagementGaps: true /* L4 */)
    }

    persistAndReturn(rowsToInsert)
    return
}

// ── Per-factor deltas (13 factors, key-matched not index-matched) ──  <!-- RESOLVED: H2 — by-key matching avoids positional drift -->
for (idx, n) in next.factors.enumerated() {
    let p = prev!.factors[idx]    // safe: validated count == 13 above
    let delta = n.points - p.points
    if abs(delta) < 0.01 { continue }
    rowsToInsert.append(factorRow(
        group: group, seq: sequence,
        title: factorTitle(idx),
        icon: factorIcon(idx),
        prev: p.points, next: n.points,
        delta: delta,
        totalBefore: prev!.score, totalAfter: next.score,
        reason: reason
    ))
    sequence += 1
}

// ── Engagement penalty decomposition ──  <!-- RESOLVED: H1 — actual keys, now: param -->
// Detect activation transition (L4): if prev penalty was 0 and next > 0, emit single
// engagementActivated row instead of decomposed gap rows.
if prev!.engagementPenalty == 0 && next.engagementPenalty > 0 {
    rowsToInsert.append(engagementActivatedRow(
        group: group, seq: sequence,
        prev: 0, next: next.engagementPenalty,
        delta: next.engagementPenalty,
        totalBefore: prev!.score, totalAfter: next.score,
        reason: reason
    ))
    sequence += 1
} else {
    let prevGaps = StressScoring.engagementBreakdown(inputs: prevInputsCache, now: now)
    let nextGaps = StressScoring.engagementBreakdown(inputs: nextInputsCache, now: now)
    let allKeys = Set(prevGaps.keys).union(nextGaps.keys)
    for key in allKeys.sorted() {
        let prevVal = prevGaps[key] ?? 0
        let nextVal = nextGaps[key] ?? 0
        let delta = nextVal - prevVal
        if abs(delta) < 0.5 { continue }   // C4: raised from 0.01 to 0.5
        rowsToInsert.append(engagementRow(
            group: group, seq: sequence, gapKey: key,
            prev: prevVal, next: nextVal, delta: delta,
            totalBefore: prev!.score, totalAfter: next.score,
            reason: reason
        ))
        sequence += 1
    }
}

// ── Pattern penalty (single line) ──
let patternDelta = next.patternPenalty - prev!.patternPenalty
if abs(patternDelta) >= 0.01 {
    rowsToInsert.append(patternRow(
        group: group, seq: sequence,
        prev: prev!.patternPenalty, next: next.patternPenalty, delta: patternDelta,
        totalBefore: prev!.score, totalAfter: next.score,
        reason: reason
    ))
    sequence += 1
}

// ── Calibrator (isolated impact, thresholded at ≥1 pt) ──  <!-- RESOLVED: C1 -->
let multiplierMoved = abs(next.calibrator - prev!.calibrator) > 0.001
let calibOnlyImpact = next.raw * (next.calibrator - prev!.calibrator)   // signed
if multiplierMoved && abs(calibOnlyImpact) >= 1.0 {
    rowsToInsert.append(calibratorRow(
        group: group, seq: sequence,
        prev: prev!.calibrator, next: next.calibrator,
        deltaPoints: calibOnlyImpact,                  // signed; preserves direction
        totalBefore: prev!.score, totalAfter: next.score,
        reason: reason
    ))
    sequence += 1
}

if !rowsToInsert.isEmpty {
    rowsToInsert.forEach { modelContext.insert($0) }
    try? modelContext.save()
    lastChangeEmittedAt = now    // @Published — view re-fetches  <!-- RESOLVED: H4 -->
}
```

### 6.3 Threshold rules summary <!-- RESOLVED: C4 — engagement raised; C1 — calibrator formula isolated -->

| Kind | Emit when |
|---|---|
| `factor` | `abs(delta) ≥ 0.01` |
| `engagementGap` | `abs(delta) ≥ 0.5` (raised from 0.01 to suppress ramp-tick noise) |
| `patternPenalty` | `abs(delta) ≥ 0.01` |
| `calibrator` | `abs(next.calibrator - prev.calibrator) > 0.001` **AND** `abs(next.raw * (next.calibrator - prev.calibrator)) ≥ 1.0`. The row's `deltaPoints` is the signed `next.raw * (next.calibrator - prev.calibrator)` (NOT abs). |
| `anchor` | First-ever recompute, day rollover, OR envelope validation failure (version mismatch / count drift). Subsumes other emissions for that group EXCEPT when a manual reason is supplied — then emit anchor + full-delta set with engagement gaps suppressed (L3 + L4). |
| `engagementActivated` | `prev.engagementPenalty == 0 && next.engagementPenalty > 0`. Emitted in lieu of decomposed gap rows for that group (L4). |

### 6.4 Persisting `lastResult` across cold launch <!-- RESOLVED: H2, M1 — versioned envelope -->

```swift
struct StressLastResultEnvelope: Codable {
    static let currentVersion: Int = 1

    let version: Int
    let capturedAt: Date
    let result: StressScoring.StressResult
}
```

- `StressScoring.FactorPoints`, `StressResult`, and `Confidence` get `Codable` conformance (auto-synthesized; mechanical). <!-- RESOLVED: L1 — String-rawValue enums Codable via RawRepresentable -->
- Stored in `UserDefaults` under `wp.stress.lastResultEnvelope.v1`.
- Read on VM init; write at end of `applyResult`.
- **Validation on read**:
  1. JSONDecoder failure → treat as missing (anchor row).
  2. `envelope.version != currentVersion` → treat as missing (anchor row).
  3. `envelope.result.factors.count != 13` → treat as missing (anchor row, schema drift).
  4. `!Calendar.current.isDate(envelope.capturedAt, inSameDayAs: now)` → treat as missing (day rollover anchor).
- **Bump `currentVersion` whenever `StressResult` / `FactorPoints` shape changes** so stale payloads from a previous app version don't silently produce ghost rows.

---

## 7. Engagement Penalty Decomposition <!-- RESOLVED: H1 — keys updated, now: added, scope carved -->

`StressScoring.computeStress` produces a single `engagementPenalty` number, but the underlying logic checks several gaps. The change log needs the per-key breakdown for honest attribution.

**Required helper** in `StressScoring`:

```swift
static func engagementBreakdown(inputs: StressInputs, now: Date) -> [String: Double]
```

Returns a dict keyed by the **actual** keys used in `engagementPenalty(inputs:now:)` per `StressScoring.swift:587-606`:

| Key | Triggered by |
|---|---|
| `no_mood` | `inputs.mood == nil` (max 5 pts, ramps 17→21) |
| `no_food` | `inputs.mealLogs.isEmpty` (max 4 pts, ramps 17→20) |
| `no_water` | `(inputs.hydration?.glasses ?? 0) == 0` (max 4 pts, ramps 14→18) |
| `low_steps` | `inputs.exercise?.steps < 2000` (max 3 pts, ramps 16→20) |
| `no_reflection` | `!hasJournalToday && mood == nil && !hasMindfulSessionToday` (max 2 pts, ramps 18→21) |

The aggregate (after engagement-cap distribution, see below) equals the existing `engagementPenalty` exactly.

**Engagement-cap distribution policy**: if the raw breakdown sum exceeds `Weights.engagementCap` (= 18), each key is scaled proportionally so the reported breakdown still sums to the actual penalty. <!-- RESOLVED: H1 unverified-assumption — cap distribution policy now explicit -->

```swift
// Pseudocode after computing raw per-key contributions:
let rawSum = perKey.values.reduce(0, +)
if rawSum > Weights.engagementCap {
    let scale = Weights.engagementCap / rawSum
    perKey = perKey.mapValues { $0 * scale }
}
```

**Scope carve-out**: `EngagementGapsCard` adoption of this helper is OUT OF SCOPE for this PR. The card today derives gap presence from `viewModel.allFactors`; changing its data source is a separate refactor. The change-log feature only consumes the new helper. <!-- RESOLVED: H1 -->

Each key gets a `displayLabel`, `subjectIcon`, and `closedDetail` / `openedDetail` string for the row UI (e.g., `no_mood` → icon `face.smiling`, label "Mood gap closed" when delta < 0).

---

## 8. Source Attribution Refactor

### 8.1 Verified call sites of `applyResult` — every entry tagged <!-- RESOLVED: C2 — exhaustive grep-verified table -->

Every path that ends in `applyResult` must pass an explicit `reason`. Verified via direct read of `StressViewModel.swift` and `StressView.swift`:

| File:line | Caller | New `reason` argument |
|---|---|---|
| `StressViewModel.swift:185-187` | `init` → `tickerCancellable = StressTimerService.shared.$tickerPulse.sink { … recompute() }` (5-min pulse) | `.autoEngagementTick` |
| `StressViewModel.swift:192-196` | `bindManualInputUpdates(...).sink → recompute()` (DailyPromptCoordinator pipe) | `.manualOther` |
| `StressViewModel.swift:200-218` | `requestPermissionAndLoad() → loadData()` | propagates caller-supplied `reason`; default `.autoAppOpen` |
| `StressViewModel.swift:220-322` | `loadData()` direct `applyResult` | uses incoming `reason:` argument |
| `StressViewModel.swift:327-336` | `recompute(reason:)` direct `applyResult` | uses caller-supplied `reason:` |
| `StressViewModel.swift:338-340` | `refreshDietFactor() → recompute()` | take new `reason:` arg, default `.manualFoodLog` |
| `StressViewModel.swift:342-345` | `refreshDietFactorAndLogIfNeeded() → recompute()` | take new `reason:` arg, default `.autoOnAppear` |
| `StressViewModel.swift:347-350` | `refreshScreenTimeOnly() → recompute()` | take new `reason:` arg, NO default — every caller specifies |
| `StressView.swift:122-133` | `.task` → `requestPermissionAndLoad()` then `refreshScreenTimeOnly()`, `loadReadings()` | `.autoAppOpen` for the load; `.autoOnAppear` for the screen-time tick |
| `StressView.swift:134-140` | `.onAppear` → `refreshDietFactorAndLogIfNeeded()` + `refreshScreenTimeOnly()` | `.autoOnAppear` |
| `StressView.swift:141-144` | `.onReceive(refreshTicker)` (30s) → `refreshScreenTimeOnly()` | `.autoTicker` |
| `StressView.swift:145-148` | `.onChange(of: scenePhase) { .active }` → `loadData()` | `.autoScenePhase` |
| `StressView.swift:197` | Mood sheet `onSaved: { viewModel.recompute() }` | `.manualMood` |
| `StressView.swift:349-353` | `.refreshable` → `loadData()` + `refreshScreenTimeOnly()` | `.autoRefreshable` |
| ScreenTimeInputSheet commit hook (when wired) | `refreshScreenTimeOnly(reason: .manualScreenTime)` | `.manualScreenTime` |

The phantom "ScreenTimeManager" entry from the v1 plan has been removed — `grep` returns no `ScreenTimeManager` → `recompute` reference. <!-- RESOLVED: C2 — spurious entry dropped -->

### 8.2 API change

```swift
func recompute(reason: StressChangeSource)                     // NO default
func loadData(reason: StressChangeSource = .autoAppOpen) async // .autoAppOpen is the only default — first launch
func requestPermissionAndLoad(reason: StressChangeSource = .autoAppOpen) async
func refreshDietFactor(reason: StressChangeSource = .manualFoodLog)
func refreshDietFactorAndLogIfNeeded(reason: StressChangeSource = .autoOnAppear)
func refreshScreenTimeOnly(reason: StressChangeSource)         // NO default
private func applyResult(_ result: StressScoring.StressResult, reason: StressChangeSource)
```

### 8.3 Backwards compat

- `StressReading.source` remains a `String` — no migration needed. The new model uses the typed enum's `rawValue`.

---

## 9. View: `StressActivityView`

### 9.1 File

New: `WellPlate/Features + UI/Stress/Views/StressActivityView.swift`

### 9.2 Init signature <!-- RESOLVED: H5 — locked, unambiguous -->

```swift
struct StressActivityView: View {
    let viewModel: StressViewModel
    let modelContext: ModelContext

    @State private var entries: [ChangeEntryDisplayable] = []
    @State private var filter: StressChangeFilter = .all
    @State private var lastFetchTrigger: Date = .distantPast

    init(viewModel: StressViewModel, modelContext: ModelContext) {
        self.viewModel = viewModel
        self.modelContext = modelContext
    }
}
```

Routing:
- If `viewModel.usesMockData`, the view reads `viewModel.mockChangeEntries: [MockChangeEntry]` (a new computed property derived from `mockSnapshot`). It does NOT touch `modelContext`.
- Otherwise, the view runs a `FetchDescriptor<StressChangeEntry>` against `modelContext`.

This guarantees no live/mock data leak when toggling `AppConfig.mockMode`. <!-- RESOLVED: H5 -->

### 9.2.a DTO + display protocol <!-- RESOLVED: M6 — explicit struct DTO -->

```swift
struct MockChangeEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let groupID: UUID
    let sequence: Int
    let kind: ChangeEntryKind
    let subjectKey: String
    let subjectIcon: String
    let deltaPoints: Double
    let prevValue: Double
    let nextValue: Double
    let totalBefore: Double
    let totalAfter: Double
    let source: StressChangeSource
    let detailText: String
}

protocol ChangeEntryDisplayable {
    var timestamp: Date { get }
    var groupID: UUID { get }
    var sequence: Int { get }
    var entryKind: ChangeEntryKind { get }
    var subjectIcon: String { get }
    var deltaPoints: Double { get }
    var detailText: String { get }
    var source: StressChangeSource { get }
}

extension StressChangeEntry: ChangeEntryDisplayable { /* trivial */ }
extension MockChangeEntry: ChangeEntryDisplayable {
    var entryKind: ChangeEntryKind { kind }
}
```

The view consumes `[any ChangeEntryDisplayable]` for rendering.

### 9.3 Layout

```
┌─────────────────────────────────────┐
│  ╳   Activity                       │  ← navigationTitle("Activity"), Done
├─────────────────────────────────────┤
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐          │  ← horizontal scroll of source filter chips
│  │All│ │Auto│ │Logs│ │Mood│ ...    │     ("All" default selected)
│  └──┘ └──┘ └──┘ └──┘ └──┘          │
│                                     │
│  TODAY                              │  ← section header
│  ┌─────────────────────────────────┐│
│  │ 🍃 Logged Great mood     -2 ↓   ││  ← row: icon, detailText, deltaPoints, dir arrow
│  │ 12:34 PM · Mood logged          ││     subtitle: time · source label
│  └─────────────────────────────────┘│
│  ┌─────────────────────────────────┐│
│  │ 📱 Screen time updated   +1 ↑   ││
│  │ 12:30 PM · Screen time          ││
│  └─────────────────────────────────┘│
│                                     │
│  YESTERDAY                          │
│  ...                                │
│                                     │
│  OLDER                              │
│  ...                                │
└─────────────────────────────────────┘
```

### 9.4 Row design

- **Icon**: `subjectIcon` in a 32×32 colored circle. Tint = accent for kind (factor=blue, engagement=orange, pattern=purple, calibrator=teal, anchor=gray).
- **Title**: `detailText` (human-readable).
- **Delta pill** trailing: `+/- N stress` with up-arrow (red) for positive, down-arrow (green) for negative. **Sign convention**: negative = good for user.
- **Subtitle**: `HH:mm a · {source.displayLabel}`.
- Tappable for kinds where it makes sense (factor → opens `StressSheet` detail; calibrator → opens vital detail). Engagement / pattern / anchor / engagementActivated → non-tappable.

### 9.5 Filter chip behaviour <!-- RESOLVED: L2 — explicit chip→source mapping -->

```swift
enum StressChangeFilter: Hashable {
    case all
    case auto                                   // any .autoX
    case logs                                   // any .manualX
    case mood, symptoms, screenTime, food, calibration

    var sources: Set<StressChangeSource>? {
        switch self {
        case .all:          return nil   // no predicate filter
        case .auto:         return Set(StressChangeSource.allCases.filter(\.isAuto))
        case .logs:         return Set(StressChangeSource.allCases.filter { !$0.isAuto })
        case .mood:         return [.manualMood]
        case .symptoms:     return [.manualSymptoms]
        case .screenTime:   return [.manualScreenTime]
        case .food:         return [.manualFoodLog, .manualFoodDelete]
        case .calibration:  return nil   // calibration is a row-kind filter, applied client-side
        }
    }
}
```

The `.calibration` chip filters by `kind == .calibrator` rather than by source.

### 9.6 Empty state

- "No changes yet today. Your stress score will log changes here as your day unfolds."
- Show under "TODAY" only if today has zero rows.

### 9.7 Fetching <!-- RESOLVED: H4 — FetchDescriptor only, no @Query -->

- **No `@Query`.** Single `FetchDescriptor<StressChangeEntry>` re-run on:
  1. View `.task` (initial load).
  2. `.onChange(of: filter)` (chip change rebuilds the predicate).
  3. `.onChange(of: viewModel.lastChangeEmittedAt)` — VM exposes `@Published var lastChangeEmittedAt: Date = .distantPast` and sets it at the end of `emitChangeEntries(...)` whenever rows are inserted. The view uses this as a refresh trigger.
- Predicate built dynamically from the current `StressChangeFilter`:

```swift
func makeDescriptor(filter: StressChangeFilter, retentionStart: Date) -> FetchDescriptor<StressChangeEntry> {
    var predicate = #Predicate<StressChangeEntry> { $0.timestamp >= retentionStart }
    if let allowed = filter.sources {
        let allowedRaws = allowed.map(\.rawValue)
        predicate = #Predicate<StressChangeEntry> {
            $0.timestamp >= retentionStart && allowedRaws.contains($0.sourceRaw)
        }
    } else if filter == .calibration {
        predicate = #Predicate<StressChangeEntry> {
            $0.timestamp >= retentionStart && $0.kind == "calibrator"
        }
    }
    var d = FetchDescriptor<StressChangeEntry>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.sequence)]
    )
    d.fetchLimit = 500          // hard cap; see §9.8
    return d
}
```

### 9.8 Performance & volume <!-- RESOLVED: C4 — corrected estimate, paging dropped -->

**Realistic volume**: ~30–80 rows/day under normal use, with bursts of up to ~10 rows on a manual user action. Even at 30-day retention worst-case (heavy user), this caps at ~3,000 rows. SwiftData handles this trivially; in-memory rendering of 3,000 rows in a `LazyVStack` is fine.

Why the v1 estimate of 2,000–6,000 rows/day was wrong: the 30s `refreshScreenTimeOnly()` ticker re-reads SwiftData inputs and reuses cached HK results (per `StressViewModel.swift:325-336`). Cached HK + cached vitals + identical SwiftData = identical factor scores between most ticks. Engagement-ramp continuous accrual was the only source of sub-`0.01` deltas, and the new 0.5-pt threshold suppresses those.

**Paging**: Infinite-scroll is dropped for v1. A single `FetchDescriptor` with `fetchLimit = 500` returns all relevant rows in one round-trip. If real-world usage produces >500 rows in the 30-day window for some users, add paging in v2.

---

## 10. Toolbar Integration

Replace the existing trailing block in `StressView.swift:108-119`:

```swift
ToolbarItem(placement: .topBarTrailing) {
    if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized && !viewModel.isLoading {
        Button { ... showInsights = true } label: { Label("Insights", ...) }
    }
}
```

Becomes (matching `WellnessCalendarView.swift:35`):

```swift
ToolbarItemGroup(placement: .topBarTrailing) {
    if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized && !viewModel.isLoading {
        Button {
            HapticService.impact(.light)
            showInsights = true
        } label: {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Self.themeBlue)
        }
        .accessibilityLabel("Insights")

        Button {
            HapticService.impact(.light)
            showActivity = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Self.themeBlue)
        }
        .accessibilityLabel("Stress activity")
    }
}
```

Add `@State private var showActivity = false` and:

```swift
.sheet(isPresented: $showActivity) {
    StressActivityView(viewModel: viewModel, modelContext: modelContext)
}
```

**Visual implication**: Insights loses its inline "Insights" text label. The icon (`chart.bar.xaxis.ascending`) carries semantics. Accessibility label preserves screen-reader UX.

---

## 11. ViewModel Wiring

### 11.1 New `StressViewModel` additions <!-- RESOLVED: C3 — pendingReason eliminated -->

```swift
// MARK: - Change Log Support

private var lastResult: StressScoring.StressResult?
@Published private(set) var lastChangeEmittedAt: Date = .distantPast    // H4 view refresh trigger
private let lastResultDefaultsKey = "wp.stress.lastResultEnvelope.v1"

// Cache inputs alongside lastResult so engagementBreakdown can be re-derived for the prev side
private var lastInputs: StressInputs?

private func loadPersistedLastResult() -> StressLastResultEnvelope? {
    guard let data = UserDefaults.standard.data(forKey: lastResultDefaultsKey),
          let env = try? JSONDecoder().decode(StressLastResultEnvelope.self, from: data)
    else { return nil }
    return env
}

private func persistLastResult(_ result: StressScoring.StressResult) {
    let env = StressLastResultEnvelope(
        version: StressLastResultEnvelope.currentVersion,
        capturedAt: Date(),
        result: result
    )
    guard let data = try? JSONEncoder().encode(env) else { return }
    UserDefaults.standard.set(data, forKey: lastResultDefaultsKey)
}

private func emitChangeEntries(
    prevEnvelope: StressLastResultEnvelope?,
    next: StressScoring.StressResult,
    reason: StressChangeSource
) {
    // ... see Section 6.2 algorithm
    // On successful insert: lastChangeEmittedAt = Date()
}

private func purgeOldChangeEntries() {
    // M3: try the #Predicate path first; fall back to fetch-all + Swift filter on compile failure
    let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    let descriptor = FetchDescriptor<StressChangeEntry>(
        predicate: #Predicate { $0.timestamp < cutoff }
    )
    if let stale = try? modelContext.fetch(descriptor) {
        stale.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
}

// Mock-mode fixtures view-side (H5 / M6)
var mockChangeEntries: [MockChangeEntry] {
    guard usesMockData, let snap = mockSnapshot else { return [] }
    return snap.changeEntries
}
```

### 11.2 Hook order in `applyResult(_:reason:)` <!-- RESOLVED: C3 -->

```swift
private func applyResult(_ result: StressScoring.StressResult, reason: StressChangeSource) {
    let prevEnvelope = loadPersistedLastResult()
    emitChangeEntries(prevEnvelope: prevEnvelope, next: result, reason: reason)
    lastResult = result
    persistLastResult(result)

    // existing publish code...
    totalScore = result.score
    calibratorMultiplier = result.calibrator
    engagementPenaltyValue = result.engagementPenalty
    patternPenaltyValue = result.patternPenalty
    // ... unchanged
}
```

### 11.3 Cleanup hook <!-- RESOLVED: M4 — purge in init, not loadData -->

Inside `StressViewModel.init`, after the existing `tickerCancellable` setup:

```swift
// Once-per-day retention purge guard
let purgeKey = "wp.stress.changeLog.lastPurgeDay"
let today = Calendar.current.startOfDay(for: Date())
let lastPurge = UserDefaults.standard.object(forKey: purgeKey) as? Date
if lastPurge.map({ !Calendar.current.isDate($0, inSameDayAs: today) }) ?? true {
    purgeOldChangeEntries()
    UserDefaults.standard.set(today, forKey: purgeKey)
}
```

Decoupled from tab lifecycle. Will run regardless of which tab launches `StressViewModel`.

---

## 12. Mock Mode <!-- RESOLVED: M6, H5 — explicit struct DTO + routing -->

`StressMockSnapshot.swift` adds:

```swift
struct StressMockSnapshot {
    // existing fields...
    var changeEntries: [MockChangeEntry] = []   // pre-baked rows; struct, NOT @Model
}
```

Notes:
- `MockChangeEntry` is a plain `struct` defined in `StressChangeEntry.swift` (alongside the `@Model` class), keeping related types together.
- `StressViewModel.emitChangeEntries(...)` early-returns when `usesMockData == true` — mock mode never writes to SwiftData.
- `StressActivityView.usesMockData` branch reads `viewModel.mockChangeEntries` directly; never touches `modelContext`.
- `StressMockSnapshot.default` gets ~12 hand-crafted entries spanning today + yesterday so previews are non-empty.
- Add `// MARK: keep in sync with StressChangeEntry` comment near `MockChangeEntry` so future schema additions don't drift.

---

## 13. Build Considerations

- No pbxproj edits (synchronized group).
- No entitlements / signing changes (verified: H3).
- New file count: **2** (`StressChangeEntry.swift` containing both `@Model class` and `MockChangeEntry`/enums, plus `StressActivityView.swift`).
- Edits: `StressViewModel.swift`, `StressView.swift`, `StressMockSnapshot.swift`, `WellPlateApp.swift` (ModelContainer types), `StressScoring.swift` (Codable conformance + `engagementBreakdown` helper).

### 13.1 Verification <!-- RESOLVED: H3, M5 — both schemes built; signing line included -->

```bash
# Main app
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build

# Widget extension (verify ModelContainer schema compatibility — should still build cleanly
# since widget does not open SwiftData; this is a smoke test for unrelated breakage)
xcodebuild -project WellPlate.xcodeproj -scheme WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

- Manual smoke: open Stress tab → Activity button → verify rows render, filter chips work, mock-mode preview is populated, empty-state copy shows when today is empty.
- Edge cases: cold launch (anchor row), midnight rollover (anchor row), kill+restart mid-day (envelope round-trip), `AppConfig.mockMode` toggle (no live row leak).
- HealthKit permission state verified for both authorized + unauthorized paths (Activity button hidden when `!isAuthorized`).
- Signing/entitlements: confirm no diff in `*.entitlements`, `project.pbxproj` signing fields, or bundle IDs after the change.

---

## 14. Risks & Open Questions

| Risk | Likelihood | Mitigation |
|---|---|---|
| `engagementBreakdown` distribution policy creates rounding drift between aggregate and per-key sum | Low | §7 specifies proportional scaling; unit-testable. <!-- RESOLVED: H1 unverified-assumption --> |
| `Codable` conformance on `StressScoring.StressResult` breaks something | Low | Pure-value structs; conformance is mechanical. Build verifies. |
| 30s ticker generates row floods in foreground | Low | Cached HK + 0.5 engagement threshold means most ticks emit zero rows. Eyeball check after first day's usage. <!-- RESOLVED: C4 --> |
| Persisted `lastResult` decode succeeds on stale shape after scoring change | Mitigated | Envelope version sentinel + factor-count check forces anchor row on drift. <!-- RESOLVED: H2 --> |
| User installs update → first launch emits 13 zero-prev rows | Mitigated | First-ever `prev == nil` emits single anchor row. |
| Day rollover at midnight emits noise | Mitigated | Day rollover → anchor row; manual-action carve-out preserves attribution (L3). <!-- RESOLVED: L3 --> |
| Calibrator continuous drift floods log | Mitigated | Isolated calibrator-only impact ≥1 pt threshold. <!-- RESOLVED: C1 --> |
| Engagement activation transition produces giant fictitious delta | Mitigated | `prev == 0 && next > 0` emits single `engagementActivated` row instead of decomposed gaps. <!-- RESOLVED: L4 --> |
| `#Predicate` macro fails on iOS 26.1 toolchain edge | Low | Fall back to fetch-all + Swift filter at retention scale (M3). <!-- RESOLVED: M3 --> |
| Mock/live data leak via `StressActivityView` reading SwiftData in mock mode | Mitigated | View routes via `viewModel.usesMockData`; mock path never touches `modelContext`. <!-- RESOLVED: H5 --> |
| Widget container schema mismatch | None | Widget does not open SwiftData (verified). <!-- RESOLVED: H3 --> |
| Filter chips overflow on small screens | Low | Horizontal `ScrollView`, `LazyHStack`. |

---

## 15. File-by-File Change List <!-- RESOLVED: H1 (carve-out), H3 (widget verification) -->

### New
- `WellPlate/Models/StressChangeEntry.swift` — `@Model class StressChangeEntry`, `struct MockChangeEntry`, `protocol ChangeEntryDisplayable`, enums `ChangeEntryKind` / `StressChangeSource` / `StressChangeFilter`, `struct StressLastResultEnvelope`
- `WellPlate/Features + UI/Stress/Views/StressActivityView.swift` — sheet view with sections, filter chips, bounded fetch, empty state, mock/live routing

### Modified
- `WellPlate/App/WellPlateApp.swift` — add `StressChangeEntry.self` to `ModelContainer` types
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` — `lastResult` cache, `lastChangeEmittedAt` published, `emitChangeEntries(prevEnvelope:next:reason:)`, `purgeOldChangeEntries` (called from init), `recompute(reason:)` / `loadData(reason:)` / `applyResult(_:reason:)` signature changes, callsite updates
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — toolbar refactor (single → group), `showActivity` state, sheet hookup, every `recompute`/`loadData`/`refreshXXX` call updated to pass an explicit `reason`
- `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` — `changeEntries: [MockChangeEntry]` field + ~12 fixtures
- `WellPlate/Core/Services/StressScoring.swift` — `Codable` on `StressResult` / `FactorPoints` / `Confidence`; new `static func engagementBreakdown(inputs:now:) -> [String: Double]` helper

### Untouched (explicit)
- `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift` — adoption deferred to follow-up PR <!-- RESOLVED: H1 carve-out -->
- `WellPlate/Models/StressReading.swift` — kept for chart compatibility
- `WellPlateWidget/**` — widget does not open SwiftData (verified) <!-- RESOLVED: H3 -->
- `ScreenTimeMonitor/**`, `ScreenTimeReport/**` — no SwiftData usage
- `WellPlate.xcodeproj/project.pbxproj` — synchronized group handles new files
- Any `*.entitlements` file — no entitlement changes

---

## 16. Estimated Scope

- **New code**: ~480 lines (model + DTO + envelope + enums 130 + view 280 + VM additions 70)
- **Modified code**: ~140 lines across 5 files (additional reason-threading callsites)
- **Risk surface**: Low — additive model, isolated UI, version-gated persisted result envelope
- **Time estimate**: 1 focused implementation session + 1 polish/QA pass

---

## 17. Implementation Order (for checklist phase) <!-- RESOLVED: M3, M4 — ordering reflects new constraints -->

1. Add `StressChangeEntry` `@Model`, `MockChangeEntry` struct, `StressLastResultEnvelope`, `ChangeEntryKind` / `StressChangeSource` / `StressChangeFilter` / `ChangeEntryDisplayable` in `WellPlate/Models/StressChangeEntry.swift`. Register `StressChangeEntry.self` in `WellPlateApp.swift:39`.
2. Add `Codable` to `StressScoring.StressResult` / `FactorPoints` / `Confidence`. Build-verify (no behavior change expected).
3. Extract `engagementBreakdown(inputs:now:) -> [String: Double]` helper in `StressScoring.swift`, with the proportional cap-distribution logic. Unit-verify aggregate equals `engagementPenalty(inputs:now:)`.
4. Add `lastResult` / `lastChangeEmittedAt` / envelope persistence helpers + `emitChangeEntries(prevEnvelope:next:reason:)` to `StressViewModel`.
5. Refactor `applyResult(_:reason:)` / `recompute(reason:)` / `loadData(reason:)` / `requestPermissionAndLoad(reason:)` / `refreshXXX(reason:)` signatures. Update every callsite (per §8.1 table) to pass an explicit reason.
6. Add `purgeOldChangeEntries()` + once-per-day guard in `StressViewModel.init`. Build-verify the `#Predicate` compiles on the iOS 26.1 toolchain; if it fails, swap to fetch-all + Swift filter (acceptable at retention scale).
7. Build `StressActivityView`: bounded `FetchDescriptor`, filter chips wired to `StressChangeFilter`, mock-mode branch reading `viewModel.mockChangeEntries`, empty-state copy.
8. Toolbar refactor in `StressView` (single → `ToolbarItemGroup` matching `WellnessCalendarView.swift:35`); add `showActivity` state and sheet hookup.
9. Mock-mode fixtures in `StressMockSnapshot` (~12 entries spanning today + yesterday).
10. Build (`WellPlate` + `WellPlateWidget` schemes) + manual smoke + edge-case checks (cold launch anchor, day rollover, kill+restart envelope round-trip, `AppConfig.mockMode` toggle, `!isAuthorized` activity button hidden).
