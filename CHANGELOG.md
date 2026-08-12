# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).
The release pipeline extracts the section for the tagged version into the
GitHub Release body — keep the `## [x.y.z]` heading format intact.

## [Unreleased]

### Added

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

- `sora anxious --remove` now also removes the desktop entry and every icon it
  imported, and `sora box rm` does the same for every command that box
  provided: a launcher pointing into a deleted container is worse than no
  launcher.

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
