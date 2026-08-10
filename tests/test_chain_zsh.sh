#!/usr/bin/env bash
# zsh hook: chaining to a pre-existing command_not_found_handler.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
setup_sandbox

out=$(zsh -f 2>&1 <<EOF
command_not_found_handler() { echo "PREV:\$*"; return 9; }
source "$HOOK_ZSH"
ghostcmd alpha 'b c'
echo "rc=\$?"
EOF
)
assert_contains "$out" "PREV:ghostcmd alpha b c" "previous handler receives the delegation"
assert_contains "$out" "rc=9" "previous handler's exit code propagates"

out=$(zsh -f 2>&1 <<EOF
command_not_found_handler() { echo "PREV:\$1"; return 3; }
source "$HOOK_ZSH"
source "$HOOK_ZSH"
ghostcmd
echo "rc=\$?"
EOF
)
assert_eq "$(grep -c PREV <<<"$out")" 1 "double-source delegates exactly once"
assert_contains "$out" "rc=3" "exit code still propagates after double-source"

out=$(zsh -f 2>&1 <<EOF
source "$HOOK_ZSH"
ghostcmd
echo "rc=\$?"
EOF
)
assert_contains "$out" "no boxes indexed" "distinguishes 'no boxes configured'"
assert_contains "$out" "rc=127" "127 when unresolved"

echo "ok: zsh chaining"
