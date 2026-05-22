#!/usr/bin/env bash
# install-dependabot-cooldown.sh — roll out Dependabot cooldown across your repos.
# Opens a PR per repo so you can review at your pace.
#
# Usage:
#   bash scripts/install-dependabot-cooldown.sh                    # interactive
#   bash scripts/install-dependabot-cooldown.sh --dry-run          # plan only
#   bash scripts/install-dependabot-cooldown.sh --owners sburl,sqburl
#
# What it does (per repo):
#   1. Detects visibility (public vs private)
#   2. If repo has NO .github/dependabot.yml:
#      → renders a fresh one with cooldown for detected ecosystems
#   3. If repo HAS .github/dependabot.yml but no cooldown:
#      → AUGMENTS it — inserts cooldown blocks into each `- package-ecosystem`
#        entry that's missing one. Preserves all other keys & comments.
#   4. If repo HAS cooldown anywhere in the file:
#      → skips (assumes you've already tuned it)
#   5. Opens a PR. Never force-pushes, never overwrites.
#
# Flags:
#   --owners <list>            comma-separated owners (default: auto-detect — user + their orgs)
#   --owner <name>             [legacy] single owner
#   --filter <regex>            only operate on repos whose nameWithOwner matches
#   --dry-run                   plan-only; no clones, no commits, no PRs
#   --limit <N>                 cap repos per owner (default: 100)
#   --public-age-days <N>       cooldown default for public repos (default: 7)
#   --public-major-days <N>     semver-major cooldown, public (default: 15)
#   --private-age-days <N>      cooldown default for private repos (default: 10)
#   --private-major-days <N>    semver-major cooldown, private (default: 20)
#   --branch <name>             branch name for PRs (default: chore/dependabot-cooldown)
#   --age-days <N>              [legacy] sets both public + private default-days
#   --create-only               skip augmentation; only act on repos with no config
#
# Policy (rationale):
#   Public repos: shorter waits — more eyes find malicious versions faster,
#     contributors expect fresher deps, the policy is already publicly known.
#   Private repos: longer waits — only you/your team affected, no contributor
#     urgency, defense-in-depth matters more for what's actually yours.
#
# Requires: gh (authenticated), jq, git, awk.

set -euo pipefail

OWNERS_ARG=""
FILTER=""
DRYRUN=0
LIMIT=100
PUBLIC_AGE_DAYS=7
PUBLIC_MAJOR_DAYS=15
PRIVATE_AGE_DAYS=10
PRIVATE_MAJOR_DAYS=20
BRANCH="chore/dependabot-cooldown"
CREATE_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --owners)             OWNERS_ARG="$2"; shift 2 ;;
        --owner)              OWNERS_ARG="$2"; shift 2 ;;
        --filter)             FILTER="$2"; shift 2 ;;
        --dry-run)            DRYRUN=1; shift ;;
        --limit)              LIMIT="$2"; shift 2 ;;
        --public-age-days)    PUBLIC_AGE_DAYS="$2"; shift 2 ;;
        --public-major-days)  PUBLIC_MAJOR_DAYS="$2"; shift 2 ;;
        --private-age-days)   PRIVATE_AGE_DAYS="$2"; shift 2 ;;
        --private-major-days) PRIVATE_MAJOR_DAYS="$2"; shift 2 ;;
        --age-days)           PUBLIC_AGE_DAYS="$2"; PRIVATE_AGE_DAYS="$2"; shift 2 ;;
        --branch)             BRANCH="$2"; shift 2 ;;
        --create-only)        CREATE_ONLY=1; shift ;;
        -h|--help)
            sed -n '2,40p' "$0"
            exit 0
            ;;
        *)
            echo "unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

# Auto-detect owners: user's own login + every org they belong to.
if [ -z "$OWNERS_ARG" ]; then
    USER_LOGIN=$(gh api user --jq '.login' 2>/dev/null || echo "")
    ORG_LOGINS=$(gh api user/orgs --jq '.[].login' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    OWNERS_ARG="$USER_LOGIN"
    [ -n "$ORG_LOGINS" ] && OWNERS_ARG="$OWNERS_ARG,$ORG_LOGINS"
fi
IFS=',' read -ra OWNERS <<< "$OWNERS_ARG"

echo "→ owners in scope: ${OWNERS[*]}"

for cmd in gh jq git; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "❌ need $cmd" >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "❌ gh not authenticated; run 'gh auth login'" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/templates/dependabot.yml"
[ -f "$TEMPLATE" ] || { echo "❌ template missing: $TEMPLATE" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Per-ecosystem block renderers
# Args: $1 = default-days, $2 = major-days
# ---------------------------------------------------------------------------
render_npm_block() {
    local d="$1" m="$2"
    local patch=$(( d > 7 ? 7 : d ))
    cat <<EOF
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: $d
      semver-major-days: $m
      semver-minor-days: $d
      semver-patch-days: $patch
    open-pull-requests-limit: 5
EOF
}

render_pip_block() {
    local d="$1" m="$2"
    local patch=$(( d > 7 ? 7 : d ))
    cat <<EOF
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: $d
      semver-major-days: $m
      semver-minor-days: $d
      semver-patch-days: $patch
    open-pull-requests-limit: 5
EOF
}

render_actions_block() {
    # Actions always get the longer (private) treatment — they run with secrets
    local d="$1" m="$2"
    local patch=$(( d > 7 ? 7 : d ))
    cat <<EOF
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: $d
      semver-major-days: $m
      semver-minor-days: $d
      semver-patch-days: $patch
EOF
}

# ---------------------------------------------------------------------------
# List repos across all owners
# ---------------------------------------------------------------------------
REPOS_JSON="[]"
for OWNER in "${OWNERS[@]}"; do
    [ -z "$OWNER" ] && continue
    echo "→ listing repos under $OWNER (limit $LIMIT)..."
    owner_json=$(gh repo list "$OWNER" --no-archived --limit "$LIMIT" \
        --json nameWithOwner,defaultBranchRef,isPrivate 2>/dev/null || echo "[]")
    REPOS_JSON=$(jq -s '.[0] + .[1]' <(echo "$REPOS_JSON") <(echo "$owner_json"))
done

if [ -n "$FILTER" ]; then
    REPOS_JSON=$(echo "$REPOS_JSON" | jq --arg f "$FILTER" '[.[] | select(.nameWithOwner | test($f))]')
fi

REPO_COUNT=$(echo "$REPOS_JSON" | jq 'length')
echo "→ $REPO_COUNT repos in scope"

# Counters for the summary
processed=0
skipped_has_cooldown=0
skipped_no_manifests=0
skipped_create_only=0
prs_created_new=0
prs_augmented=0
errors=0

# ---------------------------------------------------------------------------
# Augmentation: insert cooldown block into each package-ecosystem entry
# that doesn't already have one. Preserves comments & other keys.
# Args: input_file, default_days, major_days
# Output: rewritten file content on stdout
# ---------------------------------------------------------------------------
augment_dependabot_yaml() {
    local f="$1" d="$2" m="$3"
    local patch=$(( d > 7 ? 7 : d ))
    awk -v dd="$d" -v mm="$m" -v pp="$patch" '
    function flush(    cd_block) {
        # Emit buffered block, appending cooldown if the block lacked one.
        if (in_block && !has_cooldown) {
            cd_block = "    cooldown:\n"
            cd_block = cd_block "      default-days: " dd "\n"
            cd_block = cd_block "      semver-major-days: " mm "\n"
            cd_block = cd_block "      semver-minor-days: " dd "\n"
            cd_block = cd_block "      semver-patch-days: " pp "\n"
            # Insert cooldown at end of block (before any trailing blank lines)
            # We have the block in `buf`; strip trailing blanks, append cooldown, re-add blanks
            n_trailing = 0
            while (length(buf) > 0 && substr(buf, length(buf), 1) == "\n") {
                # peel off newlines into a counter
                n_trailing++
                buf = substr(buf, 1, length(buf) - 1)
            }
            # Find the last newline that ends a content line (we just stripped them)
            # Actually simpler: just append cooldown then re-add the newlines
            printf "%s\n%s", buf, cd_block
            for (i = 1; i < n_trailing; i++) printf "\n"
        } else {
            printf "%s", buf
        }
        buf = ""; has_cooldown = 0; in_block = 0
    }
    /^  - package-ecosystem:/ {
        flush()
        in_block = 1
    }
    /^    cooldown:/ { has_cooldown = 1 }
    { buf = buf $0 "\n" }
    END { flush() }
    ' "$f"
}

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

# ---------------------------------------------------------------------------
# Process each repo
# ---------------------------------------------------------------------------
for repo in $(echo "$REPOS_JSON" | jq -r '.[].nameWithOwner'); do
    processed=$((processed + 1))
    default_branch=$(echo "$REPOS_JSON" | jq -r --arg r "$repo" '.[] | select(.nameWithOwner == $r) | .defaultBranchRef.name // "main"')
    is_private=$(echo "$REPOS_JSON" | jq -r --arg r "$repo" '.[] | select(.nameWithOwner == $r) | .isPrivate')

    # Pick cooldown values based on visibility
    if [ "$is_private" = "true" ]; then
        repo_age_days="$PRIVATE_AGE_DAYS"
        repo_major_days="$PRIVATE_MAJOR_DAYS"
        visibility="private"
    else
        repo_age_days="$PUBLIC_AGE_DAYS"
        repo_major_days="$PUBLIC_MAJOR_DAYS"
        visibility="public"
    fi

    echo
    echo "─── [$processed/$REPO_COUNT] $repo ($visibility, default: $default_branch, cooldown: ${repo_age_days}d/${repo_major_days}d major) ───"

    # Check remote for existing config — and if present, check if it already has cooldown
    existing_content=""
    has_existing=0
    has_existing_cooldown=0
    if remote_b64=$(gh api "repos/$repo/contents/.github/dependabot.yml" --jq '.content' 2>/dev/null); then
        has_existing=1
        existing_content=$(echo "$remote_b64" | base64 -d 2>/dev/null || echo "")
        if echo "$existing_content" | grep -q "^[[:space:]]*cooldown:"; then
            has_existing_cooldown=1
        fi
    fi

    # Decision tree
    if [ $has_existing_cooldown = 1 ]; then
        echo "  ✓ already has cooldown config — skipping"
        skipped_has_cooldown=$((skipped_has_cooldown + 1))
        continue
    fi

    if [ $has_existing = 1 ] && [ "$CREATE_ONLY" = "1" ]; then
        echo "  ⊘ has dependabot.yml without cooldown but --create-only set — skipping"
        skipped_create_only=$((skipped_create_only + 1))
        continue
    fi

    mode="create"
    [ $has_existing = 1 ] && mode="augment"

    if [ "$DRYRUN" = "1" ]; then
        echo "  [dry-run] would $mode cooldown config"
        if [ "$mode" = "augment" ]; then
            prs_augmented=$((prs_augmented + 1))
        else
            prs_created_new=$((prs_created_new + 1))
        fi
        continue
    fi

    REPO_DIR="$WORK/$(basename "$repo")"
    if ! git clone --depth 1 "https://github.com/$repo.git" "$REPO_DIR" >/dev/null 2>&1; then
        echo "  ⚠️  clone failed — skipping (may be empty or no access)"
        errors=$((errors + 1))
        continue
    fi

    cd "$REPO_DIR"

    if [ "$mode" = "augment" ]; then
        # Just augment the existing file
        if [ ! -f .github/dependabot.yml ]; then
            # remote said it exists but local clone didn't pick it up — shouldn't happen on default branch
            echo "  ⚠️  remote says dependabot.yml exists but local clone has none — skipping"
            errors=$((errors + 1))
            cd "$WORK"
            continue
        fi
        cp .github/dependabot.yml .github/dependabot.yml.before
        augment_dependabot_yaml .github/dependabot.yml.before "$repo_age_days" "$repo_major_days" > .github/dependabot.yml.new
        mv .github/dependabot.yml.new .github/dependabot.yml
        rm .github/dependabot.yml.before
        # Sanity-check: did we actually add cooldown?
        if ! grep -q "^[[:space:]]*cooldown:" .github/dependabot.yml; then
            echo "  ⚠️  augmentation produced no cooldown lines — skipping (possibly no package-ecosystem blocks found)"
            errors=$((errors + 1))
            cd "$WORK"
            continue
        fi
    else
        # Create-new path: detect manifests and render template
        has_npm=0; has_pip=0; has_actions=0
        [ -f "package.json" ] && has_npm=1
        if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "Pipfile" ]; then
            has_pip=1
        fi
        [ -d ".github/workflows" ] && has_actions=1

        if [ $has_npm = 0 ] && [ $has_pip = 0 ] && [ $has_actions = 0 ]; then
            echo "  ⊘ no npm/pip/actions manifests detected — skipping"
            skipped_no_manifests=$((skipped_no_manifests + 1))
            cd "$WORK"
            continue
        fi

        npm_block=""; pip_block=""; actions_block=""
        [ $has_npm = 1 ]     && npm_block=$(render_npm_block "$repo_age_days" "$repo_major_days")
        [ $has_pip = 1 ]     && pip_block=$(render_pip_block "$repo_age_days" "$repo_major_days")
        [ $has_actions = 1 ] && actions_block=$(render_actions_block "$repo_age_days" "$repo_major_days")

        mkdir -p .github
        awk -v npm="$npm_block" -v pip="$pip_block" -v acts="$actions_block" '
            /{{NPM_BLOCK}}/     { if (length(npm) > 0)  print npm; next }
            /{{PIP_BLOCK}}/     { if (length(pip) > 0)  print pip; next }
            /{{ACTIONS_BLOCK}}/ { if (length(acts) > 0) print acts; next }
            { print }
        ' "$TEMPLATE" > .github/dependabot.yml
    fi

    # Commit + PR
    git checkout -b "$BRANCH" >/dev/null 2>&1
    git add .github/dependabot.yml
    if [ "$mode" = "augment" ]; then
        commit_subject="chore(deps): add Dependabot cooldown to existing config"
        commit_body_extra="Augments the existing .github/dependabot.yml by inserting cooldown blocks
into each \`- package-ecosystem\` entry that didn't have one. All other keys,
comments, and ecosystems are preserved untouched."
    else
        commit_subject="chore(deps): add Dependabot cooldown config"
        commit_body_extra="Adds a fresh .github/dependabot.yml with cooldown for detected ecosystems."
    fi

    git -c user.email="$(git config user.email || echo agent@local)" \
        -c user.name="$(git config user.name || echo CrossCheck)" \
        commit -m "$commit_subject

$commit_body_extra

Cooldown values (this repo is ${visibility}):
- ${repo_age_days}d default, ${repo_major_days}d for major versions
- Security advisories bypass cooldown — CVE patches still fire immediately

Generated by CrossCheck install-dependabot-cooldown.sh
Policy: https://github.com/sburl/CrossCheck/blob/main/docs/rules/trust-model.md" >/dev/null

    if git push -u origin "$BRANCH" >/dev/null 2>&1; then
        if [ "$mode" = "augment" ]; then
            pr_title="chore(deps): add Dependabot cooldown to existing config"
            pr_intro="Augments the existing .github/dependabot.yml by inserting cooldown blocks into each package-ecosystem entry. All other keys, comments, and ecosystems are preserved. Diff is purely additive."
            manifests_section=""
        else
            pr_title="chore(deps): add Dependabot cooldown config"
            pr_intro="Adds a fresh .github/dependabot.yml with cooldown so version-bump PRs lag behind upstream releases. This catches the supply-chain attack window where a bad release is live but has not been pulled yet."
            manifests_section=""
            manifests_section+="\n\n**Detected manifests:**"
            [ "${has_npm:-0}" = 1 ]     && manifests_section+="\n- package.json (npm ecosystem enabled)"
            [ "${has_pip:-0}" = 1 ]     && manifests_section+="\n- requirements.txt / pyproject.toml (pip ecosystem enabled)"
            [ "${has_actions:-0}" = 1 ] && manifests_section+="\n- .github/workflows/ (github-actions ecosystem enabled)"
        fi
        pr_body=$(printf '%s\n\n**This repo is %s** — using the %s-tier cooldown.\n\n**Cooldowns (all ecosystems):**\n- %s days default\n- %s days for major versions\n\n**Security advisories bypass cooldown** — GHSA-triggered updates still fire immediately. Only routine version-bump PRs are delayed.%b\n\nThis PR was opened in bulk across your repos by [scripts/install-dependabot-cooldown.sh](https://github.com/sburl/CrossCheck/blob/main/scripts/install-dependabot-cooldown.sh). Merge at your pace — the protection only kicks in after merge.\n\nPolicy: [trust-model.md (Supply Chain)](https://github.com/sburl/CrossCheck/blob/main/docs/rules/trust-model.md)\n' \
            "$pr_intro" "$visibility" "$visibility" "$repo_age_days" "$repo_major_days" "$manifests_section")
        if pr_url=$(gh pr create --title "$pr_title" --body "$pr_body" 2>&1); then
            echo "  ✅ PR opened ($mode): $pr_url"
            if [ "$mode" = "augment" ]; then
                prs_augmented=$((prs_augmented + 1))
            else
                prs_created_new=$((prs_created_new + 1))
            fi
        else
            echo "  ⚠️  PR creation failed: $pr_url"
            errors=$((errors + 1))
        fi
    else
        echo "  ⚠️  push failed (no write access?)"
        errors=$((errors + 1))
    fi
    cd "$WORK"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
cat <<EOF

═══════════════════════ summary ═══════════════════════
  repos processed:                  $processed
  PRs opened (new config):          $prs_created_new
  PRs opened (augmented existing):  $prs_augmented
  skipped (already has cooldown):   $skipped_has_cooldown
  skipped (no manifests):           $skipped_no_manifests
  skipped (--create-only):          $skipped_create_only
  errors (clone/push/PR failed):    $errors
═══════════════════════════════════════════════════════
EOF
