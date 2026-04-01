# Brainstorm: Feature Prioritization from Deep Research

**Date**: 2026-04-02
**Status**: Ready for Planning
**Source**: `Docs/06_Miscellaneous/deep-research-report-2.md`

---

## Problem Statement

WellPlate already has an unusually coherent multi-signal wellness app (nutrition + hydration + mood + activity + sleep + screen time + stress scoring + AI insights). The question is: **which features should we build next to create real market differentiation**, given that we're a solo dev with no custom backend, competing against well-funded incumbents?

The deep research report analyzed competitors (MyFitnessPal, Lose It!, Bearable, Daylio, Welltory, Gentler Streak) and identified specific pain points from user reviews. This brainstorm synthesizes that research into a prioritized feature set, filtering for what's **most sensible** given our existing architecture.

## Core Requirements

- Features must be **solo-dev feasible** (no custom backend, no content moat needed)
- Must leverage **existing strengths** (multi-signal stress score, on-device AI, privacy-first, screen time integration)
- Must address **proven user pain points** from competitor reviews (not hypothetical needs)
- Must create **defensible differentiation** (not just feature parity)

## Constraints

- Solo developer — no team bandwidth for large maintenance surface
- No custom backend — must use Apple frameworks (HealthKit, CloudKit, ActivityKit, Foundation Models)
- iOS 26+ Foundation Models for AI features (with fallback for older devices)
- Privacy-first identity — no cloud data, no accounts, no tracking

---

## Tier 1: High-Impact, Low-Effort — Ship First

These features have the best ratio of perceived user value to development effort, and directly exploit competitor weaknesses.

### Feature 1A: Stress Lab (n-of-1 Experiments)

**Summary**: Users pick a micro-intervention ("No caffeine after 2pm", "Screen curfew at 10:30pm"), run it for 7–14 days, and get a statistically honest report — did stress change, which factor moved, and how confident is the result?

**Why this is #1**:
- Directly exploits the loudest competitor pain point: Bearable users complain that "correlations are misleading" and show "no values." This feature is the antidote
- We already have every data input needed: composite stress score, per-factor breakdown, meal context triggers, screen time signals, sleep stages
- Creates a **unique product category** — no wellness app offers structured self-experimentation
- Builds trust through transparency (effect sizes + uncertainty + "can't infer causation" language)

**Pros**:
- Perfect fit with existing data model (stress factors, daily logs, meal context)
- No ML training needed — paired comparisons, bootstrap CI, nonparametric stats
- Highly differentiated — no competitor does this
- Strong "Pro" monetization hook (free: 1 experiment at a time; paid: history, advanced analysis)
- Creates word-of-mouth moments ("I proved caffeine after 3pm raises my stress by 15 points")

**Cons**:
- Requires careful UX to avoid being intimidating (must feel "science-y but humane")
- Users need 7–14 days of data per experiment — delayed gratification
- Statistical edge cases (missing days, confounders) need thoughtful handling

**Complexity**: Medium | **Risk**: Low
**Solo-dev effort**: ~2-3 weeks for MVP

---

### Feature 1B: Live Activities (Fasting Timer, Hydration, Screen Curfew)

**Summary**: ActivityKit Live Activities for multi-hour states: fasting window countdown, hydration target progress, screen curfew countdown. Glanceable on Lock Screen and Dynamic Island.

**Why it's high priority**:
- We already use WidgetKit — ActivityKit is adjacent and well-documented
- Makes the app feel "system-native" — always present without opening the app
- Fasting timer is a top-demanded feature that competitors market heavily (MFP, Lose It!)
- Screen curfew countdown is **unique to us** (no competitor combines screen time + live activities)

**Pros**:
- Low–Medium effort (WidgetKit knowledge transfers directly)
- Multiple use cases from one framework investment (fasting, hydration, curfew)
- Increases daily engagement without requiring app opens
- Fasting timer naturally integrates with meal logging data (auto-detect eating windows)

**Cons**:
- ActivityKit has strict update limits and size constraints
- Fasting timer needs thoughtful UX for start/stop/auto-detect
- Need to avoid "notification fatigue" with too many live activities

**Complexity**: Low–Medium | **Risk**: Low
**Solo-dev effort**: ~1-2 weeks for fasting timer MVP, ~3-4 days per additional activity type

---

### Feature 1C: Wellness Report Export (PDF + CSV)

**Summary**: One-tap "Weekly Wellness Report" export: stress trends, factor deltas, top triggers, food patterns, sleep quality, and a "what helped" section. Exportable as PDF (clinician-friendly) or CSV (for analysis).

**Why it's high priority**:
- Proven user demand — Daylio users explicitly export PDFs for therapy; Apple's mental health assessments also emphasize PDF export
- Extremely low effort relative to perceived value (our data is already report-ready)
- Doubles as marketing material (users share screenshots/PDFs → organic acquisition)
- Strong "Pro" monetization candidate

**Pros**:
- Low effort for basic PDF (SwiftUI → UIGraphicsImageRenderer or PrintFormatter)
- High perceived value — transforms ephemeral data into "real" artifacts
- Clinician-friendly exports create a unique professional use case
- No backend needed

**Cons**:
- PDF layout design takes iteration to look professional
- Need to decide what's worth saying vs. over-claiming in reports
- CSV export needs clear column semantics

**Complexity**: Low–Medium | **Risk**: Low
**Solo-dev effort**: ~1-2 weeks

---

### Feature 1D: Food Confidence & Data Provenance UI

**Summary**: When the LLM extracts nutrition, show a clear provenance label: "Barcode-verified" vs. "AI-estimated (high confidence)" vs. "AI-estimated (low confidence)" — plus "what I assumed" for ambiguous meals.

**Why it's high priority**:
- Competitors get hammered in reviews for wrong portions/entries (even barcode-scanned ones)
- We already compute confidence scores and cache them — this is purely a UI exposure
- Builds trust, which is our brand identity
- Essentially free in development cost

**Pros**:
- Lowest effort of any feature here (UI + existing data)
- Directly addresses #1 competitor complaint (data accuracy skepticism)
- Reinforces privacy-first brand ("we show you exactly what we assumed")
- No new data model or service needed

**Cons**:
- Could surface our own estimation weaknesses (if shown poorly)
- Need thoughtful UI that doesn't clutter the logging experience

**Complexity**: Low | **Risk**: Very Low
**Solo-dev effort**: ~2-3 days

---

## Tier 2: Medium-Scope Moat Builders

These require more effort but create defensible differentiation that competitors can't easily copy.

### Feature 2A: Symptom Journal with Honest Correlations

**Summary**: User-defined symptoms (headache, bloating, fatigue, brain fog, etc.) with severity + timestamps, correlated with meals, sleep, caffeine, and screen time. Show effect sizes + uncertainty + explicit "correlation ≠ causation" language.

**Why it matters**:
- Bearable's #1 complaint is "misleading correlations" — we can be the app that does correlations *right*
- Our meal context data (triggers, hunger level, food type) is already the substrate that symptom analysis needs
- Creates an incredibly sticky product ("I can't leave because 6 months of symptom data lives here")
- Very strong "Pro" monetization (free: track 3 symptoms; paid: correlations, export, experiments)

**Pros**:
- Extremely high fit with existing data model (meal context + sleep + stress = symptom substrate)
- Creates lock-in through accumulated personal health data
- Pairs perfectly with Stress Lab (experiment: "Does eliminating dairy reduce bloating?")
- Clinician export makes this a medical-adjacent tool (without being medical)

**Cons**:
- Must be extremely careful about medical framing (informational, not diagnostic)
- Correlation engine needs statistical rigor (can't repeat Bearable's mistakes)
- UI for symptom entry + correlation review is non-trivial

**Complexity**: Medium | **Risk**: Medium (statistical/medical framing)
**Solo-dev effort**: ~3-4 weeks

---

### Feature 2B: Circadian Health Module (Daylight + Sleep Regularity + Screen Timing)

**Summary**: A new "circadian health" axis blending: daylight exposure (HealthKit `timeInDaylight`), sleep timing regularity (bed/wake consistency), and screen time timing (night use patterns).

**Why it matters**:
- Genuinely differentiated — nutrition apps ignore circadian rhythm, screen time apps don't tie it to recovery
- Yields extremely actionable advice ("10 minutes outside before noon" beats "sleep better")
- HealthKit `timeInDaylight` is a newer metric that few apps leverage
- Low modeling complexity — the challenge is UX, not math

**Pros**:
- New, credible lever that competitors don't have
- On-device, explainable, privacy-first
- Pairs naturally with existing sleep + screen time data
- Actionable advice (not just scores)

**Cons**:
- `timeInDaylight` requires Apple Watch (limits audience)
- Sleep regularity scoring needs careful definition
- Risk of "shame-based" UX if screen time data is presented poorly

**Complexity**: Low–Medium | **Risk**: Low
**Solo-dev effort**: ~2 weeks

---

### Feature 2C: HealthKit Mental Wellbeing Interoperability

**Summary**: Map daily mood check-in to HealthKit State of Mind. Read/write standardized depression/anxiety assessments (PHQ-9 / GAD-7) under HealthKit's documented standards. Frame as reflective and non-diagnostic.

**Why it matters**:
- "System integration" story without any backend
- Reduces duplicate entry for users who also log mood in Apple Health
- Apple is investing heavily in mental health APIs — riding this wave
- Positions WellPlate as a serious health tool, not just a tracker

**Pros**:
- Mood already captured in-app — just needs HealthKit mapping
- Apple blesses this use case with explicit APIs
- Professional credibility (PHQ-9/GAD-7 are clinical standards)
- PDF export of assessments matches Apple's own guidance

**Cons**:
- Sensitive data — authorization UX must be respectful
- Medical framing risks (must use Apple's "informational, not diagnostic" language)
- Assessment questionnaire UI needs careful design

**Complexity**: Medium | **Risk**: Medium (sensitivity)
**Solo-dev effort**: ~2 weeks

---

### Feature 2D: Guided Breathing with Contextual Triggers (JITAI-style)

**Summary**: Short paced-breathing sessions (1–5 min) with haptic guidance and animated visuals. Key differentiator: triggered contextually by high stress score + high screen time, not just user-initiated.

**Why it matters**:
- Closes the stress loop — we measure stress, we should help reduce it
- JITAI (Just-In-Time Adaptive Interventions) is research-backed and no consumer app does it well
- Simple MVP: breathing animation + haptics + optional audio
- Pairs with Stress Lab ("Did breathing exercises reduce my stress?")

**Pros**:
- Low–Medium effort for MVP
- Directly actionable (not just data/insights)
- Contextual triggers are unique and research-backed
- Watch app synergy (breathing from wrist)

**Cons**:
- Content quality matters (bad breathing exercises feel gimmicky)
- Must not spam users with unsolicited interventions
- Meditation/Calm apps are dominant here (but we're integrated, they're standalone)

**Complexity**: Low–Medium | **Risk**: Low
**Solo-dev effort**: ~1-2 weeks

---

## Tier 3: Strategic Investments

Higher effort, but create unique positioning that's very hard to replicate.

### Feature 3A: On-Device "Why Is My Stress High Today?" Explainer

**Summary**: Deterministic attribution layer (delta contributions vs. 7-day baseline per factor, data coverage flags) + Foundation Models narrative generator producing a short explanation with citations to exact signals.

**Why it matters**:
- This is our strongest AI differentiator: "AI summarizes what your own data shows, on-device, with receipts"
- Directly counters the Welltory criticism of "gimmicky/uncalibrated" interpretations
- We already have StressInsightService doing 10-day lookbacks — this is the single-day focused version

**Pros**:
- Builds on existing Foundation Models infra
- Privacy-preserving (all on-device)
- "Receipts" = transparent factor attribution → builds trust
- Natural evolution of existing stress insights

**Cons**:
- Foundation Models only on iOS 26+ (need fallback)
- Risk of over-claiming if attribution model is simplistic
- Personalization (adapting to individual baselines) is a deeper challenge

**Complexity**: Medium | **Risk**: Medium
**Solo-dev effort**: ~2-3 weeks

---

### Feature 3B: Privacy-Preserving Partner Accountability

**Summary**: "Buddy mode" — share weekly stress summary card + one goal commitment + optional check-in messages. No accounts, no backend. Implemented via CloudKit sharing (async) or SharePlay (sync breathing sessions).

**Why it matters**:
- Social features multiply retention, but most small apps either avoid them or require servers
- "Serverless social" via CloudKit/SharePlay is a rare and marketable approach
- Our stress score + factor breakdown compresses perfectly into shareable cards

**Pros**:
- No custom backend needed (CloudKit/SharePlay are Apple-provided)
- "Partner mode" is a premium subscription differentiator
- End-to-end encrypted (SharePlay) reinforces privacy brand
- Small surface area (1-3 partners, not a social network)

**Cons**:
- CloudKit sharing has conflict modeling complexity
- SharePlay requires both users to have the app
- Medium–High effort despite "small" scope

**Complexity**: Medium–High | **Risk**: Medium
**Solo-dev effort**: ~3-4 weeks

---

## Features Evaluated and Deprioritized

### Photo Meal Logging — DEFER (P3)
- **Why deprioritize**: High effort, high risk of undermining trust story if accuracy is poor. Portion estimation is notoriously unreliable without a strong model + dataset pipeline.
- **Indie recommendation from research**: Ship a "photo as context" MVP first — store photo with meal, use it for clarifying questions, but keep macros from text/structured entry.
- **Revisit when**: Foundation Models improve enough for reliable on-device food recognition.

### Conversational AI Chat — DEFER (P2)
- **Why deprioritize**: Impressive demo, but Foundation Models on-device aren't yet powerful enough for open-ended health Q&A with reliable accuracy. Risk of wrong advice.
- **Better approach**: Invest in the structured "Why is my stress high?" explainer (Feature 3A) which is bounded and verifiable.
- **Revisit when**: Foundation Models can handle open-domain health reasoning reliably.

### Meal Planning & Recipes — DEFER (P3)
- **Why deprioritize**: Requires a content moat (recipe database) or unreliable LLM generation. Competitors with dedicated recipe teams still struggle here.
- **Better approach**: Smart meal suggestions based on remaining macro budget (much simpler, no recipe DB needed).

### Leaderboards / Social Feed — REJECT
- **Why reject**: Antithetical to privacy-first brand. Creates comparison anxiety. Requires backend infrastructure.
- **What to do instead**: Partner accountability (Feature 3B) provides social motivation without social pressure.

### Daily Unified WellPlate Score — DEFER (P2)
- **Why deprioritize**: Sounds good conceptually, but risks the exact "gimmicky" perception that Welltory gets criticized for. A composite score that users can't interrogate feels arbitrary.
- **Better approach**: Build the Stress Lab and Explainer first. If users trust the per-factor scoring, a composite score becomes credible later.
- **Revisit when**: Factor attribution is proven and trusted.

---

## Recommended Build Order

### Phase 1: Trust & Transparency (Weeks 1–4)
> Theme: "We show you exactly what we know and how we know it"

| # | Feature | Effort | Impact |
|---|---------|--------|--------|
| 1 | Food Confidence & Provenance UI (1D) | 2-3 days | Immediate trust boost |
| 2 | Wellness Report Export — PDF + CSV (1C) | 1-2 weeks | Pro monetization + clinician story |
| 3 | Stress Lab Experiments MVP (1A) | 2-3 weeks | Category-defining differentiator |

### Phase 2: Daily Loop & Engagement (Weeks 5–8)
> Theme: "The app that's useful in 20 seconds"

| # | Feature | Effort | Impact |
|---|---------|--------|--------|
| 4 | Live Activities — Fasting Timer (1B) | 1-2 weeks | Lock screen presence + fasting demand |
| 5 | Guided Breathing with Smart Triggers (2D) | 1-2 weeks | Closes the stress action loop |
| 6 | Circadian Health Module (2B) | 2 weeks | New differentiated axis |

### Phase 3: Depth & Stickiness (Weeks 9–14)
> Theme: "The more you use it, the more it knows"

| # | Feature | Effort | Impact |
|---|---------|--------|--------|
| 7 | Symptom Journal + Correlations (2A) | 3-4 weeks | Maximum stickiness + Pro value |
| 8 | "Why Is My Stress High?" Explainer (3A) | 2-3 weeks | AI trust differentiator |

### Phase 4: Platform Expansion (Weeks 15+)
> Theme: "Everywhere you need it"

| # | Feature | Effort | Impact |
|---|---------|--------|--------|
| 9 | HealthKit Mental Wellbeing APIs (2C) | 2 weeks | System integration story |
| 10 | Partner Accountability via CloudKit (3B) | 3-4 weeks | Retention multiplier |

---

## Monetization Strategy (Aligned with Features)

Based on the research's clear guidance: **don't paywall foundational logging** (barcode scanning paywall is the classic App Store lightning rod).

### Free Tier (Excellent Tracker)
- All logging (text, voice, barcode, meal context)
- Basic stress score + factor view
- 7-day history
- Basic hydration/caffeine tracking
- Mood check-in
- Food confidence labels

### Pro Tier (Compounding Insight + Convenience)
- Wellness Report Exports (PDF/CSV)
- Stress Lab Experiments (history + advanced analysis)
- Symptom correlations + export
- Circadian health module
- Guided breathing with smart triggers
- Advanced food disambiguation
- 90-day+ history
- Partner accountability
- Live Activities customization

**Pricing signal from research**: Competitors get review-bombed for >$15/month. Position at ~$5-7/month or ~$40-50/year. Offer 7-day trial (App Store natively supports introductory offers, one per subscription group).

---

## Edge Cases to Consider

- [ ] What if a user doesn't have enough data for a Stress Lab experiment? (need minimum data requirements)
- [ ] What if `timeInDaylight` isn't available (no Apple Watch)? Gracefully degrade circadian module
- [ ] What if Foundation Models aren't available (iOS <26)? All AI features need deterministic fallbacks
- [ ] Symptom correlation with <30 data points — show "not enough data" instead of misleading stats
- [ ] Live Activities battery impact — test on older devices
- [ ] PDF export accessibility — ensure VoiceOver compatibility
- [ ] Partner accountability: what happens when one partner uninstalls? Clean disconnect flow

## Open Questions

- [ ] Should Stress Lab suggest experiments based on data patterns, or only let users choose?
- [ ] What's the minimum data points for a credible correlation in Symptom Journal?
- [ ] Should breathing exercises play audio or just use haptics? (Audio needs licensing/creation)
- [ ] CloudKit vs. SharePlay for partner features — which first? (CloudKit is async and lower friction)
- [ ] How to handle fasting timer for users who eat irregularly? (manual vs. auto-detect from meal gaps)

## Research References

- `Docs/06_Miscellaneous/deep-research-report-2.md` — Primary source (competitor analysis, API research, feature evaluations)
- Competitor pain points: MyFitnessPal (paywall anger), Lose It! (data accuracy), Bearable (misleading correlations), Welltory (gimmicky perception), Gentler Streak (GPS failures)
- Apple APIs: Foundation Models, ActivityKit Live Activities, HealthKit `timeInDaylight`, State of Mind, Medications API, CloudKit sharing, SharePlay
- Research: JITAI (Just-In-Time Adaptive Interventions), n-of-1 experiment design, self-monitoring retention studies
