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

![sora demo](docs/demo.gif)

*Above: `neofetch` resolves on the host (host always wins); `type screenfetch`
knows nothing — but running it dispatches into the ubuntu box transparently;
the typo `screenfetc` fails instantly without waking any container; and
`sora which screenfetch` shows how a command would resolve.*

## Installation

```sh
# Recommended: verified installer (checks the release sha256, installs to ~/.local)
curl -fsSL https://raw.githubusercontent.com/LLawli/sora/main/packaging/install.sh | sh

# Tarball, by hand (fallback)
curl -fsSL https://github.com/LLawli/sora/releases/latest/download/sora-0.1.0.tar.gz | tar xz
make -C sora-0.1.0 install PREFIX=~/.local

# mise
mise use -g github:LLawli/sora

# Homebrew (Linux or macOS host managing remote boxes)
brew install LLawli/tap/sora
```

Requirements: `distrobox` and `podman` (or docker). Pure shell — nothing to
compile, no runtime, `noarch` everywhere. There are deliberately **no native
distro packages** (COPR/AUR/deb/rpm): for a single shell script they add
review queues and maintenance for zero benefit — see
[docs/decisions.md](docs/decisions.md). Then, once:

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
| Tab completion | yes, see below (bash and zsh; fish reduced) | yes, plus the tool's own generator |
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

### Tab completion

The `sora` command completes itself out of the box — subcommands, flags, box
names for `--box`, indexed commands for `which` and `pin`, exported commands
for `anxious --remove`. It is installed to each shell's standard location by
`make install` and by the installer, and reads only local files, so completing
a sora command never enters a container either.

For the commands *inside* your boxes, completion splits into two problems, and
sora treats them separately.

**The command name** (`kubect<Tab>`). Your shell builds that list from PATH, so
a command that only lives in a box is never in it. sora merges the index into
the candidates: `complete -I` in bash, an extra completer in zsh. This is one
awk pass over a flat file, so **completing a name never touches a container**,
exactly like a miss. Nothing to configure; it comes with the hook.

**The arguments** (`apt-get inst<Tab>`). Four mechanisms, complementary rather
than competing, because their coverage does not overlap:

| | What it covers | Cost per Tab | Setup |
|---|---|---|---|
| Synced scripts | software that ships a completion script (most of a distro) | none for static scripts | automatic on `sora reindex` |
| The tool's own generator | cobra / clap / click tools | ~300 ms | `sora anxious <cmd> --box <box> --with-completion` |
| Live delegation | anything, with the box's live state | ~300 ms, always | `sora completion delegate <cmd> --box <box>` |
| carapace-bin | ~1600 known tools | ~300 ms | install carapace; no sora config needed |

```console
$ sora completion status                              # what is wired up
$ sora completion delegate systemctl --box archbox    # opt in to live completion
$ sora completion list | remove <command>
```

`sora reindex` copies each box's completion scripts to
`~/.local/share/sora/completions/`, picking one winner per command with the
same priority and pin rules as the index, so a pinned command can never
dispatch to one box while completing from another. Nothing is ever written
into your own `bash-completion` directory: sora chains bash-completion's
dynamic loader instead, so it cannot overwrite a file you put there.

Live delegation is opt-in per command because it enters the container on
**every** Tab. While the box is stopped those Tabs return nothing rather than
freezing your terminal for three seconds to wake it.

[carapace-bin](https://carapace-sh.github.io/carapace-bin/) needs no support
code: its specs describe the tool rather than its path, so the shell-outs land
on sora's wrapper or hook like any other command.

**fish support is reduced, and it is not fixable from sora's side.** Inside a
command substitution, fish discards the output of an unknown command even when
`fish_command_not_found` runs and prints successfully (bash returns the value
there; fish returns nothing). So for a late-resolved command, the *static* half
of a synced completion works, and anything that shells out to compute
candidates silently yields nothing. Live delegation and completing the command
name are bash and zsh only. What does work in fish: export the command with
`sora anxious --with-completion`. A wrapper is a real file in PATH, not an
unknown command, so nothing is discarded.

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
- The same fish behaviour, one level deeper, is what caps tab completion
  there: inside a command substitution fish throws away an unknown command's
  output entirely, so completions that shell out get nothing. See the tab
  completion section; `sora anxious --with-completion` is the way around it.
- Completing a command *name* needs bash 5.0+ (`complete -I`). On bash 4 the
  hook still resolves commands; only the name completion is skipped.
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
