#!/bin/bash
# The checks of the fix of the third review of the M0 exit preparation (26 October 2026; integration log section 33),
# run on its last documents commit with no uncommitted file. Every log goes into <out-dir>, outside the tree, so that the
# tree stays clean while they run (the amendments' runner refuses an unclean tree); the logs are then committed in this
# folder (its README lists them), and this fix's gate checks (gate-checks.sh beside this file) run on that commit.
#   Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-3/commands/run-checks.sh <out-dir> [<extraction dir of the review records>]
# 1. The drop-ins that read the documents this fix changed: Scripts/ci.sh contracts (00-git-lfs, 10-contracts,
#    11-capture-anchor-contracts), Scripts/ci.d/12-dependency-lock.sh (it reads ADR-0014, whose status and open items
#    this fix rewords; with the Zip guard's self-test) and Scripts/ci.d/13-hard-rules.sh (its audit reads every committed
#    and new file, this fix's scripts and logs among them), each through the re-pin round's run-logged.sh. Nothing
#    outside Docs/ changed, so no build product could be in play, and none is deleted.
# 2. This fix's reading of the five findings' citations at 415ae25b, the commit the review read (finding-lines.py).
# 3. The checks under Docs/Stage0/evidence/ that read what this fix changed: the review records' own checks
#    (item-reviews.py check --extraction the extraction's folder, and render --check, the deps record rendered again from
#    the script this fix changed; audit-probe.sh); the assembly's runbook content check (the runbook's notes changed) with
#    its controls, limits and step coverage; the follow-up's fix's amendments checks with their mutations and controls
#    (the plan's and the amendments' notes changed); the assembly's check-xcode-reading.py; and three earlier rechecks,
#    each of which pins texts this fix rewords on purpose and must report exactly these groups, by design: the
#    assembly's recheck-exit-prep.py its groups Z1-Z8, R5, R6 and A (the requested texts on R4-01, R4-02 and row 76, the
#    note on the final-review records in item 1's step 5, the Written by line's date beside the State line's clause it
#    reported already, and the preparation's dates: HON-EP-01 and HON-EP-05); the first fix's recheck-fix-1.py its groups
#    F2 (Section 6.1's note on both routes) and R (the State line's clause, as before, and the Written by line's date);
#    and the second fix's recheck-ev.py its groups E1 (the deps record's and the hand-over README's notes on R4-01 to
#    R4-04) and R (the State line's clause, which now names this fix, and Section 6.2's cell for its review). The gate
#    checks read the full list of texts each reports.
# 4. This fix's recheck (recheck-hon.py beside this file).
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>. Exit 1 if any check is not as
# expected.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, round-3, fix-1, M0-ExitPrep, evidence, Stage0, Docs
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:?usage: run-checks.sh <out-dir> [<extraction dir>]}"
extraction="${2:-}"
here=Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-3/commands
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

# 1. The drop-ins.
run ci-contracts.log "$logged" Scripts/ci.sh contracts || status=1
run 12-dependency-lock.log "$logged" Scripts/ci.d/12-dependency-lock.sh || status=1
run 13-hard-rules.log "$logged" Scripts/ci.d/13-hard-rules.sh || status=1

# 2. This fix's reading of the citations.
run finding-lines.log "$logged" python3 -I "$here/finding-lines.py" || status=1

# 3. The documents checks that read what this fix changed.
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

# 4. This fix's recheck.
run recheck-hon.log "$logged" python3 -I "$here/recheck-hon.py" "$root" || status=1
echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths; end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
