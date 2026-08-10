#!/usr/bin/env bash
# Dispatch: original arguments (spaces, quotes, empty strings, literal $VARS,
# dash-arguments) must reach the box command intact, and the exit code must
# propagate. Verified against a stub distrobox that records argv verbatim.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

export SORA_TEST_RECORD="$SANDBOX/record"

cat > "$STUB_BIN/distrobox" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$SORA_TEST_RECORD"
exit 42
EOF
cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
[ "$1" = "container" ] && [ "$2" = "exists" ] && exit 0
exit 0
EOF
chmod +x "$STUB_BIN/distrobox" "$STUB_BIN/podman"

printf 'ghostcmd\tmybox\n' > "$XDG_CACHE_HOME/sora/index"

expected="$SANDBOX/expected"
printf '%s\n' enter --name mybox -- ghostcmd 'a b' "it's" '' 'q"q' '$HOME' --flag > "$expected"

# Inner scripts use a QUOTED heredoc: every argument below is literal.
cat > "$SANDBOX/inner.sh" <<'EOF'
source "$HOOK_FILE"
ghostcmd "a b" "it's" "" "q\"q" '$HOME' --flag
echo "rc=$?"
EOF

check_record() { # shell-label
    diff -u "$expected" "$SORA_TEST_RECORD" ||
        fail "$1: arguments were not preserved through dispatch"
    rm -f "$SORA_TEST_RECORD"
}

# --- bash -------------------------------------------------------------------
out=$(HOOK_FILE="$HOOK_BASH" bash --norc "$SANDBOX/inner.sh" 2>&1)
assert_contains "$out" "rc=42" "bash: exit code propagates"
check_record bash

# --- zsh --------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
    out=$(HOOK_FILE="$HOOK_ZSH" zsh -f "$SANDBOX/inner.sh" 2>&1)
    assert_contains "$out" "rc=42" "zsh: exit code propagates"
    check_record zsh
else
    echo "note: zsh not installed; skipping zsh dispatch"
fi

# --- fish -------------------------------------------------------------------
if command -v fish >/dev/null 2>&1; then
    cat > "$SANDBOX/inner.fish" <<'EOF'
source $HOOK_FILE
fish_command_not_found ghostcmd "a b" "it's" "" "q\"q" '$HOME' --flag
echo "rc=$status"
EOF
    out=$(HOOK_FILE="$HOOK_FISH" fish "$SANDBOX/inner.fish" 2>&1)
    assert_contains "$out" "rc=42" "fish: exit code propagates (direct handler call)"
    check_record fish
else
    echo "note: fish not installed; skipping fish dispatch"
fi

# --- bash hash staleness ----------------------------------------------------
# A command that was hashed and then removed (e.g. 'brew uninstall neovim')
# must fall through to the hook instead of dying forever at the old path —
# hook.bash sets 'shopt -s checkhash' exactly for this.
cat > "$SANDBOX/inner_hash.sh" <<'EOF'
source "$HOOK_FILE"
mkdir -p "$HASH_BIN"
printf '#!/bin/sh\necho REAL\n' > "$HASH_BIN/ghostcmd"
chmod +x "$HASH_BIN/ghostcmd"
PATH="$HASH_BIN:$PATH"
ghostcmd                     # found on PATH, gets hashed
rm -f "$HASH_BIN/ghostcmd"
ghostcmd                     # hashed & gone -> checkhash -> hook -> stub
echo "rc=$?"
EOF
out=$(HOOK_FILE="$HOOK_BASH" HASH_BIN="$SANDBOX/hashbin" bash --norc "$SANDBOX/inner_hash.sh" 2>&1)
assert_contains "$out" "REAL" "hash test: the real binary ran while it existed"
assert_contains "$out" "rc=42" "stale hashed command falls through to the hook"
rm -f "$SORA_TEST_RECORD"

# --- stale index safety -----------------------------------------------------
# If the container is gone, the hook must NEVER reach distrobox (a stale
# index would otherwise trigger distrobox's scary "create it?" prompt).
cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_BIN/podman"
cat > "$STUB_BIN/docker" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_BIN/docker"

out=$(HOOK_FILE="$HOOK_BASH" bash --norc "$SANDBOX/inner.sh" 2>&1)
assert_contains "$out" "no longer exists" "bash: stale index yields a clear message"
assert_contains "$out" "rc=127" "bash: stale index returns 127"
[ ! -e "$SORA_TEST_RECORD" ] || fail "bash: distrobox must NOT be invoked when the container is missing"

echo "ok: dispatch argument preservation"
