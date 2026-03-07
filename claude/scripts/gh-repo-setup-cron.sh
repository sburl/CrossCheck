#!/usr/bin/env bash
# Cron job: ensure sburl repos are protected and optionally invite bot.
#
# Install as a daily cron job:
#   0 8 * * * /path/to/gh-repo-setup-cron.sh >> ~/.local/bin/gh-repo-setup.log 2>&1
#
# Requires: gh (authenticated), jq

set -euo pipefail

RULESET_NAME="protect-main"
BOT_USER="sburl-bot"
BOT_PERMISSION="push"
OWNER="sburl"

REQUIRED_COMMANDS=(gh jq)
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not found" >&2
    exit 1
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh authentication unavailable" >&2
  exit 1
fi

# Rate limit guard: abort early if remaining quota is dangerously low.
# Each repo can use up to 3 API calls (permissions check, ruleset list, ruleset create/collaborator).
rate_remaining=$(gh api rate_limit --jq '.rate.remaining' 2>/dev/null || echo "999")
if [ "$rate_remaining" -lt 50 ]; then
  rate_reset=$(gh api rate_limit --jq '.rate.reset' 2>/dev/null || echo "unknown")
  echo "ERROR: GitHub API rate limit too low (${rate_remaining} remaining, resets at ${rate_reset})" >&2
  exit 1
fi

CUTOFF=$(date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-25H +%Y-%m-%dT%H:%M:%SZ)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULESET_FILE=""

REPO_ROOT=""
if command -v git >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$SCRIPT_DIR/.."
fi

for candidate in \
  "$REPO_ROOT/.github/rulesets/protect-main.json" \
  "$SCRIPT_DIR/../.github/rulesets/protect-main.json" \
  "$SCRIPT_DIR/../../.github/rulesets/protect-main.json" \
  "$SCRIPT_DIR/../../../.github/rulesets/protect-main.json"
do
  if [ -f "$candidate" ]; then
    RULESET_FILE="$candidate"
    break
  fi
done
PAYLOAD_FILE=""
if [ -z "$RULESET_FILE" ]; then
  echo "WARNING: ruleset payload not found; ruleset creation will be skipped."
fi
if [ -n "$RULESET_FILE" ] && [ -f "$RULESET_FILE" ] && jq -e . "$RULESET_FILE" >/dev/null 2>&1; then
  if jq -e --arg expected "$RULESET_NAME" '.name == $expected' "$RULESET_FILE" >/dev/null 2>&1; then
    PAYLOAD_FILE="$RULESET_FILE"
  else
    echo "WARNING: ruleset payload name mismatch; expected '$RULESET_NAME' in $RULESET_FILE"
  fi
elif [ -n "$RULESET_FILE" ]; then
  echo "WARNING: ruleset payload exists but contains invalid JSON: $RULESET_FILE"
fi

REPOS_JSON=$(gh repo list "$OWNER" --no-archived --limit 300 --json nameWithOwner,createdAt,viewerPermission)

HAS_VIEWER_PERMISSION="true"
if ! jq -e '. | length == 0 or (.[0] | has("viewerPermission"))' >/dev/null 2>&1 <<< "$REPOS_JSON"; then
  HAS_VIEWER_PERMISSION="false"
fi

if [ -z "$REPOS_JSON" ] || [ "$REPOS_JSON" = "null" ]; then
  echo "No repositories found for owner '$OWNER'. Exiting."
  exit 0
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — repo-setup-cron starting"

echo "$REPOS_JSON" | jq -r '.[] | "\(.nameWithOwner)\t\(.createdAt)\t\(.viewerPermission // "")"' |
  while IFS=$'\t' read -r REPO CREATED_AT VIEWER_PERMISSION; do
  if [ -z "$REPO" ]; then
    continue
  fi

  echo "--- $REPO ---"
  CAN_ADMIN="false"
  if [ "$HAS_VIEWER_PERMISSION" = "true" ] && [ -n "$VIEWER_PERMISSION" ]; then
    if [ "$VIEWER_PERMISSION" = "admin" ] || [ "$VIEWER_PERMISSION" = "ADMIN" ]; then
      CAN_ADMIN="true"
    fi
  elif [ "$HAS_VIEWER_PERMISSION" = "true" ]; then
    # Fallback in case viewerPermission is unexpectedly omitted for a specific repo.
    CAN_ADMIN="$(gh api "repos/$REPO" --jq '.permissions.admin // false' 2>/dev/null || echo false)"
  else
    CAN_ADMIN="$(gh api "repos/$REPO" --jq '.permissions.admin // false' 2>/dev/null || echo false)"
  fi

  if [ "$CAN_ADMIN" != "true" ]; then
    echo "  Ruleset: skipped (token lacks repo admin permission)"
  else
    EXISTING=$(gh api "repos/$REPO/rulesets" --paginate --jq \
      ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null | head -n 1 || true)

    if [ -n "$EXISTING" ]; then
      echo "  Ruleset: OK"
    elif [ -n "$PAYLOAD_FILE" ]; then
      if gh api "repos/$REPO/rulesets" --method POST --input "$PAYLOAD_FILE" \
          > /dev/null 2>&1; then
        echo "  Ruleset: created"
      else
        echo "  Ruleset: FAILED"
      fi
    else
      echo "  Ruleset: skipped (missing payload file $RULESET_FILE)"
    fi
  fi

  if [ -n "$CREATED_AT" ] && [[ "$CREATED_AT" > "$CUTOFF" ]]; then
    echo "  New repo (created $CREATED_AT) — inviting $BOT_USER..."
    if [ "$CAN_ADMIN" != "true" ]; then
      echo "  Collaborator: skipped (token lacks repo admin permission)"
    elif gh api "repos/$REPO/collaborators/$BOT_USER" >/dev/null 2>&1; then
      echo "  Collaborator: already present"
    elif gh api "repos/$REPO/collaborators/$BOT_USER" --method PUT -f permission="$BOT_PERMISSION" \
        > /dev/null 2>&1; then
      echo "  Collaborator: invited"
    else
      echo "  Collaborator: FAILED"
    fi
  fi

  # Pace API calls to stay within GitHub rate limits (max ~5000/hour).
  # 1-second sleep between repos keeps a 300-repo run well under the cap.
  sleep 1
done

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — repo-setup-cron finished"
