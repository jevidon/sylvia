#!/bin/bash
# The checks under Docs/Stage0/evidence/ that read what the fix of ADR-0014's review round 4 changed besides the check
# and its drop-in: ADR-0014 (its status line, sections 1-7, Evidence and open items), Docs/Licenses/third-party-inventory.md
# and the new Markdown files of Docs/Stage0/evidence/M0-dependencies/xcode-27.1/ and of this folder.
#
#   Docs/Stage0/evidence/M0-ExitPrep/zipguard/commands/docs-checks.sh > Docs/Stage0/evidence/M0-ExitPrep/zipguard/docs-checks.log 2>&1
#
# Each check runs unchanged, as committed, on this checkout's tree, and is compared with what it reported on 26530d49's
# successor, the last record of the decisions round (Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-3/
# gate-checks.log), merged into main by pull request #6:
#  - the gate summary's checker (M0-Integration/commands/gate-refresh-check.py): Section 2's statuses against the ADR
#    status lines they rest on, ADR-0014's among them (row 76 reads "reject", "R4-01" and "R4-02" in it, rows 66, 78 and
#    92 its "Proposed", row 77 its section 7): it must pass, as before;
#  - the rechecks that read ADR-0014: recheck-review4.py must report exactly FID4-02 and FID4-06, as before;
#    recheck-hon4.py and recheck-own5.py must pass, as before; recheck-own4.py must report OWN4-01, as before, and now
#    OWN4-07 too, which reports that a run under Xcode 27.1 is recorded while the records it reads (the gate summary's
#    item 4 and Section 7, the runbook's Session 10) still call it pending: those are the records this fix asks their
#    owners to update (the gate summary, the runbook and the integration log are not this fix's files);
#  - the recheck that reads every Markdown file under Docs/ (unlocked-record/round-3/commands/recheck-unl2.py), so the
#    new files here too: it must pass, as before; and the follow-up's recheck-review2.py and the moved-notes checks,
#    which read texts this fix did not touch, must pass, as before.
# The runbook's content, coverage and correction-text checks read the runbook, the checklists and other ADRs, none of
# which this fix touched, and are not run. Read-only; host only; standard library Python.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$ROOT" || exit 1
D=Docs/Stage0/evidence/M0-Decisions
status=0
echo "docs-checks started $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD); uncommitted files: $(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
run() { # label, expected problems (space-separated ids, or "pass"), command...
  local label="$1" want="$2"; shift 2
  local out code got
  out="$("$@" 2>&1)"; code=$?
  got="$(printf '%s\n' "$out" | grep -E '^PROBLEM +[A-Z0-9-]+:' | sed -E 's/^PROBLEM +([A-Z0-9-]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
  [[ -z "$got" && $code == 0 ]] && got=pass
  echo
  echo "-- $label: exit $code; reported: $got; expected: $want"
  printf '%s\n' "$out" | sed 's/^/   /'
  if [[ "$got" == "$want" ]]; then echo "   as expected"; else echo "   NOT as expected"; status=1; fi
}
run "the gate summary's checker (gate-refresh-check.py)" pass python3 -I Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py "$ROOT"
run "the follow-up's recheck of the second review's findings (recheck-review2.py)" pass python3 -I "$D/followup/commands/recheck-review2.py" "$ROOT"
run "the follow-up's fix's recheck of FID4-01 to FID4-08 (recheck-review4.py)" "FID4-02 FID4-06" python3 -I "$D/followup/round-2/commands/recheck-review4.py" "$ROOT"
run "the second fix's recheck of HON4-01 to HON4-06 (recheck-hon4.py)" pass python3 -I "$D/followup/round-3/commands/recheck-hon4.py" "$ROOT"
run "the third fix's recheck of OWN4-01 to OWN4-09 (recheck-own4.py)" "OWN4-01 OWN4-07" python3 -I "$D/followup/round-4/commands/recheck-own4.py" "$ROOT"
run "the third fix's moved history notes (round-4 moved-notes.py)" pass python3 -I "$D/followup/round-4/commands/moved-notes.py" "$ROOT"
run "the fourth fix's recheck of OWN5-01 to OWN5-06 and the answers (recheck-own5.py)" pass python3 -I "$D/followup/round-5/commands/recheck-own5.py" "$ROOT"
run "the fourth fix's moved texts (round-5 moved-notes.py)" pass python3 -I "$D/followup/round-5/commands/moved-notes.py" "$ROOT"
run "the record's second fix's recheck, every Markdown file under Docs/ included (recheck-unl2.py)" pass python3 -I "$D/unlocked-record/round-3/commands/recheck-unl2.py" "$ROOT"
echo
echo "docs-checks finished $(date -u +%Y-%m-%dT%H:%M:%SZ); $( (( status == 0 )) && echo 'every check as expected' || echo 'NOT every check as expected')"
exit $status
