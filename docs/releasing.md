# Releasing

Releases are tag-triggered: CI runs on every push/PR, but the release
pipeline (`.github/workflows/release.yml`) only fires on a `vX.Y.Z` tag.

## Cutting a release

```sh
bin/release 0.2.0
git push origin main v0.2.0
```

`bin/release` does everything local and reversible: bumps the version in
`bin/sora`, `packaging/sora.spec` and `packaging/PKGBUILD`, rolls the
`## [Unreleased]` section of `CHANGELOG.md` into `## [0.2.0] - <date>`,
runs the test suite, commits (`release: v0.2.0`) and tags. It never pushes.

The pushed tag makes the pipeline:

1. run tests + lint again (a release is never cut from a red tree);
2. verify the tag matches `SORA_VERSION` in `bin/sora`;
3. build `sora-X.Y.Z.tar.gz` via `git archive` plus its `.sha256`;
4. extract this version's section from `CHANGELOG.md` (awk over the
   `## [x.y.z]` headings) and append install instructions + checksums;
5. create the GitHub Release with that body and the artifacts.

The result explains itself: what changed, how to install, how to verify.

## One artifact, many wrappers

Pure shell means there is no per-arch build matrix: the release tarball is
**the** artifact, and every install path consumes it —

| Path | How it consumes the tarball |
|---|---|
| `curl \| sh` (primary) | `packaging/install.sh` resolves the latest release, downloads the tarball, verifies its `.sha256`, installs to `~/.local` |
| Direct download | `curl … tar.gz \| tar xz && make install` |
| mise | `mise use -g github:LLawli/sora` — the github backend picks the only `.tar.gz` asset and finds `sora-X.Y.Z/bin` on its own; the CLI runs straight from the extracted tree (checkout layout) |
| Homebrew | `LLawli/homebrew-tap` formula pins the tarball URL + sha256; the `bump-tap` job in `release.yml` rewrites it on every release |

There are deliberately no native distro packages (COPR/AUR/deb/rpm) — see
[decisions.md](decisions.md).

## Automation setup (one-time)

- **Tap bumping**: create a fine-grained PAT with push access to
  `LLawli/homebrew-tap` and add it to this repo as the `TAP_GITHUB_TOKEN`
  secret. Without it, the `bump-tap` job skips politely and the formula can
  be bumped by hand (commit style in the tap: `sora vX.Y.Z`).

## Version lives in one place

`bin/sora` (`SORA_VERSION`). `bin/release` bumps it; the pipeline's
tag-vs-code check catches a manual tag that missed the bump. The tap formula
carries its own version but is machine-written by `bump-tap`.
