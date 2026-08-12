# sora — completion for the sora CLI itself (bash).
#
# Installed to PREFIX/share/bash-completion/completions/sora, where the lazy
# loader picks it up on the first Tab. It is deliberately independent of
# bash-completion's helper functions (_init_completion, _filedir): sora runs on
# hosts where that package is not installed, and a completion that breaks there
# is worse than no completion.
#
# Every candidate list comes from a local file — box metadata, the index, the
# anxious and delegate registries. Completing a sora command never enters a
# container, exactly like the command-not-found lookup.

_sora_config_dir() { printf '%s/sora\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
_sora_cache_dir()  { printf '%s/sora\n' "${XDG_CACHE_HOME:-$HOME/.cache}"; }

_sora_boxes() {
    local d f
    d=$(_sora_config_dir)/boxes
    [ -d "$d" ] || return 0
    for f in "$d"/*.toml; do
        [ -f "$f" ] || continue
        f=${f##*/}
        printf '%s\n' "${f%.toml}"
    done
}

_sora_indexed_commands() {
    local i
    i=$(_sora_cache_dir)/index
    [ -r "$i" ] && cut -f1 -- "$i"
}

_sora_registry_commands() { # anxious.list | delegate.list
    local f
    f=$(_sora_config_dir)/$1
    [ -r "$f" ] && cut -f1 -- "$f"
}

_sora() {
    local cur prev cmd sub i
    cur=${COMP_WORDS[COMP_CWORD]}
    prev=${COMP_WORDS[COMP_CWORD-1]}
    COMPREPLY=()

    # An option that takes a value decides the candidates by itself, whatever
    # position it sits in.
    case $prev in
        --box|-b)
            mapfile -t COMPREPLY < <(compgen -W "$(_sora_boxes)" -- "$cur")
            return ;;
        --image)
            mapfile -t COMPREPLY < <(compgen -W \
                "fedora ubuntu debian arch tumbleweed alpine" -- "$cur")
            return ;;
        --priority|--pkg-manager|--hide)
            return ;;   # free-form: an integer, a pm name, a path
        --categories)
            mapfile -t COMPREPLY < <(compgen -W \
                "Network;WebBrowser; Development; Graphics; AudioVideo; \
                 Office; Game; System; Utility;" -- "$cur")
            return ;;
        --mime)
            mapfile -t COMPREPLY < <(compgen -W \
                "text/html;x-scheme-handler/http;x-scheme-handler/https; \
                 x-scheme-handler/mailto; inode/directory;" -- "$cur")
            return ;;
        --name|--comment|--generic-name|--icon|--keywords|--wmclass)
            return ;;   # free-form: whatever the user wants to read in the menu
        --path|--as)
            # --path is a path INSIDE the box, so the host filesystem is the
            # wrong candidate list; offering nothing is deliberate, not a gap.
            return ;;
    esac

    # Find the subcommand: the first word that is not an option.
    cmd=""
    for (( i = 1; i < COMP_CWORD; i++ )); do
        case ${COMP_WORDS[i]} in
            -*) ;;
            *) cmd=${COMP_WORDS[i]}; break ;;
        esac
    done

    if [ -z "$cmd" ]; then
        mapfile -t COMPREPLY < <(compgen -W \
            "box images reindex sync conflicts pin which anxious completion \
             hook doctor version help" -- "$cur")
        return
    fi

    sub=${COMP_WORDS[i+1]:-}

    case $cmd in
        box)
            if [ "$COMP_CWORD" -eq $((i + 1)) ]; then
                mapfile -t COMPREPLY < <(compgen -W \
                    "create list enter rm set-priority" -- "$cur")
                return
            fi
            case $sub in
                create)
                    mapfile -t COMPREPLY < <(compgen -W \
                        "--image --priority --pkg-manager --no-own-home \
                         --no-xdg-links --hide" -- "$cur") ;;
                enter|rm|set-priority)
                    # Only the box name; rm also takes flags.
                    if [ "$COMP_CWORD" -eq $((i + 2)) ]; then
                        mapfile -t COMPREPLY < <(compgen -W "$(_sora_boxes)" -- "$cur")
                    elif [ "$sub" = rm ]; then
                        mapfile -t COMPREPLY < <(compgen -W "--yes --delete-home" -- "$cur")
                    fi ;;
            esac
            ;;
        reindex|sync)
            mapfile -t COMPREPLY < <(compgen -W "$(_sora_boxes)" -- "$cur") ;;
        which)
            mapfile -t COMPREPLY < <(compgen -W "$(_sora_indexed_commands)" -- "$cur") ;;
        pin)
            case $cur in
                -*) mapfile -t COMPREPLY < <(compgen -W "--list --remove" -- "$cur"); return ;;
            esac
            case $prev in
                --remove|-r)
                    mapfile -t COMPREPLY < <(compgen -W \
                        "$(_sora_indexed_commands)" -- "$cur") ;;
                pin)
                    mapfile -t COMPREPLY < <(compgen -W \
                        "$(_sora_indexed_commands)" -- "$cur") ;;
                *)  # second positional: the box to pin it to
                    mapfile -t COMPREPLY < <(compgen -W "$(_sora_boxes)" -- "$cur") ;;
            esac
            ;;
        anxious)
            case $cur in
                -*) mapfile -t COMPREPLY < <(compgen -W \
                        "--sudo --with-completion --box --list --remove \
                         --path --as \
                         --desktop --name --generic-name --comment --icon \
                         --categories --mime --keywords --wmclass --terminal \
                         --browser --default-browser --detect-wmclass \
                         --no-prompt" -- "$cur")
                    return ;;
            esac
            case $prev in
                --remove|-r)
                    mapfile -t COMPREPLY < <(compgen -W \
                        "$(_sora_registry_commands anxious.list)" -- "$cur") ;;
                *)  mapfile -t COMPREPLY < <(compgen -W \
                        "$(_sora_indexed_commands)" -- "$cur") ;;
            esac
            ;;
        completion)
            if [ "$COMP_CWORD" -eq $((i + 1)) ]; then
                mapfile -t COMPREPLY < <(compgen -W \
                    "delegate list remove status" -- "$cur")
                return
            fi
            case $sub in
                delegate)
                    case $cur in
                        -*) mapfile -t COMPREPLY < <(compgen -W "--box" -- "$cur") ;;
                        *)  mapfile -t COMPREPLY < <(compgen -W \
                                "$(_sora_indexed_commands)" -- "$cur") ;;
                    esac ;;
                remove)
                    mapfile -t COMPREPLY < <(compgen -W \
                        "$(_sora_registry_commands delegate.list)" -- "$cur") ;;
            esac
            ;;
        hook)
            if [ "$COMP_CWORD" -eq $((i + 1)) ]; then
                mapfile -t COMPREPLY < <(compgen -W "install status print" -- "$cur")
                return
            fi
            case $sub in
                install|print) mapfile -t COMPREPLY < <(compgen -W "bash zsh fish" -- "$cur") ;;
            esac
            ;;
    esac
}

complete -F _sora sora
