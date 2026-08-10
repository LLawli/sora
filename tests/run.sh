#!/usr/bin/env bash
# sora test runner. Usage: tests/run.sh [test_name...]
set -u

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$TESTS_DIR" || exit 1

tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
    tests=(test_*.sh)
fi

pass=0 failcount=0 skipcount=0
failed=()

for t in "${tests[@]}"; do
    printf '== %s\n' "$t"
    if bash "$t"; then
        pass=$((pass + 1))
    else
        rc=$?
        if [ "$rc" = 77 ]; then
            skipcount=$((skipcount + 1))
        else
            failcount=$((failcount + 1))
            failed+=("$t")
        fi
    fi
done

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$failcount" "$skipcount"
if [ "$failcount" -gt 0 ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
