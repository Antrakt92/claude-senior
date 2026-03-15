# claude-code-config

Configuration, hooks, and memory for Claude Code AI agent — self-improving infrastructure for AI-only development workflow.

## What this is

A two-layer enforcement system where AI is fully responsible for code quality (user never reads code):

- **Global layer** (`~/.claude/`) — rules and hooks that fire in every project
- **Project layer** (`.claude/` per repo) — project-specific hooks and agents

## Architecture

```
~/.claude/                          ← GLOBAL (all projects)
├── CLAUDE.md                       ← 13 behavioral rules (Director Model, Ripple Effect, etc.)
├── settings.json                   ← permissions (bypassMode) + hook registration
└── hooks/
    ├── block-dangerous-git.sh      ← blocks force push, rm -rf, reset --hard, .env writes
    ├── block-protected-files.sh    ← blocks Edit/Write to .env*, lock files
    └── auto-lint-python.sh         ← ruff autofix after Edit/Write

project/.claude/                    ← PROJECT (per-repo)
├── settings.json                   ← project-specific hook registration
├── hooks/
│   ├── pre-commit-review.sh        ← Phase 1: linter check, Phase 2: review checklist
│   ├── auto-lint-typescript.sh     ← ESLint autofix (if TypeScript project)
│   └── check-css-variables.sh      ← CSS variable enforcement (if CSS project)
└── agents/
    ├── code-reviewer.md            ← code quality review agent
    ├── security-reviewer.md        ← security audit agent
    └── ripple-checker.md           ← finds all callers of changed functions
```

## How hooks work

All hooks use `exit 2 + stderr` to block and communicate with AI (VS Code silently discards `exit 0 + stdout`).

- **PreToolUse** hooks fire before tool execution — can block dangerous commands
- **PostToolUse** hooks fire after tool execution — can warn about issues
- **Marker file pattern**: hook blocks → AI does review → `touch /tmp/marker` → retry passes (expires 5 min)
- **Phase 1 (auto-checks)**: linter/type-checker errors — no marker bypass, must fix code
- **Phase 2 (checklist)**: manual review items — marker bypass after review

## Setup on new machine

```bash
# Clone
cd ~/Documents/GitHub
git clone https://github.com/YOUR_USER/claude-code-config.git

# Install global config
cp claude-code-config/global/CLAUDE.md ~/.claude/
cp claude-code-config/global/settings.json ~/.claude/
mkdir -p ~/.claude/hooks
cp claude-code-config/global/hooks/*.sh ~/.claude/hooks/

# Restore memory (optional)
mkdir -p ~/.claude/projects/c--Users-YOUR-USER-.../memory/
cp claude-code-config/memory/investments-calculator/*.md ~/.claude/projects/.../memory/
```

## Adding hooks to a new project

Global hooks (block-dangerous-git, block-protected-files, auto-lint-python) work automatically.

For project-specific hooks, copy from `projects/` templates:

- **TypeScript project**: copy from `projects/timesheet/`
- **Python project**: copy from `projects/clipboard-history/`
- **Full stack (Python + TS)**: copy from `projects/investments-calculator/`

## Repo structure

```
global/              ← what goes in ~/.claude/ (active config)
projects/            ← reference copies of per-project .claude/ configs
memory/              ← backup of ~/.claude/projects/*/memory/ (AI memory files)
```
