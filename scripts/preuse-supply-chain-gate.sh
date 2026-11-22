#!/usr/bin/env bash
# preuse-supply-chain-gate.sh — Claude Code PreToolUse hook.
#
# Reads a JSON tool-call payload on stdin. For Bash tool calls, blocks
# install verbs that would fetch arbitrary packages from public registries
# unless they're routed through the supply-chain-safe wrapper (socket / npm-safe-install)
# or explicitly overridden with SAFE_INSTALL_OVERRIDE=1 on that command.
#
# The match is on the shell command that will actually execute. Quoted
# arguments, comments, and here-document bodies are not installs. Command
# substitutions are, because the shell runs them. A quoted script passed to
# bash -c / eval is not re-parsed (GIT-6494); GIT-8227 tracks that residue.
#
# Exit codes (Claude Code contract):
#   0 = allow
#   2 = block, surface stderr back to the model so it self-corrects

set -u

input=$(cat)

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" != "Bash" ] && exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Scanner state. Heredoc queues are global and tagged with SCAN_DEPTH so a
# nested command substitution cannot consume the caller's here-documents.
SCAN_S=""
SCAN_N=0
SCAN_I=0
SCAN_OUT=""
SCAN_DEPTH=0
H_DELIM=()
H_QUOTED=()
H_TABS=()
H_LEVEL=()

scan_append_literal_gap() {
    SCAN_OUT+=" "
}

# First here-doc queued at the current depth (FIFO). Returns 1 if none.
scan_peek_heredoc() {
    local i
    HD_INDEX=-1
    for i in "${!H_LEVEL[@]}"; do
        if [ "${H_LEVEL[$i]}" -eq "$SCAN_DEPTH" ]; then
            HD_INDEX=$i
            HD_DELIM="${H_DELIM[$i]}"
            HD_QUOTED="${H_QUOTED[$i]}"
            HD_TABS="${H_TABS[$i]}"
            return 0
        fi
    done
    return 1
}

scan_drop_peeked_heredoc() {
    local idx=$HD_INDEX
    unset "H_DELIM[$idx]" "H_QUOTED[$idx]" "H_TABS[$idx]" "H_LEVEL[$idx]"
    H_DELIM=("${H_DELIM[@]+"${H_DELIM[@]}"}")
    H_QUOTED=("${H_QUOTED[@]+"${H_QUOTED[@]}"}")
    H_TABS=("${H_TABS[@]+"${H_TABS[@]}"}")
    H_LEVEL=("${H_LEVEL[@]+"${H_LEVEL[@]}"}")
}

scan_has_heredoc() {
    scan_peek_heredoc
}

scan_skip_single() {
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        if [ "${SCAN_S:$SCAN_I:1}" = "'" ]; then
            SCAN_I=$((SCAN_I + 1))
            return 0
        fi
        SCAN_I=$((SCAN_I + 1))
    done
}

scan_double() {
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        local c="${SCAN_S:$SCAN_I:1}"
        local next="${SCAN_S:$((SCAN_I + 1)):1}"
        if [ "$c" = '"' ]; then
            SCAN_I=$((SCAN_I + 1))
            return 0
        fi
        if [ "$c" = '\\' ]; then
            if [ "$next" = $'\n' ]; then
                SCAN_I=$((SCAN_I + 2))
                continue
            fi
            # Escaped character is literal prose, including \$ and \`.
            SCAN_I=$((SCAN_I + 2))
            continue
        fi
        if [ "$c" = '$' ] && [ "$next" = '(' ]; then
            scan_dollar_paren
            continue
        fi
        if [ "$c" = '`' ]; then
            SCAN_I=$((SCAN_I + 1))
            SCAN_OUT+=$'\n'
            scan_code btick
            SCAN_OUT+=$'\n'
            continue
        fi
        SCAN_I=$((SCAN_I + 1))
    done
}

scan_dollar_paren() {
    local third="${SCAN_S:$((SCAN_I + 2)):1}"
    if [ "$third" = '(' ]; then
        # $(( arithmetic )), not a command.
        SCAN_I=$((SCAN_I + 3))
        local depth=1
        while [ "$SCAN_I" -lt "$SCAN_N" ] && [ "$depth" -gt 0 ]; do
            local c="${SCAN_S:$SCAN_I:1}"
            local next="${SCAN_S:$((SCAN_I + 1)):1}"
            if [ "$c" = '(' ] && [ "$next" = '(' ]; then
                # Nested arithmetic is unusual; count parens only.
                :
            fi
            if [ "$c" = '(' ]; then
                depth=$((depth + 1))
            elif [ "$c" = ')' ]; then
                depth=$((depth - 1))
            fi
            SCAN_I=$((SCAN_I + 1))
        done
        return 0
    fi
    SCAN_I=$((SCAN_I + 2))
    SCAN_OUT+=$'\n'
    scan_code paren
    SCAN_OUT+=$'\n'
}

scan_parse_heredoc_op() {
    # SCAN_I points at the first '<'.
    SCAN_I=$((SCAN_I + 2))
    local tabs=0
    if [ "${SCAN_S:$SCAN_I:1}" = '-' ]; then
        tabs=1
        SCAN_I=$((SCAN_I + 1))
    fi
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        local c="${SCAN_S:$SCAN_I:1}"
        case "$c" in
            ' '|$'\t') SCAN_I=$((SCAN_I + 1)) ;;
            *) break ;;
        esac
    done
    local quoted=0
    local delim=""
    local c="${SCAN_S:$SCAN_I:1}"
    if [ "$c" = "'" ] || [ "$c" = '"' ]; then
        quoted=1
        local q="$c"
        SCAN_I=$((SCAN_I + 1))
        while [ "$SCAN_I" -lt "$SCAN_N" ] && [ "${SCAN_S:$SCAN_I:1}" != "$q" ]; do
            delim+="${SCAN_S:$SCAN_I:1}"
            SCAN_I=$((SCAN_I + 1))
        done
        if [ "${SCAN_S:$SCAN_I:1}" = "$q" ]; then
            SCAN_I=$((SCAN_I + 1))
        fi
    else
        while [ "$SCAN_I" -lt "$SCAN_N" ]; do
            c="${SCAN_S:$SCAN_I:1}"
            case "$c" in
                ' '|$'\t'|$'\n'|'|'|'&'|';'|'<'|'>'|'('|')') break ;;
                *) delim+="$c"; SCAN_I=$((SCAN_I + 1)) ;;
            esac
        done
    fi
    if [ -n "$delim" ]; then
        H_DELIM+=("$delim")
        H_QUOTED+=("$quoted")
        H_TABS+=("$tabs")
        H_LEVEL+=("$SCAN_DEPTH")
    fi
    scan_append_literal_gap
}

scan_read_line() {
    SCAN_LINE=""
    if [ "$SCAN_I" -ge "$SCAN_N" ]; then
        return 1
    fi
    while [ "$SCAN_I" -lt "$SCAN_N" ] && [ "${SCAN_S:$SCAN_I:1}" != $'\n' ]; do
        SCAN_LINE+="${SCAN_S:$SCAN_I:1}"
        SCAN_I=$((SCAN_I + 1))
    done
    if [ "$SCAN_I" -lt "$SCAN_N" ] && [ "${SCAN_S:$SCAN_I:1}" = $'\n' ]; then
        SCAN_I=$((SCAN_I + 1))
    fi
    return 0
}

scan_consume_heredocs() {
    while scan_peek_heredoc; do
        local delim="$HD_DELIM"
        local quoted="$HD_QUOTED"
        local tabs="$HD_TABS"
        local closed=0
        while scan_read_line; do
            local compare="$SCAN_LINE"
            if [ "$tabs" = "1" ]; then
                while [ "${compare:0:1}" = $'\t' ]; do
                    compare="${compare:1}"
                done
            fi
            if [ "$compare" = "$delim" ]; then
                scan_drop_peeked_heredoc
                closed=1
                break
            fi
            if [ "$quoted" = "0" ] && [ -n "$SCAN_LINE" ]; then
                # Unquoted body: quotes are literal, but $(...) and backticks run.
                local saved_s="$SCAN_S" saved_n="$SCAN_N" saved_i="$SCAN_I" saved_out="$SCAN_OUT"
                SCAN_S="$SCAN_LINE"
                SCAN_N=${#SCAN_LINE}
                SCAN_I=0
                SCAN_OUT=""
                scan_expansions_only
                local extra="$SCAN_OUT"
                SCAN_S="$saved_s"
                SCAN_N="$saved_n"
                SCAN_I="$saved_i"
                SCAN_OUT="$saved_out"
                if [ -n "$extra" ]; then
                    SCAN_OUT+=$'\n'"$extra"$'\n'
                fi
            fi
        done
        # EOF before the delimiter: drop it so the loop cannot spin.
        if [ "$closed" -eq 0 ] && scan_peek_heredoc; then
            scan_drop_peeked_heredoc
        fi
    done
}

# Walk a here-doc line looking only for command substitutions.
scan_expansions_only() {
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        local c="${SCAN_S:$SCAN_I:1}"
        local next="${SCAN_S:$((SCAN_I + 1)):1}"
        if [ "$c" = '\\' ]; then
            SCAN_I=$((SCAN_I + 2))
            continue
        fi
        if [ "$c" = '$' ] && [ "$next" = '(' ]; then
            scan_dollar_paren
            continue
        fi
        if [ "$c" = '`' ]; then
            SCAN_I=$((SCAN_I + 1))
            SCAN_OUT+=$'\n'
            scan_code btick
            SCAN_OUT+=$'\n'
            continue
        fi
        SCAN_I=$((SCAN_I + 1))
    done
}

scan_comment_starts() {
    if [ -z "$SCAN_OUT" ]; then
        return 0
    fi
    local last="${SCAN_OUT: -1}"
    case "$last" in
        ' '|$'\t'|$'\n'|'|'|'&'|';') return 0 ;;
        *) return 1 ;;
    esac
}

# end_type: eof | paren | btick
scan_code() {
    local end_type="$1"
    local depth=0
    if [ "$end_type" = "paren" ]; then
        depth=1
    fi
    SCAN_DEPTH=$((SCAN_DEPTH + 1))

    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        local c="${SCAN_S:$SCAN_I:1}"
        local next="${SCAN_S:$((SCAN_I + 1)):1}"

        if [ "$end_type" = "btick" ] && [ "$c" = '`' ]; then
            SCAN_I=$((SCAN_I + 1))
            SCAN_DEPTH=$((SCAN_DEPTH - 1))
            return 0
        fi
        if [ "$end_type" = "paren" ] && [ "$c" = ')' ]; then
            depth=$((depth - 1))
            SCAN_I=$((SCAN_I + 1))
            if [ "$depth" -eq 0 ]; then
                SCAN_DEPTH=$((SCAN_DEPTH - 1))
                return 0
            fi
            scan_append_literal_gap
            continue
        fi
        if [ "$end_type" = "paren" ] && [ "$c" = '(' ]; then
            depth=$((depth + 1))
            scan_append_literal_gap
            SCAN_I=$((SCAN_I + 1))
            continue
        fi

        if [ "$c" = '\\' ]; then
            SCAN_I=$((SCAN_I + 2))
            continue
        fi
        if [ "$c" = '$' ] && [ "$next" = "'" ]; then
            # $'...' is a quoted literal.
            SCAN_I=$((SCAN_I + 2))
            scan_skip_single
            continue
        fi
        if [ "$c" = '$' ] && [ "$next" = '(' ]; then
            scan_dollar_paren
            continue
        fi
        if [ "$c" = '`' ]; then
            SCAN_I=$((SCAN_I + 1))
            SCAN_OUT+=$'\n'
            scan_code btick
            SCAN_OUT+=$'\n'
            continue
        fi
        if [ "$c" = "'" ]; then
            SCAN_I=$((SCAN_I + 1))
            scan_skip_single
            continue
        fi
        if [ "$c" = '"' ]; then
            SCAN_I=$((SCAN_I + 1))
            scan_double
            continue
        fi
        if [ "$c" = '#' ] && scan_comment_starts; then
            while [ "$SCAN_I" -lt "$SCAN_N" ] && [ "${SCAN_S:$SCAN_I:1}" != $'\n' ]; do
                SCAN_I=$((SCAN_I + 1))
            done
            continue
        fi
        if [ "$c" = '<' ] && [ "$next" = '<' ]; then
            scan_parse_heredoc_op
            continue
        fi
        if [ "$c" = $'\n' ]; then
            SCAN_OUT+=$'\n'
            SCAN_I=$((SCAN_I + 1))
            scan_consume_heredocs
            continue
        fi
        case "$c" in
            '('|')'|'{'|'}')
                scan_append_literal_gap
                SCAN_I=$((SCAN_I + 1))
                ;;
            *)
                SCAN_OUT+="$c"
                SCAN_I=$((SCAN_I + 1))
                ;;
        esac
    done
    SCAN_DEPTH=$((SCAN_DEPTH - 1))
}

trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

segment_command_words() {
    WORDS=()
    local seg="$1"
    local old_ifs=$IFS
    set -f
    IFS=$' \t'
    # shellcheck disable=SC2206
    WORDS=($seg)
    set +f
    IFS=$old_ifs
}

word_is_assignment() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]
}

# Print the offending simple command, or nothing when the segment is allowed.
classify_segment() {
    local seg
    seg=$(trim_ws "$1")
    [ -z "$seg" ] && return 0
    segment_command_words "$seg"
    local i=0
    local n=${#WORDS[@]}
    local override=0
    local w base

    while [ "$i" -lt "$n" ]; do
        w="${WORDS[$i]}"
        if word_is_assignment "$w"; then
            if [ "$w" = "SAFE_INSTALL_OVERRIDE=1" ]; then
                override=1
            fi
            i=$((i + 1))
            continue
        fi
        base=$(basename "$w")
        case "$base" in
            sudo)
                i=$((i + 1))
                while [ "$i" -lt "$n" ]; do
                    w="${WORDS[$i]}"
                    case "$w" in
                        --) i=$((i + 1)); break ;;
                        -u|-g|-p|-C) i=$((i + 2)); continue ;;
                        -*) i=$((i + 1)); continue ;;
                        *) break ;;
                    esac
                done
                continue
                ;;
            command|exec|time|nohup|nice|stdbuf)
                i=$((i + 1))
                while [ "$i" -lt "$n" ] && [[ "${WORDS[$i]}" == -* ]]; do
                    i=$((i + 1))
                done
                continue
                ;;
            env)
                i=$((i + 1))
                while [ "$i" -lt "$n" ]; do
                    w="${WORDS[$i]}"
                    case "$w" in
                        --) i=$((i + 1)); break ;;
                        -u|-S) i=$((i + 2)); continue ;;
                        -*) i=$((i + 1)); continue ;;
                        *) break ;;
                    esac
                done
                continue
                ;;
            *)
                break
                ;;
        esac
    done

    if [ "$override" -eq 1 ]; then
        return 0
    fi
    [ "$i" -ge "$n" ] && return 0

    base=$(basename "${WORDS[$i]}")
    case "$base" in
        socket|npm-safe-install) return 0 ;;
    esac

    local rest_start=$((i + 1))
    if [[ "$base" =~ ^python([0-9]+(\.[0-9]+)*)?$ ]]; then
        local j=$rest_start
        while [ "$j" -lt "$n" ]; do
            if [ "${WORDS[$j]}" = "-m" ] && [ $((j + 1)) -lt "$n" ] && [ "${WORDS[$((j + 1))]}" = "pip" ]; then
                classify_manager pip "$((j + 2))" "$n" "$seg"
                return $?
            fi
            j=$((j + 1))
        done
        return 0
    fi

    case "$base" in
        npm|npx|pnpm|yarn|pip|pip3|pipx|uv|cargo|gem|go|poetry|pipenv)
            classify_manager "$base" "$rest_start" "$n" "$seg"
            return $?
            ;;
        *)
            return 0
            ;;
    esac
}

args_include() {
    local needle="$1"
    local start="$2"
    local n="$3"
    local k=$start
    while [ "$k" -lt "$n" ]; do
        if [ "${WORDS[$k]}" = "$needle" ]; then
            return 0
        fi
        k=$((k + 1))
    done
    return 1
}

classify_manager() {
    local manager="$1"
    local start="$2"
    local n="$3"
    local seg="$4"
    local sub=""
    if [ "$start" -lt "$n" ]; then
        sub="${WORDS[$start]}"
    fi

    case "$manager" in
        npm)
            case "$sub" in
                ci) return 0 ;;
                install|i|add|create)
                    if args_include "--offline" "$start" "$n" || args_include "--prefer-offline" "$start" "$n"; then
                        return 0
                    fi
                    printf '%s\n' "$seg"
                    return 1
                    ;;
                exec)
                    if args_include "--offline" "$start" "$n"; then
                        return 0
                    fi
                    printf '%s\n' "$seg"
                    return 1
                    ;;
                *) return 0 ;;
            esac
            ;;
        npx)
            # Preserve the historical rule: block only when the first argument
            # does not look like a flag (`npx cowsay`, not `npx --yes cowsay`).
            if [ -n "$sub" ] && [ "${sub#-}" = "$sub" ]; then
                printf '%s' "$seg"
                return 1
            fi
            return 0
            ;;
        pnpm)
            case "$sub" in
                add)
                    printf '%s\n' "$seg"
                    return 1
                    ;;
                install)
                    if args_include "--frozen-lockfile" "$start" "$n"; then
                        return 0
                    fi
                    printf '%s\n' "$seg"
                    return 1
                    ;;
                *) return 0 ;;
            esac
            ;;
        yarn)
            case "$sub" in
                add)
                    printf '%s\n' "$seg"
                    return 1
                    ;;
                install)
                    if args_include "--frozen-lockfile" "$start" "$n"; then
                        return 0
                    fi
                    # `yarn install` without a frozen lockfile was previously allowed.
                    return 0
                    ;;
                *) return 0 ;;
            esac
            ;;
        pip|pip3)
            if [ "$sub" = "install" ]; then
                if args_include "--no-deps" "$start" "$n"; then
                    return 0
                fi
                printf '%s' "$seg"
                return 1
            fi
            return 0
            ;;
        pipx)
            if [ "$sub" = "install" ]; then
                printf '%s' "$seg"
                return 1
            fi
            return 0
            ;;
        uv)
            if [ "$sub" = "add" ]; then
                printf '%s' "$seg"
                return 1
            fi
            if [ "$sub" = "pip" ] && [ $((start + 1)) -lt "$n" ] && [ "${WORDS[$((start + 1))]}" = "install" ]; then
                printf '%s' "$seg"
                return 1
            fi
            if [ "$sub" = "sync" ]; then
                return 0
            fi
            return 0
            ;;
        cargo|gem)
            if [ "$sub" = "install" ]; then
                printf '%s' "$seg"
                return 1
            fi
            return 0
            ;;
        go)
            # Historical rule: `go install <module>` (argument starts with a letter).
            # `go install .` stays allowed.
            if [ "$sub" = "install" ] && [ $((start + 1)) -lt "$n" ]; then
                local target="${WORDS[$((start + 1))]}"
                if [[ "$target" =~ ^[a-zA-Z] ]]; then
                    printf '%s\n' "$seg"
                    return 1
                fi
            fi
            return 0
            ;;
        poetry)
            return 0
            ;;
        pipenv)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

executed_text() {
    SCAN_S="$1"
    SCAN_N=${#SCAN_S}
    SCAN_I=0
    SCAN_OUT=""
    SCAN_DEPTH=0
    H_DELIM=()
    H_QUOTED=()
    H_TABS=()
    H_LEVEL=()
    scan_code eof
    # A here-doc opened on the last line still has a body after EOF.
    if scan_has_heredoc; then
        scan_consume_heredocs
    fi
    printf '%s' "$SCAN_OUT"
}

split_segments() {
    SEGMENTS=()
    local s="$1"
    local cur=""
    local i=0
    local n=${#s}
    while [ "$i" -lt "$n" ]; do
        local two="${s:$i:2}"
        local c="${s:$i:1}"
        if [ "$two" = "&&" ] || [ "$two" = "||" ]; then
            SEGMENTS+=("$cur")
            cur=""
            i=$((i + 2))
            continue
        fi
        case "$c" in
            ';'|'|'|'&'|$'\n')
                SEGMENTS+=("$cur")
                cur=""
                i=$((i + 1))
                ;;
            *)
                cur+="$c"
                i=$((i + 1))
                ;;
        esac
    done
    SEGMENTS+=("$cur")
}

set +e
blocked_action=$(
    text=$(executed_text "$cmd")
    split_segments "$text"
    for seg in "${SEGMENTS[@]+"${SEGMENTS[@]}"}"; do
        if ! action=$(classify_segment "$seg"); then
            printf '%s' "$action"
            exit 0
        fi
    done
    exit 0
)
scan_status=$?
set -e
# A parser crash must not fail open. The subshell exits 0 on both allow and block.
if [ "$scan_status" -ne 0 ]; then
    echo "🛡️  Supply-chain gate: could not parse the command, refusing it." >&2
    exit 2
fi

if [ -n "$blocked_action" ]; then
    cat >&2 <<EOF
🛡️  Supply-chain gate: direct package install blocked.

  Parsed action: $blocked_action

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

Quoted text, comments, and here-document bodies are not installs. The gate
names the parsed executable action above, not a mention inside a string.

Policy: CrossCheck/docs/rules/trust-model.md § Supply Chain
EOF
    exit 2
fi

exit 0
