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
# Exact comparison: two failed checks; the first lists exactly the ten draft 0.7 phrases the decisions replaced, the
# second names only the 21.2 M1 row. (A first version of this comparison cut each line to 48 characters and failed
# on a trailing space although the failures were exactly these: its run on 66237abc printed a PROBLEM line wrongly.)
printf '%s\n' "$old_out" | python3 -I -c '
import sys
fails = [line[5:] for line in sys.stdin.read().splitlines() if line.startswith("FAIL ")]
anchors = {"**Status:** Draft 0.7", "**Revised:** 20 October 2026",
           "the task window bounds those copies per job, and nothing bounds them across jobs yet",
           "nothing bounds them across jobs until the product owner chooses",
           "**Per-file timing mode (proposed, pending product-owner approval).**",
           "**Import remux (proposed, pending product-owner approval).**",
           "Which hosts count as local is proposed",
           "Every narrowing of release scope in draft 0.5 is a proposal.",
           "approving draft 0.5 does not by itself approve it",
           "Proposed for the job store (product-owner decision pending)"}
head = "new anchor phrases are present in the plan (38): "
gating = "the milestone gating rule includes M1 in all 7 places that state it, and the earlier wording is gone: plan 21.2 M1 row"
ok = (len(fails) == 2 and fails[0].startswith(head) and set(fails[0][len(head):].split("; ")) == anchors
      and fails[1] == gating)
sys.exit(0 if ok else 1)
'
exact=$?
if [[ $old_status -eq 1 && $exact -eq 0 ]]; then
  control_old=0
  echo "control: the draft 0.7 checker fails on exactly those two checks, listing exactly the ten replaced phrases and the 21.2 M1 row, as it must"
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
