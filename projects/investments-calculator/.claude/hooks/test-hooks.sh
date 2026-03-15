#!/bin/bash
# Test suite for Claude Code hooks. Run: bash .claude/hooks/test-hooks.sh
# Tests hook logic (command matching, file blocking, CSS detection).
# Pre-commit auto-checks (ruff/tsc) tested separately — they need real project state.
#
# WHY not test auto-lint hooks: they need real ruff/eslint binaries and real .py/.ts files.
# Testing would require mock file creation + cleanup. The value is low — auto-lint hooks
# are simple (md5sum before/after), and ruff/eslint are themselves well-tested.
#
# WHY >/dev/null 2>&1 on every test: hooks output to stderr (their blocking messages).
# We only care about exit codes, not output text. Keeps test output clean.

PASS=0
FAIL=0

# WHY check() helper (not assert/set -e): soft-fail allows ALL tests to run even if
# some fail. With set -e, the first failure would abort — you'd miss later regressions.
check() {
  local desc="$1"
  local expected_exit="$2"
  local actual_exit="$3"
  if [ "$actual_exit" = "$expected_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== pre-commit-review.sh (command matching) ==="

# WHY these 3 tests: verify the regex (^|&& |; |\| )git commit doesn't false-positive
# on commands that merely CONTAIN "git commit" as a substring.
# "git status" = no match at all. "echo git commit" = "echo " before "git", not a separator.
# "grep git commit" = "grep " before "git", not a separator.
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash .claude/hooks/pre-commit-review.sh >/dev/null 2>&1
check "'git status' → allowed (not a commit)" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"echo git commit"}}' | bash .claude/hooks/pre-commit-review.sh >/dev/null 2>&1
check "'echo git commit' → allowed (not real commit)" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"grep git commit README"}}' | bash .claude/hooks/pre-commit-review.sh >/dev/null 2>&1
check "'grep git commit' → allowed (not real commit)" 0 $?

echo ""
echo "=== block-dangerous-git.sh ==="

# --- Git force push ---
# WHY test both --force and -f: AI uses both forms. The regex must catch both.
# WHY test --force-with-lease separately: it's the SAFE variant — must NOT be blocked.
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git push --force → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git push --force-with-lease → allowed" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git push -f"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git push -f → blocked" 2 $?

# --- Git destructive operations ---
# WHY test each: these are the 5 most common ways AI destroys uncommitted work.
echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git reset --hard → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git branch -D feature"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git branch -D → blocked" 2 $?

# WHY -d allowed: -d is "safe delete" — only deletes if branch is fully merged.
# -D force-deletes even unmerged branches — that's the dangerous one.
echo '{"tool_name":"Bash","tool_input":{"command":"git branch -d feature"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git branch -d → allowed" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git clean -fd"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git clean -fd → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git checkout ."}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git checkout . → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git restore ."}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git restore . → blocked" 2 $?

# WHY "git checkout main" allowed: switching branches is safe. Only "." (all files) is dangerous.
echo '{"tool_name":"Bash","tool_input":{"command":"git checkout main"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git checkout main → allowed (not .)" 0 $?

# --- rm -rf protection ---
# WHY test source dir vs whitelisted dir: the whitelist must allow cleanup of build artifacts
# (node_modules, __pycache__, dist) while blocking deletion of source code (backend/, src/).
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf backend/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -rf backend/ → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -rf node_modules/ → allowed (whitelisted)" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf __pycache__/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -rf __pycache__/ → allowed (whitelisted)" 0 $?

# WHY -rfv: tests that extra flags (v=verbose) between -r and target don't bypass the check.
# The regex -[a-zA-Z]*r[a-zA-Z]* catches any flag cluster containing 'r'.
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rfv src/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -rfv src/ → blocked" 2 $?

# WHY "rm -f file.txt" allowed: -f without -r is not recursive — only deletes a single file.
# Not dangerous enough to block (AI needs to delete temp files, test fixtures, etc.).
echo '{"tool_name":"Bash","tool_input":{"command":"rm -f file.txt"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -f file.txt (no -r) → allowed" 0 $?

# WHY test "rm -r" without -f: the check triggers on -r (recursive), not -f (force).
# dist/ and coverage/ are whitelisted build artifacts.
echo '{"tool_name":"Bash","tool_input":{"command":"rm -r dist/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -r dist/ → allowed (whitelisted)" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"rm -r coverage/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -r coverage/ → allowed (whitelisted)" 0 $?

# --- Database protection ---
# WHY test downgrade vs upgrade: downgrade drops tables/columns — destructive.
# upgrade is the normal migration path — must be allowed.
echo '{"tool_name":"Bash","tool_input":{"command":"alembic downgrade -1"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "alembic downgrade → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"alembic upgrade head"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "alembic upgrade → allowed" 0 $?

# --- .env protection (Bash redirects) ---
# WHY test redirect AND cp: block-dangerous-git.sh catches Bash-level .env writes
# (redirects, cp, mv) that bypass block-protected-files.sh (which only sees Edit/Write).
echo '{"tool_name":"Bash","tool_input":{"command":"echo SECRET=x > .env"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "> .env → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"echo SECRET=x > .env.local"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "> .env.local → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"echo SECRET=x > .env.production"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "> .env.production → blocked" 2 $?

# WHY .env.example allowed: template file with placeholder values, safe to write.
echo '{"tool_name":"Bash","tool_input":{"command":"echo FOO=bar > .env.example"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "> .env.example → allowed" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"cp backup .env.local"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "cp to .env.local → blocked" 2 $?

echo ""
echo "--- Edge cases: checkout/restore with -- ---"

# WHY test: "git checkout -- ." is the standard POSIX form (more common than bare "git checkout .")
echo '{"tool_name":"Bash","tool_input":{"command":"git checkout -- ."}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git checkout -- . → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git restore -- ."}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git restore -- . → blocked" 2 $?

# Targeted checkout of specific file — should NOT be blocked
echo '{"tool_name":"Bash","tool_input":{"command":"git checkout -- src/app.ts"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git checkout -- src/app.ts → allowed (specific file)" 0 $?

echo ""
echo "--- Edge cases: rm whitelist chaining ---"

# WHY test: whitelist used to check full string — "node_modules" in first rm
# made the whole chained command pass, including "rm -rf backend/"
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules/ && rm -rf backend/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -rf node_modules/ && rm -rf backend/ → blocked (chained)" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules/ && rm -rf __pycache__/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -rf node_modules/ && rm -rf __pycache__/ → allowed (both whitelisted)" 0 $?

# Semicolon separator (same logic as &&)
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf dist/; rm -rf src/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -rf dist/; rm -rf src/ → blocked (chained via ;)" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"rm --recursive src/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm --recursive src/ → blocked (long form)" 2 $?

# WHY test pipe chaining: the whitelist used to only split on && and ;.
# Piped "rm -rf safe/ | rm -rf dangerous/" bypassed because safe target appeared in full string.
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules/ | rm -rf src/"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "rm -rf node_modules/ | rm -rf src/ → blocked (piped)" 2 $?

echo ""
echo "--- Edge cases: JSON escaped quotes in commands ---"

# WHY test: the old [^"]* regex truncated at first \", losing chained commands after quotes.
# With the fix, ([^"\\]|\\.)*  correctly matches through escaped characters.
# WHY \" not \\": in single quotes, \" is literal backslash-quote (JSON escaped quote).
# \\" would be backslash-backslash-quote (JSON escaped backslash + end of string).
echo '{"tool_name":"Bash","tool_input":{"command":"echo \"test\" && git push --force"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "echo \"test\" && git push --force → blocked (quotes in first cmd)" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix: bug\" && git push --force origin main"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "commit + push --force chained → blocked (escaped quotes)" 2 $?

# WHY no pre-commit JSON-quote test: pre-commit exits 0 when nothing is staged
# (empty commit fails on its own). Testing commit detection with quotes requires
# staged files. The JSON extraction fix is validated by the dangerous-git tests above.

echo ""
echo "--- Edge cases: .env false positives ---"

# WHY test: .env substring in .environment should NOT trigger
echo '{"tool_name":"Bash","tool_input":{"command":"echo x > config.environment.json"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "> config.environment.json → allowed (not .env)" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"echo x > .envoy-config"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "> .envoy-config → allowed (not .env)" 0 $?

# But .env.staging should still be blocked
echo '{"tool_name":"Bash","tool_input":{"command":"echo x > .env.staging"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "> .env.staging → blocked" 2 $?

# Safe --force variants should pass
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force-if-includes"}}' | bash .claude/hooks/block-dangerous-git.sh >/dev/null 2>&1
check "git push --force-if-includes → allowed (safe variant)" 0 $?

echo ""
echo "=== block-protected-files.sh ==="

# WHY these tests: verify .env* glob catches all dotenv variants while allowing .env.example.
# Also verify lock file list is exact (not a glob that catches unrelated .lock files).
echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/.env"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit .env → blocked" 2 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/.env.local"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit .env.local → blocked" 2 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/.env.production"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit .env.production → blocked" 2 $?

# WHY .env.example allowed: template with placeholder values, safe to edit.
echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/.env.example"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit .env.example → allowed" 0 $?

# WHY test all 3 lock files: explicit list (not pattern) — each must be verified individually.
echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/package-lock.json"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit package-lock.json → blocked" 2 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/yarn.lock"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit yarn.lock → blocked" 2 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/pnpm-lock.yaml"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit pnpm-lock.yaml → blocked" 2 $?

# WHY test package.json + app.ts: verify we don't over-block. package.json looks similar
# to package-lock.json. app.ts is a normal file — sanity check that the hook allows it.
echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/package.json"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit package.json → allowed" 0 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/src/app.ts"}}' | bash .claude/hooks/block-protected-files.sh >/dev/null 2>&1
check "Edit app.ts → allowed" 0 $?

echo ""
echo "=== check-css-variables.sh ==="

# WHY temp files: CSS hook reads file contents with grep — needs real files on disk.
# TMPDIR is cleaned up at the end. Each file tests one specific pattern.
TMPDIR=$(mktemp -d)
echo '.foo { color: #ff0000; }' > "$TMPDIR/test.css"
echo '.foo { color: var(--primary); }' > "$TMPDIR/clean.css"
echo ':root { --primary: #ff0000; }' > "$TMPDIR/base.css"
# WHY #cafe: tests that CSS ID selectors (#id {) are NOT flagged as hex colors.
# The hook uses grep -vE '#[0-9a-fA-F]+\s*\{' to exclude these.
echo '#cafe { display: block; }' > "$TMPDIR/selector.css"
echo '.bar { gap: 16px; }' > "$TMPDIR/spacing.css"
echo '.bar { gap: var(--space-md); }' > "$TMPDIR/spacing-ok.css"
echo '.baz { transition: all 0.3s ease; }' > "$TMPDIR/transition.css"
# WHY 1px border test: CLAUDE.md explicitly allows 1px/2px hard-coded values.
# The hook must NOT flag these.
echo '.baz { border: 1px solid red; }' > "$TMPDIR/border.css"

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/test.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS with hex color → warned" 2 $?

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/clean.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS with var() → allowed" 0 $?

# WHY base.css skipped: that's where CSS variables are defined — hex values are legitimate there.
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/base.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "base.css → skipped" 0 $?

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/selector.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS ID #cafe → allowed (not hex color)" 0 $?

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/spacing.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS gap: 16px → warned" 2 $?

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/spacing-ok.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS gap: var() → allowed" 0 $?

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/transition.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS transition hard-coded → warned" 2 $?

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/border.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS border: 1px → allowed (1px exception)" 0 $?

# WHY test margin-top/padding-left: the old pattern only caught shorthand (margin:, padding:).
# AI writes margin-top: 16px more often than margin: 16px — the fix adds (-[a-z]+)? to catch both.
echo '.card { margin-top: 24px; }' > "$TMPDIR/margin-top.css"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/margin-top.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS margin-top: 24px → warned" 2 $?

echo '.card { padding-left: 16px; }' > "$TMPDIR/padding-left.css"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/padding-left.css\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "CSS padding-left: 16px → warned" 2 $?

# WHY test .py file: verifies the .css extension filter — non-CSS files must be ignored.
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/test.py\"}}" | bash .claude/hooks/check-css-variables.sh >/dev/null 2>&1
check "Non-CSS file → skipped" 0 $?

rm -rf "$TMPDIR"

echo ""
echo "========================================="
echo "  Passed: $PASS / $((PASS + FAIL))"
if [ "$FAIL" -gt 0 ]; then
  echo "  FAILED: $FAIL"
  echo "========================================="
  exit 1
else
  echo "  ALL TESTS PASSED"
  echo "========================================="
fi
