# Implementation Plan: `/develop` Orchestrator Skill

**Date**: 2026-04-01
**Status**: Draft
**Source**: [Brainstorm](../../01_Brainstorming/260401-develop-skill-brainstorm.md)
**Approach**: Approach 1 — Single Skill with Sub-command Router

---

## Overview

Implement a `/develop` orchestrator skill that unifies the feature development workflow into a single entry point with 8 sub-commands. This requires three parallel workstreams: (1) migrate the Docs folder to match the workflow, (2) clean up and create agent SKILL.md files, and (3) create the orchestrator skill itself.

---

## Requirements

- `/develop <sub-command> [args]` as single entry point
- 8 sub-commands: `brainstorm`, `strategize`, `plan`, `audit`, `checklist`, `resolve`, `implement`, `fix`
- Each sub-command dispatches to a dedicated agent in `.claude/agents/`
- Docs folders aligned 1:1 with workflow stages
- Consistent file naming: `YYMMDD-[feature-slug]-[stage].md`
- All ghost folder references eliminated from agent prompts
- Duplicate SKILL.md files removed (16 → 10)

---

## Implementation Steps

### Phase 1: Docs Folder Migration

Every file move listed here comes from the brainstorm's "File-by-File Migration Map".

#### Step 1.1: Create `03_Audits/` and move audit files

**Action**: Create `Docs/03_Audits/`, move all 18 `*-audit.md` files from `Docs/04_Checklist/checklist/`, then delete the empty `Docs/04_Checklist/checklist/` subfolder and `Docs/03_audit-plan/`.

```bash
# Create target
mkdir -p Docs/03_Audits

# Move all audit files
mv Docs/04_Checklist/checklist/*-audit.md Docs/03_Audits/

# Remove emptied folders
rmdir Docs/04_Checklist/checklist
rmdir Docs/03_audit-plan
```

**Files moved** (18):
- `260311-accent-color-plan-audit.md`
- `260314-meallog-audio-to-text-audit.md`
- `260314-meallog-audio-to-text-impl-audit.md`
- `260315-barcode-scan-plan-audit.md`
- `260316-codex-workflow-improvements-audit.md`
- `260322-coffee-tracking-audit.md`
- `260324-stress-view-dual-mode-ui-audit.md`
- `260325-home-ai-stress-insights-audit.md`
- `APIClient-Mock-Configuration-audit.md`
- `dark-light-mode-audit.md`
- `food-aggregation-audit.md`
- `goals-feature-audit.md`
- `home-drag-to-log-meal-audit.md`
- `liquid-glass-hero-audit.md`
- `meallogview-audit.md`
- `screentime-stress-view-audit.md`
- `stress-vitals-detail-views-audit.md`
- `wellness-ring-navigation-audit.md`

**Risk**: Low — these files are docs, not code. Git tracks the moves.
**Dependencies**: None

---

#### Step 1.2: Move checklists from `02_Planning/Specs/` to `04_Checklist/`

**Action**: Move the 2 CHECKLIST files.

```bash
mv "Docs/02_Planning/Specs/CHECKLIST-APIClient-Implementation.md" Docs/04_Checklist/
mv "Docs/02_Planning/Specs/CHECKLIST-StressView-AuditFixes.md" Docs/04_Checklist/
```

**Risk**: Low
**Dependencies**: Step 1.1 must complete first (so `04_Checklist/checklist/` subfolder is already gone)

---

#### Step 1.3: Move RESOLVED files from `02_Planning/Specs/` to `05_Resolves/`

**Action**: Move the 3 RESOLVED files.

```bash
mv "Docs/02_Planning/Specs/260219-dark-light-mode-RESOLVED.md" Docs/05_Resolves/
mv "Docs/02_Planning/Specs/260322-coffee-tracking-RESOLVED.md" Docs/05_Resolves/
mv "Docs/02_Planning/Specs/260324-stress-view-dual-mode-ui-RESOLVED.md" Docs/05_Resolves/
```

**Risk**: Low
**Dependencies**: None

---

#### Step 1.4: Consolidate brainstorms into `01_Brainstorming/`

**Action**: Move 2 files from `02_Planning/Brainstorming/` to `01_Brainstorming/`, then delete the empty subfolder.

```bash
mv "Docs/02_Planning/Brainstorming/260325-home-ai-stress-insights-brainstorm.md" Docs/01_Brainstorming/
mv "Docs/02_Planning/Brainstorming/260401-feature-suggestions.md" Docs/01_Brainstorming/
rmdir Docs/02_Planning/Brainstorming
```

**Risk**: Low
**Dependencies**: None

---

#### Step 1.5: Merge `02_Planning/Plans/` into `02_Planning/Specs/`

**Action**: Move 3 plan files from `Plans/` to `Specs/`, then delete the empty subfolder.

```bash
mv Docs/02_Planning/Plans/260311-accent-color-change-plan.md Docs/02_Planning/Specs/
mv Docs/02_Planning/Plans/260314-seven-agent-workflow-plan.md Docs/02_Planning/Specs/
mv Docs/02_Planning/Plans/260315-barcode-scan-plan.md Docs/02_Planning/Specs/
rmdir Docs/02_Planning/Plans
```

**Risk**: Low
**Dependencies**: None

---

#### Step 1.6: Rename `06_Mischalleneous/` to `06_Miscellaneous/`

**Action**: Fix the typo.

```bash
mv Docs/06_Mischalleneous Docs/06_Miscellaneous
```

**Risk**: Low
**Dependencies**: None

---

#### Step 1.7: Verify final structure

**Action**: Run `find Docs -type f | sort` and confirm it matches the canonical structure from the brainstorm doc.

**Dependencies**: Steps 1.1–1.6 all complete

---

### Phase 2: `.claude/` Folder Cleanup & Agent Creation

#### Step 2.1: Delete duplicate skill files

The `skills/` folder currently mirrors `agents/` with identical files. Since these are agents (spawned by the orchestrator), not user-invoked skills, they belong only in `agents/`.

**Action**: Delete 4 duplicate skill folders.

```bash
rm -rf .claude/skills/brainstorm
rm -rf .claude/skills/planner
rm -rf .claude/skills/plan-auditor
rm -rf .claude/skills/code-reviewer
```

**Risk**: Medium — verify these aren't referenced elsewhere first. Check if any are invoked as `/brainstorm` etc.
**Dependencies**: None

---

#### Step 2.2: Rename existing agents to match sub-command names

**Action**: Rename `planner` → `plan`, `plan-auditor` → `audit`.

```bash
mv .claude/agents/planner .claude/agents/plan
mv .claude/agents/plan-auditor .claude/agents/audit
```

**Risk**: Low
**Dependencies**: Step 2.1 (so we don't rename while duplicates exist)

---

#### Step 2.3: Rewrite `brainstorm` agent SKILL.md

**File**: `.claude/agents/brainstorm/SKILL.md`

**Changes**:
- Remove all ghost folder references (`01_Transcripts`, `04_Decisions`, `02_Planning/Future`)
- Update Research Protocol to reference real folders:
  1. `Docs/01_Brainstorming/` — prior brainstorms
  2. `Docs/02_Planning/Specs/` — related plans/specs
  3. `Docs/03_Audits/` — related audits
  4. Last resort: source code
- Update output path to: `Docs/01_Brainstorming/YYMMDD-[feature-slug]-brainstorm.md`
- Remove `Docs/02_Planning/Future/` as alternate output
- Keep tools: `["Read", "Grep", "Glob", "WebSearch", "Write"]`
- Keep model: `sonnet`, extended_thinking: `true`

**Dependencies**: Phase 1 complete (folders exist)

---

#### Step 2.4: Create `strategize` agent SKILL.md

**File**: `.claude/agents/strategize/SKILL.md`

**Purpose**: Focused strategy — takes a brainstorm (if exists) or fresh topic and produces a single chosen approach with rationale.

**Frontmatter**:
```yaml
name: strategize
description: Focused strategy specialist. Narrows brainstorm options to a single chosen approach with rationale and architectural direction.
tools: ["Read", "Grep", "Glob", "Write"]
model: sonnet
extended_thinking: true
```

**Key prompt sections**:
- File Writing Protocol: Write to `Docs/02_Planning/Specs/YYMMDD-[feature-slug]-strategy.md`
- Research Protocol:
  1. Read brainstorm doc if provided (from `Docs/01_Brainstorming/`)
  2. Check related specs: `Docs/02_Planning/Specs/`
  3. Review codebase for relevant existing patterns
- Output format: Strategy doc with chosen approach, rationale, affected files, architectural direction, constraints accepted
- Must produce a single recommendation (not multiple options — that's brainstorm's job)

**Dependencies**: None

---

#### Step 2.5: Rewrite `plan` agent SKILL.md (formerly `planner`)

**File**: `.claude/agents/plan/SKILL.md`

**Changes**:
- Remove all ghost folder references (`01_Transcripts`, `04_Decisions`, `06_Maintenance/Patterns`)
- Update Research Protocol:
  1. Read strategy doc if exists: `Docs/02_Planning/Specs/YYMMDD-[feature]-strategy.md`
  2. Check brainstorms: `Docs/01_Brainstorming/`
  3. Check prior audits/resolves: `Docs/03_Audits/`, `Docs/05_Resolves/`
  4. Source code for implementation details
- Update output path: `Docs/02_Planning/Specs/YYMMDD-[feature-slug]-plan.md`
- Keep tools: `["Read", "Grep", "Glob", "Write"]`
- Keep model: `sonnet`, extended_thinking: `true`

**Dependencies**: Phase 1 complete, Step 2.2 complete (renamed from planner)

---

#### Step 2.6: Rewrite `audit` agent SKILL.md (formerly `plan-auditor`)

**File**: `.claude/agents/audit/SKILL.md`

**Changes**:
- Generalize to audit BOTH plans and checklists (dual-purpose)
- Remove all ghost folder references
- Update Research Protocol:
  1. Read the document being audited (path provided by orchestrator)
  2. Check brainstorms: `Docs/01_Brainstorming/`
  3. Check prior audits: `Docs/03_Audits/`
  4. Source code for feasibility verification
- Update output path: `Docs/03_Audits/YYMMDD-[feature-slug]-[plan|checklist]-audit.md`
- Add dual-mode detection: if input is from `02_Planning/Specs/` → plan audit mode; if from `04_Checklist/` → checklist audit mode
- Keep tools: `["Read", "Grep", "Glob", "Write"]`
- Keep model: `sonnet`, extended_thinking: `true`

**Dependencies**: Phase 1 complete, Step 2.2 complete (renamed from plan-auditor)

---

#### Step 2.7: Create `resolve` agent SKILL.md

**File**: `.claude/agents/resolve/SKILL.md`

**Purpose**: Reads an audit report + the original doc, addresses CRITICAL and HIGH issues, produces a `-RESOLVED.md` version.

**Frontmatter**:
```yaml
name: resolve
description: Audit resolution specialist. Addresses CRITICAL and HIGH audit findings and produces a resolved version of the plan or checklist.
tools: ["Read", "Grep", "Glob", "Write"]
model: sonnet
extended_thinking: true
```

**Key prompt sections**:
- Inputs: audit report path + original document path (both provided by orchestrator)
- Process:
  1. Read the audit report — extract all CRITICAL and HIGH issues
  2. Read the original document
  3. For each issue: describe the fix, apply it to the document
  4. Mark MEDIUM/LOW issues as acknowledged but deferred
- Output: Write resolved doc to appropriate location:
  - Plan resolve → `Docs/02_Planning/Specs/YYMMDD-[feature]-plan-RESOLVED.md`
  - Checklist resolve → `Docs/04_Checklist/YYMMDD-[feature]-checklist-RESOLVED.md`
- Resolution format: Each fix annotated with `<!-- RESOLVED: [issue title] -->` inline comment
- Summary: Return verdict (ALL RESOLVED / PARTIALLY RESOLVED) + count

**Dependencies**: None

---

#### Step 2.8: Create `checklist` agent SKILL.md

**File**: `.claude/agents/checklist/SKILL.md`

**Purpose**: Converts an approved/resolved plan into an ordered implementation checklist with granular, checkable steps.

**Frontmatter**:
```yaml
name: checklist
description: Checklist generator. Converts approved implementation plans into ordered, granular implementation checklists with file paths and verification steps.
tools: ["Read", "Grep", "Glob", "Write"]
model: sonnet
extended_thinking: true
```

**Key prompt sections**:
- Input: path to approved plan (from `Docs/02_Planning/Specs/` — either original or RESOLVED)
- Research Protocol:
  1. Read the plan document
  2. Read related brainstorm/strategy if referenced
  3. Scan source code for affected files to verify paths
- Output: `Docs/04_Checklist/YYMMDD-[feature-slug]-checklist.md`
- Checklist format:
  ```markdown
  # Implementation Checklist: [Feature]
  
  **Source Plan**: [link to plan]
  **Date**: YYYY-MM-DD
  
  ## Pre-Implementation
  - [ ] Verify dependencies exist
  - [ ] Create feature branch
  
  ## Implementation
  - [ ] **Step 1**: [Action] (File: `path/to/file.swift`)
    - Detail: [specific change]
    - Verify: [how to confirm it worked]
  - [ ] **Step 2**: ...
  
  ## Post-Implementation
  - [ ] Build succeeds (`xcodebuild ...`)
  - [ ] No new warnings
  - [ ] Manual smoke test
  ```
- Each step must have: action, file path, verification method
- Group by phase (pre, implementation by component, post)
- Order by dependency chain

**Dependencies**: None

---

#### Step 2.9: Create `implement` agent SKILL.md

**File**: `.claude/agents/implement/SKILL.md`

**Purpose**: Executes an approved checklist by writing/editing code, step by step.

**Frontmatter**:
```yaml
name: implement
description: Implementation specialist. Executes approved checklists by writing code, creating files, and making changes step by step.
tools: ["Read", "Grep", "Glob", "Write", "Edit", "Bash"]
model: sonnet
extended_thinking: true
```

**Key prompt sections**:
- Input: path to approved checklist (from `Docs/04_Checklist/`)
- Process:
  1. Read the full checklist
  2. Execute each step in order
  3. After each step, verify the change (read back the file, check for syntax)
  4. After all steps, run the build command
- Build command (from CLAUDE.md):
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
- Rules:
  - Follow checklist exactly — do not add unrequested features
  - If a step is ambiguous, check the source plan for clarification
  - If a step is blocked (dependency missing, file doesn't exist), report and skip
  - Do not modify files outside the checklist scope
- Output: Code changes + build result summary

**Dependencies**: None

---

#### Step 2.10: Create `fix` agent SKILL.md

**File**: `.claude/agents/fix/SKILL.md`

**Purpose**: Runs the build, identifies errors, and fixes them iteratively.

**Frontmatter**:
```yaml
name: fix
description: Build fixer. Runs the build, diagnoses errors, and applies targeted fixes until the build succeeds.
tools: ["Read", "Grep", "Glob", "Edit", "Bash"]
model: sonnet
```

**Key prompt sections**:
- Process:
  1. Run the build:
     ```bash
     xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1
     ```
  2. Parse errors from output
  3. For each error: read the file, diagnose, apply minimal fix
  4. Re-run build
  5. Repeat until clean or max 5 iterations
- Rules:
  - Fix only build errors — do not refactor, clean up, or "improve"
  - Each fix should be minimal and targeted
  - If an error requires architectural changes, report it instead of fixing
- Output: Clean build confirmation or list of unresolvable errors

**Dependencies**: None

---

#### Step 2.11: Keep `code-reviewer` agent as-is

**File**: `.claude/agents/code-reviewer/SKILL.md`

**Action**: No changes. This agent stays independent of the `/develop` workflow. No broken folder refs to fix.

**Dependencies**: None

---

### Phase 3: Create the `/develop` Orchestrator Skill

#### Step 3.1: Create `.claude/skills/develop/SKILL.md`

**File**: `.claude/skills/develop/SKILL.md`

This is the core deliverable — the single skill the user invokes.

**Frontmatter**:
```yaml
name: develop
description: "Feature development orchestrator. Routes /develop <sub-command> to the correct agent. Sub-commands: brainstorm, strategize, plan, audit, checklist, resolve, implement, fix."
```

**Prompt structure**:

```markdown
You are the `/develop` orchestrator. Parse the user's sub-command and dispatch to the correct agent.

## Sub-command Routing

| Sub-command | Agent | Input | Output Location |
|---|---|---|---|
| `brainstorm [topic]` | brainstorm | Topic description | `Docs/01_Brainstorming/YYMMDD-[slug]-brainstorm.md` |
| `strategize [topic]` | strategize | Topic or brainstorm path | `Docs/02_Planning/Specs/YYMMDD-[slug]-strategy.md` |
| `plan [topic]` | plan | Topic, strategy, or brainstorm path | `Docs/02_Planning/Specs/YYMMDD-[slug]-plan.md` |
| `audit` | audit | Most recent unaudited plan or checklist | `Docs/03_Audits/YYMMDD-[slug]-[type]-audit.md` |
| `checklist [plan]` | checklist | Path to approved/resolved plan | `Docs/04_Checklist/YYMMDD-[slug]-checklist.md` |
| `resolve [audit]` | resolve | Path to audit report | `Docs/05_Resolves/` or back into source folder as `-RESOLVED.md` |
| `implement [checklist]` | implement | Path to approved checklist | Code changes |
| `fix` | fix | None (runs build) | Code fixes |

## Naming Convention

- Date prefix: YYMMDD (today's date)
- Feature slug: kebab-case, max 4 words (e.g., `wellness-calendar`, `stress-insights`)
- Stage suffix: `-brainstorm`, `-strategy`, `-plan`, `-plan-audit`, `-plan-RESOLVED`, `-checklist`, `-checklist-audit`, `-checklist-RESOLVED`

## Gate Rules

Before dispatching, check these conditions:

1. **`plan`** — Look for a strategy doc (`*-strategy.md`) or brainstorm doc for this feature in `Docs/02_Planning/Specs/` or `Docs/01_Brainstorming/`. If found, pass it to the agent. If not found, proceed with just the topic (user may skip strategize).

2. **`audit`** — Auto-detect what to audit:
   - Find the most recent file in `Docs/02_Planning/Specs/` or `Docs/04_Checklist/` matching the feature slug
   - If it's a plan → plan audit mode
   - If it's a checklist → checklist audit mode
   - If ambiguous, ask the user

3. **`checklist`** — Verify a plan exists. Check for `*-plan-RESOLVED.md` first (preferred), then `*-plan.md`. If neither exists, warn: "No plan found. Run `/develop plan [topic]` first."

4. **`resolve`** — Requires an audit report path. If not provided, find the most recent `*-audit.md` in `Docs/03_Audits/`.

5. **`implement`** — Verify a checklist exists. Check for `*-checklist-RESOLVED.md` first, then `*-checklist.md`. If neither exists, warn: "No checklist found. Run `/develop checklist` first."
   - **Hard stop**: If checklist has not been audited (no matching `*-checklist-audit.md` in `Docs/03_Audits/`), warn: "Checklist not audited. Run `/develop audit` first, or confirm to proceed without audit."

6. **`fix`** — No gate. Can run anytime.

## Dispatch Protocol

When dispatching to an agent:
1. Determine the feature slug from the user's args or from the most recent feature context
2. Determine today's date as YYMMDD
3. Pass to the agent:
   - The feature topic/description
   - Any input file paths (strategy, plan, audit, checklist)
   - The expected output file path
4. After the agent completes, report:
   - What was created/modified
   - The output file path
   - What the next step in the workflow is (e.g., "Next: `/develop audit` to review the plan")

## Workflow Summary (show when user runs `/develop` with no sub-command)

STEP 0 (OPTIONAL): `/develop brainstorm [topic]` — explore ideas
PHASE 1 — PLANNING:
  Step 1: `/develop strategize [topic]` — choose direction
  Step 2: `/develop plan [topic]` — detailed implementation plan
  Step 3: `/develop audit` — review the plan
  Step 3b: `/develop resolve` — fix audit issues (if any)
  Step 4: `/develop checklist` — convert plan to checklist
  Step 5: `/develop audit` — review the checklist
  Step 5b: `/develop resolve` — fix audit issues (if any)
PHASE 2 — IMPLEMENTATION:
  Step 6: `/develop implement` — execute the checklist
  Step 7: `/develop fix` — build and fix errors
```

**Dependencies**: Phase 2 complete (all agents exist)

---

### Phase 4: Update CLAUDE.md

#### Step 4.1: Replace the "Development Workflow (.codex)" section in CLAUDE.md

**File**: `CLAUDE.md`

**Action**: Replace the current 7-stage workflow section with the new `/develop` workflow. Update:

- Workflow stages (now 8 sub-commands across 2 phases)
- File output locations (match new Docs structure)
- Remove references to old agent names (`planner`, `plan-auditor`, `checklist-preparer`, `implementer`, `tester`)
- Add the sub-command routing table
- Add naming convention documentation

**Dependencies**: Phases 1–3 complete

---

### Phase 5: Cleanup

#### Step 5.1: Delete stale worktree

```bash
rm -rf .claude/worktrees/hardcore-nash
```

**Risk**: Low — verify it's not an active worktree with `git worktree list` first.
**Dependencies**: None (can run anytime)

---

## Execution Order Summary

```
Phase 1 (Docs migration) ─── all steps can run sequentially in one batch
  1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.7 (verify)

Phase 2 (Agents) ─── depends on Phase 1 for folder paths
  2.1 (delete duplicate skills)
  2.2 (rename planner→plan, plan-auditor→audit)
  2.3–2.10 (rewrite/create 8 agents) ─── independent, can parallelize
  2.11 (code-reviewer: no-op)

Phase 3 (Orchestrator skill) ─── depends on Phase 2
  3.1 (create /develop SKILL.md)

Phase 4 (CLAUDE.md update) ─── depends on Phases 1–3
  4.1 (rewrite workflow section)

Phase 5 (Cleanup) ─── independent
  5.1 (delete stale worktree)
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Moving docs breaks git blame history | Low — `git log --follow` tracks renames | Accept; clean structure > blame convenience |
| Deleting `skills/` duplicates breaks existing `/brainstorm` invocations | Medium — users may have muscle memory | Check if any skill is user-invoked before deleting; keep as aliases if needed |
| Orchestrator prompt too long for skill file | Medium — may hit token limits | Keep routing table compact; agent prompts carry the detail |
| Agent sub-commands parsed incorrectly | Low — Claude is good at this | Add explicit examples in the orchestrator prompt |
| `fix` agent loops infinitely on unfixable errors | Medium | Hard cap at 5 build iterations in prompt |

---

## Success Criteria

- [ ] `find Docs -type f | sort` matches the canonical structure (no files in wrong folders)
- [ ] No ghost folder references in any `.claude/agents/*/SKILL.md` file
- [ ] `ls .claude/skills/` shows only `develop/`
- [ ] `ls .claude/agents/` shows exactly: `audit`, `brainstorm`, `checklist`, `code-reviewer`, `fix`, `implement`, `plan`, `resolve`, `strategize`
- [ ] `/develop` with no args shows the workflow summary
- [ ] `/develop brainstorm test-feature` creates `Docs/01_Brainstorming/260401-test-feature-brainstorm.md`
- [ ] `/develop plan test-feature` creates `Docs/02_Planning/Specs/260401-test-feature-plan.md`
- [ ] `/develop audit` auto-detects the most recent plan and writes to `Docs/03_Audits/`
- [ ] `/develop implement` warns if checklist hasn't been audited
- [ ] CLAUDE.md workflow section matches actual folder structure and sub-commands
- [ ] No duplicate SKILL.md files remain (worktrees cleaned, skills/ cleared)
