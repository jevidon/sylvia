#!/bin/bash
# Checks behind the follow-up's fix (23 October 2026 on the build Mac's clock; integration log section 21) on branch
# m0-decisions: the fourth agent review's findings FID4-01 to FID4-08 on the follow-up answered. Run on the commit that
# adds the fix's other logs, with no uncommitted file. The successor of
# Docs/Stage0/evidence/M0-Decisions/followup/commands/gate-checks.sh, the current equivalent of
# Docs/Stage0/evidence/M0-Decisions/assembly/commands/gate-checks.sh:
#   Docs/Stage0/evidence/M0-Decisions/followup/round-2/commands/gate-checks.sh <log>
# 1. What the fix changed since the commit the review read (19489f10, the follow-up's last commit, whose line numbers
#    the relayed findings cite): every file, by kind; nothing outside Docs/ and README.md (no code, script, contract,
#    fixture or workflow, and CLAUDE.md unchanged: HON-11 is left for the product owner); and, read-only, the
#    repository's local main against the origin/main it last fetched (no fetch: the runbook's 0.3 quotes these).
# 2. The Git LFS state of the tree and of the repository configuration (read-only), and the LFS files of HEAD against
#    those of 4c73da57 (main after pull request #5): the runbook's D-8 says m0-decisions adds none.
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the gate report rows, ADR status lines
#    and CI logs it cites (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py); then, on copies with three
#    planted wrong statuses, that the checker reports exactly the rows resting on them (22, 42, 66, 71, 78, 92).
# 4. The documents' own consistency checks: this round's amendments checker (followup/round-2/commands/
#    check-amendments.py, 0 failures required; its mutations and controls run in run-checks.sh beside it, whose log is
#    followup/round-2/check-amendments.log), the assembly's runbook content check (unchanged; its controls and limits run
#    in runbook-content-check.sh beside it, log followup/round-2/runbook-content-check.log), the step coverage check, the
#    runbook's correction-text check on 4c73da57, 19489f10 and HEAD (from 4c73da57 to HEAD exactly the nine texts of the
#    corrections the decisions round applied change from found to missing, and from 19489f10 to HEAD nothing changes:
#    the fix applied no correction and kept the words of C51, which is not applied), the follow-up's recheck of the
#    second review's twelve answered findings (followup/commands/recheck-review2.py, still passing), and this round's
#    recheck of FID4-01 to FID4-08 (followup/round-2/commands/recheck-review4.py), passing on HEAD and, as its control,
#    reporting all eight on the follow-up's tree (git archive 19489f10).
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first).
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G0.5 AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log. Exit status 1 if any part fails.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
log="$1"
cd "$root" || exit 1
source Scripts/lib/env.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
evidence="Docs/Stage0/evidence/M0-Integration"
decisions="Docs/Stage0/evidence/M0-Decisions"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca
reviewed=19489f10033e6b79d7509d9041c76850b0006703
mkdir -p .build/scratch
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. Files changed since $reviewed, the commit the review read"
} > "$log" 2>&1
changed="$(git diff --name-only "$reviewed" HEAD)"
stray="$(printf '%s\n' "$changed" | grep -v -E '^(Docs/|README\.md$)' | grep . || true)"
{
  echo "-- 1a. $(printf '%s\n' "$changed" | grep -c .) files: $(printf '%s\n' "$changed" | grep -c '^Docs/Stage0/evidence/M0-Decisions/followup/round-2/') of them this fix's evidence, $(printf '%s\n' "$changed" | grep -c '^Docs/') under Docs/ in all, $(printf '%s\n' "$changed" | grep -c -E '^README\.md$') README.md"
  echo "   the documents changed, outside this fix's evidence:"
  printf '%s\n' "$changed" | grep -v '^Docs/Stage0/evidence/M0-Decisions/followup/round-2/' | sed 's/^/   /'
  if [[ -n "$stray" ]]; then echo "   PROBLEM: changed outside Docs/ and README.md: $stray"; else echo "   nothing changed outside Docs/ and README.md"; fi
} >> "$log"
[[ -n "$stray" ]] && status=1
claude_changed="$(git diff --name-only "$reviewed" HEAD -- CLAUDE.md)"
{
  echo "-- 1b. CLAUDE.md since $reviewed: $( [[ -z "$claude_changed" ]] && echo "unchanged (review finding HON-11 is left for the product owner, in M0-gate.md Section 1, item 1); its milestone paragraph still reads: $(grep -o -E 'are combined on `m0-integrate`' CLAUDE.md | head -n 1)" || echo "PROBLEM, changed")"
} >> "$log"
[[ -n "$claude_changed" ]] && status=1
since_code="$(git diff --name-only "$reviewed" HEAD -- Spikes Scripts Contracts Fixtures Apps Packages .github)"
{
  echo "-- 1c. code, scripts, contracts, fixtures and the workflow changed since ${reviewed:0:8}: $( [[ -z "$since_code" ]] && echo "none, so every run the follow-up and its predecessors recorded on this code stands" || echo "PROBLEM: $since_code")"
} >> "$log"
[[ -n "$since_code" ]] && status=1
{
  echo "-- 1d. the repository's local main and the origin/main it last fetched (read-only; nothing is fetched):"
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
git lfs ls-files -l "$base" | sort > .build/scratch/round2-lfs-base.txt
git lfs ls-files -l HEAD | sort > .build/scratch/round2-lfs-head.txt
if cmp -s .build/scratch/round2-lfs-base.txt .build/scratch/round2-lfs-head.txt; then
  echo "LFS files (object and path, git lfs ls-files -l) at HEAD and at $base: identical, $(wc -l < .build/scratch/round2-lfs-head.txt | tr -d ' ') each: m0-decisions adds no LFS object" >> "$log"
else
  echo "LFS files at HEAD and at $base differ:" >> "$log"
  diff .build/scratch/round2-lfs-base.txt .build/scratch/round2-lfs-head.txt | head -n 20 >> "$log"
  status=1
fi
rm -f .build/scratch/round2-lfs-base.txt .build/scratch/round2-lfs-head.txt
{
  echo
  echo "== 3. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log"
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
neg=.build/scratch/gate-round2-negative
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
  echo "-- this round's amendments checker ($decisions/followup/round-2/commands/check-amendments.py; its mutations and controls: $decisions/followup/round-2/check-amendments.log)"
} >> "$log"
amend_status=0
python3 -I "$decisions/followup/round-2/commands/check-amendments.py" > .build/scratch/gate-round2-amend.out 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:|PO-12|on 23 October 2026' .build/scratch/gate-round2-amend.out
  echo "exit: $amend_status"
  echo "-- the runbook's content check ($decisions/assembly/commands/runbook-content-check.py, unchanged; its controls and limits: $decisions/followup/round-2/runbook-content-check.log)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$decisions/assembly/commands/runbook-content-check.py" "$root" > .build/scratch/gate-round2-content.out 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|NOT_CARRIED:|in its gate.s checklist|source fragments|RUNBOOK_OWN:|^result:' .build/scratch/gate-round2-content.out
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > .build/scratch/gate-round2-coverage.out 2>&1 || cov_status=$?
{
  tail -n 3 .build/scratch/gate-round2-coverage.out
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base, on $reviewed and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
cct="$root/.build/scratch/gate-round2-cct"
rm -rf "$cct"; mkdir -p "$cct/base" "$cct/reviewed" "$cct/head"
git archive "$base" | tar -x -C "$cct/base"
git archive "$reviewed" | tar -x -C "$cct/reviewed"
git archive HEAD | tar -x -C "$cct/head"
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$cct/check.py"
for side in base reviewed head; do
  (cd "$cct/$side" && python3 -I "$cct/check.py" > "$cct/$side.out" 2>&1); echo "$?" > "$cct/$side.status"
done
{
  echo "   $base: exit $(cat "$cct/base.status"); $(tail -n 1 "$cct/base.out")"
  echo "   $reviewed: exit $(cat "$cct/reviewed.status"); $(tail -n 1 "$cct/reviewed.out")"
  echo "   HEAD: exit $(cat "$cct/head.status"); $(tail -n 1 "$cct/head.out")"
  echo "   the lines that differ from $base to HEAD (the first line, a timestamp, left out):"
  diff <(tail -n +2 "$cct/base.out") <(tail -n +2 "$cct/head.out") | grep -E '^[<>] ' | sed 's/^/   /'
} >> "$log"
changed_cct="$(diff <(tail -n +2 "$cct/base.out") <(tail -n +2 "$cct/head.out") | grep -E '^> C[0-9]+ ' | sed -E 's/^> (C[0-9]+) +([A-Z]+|ok) +x([0-9]+) ([^:]+):.*/\1 \2 \3 \4/' | sort)"
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
followup_diff="$(diff <(tail -n +2 "$cct/reviewed.out") <(tail -n +2 "$cct/head.out") | grep -E '^[<>] ' || true)"
if [[ "$changed_cct" == "$expected" && "$(cat "$cct/base.status")" == 1 && "$(cat "$cct/head.status")" == 1 ]] \
   && [[ "$(diff <(tail -n +2 "$cct/base.out") <(tail -n +2 "$cct/head.out") | grep -c -E '^< ')" == 10 ]] \
   && [[ -z "$followup_diff" ]]; then
  echo "   as required: from $base to HEAD the nine texts of the corrections the decisions round applied (C28, C47's report row, C49 three times, C50, C56 three times), found before and missing after, and the summary line, nothing else; from $reviewed to HEAD no line differs (C51's words in the G0.6 report kept)" >> "$log"
else
  echo "   NOT as required: expected exactly the nine applied corrections' texts to change from $base, and nothing from $reviewed:" >> "$log"
  printf '%s\n' "$followup_diff" | sed 's/^/   /' >> "$log"
  status=1
fi
recheck_status=0
python3 -I "$decisions/followup/commands/recheck-review2.py" "$root" > .build/scratch/gate-round2-recheck2.out 2>&1 || recheck_status=$?
{
  echo "-- the follow-up's recheck of the second review's twelve answered findings and HON-11 ($decisions/followup/commands/recheck-review2.py), on HEAD"
  sed 's/^/   /' .build/scratch/gate-round2-recheck2.out
  echo "exit: $recheck_status"
} >> "$log"
(( recheck_status != 0 )) && status=1
recheck4_status=0
python3 -I "$decisions/followup/round-2/commands/recheck-review4.py" "$root" > .build/scratch/gate-round2-recheck4.out 2>&1 || recheck4_status=$?
control4_status=0
python3 -I "$decisions/followup/round-2/commands/recheck-review4.py" "$cct/reviewed" > .build/scratch/gate-round2-recheck4-control.out 2>&1 || control4_status=$?
control4_problems="$(grep -c '^PROBLEM ' .build/scratch/gate-round2-recheck4-control.out)"
{
  echo "-- this round's recheck of the review's findings FID4-01 to FID4-08 ($decisions/followup/round-2/commands/recheck-review4.py; its own log: $decisions/followup/round-2/recheck-review4.log), on HEAD"
  sed 's/^/   /' .build/scratch/gate-round2-recheck4.out
  echo "exit: $recheck4_status"
  echo "-- its control, on the follow-up's tree ($reviewed): each finding must be reported, so the checks read texts the fix changed"
  grep -E '^(PROBLEM|answered|open|changed|result)' .build/scratch/gate-round2-recheck4-control.out | cut -c1-160 | sed 's/^/   /'
  echo "exit: $control4_status; findings reported: $control4_problems"
} >> "$log"
(( recheck4_status != 0 )) && status=1
if [[ "$control4_status" == 1 && "$control4_problems" == 8 ]]; then
  echo "   as required: all eight reported on $reviewed" >> "$log"
else
  echo "   NOT as required: all eight must be reported on $reviewed" >> "$log"; status=1
fi
rm -rf "$cct"
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
