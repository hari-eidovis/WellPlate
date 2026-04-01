# Implementation Plan: `/develop` Orchestrator Skill — RESOLVED

**Date**: 2026-04-01
**Status**: Resolved
**Source**: [Brainstorm](../../01_Brainstorming/260401-develop-skill-brainstorm.md)
**Audit**: [Audit Report](../../03_audit-plan/260401-develop-skill-plan-audit.md)
**Approach**: Approach 1 — Single Skill with Sub-command Router

---

## Audit Resolution Summary

| ID | Severity | Issue | Resolution |
|---|---|---|---|
| C1 | CRITICAL | Resolve output path contradicted 3 ways | **RESOLVED** — RESOLVED files stay next to their source. `05_Resolves/` removed from workflow. Existing RESOLVED files stay in `02_Planning/Specs/`. |
| C2 | CRITICAL | Step 1.1 deletes `03_audit-plan/` which contains the audit report | **RESOLVED** — Step 1.1 now migrates `03_audit-plan/*` into `03_Audits/` before deleting. |
| C3 | CRITICAL | Orchestrator routing table ambiguous for resolve output | **RESOLVED** — Routing table now specifies deterministic paths: plan-RESOLVED → `02_Planning/Specs/`, checklist-RESOLVED → `04_Checklist/`. |
| H1 | HIGH | Worktree cleanup only covers 1 of 4 | **RESOLVED** — Step 5.1 now runs `git worktree prune` + removes all 4 worktrees. |
| H2 | HIGH | Deleting `skills/code-reviewer` breaks `/code-reviewer` slash command | **RESOLVED** — Keep `brainstorm` and `code-reviewer` as standalone skills. Only delete `planner` and `plan-auditor` (superseded by `/develop plan` and `/develop audit`). |
| H3 | HIGH | `rmdir` fails on macOS with `.DS_Store` | **RESOLVED** — All `rmdir` replaced with `rm -rf` (after verifying contents migrated). |
| H4 | HIGH | `/brainstorm` becomes unavailable after skill deletion | **RESOLVED** — See H2. `brainstorm` skill kept. |
| M1 | MEDIUM | No rollback plan for Docs migration | **RESOLVED** — Git commit checkpoint added after Phase 1. |
| M2 | MEDIUM | Checklist gate doesn't warn about unaudited plans | **RESOLVED** — Gate rule updated to warn if plan has no matching audit. |
| M3 | MEDIUM | Legacy audit files without date prefix break auto-detection | **RESOLVED** — Documented: auto-detection works only for `YYMMDD-` prefixed files. Legacy files require explicit path. |
| M4 | MEDIUM | `fix` agent has no `Write` tool | **RESOLVED** — Intentional. Added explicit note: "Can only edit existing files. Report if new file creation is needed." |
| M5 | MEDIUM | Orchestrator doesn't specify dispatch mechanism | **RESOLVED** — Clarified: orchestrator reads the agent's SKILL.md as inline instructions and executes the work directly. No sub-process spawning needed. |

---

## Overview

Implement a `/develop` orchestrator skill that unifies the feature development workflow into a single entry point with 8 sub-commands. Three workstreams: (1) migrate Docs folder, (2) clean up and create agent SKILL.md files, (3) create the orchestrator skill.

---

## Requirements

- `/develop <sub-command> [args]` as single entry point
- 8 sub-commands: `brainstorm`, `strategize`, `plan`, `audit`, `checklist`, `resolve`, `implement`, `fix`
- Each sub-command dispatches to a dedicated agent in `.claude/agents/`
- Docs folders aligned 1:1 with workflow stages
- Consistent file naming: `YYMMDD-[feature-slug]-[stage].md`
- All ghost folder references eliminated from agent prompts
- Duplicate SKILL.md files cleaned up (16 → 12: 1 orchestrator skill + 2 standalone skills + 9 agents)
- `/brainstorm` and `/code-reviewer` remain independently invocable

---

## Implementation Steps

### Phase 1: Docs Folder Migration

#### Step 1.1: Create `03_Audits/` and move ALL audit files there

**Action**: Create `Docs/03_Audits/`, move the 18 audit files from `Docs/04_Checklist/checklist/`, move any files from `Docs/03_audit-plan/` (including the audit report for this plan), then delete both emptied source folders.

```bash
mkdir -p Docs/03_Audits

# Move mislabeled audits from checklist folder
mv Docs/04_Checklist/checklist/*-audit.md Docs/03_Audits/

# Move any files from the old audit-plan folder (includes this plan's audit)
mv Docs/03_audit-plan/* Docs/03_Audits/ 2>/dev/null

# Remove emptied folders (rm -rf handles .DS_Store on macOS)
rm -rf Docs/04_Checklist/checklist
rm -rf Docs/03_audit-plan
```
<!-- RESOLVED: C2 — now migrates 03_audit-plan contents before deleting -->
<!-- RESOLVED: H3 — rmdir replaced with rm -rf -->

**Files moved** (18 from checklist + 1 from audit-plan = 19):
- All 18 `*-audit.md` from `04_Checklist/checklist/`
- `260401-develop-skill-plan-audit.md` from `03_audit-plan/`

**Risk**: Low
**Dependencies**: None

---

#### Step 1.2: Move checklists from `02_Planning/Specs/` to `04_Checklist/`

**Action**: Move the 2 CHECKLIST files.

```bash
mv "Docs/02_Planning/Specs/CHECKLIST-APIClient-Implementation.md" Docs/04_Checklist/
mv "Docs/02_Planning/Specs/CHECKLIST-StressView-AuditFixes.md" Docs/04_Checklist/
```

**Risk**: Low
**Dependencies**: Step 1.1 (so `04_Checklist/checklist/` subfolder is already gone)

---

#### Step 1.3: Keep RESOLVED files in `02_Planning/Specs/` — NO MOVE

<!-- RESOLVED: C1 — RESOLVED files stay next to their source. 05_Resolves/ is NOT used for this purpose. -->

**Action**: Leave the 3 existing RESOLVED files where they are in `02_Planning/Specs/`. This is consistent with the resolve agent writing new RESOLVED files back to the source folder.

Existing RESOLVED files (staying in place):
- `Docs/02_Planning/Specs/260219-dark-light-mode-RESOLVED.md`
- `Docs/02_Planning/Specs/260322-coffee-tracking-RESOLVED.md`
- `Docs/02_Planning/Specs/260324-stress-view-dual-mode-ui-RESOLVED.md`

**`05_Resolves/` folder**: Currently empty. Delete it since it serves no purpose in the new workflow.

```bash
rm -rf Docs/05_Resolves
```

**Risk**: Low
**Dependencies**: None

---

#### Step 1.4: Consolidate brainstorms into `01_Brainstorming/`

**Action**: Move 2 files from `02_Planning/Brainstorming/` to `01_Brainstorming/`, then delete the empty subfolder.

```bash
mv "Docs/02_Planning/Brainstorming/260325-home-ai-stress-insights-brainstorm.md" Docs/01_Brainstorming/
mv "Docs/02_Planning/Brainstorming/260401-feature-suggestions.md" Docs/01_Brainstorming/
rm -rf Docs/02_Planning/Brainstorming
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
rm -rf Docs/02_Planning/Plans
```

**Risk**: Low
**Dependencies**: None

---

#### Step 1.6: Rename `06_Mischalleneous/` to `06_Miscellaneous/`

```bash
mv Docs/06_Mischalleneous Docs/06_Miscellaneous
```

**Risk**: Low
**Dependencies**: None

---

#### Step 1.7: Verify final structure and commit

**Action**: Verify the migration, then create a git commit as a rollback checkpoint.

<!-- RESOLVED: M1 — git commit checkpoint after Phase 1 -->

```bash
# Verify
find Docs -type f | sort

# Expected structure:
# Docs/01_Brainstorming/        — 9 files (7 original + 2 moved)
# Docs/02_Planning/Specs/       — 16 files (13 original + 3 from Plans/, 3 RESOLVED stay)
# Docs/03_Audits/               — 19 files (18 from checklist + 1 from audit-plan)
# Docs/04_Checklist/            — 2 files (moved from Specs/)
# Docs/06_Miscellaneous/        — 1 file (renamed folder)
# Docs/Features_Integration/    — 1 file (unchanged)
# TOTAL: 48 files

# Commit checkpoint
git add Docs/
git commit -m "refactor: migrate Docs folder structure to align with /develop workflow"
```

**Dependencies**: Steps 1.1–1.6 all complete

---

### Phase 2: `.claude/` Folder Cleanup & Agent Creation

#### Step 2.1: Delete superseded duplicate skill files, keep standalone skills

<!-- RESOLVED: H2, H4 — brainstorm and code-reviewer kept as standalone skills -->

**Action**: Delete only `planner` and `plan-auditor` from `skills/` (superseded by `/develop plan` and `/develop audit`). Keep `brainstorm` and `code-reviewer` as standalone skills since they have use cases outside the `/develop` workflow.

```bash
rm -rf .claude/skills/planner
rm -rf .claude/skills/plan-auditor
```

**What stays in `.claude/skills/`:**
- `brainstorm/SKILL.md` — standalone `/brainstorm` still works
- `code-reviewer/SKILL.md` — standalone `/code-reviewer` still works
- `develop/SKILL.md` — NEW orchestrator (created in Phase 3)

**Risk**: Low — only deleting skills that are being replaced
**Dependencies**: None

---

#### Step 2.2: Rename existing agents to match sub-command names

```bash
mv .claude/agents/planner .claude/agents/plan
mv .claude/agents/plan-auditor .claude/agents/audit
```

**Risk**: Low
**Dependencies**: Step 2.1

---

#### Step 2.3: Rewrite `brainstorm` agent SKILL.md

**File**: `.claude/agents/brainstorm/SKILL.md`

**Changes**:
- Remove all ghost folder references (`01_Transcripts`, `04_Decisions`, `02_Planning/Future`)
- Update Research Protocol:
  1. `Docs/01_Brainstorming/` — prior brainstorms
  2. `Docs/02_Planning/Specs/` — related plans/specs
  3. `Docs/03_Audits/` — related audits
  4. Last resort: source code
- Output path: `Docs/01_Brainstorming/YYMMDD-[feature-slug]-brainstorm.md`
- Keep tools: `["Read", "Grep", "Glob", "WebSearch", "Write"]`
- Keep model: `sonnet`, extended_thinking: `true`

**Also update** `.claude/skills/brainstorm/SKILL.md` with the same path fixes (this is the standalone skill copy).

**Dependencies**: Phase 1 complete

---

#### Step 2.4: Create `strategize` agent SKILL.md

**File**: `.claude/agents/strategize/SKILL.md`

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
- Output: Strategy doc with chosen approach, rationale, affected files, architectural direction
- Must produce a single recommendation (not multiple options)

**Dependencies**: None

---

#### Step 2.5: Rewrite `plan` agent SKILL.md (formerly `planner`)

**File**: `.claude/agents/plan/SKILL.md`

**Changes**:
- Remove all ghost folder references
- Update Research Protocol:
  1. Read strategy doc if exists: `Docs/02_Planning/Specs/YYMMDD-[feature]-strategy.md`
  2. Check brainstorms: `Docs/01_Brainstorming/`
  3. Check prior audits: `Docs/03_Audits/`
  4. Source code for implementation details
- Output: `Docs/02_Planning/Specs/YYMMDD-[feature-slug]-plan.md`
- Keep tools: `["Read", "Grep", "Glob", "Write"]`
- Keep model: `sonnet`, extended_thinking: `true`

**Dependencies**: Step 2.2 complete (renamed from planner)

---

#### Step 2.6: Rewrite `audit` agent SKILL.md (formerly `plan-auditor`)

**File**: `.claude/agents/audit/SKILL.md`

**Changes**:
- Generalize to dual-purpose: audits plans AND checklists
- Remove all ghost folder references
- Research Protocol:
  1. Read the document being audited (path provided by orchestrator)
  2. Check brainstorms: `Docs/01_Brainstorming/`
  3. Check prior audits: `Docs/03_Audits/`
  4. Source code for feasibility verification
- Output: `Docs/03_Audits/YYMMDD-[feature-slug]-[plan|checklist]-audit.md`
- Dual-mode: if input from `02_Planning/Specs/` → plan audit; if from `04_Checklist/` → checklist audit
- Keep tools: `["Read", "Grep", "Glob", "Write"]`
- Keep model: `sonnet`, extended_thinking: `true`

**Dependencies**: Step 2.2 complete (renamed from plan-auditor)

---

#### Step 2.7: Create `resolve` agent SKILL.md

**File**: `.claude/agents/resolve/SKILL.md`

<!-- RESOLVED: C1 — deterministic output paths, no ambiguity -->

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
  3. For each issue: describe the fix, apply it
  4. Mark MEDIUM/LOW issues as acknowledged but deferred
- **Output paths (deterministic — no ambiguity):**
  - If resolving a **plan** audit → write to `Docs/02_Planning/Specs/YYMMDD-[feature]-plan-RESOLVED.md`
  - If resolving a **checklist** audit → write to `Docs/04_Checklist/YYMMDD-[feature]-checklist-RESOLVED.md`
  - **Rule**: RESOLVED files ALWAYS go next to their source document, never to a separate folder.
- Resolution format: Each fix annotated with `<!-- RESOLVED: [issue title] -->` inline comment
- Summary: Return verdict (ALL RESOLVED / PARTIALLY RESOLVED) + count

**Dependencies**: None

---

#### Step 2.8: Create `checklist` agent SKILL.md

**File**: `.claude/agents/checklist/SKILL.md`

**Frontmatter**:
```yaml
name: checklist
description: Checklist generator. Converts approved implementation plans into ordered, granular implementation checklists with file paths and verification steps.
tools: ["Read", "Grep", "Glob", "Write"]
model: sonnet
extended_thinking: true
```

**Key prompt sections**:
- Input: path to approved plan (from `Docs/02_Planning/Specs/` — original or RESOLVED)
- Research Protocol:
  1. Read the plan document
  2. Read related brainstorm/strategy if referenced
  3. Scan source code for affected files to verify paths
- Output: `Docs/04_Checklist/YYMMDD-[feature-slug]-checklist.md`
- Format:
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
  
  ## Post-Implementation
  - [ ] Build succeeds (all targets)
  - [ ] No new warnings
  - [ ] Manual smoke test
  ```
- Each step: action + file path + verification method
- Group by phase, order by dependency chain

**Dependencies**: None

---

#### Step 2.9: Create `implement` agent SKILL.md

**File**: `.claude/agents/implement/SKILL.md`

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
  3. After each step, verify the change
  4. After all steps, run ALL build commands:
     ```bash
     xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
     xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
     xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
     xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
     ```
- Rules:
  - Follow checklist exactly — do not add unrequested features
  - If a step is ambiguous, check the source plan for clarification
  - If a step is blocked, report and skip
  - Do not modify files outside the checklist scope
- Output: Code changes + build result summary

<!-- RESOLVED: Missing Element 5 from audit — now builds all 4 targets, not just main scheme -->

**Dependencies**: None

---

#### Step 2.10: Create `fix` agent SKILL.md

**File**: `.claude/agents/fix/SKILL.md`

**Frontmatter**:
```yaml
name: fix
description: Build fixer. Runs the build, diagnoses errors, and applies targeted fixes until the build succeeds.
tools: ["Read", "Grep", "Glob", "Edit", "Bash"]
model: sonnet
```

<!-- RESOLVED: M4 — explicitly stated: no Write tool, can only edit existing files -->

**Key prompt sections**:
- Process:
  1. Run all build targets:
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
  - **You can only edit existing files (no Write tool). If a fix requires creating a new file, report it as unresolvable and let the user handle it.**
  - If an error requires architectural changes, report instead of fixing
- Output: Clean build confirmation or list of unresolvable errors

**Dependencies**: None

---

#### Step 2.11: Keep `code-reviewer` agent as-is

**File**: `.claude/agents/code-reviewer/SKILL.md` — no changes.
**File**: `.claude/skills/code-reviewer/SKILL.md` — no changes (kept as standalone skill).

---

### Phase 3: Create the `/develop` Orchestrator Skill

#### Step 3.1: Create `.claude/skills/develop/SKILL.md`

**File**: `.claude/skills/develop/SKILL.md`

<!-- RESOLVED: C3 — routing table now has deterministic output paths, no "or" -->
<!-- RESOLVED: M2 — checklist gate now warns about unaudited plans -->
<!-- RESOLVED: M3 — auto-detection documented as YYMMDD-only -->
<!-- RESOLVED: M5 — dispatch mechanism clarified -->

**Frontmatter**:
```yaml
name: develop
description: "Feature development orchestrator. Routes /develop <sub-command> to the correct agent. Sub-commands: brainstorm, strategize, plan, audit, checklist, resolve, implement, fix."
```

**Prompt structure**:

```markdown
You are the `/develop` orchestrator. Parse the user's sub-command and execute the corresponding workflow stage.

## Dispatch Mechanism

When the user invokes `/develop <sub-command>`, you:
1. Parse the sub-command and arguments
2. Read the corresponding agent SKILL.md from `.claude/agents/<sub-command>/SKILL.md`
3. Follow that agent's instructions to execute the work directly in this conversation
4. You ARE the agent — you don't spawn a sub-process. You read the agent's prompt as your working instructions.

## Sub-command Routing

| Sub-command | Agent SKILL.md | Input | Output Location |
|---|---|---|---|
| `brainstorm [topic]` | `.claude/agents/brainstorm/` | Topic description | `Docs/01_Brainstorming/YYMMDD-[slug]-brainstorm.md` |
| `strategize [topic]` | `.claude/agents/strategize/` | Topic or brainstorm path | `Docs/02_Planning/Specs/YYMMDD-[slug]-strategy.md` |
| `plan [topic]` | `.claude/agents/plan/` | Topic, strategy, or brainstorm | `Docs/02_Planning/Specs/YYMMDD-[slug]-plan.md` |
| `audit` | `.claude/agents/audit/` | Most recent unaudited plan or checklist | `Docs/03_Audits/YYMMDD-[slug]-[type]-audit.md` |
| `checklist [plan]` | `.claude/agents/checklist/` | Approved/resolved plan path | `Docs/04_Checklist/YYMMDD-[slug]-checklist.md` |
| `resolve [audit]` | `.claude/agents/resolve/` | Audit report path | Plan-RESOLVED → `Docs/02_Planning/Specs/`, Checklist-RESOLVED → `Docs/04_Checklist/` |
| `implement [checklist]` | `.claude/agents/implement/` | Approved checklist path | Code changes |
| `fix` | `.claude/agents/fix/` | None (runs build) | Code fixes |

## Naming Convention

- Date prefix: YYMMDD (today's date)
- Feature slug: kebab-case, max 4 words (e.g., `wellness-calendar`, `stress-insights`)
- Stage suffix: `-brainstorm`, `-strategy`, `-plan`, `-plan-audit`, `-plan-RESOLVED`, `-checklist`, `-checklist-audit`, `-checklist-RESOLVED`
- Auto-detection of feature slug only works for files with `YYMMDD-` prefix. Legacy files without date prefixes require explicit path arguments.

## Gate Rules

Before dispatching, check these conditions:

1. **`brainstorm`** — No gate. Always allowed.

2. **`strategize`** — No gate. Look for a brainstorm doc in `Docs/01_Brainstorming/` matching the feature slug. If found, pass it as input. If not, proceed with just the topic.

3. **`plan`** — Soft gate. Look for a strategy doc (`*-strategy.md`) or brainstorm doc for this feature. If found, pass it to the agent. If not, proceed with just the topic.

4. **`audit`** — Auto-detect what to audit:
   - Find the most recent `YYMMDD-` prefixed file in `Docs/02_Planning/Specs/` or `Docs/04_Checklist/` matching the feature slug
   - If it's a plan (`*-plan.md` or `*-strategy.md`) → plan audit mode
   - If it's a checklist (`*-checklist.md`) → checklist audit mode
   - If ambiguous or multiple features found, list them and ask the user to specify

5. **`checklist`** — Hard gate. Check for a plan:
   - Look for `*-plan-RESOLVED.md` first (preferred), then `*-plan.md`
   - If neither exists → error: "No plan found. Run `/develop plan [topic]` first."
   - If plan exists but no matching `*-plan-audit.md` in `Docs/03_Audits/` → warn: "Plan has not been audited. Consider running `/develop audit` first, or confirm to proceed."

6. **`resolve`** — Requires an audit. If no path provided, find the most recent `*-audit.md` in `Docs/03_Audits/`. Also locate the original document being audited (from the audit report's content or matching feature slug).

7. **`implement`** — Hard gate. Check for a checklist:
   - Look for `*-checklist-RESOLVED.md` first, then `*-checklist.md` in `Docs/04_Checklist/`
   - If neither exists → error: "No checklist found. Run `/develop checklist` first."
   - If checklist exists but no matching `*-checklist-audit.md` in `Docs/03_Audits/` → warn: "Checklist not audited. Run `/develop audit` first, or confirm to proceed without audit."

8. **`fix`** — No gate. Can run anytime.

## Dispatch Protocol

When dispatching:
1. Determine the feature slug from the user's args or from the most recent YYMMDD-prefixed feature in Docs
2. Determine today's date as YYMMDD
3. Read the agent's SKILL.md and follow its instructions with:
   - The feature topic/description
   - Any input file paths (strategy, plan, audit, checklist)
   - The expected output file path
4. After completing the work, report:
   - What was created/modified
   - The output file path
   - What the next step in the workflow is (e.g., "Next: `/develop audit` to review the plan")

## Workflow Summary (show when user runs `/develop` with no sub-command)

```
STEP 0 (OPTIONAL): /develop brainstorm [topic]  — explore ideas
PHASE 1 — PLANNING:
  Step 1: /develop strategize [topic]  — choose direction (optional)
  Step 2: /develop plan [topic]        — detailed implementation plan
  Step 3: /develop audit               — review the plan
  Step 3b: /develop resolve            — fix audit issues (if any)
  Step 4: /develop checklist           — convert plan to checklist
  Step 5: /develop audit               — review the checklist
  Step 5b: /develop resolve            — fix audit issues (if any)
PHASE 2 — IMPLEMENTATION:
  Step 6: /develop implement           — execute the checklist
  Step 7: /develop fix                 — build and fix errors
```
```

**Dependencies**: Phase 2 complete (all agents exist)

---

### Phase 4: Update CLAUDE.md

#### Step 4.1: Replace the "Development Workflow (.codex)" section

**File**: `CLAUDE.md`

**Replace** the current section with:

```markdown
## Development Workflow

This repo uses a `/develop` orchestrator skill with 8 sub-commands:

```
STEP 0 (OPTIONAL): /develop brainstorm [topic]
PHASE 1 — PLANNING:
  Step 1: /develop strategize [topic]    → Docs/02_Planning/Specs/YYMMDD-[slug]-strategy.md
  Step 2: /develop plan [topic]          → Docs/02_Planning/Specs/YYMMDD-[slug]-plan.md
  Step 3: /develop audit                 → Docs/03_Audits/YYMMDD-[slug]-plan-audit.md
  Step 3b: /develop resolve              → Docs/02_Planning/Specs/YYMMDD-[slug]-plan-RESOLVED.md
  Step 4: /develop checklist             → Docs/04_Checklist/YYMMDD-[slug]-checklist.md
  Step 5: /develop audit                 → Docs/03_Audits/YYMMDD-[slug]-checklist-audit.md
  Step 5b: /develop resolve              → Docs/04_Checklist/YYMMDD-[slug]-checklist-RESOLVED.md
PHASE 2 — IMPLEMENTATION:
  Step 6: /develop implement             → Code changes
  Step 7: /develop fix                   → Build fixes
```

Standalone skills (outside `/develop`): `/brainstorm`, `/code-reviewer`

File naming convention: `YYMMDD-[feature-slug]-[stage].md`

Do not skip from planning to implementation. Step 3b/5b (resolve) is a **hard stop** — user approval required before proceeding.
```

**Dependencies**: Phases 1–3 complete

---

### Phase 5: Cleanup

#### Step 5.1: Clean up ALL worktrees

<!-- RESOLVED: H1 — now handles all 4 worktrees, not just hardcore-nash -->

```bash
# Prune the 3 already-prunable worktrees
git worktree prune

# Remove the active worktree
git worktree remove .claude/worktrees/hardcore-nash --force 2>/dev/null

# Clean up any remaining worktree directories
rm -rf .claude/worktrees

# Clean up orphaned branches
git branch -D claude/ecstatic-sammet claude/hardcore-nash claude/magical-sutherland claude/zen-solomon 2>/dev/null
```

**Risk**: Low — verify no active work in worktrees first. All 3 prunable ones already have detached/missing branches.
**Dependencies**: None (can run anytime)

---

## Execution Order Summary

```
Phase 1 (Docs migration) ─── sequential batch, then commit
  1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.7 (verify + commit checkpoint)

Phase 2 (Agents) ─── depends on Phase 1 for folder paths
  2.1 (delete 2 superseded skills: planner, plan-auditor)
  2.2 (rename planner→plan, plan-auditor→audit)
  2.3 (rewrite brainstorm agent + update standalone skill copy)
  2.4–2.10 (create/rewrite 7 agents) ─── independent, can parallelize
  2.11 (code-reviewer: no-op)

Phase 3 (Orchestrator skill) ─── depends on Phase 2
  3.1 (create /develop SKILL.md)

Phase 4 (CLAUDE.md update) ─── depends on Phases 1–3
  4.1 (rewrite workflow section)

Phase 5 (Cleanup) ─── independent
  5.1 (prune + remove all worktrees)
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Moving docs breaks git blame history | Low | `git log --follow` tracks renames. Accept tradeoff. |
| Orchestrator prompt too long for skill file | Medium | Keep routing table compact; agent prompts carry the detail. |
| Agent sub-commands parsed incorrectly | Low | Explicit examples in orchestrator prompt. |
| `fix` agent loops on unfixable errors | Medium | Hard cap at 5 build iterations. |
| Dispatch mechanism doesn't work as expected | Medium | Test with one sub-command (`/develop brainstorm test`) before writing all agents. |

---

## Success Criteria

- [ ] `find Docs -type f | sort` matches the canonical structure (no files in wrong folders)
- [ ] No ghost folder references in any `.claude/agents/*/SKILL.md` or `.claude/skills/*/SKILL.md`
- [ ] `ls .claude/skills/` shows: `brainstorm/`, `code-reviewer/`, `develop/`
- [ ] `ls .claude/agents/` shows: `audit/`, `brainstorm/`, `checklist/`, `code-reviewer/`, `fix/`, `implement/`, `plan/`, `resolve/`, `strategize/`
- [ ] `/develop` with no args shows the workflow summary
- [ ] `/develop brainstorm test-feature` creates `Docs/01_Brainstorming/YYMMDD-test-feature-brainstorm.md`
- [ ] `/develop plan test-feature` creates `Docs/02_Planning/Specs/YYMMDD-test-feature-plan.md`
- [ ] `/develop audit` auto-detects the most recent plan and writes to `Docs/03_Audits/`
- [ ] `/develop implement` warns if checklist hasn't been audited
- [ ] CLAUDE.md workflow section matches actual folder structure and sub-commands
- [ ] No stale worktrees remain (`git worktree list` shows only main)
- [ ] `/brainstorm` and `/code-reviewer` still work as standalone skills
- [ ] RESOLVED files live next to their source documents (not in a separate folder)
