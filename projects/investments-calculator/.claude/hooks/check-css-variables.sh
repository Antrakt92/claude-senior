#!/bin/bash
# PostToolUse hook: detect hard-coded CSS values that should use variables.
#
# WHY: AI writes `color: #047857` instead of `var(--status-success-text)`, then "fixes"
# the color in base.css but forgets the hard-coded value — visual inconsistency.
# SYNC WITH: CLAUDE.md §CSS Rules, base.css :root section
# SYNC WITH: all hooks use identical JSON extraction — change one, change all.

INPUT=$(cat)

# SYNC WITH: all hooks use identical JSON extraction — change one, change all.
# WHY ([^"\\]|\\.)*: escape-aware JSON extraction, handles \" and \\ in values.
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [[ "$FILE_PATH" != *.css ]]; then
  exit 0
fi

# WHY skip base.css: that's where variables are DEFINED — hard-coded values are correct there.
BASENAME=$(basename "$FILE_PATH")
if [[ "$BASENAME" == "base.css" ]]; then
  exit 0
fi

VIOLATIONS=""

# WHY {3,8}: matches #rgb(3), #rgba(4), #rrggbb(6), #rrggbbaa(8) — all valid CSS hex formats.
# WHY -v 'var(--': lines using CSS variables are correct. WHY -v '/\*': skip comments.
# WHY -v '@media print': print styles legitimately hard-code values.
# WHY -vE '#hex\s*\{': skip CSS ID selectors (#sidebar {) — false positive as hex color.
# KNOWN LIMITATION: per-line exclusion. `linear-gradient(#fff, var(--x))` is skipped
# entirely because the line contains var(--. Acceptable for this project's CSS patterns.
HEX=$(grep -nE '#[0-9a-fA-F]{3,8}' "$FILE_PATH" 2>/dev/null \
  | grep -v 'var(--' \
  | grep -v '/\*' \
  | grep -v '@media print' \
  | grep -vE '#[0-9a-fA-F]+\s*\{' \
  | head -3)

# WHY specific properties: gap/margin/padding/font-size/border-radius are the most common
# spacing variables. width/height are often truly one-off.
# WHY (-[a-z]+)? on margin/padding: catches margin-top, padding-left, etc. — AI writes
# these more often than shorthand, and the old pattern missed them entirely.
# WHY -vE ':\s*[12]px': 1px/2px borders are legitimate (CLAUDE.md exception).
SPACING=$(grep -nE '(row-|column-)?gap:\s*[0-9]+px|margin(-[a-z]+)?:\s*[0-9]+px|padding(-[a-z]+)?:\s*[0-9]+px|font-size:\s*[0-9]+px|border-radius:\s*[0-9]+px' "$FILE_PATH" 2>/dev/null \
  | grep -v 'var(--' \
  | grep -vE ':\s*[12]px' \
  | head -3)

# WHY 'all\s*[0-9]': catches `transition: all 0.2s ease` but not `transition: all var(--...)`.
# KNOWN LIMITATION: misses property-specific `transition: color 0.3s ease`.
TRANS=$(grep -nE 'transition:\s*all\s*[0-9]' "$FILE_PATH" 2>/dev/null \
  | grep -v 'var(--' \
  | head -2)

VIOLATIONS="${HEX}${SPACING:+$'\n'}${SPACING}${TRANS:+$'\n'}${TRANS}"
VIOLATIONS=$(echo "$VIOLATIONS" | sed '/^$/d' | head -5)

if [ -n "$VIOLATIONS" ]; then
  {
    echo "CSS WARNING: Hard-coded values detected in $BASENAME. Use CSS variables from base.css:"
    echo "$VIOLATIONS"
    echo ""
    echo "Check :root { } in frontend/src/styles/base.css for available variables."
  } >&2
  exit 2
fi

exit 0
