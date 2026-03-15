#!/bin/bash
# PostToolUse hook: auto-lint TypeScript files with ESLint after Edit/Write.
#
# WHY: AI's next Edit fails if ESLint reformatted the file and AI uses stale old_string.
# SYNC WITH: global auto-lint-python.sh (same md5sum/exit 2 pattern)

INPUT=$(cat)

# SYNC WITH: all hooks use identical JSON extraction.
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [[ "$FILE_PATH" != *.ts ]] && [[ "$FILE_PATH" != *.tsx ]]; then
  exit 0
fi

# WHY: this is a root-level Next.js project — ESLint config is at project root, not in a subdir.
# No need for cd like investments-calculator's frontend/ subdir.
BEFORE=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1)
LINT_ERR=$(npx eslint --fix "$FILE_PATH" 2>&1 >/dev/null) || true
AFTER=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1)

if [ "$BEFORE" != "$AFTER" ]; then
  echo "AUTO-LINT: ESLint reformatted $(basename "$FILE_PATH") — re-read before next edit." >&2
  exit 2
fi

exit 0
