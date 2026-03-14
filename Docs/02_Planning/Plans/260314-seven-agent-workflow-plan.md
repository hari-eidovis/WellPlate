# Implementation Plan: 7-Agent Brainstorm-to-Testing Workflow

**Date**: 2026-03-14
**Status**: Implemented
**Goal**: Extend `.codex` into a strict 7-step workflow for this iOS repository.

---

## Overview

The repository already has the first three workflow stages as `.codex` agents: `brainstorm`, `planner`, and `plan-auditor`. The requested workflow adds four more explicit stages: `resolve-audit`, `checklist-preparer`, `implementer`, and `tester`.

This implementation must be repository-specific. The previous draft assumed documentation trees that do not exist here. The actual workflow needs to use the materials that do exist:
- `Docs/02_Planning/Brainstorming/`
- `Docs/02_Planning/Specs/`
- `Docs/05_Audits/Code/`
- `WellPlate.xcodeproj`
- the application and extension source trees

The project also has four native targets that matter to verification:
- `WellPlate`
- `ScreenTimeMonitor`
- `ScreenTimeReport`
- `WellPlateWidget`

Shared schemes currently exist for:
- `WellPlate`
- `ScreenTimeMonitor`
- `ScreenTimeReport`

`WellPlateWidget` has a target in the project but no shared scheme, so the tester contract must account for target-level builds when widget-related code changes.

---

## Target Workflow

| Step | Agent | Purpose | Model Tier | Primary Output | Gate |
|---|---|---|---|---|---|
| 1 | `brainstorm` | Explore options, risks, and alternatives | High intelligence | `Docs/02_Planning/Brainstorming/...` | None |
| 2 | `planner` | Convert chosen direction into an implementation plan | Medium intelligence | `Docs/02_Planning/Specs/YYMMDD-[feature].md` | Must consume brainstorm doc |
| 3 | `plan-auditor` | Critique the plan for gaps, risks, and contradictions | Medium-high intelligence | `Docs/05_Audits/Code/YYMMDD-[feature]-audit.md` | Must consume plan doc |
| 4 | `resolve-audit` | Present audit issues and ask user to resolve each decision | Medium intelligence | `Docs/02_Planning/Specs/YYMMDD-[feature]-RESOLVED.md` | User approval required |
| 5 | `checklist-preparer` | Convert resolved audit decisions into an execution checklist | Medium intelligence | `Docs/02_Planning/Specs/CHECKLIST-YYMMDD-[feature].md` | Must consume resolved artifact |
| 6 | `implementer` | Execute checklist items and make code changes | Medium intelligence | Code changes + concise completion summary | Must consume checklist |
| 7 | `tester` | Verify builds, tests, and regressions for app and affected extensions | Medium intelligence | Verification summary | Must consume checklist and implementation diff |

---

## Current State

### Rewritten core agents

- `.codex/agents/brainstorm/SKILL.md`
- `.codex/agents/planner/SKILL.md`
- `.codex/agents/plan-auditor/SKILL.md`

These files were rewritten to stop depending on missing paths such as `Docs/01_Transcripts/`, `Docs/04_Decisions/`, and `Docs/06_Maintenance/Patterns/`. They now use existing planning docs, `WellPlate.xcodeproj`, shared schemes, and source files as the primary research inputs.

### Existing but outside the required seven stages

- `.codex/agents/code-reviewer/SKILL.md`

`code-reviewer` remains useful as an optional post-implementation review gate, but it should stay separate from the required seven-stage workflow.

---

## Implementation Plan

### Phase 1: Normalize Workflow Contracts

1. Use a single feature-artifact path tree under `Docs/02_Planning/Specs/` for the plan, resolved plan, and checklist.
2. Keep brainstorming in `Docs/02_Planning/Brainstorming/`.
3. Keep audit reports in `Docs/05_Audits/Code/`.
4. Make every stage consume the previous stage's explicit artifact path rather than infer it from multiple folders.

Recommended artifact contract:
- Step 1: `Docs/02_Planning/Brainstorming/YYMMDD-[feature]-brainstorm.md`
- Step 2: `Docs/02_Planning/Specs/YYMMDD-[feature].md`
- Step 3: `Docs/05_Audits/Code/YYMMDD-[feature]-audit.md`
- Step 4: `Docs/02_Planning/Specs/YYMMDD-[feature]-RESOLVED.md`
- Step 5: `Docs/02_Planning/Specs/CHECKLIST-YYMMDD-[feature].md`

Reason:
- This keeps the strict handoff unambiguous and matches the repository's existing spec/checklist conventions.

### Phase 2: Update the Existing Three Core Agents

1. Refine `brainstorm` so it researches from:
   - the user request
   - related brainstorming/spec/audit docs
   - `WellPlate.xcodeproj`
   - relevant app, widget, and Screen Time source files
2. Refine `planner` so it:
   - writes plans into `Docs/02_Planning/Specs/`
   - records impacted targets and schemes
   - includes unresolved decisions for the auditor
3. Refine `plan-auditor` so it:
   - reads plans from `Docs/02_Planning/Specs/`
   - checks target coverage and build/test feasibility
   - emits explicit decision requests for Step 4

### Phase 3: Add Four New Agents

1. Create `.codex/agents/resolve-audit/SKILL.md`
2. Create `.codex/agents/checklist-preparer/SKILL.md`
3. Create `.codex/agents/implementer/SKILL.md`
4. Create `.codex/agents/tester/SKILL.md`

Required behavior for each:

`resolve-audit`
- Reads the audit report and original spec.
- Separates findings into:
  - accept and fix
  - reject with rationale
  - defer explicitly
- Must always ask the user before choosing between competing recommendations or changing scope.
- Writes `...-RESOLVED.md` only after the required user decisions are captured.

`checklist-preparer`
- Reads the resolved spec.
- Produces a flat execution checklist with file-level steps.
- Removes superseded or rejected audit findings.
- Includes build/test verification items specific to affected targets.

`implementer`
- Reads the approved checklist and relevant source files.
- Executes tasks in order.
- Escalates blockers instead of making product or architecture decisions independently.
- Returns a concise summary of completed, skipped, and blocked items.

`tester`
- Reads the checklist and implementation diff.
- Uses explicit Xcode schemes, targets, and destinations.
- Distinguishes automated tests from build-only verification.
- Reports passed, failed, and unverified coverage areas.

### Phase 4: Add Workflow Documentation

Create workflow documentation in `.codex/` describing:
- when each agent is invoked
- required input artifact for each step
- required output artifact for each step
- blocking conditions
- the Step 4 user-approval rule
- the Step 7 iOS build/test contract

Implemented as:
- `.codex/WORKFLOW.md`
- `.codex/README.md`

This is necessary because prompt files alone do not enforce sequence or repository-specific verification.

### Phase 5: Dry Run the Workflow

Use one real feature request and run the process end to end:
1. `brainstorm`
2. `planner`
3. `plan-auditor`
4. `resolve-audit` with explicit user answers
5. `checklist-preparer`
6. `implementer`
7. `tester`

Capture what breaks:
- missing artifact references
- inconsistent naming
- duplicate responsibilities
- weak approval gates
- missing target coverage

This dry run has not been executed yet.

---

## Agent Design Notes

### Model Tier Mapping

Recommended mapping:
- `brainstorm`: highest available reasoning model
- `planner`: medium reasoning model
- `plan-auditor`: medium-high reasoning model
- `resolve-audit`: medium reasoning model with strict user-approval instructions
- `checklist-preparer`: medium reasoning model
- `implementer`: medium reasoning model
- `tester`: medium reasoning model

Reason:
- The heaviest reasoning is most valuable during divergent ideation and critical plan review, not during checklist generation or execution.

### Approval Rule for Step 4

This is the workflow rule that must not be weakened:
- If an audit finding affects scope, architecture, tradeoffs, acceptance criteria, or ownership boundaries, `resolve-audit` must ask the user before finalizing the resolved artifact.
- If an audit finding is purely mechanical, the agent may propose a default resolution, but it must still present it as a decision for confirmation before writing the final resolved spec.

### iOS Verification Rule for Step 7

This repository is not generic.

The tester contract must verify the Xcode project explicitly:
- Always verify the `WellPlate` shared scheme.
- If the change touches Screen Time monitor code or shared code consumed by it, verify `ScreenTimeMonitor`.
- If the change touches Screen Time report code or shared code consumed by it, verify `ScreenTimeReport`.
- If the change touches widget code or shared widget data, verify the `WellPlateWidget` target because there is no shared scheme for it.
- Use an explicit simulator or generic iOS Simulator destination instead of assuming defaults.
- If there are no real test bundles, report that only build verification was performed.

---

## Risks

- If the three existing prompts are not rewritten, the workflow will still chase missing documentation instead of inspecting the Xcode project and source.
- If plans, resolved specs, and checklists are split across different folders, later stages will guess the wrong input artifact.
- If the tester prompt does not require explicit Xcode scheme and target coverage, extension regressions can slip through unnoticed.
- If `resolve-audit` is not strict enough, it will collapse into autonomous replanning and violate the user-approval rule.

---

## Success Criteria

- Seven named agents exist under `.codex/agents/`.
- Matching workflow skill files exist under `.codex/skills/`.
- The three existing prompts no longer depend on nonexistent docs.
- Plans, resolved specs, and checklists use one feature-artifact path tree under `Docs/02_Planning/Specs/`.
- Step 4 always requires user approval before finalizing decisions from the audit.
- Step 7 has explicit Xcode build/test coverage rules for `WellPlate`, `ScreenTimeMonitor`, `ScreenTimeReport`, and `WellPlateWidget` when relevant.
- Workflow documentation exists in `.codex`.

---

## Recommended Build Order

1. Rewrite `brainstorm`, `planner`, and `plan-auditor`.
2. Add `resolve-audit`.
3. Add `checklist-preparer`.
4. Add `implementer`.
5. Add `tester`.
6. Write `.codex` workflow documentation.
7. Dry run the chain on a real feature.
