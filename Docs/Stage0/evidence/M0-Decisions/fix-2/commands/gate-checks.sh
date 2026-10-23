#!/bin/bash
# Checks behind the second fix of the decisions round (23 October 2026 on the build Mac's clock; integration log
# section 19) on branch m0-decisions, run on the commit that adds the fix's other logs, with no uncommitted file. The
# successor of Docs/Stage0/evidence/M0-Decisions/fix-1/commands/gate-checks.sh:
#   Docs/Stage0/evidence/M0-Decisions/fix-2/commands/gate-checks.sh <log>
# 1. What the second fix changed since the commit the review read (d0a24c43): every file, by kind; outside Docs/,
#    CLAUDE.md and README.md only the lock harness (Spikes/G05-Recovery/LockHarness), and Scripts/ci.d/71-g05-recovery.sh
#    unchanged; CLAUDE.md unchanged (review finding HON-11 is left for the product owner); no code, script, contract,
#    fixture or workflow changed after 13d999fc, the commit of the fix's from-clean run of the harness's checks (the
#    drop-in's run and the controls are on later commits that add only evidence); and, read-only, the repository's
#    local main against the origin/main it last fetched (no fetch: the runbook's 0.3 quotes these, review OWN2-03).
# 2. The Git LFS state of the tree and of the repository configuration (read-only), and the LFS files of HEAD against
#    those of 4c73da57 (main after pull request #5): the runbook's D-8 says m0-decisions adds none.
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the gate report rows, ADR status lines
#    and CI logs it cites (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py); then, on copies with three
#    planted wrong statuses, that the checker reports exactly the rows resting on them (22, 42, 66, 71, 78, 92).
# 4. The documents' own consistency checks: the first fix's amendments checker (evidence/M0-Decisions/fix-1/commands/
#    check-amendments.py, unchanged, 0 failures required; its mutations and controls run in fix-1/commands/run-checks.sh,
#    whose log for this fix is fix-2/check-amendments.log), the assembly's runbook content check (evidence/M0-Decisions/
#    assembly/commands/runbook-content-check.py, unchanged; its controls and limits run in runbook-content-check.sh beside
#    it, log fix-2/runbook-content-check.log), the step coverage check, and the runbook's correction-text check on
#    4c73da57, d0a24c43 and HEAD: from 4c73da57 to HEAD exactly the nine texts of the corrections the decisions round
#    applied change from found to missing, and from d0a24c43 to HEAD nothing changes (the second fix applied no
#    correction and restored none).
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
reviewed=d0a24c43820e587163babe5332ea678b749f93c4
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
code="$(printf '%s\n' "$changed" | grep -v -E '^(Docs/|CLAUDE\.md$|README\.md$)' || true)"
stray="$(printf '%s\n' "$code" | grep -v -E '^Spikes/G05-Recovery/LockHarness/' | grep . || true)"
{
  echo "-- 1a. $(printf '%s\n' "$changed" | grep -c .) files: $(printf '%s\n' "$changed" | grep -c '^Docs/Stage0/evidence/M0-Decisions/fix-2/') of them this fix's evidence, $(printf '%s\n' "$changed" | grep -c '^Docs/') under Docs/ in all, $(printf '%s\n' "$changed" | grep -c -E '^(CLAUDE\.md|README\.md)$') of CLAUDE.md and README.md, and outside them:"
  printf '%s\n' "$code" | grep . | sed 's/^/   /'
  echo "   the documents changed, outside this fix's evidence:"
  printf '%s\n' "$changed" | grep -E '^(Docs/|CLAUDE\.md$|README\.md$)' | grep -v '^Docs/Stage0/evidence/M0-Decisions/fix-2/' | sed 's/^/   /'
  if [[ -n "$stray" ]]; then echo "   PROBLEM: changed outside Docs/, CLAUDE.md, README.md and the lock harness: $stray"; fi
} >> "$log"
[[ -n "$stray" ]] && status=1
dropin_changed="$(git diff --name-only "$reviewed" HEAD -- Scripts/ci.d/71-g05-recovery.sh CLAUDE.md)"
{
  echo "-- 1b. Scripts/ci.d/71-g05-recovery.sh and CLAUDE.md since $reviewed: $( [[ -z "$dropin_changed" ]] && echo "both unchanged (the drop-in's steps 13-15 run the harness's own script; CLAUDE.md is left for the owner, HON-11)" || echo "PROBLEM, changed: $dropin_changed")"
} >> "$log"
[[ -n "$dropin_changed" ]] && status=1
harness_runs=13d999fc5742fe9a3ece1d3819d5befe3f7b889c   # the commit of the fix's from-clean run of the harness's checks
since_runs="$(git diff --name-only "$harness_runs" HEAD -- Spikes Scripts Contracts Fixtures Apps Packages .github)"
{
  echo "-- 1c. code, scripts, contracts, fixtures and the workflow changed since ${harness_runs:0:8}, the commit of the fix's from-clean run of the harness's checks: $( [[ -z "$since_runs" ]] && echo "none, so that run, and the later runs of the drop-in and of the controls, tested this code" || echo "PROBLEM: $since_runs")"
} >> "$log"
[[ -n "$since_runs" ]] && status=1
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
git lfs ls-files -l "$base" | sort > .build/scratch/fix2-lfs-base.txt
git lfs ls-files -l HEAD | sort > .build/scratch/fix2-lfs-head.txt
if cmp -s .build/scratch/fix2-lfs-base.txt .build/scratch/fix2-lfs-head.txt; then
  echo "LFS files (object and path, git lfs ls-files -l) at HEAD and at $base: identical, $(wc -l < .build/scratch/fix2-lfs-head.txt | tr -d ' ') each: m0-decisions adds no LFS object" >> "$log"
else
  echo "LFS files at HEAD and at $base differ:" >> "$log"
  diff .build/scratch/fix2-lfs-base.txt .build/scratch/fix2-lfs-head.txt | head -n 20 >> "$log"
  status=1
fi
rm -f .build/scratch/fix2-lfs-base.txt .build/scratch/fix2-lfs-head.txt
{
  echo
  echo "== 3. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log"
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
neg=.build/scratch/gate-fix2-negative
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
  echo "-- the first fix's amendments checker ($decisions/fix-1/commands/check-amendments.py, unchanged; its mutations and controls: $decisions/fix-2/check-amendments.log)"
} >> "$log"
amend_status=0
python3 -I "$decisions/fix-1/commands/check-amendments.py" > .build/scratch/gate-fix2-amend.out 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:|PO-12' .build/scratch/gate-fix2-amend.out
  echo "exit: $amend_status"
  echo "-- the runbook's content check ($decisions/assembly/commands/runbook-content-check.py, unchanged; its controls and limits: $decisions/fix-2/runbook-content-check.log)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$decisions/assembly/commands/runbook-content-check.py" "$root" > .build/scratch/gate-fix2-content.out 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|NOT_CARRIED:|in its gate.s checklist|source fragments|RUNBOOK_OWN:|^result:' .build/scratch/gate-fix2-content.out
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > .build/scratch/gate-fix2-coverage.out 2>&1 || cov_status=$?
{
  tail -n 3 .build/scratch/gate-fix2-coverage.out
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base, on $reviewed and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
cct="$root/.build/scratch/gate-fix2-cct"
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
fix_diff="$(diff <(tail -n +2 "$cct/reviewed.out") <(tail -n +2 "$cct/head.out") | grep -E '^[<>] ' || true)"
if [[ "$changed_cct" == "$expected" && "$(cat "$cct/base.status")" == 1 && "$(cat "$cct/head.status")" == 1 ]] \
   && [[ "$(diff <(tail -n +2 "$cct/base.out") <(tail -n +2 "$cct/head.out") | grep -c -E '^< ')" == 10 ]] \
   && [[ -z "$fix_diff" ]]; then
  echo "   as required: from $base to HEAD the nine texts of the corrections the decisions round applied (C28, C47's report row, C49 three times, C50, C56 three times), found before and missing after, and the summary line, nothing else; from $reviewed to HEAD no line differs" >> "$log"
else
  echo "   NOT as required: expected exactly the nine applied corrections' texts to change from $base, and nothing from $reviewed:" >> "$log"
  printf '%s\n' "$fix_diff" | sed 's/^/   /' >> "$log"
  status=1
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
