#!/bin/bash
# The dependency lock check's Xcode pin, end to end on this repository (M0 final review of the re-pin round, toolchain
# findings TC-02 and TC-08; integration log section 14). Run once on the commit before the check changed, as the
# control, and once after; the expectations below are the changed check's, so the run before it fails them.
#
#   Docs/Stage0/evidence/M0-Integration/repin-27.1/round-2/commands/toolchain-pin-check.sh > <log> 2>&1
#
# A. The installed Xcode (`check --toolchain`, every repository check included), with a stand-in `xcodebuild` first on
#    PATH that prints the version lines given and hands every other call to the real one:
#    1. no stand-in (this Mac: Xcode 27.1, 27A9275): must pass, its ok line naming "Build version 27A9275";
#    2. "Build version 27A9275a", a made-up build that only extends the pin (TC-02): must fail, naming that line;
#       sylvia_check_xcode is run beside it for comparison (it warns and returns 1 on any other build);
#    3. "Build version 27A9276", another build: must fail, naming that line (TC-02: the failure named the first
#       line, "Xcode 27.1", not the build).
# B. The other records of the pin (TC-08), on copies of the committed tree (git archive HEAD) with one change each,
#    checked without --toolchain (no installed tool is read, so only the repository records are compared):
#    4. the workflow's Xcode guard looks for "Build version 27A9276": must fail, naming .github/workflows/ci.yml;
#    5. the guard's first candidate is /Applications/Xcode_27.2.app: must fail, naming the workflow;
#    6. CLAUDE.md's toolchain line names Xcode 27.2 (27C100): must fail, naming CLAUDE.md;
#    7. ADR-0001's toolchain table names 27.2, build 27C100: must fail, naming ADR-0001;
#    8. the unchanged copy: must pass (the control for 4-7: the copy itself is not what fails).
# Host only: no network, simulator or build; nothing is written outside .build/scratch/toolchain-pin-check, which is
# removed at the end. Exit status 1 if any case is not as expected.
set -uo pipefail
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
here=Docs/Stage0/evidence/M0-Integration/repin-27.1/round-2
scratch="$root/.build/scratch/toolchain-pin-check"
rm -rf "$scratch"; mkdir -p "$scratch"
echo "command: $here/commands/toolchain-pin-check.sh"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
git status --porcelain | sed 's/^/  uncommitted: /'
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "pin in Scripts/lib/env.sh: $SYLVIA_XCODE_BUILD_PINNED"
echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
status=0

stub() {  # directory, version lines: a stand-in xcodebuild that prints them for -version and hands on anything else
  mkdir -p "$1"
  printf '#!/bin/bash\nif [[ "$*" == "-version" ]]; then printf %q; exit 0; fi\nexec "$DEVELOPER_DIR/usr/bin/xcodebuild" "$@"\n' "$2" > "$1/xcodebuild"
  chmod +x "$1/xcodebuild"
}

verdict() {  # label, expected exit, got exit, output file, text the output must contain ("" for none)
  local label="$1" want="$2" got="$3" out="$4" must="$5"
  echo "exit status: $got (expected $want)"
  if [[ "$got" != "$want" ]]; then
    echo "NOT as expected: $label"; status=1; return
  fi
  if [[ -n "$must" ]] && ! grep -q -F -- "$must" "$out"; then
    echo "NOT as expected: $label: the output does not contain: $must"; status=1; return
  fi
  echo "as expected${must:+ (the output contains: $must)}"
}

installed_case() {  # label, stand-in version lines ("" for none), expected exit, text the output must contain
  local label="$1" lines="$2" want="$3" must="$4" out="$scratch/case.out" got
  echo
  echo "== $label"
  if [[ -n "$lines" ]]; then
    stub "$scratch/stub" "$lines"
    echo "stand-in xcodebuild -version prints: $(PATH="$scratch/stub:$PATH" xcodebuild -version | tr '\n' ' ')"
    PATH="$scratch/stub:$PATH" sylvia_python Scripts/check-dependency-lock.py check --toolchain > "$out" 2>&1
    got=$?
  else
    sylvia_python Scripts/check-dependency-lock.py check --toolchain > "$out" 2>&1
    got=$?
  fi
  grep -E 'toolchain|^dependency lock check' "$out" | sed 's/^/   /'
  verdict "$label" "$want" "$got" "$out" "$must"
  if [[ -n "$lines" ]]; then
    PATH="$scratch/stub:$PATH" sylvia_check_xcode > "$scratch/warn.out" 2>&1
    echo "sylvia_check_xcode with the same stand-in: returns $?; $(tr '\n' ' ' < "$scratch/warn.out")"
    rm -rf "$scratch/stub"
  fi
}

echo
echo "### A. The installed Xcode, with stand-ins for xcodebuild -version"
installed_case "1. this Mac's Xcode, no stand-in" "" 0 "-> Build version $SYLVIA_XCODE_BUILD_PINNED"
installed_case "2. a build that only extends the pin: Build version ${SYLVIA_XCODE_BUILD_PINNED}a (made up)" \
  "Xcode 27.1"$'\n'"Build version ${SYLVIA_XCODE_BUILD_PINNED}a"$'\n' 1 "got 'Build version ${SYLVIA_XCODE_BUILD_PINNED}a'"
installed_case "3. another build: Build version 27A9276 (made up)" \
  "Xcode 27.1"$'\n'"Build version 27A9276"$'\n' 1 "got 'Build version 27A9276'"

echo
echo "### B. The repository's other records of the pin, on copies of the committed tree (check without --toolchain)"
mkdir -p "$scratch/base"
git archive HEAD | tar -x -C "$scratch/base" -f -
copy_case() {  # label, file, old text, new text ("" for none), expected exit, text the output must contain
  local label="$1" file="$2" old="$3" new="$4" want="$5" must="$6" copy="$scratch/copy" out="$scratch/case.out" got
  echo
  echo "== $label"
  rm -rf "$copy"; cp -R "$scratch/base" "$copy"
  if [[ -n "$old" ]]; then
    python3 -I - "$copy/$file" "$old" "$new" <<'EOF' || { echo "NOT as expected: the text to change is not in the file once"; status=1; return; }
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit(f"{old!r} occurs {text.count(old)} times in {path}")
open(path, "w", encoding="utf-8").write(text.replace(old, new))
print(f"changed in {path.split('/copy/', 1)[1]}: {old!r} -> {new!r}")
EOF
  fi
  sylvia_python Scripts/check-dependency-lock.py check --root "$copy" > "$out" 2>&1
  got=$?
  grep -E '^FAIL |^dependency lock check' "$out" | sed "s#$copy/##; s/^/   /"
  verdict "$label" "$want" "$got" "$out" "$must"
}
copy_case "4. the workflow's guard looks for another build" .github/workflows/ci.yml \
  'grep -qx "Build version 27A9275"' 'grep -qx "Build version 27A9276"' 1 "FAIL toolchain .github/workflows/ci.yml"
copy_case "5. the workflow's guard looks first for another Xcode" .github/workflows/ci.yml \
  'for candidate in /Applications/Xcode_27.1.app' 'for candidate in /Applications/Xcode_27.2.app' 1 "FAIL toolchain .github/workflows/ci.yml"
copy_case "6. CLAUDE.md's toolchain line names another Xcode" CLAUDE.md \
  '- Xcode 27.1 (27A9275), Swift 6.4' '- Xcode 27.2 (27C100), Swift 6.4' 1 "FAIL toolchain CLAUDE.md"
copy_case "7. ADR-0001's toolchain table names another Xcode" Docs/ADRs/0001-platform-baseline-and-toolchain.md \
  '| Xcode | 27.1, build 27A9275' '| Xcode | 27.2, build 27C100' 1 "FAIL toolchain Docs/ADRs/0001-platform-baseline-and-toolchain.md"
copy_case "8. the unchanged copy (the control for 4-7)" "" "" "" 0 ""

echo
echo "### C. The self-test against the earlier comparison"
echo
echo "== 9. a copy of the check whose tool comparison is the earlier search for the expected text in the output: its"
echo "   self-test must fail, on the mutations of a build or version that only extends the pin"
cp Scripts/check-dependency-lock.py "$scratch/check-substring.py"
if python3 -I - "$scratch/check-substring.py" <<'EOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
new = "            if not stated or any(s != expected for s in stated):\n"
if text.count(new) != 1:
    sys.exit("the comparison to replace is not in the check once (this case applies to the changed check only)")
open(path, "w", encoding="utf-8").write(text.replace(new, "            if expected not in out:\n"))
print("comparison replaced by: if expected not in out:")
EOF
then
  sylvia_python "$scratch/check-substring.py" self-test > "$scratch/selftest.out" 2>&1
  got=$?
  grep -E '^FAIL|^self-test:' "$scratch/selftest.out" | cut -c1-240 | sed 's/^/   /'
  verdict "9. the self-test against the earlier comparison" 1 "$got" "$scratch/selftest.out" \
    "FAIL  the installed Xcode build only extends the pin (review TC-02)"
else
  echo "NOT as expected: 9. the comparison could not be replaced"; status=1
fi
rm -rf "$scratch"
echo
echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( (( status == 0 )) && echo PASS || echo FAIL )"
exit $status
