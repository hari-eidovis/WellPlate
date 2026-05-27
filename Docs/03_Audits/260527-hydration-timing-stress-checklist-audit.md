# Checklist Audit Report: Hydration Timing in Stress Engine

**Audit Date:** 2026-05-27
**Checklist Audited:** [`Docs/04_Checklist/260527-hydration-timing-stress-checklist.md`](../04_Checklist/260527-hydration-timing-stress-checklist.md)
**Source Plan:** [`Docs/02_Planning/Specs/260527-hydration-timing-stress-plan-RESOLVED.md`](../02_Planning/Specs/260527-hydration-timing-stress-plan-RESOLVED.md)
**Auditor:** audit agent
**Verdict:** **APPROVED WITH WARNINGS** — one CRITICAL compile-order bug, one HIGH testability gap, plus polish items. None are conceptual; the resolved plan is faithfully translated.

---

## Executive Summary

The checklist faithfully decomposes every step of the resolved plan, with verify steps on every action and complete build coverage. There is, however, one CRITICAL compile-order issue: adding `let waterLogTimestamps: [Date]` (no default value) to `StressMockSnapshot` simultaneously breaks all 6 call sites of the synthesized memberwise initializer, contradicting the checklist's own claim that 3.2 builds "incrementally." Fix is one character (`= []`). One HIGH issue: Phase 4.2 expects to verify the pure-bolus-afternoon path, but no mock fixture exposes that path as configured — the bolus-today scenario is overlaid with late-bunch (22:00) in the new factory, and the seeded `MockDataInjector` bolus row is `offset==1` (yesterday), not today. Several MEDIUM polish items round out the audit.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. `let waterLogTimestamps: [Date]` (no default) breaks all 6 `StressMockSnapshot(...)` call sites simultaneously
- **Location:** Checklist §3.2 — "In the struct (after `let waterLogTimestamps: [Date]` at line 64), add: `let waterLogTimestamps: [Date]`."
- **Problem:** `StressMockSnapshot` has no custom `init`; Swift synthesizes the memberwise initializer from stored properties. Adding a new `let` property *without a default value* makes that parameter required in the synthesized init. All six call sites (`StressMockSnapshot(...)` at `:105, :141, :199, :249, :294, :522`) break at the same moment, so the checklist's "Verify after each: file builds incrementally" instruction is unachievable.
- **Impact:** The implementer either spends the entire 3.2 step in a broken-build state (against the checklist's own guidance) or has to discover the incremental-build claim is false and adjust on the fly.
- **Recommendation:** Change the new property declaration to **`let waterLogTimestamps: [Date] = []`**. With a default, the synthesized memberwise init treats the parameter as optional, so the existing 6 call sites continue to compile while the implementer adds `waterLogTimestamps:` to each factory one at a time. Explicit assignment in a factory still works (Swift allows overriding the default in the memberwise init call). The plan's spec (resolved plan §3.2) is silent on this detail — making the default explicit is a no-cost win.

---

### HIGH (Should Fix Before Proceeding)

#### H1. Phase 4.2 has no clear mock fixture exposing pure-afternoon bolus
- **Location:** Checklist §4.2 — "trigger a mock day with 8 glasses clustered 14:00–15:00... alternatively, the seeded `offset % 10 == 1` day from `MockDataInjector` will satisfy this when picked as 'today'."
- **Problem:** Two issues:
  1. The "alternatively" path is wrong — `MockDataInjector` seeds with `offset 0` being today and `offset 1` being yesterday. The bolus row at `offset % 10 == 1` is therefore *yesterday*, not today; the stress engine reads only *today's* `WellnessDayLog` for hydration. Past rows surface only in pattern penalties and history charts.
  2. The new `lateBingeHydration` factory (3.2) places its 8 timestamps at 22:00–22:10, which makes it a *late-binge* (bolus + late-bunch) — total ≥4 — not a pure bolus (total 3). There is no clean fixture for testing the bolus-only path in isolation.
- **Impact:** Phase 4.2's expected value ("hydration factor reads 3") is not directly reproducible with the mocks as-designed. The implementer will likely have to write a one-off debug button or hand-edit the simulator's SwiftData store — neither described.
- **Recommendation:** Pick one:
  - **(Preferred) Add a second mock factory `makeAfternoonBolus()` / `static let afternoonBolus`** alongside `lateBingeHydration` in 3.2. Body: same as `lateBingeHydration` but with timestamps at 14:00–14:45 instead of 22:00–22:10. This isolates the bolus signal and gives Phase 4.2 a one-line activation path ("switch AppConfig mock snapshot to `afternoonBolus`").
  - **(Alternative) Reframe Phase 4.2** as verifying the late-binge factory and updating the expected total to 4 with detail `· logged in burst, mostly after 21:00`. Remove the "pure-bolus" assertion.
  - **(Alternative)** Repurpose `MockDataInjector` so `offset == 0` is the bolus day (drop late-bunch to `offset == 1` or another bucket), then either Phase 4.2 reads "today" directly or write a debug action to force-seed offset 0. Slightly invasive.

The implementer needs a deterministic activation path; the current text isn't one.

---

### MEDIUM (Fix During Implementation)

#### M1. Step 1.1 verify ("file compiles standalone via `xcodebuild build`") is misleading
- **Location:** Checklist §1.1 — "Verify: file compiles standalone (`xcodebuild -workspace ... build` — expect failure later but model file alone should not produce a parse error)."
- **Problem:** `xcodebuild build` compiles the entire scheme, not a single file. After step 1.1 alone the workspace builds fine because the new property has a default value, but the verify text reads as if the implementer should expect a build failure here — which is wrong (the build at this checkpoint should *pass*; failures appear later when 2.1 lands).
- **Recommendation:** Replace with: "Verify: line passes Swift parse (Xcode shows no inline syntax error; saving the file leaves no red bar). Full workspace build still passes at this checkpoint." Removes the confusing "expect failure" hint.

#### M2. Pre-Impl "clean working tree" conflicts with current `git status`
- **Location:** Checklist §Pre-Implementation — "Confirm clean working tree."
- **Problem:** Current `git status` shows three already-modified files including `Cadence/Features + UI/Home/Views/HomeView.swift` — one of the files the checklist edits in Step 1.3. The implementer needs explicit guidance: either commit the pending changes first, or merge the new edits into the same stash.
- **Recommendation:** Replace with: "Confirm none of the eight target files have *uncommitted* changes that conflict. If `git status` shows pending edits on any of them (notably `HomeView.swift` per current branch state), either commit the unrelated work first or coordinate the diff manually. Document any pre-existing diff in `HomeView.swift` before editing."

#### M3. Step 3.2 misses an explicit timestamp count for `makeDefault`
- **Location:** Checklist §3.2 — "`makeDefault()` (around line 328) — use `spreadTimestamps`-equivalent over today's hours, or `[]` if `waterGlasses == 0`."
- **Problem:** `makeDefault` constructs with `waterGlasses: 4` (verified at `StressMockSnapshot.swift:549`). The checklist's "or `[]` if `waterGlasses == 0`" branch is irrelevant for this factory and the affirmative branch ("use spreadTimestamps-equivalent") is vague — should the implementer spread 4 timestamps? Match a specific time pattern?
- **Recommendation:** Tighten to: "`makeDefault()` has `waterGlasses: 4` (line 549). Set `waterLogTimestamps:` to 4 timestamps evenly spread across today's 08:00–22:00 window using the same algorithm as `spreadTimestamps`. Inline the four timestamps directly (the helper lives in `MockDataInjector`, not in `StressMockSnapshot`'s file scope)."

#### M4. Grep in §1.5 will match mock writers and produce noise
- **Location:** Checklist §1.5 — "Run `grep -rn 'waterGlasses\s*=' Cadence --include='*.swift'` and confirm exactly four assignment sites are present in non-mock code."
- **Problem:** The grep also catches `MockDataInjector.swift` and `StressMockSnapshot.swift` initializer call sites where `waterGlasses:` is a named init parameter — those are syntactically `waterGlasses:` with a colon, not `=`. So the false-positive risk is lower than implied, but the named-init lines may still appear depending on regex behavior. More importantly, the count "exactly four" doesn't anticipate the implementer running this *after* Phase 3 mock edits add timestamp-set assignments.
- **Recommendation:** Run the grep *immediately after Phase 1* and before starting Phase 2/3. Phrase: "Run before starting Phase 2: `grep -rn 'waterGlasses\s*=[^=]' Cadence --include='*.swift' | grep -v Mock`. Expect exactly four results (one per writer). If a fifth surfaces in non-mock code, halt and update the plan."

#### M5. Phase 4.3 doesn't address simulator-clock setup
- **Location:** Checklist §4.3 — table of expected values per "hour at tap."
- **Problem:** To verify all three rows in the table, the implementer must run the simulator three times with the clock set to 14:00, 19:00, and 22:00 respectively. Simulator clock manipulation isn't a one-liner — requires `xcrun simctl ... privacy ...` or pre-set environment overrides, or just running each case on different real-time days.
- **Recommendation:** Add a preamble to §4.3: "Each row requires the *device clock* to be at the specified hour because `Calendar.current.component(.hour, from: $0)` reads system time on the simulator. Either: (a) set Simulator → Features → Trigger iCloud Sync... no — use Settings → General → Date & Time → set manually; (b) run all three cases on a real day when the wall clock crosses each band; or (c) add a one-off DEBUG override that lets you inject a `Date` for the hour check. Choose (b) for honesty, (c) for speed."

---

### LOW (Consider for Future)

#### L1. Suggested commit message lacks the `Co-Authored-By` footer
- **Location:** Checklist §Post-Implementation — sample commit message.
- **Problem:** Per the project's global Bash/commit rules, commits authored by Claude should end with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`. The sample omits it. Minor.
- **Recommendation:** Append the footer to the sample. If the user commits manually, they can omit it; if `/commit` is invoked, the footer is added automatically.

#### L2. No rollback step if Phase 4.5 migration fails
- **Location:** Checklist §4.5.
- **Problem:** The step says "Do not delete `default.store` unless explicitly approved." Good. But there's no positive rollback path — if migration fails, what does the implementer do? Halt? Open a fix doc?
- **Recommendation:** Add: "If migration fails, stash the schema change (`git stash`), reproduce the error in a fix doc, and re-engage the planner — do *not* attempt destructive recovery (deleting `default.store`, resetting state) without approval."

#### L3. Hint suffix ordering in 4.3 may not match implementation
- **Location:** Checklist §4.3 expected detail: `· logged in burst, mostly after 21:00`.
- **Problem:** In the resolved plan, `hints.append` runs in this order: bolus → late-bunch → backfill. So the suffix would be `· logged in burst, mostly after 21:00` for the 22:00 row, exactly as written. Good — but the backfill suffix (`logged all at once`) is never reached in the rapid-tap path because bolus already adds 3 points, making the floor a no-op. The expected suffix in the table is correct; just confirming the implementer doesn't expect to see `logged all at once` for the rapid-tap path.
- **Recommendation:** Add a sentence after the table: "Note: `logged all at once` (backfill hint) does NOT appear in the rapid-tap rows because bolus already pushes `pts` above the backfill floor. It appears only when bolus does *not* engage — e.g., when `r ∈ [0.8, 1.0]` is reached without timestamps≥minTimestamps."

#### L4. Pre-Impl could explicitly verify `WellnessDayLog`'s synthesized init pattern still applies
- **Location:** Checklist §Pre-Implementation.
- **Problem:** Step 1.1 adds the property; step 1.2-1.4 use the existing initializer pattern. If `WellnessDayLog` were ever refactored to a custom init, default-value propagation breaks. Currently `WellnessDayLog` has an explicit `init(...)` at lines 42-64 (per planning research), so the new parameter must be added there manually — the checklist already covers this in 1.1. No action needed, but worth confirming during Pre-Impl.
- **Recommendation:** Acceptable as-is.

---

## Missing Elements

- [ ] Explicit `waterLogTimestamps: [Date] = []` default-value note in 3.2 (per C1).
- [ ] Concrete bolus-only mock fixture (per H1).
- [ ] Simulator clock manipulation guidance for §4.3 (per M5).
- [ ] Rollback policy for Phase 4.5 migration failure (per L2).

---

## Unverified Assumptions

- [ ] **`WellnessDayLog`'s explicit init accepts a new parameter with default without breaking call sites.** Risk: Low. Confirmed via source read — the init body in lines 42-64 takes all params explicitly with defaults like `waterGlasses: Int = 0`. Adding `waterLogTimestamps: [Date] = []` follows the same pattern.
- [ ] **`StressMockSnapshot` uses synthesized memberwise init only.** Risk: Resolved. Confirmed via grep — no `init(` declarations in the struct; only `StressMockSnapshot(` call sites.
- [ ] **`MockDataInjector` offset 0 is "today."** Risk: Low. Confirmed via source — `cal.date(byAdding: .day, value: -offset, to: today)!` at line 212.
- [ ] **Phase 4.5 SwiftData migration succeeds on iOS 26.1.** Risk: Medium. Carries over from the plan audit (M5). Resolved in the plan with a Phase 4.5 verification step but not actually tested until implementation.

---

## Questions for Clarification

1. **C1 resolution:** Should the implementer add the default `= []` to the new `let` in `StressMockSnapshot` (preferred, allows incremental builds) or accept atomic 6-site updates? Answer expected: add the default.
2. **H1 resolution:** Add `makeAfternoonBolus` factory (preferred), reframe Phase 4.2, or rework `MockDataInjector` offset assignment? Answer expected: add the factory.
3. **M5 resolution:** Document simulator clock setup (option b: run on real days) or add a DEBUG `Date` injection override (option c)? The DEBUG override would be reusable for other hour-sensitive tests.

---

## Recommendations (Prioritized)

1. **Fix C1** — change `let waterLogTimestamps: [Date]` to `let waterLogTimestamps: [Date] = []` in §3.2. One character. Mandatory.
2. **Fix H1** — add `makeAfternoonBolus()` factory in §3.2 alongside `makeLateBingeHydration()`. Update §4.2 to reference it. Mandatory.
3. **Apply M1–M5** — small wording and process clarifications.
4. **L1 / L2 / L3 / L4** — optional polish, can roll into implementation without further review.

---

## Verdict Detail

The checklist is structurally sound — every plan step has a corresponding checklist item with a verify step, file paths are exact and verified to exist, build verification covers all four targets, and the order respects dependencies. The CRITICAL and HIGH issues are both about *making verification actually reproducible* — a missing default and a missing fixture, not flaws in the design itself.

Recommended next step: **`/develop resolve Docs/03_Audits/260527-hydration-timing-stress-checklist-audit.md`**.
