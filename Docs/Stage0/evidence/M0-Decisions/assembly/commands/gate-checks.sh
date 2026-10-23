#!/bin/bash
# Checks behind the assembly of the M0 decisions round (22 October 2026; integration log section 17) on branch
# m0-decisions, run on the commit that adds the assembly's other logs, with no uncommitted file. The successor of
# Docs/Stage0/evidence/M0-Decisions/stage0/commands/gate-checks.sh, for the four workstreams merged together:
#   Docs/Stage0/evidence/M0-Decisions/assembly/commands/gate-checks.sh <log>
# 1. Ownership. (a) Each of the four decision branches (m0-dec-plan, m0-dec-adrs, m0-dec-stage0, m0-dec-harness, at the
#    commits merged) changed, since main after pull request #5 (4c73da57), only files its workstream owns, so the four
#    were disjoint; (b) the tree after the fourth merge differs from 4c73da57 in exactly their union; (c) every file
#    changed since 4c73da57 belongs to one of the four workstreams or to the assembly (the dependency inventory, which
#    the harness asked to have updated, and the assembly's evidence); (d) the assembly's own commits, after the fourth
#    merge, changed only documents and evidence (Docs/ and CLAUDE.md): no code, script, contract, fixture or workflow.
#    Negative control: from 87d9dde (the second final-fix round's complete run) to 4c73da57 the attribution must find
#    files that none of them owns.
# 2. The Git LFS state of the tree and of the repository configuration (read-only).
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the gate report rows, ADR status lines
#    and CI logs it cites (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py); then, on copies with three
#    planted wrong statuses, that the checker reports exactly the rows resting on them (22, 42, 66, 71, 78, 92).
# 4. The documents' own consistency checks: the plan amendments' checker for plan draft 0.8
#    (evidence/M0-Decisions/plan/commands/check-amendments.py, 0 failures required; the draft 0.7 checker, which fails
#    on draft 0.8 by design, is the plan round's control), the assembly's runbook content check
#    (evidence/M0-Decisions/assembly/commands/runbook-content-check.py; its controls and limits run in
#    runbook-content-check.sh beside it), the step coverage check (evidence/M0-Integration/final-fix/commands/
#    runbook-coverage.py), and the runbook's correction-text check on 4c73da57 and on HEAD: the outputs must differ in
#    exactly the nine texts of the corrections the decisions round applied (C28; C47's report row; C49's two ADR-0011
#    lines and its report row; C50's ADR-0013 item; C56's checklist, ADR-0010 and report texts), each found once before
#    and missing after.
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
decisions="Docs/Stage0/evidence/M0-Decisions"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca
tested=87d9ddea56ccca4948de252128bb20f1a7517e56
merged=35b7123fa325f4b8f84a74b79dfb094c9be27752   # the fourth merge (m0-dec-harness) on m0-decisions
branches=(plan:aa8d45508f5fe87539639b66ecc96778c4393bc5 adrs:890445797524c0f3f8a220ed92b2e5a3e32b7a0b
          stage0:8662c9ea7b8b0fe03a73aaabb482465680a3a10e harness:1adb8f277c87c369e38f6d947c7e688d3736f941)
mkdir -p .build/scratch
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
workstream() {  # path -> the workstream that owns it, or nothing
  case "$1" in
    Docs/Sylvia_v1_iOS_Implementation_Plan.md|"$decisions"/plan/*) echo plan ;;
    CLAUDE.md|Docs/ADRs/*|"$decisions"/adrs/*) echo adrs ;;
    Docs/Stage0/G05-Recovery.md|Docs/Stage0/device-checklists/G05-Recovery.md|"$decisions"/harness/*) echo harness ;;
    Spikes/G05-Recovery/LockHarness/*|Scripts/ci.d/71-g05-recovery.sh) echo harness ;;
    Docs/Stage0/M0-gate.md|Docs/Stage0/M0-plan-amendments.md|Docs/Stage0/M0-device-runbook.md) echo stage0 ;;
    Docs/Stage0/integration-log.md|Docs/Stage0/README.md|Docs/Stage0/device-checklists/*.md|Docs/Stage0/G0*.md) echo stage0 ;;
    "$decisions"/stage0/*) echo stage0 ;;
    Docs/Licenses/inventory.json|Docs/Licenses/third-party-inventory.md|"$decisions"/assembly/*) echo assembly ;;
  esac
}
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. Ownership of the files changed since $base (main after pull request #5)"
} > "$log" 2>&1
union=.build/scratch/gate-assembly-union
: > "$union"
for entry in "${branches[@]}"; do
  name="${entry%%:*}"; commit="${entry#*:}"
  files="$(git diff --name-only "$base" "$commit")"
  printf '%s\n' "$files" >> "$union"
  stray="$(printf '%s\n' "$files" | while IFS= read -r f; do [[ -n "$f" && "$(workstream "$f")" != "$name" ]] && echo "$f"; done)"
  echo "-- 1a. m0-dec-$name at ${commit:0:8}: $(printf '%s\n' "$files" | grep -c .) files changed, $( [[ -z "$stray" ]] && echo "each one its workstream's" || echo "NOT its workstream's: $stray")" >> "$log"
  [[ -n "$stray" ]] && status=1
done
dups="$(sort "$union" | uniq -d)"
if [[ -n "$dups" ]]; then echo "   PROBLEM: files changed by more than one branch: $dups" >> "$log"; status=1; else echo "   no file changed by two branches" >> "$log"; fi
after_merge="$(git diff --name-only "$base" "$merged" | sort)"
if [[ "$after_merge" == "$(sort -u "$union")" ]]; then
  echo "-- 1b. after the fourth merge (${merged:0:8}) the tree differs from $base in exactly the union of the four branches' files ($(printf '%s\n' "$after_merge" | grep -c .))" >> "$log"
else
  echo "-- 1b. PROBLEM: the tree after the fourth merge differs from $base in other files than the four branches' union" >> "$log"; status=1
fi
counts=""
problems=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  w="$(workstream "$f")"
  if [[ -z "$w" ]]; then problems="$problems $f"; else counts="$counts $w"; fi
done < <(git diff --name-only "$base" HEAD)
{
  echo "-- 1c. every file changed since $base, by workstream: $(printf '%s\n' $counts | sort | uniq -c | awk '{printf "%s %s; ", $2, $1}')"
  [[ -n "$problems" ]] && echo "   PROBLEM (owned by no workstream):$problems"
} >> "$log"
[[ -n "$problems" ]] && status=1
assembled="$(git diff --name-only "$merged" HEAD)"
outside="$(printf '%s\n' "$assembled" | grep -v -E '^(Docs/|CLAUDE\.md$)' || true)"
{
  echo "-- 1d. the assembly's own commits (${merged:0:8}..HEAD) changed $(printf '%s\n' "$assembled" | grep -c .) files, $( [[ -z "$outside" ]] && echo "all documents or evidence (Docs/ and CLAUDE.md)" || echo "PROBLEM, some outside Docs/ and CLAUDE.md: $outside")"
  printf '%s\n' "$assembled" | grep -v '^Docs/Stage0/evidence/M0-Decisions/assembly/' | sed 's/^/   /'
  echo "   (and $(printf '%s\n' "$assembled" | grep -c '^Docs/Stage0/evidence/M0-Decisions/assembly/') files of the assembly's evidence)"
} >> "$log"
[[ -n "$outside" ]] && status=1
control="$(git diff --name-only "$tested" "$base" | while IFS= read -r f; do [[ -z "$(workstream "$f")" ]] && echo "$f"; done)"
{
  echo "-- 1e. Negative control: from $tested to $base, files that none of the workstreams owns: $(printf '%s\n' "$control" | grep -c . || true), among them:"
  printf '%s\n' "$control" | grep -v '^Docs/Stage0/evidence/' | head -n 8 | sed 's/^/   /'
} >> "$log"
[[ -z "$control" ]] && { echo "   UNEXPECTED: none" >> "$log"; status=1; }
{
  echo
  echo "== 2. Git LFS state"
  echo ".gitattributes patterns (non-comment lines):"
  grep -v -E '^\s*(#|$)' .gitattributes
  echo "git config --show-origin --get-regexp 'filter\\.lfs|lfs\\.':"
  git config --show-origin --get-regexp 'filter\.lfs|lfs\.' || echo "(no match)"
  git lfs version
  echo "files tracked by LFS (git lfs ls-files): $(git lfs ls-files | wc -l | tr -d ' '); of them still pointer files in the working tree: $(git lfs ls-files | awk '$2 == "-"' | wc -l | tr -d ' ')"
  echo
  echo "== 3. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log" 2>&1
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
neg=.build/scratch/gate-assembly-negative
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
  echo "-- the plan amendments' checker for plan draft 0.8 ($decisions/plan/commands/check-amendments.py)"
} >> "$log"
amend_status=0
python3 -I "$decisions/plan/commands/check-amendments.py" > .build/scratch/gate-assembly-amend.out 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:' .build/scratch/gate-assembly-amend.out
  echo "exit: $amend_status"
  echo "-- the runbook's content check ($decisions/assembly/commands/runbook-content-check.py; its controls and limits: $decisions/assembly/runbook-content-check.log)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$decisions/assembly/commands/runbook-content-check.py" "$root" > .build/scratch/gate-assembly-content.out 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|NOT_CARRIED:|in its gate.s checklist|source fragments|RUNBOOK_OWN:|^result:' .build/scratch/gate-assembly-content.out
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > .build/scratch/gate-assembly-coverage.out 2>&1 || cov_status=$?
{
  tail -n 3 .build/scratch/gate-assembly-coverage.out
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
cct="$root/.build/scratch/gate-assembly-cct"
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
  "C49 MISSING 0 Docs/ADRs/0011-ai-providers-context-and-privacy.md" \
  "C49 MISSING 0 Docs/ADRs/0011-ai-providers-context-and-privacy.md" \
  "C49 MISSING 0 Docs/Stage0/G05-AI.md" \
  "C50 MISSING 0 Docs/ADRs/0013-design-language.md" \
  "C56 MISSING 0 Docs/ADRs/0010-intake-handoff-and-wired-bundles.md" \
  "C56 MISSING 0 Docs/Stage0/G03-Intake.md" \
  "C56 MISSING 0 Docs/Stage0/device-checklists/G03-Intake.md" | sort)"
if [[ "$changed" == "$expected" && "$(cat "$cct/before.status")" == 1 && "$(cat "$cct/after.status")" == 1 ]] \
   && [[ "$(diff <(tail -n +2 "$cct/before.out") <(tail -n +2 "$cct/after.out") | grep -c -E '^< ')" == 10 ]]; then
  echo "   as required: the nine texts of the corrections the decisions round applied (C28, C47's report row, C49 three times, C50, C56 three times), found before and missing after, and the summary line; nothing else" >> "$log"
else
  echo "   NOT as required: expected exactly the nine applied corrections' texts to change from found to missing" >> "$log"
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
