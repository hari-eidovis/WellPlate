# Implementation Checklist: Stress Algorithm — Phase 1 (Foundation & Quick Wins) — RESOLVED

**Source Plan:** [260420-stress-algorithm-phase1-plan-RESOLVED.md](../02_Planning/Specs/260420-stress-algorithm-phase1-plan-RESOLVED.md)
**Strategy:** [260420-stress-algorithm-improvements-strategy.md](../02_Planning/Specs/260420-stress-algorithm-improvements-strategy.md) §3 "Phase 1"
**Audit reference:** [260420-stress-algorithm-phase1-checklist-audit.md](../03_Audits/260420-stress-algorithm-phase1-checklist-audit.md)
**Date:** 2026-04-20
**Resolution date:** 2026-04-20

---

## Resolution Changelog

Every 🔴/🟠/🟡/⚪ finding from the audit is addressed below. Grep for `[resolves: <ID>]` in the body to trace resolutions inline.

| ID | Sev | Finding | Resolution |
|---|---|---|---|
| C1 | 🔴 | Step 5.1.6 cites wrong `refreshScreenTimeFactor` anchors; hides 3rd builder (none-branch) | Rewrote Step 5.1.6 with verified anchors `:621-625` / `:634-638` / `:646-650`. All 3 `maxScore: 25` sites enumerated explicitly (including none-branch). Anchors verified by re-reading source file. |
| C2 | 🔴 | Step 5.1.7 under-counts `/25` tokens (5 lines × 2 tokens = 10, not 5) | Re-grepped `StressViewModel.swift`. Rewrote 5.1.7 as a table listing each line + both tokens per line + replacement denominator. Updated drift table. 5.2.13 grep sweep expectation aligned: post-sweep `/25` hits in StressViewModel.swift must be zero. |
| C3 | 🔴 | Step 13.3.1 v1 baseline `19.34` vs audit math `18.6` discrepancy unresolved | Added pre-Phase-A live-capture step **0.6** that records the ACTUAL `Total stress : XX.XX/100` from the DEBUG log before any scoring changes. Step 13.3.1 now references this captured number instead of a plan-derived literal. |
| H1 | 🟠 | `StressLargeView.swift` in plan §10 touch list but no checklist coverage | Added Step 13.2.6.1 smoke test: add Stress Large widget variant and verify it renders post-Phase-D. Updated traceability table. |
| H2 | 🟠 | Plan snippets show `scaleEffect(... 0.85)` but live source is `0.93` | Re-read `StressView.swift:243`. Updated Steps 8.1.3 and 15.1.3 to reference the live `0.93` value and warn against copying plan's `0.85` snippet verbatim. Drift table note added. |
| H3 | 🟠 | Step 5.1.7 `fmt2(score)` at `:349` breaks when `score` becomes `Double?` | Explicit optional-unwrap checklist added inside new Step 5.1.7 table: every `fmt2(X)` where X is now `Double?` needs `fmt2(X ?? 0)`. Lines `:238`, `:246`, `:349`, `:352`, `:641` all spell this out. |
| H4 | 🟠 | Step 13.3.2 synthetic fixture v1 total `12.67` contradicts re-derived `13.0` | Step 13.3.2 reworded: capture live v1 total for synthetic fixture from DEBUG log (per C3 pattern), and relaxed assertion to `|Δ| ≤ 5` (the exit gate itself) rather than hard-coding `12.67`. Derivation footnote added. |
| M1 | 🟡 | Phase A build-break window not explicitly flagged for CI | Added warning banner at top of Phase A header. |
| M2 | 🟡 | Drift table says `sleepScore` has 4 call sites at flat line numbers; actually spans 3 lines | Drift-table row corrected: `call sites at :75, :76-78, :79, :80 (sleepScore spans 3 lines)`. |
| M3 | 🟡 | Step 15.2.1 off-by-2 on line anchor (`:372` is signature, not guard) | Corrected to `:373-374` with explicit "after the guard !usesMockData else { return } line at :373". |
| M4 | 🟡 | Step 5.2.13 exception list mentions `StressModels.swift:131` which doesn't match `/25` grep | Clarified: `StressModels.swift:131` has `maxScore: 25` (no `/25` substring) — not a grep hit; exception note removed from the `/25` sweep clause, kept as a separate "intentional literal retained" note. |
| M5 | 🟡 | Step 11.1.1 says "after `.default` at line 49" but `.default` IS line 49 | Corrected to "insertion begins around line 51 (after the `.default` one-line static let at `:49` and a blank line)". |
| M6 | 🟡 | Steps 7.1.1–7.1.3 are ambiguous about class vs file scope | Explicit scope spelled out in each sub-step: 7.1.1 = `extension StressViewModel { ... }` after class closing brace; 7.1.2/7.1.3 = inside class body adjacent to `totalScore`/`stressLevel`. |
| M7 | 🟡 | Step 10.1.3 mixed-case "ENABLED/disabled" is intentional but not explained | One-line callout added citing plan L5 resolution. |
| M8 | 🟡 | Step 13.2.3 "swap to .sparse" doesn't say where | Made explicit: temporary one-line edit at the `mockSnapshot` injection site; added explicit revert sub-step before CP4. |
| M9 | 🟡 | Step 8.1.2 prose omits `.tracking(0.4)` | Added `.tracking(0.4)` requirement to the Change bullet. |
| L1 | ⚪ | Drift-table `:298-312` vs `:300-312` | Already reconciled. No-op. |
| L2 | ⚪ | Branch-name punctuation style | Accepted — consistent with project git history. |
| L3 | ⚪ | Step 13.4.2 "6 commits" undercount (actually 7) | Fixed: "baseline + Task 1 intra-commit + CP1 + CP2 + CP3 + CP4 + final = 7 commits". |
| L4 | ⚪ | Redundant baseline/final build command note | Added a one-line note in 13.1.1 for symmetry. |
| L5 | ⚪ | Step 5.2.10 "Xcode preview" verify weaker than "build succeeds" | Replaced with "Widget scheme build succeeds". |
| L6 | ⚪ | Steps 11.1.2 / 11.1.3 preview swap risk being committed | Added "Do not commit the preview swap" warning between 11.1.2 and 11.1.3; CP3 commit sanity-checks cleanness. |
| L7 | ⚪ | Drift-table wording for `SharedWidgetViews.swift` | Accepted — step body (5.2.1–5.2.3) differentiates correctly. No change. |
| L8 | ⚪ | Step 15.3.1 "minimal 1-factor snapshot one-liner" is not actually a one-liner | Rephrased: "copy `.sparse` factory pattern in the preview scratch; override `screenTimeHours: 0` locally" — no longer pretends to be a one-liner. |

**Verdict classification:** ALL RESOLVED — 3 Critical, 4 High, 9 Medium, 8 Low findings addressed. No findings deferred.

---

## Execution Plan (decided 2026-04-23)

Three operational decisions captured before implementation. These do not change any step body — they govern how the existing steps are executed.

| # | Decision | Applies to |
|---|---|---|
| 1 | **Commit autonomy: AUTO.** The implementer may create all 7 checklist-named commits (Step 0.4 baseline marker, Task-1 intra-commit after 1.1.1, CP1, CP2, CP3, CP4, final at 13.4.1) without pausing for per-commit approval. **No pushes to remote.** | All commit points |
| 2 | **Step 0.6 baseline capture: USER-EXECUTED, UP FRONT.** The user captures `v1_default` + `v1_typical` from the DEBUG log in the simulator BEFORE Phase A begins, and writes them to `Docs/04_Checklist/phase1-v1-baseline.txt` (uncommitted). Phase A is blocked until this file exists. Exit-gate Steps 13.3.1 / 13.3.2 compare against these captured values. | Step 0.6, 13.3.1, 13.3.2 |
| 3 | **Cadence: PHASE-BY-PHASE.** The implementer pauses after CP1, CP2, CP3, and CP4 — reports state and waits for explicit user "continue" before starting the next phase. Within a phase, steps run back-to-back. Phase 13 smoke tests (13.2.x, 13.3.x) and final commit 13.4.1 are user-executed. | CP1, CP2, CP3, CP4, Phase 13 |

**User-executed steps (implementer skips these):** 0.6, 13.2.1, 13.2.2, 13.2.3, 13.2.4, 13.2.5, 13.2.6, 13.2.6.1, 13.3.1, 13.3.2, 13.3.3, 13.3.4, 13.4.1, 13.4.2.
**Implementer-executed steps:** 0.1–0.5, all of Phases A/B/C/D/E, and the final 4-target build (13.1.1).

---

## Line-anchor drift notes

Validated against current source on 2026-04-20 before writing this checklist (re-verified during resolution). Where the plan cited a line that drifted, the current anchor is used here.

| Plan cite | Current anchor | Note |
|---|---|---|
| `StressView.swift:298-312` (scoreHeader) | `StressView.swift:300-312` | 2-line drift; body unchanged |
| `StressView.swift:239-243` (scoreHeader + modifiers block) | `StressView.swift:239-243` | Confirmed. `scaleEffect` is ONLY on `:243` with value `0.93` (NOT `0.85` as plan code snippets show). `[resolves: H2]` |
| `StressViewModel.swift:615` (refreshScreenTimeFactor) | `StressViewModel.swift:615-655` | confirmed |
| `StressViewModel.swift:549-613` (builders) | `StressViewModel.swift:549-613` | confirmed |
| `StressViewModel.swift:621-625, :634-638, :646-650` (three `StressFactorResult(... maxScore: 25 ...)` sites in refreshScreenTimeFactor) | verified by re-read | All 3 sites need migration, including the none-branch. `[resolves: C1]` |
| `StressViewModel.swift:232-253` (loadData call sites) | `StressViewModel.swift:234-253` | small drift |
| `StressViewModel.swift:238, 246, 349, 352, 641` (DEBUG `/25`) | `:238, 246, 349, 352, 641` | All 5 present; **each line has TWO `/25` tokens = 10 tokens total**. `[resolves: C2]` |
| `StressModels.swift:78` (`// always 25`) | `:78` | confirmed |
| `StressModels.swift:131` (preview `maxScore: 25`) | `:131` | confirmed. Line reads `maxScore: 25,` — no `/25` substring; not a `/25` grep hit. Intentionally retained (Exercise weight IS 25). `[resolves: M4]` |
| `StressDeepDiveSection.swift:72-82` | `:72-82` confirmed; call sites at `:75, :76-78, :79, :80` (sleepScore spans 3 lines). `[resolves: M2]` | |
| `DietDetailView.swift:82` | `:82` confirmed | |
| `ScreenTimeDetailView.swift:80` | `:80` confirmed | |
| `SharedWidgetViews.swift:104, 109, 124` | all 3 confirmed (`:104`/`:109` numeric `/25.0`, `:124` string `"/25"`) | |
| `SharedStressData.swift:68-71, 95` | all confirmed | |
| `ProfileView.swift:1433, 1435, 1445` | all 3 confirmed | |
| `StressFactorCardView.swift:46` | confirmed | |
| `StressLargeView.swift` (cited in §10) | Grep shows no `/25` or `maxScore` literals — no edit needed. Smoke-tested via new Step 13.2.6.1. `[resolves: H1]` | |
| `StressViewModel.swift:372` (logCurrentStress signature) | `:372` is the `func` signature line; `:373` is `guard !usesMockData else { return }`; new guard insertion goes at `:374`. `[resolves: M3]` | |
| `StressMockSnapshot.swift:49` (`static let default`) | Line 49 is the one-line static let; new `.sparse` insertion begins around `:51`. `[resolves: M5]` | |
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
  - Verify: All 4 emit `** BUILD SUCCEEDED **`. (Symmetric with Step 13.1.1's final 4-target build.) `[resolves: L4]`

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
    - `WellPlateWidget/Views/StressLargeView.swift` (smoke-check only — no edit) `[resolves: H1]`
  - Verify: All 14 files found (13 edited + StressLargeView smoke-check).

- [ ] **Step 0.6 — Capture LIVE v1 (pre-change) stress totals for the whipsaw exit gate** `[resolves: C3]` **⚠️ USER-EXECUTED (per Execution Plan decision 2). Phase A is blocked until `Docs/04_Checklist/phase1-v1-baseline.txt` exists.**
  - Rationale: The plan §4 math and the first audit disagreed on v1 sleep contribution (plan: 1.80, audit: 1.05), yielding either `19.34` or `18.6` for the `.default` mock total. Rather than hard-code a disputed literal, capture the actual v1 totals from the DEBUG log BEFORE any scoring changes land. These captured numbers are the ground truth for Steps 13.3.1 and 13.3.2.
  - Change:
    1. With the baseline build installed (Step 0.3), launch the simulator with mock mode ON (`AppConfig.shared.mockMode = true` via Profile → Debug, or via UserDefaults).
    2. Navigate to the Stress tab. Watch the Xcode console for the `📊 Stress summary:` block (emitted by `StressViewModel.loadData()` around `:260-268`).
    3. Record the `Total stress : XX.XX/100` value. This is **`v1_default`**.
    4. Construct the synthetic "typical active user" fixture (steps=10000, energy=600, sleep 8h/2.5h deep, protein 75g / fiber 22g / fat 50g / carbs 180g, 6h screen). Easiest: temporarily edit `StressMockSnapshot.makeDefault()` locally to match those values, reload, capture the new `Total stress` value. This is **`v1_typical`**. **Revert the local edit immediately — do not commit.**
    5. Write both captured values into a scratch note (`Docs/04_Checklist/phase1-v1-baseline.txt` or equivalent — do not commit):
       ```
       v1_default = XX.XX    (captured YYYY-MM-DD HH:MM)
       v1_typical = XX.XX    (captured YYYY-MM-DD HH:MM)
       ```
  - Verify: Both values recorded. Working tree clean again after revert. `git status` shows no modifications to `StressMockSnapshot.swift`.
  - Note: This step replaces the plan's disputed `19.34` and `12.67` literals. Subsequent exit-gate steps (13.3.1, 13.3.2) compare v1.1 (post-change) against THESE captured numbers.

---

## Phase A — Scoring core (Tasks 1–4)

> 🛑 **Gate:** Phase A cannot begin until `Docs/04_Checklist/phase1-v1-baseline.txt` exists (Step 0.6 output). Implementer verifies the file is present before Step 1.1.1.
>
> ⚠️ **Build-break window:** Between Step 1.1.1 and Step 5.B the tree does NOT compile. Do not commit between 2.1.1 and 5.B. Do not push. If your editor auto-builds on save or you have a pre-commit hook wired to `xcodebuild`, expect red. CP1 (after Phase B) is the first clean commit state after the baseline. `[resolves: M1]`

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

- [ ] **Step 5.1.6 — Update all THREE `refreshScreenTimeFactor` `StressFactorResult(...)` constructions** `[resolves: C1]`
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - **Verified anchors (re-read from live source on resolution date):**

    | Branch | Line range | Current literal | Target |
    |---|---|---|---|
    | `.mock` branch (inside `if let snap = mockSnapshot`) | `:621-625` | `maxScore: 25,` at `:622` | `maxScore: StressScoring.Weights.screenTime` |
    | `.auto` branch (inside `if let reading = ScreenTimeManager...`) | `:634-638` | `maxScore: 25,` at `:635` | `maxScore: StressScoring.Weights.screenTime` |
    | `.none` branch (else — no reading) | `:646-650` | `maxScore: 25,` at `:647` | `maxScore: StressScoring.Weights.screenTime` |

  - **Additional changes:**
    - Mock branch (`:619`): local `score` becomes `Double?` after Step 4.2.1 — the `StressFactorResult(score: ...)` argument at `:622` needs `score ?? 0`. Wrap with `?? 0` when passing into the struct.
    - Auto branch (`:632`): same pattern — `score ?? 0` at `:635`.
    - None branch: `score: 0, hasValidData: false` stays as-is — only the `maxScore: 25` literal changes. `hasValidData: false` is correct (no data in this branch).
  - **Reader's note:** The original checklist said "mock branch (:619) and auto branch (:632)" — those lines are the `StressScoring.screenTimeScore(...)` calls, NOT the `StressFactorResult(...)` constructions. The constructions begin 2-3 lines after each score call. The none-branch construction was silently ignored but ALSO has `maxScore: 25`.
  - Verify: WellPlate scheme builds clean at this file's scope. `grep -n 'maxScore: 25' "WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift"` → **zero hits** (all three migrated). Confirm via the grep.

- [ ] **Step 5.1.7 — Update all 10 DEBUG `/25` tokens (5 lines × 2 tokens per line)** `[resolves: C2, H3]`
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - **Re-grepped on resolution date; every line has EXACTLY two `/25` tokens. Total: 10 edits.**

    | Line | Factor | Current (before) | Target (after) | Optional-unwrap required? |
    |---|---|---|---|---|
    | `:238` | Exercise | `score=\(fmt2(exerciseScore))/25  stressContrib=\(fmt2(exerciseFactor.stressContribution))/25` | `score=\(fmt2(exerciseScore ?? 0))/\(Int(StressScoring.Weights.exercise))  stressContrib=\(fmt2(exerciseFactor.stressContribution))/\(Int(StressScoring.Weights.exercise))` | **YES** — `exerciseScore` is now `Double?`. Use `exerciseScore ?? 0` inside `fmt2`. |
    | `:246` | Sleep | `score=\(fmt2(sleepScore))/25  stressContrib=\(fmt2(sleepFactor.stressContribution))/25` | `score=\(fmt2(sleepScore ?? 0))/\(Int(StressScoring.Weights.sleep))  stressContrib=\(fmt2(sleepFactor.stressContribution))/\(Int(StressScoring.Weights.sleep))` | **YES** — `sleepScore` is now `Double?`. Also **note denominator becomes `/35` (sleep weight), not `/25`**. |
    | `:349` | Diet (no-logs branch) | `score=\(fmt2(score))/25  stressContrib=\(fmt2(dietFactor.stressContribution))/25` | `score=\(fmt2(score ?? 0))/\(Int(StressScoring.Weights.diet))  stressContrib=\(fmt2(dietFactor.stressContribution))/\(Int(StressScoring.Weights.diet))` | **YES** — local `score` in `refreshDietFactor` is now `Double?`. Denominator becomes `/20`. |
    | `:352` | Diet (has-logs branch) | `score=\(fmt2(score))/25  stressContrib=\(fmt2(dietFactor.stressContribution))/25  [\(dietFactor.detailText)]` | `score=\(fmt2(score ?? 0))/\(Int(StressScoring.Weights.diet))  stressContrib=\(fmt2(dietFactor.stressContribution))/\(Int(StressScoring.Weights.diet))  [\(dietFactor.detailText)]` | **YES** — same local `score`. Denominator `/20`. |
    | `:641` | Screen time | `score=\(fmt2(score))/25  stressContrib=\(fmt2(screenTimeFactor.stressContribution))/25  [\(detail)]` | `score=\(fmt2(score ?? 0))/\(Int(StressScoring.Weights.screenTime))  stressContrib=\(fmt2(screenTimeFactor.stressContribution))/\(Int(StressScoring.Weights.screenTime))  [\(detail)]` | **YES** — local `score` in auto branch is now `Double?`. Denominator `/20`. |

  - **Pattern rule:** "Any `fmt2(X)` where X is now `Double?` must become `fmt2(X ?? 0)`." The `stressContrib` side uses `factor.stressContribution` which is `Double` (computed from `factor.score * factor.maxScore / ...`), so no unwrap needed there.
  - **Denominator rule:** Use `Int(StressScoring.Weights.FACTOR)` interpolation so the log automatically reflects the weight. Sleep logs `/35`, Exercise `/25`, Diet `/20`, Screen `/20`.
  - Verify:
    1. DEBUG build succeeds (WellPlate scheme).
    2. `grep -n '/25' "WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift"` returns **zero hits**. This is a hard gate.
    3. On next run, DEBUG log shows correct denominators per factor.

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
  - Verify: Widget scheme build succeeds. (Preview render is a weaker check — see L5.)

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

- [ ] **Step 5.2.10 — `SharedStressData.swift:68-71` placeholder weights** `[resolves: L5]`
  - File: `WellPlate/Widgets/SharedStressData.swift:68-71`
  - Change: Update the 4 `WidgetStressFactor` placeholder entries to use correct weights:
    - Exercise → `maxScore: 25`
    - Sleep → `maxScore: 35`
    - Diet → `maxScore: 20`
    - Screen Time → `maxScore: 20`
  - Verify: Widget scheme build succeeds (stronger check than "Xcode preview scales bars").

- [ ] **Step 5.2.11 — `SharedStressData.swift:95` comment refresh**
  - File: `WellPlate/Widgets/SharedStressData.swift:95`
  - Change: `let maxScore: Double        // 25` → `let maxScore: Double        // per-factor weight (sleep 35, exercise 25, diet 20, screen 20)`.
  - Verify: Doc-comment present.

- [ ] **Step 5.2.12 — `StressModels.swift:78` comment refresh**
  - File: `WellPlate/Models/StressModels.swift:78`
  - Change: `let maxScore: Double       // always 25` → `let maxScore: Double       // varies per factor (sleep 35, exercise 25, diet 20, screen 20)`.
  - Verify: Comment updated; no behavior change.

- [ ] **Step 5.2.13 — Grep sanity sweep** `[resolves: M4, C2]`
  - Change: Run:
    ```
    grep -rn "/25" "WellPlate/Features + UI/Stress" "WellPlate/Features + UI/Tab/ProfileView.swift" "WellPlate/Widgets" "WellPlateWidget" "WellPlate/Models/StressModels.swift"
    ```
  - Expected hits after Phase B: **zero** `/25` matches in these paths.
  - Intentional retentions (NOT `/25` grep matches — listed for reader clarity):
    - `StressModels.swift:131` reads `maxScore: 25,` — this is the `.neutral` Exercise preview stub and Exercise's weight IS 25. No `/25` substring, so the grep will not flag it. Retain as-is.
  - Verify: Grep returns zero hits. Any hit must be investigated.

### 5.3 — Task 6 verification (no code change)

- [ ] **Step 5.3.1 — Read `totalScore` property and confirm no weight-redistribution math was added**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:79-84`
  - Change: None — verify the property is still `exerciseFactor.stressContribution + sleepFactor.stressContribution + dietFactor.stressContribution + screenTimeFactor.stressContribution`.
  - Verify: Read-through only; nothing changed.

### 14 — `StressDeepDiveSection` call-site migration (Task 14)

- [ ] **Step 14.1 — Add `?? 0` to 4 `StressScoring.*` calls in `factorDecompItems`** `[resolves: M2 wording]`
  - File: `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift:72-82`
  - Change each of the 4 calls (sleepScore spans 3 lines, the others are single-line):
    - `:75` `let ex = StressScoring.exerciseScore(steps: ..., energy: ...)` → append `?? 0`
    - `:76-78` `let sl = StressScoring.sleepScore(summary: ...)` — multi-line closure expression → append `?? 0` at the END of the full expression (after the closing `})` on `:78`)
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

> 🛑 **STOP — phase-by-phase gate (Execution Plan decision 3).** Implementer reports CP1 state and waits for explicit user "continue" before starting Phase C.

---

## Phase C — Confidence badge (Tasks 7, 8)

### 7.1 — Nested `Confidence` enum + computed properties `[resolves: M6]`

- [ ] **Step 7.1.1 — Add `Confidence` nested enum at END OF FILE (after class closing brace)**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - Scope: Place this `extension StressViewModel { enum Confidence: String { ... } }` block **AFTER the `StressViewModel` class closing brace**, at file scope. Do NOT place it inside the class.
  - Change: Add
    ```swift
    extension StressViewModel {
        enum Confidence: String {
            case low, medium, high
            var label: String { ... }
            var systemImage: String { ... }
        }
    }
    ```
    per plan Task 7.
  - Verify: Nested type resolves as `StressViewModel.Confidence`; build succeeds.

- [ ] **Step 7.1.2 — Add `factorCoverage` and `stressConfidence` computed properties INSIDE the class**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` (inside the class body, adjacent to the existing `totalScore` / `stressLevel` computed properties around `:79-95`)
  - Scope: Both vars go INSIDE the `@MainActor final class StressViewModel` declaration, next to the existing computed properties — NOT in the extension from 7.1.1.
  - Change: Add
    - `var factorCoverage: Int { allFactors.filter(\.hasValidData).count }`
    - `var stressConfidence: StressViewModel.Confidence { switch factorCoverage { case 4: .high; case 2, 3: .medium; default: .low } }`
  - Verify: Build succeeds; new properties are callable from SwiftUI views.

- [ ] **Step 7.1.3 — Add `shouldHideScoreForLowConfidence` property INSIDE the class**
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` (same location as 7.1.2 — inside the class body, adjacent to `factorCoverage` / `stressConfidence`)
  - Change: `var shouldHideScoreForLowConfidence: Bool { factorCoverage < 2 }` (strategy §3 line 76 threshold).
  - Verify: Build succeeds.

### 8.1 — Render confidence badge in `StressView`

- [ ] **Step 8.1.1 — Restructure `scoreHeader` from HStack to VStack**
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift:300-312`
  - Change: Wrap the existing number+"/100" `HStack` inside a `VStack(alignment: .leading, spacing: 6)` and add `confidenceBadge` as the second child (exactly per plan Task 8 code block).
  - Verify: Score area compiles; Xcode preview or simulator renders the number with the new badge beneath.

- [ ] **Step 8.1.2 — Add `confidenceBadge` computed view** `[resolves: M9]`
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (new `private var confidenceBadge: some View` adjacent to `scoreHeader`)
  - Change: Body per plan Task 8 — HStack with `Image(systemName: viewModel.stressConfidence.systemImage)` at `size: 13 semibold`, and `Text("\(viewModel.stressConfidence.label) · \(viewModel.factorCoverage)/4 factors")` at `size: 13 medium rounded` with `.tracking(0.4)` on the Text (letter-spacing matches plan Task 8 code snippet); wrapped in a Capsule `Color(.systemGray6)` background. Font bump (M2) already baked in.
  - Verify: WellPlate scheme builds; confidence badge visible in Xcode preview.

- [ ] **Step 8.1.3 — Confirm scaleEffect value stays at LIVE `0.93` (NOT plan snippet's `0.85`)** `[resolves: H2]`
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift:243`
  - **Live-source fact (re-read during resolution):** `:243` reads `.scaleEffect(scoreAppeared ? 1 : 0.93, anchor: .topLeading)`. The plan's Task 8 / Task 15 code snippets show `0.85` but the live source is `0.93`. **Do NOT replace `0.93` with `0.85`.** Preserve existing animation value.
  - Change: None to `:243`. Preserve the existing modifiers at `:240-243`:
    - `:240` `.padding(.top, 20)`
    - `:241` `.padding(.horizontal, 20)`
    - `:242` `.opacity(scoreAppeared ? 1 : 0)`
    - `:243` `.scaleEffect(scoreAppeared ? 1 : 0.93, anchor: .topLeading)`
  - Verify: Simulator: navigate to Stress tab; on first entry, score+badge animates in together anchored to top-left at the existing scale (0.93 → 1.0). No visual drift compared to baseline.

### Build after Phase C

- [ ] **Step 8.B — 4-target build**
  - Commands: all 4 `xcodebuild` commands.
  - Verify: All clean.

**🟢 Checkpoint CP2 — confidence badge live.** Commit:
`git commit -am "feat(stress-p1): StressViewModel.Confidence + badge on StressView (Tasks 7–8)"`

> 🛑 **STOP — phase-by-phase gate.** Implementer reports CP2 state and waits for user "continue" before starting Phase D.

---

## Phase D — Feature flag + mock parity (Tasks 10, 11, 12)

### 10.1 — `AppConfig.stressAlgorithmV2` placeholder

- [ ] **Step 10.1.1 — Add UserDefaults key**
  - File: `WellPlate/Core/AppConfig.swift:14-22` (inside `private enum Keys`)
  - Change: `static let stressAlgorithmV2 = "app.stress.algorithmV2"`.
  - Verify: Key compiles; no other site references it yet.

- [ ] **Step 10.1.2 — Add `stressAlgorithmV2` computed property**
  - File: `WellPlate/Core/AppConfig.swift` (add under `mockMode` block, around line 46)
  - Change: Implement per plan Task 10 — DEBUG-gated `get` checking `UserDefaults.standard.object(forKey:) != nil` else `false`; DEBUG `set` writes to UserDefaults and logs via `WPLogger.app.info("Stress Algorithm V2 → \(newValue ? "ENABLED" : "DISABLED")")`; release build always returns `false`.
  - Verify: Release (non-DEBUG) path returns `false` unconditionally.

- [ ] **Step 10.1.3 — Add log line to `logCurrentMode()`** `[resolves: M7]`
  - File: `WellPlate/Core/AppConfig.swift:151-156`
  - Change: Append to the `lines:` array: `"Stress v2  : \(stressAlgorithmV2 ? "ENABLED" : "disabled")"` (no emoji per L5).
  - **Note:** The mixed case — **setter** logs `ENABLED`/`DISABLED` (both uppercase) but the **startup log** uses `ENABLED`/`disabled` (lowercase for false-state) — is **intentional**. It matches the existing spartan `logCurrentMode()` style where false-states are lowercase (see plan L5 resolution). Do not "fix" them to match; they are deliberately different.
  - Verify: Simulator run: `AppConfig.shared.logCurrentMode()` prints the new line once at app launch in the startup log format.

- [ ] **Step 10.1.4 — Build**
  - Commands: `xcodebuild ... -scheme WellPlate build`
  - Verify: Clean; no side effects elsewhere (grep for `stressAlgorithmV2` should only hit AppConfig.swift).

### 11.1 — `StressMockSnapshot.sparse` factory (Task 11)

- [ ] **Step 11.1.1 — Add `sparse` static + `makeSparse()`** `[resolves: M5]`
  - File: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
  - Scope: Line 49 is the one-line `static let default: StressMockSnapshot = makeDefault()`. New `.sparse` static + `makeSparse()` factory insertion begins around **line 51** (after the `.default` declaration and a blank line separator). Find the nearest "good place" in the file — typically right after `.default` and its factory function, and before any `MARK:` divider.
  - Change: Insert the `static let sparse` and `private static func makeSparse()` factory exactly per plan Task 11, including the doc comment. The factory overrides the last entry of `stepsHistory` and `energyHistory` to `value: 0` and sets `currentDayLogs: []`.
  - Verify: Build WellPlate scheme — `.sparse` compiles; struct field list matches `makeDefault()`'s initializer call.

- [ ] **Step 11.1.2 — Temporarily swap `StressView` preview to `.sparse` (DO NOT COMMIT)** `[resolves: L6]`
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (preview block at bottom)
  - Change: In `#Preview`, change `StressMockSnapshot.default` to `StressMockSnapshot.sparse` (one-line change).
  - Verify: Xcode Preview renders: exercise + diet cards grayed out; sleep and screen-time cards active; confidence badge reads `Medium confidence · 2/4 factors`; total hero reads approximately `14/100`.
  - **⚠️ Warning:** This is a throwaway preview swap. Do not commit. Step 11.1.3 reverts before CP3.

- [ ] **Step 11.1.3 — Revert preview to `.default`** `[resolves: L6]`
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (same preview block)
  - Change: Change back to `StressMockSnapshot.default`.
  - Verify: Preview now reads `19/100 · High confidence · 4/4 factors`. `git diff` shows no change to this preview line (confirming clean revert). CP3 commit must not include this swap.

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

Pre-commit sanity: `git diff --cached` shows no `.sparse` in the `#Preview` block of `StressView.swift` (i.e., 11.1.3 revert landed).

> 🛑 **STOP — phase-by-phase gate.** Implementer reports CP3 state and waits for user "continue" before starting Phase E.

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

- [ ] **Step 15.1.3 — Swap `scoreHeader` → `scoreHero` at call site (preserve existing animation modifiers)** `[resolves: H2]`
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift:239`
  - Change: Replace the one `scoreHeader` reference inside `mainScrollView` at `:239` with `scoreHero`. **Retain all existing modifiers** at `:240-243`:
    - `:240` `.padding(.top, 20)`
    - `:241` `.padding(.horizontal, 20)`
    - `:242` `.opacity(scoreAppeared ? 1 : 0)`
    - `:243` `.scaleEffect(scoreAppeared ? 1 : 0.93, anchor: .topLeading)`
  - **Do NOT replace `0.93` with `0.85`** (the plan's code snippets use `0.85`; live source is `0.93`. Preserve live value.)
  - Verify: Build succeeds; animation modifiers continue to apply to the wrapper (`scoreHero`), not to `scoreHeader` directly. Visual check: both the normal hero state (coverage ≥ 2) and the honest-mode placeholder (coverage < 2) animate in with the same `0.93 → 1.0` scale.

### 15.2 — Skip `StressReading` logging in honest mode

- [ ] **Step 15.2.1 — Add honest-mode guard in `logCurrentStress`** `[resolves: M3]`
  - File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - Anchor: Line 372 is the function signature `func logCurrentStress(source: String = "auto") {`. Line 373 is `guard !usesMockData else { return }`. **Insert the new honest-mode guard at line 374**, immediately after the `guard !usesMockData` line.
  - Change: Insert at `:374`:
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

- [ ] **Step 15.3.1 — Construct a 1-factor mock in preview scratch to smoke-test honest mode** `[resolves: L8]`
  - File: `WellPlate/Features + UI/Stress/Views/StressView.swift` (preview scratch — **do not commit**)
  - Change: In the `#Preview`, build a 1-factor snapshot. Practical approach (not the fictional "one-liner"):
    1. Copy the `.sparse` factory pattern (Step 11.1.1) into the preview as a local `let single = StressMockSnapshot(...)` construction, OR
    2. Add a temporary `makeOneFactor()` sibling factory in `StressMockSnapshot.swift` that zeroes `stepsHistory` + `energyHistory` last entries, sets `screenTimeHours: 0`, and sets `currentDayLogs: []` — leaving only sleep populated.
    Either way, `currentDayLogs: []` + screen 0 + step/energy last-entry 0 is required.
  - Verify: Preview hides the score hero and instead displays the "Log more to see your stress score" placeholder.
  - ⚠️ Warning: If you add a sibling factory to `StressMockSnapshot.swift`, remove it before CP4 OR keep it if it also serves future tests — call it out in the CP4 commit message either way.

- [ ] **Step 15.3.2 — Revert preview scratch**
  - File: same
  - Change: Restore `StressMockSnapshot.default`.
  - Verify: Preview renders normal hero + High confidence. `git diff` shows no preview change landing in CP4 commit.

### Build after Phase E

- [ ] **Step E.B — 4-target build**
  - Commands: all 4 `xcodebuild` commands.
  - Verify: All clean.

**🟢 Checkpoint CP4 — honest mode shippable.** Commit:
`git commit -am "feat(stress-p1): honest-mode placeholder + StressReading log skip (Task 15)"`

> 🛑 **STOP — phase-by-phase gate.** Implementer reports CP4 state and hands off to user for Phase 13 smoke tests (13.2.x, 13.3.x) + exit-gate verification + final commit 13.4.1. Implementer only runs the final 4-target build at 13.1.1 if asked.

---

## Post-Implementation — Smoke tests, exit-gate verification, final build (Task 13)

### 13.1 — Full 4-target clean build (FINAL)

- [ ] **Step 13.1.1 — Run all 4 builds from a clean derived-data state**
  - Commands (identical to Step 0.3 for regression symmetry):
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

- [ ] **Step 13.2.3 — Stress tab with `.sparse` mock → 2/4 medium confidence (temporary VM injection)** `[resolves: M8]`
  - Change: In `StressViewModel.swift`, find the `mockSnapshot` injection point — grep for `StressMockSnapshot.default` or `.default` usage in the VM init / factory path (there should be one production reference). Temporarily change that ONE reference from `.default` to `.sparse`. Reload simulator.
  - Verify: Hero reads ~"14/100"; badge reads "Medium confidence · 2/4 factors"; exercise + diet cards grayed.
  - **Revert:** Change back to `.default`. Verify `git diff` shows zero modifications to `StressViewModel.swift` from this smoke test. **Do not commit the swap.**

- [ ] **Step 13.2.4 — Honest mode: 1-factor mock → placeholder** `[resolves: M8]`
  - Change: Same injection approach as 13.2.3, but either use the `.sparse` snapshot further modified in-source (zero `screenTimeHours` inline on the snapshot read path), OR use the `makeOneFactor()` helper from Step 15.3.1 if you added one. Record WHICH approach was used.
  - Verify: Hero is replaced by "Log more to see your stress score"; DEBUG console shows `⏭  Skipped StressReading log: honest mode (coverage=1)` (or `=0`).
  - **Revert:** Restore the VM injection to `.default`. `git diff` clean.

- [ ] **Step 13.2.5 — Feature flag toggle is a no-op**
  - Change: In DEBUG menu or via debugger, set `AppConfig.shared.stressAlgorithmV2 = true`. Reload Stress tab.
  - Verify: UI identical to `false` state (flag currently reads nowhere). `logCurrentMode()` next launch prints `Stress v2  : ENABLED`.
  - Reset: `stressAlgorithmV2 = false`.

- [ ] **Step 13.2.6 — Widget renders 4 factor bars with correct denominators (small + medium)**
  - Change: Long-press the home screen, add Stress widget (small or medium), pin to home.
  - Verify: Bars render without crash; factor rows read "X/35" (sleep), "X/25" (exercise), "X/20" (diet), "X/20" (screen).

- [ ] **Step 13.2.6.1 — Widget Large variant smoke test (`StressLargeView`)** `[resolves: H1]`
  - Rationale: Plan §10 lists `StressLargeView.swift` in the touch summary. Grep confirmed no `/25` or `maxScore` literals inside it — the file renders via `StressFactorBar` from `SharedWidgetViews` which uses `factor.maxScore` dynamically. So no source edit is needed, but the file must still be smoke-tested post-Phase-D so a future reviewer cross-checking §10 sees it covered.
  - Change: Add the **Large** Stress widget variant to the home screen (long-press → edit widgets → Stress Large, pin).
  - Verify:
    - Widget renders the 4-factor breakdown bars without crash.
    - Factor rows read "X/35" (sleep), "X/25" (exercise), "X/20" (diet), "X/20" (screen) — confirming the large variant flows through the same `factor.maxScore` path as small/medium.
    - 7-day trend chart at the bottom still draws.
    - Vitals row (resting HR / HRV / respiratory) renders if available.
  - No code change in this step — pure smoke test.

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

- [ ] **Step 13.3.1 — Whipsaw exit gate (H6): `.default` mock**  `[resolves: C3]`
  - Change: With `.default` mock loaded AND the Phase 1 changes shipped, read the DEBUG log line `Total stress : XX.XX/100` from the `📊 Stress summary` block. This is **`v1.1_default`**. Compare against **`v1_default`** captured in Step 0.6.
  - Verify: `|v1.1_default − v1_default| ≤ 5`. (Plan §4 predicts v1 ≈ 19.34 and v1.1 ≈ 19.19; audit re-derivation suggested v1 ≈ 18.6. Either way the absolute delta matters, not the literal. The gate is ≤ 5 — generous enough to absorb the math dispute.)
  - If `|Δ| > 5`: STOP. Investigate. Do not proceed to 13.3.2.
  - Derivation note (for reference only — NOT the baseline): Plan math says `.default` v1 = Exercise 8.54 + Sleep 1.80 + Diet 0 + Screen 9 = **19.34**; audit says Sleep 1.05 → **18.6**. The live capture from Step 0.6 is the ground truth.

- [ ] **Step 13.3.2 — Whipsaw exit gate: synthetic "typical active user"** `[resolves: H4, C3]`
  - Change: Load the synthetic fixture (steps=10000, energy=600, sleep=8h/2.5h deep, protein 75g / fiber 22g / fat 50g / carbs 180g, 6h screen) that was captured in Step 0.6 as `v1_typical`. Read the new DEBUG `Total stress : XX.XX/100` — this is **`v1.1_typical`**.
  - Verify: `|v1.1_typical − v1_typical| ≤ 5`. (Plan §4 predicts v1 ≈ 12.67, audit re-derivation ≈ 13.0, v1.1 ≈ 15.7. The disputed literal is replaced by the captured baseline.)
  - Derivation note (reference only): Plan's synthetic v1 math had a `19.33+5` Sleep term that evaluates inconsistently; audit re-derivation gives 1.0 for sleep and Screen 12.0 → total 13.0 (plan said 12.67). The live capture is ground truth.

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
  - Change: Re-run Steps 13.2.6, 13.2.6.1, 13.2.7 and note the home Stress Insight card.
  - Verify: All four surfaces (small widget, large widget, AI report deep dive, home insight card) render without crashes; labels/strings unchanged in shape.

- [ ] **Step 13.3.7 — CLAUDE.md architecture rules preserved**
  - Change: Grep verify: `@MainActor final class StressViewModel` still present; `StressScoring` still an `enum` with only `static` functions; no new `.sheet()` on StressView (single `StressSheet` enum-driven sheet pattern preserved).
  - Verify: `grep -n "@MainActor final class StressViewModel" "WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift"` → 1 hit. `grep -n "enum StressScoring" "WellPlate/Core/Services/StressScoring.swift"` → 1 hit.

### 13.4 — Final commit + branch readiness

- [ ] **Step 13.4.1 — Final commit with verified math**
  - Change: `git commit --allow-empty -m "chore(stress-p1): Phase 1 exit gates verified (whipsaw Δ captured live vs Step 0.6 baseline)"`
  - Verify: Commit present; working tree clean.

- [ ] **Step 13.4.2 — Ready for review** `[resolves: L3]`
  - Verify: `git log --oneline stress/phase1-foundation ^main` shows **7 commits**: baseline (Step 0.4) + Task 1 intra-commit (after 1.1.1) + CP1 (end of Phase B) + CP2 + CP3 + CP4 + final (13.4.1).

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
| Task 5 (widget large — smoke only) | StressLargeView renders post-change | 13.2.6.1 `[resolves: H1]` |
| Task 6 | Totalscore pass-through verify | 5.3.1 |
| Task 7 | Confidence enum + props | 7.1.1, 7.1.2, 7.1.3 |
| Task 8 | Badge in StressView | 8.1.1, 8.1.2, 8.1.3 |
| Task 9 | Q5 deferral (no code) | 4.2.2 (comment only) |
| Task 10 | AppConfig.stressAlgorithmV2 flag | 10.1.1, 10.1.2, 10.1.3, 10.1.4 |
| Task 11 | StressMockSnapshot.sparse | 11.1.1, 11.1.2, 11.1.3 |
| Task 12 | StressLevel bands ripple (verify only) | 12.1.1 |
| Task 13 | Build + smoke-test | 0.3, 0.6 (v1 capture), 5.B, 8.B, D.B, E.B, 13.1.1, 13.2.1 – 13.2.9, 13.2.6.1, 13.3.1 – 13.3.7 |
| Task 14 | StressDeepDiveSection ?? 0 migration | 14.1 |
| Task 15 | Honest mode placeholder + log skip | 15.1.1, 15.1.2, 15.1.3, 15.2.1, 15.3.1, 15.3.2 |

**Coverage:** 15/15 tasks mapped; no task left behind. `StressLargeView.swift` (plan §10 file touch entry) now has explicit coverage via Step 13.2.6.1 smoke test.

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
| Widget / Profile / Diet detail / Screen Time detail denominators weighted | 5.2.1 – 5.2.12, 13.2.6, 13.2.6.1, 13.2.8 |
| `StressInsightCard` (home) renders | 13.2.1 |
| `StressDeepDiveSection` (AI report) renders without crash | 14.1, 13.2.7 |
| `StressLargeView` (widget large) renders post-change | 13.2.6.1 |
| Whipsaw `|v1.1 − v1| ≤ 5` on default mock + synthetic typical user (against LIVE-captured v1) | 0.6 (baseline capture), 13.3.1, 13.3.2 |
| Mock-mode parity: no NaN, no overflow | 13.3.5 |
| Architecture conventions preserved | 13.3.7 |

---

## Permission dialogs to expect during smoke testing

- **HealthKit** (Step 13.2.9 / any live-mode run): iOS will prompt for read access on steps, energy, sleep analysis, heart rate, resting heart rate, HRV, blood pressure, respiratory rate, and time in daylight. Grant all toggles. May need to re-grant in `Settings → Privacy → Health → WellPlate` if the initial prompt was declined.
- **Screen Time / Family Controls** (Step 13.2.9): `ScreenTimeManager` requests FamilyActivity auth. Accept the dialog. If denied earlier, revoke and re-request via Settings → Screen Time → WellPlate.
- **No new permissions are introduced by Phase 1** — these are pre-existing prompts.

---

## Open decisions that block execution

None. The v1 baseline dispute (C3) is resolved by the live-capture mechanism in Step 0.6 — no math re-derivation needed at plan-read time. The whipsaw gate in 13.3.1 / 13.3.2 compares against captured reality.

If during execution the captured `v1_default` from Step 0.6 is significantly far from BOTH `19.34` (plan) and `18.6` (audit), surface it as an open question before proceeding to Phase A — it would suggest the source file has drifted further than the drift table documented.
