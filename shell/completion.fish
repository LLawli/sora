# sora — completion for the sora CLI itself (fish).
#
# Installed to PREFIX/share/fish/vendor_completions.d/sora.fish. Every
# candidate list is read from a local file, so completing a sora command never
# enters a container.
#
# Note this is completion FOR the sora command, which is a real binary in PATH.
# It is unaffected by fish's limitation around unknown commands that caps
# completion for late-resolved box commands (see README).

function __sora_config_dir
    if set -q XDG_CONFIG_HOME
        echo $XDG_CONFIG_HOME/sora
    else
        echo $HOME/.config/sora
    end
end

function __sora_cache_dir
    if set -q XDG_CACHE_HOME
        echo $XDG_CACHE_HOME/sora
    else
        echo $HOME/.cache/sora
    end
end

function __sora_boxes
    set -l d (__sora_config_dir)/boxes
    test -d $d; or return 0
    for f in $d/*.toml
        test -f $f; and basename $f .toml
    end
end

function __sora_indexed
    set -l i (__sora_cache_dir)/index
    test -r $i; and cut -f1 -- $i
end

function __sora_registry # anxious.list | delegate.list
    set -l f (__sora_config_dir)/$argv[1]
    test -r $f; and cut -f1 -- $f
end

function __sora_no_sub
    set -l t (commandline -opc)
    test (count $t) -eq 1
end

# Top-level commands
complete -c sora -f
complete -c sora -n __sora_no_sub -a box         -d 'Manage boxes'
complete -c sora -n __sora_no_sub -a images      -d 'Show the image alias catalog'
complete -c sora -n __sora_no_sub -a reindex     -d 'Rebuild the command index'
complete -c sora -n __sora_no_sub -a sync        -d 'Alias of reindex'
complete -c sora -n __sora_no_sub -a conflicts   -d 'Commands present in more than one box'
complete -c sora -n __sora_no_sub -a pin         -d 'Force a command to resolve to one box'
complete -c sora -n __sora_no_sub -a which       -d 'How a command would resolve'
complete -c sora -n __sora_no_sub -a anxious     -d 'Export a real wrapper into PATH'
complete -c sora -n __sora_no_sub -a completion  -d 'Tab completion wiring'
complete -c sora -n __sora_no_sub -a hook        -d 'Shell hook installation'
complete -c sora -n __sora_no_sub -a doctor      -d 'Sanity-check the setup'
complete -c sora -n __sora_no_sub -a version     -d 'Print the version'
complete -c sora -n __sora_no_sub -a help        -d 'Show usage'

# box
complete -c sora -n '__fish_seen_subcommand_from box; and not __fish_seen_subcommand_from create list enter rm set-priority' \
    -a 'create list enter rm set-priority'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from enter rm set-priority' \
    -a '(__sora_boxes)'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from create' \
    -l image -x -a 'fedora ubuntu debian arch tumbleweed alpine' -d 'Source image or alias'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from create' \
    -l priority -x -d 'Index priority'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from create' \
    -l pkg-manager -x -a 'dnf5 apt-get pacman zypper apk' -d 'Override detection'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from create' \
    -l no-own-home -d 'Share the host home'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from create' \
    -l no-xdg-links -d 'Skip XDG folder symlinks'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from create' \
    -l hide -r -d 'Mask a path with tmpfs'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from rm' \
    -l yes -d 'Do not ask'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from rm' \
    -l delete-home -d 'Also delete the box home'

# reindex / sync / which
complete -c sora -n '__fish_seen_subcommand_from reindex sync' -a '(__sora_boxes)'
complete -c sora -n '__fish_seen_subcommand_from which' -a '(__sora_indexed)'

# pin
complete -c sora -n '__fish_seen_subcommand_from pin' -a '(__sora_indexed)'
complete -c sora -n '__fish_seen_subcommand_from pin' -l list -d 'List pins'
complete -c sora -n '__fish_seen_subcommand_from pin' -l remove -x -a '(__sora_indexed)' -d 'Remove a pin'

# anxious
complete -c sora -n '__fish_seen_subcommand_from anxious' -a '(__sora_indexed)'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l sudo -d 'Run with sudo inside the container'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l with-completion -d "Also install the tool's completion"
complete -c sora -n '__fish_seen_subcommand_from anxious' -l box -x -a '(__sora_boxes)' -d 'Which box provides it'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l list -d 'List exported wrappers'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l remove -x -a '(__sora_registry anxious.list)' -d 'Remove a wrapper'

# completion
complete -c sora -n '__fish_seen_subcommand_from completion; and not __fish_seen_subcommand_from delegate list remove status' \
    -a 'delegate list remove status'
complete -c sora -n '__fish_seen_subcommand_from completion; and __fish_seen_subcommand_from delegate' \
    -a '(__sora_indexed)'
complete -c sora -n '__fish_seen_subcommand_from completion; and __fish_seen_subcommand_from delegate' \
    -l box -x -a '(__sora_boxes)' -d 'Which box answers the Tab'
complete -c sora -n '__fish_seen_subcommand_from completion; and __fish_seen_subcommand_from remove' \
    -a '(__sora_registry delegate.list)'

# hook
complete -c sora -n '__fish_seen_subcommand_from hook; and not __fish_seen_subcommand_from install status print' \
    -a 'install status print'
complete -c sora -n '__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from install print' \
    -a 'bash zsh fish'
