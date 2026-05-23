#!/usr/bin/env bash
# preuse-supply-chain-gate.sh — Claude Code PreToolUse hook.
#
# Reads a JSON tool-call payload on stdin. For Bash tool calls, blocks
# install verbs that would fetch arbitrary packages from public registries
# unless they're routed through the supply-chain-safe wrapper (socket / npm-safe-install)
# or explicitly overridden with SAFE_INSTALL_OVERRIDE=1.
#
# Exit codes (Claude Code contract):
#   0 = allow
#   2 = block, surface stderr back to the model so it self-corrects
#
# The deny list in settings.json is a coarse first filter ("ask" before this hook runs).
# This hook is the smart filter: it understands command structure and lets through:
#   - npm run / npm test / npm exec --offline
#   - npm install --offline / --prefer-offline (still uses lockfile, no fresh fetch)
#   - npm ci  (lockfile-only, no new resolution)
#   - uv sync (lockfile-only)
#   - pip install -r requirements.txt --no-deps   (with deliberate flag)
#   - any command prefixed by `socket ` or `npm-safe-install`
#   - any command with env SAFE_INSTALL_OVERRIDE=1
#
# It blocks (with explanation):
#   npm install <pkg>, npm i <pkg>, npm add, npx <untrusted>, pnpm add/install,
#   yarn add, pip install <pkg>, pipx install, uv add, uv pip install,
#   cargo install, gem install, go install <url>

set -u

input=$(cat)

# Only gate Bash calls — let everything else pass.
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" != "Bash" ] && exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Allow override via env var. The model can request this in its tool input but it
# will be visible in the transcript — by design.
case "$cmd" in
    *SAFE_INSTALL_OVERRIDE=1*) exit 0 ;;
    socket\ *|*\ socket\ *) exit 0 ;;
    npm-safe-install*|*npm-safe-install*) exit 0 ;;
esac

# Lockfile-only / offline-friendly commands are fine — no fresh fetch.
case "$cmd" in
    *"npm ci"*|*"npm i --offline"*|*"npm install --offline"*|*"npm install --prefer-offline"*|*"npm i --prefer-offline"*) exit 0 ;;
    *"pnpm install --frozen-lockfile"*|*"yarn install --frozen-lockfile"*) exit 0 ;;
    *"uv sync"*|*"poetry install"*|*"pipenv install --deploy"*) exit 0 ;;
    *"pip install --no-deps"*) exit 0 ;;
esac

# Pattern set for unsafe installs. Boundary-anchored to avoid matching inside strings.
# We accept word boundaries before the verb (start, ;, &&, ||, |, $(, `, newline, space).
unsafe='(^|[[:space:];&|`(])(npm[[:space:]]+(install|i|add|create)(\b|[[:space:]])|npm[[:space:]]+exec[[:space:]]|npx[[:space:]]+[^-]|pnpm[[:space:]]+(add|install)(\b|[[:space:]])|yarn[[:space:]]+add(\b|[[:space:]])|pip[[:space:]]+install(\b|[[:space:]])|pipx[[:space:]]+install(\b|[[:space:]])|uv[[:space:]]+add(\b|[[:space:]])|uv[[:space:]]+pip[[:space:]]+install(\b|[[:space:]])|cargo[[:space:]]+install(\b|[[:space:]])|gem[[:space:]]+install(\b|[[:space:]])|go[[:space:]]+install[[:space:]]+[a-zA-Z])'

if [[ "$cmd" =~ $unsafe ]]; then
    cat >&2 <<EOF
🛡️  Supply-chain gate: direct package install blocked.

  Command: $cmd

Use one of these instead:
  socket npm install <pkg>            # malware/typosquat scan via socket.dev
  npm-safe-install <pkg>              # install version released ≥7 days ago
  npm ci                              # lockfile-only, no fresh resolution
  npm install --offline               # use cache only

For pip/uv:
  socket pip install <pkg>
  uv sync                             # lockfile-only

If this is a known-safe installation (internal package, lockfile sync, etc),
prefix the command with:  SAFE_INSTALL_OVERRIDE=1

Policy: CrossCheck/docs/rules/trust-model.md § Supply Chain
EOF
    exit 2
fi

exit 0
