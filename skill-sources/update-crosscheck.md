---
name: update-crosscheck
description: Update CrossCheck to the latest version — pulls from main, re-syncs skills and agents
---

**Created:** 2026-02-23-00-00
**Last Updated:** 2026-02-24-12-53

# Update CrossCheck

Pull the latest CrossCheck workflow from GitHub and sync skills, agents, and settings
templates to their installed locations.

## Step 1: Find CrossCheck Installation

```bash
# Allow override for non-standard install locations
if [ -n "${CROSSCHECK_DIR:-}" ] && [ -d "$CROSSCHECK_DIR" ] && [ -f "$CROSSCHECK_DIR/VERSION" ]; then
    echo "📍 Using CROSSCHECK_DIR from environment: $CROSSCHECK_DIR"
else
    CROSSCHECK_DIR=""
    for dir in \
        "$HOME/.crosscheck" \
        "$HOME/Developer/CrossCheck" \
        "$HOME/Documents/Developer/CrossCheck" \
        "$HOME/Projects/CrossCheck"; do
        if [ -d "$dir" ] && [ -f "$dir/VERSION" ]; then
            CROSSCHECK_DIR="$dir"
            break
        fi
    done
fi

if [ -z "$CROSSCHECK_DIR" ]; then
    echo "❌ CrossCheck installation not found."
    echo "   Checked: ~/.crosscheck, ~/Developer/CrossCheck, ~/Documents/Developer/CrossCheck"
    echo ""
    echo "   If CrossCheck is at a custom path, set the env var and retry:"
    echo "   export CROSSCHECK_DIR=/path/to/CrossCheck"
    echo ""
    echo "   To install from scratch:"
    echo "   curl -fsSL https://raw.githubusercontent.com/sburl/CrossCheck/main/scripts/bootstrap-crosscheck.sh | bash"
    exit 1
fi

echo "📍 Found CrossCheck at: $CROSSCHECK_DIR"
```

## Step 2: Check Current Version

```bash
CURRENT=$(cat "$CROSSCHECK_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
echo "   Current version: $CURRENT"
```

## Step 3: Pull Latest

```bash
cd "$CROSSCHECK_DIR"
git fetch origin main --quiet

# Ensure we're on main before pulling — avoids merging into a feature branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "   Switching to main branch (was on: $CURRENT_BRANCH)..."
    git checkout main --quiet || {
        echo "❌ Failed to switch to main (dirty working tree or conflicts)."
        echo "   Resolve the issue and retry."
        exit 1
    }
fi

BEHIND=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo "0")

if [ "$BEHIND" = "0" ]; then
    echo "✅ Already up to date (version $CURRENT)"
    exit 0
fi

echo "   $BEHIND new commit(s) available — pulling..."
git pull origin main --quiet
echo "   ✅ Pulled latest"
```

## Step 4: Show New Version

```bash
LATEST=$(cat "$CROSSCHECK_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

if [ "$CURRENT" = "$LATEST" ]; then
    echo "   Version: $LATEST (patch update, no version bump)"
else
    echo "   Updated: $CURRENT → $LATEST"
fi
```

## Step 5: Sync Skills

Re-copy all skills to agent command directories. Respects the skip list
at `~/.crosscheck/skip-skills` if present.

```bash
SKIP_FILE="$HOME/.crosscheck/skip-skills"
SYNCED=0

for TARGET_DIR in "$HOME/.codex/commands" "$HOME/.claude/commands"; do
    [ -d "$TARGET_DIR" ] || continue
    for skill_file in "$CROSSCHECK_DIR/skill-sources/"*.md; do
        skill_name="$(basename "$skill_file" .md)"
        [ "$skill_name" = "INSTALL" ] && continue
        if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
            continue
        fi
        cp "$skill_file" "$TARGET_DIR/"
        SYNCED=$((SYNCED + 1))
    done
done

[ "$SYNCED" -gt 0 ] && echo "   ✅ Skills synced ($SYNCED files)" || echo "   ⚠️  No skill directories found (~/.codex/commands or ~/.claude/commands)"
```

## Step 6: Sync Agents

```bash
if [ -d "$CROSSCHECK_DIR/agents" ]; then
    for TARGET_DIR in "$HOME/.codex/agents" "$HOME/.claude/agents"; do
        [ -d "$TARGET_DIR" ] || continue
        cp -r "$CROSSCHECK_DIR/agents/"* "$TARGET_DIR/" 2>/dev/null
        echo "   ✅ Agents synced to $TARGET_DIR"
    done
fi
```

## Step 7: Sync Global CLAUDE.md

Re-copy `CLAUDE.md` to the projects folder so session-start rules and principles
stay current. CLAUDE.md is managed by CrossCheck — personal overrides go in
`CLAUDE.local.md` (never touched by this script).

```bash
PROJECTS_DIR="$(cd "$CROSSCHECK_DIR/.." && pwd)"
GLOBAL_CLAUDE="$PROJECTS_DIR/CLAUDE.md"

if [ -f "$GLOBAL_CLAUDE" ] || [ -d "$PROJECTS_DIR" ]; then
    cp "$CROSSCHECK_DIR/CLAUDE.md" "$GLOBAL_CLAUDE"
    echo "   ✅ Global CLAUDE.md synced"
else
    echo "   ⚠️  Projects folder not found at $PROJECTS_DIR — skipping CLAUDE.md sync"
    echo "      Set CROSSCHECK_DIR if CrossCheck is at a non-standard path"
fi
```

## Step 8: Report

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ CrossCheck updated to $LATEST"
echo ""
echo "   Restart your agent session to load new skills."
echo ""
echo "   See what changed:"
echo "   https://github.com/sburl/CrossCheck/releases/tag/v${LATEST}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

## Notes

- **Settings are not overwritten.** `~/.codex/settings.json` and `~/.claude/settings.json`
  are your personal configs. Re-run bootstrap if you want to pick up settings template
  changes manually.
- **Git hooks are not updated.** If CrossCheck ships hook changes, re-run
  `/setup-automation` in affected repos.
- **Check the release notes** at `github.com/sburl/CrossCheck/releases` to see if any
  manual migration steps are needed for breaking changes.
