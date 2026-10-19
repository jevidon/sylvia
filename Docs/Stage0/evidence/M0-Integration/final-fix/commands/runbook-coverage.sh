#!/bin/bash
# Runs runbook-coverage.py on the device runbook as it is now and, as a control, on the runbook as reviewed
# (fea12c38dea8373e71cfd9708367d12129c7a698, extracted with git show into .build/scratch): the control must fail and
# name exactly the nine steps of M0 final review R1-01 (G0.1 PDF 11; G0.2 22 and 23; G0.3 28-32; G0.4 17).
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/runbook-coverage.sh <log>
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root" || exit 1
log="$1"
here=Docs/Stage0/evidence/M0-Integration/final-fix/commands
mkdir -p .build/scratch
git show fea12c38dea8373e71cfd9708367d12129c7a698:Docs/Stage0/M0-device-runbook.md > .build/scratch/runbook-fea12c3.md
{
  echo "commit: $(git rev-parse HEAD); uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "== the runbook now"
  /usr/bin/python3 -I "$here/runbook-coverage.py" "$root"
  now=$?
  echo
  echo "== control: the runbook as reviewed (fea12c3)"
  /usr/bin/python3 -I "$here/runbook-coverage.py" "$root" "$root/.build/scratch/runbook-fea12c3.md"
  control=$?
  echo
  if [[ $now == 0 && $control == 1 ]]; then echo "result: pass (the runbook now covers every step; the control fails)"; exit 0; fi
  echo "result: FAIL (now exit $now, control exit $control)"; exit 1
} > "$log" 2>&1
