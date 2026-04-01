# Implementation Checklist: `/develop` Orchestrator Skill

**Source Plan**: [Resolved Plan](../../02_Planning/Specs/260401-develop-skill-plan-RESOLVED.md)
**Date**: 2026-04-01

---

## Phase 1: Docs Folder Migration

### 1.1 — Create `03_Audits/` and consolidate all audit files

- [x] `mkdir -p Docs/03_Audits`
- [x] `mv Docs/04_Checklist/checklist/*-audit.md Docs/03_Audits/`
- [x] `mv Docs/03_audit-plan/* Docs/03_Audits/ 2>/dev/null`
- [x] `rm -rf Docs/04_Checklist/checklist`
- [x] `rm -rf Docs/03_audit-plan`

### 1.2 — Move checklists to `04_Checklist/`

- [x] `mv "Docs/02_Planning/Specs/CHECKLIST-APIClient-Implementation.md" Docs/04_Checklist/`
- [x] `mv "Docs/02_Planning/Specs/CHECKLIST-StressView-AuditFixes.md" Docs/04_Checklist/`

### 1.3 — Delete empty `05_Resolves/`

- [x] `rm -rf Docs/05_Resolves`

### 1.4 — Consolidate brainstorms into `01_Brainstorming/`

- [x] `mv "Docs/02_Planning/Brainstorming/260325-home-ai-stress-insights-brainstorm.md" Docs/01_Brainstorming/`
- [x] `mv "Docs/02_Planning/Brainstorming/260401-feature-suggestions.md" Docs/01_Brainstorming/`
- [x] `rm -rf Docs/02_Planning/Brainstorming`

### 1.5 — Merge `Plans/` into `Specs/`

- [x] `mv Docs/02_Planning/Plans/260311-accent-color-change-plan.md Docs/02_Planning/Specs/`
- [x] `mv Docs/02_Planning/Plans/260314-seven-agent-workflow-plan.md Docs/02_Planning/Specs/`
- [x] `mv Docs/02_Planning/Plans/260315-barcode-scan-plan.md Docs/02_Planning/Specs/`
- [x] `rm -rf Docs/02_Planning/Plans`

### 1.6 — Fix typo in `06_Mischalleneous/`

- [x] `mv Docs/06_Mischalleneous Docs/06_Miscellaneous`

### 1.7 — Verify and commit

- [x] Verified directory structure matches target
- [ ] Git commit checkpoint

---

## Phase 2: `.claude/` Cleanup & Agent Creation

### 2.1 — Delete superseded skill duplicates

- [ ] `rm -rf .claude/skills/planner`
- [ ] `rm -rf .claude/skills/plan-auditor`

### 2.2 — Rename agents to match sub-command names

- [ ] `mv .claude/agents/planner .claude/agents/plan`
- [ ] `mv .claude/agents/plan-auditor .claude/agents/audit`

### 2.3 — Rewrite brainstorm agent (+ standalone skill copy)

- [ ] Rewrite `.claude/agents/brainstorm/SKILL.md`
- [ ] Copy to `.claude/skills/brainstorm/SKILL.md`

### 2.4 — Create `strategize` agent

- [ ] `mkdir -p .claude/agents/strategize`
- [ ] Write `.claude/agents/strategize/SKILL.md`

### 2.5 — Rewrite `plan` agent (formerly `planner`)

- [ ] Rewrite `.claude/agents/plan/SKILL.md`

### 2.6 — Rewrite `audit` agent (formerly `plan-auditor`)

- [ ] Rewrite `.claude/agents/audit/SKILL.md`

### 2.7 — Create `resolve` agent

- [ ] `mkdir -p .claude/agents/resolve`
- [ ] Write `.claude/agents/resolve/SKILL.md`

### 2.8 — Create `checklist` agent

- [ ] `mkdir -p .claude/agents/checklist`
- [ ] Write `.claude/agents/checklist/SKILL.md`

### 2.9 — Create `implement` agent

- [ ] `mkdir -p .claude/agents/implement`
- [ ] Write `.claude/agents/implement/SKILL.md`

### 2.10 — Create `fix` agent

- [ ] `mkdir -p .claude/agents/fix`
- [ ] Write `.claude/agents/fix/SKILL.md`

### 2.11 — Code-reviewer: no changes

- [ ] Confirm `.claude/agents/code-reviewer/SKILL.md` exists
- [ ] Confirm `.claude/skills/code-reviewer/SKILL.md` exists

---

## Phase 3: Create `/develop` Orchestrator Skill

### 3.1 — Write the orchestrator SKILL.md

- [ ] `mkdir -p .claude/skills/develop`
- [ ] Write `.claude/skills/develop/SKILL.md`

### 3.2 — Smoke test the orchestrator

- [ ] Verify `.claude/skills/` contains: `brainstorm/`, `code-reviewer/`, `develop/`
- [ ] Verify `.claude/agents/` contains all 9 agent folders

---

## Phase 4: Update CLAUDE.md

### 4.1 — Replace workflow section

- [ ] Replace "Development Workflow (.codex)" section with new `/develop` sub-command table

### 4.2 — Update Key Files table

- [ ] Add `/develop` orchestrator to the table

---

## Phase 5: Cleanup

### 5.1 — Remove all worktrees

- [ ] `git worktree prune`
- [ ] `git worktree remove .claude/worktrees/hardcore-nash --force 2>/dev/null`
- [ ] `rm -rf .claude/worktrees`
- [ ] Delete stale branches

### 5.2 — Final git commit

- [ ] `git add .claude/ CLAUDE.md Docs/`
- [ ] Commit
