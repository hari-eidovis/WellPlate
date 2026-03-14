# `.codex` Workflow

This repository uses a strict 7-stage workflow for feature work.

## Stage Order

1. `brainstorm`
2. `planner`
3. `plan-auditor`
4. `resolve-audit`
5. `checklist-preparer`
6. `implementer`
7. `tester`

Do not skip from planning directly to implementation when the workflow is being followed intentionally.

## Artifact Chain

Use these paths consistently for one feature:

1. Brainstorm
   - `Docs/02_Planning/Brainstorming/YYMMDD-[feature]-brainstorm.md`
2. Plan
   - `Docs/02_Planning/Specs/YYMMDD-[feature].md`
3. Audit
   - `Docs/05_Audits/Code/YYMMDD-[feature]-audit.md`
4. Resolved plan
   - `Docs/02_Planning/Specs/YYMMDD-[feature]-RESOLVED.md`
5. Checklist
   - `Docs/02_Planning/Specs/CHECKLIST-YYMMDD-[feature].md`

Implementation uses the checklist. Testing uses the checklist plus the implementation diff.

## Repository Context

This is an Xcode project:
- Project: `WellPlate.xcodeproj`
- App target: `WellPlate`
- Extension targets:
  - `ScreenTimeMonitor`
  - `ScreenTimeReport`
  - `WellPlateWidget`

Shared schemes currently present:
- `WellPlate`
- `ScreenTimeMonitor`
- `ScreenTimeReport`

`WellPlateWidget` currently has no shared scheme, so widget verification must use a target build.

## Approval Gate

`resolve-audit` is the hard stop in the workflow.

If an audit issue affects scope, architecture, tradeoffs, or acceptance criteria:
- ask the user
- do not finalize the resolved plan until the user answers

Mechanical fixes can be proposed, but they still need confirmation before the final resolved artifact is written.

## Tester Contract

The tester must verify the Xcode project explicitly.

Required coverage rules:
- Verify `WellPlate` when app code is affected
- Verify `ScreenTimeMonitor` when monitor code or shared dependencies it consumes are affected
- Verify `ScreenTimeReport` when report code or shared dependencies it consumes are affected
- Verify `WellPlateWidget` with a target build when widget code or shared widget data is affected

Preferred build shape:

```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

If no real test bundles exist in the project or shared schemes, the tester must say that verification was build-only plus any manual checks that were actually performed.

If test files exist on disk but are not wired into the Xcode project or shared schemes, the tester must report that as unverified automated coverage rather than claiming tests passed.

## Agent Scope

- `brainstorm`: divergent thinking, options, tradeoffs, target impact
- `planner`: concrete implementation spec
- `plan-auditor`: critical review of the spec
- `resolve-audit`: user-controlled resolution of audit findings
- `checklist-preparer`: flat implementation checklist
- `implementer`: execute approved checklist items
- `tester`: run Xcode verification and summarize coverage

`code-reviewer` remains optional and separate from the required seven stages.
