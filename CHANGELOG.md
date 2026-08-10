# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).
The release pipeline extracts the section for the tagged version into the
GitHub Release body — keep the `## [x.y.z]` heading format intact.

## [Unreleased]

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
