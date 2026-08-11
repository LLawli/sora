#!/usr/bin/env bash
# The hook must go quiet while a completion is running.
#
# Why this matters: completion scripts shell out to the command itself (every
# cobra/clap tool does, on every Tab). For a box command that shell-out goes
# through the hook, and anything the hook writes to stderr lands on the line
# the user is typing. Stdout is a different story and is asserted here too:
# it must keep carrying the command's real output, or COMPREPLY breaks.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

printf 'boxcmd\ttestbox\n' > "$XDG_CACHE_HOME/sora/index"

cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
[ "$1" = container ] && [ "$2" = exists ] && exit 0
exit 1
EOF
# Mirrors the real distrobox: setup banner on stderr, command output on stdout.
cat > "$STUB_BIN/distrobox" <<'EOF'
#!/bin/sh
printf 'Starting container...\t[ OK ]\n' >&2
printf 'Container Setup Complete!\n' >&2
while [ "$1" != "--" ]; do shift; done
shift
[ "$1" = boxcmd ] || exit 127
printf 'apply\ndelete\n'
EOF
chmod +x "$STUB_BIN/podman" "$STUB_BIN/distrobox"

# 1. Outside a completion, the banner must still reach the user: it is the
#    only feedback that a cold box is waking up.
err=$(bash --norc 2>&1 >/dev/null <<EOF
source "$HOOK_BASH"
boxcmd
EOF
)
assert_contains "$err" "Starting container" "banner is visible outside completion"

# 2. Inside a completion (bash sets COMP_LINE), stderr must be silent...
err=$(bash --norc 2>&1 >/dev/null <<EOF
source "$HOOK_BASH"
COMP_LINE='boxcmd a' COMP_POINT=8
_c() { local out; out=\$(boxcmd __complete); COMPREPLY=(\$out); }
COMP_WORDS=(boxcmd a); COMP_CWORD=1
_c
EOF
)
assert_not_contains "$err" "Starting container" "banner is suppressed inside completion"
assert_not_contains "$err" "Setup Complete" "no decorative output inside completion"

# 3. ...while stdout still carries the candidates.
out=$(bash --norc 2>/dev/null <<EOF
source "$HOOK_BASH"
COMP_LINE='boxcmd a' COMP_POINT=8
COMP_WORDS=(boxcmd a); COMP_CWORD=1
COMPREPLY=()
out=\$(boxcmd __complete)
COMPREPLY=(\$out)
printf '%s\n' "\${#COMPREPLY[@]}" "\${COMPREPLY[@]}"
EOF
)
assert_contains "$out" "2" "COMPREPLY still receives both candidates"
assert_contains "$out" "apply" "candidate 'apply' survives"
assert_contains "$out" "delete" "candidate 'delete' survives"

# 4. A stale index (container gone) must not shout mid-Tab either.
printf 'boxcmd\tghostbox\n' > "$XDG_CACHE_HOME/sora/index"
cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_BIN/podman"
err=$(bash --norc 2>&1 >/dev/null <<EOF
source "$HOOK_BASH"
COMP_LINE='boxcmd a' COMP_POINT=8
out=\$(boxcmd __complete)
EOF
)
assert_not_contains "$err" "no longer exists" "stale-index warning is suppressed inside completion"

# 5. But outside a completion that warning is exactly what the user needs.
err=$(bash --norc 2>&1 >/dev/null <<EOF
source "$HOOK_BASH"
boxcmd
EOF
)
assert_contains "$err" "no longer exists" "stale-index warning is visible outside completion"

# 6. Unresolvable command: quiet mid-Tab, loud otherwise.
err=$(bash --norc 2>&1 >/dev/null <<EOF
source "$HOOK_BASH"
COMP_LINE='ghostcmd a' COMP_POINT=9
out=\$(ghostcmd __complete)
EOF
)
assert_not_contains "$err" "command not found" "not-found message suppressed inside completion"

# 7. zsh: same contract, driven by \$compstate instead of COMP_LINE.
if command -v zsh >/dev/null 2>&1; then
    printf 'boxcmd\ttestbox\n' > "$XDG_CACHE_HOME/sora/index"
    cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
[ "$1" = container ] && [ "$2" = exists ] && exit 0
exit 1
EOF
    chmod +x "$STUB_BIN/podman"
    # compstate cannot be faked outside a real completion widget, so this
    # asserts the other half of the OR: bashcompinit users, who do get
    # COMP_LINE. The compstate branch is covered by the pty test in
    # tests/integration.
    err=$(zsh -f 2>&1 >/dev/null <<EOF
source "$HOOK_ZSH"
COMP_LINE='boxcmd a'
out=\$(boxcmd __complete)
EOF
)
    assert_not_contains "$err" "Starting container" "zsh: banner suppressed under COMP_LINE"
    err=$(zsh -f 2>&1 >/dev/null <<EOF
source "$HOOK_ZSH"
boxcmd
EOF
)
    assert_contains "$err" "Starting container" "zsh: banner visible outside completion"
fi

echo "ok: completion stays quiet"
