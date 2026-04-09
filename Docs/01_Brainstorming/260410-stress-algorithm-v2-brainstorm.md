# Stress Algorithm v2 — Brainstorm

**Date:** 2026-04-10
**Status:** Brainstorm complete, pending strategy/plan
**Research:** [Stress Algorithm Calibration Research](../06_Miscellaneous/Stress%20Algorithm%20Calibration%20Research.md)

---

## Problem Statement

The current stress algorithm uses 4 equally-weighted factors (Exercise, Sleep, Diet, Screen Time), each scored 0-25 for a total of 0-100. This has several critical flaws:

1. **Only 9 of 30 available data points** are used in scoring
2. **One-directional bias** — factors can only add stress (0-25), never actively reduce it. Good sleep doesn't lower stress; it just adds less.
3. **No physiological signals** — HRV, Resting HR, and Heart Rate are fetched and displayed but don't contribute to the score
4. **Equal weighting** doesn't reflect research (sleep deprivation has 10x the cortisol impact of mild dietary imbalance)
5. **No gender awareness** — men and women respond differently to the same stressors
6. **Static thresholds** — HRV and RHR must be scored against personal baselines, not population averages
7. **Missing data defaults to neutral** (12.5/25) which silently fills in assumptions

## Goal

Design a research-calibrated, gender-aware, bipolar stress algorithm that:
- Produces a reliable 0-100 score from **day 1** with behavioral data alone
- Gets **more accurate** as physiological data (Apple Watch) calibrates over 7+ days
- Recognizes that good behaviors **actively reduce stress**, not just "add less"
- Handles missing data gracefully without distorting the score

---

## Available Factors (22 total)

### Complete Inventory

| # | Factor | Data Source | Type |
|---|---|---|---|
| 1 | Sleep Duration | HealthKit sleep analysis | Behavioral |
| 2 | Deep Sleep | HealthKit sleep analysis | Behavioral |
| 3 | Steps | HealthKit .stepCount | Behavioral |
| 4 | Active Energy | HealthKit .activeEnergyBurned | Behavioral |
| 5 | Diet Quality (protein, fiber, fat, carbs) | FoodLogEntry (SwiftData) | Behavioral |
| 6 | Calories | FoodLogEntry.calories | Behavioral |
| 7 | Screen Time | DeviceActivity thresholds | Behavioral |
| 8 | Caffeine (coffee cups) | WellnessDayLog.coffeeCups | Behavioral |
| 9 | Hydration (water glasses) | WellnessDayLog.waterGlasses | Behavioral |
| 10 | Mood (0-4 scale) | WellnessDayLog.moodRaw + HK State of Mind | Subjective |
| 11 | Symptoms (name, category, severity) | SymptomEntry (SwiftData) | Subjective |
| 12 | Circadian Regularity (SRI) | CircadianService (computed from 7-day sleep) | Rhythm |
| 13 | Daylight Exposure | HealthKit .timeInDaylight | Rhythm |
| 14 | Heart Rate (avg) | HealthKit .heartRate | Physiological |
| 15 | Resting Heart Rate | HealthKit .restingHeartRate | Physiological |
| 16 | HRV (SDNN) | HealthKit .heartRateVariabilitySDNN | Physiological |
| 17 | Journaling | JournalEntry (SwiftData) | Modifier |
| 18 | Eating Triggers | FoodLogEntry.eatingTriggers | Modifier |
| 19 | Hunger Level | FoodLogEntry.hungerLevel | Modifier |
| 20 | Fasting (active/completed/broken) | FastingSession (SwiftData) | Modifier |
| 21 | Mindful Eating (Presence) | FoodLogEntry.presenceLevel | Modifier |
| 22 | Supplement Adherence | AdherenceLog (SwiftData) | Modifier |

### Removed From Consideration
- **Blood Pressure** (systolic/diastolic) — too few users have data, manual logging only
- **Respiratory Rate** — minimal independent value when HRV and RHR are available
- **Exercise Minutes** — overlaps with Steps + Active Energy, not separate factor

---

## Priority Ranking by Stress Impact

### Tier 1: Primary Drivers (direct causal link to cortisol / ANS)

| Priority | Factor | Impact | Male | Female |
|---|---|---|---|---|
| 1 | Sleep Duration | Sleep deprivation elevates cortisol ~40%. Single most impactful modifiable factor. | High. Cognitive drops faster. | Very high. Hormonal sensitivity amplifies effect. Women need ~20 min more. |
| 2 | Deep Sleep | Deep sleep (N3/SWS) is when cortisol resets. <45 min = incomplete clearance. | Lose deep sleep earlier with age (~35). | Retain longer but more fragile — disrupted by hormonal cycles. |
| 3 | HRV (SDNN) | Gold-standard stress biomarker. r = -0.50 to -0.68 with cortisol. | Baseline typically higher. Drops sharply under acute stress. | Baseline typically lower. ~12% swing across menstrual cycle. |
| 4 | Resting HR | Chronic autonomic stress indicator. +10 BPM sustained = burnout. | Baseline 60-72 BPM. More responsive to physical stressors. | Baseline 65-78 BPM. More responsive to emotional stressors. |
| 5 | Exercise | 30 min moderate exercise reduces cortisol 15-25%. Benefits plateau at 7,000 steps. | Greater benefit from high-intensity. Overtraining risk. | Greater benefit from moderate-intensity. |

### Tier 2: Strong Secondary Factors

| Priority | Factor | Impact | Male | Female |
|---|---|---|---|---|
| 6 | Mood | Direct subjective proxy. Correlates 0.7+ with cortisol. | Underreport stress. Reports track physiology well. | More accurate reporters but higher baseline reporting. Limbic activation, lower cortisol correlation. |
| 7 | Caffeine | Single cup causes ~50% cortisol increase. All-day caffeine prevents HPA rest. | Faster CYP1A2 metabolism. Clears in ~4h. | Slower metabolism. OCP doubles half-life. Same 3 cups = longer elevation. |
| 8 | Circadian (SRI) | Sleep regularity is a STRONGER mortality predictor than sleep duration (UK Biobank). Irregularity shifts cortisol peak timing. | More tolerant of shifts, recover slower. | Shorter circadian period. More sensitive to disruption. |
| 9 | Screen Time | Blue light suppresses melatonin. 1-2h before bed most detrimental. >4h daily = high-stress marker. | More affected by news/gaming. | More affected by social media comparison. |
| 10 | Hydration | <1.5L/day = 50% higher cortisol reactivity to ALL stressors. Acts as systemic amplifier. | Higher absolute needs (~3.7L/day). | More sensitive to dehydration effects on mood. |

### Tier 3: Moderate Factors

| Priority | Factor | Impact | Male | Female |
|---|---|---|---|---|
| 11 | Diet Quality | Low protein = low serotonin precursors. High sugar = cortisol spike + crash. | Less affected short-term. | More sensitive to blood sugar swings. Low iron/B12 worsen resilience. |
| 12 | Calories | Under-eating (<1200 kcal) raises cortisol. Overeating triggers inflammatory stress. | Threshold ~1500 kcal. | Threshold ~1200 kcal. Chronic restriction more damaging to HPA axis. |
| 13 | Heart Rate (avg) | Acute stress marker. Less useful than RHR (confounded by activity). | Higher reactivity to physical stress. | Higher reactivity to emotional stress. |
| 14 | Symptoms | Headache/GI = blunted cortisol (burnout). Muscle tension = elevated cortisol. Fatigue = flattened curve. | Underreport somatic symptoms. | 2x more likely to report stress-related somatic symptoms. |
| 15 | Daylight | <10 min/day = disrupted serotonin/melatonin. Morning light enhances CAR by 20-40%. | Moderate mood impact. | Stronger seasonal mood sensitivity (3:1 ratio). |

### Tier 4: Modifiers (not scored, nudge final result)

| Factor | Condition | Effect |
|---|---|---|
| Journaling | Wrote entry today | Reduces cortisol 10-15% |
| Eating Triggers | "stress"/"anxiety" logged | Stress-eating feedback loop |
| Hunger Level | Ate at hunger <3/10 | Emotional eating signal |
| Fasting (active) | Dynamic based on progress/hours/experience | Hour-by-hour cortisol curve |
| Fasting (completed) | Finished target | Metabolic resilience built |
| Fasting (broken) | Abandoned early | Got stress without benefit |
| Mindful Eating | Presence >7/10 | Reduces post-meal cortisol ~12% |
| Supplement Adherence | 100% vs <50% | Indirect (Mg, B-complex, adaptogens) |

---

## Core Design Decision: Bipolar Signal Model

### Problem With Unidirectional Scoring

The old model treats every factor as a stress CONTRIBUTOR on a 0.0-1.0 scale. The best any factor can do is contribute zero. Good sleep doesn't lower stress — it just "adds less." This is physiologically wrong.

Research confirms that positive behaviors actively reduce cortisol:
- 30 min moderate exercise: -15 to -25% cortisol
- 7-9h optimal sleep: cortisol nadir properly resets
- Proper hydration: cortisol reactivity drops 50% vs dehydrated
- Morning daylight: CAR enhanced 20-40%
- Journaling: -10 to -15% cortisol
- High HRV: strong parasympathetic recovery tone

### Bipolar Signal (-1.0 to +1.0)

Each factor produces a signal on a bipolar scale:

```
-1.0                    0.0                    +1.0
  |                      |                      |
  v                      v                      v
ACTIVELY              NEUTRAL               ACTIVELY
REDUCING             (no effect)            INCREASING
STRESS                                      STRESS
```

---

## Signal Normalization Curves (Research-Calibrated)

### Sleep Duration
```
 <4h  -> +0.95  (severe deprivation, ~40% cortisol nadir shift)
 4-5h -> +0.60
 5-6h -> +0.25
 6-7h -> +0.05  (slightly stressful)
 7h   ->  0.00  (neutral threshold)
 7-8h -> -0.15  (actively recovering)
 8-9h -> -0.30  (optimal recovery, cortisol nadir reset)
 9-10h-> +0.10  (oversleeping — inflammation/depression marker)
 >10h -> +0.30
```
Research basis: Sleep loss causes ~40% increase in cortisol nadir. U-shaped curve confirmed in UK Biobank mortality studies.

### Deep Sleep
```
 0 min   -> +0.80
 <30 min -> +0.50
 30-45   -> +0.15
 45-60   ->  0.00  (cortisol clearance threshold: 45 min)
 60-75   -> -0.20  (good recovery)
 75-90   -> -0.35  (excellent cortisol reset)
 90+     -> -0.40
```
Research basis: Deep sleep <45 min = incomplete cortisol clearance. Declines naturally with age (20% in 20s -> 10% in 60s). Age-adjust thresholds downward for 45+ users.

### Exercise (Steps)
```
 0       -> +0.60  (sedentary stress)
 2,000   -> +0.30
 4,000   ->  0.00  (neutral threshold)
 5,000   -> -0.15  (active benefit begins)
 7,000   -> -0.40  (optimal — plateau per research)
 10,000  -> -0.35  (diminishing returns)
 15,000+ -> +0.10  (overtraining risk)
```
Research basis: Benefits plateau at 5,000-7,000 steps (not 10,000). 7,000 steps = 22% reduction in depression risk. Yoga/mind-body shows greatest cortisol reduction (SMD = -0.59).

### Exercise (Active Energy)
```
 0 kcal    -> +0.50
 100       -> +0.20
 200       ->  0.00
 300       -> -0.15
 400-600   -> -0.30  (optimal range)
 600+      -> -0.25  (diminishing)
 >7-day-avg×1.5 -> +0.15  (overtraining flag)
```

### Caffeine (cups, ~95mg each)
```
 0 cups -> -0.05  (no stimulant stress on HPA axis)
 1 cup  -> +0.05  (habitual users tolerate first morning dose)
 2 cups -> +0.20
 3 cups -> +0.40
 4 cups -> +0.60
 5+     -> +0.80
```
Research basis: Single cup causes ~50% cortisol increase. Habitual users develop tolerance to first dose ONLY — subsequent doses still elevate cortisol. All-day caffeine prevents HPA axis rest state. OCP doubles caffeine half-life in women.

### Screen Time
```
 0h    -> -0.10  (digital detox benefit)
 <1h   -> -0.05
 1-2h  ->  0.00  (neutral)
 2-4h  -> +0.20
 4-6h  -> +0.45
 6-8h  -> +0.65
 8h+   -> +0.80
```
Research basis: Blue light 1-2h before bed most detrimental to sleep architecture. >4h daily is a high-stress profile marker. Evening screen time has 3x the impact of daytime.

### Hydration (glasses of water)
```
 <= 2 glasses -> +0.50  (dehydration stress + systemic amplifier)
 3-4          -> +0.20
 5-6          ->  0.00  (adequate)
 7-8          -> -0.20  (optimal — actively lowering cortisol reactivity)
 9-10         -> -0.15
 12+          -> +0.10  (overhydration/hyponatremia risk)
```
Research basis: Low fluid intake (<1.5L/day) = 50% higher cortisol reactivity. Even 1-2% body mass dehydration increases cortisol. Optimal stress buffer: 2.0-3.0L. Overhydration (>3L) can cause hyponatremia. **Also acts as a systemic multiplier on positive raw scores (see Layer 3).**

### Mood (0-4 scale)
```
 awful(0) -> +0.85
 bad(1)   -> +0.55
 okay(2)  -> +0.10
 good(3)  -> -0.20
 great(4) -> -0.40
```
Research basis: Correlates 0.7+ with salivary cortisol. Men: right prefrontal cortex activation, strong cortisol correlation. Women: limbic activation, lower cortisol correlation (hence female coefficient 0.7).

### Circadian Regularity (SRI, 0-100)
```
 <50  -> +0.70
 50-60-> +0.40
 60-70-> +0.10
 70-80->  0.00  (regular enough)
 80-90-> -0.25  (strong rhythm — cortisol timing optimized)
 90+  -> -0.40  (excellent)
```
Research basis: SRI median ~81. Bottom quintile = 20-48% higher all-cause mortality. Sleep regularity is a stronger mortality predictor than sleep duration (UK Biobank, Flinders University).

### Daylight Exposure (minutes)
```
 0 min  -> +0.40
 5-10   -> +0.15
 10-20  ->  0.00  (minimum for circadian entrainment)
 20-30  -> -0.20  (CAR enhanced 20-40%)
 30+    -> -0.30  (optimal)
```
Research basis: Bright light (2,500+ lux) enhances cortisol awakening response by 20-40%. 10-20 min outdoor light within 3h of waking is optimal. Overcast days require 30 min for same effect.

### Diet Quality
```
 poor (high sugar, low protein/fiber) -> +0.50
 below average                         -> +0.25
 fair                                  -> +0.10
 balanced                              ->  0.00
 good (adequate protein, fiber)        -> -0.15
 excellent (high protein, fiber,
   low sugar, adequate micros)         -> -0.30
```
Research basis: High-GI foods cause insulin spike -> crash -> cortisol elevation. Chronic stress promotes insulin resistance. Magnesium (500mg/day) reduces cortisol and increases deep sleep.

### Calories
```
 <1000    -> +0.65  (survival threat, HPA axis alarm)
 1000-1200-> +0.30
 1200-1500-> +0.05
 1500-2200->  0.00  (neutral range)
 2200-2500-> -0.05  (slight surplus, fine)
 2500-3000-> +0.15
 >3000    -> +0.35
```
Research basis: Extreme deficit (<30% of maintenance) is a primary driver of non-functional overreaching. Women show cortisol dysregulation earlier in deficit than men (OAT axis).

### Symptoms (type-weighted severity)
```
 none        -> -0.10  (body feels good = resilience signal)
 mild (1-3)  -> +0.10
 moderate(4-6)-> +0.35
 severe (7-8)-> +0.60
 critical(9-10)-> +0.80

 Type multipliers:
   Headache/GI issues -> x1.2 (blunted cortisol = burnout signal)
   Muscle tension/TMJ -> x1.0 (elevated cortisol = acute stress)
   Fatigue/brain fog  -> x1.1 (flattened diurnal curve = chronic)
```
Research basis: Different symptom types signal different HPA axis states. Headache + GI associated with blunted cortisol reactivity (worse than acute elevation). Women 2x more likely to somatize stress.

### HRV — SDNN (when calibrated, 7+ days baseline)
```
 +15%+ above personal baseline  -> -0.40  (excellent parasympathetic tone)
 +10% above                     -> -0.25  (good recovery)
 within +/-10%                  ->  0.00  (homeostasis)
 -10% to -20% below             -> +0.40  (moderate strain)
 -20%+ below                    -> +0.80  (high stress / illness onset)
```
Research basis: Must use personal baseline, not population averages. 30-day rolling average is gold standard. Nocturnal HRV > daytime for stress prediction. Commercial wearables weight HRV at 30-50% of readiness scores. SDNN-cortisol correlation r = -0.50 to -0.68.

### Resting Heart Rate (when calibrated, 7+ days baseline)
```
 -5+ BPM below personal baseline -> -0.20  (improved cardio efficiency)
 within +/-3 BPM                 ->  0.00  (normal variation — noise)
 +5 to +8 BPM above              -> +0.40  (acute strain)
 +10 BPM+ above                  -> +0.80  (chronic stress / overtraining)
```
Research basis: Normal day-to-day variation is +/-3 BPM. Single night sleep dep = +5-8 BPM. Chronic stress = +10 BPM sustained. 7-day rolling avg >> single snapshot.

### Heart Rate Average (when available)
```
 Deviation from personal baseline, scored similarly to RHR but at lower weight.
 Confounded by activity — supplemental signal only.
```

---

## Algorithm Architecture

### Two-Mode System

```
BASE MODE (day 1 — iPhone, no Watch needed)
  Behavioral + Sleep factors carry full weight
  Full 0-100 score from logged + HealthKit basics
  HRV/RHR show "Calibrating..." in UI

ENHANCED MODE (after 7+ days with Watch data)
  HRV, RHR, HR avg activate
  They "absorb" weight from factors they overlap with
  Score refined, not shifted
  Total weight pool always = 100
```

### Weight Distribution

#### Base Mode Weights (sum = 90, normalized to 100)

| Tier | Factor | Base Weight |
|---|---|---|
| **T1** | Sleep Duration | 15 |
| **T1** | Deep Sleep | 9 |
| **T1** | Exercise (steps + energy) | 14 |
| **T1** | Circadian Regularity | 10 |
| | **Tier 1 subtotal** | **48** |
| **T2** | Caffeine | 8 |
| **T2** | Screen Time | 7 |
| **T2** | Mood | 6 |
| **T2** | Daylight | 4 |
| | **Tier 2 subtotal** | **25** |
| **T3** | Diet Quality | 7 |
| **T3** | Calories | 5 |
| **T3** | Symptoms | 5 |
| | **Tier 3 subtotal** | **17** |
| | **Base total** | **90** |
| | **Physiological reserve** | **10** (empty until calibrated) |

When physio data unavailable: 90 pts normalized to 100 scale (score = base_raw x 100/90)

#### Enhanced Mode Weights (after physio calibration)

When HRV/RHR/HR calibrate in, they absorb weight from overlapping base factors:

| Factor | Base Weight | Enhanced Weight | Change |
|---|---|---|---|
| Sleep Duration | 15 | 11.5 | -3.5 (absorbed by HRV+RHR) |
| Deep Sleep | 9 | 9 | unchanged |
| Exercise | 14 | 10 | -4 (absorbed by HRV+RHR+HR) |
| Circadian | 10 | 9 | -1 (absorbed by RHR) |
| Caffeine | 8 | 6.5 | -1.5 (absorbed by HRV) |
| Screen Time | 7 | 7 | unchanged |
| Mood | 6 | 6 | unchanged |
| Daylight | 4 | 4 | unchanged |
| Diet Quality | 7 | 7 | unchanged |
| Calories | 5 | 5 | unchanged |
| Symptoms | 5 | 5 | unchanged |
| **HRV** | — | **5** | NEW |
| **RHR** | — | **4** | NEW |
| **HR avg** | — | **1** | NEW |
| **TOTAL** | **90 (->100)** | **100** | |

### Gender Coefficients

Male = 1.0 baseline. Adjust Female only. Applied to weights, then re-normalized to maintain sum = 100.

| Factor | Male | Female | Research Basis |
|---|---|---|---|
| Sleep Duration | 1.0 | 1.3 | Higher sensitivity to fragmentation |
| Deep Sleep | 1.0 | 1.0 | Similar across genders |
| Exercise | 1.0 | 1.0 | Inconclusive for step-based measurement |
| Circadian | 1.0 | 1.1 | Shorter circadian period, more sensitive |
| Caffeine | 1.0 | 1.3 | CYP1A2 differences + OCP half-life doubling |
| Screen Time | 1.0 | 1.0 | Type-dependent, can't differentiate total hours |
| Mood | 1.0 | 0.7 | Women over-report vs physiology — dampen to avoid overestimation |
| Daylight | 1.0 | 1.1 | Stronger seasonal mood sensitivity |
| Diet Quality | 1.0 | 1.1 | More sensitive to blood sugar swings |
| Calories | 1.0 | 1.2 | Cortisol dysregulation earlier in deficit |
| Symptoms | 1.0 | 1.2 | Higher somatic expression |
| HRV (when active) | 1.0 | 0.9 | Higher baseline means drops less alarming |
| RHR (when active) | 1.0 | 1.0 | Similar deviation patterns |

Note: Menstrual cycle tracking not yet implemented. When added, apply 1.12x multiplier to raw SDNN during mid-luteal phase (days 15-28) before comparing to baseline.

### Missing Data Handling

**Within-tier redistribution:** When a factor has no data, its weight redistributes proportionally to other factors in the SAME tier. If an entire tier is empty, redistribute to remaining tiers.

**Minimum data threshold:** Require at least 3 factors with data across at least 2 tiers to produce a score. Otherwise show "Log more to see your stress score."

**Circadian early days (day 1-6):** Needs 7 days of sleep data. Its 10 pts redistributed proportionally: Sleep +4, Exercise +3, Screen Time +2, Mood +1.

**Physiological reserve (no Watch):** 10 pts normalized away. Score = base_raw x 100/90.

---

## Scoring Pipeline

### Layer 0: Baselines

```
HRV_baseline  = 30-day rolling avg (min 7 days to activate)
RHR_baseline  = 7-day rolling avg (min 5 days to activate)
Fasting_exp   = completed FastingSessions in last 30 days
```

### Layer 1: Bipolar Signal Normalization

Each factor -> signal in [-1.0, +1.0]
- Negative = actively reducing stress / building resilience
- Zero = neutral
- Positive = actively increasing stress

(See curves above for each factor)

### Layer 2: Weighted Aggregation

```
raw_score = SUM(adjusted_weight_i * bipolar_signal_i)
  for all available factors

adjusted_weight = base_weight * gender_coefficient
  then re-normalized so all adjusted weights sum to 100

raw_score range: -100 (maximum recovery) to +100 (maximum stress)
```

### Layer 3: Multipliers + Modifiers

**Hydration Multiplier (applied to POSITIVE portion only):**
Dehydration amplifies stress but doesn't reduce recovery benefits.
```
if raw_score > 0:
  raw_score = raw_score * hydration_multiplier
  
  <= 4 glasses: x1.25
  5-6 glasses:  x1.10
  7-10 glasses: x1.00
  12+ glasses:  x1.05
```

**Active Fasting Dynamic Modifier:**
During an active fast, fasting becomes a dynamic modifier based on progress, absolute hours, and gender.

| Progress | Phase | Male Modifier | Female Modifier |
|---|---|---|---|
| 0-15% | Just started | 0.0 | 0.0 |
| 15-30% | Hunger building | +0.3 | +0.5 |
| 30-50% | Blood sugar dropping | +1.0 | +1.5 |
| 50-70% | Peak stress window | +2.0 | +2.5 |
| 70-85% | Body adapting | +1.5 | +2.0 |
| 85-100% | Home stretch | +0.8 | +1.0 |

Absolute hours cap: prevents short fasts from getting high modifiers.
Experience dampening: habitual fasters (6+ sessions/30d) get 0.65x modifier.
Fasted + vigorous exercise: 1.5x amplifier on fasting modifier.

After fast ends:
- Completed: -1.0 modifier (reward)
- Broke early <50%: +1.5 (stress without benefit)
- Broke early >=50%: +0.5 (partial benefit)

Research basis: 24h fast advances cortisol peak by 48 min, amplitude +11%. 2-4 weeks for HPA adaptation. More stressful for pre-menopausal women (OAT axis).

**Compound Detector:**
```
RHR rising + HRV declining simultaneously -> +2.0 penalty
  (strongest physiological signature of burnout/illness)

Mood/HRV gap > 40% -> flag "Stress Paradox" insight
  Case A (high subjective, low physiological): anxiety/mental fatigue
  Case B (low subjective, high physiological): "wired but tired"
```

**Tier 4 Static Modifiers (cap: +/-5):**

| Factor | Condition | Male | Female |
|---|---|---|---|
| Journaling | Wrote entry today | -1.0 | -1.5 |
| Eating Triggers | "stress"/"anxiety" logged | +1.5 | +2.0 |
| Hunger Level | Ate at hunger <3/10 | +1.0 | +1.5 |
| Mindful Eating | Presence >7/10 | -0.5 | -0.5 |
| Supplement Adherence | 100% today | -0.5 | -0.5 |
| Supplement Adherence | <50% today | +0.5 | +0.5 |

**Trend Adjustment (cap: +/-3):**
For factors with 7-day history (HRV, RHR, Sleep, Exercise, Mood):
```
trend = avg_last_3_days - avg_days_4_to_7
Worsening: +1 to +3 (proportional to decline rate)
Improving: -1 to -3
```

### Layer 4: Display Mapping

```
display_score = clamp(0, 100, 50 + raw_score/2)

raw = -100 -> display = 0   (maximum resilience)
raw = 0    -> display = 50  (neutral)
raw = +100 -> display = 100 (maximum stress)
```

**Stress Levels (revised thresholds):**

| Display Score | Level | Meaning |
|---|---|---|
| 0-20 | Excellent | Active recovery state — positive behaviors dominating |
| 21-40 | Good | Resilient — healthy balance |
| 41-55 | Balanced | Neutral zone — neither stressed nor recovering |
| 56-70 | Moderate | Stress building — room to improve |
| 71-85 | High | Intervention needed |
| 86-100 | Very High | Burnout risk — prioritize self-care |

---

## Worked Example

**User: Female, iPhone only (no Watch), Day 3**

Available data: Sleep 6.5h (no deep sleep detail), Steps 5,200, Energy 310 kcal, Mood "bad" (1), Coffee 3 cups, Screen Time 5.1h, Diet fair (52g protein, 8g fiber), Calories 1,600, Symptoms headache sev 6, Water 3 glasses. Circadian/HRV/RHR/Daylight not yet available.

**Layer 1 — Bipolar signals:**
```
Sleep:    6.5h  -> +0.05
Exercise: 5,200 -> -0.05 (between 4k and 5k, slight benefit)
Caffeine: 3cups -> +0.40
Screen:   5.1h  -> +0.50
Mood:     bad   -> +0.55
Diet:     fair  -> +0.10
Calories: 1,600 -> 0.00
Symptoms: headache sev6 -> +0.35 x 1.2 = +0.42
```

**Layer 2 — Weights (base mode, excluded: Deep/Circadian/Daylight/Physio):**
Available pool = 15+14+8+7+6+7+5+5 = 67, normalized to 100.
Gender coefficients (Female) applied, then re-normalized.

```
Sleep:    15 x 1.3 = 19.5 -> normalized: 25.0
Exercise: 14 x 1.0 = 14.0 -> 17.9
Caffeine:  8 x 1.3 = 10.4 -> 13.3
Screen:    7 x 1.0 =  7.0 ->  9.0
Mood:      6 x 0.7 =  4.2 ->  5.4
Diet:      7 x 1.1 =  7.7 ->  9.9
Calories:  5 x 1.2 =  6.0 ->  7.7
Symptoms:  5 x 1.2 =  6.0 ->  7.7
(Sum after gender coeff = 74.8, then /74.8 x 100 = normalized)
Verify: 25.0+17.9+13.3+9.0+5.4+9.9+7.7+7.7 = 95.9 (rounding)
```

**Layer 2 — Weighted sum:**
```
raw = 25.0*(+0.05) + 17.9*(-0.05) + 13.3*(+0.40) + 9.0*(+0.50)
    + 5.4*(+0.55) + 9.9*(+0.10) + 7.7*(0.00) + 7.7*(+0.42)
    = 1.25 - 0.90 + 5.32 + 4.50 + 2.97 + 0.99 + 0.00 + 3.23
    = 17.36
```

**Layer 3 — Modifiers:**
```
Hydration: 3 glasses -> x1.25 (raw is positive, so apply)
  17.36 x 1.25 = 21.7

No fasting, no journaling, no eating triggers
Tier 4 modifiers = 0
Trend = not enough data yet (day 3)

Final raw = 21.7
```

**Layer 4 — Display:**
```
display = 50 + 21.7/2 = 60.85 -> 61
StressLevel: Moderate
```

Result: 61/100 — Moderate stress. She has mild sleep deficit, 3 coffees, bad mood, headache, dehydrated. But her exercise is helping slightly (negative signal). The dehydration multiplier amplified everything by 25%. If she had drunk 8 glasses of water, the score would have been ~55 (Balanced) instead.

---

## Calibration UI States

### Day 1-6
```
Stress Score: 61
Level: Moderate

[progress bar] Calibrating (Day 3/7)
Sleep regularity, HRV, and heart rate patterns
will improve accuracy after 7 days of tracking.
```

### Day 7+ (no Watch)
```
Stress Score: 58
Level: Moderate
+ Circadian regularity now active

Tip: Pair with Apple Watch for HRV and heart rate
tracking to unlock full accuracy.
```

### Day 7+ (Watch, fully calibrated)
```
Stress Score: 55
Level: Balanced
Fully calibrated

Top stressors: High caffeine, Declining sleep trend
Resilience boosters: Good exercise, Strong circadian rhythm
```

---

## Open Items for Strategy Phase

1. **REM Sleep** — Research says REM independently predicts emotional resilience. Consider splitting Deep Sleep (9 pts) into Deep (6) + REM (3) as sub-factors.
2. **Menstrual Cycle Tracking** — When implemented, apply 1.12x HRV multiplier during mid-luteal phase and adjust fasting sensitivity.
3. **Age-Adjusted Thresholds** — Deep sleep thresholds should lower for 45+ users. HRV population quintiles should be used as fallback before personal baseline exists.
4. **OCP Detection** — Women on oral contraceptives need caffeine coefficient of 1.5 (not 1.3). Requires onboarding question or health profile.
5. **Score Smoothing** — Bipolar model may be more volatile than old model. Consider: displayed_score = 0.7 x today + 0.3 x yesterday for stability.
6. **Stress Paradox Insights** — When mood and HRV disagree by >40%, surface an insight card to the user. Design needed.
7. **Overtraining Detection** — Rising RHR + declining HRV + high exercise volume = overtraining syndrome. Surface as a special insight, not just score penalty.
