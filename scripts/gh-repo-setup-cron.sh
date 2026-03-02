#!/bin/bash
# Cron job: ensures all sburl repos have the protect-main ruleset,
# and invites sburl-bot to any repos created in the last 25 hours.
#
# Install as a daily cron job:
#   0 8 * * * /path/to/gh-repo-setup-cron.sh >> ~/.local/bin/gh-repo-setup.log 2>&1
#
# Requires: gh (authenticated), jq

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

RULESET_NAME="protect-main"
BOT_USER="sburl-bot"
BOT_PERMISSION="push"
CUTOFF=$(date -u -v-25H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ)

# Load ruleset payload from the checked-in JSON if available,
# otherwise fall back to the inline definition.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULESET_FILE="$SCRIPT_DIR/../.github/rulesets/protect-main.json"

if [ -f "$RULESET_FILE" ]; then
  PAYLOAD=$(cat "$RULESET_FILE")
else
  PAYLOAD=$(cat <<'ENDJSON'
{
  "name": "protect-main",
  "enforcement": "active",
  "target": "branch",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "exclude": [],
      "include": ["~DEFAULT_BRANCH"]
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "required_reviewers": [],
        "require_code_owner_review": true,
        "require_last_push_approval": true,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"]
      }
    }
  ]
}
ENDJSON
  )
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — repo-setup-cron starting"

REPOS_JSON=$(gh repo list sburl --limit 200 --json nameWithOwner,isArchived,createdAt \
  --jq '[.[] | select(.isArchived == false)]')

echo "$REPOS_JSON" | jq -r '.[].nameWithOwner' | while IFS= read -r REPO; do
  echo "--- $REPO ---"

  # 1) Ruleset — always check all repos
  EXISTING=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null || echo "")
  if [ -n "$EXISTING" ]; then
    echo "  Ruleset: OK"
  else
    if gh api "repos/$REPO/rulesets" --method POST --input - <<< "$PAYLOAD" > /dev/null 2>&1; then
      echo "  Ruleset: created"
    else
      echo "  Ruleset: FAILED"
    fi
  fi

  # 2) Collaborator — only for repos created in the last 25 hours
  CREATED_AT=$(echo "$REPOS_JSON" | jq -r ".[] | select(.nameWithOwner == \"$REPO\") | .createdAt")
  if [[ "$CREATED_AT" > "$CUTOFF" ]]; then
    echo "  New repo (created $CREATED_AT) — inviting $BOT_USER..."
    if gh api "repos/$REPO/collaborators/$BOT_USER" --method PUT -f permission="$BOT_PERMISSION" > /dev/null 2>&1; then
      echo "  Collaborator: invited"
    else
      echo "  Collaborator: FAILED"
    fi
  fi
done

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — repo-setup-cron finished"
