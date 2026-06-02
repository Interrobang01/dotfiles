#!/usr/bin/env zsh
# Benchmark prompt cost. Two measurements:
#
#   1. Interactive startup  — spawns `zsh -i -c exit`, which sources your full
#      ~/.zshrc and so honors the STARSHIP_* toggles. This is total shell
#      launch cost (what you wait for opening a terminal / each SSH session).
#
#   2. Single-prompt render — `starship prompt`, the per-keystroke-of-Enter lag
#      you feel on every command. Honors $STARSHIP_CONFIG, so you can compare
#      configs directly.
#
# Usage:
#   ./bench-prompt.zsh [iterations]            # default 30
#
# Compare configurations (the numbers that matter are the per-line means):
#   ./bench-prompt.zsh                                   # current default
#   STARSHIP_CONFIG=~/.config/starship-lite.toml ./bench-prompt.zsh   # no node/package
#   STARSHIP_ENABLE=0 ./bench-prompt.zsh                 # manual prompt (starship off)
#
# Note: if you've hard-set the toggles in ~/.zshenv, that overrides what you
# pass on the command line for measurement (1) — comment them out there, or
# trust the STARSHIP_CONFIG comparison in measurement (2), which is unaffected.

emulate -L zsh
zmodload zsh/datetime

N=${1:-30}

bench() {  # bench <label> <command...>
    local label=$1; shift
    "$@" >/dev/null 2>&1            # warm caches
    local -F start total=0
    local i
    for (( i = 1; i <= N; i++ )); do
        start=$EPOCHREALTIME
        "$@" >/dev/null 2>&1
        (( total += EPOCHREALTIME - start ))
    done
    printf "  %-26s %7.1f ms\n" "$label" "$(( total / N * 1000 ))"
}

print -r -- "Prompt benchmark — $N iterations each"
print

print -r -- "Interactive startup (sources ~/.zshrc; honors STARSHIP_* env):"
bench "zsh -i -c exit" zsh -i -c exit

if command -v starship >/dev/null 2>&1; then
    print
    print -r -- "Single-prompt render:"
    print -r -- "  config: ${STARSHIP_CONFIG:-(default) ~/.config/starship.toml}"
    bench "starship prompt" starship prompt
    print
    print -r -- "Per-module timings (slowest first):"
    starship timings 2>/dev/null | head -20
fi
