#!/usr/bin/env bash
# 'sora anxious --path <abs> --as <name>': export a binary that is not in the
# box's PATH, under a name of your choosing.
#
# The case that motivated it: browser signing helpers live in /opt, so the
# reference implementation had to symlink them into /usr/local/bin as root
# inside the box just to give sora a name it could resolve.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

make_box_meta devbox 0

EXPORTLOG="$SANDBOX/export.log"

cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
[ "$1" = container ] && [ "$2" = exists ] && exit 0
exit 1
EOF

# sora-which stands in for 'command -v' inside the box: an absolute path
# echoes back only if the fake box "has" it; a bare name resolves under
# /usr/bin. That is exactly the real helper's contract.
cat > "$STUB_BIN/distrobox" <<EOF
#!/bin/sh
while [ \$# -gt 0 ] && [ "\$1" != "--" ]; do shift; done
[ \$# -gt 0 ] || exit 0
shift
case "\$1" in
    *sora-which)
        case "\$2" in
            /opt/vendor/tool|/opt/lacuna-webpki/webpki) printf '%s\n' "\$2" ;;
            /*) exit 1 ;;
            *)  printf '/usr/bin/%s\n' "\$2" ;;
        esac
        ;;
    distrobox-export)
        printf '%s\n' "\$*" >> "$EXPORTLOG"
        while [ \$# -gt 0 ]; do
            [ "\$1" = --bin ] && bin=\$2
            [ "\$1" = --export-path ] && dest=\$2
            shift
        done
        mkdir -p "\$dest"
        printf '#!/bin/sh\n# fake wrapper\n' > "\$dest/\${bin##*/}"
        chmod 0755 "\$dest/\${bin##*/}"
        ;;
esac
EOF
chmod +x "$STUB_BIN/podman" "$STUB_BIN/distrobox"

BIN="$HOME/.local/bin"
REG="$XDG_CONFIG_HOME/sora/anxious.list"

# --- the motivating case: a binary in /opt, renamed -------------------------
out=$("$SORA_BIN" anxious --path /opt/lacuna-webpki/webpki --as webpki-lacuna \
    --box devbox 2>&1) || fail "--path export failed: $out"
[ -x "$BIN/webpki-lacuna" ] || fail "no wrapper at $BIN/webpki-lacuna"
# The pre-rename name must not linger: it is what distrobox-export wrote, and
# leaving it behind would export a second, unrecorded command.
[ -e "$BIN/webpki" ] && fail "the pre-rename wrapper survived"

assert_eq "$(cut -f1 "$REG")" "webpki-lacuna" "the registry key is the chosen name"
assert_eq "$(cut -f5 "$REG")" "/opt/lacuna-webpki/webpki" "column 5 records the in-box path"
assert_eq "$(cut -f4 "$REG")" "$BIN/webpki-lacuna" "column 4 records the renamed wrapper"

# --- removal must not delete a sibling that happens to share the binary name -
# 'distrobox-export --delete' derives the target from the BINARY name, so for a
# renamed wrapper it would go after $EXPORT_PATH/webpki — someone else's export.
printf '#!/bin/sh\n# unrelated host export\n' > "$BIN/webpki"
chmod 0755 "$BIN/webpki"
: > "$EXPORTLOG"
out=$("$SORA_BIN" anxious --remove webpki-lacuna 2>&1) || fail "--remove failed: $out"
[ -e "$BIN/webpki-lacuna" ] && fail "the renamed wrapper survived --remove"
[ -x "$BIN/webpki" ] || fail "--remove deleted an unrelated wrapper that shared the binary name"
assert_not_contains "$(cat "$EXPORTLOG" 2>/dev/null || true)" "--delete" \
    "a renamed wrapper must not be removed through distrobox-export"
rm -f "$BIN/webpki"

# --- --as on its own is the rename half -------------------------------------
out=$("$SORA_BIN" anxious htop --as htop-box --box devbox 2>&1) ||
    fail "--as without --path failed: $out"
[ -x "$BIN/htop-box" ] || fail "no wrapper at $BIN/htop-box"
[ -e "$BIN/htop" ] && fail "the pre-rename wrapper survived"

# --- --path without --as takes the basename ---------------------------------
out=$("$SORA_BIN" anxious --path /opt/vendor/tool --box devbox 2>&1) ||
    fail "--path without --as failed: $out"
[ -x "$BIN/tool" ] || fail "no wrapper at $BIN/tool"

# --- validation -------------------------------------------------------------
out=$("$SORA_BIN" anxious --path /opt/vendor/tool sometool --box devbox 2>&1) &&
    fail "--path plus a positional name must fail"
assert_contains "$out" "mutually exclusive" "the conflict is named"

out=$("$SORA_BIN" anxious --path opt/vendor/tool --box devbox 2>&1) &&
    fail "a relative --path must fail"
assert_contains "$out" "absolute path inside the box" "the reason is named"

out=$("$SORA_BIN" anxious --path "/opt/my tool/bin" --box devbox 2>&1) &&
    fail "a --path containing a space must fail"
assert_contains "$out" "whitespace" "the reason is named"

out=$("$SORA_BIN" anxious --path '/opt/$(id)/x' --box devbox 2>&1) &&
    fail "a --path containing a command substitution must fail"

out=$("$SORA_BIN" anxious --path /opt/absent/thing --box devbox 2>&1) &&
    fail "a --path that does not exist in the box must fail"
assert_contains "$out" "not found (or is not executable) inside box" \
    "a missing path says so, and says it is about the box"

echo "ok: anxious --path/--as"
