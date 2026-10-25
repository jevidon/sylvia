#!/usr/bin/env bash
# Runs the checks the records of the device-A change feed (24 October 2026; integration log section 28), on branch
# m0-sessions-records, and prints a header naming the environment. The successor of
# Docs/Stage0/evidence/M0-Decisions/followup/round-2/commands/run-checks.sh for the plan amendments' checks:
#   1. this update's amendments checker (check-amendments.py beside this file): every check must pass;
#   2. its 66 mutations (mutation-checks.py beside this file): each must make the checker fail its guarding check;
#   3. control: the follow-up's fix's checker must fail on exactly three checks, the anchors of 22 and 23 October 2026
#      this update replaced: the revision date, D-1's anchors of 22 October 2026 in 19.1 and 21.1 (10c), and the entry's
#      last items (10i);
#   4. this update's check of the records the amendments' checker does not read (check-records.py beside this file: the
#      ADRs and their index, the gate reports, the integration log): every check must pass; as its control, on the tree
#      of the commit this update starts from it must fail every check but the one on the G0.6 rows' statuses;
#   5. the earlier rounds' rechecks of the records (the follow-up's and its four fixes', the drop-in record's and its two
#      fixes'), on this tree and on the tree of the commit this update starts from: each must report exactly what it
#      reports there, except two, each on exactly one text, the ADR index's status column, now dated 24 October 2026:
#      the follow-up's fix's recheck (its FID4-04, and its result line) and the second fix's (its HON4-06, and its result
#      line), whose new text check-records.py requires; the two drop-in fixes' rechecks count the Markdown files they
#      sweep, which this update adds to, so those counts are left out of the comparison; and each one's HON-11 line
#      (CLAUDE.md's milestone paragraph, which 5aec2518 and 6cede84a changed) is printed as it reports it on this tree;
#   6. the device runbook's content check (Docs/Stage0/evidence/M0-Decisions/assembly/commands/runbook-content-check.py,
#      the assembly's, unchanged): it must pass, so the fragments it reads in the plan, ADR-0009, ADR-0010 and the G0.2
#      report still hold (the runbook and the checklists are not changed on this branch);
#   7. the correction-text check (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py), on this tree and on
#      the start commit's: no line may differ, so every text a correction quotes in these records is kept;
#   8. Scripts/ci.sh contracts.
# Usage, from the repository root, on a clean tree whose HEAD is the commit under test:
#   Docs/Stage0/evidence/M0-DeviceA/commands/run-checks.sh <commit under test> [<start commit>] > <log> 2>&1
set -uo pipefail
here=Docs/Stage0/evidence/M0-DeviceA/commands
decisions=Docs/Stage0/evidence/M0-Decisions
previous=$decisions/followup/round-2/commands
commit="${1:?usage: run-checks.sh <commit under test> [<start commit>]}"
start="${2:-6cede84a6f6ac610976b233d875e26dd89419dbd}"
root="$(pwd)"
echo "# The device-A change of 24 October 2026: the checks its records feed (plan draft 0.8 as revised that day)"
echo "command: $here/run-checks.sh $commit $start"
echo "commit under test: $commit; the commit this update starts from: $start (m0-sessions)"
head="$(git rev-parse HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"
echo "HEAD: $head; uncommitted paths: $dirty"
if [[ "$(git rev-parse "$commit")" != "$head" || "$dirty" != "0" ]]; then
  echo "refused: run on a clean tree whose HEAD is the commit under test"
  exit 2
fi
git merge-base --is-ancestor "$start" HEAD && echo "the start commit is an ancestor of HEAD"
echo "date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m); $(python3 --version 2>&1)"
echo "load: $(uptime)"
echo "environment: host only; no simulator or device is used by these checks"
echo "files changed since the start commit, by kind:"
git diff --name-only "$start" HEAD | sed -E 's#^(Docs/Stage0/evidence/M0-DeviceA)/.*#\1/ (this update'"'"'s evidence)#' | sort | uniq -c | sed 's/^/  /'
echo
status=0

echo "== 1. $here/check-amendments.py"
python3 -I "$here/check-amendments.py"
s=$?
echo "exit status: $s"
(( s == 0 )) || status=1
echo

echo "== 2. $here/mutation-checks.py (each mutation must make the checker fail its guarding check)"
python3 -I "$here/mutation-checks.py"
s=$?
echo "exit status: $s"
echo "tree after the mutation checks: $(git status --porcelain | wc -l | tr -d ' ') uncommitted paths"
(( s == 0 )) || status=1
echo

echo "== 3. control: the follow-up's fix's checker, $previous/check-amendments.py"
echo "   It must fail on exactly three checks, on the anchors this update replaced: the revision date of 23 October 2026,"
echo "   D-1's anchors of 22 October 2026 in 19.1 and 21.1 (its 10c: the iPhone 11 as a second A13 phone, every budget"
echo "   stricter on the A13 phones, 21.1's device A an iPhone 11 Pro), and its 10i, which required the item correcting"
echo "   the dated item of 23 October 2026 to be the entry's last, where the item of 24 October 2026 now follows it."
prev_out="$(python3 -I "$previous/check-amendments.py" 2>&1)"
prev_status=$?
printf '%s\n' "$prev_out" | grep -E '^FAIL |^summary:'
echo "exit status: $prev_status"
printf '%s\n' "$prev_out" | python3 -I -c '
import sys
fails = [line[5:] for line in sys.stdin.read().splitlines() if line.startswith("FAIL ")]
anchor = "new anchor phrases are present in the plan (41): **Revised:** 23 October 2026"
d1 = ("draft 0.8: the five decisions that are not the recommendation (D-1, PO-13, PO-23, PO-33, PO-39) are applied where "
      "the plan states them, and before Appendix D only Section 19.1 names iPhone 12-class hardware: D-1 (19.1): the "
      "iPhone 11 is a second A13 phone; D-1 (19.1): every budget of Section 19.2 measured on them is stricter to meet, "
      "while no budget value changes; D-1 (21.1): on the baseline iPhone (device A, an iPhone 11 Pro; Section 19.1) and "
      "an iPad")
last = ("draft 0.8 as revised on 23 October 2026: Appendix D'"'"'s draft 0.8 entry ends with the dated item that records the "
        "answers of 23 October 2026 and the item that corrects it: the dated item lacks: *Recorded on 23 October 2026, "
        "within draft 0.8:; ")
sys.exit(0 if len(fails) == 3 and fails[0] == anchor and fails[1] == d1 and fails[2].startswith(last) else 1)
'
exact=$?
if [[ $prev_status -eq 1 && $exact -eq 0 ]]; then
  echo "control 3: the follow-up's fix's checker fails on exactly those three checks, as it must"
else
  echo "PROBLEM: the follow-up's fix's checker's failures are not exactly the three expected"
  status=1
fi
echo

base="$root/.build/scratch/devicea-checks-base"
rm -rf "$base"; mkdir -p "$base"
git archive "$start" | tar -x -C "$base"

echo "== 4. this update's check of the ADRs, the index, the gate reports and the integration log ($here/check-records.py)"
python3 -I "$here/check-records.py" "$root"
s=$?
echo "exit status: $s"
(( s == 0 )) || status=1
echo "   control: on the tree of $start it must fail every check but the one on the G0.6 rows' statuses (17 of 18)"
records_control="$(python3 -I "$here/check-records.py" "$base" 2>&1)"
printf '%s\n' "$records_control" | grep -E '^(PASS|summary)' | sed 's/^/   /'
if [[ "$(printf '%s\n' "$records_control" | grep -c '^FAIL ')" == 17 ]] \
   && [[ "$(printf '%s\n' "$records_control" | grep '^PASS ')" == "PASS G0.6 report: the three rows' statuses unchanged" ]]; then
  echo "   control as required: 17 failed checks, and only the statuses check passing"
else
  echo "   PROBLEM: the control did not fail as required"
  status=1
fi
echo

echo "== 5. the earlier rounds' rechecks of the records, on HEAD and on the tree of $start"
rechecks=(followup/commands/recheck-review2.py followup/round-2/commands/recheck-review4.py
  followup/round-3/commands/recheck-hon4.py followup/round-4/commands/recheck-own4.py
  followup/round-5/commands/recheck-own5.py unlocked-record/commands/recheck-unlocked.py
  unlocked-record/round-2/commands/recheck-unl.py unlocked-record/round-3/commands/recheck-unl2.py)
outdir="$root/.build/scratch/devicea-checks-rechecks"
rm -rf "$outdir"; mkdir -p "$outdir"
for script in "${rechecks[@]}"; do
  name="$(basename "$script" .py)"
  python3 -I "$decisions/$script" "$root" > "$outdir/$name.head" 2>&1; hs=$?
  python3 -I "$decisions/$script" "$base" > "$outdir/$name.start" 2>&1; ss=$?
  echo "-- $decisions/$script: exit $hs on HEAD, $ss on $start"
  # The drop-in fixes' rechecks count the Markdown files they sweep; this update adds some, so the counts are left out.
  for side in head start; do
    sed -E -e 's/sweep 1 over [0-9]+ Markdown files/sweep 1 over N Markdown files/' \
      -e 's/the sweep: [0-9]+ Markdown files of Docs\/Stage0 and Docs\/ADRs/the sweep: N Markdown files of Docs\/Stage0 and Docs\/ADRs/' \
      "$outdir/$name.$side" > "$outdir/$name.$side.n"
  done
  diff "$outdir/$name.start.n" "$outdir/$name.head.n" | grep -E '^[<>] ' | sed 's/^/   /'
done
echo "   HON-11 (CLAUDE.md's milestone paragraph), as each recheck that reads it reports it on HEAD:"
for script in "${rechecks[@]}"; do
  name="$(basename "$script" .py)"
  grep -h 'HON-11' "$outdir/$name.head" | sed "s/^/   $name: /"
done
python3 -I - "$outdir" <<'PY'
import sys
from pathlib import Path
out = Path(sys.argv[1])
names = ["recheck-review2", "recheck-review4", "recheck-hon4", "recheck-own4", "recheck-own5", "recheck-unlocked",
         "recheck-unl", "recheck-unl2"]
column = "| ADR | Title | Status (23 October 2026) | Owner during Stage 0 |"
problems = []
for name in names:
    start = (out / f"{name}.start.n").read_text().splitlines()
    head = (out / f"{name}.head.n").read_text().splitlines()
    changed = [(a, b) for a, b in zip(start, head) if a != b]
    if len(start) != len(head):
        problems.append(f"{name}: {len(start)} lines on the start commit, {len(head)} on HEAD")
        continue
    if name == "recheck-review4":
        ok = (len(changed) == 2 and changed[0][0].startswith("answered FID4-04:")
              and changed[0][1].startswith("PROBLEM  FID4-04:") and changed[0][1].endswith(f"(the ADR index lacks: {column})")
              and changed[1] == ("result: FAIL (2 of the eight not answered)", "result: FAIL (3 of the eight not answered)"))
    elif name == "recheck-hon4":
        ok = (len(changed) == 2 and changed[0][0].startswith("answered HON4-06:")
              and changed[0][1].startswith("PROBLEM  HON4-06:") and changed[0][1].endswith(f"(the ADR index lacks: {column})")
              and changed[1] == ("result: pass (0 of the six not answered)", "result: FAIL (1 of the six not answered)"))
    else:
        ok = not changed
    if not ok:
        problems.append(f"{name}: " + "; ".join(f"{a[:60]} -> {b[:60]}" for a, b in changed))
if problems:
    print("PROBLEM: the earlier rechecks do not report exactly as expected: " + " | ".join(problems))
    sys.exit(1)
print("as required: six rechecks report exactly what they report on the start commit; the follow-up's fix's recheck "
      "now also reports FID4-04 and the second fix's HON4-06, each on exactly the ADR index's status column, dated 24 "
      "October 2026 since this update")
PY
(( $? == 0 )) || status=1
echo

echo "== 6. the device runbook's content check ($decisions/assembly/commands/runbook-content-check.py, unchanged)"
content_out="$(python3 -I "$decisions/assembly/commands/runbook-content-check.py" "$root" 2>&1)"
content_status=$?
printf '%s\n' "$content_out" | grep -E 'PROBLEM|source fragments|RUNBOOK_OWN:|^summary|markers' | head -20
echo "exit status: $content_status"
(( content_status == 0 )) || status=1
echo

echo "== 7. the correction-text check on $start and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py)"
headtree="$root/.build/scratch/devicea-checks-head"
rm -rf "$headtree"; mkdir -p "$headtree"
git archive HEAD | tar -x -C "$headtree"
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$root/.build/scratch/devicea-check-correction-texts.py"
(cd "$base" && python3 -I "$root/.build/scratch/devicea-check-correction-texts.py" > "$outdir/cct.start" 2>&1); cs=$?
(cd "$headtree" && python3 -I "$root/.build/scratch/devicea-check-correction-texts.py" > "$outdir/cct.head" 2>&1); ch=$?
echo "   $start: exit $cs; $(tail -n 1 "$outdir/cct.start")"
echo "   HEAD: exit $ch; $(tail -n 1 "$outdir/cct.head")"
if diff <(tail -n +2 "$outdir/cct.start") <(tail -n +2 "$outdir/cct.head") > /dev/null && [[ $cs -eq $ch ]]; then
  echo "   as required: no line differs (the first line, a timestamp, left out)"
else
  echo "   PROBLEM: lines differ:"
  diff <(tail -n +2 "$outdir/cct.start") <(tail -n +2 "$outdir/cct.head") | sed 's/^/   /'
  status=1
fi
echo

echo "== 8. Scripts/ci.sh contracts"
Scripts/ci.sh contracts
s=$?
echo "exit status: $s"
(( s == 0 )) || status=1
echo
echo "overall: $([[ $status -eq 0 ]] && echo 'every check as required' || echo 'PROBLEM')"
exit $status
