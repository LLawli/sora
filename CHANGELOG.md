# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).
The release pipeline extracts the section for the tagged version into the
GitHub Release body — keep the `## [x.y.z]` heading format intact.

## [Unreleased]

### Added

- `sora provide pkcs11` now reads p11-kit's version on both sides and warns
  when the host and the box disagree.

  `p11-kit remote` forwards the PKCS#11 function table over a pipe, and the two
  ends have to agree. When they do not, nothing refuses at connect time: the
  slots enumerate, the PIN is accepted, `C_FindObjects` returns the keys, and
  only `C_SignInit` fails, with `CKR_DEVICE_ERROR`. Measured with a Fedora host
  at 0.26.4, a Debian trixie box at 0.25.5 logs in and cannot sign, while a
  Fedora 44 box at 0.26.2 signs. That first pair is the combination
  `sora-adv-br` builds by default, and it fails in the way that costs the most,
  because everything looks right up to the signature.

  The warning is advisory and never fatal: the module is still useful for
  authentication, which is the other half of what `provide` is for. It also
  does not name a bad version — which change between those releases does it was
  never bisected, so it reports that the two ends differ, which is what was
  established and what the reader can act on.

  p11-kit has no `--version` flag and no version string inside its binary, so
  the version comes from whoever installed it (`rpm`, `dpkg-query`, `pacman`,
  `apk`, then `pkg-config`), normalised to the upstream part. The soname is
  deliberately not used: Debian's 0.25.5 ships `libp11-kit.so.0.4.1` and
  Fedora's 0.26.4 ships `libp11-kit.so.0.4.10`, which agree on major.minor and
  differ in a number that means nothing to the person reading the warning.

## [0.4.0] - 2026-08-15

### Added

- `sora provide pkcs11` now reaches Flatpak browsers too, which completes the
  adapter: the module file, `~/.pki/nssdb`, every Firefox profile, and now
  every Flatpak browser database.

  A `.module` file is useless inside a sandbox. flatpak writes
  `user-config: none` into `/etc/pkcs11/pkcs11.conf` of every sandbox, from the
  flatpak binary rather than the runtime, so it holds for every app on every
  distribution and no user module is read at all. `p11-kit-client.so` escapes
  that because NSS loads it directly as a library, never consulting the p11-kit
  user configuration. It is resolved through the app's declared runtime, so the
  path written is the one the sandbox will actually see.

  It is registered under its own name, `sora-p11-kit-client`, because it is a
  different library doing a different job from the proxy, and ownership is
  derived from the name.

  The two steps that make it work both loosen confinement — enabling
  `p11-kit-server.socket` and granting the app `--filesystem=xdg-run/p11-kit/pkcs11`
  — so sora prints them and never runs them. The socket exposes every PKCS#11
  module the host has configured to the sandbox, not only the box's, which is
  the machine owner's decision. Removal does not revoke them either: sora did
  not grant them.

- `sora provide pkcs11` now registers the proxy in every Firefox profile, not
  only in the shared `~/.pki/nssdb`. Firefox keeps one NSS database per
  profile, so until now the module file was written and no Firefox saw it.

  Both profile roots are scanned: Firefox 147 moved the profile to
  `$XDG_CONFIG_HOME/mozilla/firefox` and the two coexist, because an upgraded
  install keeps the old path. A profile is a directory containing `prefs.js`,
  not something read out of `profiles.ini`, which takes relative paths and
  never lists a hand-made profile.

  A profile that already carries a p11-kit proxy registered by something else
  is reported and left alone, and removal spares it too. Success is taken from
  re-reading `pkcs11.txt`, never from modutil's exit status: a `-rawadd` into a
  profile that was never opened is silently dropped, so the database is created
  first.

  Flatpak browsers are still not covered, and that is a division of labour
  rather than an omission: inside a sandbox flatpak writes `user-config: none`
  and no user module is read at all, so that case needs `p11-kit-client.so`
  instead. Tracked in the same issue.

- `sora box create` gained `--additional-flags` (repeatable) and `--nvidia`,
  so a GPU box is creatable through sora instead of only through `distrobox
  create` directly — which cost the metadata file, the index, the priority and
  the package-manager hook, i.e. everything sora adds.

  They are two seams because they target two different programs:
  `--additional-flags` reaches the container manager, while `--nvidia` is
  distrobox's own and is what bind-mounts the host driver. Passing the latter
  through the former would hand `--nvidia` to podman, which does not know it,
  and the box would come up with the CUDA toolkit, no driver and no error.

  `--hide` no longer owns `--additional-flags`: distrobox accumulates the
  option, so the user's flags are appended alongside the tmpfs mounts rather
  than replacing them.

### Fixed

- `sora provide native-messaging` no longer writes into the leftover config
  tree of an uninstalled Flatpak. A directory under `~/.var/app` outlives the
  Flatpak, so discovery keyed on directories alone produced a manifest and an
  executable shim for a sandbox that no longer exists. Installed apps are now
  checked with a read-only `flatpak list` before writing.

  The filter is on the write path only, deliberately: an app uninstalled
  *after* sora wrote to it must still be cleaned up by `provide remove`, so
  discovery keeps reporting every directory. Both directions are tested.

## [0.3.0] - 2026-08-13

### Added

- `sora provide native-messaging <host-name> --box <box>` publishes a browser
  signing helper that lives in a box, so the host's browsers can use it. It is
  the complement of `provide pkcs11`: that one covers authentication by
  certificate, where the browser itself loads the module; this one covers
  signing, where a separate helper does the work over stdin/stdout.

  The manifest is copied out of the box and rewritten with **only** its `path`
  field changed, because `allowed_origins` binds a manifest to a browser
  extension's ID and cannot be invented. Every destination is verified before
  the file is put in place: setting the rewritten copy back to its old value
  has to reproduce the original byte for byte.

  Profiles are discovered rather than listed, including Flatpak ones. A Flatpak
  browser executes the manifest's path *inside its sandbox*, where distrobox
  does not exist, so sora writes a `flatpak-spawn` shim into the app's own
  config tree and prints the one `flatpak override` command it needs, without
  running it.

  `--extension-id` (repeatable) additionally allows a sideloaded extension.
  Each id is routed to the family whose format it has, since a Chromium id (32
  characters, a-p) is never a Firefox one (`{uuid}` or `name@domain`). It is
  the one operation that relaxes the byte-for-byte guarantee, which is why it
  is opt-in and separately verified.

  Under it, a generated `sora-json-path` reads and rewrites exactly one
  top-level JSON value, preserving every other byte. It is awk, not jq or
  python3: awk is already a hard dependency of sora and those are not, and an
  adapter that failed on a host where the rest of sora works would be the worse
  outcome.

- `sora provide` registers a box resource at a host integration point, with
  PKCS#11 as its first adapter: a token driver installed only inside a box,
  usable by the host's browsers, with nothing installed on the host.

  ```
  sora provide pkcs11 <library> --box <box> --label <label> [--no-nss]
  sora provide list
  sora provide remove <name>
  ```

  It works because p11-kit has had remoting since 2017, built to forward a
  token over SSH: a module configuration can name a command speaking the
  protocol on stdin/stdout instead of a local library, so `ssh` becomes
  `distrobox enter`. No daemon, no socket — the command starts on demand and
  dies with its consumer.

  The `~/.pki/nssdb` registration that makes Chromium/Brave/Chrome see the
  modules is a singleton: written once regardless of how many modules are
  published, removed when the last one goes, and never applied to a p11-kit
  proxy sora did not register. `--no-nss` skips it. `sora doctor` gained
  checks for missing module files, orphans, dead boxes, a `distrobox` path
  that moved out from under a module, and provisions with no NSS proxy behind
  them. `sora box rm` undoes provisions *before* destroying the container,
  since undoing one runs `modutil` inside it.

  Design and measurements: [docs/rfc-provide.md](docs/rfc-provide.md).

- `sora anxious --path <abs-path-in-box> --as <name> --box <box>` exports a
  binary that is not in the box's `PATH`, under a name you choose. Integration
  binaries usually are not in `PATH` (vendor tools land in `/opt`), and until
  now the only way through was to symlink into `/usr/local/bin` as root inside
  the box just to give sora a name it could resolve. `--as` also works on its
  own, to export under a different name than the box uses. No new in-box
  helper was needed: `command -v` already echoes an absolute path back iff it
  is executable, which is the same question `sora-which` was answering.

- `sora anxious --desktop <cmd> --box <box>` writes a `.desktop` entry for a
  graphical app in a box, asking only for what it cannot read off the box.
  Defaults are seeded from the app's own entry inside the container, so a
  packaged app is mostly Enter; the questions matter for the case
  `distrobox-export --app` cannot serve at all, an app that ships no
  `.desktop` (tarball, AppImage, a browser in `/opt`).

  Against `distrobox-export --app`: `Exec=` is the anxious wrapper by absolute
  path, so there is no `distrobox enter` prefix and no quoting around the `%U`
  field codes; `Icon=` stays a theme name with every size extracted into
  `~/.local/share/icons/hicolor/*/apps/sora-<cmd>.*`, instead of one pinned
  absolute file that loses per-size and dark variants; `MimeType` is settable,
  which is what lets a browser in a box become the host's `http`/`https`
  handler (`--browser` fills it in and offers `xdg-settings`); and
  `StartupWMClass` is inherited from the box's entry rather than guessed from
  the command name, with an optional detection pass (`xprop`, `hyprctl`,
  `swaymsg`) when there is nothing to inherit.

  Every question is also a flag — `--name`, `--generic-name`, `--comment`,
  `--icon`, `--categories`, `--mime`, `--keywords`, `--wmclass`, `--terminal`,
  `--browser`, `--default-browser`, `--detect-wmclass`, `--no-prompt` — so the
  wizard collapses into a one-liner for provisioning scripts. Without a tty it
  takes the defaults instead of blocking. Using any of them without
  `--desktop` is an error rather than a silently ignored flag.

- `sora anxious --list` gained a DESKTOP column showing which exports have an
  entry.

### Changed

- `sora anxious` now refuses an export that would shadow a host binary, with
  `--force` to do it deliberately. "Host binaries always win" is the project's
  headline claim and it is *structural* for late resolution (the hook fires
  only after `PATH` already missed), but nothing enforced it for eager export,
  which writes a real file into `~/.local/bin` — usually ahead of `/usr/bin`.
  The check is free and runs before any container is touched. Re-exporting an
  existing export is still idempotent: sora's own wrapper is not a conflict.

- `sora anxious --remove` now also removes the desktop entry and every icon it
  imported, and `sora box rm` does the same for every command that box
  provided: a launcher pointing into a deleted container is worse than no
  launcher.

### Fixed

- `sora anxious --remove` no longer risks deleting an unrelated wrapper.
  `distrobox-export --delete` derives its target from the *binary* name, so
  for a wrapper renamed with `--as` it would have gone after
  `~/.local/bin/<binary>` — potentially another command's export. Whether a
  rename happened is derived from the two names the registry already carries,
  so the on-disk format is unchanged.

- `sora doctor` no longer judges every provision against a PKCS#11 module
  file. It discarded the registry's `kind` column, so a provision of any other
  kind was reported as broken with advice to `sora provide remove` it — which
  would have destroyed a working provision. The p11-kit host check is likewise
  gated on there actually being a pkcs11 provision.

## [0.2.1] - 2026-08-11

### Added

- The `sora` CLI now completes itself, in bash, zsh and fish: subcommands and
  their subcommands, flags, box names for `--box` and `box enter|rm|
  set-priority`, indexed commands for `which`, `pin` and `completion delegate`,
  exported commands for `anxious --remove`, delegated ones for `completion
  remove`, and the image alias catalog for `--image`. v0.2.0 taught sora to
  complete the commands inside boxes but left its own CLI without completion.
  Candidates come only from local files, so completing a sora command never
  enters a container. Installed to each shell's standard directory by `make
  install` and by `packaging/install.sh`; Homebrew links those three
  directories itself, so a brew install needs no extra step.

## [0.2.0] - 2026-08-11

### Added

- **Tab completion for box commands**, in two halves. Completing the command
  *name* (`kubect<Tab>`) now merges the index into the shell's own candidates:
  `complete -I` on bash 5.0+, an extended `-command-` context on zsh. It is the
  same single awk pass a miss costs (measured at 6-16ms), so completing a name
  never touches a container.
- Completing *arguments* is covered by three complementary mechanisms:
  - `sora reindex` syncs each box's own completion scripts to the host, one
    winner per command using the same priority and pin rules as the index, so a
    pinned command can never dispatch to one box while completing from another.
    Static scripts cost nothing per Tab.
  - `sora anxious <cmd> --box <box> --with-completion` installs the completion
    script a cobra/clap/click tool generates for itself.
  - `sora completion delegate <cmd> --box <box>` opts one command in to live
    completion answered by the running box (~300ms per Tab). A Tab never wakes
    a stopped box; it returns nothing instead of freezing the terminal.
- `sora completion status | list | remove` to inspect and undo the above.

### Changed

- The command-not-found hook stays quiet while a completion is running.
  Completion scripts shell out to the command on every Tab, and distrobox's
  setup banner would otherwise land on the line being typed. Candidates were
  never affected (`$( )` captures stdout, the banner is stderr); this fixes the
  cosmetic half only, and only while completing.

### Fixed

- Installing with `PREFIX=$HOME/.local`, which is what the recommended
  installer does, made the share dir and the data dir the same directory, so
  `install(1)` was asked to copy `sora-merge-index` onto itself and printed
  "are the same file" on every invocation.

### Known limitations

- fish support is reduced and cannot be fixed from sora's side: inside a
  command substitution fish discards an unknown command's output even when
  `fish_command_not_found` ran successfully, so completions that shell out
  yield nothing there. Static synced completions work; `sora anxious
  --with-completion` is the way to get the dynamic half in fish.

## [0.1.3] - 2026-08-10

### Fixed

- `sora hook status`, `hook install`, `doctor` and the `box create` hint now
  recognize system-wide hook installs — `/etc/profile.d/*sora*` and fish's
  `vendor_conf.d` — which are the normal case on distros that package sora
  (e.g. Kuuhaku). Previously every user of such a distro was told to install
  a hook that was already active, and `hook install` would append a
  redundant rc line.

## [0.1.2] - 2026-08-10

### Fixed

- Homebrew installs no longer embed the versioned Cellar keg path: share-dir
  resolution now prefers the stable prefix (`$(brew --prefix)/share/sora`),
  so rc hook lines survive `brew upgrade` + cleanup.
- `sora hook install` now repairs rc lines that point at a hook file which
  no longer exists (e.g. a removed keg), instead of reporting "already
  installed" while the hook is silently dead.
- The bash hook sets `shopt -s checkhash`: a binary removed after being
  hashed (e.g. `brew uninstall neovim`) now falls through to late resolution
  instead of failing forever with "No such file or directory" at the old
  path.

### Added

- `sora doctor` now detects rc hook lines pointing at missing files, and
  dangling PATH symlinks that shadow indexed commands (both defeat late
  resolution invisibly).
- `sora sync` as an alias of `sora reindex`.

## [0.1.1] - 2026-08-10

### Fixed

- Reindex now scans `/usr/games` and `/usr/local/games` — Debian/Ubuntu
  install `sl`, `cowsay`, `fortune` and friends there, which left a blind
  spot in apt boxes.
- `sora hook install` idempotency no longer depends on the checkout path
  containing the string "sora": detection now greps for the marker comment,
  so installs from neutrally-named checkouts no longer append duplicate
  lines to rc files.

## [0.1.0] - 2026-08-10

### Added

- Late resolution: command-not-found hooks for bash, zsh and fish that
  dispatch into distrobox boxes via a cached `command → box` index. Host
  precedence is structural (the hook only fires after PATH lookup fails).
- Hook chaining: a pre-existing handler (mise, pkgfile, command-not-found,
  PackageKit) is preserved and delegated to, never overwritten.
- Cached TSV index with per-box priorities, manual pins (`sora pin`),
  conflict inspection (`sora conflicts`) and resolution preview
  (`sora which`). Lookups never touch a container; a missing container is
  never dispatched to.
- Box management (`sora box create|list|enter|rm|set-priority`) with
  opinionated defaults: dedicated box home, XDG folder symlinks, package
  manager detected by binary presence, metadata in
  `~/.config/sora/boxes/<box>.toml`.
- Automatic host-index refresh after every package transaction, via each
  manager's native hook: dnf5 (`libdnf5-plugin-actions`), apt
  (`DPkg::Post-Invoke`) and pacman (ALPM hook).
- Eager on-demand export (`sora anxious`, `--sudo`, `--list`, `--remove`)
  delegating to `distrobox-export`.
- `sora hook install|status|print`, `sora doctor`, `sora images`.
- Test suite (sandboxed, stubbed distrobox/podman) plus an opt-in
  integration test against a real container.
- Install surface: verified `curl | sh` installer (primary), release
  tarball, mise github backend, Homebrew formula in `LLawli/homebrew-tap`
  (auto-bumped by the release pipeline).

[Unreleased]: https://github.com/LLawli/sora/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/LLawli/sora/releases/tag/v0.1.0
