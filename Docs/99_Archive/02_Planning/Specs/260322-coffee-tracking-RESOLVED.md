# Implementation Plan: Coffee Tracking (RESOLVED)

**Date:** 2026-03-22
**Resolves audit:** `Docs/05_Audits/Code/260322-coffee-tracking-audit.md`
**Status:** APPROVED FOR IMPLEMENTATION

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| Alert silently dropped after sheet dismiss | CRITICAL | `onChange(of: showCoffeeTypePicker)` fires alert after sheet fully closes; `pendingCoffeeType` is the handoff variable |
| Decrement persistence gap | CRITICAL | Dropped `onAdd` callback; CoffeeCard uses direct binding mutation like HydrationCard; `onChange(of: coffeeCups)` handles all persistence |
| Type picker bypassed via card-tap path | HIGH | `CoffeeDetailView` shows its own type picker on first `addCup()` when `coffeeType == nil`, using the same `onChange` race-safe pattern |
| `logOneWater()` hardcoded cap at 8 | HIGH | `CoffeeDetailView` adds `@Query private var userGoalsList: [UserGoals]` and uses `.first?.waterDailyCups ?? 8` |
| `pendingCoffeeType` was dead state | MEDIUM | Now the intentional sheet→alert handoff variable; purpose documented explicitly |
| CoffeeDetailView missing toolbar +/- | MEDIUM | Added to spec comparison table; toolbar `+` also triggers type picker / water alert |
| One type per day undocumented | MEDIUM | Documented as explicit V1 product decision |
| Coffee tip copy conflict | LOW | Replaced comparative tip with absolute fact |
| No decrement smoke test | LOW | Added to testing strategy |
| Sheet detent tight on small screens | LOW | Added `ScrollView` wrapper to `CoffeeTypePickerSheet` |

---

## Overview

Add a Coffee tracking card to the Home screen mirroring the existing `HydrationCard` pattern. On a user's first cup of any new day, a type picker sheet (Espresso, Latte, etc.) is presented. After every coffee addition, an alert nudges the user to log water. A dedicated `CoffeeDetailView` provides a full-screen expanded view identical in structure to `WaterDetailView`.

---

## Product Decisions (V1 Scope)

> **One coffee type per day:** `WellnessDayLog.coffeeType` stores a single type for the entire day. A user who drinks a Latte in the morning and an Espresso in the evening will have caffeine totals calculated using the first type selected. This is a documented V1 limitation. A future `CoffeeLogEntry` model (separate SwiftData entity per cup) would enable per-cup type tracking.

> **Type retained after decrement:** Once a type is chosen for a day, it persists even if the user decrements to 0 cups. The picker will not re-appear for that calendar day. A fresh `WellnessDayLog` the next day resets the type.

> **Type picker shown every new day:** The type picker appears on the first cup of each calendar day (when `coffeeCups == 0 && coffeeType == nil`), not only on first-ever app launch.

> **Decrement does not trigger water alert:** The water alert fires only on cup additions (new value > old value), not on decrements.

> **Coffee not in Wellness Rings:** The coffee card is standalone on the Home screen. No ring is added to `WellnessRingsCard` in this iteration.

---

## Requirements

- Coffee card on Home screen, visually consistent with `HydrationCard`
- Dedicated `CoffeeDetailView` (tapping card body navigates to it)
- `CoffeeTypePickerSheet` shown on the first cup of each new day from **both** the card `+` button and inside `CoffeeDetailView`
- After every coffee cup **addition**, show alert: "Coffee can cause dehydration. Want to log a glass of water too?"
- Alert fires only after the sheet has fully dismissed (no SwiftUI race condition)
- Coffee type and cup count saved per-day in `WellnessDayLog`
- Daily coffee goal (default 4 cups) in `UserGoals`

---

## Architecture Changes

| What | Where | Notes |
|------|-------|-------|
| Add `coffeeCups: Int`, `coffeeType: String?` | `WellPlate/Models/WellnessDayLog.swift` | SwiftData auto-migration; both have init defaults |
| Add `coffeeDailyCups: Int` | `WellPlate/Models/UserGoals.swift` | Default 4; add to `init`, `resetToDefaults()` |
| New `CoffeeType` enum | `WellPlate/Models/CoffeeType.swift` | `String` raw-value; 8 cases with caffeine mg and SF symbol |
| New `CoffeeCard` | `WellPlate/Features + UI/Home/Components/CoffeeCard.swift` | Direct binding mutation (no `onAdd` callback); identical pattern to `HydrationCard` |
| New `CoffeeTypePickerSheet` | `WellPlate/Features + UI/Home/Views/CoffeeTypePickerSheet.swift` | `onSelect` callback; `.medium` detent with `ScrollView` wrapper |
| New `CoffeeDetailView` | `WellPlate/Features + UI/Home/Views/CoffeeDetailView.swift` | Mirrors `WaterDetailView`; includes toolbar ±, own type picker, own water alert |
| Update `HomeView` | `WellPlate/Features + UI/Home/Views/HomeView.swift` | 5 new state vars; `onChange(of: coffeeCups)` for persistence; `onChange(of: showCoffeeTypePicker)` for race-safe alert |

No changes needed to `WellPlateApp.swift` — `WellnessDayLog` is already registered in the `ModelContainer`.

---

## Implementation Steps

### Phase 1 — Data Model

#### Step 1 — Create `CoffeeType` enum
**File:** `WellPlate/Models/CoffeeType.swift` *(new file)*

```swift
enum CoffeeType: String, CaseIterable, Identifiable {
    case espresso   = "Espresso"
    case americano  = "Americano"
    case latte      = "Latte"
    case cappuccino = "Cappuccino"
    case flatWhite  = "Flat White"
    case macchiato  = "Macchiato"
    case coldBrew   = "Cold Brew"
    case pourOver   = "Pour Over"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var symbol: String {
        switch self {
        case .espresso:   return "cup.and.saucer.fill"
        case .americano:  return "drop.fill"
        case .latte:      return "mug.fill"
        case .cappuccino: return "cup.and.saucer.fill"
        case .flatWhite:  return "mug.fill"
        case .macchiato:  return "cup.and.saucer.fill"
        case .coldBrew:   return "takeoutbag.and.cup.and.straw.fill"
        case .pourOver:   return "drop.fill"
        }
    }

    /// Approximate caffeine per standard cup/serving in mg.
    var caffeineMg: Int {
        switch self {
        case .espresso:   return 63
        case .americano:  return 77
        case .latte:      return 63
        case .cappuccino: return 63
        case .flatWhite:  return 130
        case .macchiato:  return 63
        case .coldBrew:   return 200
        case .pourOver:   return 95
        }
    }
}
```

- **Risk:** Low

---

#### Step 2 — Extend `WellnessDayLog`
**File:** `WellPlate/Models/WellnessDayLog.swift`

Add after the `stressLevel` stored property:

```swift
/// Cups of coffee consumed today (0 = none logged).
var coffeeCups: Int

/// Raw value of the `CoffeeType` chosen for today, e.g. "Latte".
/// nil = not chosen yet. Retained for the full day even if cups are decremented to 0.
var coffeeType: String?
```

Update `init(...)` signature:

```swift
coffeeCups: Int = 0,
coffeeType: String? = nil,
```

Assign in init body:

```swift
self.coffeeCups  = coffeeCups
self.coffeeType  = coffeeType
```

Add computed convenience:

```swift
var resolvedCoffeeType: CoffeeType? {
    guard let raw = coffeeType else { return nil }
    return CoffeeType(rawValue: raw)
}
```

- **Migration note:** SwiftData performs a lightweight auto-migration for new properties with defaults. Verify by running the app in Simulator against an existing data store before shipping.
- **Risk:** Low

---

#### Step 3 — Add coffee goal to `UserGoals`
**File:** `WellPlate/Models/UserGoals.swift`

Add stored property after `waterDailyCups`:

```swift
/// Daily coffee cup goal (default: 4).
var coffeeDailyCups: Int
```

Update `init(...)` signature and body:

```swift
coffeeDailyCups: Int = 4,
// ...
self.coffeeDailyCups = coffeeDailyCups
```

Update `resetToDefaults()`:

```swift
coffeeDailyCups = 4
```

- **Risk:** Low

---

### Phase 2 — Coffee Card Component

#### Step 4 — Create `CoffeeCard`
**File:** `WellPlate/Features + UI/Home/Components/CoffeeCard.swift` *(new file)*

Model **exactly** after `HydrationCard`. Key differences:

| Property | HydrationCard | CoffeeCard |
|----------|--------------|------------|
| Title | "Hydration" | "Coffee" |
| Colour hue | 0.58 (blue) | 0.08 (amber-brown) |
| Filled icon | `drop.fill` | `cup.and.saucer.fill` |
| Empty icon | `drop.fill` (dimmed) | `cup.and.saucer` (dimmed) |
| Binding | `glassesConsumed` | `cupsConsumed` |
| Subtitle | "N of 8 cups · X mL" | "N of 4 cups · X mg caffeine" |
| Callbacks | `onTap` only | `onTap` only — **no `onAdd`** |

**Interface:**

```swift
@Binding var cupsConsumed: Int
let totalCups: Int
var coffeeType: CoffeeType? = nil
var onTap: (() -> Void)? = nil
```

**`+` button:** directly mutates `cupsConsumed += 1` (same as `HydrationCard.addGlass()`). No callback needed — `HomeView.onChange(of: coffeeCups)` handles the rest.

**Individual cup icon taps:** `toggleCup(at:)` directly mutates `cupsConsumed` (same as `HydrationCard.toggleGlass(at:)`).

**Subtitle caffeine calc:** `cupsConsumed * (coffeeType?.caffeineMg ?? 80)` — 80 mg fallback when type not yet chosen.

**Colour constants:**

```swift
private let coffeeColor      = Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
private let coffeeColorLight = Color(hue: 0.08, saturation: 0.25, brightness: 0.97)
```

**[RESOLVED — Audit #2]** Direct binding mutation (no `onAdd`) ensures all interactions (add and decrement) are captured by `HomeView.onChange(of: coffeeCups)` for persistence. This is identical to the water card pattern.

- **Risk:** Low

---

### Phase 3 — Coffee Type Picker Sheet

#### Step 5 — Create `CoffeeTypePickerSheet`
**File:** `WellPlate/Features + UI/Home/Views/CoffeeTypePickerSheet.swift` *(new file)*

```swift
struct CoffeeTypePickerSheet: View {
    var onSelect: (CoffeeType) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            // ScrollView wrapper required — 8 items × 3 columns needs ~270 pt minimum;
            // .medium detent on 4.7" screen (SE) is ~330 pt total. Wrap to be safe.
            ScrollView {
                VStack(spacing: 20) {
                    Text("What are you drinking?")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.top, 8)

                    Text("Each selection counts as 1 cup")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(CoffeeType.allCases) { type in
                            CoffeeTypeCell(type: type) {
                                onSelect(type)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Choose Coffee")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct CoffeeTypeCell: View {
    let type: CoffeeType
    let action: () -> Void

    private let coffeeColor      = Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
    private let coffeeColorLight = Color(hue: 0.08, saturation: 0.25, brightness: 0.97)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: type.symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(coffeeColor)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(coffeeColorLight)
                    )

                Text(type.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }
}
```

**[RESOLVED — Audit #11]** `ScrollView` wrapper prevents clipping on small screens.

- **Risk:** Low

---

### Phase 4 — Coffee Detail View

#### Step 6 — Create `CoffeeDetailView`
**File:** `WellPlate/Features + UI/Home/Views/CoffeeDetailView.swift` *(new file)*

Structure mirrors `WaterDetailView` completely:

| Section | WaterDetailView | CoffeeDetailView |
|---------|----------------|-----------------|
| Nav title | "Hydration" | "Coffee" |
| Toolbar | `-` and `+` buttons (topBarTrailing) | `-` and `+` buttons (topBarTrailing) |
| Hero icon | `drop.fill` | `cup.and.saucer.fill` |
| Progress colour | blue (hue 0.58) | amber-brown (hue 0.08) |
| Hero subtitle | "X mL" | "X mg caffeine" (or "Choose a type ↑" if coffeeType nil) |
| Grid title | "Today's Glasses" | "Today's Cups" |
| Grid icon filled | `drop.fill` | `cup.and.saucer.fill` |
| Grid icon empty | `drop` | `cup.and.saucer` |
| Stats pills | Progress %, mL consumed, cups remaining | Progress %, caffeine mg total, cups remaining |
| Tip card | Hydration tips | Coffee tips (see below) |

**[RESOLVED — Audit #6]** Toolbar `+`/`-` buttons are explicitly included.

**Init args:**

```swift
init(totalCups: Int, coffeeType: CoffeeType? = nil)
```

**Additional state (beyond WaterDetailView):**

```swift
@Query private var userGoalsList: [UserGoals]          // [RESOLVED — Audit #4]
@State private var showTypePicker    = false            // [RESOLVED — Audit #3]
@State private var pendingType: CoffeeType? = nil       // handoff var for sheet→alert race fix
@State private var showWaterAlert    = false
```

**`addCup()` — first-cup detection:**

```swift
private func addCup() {
    guard cupsConsumed < totalCups else { return }
    HapticService.impact(.light)
    SoundService.playConfirmation()
    updateCups(cupsConsumed + 1)

    // If this is the first cup and no type has been set today, show the type picker.
    // The water alert fires AFTER the picker dismisses (onChange race-safe pattern).
    if cupsConsumed == 1 && todayLog?.coffeeType == nil {
        showTypePicker = true
    } else {
        showWaterAlert = true
    }
}
```

Note: `cupsConsumed` is a computed property reading from `todayLog?.coffeeCups`. After `updateCups(cupsConsumed + 1)` writes to SwiftData, `cupsConsumed` will reflect the new value (1) on the next SwiftUI render. Check the updated value from the local count.

**Simpler approach** — pass the new count explicitly:

```swift
private func addCup() {
    guard cupsConsumed < totalCups else { return }
    HapticService.impact(.light)
    SoundService.playConfirmation()
    let newCount = cupsConsumed + 1
    updateCups(newCount)

    if newCount == 1 && todayLog?.coffeeType == nil {
        showTypePicker = true
        // water alert fires in onChange(of: showTypePicker) after sheet closes
    } else {
        showWaterAlert = true
    }
}
```

**`onChange(of: showTypePicker)` — race-safe alert trigger [RESOLVED — Audit #1 & #3]:**

```swift
.onChange(of: showTypePicker) { _, isShowing in
    guard !isShowing else { return }
    if let type = pendingType {
        // User selected a type — save it and show water alert
        pendingType = nil
        saveType(type)
        showWaterAlert = true
    } else {
        // User dismissed picker without selecting — revert the cup increment
        updateCups(max(0, cupsConsumed - 1))
    }
}
```

**Type picker sheet:**

```swift
.sheet(isPresented: $showTypePicker) {
    CoffeeTypePickerSheet { type in
        pendingType = type
        showTypePicker = false   // triggers onChange above after animation completes
    }
}
```

**Water alert [RESOLVED — Audit #4 — uses actual user goal, not hardcoded 8]:**

```swift
.alert("Stay Hydrated!", isPresented: $showWaterAlert) {
    Button("Log Water") { logOneWater() }
    Button("Skip", role: .cancel) {}
} message: {
    Text("Coffee can cause dehydration. Want to log a glass of water too?")
}

private func logOneWater() {
    let waterGoal = userGoalsList.first?.waterDailyCups ?? 8   // [RESOLVED — Audit #4]
    let log = fetchOrCreateTodayLog()
    log.waterGlasses = min(log.waterGlasses + 1, waterGoal)
    try? modelContext.save()
}
```

**`saveType(_:)` helper:**

```swift
private func saveType(_ type: CoffeeType) {
    let log = fetchOrCreateTodayLog()
    log.coffeeType = type.rawValue
    try? modelContext.save()
}
```

**Coffee tips (rotate by hour) [RESOLVED — Audit #9 — no comparative tips]:**

```swift
[
    ("Coffee after 2 PM can disrupt your sleep quality", "moon.fill"),
    ("Stay hydrated — drink a glass of water between cups", "drop.fill"),
    ("Most adults can safely enjoy up to 4 cups per day", "exclamationmark.circle.fill"),
    ("Black coffee has virtually zero calories", "number.circle.fill"),
    ("A single espresso shot contains about 63 mg of caffeine", "info.circle.fill"),
]
```

- **Risk:** Low

---

### Phase 5 — HomeView Integration

#### Step 7 — Update `HomeView`
**File:** `WellPlate/Features + UI/Home/Views/HomeView.swift`

**7a. New state vars** (alongside existing `@State` block):

```swift
@State private var coffeeCups: Int = 0
@State private var showCoffeeDetail     = false
@State private var showCoffeeTypePicker = false
@State private var showCoffeeWaterAlert = false
/// Handoff variable: set by the type picker sheet closure, read by onChange(of: showCoffeeTypePicker).
/// Intentionally not cleared in the sheet closure — only cleared in the onChange handler.
@State private var pendingCoffeeType: CoffeeType? = nil
```

**[RESOLVED — Audit #5]** `pendingCoffeeType` is the sheet→alert handoff variable. Its purpose is documented above so implementers don't remove it as dead code.

**7b. Add `CoffeeCard` below `HydrationCard`:**

```swift
// 6. Coffee
CoffeeCard(
    cupsConsumed: $coffeeCups,
    totalCups: currentGoals.coffeeDailyCups,
    coffeeType: todayWellnessLog?.resolvedCoffeeType,
    onTap: { showCoffeeDetail = true }
)
.padding(.horizontal, 16)
```

**7c. Navigation destination:**

```swift
.navigationDestination(isPresented: $showCoffeeDetail) {
    CoffeeDetailView(
        totalCups: currentGoals.coffeeDailyCups,
        coffeeType: todayWellnessLog?.resolvedCoffeeType
    )
}
```

**7d. Coffee type picker sheet:**

```swift
.sheet(isPresented: $showCoffeeTypePicker) {
    CoffeeTypePickerSheet { type in
        pendingCoffeeType = type        // store handoff value
        showCoffeeTypePicker = false    // dismiss sheet; alert fires in onChange below
    }
}
```

**7e. Water nudge alert:**

```swift
.alert("Stay Hydrated!", isPresented: $showCoffeeWaterAlert) {
    Button("Log Water") {
        if hydrationGlasses < currentGoals.waterDailyCups {
            hydrationGlasses += 1
        }
    }
    Button("Skip", role: .cancel) {}
} message: {
    Text("Coffee can cause dehydration. Want to log a glass of water too?")
}
```

**7f. `onChange(of: coffeeCups)` — persistence + first-cup picker trigger [RESOLVED — Audit #2]:**

```swift
.onChange(of: coffeeCups) { oldCups, newCups in
    if newCups > oldCups {
        // Addition path
        if newCups == 1 && todayWellnessLog?.coffeeType == nil {
            // First cup of the day, type not yet chosen — show picker.
            // Persist cup count optimistically; type saved after picker selection.
            updateCoffeeForToday(cups: newCups, type: nil)
            showCoffeeTypePicker = true
            // Water alert fires in onChange(of: showCoffeeTypePicker) after sheet dismisses.
        } else {
            // Subsequent cup, or type already known — persist and alert immediately.
            updateCoffeeForToday(cups: newCups, type: todayWellnessLog?.resolvedCoffeeType)
            showCoffeeWaterAlert = true
        }
    } else {
        // Decrement path — persist only, no water alert.
        updateCoffeeForToday(cups: newCups, type: todayWellnessLog?.resolvedCoffeeType)
    }
}
```

**7g. `onChange(of: showCoffeeTypePicker)` — race-safe alert [RESOLVED — Audit #1]:**

```swift
.onChange(of: showCoffeeTypePicker) { _, isShowing in
    guard !isShowing else { return }
    if let type = pendingCoffeeType {
        // User selected a type — save it then show alert.
        // Sheet is fully dismissed at this point; alert presentation is safe.
        pendingCoffeeType = nil
        updateCoffeeForToday(cups: coffeeCups, type: type)
        showCoffeeWaterAlert = true
    } else {
        // User swiped picker away without selecting — revert the cup increment.
        coffeeCups = max(0, coffeeCups - 1)
    }
}
```

**7h. `updateCoffeeForToday(cups:type:)` helper:**

```swift
private func updateCoffeeForToday(cups: Int, type: CoffeeType?) {
    let log = fetchOrCreateTodayWellnessLog()
    log.coffeeCups = max(0, cups)
    if let type { log.coffeeType = type.rawValue }
    do {
        try modelContext.save()
    } catch {
        WPLogger.home.error("Coffee save failed: \(error.localizedDescription)")
    }
}
```

**7i. `refreshTodayCoffeeState()` helper:**

```swift
private func refreshTodayCoffeeState() {
    coffeeCups = fetchTodayWellnessLog()?.coffeeCups ?? 0
}
```

Call this in:
- `onAppear { ... refreshTodayCoffeeState() }`
- `onChange(of: showCoffeeDetail) { _, showing in if !showing { refreshTodayCoffeeState() } }`
- `onChange(of: scenePhase) { _, phase in guard phase == .active else { return }; ...; refreshTodayCoffeeState() }`

- **Risk:** Low (same pattern as water; all edge cases handled)

---

## File Summary

| File | Action |
|------|--------|
| `WellPlate/Models/CoffeeType.swift` | **CREATE** |
| `WellPlate/Models/WellnessDayLog.swift` | **EDIT** — `coffeeCups`, `coffeeType`, `resolvedCoffeeType` |
| `WellPlate/Models/UserGoals.swift` | **EDIT** — `coffeeDailyCups` |
| `WellPlate/Features + UI/Home/Components/CoffeeCard.swift` | **CREATE** |
| `WellPlate/Features + UI/Home/Views/CoffeeTypePickerSheet.swift` | **CREATE** |
| `WellPlate/Features + UI/Home/Views/CoffeeDetailView.swift` | **CREATE** |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | **EDIT** |

---

## Testing Strategy

**Build verify:**
```
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```

**Manual smoke tests:**

Addition path:
- [ ] First `+` tap (coffeeCups = 0, coffeeType nil): shows type picker sheet
- [ ] Selecting a type in picker: cup count becomes 1, water alert appears **after** sheet fully closes
- [ ] "Log Water" in alert increments hydration glasses
- [ ] Subsequent `+` taps (same day): skips picker, water alert appears directly
- [ ] Card subtitle shows correct caffeine mg based on selected type
- [ ] Tapping card body navigates to `CoffeeDetailView`
- [ ] First `+` inside `CoffeeDetailView` (coffeeType nil): shows type picker within detail view
- [ ] Water alert in detail view uses actual `waterDailyCups` goal (not hardcoded 8)
- [ ] Toolbar `+` and `-` buttons work in detail view

Decrement path — **[RESOLVED — Audit #10]:**
- [ ] Tapping a filled cup icon decrements count
- [ ] After decrement, background app and reopen: count matches decremented value (persistence verified)
- [ ] Decrement to 0 does NOT trigger water alert
- [ ] After decrement to 0 then tap `+`: type picker does NOT re-appear (type retained for the day)

Picker dismissal without selection:
- [ ] Swipe picker sheet down without selecting: cup count reverts to 0 (not stuck at 1)

Day boundary:
- [ ] New calendar day: type picker appears again (new `WellnessDayLog` has `coffeeType = nil`)

Visual:
- [ ] Dark mode: amber colour scheme readable on dark background
- [ ] CoffeeDetailView hero, grid, stats, tip card all render correctly
- [ ] `CoffeeTypePickerSheet` not clipped on iPhone SE (4.7")

Migration:
- [ ] Run app with existing `WellnessDayLog` data in Simulator — no crash, `coffeeCups` defaults to 0

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| SwiftData lightweight migration fails on existing installs | Medium | Properties have explicit defaults in `init`; verify with pre-populated Simulator before shipping |
| `onChange(of: showCoffeeTypePicker)` fires unexpectedly | Low | Guard checks `!isShowing && pendingCoffeeType != nil` before acting; safe no-op otherwise |
| `CoffeeDetailView` type saves but `HomeView` shows stale type | Low | HomeView refreshes `coffeeCups` on `showCoffeeDetail` dismissal; `todayWellnessLog` is `@Query`-backed and auto-updates |
| Double `onChange` fire on `coffeeCups` | Low | SwiftData `@Query` updates are async; `onChange` fires once per binding mutation. No double-fire risk |

---

## Success Criteria

- [ ] Coffee card appears on Home screen below Hydration card
- [ ] Card shows cup count, total, and caffeine mg (correct type)
- [ ] First `+` tap shows `CoffeeTypePickerSheet`; water alert appears **after** picker closes
- [ ] Subsequent `+` taps show water alert directly
- [ ] Card body tap navigates to `CoffeeDetailView`
- [ ] First `+` in detail view shows type picker from within detail view
- [ ] Water alert in detail view respects user's water goal
- [ ] Toolbar `+`/`-` in detail view work correctly
- [ ] All decrements persist after backgrounding app
- [ ] Swiping picker away without selecting reverts cup count to 0
- [ ] App builds cleanly with no new warnings
