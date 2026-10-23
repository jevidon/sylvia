#!/bin/bash
# Checks behind the second fix of the record of G0.5 recovery's whole drop-in run with the screen unlocked (23 October
# 2026; integration log section 27) on branch m0-decisions: the findings UNL2-01 to UNL2-03 of the review of the record's
# fix answered on top of 26530d49, that fix's last commit. Run on the commit that adds the second fix's other logs, with
# no uncommitted file. The successor of Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-2/commands/gate-checks.sh,
# the current equivalent of Docs/Stage0/evidence/M0-Decisions/assembly/commands/gate-checks.sh:
#   Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-3/commands/gate-checks.sh <log>
# 1. What changed: the run's evidence commit 35543102 adds the run's folder and nothing else; since 26530d49 every file
#    by kind, nothing outside Docs/ (no code, script, contract, fixture or workflow; README.md and CLAUDE.md unchanged:
#    the change of CLAUDE.md is the product owner's, HON-11); the plan, the license inventory and its draft unchanged, so
#    the follow-up's fix's amendments checker applies; the commands and logs of the record and of its fix unchanged (only
#    their two READMEs, which carry dated notes); 9cdb0a02, the run's commit, an ancestor of HEAD, and the code, scripts,
#    contracts, fixtures and the workflow unchanged since it, so the run stands for HEAD's code; the folders the rule for
#    repeating a session names, changed since 4c73da57: the code folders only in the lock harness and the G0.5 recovery
#    drop-in, and Docs/Stage0/device-checklists in all eight checklists, none since 9cdb0a02; the committed logs of
#    resolve-locks.sh and linkage.sh unchanged since 4c73da57 and no run under Xcode 27.1 recorded; and, read-only, the
#    repository's local main against the origin/main it last fetched, and the commit origin/m0-decisions names (no
#    fetch).
# 2. The Git LFS state of the tree and of the repository configuration (read-only), and the LFS files of HEAD against
#    those of 4c73da57 (main after pull request #5): the runbook's D-8 says m0-decisions adds none.
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the gate report rows, ADR status lines
#    and CI logs it cites (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py); then, on copies with three
#    planted wrong statuses, that the checker reports exactly the rows resting on them (22, 42, 66, 71, 78, 92).
# 4. The documents' own consistency checks: the follow-up's fix's amendments checker, unchanged, since this second fix
#    changed neither the plan nor the license inventory (followup/round-2/commands/check-amendments.py, 0 failures
#    required; its mutations and controls run in that round's run-checks.sh, whose log for this second fix is
#    round-3/check-amendments.log beside this folder), the assembly's runbook content check (unchanged; its controls and
#    limits run in runbook-content-check.sh beside it, log round-3/runbook-content-check.log), the step coverage check,
#    the runbook's correction-text check on 4c73da57, 26530d49 and HEAD (from 4c73da57 to HEAD exactly the nine texts of
#    the corrections the decisions round applied change from found to missing, and from 26530d49 to HEAD nothing
#    changes); the earlier rounds' rechecks, each as it reported on the record's fix: the follow-up's recheck of the
#    second review's twelve answered findings (followup/commands/recheck-review2.py, passing), the follow-up's fix's
#    recheck of FID4-01 to FID4-08 (followup/round-2/commands/recheck-review4.py, exactly FID4-02 and FID4-06, on the
#    three anchors the second fix reworded), the second fix's recheck of HON4-01 to HON4-06
#    (followup/round-3/commands/recheck-hon4.py, passing), the third fix's recheck of OWN4-01 to OWN4-09
#    (followup/round-4/commands/recheck-own4.py, exactly OWN4-01, on run 12's old estimate) and its moved notes
#    (followup/round-4/commands/moved-notes.py, passing), and the fourth fix's recheck of OWN5-01 to OWN5-06 and of the
#    owner's answers (followup/round-5/commands/recheck-own5.py, passing, the State line within its 200 words) and its
#    moved texts (followup/round-5/commands/moved-notes.py, passing); the record's two checks: the run's facts
#    (unlocked-record/commands/check-run.py, passing, as it ran) and its recheck of the records
#    (unlocked-record/commands/recheck-unlocked.py, reporting exactly the ADR index's entry for ADR-0015 and the Stage 0
#    README's line on the gate summary, as on the fix, and integration log 24.5's note, which UNL2-02 changed); the
#    fix's three checks: the run's facts (round-2/commands/check-run.py), passing on the run's folder and, as its
#    control, failing on the assembly's run of the same wrapper with the screen locked (assembly/dropin-clean); its
#    recheck (round-2/commands/recheck-unl.py), reporting exactly UNL-02 and the review status, on the texts this second
#    fix reworded for the fix's review (the State line, the Stage 0 README and the runbook's Who wrote it), UNL-01,
#    UNL-03, UNL-04 and UNL-05 still answered; and its check of its review's cited lines (round-2/commands/
#    finding-lines.py), still holding at 91c3b46a; then this second fix's checks: its recheck (round-3/commands/
#    recheck-unl2.py), passing on HEAD and, as its control, reporting all three findings and the review status on the
#    tree of 26530d49, where its first sweep finds with no note exactly the two rows UNL2-01 names (integration log
#    lines 979 and 1003), its second sweep finds unlisted exactly their two sentences, and the clause on what remains for
#    the owner is missing after exactly the two notes UNL2-02 names (integration log line 1389, the fourth fix's README
#    line 18); and the review's cited lines (round-3/commands/finding-lines.py), holding at 26530d49 and, as its control,
#    not at 91c3b46a.
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first).
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G0.5 AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log. Exit status 1 if any part fails.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, round-3, unlocked-record, M0-Decisions, evidence, Stage0, Docs
log="$1"
cd "$root" || exit 1
source Scripts/lib/env.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
evidence="Docs/Stage0/evidence/M0-Integration"
decisions="Docs/Stage0/evidence/M0-Decisions"
record="$decisions/unlocked-record"
fix="$record/round-2"
here="$record/round-3"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e
evidence_commit=35543102e4c0f550c7bdd59ca013c788f048e8e3
start=26530d4933c070c2c154a9116ef6f7fdd0415363
mkdir -p .build/scratch
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. What changed: the run's evidence commit ${evidence_commit:0:8}, and this second fix since the fix's last commit ${start:0:8}"
} > "$log" 2>&1
evidence_files="$(git diff --name-only "$run" "$evidence_commit")"
evidence_other="$(printf '%s\n' "$evidence_files" | grep -v '^Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1/' | grep . || true)"
{
  echo "-- 1a. ${evidence_commit:0:8} (parent ${run:0:8}, the run's commit): $(printf '%s\n' "$evidence_files" | grep -c .) files, $(printf '%s\n' "$evidence_files" | grep -c '^Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1/') of them in Docs/Stage0/evidence/M0-Decisions/assembly/unlocked-run-1/; its parent is ${run:0:8}: $( [[ "$(git rev-parse "$evidence_commit^")" == "$run" ]] && echo yes || echo NO); ${start:0:8}, the fix's last commit, descends from it: $(git merge-base --is-ancestor "$evidence_commit" "$start" && echo yes || echo NO); HEAD descends from ${start:0:8}: $(git merge-base --is-ancestor "$start" HEAD && echo yes || echo NO)"
  if [[ -z "$evidence_other" && "$(git rev-parse "$evidence_commit^")" == "$run" ]]; then echo "   the run's folder and nothing else"; else echo "   PROBLEM: also $evidence_other"; fi
} >> "$log"
[[ -n "$evidence_other" || "$(git rev-parse "$evidence_commit^")" != "$run" ]] && status=1
git merge-base --is-ancestor "$start" HEAD || status=1
changed="$(git diff --name-only "$start" HEAD)"
stray="$(printf '%s\n' "$changed" | grep -v -E '^Docs/' | grep . || true)"
{
  echo "-- 1b. since ${start:0:8}: $(printf '%s\n' "$changed" | grep -c .) files: $(printf '%s\n' "$changed" | grep -c "^$here/") of them this second fix's evidence, $(printf '%s\n' "$changed" | grep -c '^Docs/') under Docs/ in all"
  echo "   the documents changed, outside this second fix's evidence:"
  printf '%s\n' "$changed" | grep -v "^$here/" | sed 's/^/   /'
  if [[ -n "$stray" ]]; then echo "   PROBLEM: changed outside Docs/: $stray"; else echo "   nothing changed outside Docs/ (README.md included)"; fi
  echo "   the plan and the license inventory since ${start:0:8}: $(git diff --name-only "$start" HEAD -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Licenses/inventory.json Docs/Licenses/acknowledgements-draft.md | tr '\n' ' ' | sed 's/ $//' | grep . || echo "unchanged, so the follow-up's fix's amendments checker and the acknowledgements draft apply as they were")"
  echo "   the commands and logs of the record and of its fix (Docs/Stage0/evidence/M0-Decisions/unlocked-record/, outside round-3/) since ${start:0:8}: $(git diff --name-only "$start" HEAD -- "$record" | grep -v "^$here/" | grep -v -E "^$record/(round-2/)?README\.md$" | tr '\n' ' ' | sed 's/ $//' | grep . || echo "unchanged but for their two READMEs' dated notes")"
} >> "$log"
[[ -n "$stray" ]] && status=1
record_changed="$(git diff --name-only "$start" HEAD -- "$record" | grep -v "^$here/" | grep -v -E "^$record/(round-2/)?README\.md$" | grep . || true)"
[[ -n "$record_changed" ]] && { echo "   PROBLEM: the commands or logs of the record or of its fix changed" >> "$log"; status=1; }
plan_changed="$(git diff --name-only "$start" HEAD -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Licenses/inventory.json Docs/Licenses/acknowledgements-draft.md)"
[[ -n "$plan_changed" ]] && { echo "   PROBLEM: the plan or the license inventory changed" >> "$log"; status=1; }
claude_changed="$(git diff --name-only "$start" HEAD -- CLAUDE.md)"
{
  echo "-- 1c. CLAUDE.md since ${start:0:8}: $( [[ -z "$claude_changed" ]] && echo "unchanged (its change is the product owner's, on m0-decisions: M0-gate.md Section 1, item 1, step 2; review finding HON-11); its milestone paragraph still reads: $(grep -o -E 'are combined on `m0-integrate`' CLAUDE.md | head -n 1)" || echo "PROBLEM, changed")"
} >> "$log"
[[ -n "$claude_changed" ]] && status=1
ancestor=no; git merge-base --is-ancestor "$run" HEAD && ancestor=yes
since_run="$(git diff --name-only "$run" HEAD -- Spikes Scripts Contracts Fixtures Apps Packages .github)"
{
  echo "-- 1d. ${run:0:8}, the commit the drop-in ran on, is an ancestor of HEAD: $ancestor"
  echo "   code, scripts, contracts, fixtures and the workflow changed since ${run:0:8}: $( [[ -z "$since_run" ]] && echo "none, so the run stands for HEAD's code (what the drop-in builds, copies or runs is as it ran)" || echo "PROBLEM: $since_run")"
} >> "$log"
[[ "$ancestor" != yes || -n "$since_run" ]] && status=1
rule_code="$(git diff --name-only "$base" HEAD -- Apps Packages Spikes Fixtures Scripts Contracts)"
rule_other="$(printf '%s\n' "$rule_code" | grep -v -E '^Spikes/G05-Recovery/LockHarness/|^Scripts/ci\.d/71-g05-recovery\.sh$' | grep . || true)"
lists_changed="$(git diff --name-only "$base" HEAD -- Docs/Stage0/device-checklists)"
lists_all="$(git ls-files Docs/Stage0/device-checklists | grep -E '\.md$')"
lists_since_run="$(git diff --name-only "$run" HEAD -- Docs/Stage0/device-checklists)"
{
  echo "-- 1e. the folders the rule for repeating a session names (Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists), changed since ${base:0:8} (pull request #5)"
  echo "   the code folders (Apps Packages Spikes Fixtures Scripts Contracts): $(printf '%s\n' "$rule_code" | grep -c .) files"
  printf '%s\n' "$rule_code" | sed -E 's#^(Spikes/G05-Recovery/LockHarness)/.*#\1/...#' | sort | uniq -c | sed 's/^/   /'
  if [[ -z "$rule_other" ]]; then echo "   only the lock harness and the G0.5 recovery drop-in, as M0-gate.md item 2 says"; else echo "   PROBLEM: also $rule_other"; fi
  echo "   Docs/Stage0/device-checklists: $(printf '%s\n' "$lists_changed" | grep -c .) of the $(printf '%s\n' "$lists_all" | grep -c .) checklists changed (git diff --stat):"
  git diff --stat "$base" HEAD -- Docs/Stage0/device-checklists | sed 's/^/   /'
  if [[ "$lists_changed" == "$lists_all" ]]; then echo "   all eight, as M0-gate.md item 2 says"; else echo "   PROBLEM: not every checklist, as item 2 says"; fi
  echo "   checklists changed since ${run:0:8}: $( [[ -z "$lists_since_run" ]] && echo "none" || echo "PROBLEM: $lists_since_run")"
} >> "$log"
[[ -n "$rule_other" || "$lists_changed" != "$lists_all" || -n "$lists_since_run" ]] && status=1
dep_logs="$(git diff --name-only "$base" HEAD -- Docs/Stage0/evidence/M0-dependencies/linkage.log Docs/Stage0/evidence/M0-dependencies/resolve-locks.log)"
{
  echo "-- 1f. the committed logs of resolve-locks.sh and linkage.sh since ${base:0:8}: $( [[ -z "$dep_logs" ]] && echo "unchanged" || echo "PROBLEM, changed: $dep_logs")"
  echo "   linkage.log's Xcode line: $(grep -m 1 -o -E 'Xcode [0-9.]+ Build version [0-9A-Za-z]+' Docs/Stage0/evidence/M0-dependencies/linkage.log)"
  echo "   a run under Xcode 27.1 (Docs/Stage0/evidence/M0-dependencies/xcode-27.1/): $( [[ -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && echo "PROBLEM, present: the records call it pending" || echo "absent, as the records say (the product owner's run, pending)")"
} >> "$log"
[[ -n "$dep_logs" || -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && status=1
{
  echo "-- 1g. the repository's remote-tracking refs, read-only (nothing is fetched):"
  echo "   main: $(git rev-parse main); origin/main: $(git rev-parse origin/main)"
  echo "   commits on origin/main that main lacks: $(git rev-list --count main..origin/main); on main that origin/main lacks: $(git rev-list --count origin/main..main)"
  echo "   origin/m0-decisions: $(git rev-parse origin/m0-decisions) ($( [[ "$(git rev-parse origin/m0-decisions)" == "$run" ]] && echo "the run's commit" || echo "not the run's commit"))"
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
git lfs ls-files -l "$base" | sort > .build/scratch/unl3-lfs-base.txt
git lfs ls-files -l HEAD | sort > .build/scratch/unl3-lfs-head.txt
if cmp -s .build/scratch/unl3-lfs-base.txt .build/scratch/unl3-lfs-head.txt; then
  echo "LFS files (object and path, git lfs ls-files -l) at HEAD and at $base: identical, $(wc -l < .build/scratch/unl3-lfs-head.txt | tr -d ' ') each: m0-decisions adds no LFS object" >> "$log"
else
  echo "LFS files at HEAD and at $base differ:" >> "$log"
  diff .build/scratch/unl3-lfs-base.txt .build/scratch/unl3-lfs-head.txt | head -n 20 >> "$log"
  status=1
fi
rm -f .build/scratch/unl3-lfs-base.txt .build/scratch/unl3-lfs-head.txt
{
  echo
  echo "== 3. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log"
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
neg=.build/scratch/gate-unl3-negative
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
  echo "-- the follow-up's fix's amendments checker, unchanged ($decisions/followup/round-2/commands/check-amendments.py; its mutations and controls on this second fix's last documents commit: $here/check-amendments.log)"
} >> "$log"
amend_status=0
python3 -I "$decisions/followup/round-2/commands/check-amendments.py" > .build/scratch/gate-unl3-amend.out 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:|PO-12|on 23 October 2026' .build/scratch/gate-unl3-amend.out
  echo "exit: $amend_status"
  echo "-- the runbook's content check ($decisions/assembly/commands/runbook-content-check.py, unchanged; its controls and limits: $here/runbook-content-check.log)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$decisions/assembly/commands/runbook-content-check.py" "$root" > .build/scratch/gate-unl3-content.out 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|NOT_CARRIED:|in its gate.s checklist|source fragments|RUNBOOK_OWN:|^result:' .build/scratch/gate-unl3-content.out
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > .build/scratch/gate-unl3-coverage.out 2>&1 || cov_status=$?
{
  tail -n 3 .build/scratch/gate-unl3-coverage.out
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base, on $start and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
trees="$root/.build/scratch/gate-unl3-trees"
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
start_diff="$(diff <(tail -n +2 "$trees/start.out") <(tail -n +2 "$trees/head.out") | grep -E '^[<>] ' || true)"
if [[ "$changed_cct" == "$expected" && "$(cat "$trees/base.status")" == 1 && "$(cat "$trees/head.status")" == 1 ]] \
   && [[ "$(diff <(tail -n +2 "$trees/base.out") <(tail -n +2 "$trees/head.out") | grep -c -E '^< ')" == 10 ]] \
   && [[ -z "$start_diff" ]]; then
  echo "   as required: from $base to HEAD the nine texts of the corrections the decisions round applied (C28, C47's report row, C49 three times, C50, C56 three times), found before and missing after, and the summary line, nothing else; from $start to HEAD no line differs" >> "$log"
else
  echo "   NOT as required: expected exactly the nine applied corrections' texts to change from $base, and nothing from $start:" >> "$log"
  printf '%s\n' "$start_diff" | sed 's/^/   /' >> "$log"
  status=1
fi
recheck_status=0
python3 -I "$decisions/followup/commands/recheck-review2.py" "$root" > .build/scratch/gate-unl3-recheck2.out 2>&1 || recheck_status=$?
{
  echo "-- the follow-up's recheck of the second review's twelve answered findings and HON-11 ($decisions/followup/commands/recheck-review2.py), on HEAD: it must still pass"
  sed 's/^/   /' .build/scratch/gate-unl3-recheck2.out
  echo "exit: $recheck_status"
} >> "$log"
(( recheck_status != 0 )) && status=1
recheck4_status=0
python3 -I "$decisions/followup/round-2/commands/recheck-review4.py" "$root" > .build/scratch/gate-unl3-recheck4.out 2>&1 || recheck4_status=$?
fid_problems="$(grep '^PROBLEM ' .build/scratch/gate-unl3-recheck4.out | sed -E 's/^PROBLEM +(FID4-[0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
fid_details="$(grep '^PROBLEM ' .build/scratch/gate-unl3-recheck4.out | sed -E 's/^PROBLEM +(FID4-[0-9]+):[^(]*\((.*)\)$/\1: \2/')"
fid_expected="FID4-02: ADR-0002's Branches lacks: reaches \`main\` before the M0 exit only through \`m0-decisions\`
FID4-06: M0-gate.md item 4 lacks: under D-6, ADR-0014 is approved once Session 10's review of it is recorded, with your security sign-off; the runbook's exit review lacks: so ADR-0014's approval, once Session 10's review of it and your security sign-off are recorded (D-6)"
{
  echo "-- the follow-up's fix's recheck of FID4-01 to FID4-08 ($decisions/followup/round-2/commands/recheck-review4.py), on HEAD: it must report exactly what it reported on the record's fix, FID4-02 and FID4-06, each lacking exactly the anchors the second fix reworded (integration log 22.2), the rest still answered"
  sed 's/^/   /' .build/scratch/gate-unl3-recheck4.out
  echo "exit: $recheck4_status; reported: $fid_problems"
} >> "$log"
if [[ "$recheck4_status" == 1 && "$fid_problems" == "FID4-02 FID4-06" && "$fid_details" == "$fid_expected" ]]; then
  echo "   as required: exactly FID4-02 and FID4-06, on exactly those anchors" >> "$log"
else
  echo "   NOT as required: exactly FID4-02 and FID4-06, on exactly the three anchors the second fix reworded" >> "$log"; status=1
fi
hon_status=0
python3 -I "$decisions/followup/round-3/commands/recheck-hon4.py" "$root" > .build/scratch/gate-unl3-hon.out 2>&1 || hon_status=$?
{
  echo "-- the second fix's recheck of HON4-01 to HON4-06 ($decisions/followup/round-3/commands/recheck-hon4.py), on HEAD: it must still pass"
  sed 's/^/   /' .build/scratch/gate-unl3-hon.out
  echo "exit: $hon_status"
} >> "$log"
(( hon_status != 0 )) && status=1
own4_status=0
python3 -I "$decisions/followup/round-4/commands/recheck-own4.py" "$root" > .build/scratch/gate-unl3-own4.out 2>&1 || own4_status=$?
own4_problems="$(grep '^PROBLEM ' .build/scratch/gate-unl3-own4.out | sed -E 's/^PROBLEM +(OWN4-[0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
own4_details="$(grep '^PROBLEM ' .build/scratch/gate-unl3-own4.out | sed -E 's/.* \(([^()]*)\)$/\1/')"
own4_expected="the runbook's run 12 lacks: about 6-6.5 days of your time"
{
  echo "-- the third fix's recheck of OWN4-01 to OWN4-09 ($decisions/followup/round-4/commands/recheck-own4.py), on HEAD: it must report exactly what it reported on the record's fix, OWN4-01 on run 12's old estimate of Session 10, the rest still answered"
  sed 's/^/   /' .build/scratch/gate-unl3-own4.out
  echo "exit: $own4_status; reported: $own4_problems"
} >> "$log"
if [[ "$own4_status" == 1 && "$own4_problems" == "OWN4-01" && "$own4_details" == "$own4_expected" ]]; then
  echo "   as required: exactly OWN4-01, on exactly that text" >> "$log"
else
  echo "   NOT as required: exactly OWN4-01, on run 12's old estimate alone" >> "$log"; status=1
fi
moved4_status=0
python3 -I "$decisions/followup/round-4/commands/moved-notes.py" "$root" > .build/scratch/gate-unl3-moved4.out 2>&1 || moved4_status=$?
{
  echo "-- the third fix's moved history notes ($decisions/followup/round-4/commands/moved-notes.py), on HEAD: still moved whole"
  tail -n 1 .build/scratch/gate-unl3-moved4.out | sed 's/^/   /'
  echo "exit: $moved4_status"
} >> "$log"
(( moved4_status != 0 )) && status=1
own5_status=0
python3 -I "$decisions/followup/round-5/commands/recheck-own5.py" "$root" > .build/scratch/gate-unl3-own5.out 2>&1 || own5_status=$?
{
  echo "-- the fourth fix's recheck of OWN5-01 to OWN5-06 and of the product owner's answers of 23 October 2026 ($decisions/followup/round-5/commands/recheck-own5.py), on HEAD: it must still pass (among its texts, the State line within its 200 words, which this second fix reworded)"
  sed 's/^/   /' .build/scratch/gate-unl3-own5.out
  echo "exit: $own5_status"
} >> "$log"
(( own5_status != 0 )) && status=1
moved5_status=0
python3 -I "$decisions/followup/round-5/commands/moved-notes.py" "$root" > .build/scratch/gate-unl3-moved5.out 2>&1 || moved5_status=$?
{
  echo "-- the fourth fix's moved texts ($decisions/followup/round-5/commands/moved-notes.py), on HEAD: still in their new places"
  tail -n 1 .build/scratch/gate-unl3-moved5.out | sed 's/^/   /'
  echo "exit: $moved5_status"
} >> "$log"
(( moved5_status != 0 )) && status=1
oldrun_status=0
python3 -I "$record/commands/check-run.py" "$root" > .build/scratch/gate-unl3-oldrun.out 2>&1 || oldrun_status=$?
{
  echo "-- the record's check of the run's facts ($record/commands/check-run.py, as it ran; its log: $record/check-run.log), on the run's folder: it must still pass"
  tail -n 1 .build/scratch/gate-unl3-oldrun.out | sed 's/^/   /'
  echo "exit: $oldrun_status"
} >> "$log"
(( oldrun_status != 0 )) && status=1
oldrec_status=0
python3 -I "$record/commands/recheck-unlocked.py" "$root" > .build/scratch/gate-unl3-oldrec.out 2>&1 || oldrec_status=$?
oldrec_problems="$(grep '^PROBLEM ' .build/scratch/gate-unl3-oldrec.out | sed -E 's/^PROBLEM +//')"
oldrec_expected="the ADR index, ADR-0015 (lacks: records the whole drop-in's run with the screen unlocked on \`9cdb0a02\`, which passed (not reviewed))
the Stage 0 README (lacks: and with the run of G0.5 recovery's whole drop-in with the screen unlocked, section 25))
the integration log, section 25 and 24.5's note (lacks: *(Dated note, 23 October 2026: a waiter of the orchestrating session ran it after this fix, on \`9cdb0a02\`, the fix's last commit, with the screen unlocked, and it passed: section 25.)*)"
{
  echo "-- the record's recheck of the records ($record/commands/recheck-unlocked.py; its log: $record/recheck-unlocked.log), on HEAD: it must report exactly the two texts it reported on the record's fix, the ADR index's entry for ADR-0015 and the Stage 0 README's line on the gate summary, and integration log 24.5's note, which UNL2-02 asked to change, every other record as on the record"
  sed 's/^/   /' .build/scratch/gate-unl3-oldrec.out
  echo "exit: $oldrec_status"
} >> "$log"
if [[ "$oldrec_status" == 1 && "$oldrec_problems" == "$oldrec_expected" ]]; then
  echo "   as required: exactly those three" >> "$log"
else
  echo "   NOT as required: exactly the ADR index's entry, the Stage 0 README's line and 24.5's note" >> "$log"; status=1
fi
run_status=0
python3 -I "$fix/commands/check-run.py" "$root" > .build/scratch/gate-unl3-run.out 2>&1 || run_status=$?
run_control=0
python3 -I "$fix/commands/check-run.py" "$root" "$decisions/assembly/dropin-clean" > .build/scratch/gate-unl3-run-control.out 2>&1 || run_control=$?
{
  echo "-- the fix's check of the run's facts ($fix/commands/check-run.py; its log: $fix/check-run.log), on the run's folder: it must still pass"
  tail -n 1 .build/scratch/gate-unl3-run.out | sed 's/^/   /'
  echo "exit: $run_status"
  echo "-- its control, on the assembly's run of the same wrapper with the screen locked ($decisions/assembly/dropin-clean): it must fail"
  grep -E '^PROBLEM|^result' .build/scratch/gate-unl3-run-control.out | cut -c1-200 | sed 's/^/   /'
  echo "exit: $run_control"
} >> "$log"
(( run_status != 0 )) && status=1
if [[ "$run_control" == 1 ]] && grep -q '^PROBLEM the screen unlocked at the start (ioreg)' .build/scratch/gate-unl3-run-control.out \
   && grep -q "^PROBLEM the guard's line: row 10 evidence present" .build/scratch/gate-unl3-run-control.out; then
  echo "   as required: the control fails, naming the locked screen and the missing row-10 line" >> "$log"
else
  echo "   NOT as required: the control must fail on the locked screen and the missing row-10 line" >> "$log"; status=1
fi
unl_status=0
python3 -I "$fix/commands/recheck-unl.py" "$root" > .build/scratch/gate-unl3-unl.out 2>&1 || unl_status=$?
unl_problems="$(grep '^PROBLEM ' .build/scratch/gate-unl3-unl.out | sed -E 's/^PROBLEM +//')"
unl_expected="UNL-02: the State line (200 words) names the record of the drop-in run and its fix and the last two fixes as unreviewed; the Stage 0 README gives the review of the record and its fix; 25.2's row has its note (the State line lacks: the follow-up and its four fixes, the record of item 4's drop-in run and its fix, and this summary's own updates; the State line lacks: and the last two fixes, the follow-up's fourth and that record's, have not been reviewed; the Stage 0 README lacks: and a sixth agent review, of that record, raised five findings, one of them major, which a fix of the record answered the same day (section 26); that fix has not been reviewed either.; the Stage 0 README lacks: by the fix of the review of that run's record, section 26))
review: the record read by an agent review, at 91c3b46a, and its fix not reviewed, in the gate summary, the runbook, the integration log, the record's README and the ADR index (the runbook's Who wrote it lacks: the follow-up's fourth fix of 23 October 2026, and the fix of the review of the drop-in's record, have not been reviewed)"
{
  echo "-- the fix's recheck of UNL-01 to UNL-05 and of the record's review status ($fix/commands/recheck-unl.py; its log: $fix/recheck-unl.log), on HEAD: it must report exactly UNL-02 and the review status, on exactly the texts this second fix reworded for the fix's review (the State line, the Stage 0 README and the runbook's Who wrote it), UNL-01, UNL-03, UNL-04 and UNL-05 still answered"
  sed 's/^/   /' .build/scratch/gate-unl3-unl.out
  echo "exit: $unl_status"
} >> "$log"
if [[ "$unl_status" == 1 && "$unl_problems" == "$unl_expected" ]]; then
  echo "   as required: exactly those two, on exactly those texts" >> "$log"
else
  echo "   NOT as required: exactly UNL-02 and the review status, on the State line, the Stage 0 README and the runbook's Who wrote it" >> "$log"; status=1
fi
oldlines_status=0
python3 -I "$fix/commands/finding-lines.py" "$root" > .build/scratch/gate-unl3-oldlines.out 2>&1 || oldlines_status=$?
{
  echo "-- the fix's check of its review's cited lines ($fix/commands/finding-lines.py; its log: $fix/finding-lines.log), at 91c3b46a: it must still hold"
  tail -n 1 .build/scratch/gate-unl3-oldlines.out | sed 's/^/   /'
  echo "exit: $oldlines_status"
} >> "$log"
(( oldlines_status != 0 )) && status=1
unl2_status=0
python3 -I "$here/commands/recheck-unl2.py" "$root" > .build/scratch/gate-unl3-unl2.out 2>&1 || unl2_status=$?
unl2_control=0
python3 -I "$here/commands/recheck-unl2.py" "$trees/start" > .build/scratch/gate-unl3-unl2-control.out 2>&1 || unl2_control=$?
reported="$(grep -c -E '^PROBLEM +(UNL2-0[1-3]|review):' .build/scratch/gate-unl3-unl2-control.out)"
bare="$(grep -o 'no dated note naming `9cdb0a02` after: [^:]*:[0-9]*' .build/scratch/gate-unl3-unl2-control.out | sed -E 's/^no dated note naming `9cdb0a02` after: //' | sort)"
unlisted="$(grep -o 'with a word of status, not read: [^:]*:[0-9]*' .build/scratch/gate-unl3-unl2-control.out | sed -E 's/^with a word of status, not read: //' | sort)"
owner="$(grep -o 'does not say what remains: [^:]*:[0-9]*' .build/scratch/gate-unl3-unl2-control.out | sed -E 's/^does not say what remains: //' | sort)"
rows_expected="$(printf '%s\n' "Docs/Stage0/integration-log.md:1003" "Docs/Stage0/integration-log.md:979" | sort)"
owner_expected="$(printf '%s\n' "Docs/Stage0/evidence/M0-Decisions/followup/round-5/README.md:18" "Docs/Stage0/integration-log.md:1389" | sort)"
{
  echo "-- this second fix's recheck of UNL2-01 to UNL2-03 and of the fix's review status ($here/commands/recheck-unl2.py; its own log: $here/recheck-unl2.log), on HEAD"
  sed 's/^/   /' .build/scratch/gate-unl3-unl2.out
  echo "exit: $unl2_status"
  echo "-- its control on the tree of $start (the fix's last commit, where this second fix starts): all three findings and the review status must be reported; sweep 1 must find with no note exactly the two rows UNL2-01 names, sweep 2 must find unlisted exactly their two sentences, and the clause on what remains for the owner must be missing after exactly the two notes UNL2-02 names"
  cut -c1-300 .build/scratch/gate-unl3-unl2-control.out | sed 's/^/   /'
  echo "   sweep 1, texts with no note there:"
  printf '%s\n' "$bare" | sed 's/^/      /'
  echo "   sweep 2, sentences not listed there:"
  printf '%s\n' "$unlisted" | sed 's/^/      /'
  echo "   notes with no clause on what remains for the owner there:"
  printf '%s\n' "$owner" | sed 's/^/      /'
  echo "exit: $unl2_control; reported: $reported of 4"
} >> "$log"
(( unl2_status != 0 )) && status=1
if [[ "$unl2_control" == 1 && "$reported" == 4 && "$bare" == "$rows_expected" && "$unlisted" == "$rows_expected" && "$owner" == "$owner_expected" ]]; then
  echo "   as required: all four reported; exactly the two rows by both sweeps, and exactly the two notes" >> "$log"
else
  echo "   NOT as required: all four reported, exactly the two rows by both sweeps and exactly the two notes" >> "$log"; status=1
fi
lines_status=0
python3 -I "$here/commands/finding-lines.py" "$root" > .build/scratch/gate-unl3-lines.out 2>&1 || lines_status=$?
lines_control=0
python3 -I "$here/commands/finding-lines.py" "$root" 91c3b46a1e034563ca9a6df9a77d5c736d202303 > .build/scratch/gate-unl3-lines-control.out 2>&1 || lines_control=$?
{
  echo "-- this second fix's check of the review's cited lines and claims ($here/commands/finding-lines.py; its own log: $here/finding-lines.log), at $start, the fix's last commit"
  tail -n 1 .build/scratch/gate-unl3-lines.out | sed 's/^/   /'
  echo "exit: $lines_status"
  echo "-- its control at 91c3b46a, the record's last commit, before the fix: it must fail"
  tail -n 1 .build/scratch/gate-unl3-lines-control.out | sed 's/^/   /'
  echo "exit: $lines_control"
} >> "$log"
(( lines_status != 0 )) && status=1
if [[ "$lines_control" == 1 ]]; then
  echo "   as required: the control fails" >> "$log"
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
