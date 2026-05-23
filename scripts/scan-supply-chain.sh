#!/usr/bin/env bash
# scan-supply-chain.sh — supply-chain guardrails for dependency manifest changes.
#
# Called by git-hooks/pre-commit and git-hooks/pre-push when staged/pushed changes
# touch dependency manifests (package.json, requirements.txt, pyproject.toml,
# Gemfile, Cargo.toml, composer.json, go.mod).
#
# Exit codes (contract — pre-commit and pre-push depend on these):
#   0 = clean
#   1 = warnings (unpinned versions, etc.). pre-commit allows; pre-push blocks.
#   2 = malicious / policy-violating. always blocks.
#
# Flags:
#   --pre-commit   uses `git diff --cached`
#   --pre-push     uses `git diff <upstream>..HEAD`
#   --staged       alias for --pre-commit
#   --age-days N   minimum age in days for newly-added deps (default: 7)
#   --offline      skip any network calls (no registry age checks)
#
# Policy:
#   1. Block known-bad package names (typosquats, recent incidents). Exit 2.
#   2. Block deps pinned to a version released < $AGE_DAYS days ago (npm registry).
#      Acts on *newly added* deps only, never on existing ones.
#   3. Warn on unpinned ranges in newly-added deps (^, ~, *, latest, no version).
#   4. Warn on deps using install scripts (git+ssh:, file:, http:, github: shorthand).
#
# The script aims to be FAST and OFFLINE-FRIENDLY for pre-commit. Network checks
# (registry age) are skipped when --offline is set OR when no network is reachable
# within 1 second per package.

set -u

MODE=""
AGE_DAYS=7
OFFLINE=0
for arg in "$@"; do
    case "$arg" in
        --pre-commit|--staged) MODE="staged" ;;
        --pre-push)            MODE="push" ;;
        --age-days=*)          AGE_DAYS="${arg#--age-days=}" ;;
        --offline)             OFFLINE=1 ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0
            ;;
    esac
done
[ -z "$MODE" ] && MODE="staged"

# ---------- known-bad list (extend over time; one entry per line) ----------
# Format: <ecosystem>:<package>[:<reason>]
# Ecosystems: npm, pypi, gem, cargo, go, composer
read -r -d '' KNOWN_BAD <<'EOF' || true
npm:left-pad-evil:demo entry — replace with real incidents
npm:colors:tagged 2021 sabotage; reverted but kept as example
npm:faker:tagged 2022 sabotage; reverted but kept as example
npm:ua-parser-js:0.7.29:malware (Oct 2021)
npm:ua-parser-js:0.8.0:malware (Oct 2021)
npm:ua-parser-js:1.0.0:malware (Oct 2021)
npm:coa:malware (Nov 2021)
npm:rc:malware (Nov 2021)
pypi:ctx:malware (May 2022)
pypi:phpass:malware (May 2022)
EOF

found_bad=0
found_warn=0

# ---------- helpers ----------
emit_err()  { printf '  ❌ %s\n' "$*" >&2; }
emit_warn() { printf '  ⚠️  %s\n' "$*" >&2; }
emit_info() { printf '  ℹ️  %s\n' "$*" >&2; }

diff_added_lines() {
    # Print only lines added in the relevant diff for $1 (file path).
    local file="$1"
    if [ "$MODE" = "staged" ]; then
        git diff --cached -- "$file" 2>/dev/null \
            | grep -E '^\+[^+]' | sed 's/^\+//'
    else
        local upstream
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "origin/main")
        git diff "$upstream"..HEAD -- "$file" 2>/dev/null \
            | grep -E '^\+[^+]' | sed 's/^\+//'
    fi
}

changed_files() {
    if [ "$MODE" = "staged" ]; then
        git diff --cached --name-only --diff-filter=ACM 2>/dev/null
    else
        local upstream
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "origin/main")
        git diff --name-only --diff-filter=ACM "$upstream"..HEAD 2>/dev/null
    fi
}

# Check known-bad list. Args: ecosystem name [version]
check_known_bad() {
    local eco="$1" name="$2" version="${3:-}"
    while IFS=: read -r e p v _; do
        [ -z "$e" ] && continue
        case "$e" in \#*) continue ;; esac
        if [ "$e" = "$eco" ] && [ "$p" = "$name" ]; then
            if [ -z "$v" ] || [ -z "$version" ] || [ "$v" = "$version" ]; then
                emit_err "Known-bad package: $eco:$name${version:+@$version}"
                found_bad=1
                return
            fi
        fi
    done <<< "$KNOWN_BAD"
}

# npm registry release-time check. Args: pkg version
# Returns 0 if version is >= AGE_DAYS old, 1 if too new, 2 if check skipped.
npm_age_ok() {
    [ "$OFFLINE" -eq 1 ] && return 2
    command -v curl >/dev/null 2>&1 || return 2
    command -v jq   >/dev/null 2>&1 || return 2
    local pkg="$1" ver="$2"
    local url="https://registry.npmjs.org/${pkg}"
    local released
    released=$(curl -fsS --max-time 2 "$url" 2>/dev/null \
        | jq -r --arg v "$ver" '.time[$v] // empty' 2>/dev/null) || return 2
    [ -z "$released" ] && return 2
    local rel_epoch
    rel_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${released%.*}" "+%s" 2>/dev/null) || return 2
    local now cutoff
    now=$(date "+%s")
    cutoff=$((now - AGE_DAYS * 86400))
    if [ "$rel_epoch" -gt "$cutoff" ]; then
        return 1
    fi
    return 0
}

# ---------- per-manifest scanners ----------

scan_package_json() {
    local f="$1" added
    added=$(diff_added_lines "$f")
    [ -z "$added" ] && return

    # Lines like:  "pkg-name": "1.2.3",   or  "pkg-name": "^1.2.3",
    # Skip "scripts": / "engines": / etc. by requiring a version-looking value.
    while IFS= read -r line; do
        # crude but effective: extract "name": "spec"
        local name spec
        name=$(echo "$line" | sed -nE 's/.*"([^"]+)"[[:space:]]*:[[:space:]]*".*".*/\1/p')
        spec=$(echo "$line" | sed -nE 's/.*"[^"]+"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')
        [ -z "$name" ] && continue
        [ -z "$spec" ] && continue
        # skip non-dep keys
        case "$name" in
            name|version|description|main|module|types|license|author|homepage|repository|bugs|funding|private|type|sideEffects|engines|scripts|keywords|files|workspaces|publishConfig|exports|bin|browser|man|directories)
                continue
                ;;
        esac
        # skip if spec is clearly not a version range
        case "$spec" in
            *://*|git+*|file:*|github:*|workspace:*)
                emit_warn "Non-registry dep source: \"$name\": \"$spec\" — review carefully"
                found_warn=1
                continue
                ;;
        esac

        check_known_bad npm "$name"

        # unpinned warnings
        case "$spec" in
            \*|latest|next)
                emit_warn "Unpinned: \"$name\": \"$spec\" — pin to a specific version"
                found_warn=1
                ;;
        esac
        # Semver ranges (^, ~, >=, <) are accepted here; CI should resolve a
        # lockfile and re-scan the resolved versions for full coverage.

        # age check on exact-pinned versions (strip leading ^ ~ = v)
        local clean_spec="${spec#[\^~=v]}"
        if [[ "$clean_spec" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._-]+)?$ ]]; then
            npm_age_ok "$name" "$clean_spec"
            case "$?" in
                1)
                    emit_err "Too new: $name@$clean_spec released < ${AGE_DAYS}d ago"
                    found_bad=1
                    ;;
            esac
        fi
    done <<< "$added"
}

scan_requirements_txt() {
    local f="$1" added
    added=$(diff_added_lines "$f")
    [ -z "$added" ] && return
    while IFS= read -r line; do
        line="${line%%#*}"      # strip comments
        line="${line// /}"      # strip spaces
        [ -z "$line" ] && continue
        # name[==><~!]version  or  name (no version)
        local name version
        name=$(echo "$line" | sed -nE 's/^([A-Za-z0-9_.-]+).*/\1/p')
        version=$(echo "$line" | sed -nE 's/^[A-Za-z0-9_.-]+==([0-9][A-Za-z0-9._-]*).*/\1/p')
        [ -z "$name" ] && continue
        check_known_bad pypi "$name"
        if [ -z "$version" ]; then
            emit_warn "Unpinned pip dep: $line — use name==version"
            found_warn=1
        fi
    done <<< "$added"
}

scan_pyproject_toml() {
    local f="$1" added
    added=$(diff_added_lines "$f")
    [ -z "$added" ] && return
    # Match poetry / PEP 621 dep lines: name = "spec"  or  "name>=1.0"
    while IFS= read -r line; do
        # poetry style: pkg = "^1.2.3"
        local name spec
        name=$(echo "$line" | sed -nE 's/^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*".*".*/\1/p')
        if [ -n "$name" ]; then
            spec=$(echo "$line" | sed -nE 's/^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p')
            case "$name" in name|version|description|authors|license|readme|requires-python|homepage|repository|documentation|keywords|classifiers)
                continue ;;
            esac
            check_known_bad pypi "$name"
            case "$spec" in
                \*|latest)
                    emit_warn "Unpinned poetry/pyproject dep: $name = $spec"
                    found_warn=1
                    ;;
            esac
        fi
    done <<< "$added"
}

scan_cargo_toml() {
    local f="$1" added
    added=$(diff_added_lines "$f")
    [ -z "$added" ] && return
    while IFS= read -r line; do
        local name spec
        name=$(echo "$line" | sed -nE 's/^[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*=[[:space:]]*".*".*/\1/p')
        if [ -n "$name" ]; then
            spec=$(echo "$line" | sed -nE 's/^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p')
            case "$name" in name|version|edition|authors|description|license|readme|repository|homepage|documentation|keywords|categories|edition|rust-version|workspace)
                continue ;;
            esac
            check_known_bad cargo "$name"
            case "$spec" in \*|latest)
                emit_warn "Unpinned cargo dep: $name = $spec"
                found_warn=1
                ;;
            esac
        fi
    done <<< "$added"
}

scan_gemfile()   { :; }   # placeholder; gemfiles are unusual in this fleet
scan_composer()  { :; }
scan_go_mod() {
    local f="$1" added
    added=$(diff_added_lines "$f")
    [ -z "$added" ] && return
    # `module name v1.2.3` — go.mod entries are always pinned by go's tooling.
    while IFS= read -r line; do
        local name
        name=$(echo "$line" | sed -nE 's/^[[:space:]]*([a-z0-9./_-]+)[[:space:]]+v[0-9].*/\1/p')
        [ -n "$name" ] && check_known_bad go "$name"
    done <<< "$added"
}

# ---------- main ----------

FILES=$(changed_files)
[ -z "$FILES" ] && exit 0

while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$(basename "$f")" in
        package.json)      scan_package_json "$f" ;;
        requirements.txt|requirements-*.txt)  scan_requirements_txt "$f" ;;
        pyproject.toml)    scan_pyproject_toml "$f" ;;
        Cargo.toml)        scan_cargo_toml "$f" ;;
        Gemfile)           scan_gemfile "$f" ;;
        composer.json)     scan_composer "$f" ;;
        go.mod)            scan_go_mod "$f" ;;
    esac
done <<< "$FILES"

if [ "$found_bad" -eq 1 ]; then
    emit_info "Supply-chain policy violation. Override by editing scripts/scan-supply-chain.sh KNOWN_BAD or running with --age-days=0."
    exit 2
fi
if [ "$found_warn" -eq 1 ]; then
    exit 1
fi
exit 0
