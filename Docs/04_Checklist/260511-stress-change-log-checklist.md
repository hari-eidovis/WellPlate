# Implementation Checklist: Stress Score Change Log ("Activity")

**Source Plan**: `Docs/02_Planning/Specs/260510-stress-change-log-plan-RESOLVED.md`
**Date**: 2026-05-11
**Slug**: `stress-change-log`

---

## Notes for the Implementer

- The project uses `PBXFileSystemSynchronizedRootGroup`. Any new `.swift` file dropped under `WellPlate/` is auto-included in the build — **do NOT edit `project.pbxproj`**.
- **Signing/entitlements are OFF-LIMITS**. Do NOT touch `*.entitlements`, signing fields, or bundle IDs (repo memory: `feedback_signing_entitlements.md`). The resolved plan explicitly confirms no signing changes; if the build fails for a signing reason, STOP and ask the user.
- **Do NOT modify `EngagementGapsCard.swift`** — its adoption of the new helper is carved out (resolved plan §3, §7, §15).
- Every Swift change that compiles must be followed by the corresponding build gate. Skipping these will cascade compile errors across files.
- `[REVIEW]` flags steps that require human judgment (e.g., the wording of fixture entries, visual smoke checks).

---

## Pre-Implementation

- [x] 0.1 Read the resolved plan top-to-bottom (`Docs/02_Planning/Specs/260510-stress-change-log-plan-RESOLVED.md`).
  - Verify: You can name the 6 enum cases of `ChangeEntryKind`, the threshold rules in §6.3, and the call-site table in §8.1 without re-reading.
- [x] 0.2 Confirm the working tree is clean *except* for unrelated changes already noted in `git status` (Lottie/HomeView).
  - Verify: `git status` shows no in-flight edits to `WellPlate/Features + UI/Stress/**`, `WellPlate/Core/Services/StressScoring.swift`, `WellPlate/Models/`, or `WellPlate/App/WellPlateApp.swift`.
- [x] 0.3 Verify referenced files exist:
  - `/Users/hariom/Desktop/WellPlate/WellPlate/App/WellPlateApp.swift`
  - `/Users/hariom/Desktop/WellPlate/WellPlate/Core/Services/StressScoring.swift`
  - `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Stress/Views/StressView.swift`
  - `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
  - `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Views/WellnessCalendarView.swift` (toolbar pattern reference)
  - Verify: All 6 paths exist (Read or Glob).
- [x] 0.4 Baseline build — confirm the project compiles BEFORE any changes.
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`. If this fails, STOP — your environment is broken and changes will compound the problem.

---

## Phase 1: Data Model & Enums (Plan §17.1)

### 1.1 — Create `StressChangeEntry.swift`

- [x] 1.1.1 Create new file `/Users/hariom/Desktop/WellPlate/WellPlate/Models/StressChangeEntry.swift`.
  - Verify: File exists; opens in Xcode.
- [x] 1.1.2 Declare `enum ChangeEntryKind: String` with cases per plan §5.2: `factor`, `engagementGap`, `patternPenalty`, `calibrator`, `anchor`, `engagementActivated`.
  - Verify: All 6 cases compile; rawValue is the case name.
- [x] 1.1.3 Declare `enum StressChangeSource: String, CaseIterable, Codable` with cases per plan §5.2:
  - Auto: `autoTicker`, `autoEngagementTick`, `autoScenePhase`, `autoAppOpen`, `autoRefreshable`, `autoOnAppear`, `autoHealthKitChange`
  - Manual: `manualScreenTime`, `manualFoodLog`, `manualFoodDelete`, `manualWater`, `manualCoffee`, `manualMood`, `manualSymptoms`, `manualFasting`, `manualIntervention`, `manualOther`
  - Add computed `var isAuto: Bool { rawValue.hasPrefix("auto") }`.
  - Add computed `var displayLabel: String` returning a short human label per case (e.g. `autoTicker` → "30s refresh", `manualWater` → "Logged water", `autoAppOpen` → "App opened").
  - Verify: All 17 cases compile; `isAuto` returns `true` for every `auto*` case and `false` for every `manual*` case (mental test or Xcode autocomplete).
- [x] 1.1.4 Declare `@Model final class StressChangeEntry` exactly per plan §5.1 (all 13 fields + designated init + 3 convenience computeds `day`, `entryKind`, `source`).
  - Verify: Fields match plan §5.1 exactly (type and order); `entryKind` falls back to `.factor` if rawValue invalid; `source` falls back to `.autoTicker`.
- [x] 1.1.5 Declare `struct MockChangeEntry: Identifiable` per plan §9.2.a with all 14 listed fields. Add `// MARK: keep in sync with StressChangeEntry` comment above the struct (plan §12).
  - Verify: Struct is NOT `@Model`; conforms to `Identifiable` via `let id: UUID`; field set matches `StressChangeEntry` semantically.
- [x] 1.1.6 Declare `protocol ChangeEntryDisplayable` per plan §9.2.a with the 7 required gettable properties.
  - Verify: Both `StressChangeEntry` and `MockChangeEntry` will satisfy this protocol via extension.
- [x] 1.1.7 Add `extension StressChangeEntry: ChangeEntryDisplayable {}` (trivial — properties already exist) and `extension MockChangeEntry: ChangeEntryDisplayable { var entryKind: ChangeEntryKind { kind } }`.
  - Verify: Both extensions compile with no additional declarations needed beyond `entryKind` mapping on the mock.
- [x] 1.1.8 Declare `struct StressLastResultEnvelope: Codable` per plan §6.4 with `static let currentVersion: Int = 1`, `let version: Int`, `let capturedAt: Date`, `let result: StressScoring.StressResult`.
  - Note: This will not compile yet because `StressResult` is not yet `Codable` — that happens in Phase 2. To keep this phase building, either (a) defer this struct's declaration to Phase 2, or (b) declare it now and accept that this phase's build gate will fail until Phase 2 lands. **Choose (a)** — defer the envelope struct to step 2.4 so Phase 1 stays green.
  - Verify: For now, the `StressLastResultEnvelope` declaration is OMITTED from `StressChangeEntry.swift`. Add a `// TODO: StressLastResultEnvelope added in Phase 2` placeholder comment.
- [x] 1.1.9 Declare `enum StressChangeFilter: Hashable` per plan §9.5 with cases `all`, `auto`, `logs`, `mood`, `symptoms`, `screenTime`, `food`, `calibration` and the `var sources: Set<StressChangeSource>?` computed property.
  - Verify: `.all.sources` returns `nil`, `.auto.sources` returns the auto subset (7 cases), `.logs.sources` returns the manual subset (10 cases), `.calibration.sources` returns `nil` (filtered by `kind` client-side).

### 1.2 — Register in ModelContainer

- [x] 1.2.1 Edit `/Users/hariom/Desktop/WellPlate/WellPlate/App/WellPlateApp.swift:39`. Add `StressChangeEntry.self` to the `.modelContainer(for: [...])` array. Append it to the existing list (order doesn't matter to SwiftData but appending keeps the diff small).
  - Verify: Grep `StressChangeEntry.self` in `WellPlateApp.swift` returns exactly one match on line 39 area.

### 1.3 — Build gate (Phase 1)

- [x] 1.3.1 Build the main app target.
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`. Compile errors here indicate enum/model declaration drift — fix before proceeding.

---

## Phase 2: Codable on StressScoring Types (Plan §17.2)

### 2.1 — Add Codable to FactorPoints

- [x] 2.1.1 Open `/Users/hariom/Desktop/WellPlate/WellPlate/Core/Services/StressScoring.swift`. Locate `struct FactorPoints` (line 24).
  - Verify: Struct is found at the expected line.
- [x] 2.1.2 Add `Codable` conformance to the declaration: `struct FactorPoints: Codable { ... }`.
  - Verify: If `FactorPoints` already conforms to another protocol, append `, Codable`. Auto-synthesis applies — no manual encoder/decoder needed.

### 2.2 — Add Codable to StressResult

- [x] 2.2.1 Locate `struct StressResult` (line 141) in `StressScoring.swift`.
  - Verify: Struct found.
- [x] 2.2.2 Add `Codable` conformance: `struct StressResult: Codable { ... }`.
  - Verify: Conformance appended; auto-synthesis applies (all fields are `Double`/`Int`/`[FactorPoints]`/`Confidence` which now are Codable).

### 2.3 — Add Codable to Confidence

- [x] 2.3.1 Locate `enum Confidence: String` (line 155) in `StressScoring.swift`.
- [x] 2.3.2 Add `Codable` conformance: `enum Confidence: String, Codable { ... }`.
  - Verify: Conformance compiles. `Codable` on a `String`-rawValue enum is auto-synthesized via `RawRepresentable` (plan §L1 / §6.4) — encodes as the rawValue string. No bespoke encoding code required.

### 2.4 — Declare `StressLastResultEnvelope`

- [x] 2.4.1 In `/Users/hariom/Desktop/WellPlate/WellPlate/Models/StressChangeEntry.swift`, replace the Phase-1 TODO placeholder with the full `struct StressLastResultEnvelope: Codable` declaration per plan §6.4: `static let currentVersion: Int = 1`, `let version: Int`, `let capturedAt: Date`, `let result: StressScoring.StressResult`.
  - Verify: Struct is `Codable`; references `StressScoring.StressResult` (which is now `Codable` after step 2.2).

### 2.5 — Build gate (Phase 2)

- [x] 2.5.1 Build main app.
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`. Any "type does not conform to Codable" error means a nested type (likely `HistoryInput`-related) inside `StressResult` isn't yet Codable — inspect `StressResult` fields and add conformance to any custom nested types as needed.

---

## Phase 3: `engagementBreakdown` Helper (Plan §17.3, §7)

### 3.1 — Add the helper to `StressScoring`

- [x] 3.1.1 In `/Users/hariom/Desktop/WellPlate/WellPlate/Core/Services/StressScoring.swift`, after `engagementPenalty(inputs:now:)` (around line 610), add:
  ```swift
  static func engagementBreakdown(inputs: StressInputs, now: Date) -> [String: Double]
  ```
  - Verify: Signature matches plan §7 (with `now:` parameter — required by H1 resolution).
- [x] 3.1.2 Inside the helper, replicate the activation guard and ramp computation from `engagementPenalty` exactly:
  - Activation guard: `let factors = allFactors(inputs: inputs); guard factors.contains(where: \.hasData) else { return [:] }`
  - Compute `hour` from `now` via `Calendar.current` (same as line 576–577).
  - Define local `func ramp(start:end:) -> Double` identical to lines 579–582.
  - Verify: Lines 570–583 logic mirrored faithfully.
- [x] 3.1.3 Build a `var perKey: [String: Double] = [:]` and populate the same 5 keys per plan §7 table:
  - `"no_mood"` → `5 * ramp(17, 21)` if `inputs.mood == nil`
  - `"no_food"` → `4 * ramp(17, 20)` if `inputs.mealLogs.isEmpty`
  - `"no_water"` → `4 * ramp(14, 18)` if `(inputs.hydration?.glasses ?? 0) == 0`
  - `"low_steps"` → `3 * ramp(16, 20)` if `inputs.exercise?.steps` is non-nil AND `< 2000`
  - `"no_reflection"` → `2 * ramp(18, 21)` if `!hasJournalToday && mood == nil && !hasMindfulSessionToday`
  - Verify: Conditions match the existing `engagementPenalty` body line-for-line. Only keys with non-zero values are inserted (keys with zero value should NOT appear in the dict — saves filter work upstream).
- [x] 3.1.4 Apply proportional cap-distribution per plan §7:
  ```swift
  let rawSum = perKey.values.reduce(0, +)
  if rawSum > Weights.engagementCap {
      let scale = Weights.engagementCap / rawSum
      perKey = perKey.mapValues { $0 * scale }
  }
  return perKey
  ```
  - Verify: After scaling, `perKey.values.reduce(0, +)` equals `engagementPenalty(inputs:now:)` (mental check or assert in a debug expression).
- [x] 3.1.5 [REVIEW] Mental verification: pick a synthetic `StressInputs` where all 5 conditions trigger at hour 22 (everything ramped to 1.0). Raw sum = 5+4+4+3+2 = 18 = cap. No scaling. Pick another where the ramp produces 19 (impossible given the cap formula, but exercise the scaling branch mentally with mock numbers).
  - Verify: Implementation is mathematically equivalent to `engagementPenalty` for the aggregate.

### 3.2 — Build gate (Phase 3)

- [x] 3.2.1 Build main app.
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`.

---

## Phase 4: ViewModel — Cache, Persistence, Emit Helper (Plan §17.4, §11.1)

> NOTE: Phase 4 introduces all the *infrastructure* on `StressViewModel`. Phase 5 then refactors signatures and threads `reason:` through every call site. Building between these is expected to surface intentional churn — the gate after Phase 5 (5.5) is the real verifier.

### 4.1 — Add cache + published trigger

- [x] 4.1.1 In `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`, find the `// MARK: - Apply v3 Result` section (around line 443). Above the existing `applyResult` declaration, insert a new `// MARK: - Change Log Support` section.
  - Verify: Section comment is in the file.
- [x] 4.1.2 Add private storage:
  ```swift
  private var lastResult: StressScoring.StressResult?
  private var lastInputs: StressScoring.StressInputs?
  @Published private(set) var lastChangeEmittedAt: Date = .distantPast
  private let lastResultDefaultsKey = "wp.stress.lastResultEnvelope.v1"
  ```
  - Verify: 4 declarations compile in isolation; `lastChangeEmittedAt` is `@Published` so views can observe via `.onChange`.

### 4.2 — Persistence helpers

- [x] 4.2.1 Add `private func loadPersistedLastResult() -> StressLastResultEnvelope?` per plan §11.1:
  ```swift
  guard let data = UserDefaults.standard.data(forKey: lastResultDefaultsKey),
        let env = try? JSONDecoder().decode(StressLastResultEnvelope.self, from: data)
  else { return nil }
  return env
  ```
  - Verify: Returns `nil` on decode failure.
- [x] 4.2.2 Add `private func persistLastResult(_ result: StressScoring.StressResult)` per plan §11.1:
  ```swift
  let env = StressLastResultEnvelope(
      version: StressLastResultEnvelope.currentVersion,
      capturedAt: Date(),
      result: result
  )
  guard let data = try? JSONEncoder().encode(env) else { return }
  UserDefaults.standard.set(data, forKey: lastResultDefaultsKey)
  ```
  - Verify: Silent failure on encode error (intentional — non-critical telemetry).

### 4.3 — `emitChangeEntries(prevEnvelope:next:reason:)`

- [x] 4.3.1 Add `private func emitChangeEntries(prevEnvelope: StressLastResultEnvelope?, next: StressScoring.StressResult, reason: StressChangeSource)` per plan §6.2.
  - Verify: Signature matches plan exactly.
- [x] 4.3.2 Implement the guards first (top of function body):
  ```swift
  guard !usesMockData else { return }
  guard isAuthorized else { return }
  let now = Date()
  let group = UUID()
  var sequence = 0
  var rowsToInsert: [StressChangeEntry] = []
  ```
  - Verify: Mock mode short-circuits BEFORE any SwiftData writes (plan §12 "mock mode never writes").
- [x] 4.3.3 Implement the envelope-validity / day-rollover guard per plan §6.2:
  ```swift
  let prev: StressScoring.StressResult? = {
      guard let env = prevEnvelope,
            env.version == StressLastResultEnvelope.currentVersion,
            env.result.factors.count == 13,
            Calendar.current.isDate(env.capturedAt, inSameDayAs: now)
      else { return nil }
      return env.result
  }()
  ```
  - Verify: 4 conditions in the guard match plan §6.4 validation rules (version, count, same-day). Decoder failure is handled upstream by `loadPersistedLastResult` returning `nil`.
- [x] 4.3.4 Implement the `prev == nil` branch (anchor + optional full-delta for manual reasons):
  - Insert an anchor row with sentinel values per plan §5.1.a: `kind: "anchor"`, `subjectKey: "anchor"`, `subjectIcon: "circle.dashed"`, `deltaPoints: 0`, `prevValue: totalBefore`, `nextValue: totalAfter`, `sequence: 0`, `detailText: "Day started"` (if `prevEnvelope != nil` — day rollover) or `"First reading"` (if `prevEnvelope == nil` — first install).
  - `totalBefore = prevEnvelope?.result.score ?? 0`.
  - If `reason.isAuto == false` (manual user action across rollover, plan §L3): synthesize a zero-prev and run the full-delta diff path against it, with engagement-gap rows suppressed (plan §L4) — emit a single `engagementActivated` row if `next.engagementPenalty > 0`.
  - After inserting, call `rowsToInsert.forEach { modelContext.insert($0) }; try? modelContext.save(); lastChangeEmittedAt = now` and `return`.
  - Verify: The anchor row is always emitted first in its group (sequence 0). Manual-action carve-out preserves attribution per plan §L3.
- [x] 4.3.5 Implement per-factor diff loop per plan §6.2:
  ```swift
  for (idx, n) in next.factors.enumerated() {
      let p = prev!.factors[idx]
      let delta = n.points - p.points
      if abs(delta) < 0.01 { continue }
      // build row with subjectKey/icon/title via factorTitle(idx), factorIcon(idx)
      // (these helpers may need to be added — see 4.3.5.a)
      rowsToInsert.append(StressChangeEntry(
          timestamp: now, groupID: group, sequence: sequence,
          kind: ChangeEntryKind.factor.rawValue,
          subjectKey: factorKey(idx), subjectIcon: factorIcon(idx),
          deltaPoints: delta, prevValue: p.points, nextValue: n.points,
          totalBefore: prev!.score, totalAfter: next.score,
          sourceRaw: reason.rawValue, detailText: factorDetailText(idx, delta: delta, reason: reason)
      ))
      sequence += 1
  }
  ```
  - Verify: Threshold is `0.01` (per §6.3 table).
- [x] 4.3.5.a If helpers `factorKey(idx)`, `factorIcon(idx)`, `factorDetailText(...)` don't already exist, add private helpers that map the 13 factor indices to stable keys/icons/labels. The existing `applyResult` in `StressViewModel.swift:453+` already maps indices to `StressFactorResult` titles/icons — reuse that mapping (same order as `StressScoring.allFactors`).
  - Verify: Grep `applyResult` body for the existing factor-mapping code and reuse the same titles/icons. Do not invent a new ordering.
- [x] 4.3.6 Implement engagement penalty decomposition per plan §6.2:
  - Detect activation transition: `if prev!.engagementPenalty == 0 && next.engagementPenalty > 0` → emit a single `engagementActivated` row (kind `"engagementActivated"`, subjectKey `"engagement"`, suitable icon, delta = `next.engagementPenalty`) and skip gap rows.
  - Else: call `StressScoring.engagementBreakdown(inputs: prevInputsCache, now: now)` and same for `nextInputsCache`, take the union of keys, diff each key's value, and emit one `engagementGap` row per key with `abs(delta) ≥ 0.5` (plan §6.3 — **threshold raised from 0.01 to 0.5**).
  - **`prevInputsCache` source**: store the `StressInputs` used in the previous `applyResult` invocation as `self.lastInputs` (declared in 4.1.2) and read it here. `nextInputsCache` is the `inputs` value just produced by the caller — needs to be threaded into `emitChangeEntries` OR cached on `self` before the call. Choose: cache on `self` (set `self.nextInputsForDiff = inputs` immediately before calling `emitChangeEntries` from `applyResult`, then read it here). Update `applyResult` accordingly in Phase 5.
  - Per-key metadata: provide a small mapping function `engagementMeta(key:) -> (icon: String, detailText: String, subjectKey: String)` per plan §7 (e.g. `no_mood` → icon `face.smiling`, label "Mood gap closed" when delta < 0, "Mood gap opened" when delta > 0).
  - Verify: Threshold 0.5 (not 0.01). Activation transition uses L4 logic.
- [x] 4.3.7 Implement pattern penalty single-line emission per plan §6.2:
  ```swift
  let patternDelta = next.patternPenalty - prev!.patternPenalty
  if abs(patternDelta) >= 0.01 {
      // emit one row, kind = patternPenalty, subjectKey = "pattern", icon = e.g. "waveform.path.ecg"
      // detailText = "Pattern penalty changed"
  }
  ```
  - Verify: Threshold 0.01 (per §6.3 table).
- [x] 4.3.8 Implement calibrator-isolated impact per plan §6.2 / §6.3:
  ```swift
  let multiplierMoved = abs(next.calibrator - prev!.calibrator) > 0.001
  let calibOnlyImpact = next.raw * (next.calibrator - prev!.calibrator)   // SIGNED — preserves direction
  if multiplierMoved && abs(calibOnlyImpact) >= 1.0 {
      // emit calibrator row with deltaPoints = calibOnlyImpact (signed, NOT abs)
  }
  ```
  - Verify: The row's `deltaPoints` field is the **signed** value, NOT `abs(...)`. Threshold gate uses `abs(...) >= 1.0`. This is the C1 resolution — the formula `next.raw * (next.calibrator - prev.calibrator)` isolates the calibrator-only impact (plan §6.3).
- [x] 4.3.9 Tail of function:
  ```swift
  if !rowsToInsert.isEmpty {
      rowsToInsert.forEach { modelContext.insert($0) }
      try? modelContext.save()
      lastChangeEmittedAt = now
  }
  ```
  - Verify: `lastChangeEmittedAt` is only updated on actual insert (not on a no-op recompute).

### 4.4 — Purge helper

- [x] 4.4.1 Add `private func purgeOldChangeEntries()` per plan §11.1:
  ```swift
  let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
  let descriptor = FetchDescriptor<StressChangeEntry>(
      predicate: #Predicate { $0.timestamp < cutoff }
  )
  if let stale = try? modelContext.fetch(descriptor) {
      stale.forEach { modelContext.delete($0) }
      try? modelContext.save()
  }
  ```
  - Verify: 30-day cutoff; uses `#Predicate`. If `#Predicate` fails to compile on iOS 26.1 (plan §M3), swap to fetch-all-then-Swift-filter — at retention scale this is fine.
- [x] 4.4.2 In `StressViewModel.init`, AFTER the existing `tickerCancellable = ...` block (around line 187), add the once-per-day guard per plan §11.3:
  ```swift
  let purgeKey = "wp.stress.changeLog.lastPurgeDay"
  let today = Calendar.current.startOfDay(for: Date())
  let lastPurge = UserDefaults.standard.object(forKey: purgeKey) as? Date
  if lastPurge.map({ !Calendar.current.isDate($0, inSameDayAs: today) }) ?? true {
      purgeOldChangeEntries()
      UserDefaults.standard.set(today, forKey: purgeKey)
  }
  ```
  - Verify: Purge is called from `init`, NOT from `loadData`. The UserDefaults guard ensures at most once per day.

### 4.5 — Mock-mode accessor

- [x] 4.5.1 Add a computed property on `StressViewModel`:
  ```swift
  var mockChangeEntries: [MockChangeEntry] {
      guard usesMockData, let snap = mockSnapshot else { return [] }
      return snap.changeEntries
  }
  ```
  - Verify: Refers to `snap.changeEntries` — that field is added to `StressMockSnapshot` in Phase 9. Until then this will fail to compile; if Phase 4 needs to build standalone, comment-out this property and uncomment it in Phase 9. Alternatively, declare `var changeEntries: [MockChangeEntry] = []` on `StressMockSnapshot` proactively in 4.5.2 below to keep the build green.
- [x] 4.5.2 Pre-add the empty `changeEntries` field on `StressMockSnapshot` to keep the build green:
  - Edit `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`. Add `var changeEntries: [MockChangeEntry] = []` to the struct (the actual fixture data is added in Phase 9).
  - Verify: Field exists; default is empty array; `// MARK: keep in sync with StressChangeEntry` comment is included.

> Build gate is intentionally deferred to step 5.5 because Phase 5 will mutate `applyResult`/`recompute`/`loadData` signatures — building between Phase 4 and Phase 5 would surface intentional churn. If you want intermediate confidence, you may build now and accept compile errors only related to "missing argument for parameter 'reason:'" — those are expected and will resolve in Phase 5.

---

## Phase 5: Signature Refactor + Reason Threading (Plan §17.5, §8.1, §8.2)

### 5.1 — Update `applyResult` signature

- [x] 5.1.1 In `StressViewModel.swift`, change `private func applyResult(_ result: StressScoring.StressResult)` (line 447) to `private func applyResult(_ result: StressScoring.StressResult, reason: StressChangeSource)`.
  - Verify: Signature matches plan §8.2.
- [x] 5.1.2 At the top of the new `applyResult` body, BEFORE existing publish code, insert per plan §11.2:
  ```swift
  let prevEnvelope = loadPersistedLastResult()
  emitChangeEntries(prevEnvelope: prevEnvelope, next: result, reason: reason)
  lastResult = result
  persistLastResult(result)
  ```
  - Verify: Diff/persist hooks run BEFORE the existing `totalScore = result.score` etc.
- [x] 5.1.3 Ensure `lastInputs` and `nextInputsForDiff` are correctly populated to feed `emitChangeEntries`. Simplest: just before each `applyResult(result, reason: ...)` call in `recompute` and `loadData`, set `self.lastInputs = inputs` AFTER the call (so the next call sees the previous value as "prev"). Pass `inputs` into `applyResult` via an additional parameter `inputs: StressScoring.StressInputs` — update signature to `applyResult(_ result: StressScoring.StressResult, inputs: StressScoring.StressInputs, reason: StressChangeSource)`.
  - Adjust 5.1.1's signature to `applyResult(_ result: StressScoring.StressResult, inputs: StressScoring.StressInputs, reason: StressChangeSource)`.
  - Inside `applyResult`, after `emitChangeEntries(...)`, set `self.lastInputs = inputs`.
  - Inside `emitChangeEntries`, read `self.lastInputs` for the "prev" engagement breakdown and use the incoming `inputs` (also stashed on `self.nextInputsForDiff` or passed via a third parameter) for the "next" breakdown.
  - Decision: pass `nextInputs` as an additional `emitChangeEntries` parameter rather than stashing on self, to avoid mid-method mutation:
    - Change `emitChangeEntries` signature to `emitChangeEntries(prevEnvelope: ..., next: ..., nextInputs: StressScoring.StressInputs, reason: ...)` and pass `inputs` from `applyResult`.
  - Verify: `lastInputs` is the PREVIOUS call's inputs at the time `emitChangeEntries` runs. The current call's inputs flow in via the `nextInputs:` parameter.

### 5.2 — Update `recompute` signature and callers

- [x] 5.2.1 In `StressViewModel.swift:327`, change `func recompute()` to `func recompute(reason: StressChangeSource)` — **NO default value** per plan §8.2.
  - Verify: Every existing caller will now fail to compile until updated — that's the point (compile-time discipline, plan §C3).
- [x] 5.2.2 Inside `recompute`, change `applyResult(result)` to `applyResult(result, inputs: inputs, reason: reason)`.
  - Verify: `inputs` is in scope at that point.
- [x] 5.2.3 In `StressViewModel.swift:185-187`, update the ticker sink callback to `self?.recompute(reason: .autoEngagementTick)` per plan §8.1 row 1.
  - Verify: `.autoEngagementTick` is the case for the 5-min `StressTimerService.tickerPulse` (plan §C2 resolution).
- [x] 5.2.4 In `StressViewModel.swift:192-196` (`bindManualInputUpdates`), update the sink to `self?.recompute(reason: .manualOther)` per plan §8.1 row 2.
  - Verify: Manual user input from `DailyPromptCoordinator` pipe gets `.manualOther` as the catch-all.

### 5.3 — Update `loadData` / `requestPermissionAndLoad` signatures and callers

- [x] 5.3.1 In `StressViewModel.swift:220`, change `func loadData() async` to `func loadData(reason: StressChangeSource = .autoAppOpen) async` per plan §8.2.
  - Verify: `.autoAppOpen` is the only default in the entire API (only first-launch is implicit).
- [x] 5.3.2 Inside `loadData`, change `applyResult(result)` (line 312) to `applyResult(result, inputs: inputs, reason: reason)`.
- [x] 5.3.3 Change `requestPermissionAndLoad()` (line 200) to `requestPermissionAndLoad(reason: StressChangeSource = .autoAppOpen) async`. Inside, change `await loadData()` (lines 205, 214) to `await loadData(reason: reason)`.
  - Verify: Propagates caller-supplied reason; default is `.autoAppOpen` (plan §6.1, §8.2).

### 5.4 — Update `refreshXXX` signatures and callers

- [x] 5.4.1 `func refreshDietFactor()` (line 339) → `func refreshDietFactor(reason: StressChangeSource = .manualFoodLog)`. Inside, `recompute()` → `recompute(reason: reason)`.
  - Verify: Default `.manualFoodLog` per plan §8.2.
- [x] 5.4.2 `func refreshDietFactorAndLogIfNeeded()` (line 343) → `func refreshDietFactorAndLogIfNeeded(reason: StressChangeSource = .autoOnAppear)`. Inside, `recompute()` → `recompute(reason: reason)`.
  - Verify: Default `.autoOnAppear` per plan §8.2.
- [x] 5.4.3 `func refreshScreenTimeOnly()` (line 348) → `func refreshScreenTimeOnly(reason: StressChangeSource)` — **NO default** per plan §8.2.
  - Inside, `recompute()` → `recompute(reason: reason)`.
  - Verify: Every caller must specify (compile-time discipline).
- [x] 5.4.4 Update `StressView.swift:122-133` (`.task` block) per plan §8.1:
  - `await viewModel.requestPermissionAndLoad()` → `await viewModel.requestPermissionAndLoad(reason: .autoAppOpen)`
  - `viewModel.refreshScreenTimeOnly()` → `viewModel.refreshScreenTimeOnly(reason: .autoOnAppear)`
  - Verify: `.autoAppOpen` for the load; `.autoOnAppear` for the screen-time post-load tick.
- [x] 5.4.5 Update `StressView.swift:134-140` (`.onAppear` block):
  - `viewModel.refreshDietFactorAndLogIfNeeded()` → `viewModel.refreshDietFactorAndLogIfNeeded(reason: .autoOnAppear)`
  - `viewModel.refreshScreenTimeOnly()` → `viewModel.refreshScreenTimeOnly(reason: .autoOnAppear)`
  - Verify: Both calls pass `.autoOnAppear`.
- [x] 5.4.6 Update `StressView.swift:141-144` (`.onReceive(refreshTicker)` block):
  - `viewModel.refreshScreenTimeOnly()` → `viewModel.refreshScreenTimeOnly(reason: .autoTicker)`
  - Verify: 30s ticker tagged `.autoTicker`.
- [x] 5.4.7 Update `StressView.swift:145-148` (`.onChange(of: scenePhase)`):
  - `await viewModel.loadData()` → `await viewModel.loadData(reason: .autoScenePhase)`
  - Verify: Foregrounding tagged `.autoScenePhase`.
- [x] 5.4.8 Update `StressView.swift:197` (mood sheet onSaved):
  - `viewModel.recompute()` → `viewModel.recompute(reason: .manualMood)`
  - Verify: `.manualMood`.
- [x] 5.4.9 Update `StressView.swift:349-353` (`.refreshable` block):
  - `await viewModel.loadData()` → `await viewModel.loadData(reason: .autoRefreshable)`
  - `viewModel.refreshScreenTimeOnly()` → `viewModel.refreshScreenTimeOnly(reason: .autoOnAppear)` (or `.autoRefreshable` — pick `.autoRefreshable` to keep attribution tight to the user gesture)
  - Verify: Both calls tagged.
- [x] 5.4.10 Grep for any remaining un-updated callers across the repo:
  - Grep pattern: `\.recompute\(\)|\.loadData\(\)|\.refreshDietFactor\(\)|\.refreshDietFactorAndLogIfNeeded\(\)|\.refreshScreenTimeOnly\(\)|\.requestPermissionAndLoad\(\)`
  - Verify: ZERO matches. If any remain, update them with the appropriate reason from plan §8.1.

### 5.5 — Build gate (Phases 4 + 5 combined)

- [x] 5.5.1 Build main app.
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`. Common failure: "missing argument for parameter 'reason:'" — locate the call site and add the appropriate reason from plan §8.1 table. If something complains about `nextInputs:` on `emitChangeEntries`, ensure step 5.1.3's signature decision is consistently applied.

---

## Phase 6: Purge Verification (Plan §17.6)

> Phase 4 already added `purgeOldChangeEntries` and wired it into `init` (step 4.4.2). Phase 6's purpose is the explicit `#Predicate` build-verification per plan §M3.

### 6.1 — Verify `#Predicate` compiles

- [x] 6.1.1 Re-check the `purgeOldChangeEntries` body — confirm the `#Predicate { $0.timestamp < cutoff }` macro is in place.
  - Verify: The macro is present in the descriptor (not a fetch-all + Swift filter fallback).
- [x] 6.1.2 Build main app (this is the build that exercises `#Predicate` against `StressChangeEntry` on iOS 26.1).
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`. If the macro fails to expand on iOS 26.1 toolchain (plan §M3), fall back to:
    ```swift
    let descriptor = FetchDescriptor<StressChangeEntry>()
    if let all = try? modelContext.fetch(descriptor) {
        let stale = all.filter { $0.timestamp < cutoff }
        stale.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
    ```
  - At retention scale (~3,000 rows max) this is acceptable.

---

## Phase 7: `StressActivityView` (Plan §17.7, §9)

### 7.1 — Create the view file

- [x] 7.1.1 Create `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Stress/Views/StressActivityView.swift`.
  - Verify: File exists.
- [x] 7.1.2 Declare the struct exactly per plan §9.2:
  ```swift
  struct StressActivityView: View {
      let viewModel: StressViewModel
      let modelContext: ModelContext

      @State private var entries: [any ChangeEntryDisplayable] = []
      @State private var filter: StressChangeFilter = .all

      init(viewModel: StressViewModel, modelContext: ModelContext) {
          self.viewModel = viewModel
          self.modelContext = modelContext
      }
      // body below
  }
  ```
  - Verify: Init signature matches plan §9.2 exactly (H5 resolution — no other init permitted).

### 7.2 — Routing (mock vs live)

- [x] 7.2.1 In `body` or a dedicated `loadEntries()` method, branch on `viewModel.usesMockData`:
  - Mock path: `entries = viewModel.mockChangeEntries.map { $0 as any ChangeEntryDisplayable }`
  - Live path: build `FetchDescriptor<StressChangeEntry>` and run `try? modelContext.fetch(descriptor)`, map to `[any ChangeEntryDisplayable]`.
  - Verify: Mock path NEVER touches `modelContext` (plan §H5 — prevents mock→SwiftData leak).

### 7.3 — Fetch descriptor builder

- [x] 7.3.1 Add `private func makeDescriptor(filter: StressChangeFilter, retentionStart: Date) -> FetchDescriptor<StressChangeEntry>` per plan §9.7:
  ```swift
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
  d.fetchLimit = 500
  return d
  ```
  - Verify: `fetchLimit = 500` (plan §9.7, §9.8 — hard cap, no paging in v1). Sort: timestamp desc, sequence asc (ties broken in emit order).

### 7.4 — Re-fetch triggers

- [x] 7.4.1 Add `.task { loadEntries() }` to the view body.
- [x] 7.4.2 Add `.onChange(of: filter) { _ in loadEntries() }`.
- [x] 7.4.3 Add `.onChange(of: viewModel.lastChangeEmittedAt) { _ in loadEntries() }` — per plan §9.7 H4 resolution.
  - Verify: All 3 triggers wired; no `@Query` used anywhere (plan §H4 — dropped entirely).

### 7.5 — Filter chip row

- [x] 7.5.1 Build a `private var filterChipRow: some View` using a horizontal `ScrollView` with `LazyHStack` per plan §9.3. Render one chip per `StressChangeFilter` case (`.all`, `.auto`, `.logs`, `.mood`, `.symptoms`, `.screenTime`, `.food`, `.calibration`).
  - Each chip: capsule background, selected = filled with theme blue, unselected = stroke.
  - Tap sets `filter = .xxx`; `HapticService.impact(.light)`.
  - Verify: 8 chips; "All" is the default selection; selection state visible.

### 7.6 — Sectioned list (Today / Yesterday / Older)

- [x] 7.6.1 Group `entries` by calendar day relative to "today". Build 3 sections:
  - "TODAY" — entries where `Calendar.current.isDateInToday(timestamp)`
  - "YESTERDAY" — `Calendar.current.isDateInYesterday(timestamp)`
  - "OLDER" — everything else
  - Within each section, render `LazyVStack` of rows in `entries` order (already sorted desc by descriptor).
  - Verify: Sections are hidden if empty (except TODAY shows the empty-state copy per §9.6).

### 7.7 — Row design

- [x] 7.7.1 Build `private func entryRow(_ entry: any ChangeEntryDisplayable) -> some View` per plan §9.4:
  - 32×32 colored circle with `Image(systemName: entry.subjectIcon)`; tint by `entry.entryKind`:
    - `.factor` → blue
    - `.engagementGap` → orange
    - `.patternPenalty` → purple
    - `.calibrator` → teal
    - `.anchor` → gray
    - `.engagementActivated` → orange
  - Title: `entry.detailText` (`.r(.subheadline, .semibold)`)
  - Subtitle: `"\(formattedTime) · \(entry.source.displayLabel)"` (`.r(.caption, .medium)` muted)
  - Trailing delta pill: hidden if `entry.deltaPoints == 0` (anchor rows); otherwise show `"+N"` or `"-N stress"` with arrow up/down. **Sign convention**: `deltaPoints < 0` → green down-arrow (good for user); `deltaPoints > 0` → red up-arrow (bad for user).
  - Tappable only for `kind == .factor` or `kind == .calibrator` per plan §9.4. Engagement/pattern/anchor/engagementActivated rows are non-tappable.
  - Verify: Sign convention is enforced — negative deltas render green (this is a common pit; double-check the conditional).

### 7.8 — Empty state

- [x] 7.8.1 If TODAY section has zero entries, render the empty-state per plan §9.6: "No changes yet today. Your stress score will log changes here as your day unfolds."
  - Verify: Copy matches plan §9.6 exactly.

### 7.9 — Navigation chrome

- [x] 7.9.1 Wrap body in `NavigationStack` with `.navigationTitle("Activity")` and `.navigationBarTitleDisplayMode(.inline)`. Add a leading "Done" toolbar button that dismisses the sheet (use `@Environment(\.dismiss)`).
  - Verify: Title "Activity"; Done button dismisses.

### 7.10 — Build gate (Phase 7)

- [x] 7.10.1 Build main app.
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`. Common failure: `entries: [any ChangeEntryDisplayable]` may need explicit casts when mapping — use `as any ChangeEntryDisplayable` at the call site.

---

## Phase 8: Toolbar Refactor in `StressView` (Plan §17.8, §10)

### 8.1 — Add `showActivity` state

- [x] 8.1.1 In `StressView.swift` near `@State private var showInsights = false`, add `@State private var showActivity = false`.
  - Verify: State is at the same level as other `@State` properties on `StressView`.

### 8.2 — Convert single `ToolbarItem` to `ToolbarItemGroup`

- [x] 8.2.1 In `StressView.swift:108-119`, replace the `ToolbarItem(placement: .topBarTrailing) { ... }` block with `ToolbarItemGroup(placement: .topBarTrailing) { ... }` per plan §10 (matching `WellnessCalendarView.swift:52`).
- [x] 8.2.2 Inside the group, wrap both buttons in the existing `if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized && !viewModel.isLoading` guard (single guard for both buttons).
- [x] 8.2.3 First button (Insights): icon-only `Image(systemName: "chart.bar.xaxis.ascending")` styled `.font(.system(size: 14, weight: .medium))` with `.foregroundStyle(Self.themeBlue)`. Action: `HapticService.impact(.light); showInsights = true`. `.accessibilityLabel("Insights")`.
  - Note: This drops the inline "Insights" `Label` text — the icon now carries semantics. Plan §10 documents this visual change.
- [x] 8.2.4 Second button (Activity): `Image(systemName: "clock.arrow.circlepath")` same styling. Action: `HapticService.impact(.light); showActivity = true`. `.accessibilityLabel("Stress activity")`.
  - Verify: Both buttons share the `if` guard; both styled identically.

### 8.3 — Add the Activity sheet

- [x] 8.3.1 Near the existing `.sheet(isPresented: $showInsights) { insightsSheet }` (around line 150), add:
  ```swift
  .sheet(isPresented: $showActivity) {
      StressActivityView(viewModel: viewModel, modelContext: modelContext)
  }
  ```
- [x] 8.3.2 Ensure `modelContext` is in scope on `StressView` — it likely already is via `@Environment(\.modelContext)`. If not, add `@Environment(\.modelContext) private var modelContext`.
  - Verify: Grep `modelContext` in `StressView.swift` returns at least one existing usage. If zero, add the environment property.

### 8.4 — Build gate (Phase 8)

- [x] 8.4.1 Build main app.
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`.

---

## Phase 9: Mock Fixtures (Plan §17.9, §12)

### 9.1 — Hand-craft ~12 fixture entries

- [x] 9.1.1 In `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`, populate `var changeEntries: [MockChangeEntry] = [...]` on `StressMockSnapshot.default` (or wherever the default snapshot is built) with ~12 entries spanning today + yesterday per plan §12.
  - Mix the kinds: include at least 1 anchor, 4–5 factor rows, 2 engagementGap rows, 1 patternPenalty, 1 calibrator, 1 engagementActivated.
  - Mix the sources: at least one of each: `.autoAppOpen`, `.autoTicker`, `.manualMood`, `.manualFoodLog`, `.manualScreenTime`, `.autoScenePhase`.
  - Use realistic deltaPoints (e.g. -2.5 for a logged-mood, +1.2 for a screen-time bump, +3.1 for a calibrator drift).
  - Timestamps: spread across today (e.g. 8 AM, 11 AM, 1 PM, 3 PM, 5 PM, 7 PM) and yesterday (3–4 entries).
  - All anchor rows: `deltaPoints: 0`, `subjectKey: "anchor"`, `subjectIcon: "circle.dashed"`, `detailText: "Day started"` or `"First reading"`.
  - Verify: Array literal compiles; entries look distinguishable in a preview.
- [x] 9.1.2 [REVIEW] Visually inspect the fixture array: do the entries tell a plausible "day in the life" narrative? Are the deltas signed correctly (negative = improvement)?
  - Verify: A non-engineer could read the `detailText` field of each entry and understand what happened.

### 9.2 — Build gate (Phase 9)

- [x] 9.2.1 Build main app.
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`.

---

## Phase 10: Final Verification (Plan §17.10, §13.1)

### 10.1 — Final build on both schemes

- [x] 10.1.1 Clean build the main app:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`.
- [x] 10.1.2 Build the widget extension (plan §13.1 — explicit verification that widget does not break, even though it doesn't open SwiftData):
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: `** BUILD SUCCEEDED **`. Per plan §H3 / §13.1: widget consumes App Group `UserDefaults` only, so it should be entirely unaffected — this is a smoke test for unrelated breakage.
- [x] 10.1.3 [REVIEW] Optional — also build the two ScreenTime extensions to ensure no transitive breakage (CLAUDE.md lists all 4 targets):
  - `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - Verify: Both succeed. (Plan §15 confirms these don't use SwiftData, so they should be unaffected.)

### 10.2 — Signing/entitlements check

- [x] 10.2.1 Confirm no diff in signing fields or entitlements:
  - Run: `git diff --stat WellPlate.xcodeproj/project.pbxproj` — should show no signing-related lines changed.
  - Run: `git diff --name-only -- '*.entitlements'` — should output nothing.
  - Verify: No entitlement files modified; no signing-field deltas in pbxproj. If anything appears, STOP and ask the user (per repo memory `feedback_signing_entitlements.md`).

### 10.3 — Smoke test — cold launch anchor

- [x] 10.3.1 [REVIEW] In Xcode simulator, delete the app to clear UserDefaults (or use a fresh simulator). Launch the app. Open Stress tab. Open Activity sheet.
  - Verify: First-ever launch shows a single anchor row with `detailText == "First reading"` for today; subsequent rows show whatever scoring rendered. No 13 zero-prev rows (plan §14 risk mitigation).

### 10.4 — Smoke test — kill+restart envelope round-trip

- [x] 10.4.1 [REVIEW] After step 10.3, kill the app and re-launch within the same calendar day.
  - Verify: NO new anchor row is emitted (envelope round-trips successfully; capturedAt is same-day). The Activity sheet shows the same rows as before plus any new rows from changes since restart.

### 10.5 — Smoke test — filter chips

- [x] 10.5.1 [REVIEW] In the Activity sheet, tap each filter chip (`All`, `Auto`, `Logs`, `Mood`, `Symptoms`, `Screen time`, `Food`, `Calibration`).
  - Verify: Each chip filters the list correctly. `All` shows everything; `Auto` shows only `auto*` source rows; `Logs` shows only `manual*` source rows; `Mood` shows only `.manualMood` rows; `Calibration` shows only `kind == .calibrator` rows regardless of source.

### 10.6 — Smoke test — sign convention

- [x] 10.6.1 [REVIEW] In the Activity sheet, verify sign convention visually: rows where `deltaPoints < 0` (good for user) render with a green down-arrow; rows where `deltaPoints > 0` (bad for user) render with a red up-arrow.
  - Verify: Plan §9.4 sign convention is enforced. Negative = good = green. This is a common pit — double-check both colors.

### 10.7 — Smoke test — mock-mode toggle

- [x] 10.7.1 [REVIEW] In DEBUG, toggle `AppConfig.shared.mockMode` (via the debug settings or by editing AppConfig). Re-open Stress tab and Activity sheet.
  - Verify: Mock-mode shows the ~12 fixture entries from `StressMockSnapshot.default`. NO entries from live SwiftData leak in (mock-mode early-returns in `emitChangeEntries`; view reads `viewModel.mockChangeEntries` only).

### 10.8 — Smoke test — `!isAuthorized` button hidden

- [x] 10.8.1 [REVIEW] In a state where `viewModel.isAuthorized == false` (or `viewModel.isLoading == true`), open the Stress tab.
  - Verify: Both toolbar buttons (Insights and Activity) are hidden. The `if` guard in the `ToolbarItemGroup` body governs both buttons.

### 10.9 — Smoke test — midnight rollover anchor

- [x] 10.9.1 [REVIEW] (Optional — hard to reproduce without time-travel) Either (a) wait until the next day and re-open the app while a previous-day envelope is in UserDefaults, or (b) manually edit the `capturedAt` in the persisted envelope to yesterday's date via debugger.
  - Verify: First post-midnight recompute emits an anchor row with `detailText == "Day started"` (NOT `"First reading"` — plan §5.1.a).

### 10.10 — Final cleanup

- [x] 10.10.1 Re-run `git diff --stat` and review the file list.
  - Expected new files: `WellPlate/Models/StressChangeEntry.swift`, `WellPlate/Features + UI/Stress/Views/StressActivityView.swift`.
  - Expected modified files: `WellPlate/App/WellPlateApp.swift`, `WellPlate/Core/Services/StressScoring.swift`, `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`, `WellPlate/Features + UI/Stress/Views/StressView.swift`, `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`.
  - Verify: No unexpected files modified. Specifically: `EngagementGapsCard.swift` is UNTOUCHED (plan §3, §7 carve-out); no `*.entitlements` modified; no `project.pbxproj` signing-field deltas.

---

## Post-Implementation Build Verification

- [x] PI.1 Final clean build on all 4 targets (CLAUDE.md spec):
  - [x] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [x] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [x] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [x] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: All 4 builds report `** BUILD SUCCEEDED **`.

- [x] PI.2 Final visual review of the Activity sheet at the end of an actual usage session (or against mock fixtures).
  - Verify: Sectioning (Today/Yesterday/Older), filter chips, sign convention, anchor-row "Day started" / "First reading" copy, empty state copy all match plan §9.

- [x] PI.3 Git commit (do NOT push — leave for the user to review):
  - Suggested commit message: `feat(stress): change log + Activity sheet (transaction-style score diff)`
  - Run: `git add -A && git commit -m "feat(stress): change log + Activity sheet (transaction-style score diff)"`
  - Verify: Commit succeeded; `git log -1` shows the new commit on top.
