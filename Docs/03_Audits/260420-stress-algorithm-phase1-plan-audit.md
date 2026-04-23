# Plan Audit Report: Stress Algorithm — Phase 1 (Foundation & Quick Wins)

**Audit Date:** 2026-04-20
**Plan Version:** `Docs/02_Planning/Specs/260420-stress-algorithm-phase1-plan.md` (Status: "Ready for audit")
**Auditor:** audit agent
**Verdict:** **NEEDS REVISION** — one critical miss (unlisted `StressScoring` consumer that will fail to build), two high-priority contradictions with the strategy, multiple arithmetic errors in verification tables, and two additional hard-coded `/25` sites the plan does not cover.

---

## Executive Summary

The plan is well-structured, grounded in the strategy and research, and the core scoring rewrites (Tasks 1–4) are sound. However, the "Preconditions" claim that the scoring functions only have one call site is wrong — `StressDeepDiveSection.swift` calls all four `StressScoring` functions directly and will fail to compile once the signatures change to `Double?`. The plan also silently drops the strategy's "honest mode" default (a committed Phase 1 decision point), partially ships Q5 against the strategy's explicit "move Q5 to P2" instruction, misses two `/25` hard-codes (`DietDetailView:82`, `ScreenTimeDetailView:80`), and publishes verification numbers (§4 and Task 5) that are arithmetically incorrect. None of these are unfixable, but the checklist cannot be generated as-is without users hitting a build break.

---

## Issues Found

### 🔴 CRITICAL (Must fix before proceeding)

#### C1. `StressDeepDiveSection` is an unlisted direct consumer of all 4 `StressScoring` functions
- **Location:** Plan §2 (Preconditions), §5b (Ripple Audit — AI Report), §8 (Risks row: "The Double? return change across 4 scoring functions cascades more call sites than expected"), §10 (File Touch Summary).
- **Problem:** The plan asserts in §2 and §8 that the only call sites of `StressScoring.*` are `StressViewModel.loadData` / `refreshDietFactor` / `refreshScreenTimeFactor`. Grep against the repo shows `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift:75–80` calls `StressScoring.exerciseScore`, `.sleepScore`, `.dietScore`, and `.screenTimeScore` directly and stores the results in `let ex: Double`, `let sl: Double`, `let dt: Double`, `let sc: Double`. Once Tasks 2–4 change those signatures to return `Double?`, this file will not build.
- **Impact:** Task 13 build will fail on the main `WellPlate` target. The plan's §5b ripple audit for the AI report reads "Does it break? No. The scalar shape is unchanged. … No factor-level reads." That statement is false — `StressDeepDiveSection.factorDecompItems` is exactly a factor-level read and drives the "Factor Breakdown: Best vs Worst Days" chart.
- **Recommendation:**
  - Add `StressDeepDiveSection.swift` to §10 File Touch Summary and §5b Ripple Audit.
  - Add a sub-task to Task 5 to update the four call sites in `factorDecompItems` to unwrap the new `Double?` returns (or substitute `?? 0` to preserve existing behavior for days with no data, since the report is rendering historical averages, not today's score).
  - Update the `(exercise, sleep, diet, screen)` tuple types to `Double?` and handle nil in the chart — or explicitly unwrap with a defaulted 0 and document that missing-data days are excluded from the decomposition chart. The caller can keep using `Double` if it defaults via `?? 0`, but the plan must say so.
  - Correct the §8 risk row that claims "only call site is StressViewModel…"

---

### 🟠 HIGH (Should fix before proceeding)

#### H1. Plan drops the strategy's committed "honest mode" default for Q2
- **Location:** Plan §9 Open Questions #2; strategy §3 Phase 1 decision point & §4 Migration.
- **Problem:** Strategy line 76 ("default to YES for Q2: if <2 factors have valid data, show 'Log more to see your stress score' instead of a number") and line 236 ("If fewer than 3 factors have `hasValidData`, show 'Log more…'") both commit honest-mode as a Phase 1 default. The plan explicitly defers it to Phase 2 with a self-justification that "decoupling the mock-default rendering path from an extra branch keeps the verification surface small." This reverses a strategy-level decision without authorization.
- **Impact:** The plan's low-confidence UX path (H4 below) becomes a misleading small number instead of the committed "Log more" fallback. Strategy §7 success-metrics "Honest-mode triggers" also tracks this — if the feature is not built, the metric cannot be measured.
- **Recommendation:** Either (a) restore honest mode as a Phase 1 requirement (add a Task 8b: when `factorCoverage < 2`, replace the `NN/100` hero with a "Log more to see your stress score" placeholder and skip `StressReading` logging for that day), OR (b) get explicit approval to defer in a /develop resolve pass and log the deviation in the strategy doc. Current plan wording ("strategy §3 decision points deferred") is not accurate — strategy §3 decided YES, not deferred.

#### H2. Q5 is neither shipped nor cleanly deferred — creates a permanent dead parameter
- **Location:** Plan Task 4, Task 9; strategy §3 Phase 1 decision: "Q5 feasibility — if not [available], Q5 moves to P2 and P1 keeps 5 items."
- **Problem:** Strategy says Q5 should be moved entirely out of Phase 1. Plan adds `eveningHours: Double? = nil` to `StressScoring.screenTimeScore` as Phase-1 API plumbing, and Task 9 calls this a "partial ship." The parameter is never populated by any call site, never read by a test, never toggled by a flag. It is pure dead code until Phase 2 touches `ScreenTimeManager`, which is at minimum several weeks out.
- **Impact:**
  - Adds one unused parameter with a default value — reviewers will question why.
  - The Phase 2 `StressScoringV2` service (strategy §2, §3 P2) will live beside v1 as a new file. Phase 2 will likely build its own `screenTimeScore` with evening handling in `StressScoringV2`, not extend v1. So the parameter may never be wired in v1 at all before v1 is deprecated (strategy §6: "v1 deprecated after P3 flip").
  - Swift does not warn on unused default parameters, so it will silently linger.
- **Recommendation:** Drop the `eveningHours` parameter from Phase 1 entirely. Keep `screenTimeScore(hours: Double?)` single-argument. Add a one-line comment: `// Q5 (evening ×1.5 multiplier) ships in StressScoringV2 — requires hourly-bucket refactor of ScreenTimeManager, tracked in Phase 2.` This aligns with strategy's "Q5 moves to P2" directive and avoids dead code.

#### H3. Missing `/25` hard-codes — `DietDetailView.swift:82` and `ScreenTimeDetailView.swift:80`
- **Location:** Plan §5a claims "This is a 3-file cosmetic sweep" (`SharedWidgetViews`, `StressFactorCardView`, `ProfileView`) and §10 File Touch Summary; grep reveals two more.
- **Problem:** `DietDetailView.swift:79–82` renders `Text("/25")` in the factor header, and `ScreenTimeDetailView.swift:77–80` does the same. After the diet factor's maxScore becomes 20 and sleep becomes 35, these headers will read "18 /25" (for a diet factor whose actual max is now 20). The plan's §5a "Net surface area" claim that the sweep is 3 files is wrong — it's 5.
- **Impact:** Sleep detail view currently does not hard-code `/25` (verified), but diet and screen-time detail views do. On ship, users tapping into Diet detail will see "X /25" where X can now only go to 20. Visually wrong; cross-checks against the main card will differ ("Diet 17/20" on card, "17 /25 stress pts" on detail sheet).
- **Recommendation:** Add both files to §10 and to Task 5's sub-checklist. Verify `SleepDetailView.swift` and `ExerciseDetailView.swift` at the same time (grep clean as of audit, but verify the files don't have the pattern elsewhere — a full grep on `/25` across Stress views should be part of Task 13 smoke). Update §5a "total 3-file cosmetic sweep" to "5-file cosmetic sweep".

#### H4. Low confidence + low score is a more misleading UX than the phantom 12.5 it replaces
- **Location:** Plan §4 "Strategy exit-gate question — could a max-screen-time-only user still hit Very High?"; §8 Risks (not addressed).
- **Problem:** The plan correctly notes that a user with *only* screen time logged will cap at 20/100 → "Excellent". This is called "intended Q2 behavior." But the same logic means a user who sleeps 3 hours and logs nothing else has a total stress score of `(35 - 0) = 35` → "Good" band. The score badge says "Good" + "Low confidence · 1/4 factors". A low-confidence number is arguably a bigger trust failure than a neutral imputation, because it looks definitive on the hero and the badge is small, secondary text. The brainstorm's honest mode (strategy §4 commit) exists precisely to prevent this misreading — it withholds the number entirely below a coverage threshold.
- **Impact:** Users with sparse logs who previously saw a 50/100 (misleading-high) will now see a 35/100 (misleading-low) — possibly worse, because it looks "actionable." This partially undermines the strategy's exit-gate claim that sparse users "stop seeing a misleading 50/100."
- **Recommendation:** Tightly coupled to H1 — restore honest mode. If not, at minimum make the confidence badge prominent: place it *above* the score (so it reads Low confidence before the number), or gray out the score digits at Low confidence. Plan Task 8 puts the badge below the score in secondary styling — this is the weakest possible placement for a trust signal.

#### H5. Task 5 verification numbers are arithmetically wrong, misleading the dev smoke test
- **Location:** Plan Task 5 "Verification" bullet (expected ranges for mock defaults); §4 mock scenario table.
- **Problem:** Hand-calculating against the Phase-1 formulas and `StressMockSnapshot.default` (steps=7500, energy=340, sleep 7.2h/2.3h deep, 3 diet logs summing to 64g protein/13g fiber/22g fat/84g carbs, 4.5h screen):
  - Exercise score = avg(25·min(1, 7500/7000), 25·min(1, 340/600)) = avg(25, 14.17) = **19.58** (plan says "≈ 25 → contribution 0"; actual contribution = 25 − 19.58 = **5.42**).
  - Sleep score = 35·0.728 + 7 (deep bonus, ratio 0.319 → full) ≈ **32.48**; contribution = 35 − 32.48 ≈ **2.52**. (Plan estimate "~32/35 → contribution ~3" is approximately correct.)
  - Diet: protein 64/60=1.0, fiber 13/25=0.52, balancedScore=0.784; fat 22/65=0.338, carbs 84/225=0.373, excessScore=0.357; netBalance = clamp((0.784 − 0.214 + 0.5)/1.0) = clamp(1.07) = 1.0; score = 20·1.0 = **20**; contribution = 20 − 20 = **0**. (Plan says "score ≈ positive netBalance ~0.55 × 20 = 11 → contribution ~9" — wrong by ~9 pts.)
  - Screen time = min(20, 4.5·2.5) = **11.25**; contribution = 11.25. (Correct.)
  - Total ≈ 5.42 + 2.52 + 0 + 11.25 = **~19.2** → **Excellent**, not **~23/Good** as plan §4 states.
- **Impact:** The dev following the checklist will log `Total stress : 19.2/100 → Excellent` and think the implementation is broken when it's actually correct. Either the implementation or the plan will get retuned incorrectly. Similarly, §4 "mock default expected total ~23, level Good" in the scenario table is wrong.
- **Recommendation:** Recompute verification tables from the actual formulas. Publish both the expected `totalScore` and each factor's contribution for `StressMockSnapshot.default` and `.sparse`. Doing this math in the plan (not the checklist) is the correct place — it's part of how we prove Task 5 is correct before writing the checklist.

#### H6. Strategy exit gate "score shifts ≤5 points vs old algorithm" is not acknowledged by the plan
- **Location:** Plan §7 Exit Criteria; strategy §3 Phase 1 Exit Gate bullet 2 ("Stress score for an average user shifts by ≤5 points on the same inputs vs old algorithm (proves re-weight didn't whipsaw)").
- **Problem:** The plan's §7 exit criteria lists 11 items but omits the strategy's quantitative whipsaw guard. With the default mock, v1 would compute: ex contribution = 25 − avg(25·(7500/10000), 25·(340/600)) = 25 − avg(18.75, 14.17) = 25 − 16.46 = **8.54**; sleep score under old curve (18.95 base + 5 bonus = 23.95, clamped 23.95) → contribution 1.05; diet old formula identical numerically = 25 so contribution 0; screen = min(25, 9) = 9. Old total ≈ 8.54 + 1.05 + 0 + 9 = **18.6**. New total ≈ 19.2. Delta ≈ 0.6 — within ≤5. So the gate *is* met for this fixture, but the plan doesn't verify it. For a user with steps=10000/energy=600/sleep 8h/3h deep/balanced diet/6h screen, the delta will be larger and should be checked.
- **Impact:** Plan may be shipped without validating the strategy's whipsaw bound, leading to a surprise "my score jumped" user report that the strategy committed to guarding against.
- **Recommendation:** Add an exit criterion: "On `StressMockSnapshot.default` and a manually constructed all-typical-values fixture, `|v2_total − v1_total| ≤ 5`. Publish the math in the plan." Also add this as a smoke-test line item in Task 13.

#### H7. Task 10 "Why" misquotes the strategy
- **Location:** Plan Task 10 "Why" bullet.
- **Problem:** Plan says `Strategy §3 Phase 1 explicitly lists "Add AppConfig.stressAlgorithmV2: Bool flag (default false) — just the flag, no v2 code yet."` Grep against the strategy doc returns **no matches** for "no v2 code yet" or "just the flag." The strategy actually assigns `AppConfig.swift` to **Phase 2** in §6 File Touch Summary line 299 (`| WellPlate/Core/AppConfig.swift:14-22, 29-46 | P2 | Add stressAlgorithmV2 flag …|`). Strategy §4 line 223 says "defaults to `false` in P1–P2" which implies existence in P1 but doesn't prescribe adding the flag in P1.
- **Impact:** Plan appears to be citing strategy to justify Task 10, but the citation is fabricated. Task 10 itself is defensible (placeholder flags are cheap and preserve the Phase 2 API), but the provenance is wrong. Fixing this is also an opportunity to reconcile: does the flag live in P1 or P2?
- **Recommendation:** Replace the "Why" with the actual strategy evidence: "Strategy §4 Feature-flag line 223 says the flag 'defaults to false in P1–P2'; adding it as an unused placeholder in Phase 1 is the smallest surface change that lets Phase 2 land as additive." Alternatively, move Task 10 to Phase 2 per strategy §6 table and drop it here.

---

### 🟡 MEDIUM (Fix during implementation or in plan before checklist)

#### M1. Deep-sleep 70% cap — arbitrary choice, no research anchor
- **Location:** Plan Task 3 "Q4: absolute deep-sleep floor — cap at 70% of max if <45 min" and §8 risk row 3.
- **Problem:** Research §3b says "If deep sleep duration falls below 45 minutes, cortisol clearance is incomplete, leading to higher baseline stress the following morning." The research never quantifies the magnitude — it just flags the threshold. The plan picks 70% by engineering taste. 70% of 35 = 24.5, which on top of a well-rested night with 7.2h and 40min deep gives you contribution 35 − 24.5 = 10.5/35 of "stress" just for missing the deep-sleep threshold. That feels aggressive for what the research calls "incomplete" rather than "absent" clearance.
- **Impact:** A user with consistent 7.5h sleep but low deep-sleep architecture (common in 45+ age group per §3b age-factor note) will always hit this cap — making sleep look like a persistent stressor when it's actually fine on duration. Combined with the age-factor research (deep-sleep declines to 10% by 60s = 45 min on 7.5h), this cap disproportionately punishes older users. Strategy §3 Phase 3 adds age-band thresholds (S3), but in Phase 1 there's no adjustment.
- **Recommendation:** Either (a) cite the 70% number as an engineering choice and commit to revisiting once Phase 3 adds age bands, or (b) use a gentler cap like 85% of max so the contribution penalty is ~5 pts rather than ~10 pts for a "borderline" night. Plan §8 risks acknowledges this weakly — make it explicit: "Cap severity re-evaluated in Phase 3 alongside age-band lowered thresholds."

#### M2. Confidence badge depends on `stressFactorCount`/`factorCoverage` — ok, but badge UI is small and easy to miss
- **Location:** Plan Task 8 — confidence badge below `/100` in secondary styling.
- **Problem:** Strategy §3 P1 exit gate says "Confidence badge shows Low when <3 factors have data, High when 4/4." Plan's implementation is font size 11, `.secondary` foreground, 5-pt padding. On a phone screen with the 72-pt hero number, this is visually dwarfed. Combined with H4, a low-confidence/low-score state will read to users as "Very good stress today" with a tiny Low-confidence note they won't notice.
- **Impact:** Strategy's trust signal gets diluted. Aligns with the brainstorm §4 UX risk ("Users can't tell when the score is calibrating vs reliable").
- **Recommendation:** Bump the badge to at least font size 13, medium weight; consider placing it above the score when `factorCoverage ≤ 2` so it reads before the number. Or — simpler — make it a full-width pill, not a compact one.

#### M3. `StressMockSnapshot.sparse` factory is underspecified
- **Location:** Plan Task 11.
- **Problem:** Plan says `steps: 0, energy: 0, … currentDayLogs: []`. But `fetchStepsSafely` filters out zero values (`return total > 0 ? total : nil` at `StressViewModel.swift:492`). In mock mode, however, `refreshScreenTimeFactor` doesn't run through that safe fetcher — it uses `snap.screenTimeHours` directly. And the code flow for exercise in mock mode needs tracing: look at the plan itself — it does not show how `.sparse` injects "steps = nil / energy = nil" vs "steps = 0 / energy = 0", because the snapshot struct declares `let steps: Double` (non-optional). Plan's bullet says "steps: 0, interpreted as no data by fetchStepsSafely > 0 filter" but in mock mode `fetchStepsSafely` is never called — the plan would have to change the mock path to actually mimic nil. Grep `StressViewModel.swift` around `loadData` — there's no mock-specific branch for exercise; the mock steps/energy are stored but the actual value used is what's passed to `StressScoring.exerciseScore`, which is the snapshot's `steps` / `energy` scalars unless the VM has mock branching I missed.

  Actually re-reading `StressViewModel.swift:214-220`, `loadData` calls `fetchStepsSafely` whether or not we're in mock mode — and `fetchStepsSafely` calls `healthService.fetchSteps`. In mock mode there's no `mockHealthService` path that returns snap values. Check: `HealthKitServiceFactory.shared` — is there a mock path? If not, mock mode returns nil from HealthKit and the mock snapshot's `steps` / `energy` scalars are never consumed. This is an existing bug the plan inherits, not one the plan creates.
- **Impact:** Plan's `.sparse` factory may not actually produce the behavior it claims ("Exercise factor shows 'No data'"). Depends on how mock mode is wired for HK.
- **Recommendation:** Before writing the checklist, verify: in mock mode does `fetchStepsSafely` return `snap.steps` or nil? If nil, the mock snapshot's `steps` field is already unused and `.sparse` is trivially unchanged from `.default` for exercise. Either way, document the actual behavior in Task 11. A cleaner `.sparse` factory also has `steps: nil, energy: nil` — which requires making those fields `Double?`. That's a breaking change to the snapshot struct. Decide and document.

#### M4. `StressConfidence` enum naming collision risk
- **Location:** Plan Task 7 — `enum StressConfidence: String` added to `StressViewModel.swift`.
- **Problem:** The plan puts `StressConfidence` as a top-level type in the same file as `StressViewModel`. File-scope types in Swift are still module-scope. If Phase 2 `StressScoringV2` defines its own `StressConfidence` (e.g., different levels like `.calibrating` that was called U4 in the brainstorm), there will be a collision. Strategy §3 P4 lists "U4 calibrating banner" which is a sibling concept. Consider making it `StressViewModel.Confidence` (nested type) or `ScoreConfidence` namespaced.
- **Impact:** Low, but a future Phase 2/P4 merge conflict.
- **Recommendation:** Name it `StressViewModel.Confidence` or `StressFactorCoverage` for clarity; either avoids collision with later "Fully Calibrated" terminology.

#### M5. Widget `WidgetStressFactor.maxScore` comment still says `// 25`
- **Location:** `WellPlate/Widgets/SharedStressData.swift:95` — `let maxScore: Double        // 25`
- **Problem:** Plan §5a says `WidgetRefreshHelper.swift:14` "already forwards `factor.maxScore` correctly" — true — but the shipping struct's doc comment says `// 25`. When Task 5 starts pushing 35/25/20/20, the comment becomes stale and misleading for future reviewers. Plan doesn't include updating this comment.
- **Impact:** Doc rot, not a bug.
- **Recommendation:** Add to Task 5 sub-list: update `WidgetStressFactor.maxScore` comment from `// 25` to `// per-factor weight (sleep 35, exercise 25, diet 20, screen 20)`. Also update `WidgetStressData.placeholder` at lines 67–72 which hard-codes `maxScore: 25` in all 4 placeholder factors — when Xcode previews the widget, the bars will scale against the wrong max.

#### M6. `ScreenTimeManager` line range cited as `124–161`; file ends at 161 — correct, but worth flagging one assertion
- **Location:** Plan §2 Preconditions — "ScreenTimeManager.currentAutoDetectedReading returns a single daily rawHours: Double from a threshold milestone — no hourly breakdown is exposed today (`ScreenTimeManager.swift:124-161`)".
- **Problem:** The cited line range ends with a closing brace at 161. Reading those lines confirms the claim — there is no hourly exposure. Additionally, `startMonitoring` uses per-threshold events (thresholdMinutes at line 95), which are *accumulated minute* milestones, not time-of-day events. The plan's Task 9 rationale is accurate.
- **Impact:** None — sanity check passed.
- **Recommendation:** No change. This is a confirmation, not an issue.

#### M7. `StressReading` history shift — plan says "pass-through" but widget sparkline reads old + new readings together
- **Location:** Plan §5d (StressReading persistence) "Does it break? No. Same API, just produces new numbers. Old rows are read-only history — accepted per strategy §4."; `WidgetRefreshHelper.swift:23-33` computes weekly averages by mixing old (pre-P1) and new (post-P1) readings.
- **Problem:** For ~7 days post-ship, the weekly bar/sparkline will show a mix of v1-scored and v1.1-scored readings. Because total score shifts (we calculated ~19.2 new vs ~18.6 old for default mock — tight), the visual sparkline will have subtle discontinuities. For realistic users whose delta is larger, Tuesday might be "v1 = 45" and Wednesday "v1.1 = 38" purely due to scoring change, not behavior change. `WellnessCalendarView.swift:379` (weekly grid coloring) has the same issue.
- **Impact:** A small visual whipsaw for ~1 week post-ship. Matches strategy §4 "Do not backfill historical rows — accepted." But the plan doesn't surface this to the user anywhere. Strategy §8 Risks row 1 mitigates this with "ship the confidence badge as the soft explainer" — but the confidence badge doesn't explain retroactive scoring changes.
- **Recommendation:** Either (a) acknowledge this as an acceptable ~1 week transient in the plan (current strategy position is this), or (b) tombstone pre-shift readings with a flag (e.g., `StressReading.algorithmVersion: String` defaulting to "v1") so the sparkline can visually distinguish. A SwiftData additive field is cheap. Strategy §4 says "we only need 7 days of history to calibrate baselines and users won't notice" — weekly sparkline is exactly where they *will* notice. Worth a decision pass before checklist.

---

### ⚪ LOW / Nits

#### L1. Brainstorm link typo
- **Location:** Plan line 5 — `../../01_Brainzstorming/` should be `../../01_Brainstorming/`.
- **Recommendation:** Fix when editing.

#### L2. §2 Preconditions cites `StressScoring.swift:14, 25, 55, 73` as "call-site hooks" but those are function declarations, not hooks
- **Recommendation:** Rephrase to "all 4 factor functions (lines 14, 25, 55, 73) are pure statics with no instance state — ready for in-place signature changes."

#### L3. Plan references `ProfileView.swift:1433, 1435, 1445` — but also says "1433, 1435" in some parts without `1445`. Both triples are accurate (grep confirms all three lines); just normalize references across §2 preconditions and §5a.

#### L4. Task 8 `scoreHeader` mutation: plan proposes changing `HStack` → `VStack(alignment: .leading, spacing: 6) { HStack { … }; confidenceBadge }`. This structural change breaks the `.padding(.top, 20)` + `.opacity(scoreAppeared ? 1 : 0)` + `.scaleEffect(… anchor: .topLeading)` modifiers at `StressView.swift:239-243`. The `.scaleEffect` with `.topLeading` will scale the new taller VStack differently than the original HStack.
- **Recommendation:** Call out in Task 8 that the entrance animation scaleEffect anchor still works (it should, since anchor is `.topLeading` and the new VStack is still anchored to the same corner).

#### L5. Task 10 "printed in logCurrentMode()" — the sample line adds an emoji 🧪 that violates the codebase convention (CLAUDE.md `.claude/CLAUDE.md` notes no emoji unless requested)
- **Recommendation:** Drop the emoji. Also make the plan's log-line style match existing `logCurrentMode()` output (all existing lines are plain text + ENABLED/DISABLED).

#### L6. §9 Open Questions item 2 has a minor internal contradiction: "the brainstorm Open Q7: show 'Log more to see your stress score' when <2 factors valid" vs strategy "default the honest-mode threshold to <2 factors" — these align at `<2`. But strategy §4 Migration line 236 says `fewer than 3` (i.e., `<3`). Strategy has an internal inconsistency the plan inherits silently.
- **Recommendation:** While addressing H1, also reconcile the <2 vs <3 threshold and pick one. H1's fix should cite the correct strategy reference.

#### L7. `logCurrentMode()` addition in Task 10 — plan inserts one line `"Stress v2  : \(stressAlgorithmV2 ? "ENABLED 🧪" : "disabled")"` into the array. The existing `logCurrentMode()` does not use tilted-equals alignment ("Mock Mode   : ...") — existing lines use 2-space internal padding alignment (see `AppConfig.swift:152-156`). The plan's proposed line uses `Stress v2  :` which is 10 chars before colon, matching the shortest existing label "Groq Model" (10 chars). Consistent — good. Just double-check alignment in actual implementation.

---

## Missing Elements

- [ ] **`StressDeepDiveSection.swift` is not listed in File Touch Summary** (Critical — see C1).
- [ ] **`DietDetailView.swift` and `ScreenTimeDetailView.swift` are not in the cosmetic sweep** (High — see H3).
- [ ] **`SharedStressData.swift` placeholder (`WidgetStressFactor` mock `maxScore: 25`) and comment** not updated (Medium — see M5).
- [ ] **Exit criterion "|v2_total − v1_total| ≤ 5 on default mock"** from strategy §3 not mirrored (High — see H6).
- [ ] **"Log more" honest-mode UX** dropped without strategy resolution (High — see H1).
- [ ] **Verification of mock-mode flow for `.sparse` snapshot** — plan assumes `steps: 0` triggers nil behavior but mock mode's HK service stubs may bypass that filter (Medium — see M3).
- [ ] **No rollback plan** — if Phase 1 ships and users complain about the jump, what's the recovery? Strategy §8 mentions a "tombstone" as a nicety; plan has no feature-flag to revert Phase 1 changes (the `stressAlgorithmV2` flag gates *Phase 2*, not Phase 1). Phase 1 changes are irreversible without a revert commit.
- [ ] **No unit tests or SwiftUI preview fixtures** for the new Weights table. Strategy §4 calls out "no automated tests — manual smoke checklist at end of each phase" as an accepted risk, but the plan could at minimum add a #Preview using `.sparse` to visually verify the badge. Plan Task 11 only mentions "temporarily swap StressView preview" — not a persistent regression guard.

---

## Unverified Assumptions

- [ ] **Mock mode HealthKit stub behavior for exercise factor** — plan assumes `snap.steps = 0` propagates as nil through `fetchStepsSafely`, but the mock-service wiring for HK isn't traced in the plan. Risk: Medium.
- [ ] **SwiftData migration safety for new `StressReading` values** — plan accepts that old rows have v1 scores and new rows have v1.1. Not a schema migration (score remains `Double`), but implicit data-shape change. Risk: Low.
- [ ] **Deep-sleep 70% cap numerical tuning** — no research anchor, pure engineering taste (M1). Risk: Medium (user trust on consistent "bad" days).
- [ ] **Confidence badge placement is "realistic without crowding"** — plan says yes, but the VStack/HStack restructure in Task 8 changes the `scaleEffect(anchor: .topLeading)` animation (L4). Risk: Low.
- [ ] **"≤5 points whipsaw" exit gate is met in realistic (non-default) user profiles** — verified for default mock (Δ ≈ 0.6), not verified for edge cases (H6). Risk: Medium.

---

## Questions for Clarification

1. **Does the strategy's "honest mode" threshold of <2 (§3) or <3 (§4) apply?** Strategy is internally inconsistent. H1 fix depends on this answer.
2. **Should `StressReading` gain an `algorithmVersion: String` field now** (additive, cheap) to enable the calendar/sparkline to distinguish pre/post-P1 scores, or is strategy §4's "don't backfill, users won't notice" position accepted as-is for P1?
3. **Who owns the Phase 2 pickup for the `eveningHours` parameter** if it ships dead in Phase 1 (H2)? If no one, drop it.
4. **Is `StressDeepDiveSection`'s factor decomposition chart business-critical enough** to require all four factors to have data, or is nil-per-day acceptable? This drives C1's nil-handling fix (`?? 0` vs filter).

---

## Strengths (what the plan got right)

- Task 1–4 refactor scope is well-bounded and each task has a concrete diff, line numbers, and a verification line.
- Strategy-level decisions are cited with source references (§3 Phase 1, §8a Research, etc.), making traceability easy where the citations are accurate.
- Explicitly states what's *not* in Phase 1 scope (bipolar, physio, honest mode) — reduces scope-creep risk.
- Risk table §8 covers the main structural risks (widget ripple, screen-time scaling, curve re-scaling).
- Task 9 correctly identifies the ScreenTimeManager re-architecture cost and reasons for deferral (even if the partial-ship decision itself is H2-flagged).
- Ripple audit §5 separates consumers that *do* need changes from those that don't — good structural hygiene. Just missed StressDeepDiveSection (C1) and 2 detail views (H3).
- `AppConfig.stressAlgorithmV2` flag pattern mirrors `mockMode` exactly — zero architectural surprise.

---

## Recommendations (prioritized for /develop resolve)

1. **(C1 blocker)** Add `StressDeepDiveSection.swift` as a required Task 5 sub-change. Decide nil-handling: likely `?? 0` since historical days can genuinely be missing. Update §5b and §10.
2. **(H1 blocker)** Get explicit decision on honest mode. If keeping it deferred, update strategy first, not plan.
3. **(H2 clean-up)** Drop `eveningHours` parameter from `screenTimeScore`; move all Q5 work to Phase 2.
4. **(H3 blocker)** Add `DietDetailView.swift:79-82` and `ScreenTimeDetailView.swift:77-80` to cosmetic sweep.
5. **(H5 blocker)** Recompute verification tables. Publish correct expected values for `.default` and `.sparse` snapshots.
6. **(H6 blocker)** Add whipsaw exit criterion with verified math.
7. **(H7 minor)** Fix Task 10 citation.
8. **(M1–M7)** Can be addressed in a follow-up resolve pass after checklist, but M3 (sparse snapshot path) is worth tracing before checklist.
9. **(L1–L7)** Sweep during resolve.

The plan is recoverable with one more `/develop resolve` pass. Not ready for `/develop checklist` until C1, H1–H3, H5, H6 are addressed.

---

**Audit complete.**
