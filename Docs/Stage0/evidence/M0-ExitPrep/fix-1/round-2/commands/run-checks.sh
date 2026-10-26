#!/bin/bash
# The checks of the fix of the second review of the M0 exit preparation (26 October 2026; integration log section 32),
# run on its last documents commit with no uncommitted file. Every log goes into <out-dir>, outside the tree, so that the
# tree stays clean while they run (the amendments' runner refuses an unclean tree); the logs are then committed in this
# folder (its README lists them), and this fix's gate checks (gate-checks.sh beside this file) run on that commit.
#   Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands/run-checks.sh <out-dir> [<extraction dir of the review records>]
# 1. The drop-ins that read the documents this fix changed: Scripts/ci.sh contracts (00-git-lfs, 10-contracts,
#    11-capture-anchor-contracts), Scripts/ci.d/12-dependency-lock.sh (it reads ADR-0014, whose status has a note; with
#    the Zip guard's self-test) and Scripts/ci.d/13-hard-rules.sh (its audit reads every committed and new file, this
#    fix's scripts and logs among them), each through the re-pin round's run-logged.sh. Nothing outside Docs/ changed,
#    so no build product could be in play, and none is deleted.
# 2. This fix's two reads of the repository: finding-lines.py (every line the four findings cite, at 83030fba and,
#    where they place it, 609ed492) and branch-reach.py (where the 28 commits the review records cite are kept).
# 3. The checks under Docs/Stage0/evidence/ that read what this fix changed: the review records' own checks
#    (item-reviews.py check --extraction the extraction's folder and render --check, as this fix changed the script,
#    and audit-probe.sh); the assembly's runbook content check (the runbook's Who wrote it has a note) with its
#    controls, limits and step coverage; the follow-up's fix's amendments checks with their mutations and controls
#    (ADR-0014 has a note); the assembly's check-xcode-reading.py, and its recheck-exit-prep.py, which must report
#    exactly its group R6, as on the first fix; and the first fix's recheck-fix-1.py, which must report exactly its
#    group R, by design: the State line no longer says that the fix of the first review has not been reviewed (the gate
#    checks check each report's text).
# 4. This fix's recheck (recheck-ev.py beside this file).
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>. Exit 1 if any check is not as
# expected.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, round-2, fix-1, M0-ExitPrep, evidence, Stage0, Docs
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:?usage: run-checks.sh <out-dir> [<extraction dir>]}"
extraction="${2:-}"
here=Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands
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

# 1. The drop-ins.
run ci-contracts.log "$logged" Scripts/ci.sh contracts || status=1
run 12-dependency-lock.log "$logged" Scripts/ci.d/12-dependency-lock.sh || status=1
run 13-hard-rules.log "$logged" Scripts/ci.d/13-hard-rules.sh || status=1

# 2. This fix's reads of the repository.
run finding-lines.log "$logged" python3 -I "$here/finding-lines.py" || status=1
run branch-reach.log "$logged" python3 -I "$here/branch-reach.py" || status=1

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
"$logged" python3 -I "$asm/recheck-exit-prep.py" "$root" > "$out/recheck-exit-prep.log" 2>&1
code=$?
got="$(reported "$out/recheck-exit-prep.log")"
echo "recheck-exit-prep.log: exit $code (1 expected, reporting exactly R6, as on the first fix); reported: ${got:-none}"
[[ $code == 1 && "$got" == R6 ]] || status=1
"$logged" python3 -I "$fix1/recheck-fix-1.py" "$root" > "$out/recheck-fix-1.log" 2>&1
code=$?
got="$(reported "$out/recheck-fix-1.log")"
echo "recheck-fix-1.log: exit $code (1 expected, reporting exactly R, by design); reported: ${got:-none}"
[[ $code == 1 && "$got" == R ]] || status=1

# 4. This fix's recheck.
run recheck-ev.log "$logged" python3 -I "$here/recheck-ev.py" "$root" || status=1
echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths; end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
