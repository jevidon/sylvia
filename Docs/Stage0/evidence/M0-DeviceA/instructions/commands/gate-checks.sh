#!/bin/bash
# Checks behind the update of the product owner's instructions of 24 October 2026 (branch m0-sessions-instructions, made
# from m0-sessions at 6cede84a): after pull request #6 (96bdc7e9), the making of m0-sessions and the owner's decision of
# that day on device A, the runbook, the gate summary, the Stage 0 README and the device checklists say what the owner
# now does. Run on the commit that adds this update's other logs, with no uncommitted file. The successor of
# Docs/Stage0/evidence/M0-Decisions/unlocked-record/round-3/commands/gate-checks.sh:
#   Docs/Stage0/evidence/M0-DeviceA/instructions/commands/gate-checks.sh <log>
# 1. What changed: since 6cede84a (m0-sessions's head), only the files this update owns (the runbook, the gate summary,
#    the Stage 0 README, the eight checklists and Docs/Stage0/evidence/M0-DeviceA/instructions/); unchanged on this
#    branch the plan, the amendments, the ADRs, the gate reports, the integration log, the session log, the license
#    inventory, README.md and CLAUDE.md, so the follow-up's fix's amendments checker applies; since 96bdc7e9 (pull
#    request #6), CLAUDE.md alone besides (5aec2518 and 6cede84a, the orchestrating session's, before this update);
#    9cdb0a02, the commit of the drop-in's run, an ancestor of HEAD, with the code, scripts, contracts, fixtures and the
#    workflow unchanged since it, and the drop-in's own paths unchanged (dropin-paths.sh); the checklists unchanged from
#    9cdb0a02 to 6cede84a and all eight changed by this update, while the session log records no sitting of the owner's
#    (its only dated rows are agents' runs of 0.8); the committed logs of resolve-locks.sh and linkage.sh
#    unchanged and no run under Xcode 27.1 on this branch; and, read-only, main, origin/main, m0-sessions and
#    m0-decisions (no fetch).
# 2. The Git LFS state of the tree and of the repository configuration (read-only), and the LFS files of HEAD against
#    those of 4c73da57: this update adds no LFS file.
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the records it cites
#    (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py), and its negative control (rows 22, 42, 66, 71,
#    78 and 92).
# 4. The documents' own checks:
#    - the follow-up's fix's amendments checker, unchanged (followup/round-2/commands/check-amendments.py): 0 failures;
#    - this update's runbook content check (commands/runbook-content-check.py): it must pass (its controls and limits:
#      commands/runbook-content-check.sh, log checks/runbook-content-check.log); and the assembly's version, which it
#      replaces, must report exactly the three texts this update changed (two quoted in Section 6's D-1, one no longer
#      quoted in 1.1);
#    - the step coverage check (final-fix/commands/runbook-coverage.py): it must pass;
#    - the correction-text check on 4c73da57, 6cede84a and HEAD: from 4c73da57 to HEAD exactly the nine texts of the
#      corrections the decisions round applied change, as before, and from 6cede84a to HEAD nothing;
#    - the earlier rounds' rechecks: those that read no text this update changed must pass (recheck-review2, the two
#      moved-notes checks, the two checks of the run's facts with the second's control, the two finding-lines checks
#      with the second's control, and recheck-unl2 with its control on the tree of 26530d49); the six that do read such
#      texts must report exactly the lines of commands/expected-rechecks.txt, which says why each is reported;
#    - this update's recheck (commands/recheck-instructions.py): it must pass on HEAD, and, as its control, report all
#      six of its items on the tree of 6cede84a.
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first; the
#    worktree's LFS files must be filled from the local store first: checks/lfs-checkout.log).
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder (G0.5 AI review R7-04).
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, and nothing is written outside
# .build/ and the log. Exit status 1 if any part fails.
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"  # six folders up: commands, instructions, M0-DeviceA, evidence, Stage0, Docs
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
source Scripts/lib/env.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
evidence="Docs/Stage0/evidence/M0-Integration"
decisions="Docs/Stage0/evidence/M0-Decisions"
here="Docs/Stage0/evidence/M0-DeviceA/instructions"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e
merge6=96bdc7e996f99fcd2571ea983cc32a04076a5a07
start=6cede84a6f6ac610976b233d875e26dd89419dbd
prev=26530d4933c070c2c154a9116ef6f7fdd0415363
scratch=.build/scratch/devicea-gate
rm -rf "$scratch"; mkdir -p "$scratch"
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo
  echo "== 1. What changed"
} > "$log" 2>&1
git merge-base --is-ancestor "$start" HEAD || { echo "PROBLEM: HEAD does not descend from $start" >> "$log"; status=1; }
changed="$(git diff --name-only "$start" HEAD)"
owned='^(Docs/Stage0/M0-device-runbook\.md|Docs/Stage0/M0-gate\.md|Docs/Stage0/README\.md|Docs/Stage0/device-checklists/[^/]+\.md|Docs/Stage0/evidence/M0-DeviceA/instructions/.+)$'
stray="$(printf '%s\n' "$changed" | grep -v -E "$owned" | grep . || true)"
{
  echo "-- 1a. since ${start:0:8} (m0-sessions's head): $(printf '%s\n' "$changed" | grep -c .) files: $(printf '%s\n' "$changed" | grep -c "^$here/") of them this update's evidence; the documents:"
  printf '%s\n' "$changed" | grep -v "^$here/" | sed 's/^/   /'
  if [[ -z "$stray" ]]; then echo "   only the files this update owns"; else echo "   PROBLEM: also $stray"; fi
} >> "$log"
[[ -n "$stray" ]] && status=1
others="$(git diff --name-only "$start" HEAD -- Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md Docs/ADRs \
  'Docs/Stage0/G0*.md' Docs/Stage0/integration-log.md Docs/Stage0/evidence/M0-runbook/sessions.md Docs/Licenses README.md CLAUDE.md)"
{
  echo "-- 1b. the plan, the amendments, the ADRs, the gate reports, the integration log, the session log, the license inventory, README.md and CLAUDE.md since ${start:0:8}: $( [[ -z "$others" ]] && echo "unchanged (their owners' updates are on other branches), so the follow-up's fix's amendments checker applies as it was" || echo "PROBLEM, changed: $others")"
} >> "$log"
[[ -n "$others" ]] && status=1
since6="$(git diff --name-only "$merge6" "$start")"
{
  echo "-- 1c. from ${merge6:0:8} (pull request #6) to ${start:0:8}, before this update: $(printf '%s\n' "$since6" | tr '\n' ' ' | sed 's/ $//')"
  git log --format='   %h %s' "$merge6..$start"
} >> "$log"
[[ "$since6" == "CLAUDE.md" ]] || { echo "   PROBLEM: expected CLAUDE.md alone" >> "$log"; status=1; }
ancestor=no; git merge-base --is-ancestor "$run" HEAD && ancestor=yes
since_run="$(git diff --name-only "$run" HEAD -- Spikes Scripts Contracts Fixtures Apps Packages .github)"
dropin_status=0
bash "$here/commands/dropin-paths.sh" "$scratch/dropin-paths.log" > /dev/null 2>&1 || dropin_status=$?
{
  echo "-- 1d. ${run:0:8}, the commit of the drop-in's run, is an ancestor of HEAD: $ancestor"
  echo "   code, scripts, contracts, fixtures and the workflow changed since ${run:0:8}: $( [[ -z "$since_run" ]] && echo "none, so the run stands for HEAD's code" || echo "PROBLEM: $since_run")"
  echo "   the drop-in's own paths ($here/commands/dropin-paths.sh, exit $dropin_status; the paths and the lines that name them: $here/checks/dropin-paths.log):"
  sed -n '/^== 2/,$p' "$scratch/dropin-paths.log" | grep -v -E '^$' | sed 's/^/   /'
} >> "$log"
[[ "$ancestor" != yes || -n "$since_run" || "$dropin_status" != 0 ]] && status=1
lists_before="$(git diff --name-only "$run" "$start" -- Docs/Stage0/device-checklists)"
lists_now="$(git diff --name-only "$start" HEAD -- Docs/Stage0/device-checklists)"
lists_all="$(git ls-files Docs/Stage0/device-checklists | grep -E '\.md$')"
# The records say the checklists' lines were rewritten when the session log recorded no sitting of the owner's: every
# dated row of its table must be an agent's (the two runs of 0.8 ahead of Session 0).
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
  echo "-- 1e. the checklists, which the rule for repeating a session names: from ${run:0:8} to ${start:0:8}: $( [[ -z "$lists_before" ]] && echo "unchanged" || echo "PROBLEM: $lists_before"); since ${start:0:8}, by this update: $(printf '%s\n' "$lists_now" | grep -c .) of the $(printf '%s\n' "$lists_all" | grep -c .) (device-A and branch lines)"
  git diff --stat "$start" HEAD -- Docs/Stage0/device-checklists | sed 's/^/   /'
  echo "   the session log at HEAD (Docs/Stage0/evidence/M0-runbook/sessions.md, unchanged since ${start:0:8}: 1b), whose dated rows must all be agents': $sittings"
} >> "$log"
[[ -n "$lists_before" || "$lists_now" != "$lists_all" ]] && status=1
[[ "$sittings" == *"dated and not an agent's: 0" ]] || { echo "   PROBLEM: a sitting of the owner's is recorded" >> "$log"; status=1; }
dep_logs="$(git diff --name-only "$base" HEAD -- Docs/Stage0/evidence/M0-dependencies/linkage.log Docs/Stage0/evidence/M0-dependencies/resolve-locks.log)"
{
  echo "-- 1f. the committed logs of resolve-locks.sh and linkage.sh since ${base:0:8}: $( [[ -z "$dep_logs" ]] && echo "unchanged" || echo "PROBLEM, changed: $dep_logs")"
  echo "   a run under Xcode 27.1 (Docs/Stage0/evidence/M0-dependencies/xcode-27.1/) on this branch: $( [[ -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && echo "PROBLEM, present: the records call it pending" || echo "absent, as the records say (the agent run on m0-exit-prep makes it: pending)")"
} >> "$log"
[[ -n "$dep_logs" || -e Docs/Stage0/evidence/M0-dependencies/xcode-27.1 ]] && status=1
{
  echo "-- 1g. branches, read-only (nothing is fetched):"
  echo "   main: $(git rev-parse main); origin/main: $(git rev-parse origin/main) (pull request #6's merge: ${merge6:0:8})"
  echo "   m0-sessions: $(git rev-parse m0-sessions); HEAD descends from it: $(git merge-base --is-ancestor m0-sessions HEAD && echo yes || echo NO); commits on m0-sessions that main lacks: $(git rev-list --count main..m0-sessions)"
  echo "   m0-decisions: $(git rev-parse m0-decisions); behind main: $(git merge-base --is-ancestor m0-decisions main && echo yes || echo NO)"
  echo "   Spikes/G05-Recovery/LockHarness/project.yml at m0-sessions: $(git cat-file -e m0-sessions:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent); at HEAD: $(git cat-file -e HEAD:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent)"
  echo
  echo "== 2. Git LFS state"
  echo ".gitattributes patterns (non-comment lines):"
  grep -v -E '^\s*(#|$)' .gitattributes
  echo "git config --show-origin --get-regexp 'filter\\.lfs|lfs\\.':"
  git config --show-origin --get-regexp 'filter\.lfs|lfs\.' || echo "(no match)"
  git lfs version
  echo "files tracked by LFS (git lfs ls-files): $(git lfs ls-files | wc -l | tr -d ' '); of them still pointer files in the working tree: $(git lfs ls-files | awk '$2 == "-"' | wc -l | tr -d ' ')"
} >> "$log" 2>&1
git lfs ls-files -l "$base" | sort > "$scratch/lfs-base.txt"
git lfs ls-files -l HEAD | sort > "$scratch/lfs-head.txt"
if cmp -s "$scratch/lfs-base.txt" "$scratch/lfs-head.txt"; then
  echo "LFS files (object and path, git lfs ls-files -l) at HEAD and at $base: identical, $(wc -l < "$scratch/lfs-head.txt" | tr -d ' ') each: this update adds no LFS object" >> "$log"
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
  echo "-- the follow-up's fix's amendments checker, unchanged ($decisions/followup/round-2/commands/check-amendments.py), the plan unchanged on this branch"
} >> "$log"
amend_status=0
python3 -I "$decisions/followup/round-2/commands/check-amendments.py" > "$scratch/amend.out" 2>&1 || amend_status=$?
{ grep -E '^FAIL |^summary:' "$scratch/amend.out"; echo "exit: $amend_status"; } >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$here/commands/runbook-content-check.py" "$root" > "$scratch/content.out" 2>&1 || content_status=$?
{
  echo "-- this update's runbook content check ($here/commands/runbook-content-check.py; its controls and limits: $here/checks/runbook-content-check.log): it must pass"
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
  echo "-- the assembly's content check ($decisions/assembly/commands/runbook-content-check.py), which the version above replaces: it must report exactly the three texts this update changed"
  printf '%s\n' "$old_problems" | sed 's/^/   /'
  echo "exit: $old_status"
} >> "$log"
if [[ "$old_status" == 1 && "$old_problems" == "$old_expected" ]]; then
  echo "   as required: exactly those three (the owner's words and the option chosen, quoted in Section 6's D-1, and plan 19.1's sentence of 22 October 2026, no longer quoted in 1.1)" >> "$log"
else
  echo "   NOT as required: exactly the three texts this update changed" >> "$log"; status=1
fi
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > "$scratch/coverage.out" 2>&1 || cov_status=$?
{
  echo "-- the runbook's step coverage ($evidence/final-fix/commands/runbook-coverage.py): it must pass"
  tail -n 3 "$scratch/coverage.out"
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base, on $start and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
trees="$root/$scratch/trees"
mkdir -p "$trees/base" "$trees/start" "$trees/head" "$trees/prev"
git archive "$base" | tar -x -C "$trees/base"
git archive "$start" | tar -x -C "$trees/start"
git archive HEAD | tar -x -C "$trees/head"
git archive "$prev" | tar -x -C "$trees/prev"
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
  echo "   the lines that differ from $base to HEAD (the first line, a timestamp, left out):"
  diff "$trees/base.body" "$trees/head.body" | grep -E '^[<>] ' | sed 's/^/   /'
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
  echo "   as required: from $base to HEAD the nine texts of the corrections the decisions round applied, found before and missing after, and the summary line, nothing else; from $start to HEAD no line differs" >> "$log"
else
  { echo "   NOT as required: expected exactly the nine applied corrections' texts to change from $base, and nothing from $start:"; printf '%s\n' "$start_diff" | sed 's/^/   /'; } >> "$log"
  status=1
fi
passing() {  # label, command...: an earlier check that reads no text this update changed must pass
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
  echo "   its control, on the assembly's run with the screen locked: fails, as required, naming the locked screen and the missing row-10 line" >> "$log"
else
  echo "   NOT as required: its control must fail on the locked screen and the missing row-10 line" >> "$log"; status=1
fi
passing "the fix's check of its review's cited lines ($decisions/unlocked-record/round-2/commands/finding-lines.py), at 91c3b46a" \
  python3 -I "$decisions/unlocked-record/round-2/commands/finding-lines.py" "$root"
passing "the second fix's recheck of UNL2-01 to UNL2-03 and of the fix's review status ($decisions/unlocked-record/round-3/commands/recheck-unl2.py)" \
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
{
  echo "-- the six earlier rechecks that read texts this update changed: each must report exactly the lines of $here/commands/expected-rechecks.txt (which says why)"
} >> "$log"
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
mine_status=0
python3 -I "$here/commands/recheck-instructions.py" "$root" > "$scratch/mine.out" 2>&1 || mine_status=$?
mine_control=0
python3 -I "$here/commands/recheck-instructions.py" "$trees/start" > "$scratch/mine-control.out" 2>&1 || mine_control=$?
mine_reported="$(grep -c '^PROBLEM' "$scratch/mine-control.out")"
{
  echo "-- this update's recheck ($here/commands/recheck-instructions.py; its log: $here/checks/recheck-instructions.log), on HEAD: it must pass"
  sed 's/^/   /' "$scratch/mine.out" | cut -c1-400
  echo "exit: $mine_status"
  echo "-- its control on the tree of ${start:0:8}, where this update starts: all six items must be reported"
  cut -c1-200 "$scratch/mine-control.out" | sed 's/^/   /'
  echo "exit: $mine_control; reported: $mine_reported of 6"
} >> "$log"
(( mine_status != 0 )) && status=1
if [[ "$mine_control" == 1 && "$mine_reported" == 6 ]]; then
  echo "   as required: all six reported" >> "$log"
else
  echo "   NOT as required: all six must be reported on the tree of ${start:0:8}" >> "$log"; status=1
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
