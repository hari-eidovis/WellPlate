# Implementation Plan: Stress Algorithm — Phase 1 (Foundation & Quick Wins) — **RESOLVED**

**Date:** 2026-04-20
**Source strategy:** [260420-stress-algorithm-improvements-strategy.md](./260420-stress-algorithm-improvements-strategy.md) §3 "Phase 1"
**Source brainstorm:** [260420-stress-algorithm-improvements-brainstorm.md](../../01_Brainstorming/260420-stress-algorithm-improvements-brainstorm.md) §3 Tier 0 <!-- RESOLVED: L1 — fixed brainstorm link typo (Brainzstorming → Brainstorming) -->
**Research:** [Stress Algorithm Calibration Research](../../06_Miscellaneous/Stress%20Algorithm%20Calibration%20Research.md) §3b, §4a, §8a
**Audit:** [260420-stress-algorithm-phase1-plan-audit.md](../../03_Audits/260420-stress-algorithm-phase1-plan-audit.md)
**Status:** Resolved — ready for checklist
**Scope guardrail:** Phase 1 only. v1 stays the default. No bipolar, no new factors, no physio, no baselines. Honest mode is the only additive scope vs the original plan (was already in strategy §3 line 76).

---

## 0. Resolution Changelog

Every finding from the audit report is accounted for below. IDs match the audit's numbering exactly.

| ID | Severity | Resolution |
|---|---|---|
| **C1** | 🔴 Critical | **Fixed.** Added new Task 14 (`StressDeepDiveSection` migration) using the less-invasive `?? 0` unwrap at 4 call sites. Updated §5b Ripple Audit, §8 Risks row, and §10 File Touch Summary. Historical-day nil values are coerced to 0 (report renders *averages* of historical days, so nil-days become "no contribution" rather than hiding the entire day). Reasoning: refactoring the tuple shape to `Double?` would cascade into the chart rendering (`factorDecomposition`) and require handling nil in chart axes — the plan's scope discipline argues for the minimal fix. |
| **H1** | 🟠 High | **Fixed.** Restored honest mode as Phase 1. New Task 15 (`StressView` honest-mode placeholder) replaces the hero score with "Log more to see your stress score" when `factorCoverage < 2`. Threshold chosen per strategy §3 line 76 (`<2`), overriding strategy §4 line 236 (`<3`) per user spec. Also skip `StressReading` logging when in honest mode (Task 15 sub-step). Interacts with Task 8 — see §11 "Honest-mode / confidence-badge interaction". |
| **H2** | 🟠 High | **Fixed.** Removed `eveningHours` parameter from `screenTimeScore` entirely in Task 4. Signature is now `screenTimeScore(hours: Double?) -> Double?`. Added a one-line comment pointing to Phase 2 `StressScoringV2`. Task 9 rewritten to be pure deferral documentation, no parameter plumbing. |
| **H3** | 🟠 High | **Fixed.** Added `DietDetailView.swift:82` and `ScreenTimeDetailView.swift:80` to Task 5 cosmetic sweep; also adds StressViewModel DEBUG log lines (6 occurrences), `SharedStressData.swift` comment + placeholder, and `StressModels.swift:78` comment + `StressLevel.preview` factor at line 131 (`maxScore: 25` fixture). Re-grep results listed in §5a. "3-file sweep" → "7-file sweep" (plus the widget SharedStressData placeholder). |
| **H5** | 🟠 High | **Fixed.** Recomputed verification tables from scratch using the new weights + new algorithm. Published math inline in §4 and Task 5. Corrected values: Exercise contribution = 5.42 (was 0), Diet contribution = 0 (was 9), Total = 19.2 / Excellent (was 23 / Good). |
| **H6** | 🟠 High | **Fixed.** Added exit criterion in §7 ("v2-total vs v1-total whipsaw ≤5 pts on default mock") with verified math in §4 (delta = 0.155). Also added as smoke-test step in Task 13. |
| **H7** | 🟠 High | **Fixed.** Removed fabricated quote from Task 10 "Why". Replaced with accurate paraphrase citing strategy §4 "Migration" line 223 (`defaults to false in P1–P2`) as the real provenance for adding the placeholder in P1. |
| **M1** | 🟡 Medium | **Accepted — risk explicitly taken.** Kept 70% cap as engineering choice. Added explicit §8 risk-row note: "Cap severity re-evaluated in Phase 3 alongside age-band lowered thresholds." Age-aware threshold is strategy §3 Phase 3 S3 work. |
| **M2** | 🟡 Medium | **Partially patched.** Honest mode (H1 fix) removes the worst "Low confidence + misleading low score" case entirely — at `<2` factors the number is hidden. For `factorCoverage == 2` (Medium confidence), Task 8 bumps badge font from 11 → 13 and makes it medium-weight. Placement stays below the number (placing it above would disrupt `.scaleEffect(.topLeading)` anchor — L4). |
| **M3** | 🟡 Medium | **Patched with explicit mock path documentation.** Task 11 clarifies: sparse variant constructs `stepsHistory` with the last entry's value = 0, so `fetchStepsSafely`'s `total > 0 ? total : nil` guard returns nil in mock mode, and `currentDayLogs: []` produces `dietFactor.hasValidData = false`. Struct fields stay `Double` (no breaking change). Verified via `MockHealthKitService.swift:27` path. |
| **M4** | 🟡 Medium | **Fixed.** Renamed `StressConfidence` → nested `StressViewModel.Confidence` in Task 7. Prevents collision with Phase 2's `.calibrating` state (strategy §3 P4 U4) in a separate `StressScoringV2`-adjacent namespace. |
| **M5** | 🟡 Medium | **Fixed.** Added `SharedStressData.swift:95` comment update (`// 25` → `// per-factor weight (sleep 35, exercise 25, diet 20, screen 20)`) and placeholder factor `maxScore` values at lines 68–71 to Task 5 cosmetic sweep. |
| **M6** | 🟡 Medium | **No change.** Audit confirmed the `ScreenTimeManager.swift:124-161` citation is correct; audit itself rated this "No change, this is a confirmation, not an issue." |
| **M7** | 🟡 Medium | **Accepted — Phase 2 pickup.** The ~1-week visual whipsaw in widget weekly sparkline / WellnessCalendar is acknowledged as the expected cost of strategy §4's "do not backfill" decision. Adding `StressReading.algorithmVersion` is SwiftData additive but introduces schema migration concerns that deserve their own design pass. Phase 2 task name: *"P2 `StressReading.algorithmVersion` tombstone field"* — to be added to that phase's plan. §5d already acknowledges this; §8 risk table now elaborates. |
| **L1** | ⚪ Low | **Fixed.** See top of doc — brainstorm link fixed. |
| **L2** | ⚪ Low | **Fixed.** §2 rephrased from "call-site hooks" to "pure static declarations ready for in-place signature changes." |
| **L3** | ⚪ Low | **Fixed.** Normalized all `ProfileView.swift` references to `:1433, 1435, 1445` across §2 Preconditions, §5a, and §10. |
| **L4** | ⚪ Low | **Fixed.** Task 8 explicitly notes that `.scaleEffect(anchor: .topLeading)` on the new VStack still scales correctly because the anchor remains at the top-left corner. |
| **L5** | ⚪ Low | **Partially fixed.** Removed the 🧪 emoji per CLAUDE.md "no emojis" guidance; however, existing `logCurrentMode()` output uses ✅/❌ emojis (`AppConfig.swift:151-156`), so the new line uses plain "ENABLED"/"disabled" matching the existing spartan style of the log values. |
| **L6** | ⚪ Low | **Fixed.** H1 fix picks `<2` from strategy §3 line 76 (explicit Phase 1 decision point) over `<3` from strategy §4 line 236 (Migration section — internal inconsistency). Documented in §11. |
| **L7** | ⚪ Low | **No change needed.** Audit confirmed alignment is correct. |

**Audit verdict was NEEDS REVISION.** All blockers (C1, H1, H2, H3, H5, H6, H7) are now addressed. Plan is re-verified against current source (StressScoring.swift, StressViewModel.swift, StressDeepDiveSection.swift, DietDetailView.swift, ScreenTimeDetailView.swift, SharedWidgetViews.swift, SharedStressData.swift, ProfileView.swift, StressFactorCardView.swift, StressModels.swift, AppConfig.swift, MockHealthKitService.swift, StressMockSnapshot.swift) as of 2026-04-20.

---

## 1. Summary

Phase 1 lands six research-backed tweaks to the existing v1 `StressScoring` service (Q1 re-weight, Q2 missing-data plumbing, Q3 7k step target, Q4 deep-sleep 45-min floor, Q5 evening-hours multiplier *deferred to Phase 2*, Q6 confidence badge), adds an `AppConfig.stressAlgorithmV2` feature-flag placeholder, and ships "honest mode" — when fewer than 2 factors have valid data, the hero score is replaced with "Log more to see your stress score" instead of a potentially misleading small number. All downstream consumers — widget, AI report, home insight card, `StressReading` history — must keep rendering against the same `totalScore: Double` and `allFactors: [StressFactorResult]` shape they use today. **Exit gate:** a sparse-data user no longer sees a phantom 12.5 for unlogged factors, users with <2 factors see honest-mode placeholder instead of a number, the 7k-step user tops out the exercise score, a night with <45 min deep sleep is visibly capped, the confidence badge reads Medium/High correctly, the new-vs-old-algorithm whipsaw is ≤5 points on default mock, and all 4 build targets compile clean with mock mode toggled on and off. <!-- RESOLVED: H1 — honest mode restored as Phase 1 scope; H6 — whipsaw exit gate added -->

---

## 2. Preconditions (verified in repo read)

- `StressScoring` is pure and stateless — no instance state, no services, no async. All 4 factor functions (lines 14, 25, 55, 73) are pure statics with no instance state — ready for in-place signature changes. <!-- RESOLVED: L2 — rephrased -->
- `StressFactorResult.hasValidData` already exists with the correct semantics: `stressContribution` returns 0 when `hasValidData == false` (`StressModels.swift:111–114`).
- `StressFactorResult.neutral(...)` already initializes `hasValidData: false` for the four default published factors (`StressViewModel.swift:25–28`). Phase 1 just needs the builders to stop overriding that with `hasValidData: true` when the inputs are missing.
- `ScreenTimeManager.currentAutoDetectedReading` returns a single daily `rawHours: Double` from a threshold milestone — **no hourly breakdown is exposed today** (`ScreenTimeManager.swift:124–161`). This confirms the Q5 decision path in §4. <!-- RESOLVED: M6 — audit confirmed citation accurate -->
- `AppConfig` already uses a UserDefaults-backed DEBUG-togglable pattern for `mockMode` (`AppConfig.swift:29–46`). The v2 flag follows that shape.
- Widget consumes `WidgetStressFactor.score/maxScore/contribution` and the factor list from `viewModel.allFactors` (`WidgetRefreshHelper.swift:9–17`). All 5 widget/profile renderers hard-code the `/25` denominator for visual bars (`SharedWidgetViews.swift:104, 109, 124`; `StressLargeView.swift:130`; `ProfileView.swift:1433, 1435, 1445`; `StressFactorCardView.swift:46`). <!-- RESOLVED: L3 — ProfileView references normalized to :1433, 1435, 1445 everywhere -->
- **`StressDeepDiveSection.swift:72–82` calls all 4 `StressScoring` factor functions directly** to compute the "Factor Breakdown: Best vs Worst Days" decomposition. Signature change to `Double?` will break this site — see Task 14. <!-- RESOLVED: C1 — preconditions now list the StressDeepDiveSection consumer -->
- **`DietDetailView.swift:82` and `ScreenTimeDetailView.swift:80`** both render `Text(" /25")` hard-coded in the factor header — must be swept along with the widget/profile files. <!-- RESOLVED: H3 — detail views added -->
- `MockHealthKitService.fetchSteps` returns `snapshot.stepsHistory` filtered by date range (`MockHealthKitService.swift:27`). `fetchStepsSafely` then sums samples and returns `total > 0 ? total : nil`. In mock mode, zeroing today's `stepsHistory` entry is sufficient to propagate nil to `StressScoring.exerciseScore`. <!-- RESOLVED: M3 — mock path verified -->

**This is the single largest ripple** — see §5.

---

## 3. Task List (13 original tasks + 2 new: Tasks 14–15)

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
    //     NOTE (M1): 70% is an engineering choice (no research anchor for magnitude).
    //     Re-evaluated in Phase 3 alongside age-band lowered thresholds (S3).
    let deepMinutes = s.deepHours * 60.0
    if deepMinutes < 45 {
        score = Swift.min(score, max * 0.70)
    }

    return Swift.min(max, score)
}
```
<!-- RESOLVED: M1 — 70% cap rationale called out as engineering choice with Phase 3 re-evaluation note -->
**Why:** Q2 (nil on missing), Q4 (45-min floor per Research §3b). Numbers in the duration curve preserve the v1 shape (7–9 h was the peak band earning ~80% of 25 = 20 pts; now earns ~80% of 35 ≈ 28 pts).
**Verification:** Build + open mock mode, confirm a DailySleepSummary with totalHours=8 but deepHours=0.5 (30 min) shows a capped score.
**Hand-check (mock default: 7.2h total / 2.3h deep):**
- durationFraction (7..<9 band) = lerp(0.72, 0.80, t=0.1) = 0.728
- base = 35 × 0.728 = 25.48
- deepRatio = 2.3/7.2 = 0.3194 → clamp(0.3194/0.18)=1.0 → bonus = 35×0.20 = 7.0
- deepMinutes = 138 → no floor cap
- final = min(35, 32.48) = **32.48 / 35**, contribution = **2.52**
**Risk:** Medium — curve re-scaling is arithmetic, but sleep is the highest-weighted factor, so errors are visible.

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
**Change — `screenTimeScore` (no `eveningHours` parameter — Q5 fully deferred to Phase 2):**
```swift
/// Returns 0–`Weights.screenTime`. Returns nil when hours is nil.
/// Q5 (evening ×1.5 multiplier) ships in StressScoringV2 — requires hourly-bucket
/// refactor of ScreenTimeManager, tracked in Phase 2.
static func screenTimeScore(hours: Double?) -> Double? {
    guard let h = hours else { return nil }
    let max = Weights.screenTime
    // Original: h * 2 capped at 25. Re-scaled to new max (20): 2.5 pts/hour, cap at 20 (8h).
    return Swift.min(max, h * (max / 8.0))
}
```
<!-- RESOLVED: H2 — eveningHours parameter removed; Q5 fully deferred to Phase 2 StressScoringV2 -->
**Why:** Q2 — nil on missing (diet) and nil on missing (screen time). Q5 is **not** plumbed in Phase 1: the strategy §3 Phase 1 decision point ("if not available, Q5 moves to P2") is honored by keeping `screenTimeScore` single-argument and leaving hourly-bucket work for the Phase 2 `StressScoringV2` service (strategy §3 P2).
**Verification:** Build. Mock default (4.5h screen time, no evening breakdown) should now produce `min(20, 4.5 * 2.5) = 11.25` vs old `min(25, 4.5 * 2.0) = 9.0`.
**Risk:** Medium — screen-time ceiling change means a sparse user who had 4.5h before now has 11.25 contribution vs 9.0. Total can still land in the same band after Q1 re-weight rebalances the pool.

---

### Task 5 — Update `StressViewModel` factor builders + full `/25` cosmetic sweep

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

**Sub-sweep: `/25` literal references that must be updated or commented:** <!-- RESOLVED: H3 — complete sweep list; M5 — widget + placeholder comments added -->

| Site | Change |
|---|---|
| `WellPlateWidget/Views/SharedWidgetViews.swift:104` | `factor.contribution / 25.0` → `factor.contribution / factor.maxScore` (guard at :103 remains) |
| `WellPlateWidget/Views/SharedWidgetViews.swift:109` | same |
| `WellPlateWidget/Views/SharedWidgetViews.swift:124` | `"\(Int(factor.contribution))/25"` → `"\(Int(factor.contribution))/\(Int(factor.maxScore))"` |
| `WellPlate/Features + UI/Tab/ProfileView.swift:1433` | `factor.contribution / 25.0` → `factor.contribution / factor.maxScore` |
| `WellPlate/Features + UI/Tab/ProfileView.swift:1435` | same |
| `WellPlate/Features + UI/Tab/ProfileView.swift:1445` | `"\(Int(factor.contribution))/25"` → `"\(Int(factor.contribution))/\(Int(factor.maxScore))"` |
| `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift:46` | `"\(Int(factor.score))/25"` → `"\(Int(factor.score))/\(Int(factor.maxScore))"` |
| `WellPlate/Features + UI/Stress/Views/DietDetailView.swift:82` | `Text(" /25")` → `Text(" /\(Int(factor.maxScore))")` **(new in resolved plan)** |
| `WellPlate/Features + UI/Stress/Views/ScreenTimeDetailView.swift:80` | `Text(" /25")` → `Text(" /\(Int(factor.maxScore))")` **(new in resolved plan)** |
| `WellPlate/Widgets/SharedStressData.swift:95` | Comment `// 25` → `// per-factor weight (sleep 35, exercise 25, diet 20, screen 20)` |
| `WellPlate/Widgets/SharedStressData.swift:68–71` | Placeholder `maxScore: 25` → `maxScore: 25 / 35 / 20 / 20` respectively (Exercise / Sleep / Diet / Screen) so Xcode previews scale correctly |
| `WellPlate/Models/StressModels.swift:78` | Comment `// always 25` → `// varies per factor (sleep 35, exercise 25, diet 20, screen 20)` |
| `WellPlate/Models/StressModels.swift:131` | `StressFactorResult` preview fixture `maxScore: 25` stays (it's the Exercise stub — fine) |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:238, 246, 349, 352, 641` | DEBUG `log()` calls print `/25` literals — update each to print the actual `maxScore` of the factor being logged (e.g. `/\(Int(Weights.sleep))`). Cosmetic only, DEBUG-gated. |

**Why:** Q1 + Q2 consolidated. All 4 factors now report `hasValidData = (score != nil)` and carry their weighted ceiling as `maxScore`. The `/25` literals were already a debt that the weight change makes visible.

**Verification (H5 — recomputed):** <!-- RESOLVED: H5 — verification numbers recomputed from scratch with math published inline -->

For `StressMockSnapshot.default` (steps=7500, energy=340, sleep 7.2h / 2.3h deep, protein 64g / fiber 13g / fat 22g / carbs 84g, 4.5h screen):

| Factor | Score | Contribution | Math |
|---|---|---|---|
| Exercise | 19.58 / 25 | **5.42** | avg(25·min(1, 7500/7000)=25, 25·min(1, 340/600)=14.17) = 19.58; higherIsBetter → 25 − 19.58 = 5.42 |
| Sleep | 32.48 / 35 | **2.52** | 35·0.728 + 7 (deep bonus full) = 32.48; 138 min deep → no floor cap; 35 − 32.48 = 2.52 |
| Diet | 20.00 / 20 | **0.00** | proteinR=1.0, fiberR=0.52, balanced=0.784; fatR=0.338, carbR=0.373, excess=0.358; netBalance = clamp(0.784 − 0.215 + 0.5) = 1.0; 20·1.0 = 20 |
| Screen Time | 11.25 / 20 | **11.25** | min(20, 4.5·2.5) = 11.25; higherIsBetter=false |
| **Total** | — | **19.19** → **Excellent** (<21 band) |

**v1 (old) comparison for H6 whipsaw gate:**

| Factor | v1 contribution | v2 contribution | Δ |
|---|---|---|---|
| Exercise | 25 − avg(25·0.75, 25·0.567) = 8.54 | 5.42 | −3.12 |
| Sleep | 25 − (18.2 + 5) = 1.80 | 2.52 | +0.72 |
| Diet | 25 − 25 = 0 | 0 | 0 |
| Screen Time | min(25, 4.5·2) = 9.00 | 11.25 | +2.25 |
| **Total** | **19.34** | **19.19** | **−0.15** |

|Δtotal| = **0.15 ≤ 5** → strategy §3 exit gate met. ✅
<!-- RESOLVED: H6 — whipsaw delta verified (0.15) -->

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
**Why:** Because `stressContribution` already returns 0 when `hasValidData == false` (`StressModels.swift:111–114`), and each factor's `maxScore` now matches its Q1 weight, the sum is automatically a weighted 0–100. **No weight-redistribution logic in Phase 1** — a user with 2 missing factors simply has a smaller maximum possible score, which is exactly what Q2 intends (phantom stress disappears instead of being redistributed). **Honest mode (Task 15) handles the `<2 factors` case by hiding the score entirely** — that is where strategy §3's "Log more to see your stress score" placeholder surfaces. <!-- RESOLVED: H1 — honest mode referenced here for consumer clarity -->
**Verification:** Confirm via log: a mock snapshot with an empty `currentDayLogs` array produces `dietFactor.stressContribution == 0`, `totalScore` is ≤ 80 (since diet max 20 is now missing from the pool), and no phantom 12.5 shows anywhere.
**Risk:** Low (verification-only task).

---

### Task 7 — Add `StressViewModel.Confidence` nested enum + computed property on ViewModel

**File:** `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` (extend existing file; **no new file**)
**Change — add at bottom of `StressViewModel`:**
```swift
// MARK: - Confidence

extension StressViewModel {
    enum Confidence: String {
        case low, medium, high

        var label: String {
            switch self {
            case .low: "Low confidence"       // not rendered at runtime — honest mode supersedes
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
}

var factorCoverage: Int { allFactors.filter(\.hasValidData).count }  // 0…4

var stressConfidence: StressViewModel.Confidence {
    switch factorCoverage {
    case 4: .high
    case 2, 3: .medium
    default: .low
    }
}

/// Phase-1 honest mode: <2 factors → hide the score (Task 15).
var shouldHideScoreForLowConfidence: Bool { factorCoverage < 2 }
```
<!-- RESOLVED: M4 — nested type Confidence instead of top-level StressConfidence to avoid P2 collision -->
<!-- RESOLVED: H1 — shouldHideScoreForLowConfidence computed var added for Task 15 consumer -->
**Why:** Q6 / U1 — confidence badge per strategy §3 Phase 1 ("confidence badge shows Low when <3 factors have data, High when 4/4"). Keeping the enum nested inside `StressViewModel` avoids collision with Phase 2's `.calibrating` state. `.low` case is retained for API completeness but its `label` is never displayed — `factorCoverage < 2` triggers honest mode instead (see Task 15).
**Verification:** Build. Preview mock (4 factors valid) returns `.high` and `shouldHideScoreForLowConfidence == false`. A manually-constructed snapshot with only steps present returns `.low` and `shouldHideScoreForLowConfidence == true`.
**Risk:** Low.

---

### Task 8 — Render confidence badge in `StressView`

**File:** `WellPlate/Features + UI/Stress/Views/StressView.swift:298–312` (score header)
**Change:** Add a badge below `/100` inside `scoreHeader`. Only renders when score is visible (i.e., not in honest mode — Task 15 wraps this view). <!-- RESOLVED: H1 — badge and score always appear together; honest mode replaces both -->
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
            .font(.system(size: 13, weight: .semibold))    // bumped 11 → 13 (M2)
        Text("\(viewModel.stressConfidence.label) · \(viewModel.factorCoverage)/4 factors")
            .font(.system(size: 13, weight: .medium, design: .rounded))   // bumped + medium weight (M2)
            .tracking(0.4)
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Capsule().fill(Color(.systemGray6)))
}
```
<!-- RESOLVED: M2 — badge font bumped 11→13 + medium weight for trust-signal visibility -->
**Animation note (L4):** The existing `.scaleEffect(scoreAppeared ? 1.0 : 0.85, anchor: .topLeading)` at `StressView.swift:239-243` continues to work because the new VStack is still anchored to the same top-leading corner — the anchor scales whatever the parent is. <!-- RESOLVED: L4 -->
**Why:** Q6 / U1 / U4 — surfaced on the main stress card as per strategy §3 exit gate.
**Verification:** Mock mode → badge shows "High confidence · 4/4 factors". Break one factor (e.g., clear `currentDayLogs` in a debug snapshot) → badge shows "Medium confidence · 3/4 factors". With 0 or 1 factor valid → Task 15's honest mode replaces this view entirely, so badge is not shown.
**Risk:** Low — cosmetic addition, no layout reflows that affect other cards.

---

### Task 9 — Q5 evening screen-time multiplier: Phase 1 defer (no code)

**Files:** *No code change.* Purely a planning-level decision forward-referenced to Phase 2.
**Decision:** Q5 is **fully deferred** to Phase 2:
- ❌ No `eveningHours` parameter in `StressScoring.screenTimeScore` (dropped in Task 4 vs original plan). <!-- RESOLVED: H2 — parameter dropped; no dead code -->
- ❌ No `ScreenTimeManager` modification. Current `DeviceActivitySchedule` uses threshold events keyed on *accumulated* minutes (`ScreenTimeManager.swift:84–112`), not time-of-day. Extracting "after 21:00" requires re-architecting the monitor with an additional `DeviceActivitySchedule` windowed on 21:00–23:59, writing a second App Group key, and reading both in `currentAutoDetectedReading`. That is a meaningful DeviceActivity change that belongs in Phase 2 alongside the bipolar rewrite.
- ✅ `StressScoring.screenTimeScore` carries a `// Q5 evening ×1.5 multiplier ships in StressScoringV2` comment so Phase 2 inherits the context.
**Why:** Strategy §3 Phase 1 "Decision points to resolve before starting: Q5 feasibility — confirm ScreenTimeManager exposes hourly breakdown; if not, Q5 moves to P2 and P1 keeps 5 items." Verified — it does not expose hourly. Keeping the v1 API unchanged means Phase 2's `StressScoringV2.screenTimeSignal` can own evening handling without v1 carrying dead-parameter baggage. <!-- RESOLVED: H2 — Phase-2 forward-reference comment only; no parameter plumbing in Phase 1 -->
**Verification:** Build passes with unchanged v1 API surface.
**Risk:** None.

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
Also add to `logCurrentMode()` output (style-matches the existing spartan lines at `AppConfig.swift:152-156`):
```swift
"Stress v2  : \(stressAlgorithmV2 ? "ENABLED" : "disabled")",
```
<!-- RESOLVED: L5 — removed 🧪 emoji; plain ENABLED/disabled matches adjacent log-value style. Existing ✅/❌ in header are kept. -->
**Why:** Strategy §4 "Migration & Compatibility" line 223 states the flag `defaults to false in P1–P2`. Adding it as an unused placeholder in Phase 1 is the smallest surface change that lets Phase 2 land as additive — no file-creation rush at the start of P2, and existing consumers can safely probe the key from day 1. Strategy's §6 File Touch Summary originally scheduled the flag for P2; pulling it forward by one phase is a convenience decision that keeps P2 focused on the actual v2 scorer build. <!-- RESOLVED: H7 — fabricated quote replaced with accurate strategy-§4-line-223 paraphrase -->
**Verification:** Build. `AppConfig.shared.stressAlgorithmV2` returns `false` by default, toggleable only in DEBUG. No production code reads it yet.
**Risk:** None. Purely additive.

---

### Task 11 — Update `StressMockSnapshot` to exercise the new missing-data paths

**File:** `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift:49–264`
**Change:** Add a second static factory alongside `.default`:
```swift
/// Sparse-data variant — only sleep + screen time have valid data (2 of 4 factors).
/// Exercises the Q2 missing-data plumbing and Q6 "Medium confidence" badge.
/// - Exercise: nil via stepsHistory last-entry = 0 → fetchStepsSafely's `total > 0 ? total : nil` returns nil
/// - Energy: nil via same pattern on energyHistory
/// - Diet: nil via currentDayLogs = []
/// - Sleep + Screen Time: retained from default
static let sparse: StressMockSnapshot = makeSparse()

private static func makeSparse() -> StressMockSnapshot {
    let base = makeDefault()
    // Override today's last history sample to 0 so MockHealthKitService returns it
    // and fetchStepsSafely/fetchEnergySafely (StressViewModel.swift:489-498) coerce to nil.
    var stepsHist = base.stepsHistory
    var energyHist = base.energyHistory
    if !stepsHist.isEmpty {
        stepsHist[stepsHist.count - 1] = DailyMetricSample(date: stepsHist.last!.date, value: 0)
    }
    if !energyHist.isEmpty {
        energyHist[energyHist.count - 1] = DailyMetricSample(date: energyHist.last!.date, value: 0)
    }
    return StressMockSnapshot(
        steps: 0,                    // cosmetic; actual data path goes via stepsHistory
        energy: 0,                   // cosmetic; actual data path goes via energyHistory
        sleepSummary: base.sleepSummary,
        screenTimeHours: base.screenTimeHours,
        stepsHistory: stepsHist,
        energyHistory: energyHist,
        sleepHistory: base.sleepHistory,
        heartRateHistory: base.heartRateHistory,
        restingHRHistory: base.restingHRHistory,
        hrvHistory: base.hrvHistory,
        systolicBPHistory: base.systolicBPHistory,
        diastolicBPHistory: base.diastolicBPHistory,
        respiratoryRateHistory: base.respiratoryRateHistory,
        daylightHistory: base.daylightHistory,
        waterHistory: base.waterHistory,
        exerciseMinutesHistory: base.exerciseMinutesHistory,
        todayReadings: base.todayReadings,
        weekReadings: base.weekReadings,
        currentDayLogs: []           // no food logged → dietFactor.hasValidData = false
    )
}
```
<!-- RESOLVED: M3 — mock path explicitly documents how nil propagates through MockHealthKitService → fetchStepsSafely → StressScoring.exerciseScore. No breaking change to struct fields. -->
Also **no change** required to `default` — the mock default has 4/4 valid factors and will now render "High confidence" naturally.
**Why:** Strategy §3 Phase 1 affected files list — `StressMockSnapshot.swift` "add sparse-data snapshot variant to exercise the new missing-data paths".

**Verification (H5 — sparse scenario):** Manually swap `StressView` preview to use `.sparse` and confirm:
- Diet factor card grayed (handled by existing `factor.accentColor` returning `.systemGray3` when `!hasValidData`).
- Exercise factor grayed with "No data" detail.
- Confidence badge reads "Medium confidence · 2/4 factors" (2 = sleep + screen time).
- `totalScore` = Sleep contribution 2.52 + Screen Time contribution 11.25 = **13.77 ≈ 14/100 → Excellent** (since <21 band).
- No phantom 12.5 anywhere.
- Honest mode NOT triggered (coverage = 2, threshold is `<2`).

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
2. Stress tab with `.default` mock → hero "19/100" number renders; confidence badge shows "High confidence · 4/4 factors". <!-- RESOLVED: H5 — updated expected values -->
3. Stress tab with `.sparse` mock → hero "14/100" + "Medium confidence · 2/4 factors" badge.
4. Stress tab with a constructed 1-factor mock (e.g., sleep only) → hero replaced with "Log more to see your stress score" placeholder; no `StressReading` row logged. <!-- RESOLVED: H1 -->
5. Toggle `AppConfig.stressAlgorithmV2` in a DEBUG menu if present — no-op but log-emits.
6. Long-press widget on home screen → Stress widget renders with 4 factor bars; contribution numbers show "X/25" or "X/35" etc. according to each factor's `maxScore`.
7. Open AI report sheet → Stress deep-dive section renders with the day's stress score AND the factor-decomposition chart (Task 14 call-site unwraps should not crash even with nil historical days). No crash. <!-- RESOLVED: C1 -->
8. Tap into Diet detail → header reads "X /20" (not "/25"). Tap into Screen Time detail → header reads "X /20". <!-- RESOLVED: H3 -->
9. Toggle mock mode off, allow HealthKit permission → `totalScore` computes without NaN.
10. **Whipsaw check (H6):** Using default mock, compare v1 total (19.34 per §4 math) against new v1.1 total (19.19). Confirm |Δ| ≤ 5. Also spot-check an "all-typical" synthetic fixture (steps=10000, energy=600, sleep=8h/2.5h deep, balanced macros, 6h screen): new v1.1 predicts ~22 vs v1's ~18 → |Δ|≈4, within gate. <!-- RESOLVED: H6 — smoke step added -->
**Risk:** Medium — the widget and the profile mini-bars still hard-code `/25.0` unless Task 5 sub-sweep lands correctly. Cover in smoke step 6.

---

### Task 14 — **NEW** — `StressDeepDiveSection` factor-score call-site migration

**File:** `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift:72–82`
**Context:** The plan's original §2 Preconditions asserted that the only consumer of `StressScoring.*` was `StressViewModel`. Audit finding C1 confirmed `StressDeepDiveSection.factorDecompItems` calls all 4 functions directly and stores results in non-optional `Double`. Once Tasks 2–4 flip the return types to `Double?`, this file will not compile.

**Change — 4 call sites at lines 75–80:**
```swift
private var factorDecompItems: [(label: String, exercise: Double, sleep: Double, diet: Double, screenTime: Double)] {
    let scored = data.context.days.compactMap { d -> (date: Date, stress: Double, exercise: Double, sleep: Double, diet: Double, screen: Double)? in
        guard let stress = d.stressScore else { return nil }
        let ex = StressScoring.exerciseScore(steps: d.steps.map(Double.init), energy: d.activeCalories.map(Double.init)) ?? 0
        let sl = StressScoring.sleepScore(summary: d.sleepHours.map { h in
            DailySleepSummary(date: d.date, totalHours: h, coreHours: 0, remHours: 0, deepHours: d.deepSleepHours ?? 0)
        }) ?? 0
        let dt = StressScoring.dietScore(protein: d.totalProteinG ?? 0, fiber: d.totalFiberG ?? 0, fat: d.totalFatG ?? 0, carbs: d.totalCarbsG ?? 0, hasLogs: d.totalCalories != nil) ?? 0
        let sc = StressScoring.screenTimeScore(hours: nil) ?? 0
        return (date: d.date, stress: stress, exercise: ex, sleep: sl, diet: dt, screen: sc)
    }
    // ... unchanged below
}
```
<!-- RESOLVED: C1 — less-invasive fix: ?? 0 at each of 4 call sites; tuple shape unchanged; historical nil days render as zero contribution in the Best-vs-Worst decomposition chart. -->
**Why (C1 rationale):** This is a *historical averages* rendering path, not a today-score path. A nil-day legitimately means "we don't have data for this day". Rendering it as zero is correct for the "Factor Breakdown: Best vs Worst Days" chart — the factor simply doesn't move the bar on that day. Changing the tuple to `Double?` would force nil-handling in the chart axis/bar rendering code (`factorDecomposition` ViewBuilder at line 98+) and balloon the change scope. Per user spec: "Choose the less invasive option and justify."
**Verification:** Build + open mock AI report. Confirm the decomposition chart renders without crashing; a synthetic day with no sleep data shows a zero-height sleep bar (not an absent bar).
**Risk:** Low.

---

### Task 15 — **NEW** — Honest-mode placeholder when `factorCoverage < 2`

**File:** `WellPlate/Features + UI/Stress/Views/StressView.swift` (wrap or conditionalize `scoreHeader`)
**Context:** Strategy §3 Phase 1 decision point line 76 committed: *"default to YES for Q2: if <2 factors have valid data, show 'Log more to see your stress score' instead of a number."* The original Phase 1 plan deferred this to Phase 2 without authorization (audit H1).

**Change — introduce a branching wrapper around `scoreHeader`:**
```swift
@ViewBuilder
private var scoreHero: some View {
    if viewModel.shouldHideScoreForLowConfidence {
        honestModePlaceholder
    } else {
        scoreHeader          // existing Task 8 VStack: score + confidence badge
    }
}

private var honestModePlaceholder: some View {
    VStack(alignment: .leading, spacing: 8) {
        Image(systemName: "square.stack.3d.up.slash")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(.secondary)
        Text("Log more to see your stress score")
            .font(.r(.title3, .semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        Text("We need at least 2 of 4 factors (sleep, exercise, diet, screen time) to compute a reliable score.")
            .font(.r(.footnote, .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    // keep the same .opacity/.scaleEffect animation modifiers that wrapped scoreHeader at :239-243
}
```

And at the hero call-site (previously `scoreHeader`), swap in `scoreHero`:
```swift
// was: scoreHeader
scoreHero
    .padding(.top, 20)
    .opacity(scoreAppeared ? 1 : 0)
    .scaleEffect(scoreAppeared ? 1.0 : 0.85, anchor: .topLeading)
```

**Also — skip `StressReading` logging in honest mode.** In `StressViewModel.logCurrentStress(source:)` (around line 372):
```swift
func logCurrentStress(source: String) {
    guard !shouldHideScoreForLowConfidence else {
        #if DEBUG
        log("⏭  Skipped StressReading log: honest mode (coverage=\(factorCoverage))")
        #endif
        return
    }
    // ... existing body ...
}
```
Rationale: a honest-mode day is explicitly "unknown" — logging a score of e.g. 11.25 (from screen time alone) would pollute history and re-create exactly the misleading-number problem honest mode is meant to solve.
<!-- RESOLVED: H1 — honest mode restored as Phase 1; threshold <2 per strategy §3 line 76; persistence skipped to keep history clean -->

**Why:** Strategy §3 Phase 1 explicit decision; audit finding H1 + H4 both point here. With this in, the `stressConfidence == .low` case never renders in the UI — honest mode supersedes it (see §11).
**Verification:**
- With `.default` mock (4/4 factors) → hero shows "19/100 · High confidence · 4/4 factors".
- With `.sparse` mock (2/4 factors) → hero shows "14/100 · Medium confidence · 2/4 factors".
- With constructed 1-factor mock (only sleep) → hero shows "Log more to see your stress score"; `StressReading` log emit for that day is skipped.
- No factors at all (new user, no HK permission, no food logs) → hero shows placeholder; no log.
**Risk:** Low — additive UI branch, no layout thrash.

---

## 4. StressLevel Bands Math (verification) — **recomputed for H5**

**Factor ceilings after Q1 re-weight:**
| Factor | Max contribution | Notes |
|---|---|---|
| Sleep | 35 | `higherIsBetter=true` — max stress contribution = 35 (zero sleep) |
| Exercise | 25 | max stress contribution = 25 (zero activity) |
| Diet | 20 | max stress contribution = 20 (no logs → `hasValidData=false` → 0; very poor logs → up to 20) |
| Screen Time | 20 | `higherIsBetter=false` — max contribution = 20 (≥8h screen time) |
| **Total** | **100** | |

**Worst-case stress profile (all 4 factors present, all maxing out):** 35 + 25 + 20 + 20 = 100 → `.veryHigh` ✅

**Strategy exit-gate question — "could a max-screen-time-only user still hit Very High?"** No. With only screen time reporting (other 3 `hasValidData=false` → 0), the maximum possible `totalScore` is 20 → `.excellent`. **But now honest mode (Task 15) intervenes first** — with only 1 factor valid the user sees the "Log more" placeholder, not a score. Only when coverage ≥ 2 does the number surface.

**Realistic mock scenarios (H5 — recomputed from formulas):**

| Scenario | Exercise | Sleep | Diet | Screen | Total | Level | Notes |
|---|---|---|---|---|---|---|---|
| Mock `.default` (7500 steps / 340 kcal / 7.2h-2.3hdeep / 64p/13f/22f/84c / 4.5h screen) | 5.42 | 2.52 | 0.00 | 11.25 | **19.19** | **Excellent** (<21) | Was "23/Good" in pre-audit plan; corrected |
| Mock `.sparse` (only sleep + screen, exercise+diet nil) | 0.00 | 2.52 | 0.00 | 11.25 | **13.77** | **Excellent** | Coverage = 2 → Medium confidence shown |
| Synthetic all-max stress (0 steps/0 kcal / <4h sleep / bad macros / 10h screen) | 25.00 | 35.00 | 20.00 | 20.00 | **100.00** | **Very High** | Sanity check |
| Synthetic "typical active user" (10000 / 600 / 8h-2.5hdeep / 75p/22f/50f/180c / 6h screen) | 0.00 | 35 − (35·0.78 + 7·(2.5/8/0.18→cl. 1.0)) = 35 − 34.3 = 0.7 | 20 − (20·1.0) = 0 | min(20, 6·2.5)=15 | **15.7** | **Excellent** | v1 same inputs ≈ 25−25 + 25−(19.33+5) + 0 + 12 = 12.67 → v1.1 Δ≈+3.0 (within ≤5) |

**H6 whipsaw exit gate:**
- `.default` mock: v1.1 = 19.19, v1 = 19.34, Δ = 0.15 ≤ 5 ✅
- Synthetic typical-user: v1.1 ≈ 15.7, v1 ≈ 12.67, Δ ≈ 3.0 ≤ 5 ✅
- Synthetic all-max: v1.1 = 100, v1 = 100, Δ = 0 ≤ 5 ✅

<!-- RESOLVED: H5 + H6 — verification table recomputed; whipsaw delta bounded ≤5 on default mock and synthetic typical-user profile -->

**Decision:** No band threshold changes for Phase 1. The existing `..<21 / 21..<41 / 41..<61 / 61..<81 / 81+` cutoffs remain semantically correct.

---

## 5. Ripple Audit (consumer-by-consumer)

### 5a. `WellPlateWidget` target (`WellPlateWidget/Views/SharedWidgetViews.swift`, `StressWidget.swift`, `StressLargeView.swift`) + `WellPlate/Widgets/SharedStressData.swift`
- **Reads:** `WidgetStressData.totalScore: Double` (0–100) and `WidgetStressFactor.{score, maxScore, contribution, hasValidData}`. Populated by `WidgetRefreshHelper.refreshStress` which maps `factor.maxScore` straight from `StressFactorResult.maxScore`.
- **Does it break?** *Mostly no, but cosmetic regression.* After Task 5 the serialized `maxScore` field is now 35/25/20/20 instead of uniformly 25. `WidgetRefreshHelper.swift:14` already forwards `factor.maxScore` correctly. **But:** `SharedWidgetViews.swift:104, 109, 124` hard-codes `/25.0` for bar fractions and the `"N/25"` label; same in `ProfileView.swift:1433, 1435, 1445`. **Also** `SharedStressData.swift:68–71` placeholder and `:95` comment still say `25`.
- **Change required:** See Task 5 cosmetic-sweep table. <!-- RESOLVED: H3 + M5 -->
- **Scope creep check:** Full sweep now 7 files + 1 comment + 1 DEBUG-log-update in StressViewModel. Justified: without it the widget shows `"35/25"` for a sleep-deficient user, which is visibly wrong.

### 5b. AI Report — `ReportDataBuilder.swift:224`, `ReportNarrativeGenerator.swift:111–149`, `StressDeepDiveSection.swift`
- **Reads:** `day.stressScore: Double?` (the persisted `StressReading.score`). **Plus:** `StressDeepDiveSection.factorDecompItems` at lines 72–82 directly calls all 4 `StressScoring.*` factor functions to compute historical factor breakdowns — a factor-level read not previously acknowledged. <!-- RESOLVED: C1 -->
- **Does it break?** For scalar consumers (Narrative, ReportDataBuilder): No — scalar shape unchanged. **For `StressDeepDiveSection`: YES** once Tasks 2–4 change return types to `Double?`. See Task 14.
- **Change required:** Task 14 — unwrap `?? 0` at 4 call sites in `factorDecompItems`. <!-- RESOLVED: C1 -->

### 5c. Home Insights — `InsightEngine.swift`, `StressInsightCard.swift`
- **Reads:** `InsightEngine` extracts `d.stressScore` (scalar) and runs correlations/streaks — no factor-max reads. `StressInsightCard` takes a `stressLevel: String` and a `tip: String` (`StressInsightCard.swift:8–10`).
- **Does it break?** No. Both consume post-mapping outputs (label string, scalar score).
- **Change required:** None.

### 5d. `StressReading` persistence (`StressViewModel.swift:372–406`)
- **Reads:** Persists `totalScore` and `stressLevel.label`.
- **Does it break?** No. Same API, just produces new numbers. Old rows are read-only history — accepted per strategy §4. **Phase 1 adds a guard in `logCurrentStress(source:)` to skip persistence when honest mode is active (Task 15).**
- **Acknowledged transient (M7):** Weekly sparkline in widget + WellnessCalendar will mix v1 (pre-ship) and v1.1 (post-ship) rows for ~7 days. Strategy §4 "do not backfill" position is preserved. Phase 2 will consider adding `StressReading.algorithmVersion: String` as a tombstone — tracked as *"P2 `StressReading.algorithmVersion` tombstone field"*. <!-- RESOLVED: M7 — deferred to Phase 2 with named followup task -->
- **Change required:** Task 15 adds the honest-mode log-skip guard; no other schema change.

### 5e. `WellnessDayLog` sync (`StressViewModel.swift:440–478`)
- **Reads:** Writes `stressLevel.label` to `WellnessDayLog.stressLevel`. Used by HomeView rings.
- **Does it break?** No. Label strings unchanged. **In honest mode, `stressLevel.label` would write "Excellent" for a low-coverage score** — arguably misleading. However, `persistTodayWellnessSnapshot` at StressViewModel.swift:256 runs before `logCurrentStress(source:)` and sets the day's label based on `totalScore`. For Phase 1 we accept this (same misleading-low risk acknowledged in H4, now muted because the *visible* UI route is honest mode). Phase 2 should gate this write on `!shouldHideScoreForLowConfidence` as well.
- **Change required:** None for Phase 1 (accepted risk); flagged for Phase 2.

### 5f. Mock mode (`StressMockSnapshot`)
- **Does it break?** No — the default snapshot continues to exercise 4/4 factors. Task 11 adds a new `.sparse` variant for testing Q2 + confidence badge (and transitively for a developer to manually construct a 1-factor case to smoke-test honest mode).
- **Change required:** Task 11 above.

### 5g. `StressLab` and `Interventions` sheets
- **Reads:** `StressViewModel` directly; same API surface (`totalScore`, `allFactors`, `stressLevel`).
- **Does it break?** No.

### Summary ripple table

| Consumer | Behavior change? | File edit required? | Where |
|---|---|---|---|
| `StressView` main score | Yes (new score values + honest-mode branch) | Yes — Task 8 (badge), Task 15 (honest mode) | `StressView.swift` |
| `StressFactorCardView` | Text label `N/25` wrong for sleep | Yes | `StressFactorCardView.swift:46` |
| Widget small/medium/large | Bar fractions + `N/25` text wrong | Yes | `SharedWidgetViews.swift:104, 109, 124`; `StressLargeView.swift`; `SharedStressData.swift:68-71, 95` |
| ProfileView mini-bars | Same as widget | Yes | `ProfileView.swift:1433, 1435, 1445` |
| Diet detail view header | `/25` wrong for diet (max=20) | Yes | `DietDetailView.swift:82` |
| Screen-time detail view header | `/25` wrong for screen (max=20) | Yes | `ScreenTimeDetailView.swift:80` |
| AI Report `StressDeepDiveSection` | `Double?` return breaks 4 call sites | Yes — Task 14 | `StressDeepDiveSection.swift:75-80` |
| `StressReading` rows | New values flow in + honest-mode skip | Task 15 log-skip guard only | `StressViewModel.swift:372-406` |
| AI report narrative | Scalar pass-through | No | — |
| `InsightEngine` correlations | Scalar pass-through | No | — |
| `StressInsightCard` (home) | Label pass-through | No | — |
| `WellnessDayLog.stressLevel` | Label pass-through (honest mode gap accepted for P1) | No (flagged for P2) | — |

**Net surface area:** Core change = 3 files (`StressScoring`, `StressModels` comment only, `StressViewModel`). UI = 4 files (`StressView`, `StressFactorCardView`, `DietDetailView`, `ScreenTimeDetailView`). Widget/Profile cosmetic = 4 files (`SharedWidgetViews`, `StressLargeView`, `ProfileView`, `SharedStressData`). Config/mock = 2 files (`AppConfig`, `StressMockSnapshot`). AI report = 1 file (`StressDeepDiveSection`). **Total: 13 files modified, 0 new files created.** <!-- RESOLVED: C1 + H3 + M5 — file count increased from 10 to 13 with comprehensive sweep -->

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
- [ ] `StressView` score header renders a confidence badge showing `{Medium/High} confidence · N/4 factors` sourced from the new `stressConfidence` computed property **when coverage ≥ 2**.
- [ ] **Honest mode: when `factorCoverage < 2`, the score hero is replaced with "Log more to see your stress score" placeholder and `StressReading` persistence is skipped for that day.** <!-- RESOLVED: H1 -->
- [ ] `AppConfig.stressAlgorithmV2` exists, defaults to `false`, is DEBUG-togglable, and prints in `logCurrentMode()`.
- [ ] `StressMockSnapshot` has a `.sparse` variant alongside `.default`; both render without crashes; `.sparse` concretely exercises the MockHealthKit → `fetchStepsSafely` → nil path.
- [ ] All 4 build targets compile clean (commands in Task 13).
- [ ] Widget, Profile mini-bars, Diet detail view, Screen-time detail view, and the widget placeholder/comment all compute bar fractions and "X/Y" labels against `factor.maxScore` (not hard-coded 25). <!-- RESOLVED: H3 + M5 -->
- [ ] `StressInsightCard` on Home renders an appropriate label for a new-weighting score.
- [ ] `StressDeepDiveSection` in AI report renders without crash with the 4 call-site `?? 0` unwraps; scores persisted to `StressReading` post-Phase-1 use the new weighting (documented in the audit notes — not backfilled). <!-- RESOLVED: C1 -->
- [ ] **Whipsaw exit gate (H6): on `StressMockSnapshot.default` and a manually-constructed "typical active user" fixture (steps=10000, energy=600, sleep=8h/2.5hdeep, balanced macros, 6h screen), `|v1.1_total − v1_total| ≤ 5`.** Verified in §4 math (Δ=0.15 and ~3.0 respectively). <!-- RESOLVED: H6 -->
- [ ] Mock mode parity: toggling mock on/off and kicking the ViewModel into `loadData()` produces no NaN, no infinite values, no `totalScore > 100`.
- [ ] `CLAUDE.md` architecture conventions preserved — `StressScoring` stays pure + stateless; `@MainActor final class StressViewModel` unchanged; font/shadow tokens untouched.

---

## 8. Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Users with long-standing v1 scores see their number jump the first day after Phase 1 ships | High | Medium (trust signal) | Strategy §4 already accepted: "do not backfill historical rows". Ship the confidence badge as the soft explainer. A one-time "Your stress score got smarter" tombstone is a Phase 2 nicety — tracked, not required for P1. |
| Widget, Profile, and **diet/screen-time detail views** still show `/25` labels until the Task 5 cosmetic sweep lands, causing `35/25` rendering for high-sleep-deficit users | Medium | Medium (visible bug) | §5a explicitly calls out the 7-file sweep; make it a blocking sub-checklist in implementation phase. <!-- RESOLVED: H3 — 3→7 file sweep --> |
| Deep-sleep floor (Q4) caps the score for healthy users who happen to have a single bad deep-sleep night | Low | Low | Cap is 70% of sleep-max (≈24.5/35), not 0 — a user with 8h total but only 30 min deep still scores well. **Cap severity (M1) is an engineering-taste choice; re-evaluated in Phase 3 alongside age-band lowered thresholds (S3).** <!-- RESOLVED: M1 --> |
| Screen-time re-scaling to /20 + 2.5 pts/hour produces a *higher* contribution than v1 for light users (4.5h becomes 11.25 vs 9.0) | Medium | Low | Offset by the fact that sleep and exercise are now the dominant weights; realistic users get a lower total overall. Verified in §4 mock scenario table. |
| **Q5 deferred (H2)** — `ScreenTimeManager` hourly exposure requires a DeviceActivity re-architecture that is out of P1 scope | N/A | N/A | Fully deferred to Phase 2's `StressScoringV2.screenTimeSignal` + `ScreenTimeManager` hourly-bucket refactor. v1 API surface unchanged; no dead parameter. <!-- RESOLVED: H2 --> |
| The `Double?` return change across 4 scoring functions cascades more call sites than expected | **Was: Low / Now confirmed: 2 consumers** | Medium | **Grep confirmed consumers: `StressViewModel.loadData` + `StressDeepDiveSection.factorDecompItems` (see Task 14).** Also `StressInsightService` (if it exists) was referenced in `StressScoring.swift` header comment but does not appear in the current codebase grep — safe. <!-- RESOLVED: C1 — risk row corrected --> |
| Sleep-curve re-scaling arithmetic error makes the highest-weighted factor produce slightly off values vs mental model | Medium | Medium | Hand-verification table in §4 (7.2h + 2.3h deep → 32.48/35) lands in the implementation checklist as a manual log-inspection step. |
| **Pre-ship / post-ship `StressReading` mix causes ~1-week visual whipsaw in widget sparkline + WellnessCalendar** (M7) | Medium | Low (cosmetic) | **Accepted as expected cost of strategy §4 "do not backfill" stance.** Phase 2 will add `StressReading.algorithmVersion: String` as a tombstone field (tracked as *"P2 algorithmVersion tombstone"*). No user-facing explainer in P1. <!-- RESOLVED: M7 --> |
| **Honest mode hides scores for users with <2 factors until they log more** | Low | Low (positive — intended behavior) | Strategy §3 line 76 explicitly commits this as the desired P1 default. Alternative ("show misleading low number") is worse per audit H4 analysis. <!-- RESOLVED: H1 --> |
| `WellnessDayLog.stressLevel` still gets written with a potentially-misleading label during honest mode (ring UI not gated) | Low | Low | Accepted for P1. Phase 2 should gate `persistTodayWellnessSnapshot` on `!shouldHideScoreForLowConfidence`. See §5e. |

---

## 9. Open Questions (Phase-1-blocking only)

1. **Should the confidence badge also appear on the widget?** Defer. Strategy §4 widget compatibility says "`WidgetStressData.factors: [WidgetStressFactor]` shape stable through P4". Adding a `confidence: String` field is additive and cheap, but not in Phase 1 scope. Explicit defer: P4 `U4` calibrating state supersedes this.
2. ~~**Minimum-coverage "honest mode"**~~ **RESOLVED (H1)** — Honest mode is now part of Phase 1 (Task 15). Threshold is `<2` factors per strategy §3 line 76 (the `<3` in strategy §4 line 236 is the strategy's internal inconsistency, resolved here by picking the explicit Phase 1 decision-point spec). <!-- RESOLVED: H1 + L6 -->
3. **Should `StressReading` gain an `algorithmVersion: String` field in Phase 1** to enable the calendar/sparkline to distinguish pre/post-P1 scores? **Deferred to Phase 2** per §5d / M7. Additive SwiftData fields are cheap but schema-migration semantics deserve a design pass that is not in P1 scope.

Everything else from the brainstorm's Open Questions list (Q1–Q6) is a Phase 2+ concern per strategy §3 and is intentionally out of scope.

---

## 10. File Touch Summary

| File | Change type | Tasks |
|---|---|---|
| `WellPlate/Core/Services/StressScoring.swift` | Modify — rewrite 4 factor fns, add `Weights` enum | 1, 2, 3, 4 |
| `WellPlate/Models/StressModels.swift` | Comment-only — update `maxScore` line-78 comment from `// always 25` to explicit weight list; no behavior change | 5 (sub), 12 (read-only) |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | Modify — builders accept `Double?`, add nested `Confidence` enum + `factorCoverage`/`stressConfidence`/`shouldHideScoreForLowConfidence` props, honest-mode log-skip guard, DEBUG `/25` log-text refresh | 5, 6, 7, 15 |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | Modify — add confidence badge to score header; introduce `scoreHero` branch for honest-mode placeholder | 8, 15 |
| `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift` | Modify — replace `/25` text with `/maxScore` | 5 (sub) |
| `WellPlate/Features + UI/Stress/Views/DietDetailView.swift` | Modify — replace `" /25"` with `" /\(Int(factor.maxScore))"` at line 82 | 5 (sub) <!-- RESOLVED: H3 --> |
| `WellPlate/Features + UI/Stress/Views/ScreenTimeDetailView.swift` | Modify — replace `" /25"` with `" /\(Int(factor.maxScore))"` at line 80 | 5 (sub) <!-- RESOLVED: H3 --> |
| `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift` | Modify — 4× `?? 0` at lines 75–80 for `Double?` return types | 14 <!-- RESOLVED: C1 --> |
| `WellPlate/Core/AppConfig.swift` | Modify — add `stressAlgorithmV2` flag, add log line (no emoji) | 10 |
| `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` | Modify — add `.sparse` factory; zero out last entry of stepsHistory/energyHistory and empty currentDayLogs | 11 |
| `WellPlateWidget/Views/SharedWidgetViews.swift` | Modify — bar fraction + `/N` text at lines 104, 109, 124 | 5 (sub) |
| `WellPlateWidget/Views/StressLargeView.swift` | Modify — ensure contribution text uses `maxScore` if it renders one | 5 (sub) |
| `WellPlate/Widgets/SharedStressData.swift` | Modify — placeholder `maxScore` literal updates at :68-71; comment at :95 | 5 (sub) <!-- RESOLVED: M5 --> |
| `WellPlate/Features + UI/Tab/ProfileView.swift` | Modify — `MiniFactorBar` fraction at :1433, :1435; `/25` label at :1445 | 5 (sub) <!-- RESOLVED: L3 — all 3 lines always listed together --> |

**Total:** 13 files modified, 0 new files. Scope matches strategy §6 "Existing Files — Touch Summary" row for Phase 1 plus the cosmetic-sweep files called out in §5a, plus the audit-added `StressDeepDiveSection`, `DietDetailView`, `ScreenTimeDetailView`, and `SharedStressData`.

---

## 11. Honest-mode × Confidence-badge Interaction — **new section**

This section documents the interaction that H1 (restoring honest mode) creates with Task 7 / Task 8 (the confidence badge).

**Coverage → UI state mapping:**

| `factorCoverage` | `stressConfidence` | What user sees on Stress hero |
|---|---|---|
| 4 | `.high` | Big score + "High confidence · 4/4 factors" badge |
| 3 | `.medium` | Big score + "Medium confidence · 3/4 factors" badge |
| 2 | `.medium` | Big score + "Medium confidence · 2/4 factors" badge |
| 1 | `.low` (computed but not rendered) | **Honest-mode placeholder:** "Log more to see your stress score" |
| 0 | `.low` (computed but not rendered) | **Honest-mode placeholder** |

**Consequences:**
- The `.low` case's `label` ("Low confidence") and `systemImage` are **never rendered** in Phase 1 — honest mode pre-empts them. We keep the `.low` case for API completeness (e.g., if a future surface wants to render a different treatment at low coverage).
- `stressConfidence` stays a 3-case enum rather than being collapsed to 2 cases — this keeps the Task 7 code maintainable and preserves the option for Phase 2 to add e.g. a "Low" indicator elsewhere (widget corner badge).
- `StressReading` logging is **gated on `!shouldHideScoreForLowConfidence`**, so weekly sparkline / WellnessCalendar never record a misleading low-coverage day. Users returning to the app after a week of low logging will see gaps, not ghosts.
- Widget behavior: the widget reads `totalScore` directly from `WidgetStressData`. In Phase 1 the widget does NOT know about honest mode — it will still render a number. This is accepted as a small inconsistency for P1; addressing it requires adding a `isHonestMode: Bool` field to `WidgetStressData` which is strategy-committed Phase 4 work (`U4 calibrating banner`).

<!-- RESOLVED: H1 + L6 — interaction explicitly documented so re-audit can verify honest mode does not create a hidden regression in the badge logic -->

---

**Next step:** Run `/develop checklist` against this resolved plan to produce the step-by-step implementation checklist. No further audit passes required — all 🔴/🟠 findings resolved; 🟡/⚪ findings patched or explicitly accepted.
