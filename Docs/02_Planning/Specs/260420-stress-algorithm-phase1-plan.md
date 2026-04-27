# Implementation Plan: Stress Algorithm — Phase 1 (Foundation & Quick Wins)

**Date:** 2026-04-20
**Source strategy:** [260420-stress-algorithm-improvements-strategy.md](./260420-stress-algorithm-improvements-strategy.md) §3 "Phase 1"
**Source brainstorm:** [260420-stress-algorithm-improvements-brainstorm.md](../../01_Brainzstorming/260420-stress-algorithm-improvements-brainstorm.md) §3 Tier 0
**Research:** [Stress Algorithm Calibration Research](../../06_Miscellaneous/Stress%20Algorithm%20Calibration%20Research.md) §3b, §4a, §8a
**Status:** Ready for audit
**Scope guardrail:** Phase 1 only. v1 stays the default. No bipolar, no new factors, no physio, no baselines.

---

## 1. Summary

Phase 1 lands six research-backed tweaks to the existing v1 `StressScoring` service (Q1 re-weight, Q2 missing-data plumbing, Q3 7k step target, Q4 deep-sleep 45-min floor, Q5 evening-hours screen-time multiplier *if* timeline data exists, Q6 confidence badge) and adds an `AppConfig.stressAlgorithmV2` feature-flag placeholder for Phase 2. All downstream consumers — widget, AI report, home insight card, `StressReading` history — must keep rendering against the same `totalScore: Double` and `allFactors: [StressFactorResult]` shape they use today. **Exit gate:** a sparse-data user no longer sees a phantom 12.5 for unlogged factors, the 7k-step user tops out the exercise score, a night with <45 min deep sleep is visibly capped, the confidence badge reads Low/Medium/High correctly, and all 4 build targets compile clean with mock mode toggled on and off.

---

## 2. Preconditions (verified in repo read)

- `StressScoring` is pure and stateless — no instance state, no services, no async. All 4 factor functions already have the call-site hook needed (`StressScoring.swift:14, 25, 55, 73`).
- `StressFactorResult.hasValidData` already exists with the correct semantics: `stressContribution` returns 0 when `hasValidData == false` (`StressModels.swift:111–114`).
- `StressFactorResult.neutral(...)` already initializes `hasValidData: false` for the four default published factors (`StressViewModel.swift:25–28`). Phase 1 just needs the builders to stop overriding that with `hasValidData: true` when the inputs are missing.
- `ScreenTimeManager.currentAutoDetectedReading` returns a single daily `rawHours: Double` from a threshold milestone — **no hourly breakdown is exposed today** (`ScreenTimeManager.swift:124–161`). This confirms the Q5 decision path in §4.
- `AppConfig` already uses a UserDefaults-backed DEBUG-togglable pattern for `mockMode` (`AppConfig.swift:29–46`). The v2 flag follows that shape.
- Widget consumes `WidgetStressFactor.score/maxScore/contribution` and the factor list from `viewModel.allFactors` (`WidgetRefreshHelper.swift:9–17`). All 5 widget/profile renderers hard-code the `/25` denominator for visual bars (`SharedWidgetViews.swift:104, 109, 124`; `StressLargeView.swift:130`; `ProfileView.swift:1433, 1435`; `StressFactorCardView.swift:46, 74`). **This is the single largest ripple** — see §6.

---

## 3. Task List (13 tasks)

### Task 1 — Introduce factor weight constants

**File:** `WellPlate/Core/Services/StressScoring.swift` (add a new `Weights` enum at top of `StressScoring` namespace, line ~9)
**Change:**
```swift
enum StressScoring {
    enum Weights {
        static let sleep: Double      = 35
        static let exercise: Double   = 25
        static let diet: Double       = 20
        static let screenTime: Double = 20
        // total = 100
    }
    ...
}
```
**Why:** Strategy §3 Phase 1 Q1 — shift from equal 25/25/25/25 to Sleep 35 / Exercise 25 / Diet 20 / Screen Time 20 per Research §3b (sleep = highest cortisol leverage) and §8a (screen time capped at 20 so it can't single-handedly dominate).
**Verification:** `xcodebuild … -scheme WellPlate build` — no new symbols referenced yet, must compile alone.
**Risk:** Low.

---

### Task 2 — Rewrite `exerciseScore` for 7k target + optional-return semantics

**File:** `WellPlate/Core/Services/StressScoring.swift:11–20`
**Change — old:**
```swift
static func exerciseScore(steps: Double?, energy: Double?) -> Double {
    guard steps != nil || energy != nil else { return 12.5 }
    var scores: [Double] = []
    if let s = steps  { scores.append(25.0 * clamp(s / 10_000.0)) }
    if let e = energy { scores.append(25.0 * clamp(e / 600.0)) }
    return scores.reduce(0, +) / Double(scores.count)
}
```
**Change — new:**
```swift
/// Returns 0–`Weights.exercise`. Returns nil when both inputs are nil (missing data).
static func exerciseScore(steps: Double?, energy: Double?) -> Double? {
    guard steps != nil || energy != nil else { return nil }
    let max = Weights.exercise
    var scores: [Double] = []
    if let s = steps  { scores.append(max * clamp(s / 7_000.0)) }   // Q3: 10k → 7k
    if let e = energy { scores.append(max * clamp(e / 600.0)) }
    return scores.reduce(0, +) / Double(scores.count)
}
```
**Why:** Q2 — eliminate phantom 12.5 on missing data. Q3 — step benefits plateau at 5k–7k per Research §4a (`"Walking 7,000 steps daily reduces the risk of depressive symptoms by 22%"`). Weight cap stays 25 per the new table.
**Verification:** Check call-site in `StressViewModel.swift:234` — must compile after Task 5 updates the caller.
**Risk:** Low.

---

### Task 3 — Rewrite `sleepScore` with deep-sleep 45-min floor + optional-return

**File:** `WellPlate/Core/Services/StressScoring.swift:24–49`
**Change — old signature:** `static func sleepScore(summary: DailySleepSummary?) -> Double` returning 12.5 on nil.
**Change — new signature and body:**
```swift
/// Returns 0–`Weights.sleep`. Returns nil when summary is missing.
/// Encodes research §3b: deep sleep <45 min caps the score regardless of total hours.
static func sleepScore(summary: DailySleepSummary?) -> Double? {
    guard let s = summary else { return nil }
    let max = Weights.sleep
    let h = s.totalHours

    // Duration curve — was anchored to 0…25; re-scale to 0…max (35).
    let durationFraction: Double
    switch h {
    case ..<4:   durationFraction = 0.0
    case 4..<5:  durationFraction = lerp(from: 0.00, to: 0.20, t: (h - 4) / 1)
    case 5..<6:  durationFraction = lerp(from: 0.20, to: 0.48, t: (h - 5) / 1)
    case 6..<7:  durationFraction = lerp(from: 0.48, to: 0.72, t: (h - 6) / 1)
    case 7..<9:  durationFraction = lerp(from: 0.72, to: 0.80, t: (h - 7) / 2)
    case 9..<10: durationFraction = lerp(from: 0.80, to: 0.64, t: (h - 9) / 1)
    default:     durationFraction = 0.56
    }
    var score = max * durationFraction

    // Existing deep-sleep ratio bonus (scaled to new ceiling).
    if h > 0 {
        let deepRatio = s.deepHours / h
        score += clamp(deepRatio / 0.18) * (max * 0.20)   // up to 20% of max as bonus
    }

    // Q4: absolute deep-sleep floor — cap at 70% of max if <45 min even if hours are optimal.
    //     Research §3b: "If deep sleep duration falls below 45 minutes, cortisol clearance is incomplete"
    let deepMinutes = s.deepHours * 60.0
    if deepMinutes < 45 {
        score = Swift.min(score, max * 0.70)
    }

    return Swift.min(max, score)
}
```
**Why:** Q2 (nil on missing), Q4 (45-min floor per Research §3b). Numbers in the duration curve preserve the v1 shape (7–9 h was the peak band earning ~80% of 25 = 20 pts; now earns ~80% of 35 ≈ 28 pts).
**Verification:** Build + open mock mode, confirm a DailySleepSummary with totalHours=8 but deepHours=0.5 (30 min) shows a capped score.
**Risk:** Medium — curve re-scaling is arithmetic, but sleep is the highest-weighted factor, so errors are visible. Hand-check: 7.2h + 2.3h deep (mock default) should yield durationFraction ≈ 0.73, score ≈ 25.5 + bonus up to 7 = ~32.5/35.

---

### Task 4 — Rewrite `dietScore` and `screenTimeScore` for optional-return + new ceilings

**File:** `WellPlate/Core/Services/StressScoring.swift:55–76`
**Change — `dietScore`:**
```swift
/// Returns 0–`Weights.diet`. Returns nil when `hasLogs == false`.
static func dietScore(protein: Double, fiber: Double, fat: Double, carbs: Double, hasLogs: Bool) -> Double? {
    guard hasLogs else { return nil }
    let max = Weights.diet
    // (same netBalance math — scaled to new max)
    let proteinRatio  = clamp(protein / 60.0)
    let fiberRatio    = clamp(fiber / 25.0)
    let balancedScore = proteinRatio * 0.55 + fiberRatio * 0.45
    let fatRatio      = clamp(fat / 65.0)
    let carbRatio     = clamp(carbs / 225.0)
    let excessScore   = fatRatio * 0.45 + carbRatio * 0.55
    let netBalance    = clamp((balancedScore - excessScore * 0.6 + 0.5) / 1.0)
    return max * netBalance
}
```
**Change — `screenTimeScore`:**
```swift
/// Returns 0–`Weights.screenTime`. Returns nil when hours is nil.
/// Q5: when hourly buckets are available, evening hours (≥21:00) weight ×1.5.
///     For now (only daily total is exposed by `ScreenTimeManager`), evening
///     multiplier is a no-op — see plan Task 9 for the Phase 2 handoff.
static func screenTimeScore(hours: Double?, eveningHours: Double? = nil) -> Double? {
    guard let h = hours else { return nil }
    let max = Weights.screenTime
    let effectiveHours: Double
    if let evening = eveningHours, evening > 0 {
        let daytime = Swift.max(0, h - evening)
        effectiveHours = daytime + evening * 1.5
    } else {
        effectiveHours = h
    }
    // Original: h * 2 capped at 25. Re-scaled to new max (20): 2.5 pts/hour, cap at 20 (8h).
    return Swift.min(max, effectiveHours * (max / 8.0))
}
```
**Why:** Q2 — nil on missing (diet) and nil on missing (screen time). Q5 — plumbing for evening ×1.5 per Research §8a (`"Exposure 1–2 hours before bed is the most detrimental"`). The `eveningHours` parameter is **optional and defaulted to nil** so Phase 1 call sites can pass only the daily total without behavioral change.
**Verification:** Build. Mock default (4.5h screen time, no evening breakdown) should now produce `min(20, 4.5 * 2.5) = 11.25` vs old `min(25, 4.5 * 2.0) = 9.0`. Call this out in §4 StressLevel bands check.
**Risk:** Medium — screen-time ceiling change means a sparse user who had 4.5h before now has 11.25 contribution vs 9.0. Total can still land in the same band after Q1 re-weight rebalances the pool.

---

### Task 5 — Update `StressViewModel` factor builders to honor optional scores

**File:** `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:232–253, 549–613, 615–655`
**Change — call sites (`loadData`):**
```swift
// was: let exerciseScore = StressScoring.exerciseScore(steps: steps, energy: energy)
let exerciseScore: Double? = StressScoring.exerciseScore(steps: steps, energy: energy)
exerciseFactor = buildExerciseFactor(score: exerciseScore, steps: steps, energy: energy)

let sleepScore: Double? = StressScoring.sleepScore(summary: sleepSummary)
sleepFactor = buildSleepFactor(score: sleepScore, summary: sleepSummary)
```
And both builder signatures become `score: Double?` with:
```swift
private func buildExerciseFactor(score: Double?, steps: Double?, energy: Double?) -> StressFactorResult {
    let hasData = score != nil
    // ... existing status/detail text ...
    return StressFactorResult(
        title: "Exercise",
        score: score ?? 0,
        maxScore: StressScoring.Weights.exercise,   // was hard-coded 25
        icon: "figure.run",
        statusText: status, detailText: detail,
        higherIsBetter: true,
        hasValidData: hasData
    )
}
```
Same pattern for `buildSleepFactor` (maxScore → `Weights.sleep`), `buildDietFactor` (maxScore → `Weights.diet`, pass `logs.isEmpty ? nil : score`), and `refreshScreenTimeFactor` (maxScore → `Weights.screenTime`, `hasValidData: reading != nil`).
**Why:** Q1 + Q2 consolidated. All 4 factors now report `hasValidData = (score != nil)` and carry their weighted ceiling as `maxScore`.
**Verification:**
- Build passes.
- Log-inspect `loadData()` output for a mock run: `Total stress : NN/100` should still produce a coherent number. With mock defaults (steps=7500, energy=340, sleep 7.2h/2.3h deep, 3 diet logs, 4.5h screen time) expected ranges:
  - Exercise score ≈ `25 * min(1, 7500/7000) = 25` → contribution `0` (higherIsBetter)
  - Sleep score ≈ ~32/35 → contribution ~3
  - Diet score ≈ positive netBalance ~0.55 × 20 = 11 → contribution ~9
  - Screen time ≈ `min(20, 4.5 * 2.5) = 11.25` → contribution 11.25
  - Total ≈ 23/100 → "Good"
**Risk:** Medium — touches the 4 builders and the `totalScore` summation site.

---

### Task 6 — Verify `totalScore` remains a simple sum (no re-normalization needed)

**File:** `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:77–84`
**Change:** *None structurally.* Keep:
```swift
var totalScore: Double {
    exerciseFactor.stressContribution
    + sleepFactor.stressContribution
    + dietFactor.stressContribution
    + screenTimeFactor.stressContribution
}
```
**Why:** Because `stressContribution` already returns 0 when `hasValidData == false` (`StressModels.swift:111–114`), and each factor's `maxScore` now matches its Q1 weight, the sum is automatically a weighted 0–100. **No weight-redistribution logic in Phase 1** — a user with 2 missing factors simply has a smaller maximum possible score, which is exactly what Q2 intends (phantom stress disappears instead of being redistributed). The brainstorm's "honest mode" (show a string instead of a number) is explicitly deferred to Phase 2 per strategy §3 decision points.
**Verification:** Confirm via log: a mock snapshot with an empty `currentDayLogs` array produces `dietFactor.stressContribution == 0`, `totalScore` is ≤ 80 (since diet max 20 is now missing from the pool), and no phantom 12.5 shows anywhere.
**Risk:** Low (verification-only task).

---

### Task 7 — Add `StressConfidence` enum + computed property on ViewModel

**File:** `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` (extend existing file; **no new file**)
**Change — add at bottom of `StressViewModel`:**
```swift
// MARK: - Confidence

enum StressConfidence: String {
    case low, medium, high

    var label: String {
        switch self {
        case .low: "Low confidence"
        case .medium: "Medium confidence"
        case .high: "High confidence"
        }
    }

    var systemImage: String {
        switch self {
        case .low: "gauge.with.dots.needle.0percent"
        case .medium: "gauge.with.dots.needle.50percent"
        case .high: "gauge.with.dots.needle.100percent"
        }
    }
}

var factorCoverage: Int { allFactors.filter(\.hasValidData).count }  // 0…4

var stressConfidence: StressConfidence {
    switch factorCoverage {
    case 4: .high
    case 2, 3: .medium
    default: .low
    }
}
```
**Why:** Q6 / U1 — confidence badge per strategy §3 Phase 1 ("confidence badge shows Low when <3 factors have data, High when 4/4"). Keeping the enum scoped inside the file avoids a new file; justification per strategy §6 "Minimize surface area".
**Verification:** Build. Preview mock (4 factors valid) returns `.high`. Previewing a manually-constructed snapshot with only steps + sleep present returns `.medium`.
**Risk:** Low.

---

### Task 8 — Render confidence badge in `StressView`

**File:** `WellPlate/Features + UI/Stress/Views/StressView.swift:298–312` (score header)
**Change:** Add a badge below `/100` inside `scoreHeader`. Minimal footprint — reuse existing iconography conventions, no new card:
```swift
private var scoreHeader: some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("\(Int(viewModel.totalScore))")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
            Text("/100")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
        }
        confidenceBadge
    }
}

private var confidenceBadge: some View {
    HStack(spacing: 6) {
        Image(systemName: viewModel.stressConfidence.systemImage)
            .font(.system(size: 11, weight: .semibold))
        Text("\(viewModel.stressConfidence.label) · \(viewModel.factorCoverage)/4 factors")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(0.4)
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Capsule().fill(Color(.systemGray6)))
}
```
**Why:** Q6 / U1 / U4 — surfaced on the main stress card as per strategy §3 exit gate.
**Verification:** Mock mode → badge shows "High confidence · 4/4 factors". Break one factor (e.g., clear `currentDayLogs` in a debug snapshot) → badge shows "Medium confidence · 3/4 factors".
**Risk:** Low — cosmetic addition, no layout reflows that affect other cards.

---

### Task 9 — Q5 evening screen-time multiplier: decision + defer note

**Files:** `WellPlate/Core/Services/StressScoring.swift:73` (already parameterized via `eveningHours: Double? = nil` in Task 4), `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:615` (call site).
**Change — call site:**
```swift
// ScreenTimeManager today exposes only a daily total (rawHours), not an hourly timeline.
// Evening multiplier is plumbed in StressScoring (parameter available) but call site
// passes eveningHours: nil until Phase 2 exposes an hourly breakdown.
let score = StressScoring.screenTimeScore(hours: reading.rawHours, eveningHours: nil)
```
**Decision:** Q5 is a **partial ship** in Phase 1:
- ✅ Plumb the `eveningHours` parameter in `StressScoring.screenTimeScore` (done in Task 4).
- ❌ Do **not** modify `ScreenTimeManager` to expose hourly buckets. The current `DeviceActivitySchedule` uses threshold events keyed on *accumulated* minutes (`ScreenTimeManager.swift:84–112`), not time-of-day. Extracting "after 21:00" requires re-architecting the monitor with an additional `DeviceActivitySchedule` windowed on 21:00–23:59, writing a second App Group key, and reading both in `currentAutoDetectedReading`. That is a meaningful DeviceActivity change that exceeds Phase 1's 1–2 week budget.
**Why:** Strategy §3 Phase 1 "Decision points to resolve before starting: Q5 feasibility — confirm ScreenTimeManager exposes hourly breakdown; if not, Q5 moves to P2 and P1 keeps 5 items." Verified — it does not. Parameter stub preserves the API for P2 without behavior change now.
**Verification:** Build — Task 4's default parameter keeps every existing caller source-compatible.
**Risk:** Low (by deferral). Follow-up tracked as a P2 pre-requisite bullet in the strategy doc.

---

### Task 10 — Add `AppConfig.stressAlgorithmV2` feature-flag placeholder

**File:** `WellPlate/Core/AppConfig.swift:14–22, 29–46`
**Change — add key:**
```swift
private enum Keys {
    static let mockMode = "app.networking.mockMode"
    // ...existing keys...
    static let stressAlgorithmV2 = "app.stress.algorithmV2"   // NEW
}
```
**Change — add property (model exactly on `mockMode`):**
```swift
/// Feature flag for the Phase 2 bipolar stress scoring service.
/// - DEBUG only. Release builds always return `false` in Phase 1.
/// - Phase 1 reads: nothing (placeholder). Phase 2 StressScoringV2 will gate on this.
var stressAlgorithmV2: Bool {
    get {
        #if DEBUG
        guard UserDefaults.standard.object(forKey: Keys.stressAlgorithmV2) != nil else {
            return false
        }
        return UserDefaults.standard.bool(forKey: Keys.stressAlgorithmV2)
        #else
        return false
        #endif
    }
    set {
        #if DEBUG
        UserDefaults.standard.set(newValue, forKey: Keys.stressAlgorithmV2)
        WPLogger.app.info("Stress Algorithm V2 → \(newValue ? "ENABLED" : "DISABLED")")
        #endif
    }
}
```
Also add to `logCurrentMode()` output:
```swift
"Stress v2  : \(stressAlgorithmV2 ? "ENABLED 🧪" : "disabled")",
```
**Why:** Strategy §3 Phase 1 explicitly lists "Add `AppConfig.stressAlgorithmV2: Bool` flag (default `false`) — just the flag, no v2 code yet."
**Verification:** Build. `AppConfig.shared.stressAlgorithmV2` returns `false` by default, toggleable only in DEBUG. No production code reads it yet.
**Risk:** None. Purely additive.

---

### Task 11 — Update `StressMockSnapshot` to exercise the new missing-data paths

**File:** `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift:49–264`
**Change:** Add a second static factory alongside `.default`:
```swift
/// Sparse-data variant — only sleep + screen time have valid data.
/// Exercises the Q2 missing-data plumbing and Q6 "Medium confidence" badge.
static let sparse: StressMockSnapshot = makeSparse()

private static func makeSparse() -> StressMockSnapshot {
    let base = makeDefault()
    return StressMockSnapshot(
        steps: 0,              // interpreted as "no data" by fetchStepsSafely > 0 filter
        energy: 0,
        sleepSummary: base.sleepSummary,
        screenTimeHours: base.screenTimeHours,
        // ...history fields identical to default...
        currentDayLogs: []     // no food logged → diet factor excluded
    )
}
```
Also **no change** required to `default` — the mock default has 4/4 valid factors and will now render "High confidence" naturally.
**Why:** Strategy §3 Phase 1 affected files list — `StressMockSnapshot.swift` "add sparse-data snapshot variant to exercise the new missing-data paths".
**Verification:** Manual — temporarily swap `StressView` preview to use `.sparse` and confirm:
- Diet factor card is absent or grayed (handled by existing `factor.accentColor` returning `.systemGray3` when `!hasValidData`).
- Exercise factor shows "No data".
- Confidence badge reads "Medium confidence · 2/4 factors".
- `totalScore` is sleep contribution + screen time contribution only (no phantom 12.5 anywhere).
**Risk:** Low.

---

### Task 12 — Ripple audit: confirm `StressLevel` bands still work

**File:** `WellPlate/Models/StressModels.swift:19–26`
**Change:** Decision — **keep existing bands** for Phase 1.
```swift
init(score: Double) {
    switch score {
    case ..<21:   self = .excellent
    case 21..<41: self = .good
    case 41..<61: self = .moderate
    case 61..<81: self = .high
    default:      self = .veryHigh
    }
}
```
**Why:** The §4 StressLevel bands math (below) confirms the worst-case single-factor extremum (full sleep deficit at 35) lands in `.good`/`.moderate` per the old thresholds. Hitting `.veryHigh` (≥81) still requires stress across multiple factors, which matches v1 intent. The brainstorm's proposed "Balanced" 41–55 band is explicitly a Phase 2 Tier 1 (`B3`) change and is out of scope per the "Hard constraints" section.
**Verification:** See §4 math below — no case where a realistic all-factor-max input breaks the level semantics.
**Risk:** Low.

---

### Task 13 — Build + smoke-test all 4 targets

**Commands:**
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate            -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor    -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport     -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target  WellPlateWidget     -destination 'generic/platform=iOS Simulator' build
```
**Manual smoke checklist:**
1. Launch app in simulator → Home tab renders `StressInsightCard` with a string level (Excellent/Good/etc.) and no crash.
2. Stress tab → hero "NN/100" number renders; confidence badge shows "High confidence · 4/4 factors" in mock mode default.
3. Toggle `AppConfig.stressAlgorithmV2` in a DEBUG menu if present — no-op but log-emits.
4. Long-press widget on home screen → Stress widget renders with 4 factor bars; contribution numbers still show "X/25" text but visual bars scale to each factor's `maxScore`.
5. Open AI report sheet → Stress deep-dive section renders with the day's stress score. No crash.
6. Toggle mock mode off, allow HealthKit permission → `totalScore` computes without NaN.
**Risk:** Medium — the widget and the profile mini-bars still hard-code `/25.0` in their text/ratio calculations. See §6 ripple audit for the specific mitigation.

---

## 4. StressLevel Bands Math (verification)

**Factor ceilings after Q1 re-weight:**
| Factor | Max contribution | Notes |
|---|---|---|
| Sleep | 35 | `higherIsBetter=true` — max stress contribution = 35 (zero sleep) |
| Exercise | 25 | max stress contribution = 25 (zero activity) |
| Diet | 20 | max stress contribution = 20 (no logs → `hasValidData=false` → 0; very poor logs → up to 20) |
| Screen Time | 20 | `higherIsBetter=false` — max contribution = 20 (≥8h screen time) |
| **Total** | **100** | |

**Worst-case stress profile (all 4 factors present, all maxing out):** 35 + 25 + 20 + 20 = 100 → `.veryHigh` ✅
**Strategy exit-gate question — "could a max-screen-time-only user still hit Very High?"** No. With only screen time reporting (other 3 `hasValidData=false` → 0), the maximum possible `totalScore` is 20 → `.excellent`. **This is the intended Q2 behavior** — a user who only logs screen time has low *confidence* and a low *number*; the confidence badge (Task 8) is the UX signal that tells them why.

**Realistic mock scenarios (verified against §2 preconditions):**
| Scenario | Expected total | Expected level |
|---|---|---|
| Mock `default` (7500 steps, 7.2h/2.3h deep, balanced diet, 4.5h screen) | ~23/100 | Good |
| Mock `sparse` (only sleep 7.2h/2.3h deep and 4.5h screen) | ~14/100 | Excellent |
| Synthetic all-max stress (0 steps, <4h sleep, worst diet, 10h screen) | ~95/100 | Very High |

**Decision:** No band threshold changes for Phase 1. The existing `..<21 / 21..<41 / 41..<61 / 61..<81 / 81+` cutoffs remain semantically correct.

---

## 5. Ripple Audit (consumer-by-consumer)

### 5a. `WellPlateWidget` target (`WellPlateWidget/Views/SharedWidgetViews.swift`, `StressWidget.swift`, `StressLargeView.swift`)
- **Reads:** `WidgetStressData.totalScore: Double` (0–100) and `WidgetStressFactor.{score, maxScore, contribution, hasValidData}`. Populated by `WidgetRefreshHelper.refreshStress` which maps `factor.maxScore` straight from `StressFactorResult.maxScore`.
- **Does it break?** *Mostly no, but cosmetic regression.* After Task 5 the serialized `maxScore` field is now 35/25/20/20 instead of uniformly 25. `WidgetRefreshHelper.swift:14` already forwards `factor.maxScore` correctly. **But:** `SharedWidgetViews.swift:104, 109, 124` hard-codes `/25.0` for bar fractions and the `"N/25"` label; same in `ProfileView.swift:1433, 1435, 1445`.
- **Change required:** Replace `factor.contribution / 25.0` with `factor.contribution / factor.maxScore` (guarded by the existing `guard factor.maxScore > 0` at line 103). Replace the `"\(Int(factor.contribution))/25"` text with `"\(Int(factor.contribution))/\(Int(factor.maxScore))"` in 3 sites (`SharedWidgetViews.swift:124`, `ProfileView.swift:1445`, `StressFactorCardView.swift:46`). **This is a required Phase 1 change**, bundled as part of Task 5 verification — flag as a blocker if missed.
- **Scope creep check:** Yes — this adds one more file (`SharedWidgetViews.swift`) to the hard-constraint list. Justified: without it the widget shows `"35/25"` for a sleep-deficient user, which is visibly wrong. Total 3-file cosmetic sweep; no new logic.

### 5b. AI Report — `ReportDataBuilder.swift:224`, `ReportNarrativeGenerator.swift:111–149`, `StressDeepDiveSection.swift`
- **Reads:** `day.stressScore: Double?` (the persisted `StressReading.score`). No factor-level reads, no `maxScore` reads.
- **Does it break?** No. The scalar shape is unchanged. New scores logged post-Phase-1 will use the new weighting; historical `StressReading` rows stay on v1 numbers (strategy §4 explicitly rejects backfill). Narrative statements like "Your average stress was 42" remain valid.
- **Change required:** None. Note for audit: scatter pairs in `ReportDataBuilder.swift:448–462` and `InsightEngine.swift:413–418` use stress as the Y axis — also fine since the 0–100 range is preserved.

### 5c. Home Insights — `InsightEngine.swift`, `StressInsightCard.swift`
- **Reads:** `InsightEngine` extracts `d.stressScore` (scalar) and runs correlations/streaks — no factor-max reads. `StressInsightCard` takes a `stressLevel: String` and a `tip: String` (`StressInsightCard.swift:8–10`).
- **Does it break?** No. Both consume post-mapping outputs (label string, scalar score).
- **Change required:** None.

### 5d. `StressReading` persistence (`StressViewModel.swift:372–406`)
- **Reads:** Persists `totalScore` and `stressLevel.label`.
- **Does it break?** No. Same API, just produces new numbers. Old rows are read-only history — accepted per strategy §4.
- **Change required:** None.

### 5e. `WellnessDayLog` sync (`StressViewModel.swift:440–478`)
- **Reads:** Writes `stressLevel.label` to `WellnessDayLog.stressLevel`. Used by HomeView rings.
- **Does it break?** No. Label strings unchanged.
- **Change required:** None.

### 5f. Mock mode (`StressMockSnapshot`)
- **Does it break?** No — the default snapshot continues to exercise 4/4 factors. Task 11 adds a new `.sparse` variant for testing Q2.
- **Change required:** Task 11 above.

### 5g. `StressLab` and `Interventions` sheets
- **Reads:** `StressViewModel` directly; same API surface (`totalScore`, `allFactors`, `stressLevel`).
- **Does it break?** No.

### Summary ripple table

| Consumer | Behavior change? | File edit required? | Where |
|---|---|---|---|
| `StressView` main score | Yes (new score values) | Yes — Task 8 (badge) | `StressView.swift` |
| `StressFactorCardView` | Text label `N/25` wrong for sleep | Yes | `StressFactorCardView.swift:46` |
| Widget small/medium/large | Bar fractions + `N/25` text wrong | Yes | `SharedWidgetViews.swift:104, 109, 124`; `StressLargeView.swift` |
| ProfileView mini-bars | Same as widget | Yes | `ProfileView.swift:1433, 1435, 1445` |
| `StressReading` rows | New values flow in | No | — |
| AI report | Scalar pass-through | No | — |
| `InsightEngine` correlations | Scalar pass-through | No | — |
| `StressInsightCard` (home) | Label pass-through | No | — |
| `WellnessDayLog.stressLevel` | Label pass-through | No | — |

**Net surface area:** Core change = 3 files (`StressScoring`, `StressModels`, `StressViewModel`). UI = 2 files (`StressView`, `StressFactorCardView`). Widget/Profile cosmetic = 3 files (`SharedWidgetViews`, `StressLargeView`, `ProfileView`). Config/mock = 2 files (`AppConfig`, `StressMockSnapshot`). **Total: 10 files, 0 new files created.**

---

## 6. Feature Flag

**Location:** `WellPlate/Core/AppConfig.swift`
**Key:** `Keys.stressAlgorithmV2 = "app.stress.algorithmV2"` (UserDefaults, DEBUG-togglable, release returns `false` unconditionally — mirrors `mockMode` at `AppConfig.swift:29–46`).
**Default:** `false` (Phase 1 and Phase 2 both default off per strategy §2 phase map; strategy flips default to `true` in Phase 3).
**What reads it in Phase 1:** *Nothing.* The flag is a placeholder exposed in `AppConfig.logCurrentMode()` output for dev visibility only.
**Intent for Phase 2:** `StressViewModel` will inject an abstract scorer whose selection is gated on `AppConfig.shared.stressAlgorithmV2`. Phase 2 also adds the shadow-log storage — not now.

---

## 7. Exit Criteria (Phase 1 is done when…)

- [ ] `StressScoring.swift` 4 factor functions all return `Double?`, all use `StressScoring.Weights.*` for their ceilings, and all encode the new thresholds (7k steps, 45-min deep-sleep floor).
- [ ] `StressViewModel.allFactors` reports `hasValidData = false` for any factor whose source data is missing; `totalScore` never includes a phantom 12.5.
- [ ] `StressView` score header renders a confidence badge showing `{Low/Medium/High} confidence · N/4 factors` sourced from the new `stressConfidence` computed property.
- [ ] `AppConfig.stressAlgorithmV2` exists, defaults to `false`, is DEBUG-togglable, and prints in `logCurrentMode()`.
- [ ] `StressMockSnapshot` has a `.sparse` variant alongside `.default`; both render without crashes.
- [ ] All 4 build targets compile clean (commands in Task 13).
- [ ] Widget and Profile mini-bars compute bar fractions and "X/Y" labels against `factor.maxScore` (not hard-coded 25).
- [ ] `StressInsightCard` on Home renders an appropriate label for a new-weighting score.
- [ ] `StressDeepDiveSection` in AI report renders without crash; scores persisted to `StressReading` post-Phase-1 use the new weighting (documented in the audit notes — not backfilled).
- [ ] Mock mode parity: toggling mock on/off and kicking the ViewModel into `loadData()` produces no NaN, no infinite values, no `totalScore > 100`.
- [ ] `CLAUDE.md` architecture conventions preserved — `StressScoring` stays pure + stateless; `@MainActor final class StressViewModel` unchanged; font/shadow tokens untouched.

---

## 8. Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Users with long-standing v1 scores see their number jump the first day after Phase 1 ships | High | Medium (trust signal) | Strategy §4 already accepted: "do not backfill historical rows". Ship the confidence badge as the soft explainer. A one-time "Your stress score got smarter" tombstone is a Phase 2 nicety — tracked, not required for P1. |
| Widget and Profile still show `/25` labels until the Task 5 cosmetic sweep lands, causing 35/25 rendering for high-sleep-deficit users | Medium | Medium (visible bug) | §5a explicitly calls out the 3-file sweep; make it a blocking sub-checklist in implementation phase. |
| Deep-sleep floor (Q4) caps the score for healthy users who happen to have a single bad deep-sleep night | Low | Low | Cap is 70% of sleep-max (≈24.5/35), not 0 — a user with 8h total but only 30 min deep still scores well. Cap only prevents "healthy total masks cortisol incompletion". |
| Screen-time re-scaling to /20 + 2.5 pts/hour produces a *higher* contribution than v1 for light users (4.5h becomes 11.25 vs 9.0) | Medium | Low | Offset by the fact that sleep and exercise are now the dominant weights; realistic users get a lower total overall. Verified in §4 mock scenario table. |
| `ScreenTimeManager` hourly exposure is non-trivial; deferring Q5 means the evening multiplier is code-only-no-op | Low | Low | Parameter stub in `screenTimeScore(hours:eveningHours:)` preserves the Phase 2 API. Strategy §3 pre-authorized this deferral. |
| The `Double?` return change across 4 scoring functions cascades more call sites than expected (InsightService, tests) | Low | Medium | Repo scan confirmed the only call site is `StressViewModel.loadData`/`refreshDietFactor`/`refreshScreenTimeFactor` and that `StressInsightService` (if it exists) was referenced in the `StressScoring.swift` header comment but does not appear in the current codebase grep — safe. Audit step during implementation. |
| Sleep-curve re-scaling arithmetic error makes the highest-weighted factor produce slightly off values vs mental model | Medium | Medium | Hand-verification table in Task 3 (7.2h + 2.3h deep → ~32.5/35) lands in the implementation checklist as a manual log-inspection step. |

---

## 9. Open Questions (Phase-1-blocking only)

1. **Should the confidence badge also appear on the widget?** Defer. Strategy §4 widget compatibility says "`WidgetStressData.factors: [WidgetStressFactor]` shape stable through P4". Adding a `confidence: String` field is additive and cheap, but not in Phase 1 scope. Explicit defer: P4 `U4` calibrating state supersedes this.
2. **Minimum-coverage "honest mode"** (brainstorm Open Q7: show "Log more to see your stress score" when <2 factors valid) — strategy §4 says "default the honest-mode threshold to <2 factors". This plan **does not implement honest mode in Phase 1**. Reason: decoupling the mock-default rendering path from an extra branch keeps the verification surface small. Flag as a Phase 2 pickup that also covers "≥3 factors across ≥2 tiers" threshold proposed in the 260410 brainstorm.

Everything else from the brainstorm's Open Questions list (Q1–Q6) is a Phase 2+ concern per strategy §3 and is intentionally out of scope.

---

## 10. File Touch Summary

| File | Change type | Tasks |
|---|---|---|
| `WellPlate/Core/Services/StressScoring.swift` | Modify — rewrite 4 factor fns, add `Weights` enum | 1, 2, 3, 4 |
| `WellPlate/Models/StressModels.swift` | Read-only verification (no change) | 12 |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | Modify — builders accept `Double?`, add `StressConfidence` enum + 2 computed props | 5, 6, 7, 9 |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | Modify — add confidence badge to score header | 8 |
| `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift` | Modify — replace `/25` text with `/maxScore` | 5 (sub) |
| `WellPlate/Core/AppConfig.swift` | Modify — add `stressAlgorithmV2` flag | 10 |
| `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` | Modify — add `.sparse` factory | 11 |
| `WellPlateWidget/Views/SharedWidgetViews.swift` | Modify — bar fraction + `/N` text | 5 (sub) |
| `WellPlateWidget/Views/StressLargeView.swift` | Modify — ensure contribution text uses `maxScore` if it renders one | 5 (sub) |
| `WellPlate/Features + UI/Tab/ProfileView.swift` | Modify — `MiniFactorBar` fraction + `/25` label | 5 (sub) |

**Total:** 10 files modified, 0 new files. Scope matches strategy §6 "Existing Files — Touch Summary" row for Phase 1 plus the three cosmetic-sweep files called out in §5a.

---

**Next step:** Run `/develop audit` against this plan. Then (pending resolution) `/develop checklist` to produce the step-by-step.
