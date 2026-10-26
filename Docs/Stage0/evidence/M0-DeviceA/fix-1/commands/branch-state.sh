#!/bin/bash
# The branches and the sessions' checkout as git shows them at the fix of the fidelity findings of the review of the
# update of 24 October 2026 (26 October 2026 on the build Mac's clock), read-only: nothing is fetched, checked out or
# run in another checkout, and no ref, index or working-tree file is written. The successor of
# Docs/Stage0/evidence/M0-DeviceA/assembly/commands/branch-state.sh, with what finding FID-DA-01 rests on added:
#   - the parent of the first commit on m0-decisions after 044ed3cf, the commit pull request #6 merged;
#   - the session log as committed on m0-decisions: of its dated rows, the first six cells (run, session, date, who,
#     the commit built from, the devices), which say when, from which commit and on which device each sitting ran, and
#     not its seventh and eighth (the steps run and their results, which are not read here);
#   - what runbook 0.3 said in its steps 1 and 6 at 96bdc7e9 (pull request #6's merge, the checkout's commit on 24
#     October 2026 as relayed to the update): the branch it had the owner check out and commit the records on;
#   - whether a merge of m0-decisions into HEAD (m0-sessions with this fix, when run on the fix's commit) would conflict
#     (git merge-tree --write-tree, which writes the merged tree's objects to the object store and nothing else; the
#     merge itself is not made here).
#   Docs/Stage0/evidence/M0-DeviceA/fix-1/commands/branch-state.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
merge6=96bdc7e996f99fcd2571ea983cc32a04076a5a07
tip=044ed3cf86db838c93cda7e2ca4829474b234ae5   # m0-decisions when pull request #6 merged it
start=6cede84a6f6ac610976b233d875e26dd89419dbd  # m0-sessions before the update of 24 October 2026
reviewed=8082bdb6a3f4a8ee8edfef6a9a5d3489f445ce22  # the commit the review read
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/fix-1/commands/branch-state.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $uncommitted"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ) (UTC; the build Mac's clock: $(date '+%Y-%m-%d %H:%M %Z'))"
  echo
  echo "== the sessions' checkout, as git worktree list shows it (the entry of ~/Git/sylvia-sessions only)"
  git worktree list --porcelain | awk -v p="$HOME/Git/sylvia-sessions" '$1 == "worktree" { show = ($2 == p) } show'
  echo
  echo "== branches"
  for b in main origin/main m0-sessions m0-decisions; do
    echo "$b: $(git rev-parse "$b") ($(git log -1 --format='%ci' "$b"))"
  done
  echo "the commit the review read: $reviewed; m0-sessions descends from it: $(git merge-base --is-ancestor "$reviewed" m0-sessions && echo yes || echo no)"
  echo "m0-decisions behind main (an ancestor of it): $(git merge-base --is-ancestor m0-decisions main && echo yes || echo no)"
  echo "commits on m0-decisions that main lacks: $(git rev-list --count main..m0-decisions)"
  echo "commits on m0-decisions that m0-sessions lacks (git log --oneline m0-sessions..m0-decisions): $(git rev-list --count m0-sessions..m0-decisions)"
  echo "commits on m0-sessions that main lacks: $(git rev-list --count main..m0-sessions)"
  echo
  echo "== m0-decisions after ${tip:0:8}, the commit pull request #6 merged (${merge6:0:8}): its commits and their parents, oldest last"
  git log --format='%h (parent %p) %ci %an %s' "$tip..m0-decisions"
  first="$(git rev-list --reverse "$tip..m0-decisions" | head -n 1)"
  if [[ -n "$first" ]]; then
    echo "the first of them: ${first:0:8}, whose parent is $(git rev-parse --short=8 "$first^") ($( [[ "$(git rev-parse "$first^")" == "$tip" ]] && echo "${tip:0:8}, the tip of m0-decisions that pull request #6 merged" || echo "NOT ${tip:0:8}"))"
  fi
  echo
  echo "== the files those commits change (git diff --stat ${tip:0:8} m0-decisions)"
  git diff --stat "$tip" m0-decisions
  echo
  echo "== of them, files the update of 24 October 2026, its assembly or this fix also changed on m0-sessions since ${start:0:8}"
  comm -12 <(git diff --name-only "$tip" m0-decisions | sort) <(git diff --name-only "$start" HEAD | sort)
  echo
  echo "== of them, paths runbook 0.8 checks (what G0.5 recovery's drop-in builds, copies or runs)"
  git diff --stat "$tip" m0-decisions -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery \
    Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1
  echo
  echo "== the session log as committed on m0-decisions (git show m0-decisions:Docs/Stage0/evidence/M0-runbook/sessions.md):"
  echo "   its dated rows, the first six cells only (run | session | date | who | commit | devices); the steps run and their"
  echo "   results, the last two cells, are not read here"
  git show m0-decisions:Docs/Stage0/evidence/M0-runbook/sessions.md | python3 -I -c '
import sys
rows = [l for l in sys.stdin.read().splitlines() if l.startswith("| ")][2:]
dated = 0
for r in rows:
    cells = [c.strip() for c in r.strip()[1:-1].split("|")]
    if len(cells) >= 6 and cells[2]:
        dated += 1
        print("   " + " | ".join(cells[:6]))
print(f"   ({dated} dated rows of {len(rows)})")
'
  echo "-- the same file at HEAD (this branch): dated rows, first six cells"
  python3 -I -c '
import sys
rows = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith("| ")][2:]
dated = 0
for r in rows:
    cells = [c.strip() for c in r.strip()[1:-1].split("|")]
    if len(cells) >= 6 and cells[2]:
        dated += 1
        print("   " + " | ".join(cells[:6]))
print(f"   ({dated} dated rows of {len(rows)})")
' Docs/Stage0/evidence/M0-runbook/sessions.md
  echo
  echo "== runbook 0.3 at ${merge6:0:8} (main after pull request #6): the start of its steps 1 and 6"
  git show "$merge6:Docs/Stage0/M0-device-runbook.md" | grep -E '^(1\. `git checkout|6\. \*\*Your session records)' | cut -c1-200
  echo
  echo "== a merge of m0-decisions into HEAD, computed and not made (git merge-tree --write-tree --name-only --messages HEAD m0-decisions)"
  git merge-tree --write-tree --name-only --messages HEAD m0-decisions
  echo "merge-tree exit: $? (0: no conflict; 1: conflicts)"
  echo
  echo "exit: 0"
} > "$log" 2>&1
