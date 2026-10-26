#!/bin/bash
# A simulation of the product owner's merge of m0-records-update into m0-decisions after the fold-in of m0-device-fixes
# (27 October 2026; integration log section 45), as the evidence README's merge section gives it, in a scratch clone, so
# that no ref of this repository is written and ~/Git/sylvia-sessions is never touched:
#   Docs/Stage0/evidence/M0-RecordsUpdate/foldin/commands/merge-simulation.sh [--dry]
# The clone is `git clone --shared --no-checkout` of this worktree under .build/scratch (a local clone: no network; its
# Git LFS files are left as pointers, which nothing here reads), with branches of its own: m0-decisions at c72247a6,
# the owner's head this branch holds (the real m0-decisions is only read, and its commit printed), m0-device-fixes at
# a60aa922 and m0-records-update at this worktree's HEAD (with --dry, at a commit made in the clone from this worktree's
# uncommitted files too, for a dry run before the documents commit).
#  A. m0-decisions has not moved: the README's commands, in order. The log line prints nothing; git merge --ff-only
#     fast-forwards; CLAUDE.md then holds the two texts with nothing put in by hand (its fifth line is the texts file's
#     paragraph, its toolchain line has the new words). The two checks of "After the merge": 0.8's lists exactly the
#     eleven files of the recovery package that the device fixes changed (0.8 runs again); 0.3 step 7's, against
#     d5336111, lists the eight checklists, the Zip guard's two scripts, Scripts/ci.d/70-g05-ai.sh, the ATS probe's test
#     file and those eleven files, and nothing else (against the other commits of the session log, printed too).
#  B. m0-decisions has moved on: a commit of the simulation's own on c72247a6 stands for the owner's next records. The
#     log line prints it; git merge --ff-only refuses with exit 128 and changes nothing; an agent's merge of m0-decisions
#     into a branch at m0-records-update (a plain git merge in the clone, standing for the agent's) is clean; the owner
#     fix's owner-records-intact.py, given that commit, passes on it; and the owner's git merge --ff-only of it then
#     fast-forwards.
#  C. m0-device-fixes merged on its own first, as its README's 7.1 asked before the fold-in: (1) on c72247a6, as a
#     fast-forward: the log line then prints nothing and the merge of m0-records-update fast-forwards; (2) after an owner
#     commit, with git merge --no-edit as 7.1 gives it, a merge commit: the log line prints both, the fast-forward
#     refuses, and after the agent's merge, clean, it fast-forwards.
#  D. A conflict: an owner commit that changes a line this branch changes too (the runbook's 0.8, which c72247a6 holds
#     and this branch gave notes). git merge --ff-only refuses, changing nothing; a plain git merge, which the README
#     never uses, stops on the conflict, and git merge --abort puts m0-decisions back as it was, with nothing
#     uncommitted.
# Exit 1 if any expectation fails. The clone is deleted at the end.
set -u
dry=0
if [[ "${1:-}" == "--dry" ]]; then dry=1; shift; fi
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
check=Docs/Stage0/evidence/M0-RecordsUpdate/fix-1/owner/commands/owner-records-intact.py
scratch="$root/.build/scratch/foldin-merge-simulation"
clone="$scratch/repo"
status=0
expect() {  # <label> <1 if the condition held>
  if [[ "$2" == 1 ]]; then echo "ok    $1"; else echo "FAIL  $1"; status=1; fi
}
sim() { git -C "$clone" -c user.name="merge simulation" -c user.email="simulation@invalid" "$@"; }
owner_commit() {  # <message> <file> <line to append>: a commit standing for the owner's next records, on the checkout
  printf '%s\n' "$3" >> "$clone/$2"
  sim add -- "$2" && sim commit -q -m "$1"
}

echo "merge-simulation (fold-in): HEAD $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "the real m0-decisions (read only): $(git rev-parse m0-decisions); the real m0-device-fixes: $(git rev-parse m0-device-fixes)"
echo "the real git log --oneline m0-records-update..m0-decisions:"
git log --oneline m0-records-update..m0-decisions | sed 's/^/  /'
echo "(the end of that list)"
if [[ -n "$(git status --porcelain --untracked-files=no)" && $dry == 0 ]]; then
  echo "refused: a tracked file is changed; run on a committed tree, or with --dry"; exit 2
fi

rm -rf "$scratch"; mkdir -p "$scratch"
GIT_LFS_SKIP_SMUDGE=1 git clone -q --shared --no-checkout "$root" "$clone" || exit 1
export GIT_LFS_SKIP_SMUDGE=1
sim checkout -q -B m0-records-update "$(git rev-parse HEAD)" || exit 1
if (( dry )); then
  git status --porcelain --untracked-files=all | sed -E 's/^.. //' | while read -r p; do
    mkdir -p "$clone/$(dirname "$p")"; cp "$p" "$clone/$p"; done
  sim add -A >/dev/null
  sim commit -q -m "dry run: this worktree's uncommitted files"
  echo "dry run: m0-records-update in the clone is $(sim rev-parse HEAD), this worktree's HEAD with its uncommitted files"
fi
records="$(sim rev-parse m0-records-update)"
sim branch -q -f m0-device-fixes a60aa92274d209bff6e1727ed36c078cd94ed8b2
fresh() {  # <branch> <commit>: check the branch out at the commit, the working tree clean
  sim checkout -q -f -B "$1" "$2" && sim clean -q -fdx >/dev/null
}
fresh m0-decisions c72247a69a374ce361834550b92689b4abab95ee
cd "$clone" || exit 1
echo

echo "== A. m0-decisions at c72247a6, not moved: the README's commands"
echo "\$ git status --short"; git status --short; expect "nothing uncommitted" "$([[ -z "$(git status --short)" ]] && echo 1)"
echo "\$ git branch --show-current"; git branch --show-current
echo "\$ git log --oneline m0-records-update..m0-decisions"; out="$(git log --oneline m0-records-update..m0-decisions)"
echo "$out"; expect "the log line prints nothing" "$([[ -z "$out" ]] && echo 1)"
echo "\$ git merge --ff-only m0-records-update"; git merge --ff-only m0-records-update 2>&1 | tail -2; s=${PIPESTATUS[0]}
expect "the merge fast-forwards (exit $s), m0-decisions now m0-records-update's head" \
  "$([[ $s == 0 && "$(git rev-parse HEAD)" == "$records" ]] && echo 1)"
echo "\$ git rev-parse HEAD"; git rev-parse HEAD
texts="$(python3 -I - "$clone" <<'EOF'
import re, sys
root = sys.argv[1]
para_file = open(f"{root}/Docs/Stage0/evidence/M0-RecordsUpdate/claude-md-paragraph.md", encoding="utf-8").read()
block = re.search(r"```markdown\n(.*?)\n```", para_file, re.S).group(1)
old_words, new_words = re.findall(r"^> (.*)$", para_file, re.M)[:2]
lines = open(f"{root}/CLAUDE.md", encoding="utf-8").read().split("\n")
tool = [l for l in lines if l.startswith("- Xcode 27.1 (27A9275)")]
print("yes" if lines[4] == block and len(tool) == 1 and new_words in tool[0] and old_words not in tool[0] else "no")
EOF
)"
expect "after the merge CLAUDE.md holds both texts, nothing put in by hand (line 5 the paragraph; the toolchain line's new words)" \
  "$([[ "$texts" == yes ]] && echo 1)"
echo
echo "-- After the merge: runbook 0.8's check"
echo "\$ git diff --stat 9cdb0a02 HEAD -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1 ':(exclude)Spikes/G05-Recovery/DeviceTests'"
git diff --stat 9cdb0a02 HEAD -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery \
  Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1 \
  ':(exclude)Spikes/G05-Recovery/DeviceTests' | cat
eight="$(git diff --name-only 9cdb0a02 HEAD -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery \
  Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1 \
  ':(exclude)Spikes/G05-Recovery/DeviceTests')"
fixes="$(git diff --name-only c72247a6 a60aa922 -- Spikes/G05-Recovery)"
expect "it lists exactly the eleven files of the recovery package that the device fixes changed: 0.8 runs again" \
  "$([[ "$eight" == "$fixes" && "$(echo "$eight" | wc -l | tr -d ' ')" == 11 ]] && echo 1)"
echo "-- After the merge: runbook 0.3, step 7's check, against each commit of the session log's rows 3a-3d and the status file"
for c in 96bdc7e9 8404f342 432acc13 4be1a1a4 d5336111; do
  echo "\$ git diff --stat $c HEAD -- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists"
  git diff --stat "$c" HEAD -- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists | cat
done
files="$(git diff --name-only d5336111 HEAD -- Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists)"
rest="$(echo "$files" | grep -v '^Docs/Stage0/device-checklists/' | grep -v '^Spikes/G05-Recovery/' | tr '\n' ' ')"
expect "against d5336111: the eight checklists, the eleven recovery files, and the Zip guard's two scripts, Scripts/ci.d/70-g05-ai.sh and the ATS probe's test file alone" "$([[ \
  "$(echo "$files" | grep -c '^Docs/Stage0/device-checklists/')" == 8 && \
  "$(echo "$files" | grep '^Spikes/G05-Recovery/')" == "$fixes" && \
  "$rest" == "Scripts/check-dependency-lock.py Scripts/ci.d/12-dependency-lock.sh Scripts/ci.d/70-g05-ai.sh Spikes/G05-AI/ATSProbe/Tests/ATSProbeTests.swift " ]] && echo 1)"
echo

echo "== B. m0-decisions moved on: a commit standing for the owner's next records"
fresh m0-decisions c72247a69a374ce361834550b92689b4abab95ee
owner_commit "simulation: the owner's records of a later sitting" Docs/Stage0/evidence/G04-Audio/device/step-01-status.txt \
  "simulation: a line standing for the owner's next records"
owner="$(git rev-parse HEAD)"
echo "\$ git log --oneline m0-records-update..m0-decisions"; out="$(git log --oneline m0-records-update..m0-decisions)"; echo "$out"
expect "the log line prints the commit, and it alone" "$([[ "$out" == "$(git log -1 --oneline "$owner")" ]] && echo 1)"
echo "\$ git merge --ff-only m0-records-update"; git merge --ff-only m0-records-update 2>&1 | tail -2; s=${PIPESTATUS[0]}
expect "the merge refuses (exit $s, 128 expected), m0-decisions unchanged, nothing uncommitted" \
  "$([[ $s == 128 && "$(git rev-parse HEAD)" == "$owner" && -z "$(git status --porcelain)" ]] && echo 1)"
fresh agent-merge "$records"
sim merge -q --no-edit m0-decisions; s=$?
expect "the agent's merge of m0-decisions into a branch at m0-records-update is clean here (exit $s)" "$([[ $s == 0 ]] && echo 1)"
python3 -I "$root/$check" --owner-head "$owner" --rev agent-merge > "$scratch/owner-records-B.log" 2>&1; s=$?
tail -2 "$scratch/owner-records-B.log"
expect "the owner fix's owner-records-intact.py, given the owner's head, passes on the agent's merge (exit $s)" "$([[ $s == 0 ]] && echo 1)"
sim checkout -q m0-decisions
echo "\$ git merge --ff-only agent-merge"; git merge --ff-only agent-merge 2>&1 | tail -1; s=${PIPESTATUS[0]}
expect "the owner's merge now fast-forwards (exit $s)" "$([[ $s == 0 && "$(git rev-parse HEAD)" == "$(git rev-parse agent-merge)" ]] && echo 1)"
echo

echo "== C1. m0-device-fixes merged on its own first, on c72247a6, as a fast-forward"
fresh m0-decisions c72247a69a374ce361834550b92689b4abab95ee
git merge -q --ff-only m0-device-fixes; s=$?
expect "m0-device-fixes fast-forwards m0-decisions to a60aa922 (exit $s)" "$([[ $s == 0 && "$(git rev-parse HEAD)" == "$(git rev-parse m0-device-fixes)" ]] && echo 1)"
out="$(git log --oneline m0-records-update..m0-decisions)"
expect "the log line then prints nothing" "$([[ -z "$out" ]] && echo 1)"
git merge -q --ff-only m0-records-update; s=$?
expect "and the merge of m0-records-update fast-forwards (exit $s)" "$([[ $s == 0 && "$(git rev-parse HEAD)" == "$records" ]] && echo 1)"
echo
echo "== C2. m0-device-fixes merged on its own after an owner commit, with git merge --no-edit, as its 7.1 gave it"
fresh m0-decisions c72247a69a374ce361834550b92689b4abab95ee
owner_commit "simulation: the owner's records of a later sitting" Docs/Stage0/evidence/G04-Audio/device/step-01-status.txt \
  "simulation: a line standing for the owner's next records"
sim merge -q --no-edit m0-device-fixes; s=$?
expect "the merge of m0-device-fixes makes a merge commit (exit $s; $(git log -1 --format=%p HEAD | wc -w | tr -d ' ') parents)" \
  "$([[ $s == 0 && "$(git log -1 --format=%p HEAD | wc -w | tr -d ' ')" == 2 ]] && echo 1)"
moved="$(git rev-parse HEAD)"
out="$(git log --oneline m0-records-update..m0-decisions)"; echo "$out" | sed 's/^/  /'
expect "the log line prints the owner's commit and that merge commit" "$([[ "$(echo "$out" | wc -l | tr -d ' ')" == 2 ]] && echo 1)"
git merge -q --ff-only m0-records-update 2>/dev/null; s=$?
expect "the fast-forward refuses (exit $s), m0-decisions unchanged" "$([[ $s == 128 && "$(git rev-parse HEAD)" == "$moved" ]] && echo 1)"
fresh agent-merge-2 "$records"
sim merge -q --no-edit m0-decisions; s=$?
expect "the agent's merge takes it in, clean (exit $s)" "$([[ $s == 0 ]] && echo 1)"
sim checkout -q m0-decisions
git merge -q --ff-only agent-merge-2; s=$?
expect "and the owner's merge then fast-forwards (exit $s)" "$([[ $s == 0 && "$(git rev-parse HEAD)" == "$(git rev-parse agent-merge-2)" ]] && echo 1)"
echo

echo "== D. a conflict: an owner commit that changes a line this branch changes too"
fresh m0-decisions c72247a69a374ce361834550b92689b4abab95ee
python3 -I - "$clone/Docs/Stage0/M0-device-runbook.md" <<'EOF'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
i = [n for n, l in enumerate(lines) if l.startswith("**0.8 G0.5 recovery report row 10")][0]
lines[i] = lines[i] + " (simulation: the owner's own sentence on a later run of 0.8.)"
open(p, "w", encoding="utf-8").write("\n".join(lines))
EOF
sim commit -q -a -m "simulation: the owner's edit of the runbook's 0.8"
owner="$(git rev-parse HEAD)"
expect "the owner's commit is made on c72247a6" "$([[ "$(git rev-parse HEAD~1)" == c72247a69a374ce361834550b92689b4abab95ee ]] && echo 1)"
git merge --ff-only m0-records-update > /dev/null 2>&1; s=$?
expect "git merge --ff-only refuses (exit $s), changing nothing" "$([[ $s == 128 && "$(git rev-parse HEAD)" == "$owner" && -z "$(git status --porcelain)" ]] && echo 1)"
echo "\$ git merge m0-records-update   (a plain merge, which the README never uses)"
sim merge --no-edit m0-records-update > "$scratch/conflict.log" 2>&1; s=$?
grep -E 'CONFLICT|Automatic merge failed' "$scratch/conflict.log" | sed 's/^/  /'
expect "the plain merge stops on the conflict (exit $s)" "$([[ $s == 1 ]] && grep -q 'CONFLICT' "$scratch/conflict.log" && echo 1)"
echo "\$ git merge --abort"; git merge --abort; s=$?
expect "git merge --abort puts m0-decisions back as it was, with nothing uncommitted (exit $s)" \
  "$([[ $s == 0 && "$(git rev-parse HEAD)" == "$owner" && -z "$(git status --porcelain)" ]] && echo 1)"
cd "$root" || exit 1
rm -rf "$scratch"
echo
echo "result: $( ((status == 0)) && echo pass || echo FAIL )"
exit $status
