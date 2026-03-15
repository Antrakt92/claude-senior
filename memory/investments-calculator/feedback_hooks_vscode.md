---
name: Hooks in VS Code — exit 2 works, stdout doesn't
description: Claude Code hooks fire in VS Code but stdout is silently consumed. Use exit 2 + stderr for blocking hooks that AI can see.
type: feedback
summary: "exit 0 + stdout = AI never sees it. exit 2 + stderr = blocks tool and shows message. Use marker file pattern for block-then-allow flow. Both project and global settings.json hooks fire."
---

Hooks DO fire in VS Code extension, but exit 0 stdout is silently consumed — AI never sees it.

**Why:** VS Code extension processes hook output differently from CLI. stdout from exit 0 hooks is discarded.

**How to apply:**
- For hooks that need to communicate with AI: use `exit 2` (blocks tool) + write message to `stderr` (`cat >&2`)
- For side-effect-only hooks (write files, run scripts): `exit 0` works fine
- Use marker file pattern (`/tmp/claude-commit-reviewed`) for "block then allow" flow
- Project-level `.claude/settings.json` hooks work; global `~/.claude/settings.json` hooks also fire but same stdout limitation
