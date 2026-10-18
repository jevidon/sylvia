#!/bin/bash
# Verification finding R3-02 of the Git LFS adoption: the documents edited for it (M0-device-runbook.md, G06-Design.md
# and M0-plan-amendments.md) are read by two consistency checks of their own:
#   Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py (the plan amendments against the reports), and
#   Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py (the texts the runbook's corrections replace).
# This runs both on the tree of <before> and on the tree of <after>, each exported with `git archive` into
# <scratch-dir>, and prints each run's exit status, its FAIL lines and summary, and whether the two runs' outputs are
# identical (the timestamp on the first line of check-correction-texts.py's output is left out of the comparison).
# The checks are the ones committed at <after>. Writes only under <scratch-dir>, which it deletes at the end.
#   doc-checks-before-after.sh <before> <after> <scratch-dir>
set -uo pipefail
before="$(git rev-parse --verify "$1^{commit}")" || exit 2
after="$(git rev-parse --verify "$2^{commit}")" || exit 2
root="$(git rev-parse --show-toplevel)"
scratch="$3"
rm -rf "$scratch"
mkdir -p "$scratch"
scratch="$(cd "$scratch" && pwd -P)"
checks=(
  "Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py"
  "Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py"
)
mkdir -p "$scratch/checks"
for c in "${checks[@]}"; do git show "$after:$c" > "$scratch/checks/$(basename "$c")"; done
echo "# consistency checks of the edited documents, before ($before) and after ($after); $(python3 --version 2>&1)"
for side in before after; do
  commit="$before"; [[ "$side" == after ]] && commit="$after"
  mkdir -p "$scratch/$side"
  git archive "$commit" | tar -x -C "$scratch/$side"
done
differ=0
for c in "${checks[@]}"; do
  name="$(basename "$c")"
  echo
  echo "== $c"
  for side in before after; do
    status=0
    (cd "$scratch/$side" && python3 -I "$scratch/checks/$name" > "$scratch/$name.$side.out" 2>&1) || status=$?
    echo "-- on the tree of $side: exit $status"
    grep -E '^(FAIL|summary:)|texts checked' "$scratch/$name.$side.out" | sed 's/^/   /'
  done
  if diff <(sed 1d "$scratch/$name.before.out") <(sed 1d "$scratch/$name.after.out") > "$scratch/$name.diff"; then
    echo "-- outputs: identical (from the second line on)"
  else
    differ=1
    echo "-- outputs: DIFFERENT:"
    sed 's/^/   /' "$scratch/$name.diff"
  fi
done
rm -rf "$scratch"
echo
if (( differ )); then echo "RESULT: the edits change what a check reports"; exit 1; fi
echo "RESULT: the edits change nothing either check reports"
