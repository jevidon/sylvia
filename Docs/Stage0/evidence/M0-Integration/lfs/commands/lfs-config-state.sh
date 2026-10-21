#!/bin/bash
# Step 3 of the Git LFS adoption (ADR-0002): where the Git LFS configuration and hooks live. Read-only.
#   lfs-config-state.sh <label>
# Prints, for the repository of the current directory: git-lfs's version; every filter.lfs.* and lfs.* entry with
# the file it comes from (`git config --show-origin`), and the same per scope (system, global, local); whether the
# user's global configuration files exist; extensions.worktreeConfig and core.hooksPath; and every hook that is not a
# *.sample file in the hooks directory, with its size, modification time and SHA-256.
set -uo pipefail
label="${1:-state}"
echo "== Git LFS configuration and hooks: $label ($(date -u +%Y-%m-%dT%H:%M:%SZ); $(date '+%Y-%m-%d %H:%M:%S %Z'))"
echo "repository: $(git rev-parse --show-toplevel); common git directory: $(cd "$(git rev-parse --git-common-dir)" && pwd)"
echo "$(git --version); $(git lfs version 2>&1 || echo 'git-lfs: not available')"
echo
echo "\$ git config --show-origin --get-regexp '^(filter\\.lfs|lfs\\.)'"
git config --show-origin --get-regexp '^(filter\.lfs|lfs\.)' || echo "(no entry)"
for scope in system global local; do
  echo
  echo "\$ git config --$scope --show-origin --get-regexp '^(filter\\.lfs|lfs\\.)'"
  git config --"$scope" --show-origin --get-regexp '^(filter\.lfs|lfs\.)' 2>&1 || echo "(no entry at the $scope scope)"
done
echo
echo "user configuration files:"
for f in "$HOME/.gitconfig" "${XDG_CONFIG_HOME:-$HOME/.config}/git/config"; do
  if [[ -e "$f" ]]; then echo "  $f: EXISTS"; else echo "  $f: does not exist"; fi
done
echo "system configuration (git config --system --list --show-origin):"
git config --system --list --show-origin 2>&1 | sed 's/^/  /'
echo "extensions.worktreeConfig: $(git config --get extensions.worktreeConfig || echo unset)"
echo "core.hooksPath: $(git config --get core.hooksPath || echo unset)"
hooks="$(cd "$(git rev-parse --git-path hooks)" && pwd)"
echo
echo "hooks directory: $hooks (git rev-parse --git-path hooks); hooks that are not *.sample:"
found=0
for h in "$hooks"/*; do
  [[ -f "$h" && "$h" != *.sample ]] || continue
  found=1
  echo "  $(basename "$h"): $(stat -f '%z bytes, mode %Sp, modified %Sm' -t '%Y-%m-%d %H:%M:%S %z' "$h"), sha256 $(shasum -a 256 "$h" | cut -d' ' -f1)"
  sed 's/^/      | /' "$h"
done
(( found )) || echo "  (none)"
