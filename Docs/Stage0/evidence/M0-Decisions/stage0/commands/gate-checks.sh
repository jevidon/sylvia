#!/bin/bash
# Checks behind the records of the product owner's M0 decisions of 22 October 2026 (integration log section 15) in
# Docs/Stage0/M0-gate.md and the other Stage 0 records, run on the commit that adds this round's other logs, with no
# uncommitted file. The successor of Docs/Stage0/evidence/M0-Integration/repin-27.1/round-2/commands/gate-checks.sh.
#   Docs/Stage0/evidence/M0-Decisions/stage0/commands/gate-checks.sh <log>
# 1. Files changed since main after pull request #5 (4c73da57), the base of this round: every one is a Stage 0 record
#    this round owns (Docs/Stage0/M0-gate.md, M0-plan-amendments.md, M0-device-runbook.md, integration-log.md, README.md,
#    the device checklists and gate reports other than G0.5 recovery's, and evidence/M0-Decisions/stage0/), so nothing
#    outside Docs/Stage0/ changed (no code, script, contract, plan, ADR or CLAUDE.md). Negative control: from 87d9dde
#    (the second final-fix round's complete run) to 4c73da57 the same listing must name files outside Docs/Stage0/.
# 2. The Git LFS state of the tree and of the repository configuration (read-only).
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the gate report rows, ADR status lines
#    and CI logs it cites (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py); then, on copies with three
#    planted wrong statuses, that the checker reports exactly the rows resting on them (22, 42, 66, 71, 78, 92).
# 4. The documents' own consistency checks: the plan amendments' checker (0 failures required), this round's runbook
#    content check (evidence/M0-Decisions/stage0/commands/runbook-content-check.py; its controls and limits run in
#    runbook-content-check.sh beside it), the step coverage check (evidence/M0-Integration/final-fix/commands/
#    runbook-coverage.py), and the runbook's correction-text check on 4c73da57 and on HEAD: the outputs must differ in
#    exactly the five texts of the corrections this round applied (C28, C47's report row, C49, and C56's checklist and
#    report texts), each found once before and missing after.
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first).
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G0.5 AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log. Exit status 1 if any part fails.
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
log="$1"
cd "$root"
source Scripts/lib/env.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
evidence="Docs/Stage0/evidence/M0-Integration"
here="Docs/Stage0/evidence/M0-Decisions/stage0"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca
tested=87d9ddea56ccca4948de252128bb20f1a7517e56
mkdir -p .build/scratch
# Counted before the log is created, so the log itself (written into the evidence folder) is not counted.
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
owned() {  # path: 0 if this round owns it
  case "$1" in
    Docs/Stage0/M0-gate.md|Docs/Stage0/M0-plan-amendments.md|Docs/Stage0/M0-device-runbook.md) return 0 ;;
    Docs/Stage0/integration-log.md|Docs/Stage0/README.md) return 0 ;;
    Docs/Stage0/device-checklists/G05-Recovery.md|Docs/Stage0/G05-Recovery.md) return 1 ;;
    Docs/Stage0/device-checklists/*.md|Docs/Stage0/G0*.md) return 0 ;;
    Docs/Stage0/evidence/M0-Decisions/stage0/*) return 0 ;;
    *) return 1 ;;
  esac
}
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. Files changed since this round's base ($base, main after pull request #5)"
  echo "files changed: $(git diff --name-only "$base" HEAD | wc -l | tr -d ' ')"
} > "$log" 2>&1
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if owned "$file"; then
    echo "   ok  $file" >> "$log"
  else
    echo "   PROBLEM (not a record this round owns) $file" >> "$log"; status=1
  fi
done < <(git diff --name-only "$base" HEAD)
{
  echo "-- 1b. Negative control: from $tested to $base the same listing must name files this round does not own"
  control="$(git diff --name-only "$tested" "$base" | while IFS= read -r f; do owned "$f" || echo "$f"; done)"
  echo "   files outside this round's records changed between them: $(printf '%s\n' "$control" | grep -c . || true), among them:"
  printf '%s\n' "$control" | grep -v '^Docs/Stage0/evidence/' | head -n 12 | sed 's/^/   /'
} >> "$log" 2>&1
[[ -z "$(git diff --name-only "$tested" "$base" | while IFS= read -r f; do owned "$f" || echo "$f"; done)" ]] && { echo "   UNEXPECTED: none" >> "$log"; status=1; }
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
neg=.build/scratch/gate-decisions-negative
rm -rf "$neg"
mkdir -p "$neg/$evidence/final-fix/ci-logs" "$neg/$evidence/final-fix-2/ci-logs" "$neg/$evidence/repin-27.1/round-2" "$neg/Docs/ADRs" "$neg/Docs/Stage0"
cp Docs/Stage0/*.md "$neg/Docs/Stage0/"
cp Docs/ADRs/*.md "$neg/Docs/ADRs/"
cp "$evidence/ci-full-clean-run-assembled.log" "$evidence/ci-documents-final.log" "$evidence/ci-full-clean-run-final.log" \
  "$neg/$evidence/"
cp "$evidence/final-fix/ci-full-clean-run-final.log" "$neg/$evidence/final-fix/"
for round in final-fix final-fix-2; do
  cp "$evidence/$round/ci-logs/10-contracts.log" "$evidence/$round/ci-logs/12-dependency-lock.log" \
    "$neg/$evidence/$round/ci-logs/"
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
  echo "-- the plan amendments' checker (Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py)"
} >> "$log"
amend_status=0
python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py > .build/scratch/gate-decisions-amend.out 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:' .build/scratch/gate-decisions-amend.out
  echo "exit: $amend_status"
  echo "-- the runbook's content check ($here/commands/runbook-content-check.py; its controls and limits: $here/runbook-content-check.log)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$here/commands/runbook-content-check.py" "$root" > .build/scratch/gate-decisions-content.out 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|NOT_CARRIED:|in its gate.s checklist|source fragments|RUNBOOK_OWN:|^result:' .build/scratch/gate-decisions-content.out
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > .build/scratch/gate-decisions-coverage.out 2>&1 || cov_status=$?
{
  tail -n 3 .build/scratch/gate-decisions-coverage.out
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
cct="$root/.build/scratch/gate-decisions-cct"
rm -rf "$cct"; mkdir -p "$cct/before" "$cct/after"
git archive "$base" | tar -x -C "$cct/before"
git archive HEAD | tar -x -C "$cct/after"
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$cct/check.py"
for side in before after; do
  (cd "$cct/$side" && python3 -I "$cct/check.py" > "$cct/$side.out" 2>&1); echo "$?" > "$cct/$side.status"
done
{
  echo "   $base: exit $(cat "$cct/before.status"); $(tail -n 1 "$cct/before.out")"
  echo "   HEAD: exit $(cat "$cct/after.status"); $(tail -n 1 "$cct/after.out")"
  echo "   the lines that differ (the first line, a timestamp, left out):"
  diff <(tail -n +2 "$cct/before.out") <(tail -n +2 "$cct/after.out") | grep -E '^[<>] ' | sed 's/^/   /'
} >> "$log"
changed="$(diff <(tail -n +2 "$cct/before.out") <(tail -n +2 "$cct/after.out") | grep -E '^> C[0-9]+ ' | sed -E 's/^> (C[0-9]+) +([A-Z]+|ok) +x([0-9]+) ([^:]+):.*/\1 \2 \3 \4/' | sort)"
expected="$(printf '%s\n' \
  "C28 MISSING 0 Docs/Stage0/device-checklists/G06-Design.md" \
  "C47 MISSING 0 Docs/Stage0/G02-Transfer.md" \
  "C49 MISSING 0 Docs/Stage0/G05-AI.md" \
  "C56 MISSING 0 Docs/Stage0/G03-Intake.md" \
  "C56 MISSING 0 Docs/Stage0/device-checklists/G03-Intake.md" | sort)"
if [[ "$changed" == "$expected" && "$(cat "$cct/before.status")" == 1 && "$(cat "$cct/after.status")" == 1 ]] \
   && [[ "$(diff <(tail -n +2 "$cct/before.out") <(tail -n +2 "$cct/after.out") | grep -c -E '^< ')" == 6 ]]; then
  echo "   as required: the texts of the five corrections applied (C28, C47's report row, C49, C56 twice), found before and missing after, and the summary line; nothing else" >> "$log"
else
  echo "   NOT as required: expected exactly the five applied corrections' texts to change from found to missing" >> "$log"
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
  echo "-- its toolchain lines:"
  grep -E '^ok    toolchain:' .build/ci-logs/12-dependency-lock.log || echo "(none)"
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
