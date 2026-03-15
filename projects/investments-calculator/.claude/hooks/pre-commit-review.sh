#!/bin/bash
# PreToolUse hook: BLOCKS git commit until self-review is completed.
# Phase 1: Auto-runs fast checks (ruff, tsc) — blocks if they fail. NO marker bypass.
# Phase 2: Shows manual review checklist — blocks until marker is set.
# Uses marker file pattern: block → review → mark → allow.
#
# INPUT: JSON from Claude Code on stdin ({"tool_name":"Bash","tool_input":{"command":"..."}})
# OUTPUT: exit 0 = allow, exit 2 + stderr = block (AI sees stderr message)
#
# SYNC WITH: CLAUDE.md §4 Self Code Review (checklist items should match)

INPUT=$(cat)

# WHY ([^"\\]|\\.)*: JSON encodes quotes as \" and backslashes as \\.
# Plain [^"]* truncates at first \", losing everything after quoted strings.
# Example: "echo \"foo\" && git push --force" truncates to "echo \", hiding the push.
# The escape-aware pattern matches through \" and \\ correctly.
CMD=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' | sed 's/\\"/"/g; s/\\\\/\\/g')
if [ -z "$CMD" ]; then
  CMD="$INPUT"
fi

# WHY (^|&& |; |\| ): match "git commit" at line start OR after command separators.
# Without \|, piped commits like "echo msg | git commit --file=-" bypass the hook.
# Intentionally does NOT match "echo git commit" or "grep git commit" because those
# have "echo "/"grep " before "git commit", not a separator. The word before "git"
# must be a separator or line start, not arbitrary text.
# KNOWN LIMITATION: "git -C /path commit" bypasses because "commit" is not directly
# after "git ". Acceptable: AI never uses git -C in this workflow.
if ! echo "$CMD" | grep -qE "(^|&& |; |\| )git commit"; then
  exit 0
fi

# WHY per-repo marker: prevents cross-repo marker reuse.
# WHY cksum: fast, no dependencies. Collision risk negligible for this use case.
REPO_HASH=$(pwd | cksum | cut -d' ' -f1)
MARKER="/tmp/claude-commit-reviewed-$REPO_HASH"

# If marker exists, review was done — allow commit and clean up
# WHY 5-minute expiry: prevents stale markers from crashed sessions from persisting.
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

# Detect file types in staged changes
# WHY not while-read: filenames with spaces would break `for f in $STAGED`,
# but this project has no such files and the consequence is minor (wrong type detection,
# not a security issue). Using for-in for readability.
HAS_PYTHON=false
HAS_TS=false
HAS_CSS=false
HAS_MIGRATION=false
HAS_MODEL=false

for f in $STAGED; do
  case "$f" in
    */versions/*.py) HAS_MIGRATION=true; HAS_PYTHON=true ;;
    *.py) HAS_PYTHON=true ;;
    *.ts|*.tsx) HAS_TS=true ;;
    *.css) HAS_CSS=true ;;
  esac
  case "$f" in
    *entities.py|*models.py) HAS_MODEL=true ;;
  esac
done

# Count files changed
FILE_COUNT=$(echo "$STAGED" | wc -l | tr -d ' ')

# === Phase 1: Auto-checks (fast, automated — no marker bypass) ===
# WHY no marker bypass: ruff/tsc errors mean the code is objectively broken.
# AI must fix the code, not skip the check. This is the strongest enforcement layer.
AUTO_ERRORS=""

if $HAS_PYTHON && [ -d "backend" ]; then
  # WHY timeout 30: ruff is normally <2s. If it hangs (corrupt config, huge codebase),
  # the hook blocks forever with no marker bypass — AI is stuck. 30s is generous.
  RUFF_OUT=$(cd backend && timeout 30 ruff check . 2>&1)
  RUFF_EXIT=$?
  if [ $RUFF_EXIT -eq 124 ]; then
    AUTO_ERRORS="${AUTO_ERRORS}\nRUFF TIMEOUT: ruff check took >30s — possible config issue"
  elif [ $RUFF_EXIT -ne 0 ]; then
    AUTO_ERRORS="${AUTO_ERRORS}\nRUFF FAILED:\n$(echo "$RUFF_OUT" | head -10)"
  fi
fi

if $HAS_TS && [ -d "frontend" ]; then
  # WHY timeout 120: tsc --noEmit on this project takes 15-40s normally.
  # 120s handles slow CI machines. If it hangs indefinitely (infinite type recursion,
  # corrupt node_modules), the hook blocks forever — AI is stuck without this timeout.
  TSC_OUT=$(cd frontend && timeout 120 npx tsc --noEmit 2>&1)
  TSC_EXIT=$?
  if [ $TSC_EXIT -eq 124 ]; then
    AUTO_ERRORS="${AUTO_ERRORS}\nTSC TIMEOUT: tsc --noEmit took >120s — possible config issue"
  elif [ $TSC_EXIT -ne 0 ]; then
    AUTO_ERRORS="${AUTO_ERRORS}\nTSC FAILED:\n$(echo "$TSC_OUT" | head -10)"
  fi
fi

# If auto-checks failed, block immediately — no marker bypass, must fix code
if [ -n "$AUTO_ERRORS" ]; then
  {
    echo "COMMIT BLOCKED — Auto-checks failed ($STAT)"
    echo ""
    echo -e "$AUTO_ERRORS"
    echo ""
    echo "Fix the errors above, then retry commit. No marker needed — just fix and retry."
  } >&2
  exit 2
fi

# === Phase 2: Manual review checklist (marker bypass) ===
# WHY marker bypass here but not Phase 1: this checklist is advisory — AI does the review
# then signals completion via marker. Phase 1 is automated and objective (pass/fail).
{
  echo "COMMIT BLOCKED — Self-review required ($STAT)"
  echo "Auto-checks passed: $([ "$HAS_PYTHON" = true ] && echo 'ruff ✓ ')$([ "$HAS_TS" = true ] && echo 'tsc ✓ ')"
  echo ""

  # Always required
  echo "1. REVIEW: Check git diff --cached — no debug code, secrets, or unrelated changes"

  # Verification commands based on file types
  STEP=2
  if $HAS_PYTHON; then
    echo "$STEP. PYTHON: cd backend && python -m pytest tests/ -x -q"
    STEP=$((STEP + 1))
  fi
  if $HAS_TS; then
    echo "$STEP. TYPESCRIPT: cd frontend && npm run lint"
    STEP=$((STEP + 1))
  fi
  if $HAS_CSS; then
    echo "$STEP. CSS: Verify no hard-coded values — use CSS variables from base.css"
    STEP=$((STEP + 1))
  fi
  if $HAS_MODEL; then
    echo "$STEP. MODEL CHANGED: Did you create a migration? alembic revision --autogenerate"
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

  # Self-improvement
  echo "$STEP. LEARNINGS: Any mistakes worth logging? Update improvement-log.md if yes"

  echo ""
  # Model changed but no migration staged = warning
  if $HAS_MODEL && ! $HAS_MIGRATION; then
    echo ""
    echo "WARNING: entities.py/models.py changed but NO migration file staged!"
  fi

  echo ""
  echo "After review: touch $MARKER && retry commit"
} >&2

exit 2
