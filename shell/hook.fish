# sora — late resolution of distrobox commands (fish hook).
#
# Installed as ~/.config/fish/conf.d/zz-sora.fish (or sourced manually).
# Note: fish loads conf.d BEFORE config.fish. If some other tool defines
# fish_command_not_found in config.fish, source this file at the END of
# config.fish instead, so sora can chain to it.
#
# Known fish limitation: fish itself forces the reported exit status of an
# unknown command to 127, even when the handler ran the command successfully.
# The command still runs and prints normally; only $status lies.

# Capture a pre-existing handler exactly once — never capture ourselves, and
# never capture fish's own do-nothing default handler (sora's fallback message
# is strictly more useful than it).
if functions -q fish_command_not_found
    set -l __sora_prev_body (functions fish_command_not_found | string collect)
    if not string match -q '*__sora*' $__sora_prev_body
        and not string match -q '*__fish_default_command_not_found_handler*' $__sora_prev_body
        functions -c fish_command_not_found __sora_prev_handle_fish
    end
end

# Completion for box commands, as far as fish can go.
#
# 'sora reindex' copies each box's own completion files to
# ~/.local/share/sora/completions/fish; putting that directory on
# $fish_complete_path is all fish needs to pick them up.
#
# The hard limit is fish itself: inside a command substitution it discards the
# output of an unknown command even when fish_command_not_found runs and
# prints (bash returns the value there; fish returns nothing). So the STATIC
# half of a completion file works, and any part that shells out to the command
# to compute candidates silently yields nothing. Export the command with
# 'sora anxious' when you need the dynamic half: a real wrapper in PATH is not
# an unknown command, so nothing gets discarded. See README.
set -l __sora_comp_dir $HOME/.local/share/sora/completions/fish
if set -q XDG_DATA_HOME
    set __sora_comp_dir $XDG_DATA_HOME/sora/completions/fish
end
if test -d "$__sora_comp_dir"
    if not contains -- $__sora_comp_dir $fish_complete_path
        set -p fish_complete_path $__sora_comp_dir
    end
end

function __sora_container_exists
    if command -q podman
        command podman container exists $argv[1] 2>/dev/null; and return 0
    end
    if command -q docker
        command docker container inspect $argv[1] >/dev/null 2>&1; and return 0
    end
    return 1
end

function fish_command_not_found
    set -l cmd $argv[1]
    set -l cache_dir $HOME/.cache
    if set -q XDG_CACHE_HOME
        set cache_dir $XDG_CACHE_HOME
    end
    set -l index $cache_dir/sora/index
    set -l box
    if test -r "$index"
        set box (awk -F '\t' -v c=$cmd '$1 == c { print $2; exit }' $index)
    end
    if test -n "$box"
        if __sora_container_exists $box
            distrobox enter --name $box -- $argv
            return $status
        end
        echo "sora: '$cmd' is indexed to box '$box', but that container no longer exists." >&2
        echo "sora: run 'sora reindex' to refresh the index." >&2
        return 127
    end
    if functions -q __sora_prev_handle_fish
        __sora_prev_handle_fish $argv
        return $status
    end
    echo "fish: Unknown command: $cmd" >&2
    if test -s "$index"
        echo "sora: not found in any box either." >&2
    else
        echo "sora: no boxes indexed - create one with 'sora box create'." >&2
    end
    return 127
end
