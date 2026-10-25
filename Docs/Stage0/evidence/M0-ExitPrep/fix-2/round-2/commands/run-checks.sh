#!/bin/bash
# The checks of the fix of the fifth review of the M0 exit preparation (26 October 2026; integration log section 35),
# run on its last documents commit with no uncommitted file. Every log goes into <out-dir>, outside the tree, so that the
# tree stays clean while they run (the amendments' runner refuses an unclean tree); the logs are then committed in this
# folder (its README lists them), and this fix's gate checks (gate-checks.sh beside this file) run on that commit.
#   Docs/Stage0/evidence/M0-ExitPrep/fix-2/round-2/commands/run-checks.sh <out-dir> [<extraction dir of the review records>]
# 1. The reading of m0-decisions against what the records now state (decisions-branch.py): the refs, read-only, the
#    commits main lacks and what they change, a merge of the two branches at 941ac9a2 and at this commit (git merge-tree
#    writes objects but no ref), the gate summary's checker with that branch's gate reports, and the earlier rounds'
#    part 1g.
# 2. The drop-ins that read the documents this fix changed: Scripts/ci.sh contracts (00-git-lfs, 10-contracts,
#    11-capture-anchor-contracts), Scripts/ci.d/12-dependency-lock.sh (it reads ADR-0014, whose status line and open
#    items this fix rewords; with the Zip guard's self-test) and Scripts/ci.d/13-hard-rules.sh (its audit reads every
#    committed and new file, this fix's scripts and logs among them), each through the re-pin round's run-logged.sh.
#    Nothing outside Docs/ changed, so no build product could be in play, and none is deleted.
# 3. This fix's reading of the three findings' citations at 941ac9a2, the commit the review read (finding-lines.py).
# 4. The checks under Docs/Stage0/evidence/ that read what this fix changed: the review records' own checks
#    (item-reviews.py check --extraction the extraction's folder, render --check and audit-probe.sh, unchanged; the gate
#    summary's Section 6.2 last row, ADR-0014's pointer line and the hand-over's README, which has a note, among what they
#    read); the assembly's runbook content check (the runbook has three notes more) with its controls, limits and step
#    coverage; the follow-up's fix's amendments checks with their mutations and controls; the assembly's
#    check-xcode-reading.py; and five earlier rechecks, each of which pins texts that this fix or an earlier one rewords
#    on purpose and must report exactly these groups, by design: the assembly's recheck-exit-prep.py its groups Z1-Z8,
#    R5, R6 and A, the first fix's recheck-fix-1.py its groups F2 and R, the third fix's recheck-hon.py its groups H1 and
#    R, each as on the fourth fix; the second fix's recheck-ev.py its groups E1 and R (R now also on the three texts
#    that called SEC-ZIPGUARD-01 closed, which this fix rewords: HON-EP-07); and the fourth fix's recheck-fix-2.py its
#    group R (the State line's clause, which now names this fix, and Section 6.2's cell for the fourth review). The gate
#    checks read the full list of texts each reports.
# 5. This fix's recheck (recheck-hon-ep.py beside this file).
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>, and no ref is written. Exit 1 if
# any check is not as expected.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, round-2, fix-2, M0-ExitPrep, evidence, Stage0, Docs
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:?usage: run-checks.sh <out-dir> [<extraction dir>]}"
extraction="${2:-}"
here=Docs/Stage0/evidence/M0-ExitPrep/fix-2/round-2/commands
ev4=Docs/Stage0/evidence/M0-ExitPrep/fix-2/commands
ev3=Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-3/commands
ev2=Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands
fix1=Docs/Stage0/evidence/M0-ExitPrep/fix-1/commands
asm=Docs/Stage0/evidence/M0-ExitPrep/assembly/commands
items=Docs/Stage0/evidence/M0-Integration/item-reviews/commands
logged=Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh
dec=Docs/Stage0/evidence/M0-Decisions
mkdir -p "$out"
head="$(git rev-parse HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"
echo "run-checks: HEAD $head, uncommitted paths: $dirty; logs in $out; start $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
[[ "$dirty" == 0 ]] || { echo "refused: run on a clean tree"; exit 2; }
status=0
run() {  # <log name> <command...>
  local name="$1"; shift
  "$@" > "$out/$name" 2>&1
  local s=$?
  echo "$name: exit $s"
  return $s
}
reported() {  # the groups a recheck's log reports, in order
  grep -E '^PROBLEM ' "$1" | sed -E 's/^PROBLEM +([A-Z0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//'
}
expect() {  # <log name> <script> <expected groups>: the recheck must exit 1 reporting exactly those groups
  local name="$1" script="$2" want="$3"
  "$logged" python3 -I "$script" "$root" > "$out/$name" 2>&1
  local code=$?
  local got
  got="$(reported "$out/$name")"
  echo "$name: exit $code (1 expected, reporting exactly $want, by design); reported: ${got:-none}"
  [[ $code == 1 && "$got" == "$want" ]] || status=1
}

# 1. The reading of m0-decisions.
run decisions-branch.log "$logged" python3 -I "$here/decisions-branch.py" || status=1

# 2. The drop-ins.
run ci-contracts.log "$logged" Scripts/ci.sh contracts || status=1
run 12-dependency-lock.log "$logged" Scripts/ci.d/12-dependency-lock.sh || status=1
run 13-hard-rules.log "$logged" Scripts/ci.d/13-hard-rules.sh || status=1

# 3. This fix's reading of the citations.
run finding-lines.log "$logged" python3 -I "$here/finding-lines.py" || status=1

# 4. The documents checks that read what this fix changed.
if [[ -n "$extraction" ]]; then
  run check-item-reviews.log "$logged" python3 -I "$items/item-reviews.py" check --extraction "$extraction" || status=1
else
  run check-item-reviews.log "$logged" python3 -I "$items/item-reviews.py" check || status=1
fi
run render-check.log "$logged" python3 -I "$items/item-reviews.py" render --check || status=1
run audit-probe.log "$logged" "$items/audit-probe.sh" || status=1
run runbook-content-check.log "$logged" "$dec/assembly/commands/runbook-content-check.sh" || status=1
run check-amendments.log "$dec/followup/round-2/commands/run-checks.sh" "$head" || status=1
run check-xcode-reading.log "$logged" python3 -I "$asm/check-xcode-reading.py" "$root" || status=1
expect recheck-exit-prep.log "$asm/recheck-exit-prep.py" "Z1 Z2 Z3 Z4 Z5 Z6 Z7 Z8 R5 R6 A"
expect recheck-fix-1.log "$fix1/recheck-fix-1.py" "F2 R"
expect recheck-ev.log "$ev2/recheck-ev.py" "E1 R"
expect recheck-hon.log "$ev3/recheck-hon.py" "H1 R"
expect recheck-fix-2.log "$ev4/recheck-fix-2.py" "R"

# 5. This fix's recheck.
run recheck-hon-ep.log "$logged" python3 -I "$here/recheck-hon-ep.py" "$root" || status=1
echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths; end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
