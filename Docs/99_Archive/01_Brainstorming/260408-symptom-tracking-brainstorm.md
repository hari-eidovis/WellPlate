# Brainstorm: Symptom Tracking Correlated with Food/Sleep

**Date**: 2026-04-08
**Status**: Ready for Planning
**Roadmap**: F5 — Phase 2 (Engagement Layer)

## Problem Statement

WellPlate tracks nutrition, sleep, stress, HRV, mood, and activity — but has no way for users to record *how they actually feel* at a granular level. "Stress: High" is a computed score; "bloating after lunch, 7/10 severity" is self-reported lived experience. Bridging these two layers is the core value proposition of symptom tracking: correlating the user's own body signals with the rich substrate of meal context, sleep data, and stress patterns already captured.

The market leader in this space (Bearable) wins on comprehensiveness but loses on *interpretability* — users explicitly report "correlations without numbers" and "conclusions that can be misleading." WellPlate's opportunity is to do it right: transparent statistics, epistemic humility, and clinical-export quality.

## Core Requirements

- R1: Log user-defined symptoms with severity (1–10) and timestamp
- R2: Built-in common symptom library + custom symptoms
- R3: Correlation engine linking symptoms to: meals/foods, sleep quality, stress score, caffeine
- R4: Effect sizes + confidence intervals on all correlations — never bare percentage grids
- R5: "Correlation ≠ causation" language throughout — non-diagnostic framing
- R6: Export integration (add to existing CSV/report pipeline)
- R7: All data on-device (SwiftData, no backend)

## Constraints

- **Design rule (mandatory)**: Ship correlations with effect sizes + uncertainty. Never opaque grids.
- **Tab real estate**: 3 current tabs — symptom tracking needs a home without a new tab if possible
- **SwiftData**: New `SymptomEntry` model must register in `WellPlateApp.swift`
- **Correlation math**: Needs enough data (≥7 days) before surfacing; guard against false confidence with small N
- **No diagnostic language**: Must never suggest medical conclusions
- **Export**: Builds on `WellnessReportGenerator` CSV pipeline — symptoms add columns, not a new pipeline

## Existing Infrastructure Ready to Use

| Asset | What it provides |
|-------|-----------------|
| `FoodLogEntry` — `mealType`, `eatingTriggers`, `reflection` | Meal-level context for correlation |
| `WellnessDayLog` — mood, sleep, stress, caffeine, water | Daily signal substrate |
| `StressExperiment` — `cachedBaselineAvg`, `cachedDelta`, `cachedCILow/High` | Proven CI + delta stats pattern |
| `StressFactorResult` — scored 0–25 per factor | Factor-contribution math pattern |
| `WellnessReportGenerator` — CSV + image pipeline | Extend, don't rebuild |
| `EatingTrigger` enum — hungry, stressed, bored, etc. | Emotional context already tracked |
| HealthKit services | Sleep + HRV already fetched |

---

## Approach 1: Symptoms as "Body Log" — Separate Log Destination

**Summary**: A dedicated "Body Log" view (similar to FoodJournalView) accessible from the Home FAB or Profile. Users log symptoms throughout the day with severity + optional notes. Correlation view is a separate "Insights" section showing which meals/habits correlate with symptom flares.

### Architecture
- `SymptomEntry` @Model: `id`, `name`, `category`, `severity` (1–10), `timestamp`, `notes?`, `day`
- `SymptomCorrelationEngine`: computes Spearman rank correlation between symptom severity and meal/sleep/stress signals per day
- `BodyLogView`: symptom list + quick-add FAB
- `SymptomCorrelationView`: effect sizes, CI bands, "N=X days" transparency
- Access: Profile tab → Body Log, OR Home FAB → Symptom entry

### Correlation Math
- **Unit of analysis**: day (align symptoms, meals, sleep per calendar day)
- **Method**: Spearman rank correlation (robust to non-normality; appropriate for ordinal severity 1–10)
- **Effect size**: r_s value (−1 to +1) displayed as "strong/moderate/weak association"
- **Confidence interval**: bootstrapped 95% CI using ≥7 day pairs
- **Minimum N**: Show correlations only when ≥7 paired observations; otherwise show "Collecting data…"
- **Caution note**: Always append "This pattern may not indicate a cause. Track more days to strengthen confidence."

**Pros:**
- Clean separation — symptoms are their own domain, not buried in stress or home
- Rich logging UX (category filter, severity slider, history)
- Correlation engine can be reused for F6 (medications/supplements)
- Follows Bearable's structure but with transparent stats

**Cons:**
- Requires a nav destination — Profile tab or new FAB entry
- More new files (~7–8)
- Correlation engine is the hardest piece; needs careful statistical implementation

**Complexity**: Medium  
**Risk**: Medium (correlation math requires testing)

---

## Approach 2: Symptoms as "Stress Factor Extension" — Inside Stress Tab

**Summary**: Symptoms live inside the Stress tab as an additional factor card ("Body Signals"). Users can log symptoms from a card tap, and they feed into the stress score as a negative modifier. Correlation shown as part of the existing stress insight report.

### Architecture
- `SymptomEntry` same as Approach 1
- Symptoms modify stress score: add a 5th factor ("body signals") to `StressFactorResult`
- Correlation surfaced in `StressInsightReport` via a new section in Foundation Models prompt
- Add `SymptomLogView` as a new `StressSheet` case

**Pros:**
- Minimal structural changes — stays inside Stress tab
- Symptoms naturally relate to stress (pain, fatigue increase perceived stress)
- Foundation Models already writing stress insights — symptoms add richness to prompt

**Cons:**
- Tight coupling: symptoms become part of stress score, which is conceptually wrong (a headache isn't "stress")
- Correlation surface area is limited to stress context only
- Harder to export symptoms independently
- Clutters Stress tab further

**Complexity**: Low–Medium  
**Risk**: Medium (score coupling is architecturally fragile)

---

## Approach 3: Symptoms as "Wellness Experiments" — Extending Stress Lab

**Summary**: Rather than building a new log, extend the existing `StressExperiment` / Stress Lab feature. Users define a symptom experiment: "Does caffeine correlate with my headaches?" The experiment runs for 7–14 days, tracking daily symptom severity alongside the existing stress metrics.

### Architecture
- Add `symptomName` and `symptomSeverities: [Date: Double]` to `StressExperiment`
- `SymptomExperimentView` alongside existing `StressLabView`
- Use cached CI/delta pattern exactly from `StressExperiment`

**Pros:**
- Minimal new code — extends an existing, proven model
- Built-in experiment framing is epistemically correct ("let's test this hypothesis")
- Already has CI + delta display
- Fewer new files

**Cons:**
- Forces structured hypothesis format — ad-hoc symptom logging (e.g., "I feel bloated right now") doesn't fit
- Experiment = one symptom at a time; users often have multiple concurrent symptoms
- No intra-day timestamp (experiments are day-granularity)
- Doesn't solve the "bring data to your doctor" use case well

**Complexity**: Low  
**Risk**: Low (familiar model, no new patterns)

---

## Approach 4: Hybrid — Lightweight Log + Lazy Correlation

**Summary**: A minimal symptom log (log a symptom in 3 taps) embedded in the Home screen and/or profile, with correlation insights that surface lazily after ≥7 days of data. No dedicated tab needed. Symptoms accessible from Home (quick-log card) and history in Profile.

### Architecture
- `SymptomEntry` @Model with fast init (name, severity, timestamp)
- Built-in symptom library (20 common symptoms across 4 categories) + free-text custom
- `SymptomQuickLogView`: sheet triggered from Home or Profile — category picker → severity slider → done
- Correlation shown as cards in Profile: "After eating late, your headaches tend to be moderate (r=0.52, N=12)"
- Lazy: No correlation shown until ≥7 paired data points

**Pros:**
- Lowest friction logging (3 taps: symptom → severity → save)
- Doesn't require a new tab
- Correlation cards in Profile are a natural "understand yourself" surface
- Gradual reveal (starts as a log, becomes insightful with data)

**Cons:**
- Home screen already has multiple cards — quick-log adds another
- Profile needs to become real (currently a placeholder) to host correlation cards
- Less powerful UX than a dedicated log view — harder to review history, trends

**Complexity**: Medium  
**Risk**: Low–Medium

---

## Edge Cases to Consider

- [ ] **Intra-day vs. daily granularity**: Headache at 2pm vs. "had a headache today" — timestamps matter for meal correlation (need to compare symptom time with meal time within the same day)
- [ ] **Baseline noise**: Severity 5 every day ≠ useful signal. Need to detect flat distributions and warn
- [ ] **Multi-symptom correlation**: User has headaches AND bloating — need to handle each independently
- [ ] **Confounders**: A correlation with "high-fat meals" may be driven by sleep not food — must not over-claim
- [ ] **Data sparsity**: User only logs symptoms some days — need to distinguish "no symptom" from "didn't log"
- [ ] **Symptom deletion**: Deleting entries retroactively invalidates correlations — need consistency
- [ ] **Symptom library vs. free text**: Limit to ~20 preset + custom to avoid overwhelming users
- [ ] **Export privacy**: Symptom data may be sensitive — export should be opt-in, clearly labeled
- [ ] **N warning thresholds**: Show "Collecting data (X/7 days)" progress until minimum reached
- [ ] **Reverse correlation**: Some correlations are protective (good sleep → no headaches) — must show direction clearly
- [ ] **SwiftData lightweight migration**: New model, no relationships — no migration needed
- [ ] **Symptom name dedup**: "headache" vs "Headache" vs "head pain" — normalize library symptoms, allow custom

## Open Questions

- [ ] Should symptom correlation use day-level aggregation or intra-day pairing (symptom within ±4hrs of meal)?
- [ ] What's the minimum symptom library? 10 presets? 20? Categories: digestive, pain, energy, mood?
- [ ] Should symptoms contribute to the stress score composite, or remain independent?
- [ ] Is Spearman the right stat? Could use Kendall's tau (better for small N) — decide in planning
- [ ] Where does symptom tracking live in the navigation? Profile tab is a placeholder; is now the time to build it?

## Recommendation

**Approach 4 (Hybrid — Lightweight Log + Lazy Correlation)** with elements from Approach 1's correlation engine.

### Rationale
1. **3-tap logging is the key UX insight**: Bearable loses users to friction. WellPlate wins by making symptom logging feel as fast as a mood check-in.
2. **Profile tab activation**: F5 is the right moment to build out the Profile tab as a "Know Yourself" hub — symptoms, past journals, wellness calendar all live there. This gives a cohesive story without a 4th tab.
3. **Correlation engine is Approach 1 quality in Approach 4 structure**: The math is the same regardless of where the UI lives; the lazy reveal respects data sparsity.
4. **Avoids Stress tab coupling**: Keeping symptoms independent from the stress score prevents architectural fragility and over-claiming.
5. **Intra-day timestamp**: Even in the hybrid approach, store exact timestamps — enables ±4hr meal correlation in future without a model migration.

### Key design decisions for planning
- **~20 preset symptoms** in 4 categories (digestive, pain, energy, mood/cognitive) + custom
- **Spearman r + bootstrapped 95% CI** with N displayed always
- **Day-level correlation for MVP** (aggregate max/avg severity per day; intra-day ±4hr pairing as v2)
- **Minimum 7 paired days** before any correlation surface
- **Profile tab becomes real**: hosts `SymptomHistoryView` + `SymptomCorrelationView`
- **Quick-log sheet**: triggered from Home FAB (new option) or Profile
- **Export**: adds `symptom_max_severity` column per day to existing CSV

## Research References

- Bearable (competitor) — "correlation grids without correlation values" as churn trigger (deep-research-report-2.md lines 27–29)
- Deep research F5 assessment — "extremely high fit" with meal context + stress substrate (lines 428–436)
- `StressExperiment.swift` — proven CI + delta pattern (bootstrapped CILow/CIHigh already in production)
- `EatingTrigger` enum — shows WellPlate already thinks about emotional/contextual meal triggers
- `WellnessReportGenerator` — CSV pipeline to extend, not rebuild
