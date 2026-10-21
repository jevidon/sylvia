#!/bin/bash
# Checks behind the update of Docs/Stage0/M0-gate.md at the toolchain re-pin round (20 October 2026; integration log
# section 13), run on the round's last commit with no uncommitted file. The current equivalent of
# final-fix-2/commands/gate-final-checks.sh, which expected 12-dependency-lock to fail on the old pin and the code to be
# unchanged since the complete run:
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/gate-repin-checks.sh <log>
# 1. Files changed since the second round's complete run (87d9dde): besides documents (files under Docs/, and Markdown
#    files elsewhere), exactly the three files of the re-pin, each changed only where the pin or a comment is:
#    Scripts/lib/env.sh (the SYLVIA_XCODE_BUILD_PINNED line), .github/workflows/ci.yml (comment lines and the Xcode
#    guard's candidate, build and error lines) and Scripts/ci.d/50-g03-intake.sh (comment lines); every changed line is
#    printed. Negative control: from the commit the second review round read (83ee280) to 87d9dde the same listing must
#    name the second round's code files.
# 2. The Git LFS state of the tree and of the repository configuration (read-only).
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the gate report rows, ADR status lines
#    and CI logs it cites (commands/gate-refresh-check.py, rows 66, 75, 78 and 82 read against the re-pin); then, on
#    copies with three planted wrong statuses, that the checker reports exactly the rows resting on them.
# 4. The documents' own consistency checks: the plan amendments' checker (0 failures required), the runbook's content
#    check of this round (repin-27.1/commands/runbook-content-check.py; its controls run in runbook-content-check.sh)
#    and step coverage check (final-fix/commands/runbook-coverage.py), and the runbook's correction-text check on the
#    commit the third review round read (dc81fce) and on HEAD (its output must be the same).
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first).
#    Every one must pass: since the re-pin, 12-dependency-lock's toolchain check too.
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G05-AI review R7-04).
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
tested=87d9ddea56ccca4948de252128bb20f1a7517e56
reviewed2=83ee28007517a9e41384a156f2ed647bb68de432
reviewed3=dc81fcea885cc1c8c326e541b889090bc5d3df4a
mkdir -p .build/scratch
# Counted before the log is created, so the log itself (written into the evidence folder) is not counted.
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. Files changed since the complete run's commit ($tested)"
  echo "files changed: $(git diff --name-only "$tested" HEAD | wc -l | tr -d ' '); Markdown files outside Docs/: $(git diff --name-only "$tested" HEAD | grep -v '^Docs/' | grep '\.md$' | tr '\n' ' ')"
} > "$log" 2>&1
outside="$(git diff --name-only "$tested" HEAD | grep -v '^Docs/' | grep -v '\.md$' || true)"
expected=$'.github/workflows/ci.yml\nScripts/ci.d/50-g03-intake.sh\nScripts/lib/env.sh'
{
  echo "other files outside Docs/:"
  printf '%s\n' "$outside" | sed 's/^/   /'
} >> "$log"
if [[ "$outside" != "$expected" ]]; then
  echo "PROBLEM: the files outside Docs/ are not exactly the re-pin's three" >> "$log"; status=1
fi
allowed_line() {  # file, changed line (without its +/- mark): 0 if the change is one the re-pin may make
  local file="$1" line="$2"
  case "$file" in
    Scripts/lib/env.sh) [[ "$line" =~ ^export\ SYLVIA_XCODE_BUILD_PINNED=\"27A(266a|9275)\"$ ]] ;;
    Scripts/ci.d/50-g03-intake.sh) [[ "$line" =~ ^# ]] ;;
    .github/workflows/ci.yml)
      [[ "$line" =~ ^# ]] || [[ "$line" =~ ^\ +for\ candidate\ in\ /Applications/Xcode_27\.[01]\.app\ /Applications/Xcode\.app\;\ do$ ]] \
        || [[ "$line" =~ ^\ +if\ \[\[\ -d\ \"\$candidate\"\ \]\]\ \&\&\ DEVELOPER_DIR=.*xcodebuild\ -version\ \|\ grep\ -q.*27A(266a|9275) ]] \
        || [[ "$line" =~ ^\ +echo\ \"::error::Xcode\ 27\.[01]\ \(27A(266a|9275)\) ]] ;;
    *) return 1 ;;
  esac
}
for file in $outside; do
  echo "-- $file: every changed line" >> "$log"
  while IFS= read -r line; do
    mark="${line:0:1}"; body="${line:1}"
    if allowed_line "$file" "$body"; then
      echo "   ok  $mark$body" >> "$log"
    else
      echo "   PROBLEM (not a pin or comment line) $mark$body" >> "$log"; status=1
    fi
  done < <(git diff -U0 "$tested" HEAD -- "$file" | grep -E '^[-+]' | grep -v -E '^(\+\+\+|---) ')
done
{
  echo "-- 1b. Negative control: from the second review round's commit ($reviewed2) to $tested the same listing must name code files"
  control="$(git diff --name-only "$reviewed2" "$tested" | grep -v '^Docs/' | grep -v '\.md$' || true)"
  echo "   files neither under Docs/ nor Markdown changed between them: $(printf '%s\n' "$control" | grep -c . || true)"
  printf '%s\n' "$control" | sed 's/^/   /'
} >> "$log" 2>&1
[[ -z "$(git diff --name-only "$reviewed2" "$tested" | grep -v '^Docs/' | grep -v '\.md$' || true)" ]] && { echo "   UNEXPECTED: none" >> "$log"; status=1; }
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
neg=.build/scratch/gate-repin-negative
rm -rf "$neg"
mkdir -p "$neg/$evidence/final-fix/ci-logs" "$neg/$evidence/final-fix-2/ci-logs" "$neg/$evidence/repin-27.1" "$neg/Docs/ADRs"
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
python3 -I Docs/Stage0/evidence/M0-plan-amendments/commands/check-amendments.py > .build/scratch/gate-repin-amend.out 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:' .build/scratch/gate-repin-amend.out
  echo "exit: $amend_status"
  echo "-- the runbook's content check (repin-27.1/commands/runbook-content-check.py; its controls: repin-27.1/runbook-content-check.log)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$evidence/repin-27.1/commands/runbook-content-check.py" "$root" > .build/scratch/gate-repin-content.out 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|in its gate.s checklist|source fragments|^result:' .build/scratch/gate-repin-content.out
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > .build/scratch/gate-repin-coverage.out 2>&1 || cov_status=$?
{
  tail -n 3 .build/scratch/gate-repin-coverage.out
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $reviewed3 and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
cct="$root/.build/scratch/gate-repin-cct"
rm -rf "$cct"; mkdir -p "$cct/before" "$cct/after"
git archive "$reviewed3" | tar -x -C "$cct/before"
git archive HEAD | tar -x -C "$cct/after"
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$cct/check.py"
for side in before after; do
  (cd "$cct/$side" && python3 -I "$cct/check.py" > "$cct/$side.out" 2>&1); echo "$?" > "$cct/$side.status"
done
{
  echo "   $reviewed3: exit $(cat "$cct/before.status"); $(tail -n 1 "$cct/before.out")"
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
