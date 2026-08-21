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
| Host precedence | structural (hook fires only after PATH misses) | enforced: an export that would shadow a host binary is refused |

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

**Creation flags.** Two seams, because they target two different programs.
`--additional-flags` goes to the *container manager* (podman/docker) and is
repeatable, for devices, extra volumes or a CDI reference. `--nvidia` is
*distrobox's own*, and is what bind-mounts the host driver into the guest:

```console
$ sora box create cuda --image nvidia/cuda:12.4.0-devel-ubuntu22.04 --nvidia
$ sora box create rocm --image debian -a '--device /dev/kfd' -a '--device /dev/dri'
```

The distinction matters: passing `--additional-flags "--nvidia"` would hand
`--nvidia` to podman, which does not know it, and the box would come up with the
CUDA toolkit, no driver and no error. sora stays out of what these flags mean,
the same way it treats an image reference as opaque.

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

**Exporting something that is not in the box's PATH.** Integration binaries
usually are not: vendor tools land in `/opt`, and `anxious` resolves a command
*name*. `--path` takes the binary directly and `--as` names the export:

```console
$ sora anxious --path /opt/lacuna-webpki/webpki --as webpki-lacuna --box adv-br
```

`--as` works on its own too, when a box's name for something is not the name
you want on the host.

**An export that would shadow a host binary is refused.** "Host binaries always
win" is *structural* for late resolution — the hook only fires after PATH
already missed — but eager export writes a real file into `~/.local/bin`, which
usually precedes `/usr/bin`. So sora checks first and stops:

```console
$ sora anxious fd --box archbox
sora: warning: 'fd' already exists on the host: /usr/bin/fd
sora: warning: ~/.local/bin usually precedes /usr/bin, so this export would shadow it
sora: warning: pick another name with --as, or pass --force to shadow it deliberately
sora: error: refusing to shadow a host binary
```

The check costs nothing and runs before any container is touched.

### `sora anxious --desktop` — GUI apps in the menu

A graphical app in a box needs more than a wrapper: it needs a `.desktop`
entry, an icon the host can actually see, and — for a browser — the MIME
types that let it become the default handler.

```console
$ sora anxious --desktop chromium --box archbox
sora: found an entry inside 'archbox': Chromium
sora: name shown in the menu [Chromium]:
sora: generic name (e.g. Web Browser) [Web Browser]:
sora: one-line description [Access the Internet]:
sora: icon name inside the box [chromium]:
sora: menu categories [Network;WebBrowser;]:
sora: MimeType (empty for none) [text/html;x-scheme-handler/http;...]:
sora: search keywords [web;browser;]:
sora: imported 9 icon file(s) as 'sora-chromium'
sora: wrote ~/.local/share/applications/sora-chromium.desktop
sora: make 'Chromium' the host's default web browser? [y/N]
```

Every default is read out of the box's own entry first, so a packaged app is
mostly Enter, Enter, Enter. The questions only get real for the case
`distrobox-export --app` cannot serve at all: an app that ships **no**
`.desktop` (a tarball install, an AppImage, a browser dropped into `/opt`).

Every question is also a flag, so the same thing scripts:

```console
$ sora anxious --desktop chromium --box archbox --no-prompt \
    --name Chromium --browser --default-browser
```

`--name`, `--generic-name`, `--comment`, `--icon`, `--categories`, `--mime`,
`--keywords`, `--wmclass`, `--terminal`, `--browser`, `--default-browser`,
`--detect-wmclass`, `--no-prompt`. Without a tty, sora takes the defaults
instead of blocking.

**What this does that `distrobox-export --app` does not:**

- **It works with no `.desktop` in the box.** `distrobox-export` needs an
  existing entry to copy; this builds one from answers.
- **`Exec=` is the anxious wrapper**, by absolute path. No `distrobox enter`
  prefix, no quoting dance around the `%U` field codes — and because the
  wrapper works from any context, the app is eligible to be a default handler.
- **`Icon=` stays a name.** Every size found in the box is extracted into
  `~/.local/share/icons/hicolor/*/apps/sora-<cmd>.*`, so the icon theme keeps
  choosing resolution and dark variant. `distrobox-export` pins one absolute
  file and loses both.
- **`MimeType` is settable**, which is the only way a browser inside a box
  becomes the host's `http`/`https` handler. `--browser` fills it in and
  offers to run `xdg-settings` for you.
- **`StartupWMClass` is inherited, not guessed.** `distrobox-export` writes
  the name you typed; when that is wrong (Chromium reports
  `Chromium-browser`), the dock shows a second generic icon instead of
  grouping the window with its launcher. sora takes the value from the box's
  entry, and only when there is none does it offer to start the app once and
  read the class off the real window.

Window-class detection needs a compositor that will say what is on screen:
X11/XWayland via `xprop`, Hyprland via `hyprctl`, sway via `swaymsg`. GNOME on
Wayland exposes nothing, so there it tells you to find the class yourself and
pass `--wmclass`.

`sora anxious --remove <cmd>` takes the entry and every imported icon with it,
and so does `sora box rm` for everything that box provided: a launcher left
pointing at a deleted container is worse than no launcher.

### `sora provide` — publish a box resource to the host

Much of what you want out of a box is never typed by anyone. It is looked up
by a host program at its own integration point: NSS looking for a PKCS#11
module, a browser looking for a signing helper, the desktop looking for a MIME
handler. The shape is always the same — a host configuration file whose "run
this" field points at something that enters the box — and only the file format
changes. `anxious --desktop` is the first adapter of that shape; `provide` is
the general form.

Today it implements PKCS#11: a smartcard/token driver installed **only inside
a box**, usable by the host's browsers.

```console
$ sora provide pkcs11 /usr/lib/libaetpkss.so --box adv-br --label safesign
sora: wrote ~/.config/pkcs11/modules/sora-adv-br-safesign.module
sora: registered /usr/lib64/p11-kit-proxy.so in ~/.pki/nssdb as sora-p11-kit-proxy
sora: the host's p11-kit sees module 'sora-adv-br-safesign'
sora: restart Chromium/Brave/Chrome for them to pick up the module

$ sora provide list
$ sora provide remove sora-adv-br-safesign
```

Nothing is installed on the host. It works because p11-kit has had *remoting*
since 2017, built to forward a token over SSH: a module's configuration can
name a command that speaks the protocol on stdin/stdout instead of a local
library. Swapping `ssh` for `distrobox enter` is the whole trick. There is no
daemon and no socket — p11-kit starts the command on demand and it dies with
the consumer.

The `--no-nss` flag skips the NSS registration, which is what makes browsers
see the module. Chromium, Brave and Chrome share one database at
`~/.pki/nssdb`; **Firefox keeps one per profile**, so sora registers into every
profile it finds (both `~/.mozilla/firefox` and `$XDG_CONFIG_HOME/mozilla/firefox`
— Firefox 147 moved the profile and the two coexist). A profile that already
has a p11-kit proxy registered by something else is left alone.

**Flatpak browsers get a different library.** flatpak writes `user-config: none`
into every sandbox, so no user `.module` is read there at all; `p11-kit-client.so`
escapes that because NSS loads it directly. sora registers it, resolved through
the app's own runtime so the path is the one the sandbox sees, and prints the
two commands it needs — enabling `p11-kit-server.socket` and granting the app
`--filesystem=xdg-run/p11-kit/pkcs11`. Both loosen confinement, and the socket
exposes every PKCS#11 module the host has, not only the box's, so sora never
runs them for you. That registration is a singleton: it is written once however many
modules you publish, and removed when the last one goes. sora will not touch a
p11-kit proxy it did not register.

**A Flatpak app that is not a browser needs `--flatpak-app`.** NSS is one way an
application finds a PKCS#11 module; loading a `.so` by path is another, and only
the first leaves a database behind for sora to discover. A Java application on
`SunPKCS11` — PJeOffice Pro, the CNJ's signing app, is the case this was built
against — has no database anywhere, so discovery structurally cannot see it. But
the socket and the override are exactly what it needs: flatpak already writes a
`p11-kit-trust.module` pointing at `p11-kit-client.so` into every sandbox, and
swapping the socket makes that same module serve everything the host's p11-kit
knows, including a `remote:` module aimed into a box. `--flatpak-app <id>` names
what discovery cannot find; the app gets those two commands, and a registration
only if it does turn out to have a database. It works with `--no-nss` too:
that flag means "do not touch NSS", and neither of those commands is an NSS
matter.

**Both ends of the pipe have to run the same p11-kit.** Remoting forwards the
PKCS#11 function table, and when the versions disagree nothing refuses at
connect time: the slots enumerate, the PIN is accepted, the keys are found, and
only the signature fails, with `CKR_DEVICE_ERROR`. A Fedora host at 0.26.4 with
a Debian trixie box at 0.25.5 authenticates and cannot sign; the same host with
a Fedora 44 box at 0.26.2 signs. So sora reads the version on both sides while
publishing and says so — the module is still good for authentication, and
matching the versions is the fix.

The second adapter covers the other half of the smartcard problem:

```console
$ sora provide native-messaging com.lacunasoftware.webpki --box adv-br
```

A browser signing helper is not a library loaded into the browser — it is a
separate program the browser executes and talks to over stdin/stdout. So if it
runs inside the box it uses the box's driver, and the host's browser only needs
to know how to execute it. sora copies the manifest out of the box and rewrites
**only** its `path` field to point at an exported wrapper; `allowed_origins`
binds a manifest to a browser extension's ID and cannot be invented, which is
why the file is copied rather than constructed. Every other byte is preserved,
and that is verified before each file is put in place.

**The two adapters solve different problems and you may well want both.**
`pkcs11` is for *authentication* by certificate, where the browser itself loads
the module (Projudi, eproc, the PJe login, gov.br). `native-messaging` is for
*signing*, where a separate helper does the work.

For a Flatpak browser sora writes a small `flatpak-spawn` shim inside the app's
own config tree and points the manifest at that: a Flatpak browser executes the
manifest's `path` **inside its sandbox**, where distrobox does not exist, so a
bare host path silently never works. sora prints the one `flatpak override`
command that shim needs and leaves running it to you.

**What this cannot become.** Not "use any `.so` from the box". PKCS#11 is
remotable by a happy accident of design — a stable, coarse function table with
no callbacks and well-defined memory ownership — and even then somebody had to
write the marshalling by hand, function by function. The correct generalization
is upward, at the integration point, not downward at the ABI. See
[docs/rfc-provide.md](docs/rfc-provide.md).

**Security.** Publishing a box resource gives any host application the same
access it would have if the resource were local. That is equivalent, not worse
— but worth saying, because people reach for containers expecting the opposite.

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
- [docs/rfc-provide.md](docs/rfc-provide.md) — the design behind `sora
  provide`: why one command with adapters, why PKCS#11 is remotable and an
  arbitrary `.so` is not, the measurements, and the traps. PKCS#11 is shipped;
  the native-messaging adapter is still a proposal.
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
