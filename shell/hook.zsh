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

# ---------------------------------------------------------------------------
# Completing the command NAME itself
#
# The dispatch above only runs after a line is submitted, so it cannot help
# with 'kubect<Tab>': zsh builds command candidates from PATH, and a command
# that only lives inside a box is not there.
#
# This is a completer rather than a compdef override: it ADDS the indexed
# names and then deliberately returns non-zero, so every completer configured
# after it still contributes its own candidates. Cost is one awk pass over a
# flat TSV — completing a name never touches a container.
# ---------------------------------------------------------------------------

# Extending the -command- context, rather than adding a completer to the
# zstyle. A completer was the obvious route and it does NOT work: one that
# adds candidates and returns non-zero (so the remaining completers still
# contribute) has its matches thrown away whenever every completer ends up
# returning non-zero, which is exactly what happens when the name exists only
# inside a box. Extending -command- keeps both halves: whatever completed
# command names before us still runs, and ours are appended.
#
# Requires compinit to have run already, which is the case when this file is
# sourced near the end of .zshrc as documented.

if (( ${+_comps} )); then
    if [[ ${_comps[-command-]:-} != _sora_command_names ]]; then
        typeset -g __sora_prev_command_comp=${_comps[-command-]:-}
    fi

    _sora_command_names() {
        local index="${XDG_CACHE_HOME:-$HOME/.cache}/sora/index"
        local -a cmds
        [[ -r $index ]] && cmds=(${(f)"$(awk -F '\t' 'NF { print $1 }' $index)"})
        [[ -n ${__sora_prev_command_comp:-} ]] && $__sora_prev_command_comp "$@"
        (( $#cmds )) && compadd -a cmds
    }
    compdef _sora_command_names -command-
fi

# ---------------------------------------------------------------------------
# Completing ARGUMENTS of a box command
#
# 'sora reindex' copies each box's own completion functions to
# ~/.local/share/sora/completions/zsh, one winner per command. Adding that
# directory to $fpath is only half the job: this file is meant to be sourced
# near the END of .zshrc, so compinit has already run and would never look at
# a newly added entry. Registering each function explicitly is what makes it
# work without forcing a second compinit (which is slow and can surprise
# frameworks).
# ---------------------------------------------------------------------------

() {
    local dir="${XDG_DATA_HOME:-$HOME/.local/share}/sora/completions/zsh"
    [[ -d $dir ]] || return 0
    (( ${fpath[(I)$dir]} )) || fpath=("$dir" $fpath)
    (( ${+functions[compdef]} )) || return 0
    local f cmd
    for f in "$dir"/_*(N); do
        cmd=${${f:t}#_}
        # Never shadow a completion the user already has for this command.
        (( ${+_comps[$cmd]} )) && continue
        autoload -Uz "${f:t}"
        compdef "${f:t}" "$cmd"
    done
}
