#!/bin/bash
# The checks of the hand-over of the thirteen M0 items' review records (24 October 2026; ../README.md). Run from any
# directory, on a clean tree whose HEAD is the commit under test; every log goes into <out-dir>, outside the tree, so the
# tree stays clean while they run (the amendments' runner refuses an unclean tree); the logs are then committed under
# Docs/Stage0/evidence/M0-ExitPrep/reviews/, whose README lists them.
#   Docs/Stage0/evidence/M0-Integration/item-reviews/commands/run-checks.sh <out-dir> <base gate-checks log> [<extraction dir>]
# 1. The records: item-reviews.py check (with --extraction when the extraction's folder is given), render --check, and
#    audit-probe.sh.
# 2. The drop-ins every document change feeds: Scripts/ci.sh contracts (00-git-lfs, 10-contracts,
#    11-capture-anchor-contracts), Scripts/ci.d/12-dependency-lock.sh and Scripts/ci.d/13-hard-rules.sh, each through
#    the re-pin round's run-logged.sh.
# 3. The checks under Docs/Stage0/evidence/M0-Decisions/ that read the files this hand-over changed (the gate reports,
#    the runbook, the plan amendments, ADR-0015 and ADR-0016), unchanged: the assembly's runbook content check with its
#    controls, limits and step coverage; the follow-up's fix's amendments checks with their mutations and controls; and
#    the latest gate summary checks (unlocked-record/round-3), compared by compare-gate-checks.py with their run on the
#    commit this hand-over starts from (<base gate-checks log>), since that script fails by design on 5aec2518's
#    change of CLAUDE.md.
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>. Exit 1 if any check fails.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:?usage: run-checks.sh <out-dir> <base gate-checks log> [<extraction dir>]}"
base_log="${2:?usage: run-checks.sh <out-dir> <base gate-checks log> [<extraction dir>]}"
extraction="${3:-}"
here=Docs/Stage0/evidence/M0-Integration/item-reviews/commands
logged=Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh
dec=Docs/Stage0/evidence/M0-Decisions
mkdir -p "$out"
head="$(git rev-parse HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"
echo "run-checks: HEAD $head, uncommitted paths: $dirty; logs in $out"
[[ "$dirty" == 0 ]] || { echo "refused: run on a clean tree"; exit 2; }
status=0
run() {  # <log name> <command...>
  local name="$1"; shift
  "$@" > "$out/$name" 2>&1
  local s=$?
  echo "$name: exit $s"
  return $s
}
if [[ -n "$extraction" ]]; then
  run check-item-reviews.log "$logged" python3 -I "$here/item-reviews.py" check --extraction "$extraction" || status=1
else
  run check-item-reviews.log "$logged" python3 -I "$here/item-reviews.py" check || status=1
fi
run render-check.log "$logged" python3 -I "$here/item-reviews.py" render --check || status=1
run audit-probe.log "$logged" "$here/audit-probe.sh" || status=1
run ci-contracts.log "$logged" Scripts/ci.sh contracts || status=1
run 12-dependency-lock.log "$logged" Scripts/ci.d/12-dependency-lock.sh || status=1
run 13-hard-rules.log "$logged" Scripts/ci.d/13-hard-rules.sh || status=1
run runbook-content-check.log "$logged" "$dec/assembly/commands/runbook-content-check.sh" || status=1
run check-amendments.log "$dec/followup/round-2/commands/run-checks.sh" "$head" || status=1
"$dec/unlocked-record/round-3/commands/gate-checks.sh" "$out/gate-checks.log" > /dev/null 2>&1
echo "gate-checks.log: exit $? (1 expected, from its parts 1b and 1c on CLAUDE.md; compared next)"
run gate-checks-compare.log python3 -I "$here/compare-gate-checks.py" "$base_log" "$out/gate-checks.log" || status=1
echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
