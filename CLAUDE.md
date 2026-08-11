# Project rules for agents

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the full picture (what CI enforces,
the design constraints, the release flow). The rules below are the ones that
are easy to miss and expensive to miss.

## Changing the CLI means changing `shell/completion.*`

**Any change to the `sora` command surface requires updating the three
completion files in the same commit:**

- `shell/completion.bash`
- `shell/completion.zsh`
- `shell/completion.fish`

"Command surface" means: a new or renamed subcommand, a new or renamed flag, a
new value a flag accepts, or a new source of dynamic candidates (a registry
file, a new kind of name the CLI takes).

**Why:** v0.2.0 shipped tab completion for the commands inside boxes and left
the `sora` CLI itself with no completion at all. It needed v0.2.1 the same day
to fix a gap that was invisible until someone typed `sora <Tab>`. Completion is
the part of a CLI nobody tests by using it, because the absence looks exactly
like "nothing happened".

**How to verify:** `bash tests/test_self_completion.sh`. Add a case there for
whatever you added — the test drives each shell's real completion engine
(bash's `_sora` function, fish's `complete --do-complete`), not just the helper
functions. A helper-only check once passed while every value-taking flag in
fish was silently completing filenames.

**Two traps in that file, both already paid for:**

- In fish, a flag that takes a value needs `-x` (or `-r`). Without it the flag
  is treated as boolean and its value falls through to the generic rule, so
  `--box <Tab>` offers filenames instead of box names.
- `shell/completion.bash` must not use bash-completion's helpers
  (`_init_completion`, `_filedir`). sora runs on hosts without that package,
  and a completion that breaks there is worse than none.

**Never let a completion touch a container.** Every candidate comes from a
local file (box metadata, the index, the anxious/delegate registries). The test
stubs `podman`, `docker` and `distrobox` with scripts that print a marker and
fail, so a shell-out turns the suite red instead of quietly costing three
seconds on every Tab.

## Two shell-facing surfaces, do not confuse them

- `shell/hook.*` — completion for the commands **inside boxes**, plus the
  command-not-found dispatch. Loaded into every interactive shell, so it stays
  dependency-free and cheap.
- `shell/completion.*` — completion for the **`sora` CLI itself**. Loaded
  lazily by each shell from its own standard directory.

New files in either group must be added to `make install`, to
`packaging/install.sh` **and** to the `make lint` file list. The lint list is
the one that gets forgotten; a file missing from it is simply never checked.
