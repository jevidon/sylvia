#!/bin/bash
# What happens where the LFS filter is required (filter.lfs.required=true, as `git lfs install --local` sets it) but
# git-lfs is missing from PATH: in a temporary repository with an LFS-tracked image, `git add` of a new image and
# `git checkout` of a committed one must fail instead of writing a pointer or the raw file.
#   required-filter-check.sh <scratch-dir>
# Isolated from the user's and system git configuration; writes only under <scratch-dir>, which it deletes at the end.
set -uo pipefail
scratch="$(mkdir -p "$1" && cd "$1" && pwd -P)"
export GIT_CEILING_DIRECTORIES="$scratch" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
repo="$scratch/repo"
rm -rf "$repo" "$scratch/bin"
git -c init.defaultBranch=main init -q "$repo"
cd "$repo" || exit 1
git lfs install --local --skip-repo >/dev/null
printf '*.png filter=lfs diff=lfs merge=lfs -text\n' > .gitattributes
printf '\211PNG\r\n\032\none' > a.png
git add -A && git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m one
echo "repository $repo: a.png committed as an LFS pointer ($(git lfs ls-files --name-only)); filter.lfs.required=$(git config --get filter.lfs.required)"
mkdir -p "$scratch/bin"
ln -s "$(command -v git)" "$scratch/bin/git"
export PATH="$scratch/bin:/usr/bin:/bin"
echo "PATH=$PATH: git-lfs $(command -v git-lfs >/dev/null 2>&1 && echo found || echo 'not found')"
status=0
echo "\$ git add b.png (a new image)"
printf '\211PNG\r\n\032\ntwo' > b.png
git add b.png; add=$?
echo "[exit $add]; staged: $(git diff --cached --name-only | tr '\n' ' ')"
echo "\$ git checkout -- a.png (after deleting it from the working tree)"
rm a.png
git checkout -- a.png; co=$?
echo "[exit $co]; a.png in the working tree: $(test -e a.png && echo present || echo absent)"
if (( add != 0 && co != 0 )) && [[ -z "$(git diff --cached --name-only)" && ! -e a.png ]]; then
  echo "RESULT: PASS: without git-lfs, adding and checking out an LFS file both fail and write nothing"
else
  echo "RESULT: FAIL"
  status=1
fi
cd / && rm -rf "$scratch"
exit "$status"
