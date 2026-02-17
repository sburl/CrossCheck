#!/bin/bash
# scan-secrets.sh - Deterministic secret scanner for repos and agent logs
# Part of /security-review skill. Can also run standalone.
#
# Usage:
#   ./scan-secrets.sh              # Scan repo working tree
#   ./scan-secrets.sh --history    # Also scan git history
#   ./scan-secrets.sh --logs       # Also scan agent conversation logs
#   ./scan-secrets.sh --all        # Everything
#   ./scan-secrets.sh --soft-fail   # Exit 0 even if secrets found

set -e

SCAN_HISTORY=false
SCAN_LOGS=false
SOFT_FAIL=false

for arg in "$@"; do
    case $arg in
        --history) SCAN_HISTORY=true ;;
        --logs) SCAN_LOGS=true ;;
        --all) SCAN_HISTORY=true; SCAN_LOGS=true ;;
        --soft-fail) SOFT_FAIL=true ;;
    esac
done

# Provider-specific patterns (high confidence, never false positives)
PATTERNS=(
    'sk-proj-[A-Za-z0-9_-]{20,}'           # OpenAI
    'sk-ant-[A-Za-z0-9_-]{20,}'            # Anthropic
    'AIza[A-Za-z0-9_-]{35}'                # Google/Gemini
    'AKIA[A-Z0-9]{16}'                     # AWS Access Key
    'ghp_[A-Za-z0-9]{36}'                  # GitHub PAT
    'gho_[A-Za-z0-9]{36}'                  # GitHub OAuth
    'ghu_[A-Za-z0-9]{36}'                  # GitHub App User
    'ghs_[A-Za-z0-9]{36}'                  # GitHub App Install
    'github_pat_[A-Za-z0-9_]{22,}'         # GitHub Fine-Grained PAT
    'sk_live_[A-Za-z0-9]{24,}'             # Stripe Live Secret
    'pk_live_[A-Za-z0-9]{24,}'             # Stripe Live Publishable
    'xoxb-[0-9]{10,}-[A-Za-z0-9]{24}'      # Slack Bot Token
    'xoxp-[0-9]{10,}-[0-9]{10,}'           # Slack User Token
    'SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}'  # SendGrid
    'sk-[a-zA-Z0-9]{32,}'                  # Generic OpenAI-style
)

# Build combined regex
COMBINED=$(IFS='|'; echo "${PATTERNS[*]}")

# Known false-positive tokens: documentation examples, placeholder keys
# These appear in security-review.md, test files, and conversation logs
# Uses exact token matching (not substring) to avoid suppressing real secrets
KNOWN_FPS=(
    AKIAIOSFODNN7EXAMPLE    # AWS official example key ID
    sk-proj-abcdef          # doc placeholder
    sk-proj-abc123          # doc placeholder
    sk-proj-test            # doc placeholder
    sk-proj-xxxx            # doc placeholder
    sk-ant-xxxx             # doc placeholder
    sk_live_xxxx            # doc placeholder
    ghp_xxxx                # doc placeholder
)

# Filter false positives by extracting matched tokens and checking exact match.
# Unlike substring grep -v, this won't suppress "sk-proj-test-real-prod-key-abc"
# just because it contains "sk-proj-test".
filter_false_positives() {
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # Extract actual matched tokens from this line
        local tokens
        tokens=$(echo "$line" | grep -oE "$COMBINED" 2>/dev/null || true)
        if [ -z "$tokens" ]; then
            echo "$line"
            continue
        fi
        local has_real=false
        while IFS= read -r token; do
            local is_fp=false
            for fp in "${KNOWN_FPS[@]}"; do
                if [ "$token" = "$fp" ]; then
                    is_fp=true
                    break
                fi
            done
            if [ "$is_fp" = false ]; then
                has_real=true
                break
            fi
        done <<< "$tokens"
        if [ "$has_real" = true ]; then
            echo "$line"
        fi
    done
}

FOUND=0

echo "🔒 Secret Scanner"
echo "━━━━━━━━━━━━━━━━━━"
echo ""

# --- Section 1: Working tree ---
echo "📁 Scanning working tree..."
if command -v rg >/dev/null 2>&1; then
    # Use ripgrep if available (much faster)
    # Exclude specific scanner/doc files to avoid self-referential false positives
    # Use anchored paths (not broad substrings) so real secrets in similarly-named files are caught
    matches=$(rg -n --no-heading -g '!.git' -g '!node_modules' -g '!*.lock' -g '!*.min.js' \
        -g '!skill-sources/security-review.md' -g '!scripts/scan-secrets.sh' -g '!scripts/test-hook-behavior.sh' \
        "$COMBINED" . 2>/dev/null || true)
else
    matches=$(grep -rn --include='*.py' --include='*.js' --include='*.ts' --include='*.tsx' \
        --include='*.jsx' --include='*.go' --include='*.rs' --include='*.java' \
        --include='*.yml' --include='*.yaml' --include='*.json' --include='*.toml' \
        --include='*.env*' --include='*.md' --include='*.sh' \
        -E "$COMBINED" . 2>/dev/null | grep -v '.git/' \
        | grep -Fv './skill-sources/security-review.md' \
        | grep -Fv './scripts/scan-secrets.sh' \
        | grep -Fv './scripts/test-hook-behavior.sh' || true)
fi

# Filter known false positives from working tree results
if [ -n "$matches" ]; then
    matches=$(echo "$matches" | filter_false_positives)
fi

if [ -n "$matches" ]; then
    echo "  ❌ SECRETS FOUND in working tree:"
    # Print file:line but mask the actual secret value
    while IFS= read -r line; do
        file_line=$(echo "$line" | cut -d: -f1-2)
        echo "     $file_line: [REDACTED - matches provider key pattern]"
        FOUND=$((FOUND + 1))
    done <<< "$matches"
    echo ""
else
    echo "  ✅ Working tree clean"
fi

# --- Section 2: Tracked files that shouldn't be ---
echo ""
echo "📋 Checking for sensitive tracked files..."
sensitive_files=$(git ls-files 2>/dev/null | grep -iE '\.env$|\.env\.|\.pem$|\.key$|id_rsa|\.p12$|\.pfx$|credentials\.json|service.account.*\.json|\.sqlite$|\.db$' || true)
if [ -n "$sensitive_files" ]; then
    echo "  ❌ Sensitive files tracked by git:"
    echo "$sensitive_files" | sed 's/^/     /'
    FOUND=$((FOUND + $(echo "$sensitive_files" | wc -l)))
    echo ""
else
    echo "  ✅ No sensitive files tracked"
fi

# --- Section 3: Git history ---
if [ "$SCAN_HISTORY" = true ]; then
    echo ""
    echo "📜 Scanning git history (this may take a moment)..."
    history_matches=""
    for pattern in "sk-proj-" "sk-ant-" "AKIA" "ghp_" "sk_live_" "AIza"; do
        # Exclude security-review.md from history results (contains example patterns)
        found=$(git log --all -p -S "$pattern" --diff-filter=D --oneline -- ':!skill-sources/security-review.md' ':!commands/security-review.md' ':!scripts/scan-secrets.sh' 2>/dev/null | head -5 || true)
        if [ -n "$found" ]; then
            history_matches="$history_matches\n  Pattern '$pattern' found in deleted history:\n$found"
        fi
    done

    env_history=$(git log --all --diff-filter=A --oneline -- '*.env' '.env.*' '*.pem' '*.key' 'id_rsa' 2>/dev/null || true)
    if [ -n "$env_history" ]; then
        history_matches="$history_matches\n  Sensitive files previously committed:\n$env_history"
    fi

    if [ -n "$history_matches" ]; then
        echo "  ⚠️   Secrets found in git history:"
        echo -e "$history_matches" | sed 's/^/     /'
        echo ""
        echo "  ⚠️   These secrets may still be exposed even though they were deleted."
        echo "     Rotate these credentials immediately."
        FOUND=$((FOUND + 1))
    else
        echo "  ✅ Git history clean"
    fi
fi

# --- Section 4: Agent conversation logs ---
if [ "$SCAN_LOGS" = true ]; then
    echo ""
    echo "🤖 Scanning agent conversation logs..."

    log_matches=""

    # Claude Code conversation logs
    CLAUDE_PROJECTS="$HOME/.claude/projects"
    if [ -d "$CLAUDE_PROJECTS" ]; then
        claude_hits=$(grep -rl -E "$COMBINED" "$CLAUDE_PROJECTS" 2>/dev/null | head -20 || true)
        if [ -n "$claude_hits" ]; then
            verified_hits=""
            while IFS= read -r f; do
                # Re-check each file: filter out known false positives
                # (documentation examples, placeholder keys loaded into conversation context)
                real=$(grep -E "$COMBINED" "$f" 2>/dev/null | filter_false_positives || true)
                if [ -n "$real" ]; then
                    verified_hits="${verified_hits}${f}
"
                fi
            done <<< "$claude_hits"
            if [ -n "$verified_hits" ]; then
                log_matches="$log_matches\n  Claude conversation logs with secrets:"
                while IFS= read -r f; do
                    [ -z "$f" ] && continue
                    log_matches="$log_matches\n     $f"
                done <<< "$verified_hits"
            fi
        fi
    fi

    # Codex review log
    CODEX_LOG="$HOME/.claude/codex-commit-reviews.log"
    if [ -f "$CODEX_LOG" ]; then
        if grep -qE "$COMBINED" "$CODEX_LOG" 2>/dev/null; then
            log_matches="$log_matches\n  Codex review log contains secrets: $CODEX_LOG"
        fi
    fi

    # Temp files from Codex debugging
    for tmpfile in /tmp/question.txt /tmp/reply.txt; do
        if [ -f "$tmpfile" ] && grep -qE "$COMBINED" "$tmpfile" 2>/dev/null; then
            log_matches="$log_matches\n  Codex temp file contains secrets: $tmpfile"
        fi
    done

    if [ -n "$log_matches" ]; then
        echo "  🚨 CRITICAL: Secrets found in agent logs!"
        echo -e "$log_matches"
        echo ""
        echo "  ⚠️   ACTION REQUIRED:"
        echo "     1. Rotate ALL affected credentials immediately"
        echo "     2. These secrets were sent to AI provider APIs"
        echo "     3. They are stored in plaintext on your disk"
        echo "     4. Delete affected .jsonl files after rotation"
        echo "     5. Add sensitive paths to ~/.claude/settings.json deny list"
        FOUND=$((FOUND + 1))
    else
        echo "  ✅ Agent logs clean"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━"
echo "🔒 Scan complete"
if [ "$SOFT_FAIL" = false ] && [ "$FOUND" -gt 0 ]; then
    exit 1
fi
