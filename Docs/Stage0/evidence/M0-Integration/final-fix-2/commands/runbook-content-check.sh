#!/bin/bash
# The device runbook against the merged checklists (M0 final review round 2: evidence R2-01, owner-readability R6-01
# and R6-02). Runs, read-only:
#   1. runbook-content-check.py on the runbook as committed: quoted texts and counts, both ways;
#   2. the same on the runbook the round-2 review read (83ee280), as a control: it must fail, with the stale values;
#   3. final-fix/commands/runbook-coverage.py on the runbook as committed (step numbers: classified and in a session).
#   Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/runbook-content-check.sh > <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
here=Docs/Stage0/evidence/M0-Integration
scratch="$root/.build/scratch/runbook-content-check"
rm -rf "$scratch"; mkdir -p "$scratch"
echo "command: $here/final-fix-2/commands/runbook-content-check.sh"
echo "commit: $(git -C "$root" rev-parse HEAD); uncommitted files: $(git -C "$root" status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
status=0
echo
echo "== 1. the runbook as committed"
python3 -I "$here/final-fix-2/commands/runbook-content-check.py" "$root"
(( $? == 0 )) || status=1
echo
echo "== 2. control: the runbook the review read (83ee280); it must fail"
git -C "$root" show 83ee28007517a9e41384a156f2ed647bb68de432:Docs/Stage0/M0-device-runbook.md > "$scratch/runbook-83ee280.md"
python3 -I "$here/final-fix-2/commands/runbook-content-check.py" "$root" "$scratch/runbook-83ee280.md" \
  | sed "s#$scratch/##"
control=${PIPESTATUS[0]}
if (( control != 0 )); then echo "control: fails, as it must (exit $control)"; else echo "PROBLEM: the control passed"; status=1; fi
echo
echo "== 3. step coverage of the runbook as committed (final-fix/commands/runbook-coverage.py)"
python3 -I "$here/final-fix/commands/runbook-coverage.py" "$root"
(( $? == 0 )) || status=1
rm -rf "$scratch"
echo
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
