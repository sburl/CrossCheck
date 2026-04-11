#!/bin/bash
# scan-supply-chain.sh - Multi-ecosystem supply chain security scanner
# Part of /security-review skill. Can also run standalone.
#
# Usage:
#   ./scan-supply-chain.sh              # Full scan (all checks)
#   ./scan-supply-chain.sh --pre-commit # Fast: blocklist + version pinning only
#   ./scan-supply-chain.sh --pre-push   # Full: + age quarantine + lock files
#   ./scan-supply-chain.sh --soft-fail  # Exit 0 even if issues found
#
# Exit codes: 0=clean, 1=warnings, 2=malicious package, 3=quarantine violation
#
# Environment:
#   SUPPLY_CHAIN_SKIP_AGE=1          Skip age quarantine check
#   SUPPLY_CHAIN_QUARANTINE_DAYS=N   Override quarantine period (default: 7)

# No set -e: this script uses many grep/sed operations that return non-zero
# on no-match. Exit codes are tracked explicitly via WORST_EXIT.

# --- Argument parsing ---
MODE="standalone"
SOFT_FAIL=false

for arg in "$@"; do
    case $arg in
        --pre-commit) MODE="pre-commit" ;;
        --pre-push)   MODE="pre-push" ;;
        --soft-fail)  SOFT_FAIL=true ;;
    esac
done

QUARANTINE_DAYS="${SUPPLY_CHAIN_QUARANTINE_DAYS:-7}"
CACHE_DIR="$HOME/.cache/CrossCheck/supply-chain-age"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BLOCKLIST_FILE="$SCRIPT_DIR/supply-chain-blocklist.txt"

# Track worst exit code: 0=clean, 1=warnings, 2=malicious, 3=quarantine
WORST_EXIT=0
update_exit() {
    local code="$1"
    if [ "$code" -gt "$WORST_EXIT" ]; then
        WORST_EXIT="$code"
    fi
}

# --- Ecosystem detection ---
ECOSYSTEMS=()

detect_ecosystems() {
    [ -f "package.json" ] && ECOSYSTEMS+=("npm") || true
    if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
        ECOSYSTEMS+=("pip")
    fi
    [ -f "Gemfile" ] && ECOSYSTEMS+=("gem") || true
    [ -f "go.mod" ] && ECOSYSTEMS+=("go") || true
    [ -f "Cargo.toml" ] && ECOSYSTEMS+=("cargo") || true
    [ -f "composer.json" ] && ECOSYSTEMS+=("composer") || true
}

detect_ecosystems

if [ ${#ECOSYSTEMS[@]} -eq 0 ]; then
    # No package ecosystems detected — nothing to scan
    exit 0
fi

echo "  📦 Supply Chain Scanner"
echo "     Ecosystems: ${ECOSYSTEMS[*]}"

# --- Cross-platform date parsing ---
# Converts ISO 8601 date string to epoch seconds
parse_iso_date() {
    local datestr="$1"
    # Strip milliseconds and trailing Z for portability
    datestr="${datestr%%.*}"
    datestr="${datestr%%Z}"
    # macOS (BSD date)
    if date -jf "%Y-%m-%dT%H:%M:%S" "$datestr" +%s 2>/dev/null; then
        return
    fi
    # Linux (GNU date)
    date -d "${datestr}" +%s 2>/dev/null || echo "0"
}

# --- Helper: extract deps from package.json without jq ---
# Outputs lines like: packagename "^1.2.3"
npm_deps_grep() {
    local file="$1"
    # Extract dependencies and devDependencies blocks, then grab "name": "version" pairs
    # One-pass sed to extract name and version
    sed -n -E '/"(dependencies|devDependencies)"/,/}/ s/^[[:space:]]*"([^"]+)"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1 \2/p' "$file" 2>/dev/null || true
}

# ============================================================
# CHECK 1: Version Pinning
# ============================================================
check_version_pinning() {
    local found_unpinned=false

    echo ""
    echo "     📌 Checking version pinning..."

    for eco in "${ECOSYSTEMS[@]}"; do
        case "$eco" in
            npm)
                if [ -f "package.json" ]; then
                    local unpinned=""
                    if command -v jq >/dev/null 2>&1; then
                        unpinned=$(jq -r '
                            [(.dependencies // {}), (.devDependencies // {})]
                            | add // {}
                            | to_entries[]
                            | select(.value | test("^[\\^~]"))
                            | "        \(.key): \(.value)"
                        ' package.json 2>/dev/null || true)
                    else
                        unpinned=$(npm_deps_grep "package.json" \
                            | grep -E '"[\^~]' \
                            | sed 's/^/        /' || true)
                    fi
                    if [ -n "$unpinned" ]; then
                        echo "        ⚠️  npm: unpinned versions in package.json:"
                        echo "$unpinned"
                        echo "        Fix: Add save-exact=true to .npmrc"
                        found_unpinned=true
                    fi
                    # Check .npmrc for save-exact
                    if [ -f ".npmrc" ]; then
                        if ! grep -q "save-exact=true" .npmrc 2>/dev/null; then
                            echo "        ⚠️  npm: .npmrc exists but missing save-exact=true"
                            found_unpinned=true
                        fi
                    else
                        echo "        ⚠️  npm: no .npmrc — add save-exact=true to pin future installs"
                        found_unpinned=true
                    fi
                fi
                ;;
            pip)
                # requirements.txt: flag lines without == pinning
                if [ -f "requirements.txt" ]; then
                    local unpinned_pip
                    unpinned_pip=$(grep -nE '^[a-zA-Z]' requirements.txt \
                        | grep -vE '==' \
                        | grep -vE '^\s*#' \
                        | sed 's/^/        /' || true)
                    if [ -n "$unpinned_pip" ]; then
                        echo "        ⚠️  pip: unpinned versions in requirements.txt:"
                        echo "$unpinned_pip"
                        echo "        Fix: Use == for exact pinning (e.g., requests==2.31.0)"
                        found_unpinned=true
                    fi
                fi
                # pyproject.toml: flag >= ~= ^ ranges in dependencies
                if [ -f "pyproject.toml" ]; then
                    local unpinned_pyp
                    unpinned_pyp=$(sed -n '/\[project\]/,/^\[/p; /\[tool\.poetry\.dependencies\]/,/^\[/p' pyproject.toml 2>/dev/null \
                        | grep -E '(>=|~=|\^|>)' \
                        | grep -vE '^\s*#' \
                        | grep -vE 'requires-python' \
                        | sed 's/^/        /' || true)
                    if [ -n "$unpinned_pyp" ]; then
                        echo "        ⚠️  pip: unpinned versions in pyproject.toml:"
                        echo "$unpinned_pyp"
                        found_unpinned=true
                    fi
                fi
                ;;
            gem)
                if [ -f "Gemfile" ]; then
                    # Flag gems with ~> (pessimistic) or no version constraint
                    local unpinned_gem
                    unpinned_gem=$(grep -nE "^\s*gem\s+" Gemfile \
                        | grep -E "(~>|>=|>)" \
                        | grep -vE '^\s*#' \
                        | sed 's/^/        /' || true)
                    local no_version_gem
                    no_version_gem=$(grep -nE "^\s*gem\s+['\"][^'\"]+['\"]\\s*$" Gemfile \
                        | grep -vE '^\s*#' \
                        | sed 's/^/        /' || true)
                    if [ -n "$unpinned_gem" ] || [ -n "$no_version_gem" ]; then
                        echo "        ⚠️  gem: unpinned versions in Gemfile:"
                        [ -n "$unpinned_gem" ] && echo "$unpinned_gem"
                        [ -n "$no_version_gem" ] && echo "$no_version_gem" && echo "        (gems with no version constraint)"
                        found_unpinned=true
                    fi
                fi
                ;;
            cargo)
                if [ -f "Cargo.toml" ]; then
                    local unpinned_cargo
                    unpinned_cargo=$(sed -n '/\[dependencies\]/,/^\[/p; /\[dev-dependencies\]/,/^\[/p' Cargo.toml 2>/dev/null \
                        | grep -E '=\s*"[\^~]' \
                        | sed 's/^/        /' || true)
                    if [ -n "$unpinned_cargo" ]; then
                        echo "        ⚠️  cargo: unpinned versions in Cargo.toml:"
                        echo "$unpinned_cargo"
                        found_unpinned=true
                    fi
                fi
                ;;
            composer)
                if [ -f "composer.json" ]; then
                    local unpinned_comp=""
                    if command -v jq >/dev/null 2>&1; then
                        unpinned_comp=$(jq -r '
                            [(.require // {}), (."require-dev" // {})]
                            | add // {}
                            | to_entries[]
                            | select(.value | test("^[\\^~]"))
                            | "        \(.key): \(.value)"
                        ' composer.json 2>/dev/null || true)
                    else
                        unpinned_comp=$(grep -E '"[\^~]' composer.json \
                            | grep -vE '"(require|require-dev)"' \
                            | sed 's/^/        /' || true)
                    fi
                    if [ -n "$unpinned_comp" ]; then
                        echo "        ⚠️  composer: unpinned versions in composer.json:"
                        echo "$unpinned_comp"
                        found_unpinned=true
                    fi
                fi
                ;;
            go)
                # Go modules enforce exact versions by design — no check needed
                ;;
        esac
    done

    if [ "$found_unpinned" = true ]; then
        update_exit 1
    else
        echo "        ✅ All detected dependencies use pinned versions"
    fi
}

# ============================================================
# CHECK 2: Blocklist Scan
# ============================================================
check_blocklist() {
    echo ""
    echo "     🚫 Checking against known malicious packages..."

    if [ ! -f "$BLOCKLIST_FILE" ]; then
        echo "        ⚠️  Blocklist not found at $BLOCKLIST_FILE"
        return
    fi

    local found_malicious=false

    # Manifest and lock files to scan per ecosystem
    local files_to_scan=()
    for eco in "${ECOSYSTEMS[@]}"; do
        case "$eco" in
            npm)
                [ -f "package.json" ] && files_to_scan+=("npm:package.json")
                [ -f "package-lock.json" ] && files_to_scan+=("npm:package-lock.json")
                [ -f "yarn.lock" ] && files_to_scan+=("npm:yarn.lock")
                [ -f "pnpm-lock.yaml" ] && files_to_scan+=("npm:pnpm-lock.yaml")
                ;;
            pip)
                [ -f "requirements.txt" ] && files_to_scan+=("pip:requirements.txt")
                [ -f "pyproject.toml" ] && files_to_scan+=("pip:pyproject.toml")
                [ -f "Pipfile" ] && files_to_scan+=("pip:Pipfile")
                [ -f "Pipfile.lock" ] && files_to_scan+=("pip:Pipfile.lock")
                [ -f "poetry.lock" ] && files_to_scan+=("pip:poetry.lock")
                [ -f "uv.lock" ] && files_to_scan+=("pip:uv.lock")
                ;;
            gem)
                [ -f "Gemfile" ] && files_to_scan+=("gem:Gemfile")
                [ -f "Gemfile.lock" ] && files_to_scan+=("gem:Gemfile.lock")
                ;;
            go)
                [ -f "go.mod" ] && files_to_scan+=("go:go.mod")
                [ -f "go.sum" ] && files_to_scan+=("go:go.sum")
                ;;
            cargo)
                [ -f "Cargo.toml" ] && files_to_scan+=("cargo:Cargo.toml")
                [ -f "Cargo.lock" ] && files_to_scan+=("cargo:Cargo.lock")
                ;;
            composer)
                [ -f "composer.json" ] && files_to_scan+=("composer:composer.json")
                [ -f "composer.lock" ] && files_to_scan+=("composer:composer.lock")
                ;;
        esac
    done

    # Load blocklist entries (strip comments, blank lines, trailing whitespace)
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Parse ecosystem:package
        local entry
        entry=$(echo "$line" | awk '{print $1}')
        local eco_prefix="${entry%%:*}"
        local pkg_name="${entry#*:}"

        # Check each relevant file
        for scan_entry in "${files_to_scan[@]}"; do
            local file_eco="${scan_entry%%:*}"
            local file_path="${scan_entry#*:}"

            # Only check files matching the blocklist entry's ecosystem
            if [ "$file_eco" = "$eco_prefix" ]; then
                # Word-boundary match to avoid substring false positives
                # (e.g., "ctx" must not match "ctxlib" or "my-context")
                if grep -qE "(^|[^a-zA-Z0-9_-])${pkg_name}([^a-zA-Z0-9_-]|$)" "$file_path" 2>/dev/null; then
                    local reason
                    reason=$(echo "$line" | sed 's/^[^#]*#//' | sed 's/^[[:space:]]*//')
                    echo "        ❌ MALICIOUS PACKAGE: $pkg_name found in $file_path"
                    [ -n "$reason" ] && echo "           Reason: $reason"
                    echo "           Remove immediately and rotate all credentials"
                    found_malicious=true
                fi
            fi
        done
    done < "$BLOCKLIST_FILE"

    if [ "$found_malicious" = true ]; then
        update_exit 2
    else
        echo "        ✅ No known malicious packages detected"
    fi
}

# ============================================================
# CHECK 3: Lock File Enforcement
# ============================================================
check_lock_files() {
    echo ""
    echo "     🔒 Checking lock file integrity..."

    local missing_lock=false

    for eco in "${ECOSYSTEMS[@]}"; do
        case "$eco" in
            npm)
                if [ -f "package.json" ]; then
                    if [ ! -f "package-lock.json" ] && [ ! -f "yarn.lock" ] && [ ! -f "pnpm-lock.yaml" ]; then
                        echo "        ⚠️  npm: package.json exists but no lock file found"
                        echo "           Run: npm install to generate package-lock.json"
                        missing_lock=true
                    fi
                fi
                ;;
            pip)
                if [ -f "pyproject.toml" ]; then
                    if [ ! -f "poetry.lock" ] && [ ! -f "uv.lock" ] && [ ! -f "pdm.lock" ] && [ ! -f "requirements.lock" ]; then
                        echo "        ⚠️  pip: pyproject.toml exists but no lock file found"
                        echo "           Consider using poetry.lock, uv.lock, or pip-compile"
                        missing_lock=true
                    fi
                fi
                ;;
            gem)
                if [ -f "Gemfile" ] && [ ! -f "Gemfile.lock" ]; then
                    echo "        ⚠️  gem: Gemfile exists but Gemfile.lock not found"
                    echo "           Run: bundle install to generate Gemfile.lock"
                    missing_lock=true
                fi
                ;;
            go)
                if [ -f "go.mod" ] && [ ! -f "go.sum" ]; then
                    echo "        ⚠️  go: go.mod exists but go.sum not found"
                    echo "           Run: go mod tidy"
                    missing_lock=true
                fi
                ;;
            cargo)
                if [ -f "Cargo.toml" ] && [ ! -f "Cargo.lock" ]; then
                    echo "        ⚠️  cargo: Cargo.toml exists but Cargo.lock not found"
                    echo "           Run: cargo generate-lockfile"
                    missing_lock=true
                fi
                ;;
            composer)
                if [ -f "composer.json" ] && [ ! -f "composer.lock" ]; then
                    echo "        ⚠️  composer: composer.json exists but composer.lock not found"
                    echo "           Run: composer install to generate composer.lock"
                    missing_lock=true
                fi
                ;;
        esac
    done

    if [ "$missing_lock" = true ]; then
        update_exit 1
    else
        echo "        ✅ Lock files present for all ecosystems"
    fi
}

# ============================================================
# CHECK 4: Age Quarantine
# ============================================================
check_age_quarantine() {
    if [ "${SUPPLY_CHAIN_SKIP_AGE:-0}" = "1" ]; then
        echo ""
        echo "     🕐 Age quarantine: skipped (SUPPLY_CHAIN_SKIP_AGE=1)"
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo ""
        echo "     ⚠️  Age quarantine: skipped (curl not available)"
        return
    fi

    # Quick connectivity check
    if ! curl -s --max-time 3 -o /dev/null "https://registry.npmjs.org" 2>/dev/null; then
        echo ""
        echo "     ⚠️  Age quarantine: skipped (offline or registry unreachable)"
        return
    fi

    echo ""
    echo "     🕐 Checking package publish age (${QUARANTINE_DAYS}-day quarantine)..."

    mkdir -p "$CACHE_DIR"
    local now
    now=$(date +%s)
    local found_too_new=false

    for eco in "${ECOSYSTEMS[@]}"; do
        case "$eco" in
            npm)
                [ ! -f "package.json" ] && continue
                local deps=""
                if command -v jq >/dev/null 2>&1; then
                    deps=$(jq -r '(.dependencies // {}) | to_entries[] | "\(.key) \(.value)"' package.json 2>/dev/null || true)
                else
                    deps=$(npm_deps_grep "package.json" \
                        | sed 's/[",]//g; s/^\s*//' \
                        | awk -F: '{gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); print $1, $2}' \
                        || true)
                fi
                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    local pkg ver
                    pkg=$(echo "$line" | awk '{print $1}')
                    ver=$(echo "$line" | awk '{print $2}')
                    # Strip range prefixes to get actual installed version
                    ver="${ver#^}"
                    ver="${ver#~}"
                    ver="${ver#>=}"
                    ver="${ver#=}"
                    [ -z "$pkg" ] || [ -z "$ver" ] && continue

                    check_package_age "npm" "$pkg" "$ver"
                done <<< "$deps"
                ;;
            pip)
                if [ -f "requirements.txt" ]; then
                    while IFS= read -r line; do
                        [[ "$line" =~ ^[[:space:]]*# ]] && continue
                        [ -z "$line" ] && continue
                        local pkg ver
                        # Parse: package==version
                        if [[ "$line" =~ ^([a-zA-Z0-9._-]+)==([0-9][a-zA-Z0-9._-]*) ]]; then
                            pkg="${BASH_REMATCH[1]}"
                            ver="${BASH_REMATCH[2]}"
                            check_package_age "pip" "$pkg" "$ver"
                        fi
                    done < requirements.txt
                fi
                ;;
            gem)
                if [ -f "Gemfile.lock" ]; then
                    # Extract pinned gems from Gemfile.lock specs section
                    local gems
                    gems=$(sed -n '/^  specs:/,/^[^ ]/p' Gemfile.lock 2>/dev/null \
                        | grep -E '^\s{4}[a-zA-Z]' \
                        | sed 's/^\s*//' \
                        | awk '{gsub(/[()]/, "", $2); print $1, $2}' || true)
                    while IFS= read -r line; do
                        [ -z "$line" ] && continue
                        local pkg ver
                        pkg=$(echo "$line" | awk '{print $1}')
                        ver=$(echo "$line" | awk '{print $2}')
                        [ -z "$pkg" ] || [ -z "$ver" ] && continue
                        check_package_age "gem" "$pkg" "$ver"
                    done <<< "$gems"
                fi
                ;;
        esac
    done

    if [ "$found_too_new" = true ]; then
        echo "        Override: SUPPLY_CHAIN_SKIP_AGE=1 git push"
        update_exit 3
    fi
}

# Check a single package's publish age against the quarantine period
check_package_age() {
    local eco="$1" pkg="$2" ver="$3"

    # Check cache first
    local cache_file="$CACHE_DIR/${eco}/${pkg}@${ver}.age"
    mkdir -p "$CACHE_DIR/${eco}"

    if [ -f "$cache_file" ]; then
        # Cache valid for 24 hours
        local cache_age
        if stat -f %m "$cache_file" >/dev/null 2>&1; then
            # macOS
            cache_age=$(( now - $(stat -f %m "$cache_file") ))
        else
            # Linux
            cache_age=$(( now - $(stat -c %Y "$cache_file") ))
        fi
        if [ "$cache_age" -lt 86400 ]; then
            local cached_ts
            cached_ts=$(cat "$cache_file")
            evaluate_age "$eco" "$pkg" "$ver" "$cached_ts"
            return
        fi
    fi

    # Query registry
    local publish_time=""
    case "$eco" in
        npm)
            local response
            response=$(curl -s --max-time 5 "https://registry.npmjs.org/${pkg}" 2>/dev/null || true)
            if [ -n "$response" ]; then
                if command -v jq >/dev/null 2>&1; then
                    publish_time=$(echo "$response" | jq -r ".time[\"${ver}\"] // empty" 2>/dev/null || true)
                else
                    publish_time=$(echo "$response" | grep -o "\"${ver}\":\"[^\"]*\"" | head -1 | sed 's/.*:"\(.*\)"/\1/' || true)
                fi
            fi
            ;;
        pip)
            local response
            response=$(curl -s --max-time 5 "https://pypi.org/pypi/${pkg}/${ver}/json" 2>/dev/null || true)
            if [ -n "$response" ]; then
                if command -v jq >/dev/null 2>&1; then
                    publish_time=$(echo "$response" | jq -r '.urls[0].upload_time_iso_8601 // empty' 2>/dev/null || true)
                else
                    publish_time=$(echo "$response" | grep -o '"upload_time_iso_8601":"[^"]*"' | head -1 | sed 's/.*:"\(.*\)"/\1/' || true)
                fi
            fi
            ;;
        gem)
            local response
            response=$(curl -s --max-time 5 "https://rubygems.org/api/v1/versions/${pkg}.json" 2>/dev/null || true)
            if [ -n "$response" ]; then
                if command -v jq >/dev/null 2>&1; then
                    publish_time=$(echo "$response" | jq -r ".[] | select(.number == \"${ver}\") | .created_at // empty" 2>/dev/null || true)
                else
                    # Simplified: grab first created_at near the version string
                    publish_time=$(echo "$response" | grep -o "\"created_at\":\"[^\"]*\"" | head -1 | sed 's/.*:"\(.*\)"/\1/' || true)
                fi
            fi
            ;;
    esac

    if [ -z "$publish_time" ]; then
        # Could not determine publish time — skip silently
        return
    fi

    local publish_epoch
    publish_epoch=$(parse_iso_date "$publish_time")
    if [ "$publish_epoch" = "0" ] || [ -z "$publish_epoch" ]; then
        return
    fi

    # Cache the result
    echo "$publish_epoch" > "$cache_file"

    evaluate_age "$eco" "$pkg" "$ver" "$publish_epoch"
}

# Evaluate a package's age and emit warnings/errors
evaluate_age() {
    local eco="$1" pkg="$2" ver="$3" publish_epoch="$4"

    local age_days=$(( (now - publish_epoch) / 86400 ))

    if [ "$age_days" -lt "$QUARANTINE_DAYS" ]; then
        local remaining=$(( QUARANTINE_DAYS - age_days ))
        echo "        ❌ ${eco}:${pkg}@${ver} published ${age_days} day(s) ago (quarantine: ${QUARANTINE_DAYS} days)"
        echo "           Wait ${remaining} more day(s) or verify manually"
        found_too_new=true
    elif [ "$age_days" -lt 30 ]; then
        echo "        ⚠️  ${eco}:${pkg}@${ver} published ${age_days} days ago (< 30 days — monitor)"
    fi
}

# ============================================================
# CHECK 5: CI Config Audit
# ============================================================
check_ci_config() {
    echo ""
    echo "     🔧 Checking CI configuration..."

    local found_issue=false

    # npm: check .npmrc for ignore-scripts
    if [[ " ${ECOSYSTEMS[*]} " == *" npm "* ]]; then
        if [ -f ".npmrc" ]; then
            if ! grep -q "ignore-scripts=true" .npmrc 2>/dev/null; then
                echo "        ⚠️  .npmrc missing ignore-scripts=true"
                echo "           Add: echo 'ignore-scripts=true' >> .npmrc"
                found_issue=true
            fi
        fi
    fi

    # GitHub Actions: check for bare install commands
    if [ -d ".github/workflows" ]; then
        # Find all workflow files and check for bare npm install/ci in one pass where possible
        while IFS= read -r wf; do
            # npm install/ci without --ignore-scripts, skipping comments
            local bare_npm
            bare_npm=$(awk '/(npm install|npm ci)/ && !/--ignore-scripts/ && !/^[[:space:]]*#/ { print NR ":" $0 }' "$wf" 2>/dev/null)
            if [ -n "$bare_npm" ]; then
                echo "        ⚠️  $wf: npm install without --ignore-scripts"
                echo "$bare_npm" | head -3 | sed 's/^/           /'
                found_issue=true
            fi
        done < <(find .github/workflows -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null)
    fi

    if [ "$found_issue" = true ]; then
        update_exit 1
    else
        echo "        ✅ CI configuration looks safe"
    fi
}

# ============================================================
# Run checks based on mode
# ============================================================

# Always run: blocklist + version pinning
check_blocklist
check_version_pinning

# Pre-push and standalone: add lock file + age quarantine
if [ "$MODE" = "pre-push" ] || [ "$MODE" = "standalone" ]; then
    check_lock_files
    check_age_quarantine
fi

# Standalone only: CI config audit
if [ "$MODE" = "standalone" ]; then
    check_ci_config
fi

echo ""
echo "     ━━━━━━━━━━━━━━━━━━"

if [ "$WORST_EXIT" -eq 0 ]; then
    echo "     ✅ Supply chain scan clean"
elif [ "$WORST_EXIT" -eq 1 ]; then
    echo "     ⚠️  Supply chain scan: warnings found (see above)"
elif [ "$WORST_EXIT" -eq 2 ]; then
    echo "     ❌ Supply chain scan: MALICIOUS PACKAGE DETECTED"
elif [ "$WORST_EXIT" -eq 3 ]; then
    echo "     ❌ Supply chain scan: package quarantine violation"
fi

if [ "$SOFT_FAIL" = true ]; then
    exit 0
fi

exit "$WORST_EXIT"
