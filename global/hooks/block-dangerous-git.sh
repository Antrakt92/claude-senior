#!/bin/bash
# PreToolUse hook: blocks dangerous CLI operations.
# Git: force push, reset --hard, clean -f, checkout/restore ., branch -D
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

if echo "$CMD" | grep -q "git reset --hard"; then
  block "BLOCKED: git reset --hard discards all uncommitted work. Stash first (git stash)."
fi

if echo "$CMD" | grep -qE "git clean.*-f"; then
  block "BLOCKED: git clean -f permanently deletes untracked files. Review with git clean -n first."
fi

# WHY (-- )?: "git checkout -- ." is the standard POSIX form and more common than
# "git checkout .". Without the optional "-- ", the standard form bypasses this hook entirely.
# The \. matches literal dot. ( |$) ensures we don't match "git checkout ./specific/path"
# which is a safe, targeted operation.
if echo "$CMD" | grep -qE "git checkout (-- )?\\.( |$)"; then
  block "BLOCKED: git checkout . discards all unstaged changes. Stash first (git stash)."
fi

# WHY same (-- )? pattern as checkout: "git restore -- ." is equally common and destructive.
if echo "$CMD" | grep -qE "git restore (-- )?\\.( |$)"; then
  block "BLOCKED: git restore . discards all unstaged changes. Stash first (git stash)."
fi

# Block force-deleting branches (allow -d safe delete, block -D force delete)
if echo "$CMD" | grep -qE "git branch.*-D"; then
  block "BLOCKED: git branch -D permanently deletes branch even if unmerged. Use -d for safe delete."
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

# WHY \.env(\.[a-z]+)?(\s|$): anchors .env to end-of-word to prevent false positives.
# Matches: .env, .env.local, .env.production, .env.staging
# Does NOT match: .environment, .envoy, config.env.json (substring match would catch these)
# The (\.[a-z]+)? allows one dot-suffix. (\s|$) prevents matching .envoy or .environment.
# WHY exclude .env.example: safe to write — it's a template with placeholder values.
if echo "$CMD" | grep -qE '(>|>>)\s*[^ ]*\.env(\.[a-z]+)?(\s|$)' && ! echo "$CMD" | grep -q '\.env\.example'; then
  block "BLOCKED: Writing to .env via redirect. Edit .env files manually outside Claude Code."
fi

# WHY same \.env(\.[a-z]+)?(\s|$) pattern: consistent with redirect check above.
if echo "$CMD" | grep -qE '(cp|mv|tee)\s+.*\s+[^ ]*\.env(\.[a-z]+)?(\s|$)' && ! echo "$CMD" | grep -q '\.env\.example'; then
  block "BLOCKED: Copying/moving to .env file. Edit .env files manually outside Claude Code."
fi

exit 0
