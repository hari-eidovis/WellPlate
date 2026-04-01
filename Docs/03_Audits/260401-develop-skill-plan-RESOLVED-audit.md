# Second-Pass Audit: /develop Plan (RESOLVED)

**Audit Date**: 2026-04-01
**Auditor**: plan-auditor agent (second pass)
**Verdict**: APPROVED WITH WARNINGS

---

## Original Audit Resolution Verification

| ID | Severity | Fixed? | Notes |
|---|---|---|---|
| C1 | CRITICAL | YES | Resolved correctly. RESOLVED files now stay next to their source in `02_Planning/Specs/` (for plans) or `04_Checklist/` (for checklists). Step 1.3 now leaves RESOLVED files in place and deletes the empty `05_Resolves/`. Routing table in Step 3.1 matches. Resolve agent in Step 2.7 matches. All three locations now agree. |
| C2 | CRITICAL | YES | Resolved correctly. Step 1.1 now runs `mv Docs/03_audit-plan/* Docs/03_Audits/ 2>/dev/null` before `rm -rf Docs/03_audit-plan`. The file count is updated to 19 (18 + 1). |
| C3 | CRITICAL | YES | Resolved correctly. Routing table in Step 3.1 now shows deterministic paths: plan-RESOLVED goes to `Docs/02_Planning/Specs/`, checklist-RESOLVED goes to `Docs/04_Checklist/`. The "or" ambiguity is gone. |
| H1 | HIGH | YES | Resolved correctly. Step 5.1 now runs `git worktree prune`, then `git worktree remove .claude/worktrees/hardcore-nash --force`, then `rm -rf .claude/worktrees`, plus cleanup of all 4 orphaned branches. |
| H2 | HIGH | YES | Resolved correctly. Only `planner` and `plan-auditor` are deleted from `skills/`. `brainstorm` and `code-reviewer` are kept as standalone skills. Requirements section updated to "16 -> 12: 1 orchestrator + 2 standalone skills + 9 agents". |
| H3 | HIGH | YES | Resolved correctly. All `rmdir` commands replaced with `rm -rf` throughout. Step 1.1, 1.3, 1.4, 1.5 all use `rm -rf`. |
| H4 | HIGH | YES | Resolved via H2. `brainstorm` kept as standalone skill. Success criteria updated to show `brainstorm/`, `code-reviewer/`, `develop/` in `ls .claude/skills/`. |
| M1 | MEDIUM | YES | Resolved correctly. Step 1.7 now includes `git add Docs/ && git commit` as a checkpoint after Phase 1. |
| M2 | MEDIUM | YES | Resolved correctly. Gate rule 5 (`checklist`) now includes: "If plan exists but no matching `*-plan-audit.md` in `Docs/03_Audits/` -> warn." |
| M3 | MEDIUM | YES | Resolved correctly. Naming Convention section now explicitly states: "Auto-detection of feature slug only works for files with `YYMMDD-` prefix. Legacy files without date prefixes require explicit path arguments." |
| M4 | MEDIUM | YES | Resolved correctly. Step 2.10 (`fix` agent) now includes an explicit bold note: "You can only edit existing files (no Write tool). If a fix requires creating a new file, report it as unresolvable." |
| M5 | MEDIUM | YES | Resolved correctly. Dispatch Mechanism section added to the orchestrator (Step 3.1): the skill reads the agent's SKILL.md as inline instructions and executes the work directly. No sub-process spawning. This is the correct architecture for Claude Code skills. |

**Summary**: All 13 original audit findings were genuinely addressed with concrete changes, not hand-waved.

---

## New Issues Found

### MEDIUM

#### N1: `05_Resolves/` deletion may conflict with brainstorm's canonical structure

Step 1.3 deletes `Docs/05_Resolves/` with `rm -rf`. The brainstorm document established a canonical Docs structure that included `05_Resolves/`. While the resolved plan correctly decides not to use it (RESOLVED files stay next to sources), any reference to `05_Resolves/` in the brainstorm doc or other planning documents becomes stale.

**Impact**: Low. The brainstorm is a historical document. No code or agent references `05_Resolves/`.

**Recommendation**: Acceptable as-is. The resolved plan's rationale is sound. No action needed.

---

#### N2: Brainstorm SKILL.md exists in both `skills/brainstorm/` and `agents/brainstorm/`

Step 2.3 says to rewrite the agent copy AND "also update `.claude/skills/brainstorm/SKILL.md` with the same path fixes." This means `brainstorm` has two SKILL.md files that must be kept in sync. The original plan's audit flagged duplicate SKILL.md files as a problem (the motivation for the cleanup), yet this resolution intentionally preserves one duplicate.

**Impact**: Medium. If the files drift apart in future edits, the standalone `/brainstorm` and the `/develop brainstorm` dispatch could behave differently.

**Recommendation**: This is a conscious tradeoff (standalone invocability vs. single source of truth). Acceptable, but Step 2.3 should note that both files must be updated together. It currently does say this, so it passes.

---

#### N3: The `fix` agent only builds the main scheme in its example command

Step 2.10 shows the fix agent running only:
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate ... build 2>&1
```

The `implement` agent (Step 2.9) was fixed to run all 4 build targets, but the `fix` agent's prompt only shows the main scheme. The audit's Missing Element 5 was about build targets, and while it was marked resolved for `implement`, the `fix` agent still has the same gap.

**Impact**: Medium. If a code fix breaks an extension target, the fix agent will report "build clean" when it is not.

**Recommendation**: Update the `fix` agent's build command to run all 4 targets, or at minimum document that it only checks the main scheme and extension builds should be verified separately.

---

#### N4: Step 1.7 file count may be off by 1

Step 1.7 says "TOTAL: 48 files" and lists `02_Planning/Specs/` as having "16 files (13 original + 3 from Plans/, 3 RESOLVED stay)". But the RESOLVED plan itself (`260401-develop-skill-plan-RESOLVED.md`) now also exists in `02_Planning/Specs/`, making it 4 RESOLVED files, not 3. The plan document being implemented is itself in the count.

**Impact**: Low. This is a documentation inaccuracy in the verification step, not a functional issue.

**Recommendation**: Update the expected count or note that the count is approximate and should be verified at execution time.

---

#### N5: Unclosed code fence in Step 3.1 orchestrator prompt

The orchestrator SKILL.md prompt in Step 3.1 has an unclosed code fence. Line 581-582 shows:
```
```
```

There is a stray triple-backtick closing a code block that was never opened (after the Workflow Summary section). This is a markdown formatting issue in the plan document that could cause confusion during implementation.

**Impact**: Low. The implementer will need to determine the correct fence structure.

**Recommendation**: Fix the stray backtick before checklist generation.

---

### LOW

#### N6: Step 5.1 branch deletion uses `-D` (force) without checking merge status

```bash
git branch -D claude/ecstatic-sammet claude/hardcore-nash claude/magical-sutherland claude/zen-solomon 2>/dev/null
```

Using `-D` (force delete) is appropriate here since these are worktree branches being cleaned up, but the `2>/dev/null` suppresses any errors. This is fine given the context (cleanup of known-stale branches).

**Impact**: None. Correct use of force delete for stale worktree branches.

**Recommendation**: No change needed.

---

#### N7: No explicit test step for the dispatch mechanism

The resolved plan added a risk entry: "Dispatch mechanism doesn't work as expected — Test with one sub-command (`/develop brainstorm test`) before writing all agents." However, this risk mitigation is not reflected in the execution order or any implementation step. There is no Step X that says "test dispatch with one command."

**Impact**: Low. The implementer can test organically, but having it as an explicit step would be better.

**Recommendation**: Consider adding a verification substep after Phase 3 (before Phase 4): "Test `/develop brainstorm test-topic` end-to-end to confirm dispatch works."

---

## Verification of Specific Concerns

### Does deleting `05_Resolves/` create problems?
No. The folder is currently empty (verified). No agent, skill, or plan references it as an output destination in the resolved version. The brainstorm's canonical structure included it, but the resolved plan supersedes the brainstorm.

### Does keeping brainstorm in both `skills/` and `agents/` cause duplication problems?
Partially. See N2 above. It is a conscious, documented tradeoff. The plan instructs updating both copies in Step 2.3, which mitigates drift.

### Is the dispatch mechanism correct for Claude Code?
Yes. The resolved plan describes: "Read the agent's SKILL.md as inline instructions and execute the work directly." This is the correct pattern. Claude Code skills cannot spawn sub-processes or invoke agents as subagents. The skill reads the agent prompt and follows it as its own instructions. This is sound.

### Are the bash commands correct for macOS?
Yes. All `rmdir` replaced with `rm -rf`. `mv` commands use `2>/dev/null` where source may not exist. `mkdir -p` used for target creation. `git worktree prune` and `git worktree remove --force` are both valid git commands.

### Does the execution order have hidden dependency issues?
One minor issue: Step 2.2 (rename agents) depends on Step 2.1, but the resolved plan's execution order lists 2.1 and 2.2 as separate lines without an explicit arrow. However, the dependency is stated in Step 2.2's "Dependencies" field. This is adequate.

### Are success criteria complete and testable?
Yes. The resolved plan has 13 success criteria, all testable. They cover folder structure, ghost references, skill/agent listings, end-to-end invocation, gate rules, CLAUDE.md consistency, worktree cleanup, standalone skill availability, and RESOLVED file placement.

### Is there anything blocking checklist generation?
No blockers. Two minor items to address first:
1. Fix N3 (fix agent build targets) -- or accept the limitation
2. Fix N5 (stray backtick) -- trivial formatting fix

---

## Readiness for Checklist Generation

**Verdict: READY** -- with minor fixes recommended.

The resolved plan is comprehensive, internally consistent, and addresses all original audit findings. The new issues found (N1-N7) are all MEDIUM or LOW severity. None are blockers.

**Before generating the checklist, consider fixing:**
1. **N3** (fix agent should build all 4 targets, not just main) -- MEDIUM, functional gap
2. **N5** (stray backtick in orchestrator prompt) -- LOW, formatting

**Can proceed to checklist without fixing:**
- N1 (05_Resolves deletion) -- acceptable
- N2 (brainstorm duplication) -- conscious tradeoff, documented
- N4 (file count off by 1) -- cosmetic
- N6 (branch -D) -- correct behavior
- N7 (no explicit test step) -- nice-to-have
