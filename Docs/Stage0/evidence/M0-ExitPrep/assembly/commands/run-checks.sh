#!/bin/bash
# The documents checks of the assembly of the M0 exit preparation (24 and 26 October 2026; integration log section 30),
# run on its last documents commit with no uncommitted file; every log goes into <out-dir>, outside the tree, so the tree
# stays clean while they run (the amendments' runner refuses an unclean tree); the logs are then committed beside this
# folder (its README lists them), and this round's gate checks (gate-checks.sh beside this file) run on that commit.
#   Docs/Stage0/evidence/M0-ExitPrep/assembly/commands/run-checks.sh <out-dir> [<extraction dir of the review records>]
# 1. The drop-ins every document change feeds: Scripts/ci.sh contracts (00-git-lfs, 10-contracts,
#    11-capture-anchor-contracts), Scripts/ci.d/12-dependency-lock.sh (with the zip guard's self-test) and
#    Scripts/ci.d/13-hard-rules.sh, each through the re-pin round's run-logged.sh.
# 2. The checks under Docs/Stage0/evidence/M0-Decisions/, newest versions, unchanged: the assembly's runbook content check
#    with its controls, limits and step coverage; the follow-up's fix's amendments checks with their mutations and
#    controls; and the latest gate summary checks (unlocked-record/round-3), which fail by design on this round,
#    each of their problem lines accounted for by compare-round-3.py against their run on 5aec2518.
# 3. The review records' own checks (item-reviews.py check, with --extraction when the extraction's folder is given,
#    render --check, audit-probe.sh), since the assembly changed texts they read.
# 4. This round's own: check-xcode-reading.py (the relay of Apple's pages against the repository) and
#    recheck-exit-prep.py (every request and what the assembly recorded besides them).
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>. Exit 1 if any check is not as
# expected.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:?usage: run-checks.sh <out-dir> [<extraction dir>]}"
extraction="${2:-}"
here=Docs/Stage0/evidence/M0-ExitPrep/assembly/commands
items=Docs/Stage0/evidence/M0-Integration/item-reviews/commands
logged=Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh
dec=Docs/Stage0/evidence/M0-Decisions
base_log=Docs/Stage0/evidence/M0-ExitPrep/reviews/gate-checks-at-5aec2518.log
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
run ci-contracts.log "$logged" Scripts/ci.sh contracts || status=1
run 12-dependency-lock.log "$logged" Scripts/ci.d/12-dependency-lock.sh || status=1
run 13-hard-rules.log "$logged" Scripts/ci.d/13-hard-rules.sh || status=1
run runbook-content-check.log "$logged" "$dec/assembly/commands/runbook-content-check.sh" || status=1
run check-amendments.log "$dec/followup/round-2/commands/run-checks.sh" "$head" || status=1
if [[ -n "$extraction" ]]; then
  run check-item-reviews.log "$logged" python3 -I "$items/item-reviews.py" check --extraction "$extraction" || status=1
else
  run check-item-reviews.log "$logged" python3 -I "$items/item-reviews.py" check || status=1
fi
run render-check.log "$logged" python3 -I "$items/item-reviews.py" render --check || status=1
run audit-probe.log "$logged" "$items/audit-probe.sh" || status=1
run check-xcode-reading.log "$logged" python3 -I "$here/check-xcode-reading.py" "$root" || status=1
run recheck-exit-prep.log "$logged" python3 -I "$here/recheck-exit-prep.py" "$root" || status=1
"$dec/unlocked-record/round-3/commands/gate-checks.sh" "$out/gate-checks-round-3.log" > /dev/null 2>&1
echo "gate-checks-round-3.log: exit $? (1 expected: the second fix's gate checks fail by design on this round; accounted for next)"
run gate-checks-round-3-compare.log "$logged" python3 -I "$here/compare-round-3.py" "$base_log" "$out/gate-checks-round-3.log" || status=1
echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths; end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
