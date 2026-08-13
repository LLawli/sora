#!/usr/bin/env bash
# sora-native-messaging: find a browser signing helper's manifest inside a box.
#
# The helper runs in the box and prints PATHS ONLY; the host copies the file
# out with 'podman cp'. That is not fussiness: piping a manifest through
# command substitution would strip its trailing newline, and the whole adapter
# rests on the copy being byte-exact.
#
# The script looks at $HOME before the system directories, so pointing HOME at
# a fixture exercises the real matching logic rather than a reimplementation
# of it — the technique test_desktop.sh established.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

NM="$SANDBOX/sora-native-messaging"
"$SORA_BIN" _template native-messaging > "$NM"
chmod +x "$NM"
sh -n "$NM" || fail "native-messaging: generated script fails sh -n"

BOXHOME="$SANDBOX/boxhome"
CHR="$BOXHOME/.config/google-chrome/NativeMessagingHosts"
FFX="$BOXHOME/.mozilla/native-messaging-hosts"
mkdir -p "$CHR" "$FFX"

cat > "$CHR/com.lacunasoftware.webpki.json" <<'EOF'
{
  "name": "com.lacunasoftware.webpki",
  "description": "Lacuna Web PKI",
  "path": "/opt/lacuna-webpki/webpki",
  "type": "stdio",
  "allowed_origins": [ "chrome-extension://dcngeagmmhegagicpcmpinaoklddcgon/" ]
}
EOF

cat > "$FFX/com.lacunasoftware.webpki.json" <<'EOF'
{
  "name": "com.lacunasoftware.webpki",
  "description": "Lacuna Web PKI",
  "path": "/opt/lacuna-webpki/webpki",
  "type": "stdio",
  "allowed_extensions": [ "webpki@lacunasoftware.com" ]
}
EOF

cat > "$CHR/br.com.softplan.websigner.json" <<'EOF'
{ "name": "br.com.softplan.websigner", "path": "/opt/softplan/websigner", "type": "stdio",
  "allowed_origins": [ "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/" ] }
EOF

# SORA_NM_ROOT points the SYSTEM directories at an empty tree, so the test
# does not depend on what the machine running it has in /etc: with the real
# ones in play, "the box has no such helper" would silently become "this
# developer has no such helper installed".
EMPTYROOT="$SANDBOX/sysroot"
mkdir -p "$EMPTYROOT"
run() { HOME="$BOXHOME" SORA_NM_ROOT="$EMPTYROOT" sh "$NM" "$@"; }

# --- find: both families, tagged ---------------------------------------------
out=$(run find com.lacunasoftware.webpki) || fail "find failed: $out"
assert_contains "$out" "chromium	$CHR/com.lacunasoftware.webpki.json" \
    "the chromium manifest is found and tagged"
assert_contains "$out" "firefox	$FFX/com.lacunasoftware.webpki.json" \
    "the firefox manifest is found and tagged"
assert_eq "$(printf '%s\n' "$out" | grep -c .)" "2" "one line per family, no more"

# A helper that only ships a chromium manifest yields exactly one line: the
# adapter must not then write anything into ~/.mozilla.
out=$(run find br.com.softplan.websigner) || fail "single-family find failed"
assert_eq "$(printf '%s\n' "$out" | grep -c .)" "1" "one family found, one line"
assert_contains "$out" "chromium	" "and it is the chromium one"

# --- system directories are searched, and searched FIRST ---------------------
# A vendor .deb or .rpm installs into /etc; the box's own ~/.config is usually
# empty. When both exist the packaged one is the real install.
SYSCHR="$EMPTYROOT/etc/opt/chrome/native-messaging-hosts"
mkdir -p "$SYSCHR"
cat > "$SYSCHR/com.lacunasoftware.webpki.json" <<'EOF'
{ "name": "com.lacunasoftware.webpki", "path": "/opt/lacuna-webpki/webpki", "type": "stdio",
  "allowed_origins": [ "chrome-extension://dcngeagmmhegagicpcmpinaoklddcgon/" ] }
EOF
out=$(run find com.lacunasoftware.webpki) || fail "find failed with a system manifest"
assert_contains "$out" "chromium	$SYSCHR/com.lacunasoftware.webpki.json" \
    "the packaged manifest wins over the one in the box's home"
assert_not_contains "$out" "$CHR/com.lacunasoftware.webpki.json" \
    "and the home one is not also returned"
rm -f "$SYSCHR/com.lacunasoftware.webpki.json"

# --- find: absent ------------------------------------------------------------
run find com.nobody.here >/dev/null 2>&1 && fail "an absent host-name must fail"

# --- list: what the box DOES have, for the error message ---------------------
out=$(run list) || fail "list failed"
assert_contains "$out" "com.lacunasoftware.webpki" "list names what is installed"
assert_contains "$out" "br.com.softplan.websigner" "list names every helper"
assert_eq "$(printf '%s\n' "$out" | grep -c .)" "3" "list reports each family separately"

# --- argument handling --------------------------------------------------------
run >/dev/null 2>&1 && fail "no arguments must be refused"
run find >/dev/null 2>&1 && fail "find with no host-name must be refused"
run bogus >/dev/null 2>&1 && fail "an unknown mode must be refused"

# --- nothing installed at all -------------------------------------------------
EMPTY="$SANDBOX/emptybox"
mkdir -p "$EMPTY"
HOME="$EMPTY" SORA_NM_ROOT="$EMPTYROOT" sh "$NM" find com.x >/dev/null 2>&1 && fail "an empty box must fail find"
out=$(HOME="$EMPTY" SORA_NM_ROOT="$EMPTYROOT" sh "$NM" list) || fail "list must succeed even when empty"
assert_eq "$out" "" "an empty box lists nothing"

echo "ok: sora-native-messaging"
