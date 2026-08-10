#!/bin/sh
# sora installer — FALLBACK ONLY. Prefer COPR (Fedora family) or AUR (Arch):
# package managers give you upgrades and clean removal; curl|sh gives neither.
#
#   curl -fsSL https://REPLACE_ME/install.sh | sh
#
# Installs into ~/.local by default (no root needed, survives OS image
# rebases on atomic distros). Override with PREFIX=/usr/local (needs root).
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
REPO="${SORA_REPO:-https://github.com/REPLACE_ME/sora}"
BRANCH="${SORA_BRANCH:-main}"

command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 1; }
command -v distrobox >/dev/null 2>&1 ||
    echo "warning: distrobox not found; install it before using sora" >&2

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Fetching sora ($BRANCH) ..."
git clone --depth 1 --branch "$BRANCH" "$REPO" "$tmp/sora"

echo "Installing to $PREFIX ..."
make -C "$tmp/sora" install PREFIX="$PREFIX"

case ":${PATH}:" in
    *":$PREFIX/bin:"*) ;;
    *) echo "note: add $PREFIX/bin to your PATH" ;;
esac

echo "Done. Next steps:"
echo "  sora box create mybox --image fedora"
echo "  sora hook install"
