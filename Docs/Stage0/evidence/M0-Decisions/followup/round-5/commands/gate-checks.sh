#!/bin/bash
# Checks behind the follow-up's fourth fix (23 October 2026 on the build Mac's clock; integration log section 24) on
# branch m0-decisions: the owner-readability findings OWN5-01 to OWN5-06 of the fifth agent review, which read the
# follow-up's three fixes at 660c2b3a, answered on top of that commit. Run on the commit that adds the fix's other logs,
# with no uncommitted file. The successor of
# Docs/Stage0/evidence/M0-Decisions/followup/round-4/commands/gate-checks.sh, the current equivalent of
# Docs/Stage0/evidence/M0-Decisions/assembly/commands/gate-checks.sh:
#   Docs/Stage0/evidence/M0-Decisions/followup/round-5/commands/gate-checks.sh <log>
# 1. What the fix changed since the commit it starts from (660c2b3a): every file, by kind; nothing outside Docs/ (no
#    code, script, contract, fixture or workflow; README.md and CLAUDE.md unchanged: the change of CLAUDE.md is the
#    product owner's, HON-11); the plan, the license inventory and its draft unchanged; the folders the rule for
#    repeating a session names, changed since 4c73da57: the code folders only in the lock harness and the G0.5
#    recovery drop-in, and Docs/Stage0/device-checklists in all eight checklists, none of them since 660c2b3a (the
#    claims of M0-gate.md item 2, OWN5-04, which the third fix's check read for the code folders only); the committed
#    logs of resolve-locks.sh and linkage.sh unchanged since 4c73da57 and no run under Xcode 27.1 recorded; and,
#    read-only, the repository's local main against the origin/main it last fetched (no fetch: the runbook's 0.3
#    quotes these).
# 2. The Git LFS state of the tree and of the repository configuration (read-only), and the LFS files of HEAD against
#    those of 4c73da57 (main after pull request #5): the runbook's D-8 says m0-decisions adds none.
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the gate report rows, ADR status lines
#    and CI logs it cites (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py); then, on copies with three
#    planted wrong statuses, that the checker reports exactly the rows resting on them (22, 42, 66, 71, 78, 92).
# 4. The documents' own consistency checks: the follow-up's fix's amendments checker, unchanged, since this fix changed
#    neither the plan nor the license inventory (followup/round-2/commands/check-amendments.py, 0 failures required; its
#    mutations and controls run in that round's run-checks.sh, whose log for this fix is followup/round-5/
#    check-amendments.log), the assembly's runbook content check (unchanged; its controls and limits run in
#    runbook-content-check.sh beside it, log followup/round-5/runbook-content-check.log), the step coverage check, the
#    runbook's correction-text check on 4c73da57, 660c2b3a and HEAD (from 4c73da57 to HEAD exactly the nine texts of the
#    corrections the decisions round applied change from found to missing, and from 660c2b3a to HEAD nothing changes),
#    the earlier rounds' rechecks: the follow-up's recheck of the second review's twelve answered findings
#    (followup/commands/recheck-review2.py, still passing), the follow-up's fix's recheck of FID4-01 to FID4-08
#    (followup/round-2/commands/recheck-review4.py), which must report exactly what it reported on 660c2b3a (FID4-02 and
#    FID4-06, on the three anchors the second fix reworded), the second fix's recheck of HON4-01 to HON4-06
#    (followup/round-3/commands/recheck-hon4.py, still passing: this fix kept every text it asserts, moving those it
#    asserted in the runbook's run 1 to 0.4 and Session 10), the third fix's recheck of OWN4-01 to OWN4-09
#    (followup/round-4/commands/recheck-own4.py), which must report exactly OWN4-01, on the one text it asserts that this
#    fix changed (run 12's estimate of Session 10, about 6-6.5 days until this fix added the Section 23.1 sign-offs),
#    and the third fix's check of its moved history notes (followup/round-4/commands/moved-notes.py, still passing);
#    then this round's recheck of OWN5-01 to OWN5-06 and of the product owner's answers of 23 October 2026
#    (followup/round-5/commands/recheck-own5.py), passing on HEAD and, as its control, reporting all six findings on the
#    third fix's tree (git archive 660c2b3a), the check of the texts this fix moved
#    (followup/round-5/commands/moved-notes.py), passing on HEAD and, as its control, failing on 660c2b3a's tree, and
#    the check of the findings' cited lines and word counts (followup/round-5/commands/finding-lines.py), all holding
#    at 660c2b3a and, as its control, not at 19489f10.
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first).
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G0.5 AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log. Exit status 1 if any part fails.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up, as the third fix's
log="$1"
cd "$root" || exit 1
source Scripts/lib/env.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
evidence="Docs/Stage0/evidence/M0-Integration"
decisions="Docs/Stage0/evidence/M0-Decisions"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca
start=660c2b3a89a15a86de0352e2f66709a322a40a5e
earlier=19489f10033e6b79d7509d9041c76850b0006703
mkdir -p .build/scratch
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. Files changed since $start, the follow-up's third fix, which the review read and from which this fix starts"
} > "$log" 2>&1
changed="$(git diff --name-only "$start" HEAD)"
stray="$(printf '%s\n' "$changed" | grep -v -E '^Docs/' | grep . || true)"
{
  echo "-- 1a. $(printf '%s\n' "$changed" | grep -c .) files: $(printf '%s\n' "$changed" | grep -c '^Docs/Stage0/evidence/M0-Decisions/followup/round-5/') of them this fix's evidence, $(printf '%s\n' "$changed" | grep -c '^Docs/') under Docs/ in all"
  echo "   the documents changed, outside this fix's evidence:"
  printf '%s\n' "$changed" | grep -v '^Docs/Stage0/evidence/M0-Decisions/followup/round-5/' | sed 's/^/   /'
  if [[ -n "$stray" ]]; then echo "   PROBLEM: changed outside Docs/: $stray"; else echo "   nothing changed outside Docs/ (README.md included)"; fi
  echo "   the plan and the license inventory since $start: $(git diff --name-only "$start" HEAD -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Licenses/inventory.json Docs/Licenses/acknowledgements-draft.md | tr '\n' ' ' | sed 's/ $//' | grep . || echo "unchanged, so the follow-up's fix's amendments checker and the acknowledgements draft apply as they were")"
} >> "$log"
[[ -n "$stray" ]] && status=1
plan_changed="$(git diff --name-only "$start" HEAD -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Licenses/inventory.json Docs/Licenses/acknowledgements-draft.md)"
[[ -n "$plan_changed" ]] && { echo "   PROBLEM: the plan or the license inventory changed" >> "$log"; status=1; }
claude_changed="$(git diff --name-only "$start" HEAD -- CLAUDE.md)"
{
  echo "-- 1b. CLAUDE.md since $start: $( [[ -z "$claude_changed" ]] && echo "unchanged (its change is the product owner's, on m0-decisions: M0-gate.md Section 1, item 1, step 2; review finding HON-11); its milestone paragraph still reads: $(grep -o -E 'are combined on `m0-integrate`' CLAUDE.md | head -n 1)" || echo "PROBLEM, changed")"
} >> "$log"
[[ -n "$claude_changed" ]] && status=1
since_code="$(git diff --name-only "$start" HEAD -- Spikes Scripts Contracts Fixtures Apps Packages .github)"
{
  echo "-- 1c. code, scripts, contracts, fixtures and the workflow changed since ${start:0:8}: $( [[ -z "$since_code" ]] && echo "none, so every run the follow-up, its fixes and their predecessors recorded on this code stands" || echo "PROBLEM: $since_code")"
} >> "$log"
[[ -n "$since_code" ]] && status=1
rule_code="$(git diff --name-only "$base" HEAD -- Apps Packages Spikes Fixtures Scripts Contracts)"
rule_other="$(printf '%s\n' "$rule_code" | grep -v -E '^Spikes/G05-Recovery/LockHarness/|^Scripts/ci\.d/71-g05-recovery\.sh$' | grep . || true)"
lists_changed="$(git diff --name-only "$base" HEAD -- Docs/Stage0/device-checklists)"
lists_all="$(git ls-files Docs/Stage0/device-checklists | grep -E '\.md$')"
lists_since_start="$(git diff --name-only "$start" HEAD -- Docs/Stage0/device-checklists)"
{
  echo "-- 1d. the folders the rule for repeating a session names (Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists), changed since ${base:0:8} (pull request #5)"
  echo "   the code folders (Apps Packages Spikes Fixtures Scripts Contracts): $(printf '%s\n' "$rule_code" | grep -c .) files"
  printf '%s\n' "$rule_code" | sed -E 's#^(Spikes/G05-Recovery/LockHarness)/.*#\1/...#' | sort | uniq -c | sed 's/^/   /'
  if [[ -z "$rule_other" ]]; then echo "   only the lock harness and the G0.5 recovery drop-in, as M0-gate.md item 2 says"; else echo "   PROBLEM: also $rule_other"; fi
  echo "   Docs/Stage0/device-checklists: $(printf '%s\n' "$lists_changed" | grep -c .) of the $(printf '%s\n' "$lists_all" | grep -c .) checklists changed (git diff --stat):"
  git diff --stat "$base" HEAD -- Docs/Stage0/device-checklists | sed 's/^/   /'
  if [[ "$lists_changed" == "$lists_all" ]]; then echo "   all eight, as M0-gate.md item 2 now says (until this fix it named the code alone: OWN5-04)"; else echo "   PROBLEM: not every checklist, as item 2 says"; fi
  echo "   checklists changed since ${start:0:8}, by this fix: $( [[ -z "$lists_since_start" ]] && echo "none" || echo "PROBLEM: $lists_since_start")"
} >> "$log"
[[ -n "$rule_other" || "$lists_changed" != "$lists_all" || -n "$lists_since_start" ]] && status=1
dep_logs="$(git diff --name-only "$base" HEAD -- Docs/Stage0/evidence/M0-dependencies/linkage.log Docs/Stage0/evidence/M0-dependencies/resolve-locks.log)"
{
  echo "-- 1e. the committed logs of resolve-locks.sh and linkage.sh since ${base:0:8}: $( [[ -z "$dep_logs" ]] && echo "unchanged" || echo "PROBLEM, changed: $dep_logs")"
  echo "   linkage.log's Xcode line: $(grep -m 1 -o -E 'Xcode [0-9.]+ Build version [0-9A-Za-z]+' Docs/Stage0/evidence/M0-dependencies/linkage.log)"
  echo "   a run under Xcode 27.1 (Docs/Stage0/evidence/M0-dependencies/xcode-27.1/): $( [[ -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && echo "PROBLEM, present: the records call it pending" || echo "absent, as the records say (the product owner's run, pending)")"
} >> "$log"
[[ -n "$dep_logs" || -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && status=1
{
  echo "-- 1f. the repository's local main and the origin/main it last fetched (read-only; nothing is fetched):"
  echo "   main: $(git rev-parse main); origin/main: $(git rev-parse origin/main)"
  echo "   commits on origin/main that main lacks: $(git rev-list --count main..origin/main); on main that origin/main lacks: $(git rev-list --count origin/main..main)"
  echo "   folders in main's tree: $(git ls-tree -d --name-only main | tr '\n' ' ')"
  echo "   Spikes/G05-Recovery/LockHarness/project.yml at main: $(git cat-file -e main:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent); at origin/main: $(git cat-file -e origin/main:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent); at HEAD: $(git cat-file -e HEAD:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent)"
} >> "$log"
{
  echo
  echo "== 2. Git LFS state"
  echo ".gitattributes patterns (non-comment lines):"
  grep -v -E '^\s*(#|$)' .gitattributes
  echo "git config --show-origin --get-regexp 'filter\\.lfs|lfs\\.':"
  git config --show-origin --get-regexp 'filter\.lfs|lfs\.' || echo "(no match)"
  git lfs version
  echo "files tracked by LFS (git lfs ls-files): $(git lfs ls-files | wc -l | tr -d ' '); of them still pointer files in the working tree: $(git lfs ls-files | awk '$2 == "-"' | wc -l | tr -d ' ')"
} >> "$log" 2>&1
git lfs ls-files -l "$base" | sort > .build/scratch/round5-lfs-base.txt
git lfs ls-files -l HEAD | sort > .build/scratch/round5-lfs-head.txt
if cmp -s .build/scratch/round5-lfs-base.txt .build/scratch/round5-lfs-head.txt; then
  echo "LFS files (object and path, git lfs ls-files -l) at HEAD and at $base: identical, $(wc -l < .build/scratch/round5-lfs-head.txt | tr -d ' ') each: m0-decisions adds no LFS object" >> "$log"
else
  echo "LFS files at HEAD and at $base differ:" >> "$log"
  diff .build/scratch/round5-lfs-base.txt .build/scratch/round5-lfs-head.txt | head -n 20 >> "$log"
  status=1
fi
rm -f .build/scratch/round5-lfs-base.txt .build/scratch/round5-lfs-head.txt
{
  echo
  echo "== 3. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log"
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
neg=.build/scratch/gate-round5-negative
rm -rf "$neg"
mkdir -p "$neg/$evidence/final-fix/ci-logs" "$neg/$evidence/final-fix-2/ci-logs" "$neg/$evidence/repin-27.1/round-2" "$neg/Docs/ADRs" "$neg/Docs/Stage0"
cp Docs/Stage0/*.md "$neg/Docs/Stage0/"
cp Docs/ADRs/*.md "$neg/Docs/ADRs/"
cp "$evidence/ci-full-clean-run-assembled.log" "$evidence/ci-documents-final.log" "$evidence/ci-full-clean-run-final.log" "$neg/$evidence/"
cp "$evidence/final-fix/ci-full-clean-run-final.log" "$neg/$evidence/final-fix/"
for round in final-fix final-fix-2; do
  cp "$evidence/$round/ci-logs/10-contracts.log" "$evidence/$round/ci-logs/12-dependency-lock.log" "$neg/$evidence/$round/ci-logs/"
done
cp "$evidence/repin-27.1/12-dependency-lock.log" "$evidence/repin-27.1/12-dependency-lock-before.log" "$neg/$evidence/repin-27.1/"
cp "$evidence/repin-27.1/round-2/12-dependency-lock.log" "$neg/$evidence/repin-27.1/round-2/"
sed -i '' -E '/^\| 22 \| /s/\| failed \|/| passed-simulator |/' "$neg/Docs/Stage0/M0-gate.md"
sed -i '' -E '/^\| 33 \| /s/budget failed for/budget missed for/' "$neg/Docs/Stage0/G04-Audio.md"
sed -i '' -E 's/^- \*\*Status:\*\* Proposed\. Security review/- **Status:** Accepted. Security review/' "$neg/Docs/ADRs/0015-threat-model.md"
neg_status=0
python3 -I "$commands/gate-refresh-check.py" "$neg" > "$neg.out" 2>&1 || neg_status=$?
disagree="$(grep -E -- '-> DISAGREES$' "$neg.out" | sed -E 's/^row ([0-9]+):.*/\1/' | sort -n -u | tr '\n' ' ' | sed 's/ $//')"
{
  echo
  echo "-- 3b. Negative control on copies with three planted wrong statuses: checker exit $neg_status; rows reported as disagreeing: $disagree"
} >> "$log"
if [[ "$neg_status" == 1 && "$disagree" == "22 42 66 71 78 92" ]]; then
  echo "   as required (22, 42, 66, 71, 78, 92)" >> "$log"
else
  echo "   NOT as required (22, 42, 66, 71, 78, 92)" >> "$log"; status=1
fi
rm -rf "$neg" "$neg.out"
{
  echo
  echo "== 4. The documents' own consistency checks"
  echo "-- the follow-up's fix's amendments checker, unchanged ($decisions/followup/round-2/commands/check-amendments.py; its mutations and controls on this fix's last documents commit: $decisions/followup/round-5/check-amendments.log)"
} >> "$log"
amend_status=0
python3 -I "$decisions/followup/round-2/commands/check-amendments.py" > .build/scratch/gate-round5-amend.out 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:|PO-12|on 23 October 2026' .build/scratch/gate-round5-amend.out
  echo "exit: $amend_status"
  echo "-- the runbook's content check ($decisions/assembly/commands/runbook-content-check.py, unchanged; its controls and limits: $decisions/followup/round-5/runbook-content-check.log)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$decisions/assembly/commands/runbook-content-check.py" "$root" > .build/scratch/gate-round5-content.out 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|NOT_CARRIED:|in its gate.s checklist|source fragments|RUNBOOK_OWN:|^result:' .build/scratch/gate-round5-content.out
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > .build/scratch/gate-round5-coverage.out 2>&1 || cov_status=$?
{
  tail -n 3 .build/scratch/gate-round5-coverage.out
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base, on $start and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
trees="$root/.build/scratch/gate-round5-trees"
rm -rf "$trees"; mkdir -p "$trees/base" "$trees/start" "$trees/head"
git archive "$base" | tar -x -C "$trees/base"
git archive "$start" | tar -x -C "$trees/start"
git archive HEAD | tar -x -C "$trees/head"
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$trees/check.py"
for side in base start head; do
  (cd "$trees/$side" && python3 -I "$trees/check.py" > "$trees/$side.out" 2>&1); echo "$?" > "$trees/$side.status"
done
{
  echo "   $base: exit $(cat "$trees/base.status"); $(tail -n 1 "$trees/base.out")"
  echo "   $start: exit $(cat "$trees/start.status"); $(tail -n 1 "$trees/start.out")"
  echo "   HEAD: exit $(cat "$trees/head.status"); $(tail -n 1 "$trees/head.out")"
  echo "   the lines that differ from $base to HEAD (the first line, a timestamp, left out):"
  diff <(tail -n +2 "$trees/base.out") <(tail -n +2 "$trees/head.out") | grep -E '^[<>] ' | sed 's/^/   /'
} >> "$log"
changed_cct="$(diff <(tail -n +2 "$trees/base.out") <(tail -n +2 "$trees/head.out") | grep -E '^> C[0-9]+ ' | sed -E 's/^> (C[0-9]+) +([A-Z]+|ok) +x([0-9]+) ([^:]+):.*/\1 \2 \3 \4/' | sort)"
expected="$(printf '%s\n' \
  "C28 MISSING 0 Docs/Stage0/device-checklists/G06-Design.md" \
  "C47 MISSING 0 Docs/Stage0/G02-Transfer.md" \
  "C49 MISSING 0 Docs/ADRs/0011-ai-providers-context-and-privacy.md" \
  "C49 MISSING 0 Docs/ADRs/0011-ai-providers-context-and-privacy.md" \
  "C49 MISSING 0 Docs/Stage0/G05-AI.md" \
  "C50 MISSING 0 Docs/ADRs/0013-design-language.md" \
  "C56 MISSING 0 Docs/ADRs/0010-intake-handoff-and-wired-bundles.md" \
  "C56 MISSING 0 Docs/Stage0/G03-Intake.md" \
  "C56 MISSING 0 Docs/Stage0/device-checklists/G03-Intake.md" | sort)"
fix_diff="$(diff <(tail -n +2 "$trees/start.out") <(tail -n +2 "$trees/head.out") | grep -E '^[<>] ' || true)"
if [[ "$changed_cct" == "$expected" && "$(cat "$trees/base.status")" == 1 && "$(cat "$trees/head.status")" == 1 ]] \
   && [[ "$(diff <(tail -n +2 "$trees/base.out") <(tail -n +2 "$trees/head.out") | grep -c -E '^< ')" == 10 ]] \
   && [[ -z "$fix_diff" ]]; then
  echo "   as required: from $base to HEAD the nine texts of the corrections the decisions round applied (C28, C47's report row, C49 three times, C50, C56 three times), found before and missing after, and the summary line, nothing else; from $start to HEAD no line differs (C51's words kept)" >> "$log"
else
  echo "   NOT as required: expected exactly the nine applied corrections' texts to change from $base, and nothing from $start:" >> "$log"
  printf '%s\n' "$fix_diff" | sed 's/^/   /' >> "$log"
  status=1
fi
recheck_status=0
python3 -I "$decisions/followup/commands/recheck-review2.py" "$root" > .build/scratch/gate-round5-recheck2.out 2>&1 || recheck_status=$?
{
  echo "-- the follow-up's recheck of the second review's twelve answered findings and HON-11 ($decisions/followup/commands/recheck-review2.py), on HEAD"
  sed 's/^/   /' .build/scratch/gate-round5-recheck2.out
  echo "exit: $recheck_status"
} >> "$log"
(( recheck_status != 0 )) && status=1
recheck4_status=0
python3 -I "$decisions/followup/round-2/commands/recheck-review4.py" "$root" > .build/scratch/gate-round5-recheck4.out 2>&1 || recheck4_status=$?
fid_problems="$(grep '^PROBLEM ' .build/scratch/gate-round5-recheck4.out | sed -E 's/^PROBLEM +(FID4-[0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
fid_details="$(grep '^PROBLEM ' .build/scratch/gate-round5-recheck4.out | sed -E 's/^PROBLEM +(FID4-[0-9]+):[^(]*\((.*)\)$/\1: \2/')"
fid_expected="FID4-02: ADR-0002's Branches lacks: reaches \`main\` before the M0 exit only through \`m0-decisions\`
FID4-06: M0-gate.md item 4 lacks: under D-6, ADR-0014 is approved once Session 10's review of it is recorded, with your security sign-off; the runbook's exit review lacks: so ADR-0014's approval, once Session 10's review of it and your security sign-off are recorded (D-6)"
{
  echo "-- the follow-up's fix's recheck of FID4-01 to FID4-08 ($decisions/followup/round-2/commands/recheck-review4.py), on HEAD: it must report exactly what it reported on $start, FID4-02 and FID4-06, each lacking exactly the anchors the second fix reworded (integration log 22.2; the second fix's recheck asserts both answers in their new wording, below), the rest still answered"
  sed 's/^/   /' .build/scratch/gate-round5-recheck4.out
  echo "exit: $recheck4_status; reported: $fid_problems"
} >> "$log"
if [[ "$recheck4_status" == 1 && "$fid_problems" == "FID4-02 FID4-06" && "$fid_details" == "$fid_expected" ]]; then
  echo "   as required: exactly FID4-02 and FID4-06, on exactly those anchors" >> "$log"
else
  echo "   NOT as required: exactly FID4-02 and FID4-06, on exactly the three anchors the second fix reworded" >> "$log"; status=1
fi
hon_status=0
python3 -I "$decisions/followup/round-3/commands/recheck-hon4.py" "$root" > .build/scratch/gate-round5-hon.out 2>&1 || hon_status=$?
{
  echo "-- the second fix's recheck of HON4-01 to HON4-06 ($decisions/followup/round-3/commands/recheck-hon4.py), on HEAD: it must still pass, since this fix kept every text it asserts (those it asserts in the runbook's run 1, now a pointer to item 1, moved to 0.4 and Session 10's paragraph on R4-01 and R4-02)"
  sed 's/^/   /' .build/scratch/gate-round5-hon.out
  echo "exit: $hon_status"
} >> "$log"
(( hon_status != 0 )) && status=1
own4_status=0
python3 -I "$decisions/followup/round-4/commands/recheck-own4.py" "$root" > .build/scratch/gate-round5-own4.out 2>&1 || own4_status=$?
own4_problems="$(grep '^PROBLEM ' .build/scratch/gate-round5-own4.out | sed -E 's/^PROBLEM +(OWN4-[0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
own4_details="$(grep '^PROBLEM ' .build/scratch/gate-round5-own4.out | sed -E 's/.* \(([^()]*)\)$/\1/')"
own4_expected="the runbook's run 12 lacks: about 6-6.5 days of your time"
{
  echo "-- the third fix's recheck of OWN4-01 to OWN4-09 ($decisions/followup/round-4/commands/recheck-own4.py), on HEAD: it must report exactly OWN4-01, lacking exactly run 12's old estimate of Session 10 (about 6-6.5 days), which this fix raised with the Section 23.1 sign-offs it added (this round's recheck asserts OWN4-01's answer with the new estimate, below), the rest still answered"
  sed 's/^/   /' .build/scratch/gate-round5-own4.out
  echo "exit: $own4_status; reported: $own4_problems"
} >> "$log"
if [[ "$own4_status" == 1 && "$own4_problems" == "OWN4-01" && "$own4_details" == "$own4_expected" ]]; then
  echo "   as required: exactly OWN4-01, on exactly that text" >> "$log"
else
  echo "   NOT as required: exactly OWN4-01, on run 12's old estimate alone" >> "$log"; status=1
fi
moved4_status=0
python3 -I "$decisions/followup/round-4/commands/moved-notes.py" "$root" > .build/scratch/gate-round5-moved4.out 2>&1 || moved4_status=$?
{
  echo "-- the third fix's moved history notes ($decisions/followup/round-4/commands/moved-notes.py), on HEAD: still moved whole"
  tail -n 1 .build/scratch/gate-round5-moved4.out | sed 's/^/   /'
  echo "exit: $moved4_status"
} >> "$log"
(( moved4_status != 0 )) && status=1
own_status=0
python3 -I "$decisions/followup/round-5/commands/recheck-own5.py" "$root" > .build/scratch/gate-round5-own5.out 2>&1 || own_status=$?
{
  echo "-- this round's recheck of OWN5-01 to OWN5-06 and of the product owner's answers of 23 October 2026 ($decisions/followup/round-5/commands/recheck-own5.py; its own log: $decisions/followup/round-5/recheck-own5.log), on HEAD"
  sed 's/^/   /' .build/scratch/gate-round5-own5.out
  echo "exit: $own_status"
} >> "$log"
(( own_status != 0 )) && status=1
control_status=0
python3 -I "$decisions/followup/round-5/commands/recheck-own5.py" "$trees/start" > .build/scratch/gate-round5-own5-start.out 2>&1 || control_status=$?
control_problems="$(grep -c '^PROBLEM  OWN5-' .build/scratch/gate-round5-own5-start.out)"
{
  echo "-- its control on $start (the third fix, which the review read and where this fix starts): each finding must be reported"
  grep -E '^(PROBLEM|answered|recorded|open|changed|result)' .build/scratch/gate-round5-own5-start.out | cut -c1-160 | sed 's/^/   /'
  echo "exit: $control_status; findings reported: $control_problems"
} >> "$log"
if [[ "$control_status" == 1 && "$control_problems" == 6 ]]; then
  echo "   as required: all six reported on $start" >> "$log"
else
  echo "   NOT as required: all six must be reported on $start" >> "$log"; status=1
fi
moved_status=0
python3 -I "$decisions/followup/round-5/commands/moved-notes.py" "$root" > .build/scratch/gate-round5-moved.out 2>&1 || moved_status=$?
moved_control=0
python3 -I "$decisions/followup/round-5/commands/moved-notes.py" "$root" "$trees/start" > .build/scratch/gate-round5-moved-control.out 2>&1 || moved_control=$?
{
  echo "-- the texts this fix moved ($decisions/followup/round-5/commands/moved-notes.py; its own log: $decisions/followup/round-5/moved-notes.log), on HEAD"
  sed 's/^/   /' .build/scratch/gate-round5-moved.out
  echo "exit: $moved_status"
  echo "-- its control, on the tree of $start, where the texts are still in their lines and their new places do not exist: it must fail"
  tail -n 1 .build/scratch/gate-round5-moved-control.out | sed 's/^/   /'
  echo "exit: $moved_control"
} >> "$log"
(( moved_status != 0 )) && status=1
if [[ "$moved_control" == 1 ]]; then
  echo "   as required: the control fails" >> "$log"
else
  echo "   NOT as required: the control must fail" >> "$log"; status=1
fi
lines_status=0
python3 -I "$decisions/followup/round-5/commands/finding-lines.py" "$root" "$start" > .build/scratch/gate-round5-lines.out 2>&1 || lines_status=$?
lines_control=0
python3 -I "$decisions/followup/round-5/commands/finding-lines.py" "$root" "$earlier" > .build/scratch/gate-round5-lines-control.out 2>&1 || lines_control=$?
{
  echo "-- the findings' cited lines and word counts ($decisions/followup/round-5/commands/finding-lines.py; its own log: $decisions/followup/round-5/finding-lines.log), at $start"
  tail -n 1 .build/scratch/gate-round5-lines.out | sed 's/^/   /'
  echo "exit: $lines_status"
  echo "-- its control, at $earlier (the follow-up, which the fourth review read): the lines must not all hold their text"
  tail -n 1 .build/scratch/gate-round5-lines-control.out | sed 's/^/   /'
  echo "exit: $lines_control"
} >> "$log"
(( lines_status != 0 )) && status=1
if [[ "$lines_control" == 1 ]]; then
  echo "   as required: the control fails, so the check reads the lines it names" >> "$log"
else
  echo "   NOT as required: the control must fail" >> "$log"; status=1
fi
rm -rf "$trees"
{
  echo
  echo "== 5. Scripts/ci.sh contracts dependency-lock hard-rules (every drop-in must pass)"
} >> "$log"
ci_status=0
Scripts/ci.sh contracts dependency-lock hard-rules >> "$log" 2>&1 || ci_status=$?
{
  echo "ci.sh exit: $ci_status"
  echo "summary lines from the drop-ins' own logs (.build/ci-logs/):"
  for name in 00-git-lfs 10-contracts 11-capture-anchor-contracts 12-dependency-lock 13-hard-rules; do
    echo "-- $name (last 4 lines)"
    tail -n 4 ".build/ci-logs/$name.log"
  done
  echo "-- the audit's result line:"
  grep -E '^result:' .build/ci-logs/hard-rules/audit-repository.log || echo "(none)"
  echo "-- FAIL lines in 12-dependency-lock's log:"
  grep -E '^FAIL ' .build/ci-logs/12-dependency-lock.log || echo "(none)"
  echo "-- its toolchain lines, and its count of the committed and registered locks (the lock harness's among them):"
  grep -E '^ok    toolchain:' .build/ci-logs/12-dependency-lock.log || echo "(none)"
  grep -E '^ok    locks:' .build/ci-logs/12-dependency-lock.log || echo "(none)"
} >> "$log" 2>&1
(( ci_status != 0 )) && { echo "part 5: a drop-in failed (above)" >> "$log"; status=1; }
{
  echo
  echo "== 6. Leftover G0.5 temporary directories (read-only count; G05-AI R7-04)"
  tmp="$(getconf DARWIN_USER_TEMP_DIR)"
  echo "g05-* directories in the user's temporary folder: $(find "$tmp" -maxdepth 1 -name 'g05-*' -type d 2>/dev/null | wc -l | tr -d ' ')"
  echo "g05-tests-* directories there: $(find "$tmp" -maxdepth 1 -name 'g05-tests-*' -type d 2>/dev/null | wc -l | tr -d ' ')"
  echo
  echo "exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log" 2>&1
exit $status
