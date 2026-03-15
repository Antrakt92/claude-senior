#!/bin/bash
# PreToolUse hook: BLOCKS git commit until auto-checks pass and self-review is completed.
# Universal version — auto-detects project stack (Python, TypeScript, Go, Rust, Node).
#
# Phase 1 (auto-checks, no bypass):
#   Detects staged file types + project markers → runs relevant linters/tests.
#   Timeout on each command. Blocks on failure.
# Phase 2 (review checklist, marker bypass):
#   Advisory checklist — AI reviews then sets marker to proceed.
#
# DOUBLE-FIRE PREVENTION: if project-level .claude/hooks/pre-commit-review.sh exists,
# this hook exits 0 immediately — the project hook takes precedence.
# WHY: both global and project hooks fire on the same event. Without this guard,
# commits in projects with custom pre-commit hooks would run checks twice.
#
# INPUT: JSON from Claude Code on stdin ({"tool_name":"Bash","tool_input":{"command":"..."}})
# OUTPUT: exit 0 = allow, exit 2 + stderr = block (AI sees stderr message)
#
# SYNC WITH: CLAUDE.md §9 Global Hooks

INPUT=$(cat)

# WHY ([^"\\]|\\.)*: JSON encodes quotes as \" and backslashes as \\.
# Plain [^"]* truncates at first \", losing everything after quoted strings.
CMD=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' | sed 's/\\"/"/g; s/\\\\/\\/g')
if [ -z "$CMD" ]; then
  CMD="$INPUT"
fi

# WHY (^|&& |; |\| ): match "git commit" at line start OR after command separators.
if ! echo "$CMD" | grep -qE "(^|&& |; |\| )git commit"; then
  exit 0
fi

# --- Double-fire prevention ---
# WHY check project-level hook: if the project has its own pre-commit-review.sh,
# it handles all commit validation. Running both wastes time (tests run twice)
# and can show duplicate/conflicting messages.
if [ -f ".claude/hooks/pre-commit-review.sh" ]; then
  exit 0
fi

# WHY per-repo marker: prevents cross-repo marker reuse.
REPO_HASH=$(pwd | cksum | cut -d' ' -f1)
MARKER="/tmp/claude-commit-reviewed-$REPO_HASH"

# If marker exists, review was done — allow commit and clean up
# WHY 5-minute expiry: prevents stale markers from crashed sessions.
# WHY rm before exit 0: marker is single-use — each commit needs fresh review.
if [ -f "$MARKER" ]; then
  if [ -n "$(find "$MARKER" -mmin +5 2>/dev/null)" ]; then
    rm -f "$MARKER"
  else
    rm -f "$MARKER"
    exit 0
  fi
fi

# Analyze what's being committed
STAGED=$(git diff --cached --name-only 2>/dev/null)

# Nothing staged — skip review (empty commit will fail on its own)
if [ -z "$STAGED" ]; then
  exit 0
fi

STAT=$(git diff --cached --stat 2>/dev/null | tail -1)

# === Detect project stack from staged files + project markers ===
HAS_PYTHON=false
HAS_TS=false
HAS_GO=false
HAS_RUST=false
HAS_NODE=false
HAS_MIGRATION=false
HAS_MODEL=false

for f in $STAGED; do
  case "$f" in
    */versions/*.py) HAS_MIGRATION=true; HAS_PYTHON=true ;;
    *.py) HAS_PYTHON=true ;;
    *.ts|*.tsx) HAS_TS=true ;;
    *.go) HAS_GO=true ;;
    *.rs) HAS_RUST=true ;;
  esac
  case "$f" in
    *entities.py|*models.py) HAS_MODEL=true ;;
  esac
done

# WHY project marker check in addition to staged files: if only a .md or config file
# is staged, file extensions don't tell us the stack. Project markers (go.mod, Cargo.toml)
# let us still run relevant tests.
# WHY backend/ check for Python: many projects have backend/ with Python. Also check
# for any pyproject.toml/setup.py as fallback.
if $HAS_PYTHON; then
  if [ -d "backend" ]; then
    PYTHON_DIR="backend"
  elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "setup.cfg" ]; then
    PYTHON_DIR="."
  else
    PYTHON_DIR=""
  fi
fi

if $HAS_TS; then
  # WHY: look for frontend/ first (common monorepo), then root tsconfig
  if [ -d "frontend" ]; then
    TS_DIR="frontend"
  elif [ -f "tsconfig.json" ]; then
    TS_DIR="."
  else
    TS_DIR=""
  fi
fi

# WHY: Go/Rust detected by both staged files AND project markers
$HAS_GO && [ ! -f "go.mod" ] && HAS_GO=false
$HAS_RUST && [ ! -f "Cargo.toml" ] && HAS_RUST=false

# WHY: detect Node.js projects that aren't TS/Python — has package.json with "test" script
if ! $HAS_PYTHON && ! $HAS_TS && ! $HAS_GO && ! $HAS_RUST && [ -f "package.json" ]; then
  if grep -q '"test"' package.json 2>/dev/null; then
    HAS_NODE=true
  fi
fi

FILE_COUNT=$(echo "$STAGED" | wc -l | tr -d ' ')

# === Phase 1: Auto-checks (no marker bypass) ===
# WHY no marker bypass: linter/test errors mean code is objectively broken.
AUTO_ERRORS=""
# WHY track PASSED separately: Phase 2 shows which checks ran. Without tracking,
# we'd show "ruff ✓" even if ruff wasn't installed and was skipped.
PASSED=""

# --- Python ---
if $HAS_PYTHON && [ -n "$PYTHON_DIR" ]; then
  # WHY command -v: skip if tool not installed (global hook, not all projects have ruff)
  if command -v ruff >/dev/null 2>&1; then
    RUFF_OUT=$(cd "$PYTHON_DIR" && timeout 30 ruff check . 2>&1)
    RUFF_EXIT=$?
    if [ $RUFF_EXIT -eq 124 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nRUFF TIMEOUT: ruff check took >30s"
    elif [ $RUFF_EXIT -ne 0 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nRUFF FAILED:\n$(echo "$RUFF_OUT" | head -10)"
    else
      PASSED="${PASSED}ruff ✓ "
    fi
  fi

  # WHY pytest: single biggest quality lever — catches broken code before commit.
  # WHY -x --tb=short: fast feedback, enough context to diagnose.
  if command -v pytest >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    # WHY: try "tests/" first (common), fall back to "test/", then root
    TEST_DIR=""
    if [ -d "$PYTHON_DIR/tests" ]; then
      TEST_DIR="tests/"
    elif [ -d "$PYTHON_DIR/test" ]; then
      TEST_DIR="test/"
    fi
    PYTEST_OUT=$(cd "$PYTHON_DIR" && timeout 120 python -m pytest ${TEST_DIR} -x -q --tb=short 2>&1)
    PYTEST_EXIT=$?
    if [ $PYTEST_EXIT -eq 124 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nPYTEST TIMEOUT: pytest took >120s"
    elif [ $PYTEST_EXIT -ne 0 ] && [ $PYTEST_EXIT -ne 5 ]; then
      # WHY exit 5 = no tests collected — not an error, just no tests in project
      AUTO_ERRORS="${AUTO_ERRORS}\nPYTEST FAILED:\n$(echo "$PYTEST_OUT" | tail -15)"
    else
      PASSED="${PASSED}pytest ✓ "
    fi
  fi
fi

# --- TypeScript ---
if $HAS_TS && [ -n "$TS_DIR" ]; then
  if [ -f "$TS_DIR/tsconfig.json" ]; then
    TSC_OUT=$(cd "$TS_DIR" && timeout 120 npx tsc --noEmit 2>&1)
    TSC_EXIT=$?
    if [ $TSC_EXIT -eq 124 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nTSC TIMEOUT: tsc --noEmit took >120s"
    elif [ $TSC_EXIT -ne 0 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nTSC FAILED:\n$(echo "$TSC_OUT" | head -10)"
    else
      PASSED="${PASSED}tsc ✓ "
    fi
  fi

  # WHY: check for eslint config before running — not all TS projects use ESLint
  HAS_ESLINT=false
  for cfg in "$TS_DIR/eslint.config."* "$TS_DIR/.eslintrc"* "$TS_DIR/package.json"; do
    if [ -f "$cfg" ]; then
      # WHY package.json check: only counts if it has eslintConfig key
      if [[ "$cfg" == *package.json ]]; then
        grep -q '"eslintConfig"' "$cfg" 2>/dev/null && HAS_ESLINT=true
      else
        HAS_ESLINT=true
      fi
      break
    fi
  done

  if $HAS_ESLINT; then
    LINT_OUT=$(cd "$TS_DIR" && timeout 60 npx eslint . --max-warnings 0 2>&1)
    LINT_EXIT=$?
    if [ $LINT_EXIT -eq 124 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nESLINT TIMEOUT: eslint took >60s"
    elif [ $LINT_EXIT -ne 0 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nESLINT FAILED:\n$(echo "$LINT_OUT" | head -10)"
    else
      PASSED="${PASSED}eslint ✓ "
    fi
  fi
fi

# --- Go ---
if $HAS_GO; then
  if command -v go >/dev/null 2>&1; then
    GOVET_OUT=$(timeout 30 go vet ./... 2>&1)
    GOVET_EXIT=$?
    if [ $GOVET_EXIT -eq 124 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nGO VET TIMEOUT: go vet took >30s"
    elif [ $GOVET_EXIT -ne 0 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nGO VET FAILED:\n$(echo "$GOVET_OUT" | head -10)"
    else
      PASSED="${PASSED}go vet ✓ "
    fi

    GOTEST_OUT=$(timeout 120 go test ./... 2>&1)
    GOTEST_EXIT=$?
    if [ $GOTEST_EXIT -eq 124 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nGO TEST TIMEOUT: go test took >120s"
    elif [ $GOTEST_EXIT -ne 0 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nGO TEST FAILED:\n$(echo "$GOTEST_OUT" | tail -15)"
    else
      PASSED="${PASSED}go test ✓ "
    fi
  fi
fi

# --- Rust ---
if $HAS_RUST; then
  if command -v cargo >/dev/null 2>&1; then
    CARGO_CHECK_OUT=$(timeout 60 cargo check 2>&1)
    CARGO_CHECK_EXIT=$?
    if [ $CARGO_CHECK_EXIT -eq 124 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nCARGO CHECK TIMEOUT: cargo check took >60s"
    elif [ $CARGO_CHECK_EXIT -ne 0 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nCARGO CHECK FAILED:\n$(echo "$CARGO_CHECK_OUT" | head -10)"
    else
      PASSED="${PASSED}cargo check ✓ "
    fi

    CARGO_TEST_OUT=$(timeout 120 cargo test 2>&1)
    CARGO_TEST_EXIT=$?
    if [ $CARGO_TEST_EXIT -eq 124 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nCARGO TEST TIMEOUT: cargo test took >120s"
    elif [ $CARGO_TEST_EXIT -ne 0 ]; then
      AUTO_ERRORS="${AUTO_ERRORS}\nCARGO TEST FAILED:\n$(echo "$CARGO_TEST_OUT" | tail -15)"
    else
      PASSED="${PASSED}cargo test ✓ "
    fi
  fi
fi

# --- Generic Node.js (not TS/Python) ---
if $HAS_NODE; then
  NPM_TEST_OUT=$(timeout 120 npm test 2>&1)
  NPM_TEST_EXIT=$?
  if [ $NPM_TEST_EXIT -eq 124 ]; then
    AUTO_ERRORS="${AUTO_ERRORS}\nNPM TEST TIMEOUT: npm test took >120s"
  elif [ $NPM_TEST_EXIT -ne 0 ]; then
    AUTO_ERRORS="${AUTO_ERRORS}\nNPM TEST FAILED:\n$(echo "$NPM_TEST_OUT" | tail -15)"
  else
    PASSED="${PASSED}npm test ✓ "
  fi
fi

# If auto-checks failed, block — no marker bypass
if [ -n "$AUTO_ERRORS" ]; then
  {
    echo "COMMIT BLOCKED — Auto-checks failed ($STAT)"
    echo ""
    echo -e "$AUTO_ERRORS"
    echo ""
    echo "Fix the errors above, then retry commit."
  } >&2
  exit 2
fi

# === Phase 2: Manual review checklist (marker bypass) ===
# WHY marker bypass here but not Phase 1: checklist is advisory — AI signals completion via marker.
{
  echo "COMMIT BLOCKED — Self-review required ($STAT)"

  # WHY use PASSED from Phase 1: only shows checks that actually ran and succeeded.
  # Previously this section rebuilt the list from flags, showing "tsc ✓" even when
  # tsc was skipped (no tsconfig) or "ruff ✓" when ruff wasn't installed.
  [ -n "$PASSED" ] && echo "Auto-checks passed: $PASSED"
  echo ""

  # Always required
  echo "1. REVIEW: Check git diff --cached — no debug code, secrets, or unrelated changes"

  STEP=2
  if $HAS_MODEL; then
    echo "$STEP. MODEL CHANGED: Did you create a migration?"
    STEP=$((STEP + 1))
  fi
  if $HAS_MIGRATION; then
    echo "$STEP. MIGRATION: Verify both upgrade() and downgrade() exist and are correct"
    STEP=$((STEP + 1))
  fi

  # Ripple check for multi-file changes
  if [ "$FILE_COUNT" -gt 3 ]; then
    echo "$STEP. RIPPLE: $FILE_COUNT files changed — did you grep ALL callers of modified functions?"
    STEP=$((STEP + 1))
  fi

  echo "$STEP. LEARNINGS: Any mistakes worth logging? Update improvement-log.md if yes"

  # Model changed but no migration staged = warning
  if $HAS_MODEL && ! $HAS_MIGRATION; then
    echo ""
    echo "WARNING: entities.py/models.py changed but NO migration file staged!"
  fi

  echo ""
  echo "After review: touch $MARKER && retry commit"
} >&2

exit 2
