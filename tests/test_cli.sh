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
assert_eq "$(grep -c 'sora: resolve distrobox commands' "$HOME/.bashrc")" 1 \
    "hook install is idempotent"
out=$("$SORA_BIN" hook status)
assert_contains "$out" "bash  installed" "hook status reports bash"

# The installed line must actually work.
out=$(bash --norc -c "source $HOME/.bashrc; declare -f command_not_found_handle >/dev/null && echo hooked")
assert_contains "$out" "hooked" "sourcing .bashrc defines the handler"

# Regression: idempotency must not depend on the checkout path containing the
# string "sora" (detection is by marker comment, not by hook path). Simulate
# a neutrally-named clone and install twice from it.
NEUTRAL="$SANDBOX/upstream-checkout"
mkdir -p "$NEUTRAL"
cp -r "$REPO_DIR/bin" "$REPO_DIR/shell" "$REPO_DIR/libexec" "$NEUTRAL/"
rm -f "$HOME/.bashrc"; touch "$HOME/.bashrc"
"$NEUTRAL/bin/sora" hook install bash >/dev/null || fail "neutral-path hook install failed"
"$NEUTRAL/bin/sora" hook install bash >/dev/null || fail "neutral-path second install failed"
assert_eq "$(grep -c 'sora: resolve distrobox commands' "$HOME/.bashrc")" 1 \
    "hook install is idempotent from a checkout not named 'sora'"

# --- Homebrew-style layout: version-stable paths ----------------------------
# Under brew, bin/sora is a symlink into a versioned Cellar keg while
# PREFIX/share/sora is a stable linked path. resolve_share must prefer the
# UNRESOLVED location: embedding the keg path in rc files kills the hook on
# the next upgrade.
BREW="$SANDBOX/brewprefix"
KEG="$BREW/Cellar/sora/9.9.9"
mkdir -p "$KEG/bin" "$KEG/share/sora" "$BREW/bin" "$BREW/share"
cp "$REPO_DIR/bin/sora" "$KEG/bin/sora"
cp -r "$REPO_DIR/shell" "$KEG/share/sora/shell"
cp -r "$REPO_DIR/libexec" "$KEG/share/sora/libexec"
ln -s ../Cellar/sora/9.9.9/bin/sora "$BREW/bin/sora"
ln -s ../Cellar/sora/9.9.9/share/sora "$BREW/share/sora"
out=$("$BREW/bin/sora" hook print bash)
assert_contains "$out" "$BREW/share/sora/shell/hook.bash" \
    "brew layout resolves to the stable prefix path"
assert_not_contains "$out" "Cellar" "brew layout must never leak the versioned keg path"

# --- hook install repairs a dead hook path ----------------------------------
# Simulate an rc whose sora block points at a removed keg: install must
# replace the block (once), not duplicate it or report 'already installed'.
rm -f "$HOME/.bashrc"
{
    printf '# sora: resolve distrobox commands on command-not-found.\n'
    printf '# Keep this near the END of the file so sora can chain to other handlers.\n'
    printf '[ -f "/gone/Cellar/sora/0.0.1/share/sora/shell/hook.bash" ] && . "/gone/Cellar/sora/0.0.1/share/sora/shell/hook.bash"\n'
} > "$HOME/.bashrc"
out=$("$SORA_BIN" hook install bash)
assert_contains "$out" "refreshing stale hook path" "repair path is reported"
assert_eq "$(grep -c 'sora: resolve distrobox commands' "$HOME/.bashrc")" 1 \
    "repair leaves exactly one sora block"
grep -q '/gone/Cellar' "$HOME/.bashrc" && fail "repair must remove the dead path"
out=$(bash --norc -c "source $HOME/.bashrc; declare -f command_not_found_handle >/dev/null && echo hooked")
assert_contains "$out" "hooked" "repaired rc loads the hook"

# --- doctor flags dangling PATH entries shadowing indexed commands ----------
DANGLE="$SANDBOX/danglebin"
mkdir -p "$DANGLE"
ln -s /nonexistent-target "$DANGLE/python"
out=$(PATH="$DANGLE:$PATH" "$SORA_BIN" doctor 2>&1 || true)
assert_contains "$out" "dangling symlink $DANGLE/python" \
    "doctor flags a dangling symlink shadowing an indexed command"

# --- sync is an alias of reindex --------------------------------------------
out=$("$SORA_BIN" sync 2>&1 || true)
assert_not_contains "$out" "unknown command" "sora sync is accepted as an alias"

echo "ok: cli"
