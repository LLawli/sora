# sora — late resolution of distrobox commands (bash hook).
#
# Source this file from ~/.bashrc, AFTER anything else that defines
# command_not_found_handle (mise, PackageKit, Debian's command-not-found...):
# sora saves the previous handler and delegates to it whenever it cannot
# resolve a command itself, so nothing already on your system breaks.
#
# The lookup below never touches a container: it is a single awk pass over a
# flat TSV file. A typo costs microseconds, not a container wake-up.

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

__sora_dispatch() {
    local cmd=$1 box index
    box=$(__sora_lookup "$cmd")
    if [ -n "$box" ]; then
        if __sora_container_exists "$box"; then
            distrobox enter --name "$box" -- "$@"
            return $?
        fi
        printf "sora: '%s' is indexed to box '%s', but that container no longer exists.\n" "$cmd" "$box" >&2
        printf "sora: run 'sora reindex' to refresh the index.\n" >&2
        return 127
    fi
    # Not ours: hand over to whatever handler was there before us.
    if declare -f __sora_prev_handle_bash >/dev/null 2>&1; then
        __sora_prev_handle_bash "$@"
        return $?
    fi
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
