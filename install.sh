#!/bin/bash
# Install global Claude Code config from this repo to ~/.claude/
# Run: bash install.sh
# Safe: backs up existing files before overwriting.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing claude-code-config to $CLAUDE_DIR"

# Backup existing config
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak"
  echo "  Backed up existing CLAUDE.md → CLAUDE.md.bak"
fi

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak"
  echo "  Backed up existing settings.json → settings.json.bak"
fi

# Install global config
cp "$SCRIPT_DIR/global/CLAUDE.md" "$CLAUDE_DIR/"
cp "$SCRIPT_DIR/global/settings.json" "$CLAUDE_DIR/"
echo "  Installed CLAUDE.md and settings.json"

# Install global hooks
mkdir -p "$CLAUDE_DIR/hooks"
cp "$SCRIPT_DIR/global/hooks/"*.sh "$CLAUDE_DIR/hooks/"
echo "  Installed $(ls "$SCRIPT_DIR/global/hooks/"*.sh | wc -l) global hooks"

echo ""
echo "Done. Global hooks active for all projects:"
ls "$CLAUDE_DIR/hooks/"
echo ""
echo "To add project-specific hooks, copy from projects/ templates."
