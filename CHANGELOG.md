# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).
The release pipeline extracts the section for the tagged version into the
GitHub Release body — keep the `## [x.y.z]` heading format intact.

## [Unreleased]

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
- Packaging: COPR spec, AUR PKGBUILD, `curl | sh` fallback installer.

[Unreleased]: https://github.com/REPLACE_ME/sora/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/REPLACE_ME/sora/releases/tag/v0.1.0
