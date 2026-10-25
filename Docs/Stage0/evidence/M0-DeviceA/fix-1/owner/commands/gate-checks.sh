#!/bin/bash
# Gate checks of the fix of the owner-readability findings of the review of the update of 24 October 2026 and its
# assembly (26 October 2026 on the build Mac's clock; integration log section 32), made on m0-sessions from caf75a84, the
# last commit of the fix of the same review's completeness findings; the findings cite 8082bdb6. Run on the commit that
# adds every other log of the fix, with no uncommitted file. The successor of
# Docs/Stage0/evidence/M0-DeviceA/fix-1/completeness/commands/gate-checks.sh, whose parts it runs with this fix's
# expectations:
#   Docs/Stage0/evidence/M0-DeviceA/fix-1/owner/commands/gate-checks.sh <log>
# 1. What changed since caf75a84: only the files this fix names (FIXED below) and its own folder; outside Docs/ only
#    README.md; CLAUDE.md, the session log, the license inventory, the gate reports, the plan and the amendments
#    unchanged; of the checklists only the G0.5 recovery one, by exactly one added line (its setup note, OWN-DA-03);
#    under Docs/Stage0/evidence, only this fix's new files and dated notes in the records part's evidence README and the
#    first three fixes' READMEs. Since 6cede84a (the update's start), nothing outside Docs/ but README.md, and CLAUDE.md,
#    the session log and the license inventory unchanged, as before. 9cdb0a02 an ancestor, the code unchanged since it,
#    the drop-in's own paths unchanged and the merge of m0-decisions changing nothing under them that the drop-in uses
#    (the third fix's dropin-paths.sh, unchanged); the checklists unchanged from 9cdb0a02 to 6cede84a, and the session log
#    at HEAD with no sitting of the owner's; the committed logs of resolve-locks.sh and linkage.sh unchanged, and no run
#    under Xcode 27.1; 1h, the branches and the sessions' checkout judged against the owner's instructions (the second
#    fix's branch-texts.py, unchanged): it must pass on HEAD, and fail on the trees of 8082bdb6 (its four rules) and
#    d6315ad3 (exactly its rule on the sittings); and 1i, the two merges computed and not made (merges.sh beside this
#    file): m0-decisions still at c72247a6 and merging without a conflict, m0-exit-prep conflicting in the same files
#    into HEAD as into caf75a84.
# 2. The Git LFS state, read-only, and the LFS files of HEAD against those of 4c73da57: no LFS file added.
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the records it cites
#    (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py), with its negative control.
# 4. The documents' own checks:
#    - the second fix's amendments checker (../../accuracy/commands/check-amendments.py), the newest: it must pass; its
#      70 mutations must each be caught, the tree restored; the records part's version must fail exactly its check 10k,
#      and the follow-up's fix's checker on exactly its three, as before;
#    - the records part's check of the ADRs, the index, the reports and the integration log (check-records.py): exactly
#      its check of the ADR index, as before; its control on the tree of 6cede84a as before (17 of 18 failing);
#    - the instructions part's runbook content check: it must pass; the decisions round's version must report exactly
#      its three texts, as before;
#    - the step coverage check: it must pass;
#    - the correction-text check on 4c73da57, 8082bdb6, d6315ad3, ec91f66a, caf75a84 and HEAD: from 4c73da57 to HEAD
#      exactly the nine texts of the corrections the decisions round applied change, and from the other four to HEAD
#      nothing;
#    - the earlier rounds' rechecks: those that read no text this fix changed must pass (with their controls); the six
#      that read texts the update or its fixes changed must report exactly the 17 lines of the second fix's
#      expected-rechecks.txt, unchanged (this fix kept the State line, the opening within its 600 words and item 1's steps
#      within their 400, which three of them measure);
#    - the instructions part's recheck: exactly its floor item, as before, and its item run-1, on exactly the two texts of
#      pull request #6's date that this fix changed (OWN-DA-06);
#    - the assembly's recheck: exactly its items run-1 (the same two texts), agree and state, as before; its controls as
#      before;
#    - the first fix's check of the review's cited lines: every one holds at 8082bdb6; its control at HEAD fails;
#    - the first fix's recheck (recheck-fix1.py): exactly its items checkout, step-0.8 and review, on the same texts as
#      before; its control on 8082bdb6's tree, all eight;
#    - the second fix's check of its findings' cited lines: every one holds at 8082bdb6; its control at HEAD fails;
#    - the second fix's recheck (recheck-acc.py): it must pass on HEAD; its control on d6315ad3's tree, six of seven;
#    - the third fix's check of its findings' cited lines: every one holds at 8082bdb6; its control at HEAD fails;
#    - the third fix's recheck (recheck-da.py): exactly its item review, on exactly the two texts that give its fix as
#      the last (Section 6.2's row and the runbook's Who wrote it), which this fix extended; its control on the tree of
#      ec91f66a, its eight items as before;
#    - this fix's check of the owner-readability findings' cited lines (finding-lines.py beside this file): every one
#      holds at 8082bdb6; as its control, at HEAD the lines this fix or the first three changed no longer hold;
#    - this fix's recheck (recheck-own.py): it must pass on HEAD; as its control, report all ten items on the tree of
#      caf75a84.
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first; the
#    worktree's LFS files filled from the local store first: ../checks/lfs-checkout.log).
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G0.5 AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log, but for the mutations of part 4, each written to the working copy and restored from memory before
# the next, and the merged trees' objects of parts 1e and 1i, written to the object store (git merge-tree). Exit status 1
# if any part fails.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, owner, fix-1, M0-DeviceA, evidence, Stage0, Docs
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
source Scripts/lib/env.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
evidence="Docs/Stage0/evidence/M0-Integration"
decisions="Docs/Stage0/evidence/M0-Decisions"
devicea="Docs/Stage0/evidence/M0-DeviceA"
instr="$devicea/instructions"
asm="$devicea/assembly"
first="$devicea/fix-1"
acc="$devicea/fix-1/accuracy"
da="$devicea/fix-1/completeness"
here="$devicea/fix-1/owner"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e
start=6cede84a6f6ac610976b233d875e26dd89419dbd
prev=26530d4933c070c2c154a9116ef6f7fdd0415363
mergeR=5e455f706c20d46711030a8b030c9dbf87dd4acd
reviewed=8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22
fixA=d6315ad3f3a69f28258bfa54581c6ab6c005dcc8  # the first fix's last commit
fixB=ec91f66a863c70980533f27f53d8e6b44f234485  # the second fix's last commit
fixC=caf75a8447597efa5076b53b9a0d36be0fdcc901  # the third fix's last commit, which this fix starts from
scratch=.build/scratch/devicea-fix1-own-gate
rm -rf "$scratch"; mkdir -p "$scratch"
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. What changed"
} > "$log" 2>&1
[[ "$uncommitted" == 0 ]] || { echo "PROBLEM: run on a clean tree ($uncommitted uncommitted files)" >> "$log"; status=1; }
git merge-base --is-ancestor "$fixC" HEAD || { echo "PROBLEM: HEAD does not descend from $fixC" >> "$log"; status=1; }
FIXED='^(README\.md|Docs/Stage0/M0-device-runbook\.md|Docs/Stage0/M0-gate\.md|Docs/Stage0/README\.md|Docs/Stage0/integration-log\.md|Docs/ADRs/0001-platform-baseline-and-toolchain\.md|Docs/Stage0/device-checklists/G05-Recovery\.md|Docs/Stage0/evidence/M0-DeviceA/(README\.md|fix-1/README\.md|fix-1/accuracy/README\.md|fix-1/completeness/README\.md|fix-1/owner/.+))$'
changed="$(git diff --name-only "$fixC" HEAD)"
stray="$(printf '%s\n' "$changed" | grep . | grep -v -E "$FIXED" || true)"
{
  echo "-- 1a. since ${fixC:0:8} (the third fix's last commit, which this fix starts from): $(printf '%s\n' "$changed" | grep -c .) files; of them this fix's folder: $(printf '%s\n' "$changed" | grep -c "^$here/"); the documents:"
  printf '%s\n' "$changed" | grep -v "^$here/" | sed 's/^/     /'
  if [[ -z "$stray" ]]; then echo "   no other file"; else echo "   PROBLEM: also $stray"; fi
} >> "$log"
[[ -n "$stray" ]] && status=1
outside="$(git diff --name-only "$fixC" HEAD -- . ':(exclude)Docs' ':(exclude)README.md')"
fixed="$(git diff --name-only "$fixC" HEAD -- CLAUDE.md Docs/Stage0/evidence/M0-runbook/sessions.md Docs/Licenses 'Docs/Stage0/G0*.md' Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md)"
lists="$(git diff --numstat "$fixC" HEAD -- Docs/Stage0/device-checklists)"
lists_ok=no
[[ "$lists" == "$(printf '1\t0\tDocs/Stage0/device-checklists/G05-Recovery.md')" ]] && lists_ok=yes
{
  echo "-- 1b. outside Docs/ and README.md since ${fixC:0:8}: $( [[ -z "$outside" ]] && echo "nothing changed" || echo "PROBLEM, changed: $outside")"
  echo "   CLAUDE.md, the session log, the license inventory, the gate reports, the plan and the amendments since ${fixC:0:8}: $( [[ -z "$fixed" ]] && echo "unchanged" || echo "PROBLEM, changed: $fixed")"
  echo "   the checklists since ${fixC:0:8} (git diff --numstat): $(printf '%s' "$lists" | tr '\t\n' ' ;')$( [[ "$lists_ok" == yes ]] && echo "- one line added to the G0.5 recovery checklist, none removed, no other checklist changed (its setup note, OWN-DA-03)" || echo "PROBLEM: not exactly one line added to the G0.5 recovery checklist")"
} >> "$log"
[[ -n "$outside" || -n "$fixed" || "$lists_ok" != yes ]] && status=1
hist="$(git diff --name-status "$fixC" HEAD -- Docs/Stage0/evidence)"
hist_bad="$(printf '%s\n' "$hist" | grep . | grep -v -E $'^A\tDocs/Stage0/evidence/M0-DeviceA/fix-1/owner/' | grep -v -E $'^M\tDocs/Stage0/evidence/M0-DeviceA/(README\\.md|fix-1/README\\.md|fix-1/accuracy/README\\.md|fix-1/completeness/README\\.md)$' || true)"
{
  echo "-- 1c. the evidence: git diff --name-status ${fixC:0:8} HEAD -- Docs/Stage0/evidence lists $(printf '%s\n' "$hist" | grep -c .) files: $(printf '%s\n' "$hist" | grep -c $'^A\t') added under $here/ and $(printf '%s\n' "$hist" | grep -c $'^M\t') modified, $( [[ -z "$hist_bad" ]] && echo "only the records part's evidence README and the first three fixes' READMEs (dated notes): no earlier evidence file changed" || echo "PROBLEM, also: $hist_bad")"
  printf '%s\n' "$hist" | grep $'^M\t' | sed 's/^/     /'
} >> "$log"
[[ -n "$hist_bad" ]] && status=1
since_start_outside="$(git diff --name-only "$start" HEAD -- . ':(exclude)Docs' ':(exclude)README.md')"
since_start_fixed="$(git diff --name-only "$start" HEAD -- CLAUDE.md Docs/Stage0/evidence/M0-runbook/sessions.md Docs/Licenses)"
since_start_hist="$(git diff --name-status "$start" HEAD -- Docs/Stage0/evidence | grep . | grep -v -E $'^A\tDocs/Stage0/evidence/M0-DeviceA/' || true)"
{
  echo "-- 1d. since ${start:0:8} (the update's start): outside Docs/ and README.md $( [[ -z "$since_start_outside" ]] && echo "nothing changed" || echo "PROBLEM: $since_start_outside"); CLAUDE.md, the session log and the license inventory $( [[ -z "$since_start_fixed" ]] && echo "unchanged" || echo "PROBLEM, changed: $since_start_fixed"); under Docs/Stage0/evidence $( [[ -z "$since_start_hist" ]] && echo "only files added under Docs/Stage0/evidence/M0-DeviceA/" || echo "PROBLEM, also: $since_start_hist")"
} >> "$log"
[[ -n "$since_start_outside" || -n "$since_start_fixed" || -n "$since_start_hist" ]] && status=1
ancestor=no; git merge-base --is-ancestor "$run" HEAD && ancestor=yes
since_run="$(git diff --name-only "$run" HEAD -- Spikes Scripts Contracts Fixtures Apps Packages .github)"
dropin_status=0
bash "$da/commands/dropin-paths.sh" "$scratch/dropin-paths.log" > /dev/null 2>&1 || dropin_status=$?
{
  echo "-- 1e. ${run:0:8}, the commit of the drop-in's run, is an ancestor of HEAD: $ancestor"
  echo "   code, scripts, contracts, fixtures and the workflow changed since ${run:0:8}: $( [[ -z "$since_run" ]] && echo "none, so the run stands for HEAD's code" || echo "PROBLEM: $since_run")"
  echo "   the drop-in's own paths, and what the merge of m0-decisions brings under them ($da/commands/dropin-paths.sh, the third fix's, unchanged; exit $dropin_status; this fix's logged run of it: $here/checks/dropin-paths.log):"
  sed -n '/^== 2/,$p' "$scratch/dropin-paths.log" | grep -v -E '^$' | sed 's/^/   /'
} >> "$log"
[[ "$ancestor" != yes || -n "$since_run" || "$dropin_status" != 0 ]] && status=1
lists_before="$(git diff --name-only "$run" "$start" -- Docs/Stage0/device-checklists)"
sittings="$(python3 -I - Docs/Stage0/evidence/M0-runbook/sessions.md <<'PY'
import sys
rows = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith("| ")][2:]
dated, owner = [], []
for r in rows:
    cells = [c.strip() for c in r.strip()[1:-1].split("|")]
    if len(cells) >= 4 and cells[2]:
        dated.append(cells[0])
        if not cells[3].startswith("agent"):
            owner.append(cells[0])
print(f"{len(rows)} rows; dated: {len(dated)} ({'; '.join(dated)}); dated and not an agent's: {len(owner)}"
      + (f" ({'; '.join(owner)})" if owner else ""))
PY
)"
{
  echo "-- 1f. the checklists: from ${run:0:8} to ${start:0:8}: $( [[ -z "$lists_before" ]] && echo "unchanged" || echo "PROBLEM: $lists_before"); since ${fixC:0:8}: one line added to the G0.5 recovery checklist, wording only (1b)"
  echo "   the session log at HEAD (unchanged since ${start:0:8}: 1d), whose dated rows are all agents' on this branch: $sittings"
} >> "$log"
[[ -n "$lists_before" ]] && status=1
[[ "$sittings" == *"dated and not an agent's: 0" ]] || { echo "   PROBLEM: a sitting of the owner's is recorded on this branch" >> "$log"; status=1; }
dep_logs="$(git diff --name-only "$base" HEAD -- Docs/Stage0/evidence/M0-dependencies/linkage.log Docs/Stage0/evidence/M0-dependencies/resolve-locks.log)"
{
  echo "-- 1g. the committed logs of resolve-locks.sh and linkage.sh since ${base:0:8}: $( [[ -z "$dep_logs" ]] && echo "unchanged" || echo "PROBLEM, changed: $dep_logs")"
  echo "   a run under Xcode 27.1 (Docs/Stage0/evidence/M0-dependencies/xcode-27.1/) on this branch: $( [[ -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && echo "PROBLEM, present: the records call it pending" || echo "absent, as the records say (the agent run on m0-exit-prep makes it: pending)")"
} >> "$log"
[[ -n "$dep_logs" || -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && status=1
trees="$root/$scratch/trees"
mkdir -p "$trees/base" "$trees/start" "$trees/head" "$trees/prev" "$trees/merged" "$trees/reviewed" "$trees/fixA" "$trees/fixB" "$trees/fixC"
git archive "$base" | tar -x -C "$trees/base"
git archive "$start" | tar -x -C "$trees/start"
git archive HEAD | tar -x -C "$trees/head"
git archive "$prev" | tar -x -C "$trees/prev"
git archive "$mergeR" | tar -x -C "$trees/merged"
git archive "$reviewed" | tar -x -C "$trees/reviewed"
git archive "$fixA" | tar -x -C "$trees/fixA"
git archive "$fixB" | tar -x -C "$trees/fixB"
git archive "$fixC" | tar -x -C "$trees/fixC"
bt_status=0
python3 -I "$acc/commands/branch-texts.py" "$root" > "$scratch/branch-texts.out" 2>&1 || bt_status=$?
bt_rev=0
python3 -I "$acc/commands/branch-texts.py" "$root" "$trees/reviewed" > "$scratch/branch-texts-reviewed.out" 2>&1 || bt_rev=$?
bt_fixA=0
python3 -I "$acc/commands/branch-texts.py" "$root" "$trees/fixA" > "$scratch/branch-texts-fixA.out" 2>&1 || bt_fixA=$?
fails_of() { grep -E '^FAIL ' "$1" | sed -E 's/^FAIL ([a-z]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//'; }
{
  echo "-- 1h. branches and the sessions' checkout, read-only (nothing is fetched), judged against the owner's instructions ($acc/commands/branch-texts.py, the second fix's, unchanged):"
  echo "   main: $(git rev-parse main); origin/main: $(git rev-parse origin/main)"
  echo "   m0-sessions: $(git rev-parse m0-sessions); HEAD descends from ${fixC:0:8}: $(git merge-base --is-ancestor "$fixC" HEAD && echo yes || echo NO)"
  echo "   Spikes/G05-Recovery/LockHarness/project.yml at HEAD: $(git cat-file -e HEAD:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent)"
  echo "   on HEAD's texts: it must pass"
  sed 's/^/     /' "$scratch/branch-texts.out"
  echo "   exit: $bt_status"
  echo "   its control on the tree of ${reviewed:0:8}, which the findings read: it must fail behind, merged, checkout and sittings; it fails: $(fails_of "$scratch/branch-texts-reviewed.out") (exit $bt_rev)"
  grep -E '^FAIL |^     ' "$scratch/branch-texts-reviewed.out" | cut -c1-260 | sed 's/^/     /'
  echo "   its control on the tree of ${fixA:0:8}, the second fix's start: it must fail exactly sittings; it fails: $(fails_of "$scratch/branch-texts-fixA.out") (exit $bt_fixA)"
  grep -E '^FAIL |^     ' "$scratch/branch-texts-fixA.out" | cut -c1-260 | sed 's/^/     /'
} >> "$log"
(( bt_status != 0 )) && status=1
if [[ "$bt_rev" == 1 && "$(fails_of "$scratch/branch-texts-reviewed.out")" == "behind merged checkout sittings" \
      && "$bt_fixA" == 1 && "$(fails_of "$scratch/branch-texts-fixA.out")" == "sittings" ]]; then
  echo "   as required: on HEAD it passes; on ${reviewed:0:8}'s tree its four rules fail, on ${fixA:0:8}'s exactly sittings" >> "$log"
else
  echo "   NOT as required" >> "$log"; status=1
fi
merges_status=0
bash "$here/commands/merges.sh" "$scratch/merges.log" > /dev/null 2>&1 || merges_status=$?
{
  echo "-- 1i. the two merges m0-sessions waits for, computed and not made ($here/commands/merges.sh; exit $merges_status; this fix's logged run of it: $here/checks/merges.log):"
  grep -v -E '^$|^command:|^date:' "$scratch/merges.log" | sed 's/^/   /'
} >> "$log"
(( merges_status != 0 )) && status=1
{
  echo
  echo "== 2. Git LFS state"
  echo "git config --show-origin --get-regexp 'filter\\.lfs|lfs\\.':"
  git config --show-origin --get-regexp 'filter\.lfs|lfs\.' || echo "(no match)"
  git lfs version
  echo "files tracked by LFS (git lfs ls-files): $(git lfs ls-files | wc -l | tr -d ' '); of them still pointer files in the working tree: $(git lfs ls-files | awk '$2 == "-"' | wc -l | tr -d ' ')"
} >> "$log" 2>&1
git lfs ls-files -l "$base" | sort > "$scratch/lfs-base.txt"
git lfs ls-files -l HEAD | sort > "$scratch/lfs-head.txt"
if cmp -s "$scratch/lfs-base.txt" "$scratch/lfs-head.txt"; then
  echo "LFS files (object and path, git lfs ls-files -l) at HEAD and at $base: identical, $(wc -l < "$scratch/lfs-head.txt" | tr -d ' ') each: no LFS object added" >> "$log"
else
  { echo "LFS files at HEAD and at $base differ:"; diff "$scratch/lfs-base.txt" "$scratch/lfs-head.txt" | head -n 20; } >> "$log"
  status=1
fi
{
  echo
  echo "== 3. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log"
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
neg="$scratch/gate-negative"
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
{
  echo
  echo "== 4. The documents' own checks"
  echo "-- the second fix's amendments checker ($acc/commands/check-amendments.py), the newest: it must pass"
} >> "$log"
amend_status=0
python3 -I "$acc/commands/check-amendments.py" > "$scratch/amend.out" 2>&1 || amend_status=$?
{ grep -E '^FAIL |^summary:' "$scratch/amend.out"; echo "exit: $amend_status"; } >> "$log"
(( amend_status != 0 )) && status=1
before_mut="$(git status --porcelain | wc -l | tr -d ' ')"
mut_status=0
python3 -I "$acc/commands/mutation-checks.py" > "$scratch/mutations.out" 2>&1 || mut_status=$?
after_mut="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "-- its mutations ($acc/commands/mutation-checks.py): each of the 70 must make the checker fail its guarding check, the tree restored"
  tail -n 2 "$scratch/mutations.out" | sed 's/^/   /'
  echo "exit: $mut_status; uncommitted paths before and after: $before_mut, $after_mut"
} >> "$log"
(( mut_status != 0 )) && status=1
grep -q '^summary: 70 mutations, 70 caught, 0 missed$' "$scratch/mutations.out" || { echo "   PROBLEM: not 70 of 70 caught" >> "$log"; status=1; }
[[ "$before_mut" == "$after_mut" ]] || { echo "   PROBLEM: the mutations left the tree changed" >> "$log"; status=1; }
rp_status=0
python3 -I "$devicea/commands/check-amendments.py" > "$scratch/amend-records.out" 2>&1 || rp_status=$?
rp_exact=0
python3 -I -c '
import sys
fails = [line[5:] for line in open(sys.argv[1], encoding="utf-8").read().splitlines() if line.startswith("FAIL ")]
want = ("draft 0.8 as revised on 24 October 2026: the product owner'"'"'s decision on device A (the iPhone 13 mini; the A13 "
        "floor left for M8) is recorded wherever the plan and this document state device A, and the statements it made "
        "stale are gone from the plan before Appendix D: lacks, in Appendix D'"'"'s item of 24 October 2026: No budget, "
        "scope or other decision changed. Agent-written; not reviewed.*; lacks, in the draft 0.8 entry'"'"'s review note: "
        "which has not been reviewed (since 24 October 2026 the item before the last: the last records the product "
        "owner'"'"'s decision of that day on device A, and has not been reviewed either)")
sys.exit(0 if fails == [want] else 1)
' "$scratch/amend-records.out" || rp_exact=1
{
  echo "-- the records part's amendments checker ($devicea/commands/check-amendments.py): it must fail exactly its check 10k, on exactly the two review-status texts the second fix replaced in Appendix D, as on the second fix"
  grep -E '^FAIL |^summary:' "$scratch/amend-records.out" | cut -c1-700 | sed 's/^/   /'
  echo "exit: $rp_status; $( [[ $rp_status == 1 && $rp_exact == 0 ]] && echo "as required: exactly that check, on exactly those texts" || echo "NOT as required")"
} >> "$log"
[[ $rp_status == 1 && $rp_exact == 0 ]] || status=1
prev_status=0
python3 -I "$decisions/followup/round-2/commands/check-amendments.py" > "$scratch/amend-prev.out" 2>&1 || prev_status=$?
exact=0
python3 -I -c '
import sys
fails = [line[5:] for line in open(sys.argv[1], encoding="utf-8").read().splitlines() if line.startswith("FAIL ")]
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
' "$scratch/amend-prev.out" || exact=1
{
  echo "-- its control: the follow-up's fix's checker ($decisions/followup/round-2/commands/check-amendments.py) must fail on exactly the three checks whose anchors the records part replaced"
  grep -E '^FAIL |^summary:' "$scratch/amend-prev.out" | cut -c1-200 | sed 's/^/   /'
  echo "exit: $prev_status; $( [[ $prev_status == 1 && $exact == 0 ]] && echo "as required: exactly those three" || echo "NOT as required")"
} >> "$log"
[[ $prev_status == 1 && $exact == 0 ]] || status=1
rec_status=0
python3 -I "$devicea/commands/check-records.py" "$root" > "$scratch/records.out" 2>&1 || rec_status=$?
rec_control="$(python3 -I "$devicea/commands/check-records.py" "$trees/start" 2>&1)"
rec_exact=0
python3 -I -c '
import sys
fails = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith("FAIL ")]
want = ("FAIL the ADR index: its status column dated 24 October 2026, D-1 decided again, rows 0001-0013 on device A "
        "(lacks: | ADR | Title | Status (24 October 2026) | Owner during Stage 0 |)")
sys.exit(0 if fails == [want] else 1)
' "$scratch/records.out" || rec_exact=1
{
  echo "-- the records part's check of the ADRs, the index, the reports and the integration log ($devicea/commands/check-records.py): it must fail exactly its check of the ADR index, whose status column the first fix dated 26 October 2026, as before"
  grep -E '^FAIL |^summary' "$scratch/records.out" | cut -c1-300 | sed 's/^/   /'
  echo "exit: $rec_status"
} >> "$log"
if [[ "$rec_status" == 1 && "$rec_exact" == 0 ]]; then
  echo "   as required: exactly that check" >> "$log"
else
  echo "   NOT as required: exactly its check of the ADR index must fail" >> "$log"; status=1
fi
{
  echo "   its control on the tree of ${start:0:8}: it must fail every check but the one on the G0.6 rows' statuses (17 of 18)"
  printf '%s\n' "$rec_control" | grep -E '^(PASS|summary)' | sed 's/^/   /'
} >> "$log"
if [[ "$(printf '%s\n' "$rec_control" | grep -c '^FAIL ')" == 17 ]] \
   && [[ "$(printf '%s\n' "$rec_control" | grep '^PASS ')" == "PASS G0.6 report: the three rows' statuses unchanged" ]]; then
  echo "   as required: 17 failed checks, and only the statuses check passing" >> "$log"
else
  echo "   NOT as required" >> "$log"; status=1
fi
content_status=0
python3 -I "$instr/commands/runbook-content-check.py" "$root" > "$scratch/content.out" 2>&1 || content_status=$?
{
  echo "-- the instructions part's runbook content check ($instr/commands/runbook-content-check.py): it must pass"
  grep -E '\.md: [0-9]+ steps|NOT_CARRIED:|in its gate.s checklist|source fragments|RUNBOOK_OWN:|^result:' "$scratch/content.out"
  echo "exit: $content_status"
} >> "$log"
(( content_status != 0 )) && status=1
old_status=0
python3 -I "$decisions/assembly/commands/runbook-content-check.py" "$root" > "$scratch/content-old.out" 2>&1 || old_status=$?
old_problems="$(grep -E '^  MISSING |^  UNLISTED |^PROBLEM ' "$scratch/content-old.out" | sed -e 's/^ *//' -e 's/at offset [0-9]* /at offset N /')"
old_expected="UNLISTED text at offset N (any checklist): 13 mini only (Recommended)
UNLISTED text at offset N (any checklist): iphone 11 pro seems to be no longer charging. i do have a 13 mini that is still working, so update the plan. even better from a screen size.
PROBLEM stale RUNBOOK_OWN entry (no longer in the header or Sections 1-7): is an iPhone 11 Pro: the product owner chose the iPhone 11 family on 22 October 2026"
{
  echo "-- the decisions round's assembly's content check ($decisions/assembly/commands/runbook-content-check.py): it must report exactly the three texts the instructions part changed, as before"
  printf '%s\n' "$old_problems" | sed 's/^/   /'
  echo "exit: $old_status"
} >> "$log"
if [[ "$old_status" == 1 && "$old_problems" == "$old_expected" ]]; then
  echo "   as required: exactly those three" >> "$log"
else
  echo "   NOT as required: exactly the three texts the instructions part changed" >> "$log"; status=1
fi
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > "$scratch/coverage.out" 2>&1 || cov_status=$?
{
  echo "-- the runbook's step coverage ($evidence/final-fix/commands/runbook-coverage.py): it must pass"
  tail -n 1 "$scratch/coverage.out"
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base, on $reviewed, on $fixA, on $fixB, on $fixC and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$trees/check.py"
for side in base reviewed fixA fixB fixC head; do
  (cd "$trees/$side" && python3 -I "$trees/check.py" > "$trees/$side.out" 2>&1); echo "$?" > "$trees/$side.status"
done
for side in base reviewed fixA fixB fixC head; do
  tail -n +2 "$trees/$side.out" > "$trees/$side.body"
done
{
  echo "   $base: exit $(cat "$trees/base.status"); $(tail -n 1 "$trees/base.out")"
  echo "   $reviewed: exit $(cat "$trees/reviewed.status"); $(tail -n 1 "$trees/reviewed.out")"
  echo "   $fixA: exit $(cat "$trees/fixA.status"); $(tail -n 1 "$trees/fixA.out")"
  echo "   $fixB: exit $(cat "$trees/fixB.status"); $(tail -n 1 "$trees/fixB.out")"
  echo "   $fixC: exit $(cat "$trees/fixC.status"); $(tail -n 1 "$trees/fixC.out")"
  echo "   HEAD: exit $(cat "$trees/head.status"); $(tail -n 1 "$trees/head.out")"
} >> "$log"
changed_cct="$(diff "$trees/base.body" "$trees/head.body" | grep -E '^> C[0-9]+ ' | sed -E 's/^> (C[0-9]+) +([A-Z]+|ok) +x([0-9]+) ([^:]+):.*/\1 \2 \3 \4/' | sort)"
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
reviewed_diff="$(diff "$trees/reviewed.body" "$trees/head.body" | grep -E '^[<>] ' || true)"
fixA_diff="$(diff "$trees/fixA.body" "$trees/head.body" | grep -E '^[<>] ' || true)"
fixB_diff="$(diff "$trees/fixB.body" "$trees/head.body" | grep -E '^[<>] ' || true)"
fixC_diff="$(diff "$trees/fixC.body" "$trees/head.body" | grep -E '^[<>] ' || true)"
if [[ "$changed_cct" == "$expected" && "$(cat "$trees/base.status")" == 1 && "$(cat "$trees/head.status")" == 1 ]] \
   && [[ "$(diff "$trees/base.body" "$trees/head.body" | grep -c -E '^< ')" == 10 ]] && [[ -z "$reviewed_diff" && -z "$fixA_diff" && -z "$fixB_diff" && -z "$fixC_diff" ]]; then
  echo "   as required: from ${base:0:8} to HEAD the nine texts of the corrections the decisions round applied, found before and missing after, and the summary line, nothing else; from ${reviewed:0:8}, ${fixA:0:8}, ${fixB:0:8} or ${fixC:0:8} to HEAD no line differs" >> "$log"
else
  { echo "   NOT as required: expected exactly the nine applied corrections' texts to change from ${base:0:8}, and nothing from ${reviewed:0:8}, ${fixA:0:8}, ${fixB:0:8} or ${fixC:0:8}:"; printf '%s\n' "$reviewed_diff" "$fixA_diff" "$fixB_diff" "$fixC_diff" | sed 's/^/   /'; } >> "$log"
  status=1
fi
passing() {  # label, command...: an earlier check that reads no text this fix changed must pass
  local label="$1" code=0; shift
  "$@" > "$scratch/pass.out" 2>&1 || code=$?
  { echo "-- $label: it must pass"; tail -n 1 "$scratch/pass.out" | cut -c1-400 | sed 's/^/   /'; echo "exit: $code"; } >> "$log"
  (( code != 0 )) && status=1
}
passing "the follow-up's recheck of the second review's twelve answered findings and HON-11 ($decisions/followup/commands/recheck-review2.py)" \
  python3 -I "$decisions/followup/commands/recheck-review2.py" "$root"
passing "the third fix's moved history notes ($decisions/followup/round-4/commands/moved-notes.py)" \
  python3 -I "$decisions/followup/round-4/commands/moved-notes.py" "$root"
passing "the fourth fix's moved texts ($decisions/followup/round-5/commands/moved-notes.py)" \
  python3 -I "$decisions/followup/round-5/commands/moved-notes.py" "$root"
passing "the record's check of the run's facts ($decisions/unlocked-record/commands/check-run.py)" \
  python3 -I "$decisions/unlocked-record/commands/check-run.py" "$root"
passing "the fix's check of the run's facts ($decisions/unlocked-record/round-2/commands/check-run.py)" \
  python3 -I "$decisions/unlocked-record/round-2/commands/check-run.py" "$root"
run_control=0
python3 -I "$decisions/unlocked-record/round-2/commands/check-run.py" "$root" "$decisions/assembly/dropin-clean" > "$scratch/run-control.out" 2>&1 || run_control=$?
if [[ "$run_control" == 1 ]] && grep -q '^PROBLEM the screen unlocked at the start (ioreg)' "$scratch/run-control.out" \
   && grep -q "^PROBLEM the guard's line: row 10 evidence present" "$scratch/run-control.out"; then
  echo "   its control, on the decisions round's assembly run with the screen locked: fails, as required, naming the locked screen and the missing row-10 line" >> "$log"
else
  echo "   NOT as required: its control must fail on the locked screen and the missing row-10 line" >> "$log"; status=1
fi
passing "the fix's check of its review's cited lines ($decisions/unlocked-record/round-2/commands/finding-lines.py), at 91c3b46a" \
  python3 -I "$decisions/unlocked-record/round-2/commands/finding-lines.py" "$root"
passing "the second fix's recheck of UNL2-01 to UNL2-03 and of the fix's review status ($decisions/unlocked-record/round-3/commands/recheck-unl2.py), whose sweeps read every Markdown file, this fix's among them" \
  python3 -I "$decisions/unlocked-record/round-3/commands/recheck-unl2.py" "$root"
unl2_control=0
python3 -I "$decisions/unlocked-record/round-3/commands/recheck-unl2.py" "$trees/prev" > "$scratch/unl2-control.out" 2>&1 || unl2_control=$?
reported="$(grep -c -E '^PROBLEM +(UNL2-0[1-3]|review):' "$scratch/unl2-control.out")"
if [[ "$unl2_control" == 1 && "$reported" == 4 ]]; then
  echo "   its control on the tree of ${prev:0:8}: all four reported, as required" >> "$log"
else
  echo "   NOT as required: its control on the tree of ${prev:0:8} must report all four (reported $reported)" >> "$log"; status=1
fi
passing "the second fix's check of its review's cited lines ($decisions/unlocked-record/round-3/commands/finding-lines.py), at ${prev:0:8}" \
  python3 -I "$decisions/unlocked-record/round-3/commands/finding-lines.py" "$root"
lines_control=0
python3 -I "$decisions/unlocked-record/round-3/commands/finding-lines.py" "$root" 91c3b46a1e034563ca9a6df9a77d5c736d202303 > "$scratch/lines-control.out" 2>&1 || lines_control=$?
if [[ "$lines_control" == 1 ]]; then
  echo "   its control at 91c3b46a: fails, as required" >> "$log"
else
  echo "   NOT as required: its control at 91c3b46a must fail" >> "$log"; status=1
fi
echo "-- the six earlier rechecks that read texts the update or its fixes changed: each must report exactly the lines of $acc/commands/expected-rechecks.txt, the second fix's list, unchanged (which says why; this fix kept the State line, the opening within its 600 words, 800 with the State line, and item 1's steps within their 400, which recheck-unl, recheck-own5 and recheck-own4 measure)" >> "$log"
: > "$scratch/rechecks.actual"
for pair in "recheck-review4:$decisions/followup/round-2/commands/recheck-review4.py" \
            "recheck-hon4:$decisions/followup/round-3/commands/recheck-hon4.py" \
            "recheck-own4:$decisions/followup/round-4/commands/recheck-own4.py" \
            "recheck-own5:$decisions/followup/round-5/commands/recheck-own5.py" \
            "recheck-unlocked:$decisions/unlocked-record/commands/recheck-unlocked.py" \
            "recheck-unl:$decisions/unlocked-record/round-2/commands/recheck-unl.py"; do
  name="${pair%%:*}"; file="${pair#*:}"; code=0
  python3 -I "$file" "$root" > "$scratch/$name.out" 2>&1 || code=$?
  grep '^PROBLEM' "$scratch/$name.out" | sed "s/^/$name	/" >> "$scratch/rechecks.actual"
  echo "   $name ($file): exit $code; $(tail -n 1 "$scratch/$name.out" | cut -c1-200)" >> "$log"
  [[ "$code" == 1 ]] || status=1
done
grep -v '^#' "$acc/commands/expected-rechecks.txt" > "$scratch/rechecks.expected"
if cmp -s "$scratch/rechecks.expected" "$scratch/rechecks.actual"; then
  echo "   as required: exactly the $(wc -l < "$scratch/rechecks.expected" | tr -d ' ') expected lines" >> "$log"
else
  { echo "   NOT as required: the reports differ from the expected lines:"; diff "$scratch/rechecks.expected" "$scratch/rechecks.actual" | cut -c1-400 | sed 's/^/   /'; } >> "$log"
  status=1
fi
ins_status=0
python3 -I "$instr/commands/recheck-instructions.py" "$root" > "$scratch/instr.out" 2>&1 || ins_status=$?
ins_exact=0
python3 -I -c '
import sys
problems = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith("PROBLEM")]
floor = ("PROBLEM   floor: the 13 mini lays out at the 11 Pro'"'"'s 375 × 812 pt drawn about 8% smaller; its figures that "
         "depend on the chip are its own, never the A13'"'"'s; no budget changes; M8 measures the A13 floor; D-2 (a) stands "
         "with a narrower form of (b)'"'"'s exception (the runbook'"'"'s 1.1 lacks: in M8, the Section 19.2 budgets are "
         "measured on an A13 iPhone, your iPhone 11 if it still works then, or a borrowed or bought one)")
run1 = ("(M0-gate.md item 1 lacks: 3. **Done: `m0-decisions` merged into `main`** by pull request #6 on 24 October 2026 "
        "(`96bdc7e9`); the runbook'"'"'s 0.3 lacks: 3. Done: pull request #6 merged `m0-decisions` into `main` on 24 October "
        "2026 (`96bdc7e9`))")
ok = (len(problems) == 2 and problems[0] == floor and problems[1].startswith("PROBLEM   run-1:")
      and problems[1].endswith(run1))
sys.exit(0 if ok else 1)
' "$scratch/instr.out" || ins_exact=1
{
  echo "-- the instructions part's recheck ($instr/commands/recheck-instructions.py): it must report exactly its floor item, as before, and its item run-1, on exactly the two texts of pull request #6's date that this fix changed (OWN-DA-06), by design"
  cut -c1-600 "$scratch/instr.out" | sed 's/^/   /'
  echo "exit: $ins_status"
} >> "$log"
if [[ "$ins_status" == 1 && "$ins_exact" == 0 ]]; then
  echo "   as required: exactly those two items, on exactly those texts" >> "$log"
else
  echo "   NOT as required" >> "$log"; status=1
fi
asm_status=0
python3 -I "$asm/commands/recheck-assembly.py" "$root" > "$scratch/asm.out" 2>&1 || asm_status=$?
asm_items="$(grep '^PROBLEM' "$scratch/asm.out" | sed -E 's/^PROBLEM +([a-zA-Z0-9.-]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
asm_exact=0
python3 -I -c '
import sys
problems = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith("PROBLEM")]
agree = ("with no memory size (ADR-0001 lacks: ADR-0013 (it does not apply to G0.6'"'"'s steps on device A, which depend on "
         "the screen))")
state = ("named where the update is described (README.md lacks: were made on the branch `m0-decisions`, which pull "
         "request #6 merged into main on 24 October 2026 (`96bdc7e9`); since then the M0 work and the device sessions use "
         "the branch `m0-sessions`, made from main that day, and nothing else reaches main before the M0 exit unless the "
         "product owner decides otherwise; the runbook'"'"'s Who wrote it lacks: nor has the update of 24 October 2026, nor "
         "its assembly)")
run1 = ("(M0-gate.md item 1 lacks: 3. **Done: `m0-decisions` merged into `main`** by pull request #6 on 24 October 2026 "
        "(`96bdc7e9`); the runbook'"'"'s 0.3 lacks: 3. Done: pull request #6 merged `m0-decisions` into `main` on 24 October "
        "2026 (`96bdc7e9`))")
ok = (len(problems) == 3 and problems[0].startswith("PROBLEM   run-1:") and problems[0].endswith(run1)
      and problems[1].startswith("PROBLEM   agree:") and problems[1].endswith(agree)
      and problems[2].startswith("PROBLEM   state:") and problems[2].endswith(state))
sys.exit(0 if ok else 1)
' "$scratch/asm.out" || asm_exact=1
asm_start=0
python3 -I "$asm/commands/recheck-assembly.py" "$trees/start" > "$scratch/asm-start.out" 2>&1 || asm_start=$?
asm_merged=0
python3 -I "$asm/commands/recheck-assembly.py" "$trees/merged" > "$scratch/asm-merged.out" 2>&1 || asm_merged=$?
{
  echo "-- the assembly's recheck ($asm/commands/recheck-assembly.py): it must report exactly run-1 (the two texts of pull request #6's date that this fix changed, OWN-DA-06, by design), agree (ADR-0001's clause on ADR-0013, which FID-DA-05 narrowed) and state (README.md's sentence on the branches and the runbook's Who wrote it, which FID-DA-01 and the review changed), the last two as before"
  cut -c1-600 "$scratch/asm.out" | sed 's/^/   /'
  echo "exit: $asm_status; reported: $asm_items"
} >> "$log"
if [[ "$asm_status" == 1 && "$asm_items" == "run-1 agree state" && "$asm_exact" == 0 ]]; then
  echo "   as required: exactly those three items, on exactly those texts" >> "$log"
else
  echo "   NOT as required: exactly run-1, agree and state, on those texts" >> "$log"; status=1
fi
{
  echo "   its control on the tree of ${start:0:8}: $(grep -c '^PROBLEM' "$scratch/asm-start.out") of 9 reported (exit $asm_start); on the tree of ${mergeR:0:8}: $(grep '^PROBLEM' "$scratch/asm-merged.out" | sed -E 's/^PROBLEM +([a-zA-Z0-9.-]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//') (exit $asm_merged)"
} >> "$log"
if [[ "$asm_start" == 1 && "$(grep -c '^PROBLEM' "$scratch/asm-start.out")" == 9 \
      && "$(grep '^PROBLEM' "$scratch/asm-merged.out" | sed -E 's/^PROBLEM +([a-zA-Z0-9.-]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')" == "floor step-0.8 agree state log" ]]; then
  echo "   as required: all nine on ${start:0:8}'s tree, and floor, step-0.8, agree, state and log on ${mergeR:0:8}'s" >> "$log"
else
  echo "   NOT as required" >> "$log"; status=1
fi
lines_status=0
python3 -I "$first/commands/finding-lines.py" "$root" > "$scratch/finding-lines-first.out" 2>&1 || lines_status=$?
lines_head=0
python3 -I "$first/commands/finding-lines.py" "$root" HEAD > "$scratch/finding-lines-first-head.out" 2>&1 || lines_head=$?
{
  echo "-- the first fix's check of the review's cited lines ($first/commands/finding-lines.py), at ${reviewed:0:8}: every one must hold"
  tail -n 1 "$scratch/finding-lines-first.out" | sed 's/^/   /'
  echo "exit: $lines_status"
  echo "   its control at HEAD, where the lines the first fix changed no longer hold the cited text: $(tail -n 1 "$scratch/finding-lines-first-head.out") (exit $lines_head)"
} >> "$log"
(( lines_status != 0 )) && status=1
[[ "$lines_head" == 1 ]] || { echo "   NOT as required: its control at HEAD must fail" >> "$log"; status=1; }
f1_status=0
python3 -I "$first/commands/recheck-fix1.py" "$root" > "$scratch/fix1.out" 2>&1 || f1_status=$?
f1_reviewed=0
python3 -I "$first/commands/recheck-fix1.py" "$trees/reviewed" > "$scratch/fix1-reviewed.out" 2>&1 || f1_reviewed=$?
f1_exact=0
python3 -I -c '
import sys
problems = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith("PROBLEM")]
ok = (len(problems) == 3
      and problems[0].startswith("PROBLEM   checkout:")
      and problems[0].endswith("(the runbook'"'"'s 0.3, step 1 lacks: so 0.8'"'"'s check from `9cdb0a02` then lists it and "
                               "0.8 runs again after it)")
      and problems[1].startswith("PROBLEM   step-0.8:")
      and problems[1].endswith("(the runbook'"'"'s 0.8 lacks: adds `Spikes/G05-Recovery/DeviceTests` under those paths: "
                               "after that merge the check from `9cdb0a02` lists it, and 0.8 runs again)")
      and problems[2].startswith("PROBLEM   review:")
      and problems[2].endswith("(the State line lacks: nor has the update'"'"'s fix (Section 6.2))"))
sys.exit(0 if ok else 1)
' "$scratch/fix1.out" || f1_exact=1
{
  echo "-- the first fix's recheck ($first/commands/recheck-fix1.py), on HEAD: it must report exactly its items checkout and step-0.8, each on exactly the text of 0.8 after the merge that the third fix changed (DA-07), and review, on exactly the State line's clause the second fix changed, as before (by design; the third fix's recheck and the second's assert the new texts)"
  cut -c1-400 "$scratch/fix1.out" | sed 's/^/   /'
  echo "exit: $f1_status"
  echo "-- its control on the tree of ${reviewed:0:8}, the commit the review read: all eight items must be reported"
  echo "   exit: $f1_reviewed; reported: $(grep -c '^PROBLEM' "$scratch/fix1-reviewed.out") of 8"
} >> "$log"
if [[ "$f1_status" == 1 && "$f1_exact" == 0 ]]; then
  echo "   as required: exactly those three items, on exactly those texts" >> "$log"
else
  echo "   NOT as required: exactly checkout, step-0.8 and review, on those texts" >> "$log"; status=1
fi
if [[ "$f1_reviewed" == 1 && "$(grep -c '^PROBLEM' "$scratch/fix1-reviewed.out")" == 8 ]]; then
  echo "   its control as required: all eight reported on ${reviewed:0:8}'s tree" >> "$log"
else
  echo "   NOT as required: all eight must be reported on ${reviewed:0:8}'s tree" >> "$log"; status=1
fi
acc_lines=0
python3 -I "$acc/commands/finding-lines.py" "$root" > "$scratch/finding-lines-acc.out" 2>&1 || acc_lines=$?
acc_lines_head=0
python3 -I "$acc/commands/finding-lines.py" "$root" HEAD > "$scratch/finding-lines-acc-head.out" 2>&1 || acc_lines_head=$?
{
  echo "-- the second fix's check of the accuracy findings' cited lines ($acc/commands/finding-lines.py), at ${reviewed:0:8}: every one must hold"
  tail -n 1 "$scratch/finding-lines-acc.out" | sed 's/^/   /'
  echo "exit: $acc_lines"
  echo "   its control at HEAD, where the lines the first two fixes changed no longer hold the cited text: $(tail -n 1 "$scratch/finding-lines-acc-head.out") (exit $acc_lines_head)"
} >> "$log"
(( acc_lines != 0 )) && status=1
[[ "$acc_lines_head" == 1 ]] || { echo "   NOT as required: its control at HEAD must fail" >> "$log"; status=1; }
acc_status=0
python3 -I "$acc/commands/recheck-acc.py" "$root" > "$scratch/acc.out" 2>&1 || acc_status=$?
acc_fixA=0
python3 -I "$acc/commands/recheck-acc.py" "$trees/fixA" > "$scratch/acc-fixA.out" 2>&1 || acc_fixA=$?
acc_items="$(grep '^PROBLEM' "$scratch/acc-fixA.out" | sed -E 's/^PROBLEM +([a-zA-Z0-9.-]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
{
  echo "-- the second fix's recheck ($acc/commands/recheck-acc.py), on HEAD: it must pass (this fix kept every text it asserts)"
  cut -c1-400 "$scratch/acc.out" | sed 's/^/   /'
  echo "exit: $acc_status"
  echo "-- its control on the tree of ${fixA:0:8}: every item but step-12 must be reported"
  echo "   exit: $acc_fixA; reported: $acc_items"
} >> "$log"
(( acc_status != 0 )) && status=1
if [[ "$acc_fixA" == 1 && "$acc_items" == "branch phones g03-times g04-17 release-notes review" ]]; then
  echo "   as required: the six items, all but step-12, reported on ${fixA:0:8}'s tree" >> "$log"
else
  echo "   NOT as required: every item but step-12 must be reported on ${fixA:0:8}'s tree" >> "$log"; status=1
fi
da_lines=0
python3 -I "$da/commands/finding-lines.py" "$root" > "$scratch/finding-lines-da.out" 2>&1 || da_lines=$?
da_lines_head=0
python3 -I "$da/commands/finding-lines.py" "$root" HEAD > "$scratch/finding-lines-da-head.out" 2>&1 || da_lines_head=$?
{
  echo "-- the third fix's check of the completeness findings' cited lines ($da/commands/finding-lines.py), at ${reviewed:0:8}: every one must hold"
  tail -n 1 "$scratch/finding-lines-da.out" | sed 's/^/   /'
  echo "exit: $da_lines"
  echo "   its control at HEAD, where the lines the first three fixes changed no longer hold the cited text: $(tail -n 1 "$scratch/finding-lines-da-head.out") (exit $da_lines_head)"
} >> "$log"
(( da_lines != 0 )) && status=1
[[ "$da_lines_head" == 1 ]] || { echo "   NOT as required: its control at HEAD must fail" >> "$log"; status=1; }
da_status=0
python3 -I "$da/commands/recheck-da.py" "$root" > "$scratch/da.out" 2>&1 || da_status=$?
da_fixB=0
python3 -I "$da/commands/recheck-da.py" "$trees/fixB" > "$scratch/da-fixB.out" 2>&1 || da_fixB=$?
da_items="$(grep '^PROBLEM' "$scratch/da-fixB.out" | sed -E 's/^PROBLEM +([a-zA-Z0-9.-]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
da_exact=0
python3 -I -c '
import sys
problems = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith("PROBLEM")]
want = ("(M0-gate.md Section 6.2'"'"'s row lacks: | integration log sections 29, 30 and 31 |; the runbook'"'"'s Who wrote it "
        "lacks: nor its third, of its completeness findings; human review pending)")
sys.exit(0 if len(problems) == 1 and problems[0].startswith("PROBLEM   review:") and problems[0].endswith(want) else 1)
' "$scratch/da.out" || da_exact=1
{
  echo "-- the third fix's recheck ($da/commands/recheck-da.py), on HEAD: it must report exactly its item review, on exactly the two texts that gave its fix as the last (Section 6.2's row, now with section 32, and the runbook's Who wrote it, now with the fourth fix), by design; this fix's recheck asserts the new texts"
  cut -c1-600 "$scratch/da.out" | sed 's/^/   /'
  echo "exit: $da_status"
  echo "-- its control on the tree of ${fixB:0:8}, the commit the third fix started from: every item but release-notes and step-12 must be reported, as before"
  echo "   exit: $da_fixB; reported: $da_items"
} >> "$log"
if [[ "$da_status" == 1 && "$da_exact" == 0 ]]; then
  echo "   as required: exactly that item, on exactly those texts" >> "$log"
else
  echo "   NOT as required: exactly its item review, on those texts" >> "$log"; status=1
fi
if [[ "$da_fixB" == 1 && "$da_items" == "branch ran log-rows adr14 step-1 dropin confirm review" ]]; then
  echo "   its control as required: the eight items, all but release-notes and step-12, reported on ${fixB:0:8}'s tree" >> "$log"
else
  echo "   NOT as required: every item but release-notes and step-12 must be reported on ${fixB:0:8}'s tree" >> "$log"; status=1
fi
own_lines=0
python3 -I "$here/commands/finding-lines.py" "$root" > "$scratch/finding-lines.out" 2>&1 || own_lines=$?
own_lines_head=0
python3 -I "$here/commands/finding-lines.py" "$root" HEAD > "$scratch/finding-lines-head.out" 2>&1 || own_lines_head=$?
{
  echo "-- this fix's check of the owner-readability findings' cited lines ($here/commands/finding-lines.py), at ${reviewed:0:8}: every one must hold"
  tail -n 1 "$scratch/finding-lines.out" | sed 's/^/   /'
  echo "exit: $own_lines"
  echo "   its control at HEAD, where the lines this fix or the first three changed no longer hold the cited text: $(tail -n 1 "$scratch/finding-lines-head.out") (exit $own_lines_head)"
} >> "$log"
(( own_lines != 0 )) && status=1
[[ "$own_lines_head" == 1 ]] || { echo "   NOT as required: its control at HEAD must fail" >> "$log"; status=1; }
mine_status=0
python3 -I "$here/commands/recheck-own.py" "$root" > "$scratch/mine.out" 2>&1 || mine_status=$?
mine_fixC=0
python3 -I "$here/commands/recheck-own.py" "$root" "$trees/fixC" > "$scratch/mine-fixC.out" 2>&1 || mine_fixC=$?
mine_items="$(grep '^PROBLEM' "$scratch/mine-fixC.out" | sed -E 's/^PROBLEM +([a-zA-Z0-9.-]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
{
  echo "-- this fix's recheck ($here/commands/recheck-own.py), on HEAD: it must pass"
  cut -c1-400 "$scratch/mine.out" | sed 's/^/   /'
  echo "exit: $mine_status"
  echo "-- its control on the tree of ${fixC:0:8}, the commit this fix started from: all ten items must be reported"
  cut -c1-200 "$scratch/mine-fixC.out" | sed 's/^/   /'
  echo "exit: $mine_fixC; reported: $mine_items"
} >> "$log"
(( mine_status != 0 )) && status=1
if [[ "$mine_fixC" == 1 && "$mine_items" == "checkout ran host confirm edits dates ios27 merge-where d01 review" ]]; then
  echo "   as required: all ten items reported on ${fixC:0:8}'s tree" >> "$log"
else
  echo "   NOT as required: all ten items must be reported on ${fixC:0:8}'s tree" >> "$log"; status=1
fi
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
rm -rf "$scratch"
exit $status
