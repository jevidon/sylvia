#!/bin/bash
# Step 8 of the Git LFS adoption (ADR-0002): clean checkouts of m0-integrate from the local repository, with no network.
#   clean-checkout.sh <source-repository> <scratch-dir> <phase>
# Phases (each prints every command before it runs it, and its exit status):
#   clone        git clone --no-local <source> <scratch>/lfs-clone; git lfs install --local in the clone; check out
#                m0-integrate (the LFS objects come from the source's own LFS storage over git-lfs's built-in
#                lfs-standalone-file transfer, which git-lfs uses for a local-path remote without any setting); then
#                Scripts/setup-repo.sh, Scripts/ci.d/00-git-lfs.sh, the SHA-256 of every LFS file against the adoption
#                manifest, git status, and Scripts/ci.sh contracts.
#   design       in that clone: Scripts/ci.sh design (00-git-lfs, 20-design with the snapshot suite against the smudged
#                references, 21-design-catalog) on simulators named $SIM_NAME, $SIM_NAME-SE and $SIM_NAME-iPad; then git
#                status (the drop-ins must leave every tracked file unchanged).
#   skip-smudge  a second clone made with GIT_LFS_SKIP_SMUDGE=1 (also set for git lfs install --local and the checkout
#                of m0-integrate): 00-git-lfs.sh must fail with its message, Scripts/ci.sh must stop after it, and
#                Scripts/setup-repo.sh must repair the checkout, after which 00-git-lfs.sh passes and every LFS file
#                matches the manifest.
#   no-setup     a third clone where Git LFS is never set up before m0-integrate is checked out (as on a Mac where
#                nobody ran git lfs install): the same failure and the same repair.
# SIM_NAME defaults to Sylvia-M0-lfs. Writes only under <scratch-dir>; reads the source repository.
set -uo pipefail
src="$1"
scratch="$(mkdir -p "$2" && cd "$2" && pwd)"
phase="$3"
SIM_NAME="${SIM_NAME:-Sylvia-M0-lfs}"
manifest="Docs/Stage0/evidence/M0-Integration/lfs/lfs-manifest.sha256"

run() {  # run <command...>: prints it, runs it, prints its exit status, returns it
  local status=0
  echo "\$ $*"
  "$@" || status=$?
  echo "[exit $status]"
  return "$status"
}

expect_status() {  # expect_status <wanted> <description> <command...>
  local want="$1" what="$2" status=0
  shift 2
  run "$@" || status=$?
  if [[ "$status" == "$want" ]]; then echo "CHECK PASS: $what (exit $status)"; else echo "CHECK FAIL: $what: exit $status, expected $want"; fi
  echo
}

manifest_check() {  # SHA-256 of every LFS file in the working tree against the adoption manifest
  local ok bad
  ok="$(shasum -a 256 -c "$manifest" 2>/dev/null | grep -c ': OK$' || true)"
  bad="$(shasum -a 256 -c "$manifest" 2>/dev/null | grep -vc ': OK$' || true)"
  echo "manifest $manifest: $ok files match their SHA-256, $bad do not (of $(wc -l < "$manifest" | tr -d ' '))"
  [[ "$bad" == 0 && "$ok" == "$(wc -l < "$manifest" | tr -d ' ')" ]]
}

pointer_count() { Scripts/ci.d/00-git-lfs.sh --list-pointers . | grep -c '^pointer ' || true; }

clean_tree() {  # git status must list nothing
  local s
  s="$(git status --porcelain)"
  echo "git status --porcelain: $(if [[ -z "$s" ]]; then echo "(nothing: the working tree matches HEAD)"; else printf '%s\n' "$s" | head -20; fi)"
  [[ -z "$s" ]]
}

echo "# clean-checkout.sh phase $phase ($(date -u +%Y-%m-%dT%H:%M:%SZ)); source $src (m0-integrate at $(git -C "$src" rev-parse m0-integrate))"
echo "$(git --version); $(git lfs version); git config --global --list: $(git config --global --list 2>&1 | head -1)"
echo

case "$phase" in
  clone)
    clone="$scratch/lfs-clone"
    rm -rf "$clone"
    expect_status 0 "clone with --no-local (origin is the local path)" git clone --no-local "$src" "$clone"
    cd "$clone" || exit 1
    echo "origin: $(git remote get-url origin); first checkout: $(git branch --show-current) at $(git rev-parse --short HEAD); .gitattributes there: $(test -f .gitattributes && echo yes || echo no)"
    expect_status 0 "git lfs install --local in the clone" git lfs install --local
    run git config --show-origin --get-regexp '^(filter\.lfs|lfs\.)'
    git lfs env 2>/dev/null | grep -E '^(Endpoint|LocalMediaDir|DownloadTransfers)='
    expect_status 0 "check out m0-integrate (smudges the LFS files from the source's LFS storage)" git checkout m0-integrate
    echo "HEAD: $(git rev-parse HEAD) $(git log -1 --format=%s)"
    echo "LFS objects now in the clone's own storage: $(find .git/lfs/objects -type f | wc -l | tr -d ' ')"
    echo
    expect_status 0 "Scripts/setup-repo.sh (idempotent: nothing to download)" Scripts/setup-repo.sh
    expect_status 0 "Scripts/ci.d/00-git-lfs.sh" Scripts/ci.d/00-git-lfs.sh
    if manifest_check; then echo "CHECK PASS: every LFS file matches the manifest"; else echo "CHECK FAIL: manifest"; fi
    if clean_tree; then echo "CHECK PASS: clean working tree"; else echo "CHECK FAIL: working tree"; fi
    echo
    expect_status 0 "Scripts/ci.sh contracts" Scripts/ci.sh contracts
    ;;
  design)
    cd "$scratch/lfs-clone" || exit 1
    echo "HEAD: $(git rev-parse HEAD); simulators: $SIM_NAME, $SIM_NAME-SE, $SIM_NAME-iPad"
    echo "Xcode: $(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcodebuild -version | tr '\n' ' ')"
    echo "load: $(uptime)"
    expect_status 0 "Scripts/ci.sh design" env SYLVIA_G06_SIM="$SIM_NAME" G02_LOOPBACK_ONLY=1 Scripts/ci.sh design
    echo "load: $(uptime)"
    if clean_tree; then echo "CHECK PASS: the design drop-ins left every tracked file unchanged"; else echo "CHECK FAIL: working tree"; fi
    ;;
  skip-smudge)
    clone="$scratch/lfs-clone-skip-smudge"
    rm -rf "$clone"
    expect_status 0 "GIT_LFS_SKIP_SMUDGE=1 git clone --no-local" env GIT_LFS_SKIP_SMUDGE=1 git clone --no-local "$src" "$clone"
    cd "$clone" || exit 1
    expect_status 0 "GIT_LFS_SKIP_SMUDGE=1 git lfs install --local" env GIT_LFS_SKIP_SMUDGE=1 git lfs install --local
    expect_status 0 "GIT_LFS_SKIP_SMUDGE=1 git checkout m0-integrate" env GIT_LFS_SKIP_SMUDGE=1 git checkout m0-integrate
    echo "HEAD: $(git rev-parse HEAD); pointer files in the working tree: $(pointer_count)"
    echo "first bytes of one snapshot reference: $(head -c 120 Packages/Design/Tests/SylviaDesignSnapshotTests/__Snapshots__/ComponentSnapshotTests/rating.light-default.png | tr '\n' '|')"
    echo
    expect_status 1 "Scripts/ci.d/00-git-lfs.sh fails on the pointer files" Scripts/ci.d/00-git-lfs.sh
    expect_status 1 "Scripts/ci.sh contracts stops after 00-git-lfs" Scripts/ci.sh contracts
    expect_status 0 "Scripts/setup-repo.sh repairs the checkout" Scripts/setup-repo.sh
    echo "pointer files in the working tree now: $(pointer_count)"
    expect_status 0 "Scripts/ci.d/00-git-lfs.sh after the repair" Scripts/ci.d/00-git-lfs.sh
    if manifest_check; then echo "CHECK PASS: every LFS file matches the manifest"; else echo "CHECK FAIL: manifest"; fi
    if clean_tree; then echo "CHECK PASS: clean working tree"; else echo "CHECK FAIL: working tree"; fi
    ;;
  no-setup)
    clone="$scratch/lfs-clone-no-setup"
    rm -rf "$clone"
    expect_status 0 "git clone --no-local (Git LFS never set up in this clone)" git clone --no-local "$src" "$clone"
    cd "$clone" || exit 1
    expect_status 0 "git checkout m0-integrate without any LFS filter" git checkout m0-integrate
    echo "HEAD: $(git rev-parse HEAD); filter.lfs settings: $(git config --get-regexp '^filter\.lfs' | wc -l | tr -d ' '); pointer files in the working tree: $(pointer_count)"
    echo
    expect_status 1 "Scripts/ci.d/00-git-lfs.sh fails (no filter, pointer files)" Scripts/ci.d/00-git-lfs.sh
    expect_status 0 "Scripts/setup-repo.sh repairs the checkout" Scripts/setup-repo.sh
    echo "pointer files in the working tree now: $(pointer_count)"
    expect_status 0 "Scripts/ci.d/00-git-lfs.sh after the repair" Scripts/ci.d/00-git-lfs.sh
    if manifest_check; then echo "CHECK PASS: every LFS file matches the manifest"; else echo "CHECK FAIL: manifest"; fi
    if clean_tree; then echo "CHECK PASS: clean working tree"; else echo "CHECK FAIL: working tree"; fi
    ;;
  *)
    echo "usage: clean-checkout.sh <source-repository> <scratch-dir> clone|design|skip-smudge|no-setup" >&2
    exit 2 ;;
esac
echo
echo "# phase $phase done ($(date -u +%Y-%m-%dT%H:%M:%SZ)); checks failed: see CHECK FAIL lines (none means all passed)"
