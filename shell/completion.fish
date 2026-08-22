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

# Flatpak application IDs, read from ~/.var/app rather than from 'flatpak list'.
# That directory is a glob with no process behind it, and it is the same place
# 'provide pkcs11' looks. An app installed but never run has no directory yet
# and so is not offered; typing its ID still works, which is the right trade
# for a Tab that must not fork.
function __sora_flatpak_apps
    set -l d $HOME/.var/app
    test -d $d; or return 0
    for f in $d/*
        test -d $f; and basename $f
    end
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
complete -c sora -n __sora_no_sub -a provide     -d 'Publish a box resource at a host integration point'
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
    -l additional-flags -x -d 'Flags for the container manager'
complete -c sora -n '__fish_seen_subcommand_from box; and __fish_seen_subcommand_from create' \
    -l nvidia -d 'Inject the host NVIDIA driver'
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
# Export by path, under a chosen name. Both take a value, so both need -x;
# neither offers candidates, because an in-box path is exactly what the host
# filesystem must not suggest.
complete -c sora -n '__fish_seen_subcommand_from anxious' -l path -x -d 'Absolute path to a binary INSIDE the box'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l as -x -d 'Export it under this name'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l force -d 'Shadow a host binary of the same name'
# Desktop entry. Every value-taking flag below needs -x: without it fish
# treats the flag as boolean and its value falls through to the generic rule,
# which offers filenames.
complete -c sora -n '__fish_seen_subcommand_from anxious' -l desktop -d 'Also write a .desktop entry'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l name -x -d 'Name shown in the menu'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l generic-name -x -d 'Generic name, e.g. Web Browser'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l comment -x -d 'One-line description'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l icon -x -d 'Icon name inside the box'
# The semicolons must be backslash-escaped even inside quotes: fish parses the
# -a list as script, so a bare ';' ends the token and 'Network;WebBrowser;'
# would be offered as two useless halves.
complete -c sora -n '__fish_seen_subcommand_from anxious' -l categories -x \
    -a 'Network\;WebBrowser\; Development\; Graphics\; AudioVideo\; Office\; Game\; System\; Utility\;' \
    -d 'Menu categories'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l mime -x -d 'MimeType list'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l keywords -x -d 'Search keywords'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l wmclass -x -d 'StartupWMClass of the app window'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l terminal -d 'The app runs in a terminal'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l browser -d 'Fill in web-browser MimeType/categories'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l default-browser -d 'Make it the default http handler'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l detect-wmclass -d 'Start the app once to read its window class'
complete -c sora -n '__fish_seen_subcommand_from anxious' -l no-prompt -d 'Take defaults, never ask'

# provide
complete -c sora -n '__fish_seen_subcommand_from provide; and not __fish_seen_subcommand_from pkcs11 native-messaging list remove' \
    -a 'pkcs11 native-messaging list remove'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from pkcs11' \
    -l box -x -a '(__sora_boxes)' -d 'Which box has the driver'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from pkcs11' \
    -l label -x -d 'Short handle for this module'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from pkcs11' \
    -l no-nss -d 'Skip the ~/.pki/nssdb registration'
# Takes a value, so it needs -x: without it fish treats the flag as boolean and
# the app ID falls through to the generic rule, which offers filenames.
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from pkcs11' \
    -l flatpak-app -x -a '(__sora_flatpak_apps)' -d 'Also address this Flatpak app'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from pkcs11' \
    -l allow-version-mismatch -d 'Publish despite differing p11-kit series'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from native-messaging' \
    -l box -x -a '(__sora_boxes)' -d 'Which box has the helper'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from native-messaging' \
    -l as -x -d 'Export the helper under this name'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from native-messaging' \
    -l browsers -x -d 'Only these browser profiles'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from native-messaging' \
    -l extension-id -x -d 'Also allow this extension id'
complete -c sora -n '__fish_seen_subcommand_from provide; and __fish_seen_subcommand_from remove' \
    -a '(__sora_registry provide.list)'

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
