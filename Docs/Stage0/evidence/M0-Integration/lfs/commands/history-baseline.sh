#!/bin/bash
# Step 2 of the Git LFS adoption (ADR-0002): the history baseline, recorded before any change.
#   history-baseline.sh <base-commit> <out-dir>
# Writes <out-dir>/branches-before.tsv (branch, commit) for main, m0 and every m0-* branch (the m0-int-* branches and
# m0-integrate included), and <out-dir>/history-before.log: the same list, `git rev-list --count m0-integrate`, the
# SHA-256 of `git ls-tree -r <base-commit>` (every path, mode and blob of the base tree) and of the base commit's
# full history listing (`git rev-list --parents <base-commit>`), and, for context only, every other local branch and
# tag (worktree-* and codex/* branches belong to other sessions and can move on their own). Read-only.
set -euo pipefail
base="$1"; out="$2"
mkdir -p "$out"
cd "$(git rev-parse --show-toplevel)"
base_full="$(git rev-parse --verify "$base^{commit}")"
{
  for b in main m0; do printf '%s\t%s\n' "$b" "$(git rev-parse --verify "refs/heads/$b")"; done
  git for-each-ref --format='%(refname:short)%09%(objectname)' 'refs/heads/m0-*'
} > "$out/branches-before.tsv"
{
  echo "# History baseline before the Git LFS adoption"
  echo "recorded $(date -u +%Y-%m-%dT%H:%M:%SZ) ($(date '+%Y-%m-%d %H:%M %Z')) on $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(git --version)"
  echo "worktree: $(pwd) on branch $(git branch --show-current || true), HEAD $(git rev-parse HEAD)"
  echo
  echo "## Branches the adoption must leave unchanged (all but m0-integrate), and m0-integrate (branches-before.tsv)"
  cat "$out/branches-before.tsv"
  echo
  echo "git rev-list --count m0-integrate: $(git rev-list --count m0-integrate)"
  echo "base commit: $base_full (m0-integrate is at it: $([[ "$(git rev-parse m0-integrate)" == "$base_full" ]] && echo yes || echo NO))"
  echo "sha256 of 'git ls-tree -r $base_full': $(git ls-tree -r "$base_full" | shasum -a 256 | cut -d' ' -f1)"
  echo "sha256 of 'git rev-list --parents $base_full' ($(git rev-list --count "$base_full") commits): $(git rev-list --parents "$base_full" | shasum -a 256 | cut -d' ' -f1)"
  echo
  echo "## Every other local branch and tag (context only; other sessions own the worktree-* and codex/* branches)"
  git for-each-ref --format='%(refname)%09%(objectname)' refs/heads refs/tags | grep -v -E '^refs/heads/(main|m0|m0-[^	]*)	' || true
} > "$out/history-before.log"
cat "$out/history-before.log"
