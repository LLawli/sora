#compdef sora
# sora — completion for the sora CLI itself (zsh).
#
# Installed to PREFIX/share/zsh/site-functions/_sora. Every candidate list is
# read from a local file, so completing a sora command never enters a
# container.

_sora_boxes() {
    local d=${XDG_CONFIG_HOME:-$HOME/.config}/sora/boxes
    local -a b
    [[ -d $d ]] || return 0
    b=(${d}/*.toml(N:t:r))
    (( $#b )) && _describe -t boxes 'box' b
}

_sora_indexed() {
    local i=${XDG_CACHE_HOME:-$HOME/.cache}/sora/index
    local -a c
    [[ -r $i ]] || return 0
    c=(${(f)"$(cut -f1 -- $i)"})
    (( $#c )) && _describe -t commands 'indexed command' c
}

_sora_registry() {  # anxious.list | delegate.list
    local f=${XDG_CONFIG_HOME:-$HOME/.config}/sora/$1
    local -a c
    [[ -r $f ]] || return 0
    c=(${(f)"$(cut -f1 -- $f)"})
    (( $#c )) && _describe -t commands 'command' c
}

_sora() {
    local context state state_descr line
    typeset -A opt_args
    local -a subcommands
    subcommands=(
        'box:manage boxes'
        'images:show the image alias catalog'
        'reindex:rebuild the command index'
        'sync:alias of reindex'
        'conflicts:commands present in more than one box'
        'pin:force a command to resolve to one box'
        'which:how a command would resolve'
        'anxious:export a real wrapper into PATH'
        'completion:tab completion wiring'
        'hook:shell hook installation'
        'doctor:sanity-check the setup'
        'version:print the version'
        'help:show usage'
    )

    _arguments -C '1:command:->cmd' '*::arg:->args'

    case $state in
        cmd) _describe -t commands 'sora command' subcommands ;;
        args)
            case $words[1] in
                box)
                    if (( CURRENT == 2 )); then
                        _values 'box command' create list enter rm set-priority
                    else
                        case $words[2] in
                            create) _arguments \
                                '--image[source image or alias]:image:(fedora ubuntu debian arch tumbleweed alpine)' \
                                '--priority[index priority]:integer:' \
                                '--pkg-manager[override detection]:pm:(dnf5 apt-get pacman zypper apk)' \
                                '--no-own-home[share the host home]' \
                                '--no-xdg-links[skip XDG folder symlinks]' \
                                '--hide[mask a path with tmpfs]:path:_files' ;;
                            enter|set-priority) _sora_boxes ;;
                            rm) _alternative 'boxes:box:_sora_boxes' \
                                             'flags:flag:(--yes --delete-home)' ;;
                        esac
                    fi ;;
                reindex|sync) _sora_boxes ;;
                which) _sora_indexed ;;
                pin)
                    if (( CURRENT == 2 )); then
                        _alternative 'commands:command:_sora_indexed' \
                                     'flags:flag:(--list --remove)'
                    else
                        [[ $words[2] == (--remove|-r) ]] && _sora_indexed || _sora_boxes
                    fi ;;
                anxious)
                    _arguments \
                        '--sudo[run with sudo inside the container]' \
                        '--with-completion[also install the tool'\''s completion]' \
                        '--box[which box provides it]:box:_sora_boxes' \
                        '--list[list exported wrappers]' \
                        "--remove[remove an exported wrapper]:command:{_sora_registry anxious.list}" \
                        '*:command:_sora_indexed' ;;
                completion)
                    if (( CURRENT == 2 )); then
                        _values 'completion command' delegate list remove status
                    else
                        case $words[2] in
                            delegate) _arguments \
                                '--box[which box answers the Tab]:box:_sora_boxes' \
                                '*:command:_sora_indexed' ;;
                            remove) _sora_registry delegate.list ;;
                        esac
                    fi ;;
                hook)
                    if (( CURRENT == 2 )); then
                        _values 'hook command' install status print
                    else
                        _values 'shell' bash zsh fish
                    fi ;;
            esac ;;
    esac
}

_sora "$@"
