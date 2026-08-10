#!/usr/bin/env bash
# sora integration test — uses REAL podman + distrobox and a disposable box.
#
# Opt-in on purpose: it pulls an image, creates a container, and writes to
# your real ~/.config/sora and ~/.cache/sora (a box named sora-itest-deb).
# Everything it creates is removed at the end.
#
#   RUN_INTEGRATION=1 tests/integration/run.sh
#
set -u

if [ "${RUN_INTEGRATION:-0}" != 1 ]; then
    echo "SKIP: set RUN_INTEGRATION=1 to run the integration test (creates a real container)"
    exit 0
fi

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$(dirname "$TESTS_DIR")")
SORA="$REPO_DIR/bin/sora"
BOX=sora-itest-deb
INDEX="${XDG_CACHE_HOME:-$HOME/.cache}/sora/index"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v distrobox >/dev/null 2>&1 || fail "distrobox not installed"
command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 || fail "no container manager"

cleanup() {
    "$SORA" box rm "$BOX" --yes --delete-home >/dev/null 2>&1
}
trap cleanup EXIT

echo "== creating box $BOX (debian) =="
"$SORA" box create "$BOX" --image debian || fail "box create failed"

echo "== index sanity =="
grep -q "^apt-get$(printf '\t')$BOX\$" "$INDEX" ||
    awk -F'\t' -v b="$BOX" '$1 == "apt-get" && $2 == b { found = 1 } END { exit !found }' "$INDEX" ||
    fail "apt-get not indexed to $BOX"

echo "== auto-reindex via apt hook =="
# 'sl' provides a binary that certainly did not exist before.
distrobox enter --name "$BOX" -- sudo apt-get install -y sl >/dev/null 2>&1 ||
    fail "apt-get install inside the box failed"
awk -F'\t' '$1 == "sl" { found = 1 } END { exit !found }' "$INDEX" ||
    fail "the apt Post-Invoke hook did not reindex 'sl' into the host index"

echo "== late resolution through the bash hook =="
out=$(bash --norc -c "source '$REPO_DIR/shell/hook.bash'; sl -h 2>&1 | head -1; exit 0")
case $out in
    *[Uu]sage*|*sl*) ;; # sl -h prints a usage line
    *) fail "dispatch through the hook did not reach the box command (got: $out)" ;;
esac

echo "== anxious export =="
"$SORA" anxious sl --box "$BOX" || fail "anxious export failed"
[ -x "$HOME/.local/bin/sl" ] || fail "wrapper not created in ~/.local/bin"
"$SORA" anxious --list | grep -q '^sl ' || fail "anxious --list does not show the export"
"$SORA" anxious --remove sl || fail "anxious --remove failed"
[ ! -e "$HOME/.local/bin/sl" ] || fail "wrapper not removed"

echo "== box rm cleans up =="
"$SORA" box rm "$BOX" --yes --delete-home || fail "box rm failed"
awk -F'\t' -v b="$BOX" '$2 == b { found = 1 } END { exit found }' "$INDEX" ||
    fail "index still references the removed box"
trap - EXIT

echo "ok: integration"
