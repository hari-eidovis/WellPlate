# Plan Audit Report: Codex Workflow Hardening and Automation

**Audit Date:** 2026-03-16
**Plan:** `Docs/02_Planning/Specs/260316-codex-workflow-improvements.md`
**Auditor:** plan-auditor agent
**Verdict:** NEEDS REVISION

## Executive Summary

The plan correctly identifies the main workflow improvement areas: repo-level Codex guidance, safe defaults, deterministic Xcode verification, and phased rollout. It also captures an important current-state constraint: `WellPlateTests` exists on disk but is not wired into `WellPlate.xcodeproj`, so the first verification lane must report build-only coverage truthfully.

The plan is not implementation-ready yet because it leaves two control-plane decisions unresolved too late in the sequence and does not operationalize the Step 4 approval gate once stage runners and CI automation are introduced. The resulting gap is structural, not editorial: as written, the repo could add non-interactive stage execution without a reliable mechanism to stop `resolve-audit` from becoming an autonomous replanning step.

## Issues Found

### CRITICAL

#### 1. Step 4 approval gate is not enforceable in the scripted workflow

- **Location:** Implementation Steps 2-4, Testing Strategy, Success Criteria
- **Problem:** The plan adds canonical prompt files and a generic `scripts/codex/run_stage.sh` runner for stage execution, but it never defines how `resolve-audit` is prevented from running headlessly or in CI. The current repo workflow makes `resolve-audit` the hard stop that must obtain user decisions before the resolved artifact is written. As written, the new runner could execute Stage 4 the same way it executes other stages.
- **Impact:** The strict seven-stage workflow can silently degrade into autonomous replanning, which breaks the current contract in `.codex/WORKFLOW.md` and undermines the user-approval control point.
- **Recommendation:** Add an explicit execution model for Stage 4 before implementation starts. At minimum:
  - mark `resolve-audit` as local/manual only,
  - make `run_stage.sh` refuse to run `resolve-audit` without a human-authored decision artifact,
  - forbid CI from invoking Stage 4,
  - define the required input/output files for user decisions.

### HIGH

#### 2. The plan tries to eliminate instruction drift before choosing the canonical source

- **Location:** Requirements, Implementation Step 2, Unresolved Decisions
- **Problem:** The plan requires one canonical source for stage instructions, but Step 2 still proposes editing `.codex/prompts`, `.codex/skills`, and `.codex/agents` in the same milestone before that source is chosen. This is not just an open question; it directly changes the implementation shape.
- **Impact:** The repo can end up with three parallel instruction systems, more migration work, and no clear pass/fail test for "drift eliminated."
- **Recommendation:** Move the canonical-source decision ahead of Step 2. If the repo must keep compatibility layers, make that explicit:
  - choose one canonical source,
  - generate or mirror the others from it,
  - document which files are read-only compatibility wrappers.

#### 3. CI scope is under-specified because the platform decision is deferred after platform-specific deliverables are named

- **Location:** Impacted Files, Assumptions, Implementation Step 4, Unresolved Decisions
- **Problem:** The plan names `.github/workflows/codex-pr-gates.yml` as a deliverable while also leaving the CI platform unresolved between GitHub Actions, Xcode Cloud, or a split model.
- **Impact:** Step 4 can produce the wrong integration surface and force immediate rework if the repo chooses Xcode Cloud or a hybrid model.
- **Recommendation:** Split Step 4 into two distinct pieces:
  - platform-agnostic repo scripts for local/CI build verification,
  - one platform-specific integration step after the user chooses the CI surface.

#### 4. Verification is too narrow for a workflow-change project

- **Location:** Testing Strategy
- **Problem:** The testing strategy smoke-tests one planning stage and one implementation/tester handoff. That does not exercise the full seven-stage artifact chain, naming conventions, prompt discovery, or the user-gated transition between `plan-auditor` and `resolve-audit`.
- **Impact:** The repo can merge a workflow refactor that passes isolated smoke checks but still fails in real use because stage-to-stage handoffs are wrong.
- **Recommendation:** Require one representative end-to-end dry run across all seven stages using a small fixture feature. Each stage should be validated for:
  - correct input artifact discovery,
  - correct output path,
  - expected stop/go behavior,
  - correct verification summary at the tester step.

#### 5. The operational safety envelope is still incomplete

- **Location:** Requirements, Implementation Steps 2 and 6
- **Problem:** The research emphasizes sandbox policy, approvals, secrets hygiene, and command constraints, but the plan only names `.codex/config.toml` and an optional PR review lane. It does not define:
  - an execution policy or allowlist for commands,
  - how repo trust and CLI prerequisites are validated,
  - how CI secrets are provisioned and documented before Codex review automation is enabled.
- **Impact:** The workflow can either fail unpredictably in real environments or require broader privileges than intended.
- **Recommendation:** Add a baseline-hardening step that includes:
  - Codex prerequisite validation,
  - command policy or allowlist enforcement,
  - secret onboarding documentation,
  - explicit enablement criteria before any Codex CI review job is turned on.

### MEDIUM

#### 6. `check_codex_prereqs.sh` is named, but its contract is not defined

- **Location:** Impacted Files, Implementation Step 3
- **Problem:** The plan adds a prerequisite script without listing what it must validate.
- **Impact:** The script risks becoming a weak presence check instead of a real environment gate.
- **Recommendation:** Define minimum checks now: `codex` availability/version, `xcodebuild` availability, required prompt/config files, expected docs folders, and whether the run is allowed for the selected stage.

#### 7. Metrics are named, but ownership and storage are unspecified

- **Location:** Requirements, Implementation Step 6, Success Criteria
- **Problem:** The plan says the rollout should track adoption and CI performance, but it does not say where metrics are stored, who reads them, or what the initial success threshold is.
- **Impact:** Metrics can become documentation-only with no operational value.
- **Recommendation:** Add a minimal reporting contract, such as CI job summaries plus retained JSON artifacts for stage runs, and define one review checkpoint after rollout.

#### 8. Test-target wiring is listed as an impacted project edit before scope is resolved

- **Location:** Impacted Files, Implementation Step 5
- **Problem:** `WellPlate.xcodeproj/project.pbxproj` and `WellPlate.xcodeproj/xcshareddata/xcschemes/WellPlate.xcscheme` are listed as impacted files even though Step 5 explicitly says test wiring may be deferred.
- **Impact:** The plan overstates immediate file impact and blurs the line between milestone-one workflow hardening and a separate test-infrastructure initiative.
- **Recommendation:** Mark those files as conditional deliverables in a follow-up milestone rather than baseline impacted files.

### LOW

#### 9. The plan does not define a migration path for old workflow docs or wrappers

- **Location:** Implementation Steps 1-2
- **Problem:** The repo already has `.codex/WORKFLOW.md`, `.codex/README.md`, `.codex/skills`, and `.codex/agents`. The plan does not say whether the old files will be replaced, wrapped, or left in place with deprecation notes.
- **Impact:** Developers can keep following stale entry points during the transition.
- **Recommendation:** Add one short migration note in `.codex/README.md` and mark deprecated paths clearly if any remain.

## Missing Elements

- [ ] No explicit rule that `resolve-audit` cannot run non-interactively in CI
- [ ] No user-decision artifact format for Stage 4 input/output
- [ ] No up-front choice of canonical instruction source before modifying prompts and skill files
- [ ] No platform-neutral/local-first verification milestone separate from CI-vendor integration
- [ ] No full seven-stage dry run requirement
- [ ] No explicit command-policy / allowlist hardening step
- [ ] No secret onboarding/documentation requirement before enabling Codex PR review

## Decision Requests For Resolve-Audit

1. Should `resolve-audit` be strictly manual/local-only, with CI forbidden from invoking it under any circumstances?
2. Which source is canonical for stage instructions: `.codex/prompts`, `.codex/skills`, or `.codex/agents`?
3. Should CI integration be split into two milestones: platform-agnostic repo scripts first, then GitHub Actions or Xcode Cloud wiring second?
4. Is `WellPlateTests` project wiring part of this workflow upgrade, or should it be a separate testing initiative after the workflow baseline is stable?
5. Do you want Codex PR review automation enabled in the initial rollout, or only after deterministic build gates and secrets handling are proven?

## Verification Gaps

- [ ] No end-to-end validation of the full seven-stage artifact chain
- [ ] No enforcement mechanism for the Step 4 user-approval gate once scripted runners are introduced
- [ ] No explicit preflight checks for `codex`, `xcodebuild`, repo trust, or stage-specific eligibility
- [ ] No CI-platform-specific verification plan because the integration surface is not yet chosen

## Recommendations

1. Revise the plan so the first milestone decides two control-plane questions up front: canonical instruction source and the execution model for `resolve-audit`.
2. Split automation into layers: repo guidance and prompt consolidation first, local runner plus prerequisite checks second, platform-specific CI wiring third.
3. Expand the testing strategy into one full dry run through all seven stages using a small feature artifact chain.
4. Add an explicit hardening deliverable for command policy, secrets onboarding, and environment prerequisites before any Codex CI review lane is enabled.
