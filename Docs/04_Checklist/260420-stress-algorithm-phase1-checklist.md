# Implementation Checklist: Stress Algorithm — Phase 1 (Foundation & Quick Wins)

**Source Plan:** [260420-stress-algorithm-phase1-plan-RESOLVED.md](../02_Planning/Specs/260420-stress-algorithm-phase1-plan-RESOLVED.md)
**Strategy:** [260420-stress-algorithm-improvements-strategy.md](../02_Planning/Specs/260420-stress-algorithm-improvements-strategy.md) §3 "Phase 1"
**Audit reference:** [260420-stress-algorithm-phase1-plan-audit.md](../03_Audits/260420-stress-algorithm-phase1-plan-audit.md)
**Date:** 2026-04-20

---

## Line-anchor drift notes

These lines were validated against current source on 2026-04-20 before writing this checklist. Where the plan cited a line that drifted, the current anchor is used here.

| Plan cite | Current anchor | Note |
|---|---|---|
| `StressView.swift:298-312` (scoreHeader) | `StressView.swift:300-312` | 2-line drift; body unchanged |
| `StressView.swift:239-243` (scaleEffect) | `StressView.swift:242-243` | Same code, fewer lines |
| `StressViewModel.swift:615` (refreshScreenTimeFactor) | `StressViewModel.swift:615-655` | confirmed |
| `StressViewModel.swift:549-613` (builders) | `StressViewModel.swift:549-613` | confirmed |
| `StressViewModel.swift:232-253` (loadData call sites) | `StressViewModel.swift:234-253` | small drift |
| `StressViewModel.swift:238, 246, 349, 352, 641` (DEBUG `/25`) | `:238, 246, 349, 352, 641` | all 5 present |
| `StressModels.swift:78` (`// always 25`) | `:78` | confirmed |
| `StressModels.swift:131` (preview `maxScore: 25`) | `:131` | confirmed (in `.neutral`) |
| `StressDeepDiveSection.swift:72-82` | `:72-82` confirmed (4 call sites at lines 75, 76, 79, 80) | |
| `DietDetailView.swift:82` | `:82` confirmed | |
| `ScreenTimeDetailView.swift:80` | `:80` confirmed | |
| `SharedWidgetViews.swift:104, 109, 124` | all 3 confirmed | |
| `SharedStressData.swift:68-71, 95` | all confirmed | |
| `ProfileView.swift:1433, 1435, 1445` | all 3 confirmed | |
| `StressFactorCardView.swift:46` | confirmed | |
| `StressLargeView.swift` (cited in §10) | Grep shows no `/25` or `maxScore` literals | **No edit needed in StressLargeView.** Keep in smoke check only. |
| `AppConfig.swift:14-22` (Keys enum) | `:14-22` confirmed | |
| `AppConfig.swift:29-46` (mockMode pattern) | `:29-46` confirmed | |
| `AppConfig.swift:151-156` (logCurrentMode lines) | `:151-156` confirmed | |

---

## Pre-Implementation

- [ ] **Step 0.1 — Read the RESOLVED plan front-to-back**
  - File: `Docs/02_Planning/Specs/260420-stress-algorithm-phase1-plan-RESOLVED.md`
  - Verify: You can articulate the 15 tasks, the 4 factor weights (35/25/20/20), and the honest-mode threshold (`<2` factors).

- [ ] **Step 0.2 — Create feature branch**
  - Change: `git checkout -b stress/phase1-foundation`
  - Verify: `git status` shows branch `stress/phase1-foundation`, working tree clean (except `.vscode/launch.json` already untracked).

- [ ] **Step 0.3 — Baseline build sanity (all 4 targets green)**
  - Commands (run each; all must succeed BEFORE any code changes):
    - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
    - `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
    - `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
    - `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: All 4 emit `** BUILD SUCCEEDED **`.

- [ ] **Step 0.4 — Clean-slate marker commit**
  - Change: `git commit --allow-empty -m "chore(stress-p1): baseline before Phase 1 foundation work"`
  - Verify: `git log -1 --oneline` shows the marker commit.

- [ ] **Step 0.5 — Verify referenced files exist (drift sanity)**
  - Files to confirm on disk:
    - `WellPlate/Core/Services/StressScoring.swift`
    - `WellPlate/Core/AppConfig.swift`
    - `WellPlate/Models/StressModels.swift`
    - `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
    - `WellPlate/Features + UI/Stress/Views/StressView.swift`
    - `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift`
    - `WellPlate/Features + UI/Stress/Views/DietDetailView.swift`
    - `WellPlate/Features + UI/Stress/Views/ScreenTimeDetailView.swift`
    - `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift`
    - `WellPlate/Features + UI/Tab/ProfileView.swift`
    - `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
    - `WellPlate/Widgets/SharedStressData.swift`
    - `WellPlateWidget/Views/SharedWidgetViews.swift`
  - Verify: All 13 files found.

---

## Phase A — Scoring core (Tasks 1–4)

### 1.1 — Add `Weights` enum to `StressScoring`

- [ ] **Step 1.1.1 — Insert `Weights` nested enum**
  - File: `WellPlate/Core/Services/StressScoring.swift:9` (just after `enum StressScoring {`)
  - Change: Add the `Weights` enum from plan Task 1 with `sleep = 35 / exercise = 25 / diet = 20 / screenTime = 20`.
  - Verify: Build WellPlate scheme → compile succeeds; no other sites broken yet because the enum is unused.

**Commit point:** after 1.1.1 → `git commit -m "feat(stress-p1): introduce StressScoring.Weights (Task 1)"`

### 2.1 — Migrate `exerciseScore` (Task 2)

- [ ] **Step 2.1.1 — Change `exerciseScore` return type to `Double?` and rewrite body**
  - File: `WellPlate/Core/Services/StressScoring.swift:13-20`
  - Change: Return `Double?`; return `nil` when both `steps` and `energy` are nil; use `Weights.exercise` in place of literal `25.0`; change step divisor from `10_000.0` → `7_000.0` (Q3).
  - Verify: Build WellPlate scheme → **expected to fail** at `StressViewModel.swift:234` (caller stores result in non-optional `Double`) and possibly `StressDeepDiveSection.swift:75`. Note the errors; do not fix yet.

### 3.1 — Migrate `sleepScore` (Task 3)

- [ ] **Step 3.1.1 — Rewrite `sleepScore` signature to `Double?` + new duration curve**
  - File: `WellPlate/Core/Services/StressScoring.swift:24-49`
  - Change: Replace body per plan Task 3 — nil on missing summary; duration curve returns a fraction (`durationFraction`) in 0…0.80, multiplied by `Weights.sleep`; deep-sleep bonus = `clamp(deepRatio / 0.18) * (max * 0.20)` (up to 20% of max).
  - Verify: Inline read only — no build yet (will rebuild after Step 3.1.2).

- [ ] **Step 3.1.2 — Add 45-minute deep-sleep floor cap**
  - File: `WellPlate/Core/Services/StressScoring.swift` (inside the new `sleepScore` body)
  - Change: After the bonus, compute `deepMinutes = s.deepHours * 60.0` and if `<45` cap `score = min(score, max * 0.70)`. Include the inline NOTE comment citing M1 + Research §3b.
  - Verify: Build → **still expected to fail** at remaining call sites. Verify the sleep function itself compiles on its own.

### 4.1 — Migrate `dietScore` (Task 4a)

- [ ] **Step 4.1.1 — Rewrite `dietScore` to return `Double?`**
  - File: `WellPlate/Core/Services/StressScoring.swift:53-68`
  - Change: `guard hasLogs else { return nil }`; replace hard-coded `25.0` with `Weights.diet` (= 20); preserve netBalance math exactly.
  - Verify: Inline read only.

### 4.2 — Migrate `screenTimeScore` (Task 4b) + defer Q5

- [ ] **Step 4.2.1 — Rewrite `screenTimeScore` to return `Double?` at new ceiling**
  - File: `WellPlate/Core/Services/StressScoring.swift:72-76`
  - Change: `guard let h = hours else { return nil }`; return `min(Weights.screenTime, h * (Weights.screenTime / 8.0))` (i.e., 2.5 pts/hour capped at 20 at 8h).
  - Verify: Inline read only.

- [ ] **Step 4.2.2 — Add Phase-2 forward-reference comment (Task 9 deferral)**
  - File: `WellPlate/Core/Services/StressScoring.swift` (immediately above `screenTimeScore`)
  - Change: Insert `// Q5 evening ×1.5 multiplier ships in StressScoringV2 — requires hourly-bucket refactor of ScreenTimeManager, tracked in Phase 2.`
  - Verify: Comment present; no parameter `eveningHours` exists anywhere (grep `eveningHours` in the project returns zero hits).

- [ ] **Step 4.2.3 — Build expectation after signature sweep**
  - Commands: `xcodebuild ... -scheme WellPlate build`
  - Verify: Build **fails** with errors in `StressViewModel.swift` (lines ~234, ~242, ~328, ~344, ~619, ~632) and `StressDeepDiveSection.swift` (lines ~75, ~76, ~79, ~80). Capture the error list; these are the consumer migration targets for Phase B.

**Do not commit yet — the tree is broken and will be fixed inside Phase B.**

---

## Phase B — Consumer migrations (Tasks 5, 6, 14) → restore a clean build

### 5.1 — Migrate `StressViewModel` call sites in `loadData()`

- [ ] **Step 5.1.1 — Update `exerciseScore` call site type**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:234`
  - Change: `let exerciseScore: Double? = StressScoring.exerciseScore(steps: steps, energy: energy)`.
  - Verify: Compiler error at this line disappears; error at :235 (builder signature) may appear — handled in 5.1.3.

- [ ] **Step 5.1.2 — Update `sleepScore` call site type**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:242`
  - Change: `let sleepScore: Double? = StressScoring.sleepScore(summary: sleepSummary)`.
  - Verify: Compiler error at this line disappears.

- [ ] **Step 5.1.3 — Update `buildExerciseFactor` signature to accept `Double?`**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:549-573`
  - Change: `private func buildExerciseFactor(score: Double?, steps: Double?, energy: Double?) -> StressFactorResult`. Replace `let hasData = steps != nil || energy != nil` with `let hasData = score != nil`. Coalesce `score ?? 0` when passing to the constructor. Replace `maxScore: 25` with `maxScore: StressScoring.Weights.exercise`.
  - Verify: WellPlate compiles past line 549; builder emits the right weight into `maxScore`.

- [ ] **Step 5.1.4 — Update `buildSleepFactor` signature**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:575-592`
  - Change: `score: Double?`; `hasData = score != nil`; `maxScore: StressScoring.Weights.sleep`; coalesce `score ?? 0` into `StressFactorResult`. The existing `summary` parameter stays for the status text.
  - Verify: Compiler error at this builder disappears.

- [ ] **Step 5.1.5 — Update `buildDietFactor` signature and both call sites in `refreshDietFactor`**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:594-613` (builder), `:328` (mock branch), `:344` (live branch)
  - Change: Builder takes `score: Double?`; `hasData = score != nil`; `maxScore: StressScoring.Weights.diet`. At both call sites the existing local `score` is already a `Double?` now — pass it through unchanged. Status/detail wording unchanged.
  - Verify: `refreshDietFactor()` compiles; builder compiles.

- [ ] **Step 5.1.6 — Update `refreshScreenTimeFactor` builder constructions**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:615-655` (three `StressFactorResult(...)` constructions)
  - Change: Replace all `maxScore: 25` → `maxScore: StressScoring.Weights.screenTime`. The mock branch (:619) and auto branch (:632) unwrap screen-time score (now `Double?`) with `?? 0` when storing in the factor struct. The "none" branch stays the same (`score: 0, hasValidData: false`).
  - Verify: WellPlate scheme builds clean at this file's scope.

- [ ] **Step 5.1.7 — Update DEBUG `/25` log literals (5 occurrences)**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:238, 246, 349, 352, 641`
  - Change each line to print the factor's actual weight:
    - `:238` exercise → `"/\(Int(StressScoring.Weights.exercise))"`
    - `:246` sleep → `"/\(Int(StressScoring.Weights.sleep))"`
    - `:349, :352` diet → `"/\(Int(StressScoring.Weights.diet))"`
    - `:641` screen time → `"/\(Int(StressScoring.Weights.screenTime))"`
    - Also unwrap `exerciseScore` and `sleepScore` for `fmt2(...)` if they are now `Double?` — use `fmt2(exerciseScore ?? 0)` (same for sleepScore).
  - Verify: DEBUG build succeeds; log output on next run shows correct denominators.

### 5.2 — `/25` cosmetic sweep (Task 5 sub-list — 7 files)

- [ ] **Step 5.2.1 — `SharedWidgetViews.swift:104`**
  - File: `WellPlateWidget/Views/SharedWidgetViews.swift:104`
  - Change: `return min(factor.contribution / 25.0, 1.0)` → `return min(factor.contribution / factor.maxScore, 1.0)` (guard at :103 stays).
  - Verify: Line reads `factor.maxScore`, not `25.0`.

- [ ] **Step 5.2.2 — `SharedWidgetViews.swift:109`**
  - File: `WellPlateWidget/Views/SharedWidgetViews.swift:109`
  - Change: `let stressRatio = min(max(factor.contribution / 25.0, 0), 1)` → `... factor.contribution / factor.maxScore ...`.
  - Verify: Widget build succeeds.

- [ ] **Step 5.2.3 — `SharedWidgetViews.swift:124`**
  - File: `WellPlateWidget/Views/SharedWidgetViews.swift:124`
  - Change: `Text("\(Int(factor.contribution))/25")` → `Text("\(Int(factor.contribution))/\(Int(factor.maxScore))")`.
  - Verify: Widget Xcode preview renders "X/35" for Sleep, "X/25" for Exercise, "X/20" for Diet and Screen after Step 5.2.10.

- [ ] **Step 5.2.4 — `ProfileView.swift:1433`**
  - File: `WellPlate/Features + UI/Tab/ProfileView.swift:1433`
  - Change: `private var fraction: Double { min(factor.contribution / 25.0, 1.0) }` → `min(factor.contribution / factor.maxScore, 1.0)`.
  - Verify: Reads `factor.maxScore`.

- [ ] **Step 5.2.5 — `ProfileView.swift:1435`**
  - File: `WellPlate/Features + UI/Tab/ProfileView.swift:1435`
  - Change: `let ratio = min(max(factor.contribution / 25.0, 0), 1)` → same with `factor.maxScore`.
  - Verify: Reads `factor.maxScore`.

- [ ] **Step 5.2.6 — `ProfileView.swift:1445`**
  - File: `WellPlate/Features + UI/Tab/ProfileView.swift:1445`
  - Change: `Text("\(Int(factor.contribution))/25")` → `Text("\(Int(factor.contribution))/\(Int(factor.maxScore))")`.
  - Verify: Profile mini-bar labels show weighted denominators.

- [ ] **Step 5.2.7 — `StressFactorCardView.swift:46`**
  - File: `WellPlate/Features + UI/Stress/Views/StressFactorCardView.swift:46`
  - Change: `Text("\(Int(factor.score))/25")` → `Text("\(Int(factor.score))/\(Int(factor.maxScore))")`.
  - Verify: Stress detail card pill shows weighted denominator.

- [ ] **Step 5.2.8 — `DietDetailView.swift:82`**
  - File: `WellPlate/Features + UI/Stress/Views/DietDetailView.swift:82`
  - Change: `+ Text(" /25")` → `+ Text(" /\(Int(factor.maxScore))")`.
  - Verify: Diet detail sheet header shows `/20` post-ship.

- [ ] **Step 5.2.9 — `ScreenTimeDetailView.swift:80`**
  - File: `WellPlate/Features + UI/Stress/Views/ScreenTimeDetailView.swift:80`
  - Change: `+ Text(" /25")` → `+ Text(" /\(Int(factor.maxScore))")`.
  - Verify: Screen Time detail sheet header shows `/20`.

- [ ] **Step 5.2.10 — `SharedStressData.swift:68-71` placeholder weights**
  - File: `WellPlate/Widgets/SharedStressData.swift:68-71`
  - Change: Update the 4 `WidgetStressFactor` placeholder entries to use correct weights:
    - Exercise → `maxScore: 25`
    - Sleep → `maxScore: 35`
    - Diet → `maxScore: 20`
    - Screen Time → `maxScore: 20`
  - Verify: Xcode preview on the widget scales the 4 bars against their correct maxes.

- [ ] **Step 5.2.11 — `SharedStressData.swift:95` comment refresh**
  - File: `WellPlate/Widgets/SharedStressData.swift:95`
  - Change: `let maxScore: Double        // 25` → `let maxScore: Double        // per-factor weight (sleep 35, exercise 25, diet 20, screen 20)`.
  - Verify: Doc-comment present.

- [ ] **Step 5.2.12 — `StressModels.swift:78` comment refresh**
  - File: `WellPlate/Models/StressModels.swift:78`
  - Change: `let maxScore: Double       // always 25` → `let maxScore: Double       // varies per factor (sleep 35, exercise 25, diet 20, screen 20)`.
  - Verify: Comment updated; no behavior change.

- [ ] **Step 5.2.13 — Grep sanity sweep**
  - Change: `grep -rn "/25" "WellPlate/Features + UI/Stress" "WellPlate/Features + UI/Tab/ProfileView.swift" "WellPlate/Widgets" "WellPlateWidget" "WellPlate/Models/StressModels.swift"` — confirm no literal `/25.0` fraction or `"/25"` string label remains outside of the preview fixture at `StressModels.swift:131` (which is the neutral Exercise stub and intentionally keeps `maxScore: 25`) and the DEBUG logs handled in 5.1.7.
  - Verify: No unexpected hits.

### 5.3 — Task 6 verification (no code change)

- [ ] **Step 5.3.1 — Read `totalScore` property and confirm no weight-redistribution math was added**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:79-84`
  - Change: None — verify the property is still `exerciseFactor.stressContribution + sleepFactor.stressContribution + dietFactor.stressContribution + screenTimeFactor.stressContribution`.
  - Verify: Read-through only; nothing changed.

### 14 — `StressDeepDiveSection` call-site migration (Task 14)

- [ ] **Step 14.1 — Add `?? 0` to 4 `StressScoring.*` calls in `factorDecompItems`**
  - File: `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift:75-80`
  - Change each of the 4 lines:
    - `:75` `let ex = StressScoring.exerciseScore(steps: ..., energy: ...)` → append `?? 0`
    - `:76-78` `let sl = StressScoring.sleepScore(summary: ...)` → append `?? 0` at end of the expression
    - `:79` `let dt = StressScoring.dietScore(protein: ..., hasLogs: ...)` → append `?? 0`
    - `:80` `let sc = StressScoring.screenTimeScore(hours: nil)` → append `?? 0`
  - Verify: Tuple component types stay `Double` (non-optional); file compiles.

### Full build after Phase B

- [ ] **Step 5.B — All 4 target builds must now be clean**
  - Commands:
    - `xcodebuild ... -scheme WellPlate build`
    - `xcodebuild ... -scheme ScreenTimeMonitor build`
    - `xcodebuild ... -scheme ScreenTimeReport build`
    - `xcodebuild ... -target WellPlateWidget build`
  - Verify: All 4 emit `** BUILD SUCCEEDED **`.

**🟢 Checkpoint CP1 — shippable state reached.** Commit:
`git commit -am "feat(stress-p1): scoring returns Double? with Weights enum; all consumers migrated (Tasks 1–6, 14)"`

---

## Phase C — Confidence badge (Tasks 7, 8)

### 7.1 — Nested `Confidence` enum + computed properties

- [ ] **Step 7.1.1 — Add `Confidence` nested enum**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` (at end of file, before closing brace)
  - Change: Add an `extension StressViewModel { enum Confidence: String { case low, medium, high; var label: String {...}; var systemImage: String {...} } }` per plan Task 7.
  - Verify: Nested type resolves as `StressViewModel.Confidence`; build succeeds.

- [ ] **Step 7.1.2 — Add `factorCoverage` and `stressConfidence` computed properties**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` (inside the class, next to other computed properties around line 79-95)
  - Change: Add
    - `var factorCoverage: Int { allFactors.filter(\.hasValidData).count }`
    - `var stressConfidence: StressViewModel.Confidence { switch factorCoverage { case 4: .high; case 2, 3: .medium; default: .low } }`
  - Verify: Build succeeds; new properties are callable from SwiftUI views.

- [ ] **Step 7.1.3 — Add `shouldHideScoreForLowConfidence` property**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` (same vicinity)
  - Change: `var shouldHideScoreForLowConfidence: Bool { factorCoverage < 2 }` (strategy §3 line 76 threshold).
  - Verify: Build succeeds.

### 8.1 — Render confidence badge in `StressView`

- [ ] **Step 8.1.1 — Restructure `scoreHeader` from HStack to VStack**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift:300-312`
  - Change: Wrap the existing number+"/100" `HStack` inside a `VStack(alignment: .leading, spacing: 6)` and add `confidenceBadge` as the second child (exactly per plan Task 8 code block).
  - Verify: Score area compiles; Xcode preview or simulator renders the number with the new badge beneath.

- [ ] **Step 8.1.2 — Add `confidenceBadge` computed view**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (new `private var confidenceBadge: some View` adjacent to `scoreHeader`)
  - Change: Body per plan Task 8 — HStack with `Image(systemName: viewModel.stressConfidence.systemImage)` at `size: 13 semibold`, and `Text("\(viewModel.stressConfidence.label) · \(viewModel.factorCoverage)/4 factors")` at `size: 13 medium rounded`; wrapped in a Capsule `Color(.systemGray6)` background. Font bump (M2) already baked in.
  - Verify: WellPlate scheme builds; confidence badge visible in Xcode preview.

- [ ] **Step 8.1.3 — Confirm scaleEffect anchor still works (L4)**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift:239-243`
  - Change: None. Confirm `.scaleEffect(scoreAppeared ? 1 : 0.93, anchor: .topLeading)` still references the VStack.
  - Verify: Simulator: navigate to Stress tab; on first entry, score+badge animates in together anchored to top-left, no visual drift.

### Build after Phase C

- [ ] **Step 8.B — 4-target build**
  - Commands: all 4 `xcodebuild` commands.
  - Verify: All clean.

**🟢 Checkpoint CP2 — confidence badge live.** Commit:
`git commit -am "feat(stress-p1): StressViewModel.Confidence + badge on StressView (Tasks 7–8)"`

---

## Phase D — Feature flag + mock parity (Tasks 10, 11, 12)

### 10.1 — `AppConfig.stressAlgorithmV2` placeholder

- [ ] **Step 10.1.1 — Add UserDefaults key**
  - File: `WellPlate/Core/AppConfig.swift:14-22` (inside `private enum Keys`)
  - Change: `static let stressAlgorithmV2 = "app.stress.algorithmV2"`.
  - Verify: Key compiles; no other site references it yet.

- [ ] **Step 10.1.2 — Add `stressAlgorithmV2` computed property**
  - File: `WellPlate/Core/AppConfig.swift` (add under `mockMode` block, around line 46)
  - Change: Implement per plan Task 10 — DEBUG-gated `get` checking `UserDefaults.standard.object(forKey:) != nil` else `false`; DEBUG `set` writes to UserDefaults and logs via `WPLogger.app.info`; release build always returns `false`.
  - Verify: Release (non-DEBUG) path returns `false` unconditionally.

- [ ] **Step 10.1.3 — Add log line to `logCurrentMode()`**
  - File: `WellPlate/Core/AppConfig.swift:151-156`
  - Change: Append to the `lines:` array: `"Stress v2  : \(stressAlgorithmV2 ? "ENABLED" : "disabled")"` (no emoji per L5).
  - Verify: Simulator run: `AppConfig.shared.logCurrentMode()` prints the new line once at app launch.

- [ ] **Step 10.1.4 — Build**
  - Commands: `xcodebuild ... -scheme WellPlate build`
  - Verify: Clean; no side effects elsewhere (grep for `stressAlgorithmV2` should only hit AppConfig.swift).

### 11.1 — `StressMockSnapshot.sparse` factory (Task 11)

- [ ] **Step 11.1.1 — Add `sparse` static + `makeSparse()`**
  - File: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` (after `.default` at line 49)
  - Change: Insert the `static let sparse` and `private static func makeSparse()` factory exactly per plan Task 11, including the doc comment. The factory overrides the last entry of `stepsHistory` and `energyHistory` to `value: 0` and sets `currentDayLogs: []`.
  - Verify: Build WellPlate scheme — `.sparse` compiles; struct field list matches `makeDefault()`'s initializer call.

- [ ] **Step 11.1.2 — Temporarily swap `StressView` preview to `.sparse`**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (preview block at bottom)
  - Change: In `#Preview`, change `StressMockSnapshot.default` to `StressMockSnapshot.sparse` (one-line change).
  - Verify: Xcode Preview renders: exercise + diet cards grayed out; sleep and screen-time cards active; confidence badge reads `Medium confidence · 2/4 factors`; total hero reads approximately `14/100`.

- [ ] **Step 11.1.3 — Revert preview to `.default`**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (same preview block)
  - Change: Change back to `StressMockSnapshot.default`.
  - Verify: Preview now reads `19/100 · High confidence · 4/4 factors`.

### 12.1 — StressLevel bands ripple (Task 12)

- [ ] **Step 12.1.1 — Confirm `StressLevel` band thresholds unchanged**
  - File: `WellPlate/Models/StressModels.swift:19-27`
  - Change: None — verify the switch still reads `..<21 / 21..<41 / 41..<61 / 61..<81 / default`.
  - Verify: No `.balanced` case, no threshold edit. Phase 1 exit criterion for §7 "bands math" is trivially met.

### Build after Phase D

- [ ] **Step D.B — 4-target build**
  - Commands: all 4 `xcodebuild` commands.
  - Verify: All clean.

**🟢 Checkpoint CP3 — mock parity + flag scaffolding complete.** Commit:
`git commit -am "feat(stress-p1): v2 flag placeholder + .sparse mock + /25 sweep (Tasks 10–12)"`

---

## Phase E — Honest mode (Task 15)

### 15.1 — Honest-mode placeholder view

- [ ] **Step 15.1.1 — Add `honestModePlaceholder` computed view to `StressView`**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (adjacent to `scoreHeader` / `confidenceBadge`)
  - Change: Add `private var honestModePlaceholder: some View { ... }` with a `VStack(alignment: .leading, spacing: 8)` containing an SF Symbol icon, a `.title3 .semibold` headline "Log more to see your stress score", and a `.footnote .regular` subtitle "We need at least 2 of 4 factors...". Use existing `.r(...)` font extension per project conventions.
  - Verify: Placeholder previews without layout overflow; uses the codebase's `.r(...)` font helpers.

- [ ] **Step 15.1.2 — Add `scoreHero` branching wrapper**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift`
  - Change: Add `@ViewBuilder private var scoreHero: some View { if viewModel.shouldHideScoreForLowConfidence { honestModePlaceholder } else { scoreHeader } }`.
  - Verify: Property compiles.

- [ ] **Step 15.1.3 — Swap `scoreHeader` → `scoreHero` at call site**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift:239`
  - Change: Replace the one `scoreHeader` reference inside `mainScrollView` with `scoreHero`. Retain all existing modifiers (`.padding(.top, 20)`, `.padding(.horizontal, 20)`, `.opacity`, `.scaleEffect(... anchor: .topLeading)`).
  - Verify: Build succeeds; animation modifiers continue to apply to the wrapper.

### 15.2 — Skip `StressReading` logging in honest mode

- [ ] **Step 15.2.1 — Add honest-mode guard in `logCurrentStress`**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:372` (top of function body, immediately after the `guard !usesMockData else { return }` line)
  - Change: Insert
    ```swift
    guard !shouldHideScoreForLowConfidence else {
        #if DEBUG
        log("⏭  Skipped StressReading log: honest mode (coverage=\(factorCoverage))")
        #endif
        return
    }
    ```
  - Verify: When a 1-factor mock is loaded, the DEBUG log prints the skip line and no `StressReading` row is inserted.

### 15.3 — Validate with a 1-factor mock

- [ ] **Step 15.3.1 — Construct a 1-factor mock inline to smoke-test honest mode**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (preview scratch — do not commit)
  - Change: In the `#Preview`, temporarily build a minimal snapshot with sleep only (override `stepsHistory` and `energyHistory` last-entry to 0, `screenTimeHours: 0` via a local factory, `currentDayLogs: []`). One-liner acceptable: copy `.sparse` factory but also zero out `screenTimeHours` via a local override.
  - Verify: Preview hides the score hero and instead displays the "Log more to see your stress score" placeholder.

- [ ] **Step 15.3.2 — Revert preview scratch**
  - File: same
  - Change: Restore `StressMockSnapshot.default`.
  - Verify: Preview renders normal hero + High confidence.

### Build after Phase E

- [ ] **Step E.B — 4-target build**
  - Commands: all 4 `xcodebuild` commands.
  - Verify: All clean.

**🟢 Checkpoint CP4 — honest mode shippable.** Commit:
`git commit -am "feat(stress-p1): honest-mode placeholder + StressReading log skip (Task 15)"`

---

## Post-Implementation — Smoke tests, exit-gate verification, final build (Task 13)

### 13.1 — Full 4-target clean build (FINAL)

- [ ] **Step 13.1.1 — Run all 4 builds from a clean derived-data state**
  - Commands:
    - `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
    - `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
    - `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
    - `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: All 4 emit `** BUILD SUCCEEDED **`.

### 13.2 — Manual smoke checklist in the simulator

> ⚠️ **Permission dialogs:** Running in the simulator with mock mode **off** will prompt for HealthKit and potentially Screen Time permission. Grant both (Settings → Privacy → Health → WellPlate, all toggles on; Screen Time permission dialog allows).

- [ ] **Step 13.2.1 — Home tab renders `StressInsightCard`**
  - Change: Launch app; default tab (Home) loads.
  - Verify: `StressInsightCard` displays a readable level label (e.g. "Excellent") and no crash.

- [ ] **Step 13.2.2 — Stress tab with `.default` mock → 4/4 high confidence**
  - Change: Enable mock mode via Profile → Debug → Mock Mode = ON. Navigate to Stress tab.
  - Verify: Hero reads ~"19/100"; badge reads "High confidence · 4/4 factors".

- [ ] **Step 13.2.3 — Stress tab with `.sparse` mock → 2/4 medium confidence**
  - Change: Swap the VM's mock snapshot source to `.sparse` (temporary — via an in-code branch or a one-line edit for the smoke test).
  - Verify: Hero reads ~"14/100"; badge reads "Medium confidence · 2/4 factors"; exercise + diet cards grayed.
  - Revert: change back to `.default`.

- [ ] **Step 13.2.4 — Honest mode: 1-factor mock → placeholder**
  - Change: Use the temporary 1-factor snapshot from Step 15.3.1 or manually zero both history arrays + clear logs + set screenTimeHours to 0.
  - Verify: Hero is replaced by "Log more to see your stress score"; DEBUG console shows `⏭  Skipped StressReading log: honest mode (coverage=1)` (or `=0`).

- [ ] **Step 13.2.5 — Feature flag toggle is a no-op**
  - Change: In DEBUG menu or via debugger, set `AppConfig.shared.stressAlgorithmV2 = true`. Reload Stress tab.
  - Verify: UI identical to `false` state (flag currently reads nowhere). `logCurrentMode()` next launch prints `Stress v2  : ENABLED`.
  - Reset: `stressAlgorithmV2 = false`.

- [ ] **Step 13.2.6 — Widget renders 4 factor bars with correct denominators**
  - Change: Long-press the home screen, add Stress widget (small or medium), pin to home.
  - Verify: Bars render without crash; factor rows read "X/35" (sleep), "X/25" (exercise), "X/20" (diet), "X/20" (screen).

- [ ] **Step 13.2.7 — AI Report → Stress Deep Dive renders**
  - Change: Generate an AI report (Home → Insights → Generate Report, or mock trigger).
  - Verify: `StressDeepDiveSection` renders; factor-decomposition chart draws without crash even when some historical days are missing data (nil-days render as zero-height bars, not absent).

- [ ] **Step 13.2.8 — Detail-view denominators**
  - Change: Tap Diet factor card → open Diet detail. Back; tap Screen Time card → open Screen Time detail.
  - Verify: Diet header reads "X /20"; Screen Time header reads "X /20". No `/25` anywhere in either sheet.

- [ ] **Step 13.2.9 — Mock mode OFF → live HealthKit read**
  - Change: Profile → Debug → Mock Mode = OFF. Relaunch. Grant HealthKit permission if prompted.
  - Verify: `StressViewModel.loadData()` completes without NaN; `totalScore` ∈ [0, 100]; confidence badge reflects real factor coverage.

### 13.3 — Exit gate verification (strategy §3 P1 + RESOLVED plan §7)

- [ ] **Step 13.3.1 — Whipsaw exit gate (H6): `.default` mock**
  - Change: With `.default` mock loaded, read the DEBUG log line `Total stress : XX.XX/100`. Compare against pre-Phase-1 v1 total (≈19.34 per plan §4 math).
  - Verify: `|v1.1_total − 19.34| ≤ 5`. Plan expects v1.1 = 19.19, |Δ| = 0.15.

- [ ] **Step 13.3.2 — Whipsaw exit gate: synthetic "typical active user"**
  - Change: Construct a synthetic fixture (steps=10000, energy=600, sleep=8h/2.5h deep, protein 75g / fiber 22g / fat 50g / carbs 180g, 6h screen). Easiest path: inject via a scratch `StressMockSnapshot` factory (follow `.sparse` pattern).
  - Verify: v1.1 total ≈ 15.7 (per plan §4 math); pre-Phase-1 v1 total ≈ 12.67; `|Δ| ≈ 3.0 ≤ 5`.

- [ ] **Step 13.3.3 — Factor coverage visible in UI**
  - Change: Confirm the confidence badge is rendered below the score in the live simulator with default mock.
  - Verify: Badge visible, readable, and labels match `factorCoverage`.

- [ ] **Step 13.3.4 — Honest mode triggers at `factorCoverage < 2`**
  - Change: Reproduce Step 13.2.4.
  - Verify: Placeholder renders; `StressReading` insert is skipped.

- [ ] **Step 13.3.5 — Mock mode parity (no NaN, no overflow)**
  - Change: Toggle mock ON/OFF a few times; trigger `loadData()` via pull-to-refresh each time.
  - Verify: `totalScore` always finite and in `[0, 100]`. Watch Xcode console for `nan`/`inf`.

- [ ] **Step 13.3.6 — Widget + AI report + home insights regression-free**
  - Change: Re-run Steps 13.2.6 and 13.2.7 and note the home Stress Insight card.
  - Verify: All three surfaces render without crashes; labels/strings unchanged in shape.

- [ ] **Step 13.3.7 — CLAUDE.md architecture rules preserved**
  - Change: Grep verify: `@MainActor final class StressViewModel` still present; `StressScoring` still an `enum` with only `static` functions; no new `.sheet()` on StressView (single `StressSheet` enum-driven sheet pattern preserved).
  - Verify: `grep -n "@MainActor final class StressViewModel" "WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift"` → 1 hit. `grep -n "enum StressScoring" "WellPlate/Core/Services/StressScoring.swift"` → 1 hit.

### 13.4 — Final commit + branch readiness

- [ ] **Step 13.4.1 — Final commit with verified math**
  - Change: `git commit --allow-empty -m "chore(stress-p1): Phase 1 exit gates verified (whipsaw Δ=0.15 on default mock, ~3.0 on synthetic typical user)"`
  - Verify: Commit present; working tree clean.

- [ ] **Step 13.4.2 — Ready for review**
  - Verify: `git log --oneline stress/phase1-foundation ^main` shows the 4 checkpoint commits + the baseline + this final commit.

---

## Task-to-Step Traceability

Every task from the RESOLVED plan maps to ≥1 checklist step below.

| Plan Task | Title | Checklist step(s) |
|---|---|---|
| Task 1 | Weights enum | 1.1.1 |
| Task 2 | exerciseScore → Double? + 7k | 2.1.1 |
| Task 3 | sleepScore → Double? + 45-min floor | 3.1.1, 3.1.2 |
| Task 4 | dietScore + screenTimeScore → Double? | 4.1.1, 4.2.1, 4.2.2 |
| Task 5 | ViewModel builders + /25 sweep | 5.1.1 – 5.1.7, 5.2.1 – 5.2.13 |
| Task 6 | Totalscore pass-through verify | 5.3.1 |
| Task 7 | Confidence enum + props | 7.1.1, 7.1.2, 7.1.3 |
| Task 8 | Badge in StressView | 8.1.1, 8.1.2, 8.1.3 |
| Task 9 | Q5 deferral (no code) | 4.2.2 (comment only) |
| Task 10 | AppConfig.stressAlgorithmV2 flag | 10.1.1, 10.1.2, 10.1.3, 10.1.4 |
| Task 11 | StressMockSnapshot.sparse | 11.1.1, 11.1.2, 11.1.3 |
| Task 12 | StressLevel bands ripple (verify only) | 12.1.1 |
| Task 13 | Build + smoke-test | 0.3, 5.B, 8.B, D.B, E.B, 13.1.1, 13.2.1 – 13.2.9, 13.3.1 – 13.3.7 |
| Task 14 | StressDeepDiveSection ?? 0 migration | 14.1 |
| Task 15 | Honest mode placeholder + log skip | 15.1.1, 15.1.2, 15.1.3, 15.2.1, 15.3.1, 15.3.2 |

**Coverage:** 15/15 tasks mapped; no task left behind.

---

## Exit Gate Verification Summary

Mapping strategy §3 Phase 1 exit gate + RESOLVED §7 exit criteria → this checklist's verify step.

| Exit criterion | Verified in step |
|---|---|
| `StressScoring` 4 fns return `Double?` with Weights | 2.1.1, 3.1.1, 3.1.2, 4.1.1, 4.2.1 |
| `StressViewModel.allFactors` reports `hasValidData = false` on missing data; no phantom 12.5 | 5.1.3 – 5.1.6, 13.2.3 |
| `StressView` confidence badge renders at `coverage ≥ 2` | 8.1.1, 8.1.2, 13.3.3 |
| Honest mode active at `coverage < 2`; no `StressReading` written | 15.1.1 – 15.2.1, 13.3.4 |
| `AppConfig.stressAlgorithmV2` flag exists, DEBUG-toggleable | 10.1.1 – 10.1.4, 13.2.5 |
| `StressMockSnapshot.sparse` exercises missing-data path | 11.1.1, 11.1.2, 13.2.3 |
| All 4 targets compile clean | 0.3, 5.B, 8.B, D.B, E.B, 13.1.1 |
| Widget / Profile / Diet detail / Screen Time detail denominators weighted | 5.2.1 – 5.2.12, 13.2.6, 13.2.8 |
| `StressInsightCard` (home) renders | 13.2.1 |
| `StressDeepDiveSection` (AI report) renders without crash | 14.1, 13.2.7 |
| Whipsaw `|v1.1 − v1| ≤ 5` on default mock + synthetic typical user | 13.3.1, 13.3.2 |
| Mock-mode parity: no NaN, no overflow | 13.3.5 |
| Architecture conventions preserved | 13.3.7 |

---

## Permission dialogs to expect during smoke testing

- **HealthKit** (Step 13.2.9 / any live-mode run): iOS will prompt for read access on steps, energy, sleep analysis, heart rate, resting heart rate, HRV, blood pressure, respiratory rate, and time in daylight. Grant all toggles. May need to re-grant in `Settings → Privacy → Health → WellPlate` if the initial prompt was declined.
- **Screen Time / Family Controls** (Step 13.2.9): `ScreenTimeManager` requests FamilyActivity auth. Accept the dialog. If denied earlier, revoke and re-request via Settings → Screen Time → WellPlate.
- **No new permissions are introduced by Phase 1** — these are pre-existing prompts.
