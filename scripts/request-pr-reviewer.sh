#!/usr/bin/env bash
# Request a PR review from a mapped human reviewer when operating as a bot account
# Usage:
#   scripts/request-pr-reviewer.sh --pr 123

set -euo pipefail

PR_NUMBER="${CROSSCHECK_PR_NUMBER:-}"
REPO="${CROSSCHECK_REPO:-}"
OPERATING_ACTOR="${CROSSCHECK_BOT_ACTOR:-}"
HUMAN_REVIEWER="${CROSSCHECK_BOT_HUMAN_REVIEWER:-}"
FORCE_REQUEST="${CROSSCHECK_FORCE_REVIEW_REQUEST:-false}"

usage() {
  cat <<'EOF'
Usage:
  request-pr-reviewer.sh --pr <number>

Options:
  --pr <number>          PR number to update (optional if current branch has an open PR)
  --repo <owner/repo>     GitHub repo (optional, inferred from origin)
  --actor <username>      Operating GitHub username (defaults to `gh api user`)
  --reviewer <username>   Explicit reviewer to request (defaults to mapped bot user)
  --force                 Request reviewer even if actor does not match bot pattern
  --help                  Show this help

Environment:
  CROSSCHECK_PR_NUMBER           PR number
  CROSSCHECK_REPO                owner/repo
  CROSSCHECK_BOT_ACTOR           actor login to evaluate
  CROSSCHECK_BOT_HUMAN_REVIEWER   mapped human reviewer
                                  supports user-bot, user_bot, user[bot]
  CROSSCHECK_FORCE_REVIEW_REQUEST set to 1/true/yes to force request
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr|--pr-number)
      PR_NUMBER="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --actor)
      OPERATING_ACTOR="${2:-}"
      shift 2
      ;;
    --reviewer)
      HUMAN_REVIEWER="${2:-}"
      shift 2
      ;;
    --force)
      FORCE_REQUEST="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

for cmd in gh sed; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

if [ -z "$REPO" ]; then
  REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
  if [ -n "$REPO_URL" ]; then
    REPO=$(echo "$REPO_URL" | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#' | sed 's/\.git$//')
  fi
fi

if [ -z "$REPO" ]; then
  echo "❌ Could not determine repository. Set --repo or run inside repo with origin URL." >&2
  exit 1
fi

if [ -z "$OPERATING_ACTOR" ]; then
  OPERATING_ACTOR="$(gh api user --jq '.login' 2>/dev/null || true)"
fi

if [ -z "$OPERATING_ACTOR" ]; then
  echo "❌ Could not determine operating GitHub user. Set --actor and retry." >&2
  exit 1
fi

if [ -z "$PR_NUMBER" ]; then
  BRANCH=$(git branch --show-current 2>/dev/null || true)
  if [ -z "$BRANCH" ]; then
    echo "❌ Could not infer PR number from current branch. Use --pr." >&2
    exit 1
  fi

  PR_NUMBER="$(gh pr list --repo "$REPO" --head "$BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)"
fi

if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ]; then
  echo "❌ No open PR found for current branch '$BRANCH'. Use --pr." >&2
  exit 1
fi

if [ -z "$HUMAN_REVIEWER" ]; then
  case "$OPERATING_ACTOR" in
    *-bot) HUMAN_REVIEWER="${OPERATING_ACTOR%-bot}" ;;
    *_bot) HUMAN_REVIEWER="${OPERATING_ACTOR%_bot}" ;;
    *\[bot\]) HUMAN_REVIEWER="${OPERATING_ACTOR%\[bot\]}" ;;
  esac
fi

if [ -z "$HUMAN_REVIEWER" ] && [ "$FORCE_REQUEST" != "true" ] && [ "$FORCE_REQUEST" != "1" ] && [ "$FORCE_REQUEST" != "yes" ]; then
  echo "ℹ️ Operating account '$OPERATING_ACTOR' is not a bot account and no explicit --reviewer was provided."
  echo "   Set --reviewer / CROSSCHECK_BOT_HUMAN_REVIEWER or pass --force to request anyway."
  exit 0
fi

if [ -z "$HUMAN_REVIEWER" ]; then
  echo "❌ No mapped human reviewer found. Set --reviewer / CROSSCHECK_BOT_HUMAN_REVIEWER." >&2
  exit 1
fi

if [ "$HUMAN_REVIEWER" = "$OPERATING_ACTOR" ]; then
  echo "ℹ️ Reviewer '$HUMAN_REVIEWER' is the same as acting account, skipping."
  exit 0
fi

if gh pr edit "$PR_NUMBER" --repo "$REPO" --add-reviewer "$HUMAN_REVIEWER"; then
  echo "✅ Requested review for PR #$PR_NUMBER from '$HUMAN_REVIEWER' on $REPO"
  exit 0
fi

echo "⚠️  Review request could not be added right now. Verify reviewer exists and has repo access."
exit 1
