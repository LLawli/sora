#!/usr/bin/env bash
# 'sora provide native-messaging': a browser signing helper lives in a box, the
# host's browsers execute it.
#
# The guarantee under test is byte-for-byte: the manifest is copied out of the
# box and only its 'path' field changes. allowed_origins binds the manifest to
# a browser extension's ID and cannot be invented, so losing it is not a thing
# that can be detected later.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

make_box_meta advbr 0

BOXROOT="$SANDBOX/boxroot"          # the fake box's filesystem
BOXHOME="$SANDBOX/boxhome"
CHR="$BOXROOT/etc/opt/chrome/native-messaging-hosts"
FFX="$BOXROOT/usr/lib/mozilla/native-messaging-hosts"
mkdir -p "$CHR" "$FFX" "$BOXHOME"
REG="$XDG_CONFIG_HOME/sora/provide.list"
BIN="$HOME/.local/bin"

# The two manifests a vendor ships, in the two formats. Deliberately awkward:
# one is pretty-printed with an array, the other is minified.
cat > "$CHR/com.lacunasoftware.webpki.json" <<'EOF'
{
  "name": "com.lacunasoftware.webpki",
  "description": "Lacuna Web PKI",
  "path": "/opt/lacuna-webpki/webpki",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://dcngeagmmhegagicpcmpinaoklddcgon/"
  ]
}
EOF
printf '{"name":"com.lacunasoftware.webpki","path":"/opt/lacuna-webpki/webpki","type":"stdio","allowed_extensions":["webpki@lacunasoftware.com"]}' \
    > "$FFX/com.lacunasoftware.webpki.json"

# --- host browser profiles ---------------------------------------------------
P_CHROMIUM="$XDG_CONFIG_HOME/chromium"
P_BRAVE="$XDG_CONFIG_HOME/BraveSoftware/Brave-Browser"
P_FF="$HOME/.mozilla"
P_FLAT="$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
mkdir -p "$P_CHROMIUM" "$P_BRAVE" "$P_FF" "$P_FLAT"

cat > "$STUB_BIN/podman" <<EOF
#!/bin/sh
case "\$1" in
    container) [ "\$2" = exists ] && exit 0; exit 1 ;;
    cp)        src=\${2#*:}; cp "\$src" "\$3" ;;
    *)         exit 1 ;;
esac
EOF

EXPORTLOG="$SANDBOX/export.log"
cat > "$STUB_BIN/distrobox" <<EOF
#!/bin/sh
[ "\$1" = rm ] && { echo "distrobox rm" >> "$SANDBOX/order.log"; exit 0; }
while [ \$# -gt 0 ] && [ "\$1" != "--" ]; do shift; done
[ \$# -gt 0 ] || exit 0
shift
case "\$1" in
    # The REAL generated scanner, against the fake box's filesystem. PATH is
    # not widened: a leak here would make the box's contents depend on the
    # machine running the suite.
    *sora-native-messaging) HOME="$BOXHOME" SORA_NM_ROOT="$BOXROOT" exec /bin/sh "\$@" ;;
    *sora-which)
        case "\$2" in
            /opt/lacuna-webpki/webpki) printf '%s\n' "\$2" ;;
            *) exit 1 ;;
        esac ;;
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

# sora must never execute flatpak: it prints the override command and leaves
# the decision to the user. This turns a regression red instead of silent.
printf '#!/bin/sh\necho "sora EXECUTED flatpak: $*" >&2\nexit 1\n' > "$STUB_BIN/flatpak"
chmod +x "$STUB_BIN/podman" "$STUB_BIN/distrobox" "$STUB_BIN/flatpak"

field() { "$XDG_DATA_HOME/sora/libexec/sora-json-path" get "$1" "$2"; }

# --- publishing --------------------------------------------------------------
out=$("$SORA_BIN" provide native-messaging com.lacunasoftware.webpki --box advbr 2>&1) ||
    fail "provide native-messaging failed: $out"

WRAP="$BIN/webpki-lacuna"
[ -x "$WRAP" ] || fail "no wrapper at $WRAP"
assert_contains "$(cat "$EXPORTLOG")" "/opt/lacuna-webpki/webpki" \
    "the binary named by the manifest is what got exported"

C_DEST="$P_CHROMIUM/NativeMessagingHosts/com.lacunasoftware.webpki.json"
B_DEST="$P_BRAVE/NativeMessagingHosts/com.lacunasoftware.webpki.json"
F_DEST="$P_FF/native-messaging-hosts/com.lacunasoftware.webpki.json"
FL_DEST="$P_FLAT/NativeMessagingHosts/com.lacunasoftware.webpki.json"
for f in "$C_DEST" "$B_DEST" "$F_DEST" "$FL_DEST"; do
    [ -f "$f" ] || fail "no manifest at $f"
done

# --- only 'path' changed ------------------------------------------------------
assert_eq "$(field "$C_DEST" path)" "$WRAP" "the chromium manifest points at the wrapper"
assert_eq "$(field "$F_DEST" path)" "$WRAP" "the firefox manifest points at the wrapper"
assert_eq "$(field "$C_DEST" name)" "com.lacunasoftware.webpki" "the name field is untouched"
# The byte-for-byte proof: rewrite the value back and compare with the original.
JP="$XDG_DATA_HOME/sora/libexec/sora-json-path"
SORA_JP_VAL="/opt/lacuna-webpki/webpki" "$JP" set "$C_DEST" path > "$SANDBOX/back.json"
cmp -s "$CHR/com.lacunasoftware.webpki.json" "$SANDBOX/back.json" ||
    fail "the chromium manifest differs from the original by more than the path"
SORA_JP_VAL="/opt/lacuna-webpki/webpki" "$JP" set "$F_DEST" path > "$SANDBOX/backf.json"
cmp -s "$FFX/com.lacunasoftware.webpki.json" "$SANDBOX/backf.json" ||
    fail "the firefox manifest differs from the original by more than the path"
assert_contains "$(cat "$C_DEST")" 'chrome-extension://dcngeagmmhegagicpcmpinaoklddcgon/' \
    "allowed_origins survives verbatim"
assert_contains "$(cat "$F_DEST")" 'webpki@lacunasoftware.com' \
    "allowed_extensions survives verbatim"

# --- the two families must not be crossed ------------------------------------
assert_not_contains "$(cat "$F_DEST")" 'allowed_origins' \
    "a chromium manifest must never be written into a firefox profile"
assert_not_contains "$(cat "$C_DEST")" 'allowed_extensions' \
    "and the reverse"

# --- flatpak: a shim, not a bare host path -----------------------------------
# A Flatpak browser execs the path INSIDE its sandbox, where distrobox does not
# exist, so pointing it straight at the wrapper produces a manifest that never
# works.
SHIM="$HOME/.var/app/com.brave.Browser/config/sora/com.lacunasoftware.webpki.sh"
[ -x "$SHIM" ] || fail "no flatpak shim at $SHIM"
assert_eq "$(field "$FL_DEST" path)" "$SHIM" "the flatpak manifest points at the shim"
assert_contains "$(cat "$SHIM")" "flatpak-spawn --host $WRAP" "the shim spawns on the host"
assert_contains "$out" "flatpak override --user --talk-name=org.freedesktop.Flatpak com.brave.Browser" \
    "the override command is printed for the user to run"
assert_not_contains "$out" "sora EXECUTED flatpak" "sora must not run flatpak itself"

# --- the registry ------------------------------------------------------------
assert_eq "$(cat "$REG")" \
"sora-advbr-com.lacunasoftware.webpki${TAB}native-messaging${TAB}advbr${TAB}com.lacunasoftware.webpki${TAB}webpki-lacuna${TAB}/opt/lacuna-webpki/webpki" \
    "the registry row is exact"

# --- list --------------------------------------------------------------------
out=$("$SORA_BIN" provide list)
assert_contains "$out" "native-messaging" "list shows the kind"
assert_contains "$out" "webpki-lacuna" "list shows the wrapper name, so it is never a mystery"
assert_not_contains "$out" "NO-FILE" "a healthy provision is not reported as missing"

# --- doctor ------------------------------------------------------------------
out=$("$SORA_BIN" doctor 2>&1 || true)
assert_not_contains "$out" "has no module file" "doctor does not judge it against a .module file"

# --- idempotency -------------------------------------------------------------
out=$("$SORA_BIN" provide native-messaging com.lacunasoftware.webpki --box advbr 2>&1) ||
    fail "re-publishing failed: $out"
assert_eq "$(grep -c . "$REG")" "1" "re-publishing leaves exactly one row"
SORA_JP_VAL="/opt/lacuna-webpki/webpki" "$JP" set "$C_DEST" path > "$SANDBOX/back2.json"
cmp -s "$CHR/com.lacunasoftware.webpki.json" "$SANDBOX/back2.json" ||
    fail "re-publishing changed the manifest"

# --- removal -----------------------------------------------------------------
out=$("$SORA_BIN" provide remove sora-advbr-com.lacunasoftware.webpki 2>&1) ||
    fail "remove failed: $out"
for f in "$C_DEST" "$B_DEST" "$F_DEST" "$FL_DEST" "$SHIM"; do
    [ -e "$f" ] && fail "remove left $f behind"
done
[ -e "$WRAP" ] && fail "remove left the wrapper behind"
assert_eq "$(grep -c . "$REG" || true)" "0" "the registry is empty"

# --- a manifest sora did not write must survive ------------------------------
# The counterpart of the foreign-NSS-proxy case: ownership is derived from the
# path field, so anything pointing elsewhere is somebody else's.
mkdir -p "$P_CHROMIUM/NativeMessagingHosts"
printf '{"name":"com.lacunasoftware.webpki","path":"/usr/bin/vendor-webpki","type":"stdio","allowed_origins":["chrome-extension://x/"]}' \
    > "$C_DEST"
cp "$C_DEST" "$SANDBOX/foreign.json"
out=$("$SORA_BIN" provide native-messaging com.lacunasoftware.webpki --box advbr 2>&1) ||
    fail "publishing over a vendor manifest failed: $out"
assert_contains "$out" "sora did not write" "the pre-existing manifest is reported"
ls "$XDG_CACHE_HOME"/sora/native-messaging/* >/dev/null 2>&1 ||
    fail "the vendor manifest was not backed up before being replaced"
out=$("$SORA_BIN" provide remove sora-advbr-com.lacunasoftware.webpki 2>&1) || fail "$out"
# Now plant a foreign one again and prove removal leaves it alone.
printf '{"name":"com.lacunasoftware.webpki","path":"/usr/bin/vendor-webpki","type":"stdio"}' > "$C_DEST"
out=$("$SORA_BIN" provide native-messaging com.lacunasoftware.webpki --box advbr 2>&1) || fail "$out"
printf '{"name":"com.lacunasoftware.webpki","path":"/usr/bin/vendor-webpki","type":"stdio"}' > "$B_DEST"
out=$("$SORA_BIN" provide remove sora-advbr-com.lacunasoftware.webpki 2>&1) || fail "$out"
[ -f "$B_DEST" ] || fail "removal destroyed a manifest sora did not write"
assert_contains "$out" "left $B_DEST alone" "and it says so"
rm -f "$B_DEST" "$C_DEST"

# --- --browsers restricts -----------------------------------------------------
out=$("$SORA_BIN" provide native-messaging com.lacunasoftware.webpki --box advbr \
    --browsers mozilla 2>&1) || fail "--browsers failed: $out"
[ -f "$F_DEST" ] || fail "--browsers mozilla did not write the firefox profile"
[ -f "$C_DEST" ] && fail "--browsers mozilla wrote a chromium profile"
"$SORA_BIN" provide remove sora-advbr-com.lacunasoftware.webpki >/dev/null 2>&1

# --- a wrapper name that would shadow a host binary --------------------------
HOSTBIN="$SANDBOX/hostbin"; mkdir -p "$HOSTBIN"
printf '#!/bin/sh\n:\n' > "$HOSTBIN/webpki-lacuna"; chmod 0755 "$HOSTBIN/webpki-lacuna"
out=$(PATH="$HOSTBIN:$PATH" "$SORA_BIN" provide native-messaging \
    com.lacunasoftware.webpki --box advbr 2>&1) &&
    fail "a wrapper that would shadow a host binary must abort"
assert_contains "$out" "refusing to shadow a host binary" "the anxious refusal surfaces"
assert_eq "$(grep -c . "$REG" || true)" "0" "a refused publish leaves no registry row"
[ -f "$C_DEST" ] && fail "a refused publish left a manifest behind"
rm -f "$HOSTBIN/webpki-lacuna"

# --- --as sidesteps it --------------------------------------------------------
out=$("$SORA_BIN" provide native-messaging com.lacunasoftware.webpki --box advbr \
    --as webpki-box 2>&1) || fail "--as failed: $out"
[ -x "$BIN/webpki-box" ] || fail "no wrapper at $BIN/webpki-box"
assert_eq "$(field "$C_DEST" path)" "$BIN/webpki-box" "the manifest points at the renamed wrapper"

# --- a second box providing the same host-name is refused --------------------
make_box_meta other 0
out=$("$SORA_BIN" provide native-messaging com.lacunasoftware.webpki --box other 2>&1) &&
    fail "two boxes providing one host-name must be refused"
assert_contains "$out" "already provides" "the conflict names the other box"

# --- an absent host-name says what the box DOES have -------------------------
out=$("$SORA_BIN" provide native-messaging com.nobody.here --box advbr 2>&1) &&
    fail "an absent host-name must fail"
assert_contains "$out" "com.lacunasoftware.webpki" "the error lists what the box provides"

# --- validation ---------------------------------------------------------------
out=$("$SORA_BIN" provide native-messaging 'Bad/Name' --box advbr 2>&1) &&
    fail "an invalid host name must be refused"
assert_contains "$out" "may only contain" "the charset is named"

# --- box rm purges before destroying the container ---------------------------
: > "$SANDBOX/order.log"
out=$("$SORA_BIN" box rm advbr --yes 2>&1) || fail "box rm failed: $out"
[ -f "$C_DEST" ] && fail "box rm left a manifest behind"
assert_eq "$(grep -c . "$REG" || true)" "0" "box rm emptied the registry"

echo "ok: provide native-messaging"
