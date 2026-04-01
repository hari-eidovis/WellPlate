# Plan Audit Report: /develop Orchestrator Skill

**Audit Date**: 2026-04-01
**Plan Version**: Draft
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary

The plan is well-structured and thorough in its file migration and agent creation strategy. However, it contains a critical internal contradiction on where resolved files should live (three different locations across different sections), an incomplete worktree cleanup that only addresses 1 of 4 worktrees, and a self-destructive migration step that would delete the folder this audit report is written to before the workflow is even tested. The orchestrator SKILL.md prompt also has routing ambiguity that will cause incorrect dispatch behavior.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1: Resolve output path is contradicted three ways

The plan gives three different answers for where resolved files go:

| Location in Plan | Says Resolved Files Go To |
|---|---|
| Step 1.3 (migration) | `Docs/05_Resolves/` (moves 3 existing RESOLVED files there) |
| Step 2.7 (resolve agent) | `Docs/02_Planning/Specs/` for plan resolves, `Docs/04_Checklist/` for checklist resolves |
| Step 3.1 (orchestrator routing table) | `Docs/05_Resolves/` **or** back into source folder as `-RESOLVED.md` |

The brainstorm is consistent with Step 2.7 (resolved files live next to their source). But Step 1.3 moves existing RESOLVED files away from their sources into `05_Resolves/`, which contradicts the agent that would create new resolved files back in the source folder.

**Impact**: Agents and orchestrator will write to different locations. Gate checks (e.g., "find `*-plan-RESOLVED.md`") will look in the wrong folder.

**Fix**: Pick ONE strategy and apply it everywhere. Recommendation: keep resolved files next to their source (Step 2.7 approach), and do NOT move existing RESOLVED files out of `02_Planning/Specs/` in Step 1.3. This makes `05_Resolves/` unnecessary. Either repurpose it or delete it.

---

#### C2: Step 1.1 deletes `Docs/03_audit-plan/` -- the folder this audit was written to

The plan says in Step 1.1:
```bash
rmdir Docs/03_audit-plan
```

But the user's task instructions say to write this audit report to `Docs/03_audit-plan/260401-develop-skill-plan-audit.md`. If Step 1.1 runs, this file is destroyed (or `rmdir` fails because the folder is non-empty).

**Impact**: Either the migration step fails or the audit is lost.

**Fix**: Step 1.1 should also move any files from `Docs/03_audit-plan/` into `Docs/03_Audits/` before attempting `rmdir`. Use `mv Docs/03_audit-plan/* Docs/03_Audits/ 2>/dev/null` before the rmdir, or use `rm -rf` only after confirming contents have been migrated. Better yet, add an explicit note: "Check `03_audit-plan/` for any files added between planning and implementation."

---

#### C3: Orchestrator routing table has ambiguous "resolve" output

Step 3.1 routing table says:
```
| resolve [audit] | resolve | Path to audit report | Docs/05_Resolves/ or back into source folder as -RESOLVED.md |
```

"Or" is not a routing instruction. The orchestrator must give the resolve agent one deterministic path. Claude will guess, and different invocations will produce files in different locations.

**Fix**: Remove the ambiguity. Specify exactly one output location pattern (see C1 fix).

---

### HIGH (Should Fix Before Proceeding)

#### H1: Worktree cleanup is incomplete -- plan only deletes 1 of 4

The plan (Step 5.1) only deletes `hardcore-nash`. But `git worktree list` shows 4 worktrees beyond the main one:

| Worktree | Status |
|---|---|
| `ecstatic-sammet` | prunable |
| `hardcore-nash` | active |
| `magical-sutherland` | prunable |
| `zen-solomon` | prunable |

Three are already prunable (their branches may be gone). `hardcore-nash` contains 8 duplicate SKILL.md files as documented.

**Impact**: The success criterion says "No duplicate SKILL.md files remain (worktrees cleaned)". Deleting only `hardcore-nash` does not satisfy this. The other worktrees may also contain stale `.claude/` directories.

**Fix**: Add cleanup for all 4 worktrees. Run `git worktree prune` first to clean the prunable ones, then `rm -rf .claude/worktrees/hardcore-nash && git worktree remove hardcore-nash`.

---

#### H2: Plan deletes `skills/code-reviewer` but Step 2.11 says "keep code-reviewer as-is"

Step 2.1 deletes:
```bash
rm -rf .claude/skills/code-reviewer
```

Step 2.11 says:
> **File**: `.claude/agents/code-reviewer/SKILL.md` — **Action**: No changes. This agent stays independent.

This is technically consistent (deleting the skill duplicate, keeping the agent), but the plan does not address what happens if the user currently invokes `/code-reviewer` as a skill. Deleting the skill folder means `/code-reviewer` stops working as a slash command.

**Impact**: If the user has been invoking `/code-reviewer` as a skill (which the `skills/` folder enables), this silently breaks it.

**Fix**: Verify whether `/code-reviewer` is invoked as a skill (user-facing slash command) or only as an agent (programmatic subagent). The current system-reminder listing shows it as an available skill: `code-reviewer: Expert code review specialist...`. Deleting it from `skills/` will remove it from the slash command list. Either keep it in `skills/` or document this as an intentional breaking change.

---

#### H3: `rmdir Docs/04_Checklist/checklist` will fail if glob doesn't match all files

Step 1.1 runs:
```bash
mv Docs/04_Checklist/checklist/*-audit.md Docs/03_Audits/
rmdir Docs/04_Checklist/checklist
```

The glob `*-audit.md` assumes every file in that directory ends with `-audit.md`. Verified: all 18 files do match. However, if any non-audit file exists at execution time (e.g., a `.DS_Store` file on macOS), `rmdir` will fail because the directory won't be empty.

**Fix**: Use `rm -rf Docs/04_Checklist/checklist` instead of `rmdir`, or add `find Docs/04_Checklist/checklist -name '.DS_Store' -delete` before the rmdir.

---

#### H4: `brainstorm` and related skills still listed in system-reminder as user-invocable skills

The current system-reminder shows these as available skills:
- `brainstorm`
- `code-reviewer`
- `plan-auditor`
- `planner`

After Step 2.1 deletes these from `.claude/skills/`, users lose the ability to invoke them directly. The plan assumes all invocation goes through `/develop`, but users may want to run `/brainstorm` independently (e.g., for non-feature brainstorming).

**Fix**: Either (a) acknowledge this is intentional and document it, or (b) keep `brainstorm` and `code-reviewer` as standalone skills alongside the `/develop` orchestrator. The brainstorm use case in particular is broader than the `/develop` workflow.

---

### MEDIUM (Fix During Implementation)

#### M1: No rollback plan for the Docs migration

The plan says "Git tracks the moves" as mitigation, but doesn't specify what to do if migration is partially completed and something fails. Steps 1.1-1.6 are presented as sequential, but there's no checkpoint or commit between them.

**Fix**: Add a git commit after Phase 1 completion (before Phase 2). This creates a clean rollback point.

---

#### M2: Gate check for `checklist` only looks for plan files, not strategy

Step 3.1 gate rule for `checklist`:
> Check for `*-plan-RESOLVED.md` first (preferred), then `*-plan.md`. If neither exists, warn.

But the workflow allows skipping the plan and going from strategy directly (unlikely but possible). The gate should also handle the case where a plan exists but hasn't been audited/resolved -- currently it only checks existence, not audit status.

**Fix**: Add an optional warning: "Plan exists but has not been audited. Consider running `/develop audit` first."

---

#### M3: Naming convention inconsistency for legacy audit files

The naming convention says `YYMMDD-[feature-slug]-[stage].md`, but many existing audit files don't follow this pattern:
- `APIClient-Mock-Configuration-audit.md` (no date prefix)
- `dark-light-mode-audit.md` (no date prefix)
- `food-aggregation-audit.md` (no date prefix)

The plan says "Legacy files keep their current names -- no mass rename." This is fine, but the orchestrator's auto-detection logic (finding "most recent unaudited" artifact) relies on date prefixes for sorting. Files without dates will sort alphabetically before dated ones and may be incorrectly selected.

**Fix**: Document that auto-detection only works reliably for files with the `YYMMDD-` prefix. Legacy files require explicit path arguments.

---

#### M4: `fix` agent has no `Write` tool but `implement` does

Step 2.10 gives the `fix` agent tools: `["Read", "Grep", "Glob", "Edit", "Bash"]` -- no `Write`. Step 2.9 gives `implement`: `["Read", "Grep", "Glob", "Write", "Edit", "Bash"]`.

If the `fix` agent needs to create a new file (e.g., a missing file that causes a build error), it cannot. This is likely intentional (fix should only edit, not create), but should be explicitly stated.

**Fix**: Add a note in the `fix` agent prompt: "You can only edit existing files. If a fix requires creating a new file, report it as unresolvable."

---

#### M5: Orchestrator prompt does not specify how to spawn agents

The orchestrator SKILL.md (Step 3.1) describes routing logic but never explains the mechanism for dispatching to an agent. In Claude Code, skills don't automatically have the ability to invoke agents. The skill prompt needs to use the `Skill` tool or the `Agent` tool (if available) to spawn subagents, or it needs to instruct the user to run the agent manually.

**Fix**: Clarify the dispatch mechanism. If skills can invoke agents via the `Skill` tool, document it. If not, the orchestrator should output the command for the user to run next (e.g., "Run: `/develop plan wellness-calendar`" which re-invokes the same skill with a different subcommand, and the skill itself does the work by reading the agent's SKILL.md as instructions).

---

### LOW (Consider for Future)

#### L1: No `status` sub-command

The brainstorm's Approach 3 proposed a `/develop status` command. While the plan deliberately chose Approach 1 (no state file), even a lightweight `status` that just scans Docs folders for the most recent feature's artifacts would be useful.

**Fix**: Consider adding a `status` subcommand that runs `find Docs -name "YYMMDD-*" | sort` and groups by feature slug.

---

#### L2: Multiple simultaneous features not addressed

The brainstorm lists this as an edge case: "Multiple features in progress simultaneously -- how does the orchestrator know which one `/develop audit` refers to?"

The plan's gate rules in Step 3.1 say "Find the most recent file... matching the feature slug" but don't explain how the feature slug is determined when the user just types `/develop audit` with no argument.

**Fix**: Add a fallback: if no feature slug is provided and multiple recent features exist, list them and ask the user to specify.

---

#### L3: `strategize` is a new concept not validated

The brainstorm introduces `strategize` as Step 1 between brainstorm and plan. This is a new agent that doesn't exist in the current workflow. The distinction between brainstorm and strategize (exploratory vs. focused) is clear in theory but may feel redundant in practice for small features.

**Fix**: No change needed now, but consider making strategize optional (skippable) with no gate enforcement, same as brainstorm.

---

## Missing Elements

1. **No git commit strategy**: The plan doesn't say when to commit during implementation. Should Phase 1 (Docs migration) be one commit? Should each phase be a separate commit? This matters for rollback.

2. **No verification of skill/agent dispatch mechanism**: The plan assumes the orchestrator skill can spawn agents, but doesn't verify how Claude Code's skill-to-agent dispatch actually works. This is the single biggest technical unknown.

3. **No handling of the `260401-develop-skill-plan.md` file itself**: The plan lives in `Docs/02_Planning/Specs/` and references the brainstorm in `Docs/01_Brainstorming/`. After migration, the plan itself becomes a test case -- but it's not listed in any migration step.

4. **No test plan**: The success criteria list what to verify, but there's no step that says "test the `/develop` skill end-to-end with a dummy feature."

5. **Extension target builds not considered in `fix` agent**: The `fix` agent's build command only runs the main WellPlate scheme. CLAUDE.md lists 3 additional build targets (ScreenTimeMonitor, ScreenTimeReport, WellPlateWidget). If implementation touches shared code, the fix agent won't catch extension build failures.

---

## Unverified Assumptions

1. **Skills can invoke agents**: The plan assumes the orchestrator skill can dispatch to agents in `.claude/agents/`. The actual mechanism for this in Claude Code is not documented in the plan.

2. **`rmdir` works on macOS with hidden files**: macOS frequently creates `.DS_Store` files in directories. Multiple `rmdir` commands in the plan will fail silently or noisily if these exist.

3. **Agents get the orchestrator's context**: The brainstorm notes "agents spawned by the skill run as subagents -- they get the SKILL.md prompt but don't see prior conversation context unless explicitly passed." The plan's dispatch protocol says to pass file paths, but doesn't address whether the agent can see the user's original request text.

4. **All 18 files in `04_Checklist/checklist/` are audit files**: Verified -- all 18 match `*-audit.md`. This assumption holds.

5. **`02_Planning/Plans/` has exactly 3 files**: Verified -- confirmed 3 files. This assumption holds.

---

## Questions for Clarification

1. **Resolve destination**: Should resolved files live next to their source (plan-RESOLVED in `02_Planning/Specs/`, checklist-RESOLVED in `04_Checklist/`) or in a separate `05_Resolves/` folder? This must be decided before implementation.

2. **Standalone skill access**: After migration, should users still be able to run `/brainstorm` and `/code-reviewer` directly, or must everything go through `/develop`?

3. **Dispatch mechanism**: How exactly does a SKILL.md file spawn an agent? Does it use the `Skill` tool, the `Agent` tool, or does the skill's prompt simply contain the agent's full instructions?

4. **Commit granularity**: Should the entire migration be one atomic commit, or phased commits per step?

5. **This audit file's fate**: This audit is written to `Docs/03_audit-plan/`. Step 1.1 deletes that folder. Should this file be migrated to `Docs/03_Audits/` as part of Step 1.1?

---

## Recommendations

1. **Fix C1 immediately**: Pick one resolve output strategy. Recommend keeping resolved files next to their sources and making `05_Resolves/` a dead folder (or removing it entirely).

2. **Fix C2 before running Step 1.1**: Add a line to move contents of `03_audit-plan/` to `03_Audits/` before deleting the folder.

3. **Add a commit checkpoint after Phase 1**: This gives a clean rollback point before the more complex agent work begins.

4. **Verify the skill-to-agent dispatch mechanism** with a minimal prototype before writing all 8 agent SKILL.md files. If skills can't spawn agents, the entire architecture needs to change.

5. **Keep `/brainstorm` and `/code-reviewer` as standalone skills** in addition to being agents. They have use cases outside the `/develop` workflow.

6. **Clean up ALL worktrees**, not just `hardcore-nash`. Run `git worktree prune` as a first step.

7. **Use `rm -rf` instead of `rmdir`** for all directory deletions to handle `.DS_Store` and other hidden files on macOS.
