#!/usr/bin/env bash
# Runs the M0 plan-amendment checks for plan draft 0.8 (the product owner's decisions of 22 October 2026) and prints
# a header naming the environment. The successor of Docs/Stage0/evidence/M0-plan-amendments/commands/run-checks.sh,
# which runs the draft 0.7 checker: that checker requires draft 0.7's own anchors, so it fails on draft 0.8 by design
# (this round's log runs it once more, as a control, and shows exactly which of its checks fail and why).
# Usage, from the repository root, on a clean tree whose HEAD is the commit under test:
#   Docs/Stage0/evidence/M0-Decisions/plan/commands/run-checks.sh <commit under test> > <log> 2>&1
set -uo pipefail
here=Docs/Stage0/evidence/M0-Decisions/plan/commands
commit="${1:?usage: run-checks.sh <commit under test>}"
echo "# M0 plan amendments and decisions: consistency checks (plan draft 0.8)"
echo "command: $here/run-checks.sh $commit"
echo "commit under test: $commit"
head="$(git rev-parse HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"
echo "HEAD: $head; uncommitted paths: $dirty"
if [[ "$(git rev-parse "$commit")" != "$head" || "$dirty" != "0" ]]; then
  echo "refused: run on a clean tree whose HEAD is the commit under test"
  exit 2
fi
echo "date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m); $(python3 --version 2>&1)"
echo "load: $(uptime)"
echo "environment: host only; no simulator or device is used by these checks"
echo
echo "== $here/check-amendments.py"
python3 -I "$here/check-amendments.py"
status=$?
echo "exit status: $status"
echo
echo "== $here/mutation-checks.py (each mutation must make the checker fail)"
python3 -I "$here/mutation-checks.py"
mutation=$?
echo "exit status: $mutation"
echo "tree after the mutation checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths"
echo
echo "== control: the draft 0.7 checker, Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py"
echo "   It must fail on draft 0.8, and only on the anchors the decisions replaced: the check of new anchor phrases"
echo "   (draft 0.7's status, revision date and pending wording) and the milestone gating rule (the 21.2 M1 row's"
echo "   '(proposed, Section 21.1)', decided with PO-34)."
old_out="$(python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py 2>&1)"
old_status=$?
printf '%s\n' "$old_out" | grep -E '^FAIL |^summary:'
echo "exit status: $old_status"
expected_fails="FAIL new anchor phrases are present in the plan
FAIL the milestone gating rule includes M1 in all"
actual_fails="$(printf '%s\n' "$old_out" | grep -E '^FAIL ' | cut -c1-48)"
expected_cut="$(printf '%s\n' "$expected_fails" | cut -c1-48)"
if [[ $old_status -eq 1 && "$actual_fails" == "$expected_cut" ]]; then
  control_old=0
  echo "control: the draft 0.7 checker fails on exactly those two checks, as it must"
else
  control_old=1
  echo "PROBLEM: the draft 0.7 checker's failures are not exactly the two expected"
fi
echo
echo "== control, not required (this work changes no contract): Scripts/ci.sh contracts"
Scripts/ci.sh contracts
control=$?
echo "exit status: $control"
if [[ $status -ne 0 || $mutation -ne 0 || $control_old -ne 0 || $control -ne 0 ]]; then exit 1; fi
exit 0
