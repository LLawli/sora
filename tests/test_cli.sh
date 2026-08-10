#!/usr/bin/env bash
# CLI-level behavior that does not need a real container: pins, conflicts,
# which, set-priority, hook install idempotency.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

make_box_meta alpha 10
make_box_meta beta 20
make_box_list alpha python git
make_box_list beta python curl

# --- conflicts --------------------------------------------------------------
out=$("$SORA_BIN" conflicts)
assert_contains "$out" "python" "conflicts lists the duplicated command"
assert_contains "$out" "beta" "conflicts shows the winner"
assert_contains "$out" "also in" "conflicts shows the losers"
assert_not_contains "$out" "git" "unique commands are not conflicts"

# --- pin / unpin ------------------------------------------------------------
"$SORA_BIN" pin python alpha >/dev/null || fail "pin failed"
assert_eq "$(index_lookup python)" "alpha" "pin rebuilds the index with the override"
out=$("$SORA_BIN" conflicts)
assert_contains "$out" "pinned" "conflicts marks pinned winners"
out=$("$SORA_BIN" pin --list)
assert_contains "$out" "python" "pin --list shows the pin"

"$SORA_BIN" pin --remove python >/dev/null || fail "unpin failed"
assert_eq "$(index_lookup python)" "beta" "unpin restores priority resolution"

# Pinning to an unmanaged box must fail.
"$SORA_BIN" pin python ghostbox >/dev/null 2>&1 && fail "pin to unknown box must fail"

# --- box set-priority -------------------------------------------------------
"$SORA_BIN" box set-priority alpha 99 >/dev/null || fail "set-priority failed"
assert_eq "$(index_lookup python)" "alpha" "set-priority rebuilds the index"
assert_eq "$(awk -F' = ' '/^priority/ { print $2 }' "$XDG_CONFIG_HOME/sora/boxes/alpha.toml")" \
    "99" "priority stored unquoted in metadata"

# --- which ------------------------------------------------------------------
out=$("$SORA_BIN" which python)
assert_contains "$out" "box 'alpha'" "which reports the winning box"
out=$("$SORA_BIN" which sh)
assert_contains "$out" "host:" "which reports host binaries"
assert_contains "$out" "host binaries always win" "which explains precedence"
"$SORA_BIN" which no-such-cmd-anywhere >/dev/null 2>&1 && fail "which must fail for unknown commands"

# --- hook install idempotency ----------------------------------------------
touch "$HOME/.bashrc"
"$SORA_BIN" hook install bash >/dev/null || fail "hook install failed"
"$SORA_BIN" hook install bash >/dev/null || fail "second hook install failed"
assert_eq "$(grep -c 'sora/shell/hook' "$HOME/.bashrc")" 1 "hook install is idempotent"
out=$("$SORA_BIN" hook status)
assert_contains "$out" "bash  installed" "hook status reports bash"

# The installed line must actually work.
out=$(bash --norc -c "source $HOME/.bashrc; declare -f command_not_found_handle >/dev/null && echo hooked")
assert_contains "$out" "hooked" "sourcing .bashrc defines the handler"

echo "ok: cli"
