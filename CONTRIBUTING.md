# Contributing to sora

Thanks for considering a contribution. The short version: open a PR, make CI
green, and expect an honest review.

## Ground rules (what CI enforces)

Every push and pull request runs two jobs — they are the common ground for
what is acceptable in the project:

- **Tests**: `bash tests/run.sh` (also `make test`). The suite is sandboxed —
  it stubs `distrobox`/`podman` and fakes `$HOME`, so it is safe and fast to
  run locally, and it exercises real bash, zsh and fish when present.
- **Lint**: `make lint` (shellcheck, strict). The accepted deviations live in
  [.shellcheckrc](.shellcheckrc), each with a justification — don't grow that
  list casually.

If you touch anything that generates files (templates in `bin/sora`), add or
extend a test that asserts on the **generated content**, not just on the
generator: quoting bugs in heredocs pass `bash -n` and only explode at
runtime. This is the project's most load-bearing test convention.

There is also an opt-in integration test that creates a real disposable box:

```sh
make integration      # needs podman + distrobox; pulls a Debian image
```

## Design constraints you should know before proposing changes

Read [docs/architecture.md](docs/architecture.md) first — especially the
pitfalls section. Several things in the code look odd on purpose (running
hooks via `runuser`, absolute paths embedded in generated scripts, staging
through container-private `/tmp`); they encode real debugging pain and have
tests pinning them down. [docs/decisions.md](docs/decisions.md) records what
was already considered and rejected (e.g. a dedicated system user, global
PATH shims, exporting everything) — PRs re-proposing those will be declined
with a pointer there.

The hot path (the shell hook) must remain dependency-free: POSIX tools only,
no interpreters, no container round-trips on a miss.

## Workflow

- Branch from `main`, keep commits scoped and conventional
  (`feat: ...`, `fix: ...`, `test: ...`, `docs: ...`).
- PR descriptions are welcome, but reviews audit the diff, not the
  description.
- Releases are cut from `main` by a maintainer with `bin/release X.Y.Z`
  (see [docs/releasing.md](docs/releasing.md)); the pushed tag does the rest.
