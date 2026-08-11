#!/usr/bin/env bash
# Strategy B: live delegation. Opt-in per command, and a Tab must never wake
# a stopped box (that would read as a frozen terminal for ~3 seconds).
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

make_box_meta devbox 0
REG="$XDG_CONFIG_HOME/sora/delegate.list"
STATE="$SANDBOX/running"          # flips the fake container between states
printf 'false\n' > "$STATE"

cat > "$STUB_BIN/podman" <<EOF
#!/bin/sh
case "\$1 \$2" in
    "container exists")  exit 0 ;;
    "container inspect") cat "$STATE" ;;
esac
exit 0
EOF
cat > "$STUB_BIN/distrobox" <<'EOF'
#!/bin/sh
echo "ENTERED" >> "$SORA_TEST_TRACE"
while [ "$1" != "--" ]; do shift; done
shift
# $1 is the capture script, $2 the COMP_LINE
printf 'install\ninstall-suggests\n'
EOF
chmod +x "$STUB_BIN/podman" "$STUB_BIN/distrobox"
export SORA_TEST_TRACE="$SANDBOX/trace"
: > "$SORA_TEST_TRACE"

# --- registering ------------------------------------------------------------
out=$("$SORA_BIN" completion delegate apt-get --box devbox 2>&1) ||
    fail "delegate failed: $out"
assert_contains "$out" "complete live from box 'devbox'" "delegation is reported"
assert_eq "$(cat "$REG")" "apt-get${TAB}devbox" "registry line is written"

# The capture script must have been materialized where the box can see it.
[ -x "$XDG_DATA_HOME/sora/libexec/sora-capture-bash" ] ||
    fail "sora-capture-bash was not installed"

# --- listing reflects container state ---------------------------------------
out=$("$SORA_BIN" completion list)
assert_contains "$out" "stopped (Tabs skipped)" "list warns when the box is down"
printf 'true\n' > "$STATE"
out=$("$SORA_BIN" completion list)
assert_contains "$out" "running" "list shows a running box"

# --- the hidden _complete entry point ---------------------------------------
# 1. Without COMP_LINE there is nothing to complete: never enter a container.
: > "$SORA_TEST_TRACE"
out=$("$SORA_BIN" _complete devbox)
assert_eq "$out" "" "no COMP_LINE means no output"
assert_eq "$(grep -c ENTERED "$SORA_TEST_TRACE" || true)" "0" \
    "no COMP_LINE means no container entered"

# 2. With COMP_LINE and a running box, the box answers.
: > "$SORA_TEST_TRACE"
out=$(COMP_LINE='apt-get inst' COMP_POINT=12 "$SORA_BIN" _complete devbox)
assert_contains "$out" "install" "candidates come back from the box"
assert_eq "$(grep -c ENTERED "$SORA_TEST_TRACE")" "1" "the box was entered exactly once"

# 3. Stopped box: silence, and above all NO container entered.
printf 'false\n' > "$STATE"
: > "$SORA_TEST_TRACE"
out=$(COMP_LINE='apt-get inst' COMP_POINT=12 "$SORA_BIN" _complete devbox)
assert_eq "$out" "" "a stopped box yields no candidates"
assert_eq "$(grep -c ENTERED "$SORA_TEST_TRACE" || true)" "0" \
    "a Tab must never wake a stopped box"

# --- the bash hook registers the delegation ---------------------------------
out=$(bash --norc -c "
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
    source '$HOOK_BASH'
    complete -p apt-get 2>/dev/null
")
assert_contains "$out" "sora _complete devbox" "hook registers complete -C for the command"

# --- removal ----------------------------------------------------------------
out=$("$SORA_BIN" completion remove apt-get 2>&1) || fail "remove failed: $out"
assert_eq "$(cat "$REG")" "" "registry is emptied"
"$SORA_BIN" completion remove apt-get >/dev/null 2>&1 &&
    fail "removing a non-delegated command must fail"

# --- status -----------------------------------------------------------------
out=$("$SORA_BIN" completion status)
assert_contains "$out" "synced from boxes" "status covers strategy A"
assert_contains "$out" "delegated live" "status covers strategy B"

# --- the generated capture script is valid bash -----------------------------
"$SORA_BIN" _template capture-bash > "$SANDBOX/capture"
bash -n "$SANDBOX/capture" || fail "generated capture script is not valid bash"
assert_contains "$(cat "$SANDBOX/capture")" "_completion_loader" \
    "capture script asks bash-completion's lazy loader"

echo "ok: completion delegate"
