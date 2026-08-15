# Shared helpers for the sora test suite. Sourced by every test_*.sh.
# shellcheck disable=SC2034  # variables are consumed by the sourcing tests
set -u

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$TESTS_DIR")
SORA_BIN="$REPO_DIR/bin/sora"
MERGE_BIN="$REPO_DIR/libexec/sora-merge-index"
HOOK_BASH="$REPO_DIR/shell/hook.bash"
HOOK_ZSH="$REPO_DIR/shell/hook.zsh"
HOOK_FISH="$REPO_DIR/shell/hook.fish"
TAB=$(printf '\t')

# Every test runs in a throwaway sandbox: fake HOME + XDG dirs, and a stub
# bin dir that shadows real distrobox/podman.
setup_sandbox() {
    SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/sora-test.XXXXXX")
    trap 'rm -rf "$SANDBOX"' EXIT
    export HOME="$SANDBOX/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_DATA_HOME="$HOME/.local/share"
    # The runtime dir belongs in the sandbox too. Without it a test reads the
    # REAL /run/user/$UID, so "the p11-kit socket is not active" silently
    # becomes "this machine has no socket right now" - green until something
    # socket-activates it, then red.
    export XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir -p "$HOME" \
        "$XDG_CONFIG_HOME/sora/boxes" \
        "$XDG_CACHE_HOME/sora/index.d" \
        "$XDG_DATA_HOME/sora" \
        "$XDG_RUNTIME_DIR"
    STUB_BIN="$SANDBOX/stubbin"
    mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"
}

make_box_meta() { # name priority
    cat > "$XDG_CONFIG_HOME/sora/boxes/$1.toml" <<EOF
image = "docker.io/test/$1:latest"
package_manager = "pacman"
home = "$XDG_DATA_HOME/sora/homes/$1"
priority = $2
created = "2026-01-01T00:00:00Z"
last_indexed = ""
EOF
}

make_box_list() { # name cmd...
    local name=$1
    shift
    printf '%s\n' "$@" > "$XDG_CACHE_HOME/sora/index.d/$name.list"
}

run_merge() {
    "$MERGE_BIN" "$XDG_CONFIG_HOME/sora" "$XDG_CACHE_HOME/sora"
}

index_lookup() { # cmd
    awk -F'\t' -v c="$1" '$1 == c { print $2; exit }' "$XDG_CACHE_HOME/sora/index"
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

assert_eq() { # actual expected label
    [ "$1" = "$2" ] || fail "$3: expected [$2], got [$1]"
}

assert_contains() { # haystack needle label
    case $1 in
        *"$2"*) ;;
        *) fail "$3: expected output to contain [$2]; got:
$1" ;;
    esac
}

assert_not_contains() { # haystack needle label
    case $1 in
        *"$2"*) fail "$3: output must NOT contain [$2]; got:
$1" ;;
    esac
}

skip() { printf 'SKIP: %s\n' "$*"; exit 77; }
