#!/usr/bin/env bash
# install-dependabot-cooldown.sh — add Dependabot cooldown config to repos that
# don't have one. Opens a PR per repo so you can review at your pace.
#
# Usage:
#   bash scripts/install-dependabot-cooldown.sh                    # interactive
#   bash scripts/install-dependabot-cooldown.sh --dry-run          # plan only
#   bash scripts/install-dependabot-cooldown.sh --owner sburl --filter foo
#
# What it does:
#   1. Lists non-archived repos for the owner
#   2. For each: clones shallow, checks for .github/dependabot.yml
#   3. If MISSING: detects manifests (package.json, requirements.txt,
#      pyproject.toml, .github/workflows/), renders templates/dependabot.yml
#      with only the relevant ecosystem blocks, pushes a branch, opens a PR.
#   4. If PRESENT: skips (does NOT overwrite — your existing config wins).
#
# Flags:
#   --owner <name>            repo owner (default: sburl)
#   --filter <regex>           only operate on repos whose nameWithOwner matches
#   --dry-run                  plan-only; no clones, no commits, no PRs
#   --limit <N>                cap the number of repos to process (default: 100)
#   --public-age-days <N>      default cooldown for public repos (default: 7)
#   --public-major-days <N>    semver-major cooldown, public (default: 15)
#   --private-age-days <N>     default cooldown for private repos (default: 10)
#   --private-major-days <N>   semver-major cooldown, private (default: 20)
#   --branch <name>            branch name for the PR (default: chore/dependabot-cooldown)
#   --age-days <N>             [legacy] applies the same value to public + private default-days
#
# Policy (rationale for the asymmetry):
#   Public repos: shorter waits — more eyes find malicious versions faster,
#     contributors expect fresher deps, you're less of a single point of failure.
#   Private repos: longer waits — only you/your team affected, no contributor
#     urgency, defense-in-depth matters more.
#
# Requires: gh (authenticated), jq, git.

set -euo pipefail

OWNER="sburl"
FILTER=""
DRYRUN=0
LIMIT=100
PUBLIC_AGE_DAYS=7
PUBLIC_MAJOR_DAYS=15
PRIVATE_AGE_DAYS=10
PRIVATE_MAJOR_DAYS=20
BRANCH="chore/dependabot-cooldown"

while [ $# -gt 0 ]; do
    case "$1" in
        --owner)              OWNER="$2"; shift 2 ;;
        --filter)             FILTER="$2"; shift 2 ;;
        --dry-run)            DRYRUN=1; shift ;;
        --limit)              LIMIT="$2"; shift 2 ;;
        --public-age-days)    PUBLIC_AGE_DAYS="$2"; shift 2 ;;
        --public-major-days)  PUBLIC_MAJOR_DAYS="$2"; shift 2 ;;
        --private-age-days)   PRIVATE_AGE_DAYS="$2"; shift 2 ;;
        --private-major-days) PRIVATE_MAJOR_DAYS="$2"; shift 2 ;;
        --age-days)           PUBLIC_AGE_DAYS="$2"; PRIVATE_AGE_DAYS="$2"; shift 2 ;;
        --branch)             BRANCH="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        *)
            echo "unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

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
# List repos
# ---------------------------------------------------------------------------
echo "→ listing repos under $OWNER (limit $LIMIT)..."
REPOS_JSON=$(gh repo list "$OWNER" --no-archived --limit "$LIMIT" \
    --json nameWithOwner,defaultBranchRef,isPrivate)

if [ -n "$FILTER" ]; then
    REPOS_JSON=$(echo "$REPOS_JSON" | jq --arg f "$FILTER" '[.[] | select(.nameWithOwner | test($f))]')
fi

REPO_COUNT=$(echo "$REPOS_JSON" | jq 'length')
echo "→ $REPO_COUNT repos in scope"

# Counters for the summary
processed=0
skipped_has_config=0
skipped_empty=0
skipped_no_manifests=0
prs_opened=0
errors=0

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

    # Quick remote check for the file — saves the clone in most cases
    if gh api "repos/$repo/contents/.github/dependabot.yml" >/dev/null 2>&1; then
        echo "  ✓ already has .github/dependabot.yml — skipping"
        skipped_has_config=$((skipped_has_config + 1))
        continue
    fi

    if [ "$DRYRUN" = "1" ]; then
        echo "  [dry-run] would add cooldown config"
        prs_opened=$((prs_opened + 1))
        continue
    fi

    REPO_DIR="$WORK/$(basename "$repo")"
    if ! git clone --depth 1 "https://github.com/$repo.git" "$REPO_DIR" >/dev/null 2>&1; then
        echo "  ⚠️  clone failed — skipping (may be empty or no access)"
        errors=$((errors + 1))
        continue
    fi

    cd "$REPO_DIR"

    # Detect manifests
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

    # Render template
    npm_block=""; pip_block=""; actions_block=""
    [ $has_npm = 1 ]     && npm_block=$(render_npm_block "$repo_age_days" "$repo_major_days")
    [ $has_pip = 1 ]     && pip_block=$(render_pip_block "$repo_age_days" "$repo_major_days")
    [ $has_actions = 1 ] && actions_block=$(render_actions_block "$repo_age_days" "$repo_major_days")

    # Build the file from the template by substituting the markers.
    # Use awk to handle multi-line replacements cleanly.
    mkdir -p .github
    awk -v npm="$npm_block" -v pip="$pip_block" -v acts="$actions_block" '
        /{{NPM_BLOCK}}/     { if (length(npm) > 0)  print npm; next }
        /{{PIP_BLOCK}}/     { if (length(pip) > 0)  print pip; next }
        /{{ACTIONS_BLOCK}}/ { if (length(acts) > 0) print acts; next }
        { print }
    ' "$TEMPLATE" > .github/dependabot.yml

    # Commit + PR
    git checkout -b "$BRANCH" >/dev/null 2>&1
    git add .github/dependabot.yml
    git -c user.email="$(git config user.email || echo agent@local)" \
        -c user.name="$(git config user.name || echo CrossCheck)" \
        commit -m "chore(deps): add Dependabot cooldown config

Adds a Dependabot config with cooldown so version-bump PRs lag behind the
upstream release. Catches the supply-chain attack window where a bad
release is live but hasn't been pulled yet.

This repo is ${visibility}: ${repo_age_days}-day default cooldown,
${repo_major_days}-day cooldown for major versions.

- All ecosystems: ${repo_age_days}d default, ${repo_major_days}d major
- Security advisories bypass cooldown — CVE patches still fire immediately

Generated by CrossCheck install-dependabot-cooldown.sh
Policy: https://github.com/sburl/CrossCheck/blob/main/docs/rules/trust-model.md" >/dev/null

    if git push -u origin "$BRANCH" >/dev/null 2>&1; then
        if pr_url=$(gh pr create \
            --title "chore(deps): add Dependabot cooldown config" \
            --body "$(cat <<EOF
Adds a \`.github/dependabot.yml\` with cooldown so version-bump PRs lag behind upstream releases. This catches the supply-chain attack window where a bad release is live but hasn't been pulled yet.

**This repo is ${visibility}** — using the ${visibility}-tier cooldown.

**Cooldowns (all ecosystems):**
- ${repo_age_days} days default
- ${repo_major_days} days for major versions

**Security advisories bypass cooldown** — GHSA-triggered updates still fire immediately. Only routine version-bump PRs are delayed.

**Detected manifests:**
$([ $has_npm = 1 ]     && echo "- \`package.json\` → npm ecosystem enabled")
$([ $has_pip = 1 ]     && echo "- \`requirements.txt\` / \`pyproject.toml\` → pip ecosystem enabled")
$([ $has_actions = 1 ] && echo "- \`.github/workflows/\` → github-actions ecosystem enabled")

This PR was opened in bulk across your repos by [\`scripts/install-dependabot-cooldown.sh\`](https://github.com/sburl/CrossCheck/blob/main/scripts/install-dependabot-cooldown.sh). Merge at your pace — there's no urgency, but the protection only kicks in after merge.

Policy: [trust-model.md § Supply Chain](https://github.com/sburl/CrossCheck/blob/main/docs/rules/trust-model.md)
EOF
)" 2>&1); then
            echo "  ✅ PR opened: $pr_url"
            prs_opened=$((prs_opened + 1))
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
  PRs opened:                       $prs_opened
  skipped (already has config):     $skipped_has_config
  skipped (no manifests):           $skipped_no_manifests
  errors (clone/push/PR failed):    $errors
═══════════════════════════════════════════════════════
EOF
