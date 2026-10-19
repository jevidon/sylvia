#!/bin/bash
# Checks behind the update of Docs/Stage0/M0-gate.md at the M0 final fix's second round (20 October 2026; integration
# log section 12), run on the round's last commit with no uncommitted file:
#   Docs/Stage0/evidence/M0-Integration/final-fix-2/commands/gate-final-checks.sh <log>
# 1. Code since the complete run's commit: between 87d9dde (the commit ci-final-clone.sh tested) and HEAD only
#    documents changed (files under Docs/, and Markdown files elsewhere, such as CLAUDE.md, Contracts/README.md and
#    Fixtures/LICENSES.md, which part 5's drop-ins read again), so the complete run covers the final code. Negative
#    control: between the commit the second review round read (83ee280) and 87d9dde the same check must fail and name
#    the round's code files.
# 2. The Git LFS state of the tree and of the repository configuration (read-only).
# 3. M0-gate.md: every cited path exists, and every Section 2 status agrees with the gate report rows, ADR status
#    lines and CI logs it cites (commands/gate-refresh-check.py, which reads both complete runs of the final fix for
#    rows 75 and 90); then, on copies with three planted wrong statuses, that the checker reports exactly the rows
#    resting on them.
# 4. The documents' own consistency checks: the plan amendments' checker (0 failures required), the runbook's content
#    check (final-fix-2/commands/runbook-content-check.py: quoted texts and counts, both ways) and step coverage check
#    (final-fix/commands/runbook-coverage.py), and the runbook's correction-text check on the reviewed commit and on
#    HEAD (its output must be the same: the round's edits change nothing it reports).
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first).
#    On this Mac 12-dependency-lock is expected to fail on one line only, its toolchain check, because the installed
#    Xcode (27.1) is not the pinned build; any other failure fails this script.
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G05-AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log. Exit status 1 if any part fails (part 5: other than the expected toolchain line).
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
log="$1"
cd "$root"
source Scripts/lib/env.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
evidence="Docs/Stage0/evidence/M0-Integration"
tested=87d9ddea56ccca4948de252128bb20f1a7517e56
reviewed=83ee28007517a9e41384a156f2ed647bb68de432
mkdir -p .build/scratch
# Counted before the log is created, so the log itself (written into the evidence folder) is not counted.
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. Files changed since the complete run's commit ($tested)"
  outside="$(git diff --name-only "$tested" HEAD | grep -v '^Docs/' | grep -v '\.md$' || true)"
  echo "files changed: $(git diff --name-only "$tested" HEAD | wc -l | tr -d ' '); Markdown files outside Docs/: $(git diff --name-only "$tested" HEAD | grep -v '^Docs/' | grep '\.md$' | tr '\n' ' ')"
  echo "other files outside Docs/: $(printf '%s' "$outside" | grep -c . || true)"
  if [[ -n "$outside" ]]; then
    echo "$outside" | sed 's/^/PROBLEM: changed, and neither under Docs\/ nor a Markdown file: /'
  else
    echo "only documents and evidence changed: the complete run covers the final code"
  fi
  echo "-- 1b. Negative control: from the reviewed commit ($reviewed) to $tested the same check must name code files"
  control="$(git diff --name-only "$reviewed" "$tested" | grep -v '^Docs/' | grep -v '\.md$' || true)"
  echo "   files neither under Docs/ nor Markdown changed between them: $(printf '%s\n' "$control" | grep -c . || true)"
  printf '%s\n' "$control" | sed 's/^/   /'
} > "$log" 2>&1
[[ -n "$outside" ]] && status=1
[[ -z "$control" ]] && { echo "   UNEXPECTED: none" >> "$log"; status=1; }
{
  echo
  echo "== 2. Git LFS state"
  echo ".gitattributes patterns (non-comment lines):"
  grep -v -E '^\s*(#|$)' .gitattributes
  echo "git config --show-origin --get-regexp 'filter\\.lfs|lfs\\.':"
  git config --show-origin --get-regexp 'filter\.lfs|lfs\.' || echo "(no match)"
  git lfs version
  echo "files tracked by LFS (git lfs ls-files): $(git lfs ls-files | wc -l | tr -d ' ')"
  echo
  echo "== 3. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log" 2>&1
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
neg=.build/scratch/gate-final-negative
rm -rf "$neg"
mkdir -p "$neg/$evidence/final-fix/ci-logs" "$neg/$evidence/final-fix-2/ci-logs" "$neg/Docs/ADRs"
cp Docs/Stage0/*.md "$neg/Docs/Stage0/"
cp Docs/ADRs/*.md "$neg/Docs/ADRs/"
cp "$evidence/ci-full-clean-run-assembled.log" "$evidence/ci-documents-final.log" "$evidence/ci-full-clean-run-final.log" \
  "$neg/$evidence/"
cp "$evidence/final-fix/ci-full-clean-run-final.log" "$neg/$evidence/final-fix/"
for round in final-fix final-fix-2; do
  cp "$evidence/$round/ci-logs/10-contracts.log" "$evidence/$round/ci-logs/12-dependency-lock.log" \
    "$neg/$evidence/$round/ci-logs/"
done
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
  echo "-- the plan amendments' checker (Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py)"
} >> "$log"
amend_status=0
python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py > .build/scratch/gate-final-amend.out 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:' .build/scratch/gate-final-amend.out
  echo "exit: $amend_status"
  echo "-- the runbook's content check (final-fix-2/commands/runbook-content-check.py: quoted texts and counts, both ways)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$evidence/final-fix-2/commands/runbook-content-check.py" "$root" > .build/scratch/gate-final-content.out 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|^result:' .build/scratch/gate-final-content.out
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > .build/scratch/gate-final-coverage.out 2>&1 || cov_status=$?
{
  tail -n 3 .build/scratch/gate-final-coverage.out
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $reviewed and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
cct="$root/.build/scratch/gate-final-cct"
rm -rf "$cct"; mkdir -p "$cct/before" "$cct/after"
git archive "$reviewed" | tar -x -C "$cct/before"
git archive HEAD | tar -x -C "$cct/after"
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$cct/check.py"
for side in before after; do
  (cd "$cct/$side" && python3 -I "$cct/check.py" > "$cct/$side.out" 2>&1); echo "$?" > "$cct/$side.status"
done
{
  echo "   $reviewed: exit $(cat "$cct/before.status"); $(tail -n 1 "$cct/before.out")"
  echo "   HEAD: exit $(cat "$cct/after.status"); $(tail -n 1 "$cct/after.out")"
} >> "$log"
if [[ -s "$cct/before.out" && -s "$cct/after.out" ]] \
   && diff <(tail -n +2 "$cct/before.out") <(tail -n +2 "$cct/after.out") > /dev/null \
   && [[ "$(cat "$cct/before.status")" == "$(cat "$cct/after.status")" ]]; then
  echo "   the two outputs are the same (the first line, a timestamp, left out): the round's edits change nothing it reports" >> "$log"
else
  echo "   the outputs DIFFER:" >> "$log"
  diff <(tail -n +2 "$cct/before.out") <(tail -n +2 "$cct/after.out") | sed 's/^/   /' >> "$log"
  status=1
fi
rm -rf "$cct"
{
  echo
  echo "== 5. Scripts/ci.sh contracts dependency-lock hard-rules"
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
} >> "$log" 2>&1
if (( ci_status != 0 )); then
  unexpected="$(grep -E '^FAIL ' .build/ci-logs/12-dependency-lock.log | grep -v -E "^FAIL toolchain xcodebuild -version: expected 'Build version 27A266a', got 'Xcode 27\.1'$" || true)"
  failed_steps="$(grep -E '^FAILED: ' "$log" | tail -n 1)"
  if [[ -z "$unexpected" && "$failed_steps" == "FAILED: 12-dependency-lock" ]]; then
    echo "part 5: the only failure is 12-dependency-lock's toolchain check (installed Xcode 27.1, pin 27A266a), as expected on this Mac" >> "$log"
  else
    echo "part 5: an unexpected failure (above)" >> "$log"
    status=1
  fi
fi
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
