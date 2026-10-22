#!/usr/bin/env bash
# Runs the M0 plan-amendment checks for plan draft 0.8 as revised and corrected on 23 October 2026 (the follow-up's fix,
# after the review of the follow-up; integration log section 21), and prints a header naming the environment. The
# successor of Docs/Stage0/evidence/M0-Decisions/followup/commands/run-checks.sh, which is the current equivalent of
# Docs/Stage0/evidence/M0-Decisions/plan/commands/run-checks.sh: this round's checker (the follow-up's, its checks
# 10g-10i changed and 10j added) and its 51 mutations, then five controls:
#   0. the follow-up's checker must fail on exactly two checks: 10h, whose sentence of 21.1 ("so no device has to be
#      acquired") this round replaced, and 10i, which required the dated item of 23 October 2026 to be the entry's last;
#   1. the first fix's checker must fail on exactly two checks: the anchor "**Revised:** 22 October 2026", missing, and
#      its 10f, which required PO-12's sources file and import ledger open, missing exactly its two open phrases;
#   2. the plan round's checker must fail on exactly one check: the same anchor, missing;
#   3. the draft 0.7 checker must fail on exactly its two expected checks, as in the earlier rounds' logs;
#   4. Scripts/ci.sh contracts (not required: this round changes no contract).
# Usage, from the repository root, on a clean tree whose HEAD is the commit under test:
#   Docs/Stage0/evidence/M0-Decisions/followup/round-2/commands/run-checks.sh <commit under test> > <log> 2>&1
set -uo pipefail
here=Docs/Stage0/evidence/M0-Decisions/followup/round-2/commands
followup=Docs/Stage0/evidence/M0-Decisions/followup/commands
fix1=Docs/Stage0/evidence/M0-Decisions/fix-1/commands
plan=Docs/Stage0/evidence/M0-Decisions/plan/commands
commit="${1:?usage: run-checks.sh <commit under test>}"
echo "# M0 plan amendments and decisions: consistency checks (plan draft 0.8 as revised and corrected on 23 October 2026, the follow-up's fix's checker)"
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
echo "== control 0: the follow-up's checker, $followup/check-amendments.py"
echo "   It must fail on exactly two checks: 10h, on the sentence of 21.1 this round replaced (no device has to be"
echo "   acquired, before the iPad's iPadOS is known), and 10i, which required the dated item of 23 October 2026 to be"
echo "   the last item of Appendix D's draft 0.8 entry, where this round's correction item now follows it."
followup_out="$(python3 -I "$followup/check-amendments.py" 2>&1)"
followup_status=$?
printf '%s\n' "$followup_out" | grep -E '^FAIL |^summary:'
echo "exit status: $followup_status"
printf '%s\n' "$followup_out" | python3 -I -c '
import sys
fails = [line[5:] for line in sys.stdin.read().splitlines() if line.startswith("FAIL ")]
h = ("draft 0.8 as revised on 23 October 2026: 19.1, 21.1 and the device-evidence risk row record the product "
     "owner'"'"'s iPad, and no text before Appendix D says none is available or asks to acquire one: 21.1: has an iPad "
     "with a hardware keyboard and a trackpad or mouse (23 October 2026; ADR-0001), so no device has to be acquired")
i = ("draft 0.8 as revised on 23 October 2026: Appendix D'"'"'s draft 0.8 entry ends with the dated item that records "
     "the answers of 23 October 2026: the last item lacks: *Recorded on 23 October 2026, within draft 0.8:; ")
sys.exit(0 if len(fails) == 2 and fails[0] == h and fails[1].startswith(i) else 1)
'
exact0=$?
if [[ $followup_status -eq 1 && $exact0 -eq 0 ]]; then
  control0=0
  echo "control 0: the follow-up's checker fails on exactly those two checks, as it must"
else
  control0=1
  echo "PROBLEM: the follow-up's checker's failures are not exactly the two expected"
fi
echo
echo "== control 1: the first fix's checker, $fix1/check-amendments.py"
echo "   It must fail on exactly two checks: the revision-date anchor of draft 0.8 as of 22 October 2026, and its 10f,"
echo "   which required PO-12's sources file and import ledger to stay the product owner's to decide."
fix1_out="$(python3 -I "$fix1/check-amendments.py" 2>&1)"
fix1_status=$?
printf '%s\n' "$fix1_out" | grep -E '^FAIL |^summary:'
echo "exit status: $fix1_status"
printf '%s\n' "$fix1_out" | python3 -I -c '
import sys
fails = [line[5:] for line in sys.stdin.read().splitlines() if line.startswith("FAIL ")]
anchor = "new anchor phrases are present in the plan (41): **Revised:** 22 October 2026"
po12 = ("draft 0.8: PO-12'"'"'s sources file and import ledger stay the product owner'"'"'s to decide in 15.5, and no text "
        "says a decision kept them so: 15.5 lacks: a repair path for a damaged sources file or import ledger is still "
        "the product owner'"'"'s to decide; 15.5 lacks: until it is decided a damaged one keeps the client'"'"'s launch deferred")
sys.exit(0 if fails == [anchor, po12] else 1)
'
exact1=$?
if [[ $fix1_status -eq 1 && $exact1 -eq 0 ]]; then
  control1=0
  echo "control 1: the first fix's checker fails on exactly those two checks, as it must"
else
  control1=1
  echo "PROBLEM: the first fix's checker's failures are not exactly the two expected"
fi
echo
echo "== control 2: the plan round's checker, $plan/check-amendments.py"
echo "   It must fail on exactly one check: the revision-date anchor of draft 0.8 as of 22 October 2026."
plan_out="$(python3 -I "$plan/check-amendments.py" 2>&1)"
plan_status=$?
printf '%s\n' "$plan_out" | grep -E '^FAIL |^summary:'
echo "exit status: $plan_status"
printf '%s\n' "$plan_out" | python3 -I -c '
import sys
fails = [line[5:] for line in sys.stdin.read().splitlines() if line.startswith("FAIL ")]
sys.exit(0 if fails == ["new anchor phrases are present in the plan (41): **Revised:** 22 October 2026"] else 1)
'
exact2=$?
if [[ $plan_status -eq 1 && $exact2 -eq 0 ]]; then
  control2=0
  echo "control 2: the plan round's checker fails on exactly that check, as it must"
else
  control2=1
  echo "PROBLEM: the plan round's checker's failures are not exactly the one expected"
fi
echo
echo "== control 3: the draft 0.7 checker, Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py"
echo "   It must fail on draft 0.8, and only on the anchors the decisions replaced: the check of new anchor phrases"
echo "   (draft 0.7's status, revision date and pending wording) and the milestone gating rule (the 21.2 M1 row's"
echo "   '(proposed, Section 21.1)', decided with PO-34)."
old_out="$(python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py 2>&1)"
old_status=$?
printf '%s\n' "$old_out" | grep -E '^FAIL |^summary:'
echo "exit status: $old_status"
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
exact3=$?
if [[ $old_status -eq 1 && $exact3 -eq 0 ]]; then
  control3=0
  echo "control 3: the draft 0.7 checker fails on exactly those two checks, listing exactly the ten replaced phrases and the 21.2 M1 row, as it must"
else
  control3=1
  echo "PROBLEM: the draft 0.7 checker's failures are not exactly the two expected"
fi
echo
echo "== control 4, not required (this round changes no contract): Scripts/ci.sh contracts"
Scripts/ci.sh contracts
control4=$?
echo "exit status: $control4"
if [[ $status -ne 0 || $mutation -ne 0 || $control0 -ne 0 || $control1 -ne 0 || $control2 -ne 0 || $control3 -ne 0 || $control4 -ne 0 ]]; then exit 1; fi
exit 0
