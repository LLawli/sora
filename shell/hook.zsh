# sora — late resolution of distrobox commands (zsh hook).
#
# Source this file from ~/.zshrc, AFTER anything else that defines
# command_not_found_handler: sora saves the previous handler and delegates to
# it whenever it cannot resolve a command itself.

# Capture a pre-existing handler exactly once — never capture ourselves.
if (( ${+functions[command_not_found_handler]} )); then
    case ${functions[command_not_found_handler]} in
        *__sora_dispatch*) ;;
        *) functions[__sora_prev_handle_zsh]=${functions[command_not_found_handler]} ;;
    esac
fi

__sora_container_exists() {
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
    [[ -r $index ]] || return 1
    awk -F '\t' -v c="$1" '$1 == c { print $2; exit }' "$index"
}

# True while a completion is running. Completion scripts routinely shell out
# to the command itself (every cobra/clap tool does, on every Tab), and for a
# box command that shell-out lands in the dispatch below. Candidates are read
# from STDOUT, which stays clean — but distrobox's setup banner and our own
# warnings go to STDERR, straight onto the line the user is typing.
# $compstate exists only inside completion widgets; COMP_LINE covers users who
# run bash completion scripts through bashcompinit.
__sora_in_completion() { (( ${+compstate} )) || [[ -n ${COMP_LINE+x} ]] }

__sora_dispatch() {
    local cmd=$1 box index
    box=$(__sora_lookup "$cmd")
    if [[ -n $box ]]; then
        if __sora_container_exists "$box"; then
            if __sora_in_completion; then
                distrobox enter --name "$box" -- "$@" 2>/dev/null
            else
                distrobox enter --name "$box" -- "$@"
            fi
            return $?
        fi
        __sora_in_completion && return 127
        print -u2 "sora: '$cmd' is indexed to box '$box', but that container no longer exists."
        print -u2 "sora: run 'sora reindex' to refresh the index."
        return 127
    fi
    if (( ${+functions[__sora_prev_handle_zsh]} )); then
        __sora_prev_handle_zsh "$@"
        return $?
    fi
    __sora_in_completion && return 127
    print -u2 "zsh: command not found: $cmd"
    index="${XDG_CACHE_HOME:-$HOME/.cache}/sora/index"
    if [[ -s $index ]]; then
        print -u2 "sora: not found in any box either."
    else
        print -u2 "sora: no boxes indexed - create one with 'sora box create'."
    fi
    return 127
}

command_not_found_handler() {
    __sora_dispatch "$@"
}


