#!/bin/bash
# PreToolUse hook: blocks dangerous CLI operations.
# Git: force push (+refspec), reset --hard, clean -f, checkout -f, checkout/restore ., branch -D, stash drop/clear
# Filesystem: rm -rf on source directories (whitelist for build artifacts)
# DB: alembic downgrade
# Secrets: Bash redirects/cp/mv to .env files
#
# INPUT: JSON from Claude Code on stdin ({"tool_name":"Bash","tool_input":{"command":"..."}})
# OUTPUT: exit 0 = allow, exit 2 + stderr = block (AI sees stderr message)
# Bypass: touch /tmp/claude-dangerous-op-REPOHASH-OPHASH to allow a single blocked operation.
#
# KNOWN LIMITATIONS (by design):
# - String-based analysis only — cannot inspect contents of `bash script.sh` or python -c "..."
# - JSON unescape handles \" and \\ but not \uXXXX or \/ (sufficient for shell commands)
# - Cannot detect variable expansion: CMD="git push --force" && $CMD bypasses all checks

INPUT=$(cat)

# WHY ([^"\\]|\\.)*: JSON encodes quotes as \" and backslashes as \\.
# Plain [^"]* truncates at first \", losing everything after quoted strings.
# Example: "echo \"foo\" && git push --force" truncates to "echo \", hiding the push.
# The escape-aware pattern matches through \" and \\ correctly.
CMD=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' | sed 's/\\"/"/g; s/\\\\/\\/g')

# Fallback: if command extraction fails, grep raw input (less precise but better than nothing)
if [ -z "$CMD" ]; then
  CMD="$INPUT"
fi

# --- Bypass mechanism (marker-file pattern, same as pre-commit-review.sh) ---
# WHY per-repo AND per-command: approving "git push --force" in repo A doesn't unlock
# "rm -rf backend/" in repo A, or "git push --force" in repo B.
# WHY 5-minute expiry: if AI crashes mid-session, stale markers don't persist forever.
REPO_HASH=$(pwd | cksum | cut -d' ' -f1)
OP_HASH=$(echo "$CMD" | cksum | cut -d' ' -f1)
MARKER="/tmp/claude-dangerous-op-${REPO_HASH}-${OP_HASH}"

if [ -f "$MARKER" ]; then
  # Stale markers (>5 min) = expired, ignore
  if [ -n "$(find "$MARKER" -mmin +5 2>/dev/null)" ]; then
    rm -f "$MARKER"
  else
    rm -f "$MARKER"
    exit 0
  fi
fi

# Helper: block with message + bypass instructions
block() {
  {
    echo "$1"
    echo "If user explicitly requested this: touch $MARKER && retry"
  } >&2
  exit 2
}

# === Git dangerous operations ===

# WHY (--force|-f)( |$): matches --force/- f followed by space or end-of-line.
# Intentionally does NOT match --force-with-lease or --force-if-includes
# because those are safe variants (the char after --force is -, not space/EOL).
if echo "$CMD" | grep -qE "git push.*(--force|-f)( |$)"; then
  HAS_LEASE=$(echo "$CMD" | grep -oE -- "--force-with-lease" | head -1)
  if [ -z "$HAS_LEASE" ]; then
    block "BLOCKED: git push --force can destroy remote history. Use --force-with-lease if you must."
  fi
  # WHY strip-then-recheck: catches "git push --force-with-lease --force origin main"
  # where user has both safe and unsafe flags simultaneously.
  STRIPPED=$(echo "$CMD" | sed 's/--force-with-lease//g')
  if echo "$STRIPPED" | grep -qE "(--force|-f)( |$)"; then
    block "BLOCKED: git push --force detected alongside --force-with-lease. Remove bare --force."
  fi
fi

# WHY \s\+[^ ]: git supports +refspec as force push syntax — "git push origin +main"
# is equivalent to "git push --force origin main" for that ref. The \s before + ensures
# we match a flag/arg boundary, not a branch name containing + (e.g. feature+1).
if echo "$CMD" | grep -qE "git push.*\s\+[^ ]"; then
  block "BLOCKED: git push +refspec is a force push. Use --force-with-lease if you must."
fi

if echo "$CMD" | grep -q "git reset --hard"; then
  block "BLOCKED: git reset --hard discards all uncommitted work. Stash first (git stash)."
fi

# WHY -[a-zA-Z]*f: catches any flag cluster containing f (e.g. -f, -df, -fd, -fnd).
# Plain "-f" misses "-df" because 'd' sits between '-' and 'f'. Same approach as rm -r pattern.
if echo "$CMD" | grep -qE "git clean.*-[a-zA-Z]*f"; then
  block "BLOCKED: git clean -f permanently deletes untracked files. Review with git clean -n first."
fi

# WHY \b.*\s before \.: catches "git checkout ." AND "git checkout HEAD ." AND
# "git checkout HEAD~1 ." — all restore all files and are destructive.
# The old pattern (-- )? only caught bare "." and "-- ." forms, missing refs before dot.
# \b prevents matching "git checkoutx". ( |$) after \. prevents "git checkout ./specific/path".
# FALSE POSITIVE: "git checkout --ours ." (merge conflict) is blocked — use marker bypass.
if echo "$CMD" | grep -qE "git checkout\b.*\s\\.( |$)"; then
  block "BLOCKED: git checkout . discards all unstaged changes. Stash first (git stash)."
fi

# WHY \s(-f|--force)( |$): catches "git checkout -f main" (force switch, discards local changes).
# The \s before -f ensures we don't match branch names ending in -f (e.g. my-feature-f).
# Does NOT overlap with "git checkout ." above — that catches "." target, this catches -f flag.
if echo "$CMD" | grep -qE "git checkout.*\s(-f|--force)( |$)"; then
  block "BLOCKED: git checkout -f discards all local changes. Stash first (git stash)."
fi

# WHY same \b.*\s pattern as checkout: "git restore -- .", "git restore --source=HEAD~1 ."
# are equally destructive. Catches any flags/refs before the dot target.
# FALSE POSITIVE: "git restore --staged ." (unstage, not destructive) — use marker bypass.
if echo "$CMD" | grep -qE "git restore\b.*\s\\.( |$)"; then
  block "BLOCKED: git restore . discards all unstaged changes. Stash first (git stash)."
fi

# WHY \s-D(\s|$): requires whitespace before -D to avoid matching branch names
# containing "-D" as substring (e.g. "git branch -m feature-Dev" was a false positive).
# (\s|$) after -D prevents matching -Dfoo (not a real flag, but defensive).
if echo "$CMD" | grep -qE "git branch.*\s-D(\s|$)"; then
  block "BLOCKED: git branch -D permanently deletes branch even if unmerged. Use -d for safe delete."
fi

# WHY drop AND clear: drop loses one stash entry, clear loses ALL. Both are effectively
# unrecoverable (technically git fsck --unreachable, but that's expert-level recovery).
if echo "$CMD" | grep -qE "git stash (drop|clear)"; then
  block "BLOCKED: git stash drop/clear permanently loses stashed work. Verify with user first."
fi

# === Database dangerous operations ===

if echo "$CMD" | grep -qE "alembic downgrade"; then
  block "BLOCKED: alembic downgrade can destroy data/tables. Verify with user before proceeding."
fi

# === Recursive delete protection ===
# WARNING: Whitelist must check EACH sub-command separately (split on && and ;).
# Without splitting, "rm -rf node_modules/ && rm -rf backend/" passes because
# node_modules appears anywhere in the full string. The whitelist then exempts the
# entire chained command, letting "rm -rf backend/" through.
#
# WHY -[a-zA-Z]*r[a-zA-Z]* and --recursive: catches all short-flag combos containing -r
# (e.g. -rf, -rfv, -fr, -r) AND the long form --recursive.
# KNOWN LIMITATION: "rm -f -r src/" with -r as a separate flag cluster is NOT caught
# by the short-flag pattern. Would need "rm\s+(-[a-zA-Z]+\s+)*-[a-zA-Z]*r" which
# risks false positives. Acceptable: AI always generates "rm -rf", never "rm -f -r".
SAFE_TARGETS="(node_modules|__pycache__|\.pytest_cache|dist|build|\.cache|coverage|\.next|\.nuxt|\.vite|htmlcov|\.mypy_cache|\.ruff_cache)"

if echo "$CMD" | grep -qE "rm\s+(-[a-zA-Z]*r[a-zA-Z]*\s|--recursive)"; then
  # Split chained commands on &&, ;, and | then check each rm independently
  # WHY split on all three: prevents whitelist bypass via chaining.
  # "rm -rf safe/ && rm -rf dangerous/" was the original bug.
  # WHY |: "rm -rf safe/ | rm -rf dangerous/" is nonsensical but still executes both.
  FOUND_UNSAFE=""
  while IFS= read -r SUBCMD; do
    # Skip sub-commands that don't contain rm
    if ! echo "$SUBCMD" | grep -qE "rm\s+" 2>/dev/null; then
      continue
    fi
    # Check if this specific rm targets a safe (whitelisted) directory
    if ! echo "$SUBCMD" | grep -qE "${SAFE_TARGETS}(/|\s|$)"; then
      FOUND_UNSAFE="$SUBCMD"
      break
    fi
  done < <(echo "$CMD" | tr ';&|' '\n')
  if [ -n "$FOUND_UNSAFE" ]; then
    block "BLOCKED: rm -rf can permanently delete source files. Verify the target directory is correct."
  fi
fi

# === Secrets protection (covers Bash bypasses of block-protected-files.sh) ===
# WHY separate from block-protected-files.sh: that hook only fires on Edit|Write tools.
# Bash redirects (echo x > .env), cp, mv, and tee bypass it entirely.

# WHY \.env([.-][a-zA-Z0-9]+)*(\s|$): anchors .env to end-of-word to prevent false positives.
# Matches: .env, .env.local, .env.PRODUCTION, .env-backup, .env.Development
# Does NOT match: .environment, .envoy (next char after .env is not [.-], and (\s|$) fails)
# WHY [.-] not just \.: also catches hyphen-separated variants (.env-backup, .env-staging)
# WHY [a-zA-Z0-9] not [a-z]: some tools use uppercase (.env.PRODUCTION, .env.LOCAL).
# WHY exclude .env.example/.env-example: template files with placeholder values, safe to write.
if echo "$CMD" | grep -qE '(>|>>)\s*[^ ]*\.env([.-][a-zA-Z0-9]+)*(\s|$)' && ! echo "$CMD" | grep -qE '\.env[.-]example'; then
  block "BLOCKED: Writing to .env via redirect. Edit .env files manually outside Claude Code."
fi

# WHY same \.env([.-][a-zA-Z0-9]+)*(\s|$) pattern: consistent with redirect check above.
# WHY cp/mv separate from tee: cp/mv need 2+ args (source dest), so .*\s+ correctly
# requires a space before the .env target. tee writes to ALL file args directly —
# "echo x | tee .env" has .env as the only arg, no preceding space after "tee ".
if echo "$CMD" | grep -qE '(cp|mv)\s+.*\s+[^ ]*\.env([.-][a-zA-Z0-9]+)*(\s|$)' && ! echo "$CMD" | grep -qE '\.env[.-]example'; then
  block "BLOCKED: Copying/moving to .env file. Edit .env files manually outside Claude Code."
fi

if echo "$CMD" | grep -qE 'tee\s+.*\.env([.-][a-zA-Z0-9]+)*(\s|$)' && ! echo "$CMD" | grep -qE '\.env[.-]example'; then
  block "BLOCKED: Writing to .env via tee. Edit .env files manually outside Claude Code."
fi

exit 0
