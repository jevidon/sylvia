#!/bin/bash
# A simulation of the product owner's merge of m0-records-update into m0-decisions, as the evidence README's merge
# section gives it (the fix of the owner-readability findings of the review of m0-records-update, its findings OWN-RU-03
# and OWN-RU-04; integration log section 44). It runs in a scratch clone, so that no ref of this repository is written
# and ~/Git/sylvia-sessions is never touched:
#   Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/merge-simulation.sh [--dry]
# The clone is `git clone --shared --no-checkout` of this worktree under .build/scratch (a local clone: no network; its
# Git LFS files are left as pointers, which nothing here reads). It gets two branches of its own: m0-decisions at
# c72247a6, the owner's head when this fix was made (the real m0-decisions is only read, and its commit printed), and
# m0-records-update at this worktree's HEAD (with --dry, at a commit made in the clone from this worktree's uncommitted
# files too, for a dry run before the documents commit).
#  A. m0-decisions has not moved: the README's commands, in the clone, in order: the log line prints nothing; git merge
#     --ff-only fast-forwards; the apply command (--check first, then for real) puts the two texts in; git diff --stat
#     shows CLAUDE.md alone, two lines; the lock check, run as the README's line runs it, in zsh, passes; the commit
#     changes CLAUDE.md alone; a second run of the apply command changes nothing. Then the two checks of "After the
#     merge": 0.8's diff, which must print nothing, and 0.3 step 7's against each commit the session log's rows 3a-3d
#     and the status file name.
#  B. m0-decisions has moved on: a commit of the simulation's own on c72247a6 stands for the owner's next records (G0.4
#     step 1's status file and a session-log row). The log line prints it; git merge --ff-only refuses with exit 128 and
#     leaves m0-decisions and the working tree as they were. The new owner-records check given that commit fails on
#     m0-records-update, which lacks it, while the version it replaces, which reads c72247a6 alone, passes there. An
#     agent's merge of m0-decisions into a branch at m0-records-update (a plain git merge in the clone, standing for the
#     agent's) is clean here; the new check passes on it, the owner's head in its history; and the owner's git merge
#     --ff-only of that branch then fast-forwards.
#  C. The apply command's refusals, on copies of CLAUDE.md: no "Current milestone:" line, two of them, and the toolchain
#     line without its old words: each exits 1 and writes nothing.
# Exit 1 if any expectation fails. The clone is deleted at the end.
set -u
dry=0
if [[ "${1:-}" == "--dry" ]]; then dry=1; shift; fi
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
here=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands
old_check=Docs/Stage0/evidence/M0-RecordsUpdate/commands/owner-records-intact.py
scratch="$root/.build/scratch/owner-merge-simulation"
clone="$scratch/repo"
status=0
expect() {  # <label> <0 or 1: the condition held>
  if [[ "$2" == 1 ]]; then echo "ok    $1"; else echo "FAIL  $1"; status=1; fi
}
sim() { git -C "$clone" -c user.name="merge simulation" -c user.email="simulation@invalid" "$@"; }

echo "merge-simulation: HEAD $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "the real m0-decisions (read only): $(git rev-parse m0-decisions)"
echo "the real git log --oneline m0-records-update..m0-decisions:"
git log --oneline m0-records-update..m0-decisions | sed 's/^/  /'
echo "(the end of that list)"
# Without --dry the clone takes HEAD as committed, so only a change to a tracked file refuses the run (the runner's logs,
# untracked, are written while it runs).
if [[ -n "$(git status --porcelain --untracked-files=no)" && $dry == 0 ]]; then
  echo "refused: a tracked file is changed; run on a committed tree, or with --dry"; exit 2
fi

rm -rf "$scratch"; mkdir -p "$scratch"
GIT_LFS_SKIP_SMUDGE=1 git clone -q --shared --no-checkout "$root" "$clone" || exit 1
export GIT_LFS_SKIP_SMUDGE=1
head="$(git rev-parse HEAD)"
# The clone's own m0-records-update (its default branch, from this worktree's) is set to HEAD and checked out.
sim checkout -q -B m0-records-update "$head" || exit 1
if (( dry )); then
  # A commit in the clone with this worktree's uncommitted files, for a dry run (no file outside the clone is written).
  git status --porcelain --untracked-files=all | sed -E 's/^.. //' | while read -r p; do
    mkdir -p "$clone/$(dirname "$p")"; cp "$p" "$clone/$p"; done
  sim add -A >/dev/null
  sim commit -q -m "dry run: this worktree's uncommitted files"
  echo "dry run: m0-records-update in the clone is $(sim rev-parse HEAD), this worktree's HEAD with its uncommitted files"
fi
sim checkout -q -b m0-decisions c72247a6
records="$(sim rev-parse m0-records-update)"
echo

echo "== A. m0-decisions at c72247a6, not moved: the README's commands"
cd "$clone" || exit 1
echo "\$ git status --short"; git status --short; expect "nothing uncommitted" "$([[ -z "$(git status --short)" ]] && echo 1)"
echo "\$ git branch --show-current"; git branch --show-current
echo "\$ git log --oneline m0-records-update..m0-decisions"; out="$(git log --oneline m0-records-update..m0-decisions)"
echo "$out"; expect "the log line prints nothing" "$([[ -z "$out" ]] && echo 1)"
echo "\$ git merge --ff-only m0-records-update"; git merge --ff-only m0-records-update 2>&1 | tail -3; s=${PIPESTATUS[0]}
expect "the merge fast-forwards (exit $s), m0-decisions now m0-records-update's head" \
  "$([[ $s == 0 && "$(git rev-parse HEAD)" == "$records" ]] && echo 1)"
echo "\$ python3 -I $here/apply-claude-md-texts.py --check"; python3 -I "$here/apply-claude-md-texts.py" --check; s=$?
expect "--check exits 0 and writes nothing" "$([[ $s == 0 && -z "$(git status --porcelain)" ]] && echo 1)"
echo "\$ python3 -I $here/apply-claude-md-texts.py"; python3 -I "$here/apply-claude-md-texts.py"; s=$?
echo "\$ git diff --stat"; stat="$(git diff --stat)"; echo "$stat"
expect "the apply command exits 0 and git diff --stat shows CLAUDE.md alone, 4 ++--" \
  "$([[ $s == 0 && "$(git diff --name-only)" == "CLAUDE.md" && "$stat" == *"CLAUDE.md | 4 ++--"* ]] && echo 1)"
para="$(python3 -I "$root/$here/merge-simulation-helpers.py" texts-in "$clone")"
expect "CLAUDE.md's line 5 is the texts file's paragraph, and its toolchain line has the new words, not the old" \
  "$([[ "$para" == yes ]] && echo 1)"
echo "\$ (source Scripts/lib/env.sh && Scripts/ci.d/12-dependency-lock.sh), in zsh, as the README has it"
zsh -c '(source Scripts/lib/env.sh && Scripts/ci.d/12-dependency-lock.sh)' > "$scratch/12-dependency-lock.log" 2>&1; s=$?
grep -E "^12-dependency-lock |failure\(s\)|warning\(s\)" "$scratch/12-dependency-lock.log" | tail -4
expect "the lock check passes on the changed CLAUDE.md (exit $s; the toolchain line's pin read)" "$([[ $s == 0 ]] && echo 1)"
echo "\$ git commit -m \"Point CLAUDE.md's milestone paragraph at m0-decisions\" -- CLAUDE.md"
sim commit -q -m "Point CLAUDE.md's milestone paragraph at m0-decisions" -- CLAUDE.md
expect "the commit changes CLAUDE.md alone" "$([[ "$(git show --name-only --format= HEAD)" == "CLAUDE.md" ]] && echo 1)"
echo "\$ git rev-parse HEAD"; git rev-parse HEAD
echo "\$ python3 -I $here/apply-claude-md-texts.py   (a second time)"; python3 -I "$here/apply-claude-md-texts.py"; s=$?
expect "a second run changes nothing" "$([[ $s == 0 && -z "$(git status --porcelain)" ]] && echo 1)"
echo
echo "-- After the merge: runbook 0.8's check"
echo "\$ git diff --stat 9cdb0a02 HEAD -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1 ':(exclude)Spikes/G05-Recovery/DeviceTests'"
out="$(git diff --stat 9cdb0a02 HEAD -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery \
  Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1 \
  ':(exclude)Spikes/G05-Recovery/DeviceTests')"
echo "$out"; expect "0.8's check prints nothing: 0.8 still needs nothing" "$([[ -z "$out" ]] && echo 1)"
echo "-- After the merge: runbook 0.3, step 7's check, against each sitting's commit"
for c in 96bdc7e9 8404f342 432acc13 4be1a1a4 d5336111; do
  echo "\$ git diff --stat $c HEAD -- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists"
  git diff --stat "$c" HEAD -- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists
done
files="$(git diff --name-only d5336111 HEAD -- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists)"
expect "against d5336111 it lists the eight checklists and the Zip guard's two scripts alone" "$([[ \
  "$(echo "$files" | grep -c '^Docs/Stage0/device-checklists/')" == 8 && \
  "$(echo "$files" | grep -v '^Docs/Stage0/device-checklists/' | tr '\n' ' ')" == "Scripts/check-dependency-lock.py Scripts/ci.d/12-dependency-lock.sh " ]] && echo 1)"
echo

echo "== B. m0-decisions moved on: a commit standing for the owner's next records"
git checkout -q -B m0-decisions c72247a6
printf '%s\n' "SIMULATED in a scratch clone by merge-simulation.sh: G0.4 step 1 finished (no device was used)." \
  >> Docs/Stage0/evidence/G04-Audio/device/step-01-status.txt
printf '\n%s\n' "| 3e | 1 Automated suites, step 1.4 (simulated) | - | merge simulation | - | - | simulated | - |" \
  >> Docs/Stage0/evidence/M0-runbook/sessions.md
sim commit -q -am "Simulated owner records after c72247a6"
owner_next="$(git rev-parse HEAD)"
echo "the simulated owner commit: $owner_next ($(git show --stat --format=%s HEAD | head -1))"
echo "\$ git log --oneline m0-records-update..m0-decisions"; out="$(git log --oneline m0-records-update..m0-decisions)"
echo "$out"; expect "the log line prints the commit, and it alone" \
  "$([[ "$(echo "$out" | wc -l | tr -d ' ')" == 1 && "$out" == *"Simulated owner records after c72247a6"* ]] && echo 1)"
echo "\$ git merge --ff-only m0-records-update"; git merge --ff-only m0-records-update; s=$?
expect "the merge refuses (exit $s, 128 expected), m0-decisions unchanged, nothing uncommitted" \
  "$([[ $s == 128 && "$(git rev-parse HEAD)" == "$owner_next" && -z "$(git status --porcelain)" ]] && echo 1)"
echo "\$ python3 -I $here/owner-records-intact.py --owner-head m0-decisions --rev m0-records-update"
python3 -I "$root/$here/owner-records-intact.py" --owner-head m0-decisions --rev m0-records-update \
  | grep -E "^(FAIL|owner)|^owner's commits|^  "; s=${PIPESTATUS[0]}
expect "the new check, given the owner's head, fails on m0-records-update (exit $s), which lacks the commit" \
  "$([[ $s == 1 ]] && echo 1)"
echo "\$ python3 -I $old_check --rev m0-records-update   (the version it replaces)"
python3 -I "$root/$old_check" --rev m0-records-update | tail -1; s=${PIPESTATUS[0]}
expect "the version it replaces passes there (exit $s): it reads c72247a6 alone" "$([[ $s == 0 ]] && echo 1)"
echo "\$ git checkout -b agent-merge m0-records-update; git merge --no-edit m0-decisions   (standing for the agent's merge)"
git checkout -q -b agent-merge m0-records-update
sim merge -q --no-edit m0-decisions; s=$?
expect "the agent's merge is clean here (exit $s)" "$([[ $s == 0 && -z "$(git status --porcelain)" ]] && echo 1)"
echo "\$ python3 -I $here/owner-records-intact.py --owner-head m0-decisions --rev agent-merge"
python3 -I "$root/$here/owner-records-intact.py" --owner-head m0-decisions --rev agent-merge \
  | grep -E "^(FAIL|owner)|^owner's commits|history"; s=${PIPESTATUS[0]}
expect "the new check passes on the agent's merge (exit $s)" "$([[ $s == 0 ]] && echo 1)"
git checkout -q m0-decisions
echo "\$ git merge --ff-only agent-merge"; git merge --ff-only agent-merge 2>&1 | tail -2; s=${PIPESTATUS[0]}
expect "the owner's merge now fast-forwards (exit $s)" \
  "$([[ $s == 0 && "$(git rev-parse HEAD)" == "$(git rev-parse agent-merge)" ]] && echo 1)"
echo

echo "== C. the apply command's refusals, on copies of CLAUDE.md"
for case in none two old-words; do
  t="$scratch/apply-$case"; mkdir -p "$t/Docs/Stage0/evidence/M0-RecordsUpdate"
  cp Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md "$t/Docs/Stage0/evidence/M0-RecordsUpdate/"
  git show c72247a6:CLAUDE.md > "$t/CLAUDE.md"
  python3 -I "$root/$here/merge-simulation-helpers.py" break "$t/CLAUDE.md" "$case" || status=1
  before="$(shasum "$t/CLAUDE.md")"
  python3 -I "$root/$here/apply-claude-md-texts.py" "$t"; s=$?
  expect "case $case: exit $s (1 expected), CLAUDE.md unchanged" "$([[ $s == 1 && "$(shasum "$t/CLAUDE.md")" == "$before" ]] && echo 1)"
done

cd "$root" || exit 1
rm -rf "$scratch"
echo
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
