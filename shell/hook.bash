# sora — late resolution of distrobox commands (bash hook).
#
# Source this file from ~/.bashrc, AFTER anything else that defines
# command_not_found_handle (mise, PackageKit, Debian's command-not-found...):
# sora saves the previous handler and delegates to it whenever it cannot
# resolve a command itself, so nothing already on your system breaks.
#
# The lookup below never touches a container: it is a single awk pass over a
# flat TSV file. A typo costs microseconds, not a container wake-up.

# Defend late resolution against bash's command hash: a binary removed after
# being hashed (e.g. 'brew uninstall neovim') otherwise fails forever with
# "No such file or directory" at the OLD path — PATH search never re-runs,
# so the command-not-found hook never gets a chance. With checkhash, bash
# re-verifies hashed paths and falls back to a fresh PATH search.
shopt -s checkhash 2>/dev/null || true

# Capture a pre-existing handler exactly once — and never capture ourselves
# (re-sourcing this file must not create an infinite delegation loop).
if declare -f command_not_found_handle >/dev/null 2>&1; then
    if ! declare -f command_not_found_handle | grep -q __sora_dispatch; then
        eval "$(declare -f command_not_found_handle |
            sed '1s/^command_not_found_handle/__sora_prev_handle_bash/')"
    fi
fi

__sora_container_exists() {
    # Cheap existence check so a stale index never triggers distrobox's
    # "create it now?" prompt from a random typed command.
    if command -v podman >/dev/null 2>&1; then
        podman container exists "$1" 2>/dev/null && return 0
    fi
    if command -v docker >/dev/null 2>&1; then
        docker container inspect "$1" >/dev/null 2>&1 && return 0
    fi
    return 1
}

__sora_lookup() {
    local index="${XDG_CACHE_HOME:-$HOME/.cache}/sora/index"
    [ -r "$index" ] || return 1
    awk -F '\t' -v c="$1" '$1 == c { print $2; exit }' "$index"
}

# Bash defines COMP_LINE while a completion function runs. Completion scripts
# routinely shell out to the command itself (every cobra/clap tool does, on
# every Tab), and for a box command that shell-out lands here. The candidate
# list is read from STDOUT, which stays clean — but distrobox's setup banner
# and our own warnings go to STDERR, straight onto the line the user is
# typing. Nothing we print mid-Tab is actionable, so this path stays quiet.
__sora_in_completion() { [ -n "${COMP_LINE+x}" ]; }

__sora_dispatch() {
    local cmd=$1 box index
    box=$(__sora_lookup "$cmd")
    if [ -n "$box" ]; then
        if __sora_container_exists "$box"; then
            if __sora_in_completion; then
                distrobox enter --name "$box" -- "$@" 2>/dev/null
            else
                distrobox enter --name "$box" -- "$@"
            fi
            return $?
        fi
        __sora_in_completion && return 127
        printf "sora: '%s' is indexed to box '%s', but that container no longer exists.\n" "$cmd" "$box" >&2
        printf "sora: run 'sora reindex' to refresh the index.\n" >&2
        return 127
    fi
    # Not ours: hand over to whatever handler was there before us.
    if declare -f __sora_prev_handle_bash >/dev/null 2>&1; then
        __sora_prev_handle_bash "$@"
        return $?
    fi
    __sora_in_completion && return 127
    printf 'bash: %s: command not found\n' "$cmd" >&2
    index="${XDG_CACHE_HOME:-$HOME/.cache}/sora/index"
    if [ -s "$index" ]; then
        printf 'sora: not found in any box either.\n' >&2
    else
        printf "sora: no boxes indexed - create one with 'sora box create'.\n" >&2
    fi
    return 127
}

command_not_found_handle() {
    __sora_dispatch "$@"
}

# ---------------------------------------------------------------------------
# Completing the command NAME itself
#
# The dispatch above only ever runs AFTER a full command line is submitted, so
# it can do nothing for 'kubect<Tab>': bash builds that candidate list from
# PATH, and a command that only lives inside a box is not there. 'complete -I'
# (bash 5.0+) hooks the INITIAL word of a line, which is exactly the gap.
#
# Cost is the same single awk pass over a flat TSV that a miss costs, so this
# keeps the project invariant intact: completing a name NEVER touches a
# container. Only the argument completion of an actual box command does.
# ---------------------------------------------------------------------------

if [ "${BASH_VERSINFO[0]:-0}" -ge 5 ]; then
    # Chain to a pre-existing initial-word completion the same way we chain to
    # a pre-existing not-found handler: capture once, never capture ourselves.
    # Only the '-F function' form can be chained; a '-C command' one is left
    # alone (overwriting it would silently break whatever installed it).
    # 'complete -p -I' prints it as 'complete -F <func> -I', so match on -F
    # and not on argument order.
    __sora_prev_initial=$(complete -p -I 2>/dev/null |
        sed -n 's/^complete .*-F \([^ ]*\).*/\1/p')
    case $__sora_prev_initial in
        __sora_complete_initial|'') __sora_prev_initial='' ;;
    esac

    __sora_complete_initial() {
        local cur index prev=()
        cur=${COMP_WORDS[COMP_CWORD]}
        index="${XDG_CACHE_HOME:-$HOME/.cache}/sora/index"

        if [ -n "$__sora_prev_initial" ] &&
           declare -f "$__sora_prev_initial" >/dev/null 2>&1; then
            COMPREPLY=()
            "$__sora_prev_initial" "$@"
            prev=("${COMPREPLY[@]}")
        fi

        # compgen -c reproduces bash's own list (PATH, aliases, functions,
        # builtins, keywords); the awk pass adds the boxes. sort -u because a
        # command can legitimately exist both on the host and in a box, and a
        # duplicated candidate would be shown twice.
        mapfile -t COMPREPLY < <(
            {
                [ ${#prev[@]} -gt 0 ] && printf '%s\n' "${prev[@]}"
                compgen -c -- "$cur"
                [ -r "$index" ] && awk -F '\t' -v p="$cur" \
                    'substr($1, 1, length(p)) == p { print $1 }' "$index"
            } | sort -u
        )
    }
    complete -I -F __sora_complete_initial
fi


