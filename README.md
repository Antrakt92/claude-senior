# claude-senior

> Claude Code says "done" without running tests. Commits `: any` types. Changes a function signature and leaves 4 callers broken. Leaves `console.log` in production code.
>
> **claude-senior** makes it stop doing that.

<p align="center">
  <a href="assets/demo.svg">
    <img src="assets/demo.svg?v=3" alt="Demo: pre-commit quality gate blocking bad code" width="780">
  </a>
</p>

## Quick start

```bash
git clone https://github.com/Antrakt92/claude-senior.git
cd claude-senior
bash install.sh
```

That's it. Next time Claude Code runs, it's a senior dev.

## What it catches

Every commit is automatically blocked until:

| Check | What happens |
|-------|-------------|
| `console.log("debug")` | **Blocked.** Use `console.warn` or `console.error`. |
| `const x: any = 1` | **Blocked.** Use a proper type. |
| `catch (e) {}` | **Blocked.** Add error handling. |
| `// TODO fix later` | **Blocked.** Fix it now or don't commit. |
| 500+ lines in one commit | **Blocked.** Split into smaller commits. |
| `entities.py` changed, no migration | **Blocked.** Create the migration. |
| `git push --force` | **Blocked.** Use `--force-with-lease`. |
| `rm -rf src/` | **Blocked.** Are you sure? |
| Write to `.env` | **Blocked.** Secrets stay out of AI. |
| Changed a function used in 5 files | **Warned.** Did you update all callers? |

Plus: `ruff check` + `pytest` + `tsc --noEmit` + `eslint --max-warnings 0` on every commit. No bypass.

## Why this exists

Vanilla Claude Code is a strong junior developer. These are the failure modes that keep it there:

| Failure mode | What goes wrong |
|-------------|-----------------|
| **Ripple effect** (#1 AI failure) | Changes function signature, leaves 4 callers broken |
| **Stale mental model** (#2 AI failure) | Edits file from memory instead of re-reading — breaks things |
| **False confidence** | Says "fixed" without running tests — "should work" = hasn't verified |
| **Code duplication** | Creates new helper instead of finding the existing one |
| **Hardcoded values** | `0.33` in 5 places — updates one, forgets four |
| **Happy-path only** | No null/empty/boundary guards — no reviewer will catch it |
| **Loop-and-tweak** | Retries same failing approach 5 times instead of rethinking |

**claude-senior** addresses all of these with three layers:

| Layer | What it does |
|-------|-------------|
| **Behavioral rules** (CLAUDE.md) | Shapes how the AI thinks — "re-read the file before editing", "search ALL callers before changing a function", "stop after 3 failed attempts" |
| **Automated enforcement** (7 hooks) | Catches violations automatically — blocks commits, warns about callers, auto-formats code |
| **Persistent learning** (memory) | AI logs mistakes and learns from them across sessions |

No existing Claude Code plugin does this. Plugins add new tools (browser, database). **claude-senior** makes the AI better at using the tools it already has.

## Architecture

```
~/.claude/                              GLOBAL — all projects
├── CLAUDE.md                           10 behavioral rules
├── settings.json                       permissions + hook registration
└── hooks/
    ├── block-dangerous-git.sh          blocks destructive git/rm/env commands
    ├── block-protected-files.sh        blocks .env and lockfile edits
    ├── pre-commit-review.sh            quality gate: linters + tests + diff analysis
    ├── auto-lint-python.sh             ruff autofix after every edit
    ├── auto-lint-typescript.sh         eslint autofix after every edit
    └── ripple-check.sh                 warns when edited code is used elsewhere

project/.claude/                        PROJECT — per-repo overrides
├── settings.json                       project-specific hooks
└── hooks/
    └── pre-commit-review.sh            project-specific checks (e.g. console.log)
```

Global hooks fire in every project. Project hooks override globals with double-fire prevention.

## How it works

### Pre-commit quality gate

Every `git commit` triggers a two-phase check:

**Phase 1 — Linters & tests** (auto-detected per stack):
- Python: `ruff check` + `pytest`
- TypeScript: `tsc --noEmit` + `eslint`
- Go: `go vet` + `go test`
- Rust: `cargo check` + `cargo test`

**Phase 2 — Diff analysis** (greps staged diff for anti-patterns):
- `: any`, `<any>`, `as any` in TypeScript
- `catch (e) {}`, bare `except:` — empty error handling
- `TODO`, `FIXME`, `HACK`, `XXX` — unfinished work
- `console.log` — debug code (only `console.warn`/`error` allowed)
- 500+ added lines — commit too large
- Model changes without migration

Both phases block with no bypass. Fix the code, retry.

### Safety net

`block-dangerous-git.sh` intercepts destructive commands before execution:

```
git push --force       →  BLOCKED (use --force-with-lease)
git reset --hard       →  BLOCKED (stash first)
git checkout .         →  BLOCKED (stash first)
rm -rf src/            →  BLOCKED (rm -rf node_modules/ is whitelisted)
echo SECRET > .env     →  BLOCKED (edit .env manually)
```

Per-operation bypass via marker file (single-use, 5-minute expiry) when user explicitly approves.

### Ripple effect protection

After every file edit, `ripple-check.sh` greps the codebase for definitions you just changed and warns:

```
RIPPLE CHECK: definitions in tax_calculator.py are also used in:
  calculate_total_tax → src/service.py:42 src/api.py:18
  TaxCalculator → src/views.py:7
Did you update all callers?
```

Non-blocking (exit 0) — it's a reminder, not a gate.

### Auto-formatting

After every `Edit`/`Write`:
- Python files → `ruff check --fix` + `ruff format`
- TypeScript files → `eslint --fix`

If the formatter changes the file, the AI is forced to re-read it before the next edit. This prevents the #2 failure mode (editing from stale memory).

## CLAUDE.md Rules

10 sections of behavioral rules:

| Rule | What it prevents |
|------|-----------------|
| **Ripple Effect Rule** | "Search ALL usages before changing any function" — prevents broken callers |
| **Read-Before-Edit Rule** | "Re-read file if not read in last 3 tool calls" — prevents stale edits |
| **3-Strike Rule** | "Stop and rethink after 3 failed attempts" — prevents loop-and-tweak |
| **Test Failure Recovery** | "Read error → read test → read source → then fix" — prevents guessing |
| **Change Size Rule** | "5+ files → write a plan first" — prevents lost overview |
| **Uncertainty Disclosure** | "If unsure, say so explicitly" — prevents false confidence |
| **Verification Rule** | "Never say 'done' without fresh test evidence" — prevents shipping broken code |

Plus: autonomy guidelines, code style for AI readability, security rules, self-improvement protocol.

## Adding project-specific hooks

Global hooks work automatically. For project-specific checks, copy a template:

```bash
# TypeScript project
cp -r projects/timesheet/.claude your-project/

# Python project
cp -r projects/clipboard-history/.claude your-project/

# Full stack (Python + TypeScript)
cp -r projects/investments-calculator/.claude your-project/
```

Then adapt `pre-commit-review.sh` to your stack.

## Test suite

```bash
# Global hooks
bash ~/.claude/hooks/test-hooks.sh

# Project hooks (from project root)
bash .claude/hooks/test-hooks.sh
```

## Known limitations

- **String-based analysis** — can't inspect `bash script.sh` contents or variable expansion
- **No AST parsing** — ripple check uses regex, may miss complex patterns
- **Per-line CSS check** — `linear-gradient(#fff, var(--x))` skipped because line contains `var(--`

All documented in hook source as `KNOWN LIMITATION` tags.

## Contributing

Found a bypass? Open an issue with the exact command, which hook should catch it, and why the regex misses it.
