#!/usr/bin/env bash
# bash hook: chaining to a pre-existing command_not_found_handle.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

# 1. A pre-existing handler must keep working when sora cannot resolve, and
#    its exit code must propagate.
out=$(bash --norc 2>&1 <<EOF
command_not_found_handle() { echo "PREV:\$*"; return 9; }
source "$HOOK_BASH"
ghostcmd alpha 'b c'
echo "rc=\$?"
EOF
)
assert_contains "$out" "PREV:ghostcmd alpha b c" "previous handler receives the delegation"
assert_contains "$out" "rc=9" "previous handler's exit code propagates"

# 2. Re-sourcing must not capture sora itself (no infinite delegation loop),
#    and the original handler must still be reachable exactly once.
out=$(bash --norc 2>&1 <<EOF
command_not_found_handle() { echo "PREV:\$1"; return 3; }
source "$HOOK_BASH"
source "$HOOK_BASH"
ghostcmd
echo "rc=\$?"
EOF
)
assert_eq "$(grep -c PREV <<<"$out")" 1 "double-source delegates exactly once"
assert_contains "$out" "rc=3" "exit code still propagates after double-source"

# 3. No previous handler + no index: useful "no boxes" message, rc 127.
out=$(bash --norc 2>&1 <<EOF
source "$HOOK_BASH"
ghostcmd
echo "rc=\$?"
EOF
)
assert_contains "$out" "no boxes indexed" "distinguishes 'no boxes configured'"
assert_contains "$out" "rc=127" "127 when unresolved"

# 4. No previous handler + populated index without the command: the message
#    must say the command exists in no box (not 'no boxes').
printf 'othercmd\tsomebox\n' > "$XDG_CACHE_HOME/sora/index"
out=$(bash --norc 2>&1 <<EOF
source "$HOOK_BASH"
ghostcmd
echo "rc=\$?"
EOF
)
assert_contains "$out" "not found in any box" "distinguishes 'not in any box'"
assert_not_contains "$out" "no boxes indexed" "does not claim there are no boxes"

echo "ok: bash chaining"
