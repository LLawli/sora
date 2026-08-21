#!/usr/bin/env bash
# Completion for the sora CLI itself.
#
# Every candidate list here must come from a local file. A completion that
# entered a container would break the project's central promise in the most
# visible place possible: typing 'sora ' and waiting three seconds.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

COMP_BASH="$REPO_DIR/shell/completion.bash"
COMP_ZSH="$REPO_DIR/shell/completion.zsh"
COMP_FISH="$REPO_DIR/shell/completion.fish"

make_box_meta alpha 10
make_box_meta beta 20
printf 'apt-cache\talpha\nhtop\tbeta\n' > "$XDG_CACHE_HOME/sora/index"
printf 'htop\tbeta\tnosudo\t/x/htop\t/usr/bin/htop\n' > "$XDG_CONFIG_HOME/sora/anxious.list"
printf 'apt-cache\talpha\n' > "$XDG_CONFIG_HOME/sora/delegate.list"
printf 'sora-alpha-tok\tpkcs11\talpha\ttok\tnss\t/usr/lib/libtok.so\n' \
    > "$XDG_CONFIG_HOME/sora/provide.list"
# --flatpak-app's candidates come from ~/.var/app, a readdir with no process
# behind it - not from 'flatpak list', which would fork on every Tab.
mkdir -p "$HOME/.var/app/br.jus.cnj.PJeOffice" "$HOME/.var/app/com.brave.Browser"

# A stub that fails loudly: if completing ever shells out to a container
# manager, these turn the test red instead of silently costing seconds.
for c in podman docker distrobox; do
    printf '#!/bin/sh\necho "CONTAINER TOUCHED: %s $*" >&2\nexit 1\n' "$c" > "$STUB_BIN/$c"
    chmod +x "$STUB_BIN/$c"
done

complete_bash() { # words... (last one is the word being completed)
    local -a w=("$@")
    bash --norc 2>&1 <<EOF
source "$COMP_BASH"
COMP_WORDS=($(printf '%q ' "${w[@]}"))
COMP_CWORD=$(( ${#w[@]} - 1 ))
COMPREPLY=()
_sora
printf '%s\n' "\${COMPREPLY[@]}"
EOF
}

# --- top-level subcommands --------------------------------------------------
out=$(complete_bash sora comp)
assert_contains "$out" "completion" "'sora comp' completes to the completion subcommand"
out=$(complete_bash sora "")
assert_contains "$out" "anxious" "bare 'sora ' lists subcommands"
assert_contains "$out" "doctor" "bare 'sora ' lists doctor"

# --- box --------------------------------------------------------------------
out=$(complete_bash sora box "")
assert_contains "$out" "set-priority" "'sora box' lists its subcommands"
out=$(complete_bash sora box enter "")
assert_contains "$out" "alpha" "'box enter' offers box names"
assert_contains "$out" "beta" "'box enter' offers every box"
assert_not_contains "$out" "create" "'box enter' does not offer subcommands"
out=$(complete_bash sora box rm --yes "")
assert_contains "$out" "--delete-home" "'box rm' offers its flags"
out=$(complete_bash sora box create --image "")
assert_contains "$out" "tumbleweed" "--image offers the alias catalog"
out=$(complete_bash sora box create -)
assert_contains "$out" "--nvidia" "'box create' offers --nvidia"
assert_contains "$out" "--additional-flags" "'box create' offers --additional-flags"
# Container-manager flags are free-form; offering box names would be nonsense.
out=$(complete_bash sora box create --additional-flags "")
assert_not_contains "$out" "alpha" "--additional-flags does not fall back to box names"

# --- value-taking options decide on their own, wherever they sit -------------
out=$(complete_bash sora anxious --box "")
assert_contains "$out" "alpha" "--box offers box names"
out=$(complete_bash sora completion delegate --box "")
assert_contains "$out" "beta" "--box works under a nested subcommand too"

# --- index-driven candidates ------------------------------------------------
out=$(complete_bash sora which apt-)
assert_contains "$out" "apt-cache" "'which' offers indexed commands"
out=$(complete_bash sora reindex "")
assert_contains "$out" "alpha" "'reindex' offers box names"

# --- registries -------------------------------------------------------------
out=$(complete_bash sora anxious --remove "")
assert_contains "$out" "htop" "'anxious --remove' offers exported commands"
assert_not_contains "$out" "apt-cache" "'anxious --remove' offers only exported ones"
out=$(complete_bash sora completion remove "")
assert_contains "$out" "apt-cache" "'completion remove' offers delegated commands"
assert_not_contains "$out" "htop" "'completion remove' offers only delegated ones"

# --- export by path, under a chosen name ------------------------------------
out=$(complete_bash sora anxious -)
assert_contains "$out" "--path" "--path is offered"
assert_contains "$out" "--as" "--as is offered"
assert_contains "$out" "--force" "--force is offered"
# An in-box path is exactly what the host's command names must not suggest.
out=$(complete_bash sora anxious --path "")
assert_not_contains "$out" "htop" "--path does not fall back to command names"
out=$(complete_bash sora anxious --as "")
assert_not_contains "$out" "htop" "--as does not fall back to command names"

# --- desktop-entry flags ----------------------------------------------------
out=$(complete_bash sora anxious --desk)
assert_contains "$out" "--desktop" "'anxious --desk' completes to --desktop"
out=$(complete_bash sora anxious --desktop -)
assert_contains "$out" "--wmclass" "--desktop's own flags are offered"
assert_contains "$out" "--browser" "--browser is offered"
assert_contains "$out" "--no-prompt" "--no-prompt is offered"
out=$(complete_bash sora anxious --desktop --categories "")
assert_contains "$out" "Network;WebBrowser;" "--categories offers the browser category"
# Free-form values must offer NOTHING, not the index: a --name that suggested
# command names would be actively misleading.
out=$(complete_bash sora anxious --desktop --name "")
assert_not_contains "$out" "htop" "--name does not fall back to command names"
out=$(complete_bash sora anxious --desktop --wmclass "")
assert_not_contains "$out" "htop" "--wmclass does not fall back to command names"

# --- provide ----------------------------------------------------------------
out=$(complete_bash sora "")
assert_contains "$out" "provide" "bare 'sora ' lists provide"
out=$(complete_bash sora provide "")
assert_contains "$out" "pkcs11" "'sora provide' lists its subcommands"
assert_contains "$out" "native-messaging" "'sora provide' lists the native-messaging adapter"
assert_contains "$out" "remove" "'sora provide' lists remove"
out=$(complete_bash sora provide pkcs11 -)
assert_contains "$out" "--no-nss" "'provide pkcs11' offers its flags"
assert_contains "$out" "--flatpak-app" "'provide pkcs11' offers --flatpak-app"
out=$(complete_bash sora provide pkcs11 --box "")
assert_contains "$out" "alpha" "'provide pkcs11 --box' offers box names"
out=$(complete_bash sora provide pkcs11 --flatpak-app "")
assert_contains "$out" "br.jus.cnj.PJeOffice" "--flatpak-app offers installed app IDs"
assert_not_contains "$out" "htop" "--flatpak-app does not fall back to command names"
out=$(complete_bash sora provide remove "")
assert_contains "$out" "sora-alpha-tok" "'provide remove' offers provisioned names"
assert_not_contains "$out" "htop" "'provide remove' offers only provisions"
# The library path is inside the box, so host candidates would be misleading.
out=$(complete_bash sora provide pkcs11 --label "")
assert_not_contains "$out" "htop" "--label does not fall back to command names"
out=$(complete_bash sora provide native-messaging -)
assert_contains "$out" "--browsers" "'provide native-messaging' offers its flags"
assert_contains "$out" "--as" "'provide native-messaging' offers --as"
out=$(complete_bash sora provide native-messaging --box "")
assert_contains "$out" "alpha" "'provide native-messaging --box' offers box names"
out=$(complete_bash sora provide native-messaging --browsers "")
assert_not_contains "$out" "htop" "--browsers does not fall back to command names"

# --- hook -------------------------------------------------------------------
out=$(complete_bash sora hook "")
assert_contains "$out" "install" "'sora hook' lists its subcommands"
out=$(complete_bash sora hook install "")
assert_contains "$out" "fish" "'hook install' offers shell names"

# --- the whole point: no container is ever touched --------------------------
for words in "sora " "sora box enter " "sora which apt-" "sora anxious --box " \
             "sora provide " "sora provide remove " "sora provide pkcs11 --box " \
             "sora provide pkcs11 --flatpak-app "; do
    # shellcheck disable=SC2086
    out=$(complete_bash $words "")
    assert_not_contains "$out" "CONTAINER TOUCHED" "completing '$words' touches no container"
done

# --- missing state must degrade, never error --------------------------------
rm -f "$XDG_CACHE_HOME/sora/index" "$XDG_CONFIG_HOME/sora/delegate.list"
rm -rf "$XDG_CONFIG_HOME/sora/boxes"
out=$(complete_bash sora box enter "")
assert_not_contains "$out" "No such file" "no boxes configured: no error output"
out=$(complete_bash sora which "")
assert_not_contains "$out" "No such file" "no index: no error output"

# --- the other two shells parse, and their helpers read the same files ------
if command -v zsh >/dev/null 2>&1; then
    zsh -n "$COMP_ZSH" || fail "zsh completion is not valid zsh"
    assert_contains "$(head -1 "$COMP_ZSH")" "#compdef sora" "zsh file carries the compdef tag"
fi
if command -v fish >/dev/null 2>&1; then
    fish -n "$COMP_FISH" || fail "fish completion is not valid fish"
    mkdir -p "$XDG_CONFIG_HOME/sora/boxes"   # a previous case removed it
    make_box_meta gamma 0
    printf 'apt-cache\tgamma\n' > "$XDG_CACHE_HOME/sora/index"

    # Drive the real completion engine, not just the helper functions. An
    # earlier version passed a helper-only check while every value-taking flag
    # was silently completing filenames instead of its own candidates: in fish
    # a flag that takes a value needs -x (or -r), otherwise it is treated as a
    # boolean and the value falls through to the generic rule.
    fish_complete() { # line
        fish -c "set -x XDG_CONFIG_HOME '$XDG_CONFIG_HOME'
                 set -x XDG_CACHE_HOME '$XDG_CACHE_HOME'
                 source '$COMP_FISH'
                 complete --do-complete '$1'" 2>/dev/null | cut -f1
    }

    out=$(fish_complete 'sora box enter ')
    assert_contains "$out" "gamma" "fish: box names for 'box enter'"
    out=$(fish_complete 'sora anxious --box ')
    assert_contains "$out" "gamma" "fish: --box offers box names"
    assert_not_contains "$out" "CHANGELOG" "fish: --box must not fall back to filenames"
    out=$(fish_complete 'sora box create --image ')
    assert_contains "$out" "tumbleweed" "fish: --image offers the alias catalog"
    out=$(fish_complete 'sora box create --additional-flags ')
    assert_not_contains "$out" "CHANGELOG" "fish: --additional-flags must not fall back to filenames"
    assert_not_contains "$out" "CHANGELOG" "fish: --image must not fall back to filenames"
    out=$(fish_complete 'sora which apt-')
    assert_contains "$out" "apt-cache" "fish: 'which' offers indexed commands"
    out=$(fish_complete 'sora comp')
    assert_contains "$out" "completion" "fish: subcommand completion"

    # The -x trap again, now for the desktop flags: each of these takes a
    # value, so none of them may fall through to filenames.
    out=$(fish_complete 'sora anxious --desktop --name ')
    assert_not_contains "$out" "CHANGELOG" "fish: --name must not fall back to filenames"
    out=$(fish_complete 'sora anxious --desktop --wmclass ')
    assert_not_contains "$out" "CHANGELOG" "fish: --wmclass must not fall back to filenames"
    out=$(fish_complete 'sora anxious --desktop --icon ')
    assert_not_contains "$out" "CHANGELOG" "fish: --icon must not fall back to filenames"
    out=$(fish_complete 'sora anxious --desktop --mime ')
    assert_not_contains "$out" "CHANGELOG" "fish: --mime must not fall back to filenames"
    out=$(fish_complete 'sora anxious --desktop --categories ')
    assert_contains "$out" "Network;WebBrowser;" "fish: --categories offers its values"
    out=$(fish_complete 'sora anxious --deskt')
    assert_contains "$out" "--desktop" "fish: --desktop is offered"

    out=$(fish_complete 'sora anxious --path ')
    assert_not_contains "$out" "CHANGELOG" "fish: --path must not fall back to filenames"
    out=$(fish_complete 'sora anxious --as ')
    assert_not_contains "$out" "CHANGELOG" "fish: --as must not fall back to filenames"

    printf 'sora-gamma-tok\tpkcs11\tgamma\ttok\tnss\t/usr/lib/libtok.so\n' \
        > "$XDG_CONFIG_HOME/sora/provide.list"
    out=$(fish_complete 'sora prov')
    assert_contains "$out" "provide" "fish: provide is offered"
    out=$(fish_complete 'sora provide ')
    assert_contains "$out" "pkcs11" "fish: provide lists its subcommands"
    out=$(fish_complete 'sora provide pkcs11 --box ')
    assert_contains "$out" "gamma" "fish: provide --box offers box names"
    assert_not_contains "$out" "CHANGELOG" "fish: provide --box must not fall back to filenames"
    out=$(fish_complete 'sora provide pkcs11 --label ')
    assert_not_contains "$out" "CHANGELOG" "fish: --label must not fall back to filenames"
    out=$(fish_complete 'sora provide pkcs11 --flatpak-app ')
    assert_contains "$out" "br.jus.cnj.PJeOffice" "fish: --flatpak-app offers installed app IDs"
    assert_not_contains "$out" "CHANGELOG" "fish: --flatpak-app must not fall back to filenames"
    out=$(fish_complete 'sora provide pkcs11 --flat')
    assert_contains "$out" "--flatpak-app" "fish: --flatpak-app is offered"
    out=$(fish_complete 'sora provide remove ')
    assert_contains "$out" "sora-gamma-tok" "fish: provide remove offers provisioned names"
    out=$(fish_complete 'sora provide ')
    assert_contains "$out" "native-messaging" "fish: the native-messaging adapter is offered"
    out=$(fish_complete 'sora provide native-messaging --box ')
    assert_contains "$out" "gamma" "fish: native-messaging --box offers box names"
    assert_not_contains "$out" "CHANGELOG" "fish: --box must not fall back to filenames"
    out=$(fish_complete 'sora provide native-messaging --as ')
    assert_not_contains "$out" "CHANGELOG" "fish: --as must not fall back to filenames"
    out=$(fish_complete 'sora provide native-messaging --browsers ')
    assert_not_contains "$out" "CHANGELOG" "fish: --browsers must not fall back to filenames"
fi

# --- installed to the standard per-shell locations --------------------------
DEST="$SANDBOX/prefix"
make -C "$REPO_DIR" install PREFIX="$DEST" >/dev/null 2>&1 ||
    fail "make install failed"
[ -f "$DEST/share/bash-completion/completions/sora" ] || fail "bash completion not installed"
[ -f "$DEST/share/zsh/site-functions/_sora" ] || fail "zsh completion not installed"
[ -f "$DEST/share/fish/vendor_completions.d/sora.fish" ] || fail "fish completion not installed"
make -C "$REPO_DIR" uninstall PREFIX="$DEST" >/dev/null 2>&1
[ -f "$DEST/share/bash-completion/completions/sora" ] && fail "uninstall left the bash completion behind"

echo "ok: sora self-completion"
