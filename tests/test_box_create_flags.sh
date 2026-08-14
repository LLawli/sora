#!/usr/bin/env bash
# 'sora box create': the seam for distrobox's own creation flags.
#
# The point of the test is argument assembly, so the stub distrobox records its
# argv verbatim and the assertions read it back. That is the only way to catch
# the mistake this feature exists to prevent: --nvidia is NOT a container
# manager flag, so passing it through --additional-flags would hand it to
# podman, which does not know it, and the box would come up with no driver and
# no error.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

ARGV="$SANDBOX/argv.log"

cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
# No container exists yet; everything else is uninteresting here.
exit 1
EOF

cat > "$STUB_BIN/distrobox" <<EOF
#!/bin/sh
case "\$1" in
    create)
        # One argument per line, so an assertion can tell "two separate
        # --additional-flags" from "one with a space in it".
        for a in "\$@"; do printf '%s\n' "\$a"; done > "$ARGV"
        ;;
    enter)
        while [ \$# -gt 0 ] && [ "\$1" != "--" ]; do shift; done
        [ \$# -gt 0 ] || exit 0
        shift
        case "\$1" in
            *sora-detect-pm) printf 'apt\n' ;;
            *sora-reindex)   : ;;
            *) exit 0 ;;
        esac
        ;;
esac
EOF
chmod +x "$STUB_BIN/podman" "$STUB_BIN/distrobox"

argv() { cat "$ARGV"; }
# The value that follows a given flag, by position.
value_after() { # flag
    awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }' "$ARGV"
}

# --- the motivating case: a GPU box ------------------------------------------
out=$("$SORA_BIN" box create gpubox --image docker.io/nvidia/cuda:12.4.0-devel-ubuntu22.04 \
    --nvidia 2>&1) || fail "box create --nvidia failed: $out"

grep -qx -- '--nvidia' "$ARGV" || fail "--nvidia was not forwarded to distrobox"
# The whole reason this is a separate flag: handed to the container manager it
# would be an unknown option, and the failure is silent (CUDA finds no device).
grep -qx -- '--additional-flags' "$ARGV" &&
    fail "--nvidia must not be smuggled through --additional-flags"

# --- container-manager flags --------------------------------------------------
rm -f "$XDG_CONFIG_HOME/sora/boxes/rocmbox.toml"
out=$("$SORA_BIN" box create rocmbox --image debian \
    --additional-flags '--device /dev/kfd' \
    --additional-flags '--device /dev/dri' 2>&1) || fail "box create -a failed: $out"

assert_eq "$(grep -cx -- '--additional-flags' "$ARGV")" "2" \
    "each --additional-flags is passed separately (distrobox accumulates them)"
assert_contains "$(argv)" '--device /dev/kfd' "the first value arrives intact"
assert_contains "$(argv)" '--device /dev/dri' "the second value arrives intact"
assert_not_contains "$(argv)" '--nvidia' "--nvidia is not implied"

# --- --hide keeps working, and no longer owns --additional-flags --------------
# Before this change --hide was the only producer of --additional-flags, so the
# risk was that a user flag would replace the tmpfs mount rather than join it.
out=$("$SORA_BIN" box create hidebox --image debian \
    --hide .ssh --additional-flags '--pids-limit 100' 2>&1) || fail "combined failed: $out"

assert_eq "$(grep -cx -- '--additional-flags' "$ARGV")" "2" \
    "--hide and the user flag each get their own --additional-flags"
assert_contains "$(argv)" "--mount type=tmpfs,dst=$HOME/.ssh" "the --hide mount survives"
assert_contains "$(argv)" '--pids-limit 100' "and so does the user flag"

# --- everything else about the box is unchanged -------------------------------
assert_eq "$(value_after --name)" "hidebox" "the box name is still passed"
grep -qx -- '--yes' "$ARGV" || fail "the non-interactive flag is still passed"
[ -f "$XDG_CONFIG_HOME/sora/boxes/hidebox.toml" ] || fail "no metadata file was written"

# --- a flag needing a value must not silently eat the next option -------------
out=$("$SORA_BIN" box create novalue --image debian --additional-flags 2>&1) &&
    fail "--additional-flags with no value must fail"
assert_contains "$out" "needs a value" "the missing value is named"

echo "ok: box create flags"
