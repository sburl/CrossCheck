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
# substitutions and process substitutions are, because the shell runs them.
# Echo, printf, and other text commands may mention an install. Any
# other command is blocked when its arguments run a package manager, so
# wrappers do not need their own flag lists. A quoted script passed to
# bash -c or eval is not re-parsed; GIT-8227 tracks that.
#
# Exit codes (Claude Code contract):
#   0 = allow
#   2 = block, surface stderr back to the model so it self-corrects
set -u
shopt -s extglob

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" != "Bash" ] && exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

SCAN_CHARS=()
SCAN_N=0
SCAN_I=0
SCAN_OUT=""
SCAN_BUF=()
SCAN_DEPTH=0
H_DELIM=()
H_QUOTED=()
H_TABS=()
H_LEVEL=()
EXP_SNIPS=()

scan_emit() {
    SCAN_BUF+=("$1")
}

scan_flush() {
    if [ "${#SCAN_BUF[@]}" -eq 0 ]; then
        return 0
    fi
    local chunk
    # printf -v keeps trailing newlines. Command substitution would strip them.
    printf -v chunk '%s' "${SCAN_BUF[@]}"
    SCAN_OUT+="$chunk"
    SCAN_BUF=()
}

scan_reset_out() {
    SCAN_OUT=""
    SCAN_BUF=()
}

scan_append_literal_gap() {
    scan_emit " "
}

scan_load() {
    local s="$1"
    SCAN_CHARS=()
    local n=${#s}
    if [ "$n" -gt 0 ]; then
        if [ "$n" -lt 2000 ]; then
            local i=0
            while [ "$i" -lt "$n" ]; do
                SCAN_CHARS[i]="${s:$i:1}"
                i=$((i + 1))
            done
        else
            local c
            while IFS= read -r -n1 c || [ -n "$c" ]; do
                if [ -z "$c" ]; then
                    SCAN_CHARS+=($'\n')
                else
                    SCAN_CHARS+=("$c")
                fi
            done < <(printf '%s' "$s")
        fi
    fi
    SCAN_N=$n
    # Past-the-end peeks must exist under set -u.
    SCAN_CHARS+=("" "" "")
}

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
        if [ "${SCAN_CHARS[$SCAN_I]}" = "'" ]; then
            SCAN_I=$((SCAN_I + 1))
            return 0
        fi
        SCAN_I=$((SCAN_I + 1))
    done
}

# $'...' treats \' as a literal quote. A plain quote walk would swallow the rest.
scan_skip_dollar_single() {
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        if [ "${SCAN_CHARS[$SCAN_I]}" = $'\\' ]; then
            SCAN_I=$((SCAN_I + 2))
            continue
        fi
        if [ "${SCAN_CHARS[$SCAN_I]}" = "'" ]; then
            SCAN_I=$((SCAN_I + 1))
            return 0
        fi
        SCAN_I=$((SCAN_I + 1))
    done
}

scan_double() {
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        local c="${SCAN_CHARS[$SCAN_I]}"
        local next="${SCAN_CHARS[$((SCAN_I + 1))]}"
        if [ "$c" = '"' ]; then
            SCAN_I=$((SCAN_I + 1))
            return 0
        fi
        if [ "$c" = $'\\' ]; then
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
            scan_emit $'\n'
            scan_code btick
            scan_emit $'\n'
            continue
        fi
        SCAN_I=$((SCAN_I + 1))
    done
}

scan_dollar_paren() {
    local third="${SCAN_CHARS[$((SCAN_I + 2))]}"
    if [ "$third" = '(' ]; then
        # $(( arithmetic )). Command substitutions inside it still run.
        SCAN_I=$((SCAN_I + 3))
        scan_arith
        return 0
    fi
    SCAN_I=$((SCAN_I + 2))
    scan_emit $'\n'
    scan_code paren
    scan_emit $'\n'
}

# depth starts at 2 because the caller already consumed "$((".
# Quotes do not hide expansions here: bash runs them before evaluating.
scan_arith() {
    local depth=2
    while [ "$SCAN_I" -lt "$SCAN_N" ] && [ "$depth" -gt 0 ]; do
        local c="${SCAN_CHARS[$SCAN_I]}"
        local next="${SCAN_CHARS[$((SCAN_I + 1))]}"
        if [ "$c" = $'\\' ]; then
            SCAN_I=$((SCAN_I + 2))
            continue
        fi
        if [ "$c" = '$' ] && [ "$next" = '(' ]; then
            scan_dollar_paren
            continue
        fi
        if [ "$c" = '`' ]; then
            SCAN_I=$((SCAN_I + 1))
            scan_emit $'\n'
            scan_code btick
            scan_emit $'\n'
            continue
        fi
        if [ "$c" = '(' ]; then
            depth=$((depth + 1))
        elif [ "$c" = ')' ]; then
            depth=$((depth - 1))
        fi
        SCAN_I=$((SCAN_I + 1))
    done
}

scan_parse_heredoc_op() {
    # SCAN_I points at the first '<'.
    SCAN_I=$((SCAN_I + 2))
    local tabs=0
    if [ "${SCAN_CHARS[$SCAN_I]}" = '-' ]; then
        tabs=1
        SCAN_I=$((SCAN_I + 1))
    fi
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        local c="${SCAN_CHARS[$SCAN_I]}"
        case "$c" in
            ' '|$'\t') SCAN_I=$((SCAN_I + 1)) ;;
            *) break ;;
        esac
    done
    local quoted=0
    local delim=""
    local c="${SCAN_CHARS[$SCAN_I]}"
    if [ "$c" = "'" ] || [ "$c" = '"' ]; then
        quoted=1
        local q="$c"
        SCAN_I=$((SCAN_I + 1))
        while [ "$SCAN_I" -lt "$SCAN_N" ] && [ "${SCAN_CHARS[$SCAN_I]}" != "$q" ]; do
            delim+="${SCAN_CHARS[$SCAN_I]}"
            SCAN_I=$((SCAN_I + 1))
        done
        if [ "${SCAN_CHARS[$SCAN_I]}" = "$q" ]; then
            SCAN_I=$((SCAN_I + 1))
        fi
    else
        while [ "$SCAN_I" -lt "$SCAN_N" ]; do
            c="${SCAN_CHARS[$SCAN_I]}"
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
    while [ "$SCAN_I" -lt "$SCAN_N" ] && [ "${SCAN_CHARS[$SCAN_I]}" != $'\n' ]; do
        SCAN_LINE+="${SCAN_CHARS[$SCAN_I]}"
        SCAN_I=$((SCAN_I + 1))
    done
    if [ "$SCAN_I" -lt "$SCAN_N" ] && [ "${SCAN_CHARS[$SCAN_I]}" = $'\n' ]; then
        SCAN_I=$((SCAN_I + 1))
    fi
    return 0
}

# Index of the matching close paren. Quotes hide parens; the full scan
# still sees command substitutions inside those quotes.
end_of_parens() {
    local s="$1" j="$2" depth=0 c
    local n=${#s}
    END_POS=$n
    while [ "$j" -lt "$n" ]; do
        c=${s:j:1}
        if [ "$c" = '\' ]; then
            j=$((j + 2))
            continue
        fi
        if [ "$c" = "'" ]; then
            j=$((j + 1))
            while [ "$j" -lt "$n" ] && [ "${s:j:1}" != "'" ]; do
                j=$((j + 1))
            done
            j=$((j + 1))
            continue
        fi
        if [ "$c" = '"' ]; then
            j=$((j + 1))
            while [ "$j" -lt "$n" ] && [ "${s:j:1}" != '"' ]; do
                if [ "${s:j:1}" = '\' ]; then
                    j=$((j + 2))
                    continue
                fi
                j=$((j + 1))
            done
            j=$((j + 1))
            continue
        fi
        if [ "$c" = '(' ]; then
            depth=$((depth + 1))
        elif [ "$c" = ')' ]; then
            depth=$((depth - 1))
            if [ "$depth" -eq 0 ]; then
                END_POS=$j
                return 0
            fi
        fi
        j=$((j + 1))
    done
}

collect_line_commands() {
    local line="$1" i=0 c nxt j len
    local n=${#line}
    while [ "$i" -lt "$n" ]; do
        c=${line:i:1}
        if [ "$c" = '\' ]; then
            i=$((i + 2))
            continue
        fi
        nxt=${line:i+1:1}
        if [ "$c" = '$' ] && [ "$nxt" = '(' ]; then
            end_of_parens "$line" $((i + 1))
            len=$((END_POS - i + 1))
            EXP_SNIPS+=("${line:i:len}")
            i=$((END_POS + 1))
            continue
        fi
        if [ "$c" = '`' ]; then
            j=$((i + 1))
            while [ "$j" -lt "$n" ]; do
                if [ "${line:j:1}" = '\' ]; then
                    j=$((j + 2))
                    continue
                fi
                if [ "${line:j:1}" = '`' ]; then
                    break
                fi
                j=$((j + 1))
            done
            len=$((j - i - 1))
            EXP_SNIPS+=("${line:i+1:len}")
            i=$((j + 1))
            continue
        fi
        i=$((i + 1))
    done
}

flush_pending_expansions() {
    local snip idx=0
    while [ "$idx" -lt "${#EXP_SNIPS[@]}" ]; do
        snip=${EXP_SNIPS[$idx]}
        idx=$((idx + 1))
        scan_flush
        scan_load "$snip"
        SCAN_I=0
        SCAN_DEPTH=0
        H_DELIM=()
        H_QUOTED=()
        H_TABS=()
        H_LEVEL=()
        scan_emit $'\n'
        scan_code eof
        if scan_has_heredoc; then
            scan_consume_heredocs
        fi
        scan_emit $'\n'
    done
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
                # Lines with neither must not snapshot the outer character array.
                case "$SCAN_LINE" in
                    *'$('*|*'`'*) ;;
                    *) continue ;;
                esac
                # Collect the snippet and scan it after the outer walk.
                # Copying SCAN_CHARS once per line is quadratic.
                collect_line_commands "$SCAN_LINE"
            fi
        done
        # EOF before the delimiter: drop it so the loop cannot spin.
        if [ "$closed" -eq 0 ] && scan_peek_heredoc; then
            scan_drop_peeked_heredoc
        fi
    done
}

scan_expansions_only() {
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        local c="${SCAN_CHARS[$SCAN_I]}"
        local next="${SCAN_CHARS[$((SCAN_I + 1))]}"
        if [ "$c" = $'\\' ]; then
            SCAN_I=$((SCAN_I + 2))
            continue
        fi
        if [ "$c" = '$' ] && [ "$next" = '(' ]; then
            scan_dollar_paren
            continue
        fi
        if [ "$c" = '`' ]; then
            SCAN_I=$((SCAN_I + 1))
            scan_emit $'\n'
            scan_code btick
            scan_emit $'\n'
            continue
        fi
        SCAN_I=$((SCAN_I + 1))
    done
}

# '#' starts a comment only at a word boundary. A quote glued on does not.
scan_comment_starts() {
    if [ "$SCAN_I" -eq 0 ]; then
        return 0
    fi
    local prev="${SCAN_CHARS[$((SCAN_I - 1))]}"
    case "$prev" in
        [[:space:]]|'|'|'&'|';'|'('|'<'|'>') return 0 ;;
        *) return 1 ;;
    esac
}

scan_code() {
    local end_type="$1"
    local depth=0
    if [ "$end_type" = "paren" ]; then
        depth=1
    fi
    SCAN_DEPTH=$((SCAN_DEPTH + 1))
    while [ "$SCAN_I" -lt "$SCAN_N" ]; do
        local c="${SCAN_CHARS[$SCAN_I]}"
        local next="${SCAN_CHARS[$((SCAN_I + 1))]}"
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
        if [ "$c" = $'\\' ]; then
            SCAN_I=$((SCAN_I + 2))
            continue
        fi
        if [ "$c" = '$' ] && [ "$next" = "'" ]; then
            SCAN_I=$((SCAN_I + 2))
            scan_skip_dollar_single
            continue
        fi
        if [ "$c" = '$' ] && [ "$next" = '(' ]; then
            scan_dollar_paren
            continue
        fi
        if [ "$c" = '`' ]; then
            SCAN_I=$((SCAN_I + 1))
            scan_emit $'\n'
            scan_code btick
            scan_emit $'\n'
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
            while [ "$SCAN_I" -lt "$SCAN_N" ] && [ "${SCAN_CHARS[$SCAN_I]}" != $'\n' ]; do
                SCAN_I=$((SCAN_I + 1))
            done
            continue
        fi
        if [ "$c" = '<' ] && [ "$next" = '<' ]; then
            scan_parse_heredoc_op
            continue
        fi
        # (( arithmetic command )). bash runs expansions inside it, quotes too.
        if [ "$c" = '(' ] && [ "$next" = '(' ]; then
            SCAN_I=$((SCAN_I + 2))
            scan_arith
            continue
        fi
        # <(...) and >(...) run. Same as $(...): the inner command is executed.
        if { [ "$c" = '<' ] || [ "$c" = '>' ]; } && [ "$next" = '(' ]; then
            SCAN_I=$((SCAN_I + 2))
            scan_emit $'\n'
            scan_code paren
            scan_emit $'\n'
            continue
        fi
        if [ "$c" = $'\n' ]; then
            scan_emit $'\n'
            SCAN_I=$((SCAN_I + 1))
            scan_consume_heredocs
            continue
        fi
        case "$c" in
            ')')
                # case-arm ')' starts a new simple command: case x in a) pip install
                scan_emit $'\n'
                SCAN_I=$((SCAN_I + 1))
                ;;
            '('|'{'|'}')
                # Own word, so `coproc NAME { ... }` stays distinct from a simple
                # command, and a glued `{pip` still classifies pip.
                scan_emit " $c "
                SCAN_I=$((SCAN_I + 1))
                ;;
            *)
                scan_emit "$c"
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

# Text utilities do not execute their arguments.
prose_command() {
    case "$1" in
        echo|printf|cat|head|tail|less|more|grep|rg|sed|awk|cut|tr|sort|uniq|diff|wc|ls|cd|pwd|true|false|test|'['|':')
            return 0
            ;;
    esac
    return 1
}

# A later manager word is the command a wrapper runs. classify_manager applies
# the historical allow rules (npm ci, offline, frozen lockfile, --no-deps).
scan_trailing_managers() {
    local j="$1" seg="$2" b override=0 nwords=${#WORDS[@]}
    while [ "$j" -lt "$nwords" ]; do
        if [ "${WORDS[$j]}" = "SAFE_INSTALL_OVERRIDE=1" ]; then
            override=1
            j=$((j + 1))
            continue
        fi
        b=${WORDS[$j]##*/}
        case "$b" in
            npm|npx|pnpm|yarn|pip|pip3|pipx|uv|cargo|gem|go|poetry|pipenv)
                if [ "$override" -eq 1 ]; then
                    return 0
                fi
                classify_manager "$b" "$((j + 1))" "$nwords" "$seg"
                if [ "$?" -ne 0 ]; then
                    return 1
                fi
                ;;
        esac
        j=$((j + 1))
    done
    return 0
}

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
        # Keywords are not the executable. Keep walking: `then pip install`.
        # Do not skip `in`; it would eat the words of `for x in a`.
        case "$w" in
            function)
                i=$((i + 2))
                continue
                ;;
            if|then|else|elif|fi|for|do|done|while|until|case|'esac'|select|'!'|'('|')'|'{'|'}'|coproc)
                i=$((i + 1))
                continue
                ;;
        esac
        break
    done
    if [ "$override" -eq 1 ]; then
        return 0
    fi
    [ "$i" -ge "$n" ] && return 0
    base=${WORDS[$i]##*/}
    case "$base" in
        socket|npm-safe-install) return 0 ;;
    esac
    if prose_command "$base"; then
        return 0
    fi
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
    fi
    case "$base" in
        npm|npx|pnpm|yarn|pip|pip3|pipx|uv|cargo|gem|go|poetry|pipenv)
            classify_manager "$base" "$rest_start" "$n" "$seg"
            if [ "$?" -ne 0 ]; then
                return 1
            fi
            ;;
    esac
    scan_trailing_managers "$rest_start" "$seg"
    return $?
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
                    CLASS_ACTION="$seg"
                    return 1
                    ;;
                exec)
                    if args_include "--offline" "$start" "$n"; then
                        return 0
                    fi
                    CLASS_ACTION="$seg"
                    return 1
                    ;;
                *) return 0 ;;
            esac
            ;;
        npx)
            # Preserve the historical rule: block only when the first argument
            # does not look like a flag (`npx cowsay`, not `npx --yes cowsay`).
            if [ -n "$sub" ] && [ "${sub#-}" = "$sub" ]; then
                CLASS_ACTION="$seg"
                return 1
            fi
            return 0
            ;;
        pnpm)
            case "$sub" in
                add)
                    CLASS_ACTION="$seg"
                    return 1
                    ;;
                install)
                    if args_include "--frozen-lockfile" "$start" "$n"; then
                        return 0
                    fi
                    CLASS_ACTION="$seg"
                    return 1
                    ;;
                *) return 0 ;;
            esac
            ;;
        yarn)
            case "$sub" in
                add)
                    CLASS_ACTION="$seg"
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
                CLASS_ACTION="$seg"
                return 1
            fi
            return 0
            ;;
        pipx)
            if [ "$sub" = "install" ]; then
                CLASS_ACTION="$seg"
                return 1
            fi
            return 0
            ;;
        uv)
            if [ "$sub" = "add" ]; then
                CLASS_ACTION="$seg"
                return 1
            fi
            if [ "$sub" = "pip" ] && [ $((start + 1)) -lt "$n" ] && [ "${WORDS[$((start + 1))]}" = "install" ]; then
                CLASS_ACTION="$seg"
                return 1
            fi
            if [ "$sub" = "sync" ]; then
                return 0
            fi
            return 0
            ;;
        cargo|gem)
            if [ "$sub" = "install" ]; then
                CLASS_ACTION="$seg"
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
                    CLASS_ACTION="$seg"
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
    if [ "${GATE_TEST_FAULT:-}" = "1" ]; then
        # Unset on purpose: a scanner fault must not fail open.
        # shellcheck disable=SC2154
        printf '%s' "$GATE_TEST_UNBOUND_SENTINEL" >/dev/null
    fi
    scan_load "$1"
    SCAN_I=0
    scan_reset_out
    SCAN_DEPTH=0
    H_DELIM=()
    H_QUOTED=()
    H_TABS=()
    H_LEVEL=()
    EXP_SNIPS=()
    scan_code eof
    # A here-doc opened on the last line still has a body after EOF.
    if scan_has_heredoc; then
        scan_consume_heredocs
    fi
    flush_pending_expansions
    scan_flush
    printf '%s' "$SCAN_OUT"
}

# Skip the walker when the text cannot name a gated manager. Do not match pipeline/going.
needs_structural_scan() {
    local s="$1"
    local re_named='(npm|npx|pnpm|yarn|pip3|pipx|cargo|poetry|pipenv)'
    local re_pip='(^|[^[:alpha:]])pip([^[:alpha:]]|$)'
    local re_uv='(^|[^[:alpha:]])uv([^[:alpha:]]|$)'
    local re_gem='(^|[^[:alpha:]])gem([^[:alpha:]]|$)'
    local re_go='go[[:space:]]+install'
    [[ "$s" =~ $re_named ]] && return 0
    [[ "$s" =~ $re_pip ]] && return 0
    [[ "$s" =~ $re_uv ]] && return 0
    [[ "$s" =~ $re_gem ]] && return 0
    [[ "$s" =~ $re_go ]] && return 0
    return 1
}

split_segments() {
    SEGMENTS=()
    local s="$1" old i
    # >& and &> are redirects. Hide them so '&' can be a separator.
    s=${s//&>/$'\x01'}
    s=${s//>&/$'\x02'}
    old=$IFS
    IFS=$';|&\n'
    set -f
    # shellcheck disable=SC2206
    SEGMENTS=($s)
    set +f
    IFS=$old
    if [ "${#SEGMENTS[@]}" -eq 0 ]; then
        SEGMENTS=("")
    fi
    for i in "${!SEGMENTS[@]}"; do
        s=${SEGMENTS[$i]}
        s=${s//$'\x01'/&>}
        SEGMENTS[$i]=${s//$'\x02'/'>&'}
    done
}
if ! needs_structural_scan "$cmd"; then
    exit 0
fi
set +e
blocked_action=$(
    text=$(executed_text "$cmd") || exit 1
    split_segments "$text"
    CLASS_ACTION=""
    for seg in "${SEGMENTS[@]+"${SEGMENTS[@]}"}"; do
        CLASS_ACTION=""
        classify_segment "$seg"
        class_status=$?
        if [ "$class_status" -ne 0 ]; then
            if [ -n "$CLASS_ACTION" ]; then
                printf '%s' "$CLASS_ACTION"
                exit 0
            fi
            exit 1
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
