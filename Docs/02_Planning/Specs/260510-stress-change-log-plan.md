# Plan: Stress Score Change Log ("Activity")

**Date**: 2026-05-10
**Status**: Awaiting audit
**Slug**: `stress-change-log`
**Related code**:
- `WellPlate/Features + UI/Stress/Views/StressView.swift`
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
- `WellPlate/Models/StressReading.swift`
- `WellPlate/Core/Services/StressScoring.swift`
- `WellPlate/Features + UI/Home/Views/WellnessCalendarView.swift` (toolbar pattern reference)

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
3. List is reverse-chronological (newest at top), filterable by source, infinite-scroll for older days.
4. Each row explains *what moved*, *by how many points*, and *why* (source attribution).
5. No noise filter — every change is logged. Calibrator entries threshold at ≥1 point of total-score effect to avoid silent-drift spam.

---

## 3. Non-Goals (Out of Scope)

- No backfill of historical changes from before this feature ships. The log starts at install/update time.
- No per-row comments, tags, or user editing.
- No widget surface — log lives only inside the Stress tab.
- No analytics / telemetry on change frequency (could be a follow-up).
- No watchOS surface in this iteration (the existing Watch companion plan is unrelated).
- No graph/chart visualisation of the log — it's a list. (Aggregate views can come later.)

---

## 4. Approach Summary

**Data model**: New `@Model class StressChangeEntry` (sibling to `StressReading`, *not* a replacement). Captures one factor or penalty or calibrator delta per row.

**Diff hook**: One new private method on `StressViewModel` — `emitChangeEntries(prev:next:reason:)` — called from `applyResult(_:)` *before* the new result replaces the old. Inserts N rows in a single transactional `modelContext.save()`, all sharing a `groupID: UUID` and incrementing `sequence: Int`.

**Source attribution**: Replace the current `String` source ("auto"/"manual") with a typed `StressChangeSource` enum, threaded through every recompute call site. Existing `StressReading.source` left unchanged (string column kept for SwiftData stability) — new enum lives only on the new model.

**View**: New `StressActivityView` presented as a sheet, with sectioned reverse-chronological list (Today / Yesterday / Older), per-row explanation, and a source filter chip row.

**Toolbar**: Convert the single trailing `ToolbarItem` in `StressView` to a `ToolbarItemGroup(placement: .topBarTrailing)` matching `WellnessCalendarView.swift:35`. Two icon-only buttons: Insights (existing label collapsed to icon) + new Activity (`clock.arrow.circlepath`).

**Mock mode**: Generate synthetic `StressChangeEntry` fixtures from `StressMockSnapshot.weekReadings` so previews are populated.

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
    var subjectKey: String       // factor title ("Sleep"), penalty sub-cause key ("mood_gap"), or "calibrator"
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

### 5.2 New supporting enums (in same file, non-`@Model`)

```swift
enum ChangeEntryKind: String {
    case factor              // one of the 13 stress factors moved
    case engagementGap       // a sub-cause of engagementPenalty changed (mood_gap, symptom_gap, ...)
    case patternPenalty      // pattern penalty changed
    case calibrator          // calibrator multiplier shifted score by ≥1 pt
    case anchor              // "Day started" or first-install anchor — no delta
}

enum StressChangeSource: String, CaseIterable {
    // Auto sources — recompute fired without explicit user action
    case autoTicker          // 30s refreshTicker
    case autoScenePhase      // app foregrounded
    case autoAppOpen         // first load on app launch
    case autoHealthKitChange // HK observer query (if added later)

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
    case manualOther         // catch-all for QuickLog etc.

    var displayLabel: String { ... }   // "30s refresh", "App opened", "Logged water" ...
    var isAuto: Bool { rawValue.hasPrefix("auto") }
}
```

### 5.3 Schema migration

- `StressChangeEntry` is purely **additive** in SwiftData. No changes to existing models. No pbxproj edits (auto-included via `PBXFileSystemSynchronizedRootGroup`).
- Add `StressChangeEntry.self` to `ModelContainer` in `WellPlateApp.swift`.
- `StressReading` remains untouched — it still feeds `StressDayChartView` / `StressWeekChartView`.
- **Personal/free dev team note**: per repo memory, *do not* touch entitlements / signing. This change involves none of that.

### 5.4 Retention policy

- Cleanup pass on `StressViewModel.loadData()`: delete `StressChangeEntry` rows older than **30 days**. Single `FetchDescriptor` + `modelContext.delete(_:)` loop, then save.
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

New code:

```swift
private var lastResult: StressScoring.StressResult?      // in-memory cache
private var pendingReason: StressChangeSource = .autoTicker  // set by caller of recompute()

private func applyResult(_ result: StressScoring.StressResult) {
    let prev = lastResult ?? loadPersistedLastResult()    // see 6.4
    emitChangeEntries(prev: prev, next: result, reason: pendingReason)
    lastResult = result
    persistLastResult(result)                              // see 6.4

    // existing publish code unchanged
    totalScore = result.score
    ...
}
```

### 6.2 `emitChangeEntries(prev:next:reason:)` algorithm

```
guard !usesMockData else { return }
guard isAuthorized else { return }

let now = Date()
let group = UUID()
var sequence = 0
var rowsToInsert: [StressChangeEntry] = []

// ── First-ever or day rollover guard ─────────────────────────
if prev == nil || !Calendar.current.isDate(prev.timestamp, inSameDayAs: now) {
    rowsToInsert.append(anchorRow(group: group, totalBefore: 0, totalAfter: next.score))
    persistAndReturn(rowsToInsert)
    return
}

// ── Per-factor deltas (13 factors) ───────────────────────────
for (idx, (p, n)) in zip(prev.factors, next.factors).enumerated() {
    let delta = n.points - p.points
    if abs(delta) < 0.01 { continue }       // no change
    rowsToInsert.append(factorRow(
        group: group, seq: sequence,
        title: factorTitle(idx),
        icon: factorIcon(idx),
        prev: p.points, next: n.points,
        delta: delta,
        totalBefore: prev.score, totalAfter: next.score,
        reason: reason
    ))
    sequence += 1
}

// ── Engagement penalty decomposition ─────────────────────────
// Reuse the breakdown EngagementGapsCard already does — see Section 7.
let prevGaps = engagementBreakdown(from: prev.factors)
let nextGaps = engagementBreakdown(from: next.factors)
for (key, prevVal) in prevGaps {
    let nextVal = nextGaps[key] ?? 0
    let delta = nextVal - prevVal
    if abs(delta) < 0.01 { continue }
    rowsToInsert.append(engagementRow(
        group: group, seq: sequence, gapKey: key,
        prev: prevVal, next: nextVal, delta: delta,
        totalBefore: prev.score, totalAfter: next.score,
        reason: reason
    ))
    sequence += 1
}

// ── Pattern penalty (single line) ────────────────────────────
let patternDelta = next.patternPenalty - prev.patternPenalty
if abs(patternDelta) >= 0.01 {
    rowsToInsert.append(patternRow(
        group: group, seq: sequence,
        prev: prev.patternPenalty, next: next.patternPenalty, delta: patternDelta,
        totalBefore: prev.score, totalAfter: next.score,
        reason: reason
    ))
    sequence += 1
}

// ── Calibrator (thresholded at ≥1 pt of total impact) ────────
let calibImpact = abs((next.score - next.raw) - (prev.score - prev.raw))
let calibratorChanged = abs(next.calibrator - prev.calibrator) > 0.001
if calibratorChanged && calibImpact >= 1.0 {
    rowsToInsert.append(calibratorRow(
        group: group, seq: sequence,
        prev: prev.calibrator, next: next.calibrator,
        deltaPoints: (next.score - next.raw) - (prev.score - prev.raw),
        totalBefore: prev.score, totalAfter: next.score,
        reason: reason
    ))
    sequence += 1
}

if !rowsToInsert.isEmpty {
    rowsToInsert.forEach { modelContext.insert($0) }
    try? modelContext.save()
}
```

### 6.3 Threshold rules summary

| Kind | Emit when |
|---|---|
| `factor` | `abs(delta) ≥ 0.01` (effectively "any change") |
| `engagementGap` | `abs(delta) ≥ 0.01` |
| `patternPenalty` | `abs(delta) ≥ 0.01` |
| `calibrator` | `abs(calibImpact) ≥ 1.0` *and* multiplier changed |
| `anchor` | First-ever recompute, or `prev.day != now.day` (skips all other emissions) |

### 6.4 Persisting `lastResult` across cold launch

`StressScoring.StressResult` is a plain struct (not Codable today). Two clean options:

- **A. Make `FactorPoints` and `StressResult` `Codable`**, store `Data` in `UserDefaults` under `wp.stress.lastResult`.
- **B. Persist a single `StressLastResultSnapshot` `@Model` row** in SwiftData (one row, upserted).

Plan picks **A** — pure value type, no SwiftData round-trip cost on every recompute. Add `Codable` conformance to `StressScoring.FactorPoints`, `StressResult`, and `Confidence` enum (5-line change). Read on VM init, write at end of `applyResult`.

If decode fails (e.g., schema drift), treat as missing → emit a single anchor row, not 13 zero-diff rows.

---

## 7. Engagement Penalty Decomposition

`StressScoring.computeStress` produces a single `engagementPenalty` number, but the underlying logic checks several gaps. The exact breakdown is needed for honest attribution.

**Investigation required during implementation**: read `StressScoring.swift:engagementPenalty(...)` (currently bundled into `computeStress`) and either:

- **(preferred)** extract a public helper `static func engagementBreakdown(inputs:) -> [String: Double]` returning a dict like `["mood_gap": 4, "symptom_gap": 0, "meal_gap": 2, ...]`. The aggregate equals the existing `engagementPenalty`. Use this from `EngagementGapsCard` *and* the change log so they agree.
- **(fallback)** in `StressViewModel`, replicate the breakdown at compute time using already-cached inputs.

The first approach is cleaner but couples the change log to a refactor of `StressScoring`. Plan recommends doing the refactor — it's small, the existing `EngagementGapsCard` already needs the same data, and centralising it avoids drift.

**Sub-cause keys (initial set)** — to be confirmed against actual scoring code during implementation:

| Key | Triggered by |
|---|---|
| `mood_gap` | No mood logged for the day |
| `symptom_gap` | No symptom check-in |
| `meal_gap` | < N meals logged |
| `water_gap` | No water logged |
| `sleep_gap` | No sleep data |

Each gets a `displayLabel`, `subjectIcon`, and a `closedDetail` / `openedDetail` string for the row UI.

---

## 8. Source Attribution Refactor

### 8.1 Current call sites of `recompute()` — must be tagged

From `grep` (`StressViewModel.swift`):

| Line | Caller | New `pendingReason` |
|---|---|---|
| `applyResult` ← `recompute()` chain | various | (set by caller via `recompute(reason:)`) |
| `loadData()` | (replaces `recompute` in flow) | `.autoAppOpen` on first call, `.autoScenePhase` thereafter |
| `refreshDietFactor()` | called after food log change | `.manualFoodLog` |
| `refreshDietFactorAndLogIfNeeded()` | onAppear | `.autoScenePhase` |
| `refreshScreenTimeOnly()` | 30s ticker, ScreenTimeManager | `.autoTicker` (ticker) / `.manualScreenTime` (input sheet) |
| `bindManualInputUpdates(...).sink` | manual log Combine pipe | `.manualOther` (refine per source if known) |

### 8.2 API change

```swift
func recompute(reason: StressChangeSource = .autoTicker) {
    pendingReason = reason
    let now = Date()
    ...
}
```

`refreshScreenTimeOnly()` becomes:

```swift
func refreshScreenTimeOnly(reason: StressChangeSource = .autoTicker) {
    recompute(reason: reason)
    logCurrentStress(source: reason.isAuto ? "auto" : "manual")
}
```

`StressView.swift:144` (the ticker `onReceive`) keeps the default `.autoTicker`. ScreenTimeInputSheet's commit hook would call `viewModel.refreshScreenTimeOnly(reason: .manualScreenTime)`.

### 8.3 Backwards compat

- `StressReading.source` remains a `String` — no migration needed. The new model uses the typed enum's `rawValue`.

---

## 9. View: `StressActivityView`

### 9.1 File

New: `WellPlate/Features + UI/Stress/Views/StressActivityView.swift`

### 9.2 Layout

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

### 9.3 Row design

- **Icon**: `subjectIcon` in a 32×32 colored circle. Tint = `accent for kind` (factor=blue, engagement=orange, pattern=purple, calibrator=teal, anchor=gray).
- **Title**: `detailText` (human-readable, e.g., "Logged Great mood", "Sleep updated", "Calibration adjusted").
- **Delta pill** trailing: `+/- N stress` with up-arrow (red-ish) for positive (more stress) or down-arrow (green-ish) for negative (less stress). **Sign convention**: negative = good for user.
- **Subtitle**: `HH:mm a · {source.displayLabel}`.
- Tappable for kinds where it makes sense (factor → opens corresponding `StressSheet` detail; calibrator → opens vital detail). For engagement / pattern / anchor → non-tappable.

### 9.4 Grouping

- Sections: Today, Yesterday, "Older — N more days" with infinite-scroll trigger.
- Within a section, rows are sorted by `(timestamp DESC, sequence ASC)`.
- Optional: collapse rows sharing the same `groupID` into one expandable row ("12:34 PM — 5 changes"). Default flat for v1; add collapse toggle in v2.

### 9.5 Filter chip behaviour

- Chip values: `All`, `Auto`, `Logs` (any manual.*), `Mood`, `Symptoms`, `Screen Time`, `Food`, `Calibration`.
- Filter applies an `#Predicate` on the fetch descriptor.

### 9.6 Empty state

- "No changes yet today. Your stress score will log changes here as your day unfolds."
- Show under "TODAY" only if today has zero rows.

### 9.7 Fetching

- Use `@Query` with a sort descriptor for **today** (cheap).
- For older sections, use a separate paged `FetchDescriptor` with `fetchLimit: 50` and a `lastFetchedTimestamp` cursor. Increment on infinite-scroll.
- Predicate: `#Predicate { $0.timestamp >= startOfToday }` and so on for sections.

### 9.8 Performance

- Storage estimate: 30s ticker × ~1–3 rows per recompute × 16 waking hours ≈ **2,000–6,000 rows/day**. SwiftData handles this trivially. UI must page (see 9.7) — never `@Query` the entire 30-day window.

---

## 10. Toolbar Integration

Replace the existing trailing block in `StressView.swift:109`:

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

Add `@State private var showActivity = false` and a corresponding `.sheet(isPresented: $showActivity) { StressActivityView(modelContext: modelContext) }` (or whatever DI shape matches; see 11).

**Visual implication**: Insights loses its inline "Insights" text label. The icon (`chart.bar.xaxis.ascending`) carries semantics. Accessibility label preserves screen-reader UX.

---

## 11. ViewModel Wiring

### 11.1 New `StressViewModel` additions

```swift
// MARK: - Change Log Support

private var lastResult: StressScoring.StressResult?
private var pendingReason: StressChangeSource = .autoTicker
private let lastResultDefaultsKey = "wp.stress.lastResult"

private func loadPersistedLastResult() -> StressScoring.StressResult? {
    guard let data = UserDefaults.standard.data(forKey: lastResultDefaultsKey),
          let decoded = try? JSONDecoder().decode(StressScoring.StressResult.self, from: data)
    else { return nil }
    return decoded
}

private func persistLastResult(_ result: StressScoring.StressResult) {
    guard let data = try? JSONEncoder().encode(result) else { return }
    UserDefaults.standard.set(data, forKey: lastResultDefaultsKey)
}

private func emitChangeEntries(
    prev: StressScoring.StressResult?,
    next: StressScoring.StressResult,
    reason: StressChangeSource
) {
    // ... see Section 6.2 algorithm
}

private func purgeOldChangeEntries() {
    let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    let descriptor = FetchDescriptor<StressChangeEntry>(
        predicate: #Predicate { $0.timestamp < cutoff }
    )
    if let stale = try? modelContext.fetch(descriptor) {
        stale.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
}
```

### 11.2 Hook order in `applyResult`

```swift
private func applyResult(_ result: StressScoring.StressResult) {
    let prev = lastResult ?? loadPersistedLastResult()
    emitChangeEntries(prev: prev, next: result, reason: pendingReason)
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

### 11.3 Cleanup hook

`loadData()` calls `purgeOldChangeEntries()` once per app launch (guard with a UserDefaults timestamp to not re-run more than 1×/day).

---

## 12. Mock Mode

`StressMockSnapshot.swift` (currently provides `weekReadings`, `todayReadings`, etc.) needs:

```swift
struct StressMockSnapshot {
    // existing fields...
    var changeEntries: [MockChangeEntry] = []   // pre-baked rows
}
```

`StressViewModel` early-returns from `emitChangeEntries` when `usesMockData == true`. A new `StressActivityView` initializer for mock mode reads `mockSnapshot.changeEntries` directly (bypasses SwiftData query).

`StressMockSnapshot.default` gets ~12 hand-crafted entries spanning today + yesterday so previews are non-empty.

---

## 13. Build Considerations

- No pbxproj edits (synchronized group).
- No entitlements / signing changes.
- New file count: **2** (`StressChangeEntry.swift`, `StressActivityView.swift`). Plus optional `StressChangeSource.swift` if the enums grow large enough to deserve their own file.
- Edits: `StressViewModel.swift`, `StressView.swift`, `StressMockSnapshot.swift`, `WellPlateApp.swift` (ModelContainer types), `StressScoring.swift` (Codable conformance + engagement breakdown helper).

### 13.1 Verification

- `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
- Manual smoke: open Stress tab → Activity button → verify rows render, filter chips work, infinite scroll loads older days, mock-mode preview is populated.
- HealthKit permission state verified for both authorized + unauthorized paths (Activity button hidden when `!isAuthorized`).

---

## 14. Risks & Open Questions

| Risk | Likelihood | Mitigation |
|---|---|---|
| `engagementPenalty` decomposition diverges from current bundled formula | Medium | Extract `engagementBreakdown(inputs:)` helper and have `EngagementGapsCard` adopt it in same PR — guarantees agreement |
| `Codable` conformance on `StressScoring.StressResult` breaks something | Low | Pure-value structs already; conformance is mechanical. Build verifies. |
| 30s ticker generates row floods in foreground | Medium | The diff-based emission means **no row is written if no factor moved** — ticker only writes when HK data actually changes. Still want eyeball check after first day's usage. |
| Recompute mid-frame (during animation) writes to SwiftData on Main and stutters UI | Low | `modelContext.save()` is fast for small inserts; existing `logCurrentStress` already writes on every recompute. |
| Persisted `lastResult` decode fails after future scoring change | Low | Catch decode failure → seed anchor row; log scenario for follow-up |
| User installs update → first launch emits 13 "factor changed from 0" rows | High if not handled | Handled: first-ever recompute (no `lastResult`) emits a single anchor row, not per-factor diffs |
| Day rollover at midnight emits noise | High if not handled | Handled: `prev.day != now.day` short-circuits to single anchor row |
| Calibrator continuous drift floods log | High if not thresholded | Handled: only emit calibrator row when total-score impact ≥1 pt |
| Filter chips overflow on small screens | Low | Horizontal `ScrollView`, `LazyHStack` |
| ChangeEntry model schema needs to evolve | Medium | All fields are simple Codable types; SwiftData lightweight migration handles add-only changes |

### 14.1 Decisions still open

1. **Engagement breakdown extraction**: do it in this plan, or defer to a separate refactor PR? Plan recommends doing it here — but it expands scope into `StressScoring.swift`.
2. **Collapse same-`groupID` rows in UI**: v1 flat or v1 collapsible? Plan recommends flat for v1; add collapsible toggle in v2 if rows feel noisy in real usage.
3. **HealthKit observer queries** (currently absent): if added later as a fifth recompute trigger, source enum already has `.autoHealthKitChange` reserved.

---

## 15. File-by-File Change List

### New
- `WellPlate/Models/StressChangeEntry.swift` — `@Model`, `ChangeEntryKind`, `StressChangeSource` enums
- `WellPlate/Features + UI/Stress/Views/StressActivityView.swift` — sheet view with sections, filter chips, infinite scroll, empty state

### Modified
- `WellPlate/App/WellPlateApp.swift` — add `StressChangeEntry.self` to `ModelContainer` types
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` — `lastResult` cache, `pendingReason`, `emitChangeEntries`, `purgeOldChangeEntries`, `recompute(reason:)` signature, callsite updates
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — toolbar refactor (single → group), `showActivity` state, sheet hookup
- `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` — `changeEntries` field + fixtures
- `WellPlate/Core/Services/StressScoring.swift` — `Codable` on `StressResult`/`FactorPoints`/`Confidence`; new `engagementBreakdown(inputs:)` helper
- `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift` — adopt `engagementBreakdown` helper (consistency guarantee)

### Untouched (explicit)
- `WellPlate/Models/StressReading.swift` — kept for chart compatibility
- `WellPlate.xcodeproj/project.pbxproj` — synchronized group handles new files
- Any *.entitlements file — no entitlement changes

---

## 16. Estimated Scope

- **New code**: ~450 lines (model 90 + view 280 + VM additions 80)
- **Modified code**: ~120 lines across 6 files
- **Risk surface**: Low — additive model, isolated UI, optional enum migration on persisted result
- **Time estimate**: 1 focused implementation session + 1 polish/QA pass

---

## 17. Implementation Order (for checklist phase)

1. Add `StressChangeEntry` model + enums; register in `ModelContainer`.
2. Add `Codable` to `StressScoring.StressResult` / `FactorPoints` / `Confidence`.
3. Extract `engagementBreakdown(inputs:)` helper; adopt in `EngagementGapsCard`.
4. Add `lastResult` cache + persistence + `emitChangeEntries` to `StressViewModel`.
5. Refactor `recompute(reason:)` signature; thread `StressChangeSource` through call sites.
6. Add `purgeOldChangeEntries()` + once-per-day guard.
7. Build `StressActivityView` (sections + filter chips + paging).
8. Toolbar refactor in `StressView`; wire sheet.
9. Mock-mode fixtures in `StressMockSnapshot`.
10. Build + manual smoke + edge-case checks (cold launch, day rollover, kill+restart).
