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
declare -A ECO_MANIFESTS
declare -A ECO_LOCKFILES

detect_ecosystems() {
    # npm
    if [ -f "package.json" ]; then
        ECOSYSTEMS+=("npm")
        ECO_MANIFESTS[npm]="package.json"
        for f in package-lock.json yarn.lock pnpm-lock.yaml; do
            [ -f "$f" ] && ECO_LOCKFILES[npm]="${ECO_LOCKFILES[npm]:-} $f"
        done
        ECO_LOCKFILES[npm]="${ECO_LOCKFILES[npm]:-}"
        ECO_LOCKFILES[npm]="${ECO_LOCKFILES[npm]# }"
    fi

    # pip
    local pip_manifests=""
    for f in requirements.txt pyproject.toml Pipfile; do
        [ -f "$f" ] && pip_manifests="$pip_manifests $f"
    done
    if [ -n "$pip_manifests" ]; then
        ECOSYSTEMS+=("pip")
        ECO_MANIFESTS[pip]="${pip_manifests# }"
        for f in Pipfile.lock poetry.lock uv.lock requirements.lock pdm.lock; do
            [ -f "$f" ] && ECO_LOCKFILES[pip]="${ECO_LOCKFILES[pip]:-} $f"
        done
        ECO_LOCKFILES[pip]="${ECO_LOCKFILES[pip]:-}"
        ECO_LOCKFILES[pip]="${ECO_LOCKFILES[pip]# }"
    fi

    # gem
    if [ -f "Gemfile" ]; then
        ECOSYSTEMS+=("gem")
        ECO_MANIFESTS[gem]="Gemfile"
        [ -f "Gemfile.lock" ] && ECO_LOCKFILES[gem]="Gemfile.lock"
    fi

    # go
    if [ -f "go.mod" ]; then
        ECOSYSTEMS+=("go")
        ECO_MANIFESTS[go]="go.mod"
        [ -f "go.sum" ] && ECO_LOCKFILES[go]="go.sum"
    fi

    # cargo
    if [ -f "Cargo.toml" ]; then
        ECOSYSTEMS+=("cargo")
        ECO_MANIFESTS[cargo]="Cargo.toml"
        [ -f "Cargo.lock" ] && ECO_LOCKFILES[cargo]="Cargo.lock"
    fi

    # composer
    if [ -f "composer.json" ]; then
        ECOSYSTEMS+=("composer")
        ECO_MANIFESTS[composer]="composer.json"
        [ -f "composer.lock" ] && ECO_LOCKFILES[composer]="composer.lock"
    fi
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
                local manifest="${ECO_MANIFESTS[$eco]}"
                [ -z "$manifest" ] && continue

                local unpinned=""
                if command -v jq >/dev/null 2>&1; then
                    unpinned=$(jq -r '
                        [(.dependencies // {}), (.devDependencies // {})]
                        | add // {}
                        | to_entries[]
                        | select(.value | test("^[\\^~]"))
                        | "        \(.key): \(.value)"
                    ' "$manifest" 2>/dev/null || true)
                else
                    while read -r pkg ver; do
                        [ -z "$pkg" ] && continue
                        if [[ "$ver" =~ ^[\^~] ]]; then
                            unpinned="${unpinned:+$unpinned$'\n'}        $pkg: $ver"
                        fi
                    done <<< "$(npm_deps_grep "$manifest")"
                fi

                if [ -n "$unpinned" ]; then
                    echo "        ⚠️  npm: unpinned versions in $manifest:"
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
                ;;
            pip)
                for manifest in ${ECO_MANIFESTS[$eco]}; do
                    if [[ "$manifest" == "requirements.txt" ]]; then
                        local unpinned_pip=""
                        local line_num=0
                        while IFS= read -r line; do
                            line_num=$((line_num + 1))
                            [[ "$line" =~ ^[[:space:]]*# ]] && continue
                            [[ -z "$line" ]] && continue
                            # Flag lines starting with a package name but without ==
                            if [[ "$line" =~ ^[a-zA-Z0-9._-]+ ]] && [[ ! "$line" =~ == ]]; then
                                unpinned_pip="${unpinned_pip:+$unpinned_pip$'\n'}        $line_num:$line"
                            fi
                        done < "$manifest"

                        if [ -n "$unpinned_pip" ]; then
                            echo "        ⚠️  pip: unpinned versions in $manifest:"
                            echo "$unpinned_pip"
                            echo "        Fix: Use == for exact pinning (e.g., requests==2.31.0)"
                            found_unpinned=true
                        fi
                    elif [[ "$manifest" == "pyproject.toml" ]]; then
                        local unpinned_pyp
                        unpinned_pyp=$(sed -n '/\[project\]/,/^\[/p; /\[tool\.poetry\.dependencies\]/,/^\[/p' "$manifest" 2>/dev/null \
                            | grep -E '(>=|~=|\^|>)' \
                            | grep -vE '^\s*#' \
                            | grep -vE 'requires-python' \
                            | sed 's/^/        /' || true)
                        if [ -n "$unpinned_pyp" ]; then
                            echo "        ⚠️  pip: unpinned versions in $manifest:"
                            echo "$unpinned_pyp"
                            found_unpinned=true
                        fi
                    fi
                done
                ;;
            gem)
                local manifest="${ECO_MANIFESTS[$eco]}"
                [ -z "$manifest" ] && continue
                # Flag gems with ~> (pessimistic) or no version constraint
                local unpinned_gem=""
                local no_version_gem=""
                local line_num=0
                while IFS= read -r line; do
                    line_num=$((line_num + 1))
                    [[ "$line" =~ ^[[:space:]]*# ]] && continue
                    if [[ "$line" =~ ^[[:space:]]*gem[[:space:]]+ ]]; then
                        if [[ "$line" =~ (~>|>=|>) ]]; then
                            unpinned_gem="${unpinned_gem:+$unpinned_gem$'\n'}        $line_num:$line"
                        elif [[ "$line" =~ ^[[:space:]]*gem[[:space:]]+[\'\"][^\'\"]+[\'\"][[:space:]]*$ ]]; then
                            no_version_gem="${no_version_gem:+$no_version_gem$'\n'}        $line_num:$line"
                        fi
                    fi
                done < "$manifest"

                if [ -n "$unpinned_gem" ] || [ -n "$no_version_gem" ]; then
                    echo "        ⚠️  gem: unpinned versions in $manifest:"
                    [ -n "$unpinned_gem" ] && echo "$unpinned_gem"
                    [ -n "$no_version_gem" ] && echo "$no_version_gem" && echo "        (gems with no version constraint)"
                    found_unpinned=true
                fi
                ;;
            cargo)
                local manifest="${ECO_MANIFESTS[$eco]}"
                [ -z "$manifest" ] && continue
                local unpinned_cargo
                unpinned_cargo=$(awk '/\[(dev-)?dependencies\]/,/^\[/ { if ($0 ~ /=[[:space:]]*"[\^~]/) { print "        " $0 } }' "$manifest" 2>/dev/null || true)
                if [ -n "$unpinned_cargo" ]; then
                    echo "        ⚠️  cargo: unpinned versions in $manifest:"
                    echo "$unpinned_cargo"
                    found_unpinned=true
                fi
                ;;
            composer)
                local manifest="${ECO_MANIFESTS[$eco]}"
                [ -z "$manifest" ] && continue
                local unpinned_comp=""
                if command -v jq >/dev/null 2>&1; then
                    unpinned_comp=$(jq -r '
                        [(.require // {}), (."require-dev" // {})]
                        | add // {}
                        | to_entries[]
                        | select(.value | test("^[\\^~]"))
                        | "        \(.key): \(.value)"
                    ' "$manifest" 2>/dev/null || true)
                else
                    while IFS= read -r line; do
                        if [[ "$line" =~ [\^~] ]] && [[ ! "$line" =~ \"(require|require-dev)\" ]]; then
                             unpinned_comp="${unpinned_comp:+$unpinned_comp$'\n'}        ${line#*\"}"
                        fi
                    done < "$manifest"
                fi
                if [ -n "$unpinned_comp" ]; then
                    echo "        ⚠️  composer: unpinned versions in $manifest:"
                    echo "$unpinned_comp"
                    found_unpinned=true
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
    declare -A ECO_REGEX
    declare -A BLOCKLIST_REASONS

    # Build combined regex per ecosystem
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        local entry
        entry=$(echo "$line" | awk '{print $1}')
        local eco_prefix="${entry%%:*}"
        local pkg_name="${entry#*:}"
        local reason
        reason=$(echo "$line" | sed 's/^[^#]*#//' | sed 's/^[[:space:]]*//')

        # Store reason for later reporting
        BLOCKLIST_REASONS["$eco_prefix:$pkg_name"]="$reason"

        # Escape pkg_name for regex
        local escaped_pkg
        escaped_pkg=$(echo "$pkg_name" | sed 's/[^a-zA-Z0-9]/\\&/g')
        local pattern="(^|[^a-zA-Z0-9_-])${escaped_pkg}([^a-zA-Z0-9_-]|$)"

        if [ -z "${ECO_REGEX[$eco_prefix]:-}" ]; then
            ECO_REGEX[$eco_prefix]="$pattern"
        else
            ECO_REGEX[$eco_prefix]="${ECO_REGEX[$eco_prefix]}|$pattern"
        fi
    done < "$BLOCKLIST_FILE"

    for eco in "${ECOSYSTEMS[@]}"; do
        local regex="${ECO_REGEX[$eco]:-}"
        [ -z "$regex" ] && continue

        local files="${ECO_MANIFESTS[$eco]} ${ECO_LOCKFILES[$eco]}"
        for file in $files; do
            [ ! -f "$file" ] && continue

            # Use grep -E for the combined regex
            local matches
            # The regex includes boundary characters. We need to strip at most one non-identifier character from both ends.
            # Identification characters: a-z, A-Z, 0-9, _, -, @, /, .
            matches=$(grep -oE "$regex" "$file" | sed -E 's/^[^a-zA-Z0-9_-]//; s/[^a-zA-Z0-9_-]$//' | sort -u || true)

            if [ -n "$matches" ]; then
                while IFS= read -r pkg_name; do
                    # Double check it is exactly one of the packages for this ecosystem
                    if [ -n "${BLOCKLIST_REASONS["$eco:$pkg_name"]+v}" ]; then
                        local reason="${BLOCKLIST_REASONS["$eco:$pkg_name"]}"
                        echo "        ❌ MALICIOUS PACKAGE: $pkg_name found in $file"
                        [ -n "$reason" ] && echo "           Reason: $reason"
                        echo "           Remove immediately and rotate all credentials"
                        found_malicious=true
                    fi
                done <<< "$matches"
            fi
        done
    done

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
        local manifests="${ECO_MANIFESTS[$eco]}"
        local locks="${ECO_LOCKFILES[$eco]:-}"

        case "$eco" in
            npm)
                if [[ "$manifests" == *"package.json"* ]] && [ -z "$locks" ]; then
                    echo "        ⚠️  npm: package.json exists but no lock file found"
                    echo "           Run: npm install to generate package-lock.json"
                    missing_lock=true
                fi
                ;;
            pip)
                if [[ "$manifests" == *"pyproject.toml"* ]] && [ -z "$locks" ]; then
                    echo "        ⚠️  pip: pyproject.toml exists but no lock file found"
                    echo "           Consider using poetry.lock, uv.lock, or pip-compile"
                    missing_lock=true
                fi
                ;;
            gem)
                if [[ "$manifests" == *"Gemfile"* ]] && [ -z "$locks" ]; then
                    echo "        ⚠️  gem: Gemfile exists but Gemfile.lock not found"
                    echo "           Run: bundle install to generate Gemfile.lock"
                    missing_lock=true
                fi
                ;;
            go)
                if [[ "$manifests" == *"go.mod"* ]] && [ -z "$locks" ]; then
                    echo "        ⚠️  go: go.mod exists but go.sum not found"
                    echo "           Run: go mod tidy"
                    missing_lock=true
                fi
                ;;
            cargo)
                if [[ "$manifests" == *"Cargo.toml"* ]] && [ -z "$locks" ]; then
                    echo "        ⚠️  cargo: Cargo.toml exists but Cargo.lock not found"
                    echo "           Run: cargo generate-lockfile"
                    missing_lock=true
                fi
                ;;
            composer)
                if [[ "$manifests" == *"composer.json"* ]] && [ -z "$locks" ]; then
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
                local manifest="${ECO_MANIFESTS[$eco]}"
                [[ "$manifest" != *"package.json"* ]] && continue
                local deps=""
                if command -v jq >/dev/null 2>&1; then
                    deps=$(jq -r '(.dependencies // {}) | to_entries[] | "\(.key) \(.value)"' "$manifest" 2>/dev/null || true)
                else
                    deps=$(npm_deps_grep "$manifest")
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
                for manifest in ${ECO_MANIFESTS[$eco]}; do
                    [[ "$manifest" != "requirements.txt" ]] && continue
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
                    done < "$manifest"
                done
                ;;
            gem)
                local lock="${ECO_LOCKFILES[$eco]}"
                [[ "$lock" != *"Gemfile.lock"* ]] && continue
                # Extract pinned gems from Gemfile.lock specs section
                local gems
                gems=$(awk '/^  specs:/ {in_specs=1; next} in_specs && /^[^ ]/ {in_specs=0} in_specs && /^[ ]{4}[a-zA-Z]/ { gsub(/[()]/, "", $2); print $1, $2 }' "$lock" 2>/dev/null || true)
                while read -r pkg ver; do
                    [ -z "$pkg" ] || [ -z "$ver" ] && continue
                    check_package_age "gem" "$pkg" "$ver"
                done <<< "$gems"
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
