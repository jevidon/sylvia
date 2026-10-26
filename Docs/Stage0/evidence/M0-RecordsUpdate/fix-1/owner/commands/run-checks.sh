#!/bin/bash
# The checks of the fix of the owner-readability findings of the review of m0-records-update (27 October 2026 on the
# build Mac's clock; integration log section 44), run on the fix's last documents commit with no uncommitted file. Each
# log is written into <out-dir> (by default Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/checks), headed with the
# commit, the uncommitted paths, the host and Xcode, the time and the load, and ended with the exit status, the time and
# the load; the console is written to run-checks.console.log there too. The commit that follows adds the logs and nothing
# else.
#   Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/run-checks.sh [--dry] [<out-dir>]
# --dry runs on an uncommitted tree (for a dry run into a scratch folder); without it the runner refuses one.
# 1. finding-lines.py: every line the eight findings cite holds the text they quote at 832a3636, and their claims about
#    other commits and branches hold. Must pass.
# 2. owner-checks.py: what this fix changed, part by part, and the earlier fixes' answers it relies on. Must pass.
# 3. merge-simulation.sh: the owner's merge, both ways, and the apply command, in a scratch clone (no ref of this
#    repository written). Must pass. With --dry, it runs with --dry too.
# 4. The owner's records: this fix's owner-records-intact.py with its defaults and with --owner-head m0-decisions --rev
#    HEAD (m0-decisions read only), and m0-records-update's version, which it replaces; each must pass.
# 5. The fix of the fidelity findings' retired-branch-texts.py (OWN-RU-01, OWN-RU-02): no live text names m0-sessions
#    as a branch to build from, commit to or merge into. Must pass.
# 6. The fix of the completeness findings' checks: this fix's version of completeness-checks.py, which must pass; the
#    version it replaces, which must fail exactly its three checks of the merge section that this fix rewrote, by
#    design; and renumbered-references.py on this tree, which must pass.
# 7. m0-records-update's step-08-paths.sh, which must pass; Scripts/ci.sh contracts, Scripts/ci.d/12-dependency-lock.sh
#    and Scripts/ci.d/13-hard-rules.sh (this fix's scripts among the files it audits), each of which must pass; the
#    device-A update's runbook content check and the step coverage, which must pass; the correction texts on the trees
#    of the three merged branches and of HEAD, which must agree.
# 8. The plan amendments, which this fix did not change: the fix of the fidelity findings' checker, which must pass,
#    with its 73 mutations, each of which must be caught; m0-records-update's and the accuracy fix's checkers, each of
#    which must fail exactly its check 10k, as before.
# 9. The device-A records, which this fix did not change: the fix of the completeness findings' check-records.py, which
#    must pass; m0-records-update's, which must fail exactly its check of the ADR index; and the records part's, which
#    must fail exactly its two checks, as before.
# 10. The earlier rechecks and gate checks that m0-records-update and its fixes recorded as they report (they pin texts
#    and states of the branches they were written on): run unchanged and recorded as they report.
# 11. The gate summary's checker, m0-records-update's version, which must pass (every cited path exists, every Section 2
#    status agrees with its records). Run last, since the summary cites this folder's logs.
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>, and no ref of this repository is
# written. Exit 1 if any check is not as expected.
set -u
dry=0
if [[ "${1:-}" == "--dry" ]]; then dry=1; shift; fi
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:-Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/checks}"
here=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands
completeness=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/commands
fix1=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/commands
ru=Docs/Stage0/evidence/M0-RecordsUpdate/commands
devicea=Docs/Stage0/evidence/M0-DeviceA
exitprep=Docs/Stage0/evidence/M0-ExitPrep
mkdir -p "$out"
console="$out/run-checks.console.log"
head="$(git rev-parse HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"
host="host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
exec > >(tee "$console") 2>&1
echo "run-checks: HEAD $head, uncommitted paths: $dirty; logs in $out; start $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "$host"
if [[ "$dirty" != 0 && $dry == 0 ]]; then echo "refused: run on a clean tree, or with --dry"; exit 2; fi
status=0
header() {  # <log> <what>
  { echo "command: $2"; echo "commit: $head; uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')";
    git status --porcelain | sed 's/^/  uncommitted: /'; echo "$host"
    echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"; echo; } > "$1"
}
footer() {  # <log> <exit status>
  { echo; echo "exit status: $2"; echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"; } >> "$1"
}
run() {  # <log name> <must pass: 1 or 0> <command...>: the log headed and ended here
  local name="$1" must="$2"; shift 2
  header "$out/$name" "$*"
  "$@" >> "$out/$name" 2>&1
  local s=$?
  footer "$out/$name" $s
  if [[ "$must" == 1 ]]; then
    echo "$name: exit $s (0 required)"
    (( s == 0 )) || status=1
  else
    echo "$name: exit $s (recorded as it reports)"
  fi
  return $s
}
expect_fail() {  # <log name> <expected FAIL count> <grep pattern of an expected FAIL line>... -- <command...>
  local name="$1" count="$2"; shift 2
  local patterns=()
  while [[ "$1" != "--" ]]; do patterns+=("$1"); shift; done
  shift
  header "$out/$name" "$*"
  "$@" >> "$out/$name" 2>&1
  local s=$?
  footer "$out/$name" $s
  local n; n="$(grep -c '^FAIL ' "$out/$name")"
  local ok=1 p
  [[ $s == 1 && $n == "$count" ]] || ok=0
  for p in "${patterns[@]}"; do grep -q -- "$p" "$out/$name" || ok=0; done
  echo "$name: exit $s (1 expected, failing exactly $count check(s), by design); FAIL lines: $n; as expected: $ok"
  (( ok == 1 )) || status=1
}

# 1
run finding-lines.log 1 python3 -I "$here/finding-lines.py"

# 2
run owner-checks.log 1 python3 -I "$here/owner-checks.py"

# 3
if (( dry )); then
  run merge-simulation.log 1 "$here/merge-simulation.sh" --dry
else
  run merge-simulation.log 1 "$here/merge-simulation.sh"
fi

# 4
log="$out/owner-records-intact.log"
header "$log" "$here/owner-records-intact.py (its defaults; --owner-head m0-decisions --rev HEAD) and $ru/owner-records-intact.py"
s_all=0
{
  echo "== 4a. this fix's version, with its defaults (the owner's commits 044ed3cf..c72247a6, the working tree)"
  python3 -I "$here/owner-records-intact.py"; s=$?; echo "exit: $s"; (( s == 0 )) || s_all=1
  echo
  echo "== 4b. this fix's version, given the commit m0-decisions is at (read only) and HEAD"
  python3 -I "$here/owner-records-intact.py" --owner-head m0-decisions --rev HEAD; s=$?; echo "exit: $s"
  (( s == 0 )) || s_all=1
  echo
  echo "== 4c. m0-records-update's version, which this fix's replaces (the working tree)"
  python3 -I "$ru/owner-records-intact.py"; s=$?; echo "exit: $s"; (( s == 0 )) || s_all=1
} >> "$log" 2>&1
footer "$log" "$s_all"
echo "owner-records-intact.log: exit $s_all (0 required, all three)"
(( s_all == 0 )) || status=1

# 5
run retired-branch-texts.log 1 python3 -I "$fix1/retired-branch-texts.py" "$root"

# 6
run completeness-checks.log 1 python3 -I "$here/completeness-checks.py"
expect_fail completeness-checks-completeness.log 3 \
  "^FAIL 1 the evidence README's merge commands apply the texts, commit them and run the lock check" \
  "^FAIL 1 the evidence README's Left for the owner and After the merge give the latest time" \
  "^FAIL 7 every file this branch changes against c72247a6 is in a group the merge bullet names" \
  -- python3 -I "$completeness/completeness-checks.py"
run renumbered-references.log 1 python3 -I "$completeness/renumbered-references.py" "$root"

# 7
run step-0.8-paths.log 1 "$ru/step-08-paths.sh"
run ci-contracts.log 1 Scripts/ci.sh contracts
run 12-dependency-lock.log 1 Scripts/ci.d/12-dependency-lock.sh
run 13-hard-rules.log 1 Scripts/ci.d/13-hard-rules.sh
run runbook-content-check.log 1 "$devicea/instructions/commands/runbook-content-check.sh"
run runbook-coverage.log 1 python3 -I Docs/Stage0/evidence/M0-Integration/final-fix/commands/runbook-coverage.py "$root"
run correction-texts.log 1 "$ru/correction-texts-compare.sh"

# 8
run check-amendments.log 1 python3 -I "$fix1/check-amendments.py" "$root"
run mutation-checks.log 1 python3 -I "$fix1/mutation-checks.py"
[[ -z "$(git status --porcelain -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md)" ]] \
  || { echo "PROBLEM: the mutations left the plan or the amendments changed"; status=1; }
expect_fail check-amendments-records-update.log 1 \
  "^FAIL draft 0.8 as revised on 24 October 2026: the product owner's decision on device A" \
  -- python3 -I "$ru/check-amendments.py" "$root"
expect_fail check-amendments-accuracy.log 1 \
  "^FAIL draft 0.8 as revised on 24 October 2026: the product owner's decision on device A" \
  -- python3 -I "$devicea/fix-1/accuracy/commands/check-amendments.py" "$root"

# 9
run check-records.log 1 python3 -I "$completeness/check-records.py" "$root"
expect_fail check-records-records-update.log 1 "^FAIL the ADR index: its status column dated 24 October 2026" \
  -- python3 -I "$ru/check-records.py" "$root"
expect_fail check-records-devicea.log 2 "^FAIL the ADR index: its status column dated 24 October 2026" \
  "^FAIL the integration log: section 28 and its parts" -- python3 -I "$devicea/commands/check-records.py" "$root"

# 10
run recheck-hon-ep.log 0 python3 -I "$exitprep/fix-2/round-2/commands/recheck-hon-ep.py" "$root"
run decisions-branch.log 0 python3 -I "$exitprep/fix-2/round-2/commands/decisions-branch.py"
run recheck-own.log 0 python3 -I "$devicea/fix-1/owner/commands/recheck-own.py" "$root"
"$exitprep/fix-2/round-2/commands/gate-checks.sh" "$out/gate-checks-exit-prep.log" > "$out/gate-checks-exit-prep.console.log" 2>&1
echo "gate-checks-exit-prep.log: exit $? (recorded as it reports)"
"$devicea/fix-1/owner/commands/gate-checks.sh" "$out/gate-checks-devicea.log" > "$out/gate-checks-devicea.console.log" 2>&1
echo "gate-checks-devicea.log: exit $? (recorded as it reports)"

# 11
run gate-refresh-check.log 1 python3 -I "$ru/gate-refresh-check.py" "$root"

echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths (the logs); end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
