#!/usr/bin/env bash
# sora-json-path: read and rewrite exactly one top-level string value, leaving
# every other byte of the file alone.
#
# The tests drive the CLI contract, not the awk. If someone later swaps the
# implementation for sed or jq, these fixtures decide whether that is
# acceptable — which is the point of testing the contract rather than the
# mechanism.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

JP="$SANDBOX/sora-json-path"
"$SORA_BIN" _template json-path > "$JP"
chmod +x "$JP"
sh -n "$JP" || fail "json-path: generated script fails sh -n"

F="$SANDBOX/f"

get()     { sh "$JP" get "$1" "${2:-path}"; }
getraw()  { sh "$JP" get-raw "$1" "${2:-path}"; }
setval()  { SORA_JP_VAL="$2" sh "$JP" set "$1" "${3:-path}"; }

# Every fixture must survive this: rewriting the value and then rewriting it
# back has to reproduce the original file byte for byte. It is the check that
# proves exactly one span moved, and it is also what the CLI runs at runtime
# before it puts a manifest in place.
roundtrip() { # file label
    local old new back
    old=$(getraw "$1") || fail "$2: get-raw failed"
    new="$SANDBOX/rt.new"; back="$SANDBOX/rt.back"
    setval "$1" "/NEW/PATH" > "$new" || fail "$2: set failed"
    SORA_JP_VAL="$old" sh "$JP" set "$new" path > "$back" || fail "$2: reverse set failed"
    cmp -s "$1" "$back" || fail "$2: the round trip is not byte-identical"
    cmp -s "$1" "$new" && fail "$2: set produced an identical file"
    assert_eq "$(get "$new")" "/NEW/PATH" "$2: the new value reads back"
}

# --- the ordinary case -------------------------------------------------------
cat > "$F" <<'EOF'
{
    "allowed_origins": [
        "chrome-extension://pdffhmdngciaglkoonimfcmckehcpafo/"
    ],
    "description": "KeePassXC integration",
    "name": "org.keepassxc.keepassxc_browser",
    "path": "/usr/bin/keepassxc-proxy",
    "type": "stdio"
}
EOF
assert_eq "$(get "$F")" "/usr/bin/keepassxc-proxy" "pretty: the value is found"
assert_eq "$(get "$F" name)" "org.keepassxc.keepassxc_browser" "pretty: another key"
roundtrip "$F" "pretty"
# The array must come through untouched, indentation included.
out=$(setval "$F" "/x")
assert_contains "$out" '        "chrome-extension://pdffhmdngciaglkoonimfcmckehcpafo/"' \
    "allowed_origins survives verbatim, indentation and all"

# --- minified ----------------------------------------------------------------
printf '{"name":"a","path":"/opt/x/bin","type":"stdio"}' > "$F"
assert_eq "$(get "$F")" "/opt/x/bin" "minified: found without any line anchor"
roundtrip "$F" "minified"

# --- 'path' inside a VALUE must not be mistaken for the key ------------------
cat > "$F" <<'EOF'
{"description":"the \"path\": /opt/decoy is a decoy","path":"/real/target"}
EOF
assert_eq "$(get "$F")" "/real/target" "a 'path' inside a string value is not a key"
roundtrip "$F" "decoy in value"

# --- nested object with its own path -----------------------------------------
printf '{"outer":{"path":"/nested/decoy"},"path":"/top/level"}' > "$F"
assert_eq "$(get "$F")" "/top/level" "only the TOP-level key is targeted"
roundtrip "$F" "nested"

# --- an array element that looks like a key ----------------------------------
printf '{"allowed_origins":["path","x:y"],"path":"/real"}' > "$F"
assert_eq "$(get "$F")" "/real" "an array element is never read as a key"
roundtrip "$F" "array element"

# --- escapes ------------------------------------------------------------------
printf '{"path":"/opt\\/vendor\\/bin","name":"x"}' > "$F"
assert_eq "$(get "$F")" "/opt/vendor/bin" "get decodes \\/ (legal JSON, seen in the wild)"
assert_eq "$(getraw "$F")" '/opt\/vendor\/bin' "get-raw leaves escapes intact"
roundtrip "$F" "escaped slashes"

printf '{"description":"a \\"quoted\\" thing","path":"/real"}' > "$F"
assert_eq "$(get "$F")" "/real" "string scanning honours \\\" inside a value"
roundtrip "$F" "escaped quote"

# \u is refused rather than guessed at.
printf '{"path":"/caf\\u00e9/bin"}' > "$F"
get "$F" >/dev/null 2>&1 && fail "get must refuse \\u rather than mis-decode it"
assert_contains "$(getraw "$F")" 'u00e9' "get-raw returns the escape undecoded"
roundtrip "$F" "unicode escape"

# --- byte fidelity at the edges ----------------------------------------------
printf '{"path":"/a"}' > "$F"                      # no trailing newline
roundtrip "$F" "no trailing newline"
assert_eq "$(setval "$F" /b | wc -c)" "13" "no newline is invented"

printf '{\r\n  "path": "/a"\r\n}\r\n' > "$F"       # CRLF
roundtrip "$F" "CRLF"
assert_eq "$(setval "$F" /b | tr -cd '\r' | wc -c)" "3" "every CR survives"

printf '{\n\t"path": "/a"\n}\n' > "$F"             # tab indentation
roundtrip "$F" "tabs"

# --- the awk -v trap ----------------------------------------------------------
# 'awk -v' interprets backslash escapes in the assigned value, so the new value
# travels through the environment instead. A literal backslash-t must stay two
# characters and not become a tab.
printf '{"path":"/a"}' > "$F"
out=$(setval "$F" '/tmp/x\ty')
assert_contains "$out" '/tmp/x\ty' "a literal backslash in the new value is not interpreted"
assert_eq "$(printf '%s' "$out" | tr -cd '\t' | wc -c)" "0" "no tab was produced"

# --- refusals -----------------------------------------------------------------
# The two failures mean different things to the caller: 1 is "this manifest
# simply has no such key", 2 is "do not touch this file at all".
rc_of() { get "$1" >/dev/null 2>&1; printf '%s\n' "$?"; }

printf '{"name":"a"}' > "$F"
assert_eq "$(rc_of "$F")" "1" "a missing key exits 1 (absent), not 2 (malformed)"

printf '{"path":"/a","path":"/b"}' > "$F"
assert_eq "$(rc_of "$F")" "2" "a duplicate top-level key is refused, not guessed at"

printf '{"path":"/a"' > "$F"
assert_eq "$(rc_of "$F")" "2" "an unbalanced object is refused"

printf '{"path":"/a' > "$F"
assert_eq "$(rc_of "$F")" "2" "an unterminated string is refused"

printf '{"path":42}' > "$F"
assert_eq "$(rc_of "$F")" "2" "a non-string value is refused"

sh "$JP" get "$SANDBOX/nope" path >/dev/null 2>&1 && fail "a missing file must be refused"
sh "$JP" >/dev/null 2>&1 && fail "no arguments must be refused"
sh "$JP" get "$F" >/dev/null 2>&1 && fail "a missing key argument must be refused"
printf '{"path":"/a"}' > "$F"
sh "$JP" set "$F" path >/dev/null 2>&1 && fail "set without SORA_JP_VAL must be refused"

# --- a big file, to catch quadratic behaviour --------------------------------
{
    printf '{"allowed_origins":['
    for i in $(seq 1 2000); do
        [ "$i" = 1 ] || printf ','
        printf '"chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaa%04d/"' "$i"
    done
    printf '],"path":"/big/target"}'
} > "$F"
assert_eq "$(get "$F")" "/big/target" "a large manifest still parses"
roundtrip "$F" "large manifest"

echo "ok: sora-json-path"
