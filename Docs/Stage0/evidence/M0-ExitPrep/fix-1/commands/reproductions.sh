#!/bin/bash
# The review of the M0 exit preparation, finding SEC-ZIPGUARD-01: a product manifest's local package inside Apps/ or
# Packages/ that git does not track passed the dependency check, which judged a local package only against Spikes/ and
# the product roots, so its manifest and sources were read by nothing.
#
#   Docs/Stage0/evidence/M0-ExitPrep/fix-1/commands/reproductions.sh <reviewed commit> \
#     > Docs/Stage0/evidence/M0-ExitPrep/fix-1/reproductions.log 2>&1
#
# Part 1. Each route of plant.py is planted in a copy of the tree at <reviewed commit> (git archive, so the check walks
#   every file but those under .build and the other directories it skips; for the route `git`, the copy is made a git
#   repository first, its files committed, so the check reads git's list of tracked files, as in a checkout), and
#   Scripts/check-dependency-lock.py is run on it twice: as it was at <reviewed commit>, before the fix, and as it is in
#   this checkout's working tree, after it (`check --root <copy>`, no --toolchain). Before the fix every route but the
#   control must pass, and after it fail with exactly one finding, the new rule's; the control (the review's b01, a
#   local package outside the product roots) fails both times, the same way; the unplanted copy passes both times.
# Part 2. What the tools do with such a package, so that the rule's reason stands on the tools: SwiftPM's dump-package
#   of the planted b02 manifest, its local package's directory absent (the manifest is read, the path not checked);
#   XcodeGen 2.46.0 on a probe project whose local package is at Vendor/.build/checkouts/Zip, absent and then populated
#   with plant.py's stand-in; and xcodebuild building the probe's macOS tool from the generated project, with the stand-
#   in compiled and linked into it (its symbol in the tool, and the tool's output). The probe has no remote package, so
#   nothing is resolved from a network, and builds with -disableAutomaticPackageResolution into its own derived data.
# Everything runs under .build/scratch/fix-1-repro, from new directories. No network: GIT_ALLOW_PROTOCOL=file for every
# git this starts. No simulator; host only.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
source "$ROOT/Scripts/lib/xcodegen.sh"
cd "$ROOT" || exit 1
BASE="${1:?usage: reproductions.sh <reviewed commit>}"
CMD=Docs/Stage0/evidence/M0-ExitPrep/fix-1/commands
WORK="$ROOT/.build/scratch/fix-1-repro"
export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
rm -rf "$WORK"
mkdir -p "$WORK"
fails=0
echo "reproductions started $(date -u +%Y-%m-%dT%H:%M:%SZ); reviewed commit $(git rev-parse "$BASE"); working tree at $(git rev-parse HEAD)" \
     "with Scripts/check-dependency-lock.py $(git diff --quiet HEAD -- Scripts/check-dependency-lock.py && echo 'as committed' || echo 'modified (the fix, not yet committed)')"
echo "check before the fix: Scripts/check-dependency-lock.py at $BASE, sha256 $(git show "$BASE:Scripts/check-dependency-lock.py" | shasum -a 256 | cut -c1-64)"
echo "check after the fix: Scripts/check-dependency-lock.py, sha256 $(shasum -a 256 Scripts/check-dependency-lock.py | cut -c1-64)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); $(xcrun swift --version 2>&1 | head -1); xcodegen $(xcodegen --version)"
echo "load: $(uptime)"

echo
echo "=== Part 1: each route in a copy of the tree at the reviewed commit, the check before and after the fix"
git show "$BASE:Scripts/check-dependency-lock.py" > "$WORK/check-before.py"
mkdir -p "$WORK/base"
git archive "$BASE" | tar -x -C "$WORK/base"
summary() { grep -E '^(FAIL|dependency lock check)' "$1" | cut -c1-420 | sed 's/^/      /'; }
for side in before after; do
  checker="$WORK/check-before.py"; [[ $side == after ]] && checker="$ROOT/Scripts/check-dependency-lock.py"
  sylvia_python "$checker" check --root "$WORK/base" > "$WORK/unplanted-$side.log" 2>&1
  code=$?
  echo "  the unplanted copy, check $side the fix: exit $code -> $(tail -n 1 "$WORK/unplanted-$side.log")"
  [[ $code -eq 0 ]] || fails=$((fails + 1))
done
NEW_RULE="whose Package.swift is not a file git tracks"
n=0
while IFS= read -r route; do
  n=$((n + 1))
  copy="$WORK/route-$n"
  cp -cR "$WORK/base" "$copy" 2>/dev/null || cp -R "$WORK/base" "$copy"
  if [[ "$route" == git\ * ]]; then
    # The copy as a git repository, its files committed (Git LFS's filter switched off for this repository's commands,
    # so the images go in as they are; nothing here reads them). The check then takes git's list of tracked files.
    lfs_off=(-c filter.lfs.clean= -c filter.lfs.smudge= -c filter.lfs.process= -c filter.lfs.required=false)
    git -C "$copy" init -q && git -C "$copy" "${lfs_off[@]}" add -A \
      && git -C "$copy" "${lfs_off[@]}" -c user.name=fix-1 -c user.email=fix-1@example.invalid commit -q --no-verify -m base \
      || { echo "FAIL: could not make route $n's copy a git repository"; fails=$((fails + 1)); continue; }
    echo
    echo "    (route $n's copy is a git repository: $(git -C "$copy" ls-files | wc -l | tr -d ' ') files tracked, the base committed as $(git -C "$copy" rev-parse --short HEAD))"
  fi
  if ! /usr/bin/python3 -I "$CMD/plant.py" "$copy" "$route" < /dev/null; then echo "FAIL: could not plant $route"; fails=$((fails + 1)); continue; fi
  if [[ "$route" == git\ * ]]; then
    echo "    after planting, git status in that copy: $(git -C "$copy" status --porcelain | tr '\n' ';' | sed 's/;$//')"
  fi
  sylvia_python "$WORK/check-before.py" check --root "$copy" > "$WORK/route-$n-before.log" 2>&1 < /dev/null &
  sylvia_python "$ROOT/Scripts/check-dependency-lock.py" check --root "$copy" > "$WORK/route-$n-after.log" 2>&1 < /dev/null &
  wait
  before=$(grep -c '^FAIL' "$WORK/route-$n-before.log"); after=$(grep -c '^FAIL' "$WORK/route-$n-after.log")
  after_new=$(grep '^FAIL outside-product' "$WORK/route-$n-after.log" | grep -c -F "$NEW_RULE")
  if [[ "$route" == b01* ]]; then
    same=no; diff -q <(grep '^FAIL' "$WORK/route-$n-before.log") <(grep '^FAIL' "$WORK/route-$n-after.log") > /dev/null && same=yes
    verdict="ok (the control: fails before the fix and after it, the same way)"
    if [[ $before -eq 0 || $same != yes || $after_new -ne 0 ]]; then verdict="UNEXPECTED"; fails=$((fails + 1)); fi
  else
    verdict="ok (passed before the fix; fails after it, with exactly the new rule's finding)"
    if [[ $before -ne 0 || $after -ne 1 || $after_new -ne 1 ]]; then verdict="UNEXPECTED"; fails=$((fails + 1)); fi
  fi
  echo
  echo "--- route $n: $route: $verdict"
  echo "    before the fix ($BASE):"; summary "$WORK/route-$n-before.log"
  echo "    after the fix:"; summary "$WORK/route-$n-after.log"
done < <(/usr/bin/python3 -I "$CMD/plant.py" --list)

echo
echo "=== Part 2a: SwiftPM reads the planted b02 manifest with its local package's directory absent"
copy="$WORK/route-3"
echo "the local package's directory: Packages/Design/.build/checkouts/Zip $( [[ -e "$copy/Packages/Design/.build/checkouts/Zip" ]] && echo exists || echo 'does not exist')"
xcrun swift package --package-path "$copy/Packages/Design" --scratch-path "$WORK/dump-scratch" dump-package > "$WORK/b02-dump.json" 2> "$WORK/b02-dump.err"
echo "swift package dump-package (the call the check makes): exit $?; stderr lines: $(wc -l < "$WORK/b02-dump.err" | tr -d ' ')"
/usr/bin/python3 -I - "$WORK/b02-dump.json" "$copy" <<'EOF'
import json, os, sys
d = json.load(open(sys.argv[1]))
for dep in d.get('dependencies', []):
    kind = next(iter(dep))
    info = dep[kind][0]
    where = os.path.relpath(info['path'], sys.argv[2]) + ' (in the copy)' if kind == 'fileSystem' else ''
    print(f"  dependency: {kind} {info.get('identity')} {where}".rstrip())
for t in d.get('targets', []):
    if t['name'] == 'SylviaDesign':
        print(f"  SylviaDesign (a shipping library) depends on: {json.dumps(t.get('dependencies'))}")
EOF

echo
echo "=== Part 2b: XcodeGen $(xcodegen --version | awk '{print $2}') on a probe project with a local package under Vendor/.build/checkouts"
P="$WORK/probe"
mkdir -p "$P/Sources"
cat > "$P/project.yml" <<'EOF'
name: Probe
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    macOS: "26.0"
packages:
  Vendored:
    path: Vendor/.build/checkouts/Zip
targets:
  Probe:
    type: tool
    platform: macOS
    sources:
      - path: Sources
    dependencies:
      - package: Vendored
        product: Zip
EOF
printf 'import Zip\nprint("probe links: \\(StandIn.name)")\n' > "$P/Sources/main.swift"
echo "project.yml:"; sed 's/^/  | /' "$P/project.yml"
echo "Sources/main.swift:"; sed 's/^/  | /' "$P/Sources/main.swift"
xcodegen generate --quiet --spec "$P/project.yml" --project "$P" > "$WORK/xcodegen-absent.log" 2>&1
echo "case 1, Vendor/.build/checkouts/Zip absent: xcodegen generate exit $?:"; sed 's/^/  /' "$WORK/xcodegen-absent.log"
rm -rf "$P/Probe.xcodeproj"
/usr/bin/python3 -I - "$CMD/plant.py" "$P" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('plant', sys.argv[1]); plant = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plant)
plant.stand_in('Vendor/.build/checkouts/Zip')(sys.argv[2])
EOF
echo "case 2, the directory populated with plant.py's stand-in (untracked: under .build):"
find "$P/Vendor" -type f | sed "s#^$P/#  #" | sort
xcodegen generate --quiet --spec "$P/project.yml" --project "$P" > "$WORK/xcodegen-present.log" 2>&1
echo "  xcodegen generate exit $?; the generated project's package reference and product dependency:"
grep -E 'XCLocalSwiftPackageReference|relativePath|productName = Zip' "$P/Probe.xcodeproj/project.pbxproj" | sort -u | sed 's/^[[:space:]]*/    /'

echo
echo "=== Part 2c: xcodebuild builds the probe's tool from the generated project, the stand-in compiled and linked into it"
start=$SECONDS
xcodebuild -project "$P/Probe.xcodeproj" -scheme Probe -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$P/.build/DerivedData" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build > "$WORK/probe-build.log" 2>&1
code=$?
echo "xcodebuild build exit $code ($((SECONDS - start)) s); its last lines:"
tail -n 3 "$WORK/probe-build.log" | sed 's/^/  /'
echo "the stand-in's sources the build compiled (SwiftCompile lines naming them):"
grep -E '^SwiftCompile .*StandIn\.swift' "$WORK/probe-build.log" | sed -E "s#$P/##g" | cut -c1-200 | sed 's/^/  /'
tool="$P/.build/DerivedData/Build/Products/Debug/Probe"
if [[ -x "$tool" ]]; then
  echo "the stand-in's type in the tool's symbols (nm): $(nm "$tool" | grep -c 'StandIn') symbols naming StandIn, for example:"
  nm "$tool" | grep 'StandIn' | head -n 2 | sed 's/^/  /'
  echo "the tool's output: $("$tool")"
else
  echo "UNEXPECTED: no tool at $tool"; fails=$((fails + 1))
fi
[[ $code -eq 0 ]] || fails=$((fails + 1))

echo
echo "reproductions finished $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((fails == 0)) && echo 'every route as expected' || echo "$fails NOT as expected")"
exit $(( fails == 0 ? 0 : 1 ))
