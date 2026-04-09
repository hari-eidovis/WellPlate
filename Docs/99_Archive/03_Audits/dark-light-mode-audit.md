# Plan Audit Report: Dark & Light Mode Support

**Audit Date**: 2026-02-19
**Plan File**: `Docs/02_Planning/Specs/260219-dark-light-mode-support.md`
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan correctly identifies the most visually critical fixes (hardcoded white backgrounds in HomeView and CustomProgressView) and the AppColors asset-catalog gap. However, it has a significant coverage gap: `LoadingScreenView.swift` was missed entirely, `ProgressInsightsView.swift` was marked "Already Adaptive" despite having 10+ `Color.white` usages, and the entire Burn module (3 files with shadow issues) was overlooked. Additionally, the proposed `appShadow` helper has a design flaw that breaks the upward-facing shadow on `GoalsExpandableView`, and Phase 1 (creating color sets) will have **zero visual impact** since no view in the codebase actually references `AppColors` tokens.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

1. **`LoadingScreenView.swift` completely missing from plan scope**
   - Location: Plan's "Current State Audit" — not listed at all
   - Problem: `LoadingScreenView.swift` has a hardcoded `LinearGradient(colors: [Color.white, Color(red: 1.0, green: 0.95, blue: 0.9)])` background (lines 11–17) and a hardcoded dark text color `Color(red: 0.2, green: 0.2, blue: 0.2)` (line 25). In dark mode this renders as a blinding white-to-warm gradient with dark text — completely broken.
   - Impact: App renders incorrectly in dark mode whenever the loading screen is shown.
   - Recommendation: Add `LoadingScreenView.swift` to Phase 2 with two fixes: replace the gradient with an adaptive background (e.g., `Color(.systemBackground)`) and replace the hardcoded dark text with `.primary`.

2. **`ProgressInsightsView.swift` incorrectly classified as "Already Adaptive"**
   - Location: Plan's "Current State Audit — ✅ Already Adaptive" table
   - Problem: A grep of the actual file found **10 instances of `Color.white` or `.white`** hardcoded in `ProgressInsightsView.swift`:
     - Lines 152, 158: `.fill(Color.white.opacity(0.08/0.06))` — pill/tag backgrounds
     - Lines 167, 179, 188: `.foregroundColor(.white)` — text inside selected metric pills
     - Lines 181, 190: `.background(Color.white.opacity(0.2))` — badge backgrounds
     - Lines 717, 895: `.foregroundColor(.white)` — selected button text
     - Line 902: `.background(Color.white.opacity(0.18))` — additional badge background
   - Impact: Multiple UI elements in the Stats/Progress screen will render incorrectly or be invisible in dark mode. The plan explicitly says this file needs "no changes needed" — that is wrong.
   - Recommendation: Remove `ProgressInsightsView.swift` from the "Already Adaptive" table. Audit each `Color.white` usage: those used as text on colored backgrounds (selected state pills) are intentional; those used as standalone backgrounds or overlays need to become adaptive (e.g., `Color(.systemBackground)` or `Color(.label).opacity(...)`).

---

### HIGH (Should Fix Before Proceeding)

3. **Burn module shadow fixes entirely omitted from Phase 3**
   - Location: Phase 3 shadow fix list
   - Problem: The plan lists 4 files for shadow fixes but misses 3 files in the Burn module — all with `cardBackground` computed properties containing `.shadow(color: .black.opacity(0.05), ...)`:
     - `BurnView.swift:285` — `cardBackground` used on `todayHeroCard` and `weeklyChartCard`
     - `BurnDetailView.swift:176` — `cardBackground` used on `kpiCard`, `chartCard`, `statsCard`
     - `BurnMetricCardView.swift:61` — inline shadow on each metric grid cell
   - Impact: All Burn screen cards will lose their depth in dark mode — inconsistent with the fix applied to other screens.
   - Recommendation: Add these 3 files to Phase 3. Note that each uses a `cardBackground` computed property pattern, so fixing one property fixes multiple instances.

4. **`appShadow` modifier breaks the upward-facing shadow in `GoalsExpandableView`**
   - Location: Phase 3, Step 1 (code snippet) + Step 2 (application to GoalsExpandableView)
   - Problem: `GoalsExpandableView` uses `.shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: -5)` — note the **negative y offset** (shadow projects upward because the view is anchored at the bottom of the screen). The proposed `appShadow(radius:y:)` defaults to `y: 4` (positive, downward). Applying it without adjustment would flip the shadow direction, breaking the visual design.
   - Impact: The collapsed pill and expanded goals card will lose their characteristic upward shadow, making them look detached from the bottom edge.
   - Recommendation: Either (a) give `appShadow` a `y` parameter that callers must explicitly pass (remove the positive default), or (b) handle the GoalsExpandableView shadow manually with a direct `shadow(color: Color(.label).opacity(0.1), radius: 20, x: 0, y: -5)` inline call rather than the generic helper.

5. **Phase 1 (AppColors color sets) will have zero visual impact**
   - Location: Phase 1 entirely + "AppColors tokens newly working may change appearance" risk entry
   - Problem: A codebase-wide grep for `AppColors.` returns **zero matches**. No view in the app references `AppColors.primary`, `AppColors.surface`, or any other token from `AppColors.swift`. Creating the `.colorset` assets will not change any view's rendering — the transparent-renders-clear behavior is technically a bug but has no current visual consequence.
   - Impact: Phase 1 is framed as a critical silent bug ("these all render as transparent/clear throughout the app") but is actually zero-impact because the tokens are never consumed. The plan's risk "tokens newly working may change appearance" is a false positive. Doing Phase 1 is good housekeeping for the future but should not be listed as part of the dark mode fix scope.
   - Recommendation: Demote Phase 1 to a separate housekeeping task. Re-order: Phase 1 → fix hardcoded colors (current Phase 2), Phase 2 → shadow fixes (current Phase 3), Phase 3 → create AppColors asset catalog (future-proofing). Do NOT imply it fixes current rendering issues.

---

### MEDIUM (Fix During Implementation)

6. **`ShimmerLogoLoader` shimmer uses hardcoded `Color.white`**
   - Location: `ByoSyncCustomProgressView.swift:79` — `.white.opacity(0.4)` shimmer overlay
   - Problem: The shimmer highlight on `ShimmerLogoLoader` uses `Color.white.opacity(0.4)`. In dark mode, a white shimmer on a dark logo image may look incorrect or overly harsh.
   - Recommendation: Change to `Color(.label).opacity(0.3)` so the shimmer adapts. Note that `Color(.label)` in dark mode is white, so the visual change is minimal.

7. **Plan file summary table is incomplete**
   - Location: "File Summary" table at the bottom of the plan
   - Problem: Lists 6 files but the actual scope (after audit corrections) is at minimum 9 files: add `LoadingScreenView.swift`, `BurnView.swift`, `BurnDetailView.swift`, `BurnMetricCardView.swift`.
   - Recommendation: Update the table after revising the plan.

8. **Testing strategy doesn't cover Burn module or LoadingScreenView**
   - Location: "Manual Device Testing" checklist
   - Problem: Lists 5 screens to test but omits `BurnView` (all 3 card types), `BurnDetailView`, and `LoadingScreenView`.
   - Recommendation: Add these to the manual test checklist. Also recommend testing `ProgressInsightsView` metric pills specifically since those have both intentional and accidental `Color.white` usages that need careful review.

---

### LOW (Consider for Future)

9. **`GoalsExpandableView` listed in both "no changes needed" AND Phase 3**
   - Location: "Already Adaptive" table AND Phase 3 Step 2
   - Problem: The table says "no changes needed" but Phase 3 Step 2 then fixes its shadows. Minor but confusing for the implementer.
   - Recommendation: Remove `GoalsExpandableView` from the "Already Adaptive" table, or add a note "background is adaptive, shadow needs fix."

10. **`TextSecondary` dark variant is identical to light**
    - Location: Phase 1, Step 7
    - Problem: Plan sets `TextSecondary` to `#8E8E93` for both light and dark, commenting "system secondary gray is already calibrated." However, iOS dark mode uses slightly different secondary label colors. Since no views currently use this token, the impact is zero now, but it sets a wrong precedent.
    - Recommendation: Use `Color(.secondaryLabel)` directly in code rather than a custom named color for secondary text, OR look up the actual iOS dark secondary color (closer to `#636366`).

---

## Missing Elements
- [ ] `LoadingScreenView.swift` not in scope (Critical miss)
- [ ] Burn module not audited in original plan (`BurnView`, `BurnDetailView`, `BurnMetricCardView`)
- [ ] `ProgressInsightsView.swift` white usages not enumerated or categorized (intentional vs accidental)
- [ ] No strategy for distinguishing "white on colored background" (intentional, keep) vs "white as background" (must fix)
- [ ] No mention of `ByoSyncCustomProgressView.ShimmerLogoLoader` shimmer color
- [ ] Testing checklist missing Burn screens and LoadingScreenView

---

## Unverified Assumptions
- [ ] "AppColors tokens render as transparent/clear" — technically correct but impact is zero since no view uses them. Risk: Low (framing issue)
- [ ] "Adaptive shadows using `Color(.label)` create a white glow in dark mode" — correct, but untested for acceptability. Risk: Medium (visual design concern)
- [ ] `ProgressInsightsView` Color.white instances at lines 167/179/188/717/895 are intentional (white text on orange gradient buttons) — likely true but needs verification before replacing. Risk: Medium
- [ ] Line number references in the plan (HomeView:96, :250, :212, CustomProgressView:9) are stable — accurate at time of writing, may drift. Risk: Low

---

## Recommendations

1. **Before implementing**, re-read `ProgressInsightsView.swift` lines 130–200 and 690–910 to classify each `Color.white` usage as intentional (keep) or accidental (fix). White text on orange selected-state buttons should stay white. White-opacity backgrounds in dark mode need to become `Color(.tertiarySystemFill)` or similar.

2. **Revise Phase ordering**:
   - Phase 1: Fix hardcoded `Color.white`/`.black` backgrounds and foregrounds (HomeView × 3, CustomProgressView × 1, LoadingScreenView × 2, ProgressInsightsView accidental whites)
   - Phase 2: Fix shadows across all 7+ files using an adaptive shadow helper (with correct y-offset handling)
   - Phase 3: Create AppColors asset catalog entries (future-proofing, zero current visual impact — deprioritize)

3. **`appShadow` modifier** should require an explicit `y` parameter with no default, or document clearly that callers with upward shadows must negate the value.

4. **Add to success criteria**: "All `Color.white` and `Color.black` usages in the codebase are either (a) intentional foreground text on a known colored background, or (b) replaced with adaptive alternatives."

---

## Sign-off Checklist
- [ ] CRITICAL issue #1 resolved (LoadingScreenView added to scope)
- [ ] CRITICAL issue #2 resolved (ProgressInsightsView re-audited and reclassified)
- [ ] HIGH issue #3 resolved (Burn module added to Phase 3)
- [ ] HIGH issue #4 resolved (appShadow y-offset flaw fixed)
- [ ] HIGH issue #5 resolved (Phase 1 re-framed as housekeeping, not dark-mode fix)
- [ ] Security review completed (N/A — UI-only change)
- [ ] Performance implications understood (none — color changes are zero-cost)
- [ ] Rollback strategy: all changes are local, reversible; revert individual files if needed
