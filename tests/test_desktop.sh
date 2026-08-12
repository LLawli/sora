#!/usr/bin/env bash
# 'sora anxious --desktop': build a .desktop entry for a GUI app in a box.
#
# The stub distrobox below runs the REAL generated sora-desktop-scan against a
# fake in-box HOME, rather than imitating what it would print. That script
# looks at $HOME/.local/share/applications before the system directories, so
# pointing HOME at a fixture exercises the actual entry-matching and icon-
# globbing logic, which is where the bugs live.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

make_box_meta guibox 0

BOXHOME="$SANDBOX/boxhome"
APPS="$BOXHOME/.local/share/applications"
ICONS="$BOXHOME/.local/share/icons/hicolor"
mkdir -p "$APPS" "$ICONS/48x48/apps" "$ICONS/256x256/apps" "$ICONS/scalable/apps"

# A packaged browser, with the two fields distrobox-export gets wrong:
# a StartupWMClass that does NOT match the command name, and sibling keys
# (GenericName, Name[pt_BR]) that an unanchored Name match would corrupt.
cat > "$APPS/chromium.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Chromium
Name[pt_BR]=Navegador Chromium
GenericName=Web Browser
Comment=Access the Internet
Exec=/usr/lib/chromium-browser/chromium-browser %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=Chromium-browser
Keywords=web;browser;
EOF

# A second entry that also mentions chromium but is a link handler: matching
# it instead of the real app would produce a launcher that opens nothing.
cat > "$APPS/chromium-url-handler.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Chromium URL Handler
NoDisplay=true
Exec=/usr/lib/chromium-browser/chromium-browser --open-url %u
Icon=chromium
EOF

printf 'PNG-48\n'  > "$ICONS/48x48/apps/chromium.png"
printf 'PNG-256\n' > "$ICONS/256x256/apps/chromium.png"
printf '<svg/>\n'  > "$ICONS/scalable/apps/chromium.svg"

cat > "$STUB_BIN/podman" <<EOF
#!/bin/sh
# 'container exists' answers yes; 'cp box:PATH DEST' copies from the fake box,
# whose paths are real host paths under the sandbox.
case "\$1" in
    container) [ "\$2" = exists ] && exit 0; exit 1 ;;
    cp)        src=\${2#*:}; cp "\$src" "\$3" ;;
    *)         exit 1 ;;
esac
EOF

cat > "$STUB_BIN/distrobox" <<EOF
#!/bin/sh
# Subcommands that take no '--' must be answered BEFORE scanning for one:
# 'while [ "\$1" != "--" ]; do shift; done' spins forever once the arguments
# run out, and a hung test looks exactly like a slow one.
[ "\$1" = rm ] && exit 0
while [ \$# -gt 0 ] && [ "\$1" != "--" ]; do shift; done
[ \$# -gt 0 ] || exit 0
shift
case "\$1" in
    *sora-which)        printf '/usr/bin/%s\n' "\$2" ;;
    *sora-desktop-scan) HOME="$BOXHOME" exec sh "\$1" "\$2" "\$3" ;;
    distrobox-export)
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

ENTRY="$XDG_DATA_HOME/applications/sora-chromium.desktop"
HICOLOR="$XDG_DATA_HOME/icons/hicolor"

field() { # file key   — same anchored read the CLI itself uses
    awk -F= -v k="$2" '
        /^\[/    { ingroup = ($0 == "[Desktop Entry]"); next }
        !ingroup { next }
        index($0, k "=") == 1 { sub(/^[^=]*=/, ""); print; exit }
    ' "$1"
}

# --- a packaged app: the box answers almost every question -------------------
out=$("$SORA_BIN" anxious --desktop chromium --box guibox --no-prompt 2>&1) ||
    fail "anxious --desktop failed: $out"
assert_contains "$out" "found an entry inside 'guibox'" "the box's own entry is found"
[ -f "$ENTRY" ] || fail "no desktop entry written at $ENTRY"

assert_eq "$(field "$ENTRY" Name)" "Chromium" "Name comes from the box"
assert_eq "$(field "$ENTRY" GenericName)" "Web Browser" "GenericName is carried over intact"
assert_eq "$(field "$ENTRY" Comment)" "Access the Internet" "Comment is carried over"
assert_eq "$(field "$ENTRY" Terminal)" "false" "a GUI app is not a terminal app"
assert_eq "$(field "$ENTRY" Categories)" "Network;WebBrowser;" "Categories survive"
assert_contains "$(field "$ENTRY" MimeType)" "x-scheme-handler/https" "MimeType survives"

# The whole point of hanging this off 'anxious': Exec is the wrapper, by
# absolute path. A bare name would depend on the session PATH containing
# ~/.local/bin, which no launcher guarantees.
assert_eq "$(field "$ENTRY" Exec)" "$HOME/.local/bin/chromium %U" \
    "Exec is the absolute wrapper path plus the field code"
[ -x "$HOME/.local/bin/chromium" ] || fail "the wrapper Exec points at does not exist"

# Inherited, not guessed. 'chromium' would have been wrong.
assert_eq "$(field "$ENTRY" StartupWMClass)" "Chromium-browser" \
    "StartupWMClass is inherited from the box entry"

# Regression against the distrobox-export bug this feature exists to avoid:
# an unanchored Name match corrupts every sibling key.
assert_not_contains "$(field "$ENTRY" GenericName)" "Chromium" \
    "GenericName must not be polluted by the Name value"

# --- icons: every size, one stable name --------------------------------------
assert_eq "$(field "$ENTRY" Icon)" "sora-chromium" "Icon is a theme NAME, not a path"
[ -f "$HICOLOR/48x48/apps/sora-chromium.png" ]   || fail "48x48 icon not imported"
[ -f "$HICOLOR/256x256/apps/sora-chromium.png" ] || fail "256x256 icon not imported"
[ -f "$HICOLOR/scalable/apps/sora-chromium.svg" ] || fail "scalable icon not imported"
assert_eq "$(cat "$HICOLOR/256x256/apps/sora-chromium.png")" "PNG-256" \
    "each size keeps its own content (not all copies of one file)"

# --- 'anxious --list' shows which exports have an entry ----------------------
out=$("$SORA_BIN" anxious --list)
assert_contains "$out" "DESKTOP" "the list has a DESKTOP column"
assert_contains "$out" "chromium" "the export is listed"

# --- an app with no .desktop at all: the case distrobox-export cannot serve --
out=$("$SORA_BIN" anxious --desktop tarballapp --box guibox --no-prompt \
    --name "Tarball App" --comment "Installed by hand" --icon missingicon 2>&1) ||
    fail "anxious --desktop failed for an app with no entry: $out"
assert_contains "$out" "ships no .desktop" "the missing entry is reported, not fatal"
assert_contains "$out" "no icon named 'missingicon'" "a missing icon warns"
TAR="$XDG_DATA_HOME/applications/sora-tarballapp.desktop"
assert_eq "$(field "$TAR" Name)" "Tarball App" "--name is used"
assert_eq "$(field "$TAR" Comment)" "Installed by hand" "--comment is used"
assert_eq "$(field "$TAR" Icon)" "missingicon" "a non-imported icon is kept verbatim"
assert_eq "$(field "$TAR" Exec)" "$HOME/.local/bin/tarballapp" \
    "no field code when the app takes no arguments"
[ -z "$(field "$TAR" MimeType)" ] || fail "a plain app must not claim MIME types"

# --- --browser fills in what makes a default handler possible ----------------
out=$("$SORA_BIN" anxious --desktop mybrowser --box guibox --no-prompt --browser 2>&1) ||
    fail "--browser failed: $out"
BR="$XDG_DATA_HOME/applications/sora-mybrowser.desktop"
assert_contains "$(field "$BR" MimeType)" "x-scheme-handler/http" \
    "--browser claims the http scheme"
assert_eq "$(field "$BR" Categories)" "Network;WebBrowser;" "--browser sets the categories"
assert_eq "$(field "$BR" Exec)" "$HOME/.local/bin/mybrowser %U" \
    "--browser implies the %U field code"

# --- the spec's own validator has the last word -----------------------------
# Hand-built .desktop files rot in ways that only show up as "the icon is just
# missing from the menu", with no error anywhere.
if command -v desktop-file-validate >/dev/null 2>&1; then
    for f in "$ENTRY" "$TAR" "$BR"; do
        desktop-file-validate "$f" || fail "desktop-file-validate rejected $f"
    done
else
    printf 'note: desktop-file-validate not installed, spec check skipped\n'
fi

# --- flags beat the box ------------------------------------------------------
out=$("$SORA_BIN" anxious --desktop chromium --box guibox --no-prompt \
    --name "My Chromium" --wmclass "custom-class" --terminal 2>&1) ||
    fail "flag override failed: $out"
assert_eq "$(field "$ENTRY" Name)" "My Chromium" "--name overrides the box value"
assert_eq "$(field "$ENTRY" StartupWMClass)" "custom-class" "--wmclass overrides"
assert_eq "$(field "$ENTRY" Terminal)" "true" "--terminal is honoured"

# --- a value with a newline must not be able to forge keys ------------------
# .desktop values are single-line. An unsanitized one does not error, it just
# turns every key after it into garbage the menu silently ignores.
out=$("$SORA_BIN" anxious --desktop eviltool --box guibox --no-prompt \
    --name "$(printf 'Evil\nExec=/bin/true')" 2>&1) || fail "newline case failed: $out"
EVIL="$XDG_DATA_HOME/applications/sora-eviltool.desktop"
assert_eq "$(field "$EVIL" Exec)" "$HOME/.local/bin/eviltool" \
    "a newline in --name cannot inject an Exec line"
assert_eq "$(grep -c '^Exec=' "$EVIL")" "1" "exactly one Exec key survives"

# --- desktop options without --desktop must not pass silently ---------------
out=$("$SORA_BIN" anxious somecmd --box guibox --icon foo 2>&1) &&
    fail "--icon without --desktop must fail"
assert_contains "$out" "only apply together with --desktop" "the mistake is named"

# --- no tty: take the defaults instead of blocking on a closed stdin --------
out=$("$SORA_BIN" anxious --desktop quiettool --box guibox < /dev/null 2>&1) ||
    fail "anxious --desktop must not fail without a tty: $out"
[ -f "$XDG_DATA_HOME/applications/sora-quiettool.desktop" ] ||
    fail "no entry written when stdin is closed"

# --- removal takes the entry and every icon with it -------------------------
out=$("$SORA_BIN" anxious --remove chromium 2>&1) || fail "anxious --remove failed: $out"
[ -f "$ENTRY" ] && fail "the desktop entry survived --remove"
for f in "$HICOLOR"/*/apps/sora-chromium.*; do
    [ -e "$f" ] && fail "an icon survived --remove: $f"
done
assert_contains "$out" "removed desktop entry" "removal is reported"

# --- box rm takes the entries of everything it exported ---------------------
[ -f "$XDG_DATA_HOME/applications/sora-mybrowser.desktop" ] ||
    fail "precondition: mybrowser entry should still exist"
out=$("$SORA_BIN" box rm guibox --yes 2>&1) || fail "box rm failed: $out"
[ -f "$XDG_DATA_HOME/applications/sora-mybrowser.desktop" ] &&
    fail "a desktop entry outlived the box it launches into"

echo "ok: anxious --desktop"
