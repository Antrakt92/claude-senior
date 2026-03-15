#!/bin/bash
# PostToolUse hook: warns about callers/usages of definitions in the edited file.
#
# WHY: AI's #1 failure mode is changing a function/type and forgetting to update callers.
# This hook greps the codebase for names defined in the edited file and warns if they
# appear elsewhere — a lightweight "ripple effect" reminder.
#
# NON-BLOCKING: exit 0 always. Warnings go to stderr (AI sees them).
# WHY non-blocking: false positives are common (common names, re-exports). Blocking would
# make the hook unusable. The warning is enough to trigger AI to check.
#
# PERFORMANCE: must complete in <3 seconds. Uses timeout on grep, limits results.
# SYNC WITH: CLAUDE.md §3 The Ripple Effect Rule
# SYNC WITH: CLAUDE.md §9 Global Hooks

INPUT=$(cat)

# SYNC WITH: all hooks use identical JSON extraction — change one, change all.
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' | sed 's/\\"/"/g; s/\\\\/\\/g')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# WHY skip these directories: they're generated/vendored — not authored code.
# Editing files in these dirs doesn't need ripple checking.
case "$FILE_PATH" in
  *node_modules/*|*dist/*|*build/*|*__pycache__/*|*.git/*|*coverage/*|*.next/*|*.vite/*|*target/*)
    exit 0
    ;;
esac

# WHY skip non-code files: markdown, JSON config, etc. don't define functions/types.
case "$FILE_PATH" in
  *.py|*.ts|*.tsx|*.js|*.jsx|*.go|*.rs) ;;  # proceed
  *) exit 0 ;;
esac

# WHY check file exists: Edit tool might report a path for a file that was deleted.
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# === Extract definition names from the edited file ===
# WHY simple regex, not AST: must be fast (<1s), language-agnostic, no dependencies.
# Catches the common patterns — not exhaustive, but good enough for warnings.
NAMES=""

case "$FILE_PATH" in
  *.py)
    # WHY: def func_name, class ClassName, CONSTANT_NAME = (uppercase with underscores)
    NAMES=$(grep -oE '^\s*(def|class)\s+[a-zA-Z_][a-zA-Z0-9_]*' "$FILE_PATH" 2>/dev/null \
      | sed 's/.*\(def\|class\)\s\+//' \
      | head -20)
    # WHY separate grep for constants: pattern is different (UPPER_CASE = value)
    PY_CONSTANTS=$(grep -oE '^[A-Z][A-Z0-9_]+\s*=' "$FILE_PATH" 2>/dev/null \
      | sed 's/\s*=.*//' \
      | head -10)
    NAMES="${NAMES}${PY_CONSTANTS:+$'\n'}${PY_CONSTANTS}"
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    # WHY: export function/const/class/interface/type — only exported names matter for ripple
    NAMES=$(grep -oE '^\s*export\s+(default\s+)?(function|const|let|class|interface|type|enum)\s+[a-zA-Z_][a-zA-Z0-9_]*' "$FILE_PATH" 2>/dev/null \
      | sed 's/.*\(function\|const\|let\|class\|interface\|type\|enum\)\s\+//' \
      | head -20)
    ;;
  *.go)
    # WHY: Go exports are capitalized names — func Foo, type Bar, const Baz
    NAMES=$(grep -oE '^\s*(func|type|const|var)\s+[A-Z][a-zA-Z0-9_]*' "$FILE_PATH" 2>/dev/null \
      | sed 's/.*\(func\|type\|const\|var\)\s\+//' \
      | head -20)
    ;;
  *.rs)
    # WHY: pub fn/struct/enum/type/const/trait — only pub items are externally visible
    NAMES=$(grep -oE '^\s*pub\s+(fn|struct|enum|type|const|trait)\s+[a-zA-Z_][a-zA-Z0-9_]*' "$FILE_PATH" 2>/dev/null \
      | sed 's/.*\(fn\|struct\|enum\|type\|const\|trait\)\s\+//' \
      | head -20)
    ;;
esac

# Remove duplicates and empty lines
NAMES=$(echo "$NAMES" | sort -u | sed '/^$/d')

if [ -z "$NAMES" ]; then
  exit 0
fi

# WHY filter short/common names: "id", "get", "set", "run" etc. would match everywhere.
# 4-char minimum eliminates most false positives while catching real function names.
NAMES=$(echo "$NAMES" | awk 'length >= 4')

if [ -z "$NAMES" ]; then
  exit 0
fi

# === Grep codebase for each name ===
# WHY: we search for each name in the codebase, excluding the file itself and generated dirs.
WARNINGS=""
WARNING_COUNT=0
MAX_WARNINGS=5

# WHY basename for filtering: grep results are relative (./src/file.py) but FILE_PATH
# may be absolute (/home/user/project/src/file.py). Filtering by basename works for both.
# KNOWN LIMITATION: if two files share the same basename in different dirs, we'll filter
# both. Acceptable: better to miss a warning than to self-match and always warn.
FILE_BASENAME=$(basename "$FILE_PATH")

# WHY grep -r not rg: rg may not be installed globally. grep -r is universal.
# WHY --include: limit to code files for speed.
# WHY timeout 3: hard limit — if grep is slow (huge repo), bail out rather than block AI.
EXCLUDE_DIRS="--exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=__pycache__ --exclude-dir=.git --exclude-dir=coverage --exclude-dir=.next --exclude-dir=.vite --exclude-dir=target --exclude-dir=.mypy_cache --exclude-dir=.ruff_cache --exclude-dir=htmlcov --exclude-dir=.pytest_cache"

while IFS= read -r NAME; do
  [ -z "$NAME" ] && continue
  [ "$WARNING_COUNT" -ge "$MAX_WARNINGS" ] && break

  # WHY -rn: recursive + line numbers. WHY -w: whole word match (prevents "getName" matching "name").
  # WHY head -5: limit results per name to keep output manageable.
  MATCHES=$(timeout 3 grep -rnw "$NAME" . $EXCLUDE_DIRS \
    --include="*.py" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    --include="*.go" --include="*.rs" \
    2>/dev/null \
    | grep -Fv "$FILE_BASENAME" \
    | head -5)

  if [ -n "$MATCHES" ]; then
    # WHY format as "name → file:line": concise, scannable by AI.
    FILES=$(echo "$MATCHES" | sed 's/:.*/:/' | sed 's/^\.\///' | head -3 | tr '\n' ' ')
    WARNINGS="${WARNINGS}\n  ${NAME} → ${FILES}"
    WARNING_COUNT=$((WARNING_COUNT + 1))
  fi
done <<< "$NAMES"

if [ -n "$WARNINGS" ]; then
  {
    echo "RIPPLE CHECK: definitions in $(basename "$FILE_PATH") are also used in:"
    echo -e "$WARNINGS"
    echo "Did you update all callers?"
  } >&2
fi

exit 0
