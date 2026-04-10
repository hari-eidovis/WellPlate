# Claude Code Configuration — WellPlate

This directory powers [Claude Code](https://claude.ai/code) for the WellPlate iOS app. It provides a structured development workflow with specialized skills, agents, references, and an integrated code-review knowledge graph.

## Overview

The `.claude/` directory turns Claude Code from a general-purpose assistant into a project-aware development partner. It defines:

1. **Skills** — slash commands that trigger specialized behavior
2. **Agents** — sub-agents with focused roles, orchestrated by `/develop`
3. **References** — coding standards and test conventions Claude follows
4. **Hooks** — automatic actions (e.g., graph updates after edits)

## Skills

Skills are invoked as slash commands in Claude Code. Each skill has a `SKILL.md` that defines its behavior, tools, and model.

### `/develop` — Feature Development Orchestrator

The primary entry point for feature work. Routes to specialized sub-agents based on the sub-command:

```
/develop brainstorm <topic>   → Creative exploration
/develop strategize <topic>   → Choose one approach
/develop plan <topic>         → Detailed implementation plan
/develop audit <path>         → Review plan or checklist for issues
/develop resolve <path>       → Fix audit findings (requires user approval)
/develop checklist <path>     → Convert plan to step-by-step checklist
/develop implement <path>     → Execute checklist (writes code)
/develop fix                  → Fix build errors across all targets
```

**Workflow**: brainstorm → strategize → plan → audit → resolve → checklist → audit → resolve → implement → fix

Each stage produces a document in `Docs/` following the naming convention `YYMMDD-[feature-slug]-[stage].md`.

### `/commit` — Git Commit & Push

Analyzes all staged/unstaged changes, writes a descriptive commit message, commits, and pushes to GitHub. Uses the Haiku model for speed.

### `/brainstorm` — Standalone Brainstorming

Creative ideation without the full `/develop` pipeline. Explores possibilities, alternatives, and edge cases.

### `/code-reviewer` — Code Review

Runs immediately after writing or modifying code. Reviews for quality, security, performance, and maintainability against the project's coding standards.

### `/ui-ux-pro-max` — Design Intelligence

Comprehensive UI/UX design system with 67 styles, 96 color palettes, 57 font pairings, 25 chart types, and 13 technology stacks. Includes SwiftUI-specific guidance.

### Graph-Powered Skills

These skills leverage the `code-review-graph` MCP for structural code understanding:

| Skill | File | Purpose |
|---|---|---|
| Explore Codebase | `explore-codebase.md` | Navigate structure using the knowledge graph |
| Review Changes | `review-changes.md` | Structured review with change detection and impact analysis |
| Debug Issue | `debug-issue.md` | Systematic debugging using graph-powered navigation |
| Refactor Safely | `refactor-safely.md` | Dependency-aware refactoring with impact analysis |

## Agents

Agents live in `.claude/agents/` and are spawned by the `/develop` orchestrator. Each agent has a `SKILL.md` defining its role, available tools, and model. All agents use the Opus model for maximum quality.

| Agent | Role | Tools |
|---|---|---|
| `brainstorm` | Creative exploration of possibilities | Read, Grep, Glob, WebSearch, Write |
| `strategize` | Evaluate options, choose one approach | Read, Grep, Glob, Write |
| `plan` | Comprehensive implementation plans | Read, Grep, Glob, Write |
| `audit` | Review plans/checklists for risks | Read, Grep, Glob, Write |
| `resolve` | Fix audit findings (asks user for approval) | Read, Grep, Glob, Write, AskUserQuestion |
| `checklist` | Convert plans to actionable checklists | Read, Grep, Glob, Write |
| `implement` | Execute checklists, write code | Read, Grep, Glob, Write, Edit, Bash |
| `fix` | Fix build errors across all targets | Read, Grep, Glob, Edit, Bash |
| `code-reviewer` | Quality, security, performance review | Read, Grep, Glob, Bash |

## References

Reference documents in `.claude/references/` provide coding standards that Claude follows during implementation and review.

- **`coding-style.md`** — Swift/SwiftUI conventions: MVVM pattern, `@MainActor` discipline, font/color/shadow usage, navigation patterns, SwiftData usage, naming conventions, DI approach, logging, and a quality checklist.
- **`testing.md`** — Test strategy, mock/stub patterns, ViewModel test patterns, async test yielding, build/test commands, and priority guidelines for what to test.

## Settings

`settings.json` configures hooks that run automatically:

```json
{
  "hooks": {
    "PostToolUse": [{ "matcher": "Edit|Write|Bash", "command": "code-review-graph update ..." }],
    "SessionStart": [{ "command": "code-review-graph status --json" }],
    "PreCommit":    [{ "command": "code-review-graph detect-changes --brief" }]
  }
}
```

These keep the code-review knowledge graph in sync with file changes, enabling graph-powered skills and MCP tools.

## `.claudeignore`

Excludes paths from Claude's context:

```
/.codex
/.cursor
```

## Adding New Skills or Agents

### New Skill

1. Create `skills/<skill-name>/SKILL.md` (or `skills/<skill-name>.md` for simple skills)
2. Add YAML frontmatter: `name`, `description`, `tools`, `model`
3. Write the system prompt below the frontmatter

### New Agent

1. Create `agents/<agent-name>/SKILL.md`
2. Add YAML frontmatter (same format as skills)
3. Add a routing entry in `skills/develop/SKILL.md` if it should be part of the `/develop` pipeline

### Frontmatter Format

```yaml
---
name: my-skill
description: "One-line description of what this skill does"
tools: ["Read", "Grep", "Glob", "Write", "Edit", "Bash"]
model: opus        # opus | sonnet | haiku
extended_thinking: true  # optional
---
```

## Integration with Project

The `.claude/` configuration works alongside the root `CLAUDE.md` which contains:
- Build commands for all targets
- Project structure overview
- Architecture patterns (MVVM, SwiftData, HealthKit)
- UI conventions (fonts, colors, shadows, cards)
- Development workflow reference table
- MCP tools usage guidelines
