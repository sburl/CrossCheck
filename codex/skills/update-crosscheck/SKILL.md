---
name: update-crosscheck
description: Update CrossCheck to the latest version, including copied Codex-native skills and newly added legacy skills and agents.
---

**Created:** 2026-02-23-00-00
**Last Updated:** 2026-11-23-23-15

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

## Step 3: Sync Critical Deny Rules

Critical security deny rules must propagate to existing settings even when settings
are not fully overwritten. This runs BEFORE the up-to-date check so it always executes.

```bash
CRITICAL_DENY_RULES=(
    'Bash(gh*--admin*)'
    'Bash(*--admin*)'
    'Bash(gh api*rulesets*)'
    'Bash(gh api*branches/*/protection*)'
    'Bash(*graphql*BranchProtection*)'
    'Bash(*graphql*Ruleset*)'
)

SETTINGS_UPDATED=0
SETTINGS_FAILED=0

for SETTINGS_FILE in "$HOME/.claude/settings.json" "$HOME/.codex/settings.json"; do
    [ -f "$SETTINGS_FILE" ] || continue

    for rule in "${CRITICAL_DENY_RULES[@]}"; do
        if ! jq -e --arg r "$rule" '.permissions.deny | index($r)' "$SETTINGS_FILE" >/dev/null 2>&1; then
            if jq --arg r "$rule" '.permissions.deny += [$r]' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
                && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"; then
                echo "   + Added critical deny rule to $(basename "$SETTINGS_FILE"): $rule"
                SETTINGS_UPDATED=$((SETTINGS_UPDATED + 1))
            else
                echo "   ⚠️  Failed to add deny rule to $(basename "$SETTINGS_FILE"): $rule"
                SETTINGS_FAILED=$((SETTINGS_FAILED + 1))
            fi
        fi
    done

    if ! jq -e '.permissions.ask | index("Bash(gh api *)")' "$SETTINGS_FILE" >/dev/null 2>&1; then
        if jq '.permissions.ask += ["Bash(gh api *)"]' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
            && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"; then
            echo "   + Added gh api to ask list in $(basename "$SETTINGS_FILE")"
            SETTINGS_UPDATED=$((SETTINGS_UPDATED + 1))
        else
            echo "   ⚠️  Failed to update ask list in $(basename "$SETTINGS_FILE")"
            SETTINGS_FAILED=$((SETTINGS_FAILED + 1))
        fi
    fi
done

if [ "$SETTINGS_FAILED" -gt 0 ]; then
    echo "   ⚠️  $SETTINGS_FAILED setting(s) failed to sync — check settings files are valid JSON"
elif [ "$SETTINGS_UPDATED" -eq 0 ]; then
    echo "   ✅ All critical deny rules present"
else
    echo "   ✅ $SETTINGS_UPDATED setting(s) updated with critical security rules"
fi
```

## Step 4: Pull Latest

```bash
cd "$CROSSCHECK_DIR"
git fetch origin main --quiet

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
else
    echo "   $BEHIND new commit(s) available — pulling..."
    git pull origin main --quiet
    echo "   ✅ Pulled latest"
fi
```

Continue to Steps 5 and 6 when `main` is already current. Step 6 refreshes
installed Codex-native skill copies even when there are no new Git commits.

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

# Codex-native skills are copied into ~/.codex/skills, so refresh existing installs.
if [ -d "$CROSSCHECK_DIR/codex/skills" ]; then
    NATIVE_SKILLS_DIR="$CROSSCHECK_DIR/codex/skills"
else
    NATIVE_SKILLS_DIR="$CROSSCHECK_DIR/skills"
fi
NATIVE_UPDATED=0
NATIVE_PRESERVED=0
NATIVE_SKILLS_ROOT="$HOME/.codex/skills"
NATIVE_SOURCE_ROOT="${NATIVE_SKILLS_DIR#"$CROSSCHECK_DIR/"}"

is_known_shipped_codex_file() {
    local target_file="$1" source_path="$2" revision
    if ! git -C "$CROSSCHECK_DIR" rev-parse --verify refs/remotes/origin/main >/dev/null 2>&1; then
        return 1
    fi
    while IFS= read -r revision; do
        if git -C "$CROSSCHECK_DIR" show "$revision:$source_path" 2>/dev/null | cmp -s - "$target_file"; then
            return 0
        fi
    done < <(git -C "$CROSSCHECK_DIR" rev-list refs/remotes/origin/main -- "$source_path" 2>/dev/null)
    return 1
}

has_symlink_ancestor() {
    local current="$1" root="$2"
    while [ "$current" != "$root" ]; do
        [ ! -L "$current" ] || return 0
        current="$(dirname "$current")"
    done
    return 1
}

if [ -L "$HOME/.codex" ] || [ -L "$NATIVE_SKILLS_ROOT" ]; then
    echo "   Preserving linked Codex skills directory; managed skill refresh skipped"
else
    mkdir -p "$NATIVE_SKILLS_ROOT"
for skill_dir in "$NATIVE_SKILLS_DIR"/*; do
    [ -d "$skill_dir" ] || continue
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
        continue
    fi
    target_dir="$NATIVE_SKILLS_ROOT/$skill_name"
    if [ -L "$target_dir" ] || { [ -e "$target_dir" ] && [ ! -d "$target_dir" ]; }; then
        echo "   Preserving linked or non-directory Codex skill: $skill_name"
        NATIVE_PRESERVED=$((NATIVE_PRESERVED + 1))
        continue
    fi
    mkdir -p "$target_dir"
    skill_changed=0
    while IFS= read -r -d '' source_file; do
        relative_path="${source_file#"$skill_dir"/}"
        target_file="$target_dir/$relative_path"
        target_parent="$(dirname "$target_file")"
        if has_symlink_ancestor "$target_parent" "$target_dir" || [ -L "$target_file" ] || { [ -e "$target_file" ] && [ ! -f "$target_file" ]; }; then
            echo "   Preserving linked or non-regular Codex skill path: $skill_name/$relative_path"
            NATIVE_PRESERVED=$((NATIVE_PRESERVED + 1))
            continue
        fi
        if [ -f "$target_file" ]; then
            if cmp -s "$source_file" "$target_file"; then
                continue
            fi
            source_path="$NATIVE_SOURCE_ROOT/$skill_name/$relative_path"
            if ! is_known_shipped_codex_file "$target_file" "$source_path"; then
                echo "   Preserving customized Codex skill file: $skill_name/$relative_path"
                NATIVE_PRESERVED=$((NATIVE_PRESERVED + 1))
                continue
            fi
        fi
        mkdir -p "$target_parent"
        cp "$source_file" "$target_file"
        skill_changed=1
    done < <(find "$skill_dir" -type f -print0)
    if [ "$skill_changed" -eq 1 ]; then
        NATIVE_UPDATED=$((NATIVE_UPDATED + 1))
    fi
done
fi
echo "   ✅ Refreshed $NATIVE_UPDATED Codex-native skill(s); preserved $NATIVE_PRESERVED customized or linked path(s)"

# Claude commands use the Claude mirror and preserve user-owned files.
CLAUDE_SYNC_RESULT="$("$CROSSCHECK_DIR/claude/scripts/sync-managed-claude-skills.sh" "$CROSSCHECK_DIR" "$HOME")"
echo "   $CLAUDE_SYNC_RESULT"
CLAUDE_SYNC_COUNT="${CLAUDE_SYNC_RESULT##*: }"
NEW_LINKED=$((NEW_LINKED + CLAUDE_SYNC_COUNT))

# New Codex compatibility commands use the root sources.
for skill_file in "$CROSSCHECK_DIR/skill-sources/"*.md; do
    skill_name="$(basename "$skill_file" .md)"
    [ "$skill_name" = "INSTALL" ] && continue
    if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
        continue
    fi
    TARGET_DIR="$HOME/.codex/commands"
    [ -d "$TARGET_DIR" ] || continue
    target="$TARGET_DIR/$skill_name.md"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        ln -sf "$skill_file" "$target"
        echo "   + New Codex command linked: $skill_name"
        NEW_LINKED=$((NEW_LINKED + 1))
    fi
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

- **Codex-native skills are copied**, so Step 6 refreshes their installed files.
- **Legacy Claude/Codex commands and agents are symlinked** in multi-project
  mode, so `git pull` updates existing links and Step 6 creates missing links.
- **CLAUDE.md updates instantly** — symlinked in multi-project mode; git pull
  propagates changes to all sessions automatically.
- **Settings are not overwritten,** but **critical deny rules are synced.** Step 3
  ensures security-critical deny rules (like `--admin` bypass prevention) are always
  present in your settings — this runs even when already up to date.
- **Git hooks are not updated.** If CrossCheck ships hook changes, re-run
  `/setup-automation` in affected repos.
- **Check the release notes** at `github.com/sburl/CrossCheck/releases` for any
  manual migration steps needed for breaking changes.
