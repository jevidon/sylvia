#!/bin/bash
# How m0-integrate reached the adoption's base commit (a gap noted by the verification of the Git LFS adoption):
# the reflog entries of m0-integrate from the adoption commit back to the commit before the base, the latest entries of
# origin/main and origin/m0-integrate, the first entries of the adoption agent's worktree HEAD, and the base commit's
# parents. Read-only; run from a checkout of this repository.
#   base-reflog.sh <base-commit> <adoption-commit> <adoption-worktree-name>
set -uo pipefail
base="$(git rev-parse --verify "$1^{commit}")" || exit 2
adoption="$(git rev-parse --verify "$2^{commit}")" || exit 2
wt="$3"
echo "# reflog around the adoption's base $base ($(date -u +%Y-%m-%dT%H:%M:%SZ)); $(git --version)"
echo
echo "\$ git log -1 --format='%H parents: %P; %s' $base"
git log -1 --format='%H parents: %P; %s' "$base"
echo
echo "\$ git reflog show --date=iso-local m0-integrate, from the entry of the adoption commit to the entry before the base's"
git reflog show --date=iso-local --format='%H %gd: %gs' m0-integrate |
  awk -v a="$adoption" -v b="$base" '
    $1 == a && !on { on = 1 }
    on { print; if (seen) exit; if ($1 == b) seen = 1 }' |
  awk '{ $1 = substr($1, 1, 7); print }'
echo
echo "\$ git reflog show --date=iso-local origin/main (latest 3)"
git reflog show --date=iso-local --format='%h %gd: %gs' refs/remotes/origin/main | head -n 3
echo
echo "\$ git reflog show --date=iso-local origin/m0-integrate (latest 2)"
git reflog show --date=iso-local --format='%h %gd: %gs' refs/remotes/origin/m0-integrate | head -n 2
echo
echo "\$ git reflog show --date=iso-local worktrees/$wt/HEAD (oldest 3 entries: the worktree's creation and first checkout)"
git reflog show --date=iso-local --format='%h %gd: %gs' "worktrees/$wt/HEAD" | tail -n 3
echo
first="$(git log -1 --format=%P "$base" | awk '{print $1}')"
second="$(git log -1 --format=%P "$base" | awk '{print $2}')"
echo "first parent $first: $(git log -1 --format='%s' "$first")"
echo "second parent $second: $(git log -1 --format='%s' "$second")"
if [[ -n "$second" ]] && git merge-base --is-ancestor "$second" "$base"; then
  echo "the second parent is an ancestor of the base: moving m0-integrate from it to the base only adds commits"
fi
