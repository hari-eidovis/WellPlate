# Strategy: Symptom Tracking Correlated with Food/Sleep

**Date**: 2026-04-08
**Source**: `Docs/01_Brainstorming/260408-symptom-tracking-brainstorm.md`
**Status**: Ready for Planning

## Chosen Approach

**Hybrid — Lightweight Log + Lazy Correlation (Approach 4 from brainstorm, with Approach 1's correlation engine)**

A 3-tap symptom logging sheet accessible from both the Home screen and the Profile tab. Profile tab evolves from a placeholder into a "Know Yourself" hub hosting symptom history, correlation cards, and existing features (goals, body metrics, widget setup). Correlation engine computes Spearman rank correlations with bootstrapped 95% CI and surfaces results only after ≥7 paired days. Export extends the existing CSV pipeline.

## Rationale

- **3-tap logging wins adoption**: Bearable's biggest complaint is friction. Our flow: tap symptom → slide severity → save. Under 5 seconds, which matches our mood check-in UX standard.
- **Profile tab is ready**: `ProfilePlaceholderView` already has body metrics, goals, and widget setup. Adding symptom history + correlations transforms it into a coherent "understand yourself" hub without needing a 4th tab.
- **Reuses proven CI math**: `StressLabAnalyzer.swift` already implements 1000-iteration bootstrap CI for stress experiments. The same `bootstrapCI(baseline:experiment:iterations:)` function pattern works directly for symptom-factor correlations.
- **Independent from stress score**: Symptoms remain separate from the stress composite — no architectural fragility, no over-claiming. They're a parallel signal layer.
- **Lazy reveal respects data sparsity**: No premature correlations. Users see "Collecting data (X/7 days)" until enough paired observations exist. This prevents the Bearable trap of "correlations without confidence."

### Trade-offs accepted
- Profile tab restructure is non-trivial but necessary for Phase 2's engagement story
- Day-level correlation only in MVP (intra-day ±4hr meal pairing deferred)
- No Foundation Models insight generation for symptoms in MVP — raw correlation cards with human-readable interpretation are more trustworthy at launch

## Affected Files & Components

### New Files (~7)
| File | Purpose |
|---|---|
| `WellPlate/Models/SymptomEntry.swift` | SwiftData `@Model` — name, category, severity 1–10, timestamp, notes |
| `WellPlate/Models/SymptomDefinition.swift` | Built-in symptom library (20 presets in 4 categories) + custom type |
| `WellPlate/Core/Services/SymptomCorrelationEngine.swift` | Spearman r + bootstrapped 95% CI computation |
| `WellPlate/Features + UI/Symptoms/Views/SymptomLogSheet.swift` | Quick-log sheet — category → symptom → severity → save |
| `WellPlate/Features + UI/Symptoms/Views/SymptomHistoryView.swift` | Chronological list of past entries with severity badges |
| `WellPlate/Features + UI/Symptoms/Views/SymptomCorrelationView.swift` | Correlation cards with effect sizes, CI bands, N, disclaimers |
| `WellPlate/Features + UI/Symptoms/Views/SymptomDetailCardView.swift` | Individual correlation card component (reusable) |

### Modified Files (~4)
| File | Change |
|---|---|
| `WellPlate/App/WellPlateApp.swift` | Add `SymptomEntry.self` to `.modelContainer(for:)` |
| `WellPlate/Features + UI/Tab/ProfileView.swift` | Restructure `ProfilePlaceholderView` → add symptom history section + correlation section + "Log Symptom" button |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | Add symptom quick-log button to header (or body), add state + sheet for `SymptomLogSheet` |
| `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` | Add `symptom_name`, `symptom_max_severity` columns to CSV |

### Untouched (explicitly)
- `StressLabAnalyzer.swift` — referenced as a pattern but not modified; correlation engine is new
- `StressExperiment.swift` — not modified; symptoms are independent
- `MainTabView.swift` — no tab changes; Profile tab already exists
- `MoodCheckInCard.swift` — no changes

## Architectural Direction

### Data Model
```
SymptomEntry (@Model)
├── id: UUID
├── name: String              // e.g. "Headache", "Bloating"
├── category: String          // digestive, pain, energy, cognitive
├── severity: Int             // 1–10 scale
├── timestamp: Date           // Exact time of logging
├── day: Date                 // Calendar.startOfDay — for daily aggregation
├── notes: String?            // Optional context
├── createdAt: Date
```

```
SymptomDefinition (plain struct, not @Model)
├── name: String
├── category: SymptomCategory
├── icon: String              // SF Symbol
├── isCustom: Bool
```

Separate model from `WellnessDayLog` — symptoms are event-based (multiple per day) with intra-day timestamps. Linked by `day` for daily aggregation.

### Symptom Library (20 presets, 4 categories)
| Category | Symptoms |
|----------|----------|
| **Digestive** | Bloating, Nausea, Acid reflux, Stomach pain, Irregular digestion |
| **Pain** | Headache, Migraine, Joint pain, Muscle soreness, Back pain |
| **Energy** | Fatigue, Energy crash, Brain fog, Dizziness, Insomnia |
| **Mood/Cognitive** | Anxiety, Irritability, Low mood, Difficulty concentrating, Restlessness |

Users can add custom symptoms with free-text name.

### Correlation Engine
`SymptomCorrelationEngine` computes correlations between a specific symptom and a specific factor:

**Input**: Array of `(symptomSeverity: Double, factorValue: Double)` day-pairs  
**Output**: `SymptomCorrelation` struct with:
- `spearmanR`: Double (−1 to +1)
- `ciLow`: Double (5th percentile)
- `ciHigh`: Double (95th percentile)
- `pairedDays`: Int (N)
- `interpretation`: String (auto-generated: "moderate positive association")
- `isSignificant`: Bool (CI doesn't span zero)

**Factors correlated against** (per day):
1. Sleep hours (from HealthKit)
2. Stress score (from `StressReading` daily avg)
3. Caffeine cups (from `WellnessDayLog`)
4. Total calories (from `FoodLogEntry`)
5. Protein intake (from `FoodLogEntry`)
6. Fiber intake (from `FoodLogEntry`)
7. Water intake (from `WellnessDayLog`)

**Spearman rank correlation**: Convert both arrays to ranks, compute Pearson r on ranks. Robust to non-normality, appropriate for ordinal severity 1–10.

**Bootstrap CI**: 1000 iterations, resample paired observations with replacement, compute Spearman r for each sample, extract 5th/95th percentiles. Follows exact `StressLabAnalyzer.bootstrapCI()` pattern.

**Minimum N**: 7 paired days. Below this, show "Collecting data (X/7 days)".

### UI Flow
```
Home screen header → [+] symptom icon → SymptomLogSheet (sheet)
Profile tab → Symptom History section → SymptomHistoryView (navigationDestination)
Profile tab → Insights section → SymptomCorrelationView (navigationDestination)
Profile tab → "Log Symptom" CTA → SymptomLogSheet (sheet)
```

### SymptomLogSheet (3-tap flow)
```
Step 1: Category picker (4 large pills: Digestive, Pain, Energy, Cognitive)
Step 2: Symptom picker (5 pills per category + "Custom" option)
Step 3: Severity slider (1–10) + optional notes + Save
```

### Correlation Card Design (SymptomDetailCardView)
```
┌─────────────────────────────────────────┐
│ Headache ↔ Caffeine                     │
│                                         │
│ r = 0.52 (moderate positive)   N=14     │
│ ┌─────[====■=====]─────┐               │
│ -1          0          +1               │
│ 95% CI: [0.18, 0.79]                   │
│                                         │
│ ⚠ Correlation does not imply causation. │
│   Track more days to strengthen this.   │
└─────────────────────────────────────────┘
```

Every card shows: Spearman r with label, N (paired days), CI band visualization with zero line, and epistemic disclaimer.

### CSV Export Extension
Add to `WellnessReportGenerator.swift` header:
```
date,stress_score,calories,protein_g,carbs_g,fat_g,steps,water_glasses,mood,symptom_name,symptom_max_severity
```
Per day: join most-severe symptom name + its severity. Days without symptoms: empty cells.

## Design Constraints

1. **≥7 paired days** before showing any correlation — no premature insights
2. **Effect sizes always visible**: r value + CI band + N on every correlation card
3. **"Correlation ≠ causation" on every card** — non-negotiable
4. **Day-level aggregation for MVP**: Max severity per symptom per day; no intra-day meal pairing yet
5. **20 preset symptoms + custom**: Library is curated, not overwhelming
6. **Font/card conventions**: `.system(size:weight:design:.rounded)` on Profile (match Home convention); standard card styling
7. **Severity scale 1–10**: Not 1–5 (too coarse for meaningful correlation) or 1–100 (too granular for quick logging)
8. **Symptoms independent from stress score**: No coupling to the composite

## Non-Goals

- **Intra-day meal correlation** (±4hr window): Deferred to v2 — requires temporal pairing logic
- **Foundation Models symptom insights**: Not in MVP — raw correlation cards are more trustworthy
- **Symptom-intervention experiments**: Could extend StressLab later (F6 synergy)
- **Symptom contribution to stress score**: Explicitly excluded — separate signal layer
- **Medical diagnosis language**: Never — "This pattern may indicate" not "You have"
- **Symptom-to-symptom correlation**: Only symptom-to-factor; cross-symptom patterns deferred
- **Photo attachment on symptoms**: Out of scope
- **Monetization gating**: Decide in a future pass; ship full feature for now

## Open Risks

- **Profile tab restructure**: `ProfilePlaceholderView` has 700+ lines already (body metrics, goals, widgets). Adding symptoms sections increases complexity — consider splitting into sub-views.
  - Mitigation: New symptom sections are separate views passed into profile; don't bloat the existing file
- **Bootstrap CI performance**: 1000 iterations × 7 factors × N symptoms. For 5 symptoms × 7 factors = 35 correlations × 1000 iterations.
  - Mitigation: Run off main actor in a `Task`; cache results in the engine; recompute only when new data arrives
- **Small N variance**: With N=7, Spearman r can be noisy. Users might see contradictory results week to week.
  - Mitigation: CI band visually communicates uncertainty; "Track more days" language encourages patience
- **CSV column proliferation**: Multiple symptoms means multiple rows per day or wide columns.
  - Mitigation: MVP exports only the most-severe symptom per day; detailed export as v2
