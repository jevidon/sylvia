#!/bin/bash
# The state of the branches and of the sessions' checkout as git shows it at the assembly of the update of 24 October
# 2026 (26 October 2026 on the build Mac's clock), read-only: nothing is fetched, checked out, written or run in another
# checkout. What is printed for m0-decisions is what its commits' metadata and file list say, not a reading of their
# content: no device result is read or inferred here.
#   Docs/Stage0/evidence/M0-DeviceA/assembly/commands/branch-state.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
merge6=96bdc7e996f99fcd2571ea983cc32a04076a5a07
tip=044ed3cf86db838c93cda7e2ca4829474b234ae5   # m0-decisions when pull request #6 merged it
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/assembly/commands/branch-state.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $uncommitted"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ) (UTC; the build Mac's clock: $(date '+%Y-%m-%d %H:%M %Z'))"
  echo
  echo "== the sessions' checkout, as git worktree list shows it (the entry of ~/Git/sylvia-sessions only)"
  git worktree list --porcelain | awk -v p="$HOME/Git/sylvia-sessions" '$1 == "worktree" { show = ($2 == p) } show'
  echo
  echo "== branches"
  for b in main origin/main m0-sessions m0-decisions m0-sessions-instructions m0-sessions-records; do
    echo "$b: $(git rev-parse "$b") ($(git log -1 --format='%ci' "$b"))"
  done
  echo "m0-decisions behind main (an ancestor of it): $(git merge-base --is-ancestor m0-decisions main && echo yes || echo no)"
  echo "commits on m0-decisions that main lacks: $(git rev-list --count main..m0-decisions)"
  echo "commits on m0-sessions that main lacks: $(git rev-list --count main..m0-sessions)"
  echo
  echo "== m0-decisions after ${tip:0:8}, the commit pull request #6 merged (${merge6:0:8}): its commits, oldest last"
  git log --format='%h %ci %an %s' "$tip..m0-decisions"
  echo
  echo "== the files those commits change (git diff --stat ${tip:0:8} m0-decisions)"
  git diff --stat "$tip" m0-decisions
  echo
  echo "== of them, files the update of 24 October 2026 or its assembly also changed on m0-sessions since 6cede84a"
  comm -12 <(git diff --name-only "$tip" m0-decisions | sort) <(git diff --name-only 6cede84a6f6ac610976b233d875e26dd89419dbd HEAD | sort)
  echo
  echo "== of them, paths runbook 0.8 checks (what G0.5 recovery's drop-in builds, copies or runs)"
  git diff --stat "$tip" m0-decisions -- Scripts/ci.d/71-g05-recovery.sh Scripts/lib Scripts/tools Spikes/G05-Recovery \
    Contracts/schemas/backup-manifest.v1.schema.json Contracts/fixtures/backup-manifest.v1
  echo
  echo "exit: 0"
} > "$log" 2>&1
