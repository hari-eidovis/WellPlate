# Implementation Plan: Codex Workflow Hardening and Automation

## Overview
This plan upgrades the repository's `.codex` workflow from a documented process into a repeatable, tool-backed system with explicit agent guidance, safe execution defaults, deterministic Xcode verification, and measurable rollout checkpoints. The work is intentionally phased so the team can stabilize repo-local guidance and CI build coverage before deciding whether to add Xcode test-target wiring, agentic PR review, or broader automation.

## Inputs
- User request: improve the workflow in `.codex` using the research document at `Docs/09_Mischalleneous/deep-research-report.md`
- Brainstorm artifact: workflow skipped; using the research document directly plus current repository context

## Impacted Targets
- `WellPlate` - primary app scheme used in the canonical verification contract and any future test wiring
- `ScreenTimeMonitor` - extension scheme included in deterministic build verification
- `ScreenTimeReport` - extension scheme included in deterministic build verification
- `WellPlateWidget` - widget target requires explicit target-level build coverage because no shared scheme exists

## Impacted Files
- `.codex/WORKFLOW.md` - tighten the workflow contract so it references the new repo-native guidance, prompt sources, and verification scripts
- `.codex/README.md` - document how developers invoke the workflow locally and which artifacts are authoritative
- `AGENTS.md` - add repository-root Codex guidance so the agent consistently loads the stage order, approval gate, and canonical Xcode commands
- `.codex/config.toml` - define safe default sandbox and approval behavior plus task-specific profiles
- `.codex/prompts/brainstorm.md` - add a canonical non-interactive prompt for the brainstorm stage
- `.codex/prompts/planner.md` - add a canonical non-interactive prompt for the planner stage
- `.codex/prompts/plan-auditor.md` - add a canonical non-interactive prompt for the audit stage
- `.codex/prompts/resolve-audit.md` - add a canonical non-interactive prompt for audit resolution
- `.codex/prompts/checklist-preparer.md` - add a canonical non-interactive prompt for checklist generation
- `.codex/prompts/implementer.md` - add a canonical non-interactive prompt for implementation runs
- `.codex/prompts/tester.md` - add a canonical non-interactive prompt for verification runs
- `.codex/skills/*/SKILL.md` - update or trim stage skill files so they reference one canonical source of truth and do not drift from prompt files
- `.codex/agents/*/SKILL.md` - update or trim duplicate stage skill files if the repo keeps both `skills` and `agents`
- `scripts/codex/run_stage.sh` - add a local runner for `codex exec` with profile selection and artifact-oriented invocation
- `scripts/ci/build_all.sh` - codify the existing Xcode build contract for app, extensions, and widget
- `scripts/ci/check_codex_prereqs.sh` - add a small smoke check for required files, config, and artifact paths
- `.github/workflows/codex-pr-gates.yml` - add deterministic CI gates for builds and optional non-blocking Codex review automation
- `WellPlate.xcodeproj/project.pbxproj` - only if the repo decides to wire `WellPlateTests` into the Xcode project as part of this effort
- `WellPlate.xcodeproj/xcshareddata/xcschemes/WellPlate.xcscheme` - only if test execution is added to the shared scheme

## Requirements
- Preserve the existing seven-stage workflow and the Step 4 user-approval gate as the repository's non-negotiable control point.
- Make Codex workflow-aware at repo load time through versioned guidance rather than relying on ad hoc session prompts.
- Default local Codex operation to least-privilege behavior (`workspace-write` plus approval prompts) and keep read-only profiles available for planning and audit stages.
- Provide one canonical source for stage instructions so `.codex/skills` and `.codex/agents` cannot silently diverge.
- Convert the current Xcode verification contract into runnable scripts and CI checks that cover `WellPlate`, `ScreenTimeMonitor`, `ScreenTimeReport`, and `WellPlateWidget`.
- Report automated test coverage truthfully: `WellPlateTests` exists on disk, but there is currently no test target in `WellPlate.xcodeproj`, so initial automation must be build-only unless test wiring is explicitly approved.
- Add rollout metrics so the workflow can be judged by adoption, first-pass build success, CI iteration count, and stage usage rather than anecdotal feedback.

## Assumptions
- The repo currently has no committed `AGENTS.md`, `.codex/config.toml`, `.github/workflows`, or Codex/CI helper scripts.
- The existing `.codex/skills` and `.codex/agents` directories are both present and should be treated as a drift risk until a canonical source is chosen.
- The first milestone should not change product behavior in the iOS app; it should improve developer workflow and verification only.
- GitHub Actions is an acceptable first CI target unless the user prefers Xcode Cloud as the primary gate.
- Build-only verification is acceptable for milestone one if the plan documents the current absence of an Xcode-wired test target.

## Implementation Steps
1. **Codify Repository-Level Agent Guidance**
   - Files: `AGENTS.md`, `.codex/WORKFLOW.md`, `.codex/README.md`
   - Action: Add root-level Codex instructions, align the repo workflow docs with the seven-stage contract, and document how artifact paths, approval gates, and canonical Xcode commands are discovered.
   - Why: The research report's highest-leverage recommendation is to make Codex workflow-aware through first-class repo guidance instead of relying on manual context loading.
   - Dependencies: Existing `.codex/WORKFLOW.md`; confirmed artifact path conventions under `Docs/02_Planning` and `Docs/05_Audits/Code`
   - Risk: Low

2. **Establish Safe Codex Configuration and Canonical Stage Prompts**
   - Files: `.codex/config.toml`, `.codex/prompts/*.md`, `.codex/skills/*/SKILL.md`, `.codex/agents/*/SKILL.md`
   - Action: Add repo-scoped Codex config with safe defaults and task profiles, create prompt templates for each stage, and either consolidate or synchronize existing `skills` and `agents` instructions around one canonical source.
   - Why: This turns the documented workflow into repeatable local and non-interactive execution while eliminating instruction drift.
   - Dependencies: Step 1 guidance decisions; user decision on whether prompt files or stage skill files are the canonical source
   - Risk: Medium

3. **Automate Local Stage Execution and Verification Preconditions**
   - Files: `scripts/codex/run_stage.sh`, `scripts/ci/check_codex_prereqs.sh`
   - Action: Add a small runner for `codex exec` that selects the correct profile and prompt, plus a prerequisite check that validates required guidance files, config, and artifact inputs before a stage runs.
   - Why: The workflow needs a low-friction path for developers to use the same commands locally that CI will use later.
   - Dependencies: Step 2 config and prompt files
   - Risk: Medium

4. **Convert the Xcode Verification Contract into Deterministic Build Gates**
   - Files: `scripts/ci/build_all.sh`, `.github/workflows/codex-pr-gates.yml`
   - Action: Encode the existing build matrix into scripts and a required CI workflow that builds `WellPlate`, `ScreenTimeMonitor`, `ScreenTimeReport`, and `WellPlateWidget`, and clearly marks the lane as build-only until test targets are wired.
   - Why: The current workflow already knows what must be verified; the missing piece is mechanized enforcement with consistent outputs.
   - Dependencies: Step 1 command documentation; CI platform decision; available macOS CI runner
   - Risk: Medium

5. **Decide Whether Test Wiring Is Part of the Workflow Upgrade**
   - Files: `WellPlate.xcodeproj/project.pbxproj`, `WellPlate.xcodeproj/xcshareddata/xcschemes/WellPlate.xcscheme`, `WellPlateTests/*` (validation only unless changes are needed)
   - Action: Evaluate whether to add `WellPlateTests` to the Xcode project and shared scheme during this effort or defer that work to a dedicated testing initiative.
   - Why: The research recommends evidence-based verification, but the repo currently cannot truthfully claim automated Xcode tests because the project lacks a test target.
   - Dependencies: User decision on scope; Step 4 CI baseline
   - Risk: High

6. **Add Optional Agentic Review and Workflow Metrics**
   - Files: `.github/workflows/codex-pr-gates.yml`, `.codex/README.md`, optional metrics/log artifact paths under CI
   - Action: Add a non-blocking Codex PR review lane after deterministic builds are stable, and document/report usage metrics such as stage runs, CI retries, and first-pass build success.
   - Why: PR review augmentation and workflow metrics are useful only after the deterministic lane is trustworthy; adding them earlier would mix process risk with tooling risk.
   - Dependencies: Step 4 stable CI lane; API key and secret handling decisions
   - Risk: Medium

## Testing Strategy
- Required scheme or target builds: run the scripted build matrix for `WellPlate`, `ScreenTimeMonitor`, `ScreenTimeReport`, and `WellPlateWidget` using the existing generic iOS Simulator destination.
- Manual verification: smoke-test one planning stage in read-only mode and one implementation/tester handoff in workspace-write mode to confirm prompt discovery, artifact naming, approval behavior, and script invocation.
- Automated tests, if any: none should be claimed initially unless `WellPlateTests` is added to `WellPlate.xcodeproj` and exposed through a shared scheme; until then, CI must report build-only verification.

## Unresolved Decisions
- [ ] Should `AGENTS.md` be the only top-level instruction source, or should the repo also use nested overrides inside `.codex/`?
- [ ] Which source should be canonical for stage instructions: `.codex/prompts`, `.codex/skills`, or `.codex/agents`?
- [ ] Should the first CI rollout use GitHub Actions, Xcode Cloud, or a split model with one deterministic lane and one release lane?
- [ ] Is wiring `WellPlateTests` into the Xcode project in scope for this workflow upgrade, or should it be deferred to a separate testing plan?
- [ ] Should Codex PR review comments ship in the first release of the workflow, or only after deterministic build gates have passed for a trial period?

## Success Criteria
- [ ] A new Codex session can discover the seven-stage contract, artifact paths, approval gate, and canonical Xcode commands from versioned repo files without manual restatement.
- [ ] Developers can run a stage locally through a single repo script using safe Codex defaults and stable prompt files.
- [ ] CI enforces the current four-target Xcode build contract and reports build-only status accurately when no test target is wired.
- [ ] The repo has one clearly documented canonical source for stage instructions, with no silent drift between `.codex/skills` and `.codex/agents`.
- [ ] The rollout documentation names the metrics to track and the conditions for enabling optional PR review automation.
