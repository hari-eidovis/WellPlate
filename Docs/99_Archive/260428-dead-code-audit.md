# Dead Code Audit — WellPlate

**Date:** 2026-04-28
**Branch:** `UI-component-addition-and-refactor`
**Scope:** `WellPlate/` (~216 Swift files), plus `Resources/Assets.xcassets/` and `Resources/MockData/`
**Method:** Grep-based reachability analysis. A symbol is treated as dead only if it has zero references outside its own declaration (or appears only inside its own file's commented blocks). Asset reachability checked via `Image("name")` / `UIImage(named:)` / matchedGeometry IDs.

> ⚠️ All claims below were spot-verified by re-running grep at audit time. Counts that disagreed with an earlier draft were corrected (e.g. `water_bg`, `Group 9–18` are **not** dead — see §6).

---

## Summary

| # | Category                         | Confirmed dead | Action |
|---|----------------------------------|----------------|--------|
| 1 | Files (whole-file dead)          | 2              | Delete |
| 2 | Commented-out blocks (>5 lines)  | 1              | Delete inline |
| 3 | Image asset sets                 | 7              | Delete from `.xcassets` |
| 4 | Stale filename (live type)       | 1              | Rename file |
| 5 | Unused types / funcs / props     | 0 found        | — |
| 6 | Unused enum cases                | 0 (Phase-2 placeholders are intentional) | — |
| 7 | Unused mock JSON fixtures        | 0              | — |
| 8 | TODO/FIXME marked "remove"       | 0              | — |

Total: **~125 lines of code + 7 asset directories** safely removable.

---

## 1. Whole-file dead code

### 1.1 `Features + UI/Tab/BurnView_REMOVE.swift`
- **Size:** 4 lines, comments only.
- **Content:**
  ```
  // BurnView.swift (Tab/) — superseded.
  // The real BurnView lives at: Features + UI/Burn/Views/BurnView.swift
  // This file can be removed from the Xcode project.
  ```
- **Evidence:** Filename literally encodes the disposition. Verified no `BurnView_REMOVE` references anywhere.
- **Action:** Delete the file. With `PBXFileSystemSynchronizedRootGroup`, no pbxproj edit is needed.

### 1.2 `Features + UI/Home/Components/QuickAddCard.swift`
- **Size:** 69 lines — every line is `//`-prefixed; the entire `struct QuickAddCard: View` body is commented out.
- **Evidence:** No `QuickAddCard(` instantiation anywhere in the codebase (live or commented). Superseded by the active food-entry UI in `MealLogView` / `FoodJournalView`.
- **Action:** Delete the file.

---

## 2. Commented-out code blocks (>5 lines)

### 2.1 `Features + UI/Home/Components/CalorieHeroCard.swift:14–67`
- **Size:** 54 commented lines (an old calorie-header + progress-bar layout).
- **Status:** The file is otherwise live (`CalorieHeroCard` is rendered from `HomeView`); only this block is dead.
- **Evidence:** `grep -c "^//" CalorieHeroCard.swift` → 53 (out of 279 total lines). The active layout starts at line 69 ("Macro columns").
- **Action:** Delete lines 14–67 in place. Keep the file.

---

## 3. Unused image / symbol assets in `Resources/Assets.xcassets/`

Asset is "live" if any Swift file references it via `Image("name")`, `UIImage(named: "name")`, or `matchedGeometryEffect(id: "name", ...)` against a value that maps to an image. Verified with:

```bash
grep -rn '"<name>"' WellPlate --include="*.swift"
```

| # | Asset | Path | Refs | Notes |
|---|-------|------|------|-------|
| 1 | `Good-Onboard.imageset`   | `Assets.xcassets/Good-Onboard.imageset/`   | 0 | Old onboarding character |
| 2 | `Groovy-Onboard.imageset` | `Assets.xcassets/Groovy-Onboard.imageset/` | 0 | Old onboarding character |
| 3 | `Lemon-Onboard.imageset`  | `Assets.xcassets/Lemon-Onboard.imageset/`  | 0 | Old onboarding character |
| 4 | `Image.imageset` | `Assets.xcassets/Image.imageset/` | 0 | Generic placeholder, no `Image("Image")` anywhere |
| 5 | `pill.imageset` | `Assets.xcassets/pill.imageset/` | 0 | Only `Image(systemName: "pill")` (SF Symbol) and a `matchedGeometryEffect(id: "pill")` exist — the **bitmap asset** is unreferenced |
| 6 | `colorful-vegetable-stir-fry-black-bowl.imageset` | same | 0 | Unused food image |
| 7 | `beaker.symbolset` | `Assets.xcassets/beaker.symbolset/` | 0 | Custom SF symbol, never used (no `"beaker"` string anywhere) |

**Action:** Delete these 7 imageset/symbolset directories from `Assets.xcassets/`.

---

## 4. Stale filename (file is live, name is wrong)

### 4.1 `Features + UI/Tab/MockDataDebugCard.swift` contains `MockModeDebugCard`
- The struct inside the file is `MockModeDebugCard` (used at `ProfileView.swift:167`).
- The file's own header comment states it "replaces both NutritionSourceDebugCard and MockDataDebugCard."
- The filename still says `MockDataDebugCard.swift`.
- **Action:** Rename file → `MockModeDebugCard.swift`. Not strictly dead code, but it confuses search.

---

## 5. Verified-live items (corrections to an earlier draft)

These looked dead at first glance but are actively referenced. Listing them so future audits don't repeat the mistake:

| Asset / symbol | Where it's used |
|----------------|-----------------|
| `water_bg.imageset` | `HydrationCard.swift:28`, `LiquidGaugeTile.swift:170` |
| `Group 9.imageset`  | `App/SplashScreenView.swift:104` |
| `Group 10.imageset` | `App/SplashScreenView.swift:86` |
| `Group 11.imageset` | `App/SplashScreenView.swift:68` |
| `Group 16.imageset` | `App/SplashScreenView.swift:92` |
| `Group 17.imageset` | `App/SplashScreenView.swift:98` |
| `Group 18.imageset` | `App/SplashScreenView.swift:80` |
| `Today.imageset`    | `App/SplashScreenView.swift:74` (separate from the many `"Today"` string labels) |
| `bowl.imageset`     | `ContextualActionBar.swift:180` |
| `stomach.imageset`  | `Models/SymptomDefinition.swift:13` |
| `logo.imageset`     | Splash + branding (8 refs) |

The Splash screen renders the project's name "Today, GroovyLemon, Group ..." characters letter-by-letter, which is why the `Group N` assets are alive despite their generic names.

---

## 6. Phase-2 placeholders (intentional, not dead)

`Models/ResetType.swift:16–17` keeps two enum cases commented out with the note `// Phase 2 additions (not implemented yet)` (`vocalEntrainment`, `grounding`). Leave as-is — they are roadmap markers, not stale code.

---

## 7. Things scanned and found clean

These categories were checked and produced **no high-confidence findings**, so they're listed for transparency rather than action:

- **`@Model` types** — every type registered in `WellPlateApp.swift`'s SwiftData schema list (`FoodCache`, `FoodLogEntry`, `WellnessDayLog`, `UserGoals`, `StressReading`, `StressExperiment`, `InterventionSession`, `FastingSchedule`, `FastingSession`, `JournalEntry`, `SymptomEntry`, `SupplementEntry`, `AdherenceLog`) is referenced by at least one view or service.
- **ViewModels** — `HomeViewModel`, `BurnViewModel`, `StressViewModel`, `GoalsViewModel`, `SleepViewModel`, `WellnessCalendarViewModel`, `MealLogViewModel`, `AI15DayReportViewModel` all instantiated.
- **Protocols** — `NutritionServiceProtocol`, `NutritionProvider`, `HealthKitServiceProtocol`, `SpeechTranscriptionServiceProtocol`, `BarcodeProductServiceProtocol` all have ≥1 conformer and ≥1 caller.
- **Mock JSON fixtures** — every file in `Resources/MockData/` is registered in `MockResponseRegistry`.
- **`#Preview` / `PreviewProvider`** — only one legacy `PreviewProvider` (`SplashScreenView.swift:199`); rest use the modern `#Preview` macro. Not dead, just stylistically older.

---

## 8. Likely false positives — verify manually before deleting

- **`pill.imageset`** (item 3.5 above): the asset name collides with SF Symbol `pill` and a `matchedGeometryEffect(id: "pill")` token. Grep cannot tell those apart from a true asset reference without context, but a manual read of `ContextualActionBar.swift:89` and `ProfileView.swift:1209` confirms neither uses the bitmap. Still, eyeball before deleting.
- **`Image.imageset`** (item 3.4): the bare name `Image` is the SwiftUI type — grep returns thousands of false matches. The check used `Image("Image")` / `UIImage(named: "Image")` exactly, both empty. Asset name is so generic that a future contributor might accidentally re-add it; consider deleting now.
- **Reflection / Codable / SwiftData**: types instantiated only via `JSONDecoder` or SwiftData model containers won't appear in grep as constructor calls. Spot-checks of `NutritionalInfo`, `NutritionAnalysisRequest`, and the `@Model` types showed they all *also* have direct call sites, so this risk did not materialize, but keep it in mind for future audits.

---

## 9. Recommended deletion order

Safest first; each step is independent.

1. **Delete** `Features + UI/Tab/BurnView_REMOVE.swift` — comments-only, name asks to be deleted.
2. **Delete** `Features + UI/Home/Components/QuickAddCard.swift` — fully commented-out, no references.
3. **Edit** `Features + UI/Home/Components/CalorieHeroCard.swift` — remove lines 14–67.
4. **Delete** these 7 directories under `Resources/Assets.xcassets/`:
   `Good-Onboard.imageset`, `Groovy-Onboard.imageset`, `Lemon-Onboard.imageset`, `Image.imageset`, `pill.imageset`, `colorful-vegetable-stir-fry-black-bowl.imageset`, `beaker.symbolset`.
5. **Rename** `Features + UI/Tab/MockDataDebugCard.swift` → `MockModeDebugCard.swift` (filename hygiene; no code change).
6. After each step run the four build commands from `CLAUDE.md` and confirm clean compile before moving on.

---

## Appendix — grep commands used

```bash
# Asset usage check (run per asset name)
grep -rn '"<asset-name>"' WellPlate --include="*.swift"

# SwiftData schema discovery
grep -n "Schema\|ModelContainer" WellPlate/App/WellPlateApp.swift

# Comment-density check (commented-out blocks)
grep -c "^//" "<file>"

# Type instantiation check
grep -rn "<TypeName>(\|struct <TypeName>\|class <TypeName>" WellPlate --include="*.swift"
```
