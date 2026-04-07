# 10-Feature Integration Roadmap

**Date**: 2026-04-06
**Source**: `Docs/06_Miscellaneous/deep-research-report-2.md`
**Workflow**: Each feature follows `/develop` pipeline: brainstorm → strategize → plan → audit → resolve → checklist → implement → fix

---

## Phase 1 — Low-Hanging Fruit (High Value, Low Complexity)

> Goal: Ship features that build directly on existing infrastructure with minimal new frameworks or permissions.

### F1. Fasting Timer / IF Tracker
- **Why first**: InterventionTimer infrastructure already exists; fasting is a timer + schedule + stress correlation
- **Scope**: Eat/fast window definition, timer UI, notification at window open/close, "fasting vs. stress score" mini-insight
- **Builds on**: `InterventionTimer.swift`, `WellnessDayLog`, stress score pipeline
- **New files**: ~3–4 (model, view, VM)
- **Effort**: Low

### F2. HealthKit Mental Wellbeing (State of Mind + Assessments)
- **Why first**: You already write mood (5-emoji); mapping it to HealthKit State of Mind is a thin integration layer
- **Scope**: Write mood → `HKStateOfMind`; read State of Mind from Health app; optional PHQ-9/GAD-7 read (display-only, not diagnostic)
- **Builds on**: `MoodCheckInCard`, `HealthKitService`, `WellnessDayLog.moodRaw`
- **New files**: ~2 (service extension, optional assessment view)
- **Effort**: Low–Medium

### F3. Circadian Stack
- **Why first**: Pure HealthKit read + simple scoring math; no new frameworks
- **Scope**: Fetch `timeInDaylight`, compute sleep regularity index (bed/wake consistency over 7 days), blend with existing screen time timing → "Circadian Score" card on StressView
- **Builds on**: `HealthKitService`, `StressViewModel`, sleep data pipeline
- **New files**: ~3 (CircadianService, CircadianCardView, model)
- **Effort**: Low–Medium

**Phase 1 delivers**: 3 features, ~8–10 new files, no new framework entitlements

---

## Phase 2 — Engagement Layer (Retention + Daily Loop)

> Goal: Features that make users open the app daily and deepen the reflection habit.

### F4. Journal / Gratitude Prompts Tied to Mood
- **Why now**: Mood check-in exists; journaling extends it into a reflection habit that feeds the daily loop
- **Scope**: Text journal entry per day, AI-generated prompts (Foundation Models) based on mood + stress signals, "themes over time" summary view
- **Builds on**: `MoodCheckInCard`, `WellnessDayLog`, `StressInsightService` (Foundation Models pattern)
- **New files**: ~4–5 (JournalEntry model, JournalView, JournalPromptService, JournalInsightView)
- **Effort**: Medium

### F5. Symptom Tracking Correlated with Food/Sleep
- **Why now**: The meal context + sleep + stress substrate is mature; symptom tracking is the natural "bring data to your doctor" extension
- **Scope**: User-defined symptoms (headache, bloating, energy crash, etc.), severity + timestamp, correlation engine with effect sizes + uncertainty, export integration
- **Builds on**: `FoodLogEntry`, `WellnessDayLog`, `WellnessReportGenerator` (export)
- **New files**: ~5–6 (SymptomEntry model, SymptomLogView, CorrelationEngine, SymptomReportView)
- **Design rule**: Ship correlations with effect sizes + confidence intervals + "correlation ≠ causation" language. Never ship opaque grids.
- **Effort**: Medium

### F6. Supplement / Medication Reminders
- **Why now**: Pairs naturally with symptom tracking (Phase 2 synergy) and clinician export
- **Scope**: HealthKit Medications API read, manual supplement entry, reminder notifications, adherence log, correlation with symptoms/stress
- **Builds on**: `HealthKitService`, symptom tracking (F5), notification infrastructure
- **New files**: ~4–5 (MedicationService, SupplementEntry model, MedicationReminderView, AdherenceView)
- **Effort**: Medium

**Phase 2 delivers**: 3 features, ~13–16 new files, deepens daily engagement loop + clinician export story

---

## Phase 3 — Platform Expansion (New Surfaces)

> Goal: Bring WellPlate to Lock Screen, Dynamic Island, and Apple Watch.

### F7. Live Activities (ActivityKit)
- **Why now**: Fasting timer (F1) and interventions (existing) provide the "active state" content; Live Activities are the surface
- **Scope**: Fasting window countdown on Lock Screen + Dynamic Island, breathing session progress, optional hydration streak tracker
- **Builds on**: Fasting timer (F1), `InterventionTimer`, WidgetKit (existing stress widget)
- **New files**: ~4–5 (ActivityAttributes, LiveActivityView, ActivityManager)
- **Framework**: ActivityKit (new entitlement)
- **Effort**: Medium

### F8. Apple Watch Companion
- **Why now**: All data sources are mature; Watch is UX surface, not data source
- **Scope**: Glanceable stress score complication, quick mood/water logging, breathing session launch, "one suggestion" display. NO GPS workout tracking.
- **Builds on**: Everything — stress score, mood, interventions, hydration
- **New target**: WatchKit app extension
- **New files**: ~8–10 (Watch target, views, WatchConnectivity service)
- **Design rule**: Only ship what looks correct. No GPS mapping.
- **Effort**: Medium–High

**Phase 3 delivers**: 2 features, new platform surfaces (Lock Screen + Watch), ~12–15 new files

---

## Phase 4 — Social + Advanced AI (Moat Builders)

> Goal: Features that create defensible differentiation and subscription value.

### F9. Photo Meal Logging
- **Why now**: Requires most AI maturity; ship as "photo as context" MVP first
- **Scope MVP**: Snap photo → store with meal → use photo to ask clarifying questions via Foundation Models. Macros still derived from text/structured entry unless confidence is very high.
- **Scope V2** (later): On-device Vision food detection + portion estimation
- **Builds on**: `FoodLogEntry`, barcode scanner pattern, Foundation Models
- **New files**: ~3–4 (PhotoMealCaptureView, FoodVisionService)
- **Design rule**: Don't undermine trust story — if recognition is wrong, it's worse than no feature
- **Effort**: Medium (MVP) / High (V2)

### F10. Partner Accountability (SharePlay + CloudKit)
- **Why last**: Highest complexity, requires new frameworks + careful privacy design; all shareable artifacts (reports, scores, experiments) must exist first
- **Scope MVP**: Share a weekly wellness card via CloudKit private database sharing between 2 iCloud users. Optional co-breathing via SharePlay.
- **Builds on**: `WellnessReportGenerator`, stress score, interventions
- **New files**: ~6–8 (CloudKit sharing service, PartnerView, SharePlay activity, shared card model)
- **Frameworks**: CloudKit, GroupActivities (new entitlements)
- **Effort**: Medium–High

**Phase 4 delivers**: 2 features, subscription-tier differentiators, ~9–12 new files

---

## Phase Summary

| Phase | Features | New Files | Key Frameworks | Effort |
|-------|----------|-----------|----------------|--------|
| **1** | Fasting Timer, State of Mind, Circadian Stack | ~8–10 | HealthKit (existing) | Low–Med |
| **2** | Journal, Symptom Tracking, Medications | ~13–16 | HealthKit Medications, Notifications | Medium |
| **3** | Live Activities, Apple Watch | ~12–15 | ActivityKit, WatchKit | Med–High |
| **4** | Photo Meal Logging, Partner Accountability | ~9–12 | Vision, CloudKit, GroupActivities | Med–High |

---

## Develop Workflow Per Feature

Each feature (F1–F10) follows this pipeline sequentially:

```
/develop brainstorm <feature>     → Docs/01_Brainstorming/
/develop strategize <feature>     → Docs/02_Planning/Specs/
/develop plan <feature>           → Docs/02_Planning/Specs/
/develop audit <plan-path>        → Docs/03_Audits/
/develop resolve <plan-path>      → Docs/02_Planning/Specs/...-RESOLVED.md
 ── USER APPROVAL GATE ──
/develop checklist <resolved-path> → Docs/04_Checklist/
/develop audit <checklist-path>    → Docs/03_Audits/
/develop resolve <checklist-path>  → Docs/04_Checklist/...-RESOLVED.md
/develop implement <checklist>     → code changes + build
/develop fix                       → if build errors
```

**Hard stop**: No implementation begins without user approval of the resolved plan.

---

## Dependencies Graph

```
F1 (Fasting) ──────────────────────► F7 (Live Activities)
                                          │
F2 (State of Mind)                        ▼
                                     F8 (Watch)
F3 (Circadian)                            ▲
                                          │
F4 (Journal) ─────► F9 (Photo Meals) ────┘
                                          
F5 (Symptoms) ◄──► F6 (Medications)      
                         │                
                         ▼                
                    F10 (Partner) ◄── needs reports + scores ready
```

- F7 depends on F1 (fasting is the primary Live Activity content)
- F8 depends on F7 (Watch can mirror Live Activity states)
- F5 and F6 are mutual enhancers (ship in same phase)
- F10 depends on all shareable artifacts existing first
