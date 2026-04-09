# Brainstorm: F3. Circadian Stack

**Date**: 2026-04-07
**Status**: Ready for Planning

---

## Problem Statement

WellPlate already collects sleep data (duration, stages) and screen time (total daily hours). Neither is presented through a *circadian lens* — the app doesn't ask "is your body aligned with the light-dark cycle?" Competitors (Oura, WHOOP) touch on readiness scores, but no mainstream nutrition/wellness app blends daylight exposure + sleep timing regularity + late-screen-use into a coherent "Circadian Health" picture.

The goal: add a Circadian Score card to StressView that surfaces one new, credible wellness axis that users can actually act on.

---

## Core Requirements

- Compute a Circadian Score (0–100 or labeled) from existing + new signals
- Show as a new card on StressView (not replacing the existing 4 stress factors)
- At minimum: sleep timing regularity (bed/wake consistency over 7 days)
- Optionally: daylight exposure via `timeInDaylight` (Apple Watch only — must degrade gracefully)
- Actionable tip: one concrete micro-action surfaced alongside the score
- No new onboarding friction — data-first, permissions-light design
- Works without Apple Watch (Watch-only data enhances but isn't required)

---

## Constraints

- Solo dev — scope must be 1–2 weeks maximum
- `HealthKitService.readTypes` doesn't include `timeInDaylight` yet → add it
- `DailySleepSummary` currently lacks bedtime/wake time (only duration) → must be extended or a parallel struct added
- `ScreenTimeManager` gives total daily hours only — no per-hour breakdown, so "nighttime screen time" can't be derived directly
- `StressView` already has 4 factor cards + vitals section — new card must be additive, not disruptive
- iOS 26+ target; `timeInDaylight` is available from iOS 17 via `HKQuantityTypeIdentifier.timeInDaylight`

---

## Signal Inventory

| Signal | Available? | Source | Notes |
|---|---|---|---|
| Sleep regularity (bed/wake SD) | With code change | HealthKit SleepAnalysis | Must infer from `SleepSample.date` (earliest start = bedtime, max date+value = wake) |
| `timeInDaylight` (minutes/day) | After auth addition | HealthKit, Apple Watch | Not in `readTypes` yet; Watch required for data |
| Nighttime screen time | Not available | ScreenTimeManager | Only total hours; cannot determine *when* usage occurred |
| Sleep onset latency | Partial | SleepSample first stage timestamp | Could approximate from earliest sleep sample vs. typical bedtime |

**Key gap**: Nighttime screen time signal is not retrievable from the current ScreenTimeManager design (FamilyControls gives aggregate threshold, not hour-by-hour usage). Two strategies:

A. **Omit it** — score from daylight + regularity only; add a "reduce screens 1hr before bed" tip as advice regardless
B. **Proxy via sleep onset** — later bedtime may correlate with more late-night screen use; use it as an indirect signal

---

## Approach 1: Two-Signal Circadian Score (Recommended MVP)

**Summary**: Score based on sleep timing regularity + daylight exposure (Apple Watch) with graceful degradation to regularity-only when Watch data is absent.

**Scoring formula**:
- **Sleep Regularity Index (SRI)** — 50% weight. Compute standard deviation of bedtime-minutes and wake-minutes over last 7 days. SD ≤ 15 min → 100 pts; SD ≥ 90 min → 0 pts.
- **Daylight Exposure** — 50% weight (if available). ≥ 30 min/day → 100 pts; 0 min → 0 pts; linear interpolation.
- If no Watch data: score from SRI alone (renormalized to 100).

**Actionable tips** (surfaced based on lowest sub-score):
- Low SRI: "Try going to bed within 30 min of your usual time tonight"
- Low daylight: "10 min of outdoor light before noon sets your body clock"
- Both low: "A regular bedtime matters more than early bedtime for rhythm"

**Pros**:
- Can be computed from existing data + 1 new HK type
- `DailySleepSummary` just needs bedtime/wake time added
- Graceful Watch degradation is clean (just hide that sub-component)
- Scientifically grounded (SRI is an established metric in sleep research)

**Cons**:
- Two-signal score may feel thin; daylight data will be missing for most non-Watch users
- Sleep sample timestamps from HealthKit may be noisy if user wears Watch inconsistently

**Complexity**: Low–Medium  
**Risk**: Low

---

## Approach 2: Three-Signal Full Circadian Stack

**Summary**: Adds a "screen curfew" third component by inferring late-night screen use from sleep onset deviation.

**Extra signal**: "Sleep onset latency" — compare actual first-sleep-stage timestamp to the user's personal median bedtime. If going to bed 30+ min later than usual, flag as possible late-screen-use night. Score this as a discrete event (good/bad nights), not a continuous measure.

**Pros**:
- Three components feels more substantial
- Uses already-available sleep timestamp data (no new API)
- Can surface more specific advice: "Last night you went to bed 45 min late — try a screen curfew"

**Cons**:
- The proxy (late bedtime → screen use) is an assumption, not a measured fact
- Users without a baseline (< 7 days of sleep data) get no score from this component
- Risk of over-engineering a heuristic that feels misleading

**Complexity**: Medium  
**Risk**: Low–Medium (attribution heuristic is an assumption)

---

## Approach 3: Separate Circadian Tab / View

**Summary**: A dedicated full-screen Circadian view (like SleepDetailView) with trend charts for each pillar: Daylight Timeline, Sleep Rhythm Calendar, Screen Curfew History.

**Pros**:
- Better storytelling; room for 7/30-day trend charts
- Positions Circadian as a first-class axis (not just a card in Stress)
- Could be the home for future features (light therapy suggestions, jet lag calculator)

**Cons**:
- Requires a new tab or navigation destination; tab structure is already 4 tabs (Home, Burn, Stress, Profile)
- Significant scope expansion for an MVP: 2–3 weeks of UI work
- Premature to build a full tab for a feature whose user value isn't proven yet

**Complexity**: High  
**Risk**: Medium (scope creep, underused if data is sparse)

---

## Approach 4: Augment Existing Sleep Factor

**Summary**: Instead of a new card, fold circadian regularity into the existing sleep stress factor. Sleep score already penalizes for short duration; add regularity as a modifier.

**Pros**:
- Zero new UI surface
- Instantly visible to all users (sleep factor already on StressView)
- Lowest implementation cost

**Cons**:
- Hides the circadian concept entirely — no educational value
- Sleep factor already has a well-tuned formula; changing it risks confusing existing users who track it
- Misses the opportunity to surface daylight exposure as a distinct signal

**Complexity**: Low  
**Risk**: Low (but low value differentiation too)

---

## Implementation Notes: Sleep Timing Extraction

`DailySleepSummary` currently aggregates only duration. To get bedtime/wake time:

**Option A — Extend `DailySleepSummary`**:
```swift
struct DailySleepSummary {
    // existing fields...
    let bedtime: Date?    // earliest sleep sample startDate in session
    let wakeTime: Date?   // latest sleep sample (startDate + value * 3600)
}
```
Change `fetchDailySleepSummaries` in `HealthKitService` to track `min(startDate)` and `max(endDate)` per night session. Minimal change; touches one shared model.

**Option B — Separate `SleepTimingDay` struct**:
```swift
struct SleepTimingDay {
    let date: Date
    let bedtime: Date
    let wakeTime: Date
}
```
Computed separately in `CircadianService` from raw `fetchSleep` samples. No changes to shared model.

**Recommendation**: Option A for simplicity — bedtime/wake time belongs naturally in `DailySleepSummary`. Check that SleepViewModel and SleepDetailView still compile cleanly (they use `totalHours` primarily).

---

## Sleep Regularity Index (SRI) Formula

Standard deviation of bedtime-in-minutes-past-midnight over N nights:

```
bedtimeMinutes[i] = (bedtime[i].hour * 60 + bedtime[i].minute)
// Handle midnight-crosser: if bedtime is between 0-3am, add 1440 (24h)
SRI = max(0, 1 - (stdDev / 75.0))  // 75 min SD → SRI = 0, 0 min SD → SRI = 1
CircadianRegularityScore = SRI * 50  // maps to 0–50 of total 100
```

Require ≥ 5 nights in the past 7 days for a valid score (else show "Not enough data").

---

## Edge Cases to Consider

- [ ] User has no Apple Watch → daylight component absent; show 1-component score with note "Add Apple Watch for daylight data"
- [ ] < 5 nights of sleep data in last 7 days → show "Need more data" state, not a misleading score
- [ ] Sleep session spanning multiple days (e.g., nap at 2am, wake at 4am) → require session ≥ 3 hours to count as a sleep session
- [ ] Night shift / irregular work schedules → high SD will flag as "poor" even if intentional; no override mechanism in MVP
- [ ] Sleep recorded only by iPhone (no Watch stages) → `asleepUnspecified` samples; still valid for timing, just fewer stage details
- [ ] `timeInDaylight` authorization denied → treat as Watch-absent gracefully (don't re-prompt)
- [ ] `timeInDaylight` = 0 every day → could be legitimate indoor lifestyle or Watch not worn; no minimum threshold, just show the value

---

## Open Questions

- [ ] Should the Circadian Score card be tappable → opens a `CircadianDetailView` sheet with 7-day regularity chart? (Adds scope but fits the existing pattern)
- [ ] Where exactly in StressView does the card appear? Above or below the 4 factor cards? Between vitals and factors?
- [ ] Should the Circadian Score feed back into the overall stress composite score? (Probably not in MVP — keep it as informational only)
- [ ] Should we add `timeInDaylight` to the HealthKit authorization request on first launch, or request it lazily when the user sees the Circadian card?
- [ ] Should SRI use bedtime or wake time variability, or both? (Research suggests wake time consistency is more important for circadian entrainment)

---

## Recommendation

**Approach 1 (Two-Signal Circadian Score)** as MVP.

Rationale:
- Sleep regularity is derivable from existing data with a minimal model change
- `timeInDaylight` is a clean, scientifically grounded signal — just needs to be added to `readTypes` + authorized
- The graceful Watch degradation story is clean and honest
- A score + one actionable tip is the right UX density for a card that lives alongside 4 other factors
- Approach 2's screen-onset proxy feels like a stretch in terms of attribution honesty; can be added later
- Approach 3 is the right V2 destination, not MVP

**Proposed new files**:
- `WellPlate/Features + UI/Stress/Views/CircadianCardView.swift` — score card + tip display
- `WellPlate/Core/Services/CircadianService.swift` — SRI computation + daylight scoring
- (Optional) `WellPlate/Features + UI/Stress/Views/CircadianDetailView.swift` — tappable detail sheet

**Proposed model changes**:
- `DailySleepSummary` — add `bedtime: Date?` and `wakeTime: Date?`
- `HealthKitService.readTypes` — add `.timeInDaylight`
- `HealthKitServiceProtocol` — add `fetchDaylight(for:)` method

---

## Research References

- `Docs/02_Planning/260406-10-feature-roadmap.md` — F3 scope definition
- `Docs/01_Brainstorming/260402-feature-prioritization-from-deep-research-brainstorm.md` — Feature 2B: Circadian Health Module (detailed rationale)
- `Docs/06_Miscellaneous/deep-research-report-2.md` — Primary deep research source
- Sleep Regularity Index: Lunsford-Avery et al. (2018) — SRI validated against circadian misalignment outcomes
- HealthKit `timeInDaylight`: `HKQuantityTypeIdentifier.timeInDaylight`, Apple Watch required, iOS 17+
