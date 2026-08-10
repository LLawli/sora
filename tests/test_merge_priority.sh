#!/usr/bin/env bash
# Index merge: priority tie-break, deterministic ordering, pins, dangling pins.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

make_box_meta alpha 10
make_box_meta beta 20
make_box_list alpha python git shared-tool
make_box_list beta python curl shared-tool

run_merge || fail "merge failed"

assert_eq "$(index_lookup python)" "beta" "higher priority wins"
assert_eq "$(index_lookup git)"    "alpha" "unique command resolves to its box"
assert_eq "$(index_lookup curl)"   "beta" "unique command resolves to its box"

# Tie at the same priority: alphabetical box name (deterministic, documented).
make_box_meta beta 10
run_merge || fail "merge failed"
assert_eq "$(index_lookup shared-tool)" "alpha" "tie breaks alphabetically"

# A pin overrides priority entirely.
make_box_meta beta 20
printf 'python\talpha\n' > "$XDG_CONFIG_HOME/sora/pins"
run_merge || fail "merge failed"
assert_eq "$(index_lookup python)" "alpha" "pin overrides priority"
assert_eq "$(index_lookup curl)"   "beta" "pin does not leak onto other commands"

# A dangling pin (box does not provide the command) must be ignored, never
# breaking resolution.
printf 'python\talpha\ncurl\talpha\n' > "$XDG_CONFIG_HOME/sora/pins"
run_merge || fail "merge failed"
assert_eq "$(index_lookup curl)" "beta" "dangling pin is ignored"

# A box list without metadata still indexes (priority 0).
make_box_list gamma onlyingamma python
run_merge || fail "merge failed"
assert_eq "$(index_lookup onlyingamma)" "gamma" "list without metadata defaults to priority 0"
assert_eq "$(index_lookup python)" "alpha" "priority 0 loses to pinned/prioritized boxes"

# Index is TSV: exactly two fields per line.
badlines=$(awk -F'\t' 'NF != 2' "$XDG_CACHE_HOME/sora/index" | wc -l)
assert_eq "$badlines" 0 "index is strict two-field TSV"

echo "ok: merge priority"
