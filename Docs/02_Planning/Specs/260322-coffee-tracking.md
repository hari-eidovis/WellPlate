# Implementation Plan: Coffee Tracking

**Date:** 2026-03-22
**Feature:** Coffee tracking card on Home screen with dedicated detail view, coffee type picker, and hydration nudge alert

---

## Overview

Add a Coffee tracking card to the Home screen that mirrors the existing Hydration card pattern. When a user logs their first cup of the day, a type picker sheet (Espresso, Latte, Americano, etc.) is presented. After every coffee log, an alert nudges the user to also log a glass of water to counter dehydration. A dedicated `CoffeeDetailView` provides a full-screen expanded view identical in structure to `WaterDetailView`.

---

## Requirements

- Coffee card on Home screen, visually consistent with `HydrationCard`
- Dedicated `CoffeeDetailView` (tapping card navigates to it)
- `CoffeeTypePickerSheet` shown when `coffeeCups == 0` for today (first cup of the day)
- After every coffee cup logged, show an alert: "Coffee dehydrates — log a glass of water too?"
- Coffee type saved per-day alongside cup count in `WellnessDayLog`
- Daily coffee goal (default 4 cups) stored in `UserGoals`
- No extra build targets or separate SwiftData models needed

---

## Architecture Changes

| What | Where | Notes |
|------|-------|-------|
| Add `coffeeCups: Int`, `coffeeType: String?` | `WellPlate/Models/WellnessDayLog.swift` | Lightweight SwiftData auto-migration (new props with defaults) |
| Add `coffeeDailyCups: Int` | `WellPlate/Models/UserGoals.swift` | Default 4; add to `init`, `resetToDefaults()` |
| New `CoffeeType` enum | `WellPlate/Models/CoffeeType.swift` | `String` raw-value enum: cases + display name + SF symbol |
| New `CoffeeCard` component | `WellPlate/Features + UI/Home/Components/CoffeeCard.swift` | Clone of `HydrationCard`, amber colour scheme, cup icons |
| New `CoffeeTypePickerSheet` | `WellPlate/Features + UI/Home/Views/CoffeeTypePickerSheet.swift` | Sheet with grid of coffee types, dismisses with selection |
| New `CoffeeDetailView` | `WellPlate/Features + UI/Home/Views/CoffeeDetailView.swift` | Clone of `WaterDetailView`, coffee colour scheme, coffee tips |
| Update `HomeView` | `WellPlate/Features + UI/Home/Views/HomeView.swift` | State vars, CoffeeCard, navigationDestinations, alert, refresh helpers |

---

## Implementation Steps

### Phase 1 — Data Model

#### Step 1 — Add `CoffeeType` enum
**File:** `WellPlate/Models/CoffeeType.swift` *(new file)*

```swift
enum CoffeeType: String, CaseIterable, Identifiable {
    case espresso    = "Espresso"
    case americano   = "Americano"
    case latte       = "Latte"
    case cappuccino  = "Cappuccino"
    case flatWhite   = "Flat White"
    case macchiato   = "Macchiato"
    case coldBrew    = "Cold Brew"
    case pourOver    = "Pour Over"

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

- **Action:** Create file at path above with the enum body
- **Why:** Centralises coffee type knowledge; `String` raw value lets it store cleanly as `WellnessDayLog.coffeeType`
- **Risk:** Low

---

#### Step 2 — Extend `WellnessDayLog`
**File:** `WellPlate/Models/WellnessDayLog.swift`

Add two new stored properties **after** the existing `stressLevel` field:

```swift
/// Cups of coffee consumed today (0 = none logged).
var coffeeCups: Int

/// Raw value of the `CoffeeType` chosen for today, e.g. "Latte". nil = not chosen yet.
var coffeeType: String?
```

Update `init(...)` signature defaults:

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

- **Action:** Edit `WellnessDayLog.swift` in three places (stored props, init signature, init body) + add computed var
- **Why:** SwiftData auto-migrates new `@Model` properties that have defaults — no manual migration needed
- **Risk:** Low (confirmed by SwiftData lightweight migration rules)

---

#### Step 3 — Add coffee goal to `UserGoals`
**File:** `WellPlate/Models/UserGoals.swift`

Add stored property after `waterDailyCups`:

```swift
/// Daily coffee cup goal (default: 4).
var coffeeDailyCups: Int
```

Update `init(...)`:

```swift
coffeeDailyCups: Int = 4,
```

Update `init` body:

```swift
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

Model directly after `HydrationCard`. Key differences:

| Property | HydrationCard | CoffeeCard |
|----------|--------------|------------|
| Title | "Hydration" | "Coffee" |
| Colour hue | 0.58 (blue) | 0.08 (amber-brown) |
| Icon | `drop.fill` | `cup.and.saucer.fill` |
| Binding | `glassesConsumed` | `cupsConsumed` |
| Subtitle | "\(n) of 8 cups · \(mL) mL" | "\(n) of \(total) cups · \(caffeine) mg caffeine" |

**Bindings & args:**

```swift
@Binding var cupsConsumed: Int
let totalCups: Int
var coffeeType: CoffeeType? = nil   // shown as subtitle badge when set
var onTap: (() -> Void)? = nil
var onAdd: (() -> Void)? = nil      // separate callback so HomeView can intercept first-cup flow
```

The `+` button calls `onAdd?()` instead of directly mutating `cupsConsumed`, allowing `HomeView` to decide whether to show the type picker or just log.

Individual cup icons use the same `CoffeeIcon` private subview (same pattern as `GlassIcon`).

`CoffeeIcon` uses `cup.and.saucer.fill` / `cup.and.saucer` for filled/empty states.

Colour constants:

```swift
private let coffeeColor      = Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
private let coffeeColorLight = Color(hue: 0.08, saturation: 0.25, brightness: 0.97)
```

Subtitle example: `"2 of 4 cups · 126 mg caffeine"`
Caffeine calc: `cupsConsumed * (coffeeType?.caffeineMg ?? 80)` — 80 mg default when type unknown.

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

                Spacer()
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: type.symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(coffeeColor)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(coffeeColorLight))

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

    private let coffeeColor      = Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
    private let coffeeColorLight = Color(hue: 0.08, saturation: 0.25, brightness: 0.97)
}
```

- **Presentation:** `.sheet(isPresented:)` triggered from HomeView
- **Risk:** Low

---

### Phase 4 — Coffee Detail View

#### Step 6 — Create `CoffeeDetailView`
**File:** `WellPlate/Features + UI/Home/Views/CoffeeDetailView.swift` *(new file)*

Structure mirrors `WaterDetailView` exactly:

| Section | WaterDetailView | CoffeeDetailView |
|---------|----------------|-----------------|
| Navigation title | "Hydration" | "Coffee" |
| Hero icon | `drop.fill` | `cup.and.saucer.fill` |
| Progress colour | blue (hue 0.58) | amber-brown (hue 0.08) |
| Grid title | "Today's Glasses" | "Today's Cups" |
| Grid icon filled | `drop.fill` | `cup.and.saucer.fill` |
| Grid icon empty | `drop` | `cup.and.saucer` |
| Stats | Progress %, mL consumed, cups remaining | Progress %, caffeine mg, cups remaining |
| Tip card | Hydration tips | Coffee / caffeine tips |

**Init args:**

```swift
init(totalCups: Int, coffeeType: CoffeeType? = nil)
```

`coffeeType` is used to display caffeine per cup and the chosen type name in the hero card subtitle.

**Caffeine stats pill:** `"\(glassesConsumed * caffeineMgPerCup) mg"` where `caffeineMgPerCup = coffeeType?.caffeineMg ?? 80`.

**Coffee tips (rotate by hour):**

```swift
[
    ("Coffee after 2 PM can disrupt sleep", "moon.fill"),
    ("Stay hydrated — drink water between cups", "drop.fill"),
    ("Limit to 4 cups per day for most adults", "exclamationmark.circle.fill"),
    ("Black coffee has zero calories", "number.circle.fill"),
    ("Espresso has less caffeine than drip coffee", "info.circle.fill"),
]
```

**No type picker inside detail view** — type is already set before navigating here. If `coffeeType` is nil, show "Mixed" as a fallback label.

**Water alert:** The detail view's `+` button / grid tap also shows the same "log water?" alert for consistency. Use the same `.alert` pattern as HomeView.

- **Risk:** Low

---

### Phase 5 — HomeView Integration

#### Step 7 — Update `HomeView`
**File:** `WellPlate/Features + UI/Home/Views/HomeView.swift`

**7a. New state vars** (add alongside existing `@State` block):

```swift
@State private var coffeeCups: Int = 0
@State private var showCoffeeDetail    = false
@State private var showCoffeeTypePicker = false
@State private var showCoffeeWaterAlert = false
@State private var pendingCoffeeType: CoffeeType? = nil
```

**7b. Add `CoffeeCard` below `HydrationCard`** (in the LazyVStack, after item 5):

```swift
// 6. Coffee
CoffeeCard(
    cupsConsumed: $coffeeCups,
    totalCups: currentGoals.coffeeDailyCups,
    coffeeType: todayWellnessLog?.resolvedCoffeeType,
    onTap: { showCoffeeDetail = true },
    onAdd: { handleCoffeeAdd() }
)
.padding(.horizontal, 16)
```

**7c. Navigation destination** (alongside existing `.navigationDestination` calls):

```swift
.navigationDestination(isPresented: $showCoffeeDetail) {
    CoffeeDetailView(
        totalCups: currentGoals.coffeeDailyCups,
        coffeeType: todayWellnessLog?.resolvedCoffeeType
    )
}
```

**7d. Coffee type picker sheet** (attach to the ScrollView or NavigationStack):

```swift
.sheet(isPresented: $showCoffeeTypePicker) {
    CoffeeTypePickerSheet { type in
        showCoffeeTypePicker = false
        pendingCoffeeType = type
        commitCoffeeAdd(type: type)
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

**7f. `handleCoffeeAdd()` helper:**

```swift
private func handleCoffeeAdd() {
    guard coffeeCups < currentGoals.coffeeDailyCups else { return }
    // First cup of the day — ask which type
    if coffeeCups == 0 && todayWellnessLog?.coffeeType == nil {
        showCoffeeTypePicker = true
    } else {
        // Subsequent cups — just add directly
        commitCoffeeAdd(type: todayWellnessLog?.resolvedCoffeeType)
    }
}
```

**7g. `commitCoffeeAdd(type:)` helper:**

```swift
private func commitCoffeeAdd(type: CoffeeType?) {
    HapticService.impact(.light)
    SoundService.playConfirmation()
    coffeeCups += 1
    updateCoffeeForToday(cups: coffeeCups, type: type)
    showCoffeeWaterAlert = true
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

- **Risk:** Medium — requires careful state coordination between type picker sheet, water alert, and cup count binding

---

### Phase 6 — `CoffeeDetailView` Water Alert

#### Step 8 — Water alert inside `CoffeeDetailView`

`CoffeeDetailView` is self-contained (reads/writes `WellnessDayLog` directly like `WaterDetailView`). Add:

```swift
@State private var showWaterAlert = false
```

Trigger in `addCup()`:

```swift
private func addCup() {
    guard cupsConsumed < totalCups else { return }
    HapticService.impact(.light)
    SoundService.playConfirmation()
    updateCups(cupsConsumed + 1)
    showWaterAlert = true
}
```

Alert modifier on the ScrollView:

```swift
.alert("Stay Hydrated!", isPresented: $showWaterAlert) {
    Button("Log Water") { logOneWater() }
    Button("Skip", role: .cancel) {}
} message: {
    Text("Coffee can cause dehydration. Want to log a glass of water too?")
}
```

`logOneWater()` fetches/creates today's `WellnessDayLog` and increments `waterGlasses` by 1 (capped at 8), saves context.

- **Risk:** Low

---

## File Summary

| File | Action |
|------|--------|
| `WellPlate/Models/CoffeeType.swift` | **CREATE** — `CoffeeType` String enum |
| `WellPlate/Models/WellnessDayLog.swift` | **EDIT** — add `coffeeCups`, `coffeeType`, `resolvedCoffeeType` |
| `WellPlate/Models/UserGoals.swift` | **EDIT** — add `coffeeDailyCups` |
| `WellPlate/Features + UI/Home/Components/CoffeeCard.swift` | **CREATE** — card component |
| `WellPlate/Features + UI/Home/Views/CoffeeTypePickerSheet.swift` | **CREATE** — type picker half-sheet |
| `WellPlate/Features + UI/Home/Views/CoffeeDetailView.swift` | **CREATE** — full detail view |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | **EDIT** — integrate card, states, sheet, alert |

No changes needed to `WellPlateApp.swift` — `WellnessDayLog` is already registered in the ModelContainer.

---

## Testing Strategy

- **Build verify:** `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
- **Manual smoke tests:**
  - [ ] Fresh install: first coffee tap shows type picker
  - [ ] Type picker selection saves type and increments to 1 cup
  - [ ] Water alert appears after every coffee log (in card + detail view)
  - [ ] "Log Water" in alert increments hydration glasses
  - [ ] Subsequent coffee taps (same day) skip type picker
  - [ ] Detail view navigates from card tap
  - [ ] Cup count syncs between card and detail view on back navigation
  - [ ] Caffeine mg updates correctly in CoffeeCard subtitle and CoffeeDetailView stats
  - [ ] Tomorrow (new day): type picker appears again (coffeeType nil for new WellnessDayLog)
  - [ ] Dark mode: amber colour scheme readable on dark background

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| SwiftData lightweight migration fails on existing devices | Medium | New properties have explicit defaults in `init` — SwiftData handles this automatically; test in Simulator with existing data |
| Double `.sheet` conflict | Low | `CoffeeTypePickerSheet` uses its own `showCoffeeTypePicker` bool; existing sheets use `isPresented` bools already scoped — no `sheet(item:)` conflicts |
| Water alert and type picker sheet overlapping | Low | `handleCoffeeAdd()` only sets one bool at a time; water alert is set in `commitCoffeeAdd` which runs *after* picker dismisses |
| `CoffeeDetailView` and `HomeView` cup counts diverging | Medium | Both read from `WellnessDayLog` via `@Query` / `fetchTodayWellnessLog()`; HomeView refreshes on `showCoffeeDetail` dismissal |

---

## Success Criteria

- [ ] Coffee card appears on Home screen below Hydration card
- [ ] Card shows cup count, total, and caffeine mg
- [ ] First tap on `+` (when 0 cups) shows `CoffeeTypePickerSheet` with 8 coffee types
- [ ] After type selection, cup count becomes 1 and water alert appears
- [ ] Subsequent `+` taps skip picker and directly show water alert
- [ ] Tapping card body navigates to `CoffeeDetailView`
- [ ] Detail view shows circular progress, cup grid, stats (progress %, caffeine, remaining), tip
- [ ] Logging a cup inside detail view also shows water alert
- [ ] App builds cleanly with no new warnings
