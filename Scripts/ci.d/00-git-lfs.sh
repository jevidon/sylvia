#!/usr/bin/env bash
# Git LFS checkout check (ADR-0002). Snapshot references (any __Snapshots__ directory) and Stage 0 evidence images
# (Docs/Stage0/evidence/) are stored with Git LFS. A checkout made without git-lfs, before the repository-local LFS
# filter was set up, or with GIT_LFS_SKIP_SMUDGE set holds small pointer files in their place, and the snapshot suite
# then fails in confusing ways. Scripts/ci.sh runs this drop-in first in every run, filtered or not, and stops the run
# if it fails. It fails, naming Scripts/setup-repo.sh, when:
#   - git-lfs is not installed;
#   - the repository-local LFS filter is not configured (filter.lfs.clean, smudge, process and required, as
#     `git lfs install --local` writes them into the repository's own .git/config);
#   - a file that `git lfs ls-files` lists (HEAD and the index), or that an LFS attribute in .gitattributes matches,
#     is still an LFS pointer in the working tree;
#   - a file that an LFS attribute matches is committed as a plain git blob instead of an LFS pointer
#     (`git lfs fsck --pointers` on HEAD), which happens when it was committed where Git LFS was not set up.
# A tracked LFS file missing from the working tree is reported on a WARN line, not as a failure.
#
# Before checking this checkout it runs its self-test: a temporary repository under .build/scratch with this
# repository's .gitattributes and small stand-in images at real paths, where a correct checkout must pass, pointer text
# in a plain-git file must not be reported, and each failure above, planted in turn, must fail with its message.
#
#   Scripts/ci.d/00-git-lfs.sh                       # self-test, then check this checkout
#   Scripts/ci.d/00-git-lfs.sh --self-test           # self-test only
#   Scripts/ci.d/00-git-lfs.sh --check <dir>         # check the repository at <dir> only
#   Scripts/ci.d/00-git-lfs.sh --list-pointers <dir> # print "pointer <path>" or "missing <path>" for each LFS file
#                                                    # that is a pointer or missing in the working tree there
#                                                    # (Scripts/setup-repo.sh uses it to decide on `git lfs pull`)
# Host only: no network, no simulator, no build. Paths containing a line feed are not supported.
set -euo pipefail
export LC_ALL=C
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

SELF="$SYLVIA_ROOT/Scripts/ci.d/$(basename "$0")"
SETUP="Scripts/setup-repo.sh"
POINTER_V1='version https://git-lfs.github.com/spec/v1'
POINTER_LEGACY='version https://hawser.github.com/spec/v1'
SHOW=10  # paths listed per failure

lfs_present() { command -v git-lfs >/dev/null 2>&1 && git lfs version >/dev/null 2>&1; }

count_lines() { if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }

# True when the file's first line is an LFS pointer's version line.
is_pointer_file() {
  local first=''
  IFS= read -r -n 64 first < "$1" || true
  [[ "$first" == "$POINTER_V1" || "$first" == "$POINTER_LEGACY" ]]
}

# Prints the tracked paths an LFS attribute matches.
attr_paths() {
  local dir="$1" path value
  # check-attr -z prints <path> NUL <attribute> NUL <value> NUL; the attribute's name (always "filter") goes to _.
  git -C "$dir" ls-files -z | git -C "$dir" check-attr -z --stdin filter |
    while IFS= read -r -d '' path && IFS= read -r -d '' _ && IFS= read -r -d '' value; do
      if [[ "$value" == lfs ]]; then printf '%s\n' "$path"; fi
    done
}

# Prints every path that git lfs ls-files lists (HEAD and the index) or an LFS attribute matches, once each.
lfs_paths() {
  local dir="$1" names attrs
  names="$(git -C "$dir" lfs ls-files --name-only)" || return 1
  attrs="$(attr_paths "$dir")" || return 1
  printf '%s\n%s\n' "$names" "$attrs" | sed '/^$/d' | sort -u
}

# Reads paths on stdin; prints "P <path>" for each that is a pointer in the working tree of $1 and "M <path>" for each
# that is missing there.
classify_paths() {
  local dir="$1" path
  while IFS= read -r path; do
    if [[ -z "$path" ]]; then
      continue
    elif [[ ! -e "$dir/$path" ]]; then
      printf 'M %s\n' "$path"
    elif [[ -f "$dir/$path" ]] && is_pointer_file "$dir/$path"; then
      printf 'P %s\n' "$path"
    fi
  done
}

# Prints up to $SHOW lines of $1, indented, and how many more there are.
show_some() {
  local total
  total="$(count_lines "$1")"
  printf '%s\n' "$1" | sed -n "1,${SHOW}p" | sed 's/^/    /'
  if (( total > SHOW )); then echo "    ... and $((total - SHOW)) more"; fi
}

# Checks the repository whose working tree is $1. Returns 0 on a correct checkout; prints what is wrong and what to do
# and returns 1 otherwise.
check_repo() {
  local dir="$1" common config i key want have local_have all listed matched report pointers missing fsck filter_ok=1
  local -a problems=()
  local -a keys=(filter.lfs.clean filter.lfs.smudge filter.lfs.process filter.lfs.required)
  local -a wants=('git-lfs clean -- %f' 'git-lfs smudge -- %f' 'git-lfs filter-process' 'true')
  if ! lfs_present; then
    echo "FAIL: git-lfs is not installed (no working git-lfs on PATH)."
    echo "  This repository stores its snapshot references and evidence images with Git LFS (ADR-0002); without"
    echo "  git-lfs a checkout holds small pointer files in their place. Install it with 'brew install git-lfs',"
    echo "  then run $SETUP from the repository root."
    return 1
  fi
  dir="$(cd "$dir" && pwd)"
  common="$(cd "$dir" && cd "$(git rev-parse --git-common-dir)" && pwd)"
  config="$common/config"
  echo "repository: $dir (git directory $common); $(git --version); $(git lfs version)"

  # 1. The repository-local filter, exactly as `git lfs install --local` writes it, and in effect.
  for i in 0 1 2 3; do
    key="${keys[$i]}"
    want="${wants[$i]}"
    if [[ "$key" == filter.lfs.required ]]; then
      local_have="$(git -C "$dir" config --local --type=bool --get "$key" 2>/dev/null || true)"
      have="$(git -C "$dir" config --type=bool --get "$key" 2>/dev/null || true)"
    else
      local_have="$(git -C "$dir" config --local --get "$key" 2>/dev/null || true)"
      have="$(git -C "$dir" config --get "$key" 2>/dev/null || true)"
    fi
    if [[ "$local_have" != "$want" || "$have" != "$want" ]]; then
      echo "FAIL: the repository-local Git LFS filter is not configured: $key is '${local_have:-unset}' in $config (in effect: '${have:-unset}'), expected '$want'."
      filter_ok=0
    fi
  done
  if (( filter_ok )); then
    echo "repository-local LFS filter: set in $config (clean, smudge, process, required)"
  else
    problems+=(filter)
  fi

  # 2. No LFS file is still a pointer in the working tree.
  if ! all="$(lfs_paths "$dir")"; then
    echo "FAIL: could not list the LFS files ('git lfs ls-files' or 'git check-attr' failed in $dir)."
    problems+=(listing)
    all=""
  fi
  listed="$(count_lines "$(git -C "$dir" lfs ls-files --name-only 2>/dev/null || true)")"
  matched="$(count_lines "$(attr_paths "$dir" || true)")"
  report="$(printf '%s\n' "$all" | classify_paths "$dir")"
  pointers="$(printf '%s\n' "$report" | sed -n 's/^P //p')"
  missing="$(printf '%s\n' "$report" | sed -n 's/^M //p')"
  echo "LFS files: $listed listed by git lfs ls-files, $matched tracked paths matched by an LFS attribute, $(count_lines "$all") distinct"
  if [[ -n "$pointers" ]]; then
    echo "FAIL: files stored with Git LFS are still LFS pointer files in the working tree, not the files themselves ($(count_lines "$pointers")):"
    show_some "$pointers"
    problems+=(pointers)
  else
    echo "pointer files in the working tree: none"
  fi
  if [[ -n "$missing" ]]; then
    echo "WARN 00-git-lfs: files stored with Git LFS are missing from the working tree (deleted locally?) ($(count_lines "$missing")), first: $(printf '%s\n' "$missing" | head -n 1)"
  fi
  if [[ -n "${GIT_LFS_SKIP_SMUDGE:-}" && "${GIT_LFS_SKIP_SMUDGE}" != 0 ]]; then
    echo "WARN 00-git-lfs: GIT_LFS_SKIP_SMUDGE=$GIT_LFS_SKIP_SMUDGE is set; checkouts made with it write pointer files instead of the LFS files."
  fi

  # 3. Every file an LFS attribute matches is committed as an LFS pointer.
  if fsck="$(git -C "$dir" lfs fsck --pointers 2>&1)"; then
    echo "git lfs fsck --pointers (HEAD): $fsck"
  else
    echo "FAIL: git lfs fsck --pointers found files that .gitattributes stores with Git LFS but HEAD holds as plain git blobs, or malformed pointers:"
    show_some "$fsck"
    problems+=(fsck)
  fi

  if (( ${#problems[@]} == 0 )); then
    echo "00-git-lfs: pass: every LFS file is present in the working tree and committed as an LFS pointer"
    return 0
  fi
  echo
  echo "00-git-lfs: FAIL (${problems[*]}). What to do:"
  if [[ " ${problems[*]} " == *" filter "* || " ${problems[*]} " == *" pointers "* || " ${problems[*]} " == *" listing "* ]]; then
    echo "  Run $SETUP from the repository root. It runs 'git lfs install --local', which writes the LFS filter into this"
    echo "  repository's own configuration ($config, never your global one), and 'git lfs pull', which replaces the"
    echo "  pointer files with the files. A pointer file means the checkout was made without git-lfs, before the filter"
    echo "  was set up, or with GIT_LFS_SKIP_SMUDGE set."
  fi
  if [[ " ${problems[*]} " == *" fsck "* ]]; then
    echo "  The files git lfs fsck lists were committed where Git LFS was not set up. Run $SETUP, then"
    echo "  'git add --renormalize -- <path>' for each of them and commit, so that they are stored as LFS pointers."
  fi
  return 1
}

# --- self-test -------------------------------------------------------------------------------------------------------

# Writes a small stand-in image (the format's signature and a unique tail) at $1.
write_image() {
  mkdir -p "$(dirname "$1")"
  case "$1" in
    *.[jJ][pP][gG] | *.[jJ][pP][eE][gG]) printf '\377\330\377\340self-test %s\n' "$2" > "$1" ;;
    *) printf '\211PNG\r\n\032\nself-test %s\n' "$2" > "$1" ;;
  esac
}

# run_case <label> <expected exit: 0 or 1> <text the output must contain when 1> <command...>
run_case() {
  local label="$1" want="$2" needle="$3" out expected status=0
  shift 3
  out="$("$@" 2>&1)" || status=$?
  if [[ "$want" == 0 && "$status" == 0 ]]; then
    echo "self-test: $label: the check passed, as it must"
  elif [[ "$want" == 1 && "$status" == 1 && "$out" == *"$needle"* && "$out" == *"$SETUP"* ]]; then
    echo "self-test: $label: the check failed, as it must, naming $SETUP: $(printf '%s\n' "$out" | grep -m 1 '^FAIL:')"
  else
    expected="exit $want"
    if [[ -n "$needle" ]]; then expected="exit $want, with \"$needle\" and $SETUP in the output"; fi
    echo "self-test: $label: WRONG RESULT: expected $expected; got exit $status:"
    printf '%s\n' "$out" | sed 's/^/    | /'
    return 1
  fi
  printf '%s\n' "$out" | sed 's/^/    | /'
}

expect() {  # expect <description> <actual> <wanted>
  if [[ "$2" != "$3" ]]; then
    echo "self-test: precondition failed: $1: got '$2', expected '$3'"
    exit 1
  fi
}

commit_all() {  # commit_all <repo> <message>
  git -C "$1" -c user.name=self-test -c user.email=self-test@example.invalid -c commit.gpgsign=false commit -q -m "$2"
}

# The self-test body; runs in its own process with the temporary directory $1.
self_test_body() {
  local scratch repo bin snap evid photo board log copied staged stray raw out
  local -a no_filter=(-c filter.lfs.clean= -c filter.lfs.smudge= -c filter.lfs.process= -c filter.lfs.required=false)
  scratch="$(cd "$1" && pwd -P)"
  repo="$scratch/repo"
  bin="$scratch/bin"
  # Never touch this repository or the user's configuration: no repository discovery above the temporary directory,
  # no global or system git configuration (hooks paths, signing, templates), no skip-smudge from the environment.
  export GIT_CEILING_DIRECTORIES="$scratch" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_LFS_SKIP_SMUDGE \
    GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
  mkdir -p "$repo" "$bin"
  git -c init.defaultBranch=main init -q "$repo"
  expect "the temporary repository is its own" "$(cd "$repo" && git rev-parse --show-toplevel)" "$repo"
  git -C "$repo" lfs install --local --skip-repo >/dev/null   # the filter only; no hooks in the temporary repository
  cp "$SYLVIA_ROOT/.gitattributes" "$repo/.gitattributes"
  snap="Packages/Design/Tests/SylviaDesignSnapshotTests/__Snapshots__/ComponentSnapshotTests/sample.light-default.png"
  evid="Docs/Stage0/evidence/G06-Design/screens/iphone/light/sample.png"
  photo="Docs/Stage0/evidence/G02-Transfer/DEVICE-PHOTO.JPG"
  board="Docs/Design/images/SampleBoard.png"
  log="Docs/Stage0/evidence/G06-Design/sample-run.log"
  write_image "$repo/$snap" snapshot
  write_image "$repo/$evid" evidence
  write_image "$repo/$photo" photo
  write_image "$repo/$board" board
  printf 'a log line\n' > "$repo/$log"
  git -C "$repo" add -A
  commit_all "$repo" "self-test"
  echo "self-test: temporary repository $repo with this repository's .gitattributes ($(git --version); $(git lfs version))"
  expect "the files git lfs ls-files lists in the temporary repository" \
    "$(git -C "$repo" lfs ls-files --name-only | sort | tr '\n' ' ')" \
    "$(printf '%s\n' "$snap" "$evid" "$photo" | sort | tr '\n' ' ')"

  run_case "1, a correct checkout" 0 "" "$SELF" --check "$repo"

  cp "$repo/$board" "$scratch/board.bak"
  git -C "$repo" cat-file -p "HEAD:$evid" > "$repo/$board"
  run_case "2, pointer text in a plain-git file (outside the LFS patterns) is not reported" 0 "" "$SELF" --check "$repo"
  cp "$scratch/board.bak" "$repo/$board"

  cp "$repo/$snap" "$scratch/snap.bak"
  git -C "$repo" cat-file -p "HEAD:$snap" > "$repo/$snap"   # what a checkout without the LFS filter writes
  run_case "3, a snapshot reference left as a pointer file" 1 "$snap" "$SELF" --check "$repo"
  cp "$scratch/snap.bak" "$repo/$snap"

  cp "$repo/$photo" "$scratch/photo.bak"
  git -C "$repo" cat-file -p "HEAD:$photo" > "$repo/$photo"
  run_case "4, an evidence photo (.JPG) left as a pointer file" 1 "$photo" "$SELF" --check "$repo"
  cp "$scratch/photo.bak" "$repo/$photo"

  copied="Docs/Stage0/evidence/G01-PDF/copied-from-another-checkout.png"
  mkdir -p "$(dirname "$repo/$copied")"
  git -C "$repo" cat-file -p "HEAD:$evid" > "$repo/$copied"
  git -C "$repo" add -- "$copied"
  run_case "5, a pointer file added at a new path (staged, not committed)" 1 "$copied" "$SELF" --check "$repo"
  git -C "$repo" rm -q -f --cached -- "$copied"
  rm -f "$repo/$copied"

  staged="Docs/Stage0/evidence/G01-EPUB/staged-without-lfs.png"
  write_image "$repo/$staged" staged
  git -C "$repo" "${no_filter[@]}" add -- "$staged"
  git -C "$repo" cat-file -p "HEAD:$evid" > "$repo/$staged"
  expect "git lfs ls-files does not list a path whose staged blob is not a pointer" \
    "$(git -C "$repo" lfs ls-files --name-only | grep -c -F -x "$staged" || true)" "0"
  run_case "6, a pointer file that only the LFS attribute catches (git lfs ls-files does not list it)" 1 "$staged" \
    "$SELF" --check "$repo"
  git -C "$repo" rm -q -f --cached -- "$staged"
  rm -f "$repo/$staged"

  stray="Docs/Design/images/committed-as-a-pointer.png"
  git -C "$repo" cat-file -p "HEAD:$evid" > "$repo/$stray"
  git -C "$repo" add -- "$stray"   # no LFS attribute matches it, so the pointer text is committed as it is
  commit_all "$repo" "a pointer committed outside the LFS patterns"
  expect "no LFS attribute matches $stray" "$(git -C "$repo" check-attr filter -- "$stray")" "$stray: filter: unspecified"
  expect "git lfs ls-files lists $stray" "$(git -C "$repo" lfs ls-files --name-only | grep -c -F -x "$stray" || true)" "1"
  run_case "7, a pointer committed outside the LFS patterns (only git lfs ls-files catches it)" 1 "$stray" \
    "$SELF" --check "$repo"
  git -C "$repo" rm -q -f -- "$stray"
  commit_all "$repo" "remove the stray pointer"

  git -C "$repo" config --local --remove-section filter.lfs
  run_case "8, the repository-local LFS filter not configured" 1 "repository-local Git LFS filter is not configured" \
    "$SELF" --check "$repo"
  git -C "$repo" lfs install --local --skip-repo >/dev/null

  ln -s "$(command -v git)" "$bin/git"
  expect "git-lfs is hidden from PATH=$bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$(PATH="$bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/sh -c 'command -v git-lfs || git lfs version 2>/dev/null || echo hidden')" \
    "hidden"
  run_case "9, git-lfs not installed" 1 "git-lfs is not installed" \
    env PATH="$bin:/usr/bin:/bin:/usr/sbin:/sbin" "$SELF" --check "$repo"

  raw="Docs/Stage0/evidence/G06-Design/committed-without-lfs.png"
  write_image "$repo/$raw" raw
  git -C "$repo" "${no_filter[@]}" add -- "$raw"
  out="$(git -C "$repo" cat-file -p ":$raw" | head -c 4 | od -An -tx1 | tr -d ' \n')"
  expect "the index holds the image itself, not a pointer" "$out" "89504e47"
  commit_all "$repo" "an image committed without Git LFS"
  run_case "10, an image committed as a plain git blob" 1 "$raw" "$SELF" --check "$repo"

  echo "self-test: passed (10 cases)"
}

self_test() {
  local scratch status=0
  mkdir -p "$SYLVIA_ROOT/.build/scratch"
  scratch="$(mktemp -d "$SYLVIA_ROOT/.build/scratch/ci-00-git-lfs.XXXXXX")"
  "$SELF" --self-test-body "$scratch" || status=$?
  rm -rf "$scratch"
  return "$status"
}

case "${1:-}" in
  --check)
    check_repo "${2:?usage: 00-git-lfs.sh --check <dir>}" ;;
  --list-pointers)
    lfs_present || { echo "git-lfs is not installed" >&2; exit 1; }
    lfs_paths "${2:?usage: 00-git-lfs.sh --list-pointers <dir>}" | classify_paths "$2" |
      sed -e 's/^P /pointer /' -e 's/^M /missing /' ;;
  --self-test-body)
    self_test_body "${2:?}" ;;
  --self-test)
    if ! lfs_present; then check_repo "$SYLVIA_ROOT"; exit 1; fi
    self_test ;;
  "")
    echo "00-git-lfs $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git -C "$SYLVIA_ROOT" rev-parse HEAD)"
    if ! lfs_present; then check_repo "$SYLVIA_ROOT"; exit 1; fi
    echo
    echo "--- self-test"
    self_test
    echo
    echo "--- this checkout"
    check_repo "$SYLVIA_ROOT" ;;
  *)
    echo "usage: 00-git-lfs.sh [--self-test | --check <dir> | --list-pointers <dir>]" >&2
    exit 2 ;;
esac
