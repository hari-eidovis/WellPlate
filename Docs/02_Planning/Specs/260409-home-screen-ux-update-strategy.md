# Strategy: Home Screen UX Update

**Date**: 2026-04-09
**Source**: `Docs/01_Brainstorming/260409-home-screen-ux-update-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**Approach 6 (Contextual Action Bar + Streamlined Stack) with selective Approach 1 (Time-Aware) grafted at the contextual bar layer only.** The current vertically-stacked card layout is retained as the core structure. Three targeted surgeries fix the biggest pain points: (1) `DragToLogOverlay` is replaced by a persistent `ContextualActionBar` positioned via `.safeAreaInset(edge: .bottom)`; (2) `HydrationCard` and `CoffeeCard` are compressed into a single `QuickStatsRow` with full-card detail on tap; (3) `MealLogCard` is re-enabled inline; and (4) the header is slimmed to two icon buttons plus the mood badge. Time-awareness is scoped exclusively to what the contextual bar says and which text-message the header greeting emits — no structural re-arrangement of cards occurs based on time.

---

## Rationale

### Why Approach 6 wins

- **Zero layout regression risk**: every existing `@Binding` (`hydrationGlasses`, `coffeeCups`), `@State` flag, sheet, and navigation destination in `HomeView.swift` is preserved. The diff is additive rather than a rewrite.
- **DragToLogOverlay is the weakest element**: it requires the user to discover an invisible drag gesture, obscures scroll content via the blur-overlay effect, and competes with the system home indicator. A visible pill bar above the tab bar is a standard iOS pattern that addresses all three issues.
- **Two cards → one row is the highest-density win available**: `HydrationCard` and `CoffeeCard` each occupy ~120 pt of vertical height but show a single scalar each. Compressing them to a `QuickStatsRow` puts ~200 pt of space back into view — enough to surface `MealLogCard` without the user ever scrolling.
- **MealLogCard already exists and is functional**: it has swipe-to-delete, context menu, macro chips, provenance badges, and an empty state. Re-enabling it is a matter of passing `todayFoodLogs` and wiring `onDelete` / `onAddAgain` — two method bodies.

### Why the other approaches were rejected

- **Approach 1 (Full Time-Aware)**: restructuring card order based on time of day creates a combinatorial test matrix (5 time windows × 4 data-availability states = 20 layout permutations) with no existing infrastructure for time-windowed layout management. The benefit — users see "what matters now" — is largely captured by the contextual bar message, which is far cheaper.
- **Approach 2 (Widget Grid)**: requires a custom flexible grid layout engine, drag-to-rearrange state persistence in SwiftData or UserDefaults, an onboarding to explain jiggle mode, and a complete UI design overhaul. Estimated scope is 3× larger than Approach 6 for unclear user benefit given the app's current stage.
- **Approach 3 (Narrative Dashboard)**: AI latency on app open is a critical UX problem — the `StressInsightService` pattern shows that Groq calls are 1–3 seconds even on good connections. A narrative that arrives late is worse than no narrative. Deferred to a future "AI Summary Card" opt-in.
- **Approach 4 (Hub & Spoke)**: accordion UX adds a tap to see any content. Today's rings → expand, today's meals → expand, hydration → expand. This increases interaction cost for the most frequent actions. The home screen is already a "scan at a glance" surface; collapsing it contradicts that intent.
- **Approach 5 (Dual-Mode)**: introduces a discoverability cliff (users don't know two modes exist), adds page indicators that consume vertical space, and splits the mental model of what "home" means. Logging and reviewing wellness data are not cleanly separable — tapping a ring to log is both actions simultaneously.

### Quick wins selected for this update

From the brainstorm quick-wins list, three are in scope because they fit the evolutionary constraint:

1. **Skeleton loading states** — `WellnessRingsCard` shows shimmer placeholders while `wellnessRings` data settles from HealthKit.
2. **Yesterday vs Today delta badges** — a `Δ +200 cal` tag on the calories ring and `Δ +1,200 steps` on the activity row, sourced from the existing 30-day history already loaded by `HomeViewModel`.
3. **Greeting personality** — extend the `greeting` computed property in `HomeView` with weekday references and streak acknowledgments.

Horizontal timeline strip and pull-to-refresh with custom animation are explicitly deferred (non-goals).

---

## New Layout — What the User Sees Top to Bottom

```
┌──────────────────────────────────────────┐
│  HomeHeaderView (slimmed)                │  Greeting + date + streak flame
│  [ sparkles ]  [ book.fill ]  [ 😌 ]    │  2 icon buttons + mood badge
├──────────────────────────────────────────┤
│  WellnessRingsCard                       │  Unchanged. Delta badges added.
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐            │
│  │Cal │ │H2O │ │Exc │ │Str │            │
│  └────┘ └────┘ └────┘ └────┘            │
│  Δ +200  Δ+1  —      —                  │
├──────────────────────────────────────────┤
│  MoodCheckInCard  OR  JournalReflection  │  Unchanged logic
├──────────────────────────────────────────┤
│  Today's Meals (MealLogCard)             │  RE-ENABLED. Inline swipe-delete.
│  ┌─────────────────────────────────────┐ │
│  │ 08:14  Oat porridge     380 kcal   │ │
│  │ 12:40  Chicken wrap     520 kcal   │ │
│  │  [ + Log Meal ] button (empty)     │ │
│  └─────────────────────────────────────┘ │
├──────────────────────────────────────────┤
│  QuickStatsRow                           │  NEW — replaces HydrationCard +
│  ┌─────────────┐ ┌──────────┐ ┌───────┐ │  CoffeeCard + ActivityCard (stub)
│  │ 💧 5 / 8   │ │ ☕ 2 / 4 │ │🏃6.2k│ │
│  └─────────────┘ └──────────┘ └───────┘ │
│  tap → WaterDetailView / CoffeeDetailView│
│  tap → BurnView                          │
├──────────────────────────────────────────┤  (no more content; short scroll)
│  ContextualActionBar                     │  NEW — .safeAreaInset bottom
│  ┌──────────────────────────────────┐    │
│  │  🍳 Log Breakfast  •  💧  •  ☕ │    │
│  └──────────────────────────────────┘    │
├──────────────────────────────────────────┤
│  Tab Bar: Home  Stress  Profile          │
└──────────────────────────────────────────┘
```

---

## Header Changes

**Remove**: the `heart.text.square.fill` (symptom log) button and the `calendar` button from the header icon row.

**Rationale**: the header currently has 4 icon buttons at 38 pt each — this is visually cluttered and pushes the mood badge off-screen on small devices. Symptom logging is accessed from the `HomeSheet.symptomLog` path; relocate the trigger to the `ContextualActionBar` or to a Profile tab shortcut. The calendar (`WellnessCalendarView`) moves to the Profile tab.

**Keep**: `sparkles` (AI Insight) and `book.fill` (Journal History) — these are the two most discovery-sensitive navigations that don't fit elsewhere.

**Result**: header has 2 icon buttons + optional mood badge. `HomeHeaderView.swift` component is unused by `HomeView` (it exists as a separate component file but `HomeView` renders its own `homeHeader` computed property inline — the inline version is what gets updated).

---

## Contextual Action Bar — Specification

### Component: `ContextualActionBar`

New file: `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift`

**Position**: `.safeAreaInset(edge: .bottom)` in `HomeView`, replacing the current `.safeAreaInset` that holds `DragToLogOverlay`. The bar sits above the tab bar safe area, not overlapping it.

**Visual design**: a `Capsule` (height 52 pt) with `Color(.secondarySystemBackground)` fill, `.appShadow(radius: 16, y: -4)` (shadow upward), centered horizontally with 32 pt horizontal margin. Blurs content beneath it? No — the current blur-on-drag effect from `DragToLogOverlay` is removed entirely.

### Bar States

The bar is driven by a `ContextualBarState` enum computed in `HomeView` as a derived property from existing state (no new async work):

```swift
enum ContextualBarState {
    case defaultActions                      // always available fallback
    case logNextMeal(mealLabel: String)      // time-of-day: no meal logged in window
    case waterBehindPace(glassesNeeded: Int) // below expected pace for time of day
    case goalsCelebration                    // all 4 rings ≥ 100 %
    case stressActionable(level: String)     // stress ring shows High / Very High
}
```

State priority (highest wins):
1. `goalsCelebration` — if `wellnessCompletionPercent == 100`
2. `stressActionable` — if stress level is High or Very High
3. `waterBehindPace` — if `hydrationGlasses < expectedCupsByNow()`
4. `logNextMeal` — if current time is within a meal window and no meal logged in that window
5. `defaultActions` — always

### Bar content per state

| State | Leading area | Trailing row |
|---|---|---|
| `defaultActions` | "Log Meal" pill (primary, `AppColors.brand`) | `💧` + button, `☕` + button |
| `logNextMeal(.breakfast)` | "Log Breakfast" pill with `fork.knife` icon | `💧` + button |
| `logNextMeal(.lunch)` | "Log Lunch" pill | `💧` + button |
| `logNextMeal(.dinner)` | "Log Dinner" pill | `💧` + button |
| `waterBehindPace(n)` | `💧 \(n) more to stay on track` in blue | "Add" (+) button |
| `goalsCelebration` | `🎉 All goals met today!` label (green) | "See Summary" → AI Insight |
| `stressActionable(level)` | `🧘 Stress is \(level) — try breathing` | "Start" → Stress tab |

### Time-window logic for meal labels

`logNextMeal` uses the current hour and today's food logs to decide which meal label to show. This is a pure computed property — no stored state, no clock observer:

```
05:00–10:59 and no breakfast (no log with createdAt in this window) → .breakfast
11:00–13:59 and no lunch logged → .lunch
17:00–20:59 and no dinner logged → .dinner
otherwise → nil (fall through to next priority)
```

A "meal in window" is defined as any `FoodLogEntry` whose `createdAt` hour falls in the window. This uses the existing `allFoodLogs` `@Query` — no new query.

### `expectedCupsByNow()` for water pace

```
target = currentGoals.waterDailyCups
wake = 07:00 (hardcoded for now; user-configurable in future)
sleep = 22:00
fraction = (now - wake) / (sleep - wake), clamped 0–1
expected = Int(ceil(fraction * Double(target)))
behind = expected > hydrationGlasses ? expected - hydrationGlasses : 0
```

If `behind > 1`, show `waterBehindPace` state.

### Interactions

- Tapping the primary pill in `logNextMeal` / `defaultActions` → `showLogMeal = true` (same `NavigationStack` destination as before)
- `💧` button → `hydrationGlasses += 1` (same binding mutation as `HydrationCard`); triggers `HapticService.impact(.light)` and `SoundService.play("water_log_sound", ext: "mp3")`
- `☕` button → same logic as `CoffeeCard` add button; if first cup and no type set, sets `activeSheet = .coffeeTypePicker`
- "Start" in `stressActionable` → `selectedTab = 1` (Stress tab)
- "See Summary" in `goalsCelebration` → `showAIInsight = true`

### Accessibility

- The bar is a single `HStack` wrapped in an `.accessibilityElement(children: .contain)` container with label "Quick Actions".
- Each pill/button has `.accessibilityLabel` explicitly set.
- Minimum tap target: 44×44 pt enforced via `.frame(minWidth: 44, minHeight: 44)`.
- Reduce Motion: no transition animation on state change, just an instant content swap.

---

## QuickStatsRow — Specification

New file: `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift`

Replaces `HydrationCard` and `CoffeeCard` in the card stack. Both full-card views (`WaterDetailView`, `CoffeeDetailView`) remain as navigation destinations — they are not removed.

### Layout

A single `HStack` of three `QuickStatTile` views inside the standard card container:

```
┌─────────────────────────────────────────────┐
│  💧 Water        ☕ Coffee       🏃 Activity │
│  5 / 8 cups      2 / 4 cups     6,200 steps │
│  +1 tap          +1 tap         → BurnView  │
└─────────────────────────────────────────────┘
```

Each tile is 1/3 of available width. Tapping the water or coffee tile increments the counter in-place (same haptic + sound) AND shows the detail navigation when the tile label area (not the +1 area) is long-pressed or when a separate "See all" chevron is tapped.

**Decision: split the tile into two touch zones**:
- The `+` button area (44×44 pt, right-aligned) → increment
- The rest of the tile body → `showWaterDetail = true` / `showCoffeeDetail = true` / `showBurnView = true`

This preserves the "quick tap to add" interaction that users already know from the full cards, without requiring a navigation push for every increment.

### Activity tile

The activity tile shows `steps` from `WellnessDayLog.steps` (already stored in the model). If no data (`steps == nil`), show `—` with a faint `figure.walk` icon. Tap → `showBurnView = true`. No `+` button (you don't log steps here).

### Delta badges (Quick Win #2)

Each tile can optionally show a `Δ` comparison vs. yesterday. Shown as a small capsule below the value:

```
Δ +800 steps  (green)
Δ -1 cup      (amber)
```

These are computed from `HomeViewModel`'s existing 7-day history fetch. The `HomeViewModel` already has access to this data — a new computed property `yesterdayStats: (water: Int, coffee: Int, steps: Int)` is added.

### What happens to `HydrationCard.swift` and `CoffeeCard.swift`

Both files are **kept but unused in HomeView**. They continue to be used in `WaterDetailView` and `CoffeeDetailView` respectively — those detail views remain full-card experiences. No file is deleted.

---

## Today's Meals Section

`MealLogCard` is re-enabled in `HomeView` at position 3 (after mood, before `QuickStatsRow`).

**Wiring required** (both currently missing):

```swift
MealLogCard(
    foodLogs: todayFoodLogs,       // new computed var: allFoodLogs filtered to today
    isToday: true,
    onDelete: { entry in
        modelContext.delete(entry)
        try? modelContext.save()
    },
    onAddAgain: { entry in
        showLogMeal = true
        foodJournalViewModel.prefillFromEntry(entry)   // new method on HomeViewModel
    }
)
.padding(.horizontal, 16)
```

`todayFoodLogs` is a new private computed property on `HomeView`:

```swift
private var todayFoodLogs: [FoodLogEntry] {
    allFoodLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
}
```

Note: `allFoodLogs` is already `@Query(sort: \FoodLogEntry.createdAt, order: .forward)` — the filter is O(n) but n is small (typically < 20 entries per day).

**Empty state behavior**: `MealLogCard` already has an empty state view ("No meals logged yet"). When empty, the card shows the empty state at reduced height (~96 pt). This is acceptable — the card is always present, and the `ContextualActionBar` will be showing `logNextMeal` or `defaultActions` which surfaces the meal log CTA prominently.

**MealLogCard height cap**: The card has no max-height limit today, meaning 10+ meal entries would push everything below it off-screen. Add a `ScrollView` wrapper with `.frame(maxHeight: 360)` around `mealList` inside `MealLogCard` to cap the visible height and keep the overall home screen compact.

---

## Architectural Decisions

### State Management

No new `@StateObject` ViewModel is needed. All new state derives from:
- Existing `@Query` results (`allFoodLogs`, `allWellnessDayLogs`)
- Existing `@State` values (`hydrationGlasses`, `coffeeCups`)
- The current hour (evaluated inline, no timer subscription)

`ContextualBarState` is a `private var` computed property on `HomeView` — it recomputes on every body evaluation, which is already triggered whenever the above state changes. No performance concern at this scale.

### `HomeViewModel` additions

`HomeViewModel` (`ViewModels/HomeViewModel.swift`) needs two additions:
1. `func prefillFromEntry(_ entry: FoodLogEntry)` — pre-populates the food name field in `FoodJournalView` so "Add Again" works.
2. `var yesterdayStats: (water: Int, coffee: Int, steps: Int)` — computed from `WellnessDayLog` records fetched via the model context already available to the VM.

### Delta badge data path

`HomeViewModel` currently orchestrates food journal logic. It holds `modelContext` via `bindContext(_:)`. `yesterdayStats` is a simple SwiftData fetch for yesterday's `WellnessDayLog`:

```swift
var yesterdayStats: (water: Int, coffee: Int, steps: Int) {
    guard let ctx = modelContext else { return (0, 0, 0) }
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
    let descriptor = FetchDescriptor<WellnessDayLog>(predicate: #Predicate { $0.day == yesterday })
    let log = try? ctx.fetch(descriptor).first
    return (log?.waterGlasses ?? 0, log?.coffeeCups ?? 0, log?.steps ?? 0)
}
```

This is called once during `HomeView.onAppear` and stored in a `@Published` property. Not live-updated.

### Removing DragToLogOverlay

`DragToLogOverlay.swift` is kept (not deleted) but its usage is removed from `HomeView`. The `dragLogProgress` `@State` variable and the `.blur` + `.overlay` modifiers that depend on it are also removed from `HomeView.body`. The right-swipe `DragGesture` remains — it is a useful shortcut and has no UX cost.

### Tab structure: unchanged

`MainTabView.swift` is not modified. The 3-tab structure (Home, Stress, Profile) stays. Adding a fourth tab was flagged in the brainstorm as a desire but is out of scope for this update — that belongs in a dedicated tab structure redesign.

---

## Affected Files

### New Files (3)

| File | Purpose |
|---|---|
| `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift` | Floating bar above tab bar; driven by `ContextualBarState` enum defined in this file |
| `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift` | Compressed water + coffee + activity tile row |
| `WellPlate/Features + UI/Home/Components/QuickStatTile.swift` | Single tile within `QuickStatsRow` (split touch zones: increment vs. navigate) |

### Modified Files (4)

| File | What changes |
|---|---|
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | (1) Remove `DragToLogOverlay` from `.safeAreaInset`; add `ContextualActionBar`. (2) Remove `HydrationCard` + `CoffeeCard` from stack; add `QuickStatsRow`. (3) Re-enable `MealLogCard` with `todayFoodLogs` + `onDelete` + `onAddAgain`. (4) Remove `dragLogProgress` state + blur/overlay. (5) Slim header icon buttons from 4 to 2. (6) Add delta badge forwarding to `WellnessRingsCard`. (7) Extend `greeting` with day/streak personality. |
| `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` | Add `prefillFromEntry(_:)` method; add `yesterdayStats` computed property; expose `@Published var yesterdayStats` for binding |
| `WellPlate/Features + UI/Home/Components/MealLogCard.swift` | Add `.frame(maxHeight: 360)` cap on `mealList` scroll; minor: remove the erroneous `padding(.horizontal, 16)` that is applied both inside `mealList` and outside the card call-site |
| `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift` | Accept optional `deltaValues: [WellnessRingDestination: Int]?` parameter; render `Δ +n` badge below each ring label when non-nil |

### Kept but no longer used in HomeView (not deleted)

| File | Reason kept |
|---|---|
| `WellPlate/Features + UI/Home/Components/DragToLogOverlay.swift` | Possible re-use in other surfaces; keep for now |
| `WellPlate/Features + UI/Home/Components/HydrationCard.swift` | Still used inside `WaterDetailView` |
| `WellPlate/Features + UI/Home/Components/CoffeeCard.swift` | Still used inside `CoffeeDetailView` |
| `WellPlate/Features + UI/Home/Components/QuickLogSection.swift` | Currently commented-out in HomeView; no new usage. Keep for reference. |
| `WellPlate/Features + UI/Home/Components/ActivityCard.swift` | Still commented out; `QuickStatsRow` uses a simpler steps tile. Full ActivityCard remains available for future use. |
| `WellPlate/Features + UI/Home/Components/StressInsightCard.swift` | Still commented out; `ContextualActionBar` covers the actionable stress nudge surface. |
| `WellPlate/Features + UI/Home/Components/HomeHeaderView.swift` | Not used by HomeView (HomeView renders its own inline header). Keep as a reusable component. |
| `WellPlate/Features + UI/Home/Components/ExpandableFAB.swift` | Not used in this update. Keep. |

### Not touched

`MainTabView.swift`, `AppColor.swift`, all ViewModel files except `HomeViewModel.swift`, all detail views (`WaterDetailView`, `CoffeeDetailView`, `BurnView`, `FoodJournalView`, `JournalHistoryView`, `HomeAIInsightView`, `WellnessCalendarView`), all models, all services.

---

## Roadmap Accommodation (F1–F10)

| Feature | How this UX update accommodates it |
|---|---|
| **F1 Fasting Timer** | `ContextualActionBar` gains a `fastingActive(timeRemaining: String)` case that shows the countdown when a fast is running. The bar's priority system gives fasting status a dedicated high-priority slot. No layout change needed. |
| **F2 State of Mind** | `MoodCheckInCard` continues unchanged. The bar's `defaultActions` state shows the mood face icon when mood is not yet logged. |
| **F3 Circadian Stack** | `QuickStatsRow` has a fourth slot reserved (the current 3-tile row leaves room for expansion). Circadian score or sleep quality can become a fourth tile without layout surgery. |
| **F4 Journal** | `JournalReflectionCard` already exists and is already in the card stack. No change needed. |
| **F5 Symptom Tracking** | Symptom log shortcut moves from the header to the `ContextualActionBar` `defaultActions` trailing area (replaces the current `heart.text.square.fill` header button). The bar has room for a third trailing icon. |
| **F6 Supplements** | No home screen surface needed at MVP. Adherence nudge ("Take your evening supplement") can be a future `ContextualBarState.supplementReminder` case. |
| **F7 Live Activities** | Live Activities live on Lock Screen and Dynamic Island — no home screen interaction needed. |
| **F8 Apple Watch** | Watch companion reads from the same `WellnessDayLog` and `WatchTransferPayload` structures. No home screen change affects Watch data flow. |
| **F9 Photo Meal Logging** | `ContextualActionBar` pill in `defaultActions` or `logNextMeal` states can add a camera icon that opens photo meal capture. The bar already has trailing icon slots. |
| **F10 Partner Accountability** | No home screen surface needed for MVP (shared card is a share-sheet action from Profile tab). |

---

## Design Constraints

1. **Single `.sheet(item: $activeSheet)` rule**: do not add any new `.sheet()` modifier to `HomeView`. All new sheets route through the existing `HomeSheet` enum and `activeSheet` state variable.
2. **`.safeAreaInset(edge: .bottom)` is exclusive**: `HomeView` may have only one `.safeAreaInset(edge: .bottom)` modifier. The `ContextualActionBar` replaces `DragToLogOverlay` in this slot. Do not stack two `.safeAreaInset` calls.
3. **No new `@StateObject` ViewModels in `HomeView`**: all new state is computed or sourced from existing objects. `HomeView` already has `foodJournalViewModel`, `insightService`, and `journalPromptService` — do not add more `@StateObject` references.
4. **`ContextualBarState` is a pure computed property**: it must not make any async calls, trigger any side effects, or depend on stored state beyond what already exists. It is evaluated on every `body` call.
5. **Delta badges are opt-in on `WellnessRingsCard`**: the `deltaValues` parameter is `optional` with a `nil` default. Passing `nil` renders the card identically to today. This preserves backward compatibility for any previews or other callers.
6. **`MealLogCard` max height**: 360 pt cap is non-negotiable. The home screen must not be dominated by a long meal list.
7. **Font/shadow conventions apply**: all new components use `.r(.headline, .semibold)` for primary labels, `.appShadow(radius:y:)` for card shadows, and the standard `RoundedRectangle(cornerRadius: 20)` card container.
8. **Minimum touch targets**: all interactive elements including the `QuickStatTile` increment button and the contextual bar pill are at least 44×44 pt.
9. **Reduce Motion compliance**: `ContextualActionBar` state transitions do not animate content if `UIAccessibility.isReduceMotionEnabled`. The bar slides in on first appear only.
10. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**: `ContextualBarState` and `yesterdayStats` computations are implicitly `@MainActor` — no explicit annotation needed, but do not dispatch them onto background actors.

---

## Non-Goals

- Adding a fourth tab (Burn or Sleep) to `MainTabView`. This is a separate structural decision.
- Modular widget grid or drag-to-rearrange home screen.
- AI-generated narrative card at the top of the home screen.
- Pull-to-refresh with custom animation.
- Horizontal "Today's Timeline" strip.
- User-configurable wake/sleep times for the water-pace calculation (hardcoded 07:00–22:00 for now).
- Migrating `WellnessCalendarView` to a new tab — it stays behind the `calendar` icon, which is simply removed from the header and re-homed to the Profile tab action list.
- Greeting weather-awareness (requires CoreLocation or WeatherKit — new framework entitlement, out of scope).
- Fasting timer UI (belongs to F1 strategy/plan).
- Any changes to `StressView`, `BurnView`, `SleepDetailView`, or `ProfilePlaceholderView`.

---

## Open Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `ContextualBarState` recomputes on every body evaluation — if `allFoodLogs` or `allWellnessDayLogs` triggers frequent SwiftData notifications, this could cause excessive re-renders | Medium | Profile in Instruments. If an issue, elevate `ContextualBarState` to a `@State` var updated via explicit `onChange(of:)` triggers — the same pattern already used for `hydrationGlasses`. |
| Removing `DragToLogOverlay` breaks muscle memory for users who learned the swipe-up gesture | Low | The right-swipe gesture (already in `HomeView.simultaneousGesture`) is preserved and opens meal log. The new `ContextualActionBar` visible CTA more than compensates for discoverability. |
| `MealLogCard` height cap (360 pt) may truncate meals for heavy loggers (> 5 per day) | Low | The scroll inside the cap is user-accessible. "See all" can be addressed in a future iteration with a "Show More" expansion button. |
| `QuickStatsRow` split touch zone (increment vs. navigate) may be confusing | Medium | Visual affordance: the `+` button is a distinct circle at 36×36 pt with background fill; the tile body has a subtle "chevron.right" indicator. User test if possible before shipping. |
| `yesterdayStats` fetch on `HomeViewModel` is a synchronous SwiftData query on the main actor — if model context is slow to hydrate, this could stall on first launch | Low | The fetch is for a single `WellnessDayLog` record with an equality predicate. At worst it's a few microseconds. Acceptable. |
| Symptom log button moved from header to ContextualActionBar trailing row — reduces discoverability | Low | The symptom log button was already hidden behind a 38 pt icon with no label. Moving it to the bar where it has label space ("+ Symptom") is a net improvement. Add it as the third trailing icon in `defaultActions` state. |

---

## Rollback Strategy

All changes are additive with respect to navigation and data persistence. If the update must be reverted:

1. **Re-add `DragToLogOverlay`** to `.safeAreaInset(edge: .bottom)` in `HomeView` — one line change.
2. **Re-add `HydrationCard` and `CoffeeCard`** to the card stack — two blocks of code already in the file as comments.
3. **Comment out `MealLogCard`** — already the current state.
4. **Remove `ContextualActionBar` and `QuickStatsRow`** calls from `HomeView` body.

The three new component files (`ContextualActionBar.swift`, `QuickStatsRow.swift`, `QuickStatTile.swift`) can remain in the project without affecting the build — they just become unreferenced. `HomeViewModel` additions (`prefillFromEntry`, `yesterdayStats`) are additive and do not break existing callers if not removed.

No SwiftData migrations are required. No new model fields are added. Rollback is a 15-minute code revert.
