#!/usr/bin/env bash
# 'sora anxious --with-completion': generate the tool's own completion script
# from inside the box and install it on the host.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

make_box_meta devbox 0

cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
[ "$1" = container ] && [ "$2" = exists ] && exit 0
exit 1
EOF

# Stands in for distrobox: routes 'enter --name BOX -- ARGS' to a fake in-box
# world where 'goodtool' is a cobra-style CLI and 'plaintool' is not.
cat > "$STUB_BIN/distrobox" <<'EOF'
#!/bin/sh
while [ "$1" != "--" ]; do shift; done
shift
case "$1" in
    *sora-which)     printf '/usr/bin/%s\n' "$2" ;;
    distrobox-export)
        # mimic the real thing: drop a wrapper into --export-path
        while [ $# -gt 0 ]; do
            [ "$1" = --bin ] && bin=$2
            [ "$1" = --export-path ] && dest=$2
            shift
        done
        mkdir -p "$dest"
        printf '#!/bin/sh\n# fake wrapper\n' > "$dest/${bin##*/}"
        chmod 0755 "$dest/${bin##*/}"
        ;;
    goodtool)
        [ "$2" = completion ] || exit 1
        case $3 in
            bash) printf '_goodtool() { :; }\ncomplete -F _goodtool goodtool\n' ;;
            zsh)  printf '#compdef goodtool\n_goodtool() { :; }\n' ;;
            fish) printf 'complete -c goodtool -a "apply delete"\n' ;;
            *)    exit 1 ;;
        esac
        ;;
    plaintool)
        # Has no completion generator: prints usage to stderr and fails.
        printf 'plaintool: unknown subcommand\n' >&2
        exit 2
        ;;
    weirdtool)
        # Exits 0 but 'completion' means something unrelated. The output must
        # be rejected: writing it to the user's home would break their shell.
        printf 'Completion: 87%%\n'
        ;;
    crosstool)
        # Ignores the shell argument and always prints its BASH script. Real
        # tools do this. Only bash may accept it: a bash script installed as
        # fish completion is a syntax error on every fish startup.
        [ "$2" = completion ] || exit 1
        printf '_crosstool() { COMPREPLY=(); }\ncomplete -F _crosstool crosstool\n'
        ;;
esac
EOF
chmod +x "$STUB_BIN/podman" "$STUB_BIN/distrobox"

BASHC="$XDG_DATA_HOME/bash-completion/completions"
ZSHC="$XDG_DATA_HOME/zsh/site-functions"
FISHC="$XDG_CONFIG_HOME/fish/completions"

# --- a cobra-style tool: scripts land in the right per-shell locations -------
out=$("$SORA_BIN" anxious goodtool --box devbox --with-completion 2>&1) ||
    fail "anxious --with-completion failed: $out"
assert_contains "$out" "exported 'goodtool'" "the wrapper is still exported"

[ -f "$BASHC/goodtool" ] || fail "bash completion not installed at $BASHC/goodtool"
assert_contains "$(cat "$BASHC/goodtool")" "complete -F _goodtool goodtool" \
    "bash completion has the generated content"

if command -v zsh >/dev/null 2>&1; then
    [ -f "$ZSHC/_goodtool" ] || fail "zsh completion not installed at $ZSHC/_goodtool"
    assert_contains "$(cat "$ZSHC/_goodtool")" "#compdef goodtool" "zsh completion content"
    assert_contains "$out" "not in your zsh \$fpath" "warns when the fpath entry is missing"
fi
if command -v fish >/dev/null 2>&1; then
    [ -f "$FISHC/goodtool.fish" ] || fail "fish completion not installed"
fi

# --- without the flag, nothing is written ------------------------------------
out=$("$SORA_BIN" anxious goodtool2 --box devbox 2>&1) || fail "plain anxious failed: $out"
[ -f "$BASHC/goodtool2" ] && fail "completion installed without --with-completion"

# --- a tool with no generator: clear warning, export still succeeds ----------
out=$("$SORA_BIN" anxious plaintool --box devbox --with-completion 2>&1) ||
    fail "anxious must still succeed when completion generation fails"
assert_contains "$out" "exported 'plaintool'" "the wrapper is exported anyway"
assert_contains "$out" "does not generate completion scripts" "explains the miss"
[ -f "$BASHC/plaintool" ] && fail "nothing may be written when generation fails"

# --- output that is not a completion script must be rejected -----------------
out=$("$SORA_BIN" anxious weirdtool --box devbox --with-completion 2>&1) ||
    fail "anxious must survive a bogus 'completion' subcommand"
[ -f "$BASHC/weirdtool" ] && fail "bogus output must not be installed"
assert_contains "$out" "does not generate completion scripts" "bogus output counts as a miss"

# --- a tool that prints its bash script for every shell ----------------------
# Regression: the per-shell validators must not overlap, or a bash script
# lands in fish's completions dir and breaks every fish startup.
out=$("$SORA_BIN" anxious crosstool --box devbox --with-completion 2>&1) ||
    fail "anxious failed for crosstool: $out"
[ -f "$BASHC/crosstool" ] || fail "bash completion should be accepted for crosstool"
if command -v fish >/dev/null 2>&1; then
    [ -f "$FISHC/crosstool.fish" ] && fail "a bash script must never be installed as fish completion"
fi
if command -v zsh >/dev/null 2>&1; then
    [ -f "$ZSHC/_crosstool" ] && fail "a bash script must never be installed as zsh completion"
fi

# --- removal takes the completion scripts with it ----------------------------
out=$("$SORA_BIN" anxious --remove goodtool 2>&1) || fail "anxious --remove failed: $out"
[ -f "$BASHC/goodtool" ] && fail "bash completion survived --remove"
if command -v zsh >/dev/null 2>&1; then
    [ -f "$ZSHC/_goodtool" ] && fail "zsh completion survived --remove"
fi
if command -v fish >/dev/null 2>&1; then
    [ -f "$FISHC/goodtool.fish" ] && fail "fish completion survived --remove"
fi
assert_contains "$out" "removed" "removal is reported"

echo "ok: anxious --with-completion"
