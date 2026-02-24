---
name: update-crosscheck
description: Update CrossCheck to the latest version — pulls from main. Skills and agents update instantly via symlinks; new ones get linked automatically.
---

**Created:** 2026-02-23-00-00
**Last Updated:** 2026-02-24-13-46

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

## Step 5: Wire Any New Skills and Agents

Skills and agents are symlinked to CrossCheck — the git pull already updated
them in place. This step only needs to create symlinks for files that were
*added* since the last bootstrap (new symlinks aren't created by git pull).

```bash
SKIP_FILE="$HOME/.crosscheck/skip-skills"
NEW_LINKED=0

# New skills
for skill_file in "$CROSSCHECK_DIR/skill-sources/"*.md; do
    skill_name="$(basename "$skill_file" .md)"
    [ "$skill_name" = "INSTALL" ] && continue
    if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
        continue
    fi
    for TARGET_DIR in "$HOME/.claude/commands" "$HOME/.codex/commands"; do
        [ -d "$TARGET_DIR" ] || continue
        target="$TARGET_DIR/$skill_name.md"
        if [ ! -e "$target" ] && [ ! -L "$target" ]; then
            ln -sf "$skill_file" "$target"
            echo "   + New skill linked: $skill_name"
            NEW_LINKED=$((NEW_LINKED + 1))
        fi
    done
done

# New agents
for agent_path in "$CROSSCHECK_DIR/agents/"*; do
    [ -e "$agent_path" ] || continue
    agent_name="$(basename "$agent_path")"
    for TARGET_DIR in "$HOME/.claude/agents" "$HOME/.codex/agents"; do
        [ -d "$TARGET_DIR" ] || continue
        target="$TARGET_DIR/$agent_name"
        if [ ! -e "$target" ] && [ ! -L "$target" ]; then
            ln -sf "$agent_path" "$target"
            echo "   + New agent linked: $agent_name"
            NEW_LINKED=$((NEW_LINKED + 1))
        fi
    done
done

[ "$NEW_LINKED" -eq 0 ] \
    && echo "   ✅ All symlinks up to date" \
    || echo "   ✅ $NEW_LINKED new symlink(s) created"
```

## Step 6: Report

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

- **Skills and agents update instantly** — they're symlinked to CrossCheck, so
  `git pull` is the update. No re-run needed for existing files; new files get
  symlinked by Step 5.
- **CLAUDE.md updates instantly** — symlinked in multi-project mode; git pull
  propagates changes to all sessions automatically.
- **Settings are not overwritten.** `~/.codex/settings.json` and `~/.claude/settings.json`
  are your personal configs. Re-run bootstrap to pick up settings template changes.
- **Git hooks are not updated.** If CrossCheck ships hook changes, re-run
  `/setup-automation` in affected repos.
- **Check the release notes** at `github.com/sburl/CrossCheck/releases` for any
  manual migration steps needed for breaking changes.
