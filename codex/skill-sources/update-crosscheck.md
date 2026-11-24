---
name: update-crosscheck
description: Update CrossCheck to the latest version — pulls from main. Skills and agents update instantly via symlinks; new ones get linked automatically.
---

**Created:** 2026-02-23-00-00
**Last Updated:** 2026-11-24-08-43

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
if ! git fetch origin main --quiet; then
    echo "❌ Failed to fetch origin/main; no update was applied." >&2
    exit 1
fi

CURRENT_BRANCH=$(git branch --show-current) || {
    echo "❌ Failed to read the current branch." >&2
    exit 1
}
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "   Switching to main branch (was on: $CURRENT_BRANCH)..."
    git checkout main --quiet || {
        echo "❌ Failed to switch to main (dirty working tree or conflicts)."
        echo "   Resolve the issue and retry."
        exit 1
    }
fi

BEHIND=$(git rev-list HEAD..origin/main --count 2>/dev/null) || {
    echo "❌ Failed to determine whether origin/main has new commits." >&2
    exit 1
}
if ! [[ "$BEHIND" =~ ^[0-9]+$ ]]; then
    echo "❌ Git returned an invalid commit count: $BEHIND" >&2
    exit 1
fi

if [ "$BEHIND" = "0" ]; then
    echo "✅ Already up to date (version $CURRENT)"
else
    echo "   $BEHIND new commit(s) available — pulling..."
    if ! git pull origin main --quiet; then
        echo "❌ Failed to pull origin/main." >&2
        exit 1
    fi
    echo "   ✅ Pulled latest"
fi
```


## Step 4: Sync Critical Deny Rules and the Claude Hook

Update existing settings through the managed scripts. They preserve a settings
symlink and refuse to replace concurrent edits.

```bash
SETTINGS_SYNC_FAILED=0
CLAUDE_SYNC_FAILED=0
for SETTINGS_FILE in "$HOME/.claude/settings.json" "$HOME/.codex/settings.json" "$HOME/.gemini/settings.json"; do
    if [ -f "$SETTINGS_FILE" ]; then
        if ! "$CROSSCHECK_DIR/scripts/sync-critical-settings.sh" "$SETTINGS_FILE" --include-ask; then
            echo "❌ Failed to sync critical settings in $SETTINGS_FILE." >&2
            SETTINGS_SYNC_FAILED=1
            if [ "$SETTINGS_FILE" = "$HOME/.claude/settings.json" ]; then
                CLAUDE_SYNC_FAILED=1
            fi
        fi
    fi
done

if [ -f "$HOME/.claude/settings.json" ] && [ "$CLAUDE_SYNC_FAILED" -eq 0 ]; then
    if ! "$CROSSCHECK_DIR/claude/scripts/install-supply-chain-hook.sh" \
        "$HOME/.claude/settings.json" \
        "$CROSSCHECK_DIR/claude/scripts/preuse-supply-chain-gate.sh"; then
        echo "❌ Failed to install the Claude supply-chain hook." >&2
        SETTINGS_SYNC_FAILED=1
    fi
fi

if [ "$SETTINGS_SYNC_FAILED" -ne 0 ]; then
    echo "❌ One or more settings updates failed; successful updates were retained." >&2
    exit 1
fi
```

This keeps the critical deny rules and `Bash(gh api *)` ask rule current, and
refreshes the Claude supply-chain hook without replacing unrelated settings.
The updater attempts every existing settings file before it exits on an error,
so a Claude or Codex failure does not skip the Gemini refresh. It installs the
Claude hook only after Claude settings sync succeeds. When an existing file is
replaced, the updater prints a private recovery path for the prior file. Keep
it until apps that may have the file open are closed and any late save has been
checked.


Settings sync still runs when `main` is already current. Continue to Steps 5
and 6; Step 6 refreshes installed Codex-native skill copies even when there
are no new Git commits.

## Step 5: Show New Version

```bash
LATEST=$(cat "$CROSSCHECK_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

if [ "$CURRENT" = "$LATEST" ]; then
    echo "   Version: $LATEST (patch update, no version bump)"
else
    echo "   Updated: $CURRENT → $LATEST"
fi
```

## Step 6: Wire Any New Skills and Agents

Skills and agents are symlinked to CrossCheck — the git pull already updated
them in place. This step only needs to create symlinks for files that were
*added* since the last bootstrap (new symlinks aren't created by git pull).

```bash
SKIP_FILE="$HOME/.crosscheck/skip-skills"
NEW_LINKED=0

# Refresh Codex-native skills even when main was already current.
if ! bash "$CROSSCHECK_DIR/codex/scripts/sync-managed-codex-skills.sh" "$CROSSCHECK_DIR" "$HOME"; then
    echo "❌ Codex-native skill sync failed." >&2
    exit 1
fi

# New skills
for skill_file in "$CROSSCHECK_DIR/skill-sources/"*.md; do
    skill_name="$(basename "$skill_file" .md)"
    [ "$skill_name" = "INSTALL" ] && continue
    if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
        continue
    fi
    for TARGET_DIR in "$HOME/.codex/commands"; do
        [ -d "$TARGET_DIR" ] || continue
        target="$TARGET_DIR/$skill_name.md"
        if [ ! -e "$target" ] && [ ! -L "$target" ]; then
            ln -sf "$skill_file" "$target"
            echo "   + New skill linked: $skill_name"
            NEW_LINKED=$((NEW_LINKED + 1))
        fi
    done
done

# Claude commands use the Claude mirror and preserve user-owned files.
CLAUDE_SYNC_COUNT="$("$CROSSCHECK_DIR/claude/scripts/sync-managed-claude-skills.sh" "$CROSSCHECK_DIR" "$HOME" --count-only)"
case "$CLAUDE_SYNC_COUNT" in
    ''|*[!0-9]*)
        echo "❌ Claude command sync returned an invalid count: $CLAUDE_SYNC_COUNT" >&2
        exit 1
        ;;
esac
NEW_LINKED=$((NEW_LINKED + CLAUDE_SYNC_COUNT))

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

## Step 7: Report

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
  symlinked by Step 6.
- **CLAUDE.md updates instantly** — symlinked in multi-project mode; git pull
  propagates changes to all sessions automatically.
- **Settings are not overwritten,** but **critical deny rules are synced.** Step 4
  ensures security-critical deny rules (like `--admin` bypass prevention) are always
  present in your settings — this runs even when already up to date.
- **Git hooks are not updated.** If CrossCheck ships hook changes, re-run
  `/setup-automation` in affected repos.
- **Check the release notes** at `github.com/sburl/CrossCheck/releases` for any
  manual migration steps needed for breaking changes.
