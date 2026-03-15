#!/bin/bash
# PostToolUse hook: auto-lint TypeScript files with ESLint after Edit/Write.
#
# WHY: same as auto-lint-python.sh — AI's next Edit fails if ESLint reformatted the file.
# SYNC WITH: auto-lint-python.sh (same md5sum/exit 2 pattern)
# SYNC WITH: CLAUDE.md Hook Behavior section

INPUT=$(cat)

# SYNC WITH: all hooks use identical JSON extraction — change one, change all.
# WHY ([^"\\]|\\.)*: escape-aware JSON extraction, handles \" and \\ in values.
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [[ "$FILE_PATH" != *.ts ]] && [[ "$FILE_PATH" != *.tsx ]]; then
  exit 0
fi

# WHY frontend/* check: ESLint config lives in frontend/ — can't run from repo root.
# WHY *frontend\\*: Windows paths use backslashes; Claude Code on Windows may pass either.
if [[ "$FILE_PATH" != *frontend/* ]] && [[ "$FILE_PATH" != *frontend\\* ]]; then
  exit 0
fi

FRONTEND_DIR="frontend"
if [ ! -d "$FRONTEND_DIR" ]; then
  exit 0
fi

BEFORE=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1)

# WHY cd subshell: ESLint needs config-relative CWD. FILE_PATH is absolute, so resolves fine.
# KNOWN LIMITATION: relative FILE_PATH would resolve to frontend/frontend/... — but
# Claude Code always passes absolute paths.
# WHY || true: ESLint exits non-zero for unfixable issues; we still check if file changed.
LINT_ERR=$( (cd "$FRONTEND_DIR" && npx eslint --fix "$FILE_PATH") 2>&1 >/dev/null ) || true
AFTER=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1)

if [ "$BEFORE" != "$AFTER" ]; then
  echo "AUTO-LINT: ESLint reformatted $(basename "$FILE_PATH") — re-read before next edit." >&2
  exit 2
fi

exit 0
