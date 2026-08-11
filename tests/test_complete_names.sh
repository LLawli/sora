#!/usr/bin/env bash
# Completing the command NAME from the index (bash 'complete -I', zsh completer).
#
# This is the cheap half of tab completion: it answers 'kubect<Tab>' with a
# single awk pass over the index and never touches a container. The expensive
# half (arguments) is what the per-strategy machinery deals with.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup_sandbox

# A box that does not exist, on purpose: nothing here may need a container.
{
    printf 'zzboxalpha\tghostbox\n'
    printf 'zzboxbeta\tghostbox\n'
    printf 'sh\tghostbox\n'
} > "$XDG_CACHE_HOME/sora/index"

if [ "${BASH_VERSINFO[0]}" -lt 5 ]; then
    skip "bash >= 5 required for 'complete -I' (found ${BASH_VERSINFO[0]})"
fi

run_bash_completion() { # word
    bash --norc <<EOF
source "$HOOK_BASH"
COMP_WORDS=($1); COMP_CWORD=0
COMPREPLY=()
__sora_complete_initial
printf '%s\n' "\${COMPREPLY[@]}"
EOF
}

# 1. Names that only exist inside a box are offered.
out=$(run_bash_completion zzbox)
assert_contains "$out" "zzboxalpha" "indexed name is offered"
assert_contains "$out" "zzboxbeta" "second indexed name is offered"

# 2. The shell's own candidates survive: this ADDS to the list, never replaces
#    it. 'sh' is a host binary in every environment this runs in.
out=$(run_bash_completion sh)
assert_contains "$out" "sh" "host commands still complete"

# 3. A command present both on the host and in a box must appear exactly once.
assert_eq "$(run_bash_completion sh | grep -cx 'sh')" "1" \
    "a command in both host and box is not duplicated"

# 4. The registration happened, and as an initial-word completion.
out=$(bash --norc -c "source '$HOOK_BASH'; complete -p -I 2>/dev/null")
assert_contains "$out" "__sora_complete_initial" "complete -I is registered"

# 5. No index at all: the completion must still return the shell's own
#    candidates instead of erroring or coming back empty.
rm -f "$XDG_CACHE_HOME/sora/index"
out=$(run_bash_completion sh)
assert_contains "$out" "sh" "works with no index present"

# 6. A pre-existing initial-word completion must be chained, not clobbered.
printf 'zzboxalpha\tghostbox\n' > "$XDG_CACHE_HOME/sora/index"
out=$(bash --norc <<EOF
_other_initial() { COMPREPLY=(from-other-tool); }
complete -I -F _other_initial
source "$HOOK_BASH"
COMP_WORDS=(zzbox); COMP_CWORD=0
COMPREPLY=()
__sora_complete_initial
printf '%s\n' "\${COMPREPLY[@]}"
EOF
)
assert_contains "$out" "from-other-tool" "a pre-existing -I completion is chained"
assert_contains "$out" "zzboxalpha" "and our candidates are added to it"

# 7. zsh: the -command- context is extended, and whatever completed command
#    names before is still called (this ADDS candidates, never replaces them).
if command -v zsh >/dev/null 2>&1; then
    out=$(zsh -f -c "
        autoload -Uz compinit && compinit -u -d '$SANDBOX/zcd1' 2>/dev/null
        print -r -- \"before=\${_comps[-command-]}\"
        source '$HOOK_ZSH'
        print -r -- \"after=\${_comps[-command-]}\"
        print -r -- \"chained=\$__sora_prev_command_comp\"
    ")
    assert_contains "$out" "after=_sora_command_names" "zsh: -command- context is ours"
    assert_contains "$out" "chained=_autocd" "zsh: the previous command completion is chained"

    # Double-source must not make us chain to ourselves (infinite recursion).
    out=$(zsh -f -c "
        autoload -Uz compinit && compinit -u -d '$SANDBOX/zcd2' 2>/dev/null
        source '$HOOK_ZSH'
        source '$HOOK_ZSH'
        print -r -- \"chained=\$__sora_prev_command_comp\"
    ")
    assert_not_contains "$out" "chained=_sora_command_names" \
        "zsh: double-source never chains to itself"

    out=$(zsh -f -c "
        autoload -Uz compinit && compinit -u -d '$SANDBOX/zcd3' 2>/dev/null
        source '$HOOK_ZSH'
        (( \${+functions[_sora_command_names]} )) && print yes
    ")
    assert_eq "$out" "yes" "zsh: the completion function is defined"
fi

echo "ok: command-name completion"
