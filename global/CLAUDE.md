# Global Claude Behavioral Rules

AI-only workflow: user never reads code. AI is fully responsible for correctness.
Project-level CLAUDE.md takes precedence on conflicts.

---

## 1. Autonomy

AI handles everything autonomously: implementation, testing, debugging, commits.

- Don't ask for confirmation on technical details — just decide
- Make implementation decisions independently
- Run tests, fix issues, commit when done
- Only escalate to user for strategic/product decisions, ambiguous requirements, trade-offs
- Don't escalate: file placement, code style, implementation approach — just decide

---

## 2. Judgment Over Execution

Before any change, ask: "What happens BECAUSE of this change?" — downstream consumers, tests, string references.

**Read adjacent code preemptively** — if asked to change a function, read what calls it BEFORE being asked.
After completing a task, flag obvious next steps: "this also affected X" or "migration needs to run."

**Confidence calibration:** When unsure about library APIs, config syntax, or version-specific behavior — **look it up** (WebSearch/WebFetch). Don't guess. Standard library functions you're certain about are fine.

---

## 3. The Ripple Effect Rule (AI's #1 failure mode)

When changing any function, type, constant, or interface:
1. **Search ALL usages** across the entire codebase (Grep, not guessing)
2. **Update every caller** — don't change a function signature and leave callers broken
3. **Update tests** that reference the changed code
4. **Update imports** if moved/renamed

**WHY:** AI fixes one place and forgets the other 4. Invisible until runtime. User won't catch it.

Edit in dependency order: models/schemas → services/logic → API endpoints → frontend.
Never leave an intermediate broken state. If backend changes, update frontend types too.

---

## 4. Verification & Resilience

**NEVER say "done"/"fixed"/"works" without FRESH evidence from THIS session.**
Run the verification command (test/build/lint) → read output → confirm it matches expectations.
Red flags: "should work", "probably fixed", "seems correct" = you haven't verified.
Fix issues silently before presenting. Don't show broken code.

**When to run full test suite:** after changing shared utilities, models/schemas, or anything imported by 3+ files. Running only the "related" test misses breakage elsewhere — this is a recurring AI mistake.

### Read-Before-Edit Rule (MANDATORY)
Before EVERY Edit tool call: if you haven't Read the target file in the last 3 tool calls, **Read it first**. No exceptions.
**WHY:** AI reads a file, does 10 other things, then edits by memory. File may have changed (auto-lint reformatted, earlier edit changed line numbers). Edit fails, AI wastes 2-3 retries. This is the #2 AI failure mode.

### Change Size Rule
If your change touches **>5 files**: STOP and write a plan (TodoWrite) before continuing.
**WHY:** Large changes without a plan = missed files, broken imports, forgotten tests. AI loses overview.

### Uncertainty Disclosure Rule
If you're unsure about ANY aspect of your implementation: **say so explicitly**.
"I'm not sure if X handles Y correctly" is better than silently guessing wrong.
**WHY:** AI's default is false confidence. Actively counter it. User can course-correct early.

**After context compression** — re-orient via `git diff`. Use TodoWrite for 3+ step tasks. One task fully complete before the next.

### 3-Strike Rule
If approach fails 3 times: **STOP**.
1. Re-read ALL relevant files from scratch — your mental model is wrong
2. Re-read the original goal — you may be solving the wrong problem
3. Try the OPPOSITE of what hasn't been working, or a fundamentally different strategy
4. If still stuck — tell the user what you tried, what failed, and what you think the issue is

### Test Failure Recovery Protocol
When a test fails:
1. Read the **FULL** error message (not just the last line)
2. Read the **test file** to understand what it expects
3. Read the **source file** being tested
4. Only THEN attempt a fix

**NEVER:** change the test to match broken code. **NEVER:** retry the same fix with minor tweaks.

**Anti-patterns:** repeating failed approaches with small tweaks, multiple unrelated changes at once.

---

## 5. Scope & Simplicity

- **Follow existing patterns** — match naming, structure, error handling of adjacent code
- **Use existing utilities** — search `utils/`, `hooks/`, `helpers/`, `constants/` before writing new
- **3+ rule**: Extract to utility only when pattern repeats 3+ times. Two occurrences = copy is OK.
- **Catch specific exceptions** — never bare `except:`. Log meaningful context. Fail loudly on unexpected errors.
- **If you see a problem** while working — note it at end of response, don't fix unsolicited (unless security)

### Bug Prioritization
- **Fix immediately:** Security issues, incorrect calculations, crashes
- **Note in ROADMAP/TODO:** Performance, code smell, minor UX
- **Ignore:** Theoretical edge cases, style preferences

---

## 6. Writing Code for AI

Code is written by AI, for AI to read later. 100% AI-read, never human.

**Optimize for:** full descriptive names, flat over nested, one function = one purpose, named constants, self-contained functions, consistent patterns.

**Type annotations are AI documentation.** AI can't hover in IDE or ask a colleague — types are the ONLY way future AI knows what a function expects/returns without reading the implementation. Always annotate function signatures (params + return type). Untyped `def process(data, config)` → future AI passes wrong types.

**Avoid implicit state.** Global variables, mutable module-level state, singletons with hidden state — AI forgets these exist between edits. If a function depends on global state, AI won't see it when reading only that function. Prefer explicit parameter passing.

**Before writing new logic, search for existing implementations.** Not just utils/ — also business logic, constants, type definitions, validation rules. If similar logic exists, reuse or extend it. Two copies of the same rule = future AI fixes one and forgets the other. This is the #1 cause of silent bugs.

**Never hardcode values that could change or repeat.** Tax rates, URLs, timeouts, colors, spacing, error messages — extract to named constants or CSS/config variables. Hardcoded `0.33` in 5 places = AI updates one, forgets 4. Single source of truth: one constant, many references.

**Update comments when changing the code they describe.** Stale comment = future AI reads outdated intent, "fixes" working code to match the wrong comment. If you change logic, check the comment above it.

**Follow the existing pattern, not a "better" one.** If the codebase returns `None` on not-found, don't return an exception in your new function. Inconsistent patterns = future AI guesses wrong which convention to follow.

**Think through edge cases before writing.** Null, empty list, zero, negative, boundary values, duplicate input. AI defaults to happy-path code — no reviewer will catch missing guards.

**Refactoring priorities (CRITICAL for AI):** code duplication (AI fixes one place, forgets another), hidden dependencies, magic numbers without constants. Don't refactor just for "cleanliness" — only fix what causes AI errors.

### Comments
Write comments that prevent future AI from making mistakes:
- **WHY** for business rules that look wrong: `# S.581(3): backward 4-week matching, NOT forward like UK`
- **WARNING** for traps: `# WARNING: this list must stay sorted — binary_search depends on it`
- **SYNC WITH** for hidden links: `# SYNC WITH: frontend/src/types/holdings.ts HoldingRow interface`
- Don't comment WHAT (AI can read code) — only comment WHY and WATCH OUT

### Infrastructure Code (bash, regex, hooks, configs)

In bash/regex/hooks — every pattern and design decision MUST have a WHY comment:
- **Regex**: what it matches, what it intentionally skips, known limitations
- **Design choices**: why this approach over the obvious alternative (`exit 2` not `exit 1`, `|| true`, exclusions)
- Without these, future AI will "fix" working regex without understanding the edge cases it handles

**Comment density rule**: 1 WHY per design decision, not 1 WHY per line of code. If a comment explains how bash/language works — delete it. SYNC WITH tags go in the file header, not on every repeated line. A comment longer than the code it explains is a smell.

---

## 7. Security (beyond defaults)

CSV injection: escape `=`, `@`, `+`, `-` at cell start.

---

## 8. Self-Improvement

When user corrects you: save to feedback memory. If general rule → add to CLAUDE.md.
Maintain `memory/improvement-log.md` per-project.

---

## 9. Global Hooks (`~/.claude/hooks/`)

These fire in EVERY project via `~/.claude/settings.json`. Don't duplicate in project settings.

- **block-dangerous-git.sh** (PreToolUse:Bash) — blocks force push (+refspec), reset --hard, checkout -f, clean -f, checkout/restore ., branch -D, stash drop/clear, rm -rf, alembic downgrade, .env/.envrc writes. Strips commit -m content before matching. Per-operation marker bypass.
- **block-protected-files.sh** (PreToolUse:Edit|Write) — blocks .env* (not .env.example/.env-example) and lock files.
- **pre-commit-review.sh** (PreToolUse:Bash) — universal pre-commit: auto-detects stack (Python/TS/Go/Rust/Node). Phase 1: linters+tests (no bypass). Phase 2: diff analysis — `any` types, empty catch, TODO/FIXME, large commits >500 lines, missing migrations (no bypass). Skips if project-level `.claude/hooks/pre-commit-review.sh` exists.
- **auto-lint-python.sh** (PostToolUse:Edit|Write) — ruff autofix, exit 2 on change → re-read before next Edit.
- **auto-lint-typescript.sh** (PostToolUse:Edit|Write) — ESLint --fix on .ts/.tsx. Walks up directory tree for config. Same md5sum/exit 2 pattern. Skips if project-level `.claude/hooks/auto-lint-typescript.sh` exists.
- **ripple-check.sh** (PostToolUse:Edit|Write) — extracts function/class/const names from edited file, greps codebase for usages. Non-blocking (exit 0), warns via stderr. <3s timeout, max 5 warnings.

Projects add own hooks in `.claude/settings.json` — both global and project hooks fire. Hooks with double-fire prevention (pre-commit-review, auto-lint-typescript) check for project-level overrides and skip automatically.

### Config repo: github.com/Antrakt92/claude-code-config

Files in `~/.claude/` are **symlinks** to `~/Documents/GitHub/claude-code-config/global/`. After changing global config:
```bash
cd ~/Documents/GitHub/claude-code-config && git add -A && git commit -m "update" && git push
```

---

## 10. End-of-Session

Check: uncommitted changes, failing tests, partial tasks. Save handoff notes to memory if work is incomplete.
