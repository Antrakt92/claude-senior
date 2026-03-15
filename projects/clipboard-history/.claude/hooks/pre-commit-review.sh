#!/bin/bash
# PreToolUse hook: BLOCKS git commit until self-review is completed.
# Phase 1: Auto-runs ruff — blocks if it fails. NO marker bypass.
# Phase 2: Shows manual review checklist — blocks until marker is set.
#
# WHY: this is a Python desktop app. ruff catches lint errors before commit.
# SYNC WITH: global CLAUDE.md §12 (hook architecture)

INPUT=$(cat)

CMD=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' | sed 's/\\"/"/g; s/\\\\/\\/g')
if [ -z "$CMD" ]; then
  CMD="$INPUT"
fi

if ! echo "$CMD" | grep -qE "(^|&& |; |\| )git commit"; then
  exit 0
fi

REPO_HASH=$(pwd | cksum | cut -d' ' -f1)
MARKER="/tmp/claude-commit-reviewed-$REPO_HASH"

if [ -f "$MARKER" ]; then
  if [ -n "$(find "$MARKER" -mmin +5 2>/dev/null)" ]; then
    rm -f "$MARKER"
  else
    rm -f "$MARKER"
    exit 0
  fi
fi

STAGED=$(git diff --cached --name-only 2>/dev/null)
if [ -z "$STAGED" ]; then
  exit 0
fi

STAT=$(git diff --cached --stat 2>/dev/null | tail -1)

HAS_PYTHON=false
for f in $STAGED; do
  case "$f" in
    *.py) HAS_PYTHON=true ;;
  esac
done

FILE_COUNT=$(echo "$STAGED" | wc -l | tr -d ' ')

# === Phase 1: Auto-checks (no marker bypass) ===
AUTO_ERRORS=""

if $HAS_PYTHON; then
  RUFF_OUT=$(timeout 30 ruff check . 2>&1)
  RUFF_EXIT=$?
  if [ $RUFF_EXIT -eq 124 ]; then
    AUTO_ERRORS="${AUTO_ERRORS}\nRUFF TIMEOUT: ruff check took >30s"
  elif [ $RUFF_EXIT -ne 0 ]; then
    AUTO_ERRORS="${AUTO_ERRORS}\nRUFF FAILED:\n$(echo "$RUFF_OUT" | head -10)"
  fi
fi

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

# === Phase 2: Manual review checklist ===
{
  echo "COMMIT BLOCKED — Self-review required ($STAT)"
  [ "$HAS_PYTHON" = true ] && echo "Auto-checks passed: ruff ✓"
  echo ""
  echo "1. REVIEW: Check git diff --cached — no debug code, secrets, or unrelated changes"
  STEP=2
  if [ "$FILE_COUNT" -gt 3 ]; then
    echo "$STEP. RIPPLE: $FILE_COUNT files changed — did you grep ALL callers of modified functions?"
    STEP=$((STEP + 1))
  fi
  echo "$STEP. LEARNINGS: Any mistakes worth logging?"
  echo ""
  echo "After review: touch $MARKER && retry commit"
} >&2

exit 2
