#!/bin/bash
# The checks of the fix of the completeness findings of the review of m0-records-update (27 October 2026 on the build
# Mac's clock; integration log section 43), run on the fix's last documents commit with no uncommitted file. Each log is
# written into <out-dir> (by default Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/checks), headed with the
# commit, the uncommitted paths, the host and Xcode, the time and the load, and ended with the exit status, the time and
# the load; the console is written to run-checks.console.log there too. The commit that follows adds the logs and nothing
# else.
#   Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/commands/run-checks.sh [--dry] [<out-dir>]
# --dry runs on an uncommitted tree (for a dry run into a scratch folder); without it the runner refuses one.
# 1. finding-lines.py: every line the seven findings cite holds the text they quote at 832a3636, and their claims about
#    other commits hold. Must pass.
# 2. renumbered-references.py (CMP-03): every reference to an item or a section that the merges brought is numbered as
#    the merged records number it. Must pass on this tree; and two controls, each of which must fail on exactly its
#    wrong references: the tree of 832a3636, the commit the review read (the four CMP-03 names and item 150's), and a
#    copy of this tree with CMP-03's four references put back (those four). With --list-new, on this tree, every
#    reference written after the merges, with what it names, for audit.
# 3. completeness-checks.py: what this fix changed, part by part (CMP-01 to CMP-07, and its records), with the sweep of
#    part 5. Must pass. And its sweep alone on the tree of 7f7eae88, the commit this fix started from, as a control: it
#    must fail on exactly the 16 open paragraphs this fix gave later notes.
# 4. The fix of the fidelity findings' retired-branch-texts.py (CMP-02): no live text names m0-sessions as a branch to
#    build from, commit to or merge into. Must pass.
# 5. m0-records-update's owner-records-intact.py and step-08-paths.sh, each of which must pass; Scripts/ci.sh contracts,
#    Scripts/ci.d/12-dependency-lock.sh (ADR-0014, which this fix gave a note, among what it reads) and
#    Scripts/ci.d/13-hard-rules.sh (this fix's scripts among the files it audits), each of which must pass; the
#    device-A update's runbook content check and the step coverage, which must pass; the correction texts on the trees
#    of the three merged branches and of HEAD, which must agree.
# 6. The plan amendments, which this fix did not change: the fix of the fidelity findings' checker, which must pass,
#    with its 73 mutations, each of which must be caught; m0-records-update's and the accuracy fix's checkers, each of
#    which must fail exactly its check 10k, as at that fix.
# 7. The device-A records: this fix's check-records.py (beside this file), which must pass; m0-records-update's, which
#    must fail exactly its check of the ADR index, whose column this fix dated 27 October 2026, by design; and the
#    records part's, which must fail exactly its two checks, as before.
# 8. The earlier rechecks and gate checks that m0-records-update and its first fix recorded as they report (they pin
#    texts and states of the branches they were written on): run unchanged and recorded as they report.
# 9. The gate summary's checker, m0-records-update's version, which must pass (every cited path exists, every Section 2
#    status agrees with its records). Run last, since the summary cites this folder's logs.
# No simulator, no device, no network; nothing is written outside .build/ and <out-dir>, and no ref is written. Exit 1 if
# any check is not as expected.
set -u
dry=0
if [[ "${1:-}" == "--dry" ]]; then dry=1; shift; fi
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
out="${1:-Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/checks}"
here=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/completeness/commands
fix1=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/commands
ru=Docs/Stage0/evidence/M0-RecordsUpdate/commands
devicea=Docs/Stage0/evidence/M0-DeviceA
exitprep=Docs/Stage0/evidence/M0-ExitPrep
scratch="$root/.build/scratch/completeness-checks"
rm -rf "$scratch"; mkdir -p "$out" "$scratch"
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
expect_fail() {  # <log name> <grep pattern of the one expected FAIL line> <expected FAIL count> <command...>
  local name="$1" pattern="$2" count="$3"; shift 3
  header "$out/$name" "$*"
  "$@" >> "$out/$name" 2>&1
  local s=$?
  footer "$out/$name" $s
  local n; n="$(grep -c '^FAIL ' "$out/$name")"
  echo "$name: exit $s (1 expected, failing exactly $count check(s), by design); FAIL lines: $n"
  [[ $s == 1 && $n == "$count" ]] && grep -q "$pattern" "$out/$name" || status=1
}

# 1
run finding-lines.log 1 python3 -I "$here/finding-lines.py"

# 2
log="$out/renumbered-references.log"
header "$log" "$here/renumbered-references.py, on this tree and on two controls"
{
  echo "== 2a. this tree (HEAD): it must pass"
  python3 -I "$here/renumbered-references.py" "$root"; echo "exit: $?"
} >> "$log" 2>&1
grep -q '^result: pass$' "$log" || { echo "renumbered-references: this tree does not pass"; status=1; }
records=(Docs/Stage0/M0-gate.md Docs/Stage0/M0-device-runbook.md Docs/Stage0/README.md Docs/ADRs/README.md
         Docs/Stage0/M0-plan-amendments.md Docs/Stage0/integration-log.md)
mkdir -p "$scratch/tree-832a3636" "$scratch/tree-cmp03"
git archive 832a3636 -- "${records[@]}" | tar -x -C "$scratch/tree-832a3636"
if (( dry )); then
  tar -c "${records[@]}" | tar -x -C "$scratch/tree-cmp03"
else
  git archive HEAD -- "${records[@]}" | tar -x -C "$scratch/tree-cmp03"
fi
python3 -I - "$scratch/tree-cmp03/Docs/Stage0/M0-gate.md" <<'EOF'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
for new, old in (("this line dated it 24 October alone: Section 6.3, item 173)",
                  "this line dated it 24 October alone: Section 6.3, item 146)"),
                 ("the Stage 0 README (Section 6.3, items 131-137;", "the Stage 0 README (Section 6.3, items 104-110;"),
                 ("the reports and the integration log, section 36), applied",
                  "the reports and the integration log, section 28), applied"),
                 ("made the two agree (Section 6.3, items 138-142).", "made the two agree (Section 6.3, items 111-115).")):
    assert t.count(new) == 1, new
    t = t.replace(new, old)
open(p, "w", encoding="utf-8").write(t)
EOF
{
  echo
  echo "== 2b. the tree of 832a3636, the commit the review read: it must fail, on exactly CMP-03's four and item 150's"
  python3 -I "$here/renumbered-references.py" "$scratch/tree-832a3636" | sed "s#$scratch/##"; echo "exit: ${PIPESTATUS[0]}"
  echo
  echo "== 2c. this tree with CMP-03's four references put back: it must fail, on those four alone"
  python3 -I "$here/renumbered-references.py" "$scratch/tree-cmp03" | sed "s#$scratch/##"; echo "exit: ${PIPESTATUS[0]}"
} >> "$log" 2>&1
wrong() {  # the WRONG lines of one part of the log, as file:line 'reference'
  sed -n "/^== $1/,/^== $2/p" "$log" | grep -E '^WRONG ' | sed -E "s/^WRONG +([^ ]+) ('[^']*').*/\1 \2/" | tr '\n' ' ' \
    | sed 's/ $//'
}
got_b="$(wrong 2b 2c)"
got_c="$(sed -n '/^== 2c/,$p' "$log" | grep -E '^WRONG ' | sed -E "s/^WRONG +([^ ]+) ('[^']*').*/\1 \2/" | tr '\n' ' ' \
         | sed 's/ $//')"
exp_b="Docs/Stage0/M0-gate.md:799: 'integration log 36 and 29' Docs/Stage0/M0-gate.md:870: 'item 146' Docs/Stage0/M0-gate.md:890: 'items 104-110' Docs/Stage0/M0-gate.md:890: 'section 28' Docs/Stage0/M0-gate.md:890: 'items 111-115'"
{
  echo
  echo "control 2b, found:    $got_b"
  echo "control 2b, expected: $exp_b"
  echo "control 2c, found:    $got_c"
} >> "$log"
n_c="$(echo "$got_c" | grep -o "'" | wc -l | tr -d ' ')"
if [[ "$got_b" == "$exp_b" && "$n_c" == 8 && "$got_c" == *"'item 146'"* && "$got_c" == *"'items 104-110'"* \
      && "$got_c" == *"'section 28'"* && "$got_c" == *"'items 111-115'"* ]]; then
  echo "result: pass (this tree passes; 2b fails on the five; 2c on the four)" >> "$log"
  echo "renumbered-references.log: pass (this tree passes; 2b fails on the five; 2c on the four)"
else
  echo "result: FAIL" >> "$log"; echo "renumbered-references.log: FAIL"; status=1
fi
footer "$log" "$status"
run renumbered-references-new.log 1 python3 -I "$here/renumbered-references.py" "$root" --list-new

# 3
run completeness-checks.log 1 python3 -I "$here/completeness-checks.py"
live=(CLAUDE.md README.md Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/ADRs Docs/Stage0/device-checklists
      Docs/Stage0/evidence/M0-RecordsUpdate)
mkdir -p "$scratch/tree-7f7eae88"
git archive 7f7eae88 -- "${live[@]}" $(git ls-tree --name-only 7f7eae88 Docs/Stage0/ | grep '\.md$') \
  | tar -x -C "$scratch/tree-7f7eae88"
log="$out/completeness-sweep-control.log"
header "$log" "$here/completeness-checks.py --sweep, on the tree of 7f7eae88, the commit this fix started from"
python3 -I "$here/completeness-checks.py" --sweep "$scratch/tree-7f7eae88" | sed "s#$scratch/##" >> "$log" 2>&1
s=${PIPESTATUS[0]}
got="$(grep -E '^OPEN ' "$log" | awk '{print $2}' | sed 's/:$//' | tr '\n' ' ' | sed 's/ $//')"
expected="Docs/ADRs/0004-epub-reader-adapter.md:32 Docs/ADRs/0014-dependency-lock-and-license-inventory.md:149 Docs/ADRs/0015-threat-model.md:3 Docs/ADRs/0015-threat-model.md:202 Docs/ADRs/0015-threat-model.md:302 Docs/ADRs/README.md:31 Docs/Stage0/M0-gate.md:279 Docs/Stage0/M0-gate.md:310 Docs/Stage0/M0-gate.md:463 Docs/Stage0/M0-gate.md:494 Docs/Stage0/M0-gate.md:501 Docs/Stage0/M0-gate.md:871 Docs/Stage0/M0-gate.md:872 Docs/Stage0/M0-gate.md:873 Docs/Stage0/README.md:5 Docs/Stage0/README.md:36"
{ echo; echo "open paragraphs found:    $got"; echo "open paragraphs expected: $expected"; } >> "$log"
footer "$log" "$s"
echo "completeness-sweep-control.log: exit $s (1 expected, finding exactly the 16 open paragraphs this fix gave later notes)"
[[ $s == 1 && "$got" == "$expected" ]] || status=1

# 4
run retired-branch-texts.log 1 python3 -I "$fix1/retired-branch-texts.py" "$root"

# 5
run owner-records-intact.log 1 python3 -I "$ru/owner-records-intact.py"
run step-0.8-paths.log 1 "$ru/step-08-paths.sh"
run ci-contracts.log 1 Scripts/ci.sh contracts
run 12-dependency-lock.log 1 Scripts/ci.d/12-dependency-lock.sh
run 13-hard-rules.log 1 Scripts/ci.d/13-hard-rules.sh
run runbook-content-check.log 1 "$devicea/instructions/commands/runbook-content-check.sh"
run runbook-coverage.log 1 python3 -I Docs/Stage0/evidence/M0-Integration/final-fix/commands/runbook-coverage.py "$root"
run correction-texts.log 1 "$ru/correction-texts-compare.sh"

# 6
run check-amendments.log 1 python3 -I "$fix1/check-amendments.py" "$root"
run mutation-checks.log 1 python3 -I "$fix1/mutation-checks.py"
[[ -z "$(git status --porcelain -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md)" ]] \
  || { echo "PROBLEM: the mutations left the plan or the amendments changed"; status=1; }
expect_fail check-amendments-records-update.log "^FAIL draft 0.8 as revised on 24 October 2026: the product owner's decision on device A" 1 \
  python3 -I "$ru/check-amendments.py" "$root"
expect_fail check-amendments-accuracy.log "^FAIL draft 0.8 as revised on 24 October 2026: the product owner's decision on device A" 1 \
  python3 -I "$devicea/fix-1/accuracy/commands/check-amendments.py" "$root"

# 7
run check-records.log 1 python3 -I "$here/check-records.py" "$root"
expect_fail check-records-records-update.log "^FAIL the ADR index: its status column dated 24 October 2026" 1 \
  python3 -I "$ru/check-records.py" "$root"
header "$out/check-records-devicea.log" "python3 -I $devicea/commands/check-records.py $root"
python3 -I "$devicea/commands/check-records.py" "$root" >> "$out/check-records-devicea.log" 2>&1
s=$?; footer "$out/check-records-devicea.log" $s; n="$(grep -c '^FAIL ' "$out/check-records-devicea.log")"
echo "check-records-devicea.log: exit $s (1 expected, failing exactly its checks of the ADR index and of section 28, by design); FAIL lines: $n"
[[ $s == 1 && $n == 2 ]] && grep -q '^FAIL the ADR index: its status column dated 24 October 2026' "$out/check-records-devicea.log" \
  && grep -q '^FAIL the integration log: section 28 and its parts' "$out/check-records-devicea.log" || status=1

# 8
run recheck-hon-ep.log 0 python3 -I "$exitprep/fix-2/round-2/commands/recheck-hon-ep.py" "$root"
run decisions-branch.log 0 python3 -I "$exitprep/fix-2/round-2/commands/decisions-branch.py"
run recheck-own.log 0 python3 -I "$devicea/fix-1/owner/commands/recheck-own.py" "$root"
"$exitprep/fix-2/round-2/commands/gate-checks.sh" "$out/gate-checks-exit-prep.log" > "$out/gate-checks-exit-prep.console.log" 2>&1
echo "gate-checks-exit-prep.log: exit $? (recorded as it reports)"
"$devicea/fix-1/owner/commands/gate-checks.sh" "$out/gate-checks-devicea.log" > "$out/gate-checks-devicea.console.log" 2>&1
echo "gate-checks-devicea.log: exit $? (recorded as it reports)"

# 9
run gate-refresh-check.log 1 python3 -I "$ru/gate-refresh-check.py" "$root"

echo "tree after the checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths (the logs); end $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
