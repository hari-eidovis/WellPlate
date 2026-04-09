# Brainstorm: Home Screen UX Update

**Date**: 2026-04-09
**Status**: Brainstorming
**Prior Art**: `HomeScreen-UI-Differentiation.md` (2026-02-18) — focused on food logging differentiation. This brainstorm focuses on the **overall Home Screen layout, information architecture, and daily wellness UX** as the app has evolved well beyond a calorie tracker.

---

## Current State Assessment

The Home Screen has grown organically into a **vertically stacked card list**:

```
┌─────────────────────────┐
│  HomeHeaderView         │  Greeting + action buttons
├─────────────────────────┤
│  WellnessRingsCard      │  4 rings: Calories, Water, Exercise, Stress
├─────────────────────────┤
│  MoodCheckInCard        │  5 emoji mood selector (or JournalReflectionCard)
├─────────────────────────┤
│  HydrationCard          │  8 water glass icons + wave animation
├─────────────────────────┤
│  CoffeeCard             │  Cup icons + caffeine counter
├─────────────────────────┤
│  (ActivityCard)         │  COMMENTED OUT
├─────────────────────────┤
│  (StressInsightCard)    │  COMMENTED OUT
├─────────────────────────┤
│  DragToLogOverlay       │  Bottom meal-log trigger
└─────────────────────────┘
```

### What's Working
- Wellness rings give a strong at-a-glance daily summary
- Mood check-in is a unique differentiator
- Water/coffee tracking is quick and satisfying (haptics + animation)
- DragToLog + swipe-right gesture for meal logging is clever
- Journal reflection card post-mood is contextual and non-intrusive

### What's Not Working
1. **Linear scroll fatigue** — everything is the same visual weight; nothing is prioritized
2. **Below the fold problem** — hydration/coffee cards require scrolling; users may miss them
3. **Missing food context** — today's meals aren't visible on the home screen (only via MealLogCard, which isn't in the current layout)
4. **Commented-out cards** — ActivityCard and StressInsightCard were disabled, leaving gaps in the wellness story
5. **Header is overloaded** — 4 action buttons (AI insights, calendar, symptom log, journal history) compete for attention
6. **No time-of-day awareness** — the screen looks identical at 7 AM and 9 PM
7. **No progress narrative** — rings show numbers but don't tell a story ("You're 80% there today!")
8. **3-tab structure** — only Home, Stress, Profile. No dedicated Burn/Sleep tab despite features existing

---

## Approach 1: Time-Aware Adaptive Home

**Summary**: The home screen morphs throughout the day, surfacing what matters *right now* instead of showing everything at once.

### How It Works

**Morning (5 AM – 11 AM)**
- Hero: Sleep summary card (last night's sleep quality + duration)
- Prominent: "Log Breakfast" CTA with recent breakfast foods
- Compact: Wellness rings (small, top bar)
- Hidden: Coffee card appears only after first log

**Midday (11 AM – 2 PM)**
- Hero: Calorie progress so far + meal log CTA
- Prominent: Hydration reminder if below pace
- Compact: Morning summary (meals logged, mood)

**Afternoon (2 PM – 6 PM)**
- Hero: Activity/exercise card (steps, active calories)
- Prominent: Stress check-in if not done today
- Compact: Hydration + caffeine status

**Evening (6 PM – 10 PM)**
- Hero: Daily summary with all-ring progress
- Prominent: "How was your day?" reflection prompt
- Compact: Remaining goals nudge

**Night (10 PM – 5 AM)**
- Hero: Wind-down card (screen time, caffeine intake warnings)
- Prominent: Tomorrow's plan/goals preview
- Minimal: Just the essentials

### UI Pattern
```
┌─────────────────────────┐
│  Compact Status Bar     │  Rings as dots/pills, date, streak
├─────────────────────────┤
│  ┌─────────────────┐    │
│  │   HERO CARD     │    │  Time-contextual primary card
│  │   (large)       │    │  ~40% of viewport
│  └─────────────────┘    │
├─────────────────────────┤
│  Quick Actions Row      │  2-3 contextual action pills
├─────────────────────────┤
│  Secondary Cards        │  Smaller, relevant-now cards
├─────────────────────────┤
│  "More" section         │  Collapsed remaining cards
└─────────────────────────┘
```

### Pros
- Reduces cognitive load — users see only what's relevant
- Creates a "living" feel — the app feels aware and personal
- Solves the "everything looks the same" problem
- Natural nudges without notifications
- Morning sleep summary ties Sleep feature into Home tab

### Cons
- Complex state management (time zones, irregular schedules)
- Users who want full dashboard can't see everything at once
- Harder to test — different states at different times
- Shift workers or irregular schedule users may get wrong context

### Mitigation
- "Show All" toggle to expand full dashboard anytime
- User-configurable schedule (wake time, meal times)
- Learn from actual logging patterns to adapt time windows

---

## Approach 2: Modular Widget Grid (Apple-Inspired)

**Summary**: Replace the linear card stack with a configurable widget grid where users arrange their own home screen, similar to iOS home screen widgets.

### How It Works
- Home screen is a **2-column grid** of widgets in 3 sizes: small (1x1), medium (2x1), large (2x2)
- Users long-press to enter "jiggle mode" and rearrange/resize widgets
- Default layout is curated, but fully customizable
- Available widgets: Rings, Hydration, Coffee, Meals Today, Mood, Activity, Stress, Sleep Summary, Streak, Journal, Quick Log

### Default Layout
```
┌───────────┬───────────┐
│  Wellness Rings (2x2) │
│                       │
├───────────┬───────────┤
│ Hydration │  Coffee   │
│   (1x1)   │   (1x1)  │
├───────────┴───────────┤
│  Today's Meals (2x1)  │
├───────────┬───────────┤
│   Mood    │ Activity  │
│   (1x1)   │   (1x1)  │
└───────────┴───────────┘
```

### Pros
- Maximum user control — power users love customization
- Density — more info above the fold in a grid vs. stacked cards
- Familiar pattern — iOS users already understand widget grids
- Each widget is a self-contained SwiftUI view — easy to add new ones
- Users who don't care about coffee can remove it; runners can add Activity

### Cons
- Complex layout engine (adaptive grid with multiple sizes)
- Onboarding burden — new users may not know what to configure
- Visual consistency harder to maintain with user-arranged layouts
- Accessibility: grid navigation is harder than linear scroll

### Mitigation
- Ship with 3 pre-built layouts: "Wellness Focus", "Fitness Focus", "Minimal"
- Smart defaults based on onboarding answers
- "Reset to Default" option always available

---

## Approach 3: Today's Story — Narrative Dashboard

**Summary**: Transform the home screen from a data dashboard into a **narrative summary** that tells the user the story of their day in plain language, backed by data cards.

### How It Works
- Top of screen: AI-generated daily narrative in a speech-bubble or card
- Below: Supporting data cards that the narrative references
- Narrative updates throughout the day as new data comes in

### Example Narratives
- **Morning**: "Good morning! You slept 7h 12m last night — better than your weekly average. Your stress was low yesterday. Ready to keep the momentum?"
- **Midday**: "You've logged 1,240 cal so far with solid protein (82g). You're a bit behind on water — 3 glasses to go. Your afternoon coffee was your second today."
- **Evening**: "Great day! You hit 3 of 4 wellness goals. Your mood was 😊 and you walked 8,200 steps. Only water is a bit low — try a glass before bed?"

### UI Pattern
```
┌─────────────────────────┐
│  "Good afternoon, Alex" │
│                         │
│  "You've logged 1,240   │
│  cal with strong protein │
│  (82g). 3 glasses of    │
│  water to go — you've   │
│  got this!"             │
│                         │
│  [See Details ↓]        │
├─────────────────────────┤
│  ┌──────┐ ┌──────┐     │
│  │Meals │ │Water │     │  Compact data cards
│  └──────┘ └──────┘     │
│  ┌──────┐ ┌──────┐     │
│  │Mood  │ │Steps │     │
│  └──────┘ └──────┘     │
└─────────────────────────┘
```

### Pros
- Unique in the market — no wellness app does narrative dashboards
- Emotionally engaging — feels like a coach, not a spreadsheet
- Leverages existing Groq LLM integration for narrative generation
- Naturally incorporates encouragement and positive framing
- Solves "information overload" — narrative highlights what matters

### Cons
- AI latency — narrative generation takes time on app open
- Generic/repetitive narratives would feel hollow fast
- Depends heavily on data availability (empty narrative if nothing logged)
- Users who want raw numbers first may find narrative distracting

### Mitigation
- Cache narrative and update incrementally (not full regen each time)
- "Numbers view" toggle for data-first users
- Fallback to template-based narrative when AI is unavailable
- Rich narrative only when enough data exists; simple greeting otherwise

---

## Approach 4: Hub & Spoke — Collapsed Summary + Expandable Sections

**Summary**: Compress the home screen into a tight summary view with expandable sections, so users see everything at a glance but can drill into any area.

### How It Works
- **Top**: A single "Daily Pulse" card showing all key metrics as compact pills/badges
- **Below**: Accordion-style sections that expand on tap
- Each section shows a 1-line summary when collapsed, full card when expanded
- Last-expanded section is remembered between sessions

### Layout
```
┌─────────────────────────────────┐
│  Daily Pulse                    │
│  🔥 1,240 cal  💧 5/8  ☕ 2    │
│  😊 Good mood  🏃 6,200 steps  │
│  ⚡ Stress: Low                 │
└─────────────────────────────────┘

▸ Meals Today (3 logged)          ← tap to expand
▸ Hydration (5 of 8 glasses)      ← tap to expand
▾ Activity                        ← expanded
  ┌─────────────────────────┐
  │  ActivityCard (full)    │
  │  Exercise: 32 min       │
  │  Burned: 420 cal        │
  │  Steps: 6,200           │
  └─────────────────────────┘
▸ Mood & Journal
▸ Stress Overview
▸ Sleep (last night)
```

### Pros
- **Everything above the fold** — Daily Pulse shows all metrics instantly
- Zero scrolling needed for quick check-ins
- Users control their own information depth
- Clean and organized — no visual overwhelm
- Naturally scales as features are added (just add a new section)

### Cons
- Collapsed state can feel "dry" — less visually engaging
- Lots of tapping to see details (higher interaction cost)
- Accordion UX can feel old-fashioned if not styled well
- Harder to discover features hidden behind collapsed headers

### Mitigation
- Auto-expand sections that need attention (e.g., low hydration)
- Rich animations on expand/collapse (spring + content transition)
- Daily Pulse pills are tappable → jump to that section
- Sections with actionable items show a subtle badge/indicator

---

## Approach 5: Dual-Mode Home — Dashboard vs. Journal

**Summary**: Offer two distinct home screen modes that users can swipe between: a **Dashboard** (data-focused) and a **Journal** (action-focused).

### How It Works

**Dashboard Mode** (swipe left or default)
- Optimized for checking status at a glance
- Wellness rings, metrics, progress bars
- Read-only — no input fields
- "How am I doing today?"

**Journal Mode** (swipe right)
- Optimized for logging and input
- Meal log with text field at top
- Water/coffee quick-add buttons
- Mood selector
- "Let me log something"

### UI Pattern
```
         ← swipe →
┌──────────────┐  ┌──────────────┐
│  DASHBOARD   │  │   JOURNAL    │
│              │  │              │
│  Rings       │  │  Log Meal    │
│  Metrics     │  │  [text field]│
│  Charts      │  │              │
│  Insights    │  │  + Water     │
│              │  │  + Coffee    │
│              │  │  + Mood      │
│              │  │              │
│  ● ○         │  │  ○ ●        │
└──────────────┘  └──────────────┘
```

### Pros
- Clear separation of concerns — viewing vs. doing
- Dashboard stays clean (no input elements cluttering it)
- Journal mode is focused and efficient for logging
- Familiar swipe-between-pages pattern (like Weather app)
- Each mode can be optimized independently

### Cons
- Users need to learn two modes exist (discoverability)
- Which mode should be default? (Opinion-based)
- Some actions span both modes (e.g., tap ring to see detail AND log)
- Page dots take up space and add visual noise

### Mitigation
- Default to Journal mode in morning, Dashboard in evening (or user preference)
- Onboarding tip showing the swipe gesture
- Cross-mode shortcuts (ring tap on Dashboard opens Journal for that category)

---

## Approach 6: Contextual Action Bar + Streamlined Stack

**Summary**: Keep the current card stack but add a persistent **contextual action bar** that floats above the tab bar, replacing DragToLogOverlay with something smarter.

### How It Works
- **Action Bar**: A floating pill/bar above the tab bar that changes based on context
- The card stack is streamlined — MealLogCard is re-enabled, ActivityCard is brought back, content is prioritized

### Action Bar States
```
Morning, no breakfast:    [ 🍳 Log Breakfast ]
After meal logged:        [ ✅ Logged! — Undo ]
Low on water at 2 PM:     [ 💧 You're behind — Add Water ]
Stress high:              [ 🧘 Try breathing — 2 min ]
Evening, all goals met:   [ 🎉 Great day! — See Summary ]
Default:                  [ + Log Meal  |  💧  |  ☕ ]
```

### Streamlined Card Stack
```
┌─────────────────────────┐
│  Header (simplified)    │  Just greeting + date + streak
├─────────────────────────┤
│  WellnessRingsCard      │  Keep as-is (proven effective)
├─────────────────────────┤
│  MoodCheckInCard        │  Keep (or JournalReflection)
├─────────────────────────┤
│  Today's Meals          │  RE-ENABLE MealLogCard
│  (scrollable row)       │  Horizontal scroll, not vertical
├─────────────────────────┤
│  Quick Stats Row        │  💧 5/8  ☕ 2/3  🏃 6.2k steps
│  (compact, tappable)    │  Tap any → detail view
├─────────────────────────┤
│                         │
│  ┌─────────────────┐    │
│  │ Contextual Bar  │    │  Floating above tab bar
│  └─────────────────┘    │
│  [Home] [Stress] [Prof] │
└─────────────────────────┘
```

### Pros
- **Minimal disruption** — evolution, not revolution
- Contextual bar is a natural upgrade from DragToLogOverlay
- Horizontal meal scroll keeps food visible without taking vertical space
- Quick Stats Row compresses 2 cards (hydration + coffee) into 1 line
- Re-enables commented-out functionality organically

### Cons
- Action bar logic needs careful state management
- Floating elements can interfere with scrolling
- Horizontal scroll for meals is less accessible than vertical
- "Quick Stats Row" loses the satisfying water glass interaction

### Mitigation
- Action bar is a Capsule with shadow, positioned with `.safeAreaInset(edge: .bottom)`
- Preserve water glass interaction in WaterDetailView (tap row → full card)
- Test floating bar with VoiceOver for accessibility
- If contextual logic is too complex, fall back to static quick-action bar

---

## Quick Wins (Independent of Approach)

These improvements work with any of the above approaches:

### 1. Animated "Daily Score" in Header
- Single number (0-100) that represents overall wellness today
- Animated ring or gauge next to greeting
- Tap → breakdown of how score is calculated
- **Why**: Gives users ONE number to optimize, reducing cognitive load

### 2. "You're on Track" / "Needs Attention" Badges
- Small pill badges on cards: green "On Track" or amber "Behind"
- Based on time-of-day pace (e.g., 50% of water by noon = on track)
- **Why**: Proactive guidance without nagging notifications

### 3. Smooth Skeleton Loading States
- Show animated skeleton placeholders while HealthKit data loads
- Rings animate from 0 → actual value on load
- **Why**: Perceived performance; feels polished and premium

### 4. Pull-to-Refresh with Delight
- Custom pull-to-refresh animation (rings spin, water waves)
- Refreshes HealthKit data + recalculates stress
- **Why**: Users expect pull-to-refresh; custom animation = delight

### 5. "Yesterday vs Today" Quick Compare
- Subtle comparison badges: "↑ 200 cal vs yesterday" on calorie ring
- Arrows + delta values on key metrics
- **Why**: Context makes numbers meaningful

### 6. Greeting Personality
- Vary greetings beyond time-of-day: reference weather, day of week, streaks
- "Happy Friday, Alex! One more day of your 12-day streak."
- "Rainy Wednesday — perfect soup weather 🍜"
- **Why**: Makes the app feel alive and personal

### 7. Quick-Log Gesture Improvements
- Double-tap anywhere on home → open meal log
- 3D Touch / long-press on tab bar icon → quick-add menu
- Shake to undo last log
- **Why**: Reduce friction for the most common action

### 8. Horizontal Scroll "Today's Timeline"
- Thin horizontal strip showing logged events on a timeline
- Meals, water, coffee, mood — all as dots on a 24h line
- **Why**: At-a-glance view of daily activity pattern

---

## Edge Cases & Considerations

### Onboarding & First-Day Experience
- New users have no data → home screen must not feel empty
- Show sample data with "Log your first meal to see your dashboard come alive"
- Progressive disclosure: start with 2-3 cards, unlock more as user logs

### Power Users vs. Casual Users
- Power users want density and data
- Casual users want simplicity and encouragement
- Consider onboarding question: "How detailed do you want your dashboard?"

### Accessibility
- All approaches must work with Dynamic Type (up to AX5)
- VoiceOver reading order must make semantic sense
- Reduce Motion: disable wave animations, spring bounces
- Minimum touch targets: 44x44pt for all interactive elements

### Performance
- Home screen loads on every app open — must be <200ms to first paint
- Lazy-load HealthKit data; show cached values first
- Avoid re-rendering entire screen when one metric updates

### Data Sparsity
- Users who only track meals shouldn't see empty water/coffee/activity cards
- Hide or minimize cards with no data; show "Set up" CTA instead
- Don't show stress ring if user hasn't granted HealthKit permissions

---

## Recommendation

**Primary**: Start with **Approach 6 (Contextual Action Bar + Streamlined Stack)** — it's the lowest-risk, highest-impact evolution of the current design. It fixes the main problems (below-the-fold content, missing meals, DragToLog limitations) without requiring a full redesign.

**Secondary**: Layer in elements from **Approach 1 (Time-Aware)** — specifically the time-contextual hero card and smart action bar states. This adds the "living app" feel without rebuilding the layout engine.

**Future**: If user research validates demand, explore **Approach 2 (Widget Grid)** as a v2 redesign or **Approach 3 (Narrative)** as an optional "AI Summary" card at the top.

**Quick Wins**: Implement 3-4 quick wins immediately regardless of approach chosen:
1. Skeleton loading states (polish)
2. "Yesterday vs Today" delta badges (context)
3. Greeting personality (delight)
4. Horizontal timeline strip (information density)

---

## Next Step

→ Run `/develop strategize home-screen-ux-update` to select and refine one approach into a concrete strategy.
