#!/bin/bash
# Checks behind the 19 October 2026 refresh of Docs/Stage0/M0-gate.md, run on a commit that holds the refresh:
#   Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-checks.sh <log>
# 1. Code since the second complete CI run (efc9479): only the Git LFS adoption's five files changed, and each of the
#    527 snapshot references is an LFS pointer to exactly its bytes at efc9479 (gate-refresh-codetree.py).
# 2. The merge of the M0 work into main, read from the local repository (nothing is fetched): 504fac2 is a merge
#    whose second parent is 177ed9a and whose tree is 177ed9a's, and 504fac2, 177ed9a and d8e7d39 are in this
#    branch's history.
# 3. The Git LFS state of the tree and of the repository configuration (read-only).
# 4. M0-gate.md: every cited path exists, and every Section 2 status agrees with the gate report rows, ADR status
#    lines and CI logs it cites (gate-refresh-check.py); then, on copies with three planted wrong statuses, that the
#    checker reports exactly the rows resting on them. Part 1 has a negative control of its own (1b).
# 5. The consistency checks of the documents this refresh edited (the plan amendments' checker and the runbook's
#    correction-text check), on the trees of e3e8886, before the refresh, and of HEAD: their outputs must be the same
#    (lfs/commands/doc-checks-before-after.sh).
# 6. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first).
#    On this Mac 12-dependency-lock is expected to fail on one line only, its toolchain check, because the installed
#    Xcode (27.1) is not the pinned build (integration log 9.5); any other failure fails this script.
# 7. A read-only count of the leftover g05-* directories in the user's temporary folder (G05-AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log. Exit status 1 if any part fails (part 6: other than the expected toolchain line).
set -u
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
log="$1"
cd "$root"
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
mkdir -p .build/scratch
# Counted before the log is created, so the log itself (often written into the evidence folder) is not counted.
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. Code since the second complete CI run (efc9479)"
} > "$log" 2>&1
python3 -I "$commands/gate-refresh-codetree.py" "$root" efc9479 >> "$log" 2>&1 || status=1
{
  echo
  echo "-- 1b. The same check from the first complete run's commit (4a44739), which 038145a's code fixes followed:"
  echo "   it must fail and name those files (the check is not vacuous)"
} >> "$log"
if python3 -I "$commands/gate-refresh-codetree.py" "$root" 4a44739 > .build/scratch/gate-refresh-codetree-negative.out 2>&1; then
  echo "   UNEXPECTED: it passed" >> "$log"; status=1
else
  grep -E '^PROBLEM|^result:' .build/scratch/gate-refresh-codetree-negative.out | sed 's/^/   /' >> "$log"
fi
{
  echo
  echo "== 2. The merge of the M0 work into main (local repository; nothing fetched)"
  echo "504fac2: $(git log -1 --format='%H parents %P; %s' 504fac2)"
  if [[ "$(git rev-parse 504fac2^2)" == "$(git rev-parse 177ed9a)" ]]; then
    echo "second parent of 504fac2 is 177ed9a: yes"
  else
    echo "second parent of 504fac2 is 177ed9a: NO"; echo "PROBLEM: merge parents"
  fi
  if [[ "$(git rev-parse '504fac2^{tree}')" == "$(git rev-parse '177ed9a^{tree}')" ]]; then
    echo "tree of 504fac2 equals the tree of 177ed9a: yes ($(git rev-parse '504fac2^{tree}'))"
  else
    echo "tree of 504fac2 equals the tree of 177ed9a: NO"; echo "PROBLEM: merge tree"
  fi
  for c in 504fac2 177ed9a d8e7d39; do
    if git merge-base --is-ancestor "$c" HEAD; then echo "$c is in the history of HEAD: yes"; else echo "$c is in the history of HEAD: NO"; fi
  done
  echo "origin/main as this repository last fetched it (not fetched here): $(git rev-parse --verify -q origin/main || echo none)"
  echo "commits on HEAD after 504fac2: $(git rev-list --count 504fac2..HEAD)"
} >> "$log" 2>&1
grep -q -E 'PROBLEM|in the history of HEAD: NO' "$log" && status=1
{
  echo
  echo "== 3. Git LFS state"
  echo ".gitattributes patterns (non-comment lines):"
  grep -v -E '^\s*(#|$)' .gitattributes
  echo "git config --show-origin --get-regexp 'filter\\.lfs|lfs\\.':"
  git config --show-origin --get-regexp 'filter\.lfs|lfs\.' || echo "(no match)"
  git lfs version
  echo "files tracked by LFS (git lfs ls-files): $(git lfs ls-files | wc -l | tr -d ' ')"
  echo "git check-attr filter on one snapshot reference and one evidence image:"
  git check-attr filter -- \
    Packages/Design/Tests/SylviaDesignSnapshotTests/__Snapshots__/ComponentSnapshotTests/progressRule.light-default.png \
    Docs/Stage0/evidence/G01-EPUB/highlight-paper.png
  echo
  echo "== 4. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log" 2>&1
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
# 4b. Not vacuous: on copies of the documents, three wrong statuses are planted (the summary's row 22 claims
# passed-simulator; G0.4 row 33 no longer says failed; ADR-0015's status reads Accepted). The checker must fail and
# report exactly the rows that rest on them: 22, 42, and 66, 71, 78 and 92.
neg=.build/scratch/gate-refresh-negative
rm -rf "$neg"
mkdir -p "$neg/Docs/Stage0/evidence/M0-Integration" "$neg/Docs/ADRs"
cp Docs/Stage0/*.md "$neg/Docs/Stage0/"
cp Docs/ADRs/*.md "$neg/Docs/ADRs/"
cp Docs/Stage0/evidence/M0-Integration/ci-full-clean-run-assembled.log Docs/Stage0/evidence/M0-Integration/ci-documents-final.log "$neg/Docs/Stage0/evidence/M0-Integration/"
sed -i '' -E '/^\| 22 \| /s/\| failed \|/| passed-simulator |/' "$neg/Docs/Stage0/M0-gate.md"
sed -i '' -E '/^\| 33 \| /s/budget failed for/budget missed for/' "$neg/Docs/Stage0/G04-Audio.md"
sed -i '' -E 's/^- \*\*Status:\*\* Proposed\. Security review/- **Status:** Accepted. Security review/' "$neg/Docs/ADRs/0015-threat-model.md"
neg_status=0
python3 -I "$commands/gate-refresh-check.py" "$neg" > "$neg.out" 2>&1 || neg_status=$?
disagree="$(grep -E -- '-> DISAGREES$' "$neg.out" | sed -E 's/^row ([0-9]+):.*/\1/' | sort -n -u | tr '\n' ' ' | sed 's/ $//')"
{
  echo
  echo "-- 4b. Negative control on copies with three planted wrong statuses: checker exit $neg_status; rows reported as disagreeing: $disagree"
} >> "$log"
if [[ "$neg_status" == 1 && "$disagree" == "22 42 66 71 78 92" ]]; then
  echo "   as required (22, 42, 66, 71, 78, 92)" >> "$log"
else
  echo "   NOT as required (22, 42, 66, 71, 78, 92)" >> "$log"; status=1
fi
rm -rf "$neg" "$neg.out"
{
  echo
  echo "== 5. The edited documents' own consistency checks, before (e3e8886) and after (HEAD)"
} >> "$log"
Docs/Stage0/evidence/M0-Integration/lfs/commands/doc-checks-before-after.sh e3e8886 HEAD .build/scratch/gate-refresh-doc-checks >> "$log" 2>&1 || status=1
{
  echo
  echo "== 6. Scripts/ci.sh contracts dependency-lock hard-rules"
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
  echo "-- FAIL lines in 12-dependency-lock's log:"
  grep -E '^FAIL ' .build/ci-logs/12-dependency-lock.log || echo "(none)"
} >> "$log" 2>&1
if (( ci_status != 0 )); then
  unexpected="$(grep -E '^FAIL ' .build/ci-logs/12-dependency-lock.log | grep -v -E "^FAIL toolchain xcodebuild -version: expected 'Build version 27A266a', got 'Xcode 27\.1'$" || true)"
  failed_steps="$(grep -E '^FAILED: ' "$log" | tail -n 1)"
  if [[ -z "$unexpected" && "$failed_steps" == "FAILED: 12-dependency-lock" ]]; then
    echo "part 6: the only failure is 12-dependency-lock's toolchain check (installed Xcode 27.1, pin 27A266a), as expected on this Mac" >> "$log"
  else
    echo "part 6: an unexpected failure (above)" >> "$log"
    status=1
  fi
fi
{
  echo
  echo "== 7. Leftover G0.5 temporary directories (read-only count; G05-AI R7-04)"
  tmp="$(getconf DARWIN_USER_TEMP_DIR)"
  echo "g05-* directories in the user's temporary folder: $(find "$tmp" -maxdepth 1 -name 'g05-*' -type d 2>/dev/null | wc -l | tr -d ' ')"
  echo "g05-tests-* directories there: $(find "$tmp" -maxdepth 1 -name 'g05-tests-*' -type d 2>/dev/null | wc -l | tr -d ' ')"
  echo
  echo "exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log" 2>&1
exit $status
