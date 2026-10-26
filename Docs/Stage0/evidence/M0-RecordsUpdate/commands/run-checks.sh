#!/bin/bash
# The checks of m0-records-update (26 October 2026; integration log section 41), run on its last documents commit with no
# uncommitted file. Each log is written into <out-dir> (by default this branch's checks folder,
# Docs/Stage0/evidence/M0-RecordsUpdate/checks); the commit that follows adds them and nothing else.
#   Docs/Stage0/evidence/M0-RecordsUpdate/commands/run-checks.sh [<out-dir>]
# 1. owner-records-intact.py: the product owner's eight commits (8404f342..c72247a6) as committed: every file they added
#    or changed under Docs/Stage0/evidence/, Spikes/ and Docs/Licenses/inventory.json byte for byte, and every line they
#    added or removed in the records an agent also edits. Must pass.
# 2. step-08-paths.sh: runbook 0.8, what G0.5 recovery's drop-in builds, copies or runs, since 9cdb0a02. Must pass.
# 3. The drop-ins that read the documents: Scripts/ci.sh contracts, Scripts/ci.d/12-dependency-lock.sh (the Zip guard of
#    m0-exit-prep with the owner's lock for Spikes/G05-Recovery/DeviceTests) and Scripts/ci.d/13-hard-rules.sh, each
#    through the re-pin round's run-logged.sh. Each must pass.
# 4. The runbook: the device-A update's content check with its controls and limits (it runs the step coverage too),
#    which must pass, and the step coverage alone.
# 5. The plan amendments: this branch's checker (check-amendments.py beside this file), which must pass, with its
#    mutations (mutation-checks.py beside this file), each of which must be caught; and the accuracy fix's checker, which
#    must fail exactly its check 10k, by design (four of the texts it pins were renumbered or replaced here).
# 6. The device-A records: this branch's check-records.py, which must pass, and the records part's, which must fail
#    exactly its checks of the ADR index's date and of the integration log's section 28, by design.
# 7. The correction texts (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py), recorded as they read.
# 8. The two branches' latest rechecks and gate checks, run unchanged and recorded as they report, by design: they pin
#    the texts and the tree of the branch each was written on (m0-exit-prep at 941ac9a2..c3adae68, m0-sessions at
#    caf75a84..c2fd9ece), and this branch changed those texts and merged both trees with the owner's commits.
# 9. The gate summary's checker: this branch's version (gate-refresh-check.py beside this file), which must pass, and
#    the version it replaces, which must report exactly row 76's facts, by design (row 76 is passed-host since the Zip
#    guard's change was accepted). Run last, since the summary cites this folder's logs.
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>, and no ref is written. Exit 1 if
# any check is not as expected.
set -u
root="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:-Docs/Stage0/evidence/M0-RecordsUpdate/checks}"
here=Docs/Stage0/evidence/M0-RecordsUpdate/commands
logged=Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh
devicea=Docs/Stage0/evidence/M0-DeviceA
exitprep=Docs/Stage0/evidence/M0-ExitPrep
mkdir -p "$out"
head="$(git rev-parse HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"
echo "run-checks: HEAD $head, uncommitted paths: $dirty; logs in $out; start $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
[[ "$dirty" == 0 ]] || { echo "refused: run on a clean tree"; exit 2; }
status=0
run() {  # <log name> <must pass: 1 or 0> <command...>
  local name="$1" must="$2"; shift 2
  "$@" > "$out/$name" 2>&1
  local s=$?
  if [[ "$must" == 1 ]]; then
    echo "$name: exit $s (0 required)"
    (( s == 0 )) || status=1
  else
    echo "$name: exit $s (recorded as it reports)"
  fi
}
fails() {  # the FAIL lines of a checker's log, as one line
  grep -E '^FAIL ' "$1" | sed -E 's/^FAIL (.{0,90}).*/\1/' | tr '\n' '|' | sed 's/|$//'
}

# 1-2
run owner-records-intact.log 1 python3 -I "$here/owner-records-intact.py"
run step-0.8-paths.log 1 "$here/step-08-paths.sh"

# 3
run ci-contracts.log 1 "$logged" Scripts/ci.sh contracts
run 12-dependency-lock.log 1 "$logged" Scripts/ci.d/12-dependency-lock.sh
run 13-hard-rules.log 1 "$logged" Scripts/ci.d/13-hard-rules.sh

# 4
run runbook-content-check.log 1 "$devicea/instructions/commands/runbook-content-check.sh"
run runbook-coverage.log 1 python3 -I Docs/Stage0/evidence/M0-Integration/final-fix/commands/runbook-coverage.py "$root"

# 5
run check-amendments.log 1 python3 -I "$here/check-amendments.py" "$root"
run mutation-checks.log 1 python3 -I "$here/mutation-checks.py"
[[ -z "$(git status --porcelain -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md)" ]] \
  || { echo "PROBLEM: the mutations left the plan or the amendments changed"; status=1; }
python3 -I "$devicea/fix-1/accuracy/commands/check-amendments.py" "$root" > "$out/check-amendments-accuracy.log" 2>&1
s=$?; got="$(fails "$out/check-amendments-accuracy.log")"
echo "check-amendments-accuracy.log: exit $s (1 expected, failing exactly its check 10k, by design); fails: ${got:-none}"
[[ $s == 1 && "$(grep -c '^FAIL ' "$out/check-amendments-accuracy.log")" == 1 \
   && "$got" == "draft 0.8 as revised on 24 October 2026: the product owner's decision on device A (the iPhone 13 m" ]] || status=1

# 6
run check-records.log 1 python3 -I "$here/check-records.py" "$root"
python3 -I "$devicea/commands/check-records.py" "$root" > "$out/check-records-devicea.log" 2>&1
s=$?; n="$(grep -c '^FAIL ' "$out/check-records-devicea.log")"
echo "check-records-devicea.log: exit $s (1 expected, failing exactly its checks of the ADR index and of section 28, by design); FAIL lines: $n"
[[ $s == 1 && $n == 2 ]] && grep -q '^FAIL the ADR index: its status column dated 24 October 2026' "$out/check-records-devicea.log" \
  && grep -q '^FAIL the integration log: section 28 and its parts' "$out/check-records-devicea.log" || status=1

# 7
(cd "$root" && python3 -I Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py) > "$out/correction-texts.log" 2>&1
echo "correction-texts.log: exit $? (recorded as it reads)"

# 8
run recheck-hon-ep.log 0 "$logged" python3 -I "$exitprep/fix-2/round-2/commands/recheck-hon-ep.py" "$root"
run decisions-branch.log 0 "$logged" python3 -I "$exitprep/fix-2/round-2/commands/decisions-branch.py"
run recheck-own.log 0 "$logged" python3 -I "$devicea/fix-1/owner/commands/recheck-own.py" "$root"
"$exitprep/fix-2/round-2/commands/gate-checks.sh" "$out/gate-checks-exit-prep.log" > "$out/gate-checks-exit-prep.console.log" 2>&1
echo "gate-checks-exit-prep.log: exit $? (recorded as it reports)"
"$devicea/fix-1/owner/commands/gate-checks.sh" "$out/gate-checks-devicea.log" > "$out/gate-checks-devicea.console.log" 2>&1
echo "gate-checks-devicea.log: exit $? (recorded as it reports)"

# 9
run gate-refresh-check.log 1 python3 -I "$here/gate-refresh-check.py" "$root"
python3 -I Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py "$root" > "$out/gate-refresh-check-old.log" 2>&1
s=$?
probs="$(grep -E '^PROBLEM' "$out/gate-refresh-check-old.log" | sed 's/^PROBLEM: //' | tr '\n' '|' | sed 's/|$//')"
echo "gate-refresh-check-old.log: exit $s (1 expected, reporting exactly row 76's facts, by design); problems: ${probs:-none}"
[[ $s == 1 ]] && ! grep -E '^PROBLEM' "$out/gate-refresh-check-old.log" | grep -qv 'row 76' || status=1

echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths (the logs); end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
