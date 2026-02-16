#!/bin/bash
# Fix missing timestamps in markdown files using git history
# Called by pre-push hook when .md files are missing Created/Last Updated metadata

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

fixed=0
already_ok=0
errors=0

echo "🔧 Fixing missing timestamps in markdown files..."
echo ""

# inject_after_line: insert text after a specific line number (handles multi-line text)
# Usage: inject_after_line <file> <line_number> <text_to_insert>
inject_after_line() {
    local file="$1" line_num="$2" text="$3"
    local tmp_file
    tmp_file=$(mktemp)
    head -n "$line_num" "$file" > "$tmp_file"
    printf '\n%s\n' "$text" >> "$tmp_file"
    tail -n +"$((line_num + 1))" "$file" >> "$tmp_file"
    mv "$tmp_file" "$file"
}

# inject_before_line: insert text before a specific line number
# Usage: inject_before_line <file> <line_number> <text_to_insert>
inject_before_line() {
    local file="$1" line_num="$2" text="$3"
    local tmp_file
    tmp_file=$(mktemp)
    if [ "$line_num" -gt 1 ]; then
        head -n "$((line_num - 1))" "$file" > "$tmp_file"
    else
        : > "$tmp_file"
    fi
    printf '%s\n' "$text" >> "$tmp_file"
    tail -n +"$line_num" "$file" >> "$tmp_file"
    mv "$tmp_file" "$file"
}

# prepend_to_file: add text at the very top
# Usage: prepend_to_file <file> <text_to_prepend>
prepend_to_file() {
    local file="$1" text="$2"
    local tmp_file
    tmp_file=$(mktemp)
    printf '%s\n\n' "$text" | cat - "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
}

while IFS= read -r -d '' file; do
    # Skip symlinks — can't inject metadata into link targets
    [ -L "$file" ] && continue
    # Skip files not present on disk (sparse checkout)
    if [ ! -f "$file" ]; then
        echo "  ⚠️  $file: tracked but not present on disk (sparse checkout?) — skipping"
        continue
    fi

    has_created=$(grep -c '^\*\*Created:\*\*' "$file" || true)
    has_updated=$(grep -c '^\*\*Last Updated:\*\*' "$file" || true)

    if [ "$has_created" -gt 0 ] && [ "$has_updated" -gt 0 ]; then
        already_ok=$((already_ok + 1))
        continue
    fi

    # Get dates from git history
    last_modified=$(git log -1 --format="%ad" --date=format:"%Y-%m-%d-%H-%M" -- "$file" 2>/dev/null || true)
    first_committed=$(git log --follow --diff-filter=A --format="%ad" --date=format:"%Y-%m-%d-%H-%M" -- "$file" 2>/dev/null | tail -1)

    # Fallback to current date if no git history (untracked/new file)
    if [ -z "$last_modified" ]; then
        last_modified=$(date +"%Y-%m-%d-%H-%M")
        echo "  ℹ️  $file: no git history, using current date as fallback"
    fi
    if [ -z "$first_committed" ]; then
        first_committed="$last_modified"
    fi

    timestamp_created="**Created:** $first_committed"
    timestamp_updated="**Last Updated:** $last_modified"

    if [ "$has_created" -gt 0 ] && [ "$has_updated" -eq 0 ]; then
        # Has Created but missing Last Updated — add it after the Created line
        created_line=$(grep -n '^\*\*Created:\*\*' "$file" | head -1 | cut -d: -f1)
        inject_after_line "$file" "$created_line" "$timestamp_updated"
        echo "  ✅ $file: added Last Updated ($last_modified) from git history"
        fixed=$((fixed + 1))

    elif [ "$has_created" -eq 0 ] && [ "$has_updated" -gt 0 ]; then
        # Has Last Updated but missing Created — add Created before it
        updated_line=$(grep -n '^\*\*Last Updated:\*\*' "$file" | head -1 | cut -d: -f1)
        inject_before_line "$file" "$updated_line" "$timestamp_created"
        echo "  ✅ $file: added Created ($first_committed) from git history"
        fixed=$((fixed + 1))

    else
        # Missing both — need to inject the full block
        timestamp_block="$timestamp_created
$timestamp_updated"

        first_line=$(head -1 "$file")

        if [ "$first_line" = "---" ]; then
            # YAML frontmatter: inject after closing ---
            closing_line=$(awk '/^---$/{count++; if(count==2){print NR; exit}}' "$file")
            if [ -n "$closing_line" ]; then
                inject_after_line "$file" "$closing_line" "$timestamp_block"
                echo "  ✅ $file: added timestamps after frontmatter (created: $first_committed, updated: $last_modified)"
                fixed=$((fixed + 1))
            else
                echo "  ❌ $file: has opening --- but no closing frontmatter delimiter"
                errors=$((errors + 1))
            fi

        elif echo "$first_line" | grep -q '^#'; then
            # Starts with markdown heading (any level: #, ##, ###, etc.): inject after it
            inject_after_line "$file" 1 "$timestamp_block"
            echo "  ✅ $file: added timestamps after heading (created: $first_committed, updated: $last_modified)"
            fixed=$((fixed + 1))

        else
            # No frontmatter, no heading: inject at very top
            prepend_to_file "$file" "$timestamp_block"
            echo "  ✅ $file: added timestamps at top (created: $first_committed, updated: $last_modified)"
            fixed=$((fixed + 1))
        fi
    fi
done < <(git ls-files -z -- '*.md')

echo ""
echo "📊 Results: $fixed fixed, $already_ok already OK, $errors errors"

if [ "$fixed" -gt 0 ]; then
    echo ""
    echo "📝 Next steps:"
    echo "   1. Review the changes: git diff"
    echo "   2. Stage and commit:   git add -A && git commit -m 'docs: add missing timestamps from git history'"
    echo "   3. Push again:         git push"
fi

if [ "$errors" -gt 0 ]; then
    echo ""
    echo "⚠️  $errors file(s) could not be auto-fixed. Edit manually."
    exit 1
fi
