#!/bin/bash
# Gate checks of the assembly of the update of 24 October 2026 (26 October 2026 on the build Mac's clock), which merged
# its two parts into m0-sessions: m0-sessions-instructions (1c69da4c; the owner's instructions) and m0-sessions-records
# (9a4c9810; the records of the device-A change), each made from m0-sessions at 6cede84a, merged in that order
# (25186d65, 5e455f70), then the assembly's own changes. Run on the commit that adds every other log of the assembly,
# with no uncommitted file. The successor, for the merged tree, of the instructions part's gate checks
# (Docs/Stage0/evidence/M0-DeviceA/instructions/commands/gate-checks.sh) and of the records part's runner
# (Docs/Stage0/evidence/M0-DeviceA/commands/run-checks.sh), whose parts it runs with the merged tree's expectations:
#   Docs/Stage0/evidence/M0-DeviceA/assembly/commands/gate-checks.sh <log>
# 1. What changed: since 6cede84a only the files the two parts own and the assembly's (README.md and
#    Docs/Stage0/evidence/M0-DeviceA/assembly/), nothing outside Docs/ but README.md, CLAUDE.md, the session log and the
#    license inventory unchanged; under Docs/Stage0/evidence only new files, all under Docs/Stage0/evidence/M0-DeviceA/
#    (the historical evidence untouched); the two merges as made (each part's files, and the merge commits' parents);
#    since 96bdc7e9, CLAUDE.md alone besides (5aec2518 and 6cede84a); 9cdb0a02 an ancestor, the code unchanged since it
#    and the drop-in's own paths unchanged (the instructions part's dropin-paths.sh); the checklists unchanged from
#    9cdb0a02 to 6cede84a and all eight changed since, while the session log records no sitting of the owner's; the
#    committed logs of resolve-locks.sh and linkage.sh unchanged and no run under Xcode 27.1; and, read-only, main,
#    origin/main, m0-sessions, m0-decisions and the two parts' branches (no fetch).
# 2. The Git LFS state, read-only, and the LFS files of HEAD against those of 4c73da57: the update adds no LFS file.
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the records it cites
#    (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py), with its negative control.
# 4. The documents' own checks, on the merged tree:
#    - the records part's amendments checker (Docs/Stage0/evidence/M0-DeviceA/commands/check-amendments.py), the newest:
#      it must pass; its 66 mutations must each be caught, the tree restored; and, as its control, the follow-up's
#      fix's checker must fail on exactly the three checks whose anchors the records part replaced;
#    - the records part's check of the ADRs, the index, the gate reports and the integration log (check-records.py): it
#      must pass, and, as its control, fail 17 of its 18 checks on the tree of 6cede84a (all but the G0.6 rows' statuses);
#    - the instructions part's runbook content check (instructions/commands/runbook-content-check.py): it must pass; and
#      the assembly's version, which it replaces, must report exactly the three texts that part changed;
#    - the step coverage check: it must pass;
#    - the correction-text check on 4c73da57, 6cede84a and HEAD: from 4c73da57 to HEAD exactly the nine texts of the
#      corrections the decisions round applied change, and from 6cede84a to HEAD nothing;
#    - the earlier rounds' rechecks: those that read no text the update changed must pass (with their controls); the six
#      that do must report exactly the 16 lines of expected-rechecks.txt beside this file (the instructions part's 14,
#      and the records part's FID4-04 and HON4-06);
#    - the instructions part's recheck (instructions/commands/recheck-instructions.py): it must report exactly its floor
#      item, on the runbook's text of M8's A13 phone that the assembly reworded as the records part asked, by design;
#    - this assembly's recheck (recheck-assembly.py beside this file): it must pass on HEAD; as its controls, report all
#      nine items on the tree of 6cede84a, and exactly floor, step-0.8, agree, state and log on the tree of 5e455f70,
#      the second merge, before the assembly's own changes.
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first; the
#    worktree's LFS files must be filled from the local store first: ../checks/lfs-checkout.log).
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G0.5 AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log, but for the mutations of part 4, each written to the working copy and restored from memory before
# the next. Exit status 1 if any part fails.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"  # six folders up: commands, assembly, M0-DeviceA, evidence, Stage0, Docs
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
here="$devicea/assembly"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e
merge6=96bdc7e996f99fcd2571ea983cc32a04076a5a07
start=6cede84a6f6ac610976b233d875e26dd89419dbd
prev=26530d4933c070c2c154a9116ef6f7fdd0415363
partI=1c69da4c475245e078e1c6c5cba81912d0ac6eb4
partR=9a4c98101130e2bbedf1bc39cebaa39ca801f3ce
mergeI=25186d65
mergeR=5e455f70
scratch=.build/scratch/devicea-assembly-gate
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
for c in "$start" "$partI" "$partR"; do
  git merge-base --is-ancestor "$c" HEAD || { echo "PROBLEM: HEAD does not descend from $c" >> "$log"; status=1; }
done
own_i='^(Docs/Stage0/M0-device-runbook\.md|Docs/Stage0/M0-gate\.md|Docs/Stage0/README\.md|Docs/Stage0/device-checklists/[^/]+\.md|Docs/Stage0/evidence/M0-DeviceA/instructions/.+)$'
own_r='^(Docs/Sylvia_v1_iOS_Implementation_Plan\.md|Docs/Stage0/M0-plan-amendments\.md|Docs/ADRs/[^/]+\.md|Docs/Stage0/G0[^/]*\.md|Docs/Stage0/integration-log\.md|Docs/Stage0/evidence/M0-DeviceA/(README\.md|inventory-records\.md|checks/.+|commands/.+|simulator/.+))$'
own_a='^(README\.md|Docs/Stage0/evidence/M0-DeviceA/assembly/.+)$'
changed="$(git diff --name-only "$start" HEAD)"
stray="$(printf '%s\n' "$changed" | grep -v -E "$own_i" | grep -v -E "$own_r" | grep -v -E "$own_a" | grep . || true)"
{
  echo "-- 1a. since ${start:0:8} (m0-sessions's head before the update): $(printf '%s\n' "$changed" | grep -c .) files:"
  echo "   the instructions part's: $(printf '%s\n' "$changed" | grep -c -E "$own_i") ($(printf '%s\n' "$changed" | grep -E "$own_i" | grep -c "^$instr/") of them its evidence); the documents:"
  printf '%s\n' "$changed" | grep -E "$own_i" | grep -v "^$instr/" | sed 's/^/     /'
  echo "   the records part's: $(printf '%s\n' "$changed" | grep -c -E "$own_r") ($(printf '%s\n' "$changed" | grep -E "$own_r" | grep -c "^$devicea/") of them its evidence); the documents:"
  printf '%s\n' "$changed" | grep -E "$own_r" | grep -v "^$devicea/" | sed 's/^/     /'
  echo "   the assembly's own: $(printf '%s\n' "$changed" | grep -c -E "$own_a"): README.md and $here/"
  if [[ -z "$stray" ]]; then echo "   no other file"; else echo "   PROBLEM: also $stray"; fi
} >> "$log"
[[ -n "$stray" ]] && status=1
outside="$(git diff --name-only "$start" HEAD -- . ':(exclude)Docs' ':(exclude)README.md')"
fixed="$(git diff --name-only "$start" HEAD -- CLAUDE.md Docs/Stage0/evidence/M0-runbook/sessions.md Docs/Licenses)"
{
  echo "-- 1b. outside Docs/ and README.md since ${start:0:8}: $( [[ -z "$outside" ]] && echo "nothing changed" || echo "PROBLEM, changed: $outside")"
  echo "   CLAUDE.md, the session log and the license inventory since ${start:0:8}: $( [[ -z "$fixed" ]] && echo "unchanged (CLAUDE.md's toolchain line and the session log's rows 1 and 8, asked of their owners, are left to them)" || echo "PROBLEM, changed: $fixed")"
} >> "$log"
[[ -n "$outside" || -n "$fixed" ]] && status=1
hist="$(git diff --name-status "$start" HEAD -- Docs/Stage0/evidence)"
hist_bad="$(printf '%s\n' "$hist" | grep . | grep -v -E $'^A\tDocs/Stage0/evidence/M0-DeviceA/' || true)"
{
  echo "-- 1c. the historical evidence: git diff --stat ${start:0:8} HEAD -- Docs/Stage0/evidence lists $(printf '%s\n' "$hist" | grep -c .) files, $( [[ -z "$hist_bad" ]] && echo "every one added (A) under Docs/Stage0/evidence/M0-DeviceA/: no earlier evidence file changed" || echo "PROBLEM, also: $hist_bad")"
  git diff --stat "$start" HEAD -- Docs/Stage0/evidence | tail -n 1 | sed 's/^/  /'
} >> "$log"
[[ -n "$hist_bad" ]] && status=1
# The two merges: each part's files and nothing else, and the merge commits' parents.
i_files="$(git diff --name-only "$start" "$partI")"
r_files="$(git diff --name-only "$start" "$partR")"
overlap="$(comm -12 <(printf '%s\n' "$i_files" | sort) <(printf '%s\n' "$r_files" | sort))"
after_i="$(git diff --name-only "$partI" "$mergeI")"
after_r_from_i="$(git diff --name-only "$mergeI" "$mergeR")"
{
  echo "-- 1d. the merges: the instructions part changed $(printf '%s\n' "$i_files" | grep -c .) files, the records part $(printf '%s\n' "$r_files" | grep -c .), $( [[ -z "$overlap" ]] && echo "none in common" || echo "PROBLEM, in common: $overlap")"
  echo "   $mergeI's parents: $(git rev-parse --short=8 "$mergeI^1") and $(git rev-parse --short=8 "$mergeI^2"); its tree against ${partI:0:8}'s: $( [[ -z "$after_i" ]] && echo "identical" || echo "PROBLEM, differs: $after_i")"
  echo "   $mergeR's parents: $(git rev-parse --short=8 "$mergeR^1") and $(git rev-parse --short=8 "$mergeR^2"); what it adds to $mergeI: $( [[ "$(printf '%s\n' "$after_r_from_i" | sort)" == "$(printf '%s\n' "$r_files" | sort)" ]] && echo "exactly the records part's files" || echo "PROBLEM, not exactly the records part's files")"
  echo "   since $mergeR, the assembly's own changes:"
  git diff --stat "$mergeR" HEAD | sed 's/^/     /'
} >> "$log"
[[ -n "$overlap" || -n "$after_i" ]] && status=1
[[ "$(git rev-parse --short=8 "$mergeI^1") $(git rev-parse --short=8 "$mergeI^2")" == "${start:0:8} ${partI:0:8}" ]] || { echo "   PROBLEM: $mergeI's parents" >> "$log"; status=1; }
[[ "$(git rev-parse --short=8 "$mergeR^1") $(git rev-parse --short=8 "$mergeR^2")" == "$mergeI ${partR:0:8}" ]] || { echo "   PROBLEM: $mergeR's parents" >> "$log"; status=1; }
[[ "$(printf '%s\n' "$after_r_from_i" | sort)" == "$(printf '%s\n' "$r_files" | sort)" ]] || status=1
since6="$(git diff --name-only "$merge6" "$start")"
{
  echo "-- 1e. from ${merge6:0:8} (pull request #6) to ${start:0:8}, before the update: $(printf '%s\n' "$since6" | tr '\n' ' ' | sed 's/ $//')"
  git log --format='   %h %s' "$merge6..$start"
} >> "$log"
[[ "$since6" == "CLAUDE.md" ]] || { echo "   PROBLEM: expected CLAUDE.md alone" >> "$log"; status=1; }
ancestor=no; git merge-base --is-ancestor "$run" HEAD && ancestor=yes
since_run="$(git diff --name-only "$run" HEAD -- Spikes Scripts Contracts Fixtures Apps Packages .github)"
dropin_status=0
bash "$instr/commands/dropin-paths.sh" "$scratch/dropin-paths.log" > /dev/null 2>&1 || dropin_status=$?
{
  echo "-- 1f. ${run:0:8}, the commit of the drop-in's run, is an ancestor of HEAD: $ancestor"
  echo "   code, scripts, contracts, fixtures and the workflow changed since ${run:0:8}: $( [[ -z "$since_run" ]] && echo "none, so the run stands for HEAD's code" || echo "PROBLEM: $since_run")"
  echo "   the drop-in's own paths ($instr/commands/dropin-paths.sh, exit $dropin_status; the assembly's logged run of it: $here/checks/dropin-paths.log):"
  sed -n '/^== 2/,$p' "$scratch/dropin-paths.log" | grep -v -E '^$' | sed 's/^/   /'
} >> "$log"
[[ "$ancestor" != yes || -n "$since_run" || "$dropin_status" != 0 ]] && status=1
lists_before="$(git diff --name-only "$run" "$start" -- Docs/Stage0/device-checklists)"
lists_now="$(git diff --name-only "$start" HEAD -- Docs/Stage0/device-checklists)"
lists_all="$(git ls-files Docs/Stage0/device-checklists | grep -E '\.md$')"
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
  echo "-- 1g. the checklists, which the rule for repeating a session names: from ${run:0:8} to ${start:0:8}: $( [[ -z "$lists_before" ]] && echo "unchanged" || echo "PROBLEM: $lists_before"); since ${start:0:8}, by the update: $(printf '%s\n' "$lists_now" | grep -c .) of the $(printf '%s\n' "$lists_all" | grep -c .) (device-A and branch lines; the assembly: a clause of G0.4's device-A note)"
  git diff --stat "$start" HEAD -- Docs/Stage0/device-checklists | sed 's/^/   /'
  echo "   the session log at HEAD (unchanged since ${start:0:8}: 1b), whose dated rows must all be agents': $sittings"
} >> "$log"
[[ -n "$lists_before" || "$lists_now" != "$lists_all" ]] && status=1
[[ "$sittings" == *"dated and not an agent's: 0" ]] || { echo "   PROBLEM: a sitting of the owner's is recorded" >> "$log"; status=1; }
dep_logs="$(git diff --name-only "$base" HEAD -- Docs/Stage0/evidence/M0-dependencies/linkage.log Docs/Stage0/evidence/M0-dependencies/resolve-locks.log)"
{
  echo "-- 1h. the committed logs of resolve-locks.sh and linkage.sh since ${base:0:8}: $( [[ -z "$dep_logs" ]] && echo "unchanged" || echo "PROBLEM, changed: $dep_logs")"
  echo "   a run under Xcode 27.1 (Docs/Stage0/evidence/M0-dependencies/xcode-27.1/) on this branch: $( [[ -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && echo "PROBLEM, present: the records call it pending" || echo "absent, as the records say (the agent run on m0-exit-prep makes it: pending)")"
} >> "$log"
[[ -n "$dep_logs" || -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && status=1
{
  echo "-- 1i. branches, read-only (nothing is fetched):"
  echo "   main: $(git rev-parse main); origin/main: $(git rev-parse origin/main) (pull request #6's merge: ${merge6:0:8})"
  echo "   m0-sessions: $(git rev-parse m0-sessions); HEAD descends from it: $(git merge-base --is-ancestor m0-sessions HEAD && echo yes || echo NO); commits on m0-sessions that main lacks: $(git rev-list --count main..m0-sessions)"
  echo "   m0-sessions-instructions: $(git rev-parse m0-sessions-instructions); m0-sessions-records: $(git rev-parse m0-sessions-records)"
  echo "   m0-decisions: $(git rev-parse m0-decisions); behind main: $(git merge-base --is-ancestor m0-decisions main && echo yes || echo NO)"
  echo "   Spikes/G05-Recovery/LockHarness/project.yml at HEAD: $(git cat-file -e HEAD:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent)"
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
  echo "LFS files (object and path, git lfs ls-files -l) at HEAD and at $base: identical, $(wc -l < "$scratch/lfs-head.txt" | tr -d ' ') each: the update adds no LFS object" >> "$log"
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
  echo "-- the records part's amendments checker ($devicea/commands/check-amendments.py), the newest: it must pass"
} >> "$log"
amend_status=0
python3 -I "$devicea/commands/check-amendments.py" > "$scratch/amend.out" 2>&1 || amend_status=$?
{ grep -E '^FAIL |^summary:' "$scratch/amend.out"; echo "exit: $amend_status"; } >> "$log"
(( amend_status != 0 )) && status=1
before_mut="$(git status --porcelain | wc -l | tr -d ' ')"
mut_status=0
python3 -I "$devicea/commands/mutation-checks.py" > "$scratch/mutations.out" 2>&1 || mut_status=$?
after_mut="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "-- its mutations ($devicea/commands/mutation-checks.py): each must make the checker fail its guarding check, the tree restored"
  tail -n 2 "$scratch/mutations.out" | sed 's/^/   /'
  echo "exit: $mut_status; uncommitted paths before and after: $before_mut, $after_mut"
} >> "$log"
(( mut_status != 0 )) && status=1
[[ "$before_mut" == "$after_mut" ]] || { echo "   PROBLEM: the mutations left the tree changed" >> "$log"; status=1; }
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
  echo "-- its control: the follow-up's fix's checker ($decisions/followup/round-2/commands/check-amendments.py) must fail on exactly the three checks whose anchors the records part replaced (the revision date; D-1's anchors of 22 October 2026 in 19.1 and 21.1, its 10c; its 10i)"
  grep -E '^FAIL |^summary:' "$scratch/amend-prev.out" | cut -c1-200 | sed 's/^/   /'
  echo "exit: $prev_status; $( [[ $prev_status == 1 && $exact == 0 ]] && echo "as required: exactly those three" || echo "NOT as required")"
} >> "$log"
[[ $prev_status == 1 && $exact == 0 ]] || status=1
trees="$root/$scratch/trees"
mkdir -p "$trees/base" "$trees/start" "$trees/head" "$trees/prev" "$trees/merged"
git archive "$base" | tar -x -C "$trees/base"
git archive "$start" | tar -x -C "$trees/start"
git archive HEAD | tar -x -C "$trees/head"
git archive "$prev" | tar -x -C "$trees/prev"
git archive "$mergeR" | tar -x -C "$trees/merged"
rec_status=0
python3 -I "$devicea/commands/check-records.py" "$root" > "$scratch/records.out" 2>&1 || rec_status=$?
rec_control="$(python3 -I "$devicea/commands/check-records.py" "$trees/start" 2>&1)"
{
  echo "-- the records part's check of the ADRs, the index, the gate reports and the integration log ($devicea/commands/check-records.py): it must pass"
  grep -E '^FAIL |^summary' "$scratch/records.out" | sed 's/^/   /'
  echo "exit: $rec_status"
  echo "   its control on the tree of ${start:0:8}: it must fail every check but the one on the G0.6 rows' statuses (17 of 18)"
  printf '%s\n' "$rec_control" | grep -E '^(PASS|summary)' | sed 's/^/   /'
} >> "$log"
(( rec_status != 0 )) && status=1
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
  echo "-- the decisions round's assembly's content check ($decisions/assembly/commands/runbook-content-check.py), which the version above replaces: it must report exactly the three texts the instructions part changed"
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
  echo "-- the runbook's correction-text check on $base, on $start and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$trees/check.py"
for side in base start head; do
  (cd "$trees/$side" && python3 -I "$trees/check.py" > "$trees/$side.out" 2>&1); echo "$?" > "$trees/$side.status"
done
tail -n +2 "$trees/base.out" > "$trees/base.body"
tail -n +2 "$trees/start.out" > "$trees/start.body"
tail -n +2 "$trees/head.out" > "$trees/head.body"
{
  echo "   $base: exit $(cat "$trees/base.status"); $(tail -n 1 "$trees/base.out")"
  echo "   $start: exit $(cat "$trees/start.status"); $(tail -n 1 "$trees/start.out")"
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
start_diff="$(diff "$trees/start.body" "$trees/head.body" | grep -E '^[<>] ' || true)"
if [[ "$changed_cct" == "$expected" && "$(cat "$trees/base.status")" == 1 && "$(cat "$trees/head.status")" == 1 ]] \
   && [[ "$(diff "$trees/base.body" "$trees/head.body" | grep -c -E '^< ')" == 10 ]] && [[ -z "$start_diff" ]]; then
  echo "   as required: from ${base:0:8} to HEAD the nine texts of the corrections the decisions round applied, found before and missing after, and the summary line, nothing else; from ${start:0:8} to HEAD no line differs" >> "$log"
else
  { echo "   NOT as required: expected exactly the nine applied corrections' texts to change from ${base:0:8}, and nothing from ${start:0:8}:"; printf '%s\n' "$start_diff" | sed 's/^/   /'; } >> "$log"
  status=1
fi
passing() {  # label, command...: an earlier check that reads no text the update changed must pass
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
passing "the second fix's recheck of UNL2-01 to UNL2-03 and of the fix's review status ($decisions/unlocked-record/round-3/commands/recheck-unl2.py), whose sweeps read every Markdown file, this update's new ones among them" \
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
echo "-- the six earlier rechecks that read texts the update changed: each must report exactly the lines of $here/commands/expected-rechecks.txt (which says why)" >> "$log"
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
grep -v '^#' "$here/commands/expected-rechecks.txt" > "$scratch/rechecks.expected"
if cmp -s "$scratch/rechecks.expected" "$scratch/rechecks.actual"; then
  echo "   as required: exactly the $(wc -l < "$scratch/rechecks.expected" | tr -d ' ') expected lines" >> "$log"
else
  { echo "   NOT as required: the reports differ from the expected lines:"; diff "$scratch/rechecks.expected" "$scratch/rechecks.actual" | cut -c1-400 | sed 's/^/   /'; } >> "$log"
  status=1
fi
ins_status=0
python3 -I "$instr/commands/recheck-instructions.py" "$root" > "$scratch/instr.out" 2>&1 || ins_status=$?
ins_problems="$(grep '^PROBLEM' "$scratch/instr.out")"
ins_expected="PROBLEM   floor: the 13 mini lays out at the 11 Pro's 375 × 812 pt drawn about 8% smaller; its figures that depend on the chip are its own, never the A13's; no budget changes; M8 measures the A13 floor; D-2 (a) stands with a narrower form of (b)'s exception (the runbook's 1.1 lacks: in M8, the Section 19.2 budgets are measured on an A13 iPhone, your iPhone 11 if it still works then, or a borrowed or bought one)"
{
  echo "-- the instructions part's recheck ($instr/commands/recheck-instructions.py), which the assembly's replaces: it must report exactly its floor item, on the runbook's text of M8's A13 phone, reworded as the records part asked"
  cut -c1-400 "$scratch/instr.out" | sed 's/^/   /'
  echo "exit: $ins_status"
} >> "$log"
if [[ "$ins_status" == 1 && "$ins_problems" == "$ins_expected" ]]; then
  echo "   as required: exactly that item, and on exactly that text" >> "$log"
else
  echo "   NOT as required" >> "$log"; status=1
fi
mine_status=0
python3 -I "$here/commands/recheck-assembly.py" "$root" > "$scratch/mine.out" 2>&1 || mine_status=$?
mine_start=0
python3 -I "$here/commands/recheck-assembly.py" "$trees/start" > "$scratch/mine-start.out" 2>&1 || mine_start=$?
mine_merged=0
python3 -I "$here/commands/recheck-assembly.py" "$trees/merged" > "$scratch/mine-merged.out" 2>&1 || mine_merged=$?
start_reported="$(grep -c '^PROBLEM' "$scratch/mine-start.out")"
merged_items="$(grep '^PROBLEM' "$scratch/mine-merged.out" | sed -E 's/^PROBLEM +([a-zA-Z0-9.-]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
{
  echo "-- the assembly's recheck ($here/commands/recheck-assembly.py), on HEAD: it must pass"
  cut -c1-400 "$scratch/mine.out" | sed 's/^/   /'
  echo "exit: $mine_status"
  echo "-- its control on the tree of ${start:0:8}, where the update starts: all nine items must be reported"
  cut -c1-200 "$scratch/mine-start.out" | sed 's/^/   /'
  echo "exit: $mine_start; reported: $start_reported of 9"
  echo "-- its control on the tree of $mergeR, the second merge, before the assembly's own changes: exactly floor, step-0.8, agree, state and log must be reported"
  cut -c1-300 "$scratch/mine-merged.out" | sed 's/^/   /'
  echo "exit: $mine_merged; reported: $merged_items"
} >> "$log"
(( mine_status != 0 )) && status=1
if [[ "$mine_start" == 1 && "$start_reported" == 9 ]]; then
  echo "   as required: all nine reported on ${start:0:8}'s tree" >> "$log"
else
  echo "   NOT as required: all nine must be reported on ${start:0:8}'s tree" >> "$log"; status=1
fi
if [[ "$mine_merged" == 1 && "$merged_items" == "floor step-0.8 agree state log" ]]; then
  echo "   as required: exactly those five reported on $mergeR's tree" >> "$log"
else
  echo "   NOT as required: exactly floor, step-0.8, agree, state and log must be reported on $mergeR's tree" >> "$log"; status=1
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
