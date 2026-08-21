#!/usr/bin/env bash
# 'sora provide pkcs11': a token driver lives in a box, the host's browsers use it.
#
# As in test_desktop.sh, the stub distrobox runs the REAL generated sora-pkcs11
# against a fake in-box world. The most valuable stub here is modutil: it is a
# working fake that writes a real pkcs11.txt, and it FAILS LOUDLY on -add, so a
# regression to the flag that loads a foreign-ABI .so turns the suite red.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

make_box_meta advbr 0

BOXBIN="$SANDBOX/boxbin"          # what "exists inside the box"
ORDER="$SANDBOX/order.log"
MODLOG="$SANDBOX/modutil.log"
NSSDB="$HOME/.pki/nssdb"
MODULES="$XDG_CONFIG_HOME/pkcs11/modules"
REG="$XDG_CONFIG_HOME/sora/provide.list"

export SORA_SYSROOT="$SANDBOX/sysroot"
mkdir -p "$BOXBIN" "$SORA_SYSROOT/usr/lib64"
: > "$SORA_SYSROOT/usr/lib64/p11-kit-proxy.so"
PROXY="$SORA_SYSROOT/usr/lib64/p11-kit-proxy.so"

cat > "$STUB_BIN/podman" <<'EOF'
#!/bin/sh
[ "$1" = container ] && [ "$2" = exists ] && exit 0
exit 1
EOF

cat > "$STUB_BIN/distrobox" <<EOF
#!/bin/sh
# Subcommands taking no '--' must be answered BEFORE scanning for one, or the
# scan spins forever and a hung test looks exactly like a slow one.
[ "\$1" = rm ] && { echo "distrobox rm" >> "$ORDER"; exit 0; }
while [ \$# -gt 0 ] && [ "\$1" != "--" ]; do shift; done
[ \$# -gt 0 ] || exit 0
shift
case "\$1" in
    # PATH is \$BOXBIN and NOTHING else. The fake box's world must not inherit
    # the host's: with ':\$PATH' appended, "the box has no modutil" silently
    # becomes "the host has modutil", which passes on a machine without
    # nss-tools and fails on one with it.
    *sora-pkcs11) PATH="$BOXBIN" exec /bin/sh "\$@" ;;
    *) exit 1 ;;
esac
EOF

# The real tools the fakes below shell out to, named explicitly. Anything not
# listed here does not exist inside the fake box, which is the point.
for t in grep sed awk mkdir mv rm cat printf; do
    p=$(command -v "$t") && ln -sf "$p" "$BOXBIN/$t"
done

cat > "$BOXBIN/p11-kit" <<'EOF'
#!/bin/sh
[ "$1" = --help ] && { printf 'usage\n  remote  run a module remotely\n'; exit 0; }
exit 0
EOF

# A working fake NSS module database. Everything the real modutil does that
# this feature depends on, and loud refusals for the two things it must never
# be asked to do.
cat > "$BOXBIN/modutil" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$MODLOG"
dbdir=''; op=''; arg=''; forced=0
while [ \$# -gt 0 ]; do
    case "\$1" in
        -dbdir)   dbdir=\${2#sql:}; shift ;;
        -force)   forced=1 ;;
        -create)  op=create ;;
        -rawadd)  op=rawadd; arg=\$2; shift ;;
        -delete)  op=delete; arg=\$2; shift ;;
        -add)     echo "REFUSED: -add LOADS the library" >&2; exit 1 ;;
    esac
    shift
done
[ "\$forced" = 1 ] || { echo "would prompt: shut down all browsers" >&2; exit 1; }
db="\$dbdir/pkcs11.txt"
case "\$op" in
    create) mkdir -p "\$dbdir"; printf 'library=\nname=NSS Internal PKCS #11 Module\n\n' > "\$db" ;;
    rawadd)
        lib=\$(printf '%s' "\$arg" | sed -n 's/.*library=\([^ ]*\).*/\1/p')
        nm=\$(printf '%s' "\$arg" | sed -n 's/.*name="\([^"]*\)".*/\1/p')
        mkdir -p "\$dbdir"
        printf 'library=%s\nname=%s\n\n' "\$lib" "\$nm" >> "\$db"
        echo "modutil -delete \$nm" >> "$ORDER" 2>/dev/null || :
        ;;
    delete)
        [ -f "\$db" ] || exit 1
        echo "modutil -delete \$arg" >> "$ORDER"
        awk -v n="name=\$arg" 'BEGIN{RS="";FS="\n"} \$0 !~ n { print \$0 "\n" }' "\$db" > "\$db.t"
        mv "\$db.t" "\$db"
        ;;
    *) exit 1 ;;
esac
exit 0
EOF
# Reproduces the CI runner, which ships libnss3-tools: a modutil on the HOST
# must never be reachable from inside the fake box. Without the hermetic PATH
# above, this file is what the "box has no modutil" case would find, and the
# test would pass on a machine without nss-tools and fail on one with it.
printf '#!/bin/sh\necho "HOST modutil leaked into the fake box" >&2\nexit 1\n' \
    > "$STUB_BIN/modutil"

# Reading is allowed; anything that changes permissions is not. sora prints the
# socket and override commands and must never run them - the socket exposes
# EVERY host PKCS#11 module to the sandbox, which is the machine owner's call.
FLATPAK_APPS="$SANDBOX/flatpak-apps"
RUNTIME_LOC="$SANDBOX/runtime"
mkdir -p "$RUNTIME_LOC/files/lib/x86_64-linux-gnu/pkcs11"
: > "$RUNTIME_LOC/files/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so"
: > "$FLATPAK_APPS"
cat > "$STUB_BIN/flatpak" <<EOF
#!/bin/sh
case "\$1 \$2" in
    "list --app") cat "$FLATPAK_APPS" ;;
    "info -m")    grep -qx "\$3" "$FLATPAK_APPS" && echo "runtime=org.freedesktop.Platform/x86_64/25.08" ;;
    "info --show-location") echo "$RUNTIME_LOC" ;;
    *) case "\$1" in
           list) cat "$FLATPAK_APPS" ;;
           info) grep -qx "\$2" "$FLATPAK_APPS" ;;
           *) echo "sora EXECUTED flatpak: \$*" >&2; exit 1 ;;
       esac ;;
esac
EOF
printf '#!/bin/sh\necho "sora EXECUTED systemctl: $*" >&2\nexit 1\n' > "$STUB_BIN/systemctl"
chmod +x "$STUB_BIN/podman" "$STUB_BIN/distrobox" "$STUB_BIN/modutil" \
    "$STUB_BIN/flatpak" "$STUB_BIN/systemctl" "$BOXBIN/p11-kit" "$BOXBIN/modutil"

# sora-pkcs11's 'check' mode tests that the library exists inside the box, and
# the fake box's filesystem is the host's, so the fixture is a real file under
# the sandbox at an absolute, whitespace-free path.
: > "$BOXBIN/libaetpkss.so"
LIB="$BOXBIN/libaetpkss.so"

# --- publishing a driver -----------------------------------------------------
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label safesign 2>&1) ||
    fail "provide pkcs11 failed: $out"

MOD="$MODULES/sora-advbr-safesign.module"
[ -f "$MOD" ] || fail "no module file at $MOD"

# The exact line, with an ABSOLUTE distrobox: a browser started from the menu
# has a PATH that frequently lacks it.
assert_eq "$(grep '^remote:' "$MOD")" \
    "remote: |$STUB_BIN/distrobox enter --name advbr -- p11-kit remote $LIB" \
    "the remote: line is exact and absolute"
assert_not_contains "$(cat "$MOD")" '$SORA' "no unexpanded generator variables"
assert_not_contains "$(cat "$MOD")" 'module:' "a remote module has no local path"
assert_contains "$(cat "$MOD")" 'Do not edit' "the file says it is generated"

assert_eq "$(cat "$REG")" \
    "sora-advbr-safesign${TAB}pkcs11${TAB}advbr${TAB}safesign${TAB}nss${TAB}$LIB" \
    "the registry row is exact"

# --- NSS registration --------------------------------------------------------
grep -q "^name=sora-p11-kit-proxy$" "$NSSDB/pkcs11.txt" || fail "the proxy was not registered"
grep -q "^library=$PROXY$" "$NSSDB/pkcs11.txt" || fail "the registered library is not the host proxy"
assert_contains "$(cat "$MODLOG")" "-rawadd" "registration goes through -rawadd"
assert_not_contains "$(cat "$MODLOG")" " -add " "-add must never be used: it LOADS the library"
assert_contains "$(cat "$MODLOG")" "-force" "modutil is never allowed to prompt"

# --- idempotency -------------------------------------------------------------
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label safesign 2>&1) ||
    fail "re-providing failed: $out"
assert_eq "$(grep -c '^name=sora-p11-kit-proxy$' "$NSSDB/pkcs11.txt")" "1" \
    "the proxy is registered exactly once"
assert_eq "$(grep -c . "$REG")" "1" "re-providing leaves exactly one row"

# --- a second label shares the single NSS registration -----------------------
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label serpro 2>&1) ||
    fail "second provision failed: $out"
assert_eq "$(grep -c . "$REG")" "2" "two provisions"
assert_eq "$(grep -c '^name=sora-p11-kit-proxy$' "$NSSDB/pkcs11.txt")" "1" \
    "still exactly one NSS registration"

# --- removing the first keeps NSS; removing the last takes it ----------------
out=$("$SORA_BIN" provide remove sora-advbr-safesign 2>&1) || fail "remove failed: $out"
[ -f "$MOD" ] && fail "the module file survived remove"
[ -f "$MODULES/sora-advbr-serpro.module" ] || fail "remove took the wrong module file"
grep -q "^name=sora-p11-kit-proxy$" "$NSSDB/pkcs11.txt" ||
    fail "NSS was unregistered while a provision still existed"

out=$("$SORA_BIN" provide remove sora-advbr-serpro 2>&1) || fail "second remove failed: $out"
assert_eq "$(grep -c . "$REG" || true)" "0" "the registry is empty"
grep -q "^name=sora-p11-kit-proxy$" "$NSSDB/pkcs11.txt" &&
    fail "NSS registration survived the removal of the last provision"

# --- the undo must never touch somebody else's registration ------------------
# This is the "could destroy user data" case: a p11-kit proxy registered by
# something that is not sora.
rm -rf "$NSSDB"; mkdir -p "$NSSDB"
printf 'library=/usr/lib64/p11-kit-proxy.so\nname=Foreign Proxy\n\n' > "$NSSDB/pkcs11.txt"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label tok 2>&1) ||
    fail "provide failed with a foreign proxy present: $out"
assert_contains "$out" "registered by something else" "the foreign registration is reported"
assert_eq "$(grep -c 'p11-kit-proxy' "$NSSDB/pkcs11.txt")" "1" \
    "sora must not add a second registration of the same library"
out=$("$SORA_BIN" provide remove sora-advbr-tok 2>&1) || fail "remove failed: $out"
grep -q "^name=Foreign Proxy$" "$NSSDB/pkcs11.txt" ||
    fail "the undo destroyed a registration sora did not create"

# --- --no-nss ----------------------------------------------------------------
rm -rf "$NSSDB"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label quiet --no-nss 2>&1) ||
    fail "--no-nss failed: $out"
[ -f "$MODULES/sora-advbr-quiet.module" ] || fail "--no-nss must still write the module file"
[ -f "$NSSDB/pkcs11.txt" ] && fail "--no-nss must not touch the NSS database"
assert_eq "$(awk -F'\t' '{print $5}' "$REG")" "nonss" "the intent is recorded, not inferred"
"$SORA_BIN" provide remove sora-advbr-quiet >/dev/null 2>&1

# --- backups -----------------------------------------------------------------
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label bak 2>&1) || fail "$out"
out=$("$SORA_BIN" provide remove sora-advbr-bak 2>&1) || fail "$out"
ls "$XDG_CACHE_HOME"/sora/nssdb/pkcs11.txt.* >/dev/null 2>&1 ||
    fail "no backup was taken before mutating the NSS database"

# --- preconditions: nothing partial survives a failure -----------------------
# p11-kit present but WITHOUT the 'remote' subcommand is the realistic shape of
# this failure: on Fedora that subcommand ships in a separate package
# (p11-kit-server), so having the binary is not enough.
cp "$BOXBIN/p11-kit" "$BOXBIN/p11-kit.bak"
printf '#!/bin/sh\n[ "$1" = --help ] && { printf "usage\\n  list-modules\\n"; exit 0; }\nexit 0\n' \
    > "$BOXBIN/p11-kit"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label nop 2>&1) &&
    fail "a box that cannot run 'p11-kit remote' must fail"
assert_contains "$out" "pacman -S p11-kit" "the exact install command for THIS box's pm"
[ -f "$MODULES/sora-advbr-nop.module" ] && fail "a failed precondition wrote a module file"
grep -q 'sora-advbr-nop' "$REG" 2>/dev/null && fail "a failed precondition wrote a registry row"
mv "$BOXBIN/p11-kit.bak" "$BOXBIN/p11-kit"

# --- a missing modutil must not roll the provision back ----------------------
rm -rf "$NSSDB"
mv "$BOXBIN/modutil" "$BOXBIN/modutil.off"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label nomod 2>&1) ||
    fail "a missing modutil must not fail the provision: $out"
[ -f "$MODULES/sora-advbr-nomod.module" ] || fail "the module file must still be written"
assert_contains "$out" "pacman -S nss" "the message names the package for THIS box's pm"
mv "$BOXBIN/modutil.off" "$BOXBIN/modutil"
"$SORA_BIN" provide remove sora-advbr-nomod >/dev/null 2>&1

# --- a host p11-kit that aborts must not fail the provision ------------------
# A PKCS#11 driver is allowed to SIGSEGV the process that loads it, and
# 'p11-kit list-modules' loads every module.
printf '#!/bin/sh\nkill -SEGV $$\n' > "$STUB_BIN/p11-kit"
chmod +x "$STUB_BIN/p11-kit"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label segv 2>&1) ||
    fail "a crashing host p11-kit must not fail the provision: $out"
[ -f "$MODULES/sora-advbr-segv.module" ] || fail "the module file must still be written"
rm -f "$STUB_BIN/p11-kit"

# --- list --------------------------------------------------------------------
out=$("$SORA_BIN" provide list)
assert_contains "$out" "NAME" "the list has a header"
assert_contains "$out" "sora-advbr-segv" "the provision is listed"
assert_contains "$out" "pkcs11" "the kind is shown"

# --- validation --------------------------------------------------------------
out=$("$SORA_BIN" provide remove nosuchthing 2>&1) && fail "removing a nonexistent name must fail"
assert_contains "$out" "is not provided" "the name is reported"

out=$("$SORA_BIN" provide pkcs11 relative/path --box advbr --label rel 2>&1) &&
    fail "a relative library path must fail"
assert_contains "$out" "INSIDE box" "the message says whose filesystem it is"

out=$("$SORA_BIN" provide pkcs11 "/usr/lib/my lib.so" --box advbr --label sp 2>&1) &&
    fail "a library path with a space must fail"
assert_contains "$out" "cannot quote" "the reason is p11-kit's lack of quoting"

out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label 'bad/label' 2>&1) &&
    fail "a label with a slash must fail"

# --- name collision ----------------------------------------------------------
make_box_meta advbr-x 0
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label x-tok 2>&1) || fail "$out"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr-x --label tok 2>&1) &&
    fail "a colliding derived name must be refused"
assert_contains "$out" "already used by box 'advbr' label 'x-tok'" \
    "the collision names both halves of the existing provision"

# --- doctor ------------------------------------------------------------------
out=$("$SORA_BIN" doctor 2>&1 || true)
assert_contains "$out" "ok" "doctor still runs"
rm -f "$MODULES/sora-advbr-segv.module"
out=$("$SORA_BIN" doctor 2>&1 || true)
assert_contains "$out" "sora-advbr-segv" "doctor flags a provision whose module file is gone"
: > "$MODULES/sora-orphan.module"
out=$("$SORA_BIN" doctor 2>&1 || true)
assert_contains "$out" "orphan module file" "doctor flags a module file with no registry row"
rm -f "$MODULES/sora-orphan.module"

# --- doctor must read the kind column, not assume pkcs11 ---------------------
# A row of another kind keeps its own meaning in columns 5 and 6. Reading every
# row as pkcs11 reported a perfectly good provision as broken and advised a
# 'remove' that would have destroyed it.
cp "$REG" "$SANDBOX/reg.bak"
printf 'sora-advbr-com.example.helper\tsomekind\tadvbr\tcom.example.helper\twrapper-name\t/opt/x/helper\n' \
    >> "$REG"
out=$("$SORA_BIN" doctor 2>&1 || true)
assert_not_contains "$out" "sora-advbr-com.example.helper' has no module file" \
    "a row of another kind is not judged against a .module file"
assert_contains "$out" "unknown kind 'somekind'" "an unrecognised kind is named as such"
cp "$SANDBOX/reg.bak" "$REG"

# The p11-kit host check must not fire for a host with no pkcs11 provision at
# all: it would be crying wolf on the one command people run when something is
# already wrong.
printf 'sora-advbr-com.example.helper\tsomekind\tadvbr\tcom.example.helper\twrapper-name\t/opt/x/helper\n' \
    > "$REG"
out=$("$SORA_BIN" doctor 2>&1 || true)
assert_not_contains "$out" "p11-kit is not installed on the host" \
    "no pkcs11 provision, no p11-kit complaint"
cp "$SANDBOX/reg.bak" "$REG"

# --- box rm must undo BEFORE the container is destroyed ----------------------
: > "$ORDER"
rm -rf "$NSSDB"
"$SORA_BIN" provide remove sora-advbr-x-tok >/dev/null 2>&1
"$SORA_BIN" provide remove sora-advbr-segv >/dev/null 2>&1
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label last 2>&1) || fail "$out"
: > "$ORDER"
out=$("$SORA_BIN" box rm advbr --yes 2>&1) || fail "box rm failed: $out"
[ -f "$MODULES/sora-advbr-last.module" ] && fail "box rm left a module file behind"
grep -q 'sora-advbr-last' "$REG" 2>/dev/null && fail "box rm left a registry row behind"
# Undoing a provision runs modutil INSIDE the box, so it has to happen while
# the container still exists.
assert_contains "$(cat "$ORDER")" "modutil -delete" "the NSS undo ran"
DEL_LINE=$(grep -n 'modutil -delete' "$ORDER" | head -n1 | cut -d: -f1)
RM_LINE=$(grep -n 'distrobox rm' "$ORDER" | head -n1 | cut -d: -f1)
[ -n "$RM_LINE" ] || fail "distrobox rm was never called"
[ "$DEL_LINE" -lt "$RM_LINE" ] ||
    fail "the NSS undo ran AFTER the container was destroyed (line $DEL_LINE vs $RM_LINE)"

# --- Firefox: one NSS database PER PROFILE -----------------------------------
# The Chromium family shares ~/.pki/nssdb. Firefox does not, so registering the
# proxy there alone leaves every Firefox blind - which is what this covers.
# Runs LAST, after 'box rm' emptied the registry: the NSS registration is a
# singleton that only goes when the last pkcs11 provision does, so a leftover
# row from an earlier block would (correctly) keep it alive and make the
# removal assertions below unreachable.
make_box_meta advbr 0
rm -rf "$NSSDB" "$MODULES"
P1="$HOME/.mozilla/firefox/abc.default"
P2="$HOME/.mozilla/firefox/xyz.dev"
# The XDG root exists because Firefox 147 moved the profile there, and the two
# coexist: an upgraded install keeps the old path.
P3="$XDG_CONFIG_HOME/mozilla/firefox/new.default"
NOTPROFILE="$HOME/.mozilla/firefox/Crash Reports"
mkdir -p "$P1" "$P2" "$P3" "$NOTPROFILE"
: > "$P1/prefs.js"; : > "$P2/prefs.js"; : > "$P3/prefs.js"
# P1 has been opened before; P2 and P3 never have, so they have no database at
# all - and -rawadd into a missing database is silently dropped.
printf 'library=\nname=NSS Internal PKCS #11 Module\n\n' > "$P1/pkcs11.txt"

out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label ff 2>&1) || fail "$out"

for d in "$P1" "$P2" "$P3" "$NSSDB"; do
    grep -q "^name=sora-p11-kit-proxy$" "$d/pkcs11.txt" 2>/dev/null ||
        fail "the proxy was not registered in $d"
done
[ -f "$NOTPROFILE/pkcs11.txt" ] && fail "a directory without prefs.js is not a profile"
assert_contains "$out" "4 NSS database(s)" "every database is reported"
# The never-opened profiles prove the database was created first: -rawadd alone
# would have reported success and written nothing.
assert_contains "$(cat "$MODLOG")" "sql:$P2" "the never-opened profile was targeted"

# --- idempotency across profiles ---------------------------------------------
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label ff2 2>&1) || fail "$out"
for d in "$P1" "$P2" "$P3"; do
    assert_eq "$(grep -c "^name=sora-p11-kit-proxy$" "$d/pkcs11.txt")" "1" \
        "re-providing did not duplicate the stanza in $d"
done

# --- a profile registered by something else is left alone --------------------
P4="$HOME/.mozilla/firefox/foreign.default"
mkdir -p "$P4"; : > "$P4/prefs.js"
printf 'library=/usr/lib64/p11-kit-proxy.so\nname=Someone Else\n\n' > "$P4/pkcs11.txt"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label ff3 2>&1) || fail "$out"
assert_contains "$out" "registered by something else" "the foreign profile is reported"
grep -q "^name=Someone Else$" "$P4/pkcs11.txt" || fail "the foreign registration was destroyed"
grep -q "^name=sora-p11-kit-proxy$" "$P4/pkcs11.txt" &&
    fail "sora registered into a profile that already had another proxy"

# --- removal covers every profile, and still spares the foreign one ----------
"$SORA_BIN" provide remove sora-advbr-ff >/dev/null 2>&1
"$SORA_BIN" provide remove sora-advbr-ff2 >/dev/null 2>&1
out=$("$SORA_BIN" provide remove sora-advbr-ff3 2>&1) || fail "$out"
for d in "$P1" "$P2" "$P3" "$NSSDB"; do
    grep -q "^name=sora-p11-kit-proxy$" "$d/pkcs11.txt" 2>/dev/null &&
        fail "removal left the proxy in $d"
done
grep -q "^name=Someone Else$" "$P4/pkcs11.txt" || fail "removal destroyed the foreign registration"
grep -q 'NSS Internal PKCS #11 Module' "$P1/pkcs11.txt" ||
    fail "removal destroyed the NSS Internal module in a profile"

# --- --no-nss touches no profile ---------------------------------------------
rm -rf "$NSSDB"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label quiet2 --no-nss 2>&1) || fail "$out"
for d in "$P1" "$P2" "$P3"; do
    grep -q "^name=sora-p11-kit-proxy$" "$d/pkcs11.txt" 2>/dev/null &&
        fail "--no-nss wrote into $d"
done
"$SORA_BIN" provide remove sora-advbr-quiet2 >/dev/null 2>&1
rm -rf "$HOME/.mozilla" "$XDG_CONFIG_HOME/mozilla"

# --- Flatpak browsers get the CLIENT, not the proxy --------------------------
# A .module is useless inside a sandbox: flatpak writes 'user-config: none' into
# every one of them, so no user module is read at all. p11-kit-client.so escapes
# that because NSS loads it directly as a library.
rm -rf "$NSSDB" "$MODULES" "$HOME/.mozilla" "$XDG_CONFIG_HOME/mozilla"
printf 'com.brave.Browser\norg.mozilla.firefox\n' > "$FLATPAK_APPS"
FB="$HOME/.var/app/com.brave.Browser/.pki/nssdb"
FF="$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox/p1.default"
GONE="$HOME/.var/app/com.leftover.App/.pki/nssdb"
mkdir -p "$FB" "$FF" "$GONE"
: > "$FF/prefs.js"

out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label fp 2>&1) || fail "$out"

grep -q "^name=sora-p11-kit-client$" "$FB/pkcs11.txt" 2>/dev/null ||
    fail "the client was not registered in the Flatpak Chromium database"
grep -q "^name=sora-p11-kit-client$" "$FF/pkcs11.txt" 2>/dev/null ||
    fail "the client was not registered in the Flatpak Firefox profile"
# The in-sandbox path, resolved through the runtime - not a host path.
grep -q "^library=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so$" "$FB/pkcs11.txt" ||
    fail "the registered library is not the runtime's client path"
grep -q "^name=sora-p11-kit-proxy$" "$FB/pkcs11.txt" &&
    fail "a sandbox database must get the client, never the proxy"
[ -f "$GONE/pkcs11.txt" ] && fail "wrote into an uninstalled Flatpak's leftover directory"

# Both permission steps are printed, never run.
assert_contains "$out" "flatpak override --user --filesystem=xdg-run/p11-kit/pkcs11 com.brave.Browser" \
    "the override command is printed"
assert_contains "$out" "systemctl --user enable --now p11-kit-server.socket" \
    "the socket command is printed"
assert_not_contains "$out" "sora EXECUTED flatpak" "sora must not run flatpak itself"
assert_not_contains "$out" "sora EXECUTED systemctl" "sora must not run systemctl itself"

# --- idempotency and a foreign client ----------------------------------------
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label fp2 2>&1) || fail "$out"
assert_eq "$(grep -c "^name=sora-p11-kit-client$" "$FB/pkcs11.txt")" "1" \
    "re-providing did not duplicate the client stanza"

FOREIGN="$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox/p2.default"
mkdir -p "$FOREIGN"; : > "$FOREIGN/prefs.js"
printf 'library=/usr/lib/pkcs11/p11-kit-client.so\nname=Someone Else\n\n' > "$FOREIGN/pkcs11.txt"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label fp3 2>&1) || fail "$out"
grep -q "^name=Someone Else$" "$FOREIGN/pkcs11.txt" || fail "a foreign client was destroyed"
grep -q "^name=sora-p11-kit-client$" "$FOREIGN/pkcs11.txt" &&
    fail "sora registered into a database that already had another client"

# --- removal takes the client and spares the foreign one ---------------------
"$SORA_BIN" provide remove sora-advbr-fp >/dev/null 2>&1
"$SORA_BIN" provide remove sora-advbr-fp2 >/dev/null 2>&1
out=$("$SORA_BIN" provide remove sora-advbr-fp3 2>&1) || fail "$out"
for d in "$FB" "$FF"; do
    grep -q "^name=sora-p11-kit-client$" "$d/pkcs11.txt" 2>/dev/null &&
        fail "removal left the client in $d"
done
grep -q "^name=Someone Else$" "$FOREIGN/pkcs11.txt" || fail "removal destroyed a foreign client"
assert_not_contains "$out" "sora EXECUTED flatpak" "removal must not revoke permissions"
rm -rf "$HOME/.var"

# --- host/box p11-kit version mismatch ---------------------------------------
# 'p11-kit remote' forwards the PKCS#11 function table over a pipe and the two
# ends have to agree. When they do not, nothing refuses at connect time: the
# slots enumerate, the PIN is accepted, the keys are found, and only C_SignInit
# fails with CKR_DEVICE_ERROR. So the check has to run at publish time - by
# signature time nobody is looking at p11-kit any more.
rm -rf "$NSSDB" "$MODULES"
: > "$FLATPAK_APPS"
# The host answers through rpm, the box through dpkg-query, which is the real
# shape of the failing pair: Fedora host, Debian box. The box's PATH is $BOXBIN
# and nothing else, so the two sides cannot answer through the same tool by
# accident.
printf '#!/bin/sh\nprintf 0.26.4-1.fc44\n' > "$STUB_BIN/rpm"
chmod 0755 "$STUB_BIN/rpm"
box_p11_version() { # version
    printf '#!/bin/sh\nprintf %s\n' "$1" > "$BOXBIN/dpkg-query"
    chmod 0755 "$BOXBIN/dpkg-query"
}

box_p11_version '0.25.5-3'
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label ver1 2>&1) ||
    fail "a version mismatch must not fail the provision: $out"
assert_contains "$out" "host p11-kit 0.26.4, box 'advbr' p11-kit 0.25.5" \
    "the warning names both versions and the box"
assert_contains "$out" "CKR_DEVICE_ERROR" "the warning names the error that will be seen"
[ -f "$MODULES/sora-advbr-ver1.module" ] ||
    fail "the warning is advisory; the module file must still be written"
"$SORA_BIN" provide remove sora-advbr-ver1 >/dev/null 2>&1

# 0.26.4 host with a 0.26.2 box is a pair that signs, so the comparison is on
# the series and a patch-level difference says nothing.
box_p11_version '0.26.2-1'
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label ver2 2>&1) || fail "$out"
assert_not_contains "$out" "CKR_DEVICE_ERROR" "a patch-level difference is not a mismatch"
"$SORA_BIN" provide remove sora-advbr-ver2 >/dev/null 2>&1

box_p11_version '1:0.26.4-3'
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label ver3 2>&1) || fail "$out"
assert_not_contains "$out" "CKR_DEVICE_ERROR" \
    "an epoch belongs to the packaging, not to p11-kit"
"$SORA_BIN" provide remove sora-advbr-ver3 >/dev/null 2>&1

# A box whose package manager cannot answer says nothing at all: a warning
# nobody can act on is noise.
rm -f "$BOXBIN/dpkg-query"
out=$("$SORA_BIN" provide pkcs11 "$LIB" --box advbr --label ver4 2>&1) || fail "$out"
assert_not_contains "$out" "CKR_DEVICE_ERROR" "an unknown version is silent"
"$SORA_BIN" provide remove sora-advbr-ver4 >/dev/null 2>&1
rm -f "$STUB_BIN/rpm"

echo "ok: provide pkcs11"
