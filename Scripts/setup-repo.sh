#!/usr/bin/env bash
# Sets up a checkout of Sylvia for Git LFS (ADR-0002). Run it once after cloning, and again whenever
# Scripts/ci.d/00-git-lfs.sh says so; running it again changes nothing that is already right.
#
#   1. Checks that git-lfs is installed; if not, says to run `brew install git-lfs` and stops.
#   2. Runs `git lfs install --local`: the LFS filter in this repository's own .git/config and git-lfs's hooks in its
#      .git/hooks, which every worktree of the repository shares. Never the user's global or the system configuration.
#      git-lfs refuses to replace a hook that is not its own, and this script never forces it.
#   3. Runs `git lfs pull` only when a file stored with Git LFS is missing from the working tree or still a pointer
#      file there (`Scripts/ci.d/00-git-lfs.sh --list-pointers`). git-lfs downloads from the remote the branch tracks,
#      or origin; for a clone of GitHub's jevidon/sylvia that is GitHub's LFS storage.
#   4. Runs Scripts/ci.d/00-git-lfs.sh, which checks the result (after its own self-test).
#
# Snapshot references and evidence images added later are stored with LFS automatically: .gitattributes names them,
# and the filter set up in step 2 turns them into LFS pointers when they are committed.
set -euo pipefail
export LC_ALL=C
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
check="$root/Scripts/ci.d/00-git-lfs.sh"

echo "==> 1. git-lfs"
if ! command -v git-lfs >/dev/null 2>&1 || ! git lfs version >/dev/null 2>&1; then
  echo "git-lfs is not installed. Install it with" >&2
  echo "    brew install git-lfs" >&2
  echo "and run Scripts/setup-repo.sh again. (Do not run 'git lfs install' without --local: that writes your global git" >&2
  echo "configuration. This script sets up only this repository.)" >&2
  exit 1
fi
git lfs version
if [[ -n "${GIT_LFS_SKIP_SMUDGE:-}" && "${GIT_LFS_SKIP_SMUDGE}" != 0 ]]; then
  echo "note: GIT_LFS_SKIP_SMUDGE=$GIT_LFS_SKIP_SMUDGE is set in this shell; checkouts made while it is set write pointer"
  echo "      files instead of the LFS files. Unset it, or run this script again after such a checkout."
fi

echo "==> 2. git lfs install --local (repository: $root)"
if ! git lfs install --local; then
  echo "git lfs install --local failed (see above). If a hook that is not git-lfs's own already exists, merge the two" >&2
  echo "by hand ('git lfs update --manual' prints what git-lfs needs); this script does not overwrite hooks." >&2
  exit 1
fi

echo "==> 3. LFS files in the working tree"
pending="$("$check" --list-pointers "$root")"
if [[ -z "$pending" ]]; then
  echo "every file stored with Git LFS is present: nothing to download"
else
  echo "files stored with Git LFS that are pointer files: $(printf '%s\n' "$pending" | grep -c '^pointer ' || true);" \
    "missing: $(printf '%s\n' "$pending" | grep -c '^missing ' || true). Running git lfs pull."
  git lfs pull
  remaining="$("$check" --list-pointers "$root")"
  if printf '%s\n' "$remaining" | grep -q '^pointer '; then
    echo "after git lfs pull these files are still pointer files:" >&2
    printf '%s\n' "$remaining" | grep '^pointer ' | sed -n '1,10p' | sed 's/^pointer /    /' >&2
    echo "Their LFS objects could not be downloaded; 'git lfs fetch' reports why." >&2
    exit 1
  fi
  if printf '%s\n' "$remaining" | grep -q '^missing '; then
    echo "note: files stored with Git LFS that are still missing after git lfs pull (deleted in this working tree?):"
    printf '%s\n' "$remaining" | grep '^missing ' | sed -n '1,10p' | sed 's/^missing /    /'
  fi
  echo "git lfs pull replaced the pointer files with the files"
fi

echo "==> 4. Scripts/ci.d/00-git-lfs.sh"
"$check"
