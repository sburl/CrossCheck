#!/usr/bin/env bash
set -euo pipefail

BRANCHES=(
  "chore/pr51-pr53-cleanup"
  "feat/pr46-gh-repo-setup-cron"
  "feat/pr49-50-ci-nightly-audit"
  "feat/pr52-54-gemini-telemetry-hardened"
  "feat/pr57-bot-reviewer"
  "feat/pr58-bot-reviewer-map"
)

REPO="sburl/CrossCheck"
REQUIRED_ACCOUNT="${REQUIRED_ACCOUNT_OVERRIDE:-sburl-bot}"

if ! CURRENT_ACCOUNT="$(gh api /user --jq '.login' 2>/dev/null)"; then
  echo "❌ No active gh auth session. Run: gh auth login --hostname github.com --git-protocol https --web" >&2
  exit 1
fi
if [[ "$CURRENT_ACCOUNT" != "$REQUIRED_ACCOUNT" ]]; then
  echo "❌ Wrong account: $CURRENT_ACCOUNT (expected $REQUIRED_ACCOUNT)." >&2
  exit 1
fi

if [[ "$(gh api "repos/$REPO" --jq '.permissions.push')" != "true" ]]; then
  echo "❌ Account $CURRENT_ACCOUNT does not have push access to $REPO." >&2
  exit 1
fi

for branch in "${BRANCHES[@]}"; do
  if ! git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "⚠️  branch missing locally: $branch"
    continue
  fi

  git checkout "$branch"

  if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    echo "==> pushing $branch"
    git push -u origin "$branch"
  else
    echo "==> $branch already on origin; skipping push"
  fi

  if gh pr view "$branch" --repo "$REPO" >/dev/null 2>&1; then
    echo "==> PR already exists for $branch"
  else
    title="$(git log -1 --pretty=%s "$branch")"
    echo "==> creating PR for $branch"
    gh pr create \
      --repo "$REPO" \
      --base main \
      --head "$branch" \
      --title "$title" \
      --body "Automated branch handoff: ${branch}."
  fi
done

echo "✅ Branch push + PR workflow complete."
