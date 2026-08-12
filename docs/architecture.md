# Architecture

This document is for contributors. If you just want to use sora, the
[README](../README.md) is enough.

## Data flow

```
host                                      box (keep-id userns)
────────────────────────────────────      ─────────────────────────────────
~/.cache/sora/index          ◄─ merge ─┐  package transaction
~/.cache/sora/index.d/<box>.list ◄──┐  │    └─ native pm hook (as root)
~/.config/sora/boxes/<box>.toml     │  │         └─ /usr/local/bin/sora-index-refresh
~/.local/share/sora/libexec/        │  │              └─ runuser -u <user>
    sora-reindex  ──────────────────┴──┴─────────────────┘  (writes DIRECTLY
    sora-merge-index                                         through the
                                                             bind-mounted home)
```

Two properties fall out of this design and everything else defends them:

1. **Host precedence is structural.** The shell hook only runs after PATH
   lookup already failed, so no host binary can ever be shadowed.
2. **A miss never touches a container.** The hook's lookup is one `awk` pass
   over a flat file; `podman container exists` gates the dispatch so a stale
   index can never trigger distrobox's "create it?" prompt.

## On-disk formats

Everything is designed to be readable by POSIX `awk`/`grep` — the shell hook
and the in-box merge run where nothing richer is guaranteed to exist.

| Path | Format | Purpose |
|---|---|---|
| `~/.cache/sora/index` | TSV `command<TAB>box`, one winner per command | read by the shell hooks |
| `~/.cache/sora/index.d/<box>.list` | one command name per line | written by the in-box reindex |
| `~/.config/sora/boxes/<box>.toml` | flat `key = value` TOML subset | box metadata: image, package_manager, home, priority, created, last_indexed |
| `~/.config/sora/pins` | TSV `command<TAB>box` | manual overrides |
| `~/.config/sora/anxious.list` | TSV `command box sudo wrapper binpath` | registry of eager exports |
| `~/.local/share/sora/homes/<box>/` | directory | dedicated box homes |
| `~/.local/share/sora/libexec/` | generated scripts | see below |

The metadata is a deliberate TOML *subset* (flat `key = value` only): the
same file must be parseable by `awk` from the POSIX merge script. Don't add
nesting.

## Resolution rules

For a command present in several boxes, the merge picks one winner:

1. **Pin** — but only if the pinned box actually provides the command. A
   dangling pin (box lost the command) goes dormant instead of breaking
   resolution; internally pins are a priority boost to 10^9, not a forced
   row, which is what makes dangling pins harmless.
2. **Highest `priority`** from the box metadata.
3. **Alphabetical box name** — an arbitrary tie needs a deterministic,
   documented answer; "first file globbed" is not one.

## Generated scripts

`ensure_libexec` (re)generates these under `~/.local/share/sora/libexec/` —
inside the home **on purpose**, because the home is bind-mounted in every box
at the same absolute path, so in-box hooks can call them directly:

| Script | Runs | Role |
|---|---|---|
| `sora-merge-index` | host and box, as user | copy of the shipped POSIX merge |
| `sora-reindex` | inside box, as user | enumerate executables → `index.d/<box>.list` → merge |
| `sora-detect-pm` | inside box, as user | package manager detection by binary presence |
| `sora-which` | inside box, as user | `command -v` without shell-quoting games through `distrobox enter` |
| `sora-capture-bash` | inside box, as user | ask the box's own bash for completion candidates (live delegation) |
| `sora-desktop-scan` | inside box, as user | locate an app's `.desktop` and its icon files for `anxious --desktop`; prints **paths only**, so the host can `podman cp` them out — a binary icon would not survive command substitution |

Installed inside each box at creation time (root side):

- `/usr/local/bin/sora-index-refresh` — the trigger the package-manager hook
  calls; drops to the user via `runuser` (fallback `su`) and executes
  `sora-reindex`.
- The package-manager hook itself:
  - dnf5: `/etc/dnf/libdnf5-plugins/actions.d/sora.actions`
    (`post_transaction::::…` — empty filter = once per transaction; requires
    `libdnf5-plugin-actions`, which sora installs because the fedora-toolbox
    image lacks it)
  - apt: `/etc/apt/apt.conf.d/99-sora-index` (`DPkg::Post-Invoke` + `|| true`)
  - pacman: `/etc/pacman.d/hooks/sora-index.hook` (`PostTransaction`,
    `Target = *`)

## The pitfalls (hard constraints, all test-pinned)

These cost real debugging. Treat them as rules, not suggestions:

1. **The in-box hook must run as the user, not root.** Under
   `--userns keep-id`, container root maps to an unprivileged host *subuid*
   with no permission on the user's 0700 `~/.cache`. Hence
   `runuser -u <user>` in the trigger.
2. **Root in the box cannot READ the 0700 home either.** The root-side
   install therefore stages files into container-private `/tmp` (copied as
   the user) before `sudo sh` consumes them.
3. **No `distrobox-host-exec` from the hook.** Host callback IPC is fragile
   in non-interactive contexts. The reindex writes the host cache directly
   through the bind-mounted home instead.
4. **`sudo` inside a container resets `$HOME` to `/root`** — and with
   `--home`, the box `$HOME` differs from the host's anyway. Every generated
   script embeds absolute paths at generation time and reads nothing from
   the runtime environment.
5. **Heredoc escaping is where the silent bug lives.** Generated files pass
   `bash -n` on the *generator* while being broken at runtime. Tests assert
   on the generated content and execute it (`tests/test_templates.sh`).
6. **Never put "distrobox" in the pacman hook filename.** distrobox deletes
   libalpm hooks matching `*distrobox*` inside its containers.

## Shell hooks and chaining

Hook names: `command_not_found_handle` (bash), `command_not_found_handler`
(zsh), `fish_command_not_found` (fish). On source, a pre-existing handler is
renamed/copied to `__sora_prev_handle_<shell>` and delegated to whenever sora
cannot resolve — these hooks are usually occupied in the real world (mise,
pkgfile, Debian's command-not-found, PackageKit). Guards:

- never capture a handler that already contains `__sora` (re-source safety);
- in fish, never capture fish's own default handler (sora's fallback message
  is strictly more useful);
- original argv reaches the box via `"$@"` untouched; exit codes propagate
  (fish caveat: fish itself forces the *reported* status of an unknown
  command to 127 — the command still ran).

## Eager export

`sora anxious` shells out to `distrobox-export --bin` inside the box (with
`--sudo` when asked — meaning sudo *inside* the container) and records the
export in its registry so `--list`/`--remove` and `box rm` can clean up even
after the box is gone. sora deliberately does not reimplement wrapper
generation; its value is the layer above (discovery, index, metadata,
lifecycle).
