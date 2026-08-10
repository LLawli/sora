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
| Direct download | `curl … tar.gz \| tar xz && make install` |
| AUR | `source=()` pointing at the tag tarball, sha256 pinned |
| COPR | `Source0` pointing at the tag tarball; COPR webhook builds on tag |
| `curl \| sh` | clones the tag (fallback path, documented as such) |

## Registry setup (one-time, still pending)

- **COPR**: create the project, add the GitHub webhook, point it at
  `packaging/sora.spec`. Replace `REPLACE_ME` URLs in the spec.
- **AUR**: claim the `sora` package name (free as of 2026-08), then enable
  the commented AUR job in `release.yml`
  (`KSXGitHub/github-actions-deploy-aur`, sha256 injected from the release
  artifact — same pattern as the checksum step).
- Replace the remaining `REPLACE_ME` placeholders (spec `URL:`, PKGBUILD
  `url=`, installer repo URL, CHANGELOG links) once the forge URL exists.

## Version lives in three places

`bin/sora` (`SORA_VERSION`), `packaging/sora.spec`, `packaging/PKGBUILD`.
`bin/release` bumps all three; the pipeline's tag-vs-code check catches a
manual bump that missed one.
