# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Main app
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build

# Extension targets
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

No Makefile or fastlane setup — use xcodebuild or Xcode IDE directly.

**Testing:** Verify via build-only (`build` command above). If test files exist but aren't wired into shared schemes, report as unverified automated coverage.

## Project Structure

The project uses `PBXFileSystemSynchronizedRootGroup` — all files placed under `WellPlate/` are automatically included in the build. **No pbxproj edits needed when adding new files.**

```
WellPlate/
├── App/                    # Entry point, RootView (Splash → Onboarding → MainTabView)
├── Core/
│   ├── AppConfig.swift     # Debug toggle: mockMode, groqModel, API timeouts
│   └── Services/           # HealthKitService, NutritionService, ScreenTimeManager, etc.
├── Features + UI/
│   ├── Home/               # Food logging, dashboard, activity rings
│   ├── Stress/             # Stress score, vitals, factor cards
│   ├── Burn/               # Calorie burn charts
│   ├── Sleep/              # Sleep analytics
│   ├── Goals/              # Goal management
│   ├── Onboarding/         # User setup
│   ├── FoodScanner/        # Barcode scanning
│   └── Tab/                # MainTabView (4 tabs)
├── Models/                 # SwiftData @Model classes + domain enums
├── Networking/
│   ├── Real/               # Groq LLM API (llama-3.3-70b-versatile)
│   └── Mock/               # MockAPIClient + JSON fixtures in Resources/MockData/
└── Shared/
    ├── Color/AppColor.swift # Design tokens, shadows, semantic colors
    ├── Components/         # Reusable SwiftUI views
    └── Extensions/         # Font, text, normalization helpers
```

**Extension targets:** `ScreenTimeMonitor.appex`, `ScreenTimeReport.appex`, `WellPlateWidget.appex`

## Architecture

**Pattern:** MVVM + Service Layer + Feature Modules

**Swift concurrency:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`. ViewModels are `@MainActor final class` with `@Published` properties. Use `async let` with private helper methods (not protocol existential references — compiler restriction).

**Navigation:**
- `RootView` manages app state transitions (splash → onboarding → main)
- `MainTabView` uses iOS 18+ `Tab` API (4 tabs: Home, Burn, Stress, Profile)
- Feature sheets use a single enum (e.g., `StressSheet`) driving one `.sheet(item:)` — do not add multiple `.sheet()` calls

**Data layer:**
- **SwiftData** for persistence — models in `WellPlate/Models/`. ModelContainer initialized in `WellPlateApp.swift` with: `FoodCache`, `FoodLogEntry`, `WellnessDayLog`, `UserGoals`, `StressReading`
- **HealthKit** for vitals and activity — all new metrics use `fetchDailyAvg()` (not sum). HRV unit: `HKUnit(from: "ms")`. Blood pressure: `.millimeterOfMercury()`
- SwiftData context accessed via `@Environment(\.modelContext)` in views

**Networking / mock mode:**
- `APIClientFactory.shared` returns real or mock client based on `AppConfig.shared.mockMode`
- Toggle mock mode in DEBUG via `AppConfig` (UserDefaults-backed)

## UI Conventions

- **Font:** `.r(.headline, .semibold)` — custom extension, not system fonts directly
- **Shadows:** `.appShadow(radius:y:)` — adaptive dark mode modifier
- **Cards:** `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)`
- **Colors:** `VitalMetric` and `BurnMetric` enums define accent colors per metric; `StressLevel` enum maps scores to semantic colors

## Development Workflow

Use `/develop <sub-command>` as the single entry point for feature development:

| Sub-command | What it does | Output |
|---|---|---|
| `brainstorm <topic>` | Creative exploration | `Docs/01_Brainstorming/YYMMDD-[slug]-brainstorm.md` |
| `strategize <topic>` | Choose one approach | `Docs/02_Planning/Specs/YYMMDD-[slug]-strategy.md` |
| `plan <topic>` | Detailed implementation plan | `Docs/02_Planning/Specs/YYMMDD-[slug]-plan.md` |
| `audit <path>` | Review plan or checklist | `Docs/03_Audits/YYMMDD-[slug]-[plan\|checklist]-audit.md` |
| `resolve <path>` | Fix audit findings | `Docs/02_Planning/Specs/...-RESOLVED.md` or `Docs/04_Checklist/...-RESOLVED.md` |
| `checklist <path>` | Step-by-step checklist | `Docs/04_Checklist/YYMMDD-[slug]-checklist.md` |
| `implement <path>` | Execute checklist | (code changes + build verification) |
| `fix` | Fix build errors | (code fixes + build verification) |

**Standalone skills**: `/brainstorm` and `/code-reviewer` also work independently outside `/develop`.

**Naming convention**: `YYMMDD-[feature-slug]-[stage].md` (e.g., `260401-wellness-calendar-plan.md`)

**Hard stop**: The `resolve` step requires user approval before proceeding. Do not skip from planning to implementation.

## Key Files

| Purpose | Path |
|---|---|
| App entry | `WellPlate/App/WellPlateApp.swift` |
| Debug config | `WellPlate/Core/AppConfig.swift` |
| HealthKit service | `WellPlate/Core/Services/HealthKitService.swift` |
| Stress ViewModel | `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` |
| Design tokens | `WellPlate/Shared/Color/AppColor.swift` |
| SwiftData models | `WellPlate/Models/` |
| Mock API data | `WellPlate/Resources/MockData/` |
| /develop orchestrator | `.claude/skills/develop/SKILL.md` |
