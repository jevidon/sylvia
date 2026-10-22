#!/bin/bash
# The second fix of the decisions round (23 October 2026 on the build Mac's clock; integration log section 19): this
# worktree was checked out with its Git LFS files as pointer files again, so 00-git-lfs would fail before any other
# drop-in runs. As fix-1/commands/lfs-checkout.sh did, this checks that every object the pointers name is in the
# repository's local LFS store (git lfs fsck --objects) and then fills the working tree from that store
# (git lfs checkout), which downloads nothing; the repository's configuration is not touched.
#   Docs/Stage0/evidence/M0-Decisions/fix-2/commands/lfs-checkout.sh > <log> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
echo "command: Docs/Stage0/evidence/M0-Decisions/fix-2/commands/lfs-checkout.sh"
echo "commit: $(git rev-parse HEAD); date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git lfs version
count() {  # LFS files still pointer files in the working tree
  git lfs ls-files | awk '$2 == "-"' | wc -l | tr -d ' '
}
echo "LFS files: $(git lfs ls-files | wc -l | tr -d ' '); still pointer files before: $(count)"
echo "-- git lfs fsck --objects"
git lfs fsck --objects
fsck=$?
echo "fsck exit: $fsck"
(( fsck == 0 )) || exit 1
echo "-- git lfs checkout"
git lfs checkout
echo "checkout exit: $?"
echo "still pointer files after: $(count)"
echo "git status --porcelain lines: $(git status --porcelain | wc -l | tr -d ' ')"
