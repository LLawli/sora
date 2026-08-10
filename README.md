# sora

**Type a command that only exists inside a distrobox container, and it just
runs — with host binaries always winning.**

[Leia em Português (BR)](README.pt-BR.md)

On immutable/atomic distros (Fedora Silverblue, Bluefin, Bazzite, Aurora,
openSUSE MicroOS, Vanilla OS) you keep your tools in distrobox containers —
and then pay for it on every invocation: `distrobox enter archbox --
neofetch`, again and again. The ecosystem solved the **container → host**
direction (`distrobox-host-exec`, `host-spawn`); sora solves the opposite
one, **host → container**:

```console
$ sora box create archbox --image arch
$ sora hook install
$ neofetch            # not on the host — runs from archbox, transparently
$ sora anxious --sudo pacman --box archbox
$ pacman -S steam     # works from scripts, .desktop files, cron, anywhere
```

No daemon, no PATH pollution, and a typo never wakes a container.

## Installation

```sh
# COPR (Fedora family — the primary channel)
sudo dnf copr enable <owner>/sora && sudo dnf install sora

# AUR (Arch Linux)
paru -S sora

# Tarball from the latest release
curl -fsSL https://github.com/REPLACE_ME/sora/releases/latest/download/sora-0.1.0.tar.gz | tar xz
make -C sora-0.1.0 install PREFIX=~/.local

# curl | sh (fallback; installs to ~/.local)
curl -fsSL https://REPLACE_ME/install.sh | sh

# From a checkout
make install PREFIX=~/.local
```

Requirements: `distrobox` and `podman` (or docker). Pure shell — nothing to
compile, no runtime. Then, once:

```console
$ sora hook install        # bash, zsh and fish
```

## Two complementary strategies

sora deliberately implements **both** models, because neither one covers the
other's territory:

1. **Late resolution** (the differentiator). Nothing is exported. PATH lookup
   is allowed to fail, and the shell's command-not-found hook resolves the
   miss against a cached `command → box` index. Important consequence: **host
   precedence is structural** — the hook only ever runs *after* the host PATH
   already failed, so nothing can ever shadow a host binary.

2. **Eager export on demand** (`sora anxious`). A real wrapper file is placed
   in PATH for one specific command, delegated to `distrobox-export` under the
   hood. This covers every context the late hook cannot reach.

| | Late resolution | Eager export |
|---|---|---|
| Works in | interactive shells with the hook installed | anything: scripts, `.desktop`, cron, other shells |
| Tab completion | no | yes (it is a file in PATH) |
| Coverage | every binary in every box, automatically | one command at a time, explicitly |
| PATH pollution | none | one file per exported command |
| Host precedence | structural (hook fires only after PATH misses) | depends on PATH order |

**Why not simply export everything?** A box has thousands of binaries.
Exporting them all floods PATH and tab completion, inverts precedence on any
name collision, and leaves stale wrappers behind on every package removal.
**Why the cached index?** The naive command-not-found handlers that circulate
forward *every* unknown word to a container — a typo like `gti status` wakes
a stopped container just to fail confusingly. sora's miss costs microseconds,
never touches a container, and verifies the container exists before
dispatching.

## Usage

### Boxes

```console
$ sora images                                  # alias catalog (any OCI image works)
$ sora box create archbox --image arch
$ sora box list
$ sora box enter archbox
$ sora box rm archbox [--delete-home]
```

`sora box create` applies two opinionated defaults, both overridable:

- **A dedicated home** per box (`~/.local/share/sora/homes/<box>`, disable
  with `--no-own-home`). This is *organization*, not isolation: it keeps
  packages installed in the box from scattering dotfiles into your host home.
  The host home stays bind-mounted at the same absolute path regardless —
  `--home` changes `$HOME`, it hides nothing. To actually hide sensitive
  subpaths, use `--hide` (tmpfs over them): `--hide .ssh --hide .gnupg`.
- **XDG folder symlinks** from the box home to the host's real folders
  (disable with `--no-xdg-links`), resolved with `xdg-user-dir` because the
  folders are localized ("Documentos", "Imagens"…).

Box metadata lives in `~/.config/sora/boxes/<box>.toml`: source image,
package-manager family (detected by **binary presence** inside the box, never
guessed from the image name; override with `--pkg-manager`), box home, index
priority, last-indexed timestamp.

### The index

```console
$ sora reindex [box...]        # rebuild (create/rm/pin already do this)
$ sora conflicts               # commands in >1 box, and who wins
$ sora pin python archbox      # manual override, beats priority
$ sora which python            # how a command would resolve (host vs box)
$ sora box set-priority archbox 50
```

Resolution order for a command present in several boxes: **pin → highest
priority → alphabetical box name** (deterministic). The index refreshes
itself: `sora box create` installs a hook *inside* the box using the package
manager's own mechanism (dnf5 actions plugin, apt `DPkg::Post-Invoke`,
pacman ALPM hook), so every install/remove transaction rewrites the host
index. Other managers (zypper, apk, …) need a manual `sora reindex <box>` —
sora warns about this at creation time.

### `sora anxious` — eager export

```console
$ sora anxious --sudo pacman --box archbox
$ sora anxious htop --box fedora
$ sora anxious --list
$ sora anxious --remove pacman
```

Wrappers land in `~/.local/bin`, generated by `distrobox-export` underneath.

**`--sudo` semantics — read this, everyone gets it wrong.** The wrapper runs
the command with `sudo` **inside** the container (distrobox already
configured `NOPASSWD` there). That is what lets you type `pacman -S steam`
directly in a host terminal, **without** host `sudo` in front. Prefixing host
`sudo` would break everything: it would target podman's *rootful* storage
instead of your rootless containers.

Package managers are the flagship use case for eager mode precisely because
they get invoked from scripts and other contexts where late resolution does
not apply.

### Shell hooks

```console
$ sora hook install [bash zsh fish]
$ sora hook status
$ sora doctor                  # sanity-check the whole setup
```

**Chaining is non-negotiable.** The command-not-found hook is usually already
occupied (`mise`, `pkgfile`, Debian's `command-not-found`, PackageKit on
Fedora). sora never overwrites it — it saves the previous handler and
delegates to it whenever it cannot resolve a command itself. Source sora's
hook **after** those tools (the installer appends to the end of your rc
file). When sora cannot resolve, the message distinguishes "no boxes
indexed" from "the command exists in no box". Arguments (spaces, quotes,
empty strings) reach the box intact; exit codes propagate.

## Limitations, honestly

- Late resolution requires an interactive shell with the hook installed —
  that's the whole reason `sora anxious` exists.
- fish forces the *reported* exit status of an unknown command to 127 even
  when the handler ran it successfully; the command runs and prints normally,
  only `$status` lies. bash and zsh propagate correctly.
- Argument fidelity through `distrobox enter` is as good as your distrobox
  version; sora passes `"$@"` untouched to it.
- In fish, sora installs to `conf.d`, which loads *before* `config.fish`; if
  another tool defines its handler in `config.fish`, source sora at the end
  of `config.fish` instead so it can chain.

## For contributors

Implementation detail deliberately lives out of this README:

- [docs/architecture.md](docs/architecture.md) — data flow, on-disk formats,
  generated scripts, and the six hard-won pitfalls the code encodes
  (keep-id/subuid permissions, sudo resetting `$HOME`, heredoc quoting…).
- [docs/decisions.md](docs/decisions.md) — why bash, why not a dedicated
  system user, why not a PATH shim, why not export everything, prior art.
- [docs/releasing.md](docs/releasing.md) — tag-triggered releases,
  `bin/release`.
- [CONTRIBUTING.md](CONTRIBUTING.md) — what CI enforces.

```console
$ make test           # sandboxed suite, stubs distrobox/podman
$ make lint           # shellcheck, strict
$ make integration    # opt-in: creates a real disposable box
```

## License

[MIT](LICENSE)
