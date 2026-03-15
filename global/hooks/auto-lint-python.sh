#!/bin/bash
# PostToolUse hook: auto-lint Python files with Ruff after Edit/Write.
#
# WHY: AI writes code → ruff reformats → AI's old_string in next Edit won't match.
# Exit 2 + stderr forces AI to re-read the file before next Edit.
# WHY PostToolUse: must run AFTER Edit/Write so ruff lints the new content.
# SYNC WITH: auto-lint-typescript.sh (same md5sum/exit 2 pattern)
# SYNC WITH: CLAUDE.md Hook Behavior section

INPUT=$(cat)

# SYNC WITH: all hooks use identical JSON extraction — change one, change all.
# WHY ([^"\\]|\\.)*: escape-aware JSON extraction, handles \" and \\ in values.
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [[ "$FILE_PATH" != *.py ]]; then
  exit 0
fi

# WHY md5sum: fast, sufficient for change detection (not security). Available in Git Bash.
BEFORE=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1)

# WHY --fix then format: --fix corrects violations, format handles style. Order matters.
# WHY || true: ruff exits non-zero for unfixable violations — format should still run.
# Pre-commit hook catches real ruff errors at commit time.
ruff check --fix --quiet "$FILE_PATH" 2>/dev/null || true
ruff format --quiet "$FILE_PATH" 2>/dev/null
AFTER=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1)

# WHY exit 2: forces AI to re-read. WHY stderr: VS Code only surfaces stderr to AI.
if [ "$BEFORE" != "$AFTER" ]; then
  echo "AUTO-LINT: Ruff reformatted $(basename "$FILE_PATH") — re-read before next edit." >&2
  exit 2
fi

exit 0
