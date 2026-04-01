# Brainstorm: `/develop` Orchestrator Skill

**Date**: 2026-04-01
**Status**: Draft

---

## Problem Statement

The current 7-stage development workflow (`brainstorm → planner → plan-auditor → resolve-audit → checklist-preparer → implementer → tester`) exists only as documentation in CLAUDE.md. There is no enforced entry point — the user must manually invoke each skill in sequence, remember the correct order, pass the right file paths between stages, and mentally track which phase they're in. This leads to skipped steps, inconsistent doc locations, and agents referencing ghost folders.

We need a single `/develop` skill that acts as an **orchestrator**, routing sub-commands to the correct agent while enforcing stage gates, file naming conventions, and output locations.

---

## Core Requirements

- Single entry point: `/develop <sub-command> [args]`
- Sub-commands map to discrete workflow stages
- Each stage knows where to read input from and where to write output to
- Stage gates prevent skipping (e.g., can't checklist without an approved plan)
- Consistent file naming: `YYMMDD-[feature]-[stage].md`
- All agents write docs to the correct, **actually existing** folder
- The orchestrator itself is a skill (`.claude/skills/develop/SKILL.md`)
- Sub-agents (brainstorm, strategize, plan, audit, checklist, resolve, implement) are agents (`.claude/agents/`)

---

## Constraints

- Claude Code skills can only be user-invoked slash commands — they cannot auto-chain (i.e., `/develop plan` cannot auto-invoke `/develop audit` without user action)
- Agents spawned by the skill run as subagents — they get the SKILL.md prompt but don't see prior conversation context unless explicitly passed
- File paths in agent prompts must match **real** Docs folder structure (current ghost folder problem must be solved first or simultaneously)
- The skill must work with the existing `.claude/agents/` and `.claude/skills/` structure
- Each sub-command should be independently invocable (user may re-run a stage)

---

## Proposed Workflow

```
STEP 0 (OPTIONAL): BRAINSTORM
  └─ /develop brainstorm [topic]
     └─ Creative exploration, multiple approaches, edge cases
     └─ Output: Docs/01_Brainstorming/YYMMDD-[feature]-brainstorm.md

PHASE 1: PLANNING (Steps 1–5)
  ┌─ Step 1: STRATEGIZE (or skip if brainstorm was deep enough)
  │  └─ /develop strategize [topic]
  │     └─ Focused strategy from brainstorm output or fresh topic
  │     └─ Output: Docs/02_Planning/Specs/YYMMDD-[feature]-strategy.md
  │
  ├─ Step 2: PLAN
  │  └─ /develop plan [topic]
  │     └─ Reads strategy (if exists), produces implementation plan
  │     └─ Output: Docs/02_Planning/Specs/YYMMDD-[feature]-plan.md
  │
  ├─ Step 3: PLAN REVIEW (audit)
  │  └─ /develop audit
  │     └─ Audits the most recent plan, finds gaps and risks
  │     └─ Output: Docs/03_Audits/YYMMDD-[feature]-plan-audit.md
  │
  │  Step 3b: RESOLVE (if audit has issues)
  │  └─ /develop resolve [audit]
  │     └─ Addresses audit findings, produces resolved plan
  │     └─ Output: Docs/02_Planning/Specs/YYMMDD-[feature]-plan-RESOLVED.md
  │
  ├─ Step 4: CHECKLIST
  │  └─ /develop checklist [plan]
  │     └─ Converts approved plan into implementation checklist
  │     └─ Output: Docs/04_Checklist/YYMMDD-[feature]-checklist.md
  │
  └─ Step 5: CHECKLIST REVIEW (audit)
     └─ /develop audit
        └─ Audits the checklist for completeness
        └─ Output: Docs/03_Audits/YYMMDD-[feature]-checklist-audit.md

     Step 5b: RESOLVE (if audit has issues)
     └─ /develop resolve [audit]
        └─ Output: Docs/04_Checklist/YYMMDD-[feature]-checklist-RESOLVED.md

PHASE 2: IMPLEMENTATION (Steps 6–7)
  ┌─ Step 6: IMPLEMENT
  │  └─ /develop implement [checklist]
  │     └─ Executes the approved checklist step by step
  │     └─ Output: Code changes + build verification
  │
  └─ Step 7: FIX
     └─ /develop fix
        └─ Runs build, identifies errors, fixes them
        └─ Output: Clean build
```

---

## Approach 1: Single Skill with Sub-command Router

**Summary**: One `develop` SKILL.md that parses the sub-command and dispatches to the correct agent.

The skill file contains:
- Sub-command parsing logic (in the prompt itself — Claude reads the arg and decides which agent to spawn)
- File path conventions for each stage
- Stage gate rules (e.g., "before checklist, verify a plan-RESOLVED or approved plan exists")
- Each agent is a separate file in `.claude/agents/`

**Folder structure**:
```
.claude/
├── skills/
│   └── develop/
│       └── SKILL.md          # Orchestrator — parses sub-commands, enforces gates
└── agents/
    ├── brainstorm/SKILL.md   # Step 0
    ├── strategize/SKILL.md   # Step 1 (NEW)
    ├── plan/SKILL.md         # Step 2 (renamed from planner)
    ├── audit/SKILL.md        # Steps 3 & 5 (renamed from plan-auditor)
    ├── resolve/SKILL.md      # Steps 3b & 5b (NEW)
    ├── checklist/SKILL.md    # Step 4 (NEW)
    ├── implement/SKILL.md    # Step 6 (NEW)
    └── fix/SKILL.md          # Step 7 (NEW)
```

**Pros**:
- Clean separation: orchestrator knows flow, agents know their job
- Each agent is independently testable and reusable
- Sub-command naming is intuitive (`/develop plan`, `/develop audit`)
- Agents don't need to know about the workflow — they just do their stage

**Cons**:
- Skill prompt will be long (routing logic + gate checks + path conventions)
- Claude must parse free-text args to determine which agent to call
- No true enforcement — Claude "should" check gates but can be overridden

**Complexity**: Medium
**Risk**: Low

---

## Approach 2: Separate Skills Per Stage

**Summary**: Each sub-command is its own skill (`/develop-brainstorm`, `/develop-plan`, etc.)

**Pros**:
- Simpler per-skill prompts
- Each skill is fully self-contained

**Cons**:
- Loses the unified `/develop` entry point
- User must remember 8 different slash commands
- No shared orchestration logic (gates must be duplicated in each skill)
- Defeats the purpose of the orchestrator pattern

**Complexity**: Low
**Risk**: Medium (fragmentation, no enforcement)

---

## Approach 3: Skill + State File Tracking

**Summary**: Same as Approach 1, but the orchestrator maintains a state file (`Docs/.develop-state.json`) that tracks which stages have been completed for the current feature.

```json
{
  "feature": "wellness-calendar",
  "date": "260401",
  "stages": {
    "brainstorm": { "status": "completed", "output": "Docs/01_Brainstorming/260401-wellness-calendar-brainstorm.md" },
    "strategize": { "status": "completed", "output": "Docs/02_Planning/Specs/260401-wellness-calendar-strategy.md" },
    "plan": { "status": "completed", "output": "Docs/02_Planning/Specs/260401-wellness-calendar-plan.md" },
    "plan-audit": { "status": "needs-revision", "output": "Docs/03_Audits/260401-wellness-calendar-plan-audit.md" },
    "plan-resolve": { "status": "pending" },
    "checklist": { "status": "pending" },
    "checklist-audit": { "status": "pending" },
    "checklist-resolve": { "status": "pending" },
    "implement": { "status": "pending" },
    "fix": { "status": "pending" }
  }
}
```

**Pros**:
- Hard enforcement of stage gates (orchestrator reads state file before dispatching)
- Progress is visible and resumable across conversations
- Can show status with `/develop status`
- Multiple features can be tracked in parallel

**Cons**:
- Adds file I/O overhead to every invocation
- State file can become stale or out of sync with actual docs
- More complex orchestrator prompt
- JSON state management via Claude prompt is fragile

**Complexity**: High
**Risk**: Medium (state sync issues)

---

## Agent Design Decisions

### New Agents Needed

| Agent | Purpose | Input | Output |
|---|---|---|---|
| **strategize** | Focused strategy — narrower than brainstorm, feeds into plan | Topic description or brainstorm doc | `YYMMDD-[feature]-strategy.md` |
| **checklist** | Convert plan into ordered implementation checklist | Approved/resolved plan | `YYMMDD-[feature]-checklist.md` |
| **resolve** | Address audit findings, produce resolved version | Audit report + original doc | `YYMMDD-[feature]-[stage]-RESOLVED.md` |
| **implement** | Execute checklist items as code changes | Approved checklist | Code changes |
| **fix** | Build verification + error fixing | Build output | Clean build |

### Existing Agents to Rename/Refactor

| Current | New Name | Changes |
|---|---|---|
| `brainstorm` | `brainstorm` | Fix folder refs, remove ghost paths |
| `planner` | `plan` | Rename to match sub-command, fix folder refs |
| `plan-auditor` | `audit` | Generalize to audit both plans and checklists |
| `code-reviewer` | `code-reviewer` | Keep separate — not part of `/develop` flow |

### Strategize vs Brainstorm — What's the Difference?

| Aspect | Brainstorm (Step 0) | Strategize (Step 1) |
|---|---|---|
| **Purpose** | Explore the problem space | Define the solution direction |
| **Output** | Multiple approaches, open questions | Single chosen approach with rationale |
| **Scope** | Wide — "what could we do?" | Narrow — "what will we do and why?" |
| **Required?** | Optional | Yes (or brainstorm serves as strategy if deep enough) |
| **Reads** | Nothing (fresh exploration) | Brainstorm doc (if exists) + codebase |
| **Feeds into** | Strategize or Plan | Plan |

### Audit Agent — Dual Purpose

The `audit` agent must handle two contexts:
1. **Plan audit** (Step 3): Reviews the implementation plan for gaps, risks, feasibility
2. **Checklist audit** (Step 5): Reviews the checklist for completeness, ordering, missing steps

The orchestrator determines which mode by checking what stage the feature is in (or by the most recent unaudited artifact).

### Resolve Agent — How It Works

1. Reads the audit report (identifies issues by severity)
2. Reads the original document (plan or checklist)
3. Addresses each CRITICAL and HIGH issue
4. Produces a `-RESOLVED.md` version with changes annotated
5. This is a **hard stop** — user must review and approve before proceeding

---

## Docs Folder Structure — Current State Audit

### What Actually Exists (as of 2026-04-01)

```
Docs/
├── 01_Brainstorming/              # 7 brainstorm docs ✅ correct
├── 02_Planning/
│   ├── Brainstorming/             # 2 more brainstorm docs ❌ DUPLICATE location
│   ├── Plans/                     # 3 plan docs ❌ unclear distinction from Specs/
│   └── Specs/                     # 13 files: specs + RESOLVED + CHECKLISTs ❌ MIXED
├── 03_audit-plan/                 # EMPTY ❌ never used
├── 04_Checklist/
│   └── checklist/                 # 18 files — ALL are *-audit.md ❌ MISLABELED
├── 05_Resolves/                   # EMPTY ❌ never used
├── 06_Mischalleneous/             # 1 file ❌ typo in name
└── Features_Integration/          # 1 file (unnumbered)
```

### Critical Problems

**1. Brainstorms split across 2 locations**
- `01_Brainstorming/` has 7 files
- `02_Planning/Brainstorming/` has 2 files
- Agents don't know which to check; files get orphaned

**2. `04_Checklist/checklist/` contains AUDIT reports, not checklists**
- Every file is named `*-audit.md` (18 audit reports)
- The actual checklists (`CHECKLIST-APIClient-Implementation.md`, `CHECKLIST-StressView-AuditFixes.md`) live in `02_Planning/Specs/`
- This is the single biggest mislabel in the entire structure

**3. `02_Planning/Specs/` is a dumping ground**
- Contains specs (correct), RESOLVED docs (should be in 05_Resolves/), and CHECKLISTs (should be in 04_Checklist/)
- 3 different document types in one folder

**4. `02_Planning/Plans/` vs `02_Planning/Specs/` — no clear distinction**
- Plans/ has: `accent-color-change-plan.md`, `seven-agent-workflow-plan.md`, `barcode-scan-plan.md`
- Specs/ has: `stress-view.md`, `coffee-tracking.md`, `dark-light-mode-support.md`
- These are functionally the same thing (implementation plans/specs)

**5. Three empty or near-empty folders**
- `03_audit-plan/` — empty, never received any audit output
- `05_Resolves/` — empty, RESOLVED files went to `02_Planning/Specs/` instead
- Both were created with good intent but agents never wrote to them

**6. Agent SKILL.md files reference 4 ghost folder hierarchies**

| Ghost Path (in agent prompts) | Actual Location | Used By |
|---|---|---|
| `Docs/01_Transcripts/` | Does not exist at all | brainstorm, planner, plan-auditor |
| `Docs/04_Decisions/` | Does not exist (04 is Checklist) | brainstorm, planner, plan-auditor |
| `Docs/05_Audits/Code/` | Does not exist (05 is Resolves, empty) | plan-auditor (output path!) |
| `Docs/06_Maintenance/Patterns/` | Does not exist (06 is Mischalleneous) | planner, plan-auditor |

### File-by-File Migration Map

**Files that need to MOVE:**

| Current Location | Should Be | Reason |
|---|---|---|
| `02_Planning/Brainstorming/260325-home-ai-stress-insights-brainstorm.md` | `01_Brainstorming/` | Consolidate brainstorms |
| `02_Planning/Brainstorming/260401-feature-suggestions.md` | `01_Brainstorming/` | Consolidate brainstorms |
| `02_Planning/Specs/CHECKLIST-APIClient-Implementation.md` | `04_Checklist/` | It's a checklist, not a spec |
| `02_Planning/Specs/CHECKLIST-StressView-AuditFixes.md` | `04_Checklist/` | It's a checklist, not a spec |
| `02_Planning/Specs/260219-dark-light-mode-RESOLVED.md` | `05_Resolves/` | It's a resolved doc |
| `02_Planning/Specs/260322-coffee-tracking-RESOLVED.md` | `05_Resolves/` | It's a resolved doc |
| `02_Planning/Specs/260324-stress-view-dual-mode-ui-RESOLVED.md` | `05_Resolves/` | It's a resolved doc |
| All 18 files in `04_Checklist/checklist/*-audit.md` | `03_Audits/` | They're audits, not checklists |

**Folders to DELETE after migration:**
- `02_Planning/Brainstorming/` (emptied — brainstorms consolidated to 01)
- `02_Planning/Plans/` (merge into Specs/ — same purpose)
- `03_audit-plan/` (replace with `03_Audits/`)
- `04_Checklist/checklist/` (flatten — remove redundant nesting)

**Folders to RENAME:**
- `03_audit-plan/` → `03_Audits/` (receives the 18 audit files + future audits)
- `06_Mischalleneous/` → `06_Miscellaneous/` (fix typo)

---

## Proposed Canonical Docs Structure

After migration, aligned 1:1 with `/develop` workflow stages:

```
Docs/
├── 01_Brainstorming/                    # Step 0: /develop brainstorm
│   ├── 260311-accent-color-brainstorm.md
│   ├── 260314-meallog-audio-brainstorm.md
│   ├── 260315-barcode-scan-brainstorm.md
│   ├── 260325-home-ai-stress-insights-brainstorm.md  ← moved from 02_Planning/Brainstorming/
│   ├── 260401-develop-skill-brainstorm.md
│   ├── 260401-feature-suggestions.md                 ← moved from 02_Planning/Brainstorming/
│   ├── APIClient-Mock-Configuration.md
│   ├── FoodJournalView-Redesign-Brainstorm.md
│   └── HomeScreen-UI-Differentiation.md
│
├── 02_Planning/                         # Steps 1-2: /develop strategize, /develop plan
│   └── Specs/                           # Strategy docs + Plan docs (merged with Plans/)
│       ├── 260216-APIClient-Mock-Configuration.md
│       ├── 260216-APIClient-Mock-Configuration-v2.md
│       ├── 260219-dark-light-mode-support.md
│       ├── 260221-stress-view.md
│       ├── 260311-accent-color-change-plan.md         ← moved from Plans/
│       ├── 260311-home-drag-to-log-meal.md
│       ├── 260314-meallog-audio-to-text.md
│       ├── 260314-seven-agent-workflow-plan.md         ← moved from Plans/
│       ├── 260315-barcode-scan-plan.md                 ← moved from Plans/
│       ├── 260316-codex-workflow-improvements.md
│       ├── 260322-coffee-tracking.md
│       ├── 260324-stress-view-dual-mode-ui.md
│       └── 260325-stress-view-mock-mode.md
│
├── 03_Audits/                           # Steps 3 & 5: /develop audit
│   ├── 260311-accent-color-plan-audit.md              ← moved from 04_Checklist/checklist/
│   ├── 260314-meallog-audio-to-text-audit.md          ← moved from 04_Checklist/checklist/
│   ├── 260314-meallog-audio-to-text-impl-audit.md     ← moved from 04_Checklist/checklist/
│   ├── 260315-barcode-scan-plan-audit.md              ← moved from 04_Checklist/checklist/
│   ├── 260316-codex-workflow-improvements-audit.md    ← moved from 04_Checklist/checklist/
│   ├── 260322-coffee-tracking-audit.md                ← moved from 04_Checklist/checklist/
│   ├── 260324-stress-view-dual-mode-ui-audit.md       ← moved from 04_Checklist/checklist/
│   ├── 260325-home-ai-stress-insights-audit.md        ← moved from 04_Checklist/checklist/
│   ├── APIClient-Mock-Configuration-audit.md          ← moved from 04_Checklist/checklist/
│   ├── dark-light-mode-audit.md                       ← moved from 04_Checklist/checklist/
│   ├── food-aggregation-audit.md                      ← moved from 04_Checklist/checklist/
│   ├── goals-feature-audit.md                         ← moved from 04_Checklist/checklist/
│   ├── home-drag-to-log-meal-audit.md                 ← moved from 04_Checklist/checklist/
│   ├── liquid-glass-hero-audit.md                     ← moved from 04_Checklist/checklist/
│   ├── meallogview-audit.md                           ← moved from 04_Checklist/checklist/
│   ├── screentime-stress-view-audit.md                ← moved from 04_Checklist/checklist/
│   ├── stress-vitals-detail-views-audit.md            ← moved from 04_Checklist/checklist/
│   └── wellness-ring-navigation-audit.md              ← moved from 04_Checklist/checklist/
│
├── 04_Checklist/                        # Step 4: /develop checklist
│   ├── CHECKLIST-APIClient-Implementation.md          ← moved from 02_Planning/Specs/
│   └── CHECKLIST-StressView-AuditFixes.md             ← moved from 02_Planning/Specs/
│
├── 05_Resolves/                         # Steps 3b & 5b: /develop resolve
│   ├── 260219-dark-light-mode-RESOLVED.md             ← moved from 02_Planning/Specs/
│   ├── 260322-coffee-tracking-RESOLVED.md             ← moved from 02_Planning/Specs/
│   └── 260324-stress-view-dual-mode-ui-RESOLVED.md    ← moved from 02_Planning/Specs/
│
├── 06_Miscellaneous/                    # Renamed (typo fix)
│   └── deep-research-report.md
│
└── Features_Integration/               # Keep as-is (unnumbered, outside workflow)
    └── AI-Features-Integration.md
```

### Naming Convention (Enforced by `/develop`)

All new files follow: `YYMMDD-[feature-slug]-[stage].md`

| Stage | Suffix | Example |
|---|---|---|
| Brainstorm | `-brainstorm.md` | `260401-wellness-calendar-brainstorm.md` |
| Strategy | `-strategy.md` | `260401-wellness-calendar-strategy.md` |
| Plan | `-plan.md` | `260401-wellness-calendar-plan.md` |
| Plan Audit | `-plan-audit.md` | `260401-wellness-calendar-plan-audit.md` |
| Plan Resolved | `-plan-RESOLVED.md` | `260401-wellness-calendar-plan-RESOLVED.md` |
| Checklist | `-checklist.md` | `260401-wellness-calendar-checklist.md` |
| Checklist Audit | `-checklist-audit.md` | `260401-wellness-calendar-checklist-audit.md` |
| Checklist Resolved | `-checklist-RESOLVED.md` | `260401-wellness-calendar-checklist-RESOLVED.md` |

Legacy files (pre-convention) keep their current names — no mass rename.

---

## Agent SKILL.md — Required Path Fixes

Every agent's Research Protocol must be rewritten to reference **real** folders. Here is the corrected mapping:

### brainstorm agent
| Current (broken) | Fix to |
|---|---|
| `Docs/01_Transcripts/README.md` | **Remove** — folder never existed. Replace with: "Read `Docs/01_Brainstorming/` for prior brainstorms on related topics" |
| `Docs/04_Decisions/` | **Remove** — folder never existed. No ADR system in this project |
| `Docs/02_Planning/Future/` (output) | **Remove** — subfolder never existed |
| Output: `Docs/02_Planning/Brainstorming/` | Fix to: `Docs/01_Brainstorming/` |

**Corrected Research Protocol for brainstorm:**
```
1. Check existing brainstorms: Docs/01_Brainstorming/
2. Check related plans/specs: Docs/02_Planning/Specs/
3. Check related audits: Docs/03_Audits/
4. Last resort: Access source code
```

### planner → plan agent
| Current (broken) | Fix to |
|---|---|
| `Docs/01_Transcripts/README.md` | **Remove** |
| `Docs/01_Transcripts/` (multiple refs) | **Remove** |
| `Docs/04_Decisions/` | **Remove** |
| `Docs/06_Maintenance/Patterns/` | **Remove** — no patterns folder exists |

**Corrected Research Protocol for plan:**
```
1. Check brainstorms/strategy: Docs/01_Brainstorming/ and Docs/02_Planning/Specs/
2. Check related audits: Docs/03_Audits/
3. Check resolved docs: Docs/05_Resolves/
4. Last resort: Access source code
```

### plan-auditor → audit agent
| Current (broken) | Fix to |
|---|---|
| `Docs/01_Transcripts/` | **Remove** |
| `Docs/06_Maintenance/Patterns/` | **Remove** |
| `Docs/04_Decisions/` | **Remove** |
| Output: `Docs/05_Audits/Code/` | Fix to: `Docs/03_Audits/` |

**Corrected Research Protocol for audit:**
```
1. Read the document being audited (from Docs/02_Planning/Specs/ or Docs/04_Checklist/)
2. Check prior brainstorms: Docs/01_Brainstorming/
3. Check prior audits on same feature: Docs/03_Audits/
4. Last resort: Access source code
```

### code-reviewer agent
- No broken folder refs (uses `git diff`, not Docs/)
- Keep as-is, stays outside `/develop` flow

---

## `.claude/` Folder Cleanup

### Current state (duplicates everywhere)

```
.claude/
├── agents/
│   ├── brainstorm/SKILL.md      # Identical to skills/brainstorm/SKILL.md
│   ├── planner/SKILL.md         # Identical to skills/planner/SKILL.md
│   ├── plan-auditor/SKILL.md    # Identical to skills/plan-auditor/SKILL.md
│   └── code-reviewer/SKILL.md   # Identical to skills/code-reviewer/SKILL.md
├── skills/
│   ├── brainstorm/SKILL.md      # Duplicate
│   ├── planner/SKILL.md         # Duplicate
│   ├── plan-auditor/SKILL.md    # Duplicate
│   └── code-reviewer/SKILL.md   # Duplicate
└── worktrees/
    └── hardcore-nash/            # Stale worktree with ANOTHER copy of everything
        └── .claude/
            ├── agents/...       # 4 more copies
            └── skills/...       # 4 more copies
```

**16 SKILL.md files** for 4 agents. Should be 4.

### Proposed state (after `/develop` implementation)

```
.claude/
├── skills/
│   └── develop/
│       └── SKILL.md             # Orchestrator (user-invoked via /develop)
└── agents/
    ├── brainstorm/SKILL.md      # Step 0
    ├── strategize/SKILL.md      # Step 1 (NEW)
    ├── plan/SKILL.md            # Step 2 (refactored from planner)
    ├── audit/SKILL.md           # Steps 3 & 5 (refactored from plan-auditor)
    ├── resolve/SKILL.md         # Steps 3b & 5b (NEW)
    ├── checklist/SKILL.md       # Step 4 (NEW)
    ├── implement/SKILL.md       # Step 6 (NEW)
    ├── fix/SKILL.md             # Step 7 (NEW)
    └── code-reviewer/SKILL.md   # Independent (not part of /develop)
```

**Delete:**
- `skills/brainstorm/` — agent, not user-invoked skill
- `skills/planner/` — agent, not user-invoked skill
- `skills/plan-auditor/` — agent, not user-invoked skill
- `skills/code-reviewer/` — agent, not user-invoked skill
- `worktrees/hardcore-nash/` — stale worktree with 12 duplicate files

**Result:** 1 skill + 9 agents = 10 SKILL.md files (down from 16)

---

## Edge Cases to Consider

- [ ] User runs `/develop plan` without a prior strategy — should it proceed with just a topic description, or block?
- [ ] User runs `/develop audit` when both a plan and checklist exist — which gets audited? (Most recent unaudited artifact)
- [ ] User wants to re-run a stage (e.g., redo the plan after implementation started) — allow or warn?
- [ ] Feature naming conflicts (two features on same date with similar names)
- [ ] Long feature names in file paths — need a slug/shorthand convention
- [ ] User passes a file path vs a topic string — agent must handle both
- [ ] `/develop implement` on a checklist that hasn't been audited — soft warning or hard block?
- [ ] Multiple features in progress simultaneously — how does the orchestrator know which one `/develop audit` refers to?

---

## Open Questions

- [ ] Should `/develop status` be a sub-command that shows current feature progress? (Approach 3)
- [ ] Should the orchestrator auto-detect the current feature from recent git changes or require explicit naming?
- [ ] Do we delete the duplicate `.claude/agents/` files and keep only `.claude/skills/` (or vice versa)?
- [ ] Should `code-reviewer` be folded into the `/develop` flow as an optional post-implement step, or stay independent?
- [ ] What model should each agent use — Sonnet for speed, Opus for quality on critical stages (audit, implement)?

---

## Recommendation

**Approach 1 (Single Skill with Sub-command Router)** is the right starting point.

- It's the simplest architecture that delivers the full workflow
- Approach 3's state file adds complexity that can be layered on later if needed
- Approach 2 fragments the UX and defeats the orchestrator concept

**Implementation order**:
1. Fix Docs folder structure (prerequisite)
2. Create the `/develop` orchestrator skill
3. Create/refactor the 8 agents (brainstorm, strategize, plan, audit, checklist, resolve, implement, fix)
4. Update CLAUDE.md to reflect new workflow
5. Clean up duplicate files (agents/ vs skills/, worktrees/)

---

## Research References

- Current skill structure: `.claude/skills/brainstorm/SKILL.md` (pattern to follow)
- Current agent structure: `.claude/agents/planner/SKILL.md` (pattern to follow)
- Claude Code skill docs: Skills are user-invoked via `/skill-name`, agents are spawned programmatically
- Existing workflow doc: `CLAUDE.md` → "Development Workflow (.codex)" section
