#!/bin/bash
# Shows that the self-test of Scripts/ci.d/00-git-lfs.sh notices each of its checks being broken: for every mutation
# below, a copy of the drop-in with that one check disabled must fail its self-test, and the unchanged copy must pass.
#   dropin-mutations.sh <repository-root> <scratch-dir>
# Each copy lives in <scratch-dir>/<name>/ with the repository's Scripts/lib/env.sh and .gitattributes beside it (the
# drop-in reads both from its own root). Writes nothing outside <scratch-dir>, which it deletes at the end.
set -uo pipefail
root="$(cd "$1" && pwd)"
scratch="$2"
rm -rf "$scratch"
mkdir -p "$scratch"
scratch="$(cd "$scratch" && pwd -P)"
failures=0

copy() {  # copy <name>: prints the path of a fresh copy of the drop-in
  local dest="$scratch/$1"
  mkdir -p "$dest/Scripts/lib" "$dest/Scripts/ci.d"
  cp "$root/Scripts/lib/env.sh" "$dest/Scripts/lib/"
  cp "$root/Scripts/ci.d/00-git-lfs.sh" "$dest/Scripts/ci.d/"
  cp "$root/.gitattributes" "$dest/"
  echo "$dest/Scripts/ci.d/00-git-lfs.sh"
}

# mutate <name> <exact text> <replacement>: prints the path of a copy with the one occurrence of the text replaced;
# prints why and returns 1 if the text does not occur exactly once.
mutate() {
  local file
  file="$(copy "$1")"
  if [[ "$(grep -c -F -- "$2" "$file")" != 1 ]]; then
    echo "MUTATION NOT APPLIED: $1: the text occurs $(grep -c -F -- "$2" "$file") times in the drop-in"
    return 1
  fi
  FROM="$2" TO="$3" perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$file"
  echo "$file"
}

run() {  # run <name> <expected: pass|fail> <file>
  local out status=0
  out="$("$3" --self-test 2>&1)" || status=$?
  local verdict="pass"
  (( status == 0 )) || verdict="fail"
  if [[ "$verdict" == "$2" ]]; then
    echo "$1: self-test ${verdict}ed (exit $status), as it must$( [[ "$2" == fail ]] && printf ': %s' "$(printf '%s\n' "$out" | grep -m 1 -E 'WRONG RESULT|precondition failed' | cut -c1-160)")"
  else
    echo "$1: WRONG: the self-test ${verdict}ed (exit $status), expected it to $2:"
    printf '%s\n' "$out" | tail -n 20 | sed 's/^/    | /'
    failures=$((failures + 1))
  fi
}

# try <name> <label> <exact text> <replacement>: the mutated copy must fail its self-test.
try() {
  local f
  if f="$(mutate "$1" "$3" "$4")"; then
    run "$2" fail "$f"
  else
    echo "$f"
    failures=$((failures + 1))
  fi
}

echo "# Mutation check of the self-test of Scripts/ci.d/00-git-lfs.sh ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
echo "drop-in: $root/Scripts/ci.d/00-git-lfs.sh, sha256 $(shasum -a 256 "$root/Scripts/ci.d/00-git-lfs.sh" | cut -d' ' -f1)"
echo
run "unchanged copy" pass "$(copy unchanged)"
try no-pointer-detection "pointer detection disabled (is_pointer_file never true)" \
  '[[ "$first" == "$POINTER_V1" || "$first" == "$POINTER_LEGACY" ]]' 'false'
try no-ls-files-route "the git lfs ls-files route disabled" \
  'names="$(git -C "$dir" lfs ls-files --name-only)" || return 1' 'names=""'
try no-attribute-route "the LFS attribute route disabled" \
  'if [[ "$value" == lfs ]]; then printf '"'"'%s\n'"'"' "$path"; fi' ':'
try no-filter-check "the repository-local filter check disabled" \
  'if [[ "$local_have" != "$want" || "$have" != "$want" ]]; then' 'if false; then'
try no-lfs-presence-check "the git-lfs presence check disabled" \
  'lfs_present() { command -v git-lfs >/dev/null 2>&1 && git lfs version >/dev/null 2>&1; }' 'lfs_present() { true; }'
try no-fsck-check "the git lfs fsck --pointers check disabled" \
  'if fsck="$(git -C "$dir" lfs fsck --pointers 2>&1)"; then' 'if fsck="skipped"; then'
echo
rm -rf "$scratch"
if (( failures )); then
  echo "RESULT: FAIL ($failures)"
  exit 1
fi
echo "RESULT: PASS: the unchanged drop-in passes its self-test, and each of the 6 mutations makes it fail"
