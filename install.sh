#!/bin/bash
# Install claude-senior global config to ~/.claude/
# Creates symlinks so edits in ~/.claude/ auto-sync to the repo.
# Run: bash install.sh
#
# REQUIRES: Developer Mode on Windows (Settings → System → Advanced → Developer Mode)
# WHY symlinks: editing ~/.claude/CLAUDE.md edits the repo copy directly.
# Just `git commit && push` to backup — no manual copy step.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# WHY: Git Bash on Windows needs this env var to create native NTFS symlinks.
# Without it, ln -s creates copies instead of symlinks.
export MSYS=winsymlinks:nativestrict

echo "Installing claude-senior to $CLAUDE_DIR (via symlinks)"
echo ""

# WHY check ~/.claude exists: Claude Code creates it on first run.
# If it doesn't exist, user hasn't run Claude Code yet.
if [ ! -d "$CLAUDE_DIR" ]; then
  echo "  Creating $CLAUDE_DIR (first install)"
  mkdir -p "$CLAUDE_DIR/hooks"
fi

mkdir -p "$CLAUDE_DIR/hooks"

# Backup existing files (not symlinks) before overwriting
# WHY skip symlinks: if re-running install, old symlinks don't need backup.
for f in CLAUDE.md settings.json; do
  if [ -f "$CLAUDE_DIR/$f" ] && [ ! -L "$CLAUDE_DIR/$f" ]; then
    cp "$CLAUDE_DIR/$f" "$CLAUDE_DIR/$f.bak"
    echo "  Backed up existing $f → $f.bak"
  fi
done

# WHY backup existing hooks: user may have custom hooks that aren't in this repo.
for hook in "$CLAUDE_DIR/hooks/"*.sh; do
  [ -f "$hook" ] || continue
  if [ ! -L "$hook" ]; then
    name=$(basename "$hook")
    cp "$hook" "$hook.bak"
    echo "  Backed up existing hook $name → $name.bak"
  fi
done

# --- Symlink CLAUDE.md ---
rm -f "$CLAUDE_DIR/CLAUDE.md"
ln -s "$SCRIPT_DIR/global/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

# --- Symlink settings.json ---
# WHY warn instead of overwrite: settings.json contains user-specific permissions,
# plugins, and defaultMode. Blindly overwriting loses their config.
if [ -f "$CLAUDE_DIR/settings.json" ] || [ -L "$CLAUDE_DIR/settings.json" ]; then
  # WHY check if already pointing to us: re-running install shouldn't warn.
  CURRENT_TARGET=$(readlink "$CLAUDE_DIR/settings.json" 2>/dev/null || echo "")
  if [ "$CURRENT_TARGET" = "$SCRIPT_DIR/global/settings.json" ]; then
    echo "  settings.json already linked"
  else
    echo ""
    echo "  ⚠ settings.json already exists."
    echo "  Our settings.json contains hooks config that claude-senior needs."
    echo "  You have two options:"
    echo "    1. Merge manually: copy the \"hooks\" section from global/settings.json into yours"
    echo "    2. Replace: rm ~/.claude/settings.json && bash install.sh"
    echo ""
    echo "  Skipping settings.json (not overwritten)"
    SKIP_SETTINGS=true
  fi
fi

if [ "$SKIP_SETTINGS" != "true" ]; then
  rm -f "$CLAUDE_DIR/settings.json"
  ln -s "$SCRIPT_DIR/global/settings.json" "$CLAUDE_DIR/settings.json"
  echo "  Linked settings.json"
fi

echo "  Linked CLAUDE.md"

# --- Symlink global hooks ---
HOOK_COUNT=0
for hook in "$SCRIPT_DIR/global/hooks/"*.sh; do
  name=$(basename "$hook")
  rm -f "$CLAUDE_DIR/hooks/$name"
  ln -s "$hook" "$CLAUDE_DIR/hooks/$name"
  HOOK_COUNT=$((HOOK_COUNT + 1))
done

echo "  Linked $HOOK_COUNT global hooks"

echo ""
echo "Done. Verify:"
ls -la "$CLAUDE_DIR/CLAUDE.md"
[ "$SKIP_SETTINGS" != "true" ] && ls -la "$CLAUDE_DIR/settings.json"
ls -la "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null | head -3
echo "  ... ($HOOK_COUNT hooks total)"
echo ""
echo "Edits to ~/.claude/ files now auto-sync to this repo."
echo "To push changes: cd $SCRIPT_DIR && git add -A && git commit -m 'update' && git push"
