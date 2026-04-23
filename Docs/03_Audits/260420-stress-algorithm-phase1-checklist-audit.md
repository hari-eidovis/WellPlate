# Checklist Audit Report: Stress Algorithm — Phase 1

**Audit Date:** 2026-04-20
**Checklist Version:** `Docs/04_Checklist/260420-stress-algorithm-phase1-checklist.md` (73 steps)
**Auditor:** audit agent
**Verdict:** **READY-WITH-FIXES** — structure is solid, traceability is complete, and line-anchor drift has been well-managed; however, 3 line anchors are meaningfully off, 1 step is under-specified in a way that will leak build breaks, 2 verification steps assert "correct" values that do not match the RESOLVED plan's math, and one legitimate edit site (`StressLargeView.swift`) silently disappears between the plan and the checklist. Fix the 🔴/🟠 items below before executing.

---

## Executive Summary

The checklist does a better job than most — the Line-anchor Drift Notes table up top, per-task traceability, and 4 real "compiles-and-ships" checkpoints are all good practice. The Task 14 (StressDeepDiveSection) migration is correctly sequenced to happen **inside** Phase B, before CP1, so the C1 audit finding does not regress. Honest mode is sequenced correctly after the confidence badge, and the `.sparse` mock is introduced before any step that would need to test honest mode. That said, several line anchors are wrong (the drift table is partly fabricated), step 5.1.6 hides a real builder-line mismatch, step 13.3.1 quotes "19.34" as the v1 baseline when the RESOLVED plan's own H5 math shows the v1 total is **18.6** (an echo of the pre-RESOLVED "19.34" number that's inconsistent with the rest of the recomputed table), and the planned edit for `StressLargeView.swift` vanishes from the checklist.

---

## Issues Found

### 🔴 CRITICAL (Must fix before proceeding)

#### C1. Step 5.1.6 line anchors for `refreshScreenTimeFactor` builder constructions are wrong
- **Location:** checklist Step 5.1.6 "mock branch (:619) and auto branch (:632)".
- **Evidence:** `StressViewModel.swift:619` is `let score = StressScoring.screenTimeScore(hours: snap.screenTimeHours)` — a scoring call, not a `StressFactorResult(...)` construction. `:632` is the same pattern for the auto branch. The actual `StressFactorResult(..., maxScore: 25, ...)` constructions are at **:621-625 (mock), :634-638 (auto), :646-650 (none branch)**. Three `maxScore: 25` literals, not two as implied.
- **Impact:** The implementer will search line 619/632 for `maxScore: 25`, not find it there, and either (a) waste time resolving the mismatch or (b) edit the wrong line. Also the "none branch" (`:647`) has `maxScore: 25` that must be swept too, but the step says "The 'none' branch stays the same (`score: 0, hasValidData: false`)" — correct about hasValidData but silently ignores that this branch *also* has `maxScore: 25` that needs updating to `Weights.screenTime`.
- **Recommendation:**
  - Update Step 5.1.6 to read: "3 `StressFactorResult(...)` constructions at `:621-625` (mock), `:634-638` (auto), `:646-650` (none). All 3 need `maxScore: 25 → maxScore: StressScoring.Weights.screenTime`."
  - Explicitly note the `none` branch — it still constructs a StressFactorResult, and its `maxScore` is currently `25`.
- **Affects:** Step 5.1.6.

#### C2. Step 5.1.7 drift-table claim "all 5 present" masks that each of the 5 lines has TWO `/25` occurrences (10 tokens total)
- **Location:** checklist drift table row "StressViewModel.swift:238, 246, 349, 352, 641 (DEBUG `/25`)" says "all 5 present"; Step 5.1.7 says "DEBUG `/25` log literals (5 occurrences)".
- **Evidence:** Reading each line:
  - `:238` → `"score=...)/25 stressContrib=...)/25"` — 2 tokens
  - `:246` → 2 tokens
  - `:349` → 2 tokens
  - `:352` → 2 tokens
  - `:641` → 2 tokens
  Total: 10 `/25` occurrences, not 5.
- **Impact:** The implementer may only update one `/25` per line and leave the other — the `fmt2(... )/25 ... stressContrib=...)/25` pattern has two. Tests will fail the grep sanity sweep (Step 5.2.13) which explicitly excludes these DEBUG lines from the expected-matches set, leaving real `/25` hits unchecked.
- **Recommendation:**
  - Update Step 5.1.7 to "5 lines × 2 `/25` tokens per line = 10 total edits. Update BOTH occurrences on each line."
  - Also explicitly list that `:352` currently reads `stressContrib=\(fmt2(dietFactor.stressContribution))/25` — its denominator should be `/20` (Diet's new weight), not `/25`. Similarly `:641` is Screen Time `/20`, and `:238`/`:246` are Exercise/Sleep `/25`/`/35`.
  - Reword drift-table entry.
- **Affects:** drift table + Step 5.1.7 + Step 5.2.13's `grep` expectation.

#### C3. Step 13.3.1 verify math contradicts the RESOLVED plan's own computed v1 baseline
- **Location:** checklist Step 13.3.1 "Compare against pre-Phase-1 v1 total (≈19.34 per plan §4 math)" and "|v1.1_total − 19.34| ≤ 5. Plan expects v1.1 = 19.19, |Δ| = 0.15."
- **Evidence:**
  - RESOLVED plan §4 H6 whipsaw gate explicitly says: "`.default` mock: v1.1 = 19.19, v1 = 19.34, Δ = 0.15 ≤ 5 ✅" — the checklist's 19.34 matches this.
  - **BUT** the original audit H6 (see `260420-stress-algorithm-phase1-plan-audit.md` line 73) computed v1 = **18.6** for the same default mock using the same v1 formulas. The RESOLVED plan adopts 19.34 without showing its work for v1 specifically (only the H6-corrected delta). The audit's math: "ex contribution = 25 − avg(25·(7500/10000), 25·(340/600)) = 25 − avg(18.75, 14.17) = 25 − 16.46 = **8.54**; sleep contribution 1.05; diet 0; screen 9. Old total ≈ **18.6**."
  - By contrast the RESOLVED plan's per-factor v1 table (plan §4 "v1 (old) comparison for H6 whipsaw gate") gives Exercise=8.54, Sleep=1.80, Diet=0, Screen=9.00 → sums to **19.34**. The discrepancy is in Sleep: audit says 1.05, plan says 1.80, and a third-party recomputation of sleep under old curve (18.95 base + 5 bonus = 23.95 → contribution 25-23.95 = **1.05**) agrees with the audit, not the plan.
- **Impact:** The implementer will see their live DEBUG log print `Total stress : ~18.6/100` (actual v1 pre-change) or `~19.19/100` (actual v1.1 post-change) and have no reliable baseline to verify the ≤5 delta against. Step 13.3.1 asserts a number that may be wrong in the RESOLVED plan, and the checklist propagates it uncritically. Either the plan's 19.34 is a computation error or the audit's 18.6 is — one of them needs to be resolved before the exit gate is measurable.
- **Recommendation:**
  - Re-derive v1 default-mock sleep contribution from scratch: with totalHours=7.2, deepHours=2.3, under v1 formula: base (7..<9 band) = lerp(18, 20, t=0.1) = 18.2; deepBonus = clamp(2.3/7.2 / 0.18) · 5 = clamp(1.77) · 5 = 5.0; total = 23.2 → contribution = 25 − 23.2 = **1.80**. So plan's 1.80 is right; audit's 1.05 is wrong. But the checklist should **show this derivation** in Step 13.3.1 rather than just citing the number.
  - Add a "compute v1 baseline locally before Phase A" step: before 2.1.1, run the app with mock mode on and capture `Total stress : XX.XX/100` from the DEBUG log. That becomes the ground-truth v1 number for the whipsaw gate.
- **Affects:** Steps 13.3.1, 13.3.2.

---

### 🟠 HIGH (Should fix before proceeding)

#### H1. `StressLargeView.swift` silently dropped from the checklist despite being in plan §10 File Touch
- **Location:** RESOLVED plan §10 File Touch Summary lists `WellPlateWidget/Views/StressLargeView.swift` as "Modify — ensure contribution text uses `maxScore` if it renders one" (Task 5 sub). Checklist drift table says "Grep shows no `/25` or `maxScore` literals — **No edit needed in StressLargeView. Keep in smoke check only.**" — but there is no smoke-check step that touches this file.
- **Evidence:** Grep confirmed no `/25` or `maxScore` tokens in `StressLargeView.swift`. The drift-table conclusion is defensible (no edit needed). But the file is listed in plan §10 as touched. Either the plan is wrong (file should be dropped from §10) or the checklist is incomplete (should have a "confirm StressLargeView renders post-change" smoke step).
- **Impact:** A future reviewer cross-checking plan §10 "13 files modified" against the checklist's actual edits will find 12 files edited, 1 listed but not covered. Minor accuracy debt but this is exactly the kind of gap the Task-to-Step Traceability table is supposed to prevent.
- **Recommendation:**
  - Add a smoke step (e.g. Step 13.2.6.1): "Add Stress Large widget variant to home screen. Verify the large-size widget renders with correct factor bars and no `/25` artifacts." This also catches whether `StressLargeView` reads `factor.maxScore` or a literal.
  - OR update the RESOLVED plan §10 to remove `StressLargeView.swift` and the Net Surface Area from "13 files modified" → "12 files modified".
  - Pick one; drift table needs to close the loop.
- **Affects:** Traceability + Step 13.2.6 (new sub-step).

#### H2. `scoreHeader` anchor listed as `:300-312` in the drift table but the scaleEffect anchor range is really just `:243`
- **Location:** checklist drift table: "`StressView.swift:239-243` (scaleEffect) | `StressView.swift:242-243` | Same code, fewer lines". And Step 8.1.3 still asserts `:239-243`.
- **Evidence:** Actual file has `mainScrollView` calling `scoreHeader` at `:239`, followed by modifiers:
  - `:240` `.padding(.top, 20)`
  - `:241` `.padding(.horizontal, 20)`
  - `:242` `.opacity(scoreAppeared ? 1 : 0)`
  - `:243` `.scaleEffect(scoreAppeared ? 1 : 0.93, anchor: .topLeading)`
  So the scaleEffect is **only on :243**, not a multi-line thing. The drift table's "fewer lines" hedge is right that it's not `:239-243`, but "Same code" is misleading — the scale factor in-source is `0.93`, not `0.85` as the plan's sample Task 15 snippet says (`scoreAppeared ? 1.0 : 0.85`). The RESOLVED plan has `.scaleEffect(scoreAppeared ? 1.0 : 0.85, anchor: .topLeading)` in Tasks 8 and 15 code snippets — neither matches the live code's `0.93`.
- **Impact:** Step 15.1.3 says "Retain all existing modifiers (`.padding(.top, 20)`, `.padding(.horizontal, 20)`, `.opacity`, `.scaleEffect(... anchor: .topLeading)`)." — the implementer will keep the existing `0.93` which is correct. But if they blindly copy the plan's code snippet that shows `0.85`, they'll silently alter the entrance animation. The plan's snippets should have matched current source.
- **Recommendation:**
  - Update Step 8.1.3 to "Confirm at `:243` that `.scaleEffect(scoreAppeared ? 1 : 0.93, anchor: .topLeading)` is unchanged. Note the `0.93` scale factor — do NOT replace with the plan's `0.85` snippet."
  - Add a drift-table row confirming `:243` scaleEffect value is `0.93` (not `0.85`).
- **Affects:** Steps 8.1.3, 15.1.3.

#### H3. Step 5.1.7 does not show the correct per-line denominator in the implementer's log output
- **Location:** Step 5.1.7 says "Change each line to print the factor's actual weight" with bullets for each line's intended factor.
- **Evidence:** Line `:352` is the "has logs" branch of diet logging: `log("             → score=\(fmt2(score))/25  stressContrib=\(fmt2(dietFactor.stressContribution))/25  [\(dietFactor.detailText)]")`. It has TWO `/25` tokens. The step correctly says diet → `\(Int(StressScoring.Weights.diet))` = 20. Good. But `:349` is the "no logs" branch — currently `log("🥗 Diet → no food logged today score=\(fmt2(score))/25 stressContrib=\(fmt2(dietFactor.stressContribution))/25")`. After Task 4, `dietScore` returns `nil` when `hasLogs: false` — so the local `score` at line 344 will be `Double?`, and `fmt2(score)` breaks the build. The step doesn't explicitly mention that this line's `fmt2(score)` also needs `?? 0` unwrap (only calls it out for `exerciseScore`/`sleepScore`).
- **Impact:** Build break at `:349` that Step 5.1.7's verification ("DEBUG build succeeds") will catch — but not before the implementer discovers it the hard way. The intent is obvious, but spelling it out makes this a deterministic step rather than an "oh right, that too" discovery.
- **Recommendation:** Explicitly list all local variables that are now `Double?` and need `?? 0` for the `fmt2(...)` logger: `exerciseScore`, `sleepScore`, `score` (both diet refresh branches: `:349`, `:352`), and screen-time `score` at `:641`. Or rephrase: "Any `fmt2(X)` where X is now `Double?` needs `fmt2(X ?? 0)`."
- **Affects:** Step 5.1.7.

#### H4. Step 13.3.2 synthetic fixture math inherits an arithmetic error from RESOLVED plan §4
- **Location:** Step 13.3.2: "synthetic 'typical active user'"; RESOLVED plan §4 "Synthetic 'typical active user'" row (steps=10000 / energy=600 / sleep 8h-2.5h deep / ...).
- **Evidence:** Plan §4 computes synthetic user **Exercise = 0.00** contribution ("0.00" for both 10000 steps and 600 kcal energy) which is correct (both inputs max out → score=25 → contribution 25-25=0). But the row's v1 comparison in the same table says "v1 same inputs ≈ 25−25 + 25−(19.33+5) + 0 + 12 = 12.67". The v1 "sleep 8h/2.5h deep" under v1 formula: base (7..<9 band) = lerp(18, 20, t=(8-7)/2)=19.0; deepBonus = clamp(2.5/8/0.18) * 5 = clamp(1.74)*5 = 5.0; total=24.0 → contribution = 25-24 = 1.0, not 0.67 (the `19.33+5` in the plan's formula is an error). Screen time v1: min(25, 6*2) = **12.0** → contribution 12.0. Exercise v1: 0. Diet v1: 0. **v1 total = 0 + 1.0 + 0 + 12 = 13.0**, not 12.67.
  v1.1: Exercise 0 + Sleep 0.7 + Diet 0 + Screen 15 = **15.7** (plan correct on this).
  So |Δ| = 15.7 - 13.0 = **2.7**, not 3.0 as plan/checklist say. Small error, still within ≤5 gate — but the checklist will have the implementer confirming "v1 total ≈ 12.67" which the DEBUG log won't produce.
- **Impact:** Minor — the exit gate still passes, but the checklist's "expected" value is off by 0.33 from the actual v1 math. Confusion.
- **Recommendation:** Re-derive the synthetic fixture v1 total step-by-step in Step 13.3.2. Publish the derivation. Or at minimum, relax the assertion from "≈ 12.67" to "within 13 ± 1" to absorb the rounding.
- **Affects:** Step 13.3.2.

---

### 🟡 MEDIUM (Fix during implementation or explicitly accept)

#### M1. Step 5.B ("All 4 target builds must now be clean") hides that the tree is broken between Phase A and Phase B
- **Location:** Steps 2.1.1 / 3.1.1 / 3.1.2 / 4.1.1 / 4.2.1 each say "Verify: inline read only — no build yet" or "Build → still expected to fail". Step 4.2.3 captures the break explicitly. Then Phase B (Steps 5.1.1–5.1.7, 5.2.1-5.2.13, 14.1) migrates consumers. Step 5.B runs the 4-target build and demands green.
- **Evidence:** This sequencing is actually correct — the checklist explicitly flags the build break at 4.2.3 ("Do not commit yet — the tree is broken"). Good.
- **Impact:** None — if the implementer runs builds in Phase A steps they will see errors, but the checklist warned them. This is a strength, but it interacts with CI / pre-commit hooks: if the dev's git setup auto-builds on save, every save between 2.1.1 and 5.B will fail. Worth a note.
- **Recommendation:** Add a note at the start of Phase A: "⚠️ The main branch compiles between every step EXCEPT inside Phase A. If you commit between 2.1.1 and 5.B, CI will fail. Commit only at the 🟢 Checkpoints." Checkpoint CP1 already serves this role but the note makes it explicit.
- **Affects:** Phase A header.

#### M2. Drift table row for `StressDeepDiveSection.swift:72–82` says "4 call sites at lines 75, 76, 79, 80" — correct but the actual `sleepScore` call spans lines 76-78
- **Location:** checklist drift table; Step 14.1.
- **Evidence:** `:76-78` is `let sl = StressScoring.sleepScore(summary: d.sleepHours.map { h in ... })` — a multi-line expression. The `?? 0` must go at end of the expression (after the closing `})` on :78). Step 14.1 captures this: "append `?? 0` at end of the expression".
- **Impact:** Low — the intent is clear.
- **Recommendation:** No change needed, but the drift table saying "4 call sites at lines 75, 76, 79, 80" would be more accurate as "call sites at :75, :76-78, :79, :80 (4 total, sleepScore spans 3 lines)".
- **Affects:** drift table cosmetic.

#### M3. Step 15.2.1 says insert "immediately after the `guard !usesMockData else { return }` line" at `:372`, but `:372` is the function signature line
- **Location:** Step 15.2.1: "File: `StressViewModel.swift:372` (top of function body, immediately after the `guard !usesMockData else { return }` line)"
- **Evidence:** Line 372 is `func logCurrentStress(source: String = "auto") {` — the function signature. Line 373 is the `guard !usesMockData` line. So the insertion should be at/after line 374, not 372.
- **Impact:** Minor off-by-2. The descriptive text ("immediately after the guard") is correct; only the line anchor is off.
- **Recommendation:** Update to `:373-374 (after the guard !usesMockData else { return } line at :373, insert new guard at :374)`.
- **Affects:** Step 15.2.1.

#### M4. Step 5.2.13 grep-sanity regex exception list includes `StressModels.swift:131` but that line does NOT match the pattern `/25`
- **Location:** Step 5.2.13: "confirm no literal `/25.0` fraction or `"/25"` string label remains outside of the preview fixture at `StressModels.swift:131` (which is the neutral Exercise stub and intentionally keeps `maxScore: 25`)"
- **Evidence:** Line 131 reads `maxScore: 25,` — no `/25` substring. So `grep "/25"` wouldn't hit it. The exception-list clause is harmless but confusing — it implies the grep might hit this line when it can't.
- **Impact:** None functional. Implementer might second-guess whether the exclusion logic is correct.
- **Recommendation:** Remove the `StressModels.swift:131` clause from Step 5.2.13 — it's not a grep match. Or clarify: "`StressModels.swift:131`'s `maxScore: 25` is intentionally kept because this is the Exercise neutral stub (Exercise's weight IS 25); but this line doesn't match the `/25` grep pattern."
- **Affects:** Step 5.2.13.

#### M5. Step 11.1.1 says "after `.default` at line 49" but `.default` IS line 49 (a one-line static let)
- **Location:** Step 11.1.1: "File: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` (after `.default` at line 49)"
- **Evidence:** Line 49 is `static let default: StressMockSnapshot = makeDefault()` — one line. Insertion goes at line 50 or later.
- **Impact:** Cosmetic. The intent is clear.
- **Recommendation:** Update to "after line 49 (the `.default` static let declaration). Insert new `.sparse` static + `makeSparse()` factory starting at approximately line 51 (after a blank line)."
- **Affects:** Step 11.1.1.

#### M6. Step 7.1.1 places `Confidence` enum via `extension StressViewModel { ... }` but Step 7.1.2 places `factorCoverage` / `stressConfidence` "inside the class, next to other computed properties around line 79-95"
- **Location:** Steps 7.1.1 & 7.1.2.
- **Evidence:** The RESOLVED plan Task 7 code block puts **both** the extension and the computed properties. The plan's code snippet shows:
  ```swift
  extension StressViewModel {
      enum Confidence: ...
  }
  var factorCoverage: Int { ... }
  var stressConfidence: ...
  var shouldHideScoreForLowConfidence: ...
  ```
  The `var factorCoverage` declaration has no containing scope in the plan snippet — it's top-level-file code outside any class. That's a Swift compile error (can't have top-level stored properties in a file containing a class). In the checklist, Step 7.1.2 fixes this by saying "inside the class", but Step 7.1.1 says "at end of file, before closing brace" — ambiguous whether this means "end of StressViewModel class" or "end of file".
- **Impact:** If implementer reads Step 7.1.1 as "end of file after the class closing brace" and then Step 7.1.2 as "inside the class", the extension and the vars end up in two different places. This works but is messier than the plan snippet implies. Also the `var shouldHideScoreForLowConfidence` in Step 7.1.3 says "same vicinity" — vicinity of what?
- **Recommendation:** Be explicit:
  - Step 7.1.1: "Add an `extension StressViewModel { enum Confidence: String { ... } }` block at the end of the file, AFTER the class's closing brace."
  - Step 7.1.2: "Add `var factorCoverage: Int { ... }` and `var stressConfidence: StressViewModel.Confidence { ... }` inside the class body, adjacent to the existing `totalScore` / `stressLevel` properties around `:79-95`."
  - Step 7.1.3: "Add inside the class body, adjacent to the vars from 7.1.2."
- **Affects:** Steps 7.1.1, 7.1.2, 7.1.3.

#### M7. Step 10.1.2 doesn't specify exact log-text format and will likely produce a subtly different output from `mockMode`'s style
- **Location:** Step 10.1.2 "DEBUG-gated `get` checking `UserDefaults.standard.object(forKey:) != nil` else `false`; DEBUG `set` writes to UserDefaults and logs via `WPLogger.app.info`"
- **Evidence:** The existing `mockMode` setter logs: `WPLogger.app.info("Mock Mode → \(newValue ? "ENABLED" : "DISABLED")")` — note both states are uppercase. The plan's Task 10 code shows `WPLogger.app.info("Stress Algorithm V2 → \(newValue ? "ENABLED" : "DISABLED")")` — matches. But Step 10.1.3 says the logCurrentMode() line is `"Stress v2  : \(stressAlgorithmV2 ? "ENABLED" : "disabled")"` — lowercase "disabled" intentionally for the spartan log (per L5 resolution). So the **setter** uses ENABLED/DISABLED (uppercase) and the **startup log** uses ENABLED/disabled (mixed case). This is intentional per the RESOLVED plan but the checklist doesn't explain why they differ — an implementer might "fix" them to match.
- **Impact:** Low — the RESOLVED plan §0 changelog for L5 documents this. Just cite it.
- **Recommendation:** Add a one-liner to Step 10.1.3: "Note: mixed case 'ENABLED/disabled' is intentional — matches the existing spartan `logCurrentMode()` style where false-states are lowercase (see plan L5 resolution)."
- **Affects:** Step 10.1.3.

#### M8. Step 13.2.3 says "Swap the VM's mock snapshot source to `.sparse`" without showing where the swap happens
- **Location:** Step 13.2.3: "Change: Swap the VM's mock snapshot source to `.sparse` (temporary — via an in-code branch or a one-line edit for the smoke test)."
- **Evidence:** `mockSnapshot` is injected via `StressViewModel`'s init (need to check exactly where). The checklist doesn't say *where* this swap occurs — in the VM's mock branch, in a Preview, in the factory? The same vagueness applies to Step 13.2.4.
- **Impact:** Implementer will have to hunt for the injection point. This is a smoke test, not a code change — so the only clean path is via a Preview override. But Step 13.2.3 runs in the simulator (`Launch app in simulator`), which reads from the actual VM init path, not a Preview. So the "one-line edit" has to change the production code temporarily — and that needs to be reverted before CP4.
- **Recommendation:** Be specific: "In `StressViewModel.swift`, find the line that reads `StressMockSnapshot.default` (likely in an init or factory — grep for it). Temporarily change to `.sparse`. Reload simulator. After verifying, revert back to `.default` before continuing." Also add a revert-checkbox.
- **Affects:** Steps 13.2.3, 13.2.4.

#### M9. Step 8.1.2 plan-code snippet includes `.tracking(0.4)` that isn't in the RESOLVED plan Task 8 code block
- **Location:** Step 8.1.2: "`Text(...)` at `size: 13 medium rounded`"
- **Evidence:** RESOLVED plan Task 8 code snippet explicitly has `.tracking(0.4)` on the label Text. Checklist's prose summary omits it. Minor but if the implementer builds strictly from the prose they'll miss the letter-spacing.
- **Impact:** Low — purely cosmetic.
- **Recommendation:** Add "Include `.tracking(0.4)` on the badge label Text (matches the plan's Task 8 code snippet)."
- **Affects:** Step 8.1.2.

---

### ⚪ LOW / Nits

#### L1. Drift-table claim "StressView.swift:300-312 (scoreHeader) | 2-line drift; body unchanged" is accurate but the plan cited `:298-312`
- The plan's Task 8 file header says `StressView.swift:298-312`; actual `:300-312`. Drift table reconciles it. Good.

#### L2. Step 0.2's `git checkout -b stress/phase1-foundation` branch name is reasonable but mixes punctuation styles (`/` slash, hyphens). Consistent with the project's history (`feat(stress-p1):`).

#### L3. Step 13.4.2 verification `git log --oneline stress/phase1-foundation ^main` will only show commits unique to the branch, which is correct. But the checklist promises "the 4 checkpoint commits + the baseline + this final commit" = 6 commits. Counting: baseline (0.4) + CP1 (Task 1 commit-point) + CP1 (end of Phase B) + CP2 + CP3 + CP4 + final (13.4.1) = 7 commits. Actually re-reading: "after 1.1.1" commit is an intermediate commit inside Phase A, so CP1 is the end of Phase B. So: baseline, Task 1 intra-commit, Phase-B end (CP1), CP2, CP3, CP4, final = **7 commits**, not 6. Minor count error in 13.4.2.

#### L4. Step 0.3 baseline build and Step 13.1.1 final build use identical commands — could note the final uses same commands for regression symmetry.

#### L5. Step 5.2.10 / 5.2.11 / 5.2.12 are comment/literal updates — Verify steps say "Xcode preview on the widget scales the 4 bars against their correct maxes" (5.2.10) but this requires running SwiftUI Previews, which needs the widget bundle to preview. The check "Xcode preview renders" is weaker than "build succeeds"; preferable to just say "Widget scheme build succeeds".

#### L6. Step 11.1.2 "Temporarily swap StressView preview to .sparse" then 11.1.3 "Revert preview to .default" — these should be linked with a "Do not commit the preview swap" warning. The 🟢 CP3 commit runs immediately after, risking the swap being included.

#### L7. Drift-table says "`SharedWidgetViews.swift:104, 109, 124` | all 3 confirmed" — but the actual `/25.0` occurrences are at `:104` and `:109`, and the `"/25"` string at `:124`. That's what it means, but listing them as 3 equivalents can confuse: `:104` and `:109` are *number* divisions, `:124` is a *string* literal. Steps 5.2.1-5.2.3 correctly differentiate, so no issue in the checklist body.

#### L8. Step 15.3.1 tells the implementer to "build a minimal snapshot with sleep only" but `StressMockSnapshot` requires 19+ `let` fields including `currentDayLogs: [FoodLogEntry]` (SwiftData model). Building a 1-factor snapshot inline is heavier than the "one-liner" the step promises. Either (a) add an explicit `makeSingleSleepFactor()` factory to `StressMockSnapshot.swift` (code change, should have its own step), or (b) rely on `.sparse` with an additional `screenTimeHours: 0` override, which is closer to what the step implies but still not a one-liner.

---

## Strengths (brief)

- **Phase A → Phase B → CP1 sequencing** correctly encapsulates the build-break window. The "Do not commit yet" note at 4.2.3 is excellent.
- **Task 14 (StressDeepDiveSection) is inside Phase B, before CP1** — the C1 audit finding from the first pass is fully defanged.
- **Honest-mode ordering is correct:** confidence-badge computed vars (Step 7.1.2) precede honest-mode wrapper (Step 15.1.2), which precedes the 1-factor mock smoke test (Step 15.3.1 / 13.3.4). No step references a symbol that doesn't yet exist.
- **Traceability matrix (§Task-to-Step)** explicitly lists Task 9 as "4.2.2 (comment only)" — correctly captures the RESOLVED plan's "no code" decision. Not silently dropped.
- **Exit-gate summary table** maps each strategy/plan criterion to specific steps. Easy to audit.
- **Permission-dialog section** is present and explicit about HealthKit + Screen Time prompts — meets the audit requirement.
- **Drift-table at top** is a real attempt at reconciliation, better than most checklists.
- **4 checkpoints (CP1-CP4) are real compile-clean states**, each with a real commit message. CP1 in particular is non-trivial — it's the "all consumers migrated" state.
- **Honest-mode × confidence-badge interaction** — Step 15 verify steps cover the "1 factor valid → placeholder appears AND .low label never renders" case, addressing §11 of the RESOLVED plan.
- **Grep sanity sweep (5.2.13)** exists (even if its exception list has a typo — see M4).

---

## Summary of Affected Steps by Severity

| Severity | Steps |
|---|---|
| 🔴 | 5.1.6, 5.1.7, 13.3.1 |
| 🟠 | 8.1.3, 13.2.6 (new), 13.3.2, 15.1.3 |
| 🟡 | Phase A header, 5.1.7, 5.2.13, 7.1.1, 7.1.2, 7.1.3, 8.1.2, 10.1.3, 11.1.1, 13.2.3, 13.2.4, 14.1 (drift-table wording only), 15.2.1 |
| ⚪ | 0.3, 5.2.10-5.2.12, 11.1.2, 11.1.3, 13.4.2, 15.3.1 |

---

## Recommendations (prioritized)

1. **(C1)** Rewrite Step 5.1.6 with correct line anchors (:621-625, :634-638, :646-650) and explicitly list all 3 `maxScore: 25` literals including the none-branch.
2. **(C2)** Rewrite Step 5.1.7 to say "10 edits total (5 lines × 2 tokens each)" and enumerate the correct per-line denominator (exercise /25, sleep /35, diet /20×2, screen /20).
3. **(C3)** Re-derive v1 baseline for default mock step-by-step in Step 13.3.1 (sleep contribution = 1.80, exercise 8.54, diet 0, screen 9 → total 19.34). Or add a pre-Phase-A step that captures the live DEBUG log's `Total stress: XX.XX/100` as the ground-truth baseline.
4. **(H1)** Resolve the `StressLargeView.swift` gap — either add a smoke step or remove from plan §10.
5. **(H2)** Update drift table + Step 8.1.3 to reflect `.scaleEffect` is only at `:243` with scale factor `0.93` (not plan-snippet's `0.85`).
6. **(H3)** Step 5.1.7 must explicitly list `:349` `fmt2(score)` as needing `?? 0` unwrap (score is now `Double?`).
7. **(H4)** Re-derive synthetic fixture v1 total in Step 13.3.2 (≈13.0, not 12.67).
8. **(M1–M9)** Tighten per-step annotations before execute.
9. **(L1–L8)** Sweep during implementation.

---

**Verdict:** **Ready-with-fixes.** Address the 3 🔴 items (all involve incorrect line anchors or math that will directly mislead the implementer) and the 4 🟠 items (missed file, scale-factor drift, `Double?` unwrap gap, synthetic-fixture math) before starting `/develop implement`. The 🟡/⚪ items can be cleaned up during implementation without risk to the build.

**Blocker count:** 3 Critical, 4 High. Total blocker-class issues: 7 of 73 steps affected.

---

**Audit complete.**
