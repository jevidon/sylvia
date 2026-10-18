#!/bin/bash
# Steps 6 and 7 of the Git LFS adoption (ADR-0002), in an existing checkout of m0-integrate with LFS set up:
# the drop-in (self-test and check), the mutation check of its self-test, Scripts/setup-repo.sh, and Scripts/ci.sh
# with filter words (the 00-* drop-in runs first; a filter that matches nothing still exits 2; the drop-ins that read
# documents, scripts and the workflow still pass). Each command is recorded with run-logged.sh.
#   ci-worktree-checks.sh <checkout> <log-dir>
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
checkout="$(cd "$1" && pwd)"
out="$2"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
log() { "$here/run-logged.sh" "$out/$1" "$checkout" "${@:2}"; echo "$1: exit $?"; }
log ci-00-git-lfs-worktree.log Scripts/ci.d/00-git-lfs.sh
log dropin-mutations.log "$here/dropin-mutations.sh" "$checkout" "$checkout/.build/scratch/lfs-dropin-mutations"
log setup-repo-worktree.log Scripts/setup-repo.sh
log ci-sh-contracts-lock-hardrules-worktree.log Scripts/ci.sh contracts dependency-lock hard-rules
log ci-sh-no-match-worktree.log Scripts/ci.sh nosuchstep
log ci-sh-git-lfs-only-worktree.log Scripts/ci.sh git-lfs
