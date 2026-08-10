#!/usr/bin/env bash
# The generated files are where quoting bugs hide silently (they pass bash -n
# on the GENERATOR but break at runtime). So these tests assert on the
# GENERATED CONTENT, not just on the generator's syntax.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

# --- dnf5 actions file ------------------------------------------------------
out=$("$SORA_BIN" _template dnf5)
assert_contains "$out" 'post_transaction::::/usr/local/bin/sora-index-refresh' \
    "dnf5: post_transaction line with empty filter (4 colons)"
noncomment=$(printf '%s\n' "$out" | grep -cv '^#\|^$')
assert_eq "$noncomment" 1 "dnf5: exactly one action line"
path=$("$SORA_BIN" _template-path dnf5)
assert_eq "$path" "/etc/dnf/libdnf5-plugins/actions.d/sora.actions" "dnf5: hook path"

# --- apt conf ---------------------------------------------------------------
out=$("$SORA_BIN" _template apt)
assert_contains "$out" 'DPkg::Post-Invoke {"/usr/local/bin/sora-index-refresh || true";};' \
    "apt: Post-Invoke line with || true"
path=$("$SORA_BIN" _template-path apt)
assert_eq "$path" "/etc/apt/apt.conf.d/99-sora-index" "apt: hook path"

# --- pacman hook ------------------------------------------------------------
out=$("$SORA_BIN" _template pacman)
for needle in '[Trigger]' 'Operation = Install' 'Operation = Upgrade' \
              'Operation = Remove' 'Type = Package' 'Target = *' \
              '[Action]' 'When = PostTransaction' \
              'Exec = /usr/local/bin/sora-index-refresh'; do
    assert_contains "$out" "$needle" "pacman: hook contains [$needle]"
done
path=$("$SORA_BIN" _template-path pacman)
assert_eq "$path" "/etc/pacman.d/hooks/sora-index.hook" "pacman: hook path"
# distrobox deletes libalpm hooks matching *distrobox*; the FILENAME must
# never contain that string.
assert_not_contains "${path##*/}" "distrobox" "pacman: filename must not contain 'distrobox'"

# --- in-box trigger (runs as root, must drop to the user) -------------------
trigger="$SANDBOX/trigger"
"$SORA_BIN" _template trigger mybox > "$trigger"
sh -n "$trigger" || fail "trigger: generated script fails sh -n"
content=$(cat "$trigger")
assert_contains "$content" "runuser -u \"\$SORA_USER\"" "trigger: drops privileges via runuser"
assert_contains "$content" "SORA_USER='$(id -un)'" "trigger: username embedded at generation time"
assert_contains "$content" "SORA_BOX='mybox'" "trigger: box name embedded"
assert_contains "$content" "REINDEX='$XDG_DATA_HOME/sora/libexec/sora-reindex'" \
    "trigger: absolute reindex path embedded (never \$HOME at runtime)"
assert_not_contains "$content" '$SORA_DATA' "trigger: no unexpanded generator variables"
assert_not_contains "$content" '$SORA_CACHE' "trigger: no unexpanded generator variables"

# --- in-box reindex script --------------------------------------------------
reindex="$SANDBOX/reindex"
"$SORA_BIN" _template reindex > "$reindex"
sh -n "$reindex" || fail "reindex: generated script fails sh -n"
content=$(cat "$reindex")
assert_contains "$content" "CACHE_DIR='$XDG_CACHE_HOME/sora'" "reindex: absolute cache path embedded"
assert_contains "$content" "CONFIG_DIR='$XDG_CONFIG_HOME/sora'" "reindex: absolute config path embedded"
assert_contains "$content" "MERGE='$XDG_DATA_HOME/sora/libexec/sora-merge-index'" \
    "reindex: absolute merge path embedded"
assert_not_contains "$content" '$SORA_' "reindex: no unexpanded generator variables"

# Behavioral check: run the generated reindex against a fake root layout to
# prove it produces a list and calls the merge.
mkdir -p "$XDG_DATA_HOME/sora/libexec"
cp "$MERGE_BIN" "$XDG_DATA_HOME/sora/libexec/sora-merge-index"
chmod 0755 "$XDG_DATA_HOME/sora/libexec/sora-merge-index"
make_box_meta fakebox 5
sh "$reindex" fakebox || fail "reindex: generated script failed at runtime"
[ -f "$XDG_CACHE_HOME/sora/index.d/fakebox.list" ] || fail "reindex: did not write the box list"
grep -qx 'sh' "$XDG_CACHE_HOME/sora/index.d/fakebox.list" ||
    fail "reindex: expected 'sh' (from /usr/bin) in the generated list"
[ -f "$XDG_CACHE_HOME/sora/index" ] || fail "reindex: did not trigger the merge"
grep -q "^last_indexed = \"20" "$XDG_CONFIG_HOME/sora/boxes/fakebox.toml" ||
    fail "reindex: did not stamp last_indexed"

# --- in-box root install scripts -------------------------------------------
for pm in dnf5 apt pacman; do
    script="$SANDBOX/install-$pm.sh"
    "$SORA_BIN" _template inbox-install "$pm" > "$script"
    sh -n "$script" || fail "inbox-install $pm: generated script fails sh -n"
    content=$(cat "$script")
    assert_contains "$content" 'STAGE=/tmp/.sora-stage' \
        "inbox-install $pm: reads from container-private /tmp (root cannot read the 0700 home)"
    assert_contains "$content" '/usr/local/bin/sora-index-refresh' "inbox-install $pm: installs trigger"
done
content=$("$SORA_BIN" _template inbox-install dnf5)
assert_contains "$content" 'libdnf5-plugin-actions' \
    "inbox-install dnf5: installs the actions plugin (absent from fedora-toolbox)"

# --- helper scripts ---------------------------------------------------------
for t in detect-pm which; do
    "$SORA_BIN" _template "$t" > "$SANDBOX/$t"
    sh -n "$SANDBOX/$t" || fail "$t: generated script fails sh -n"
done

echo "ok: templates"
