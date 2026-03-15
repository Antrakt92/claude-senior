#!/bin/bash
# PreToolUse hook: block Edit/Write to .env files (not .env.example) and lock files.
#
# WHY separate from block-dangerous-git.sh: that hook catches Bash tool (redirects, cp, mv).
# Edit/Write tools bypass it — this hook covers that gap.
# SYNC WITH: block-dangerous-git.sh .env section (both must agree on what's protected)
# SYNC WITH: all hooks use identical JSON extraction — change one, change all.

INPUT=$(cat)

# WHY ([^"\\]|\\.)*: consistent escape-aware JSON extraction.
# SYNC WITH: all hooks use identical JSON extraction — change one, change all.
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")

# WHY .env* glob (not regex): simpler, catches .env, .env.local, .env.production.
# WHY *.example exclusion: template files with placeholder values, safe to edit.
# NOTE: glob is broader than block-dangerous-git.sh regex (\.env(\.[a-z]+)?(\s|$)).
# This also catches .envrc (direnv). Over-blocking is safer for secrets.
if [[ "$BASENAME" == .env* ]] && [[ "$BASENAME" != *.example ]]; then
  echo "BLOCKED: $BASENAME is a protected secrets file. Edit it manually outside Claude Code." >&2
  exit 2
fi

# WHY explicit list (not *.lock glob): avoids catching Cargo.lock, Gemfile.lock.
# WHY block: AI editing lock files directly creates inconsistencies with node_modules.
if [[ "$BASENAME" == "package-lock.json" ]] || [[ "$BASENAME" == "yarn.lock" ]] || [[ "$BASENAME" == "pnpm-lock.yaml" ]]; then
  echo "BLOCKED: $BASENAME should only change via package manager, not direct edit." >&2
  exit 2
fi

exit 0
