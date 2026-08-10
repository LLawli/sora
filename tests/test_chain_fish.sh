#!/usr/bin/env bash
# fish hook: chaining to a pre-existing fish_command_not_found.
# The handler is invoked directly (the trigger itself is fish-internal);
# direct invocation also sidesteps fish forcing $status to 127.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
command -v fish >/dev/null 2>&1 || skip "fish not installed"
setup_sandbox

out=$(fish 2>&1 <<EOF
function fish_command_not_found; echo "PREV:\$argv"; return 9; end
source "$HOOK_FISH"
fish_command_not_found ghostcmd alpha 'b c'
echo "rc=\$status"
EOF
)
assert_contains "$out" "PREV:ghostcmd alpha b c" "previous handler receives the delegation"
assert_contains "$out" "rc=9" "previous handler's exit code propagates"

out=$(fish 2>&1 <<EOF
function fish_command_not_found; echo "PREV:\$argv[1]"; return 3; end
source "$HOOK_FISH"
source "$HOOK_FISH"
fish_command_not_found ghostcmd
echo "rc=\$status"
EOF
)
assert_eq "$(grep -c PREV <<<"$out")" 1 "double-source delegates exactly once"
assert_contains "$out" "rc=3" "exit code still propagates after double-source"

out=$(fish 2>&1 <<EOF
source "$HOOK_FISH"
fish_command_not_found ghostcmd
echo "rc=\$status"
EOF
)
assert_contains "$out" "no boxes indexed" "distinguishes 'no boxes configured'"
assert_contains "$out" "rc=127" "127 when unresolved"

echo "ok: fish chaining"
