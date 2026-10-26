#!/bin/bash
# The checks of the fix of the fidelity findings of the review of m0-records-update (26 October 2026; integration log
# section 42), run on the fix's last documents commit with no uncommitted file. Each log is written into <out-dir> (by
# default Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/checks); the commit that follows adds them and nothing else.
#   Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/commands/run-checks.sh [<out-dir>]
# 1. finding-lines.py: every line the eleven findings cite holds the text they quote at 832a3636, and their claims about
#    other commits hold. Must pass.
# 2. retired-branch-texts.py (FID-RU-01's check): no live text names m0-sessions as a branch to build from, commit to or
#    merge into. Must pass on this tree; and two controls, each of which must fail: the tree of 832a3636, the commit the
#    review read, on exactly the eleven clauses the fix changed (CLAUDE.md 2, ADR-0002 3, the runbook's 0.7 1, the gate
#    summary 5), and a copy of this tree with 0.7's old record put back, on that clause alone. With --all, the same
#    check on this tree lists every mention it read, for audit.
# 3. m0-records-update's checks that this fix's changes reach, unchanged: owner-records-intact.py (the owner's eight
#    commits as committed) and step-08-paths.sh (runbook 0.8), each of which must pass; Scripts/ci.sh contracts,
#    Scripts/ci.d/12-dependency-lock.sh (CLAUDE.md's toolchain line, restored to m0-decisions's) and
#    Scripts/ci.d/13-hard-rules.sh (this fix's scripts among the files it audits), through the re-pin round's
#    run-logged.sh, each of which must pass; the device-A update's runbook content check and the step coverage, which
#    must pass; the correction texts on the trees of the three merged branches and of HEAD, which must agree.
# 4. The plan amendments: this fix's checker (check-amendments.py beside this file), which must pass, with its 73
#    mutations, each of which must be caught; m0-records-update's checker, which must fail exactly its check 10k, on
#    Section 9's pointer to the latest checker (by design: FID-RU-11 had it name the newest version); the accuracy fix's
#    checker, which must fail exactly its check 10k, as it did at m0-records-update.
# 5. The device-A records: m0-records-update's check-records.py, which must pass, and the records part's, which must fail
#    exactly its two checks, as it did at m0-records-update.
# 6. The earlier rechecks and gate checks that m0-records-update recorded as they report (they pin texts and states of
#    the branches they were written on): run unchanged and recorded as they report.
# 7. The gate summary's checker, m0-records-update's version, which must pass (every cited path exists, every Section 2
#    status agrees with its records). Run last, since the summary cites this folder's logs.
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>, and no ref is written. Exit 1 if
# any check is not as expected.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:-Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/checks}"
here=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/commands
ru=Docs/Stage0/evidence/M0-RecordsUpdate/commands
logged=Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh
devicea=Docs/Stage0/evidence/M0-DeviceA
exitprep=Docs/Stage0/evidence/M0-ExitPrep
scratch="$root/.build/scratch/fix-1-checks"
rm -rf "$scratch"; mkdir -p "$out" "$scratch"
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
header() {  # <log> <what>: the commit, the tree and the time, at the head of a log written here
  { echo "command: $2"; echo "commit: $head; uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')";
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"; echo; } > "$1"
}

# 1
run finding-lines.log 1 "$logged" python3 -I "$here/finding-lines.py"

# 2
log="$out/retired-branch-texts.log"
header "$log" "$here/retired-branch-texts.py, on this tree and on two controls"
{
  echo "== 1. this tree (HEAD): it must pass"
  python3 -I "$here/retired-branch-texts.py" "$root"; echo "exit: $?"
} >> "$log" 2>&1
grep -q '^result: pass$' "$log" || { echo "retired-branch-texts: this tree does not pass"; status=1; }
mkdir -p "$scratch/tree-832a3636" "$scratch/tree-0.7"
live=(CLAUDE.md README.md Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/ADRs Docs/Stage0/device-checklists
      Docs/Stage0/evidence/M0-RecordsUpdate)
git archive 832a3636 -- "${live[@]}" $(git ls-tree --name-only 832a3636 Docs/Stage0/ | grep '\.md$') \
  | tar -x -C "$scratch/tree-832a3636"
git archive HEAD -- "${live[@]}" $(git ls-tree --name-only HEAD Docs/Stage0/ | grep '\.md$') | tar -x -C "$scratch/tree-0.7"
python3 -I - "$scratch/tree-0.7/Docs/Stage0/M0-device-runbook.md" <<'EOF'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
new = "Record: commit the regenerated log on `m0-decisions` (0.3, step 6; from 24 October 2026"
old = "Record: commit the regenerated log on `m0-sessions` (0.3, step 6; until 24 October 2026 this said `m0-decisions`); update the G0.2 row. 20 min."
start = t.index(new)
end = t.index("update the G0.2 row. 20 min.", start) + len("update the G0.2 row. 20 min.")
open(p, "w", encoding="utf-8").write(t[:start] + old + t[end:])
EOF
{
  echo
  echo "== 2a. the tree of 832a3636, the commit the review read: it must fail, on exactly the eleven clauses this fix changed"
  python3 -I "$here/retired-branch-texts.py" "$scratch/tree-832a3636" | sed "s#$scratch/##"; echo "exit: ${PIPESTATUS[0]}"
  echo
  echo "== 2b. this tree with 0.7's old record put back: it must fail, on that clause alone"
  python3 -I "$here/retired-branch-texts.py" "$scratch/tree-0.7" | sed "s#$scratch/##"; echo "exit: ${PIPESTATUS[0]}"
} >> "$log" 2>&1
expected="CLAUDE.md:5 CLAUDE.md:5 Docs/ADRs/0002-repository-build-and-ci.md:41 Docs/ADRs/0002-repository-build-and-ci.md:42 Docs/ADRs/0002-repository-build-and-ci.md:42 Docs/Stage0/M0-device-runbook.md:210 Docs/Stage0/M0-gate.md:122 Docs/Stage0/M0-gate.md:466 Docs/Stage0/M0-gate.md:466 Docs/Stage0/M0-gate.md:471 Docs/Stage0/M0-gate.md:556"
got_a="$(sed -n '/^== 2a/,/^== 2b/p' "$log" | sed -n '/^FAIL /,/^result/p' | grep -E '^  LIVE ' | awk '{print $2}' | sed 's/:$//' | tr '\n' ' ' | sed 's/ $//')"
got_b="$(sed -n '/^== 2b/,$p' "$log" | sed -n '/^FAIL /,/^result/p' | grep -E '^  LIVE ' | awk '{print $2}' | sed 's/:$//' | tr '\n' ' ' | sed 's/ $//')"
{
  echo
  echo "control 2a, the clauses found: $got_a"
  echo "control 2a, the clauses expected: $expected"
  echo "control 2b, the clauses found: $got_b"
} >> "$log"
if [[ "$got_a" == "$expected" && "$got_b" == Docs/Stage0/M0-device-runbook.md:* && "$got_b" != *" "* ]]; then
  echo "result: pass (this tree passes; each control fails on exactly its clauses)" >> "$log"
  echo "retired-branch-texts.log: pass (this tree passes; 2a fails on the eleven clauses; 2b on 0.7 alone)"
else
  echo "result: FAIL" >> "$log"; echo "retired-branch-texts.log: FAIL"; status=1
fi
run retired-branch-texts-all.log 1 python3 -I "$here/retired-branch-texts.py" "$root" --all

# 3
run owner-records-intact.log 1 python3 -I "$ru/owner-records-intact.py"
run step-0.8-paths.log 1 "$ru/step-08-paths.sh"
run ci-contracts.log 1 "$logged" Scripts/ci.sh contracts
run 12-dependency-lock.log 1 "$logged" Scripts/ci.d/12-dependency-lock.sh
run 13-hard-rules.log 1 "$logged" Scripts/ci.d/13-hard-rules.sh
run runbook-content-check.log 1 "$devicea/instructions/commands/runbook-content-check.sh"
run runbook-coverage.log 1 python3 -I Docs/Stage0/evidence/M0-Integration/final-fix/commands/runbook-coverage.py "$root"
run correction-texts.log 1 "$ru/correction-texts-compare.sh"

# 4
run check-amendments.log 1 python3 -I "$here/check-amendments.py" "$root"
run mutation-checks.log 1 python3 -I "$here/mutation-checks.py"
[[ -z "$(git status --porcelain -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md)" ]] \
  || { echo "PROBLEM: the mutations left the plan or the amendments changed"; status=1; }
python3 -I "$ru/check-amendments.py" "$root" > "$out/check-amendments-records-update.log" 2>&1
s=$?; n="$(grep -c '^FAIL ' "$out/check-amendments-records-update.log")"
echo "check-amendments-records-update.log: exit $s (1 expected, failing exactly its check 10k, on Section 9's pointer, by design); FAIL lines: $n"
[[ $s == 1 && $n == 1 ]] && grep -q "^FAIL draft 0.8 as revised on 24 October 2026: the product owner's decision on device A.*lacks, in Section 9: (the latest, for draft 0.8 as revised on 24 and 26 October 2026, \`evidence/M0-DeviceA/fix-1/accuracy/commands/check-amendments.py\`" "$out/check-amendments-records-update.log" \
  && [[ "$(grep '^FAIL ' "$out/check-amendments-records-update.log" | grep -o 'lacks, in ' | wc -l | tr -d ' ')" == 1 ]] \
  || status=1
python3 -I "$devicea/fix-1/accuracy/commands/check-amendments.py" "$root" > "$out/check-amendments-accuracy.log" 2>&1
s=$?; n="$(grep -c '^FAIL ' "$out/check-amendments-accuracy.log")"
echo "check-amendments-accuracy.log: exit $s (1 expected, failing exactly its check 10k, as at m0-records-update); FAIL lines: $n"
[[ $s == 1 && $n == 1 ]] && grep -q "^FAIL draft 0.8 as revised on 24 October 2026: the product owner's decision on device A" \
  "$out/check-amendments-accuracy.log" || status=1

# 5
run check-records.log 1 python3 -I "$ru/check-records.py" "$root"
python3 -I "$devicea/commands/check-records.py" "$root" > "$out/check-records-devicea.log" 2>&1
s=$?; n="$(grep -c '^FAIL ' "$out/check-records-devicea.log")"
echo "check-records-devicea.log: exit $s (1 expected, failing exactly its checks of the ADR index and of section 28, by design); FAIL lines: $n"
[[ $s == 1 && $n == 2 ]] && grep -q '^FAIL the ADR index: its status column dated 24 October 2026' "$out/check-records-devicea.log" \
  && grep -q '^FAIL the integration log: section 28 and its parts' "$out/check-records-devicea.log" || status=1

# 6
run recheck-hon-ep.log 0 "$logged" python3 -I "$exitprep/fix-2/round-2/commands/recheck-hon-ep.py" "$root"
run decisions-branch.log 0 "$logged" python3 -I "$exitprep/fix-2/round-2/commands/decisions-branch.py"
run recheck-own.log 0 "$logged" python3 -I "$devicea/fix-1/owner/commands/recheck-own.py" "$root"
"$exitprep/fix-2/round-2/commands/gate-checks.sh" "$out/gate-checks-exit-prep.log" > "$out/gate-checks-exit-prep.console.log" 2>&1
echo "gate-checks-exit-prep.log: exit $? (recorded as it reports)"
"$devicea/fix-1/owner/commands/gate-checks.sh" "$out/gate-checks-devicea.log" > "$out/gate-checks-devicea.console.log" 2>&1
echo "gate-checks-devicea.log: exit $? (recorded as it reports)"

# 7
run gate-refresh-check.log 1 python3 -I "$ru/gate-refresh-check.py" "$root"

echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths (the logs); end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
