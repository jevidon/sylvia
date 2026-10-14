#!/bin/bash
# List paths changed by more than one item branch (each relative to its merge base with the integration head).
set -u
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
mkdir -p .build/scratch; out=.build/scratch/paths.txt
: > "$out"
for b in contracts deps threat minors-g06-design minors-g05-recovery minors-g01-epub minors-g01-pdf minors-g03-intake minors-g02-transfer minors-g05-ai runbook amendments minors-g04-audio; do
  base=$(git merge-base "m0-int-$b" 70f6f54)
  git diff --name-only --no-renames "$base" "m0-int-$b" | sed "s|^|$b |" >> "$out"
done
awk '{print $2}' "$out" | sort | uniq -d | while read -r p; do grep " $p\$" "$out"; done
