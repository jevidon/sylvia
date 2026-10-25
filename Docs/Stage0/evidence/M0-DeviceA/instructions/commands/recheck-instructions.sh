#!/bin/bash
# Runs this update's recheck (recheck-instructions.py beside this file) on the tree as it stands, where it must pass, and
# its control on the tree of 6cede84a (m0-sessions's head, where the update starts, unpacked with git archive under
# .build/scratch), where it must report all six of its items. Read-only; writes only the log and .build/scratch.
#   Docs/Stage0/evidence/M0-DeviceA/instructions/commands/recheck-instructions.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
check=Docs/Stage0/evidence/M0-DeviceA/instructions/commands/recheck-instructions.py
start=6cede84a6f6ac610976b233d875e26dd89419dbd
control=.build/scratch/recheck-instructions-control
rm -rf "$control"; mkdir -p "$control"
git archive "$start" | tar -x -C "$control"
status=0
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"  # counted before the log is opened
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/instructions/commands/recheck-instructions.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "== on the tree as it stands: it must pass"
} > "$log"
python3 -I "$check" "$root" >> "$log" 2>&1
code=$?
echo "exit: $code" >> "$log"
(( code == 0 )) || status=1
{
  echo
  echo "== its control on the tree of ${start:0:8}, where this update starts: all six items must be reported"
} >> "$log"
python3 -I "$check" "$control" > "$control.out" 2>&1
code=$?
cut -c1-400 "$control.out" >> "$log"
reported="$(grep -c '^PROBLEM' "$control.out")"
echo "exit: $code; reported: $reported of 6" >> "$log"
if [[ "$code" == 1 && "$reported" == 6 ]]; then
  echo "as required: all six reported" >> "$log"
else
  echo "NOT as required: all six must be reported" >> "$log"; status=1
fi
rm -rf "$control" "$control.out"
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )" >> "$log"
exit $status
