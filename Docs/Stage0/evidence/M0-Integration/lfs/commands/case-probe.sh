#!/bin/bash
# Verification finding R3-03 of the Git LFS adoption: how letter case in the directory part of a path affects the LFS
# patterns of .gitattributes, for git and for git-lfs, on this Mac.
#   case-probe.sh <commit> <scratch-dir>
# Builds a temporary repository in <scratch-dir> whose only commit holds the .gitattributes of <commit> and small
# stand-in PNG files (plain git blobs, no LFS) at the paths below: two with the directory names as the patterns write
# them, one with an upper-case extension, and three whose directory names differ only in letter case. The paths are put
# into the index with `git update-index --cacheinfo`, because this Mac's file system cannot hold docs/ beside Docs/.
# Then, with core.ignorecase true and false: `git check-attr --source HEAD filter` for each path (which paths git gives
# the LFS filter), and `git lfs fsck --pointers` (which of them git-lfs reports as plain blobs that should have been
# pointers; 00-git-lfs's committed-blob check uses it). No global or system git configuration is read. Writes only
# under <scratch-dir>, which it deletes at the end.
set -uo pipefail
commit="$(git rev-parse --verify "$1^{commit}")" || exit 2
scratch="$2"
rm -rf "$scratch"
mkdir -p "$scratch"
scratch="$(cd "$scratch" && pwd -P)"
git show "$commit:.gitattributes" > "$scratch/gitattributes"
export GIT_CEILING_DIRECTORIES="$scratch" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
repo="$scratch/repo"
git -c init.defaultBranch=main init -q "$repo"
cd "$repo" || exit 2
paths=(
  "Docs/Stage0/evidence/G06-Design/as-written.png"
  "Docs/Stage0/evidence/G06-Design/UPPER-CASE-EXTENSION.PNG"
  "Packages/Design/Tests/X/__Snapshots__/as-written.png"
  "docs/stage0/evidence/lower-case-directories.png"
  "Docs/Stage0/Evidence/capital-e-evidence.png"
  "Packages/Design/Tests/X/__snapshots__/lower-case-snapshots.png"
)
blob="$(git hash-object -w "$scratch/gitattributes")"
git update-index --add --cacheinfo "100644,$blob,.gitattributes"
for p in "${paths[@]}"; do
  blob="$(printf '\211PNG\r\n\032\nstand-in for %s\n' "$p" | git hash-object -w --stdin)"
  git update-index --add --cacheinfo "100644,$blob,$p"
done
git -c user.name=probe -c user.email=probe@example.invalid -c commit.gpgsign=false commit -q -m "plain blobs"
echo "# case-probe.sh: .gitattributes of $commit (sha256 $(shasum -a 256 "$scratch/gitattributes" | cut -d' ' -f1))"
echo "$(git --version); $(git lfs version); $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "temporary repository: $repo; its own core.ignorecase: $(git config --local --get core.ignorecase || echo unset)"
echo "tracked paths (git ls-files), all plain git blobs:"
git ls-files | sed 's/^/  /'
for ic in true false; do
  echo
  echo "== core.ignorecase=$ic: git check-attr --source HEAD filter"
  for p in "${paths[@]}"; do git -c core.ignorecase="$ic" check-attr --source HEAD filter -- "$p" | sed 's/^/  /'; done
  echo "== core.ignorecase=$ic: git lfs fsck --pointers"
  status=0
  out="$(git -c core.ignorecase="$ic" lfs fsck --pointers 2>&1)" || status=$?
  printf '%s\n' "$out" | sed -e 's/ (treeish [0-9a-f]*)//' -e 's/^/  /'
  echo "  [exit $status]"
  for p in "${paths[@]}"; do
    if printf '%s\n' "$out" | grep -q -F "\"$p\""; then r="reported"; else r="not reported"; fi
    echo "  $p: $r"
  done
done
cd / && rm -rf "$scratch"
