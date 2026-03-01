# WellPlate Swift Playgrounds Migration Checklist

## Goal
Ship a Swift Playgrounds package that is safe for Swift Student Challenge judging:
- Offline-first
- No extension-only capabilities
- Reliable 3-minute demo flow

## What This Repo Now Has
- `Package.swift` configured for the `PlaygroundsSupport/Sources` executable target
- A full SwiftUI playground app entry:
  - `WellPlatePlaygroundsApp.swift`
  - `PlaygroundRootView.swift`
  - `IntakePlaygroundView.swift`
  - `WellnessPlaygroundView.swift`
  - `AboutPlaygroundView.swift`
  - `PlaygroundStore.swift`

## Removed / Avoided in Playground Build
- HealthKit integration and permission prompts
- FamilyControls / DeviceActivity screen-time APIs
- WidgetKit and widget timeline reload
- App extensions and entitlement-driven behavior
- Live networking dependencies for critical flow

## Remaining Work Before Final Submission Package
1. Reuse existing visual assets (`WellPlate/Resources/Assets.xcassets`) in the playground target if needed.
2. Add narration text or onboarding cards to guide judges through the intended flow.
3. Validate interaction timing: full story in under 3 minutes.
4. Trim package size and verify final zip is below challenge limits.
5. Final QA in Swift Playgrounds app:
   - cold launch
   - offline launch
   - repeated reset/run cycles

## Optional Next Iteration
If you want to preserve more of the original app logic, create a compatibility layer:
- `PlaygroundHealthService` (mocked)
- `PlaygroundScreenTimeManager` (manual-only)
- `PlaygroundWidgetBridge` (no-op)
and inject these instead of iOS capability-specific services.
