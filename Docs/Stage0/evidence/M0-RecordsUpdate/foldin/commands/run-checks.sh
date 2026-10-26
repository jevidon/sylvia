#!/bin/bash
# The checks of the fold-in of m0-device-fixes into m0-records-update (27 October 2026 on the build Mac's clock;
# integration log section 45), run on the fold-in's last documents commit with no uncommitted file. Each log is written
# into <out-dir> (by default Docs/Stage0/evidence/M0-RecordsUpdate/foldin/checks), headed with the command, the commit,
# the uncommitted paths, the host and Xcode, the time and the load, and ended with the exit status, the time and the
# load; the console is written to run-checks.console.log there too. The commit that follows adds the logs and nothing
# else.
#   Docs/Stage0/evidence/M0-RecordsUpdate/foldin/commands/run-checks.sh [--dry] [<out-dir>]
# --dry runs on an uncommitted tree (for a dry run into a scratch folder); without it the runner refuses one.
# Must pass:
#  1. merge-check.sh: the merge commit, its parents, the two sides' files, and the device fixes' files at HEAD.
#  2. The owner's records: the owner fix's owner-records-intact.py with its defaults and with --owner-head m0-decisions
#     --rev HEAD (m0-decisions read only), and m0-records-update's version.
#  3. foldin-checks.py: the record requests as applied, CLAUDE.md's notes, the next steps, the word limits.
#  4. merge-simulation.sh: the owner's merge after the fold-in, in a scratch clone (no ref of this repository written).
#  5. step-08-paths.sh (this fold-in's version): runbook 0.8's paths changed since 9cdb0a02 by exactly the device fixes'
#     eleven files, so 0.8 runs again.
#  6. probe-count-check.sh: Scripts/ci.d/70-g05-ai.sh's own count check, with its new minimum, on committed probe logs
#     (no device, no simulator).
#  7. The fidelity fix's retired-branch-texts.py; the completeness fix's renumbered-references.py.
#  8. Scripts/ci.sh contracts, Scripts/ci.d/12-dependency-lock.sh, Scripts/ci.d/13-hard-rules.sh.
#  9. The device-A update's runbook content check (with its controls and limits) and the step coverage; the correction
#     texts on the trees of the three merged branches and HEAD.
# 10. The plan amendments, unchanged: the fidelity fix's checker and its 73 mutations (and the plan and the amendments
#     as committed afterwards); m0-records-update's and the accuracy fix's checkers fail exactly their check 10k, as
#     before.
# 11. The device-A records, unchanged: the completeness fix's check-records.py passes; m0-records-update's fails
#     exactly its check of the ADR index, and the records part's exactly its two checks, as before.
# 12. The owner fix's finding-lines.py (its findings at 832a3636).
# Recorded as they report, each failing by design on exactly the lines the fold-in's README gives (the runner checks
# the FAIL lines against that list):
# 13. m0-records-update's step-08-paths.sh (it expects no change since 9cdb0a02); the owner fix's owner-checks.py, its
#     completeness-checks.py and merge-simulation.sh, and the completeness fix's completeness-checks.py.
# Recorded as they report (they pin texts and states of the branches they were written on):
# 14. The earlier rechecks and gate checks: recheck-hon-ep.py, decisions-branch.py, recheck-own.py and the two
#     branches' gate-checks.sh; then compare-earlier-checks.py, which lists what they report beside what they reported
#     at the fix of the owner-readability findings (its logs in fix-1/owner/checks/).
# Must pass, run last since the summary cites this folder's logs:
# 15. The gate summary's checker, m0-records-update's version.
# No device; no simulator; no network; nothing is written outside .build/ and <out-dir>, and no ref of this repository
# is written. Exit 1 if any check is not as expected.
set -u
dry=0
if [[ "${1:-}" == "--dry" ]]; then dry=1; shift; fi
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:-Docs/Stage0/evidence/M0-RecordsUpdate/foldin/checks}"
here=Docs/Stage0/evidence/M0-RecordsUpdate/foldin/commands
owner=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands
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
echo "run-checks (fold-in): HEAD $head, uncommitted paths: $dirty; logs in $out; start $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
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
run() {  # <log name> <must pass: 1 or 0> <command...>
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
expect_fail() {  # <log name> <FAIL pattern, a grep -E of the lines that count> <expected count> <grep -F of an expected line>... -- <command...>
  local name="$1" pattern="$2" count="$3"; shift 3
  local lines=()
  while [[ "$1" != "--" ]]; do lines+=("$1"); shift; done
  shift
  header "$out/$name" "$*"
  "$@" >> "$out/$name" 2>&1
  local s=$?
  footer "$out/$name" $s
  local n; n="$(grep -Ec "$pattern" "$out/$name")"
  local ok=1 l
  [[ $s != 0 && $n == "$count" ]] || ok=0
  for l in "${lines[@]}"; do grep -qF -- "$l" "$out/$name" || ok=0; done
  echo "$name: exit $s (not 0 expected, exactly $count line(s) matching '$pattern', by design); found $n; as expected: $ok"
  (( ok == 1 )) || status=1
}

# 1
if (( dry )); then run merge-check.log 1 "$here/merge-check.sh" --worktree; else run merge-check.log 1 "$here/merge-check.sh"; fi

# 2
log="$out/owner-records-intact.log"
header "$log" "$owner/owner-records-intact.py (its defaults; --owner-head m0-decisions --rev HEAD) and $ru/owner-records-intact.py"
s_all=0
{
  echo "== 2a. the owner fix's version, with its defaults (the owner's commits 044ed3cf..c72247a6, the working tree)"
  python3 -I "$owner/owner-records-intact.py"; s=$?; echo "exit: $s"; (( s == 0 )) || s_all=1
  echo
  echo "== 2b. the owner fix's version, given the commit m0-decisions is at (read only) and HEAD"
  python3 -I "$owner/owner-records-intact.py" --owner-head m0-decisions --rev HEAD; s=$?; echo "exit: $s"
  (( s == 0 )) || s_all=1
  echo
  echo "== 2c. m0-records-update's version (the working tree)"
  python3 -I "$ru/owner-records-intact.py"; s=$?; echo "exit: $s"; (( s == 0 )) || s_all=1
} >> "$log" 2>&1
footer "$log" "$s_all"
echo "owner-records-intact.log: exit $s_all (0 required, all three)"
(( s_all == 0 )) || status=1

# 3
run foldin-checks.log 1 python3 -I "$here/foldin-checks.py"

# 4
if (( dry )); then run merge-simulation.log 1 "$here/merge-simulation.sh" --dry; else run merge-simulation.log 1 "$here/merge-simulation.sh"; fi

# 5
run step-0.8-paths.log 1 "$here/step-08-paths.sh"

# 6
run probe-count-check.log 1 "$here/probe-count-check.sh"

# 7
run retired-branch-texts.log 1 python3 -I "$fix1/retired-branch-texts.py" "$root"
run renumbered-references.log 1 python3 -I "$completeness/renumbered-references.py" "$root"

# 8
run ci-contracts.log 1 Scripts/ci.sh contracts
run 12-dependency-lock.log 1 Scripts/ci.d/12-dependency-lock.sh
run 13-hard-rules.log 1 Scripts/ci.d/13-hard-rules.sh

# 9
run runbook-content-check.log 1 "$devicea/instructions/commands/runbook-content-check.sh"
run runbook-coverage.log 1 python3 -I Docs/Stage0/evidence/M0-Integration/final-fix/commands/runbook-coverage.py "$root"
run correction-texts.log 1 "$ru/correction-texts-compare.sh"

# 10
run check-amendments.log 1 python3 -I "$fix1/check-amendments.py" "$root"
run mutation-checks.log 1 python3 -I "$fix1/mutation-checks.py"
[[ -z "$(git status --porcelain -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md)" ]] \
  || { echo "PROBLEM: the mutations left the plan or the amendments changed"; status=1; }
expect_fail check-amendments-records-update.log '^FAIL ' 1 \
  "FAIL draft 0.8 as revised on 24 October 2026: the product owner's decision on device A" \
  -- python3 -I "$ru/check-amendments.py" "$root"
expect_fail check-amendments-accuracy.log '^FAIL ' 1 \
  "FAIL draft 0.8 as revised on 24 October 2026: the product owner's decision on device A" \
  -- python3 -I "$devicea/fix-1/accuracy/commands/check-amendments.py" "$root"

# 11
run check-records.log 1 python3 -I "$completeness/check-records.py" "$root"
expect_fail check-records-records-update.log '^FAIL ' 1 "FAIL the ADR index: its status column dated 24 October 2026" \
  -- python3 -I "$ru/check-records.py" "$root"
expect_fail check-records-devicea.log '^FAIL ' 2 "FAIL the ADR index: its status column dated 24 October 2026" \
  "FAIL the integration log: section 28 and its parts" -- python3 -I "$devicea/commands/check-records.py" "$root"

# 12
run finding-lines.log 1 python3 -I "$owner/finding-lines.py"

# 13
expect_fail step-0.8-paths-records-update.log '^PROBLEM' 2 "PROBLEM: the drop-in's paths changed" \
  "PROBLEM: changed outside DeviceTests: Spikes/G05-Recovery/Sources/SylviaRecovery/Backup/Container.swift" \
  -- "$ru/step-08-paths.sh"
expect_fail owner-checks.log '^FAIL ' 5 \
  "FAIL 2 the merge commands, in order: the log line, the fast-forward merge, the apply command, the diff, the lock check, the commit, the commit noted" \
  "FAIL 4 CLAUDE.md is byte for byte c72247a6's" \
  "FAIL 4 the runbook's 0.3, step 2: the command, the same pause, and its history clause" \
  "FAIL 4 the gate summary's item 1, step 2: the command, the same pause, and its history clause" \
  "FAIL 5 no checklist changed since 7c87a82d" \
  -- python3 -I "$owner/owner-checks.py"
for v in owner completeness; do
  dir="$owner"; [[ $v == completeness ]] && dir="$completeness"
  expect_fail "completeness-checks-$v.log" '^FAIL ' 14 \
    "FAIL 1 CLAUDE.md is byte for byte c72247a6's" \
    "FAIL 1 the gate summary's item 1, step 2: its latest time and both texts" \
    "FAIL 1 the runbook's 0.3, step 2: its latest time and both texts" \
    "FAIL 1 the runbook's run 1: step 2 with the merge at the latest" \
    "FAIL 6 against 96bdc7e9:" "FAIL 6 against 8404f342:" "FAIL 6 against 432acc13:" "FAIL 6 against 4be1a1a4:" \
    "FAIL 6 against d5336111:" "FAIL 6 against c72247a6:" \
    "FAIL 7 every file this branch changes against c72247a6 is in a group the merge bullet names" \
    "FAIL 7 CLAUDE.md is not among them" \
    -- python3 -I "$dir/completeness-checks.py"
done
expect_fail merge-simulation-owner.log '^FAIL  ' 7 \
  "FAIL  the apply command exits 0 and git diff --stat shows CLAUDE.md alone, 4 ++--" \
  "FAIL  the commit changes CLAUDE.md alone" \
  "FAIL  0.8's check prints nothing: 0.8 still needs nothing" \
  "FAIL  against d5336111 it lists the eight checklists and the Zip guard's two scripts alone" \
  "FAIL  Docs/Stage0/evidence/G04-Audio/device/step-01-status.txt: differs from" \
  "FAIL  Docs/Stage0/evidence/M0-runbook/sessions.md: differs from" \
  -- "$owner/merge-simulation.sh"

# 14
run recheck-hon-ep.log 0 python3 -I "$exitprep/fix-2/round-2/commands/recheck-hon-ep.py" "$root"
run decisions-branch.log 0 python3 -I "$exitprep/fix-2/round-2/commands/decisions-branch.py"
run recheck-own.log 0 python3 -I "$devicea/fix-1/owner/commands/recheck-own.py" "$root"
"$exitprep/fix-2/round-2/commands/gate-checks.sh" "$out/gate-checks-exit-prep.log" > "$out/gate-checks-exit-prep.console.log" 2>&1
echo "gate-checks-exit-prep.log: exit $? (recorded as it reports)"
"$devicea/fix-1/owner/commands/gate-checks.sh" "$out/gate-checks-devicea.log" > "$out/gate-checks-devicea.console.log" 2>&1
echo "gate-checks-devicea.log: exit $? (recorded as it reports)"
run compare-earlier-checks.log 0 python3 -I "$here/compare-earlier-checks.py" "$out"

# 15
run gate-refresh-check.log 1 python3 -I "$ru/gate-refresh-check.py" "$root"

echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths (the logs); end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
