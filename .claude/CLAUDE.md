# .claude Directory

This directory configures [Claude Code](https://claude.ai/code) for the WellPlate project. It contains custom skills, agents, references, and settings that define how Claude assists with development.

## Structure

```
.claude/
├── CLAUDE.md           # This file
├── README.md           # Detailed documentation for contributors
├── .claudeignore       # Paths excluded from Claude's context
├── settings.json       # Hooks and runtime configuration
├── skills/             # Slash-command skills (invoked via /skill-name)
│   ├── develop/        # /develop — feature development orchestrator
│   ├── commit/         # /commit — git commit + push workflow
│   ├── brainstorm/     # /brainstorm — creative ideation
│   ├── code-reviewer/  # /code-reviewer — post-edit code review
│   ├── ui-ux-pro-max/  # /ui-ux-pro-max — design intelligence (67 styles, 96 palettes, 13 stacks)
│   ├── explore-codebase.md  # Graph-powered codebase navigation
│   ├── review-changes.md    # Structured change review
│   ├── debug-issue.md       # Graph-powered debugging
│   └── refactor-safely.md   # Dependency-aware refactoring
├── agents/             # Sub-agents spawned by /develop orchestrator
│   ├── brainstorm/     # Creative exploration
│   ├── strategize/     # Approach selection
│   ├── plan/           # Implementation planning
│   ├── audit/          # Plan/checklist review
│   ├── resolve/        # Audit finding resolution
│   ├── checklist/      # Step-by-step checklist generation
│   ├── implement/      # Checklist execution
│   ├── fix/            # Build error fixer
│   └── code-reviewer/  # Quality/security review
└── references/         # Coding standards and conventions
    ├── coding-style.md # Swift/SwiftUI conventions, patterns
    └── testing.md      # Test strategy, patterns, commands
```

## Quick Reference

| Command | Purpose |
|---|---|
| `/develop brainstorm <topic>` | Explore ideas for a feature |
| `/develop plan <topic>` | Create an implementation plan |
| `/develop implement <path>` | Execute a checklist |
| `/develop fix` | Fix build errors |
| `/commit` | Stage, commit, and push changes |
| `/brainstorm <topic>` | Standalone brainstorming |
| `/code-reviewer` | Review recently modified code |

## Hooks

Configured in `settings.json`:
- **PostToolUse**: Updates the code-review-graph after file edits
- **SessionStart**: Checks graph status on conversation start
- **PreCommit**: Runs change detection before commits
