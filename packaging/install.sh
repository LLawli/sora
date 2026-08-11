#!/bin/sh
# sora installer — the primary install path:
#
#   curl -fsSL https://raw.githubusercontent.com/LLawli/sora/main/packaging/install.sh | sh
#
# Downloads the latest release tarball, verifies its sha256 against the
# published checksum, and installs to ~/.local (no root; survives OS image
# rebases on atomic distros). Override the destination with PREFIX=/some/path.
#
# Requires only curl + tar + sha256sum — deliberately not make or git, since
# minimal/atomic hosts may lack both.
set -eu

REPO="${SORA_REPO:-LLawli/sora}"
PREFIX="${PREFIX:-$HOME/.local}"

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "error: tar is required" >&2; exit 1; }
command -v distrobox >/dev/null 2>&1 ||
    echo "warning: distrobox not found; install it before using sora" >&2

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "==> Finding the latest release of $REPO ..."
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null |
    sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1) || TAG=""

if [ -n "$TAG" ]; then
    VER=${TAG#v}
    ASSET="sora-$VER.tar.gz"
    URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
    echo "==> Downloading $ASSET ($TAG) ..."
    curl -fsSL -o "$tmp/$ASSET" "$URL"
    echo "==> Verifying checksum ..."
    curl -fsSL -o "$tmp/$ASSET.sha256" "$URL.sha256"
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$tmp" && sha256sum -c "$ASSET.sha256")
    else
        echo "warning: sha256sum not found; skipping checksum verification" >&2
    fi
    tar -xzf "$tmp/$ASSET" -C "$tmp"
    SRC="$tmp/sora-$VER"
else
    # No release yet (or the API is unreachable): fall back to the main
    # branch tarball. No checksum exists for this path — say so.
    echo "warning: no release found; falling back to the main branch (unverified)" >&2
    curl -fsSL -o "$tmp/main.tar.gz" "https://github.com/$REPO/archive/refs/heads/main.tar.gz"
    tar -xzf "$tmp/main.tar.gz" -C "$tmp"
    SRC="$tmp/sora-main"
fi

echo "==> Installing to $PREFIX ..."
install -D -m 0755 "$SRC/bin/sora" "$PREFIX/bin/sora"
install -D -m 0644 "$SRC/shell/hook.bash" "$PREFIX/share/sora/shell/hook.bash"
install -D -m 0644 "$SRC/shell/hook.zsh" "$PREFIX/share/sora/shell/hook.zsh"
install -D -m 0644 "$SRC/shell/hook.fish" "$PREFIX/share/sora/shell/hook.fish"
install -D -m 0755 "$SRC/libexec/sora-merge-index" "$PREFIX/share/sora/libexec/sora-merge-index"
# Completion for the sora CLI itself, in each shell's standard location.
install -D -m 0644 "$SRC/shell/completion.bash" \
    "$PREFIX/share/bash-completion/completions/sora"
install -D -m 0644 "$SRC/shell/completion.zsh" \
    "$PREFIX/share/zsh/site-functions/_sora"
install -D -m 0644 "$SRC/shell/completion.fish" \
    "$PREFIX/share/fish/vendor_completions.d/sora.fish"

case ":${PATH}:" in
    *":$PREFIX/bin:"*) ;;
    *) echo "note: add $PREFIX/bin to your PATH" ;;
esac

echo "Done. Next steps:"
echo "  sora box create mybox --image fedora"
echo "  sora hook install"
