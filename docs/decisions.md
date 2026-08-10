# Design decisions

The record of what was decided, why, and what was rejected — so future
contributors (human or LLM) don't relitigate it from scratch. If a decision
here stops holding, change this file in the same PR that changes the
behavior.

## Implementation language: bash (+ POSIX sh at the edges)

The hot path — the command-not-found hook — must be shell no matter what: it
executes on every miss and may not spawn interpreters (one `awk` pass over a
flat file is the ceiling). Given that, a compiled CLI (Rust/Go) would add a
build/packaging matrix to what is orchestration glue around distrobox —
which is itself shell — so shell adds **zero** new dependencies on immutable
hosts, and packaging is trivially `noarch`.

Escape hatch: the contract (index TSV, TOML subset, hook file formats,
generated-script paths) is defined in [architecture.md](architecture.md);
the CLI implementation can be swapped without touching the hooks.

Everything that runs inside boxes is POSIX sh (busybox-safe). The generated
scripts double-quote their heredoc discipline with content-level tests.

## English code and messages, bilingual README

The project was born in Portuguese; the audience is international. Code,
messages, and docs/ are English; the README exists in both languages.

## Scope: distrobox only, no Flatpak management

Flatpaks already integrate with the host (desktop entries, `flatpak run`);
their problem is not "commands invisible to the host", which is the one
problem sora solves. Scope creep refused.

## Name: sora

Checked 2026-08: taken on crates.io and PyPI by unrelated projects —
irrelevant unless the implementation language changes; free on AUR at the
time of checking (moot: see the packaging decision below). Fallback if a
registry collision ever forces it: `sora-box`.

## Distribution: release tarball first, no native distro packages

The install surface is `curl | sh` (verified installer) as the primary
path, the tarball as fallback, mise's github backend, and the
`LLawli/homebrew-tap` Homebrew formula. All four consume the same release
tarball — "build once, repackage many" collapses to "publish one tarball"
for a noarch shell project.

COPR and AUR were built and then **removed on purpose**: for a single shell
script they are overkill — a spec/PKGBUILD to maintain, an external review
and build queue, and (at the time of the decision, 2026-08) AUR was closed
to new submissions anyway. Every target user is covered by the four paths
above at zero registry cost. Revisit only if real demand shows up in
issues.

## License: MIT

No dependency constraints (distrobox is invoked as an external tool, not
linked), and MIT maximizes reuse of the hook/index patterns.

## Rejected: a dedicated system user for the containers

Investigated in depth; does not hold up:

- the Wayland socket in `/run/user/<uid>` is 0700 to its owner;
- `keep-id` makes files created in shared dirs belong to an orphan subuid;
- `/dev/dri/card*` is granted by udev only to the active session's user;
- `distrobox-export` writes into `$DISTROBOX_HOST_HOME`, so exported
  shortcuts would land in the *wrong user's* home — breaking exactly the
  integration that is the point.

No real project (Universal Blue, BlendOS, apx, Toolbx) does this, and
distrobox upstream closed per-user isolation requests as *not planned*.

## Rejected: a global PATH shim preceding /usr/bin

Would invert host precedence, which is the central guarantee of the design.
The same reasoning caps eager export at "one explicit command at a time" in
`~/.local/bin`.

## Rejected: exporting everything eagerly

A box has thousands of binaries. Exporting all of them floods PATH and tab
completion, inverts precedence on any name collision, leaves stale wrappers
on every package removal, and still costs a full re-export sweep per
transaction. The cached index gives interactive use the same coverage at
zero PATH cost.

## Rejected: index-less late resolution

The circulating command-not-found handlers forward every unknown word to a
container: a typo wakes a stopped container for hundreds of milliseconds to
fail with a confusing message. sora's index makes a miss cost microseconds
and never touch a container — this is why the index is mandatory, not an
optimization.

## Prior art

- `distrobox-export --bin/--app` — eager export of binaries and `.desktop`
  entries; sora uses it underneath.
- BlendOS (`~/.local/bin/<bin>.<container>`) and Vanilla OS `apx` (calls
  `distrobox-export`) — eager export only; no late resolution.
- `distrobox-host-exec` / `host-spawn` — the opposite direction
  (container → host).
