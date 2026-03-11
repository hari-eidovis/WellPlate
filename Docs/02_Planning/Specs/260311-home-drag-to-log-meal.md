# Implementation Plan: Home "Drag Up to Log a Meal" Overlay

## Overview
Add a subtle, pill-shaped bottom overlay on HomeView that hints the user can drag upward to log a meal. When the user performs a sufficient upward drag gesture on that overlay, it presents `MealLogSheetContent` as a sheet. After the user saves or dismisses the meal log sheet, they land on `FoodJournalView`, not back on HomeView. This is achieved by switching `MainTabView.selectedTab` to a new Food Journal tab and then navigating into `FoodJournalView` within that tab's `NavigationStack`.

## Requirements
- A minimal, non-intrusive bottom overlay on HomeView with the label "drag up to log a meal"
- Upward drag on the overlay opens the same `MealLogSheetContent` sheet that the plus button opens in `FoodJournalView`
- After dismissing/saving the meal log sheet, the user lands on `FoodJournalView` (not HomeView)
- Visual and haptic feedback during the drag gesture
- The overlay must not interfere with normal ScrollView scrolling elsewhere in HomeView
- Smooth spring animation on drag
- Consistent with the app's design language (orange accent, system background card, `appShadow`)

## Current Architecture (Key Facts)

### Navigation Structure
- `RootView` -> `MainTabView` (TabView with `@State private var selectedTab = 0`)
- Tab 0 = HomeView (owns its own `NavigationStack`)
- No dedicated Food Journal tab currently exists; FoodJournalView is pushed via `navigationDestination(isPresented:)` from HomeView using `showLogMeal = true`
- HomeView already holds a `@StateObject private var foodJournalViewModel = HomeViewModel()`

### How Meal Logging Currently Works
1. User taps plus button in `FoodJournalView` -> `showMealLog = true`
2. `.sheet(isPresented: $showMealLog)` presents `MealLogSheetContent(homeViewModel: viewModel, selectedDate: selectedDate)`
3. `MealLogSheetContent` creates a `MealLogViewModel` as `@StateObject` and embeds `MealLogView` in a `NavigationStack`
4. `MealLogView` dismisses itself when `viewModel.shouldDismiss` becomes true (after save) or when back is tapped
5. After dismiss, user lands back in `FoodJournalView`

### Key Constraint
HomeView pushes FoodJournalView via `NavigationStack` + `navigationDestination`. To ensure the user lands on FoodJournalView after closing MealLogView (not HomeView), we need the tab switch + navigation push to happen **before or coincident with** opening the MealLogSheet. The cleanest approach: open MealLogSheetContent directly from HomeView with a `.sheet`, and in the `onDismiss` callback of that sheet, navigate to FoodJournalView by setting `showLogMeal = true` (which navigates HomeView's NavigationStack to FoodJournalView).

## Architecture Changes

### Approach: Sheet from HomeView + NavigationStack push on dismiss
1. HomeView presents `MealLogSheetContent` directly via `.sheet` (no tab switching needed)
2. When that sheet is dismissed (via save or back), the `onDismiss` of the sheet sets `showLogMeal = true`, pushing FoodJournalView onto the NavigationStack
3. The user lands on FoodJournalView with their full history visible
4. This avoids tab management complexity entirely and stays within the existing `NavigationStack` pattern

**Why this works**: `MealLogSheetContent` is a self-contained view that only depends on `HomeViewModel` and a `selectedDate`. HomeView already owns a `HomeViewModel` (`foodJournalViewModel`), so it can present this sheet directly.

## Implementation Steps

### Phase 1: Add drag overlay state and sheet to HomeView

**Step 1.1 — Add state variables to HomeView** (File: `WellPlate/Features + UI/Home/Views/HomeView.swift`)
- Action: Add two new `@State` variables inside the `// MARK: - State` block (after line 20):
  ```swift
  @State private var showMealLogFromDrag = false
  @State private var dragOverlayOffset: CGFloat = 0
  ```
- Why: `showMealLogFromDrag` drives the `.sheet` presentation; `dragOverlayOffset` drives the drag animation
- Dependencies: None
- Risk: Low

**Step 1.2 — Attach sheet and onDismiss to HomeView's body** (File: `WellPlate/Features + UI/Home/Views/HomeView.swift`)
- Action: After the existing `.navigationDestination(isPresented: $showLogMeal)` modifier (around line 95), add:
  ```swift
  .sheet(isPresented: $showMealLogFromDrag, onDismiss: {
      showLogMeal = true
  }) {
      MealLogSheetContent(homeViewModel: foodJournalViewModel, selectedDate: Date())
  }
  ```
- Why: Presenting the sheet directly from HomeView means we control `onDismiss`. When MealLogSheetContent is dismissed (save or back), `onDismiss` fires and pushes FoodJournalView.
- Dependencies: Step 1.1
- Risk: Low — uses the exact same `MealLogSheetContent` the plus button in FoodJournalView uses

**Step 1.3 — Add `DragToLogOverlay` component call to HomeView body** (File: `WellPlate/Features + UI/Home/Views/HomeView.swift`)
- Action: Wrap the `NavigationStack`'s contents in a `ZStack` and add the overlay at the bottom. Change line 31–102 from:
  ```swift
  NavigationStack {
      ScrollView { ... }
      ...
      .navigationBarHidden(true)
  }
  ```
  To:
  ```swift
  NavigationStack {
      ZStack(alignment: .bottom) {
          ScrollView { ... }
          ...
          DragToLogOverlay(
              offset: $dragOverlayOffset,
              onThresholdReached: {
                  showMealLogFromDrag = true
              }
          )
          .padding(.bottom, 0) // sits above tab bar naturally via safe area
      }
      .navigationBarHidden(true)
  }
  ```
- Why: Overlay floats above the scroll content, always visible, below the tab bar safe area
- Dependencies: Steps 1.1, 1.2, Phase 2
- Risk: Low

### Phase 2: Create DragToLogOverlay component

**Step 2.1 — Create new file** (File: `WellPlate/Features + UI/Home/Components/DragToLogOverlay.swift`)
- Action: Create a new Swift file with the following complete implementation:

```swift
import SwiftUI

// MARK: - DragToLogOverlay
// A subtle bottom-of-screen pill that responds to an upward drag gesture.
// When the user drags up past the threshold, `onThresholdReached` is called.

struct DragToLogOverlay: View {
    @Binding var offset: CGFloat
    let onThresholdReached: () -> Void

    // How far up (in points) the user must drag to trigger
    private let dragThreshold: CGFloat = 60

    var body: some View {
        VStack(spacing: 6) {
            // Drag handle indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 4)

            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.primary.opacity(0.7))

                Text("drag up to log a meal")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: -4)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        // Lift the pill as the user drags up
        .offset(y: -max(0, -offset))
        // Scale up very subtly as drag progresses
        .scaleEffect(
            1 + min(0.03, max(0, -offset) / dragThreshold * 0.03),
            anchor: .bottom
        )
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    // Only respond to upward drags
                    let translation = value.translation.height
                    if translation < 0 {
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
                            offset = translation
                        }
                        // Haptic tick at half-threshold
                        if -translation >= dragThreshold / 2 && -offset < dragThreshold / 2 + 1 {
                            HapticService.selectionChanged()
                        }
                    }
                }
                .onEnded { value in
                    let translation = value.translation.height
                    if -translation >= dragThreshold {
                        // Trigger meal logging
                        HapticService.impact(.medium)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = 0
                        }
                        onThresholdReached()
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            offset = 0
                        }
                    }
                }
        )
    }
}

// MARK: - Preview

#Preview("Drag Overlay") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        DragToLogOverlay(offset: .constant(0)) {}
    }
}
```
- Why: Encapsulates all gesture logic and animation in a single reusable component. Uses only project patterns (`AppColors`, `appShadow`, `HapticService`).
- Dependencies: None (standalone component)
- Risk: Low

### Phase 3: Handle the "land on FoodJournalView" requirement

The `onDismiss` approach in Step 1.2 handles this automatically. When `showMealLogFromDrag` becomes `false` (sheet dismissed), the closure fires `showLogMeal = true`, which triggers `.navigationDestination(isPresented: $showLogMeal)` and pushes `FoodJournalView` onto the NavigationStack.

**Step 3.1 — Verify foodJournalViewModel is bound before sheet is shown** (File: `WellPlate/Features + UI/Home/Views/HomeView.swift`)
- Action: Confirm `foodJournalViewModel.bindContext(modelContext)` is called in `.onAppear` (it already is, at line 105). No changes needed.
- Why: `MealLogSheetContent` accepts `homeViewModel: foodJournalViewModel`. The context must be bound for saving to work.
- Dependencies: None
- Risk: Low

**Step 3.2 — Ensure FoodJournalView navigation destination passes the same viewModel** (File: `WellPlate/Features + UI/Home/Views/HomeView.swift`)
- Action: Verify line 96 already passes `foodJournalViewModel`:
  ```swift
  .navigationDestination(isPresented: $showLogMeal) {
      FoodJournalView(viewModel: foodJournalViewModel)
  }
  ```
  This is already the case. No changes needed.
- Why: After the sheet dismisses and `showLogMeal = true` is set, FoodJournalView opens with the same ViewModel that was used for logging. The new entry will already be visible.
- Dependencies: None
- Risk: Low

### Phase 4: Overlay placement and safe area

**Step 4.1 — Adjust ZStack and padding** (File: `WellPlate/Features + UI/Home/Views/HomeView.swift`)
- Action: The overlay sits inside the NavigationStack's ZStack at `.bottom` alignment. The tab bar provides its own safe area inset automatically via the TabView. Add `.ignoresSafeArea(.keyboard)` to the ZStack so the overlay doesn't jump when a keyboard appears in other views.
  ```swift
  ZStack(alignment: .bottom) {
      ScrollView { ... }
          .padding(.bottom, 32) // existing
      // other modifiers...
      DragToLogOverlay(...)
  }
  .ignoresSafeArea(.keyboard)
  ```
- Why: Without this, on iOS 26 with `SWIFT_APPROACHABLE_CONCURRENCY`, any keyboard interaction from a sibling view could shift the overlay.
- Dependencies: Step 1.3
- Risk: Low

### Phase 5: Polish — opacity hint animation

**Step 5.1 — Add breathing animation to hint label** (File: `WellPlate/Features + UI/Home/Components/DragToLogOverlay.swift`)
- Action: Add a `@State private var hintOpacity: Double = 1.0` and an `onAppear` that runs a repeating opacity animation on the hint text:
  ```swift
  @State private var hintOpacity: Double = 0.6

  // inside body, on the Text label:
  Text("drag up to log a meal")
      ...
      .opacity(hintOpacity)
      .onAppear {
          withAnimation(
              .easeInOut(duration: 1.8)
              .repeatForever(autoreverses: true)
          ) {
              hintOpacity = 1.0
          }
      }
  ```
- Why: A gentle breathing effect draws attention without being garish. Starts at 0.6 and pulses to 1.0.
- Dependencies: Step 2.1
- Risk: Low — purely cosmetic

## Full Modified HomeView.swift (Diff Summary)

Lines added/changed in `HomeView.swift`:
- Lines 20–21: Add `@State private var showMealLogFromDrag = false` and `@State private var dragOverlayOffset: CGFloat = 0`
- Lines 31–102: Wrap `ScrollView { ... }` in `ZStack(alignment: .bottom)`, append `DragToLogOverlay(...)` as last ZStack child
- After line 97 (existing `.navigationDestination(isPresented: $showLogMeal)`): Add `.sheet(isPresented: $showMealLogFromDrag, onDismiss: { showLogMeal = true })` presenting `MealLogSheetContent`

## Testing Strategy

- **Manual test 1**: Open HomeView. Drag overlay upward ~70pt. Verify `MealLogSheetContent` opens.
- **Manual test 2**: Open MealLogSheetContent from overlay. Type a food, tap "Save & Reflect". Verify sheet closes and FoodJournalView opens (not HomeView).
- **Manual test 3**: Open MealLogSheetContent from overlay. Tap the back chevron without saving. Verify sheet closes and FoodJournalView opens.
- **Manual test 4**: Drag overlay upward less than 60pt, release. Verify overlay snaps back with no sheet opening.
- **Manual test 5**: Drag overlay downward. Verify nothing happens (only upward drags are handled).
- **Manual test 6**: Confirm normal scroll in HomeView is unaffected (drag on rest of scroll view still scrolls).
- **Manual test 7**: Verify haptic fires at 30pt (half-threshold) and again at trigger.
- **Manual test 8**: Open plus button in FoodJournalView normally. Verify no regression in that flow.

## Risks & Mitigations

- **Risk**: `onDismiss` of the sheet fires even when the user dismisses via the system swipe-down gesture. This is intended — all dismissals should land on FoodJournalView.
  - Mitigation: This is the desired behavior per requirements. No extra handling needed.

- **Risk**: If the user already navigated to FoodJournalView (via another path) and `showLogMeal` is already `true`, calling `showLogMeal = true` again would be a no-op (same value). No double-push.
  - Mitigation: SwiftUI's `@State` binding change detection handles this. No action needed.

- **Risk**: The `DragGesture` on the overlay competes with the `ScrollView`'s gesture recognizer.
  - Mitigation: The overlay is **outside** the ScrollView (as a ZStack sibling). Its gesture only fires when the user starts dragging on the pill itself, not the scroll content. `minimumDistance: 8` prevents accidental triggers from taps.

- **Risk**: On very small screens, the overlay might overlap lower content (StressInsightCard).
  - Mitigation: The ScrollView already has `.padding(.bottom, 32)` and the overlay height is approximately 60pt. If needed, increase bottom padding to 80pt.

- **Risk**: The breathing animation (`repeatForever`) continues even when not on screen.
  - Mitigation: SwiftUI pauses animations on views not in the hierarchy. The animation runs only while HomeView is the active tab. Acceptable.

## Success Criteria
- [ ] Bottom overlay is visible on HomeView at all times when on the Home tab
- [ ] Upward drag of >= 60pt on the overlay opens `MealLogSheetContent`
- [ ] Drag < 60pt snaps the overlay back without opening the sheet
- [ ] After any dismissal of the meal log sheet (save or back), user sees FoodJournalView
- [ ] Normal HomeView scroll behavior is unaffected
- [ ] Two haptic events fire: a tick at 30pt drag and an impact at trigger
- [ ] Breathing opacity animation on hint label
- [ ] No regressions in FoodJournalView plus button flow
- [ ] Overlay uses only existing design tokens (`AppColors`, `appShadow`, `HapticService`)
