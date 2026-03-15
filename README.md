# claude-code-config

A battle-tested enforcement system for Claude Code that makes AI agents self-reviewing, self-correcting, and safe by default. Built for AI-only workflows where the developer directs and the AI implements everything autonomously.

## The Problem

Claude Code with `bypassPermissions: true` can run any command without asking. One hallucinated `rm -rf src/` or `git push --force` and your work is gone. CLAUDE.md rules help, but AI follows them ~80% of the time — and degrades in long conversations.

## The Solution

Three layers of defense, each catching what the previous misses:

| Layer | Mechanism | Enforcement |
|-------|-----------|-------------|
| **CLAUDE.md** | Behavioral rules (13 sections) | Advisory — AI follows most of the time |
| **Hooks** | Shell scripts triggered on every tool call | Mandatory — `exit 2` physically blocks the action |
| **Memory** | Persistent knowledge between sessions | Cumulative — AI learns from past mistakes |

Hooks are the only layer that **forces** compliance. Everything else is a suggestion.

## What the Hooks Do

### Global hooks (fire in every project, zero config)

| Hook | Trigger | What it blocks |
|------|---------|---------------|
| `block-dangerous-git.sh` | PreToolUse:Bash | `git push --force`, `reset --hard`, `clean -f`, `checkout .`, `restore .`, `branch -D`, `rm -rf` on source dirs, `alembic downgrade`, writes to `.env*` files |
| `block-protected-files.sh` | PreToolUse:Edit\|Write | Direct edits to `.env*` (not `.env.example`) and lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`) |
| `auto-lint-python.sh` | PostToolUse:Edit\|Write | Nothing — auto-runs `ruff check --fix` + `ruff format`, then forces AI to re-read the file before next edit |

### Project hooks (per-repo, adapt to your stack)

| Hook | What it does |
|------|-------------|
| `pre-commit-review.sh` | Two-phase commit gate. Phase 1: runs your linter/type-checker (ruff, tsc, etc.) — **blocks until code passes, no bypass**. Phase 2: shows review checklist — blocks until AI confirms review via marker file. |
| `auto-lint-typescript.sh` | Same as auto-lint-python but for ESLint. Runs `--fix`, forces re-read on change. |
| `check-css-variables.sh` | Warns when AI writes hard-coded hex colors, pixel values, or transitions instead of CSS variables. |

### How hooks communicate with AI

Claude Code in VS Code **silently discards** `exit 0` + `stdout`. The only way to talk to the AI is `exit 2` + `stderr`. Every hook in this system uses this pattern.

**Marker file pattern** for "block then allow" flow:
```
Hook blocks with exit 2 → AI reads stderr message → AI does the review →
AI runs: touch /tmp/claude-marker-HASH → AI retries the command → Hook sees marker → exit 0
```
Markers are per-operation and expire after 5 minutes (prevents stale markers from crashed sessions).

## Architecture

```
~/.claude/                              GLOBAL — all projects
├── CLAUDE.md                           13 behavioral rules
├── settings.json                       permissions + global hook registration
└── hooks/
    ├── block-dangerous-git.sh          PreToolUse:Bash
    ├── block-protected-files.sh        PreToolUse:Edit|Write
    └── auto-lint-python.sh             PostToolUse:Edit|Write

project/.claude/                        PROJECT — per-repo overrides
├── settings.json                       project hook registration (no duplicates with global!)
├── hooks/
│   ├── pre-commit-review.sh            PreToolUse:Bash (commit gate)
│   ├── auto-lint-typescript.sh         PostToolUse:Edit|Write
│   └── check-css-variables.sh          PostToolUse:Edit|Write
└── agents/
    ├── code-reviewer.md                quality review on staged changes
    ├── security-reviewer.md            security audit (OWASP, injection, auth)
    └── ripple-checker.md               finds all callers of changed functions
```

Both global and project hooks fire on every tool call. **Never register the same hook in both** — it will run twice.

## CLAUDE.md Rules (what the AI follows)

13 sections covering autonomous AI behavior:

| Section | Purpose |
|---------|---------|
| **Director Model** | User gives direction, AI makes all technical decisions |
| **Judgment Over Execution** | Think about consequences before changing code |
| **Session Awareness** | Check memory/git at start, re-read files before editing |
| **Ripple Effect Rule** | Search ALL callers before changing any function/type/constant |
| **After Writing Code** | Mandatory self-review checklist, verify before saying "done" |
| **Scope & Simplicity** | Do exactly what was asked, follow existing patterns |
| **Writing Code for AI** | Optimize for AI readability: descriptive names, WHY comments |
| **Infrastructure Code** | Every regex/hook MUST have WHY comments explaining edge cases |
| **Security Fundamentals** | Injection, XSS, auth, file upload, secrets |
| **Recovery & Escalation** | 3-strike rule: if approach fails 3 times, stop and rethink |
| **Self-Improvement** | Log mistakes to memory, create rules to prevent recurrence |
| **Global Hooks** | Documents hook architecture and what fires globally |
| **End-of-Session** | Check uncommitted changes, save handoff notes to memory |

## Memory System (L0/L1/L2 Tiered Loading)

Inspired by [OpenViking](https://github.com/volcengine/OpenViking). Reduces token consumption by ~90%:

| Tier | What | Size | When loaded |
|------|------|------|-------------|
| **L0** | `MEMORY.md` index with inline summaries | ~200 tokens | Always (every conversation start) |
| **L1** | `summary` field in file frontmatter | ~50 tokens each | Visible in L0 — AI decides relevance without opening file |
| **L2** | Full file contents | 100-500 tokens each | Only when AI decides it needs the details |

Memory file format:
```markdown
---
name: improvement-log
description: Mistakes, root causes, rules created
type: project
summary: "5 bugs fixed: Bybit phantom SELL, Binance fee matching, CoinGecko price=0 cache poisoning..."
---

[full content here]
```

## Installation

### New machine setup

```bash
git clone https://github.com/YOUR_USER/claude-code-config.git
cd claude-code-config
bash install.sh
```

The install script copies `global/` to `~/.claude/` (backs up existing files first).

### Adding hooks to a project

Global hooks work automatically after install. For project-specific hooks:

**TypeScript project** (Next.js, React, etc.):
```bash
mkdir -p your-project/.claude/hooks
cp projects/timesheet/.claude/settings.json your-project/.claude/
cp projects/timesheet/.claude/hooks/*.sh your-project/.claude/hooks/
```

**Python project**:
```bash
mkdir -p your-project/.claude/hooks
cp projects/clipboard-history/.claude/settings.json your-project/.claude/
cp projects/clipboard-history/.claude/hooks/*.sh your-project/.claude/hooks/
```

**Full stack (Python + TypeScript)**:
```bash
cp -r projects/investments-calculator/.claude your-project/
```

Then adapt: change directory paths in `pre-commit-review.sh`, adjust linter commands to match your project.

## Repo Structure

```
global/              what goes in ~/.claude/ — active global config
projects/            reference copies of per-project .claude/ configs (3 templates)
memory/              backup of per-project AI memory files
install.sh           setup script for new machines
```

## Test Suite

61 tests covering all hook logic:
```bash
cd your-project && bash .claude/hooks/test-hooks.sh
```

Tests cover: command matching, false positive/negative edge cases, JSON escape handling, chained command splitting, CSS pattern detection.

## Known Limitations

- **String-based analysis only** — hooks can't inspect `bash script.sh` contents or `python -c "..."` payloads
- **No variable expansion detection** — `CMD="git push --force" && $CMD` bypasses checks
- **`rm -f -r` with split flags** — only catches `-rf`/`-r` as single flag cluster, not separate `-f -r`
- **CSS checker is per-line** — `linear-gradient(#fff, var(--x))` skipped because line contains `var(--`

These are documented in hook comments as `KNOWN LIMITATION` tags.

## Contributing

Found a bypass? Open an issue with the exact command that passes when it shouldn't. Include:
1. The command
2. Which hook should catch it
3. Why the current regex misses it
