#!/bin/bash
# The runbook's correction-text check (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at
# HEAD) on the trees of c72247a6 (m0-decisions when this branch was made), c3adae68 (m0-exit-prep), 1d5ac477
# (m0-sessions) and HEAD, each exported with git archive under .build/scratch; then the lines of each that differ from
# HEAD's (the first line, a timestamp, left out). This branch must change no text a correction replaces, so HEAD's lines
# must equal those of the three trees it merged wherever those agree. Read-only.
#   Docs/Stage0/evidence/M0-RecordsUpdate/commands/correction-texts-compare.sh > <log>
set -u
root="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$root" || exit 1
trees="$root/.build/scratch/correction-texts-trees"
rm -rf "$trees"; mkdir -p "$trees"
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$trees/check.py"
echo "correction-texts-compare: HEAD $(git rev-parse HEAD), uncommitted paths: $(git status --porcelain | wc -l | tr -d ' '); $(date -u +%Y-%m-%dT%H:%M:%SZ)"
for rev in c72247a6 c3adae68 1d5ac477 HEAD; do
  mkdir -p "$trees/$rev"
  git archive "$rev" | tar -x -C "$trees/$rev"
  (cd "$trees/$rev" && python3 -I "$trees/check.py" > "$trees/$rev.out" 2>&1); echo "$?" > "$trees/$rev.status"
  echo "$rev: exit $(cat "$trees/$rev.status"); $(tail -n 1 "$trees/$rev.out")"
done
status=0
for rev in c72247a6 c3adae68 1d5ac477; do
  echo
  echo "== lines that differ from $rev to HEAD"
  d="$(diff <(tail -n +2 "$trees/$rev.out") <(tail -n +2 "$trees/HEAD.out") | grep -E '^[<>] ' || true)"
  if [[ -z "$d" ]]; then echo "   none"; else echo "$d" | sed 's/^/   /'; fi
done
# every text that is found (ok) in all three merged trees must be found at HEAD
lost="$(comm -12 <(grep -E ' ok ' "$trees/c72247a6.out" | sort) <(grep -E ' ok ' "$trees/c3adae68.out" | sort) \
        | comm -12 - <(grep -E ' ok ' "$trees/1d5ac477.out" | sort) | comm -23 - <(grep -E ' ok ' "$trees/HEAD.out" | sort))"
echo
if [[ -z "$lost" ]]; then
  echo "result: every text found in all three merged trees is found at HEAD"
else
  echo "PROBLEM: texts found in all three merged trees and not at HEAD:"; echo "$lost"; status=1
fi
exit $status
