#!/bin/bash
# The fourth review of the M0 exit preparation, finding SEC-ZIPGUARD-03, and the routes of the same kind found with its
# fix: SwiftPM evaluates a version-specific manifest (Package@swift-<version>.swift) instead of the Package.swift beside
# it, and the dependency check's manifest-input rule read the raw text of Package.swift alone; and the default macOS file
# system, which ignores letter case, gives the build files the check read only under the names as it spells them.
#
#   Docs/Stage0/evidence/M0-ExitPrep/fix-2/commands/reproductions.sh <reviewed commit> \
#     > Docs/Stage0/evidence/M0-ExitPrep/fix-2/reproductions.log 2>&1
#
# Part 1. Each route of plant.py is planted in a copy of the tree at <reviewed commit> (git archive; for a route whose
#   name begins with `git`, the copy is made a git repository first, its files committed, and the planted files are
#   committed under the paths plant.py --index gives, so that the check reads git's list of tracked files, as in a
#   checkout, with a path in another letter case where the route has one), and Scripts/check-dependency-lock.py is run
#   on it twice, without the variable SYLVIA_EXTRA, as CI runs it: as it was at <reviewed commit>, before the fix, and as
#   it is in this checkout's working tree, after it (`check --root <copy>`, no --toolchain). Every route but a control
#   must pass before the fix and fail after it, every finding at a file the route planted; a control (the same change
#   with every name as the check reads it) fails both times, the same way; the unplanted copy passes both times. For the
#   route that adds a test-only package from the environment, the check before the fix runs a third time, with
#   SYLVIA_EXTRA set, as a build that sets it evaluates the manifest.
# Part 2. What the tools do with such files, so that each rule stands on the tools of the pinned toolchain: (a) which file
#   SwiftPM's dump-package evaluates when a version-specific manifest, under each of twenty names, is beside a
#   Package.swift; (b) the review's route, dump-package of the planted Packages/Design without and with SYLVIA_EXTRA;
#   (c) SwiftPM and XcodeGen loading a manifest named in another letter case, and neither compiling a Swift file whose
#   extension is in another letter case; (d) which module map names clang reads; (e) git checking a path tracked under
#   packages/ out into Packages/, and SwiftPM compiling it there into a tool that runs.
# Everything runs under .build/scratch/fix-2-repro, from new directories; the scratch packages and projects have no
# remote package, so nothing is resolved from a network, and GIT_ALLOW_PROTOCOL=file holds for every git this starts.
# No simulator; host only.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
BASE="${1:?usage: reproductions.sh <reviewed commit>}"
CMD=Docs/Stage0/evidence/M0-ExitPrep/fix-2/commands
WORK="$ROOT/.build/scratch/fix-2-repro"
export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
unset SYLVIA_EXTRA
rm -rf "$WORK"
mkdir -p "$WORK"
fails=0
echo "reproductions started $(date -u +%Y-%m-%dT%H:%M:%SZ); reviewed commit $(git rev-parse "$BASE"); working tree at $(git rev-parse HEAD)" \
     "with Scripts/check-dependency-lock.py $(git diff --quiet HEAD -- Scripts/check-dependency-lock.py && echo 'as committed' || echo 'modified (the fix, not yet committed)')"
echo "check before the fix: Scripts/check-dependency-lock.py at $BASE, sha256 $(git show "$BASE:Scripts/check-dependency-lock.py" | shasum -a 256 | cut -c1-64)"
echo "check after the fix: Scripts/check-dependency-lock.py, sha256 $(shasum -a 256 Scripts/check-dependency-lock.py | cut -c1-64)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); $(xcrun swift --version 2>&1 | head -1); xcodegen $(xcodegen --version); $(git --version)"
mkdir -p "$WORK/fs-probe"
echo "the file system of the checkout: $(touch "$WORK/fs-probe/Case" && [[ -e "$WORK/fs-probe/cASE" ]] && echo 'ignores letter case (a file named Case is found as cASE)' || echo 'is case-sensitive')"
echo "load: $(uptime)"

echo
echo "=== Part 1: each route in a copy of the tree at the reviewed commit, the check before and after the fix"
git show "$BASE:Scripts/check-dependency-lock.py" > "$WORK/check-before.py"
mkdir -p "$WORK/base"
git archive "$BASE" | tar -x -C "$WORK/base"
summary() { grep -E '^(FAIL|dependency lock check)' "$1" | cut -c1-400 | sed 's/^/      /'; }
for side in before after; do
  checker="$WORK/check-before.py"; [[ $side == after ]] && checker="$ROOT/Scripts/check-dependency-lock.py"
  sylvia_python "$checker" check --root "$WORK/base" > "$WORK/unplanted-$side.log" 2>&1
  code=$?
  echo "  the unplanted copy, check $side the fix: exit $code -> $(tail -n 1 "$WORK/unplanted-$side.log")"
  [[ $code -eq 0 ]] || fails=$((fails + 1))
done
lfs_off=(-c filter.lfs.clean= -c filter.lfs.smudge= -c filter.lfs.process= -c filter.lfs.required=false)
who=(-c user.name=fix-2 -c user.email=fix-2@example.invalid)
n=0
while IFS= read -r route; do
  n=$((n + 1))
  copy="$WORK/route-$n"
  cp -cR "$WORK/base" "$copy" 2>/dev/null || cp -R "$WORK/base" "$copy"
  echo
  echo "--- route $n, $route: $(/usr/bin/python3 -I "$CMD/plant.py" --describe "$route")"
  if [[ "$route" == git-* ]]; then
    git -C "$copy" init -q && git -C "$copy" "${lfs_off[@]}" add -A \
      && git -C "$copy" "${lfs_off[@]}" "${who[@]}" commit -q --no-verify -m base \
      || { echo "FAIL: could not make route $n's copy a git repository"; fails=$((fails + 1)); continue; }
    echo "    the copy is a git repository: $(git -C "$copy" ls-files | wc -l | tr -d ' ') files tracked, the base committed as $(git -C "$copy" rev-parse --short HEAD); core.ignorecase $(git -C "$copy" config --get core.ignorecase)"
  fi
  if ! /usr/bin/python3 -I "$CMD/plant.py" "$copy" "$route" < /dev/null; then echo "FAIL: could not plant $route"; fails=$((fails + 1)); continue; fi
  if [[ "$route" == git-* ]]; then
    while read -r disk index; do
      if [[ "$disk" == "$index" ]]; then
        git -C "$copy" "${lfs_off[@]}" add -- "$disk"
      else
        blob="$(git -C "$copy" hash-object -w -- "$disk")"
        git -C "$copy" update-index --add --cacheinfo "100644,$blob,$index"
      fi
    done < <(/usr/bin/python3 -I "$CMD/plant.py" --index "$route")
    git -C "$copy" "${lfs_off[@]}" "${who[@]}" commit -q --no-verify -m "$route" || { echo "FAIL: could not commit $route"; fails=$((fails + 1)); continue; }
    echo "    planted and committed; the paths git tracks for it: $(git -C "$copy" diff --name-only HEAD~1 HEAD | tr '\n' ' ')"
    echo "    on disk: $(/usr/bin/python3 -I "$CMD/plant.py" --index "$route" | while read -r disk _; do [[ -f "$copy/$disk" ]] && printf '%s ' "$disk"; done)"
    echo "    git status --porcelain after the commit: $(git -C "$copy" status --porcelain | tr '\n' ';' | sed 's/;$//')"
  fi
  sylvia_python "$WORK/check-before.py" check --root "$copy" > "$WORK/route-$n-before.log" 2>&1 < /dev/null &
  sylvia_python "$ROOT/Scripts/check-dependency-lock.py" check --root "$copy" > "$WORK/route-$n-after.log" 2>&1 < /dev/null &
  wait
  verdict="$(/usr/bin/python3 -I "$CMD/plant.py" --verdict "$route" "$WORK/route-$n-before.log" "$WORK/route-$n-after.log")" || fails=$((fails + 1))
  echo "    $verdict"
  echo "    before the fix ($BASE):"; summary "$WORK/route-$n-before.log"
  echo "    after the fix:"; summary "$WORK/route-$n-after.log"
  if [[ "$route" == vsm-test-package ]]; then
    SYLVIA_EXTRA=1 sylvia_python "$WORK/check-before.py" check --root "$copy" > "$WORK/route-$n-before-set.log" 2>&1 < /dev/null
    in_product="$(grep -c '^FAIL test-in-product' "$WORK/route-$n-before-set.log")"
    echo "    the check before the fix, with SYLVIA_EXTRA=1 set, as a build that sets it evaluates the manifest: $( ((in_product > 0)) && echo "it reports the test-only package in shipping code ($in_product test-in-product finding(s)), which it does not see without the variable" || echo "UNEXPECTED: no test-in-product finding")"
    summary "$WORK/route-$n-before-set.log"
    ((in_product > 0)) || fails=$((fails + 1))
  fi
done < <(/usr/bin/python3 -I "$CMD/plant.py" --list)

echo
echo "=== Part 2a: which file SwiftPM's dump-package (the call the check makes) evaluates beside a Package.swift"
echo "Each case is a package of its own whose one target's path names the manifest that declares it: Sources/Regular in"
echo "Package.swift, Sources/Specific in the other file; both declare tools version 6.2 unless the case says otherwise."
P="$WORK/selection"
mkdir -p "$P"
manifest() { printf '// swift-tools-version: %s\nimport PackageDescription\nlet package = Package(name: "P", targets: [.target(name: "P", path: "%s")])\n' "$1" "$2"; }
selection() {  # <case> <file>=<tools>|<path> ...
  local name="$1"; shift
  local d="$P/$name"; mkdir -p "$d"
  for spec in "$@"; do
    local file="${spec%%=*}" rest="${spec#*=}"
    manifest "${rest%%|*}" "${rest#*|}" > "$d/$file"
    mkdir -p "$d/${rest#*|}"; echo 'public struct P {}' > "$d/${rest#*|}/P.swift"
  done
  local out code path
  out="$(xcrun swift package --package-path "$d" --scratch-path "$P/scratch-$name" dump-package 2> "$P/$name.err")"; code=$?
  path="$(printf '%s' "$out" | /usr/bin/python3 -I -c 'import json, sys
try:
    print(json.load(sys.stdin)["targets"][0].get("path"))
except Exception:
    print("(no manifest read)")')"
  printf '  %-34s exit %s; files: %s-> evaluates the one declaring %s%s\n' "$name" "$code" "$(cd "$d" && ls -p | grep -v / | tr '\n' ' ')" "$path" \
    "$( [[ -s "$P/$name.err" ]] && echo "; stderr: $(tr '\n' ' ' < "$P/$name.err" | cut -c1-120)")"
}
R='Package.swift=6.2|Sources/Regular'
selection 6.4                 "$R" 'Package@swift-6.4.swift=6.2|Sources/Specific'
selection 6                   "$R" 'Package@swift-6.swift=6.2|Sources/Specific'
selection 6.4.0               "$R" 'Package@swift-6.4.0.swift=6.2|Sources/Specific'
selection 6.4-tools-6.4       "$R" 'Package@swift-6.4.swift=6.4|Sources/Specific'
selection 6-and-6.4           "$R" 'Package@swift-6.swift=6.2|Sources/Six' 'Package@swift-6.4.swift=6.2|Sources/SixFour'
selection lower-p             "$R" 'package@swift-6.4.swift=6.2|Sources/Specific'
selection capital-S           "$R" 'Package@Swift-6.4.swift=6.2|Sources/Specific'
selection capital-extension   "$R" 'Package@swift-6.4.SWIFT=6.2|Sources/Specific'
selection all-capitals        "$R" 'PACKAGE@SWIFT-6.4.SWIFT=6.2|Sources/Specific'
selection 7                   "$R" 'Package@swift-7.swift=6.2|Sources/Specific'
selection 5.9-tools-5.9       "$R" 'Package@swift-5.9.swift=5.9|Sources/Specific'
selection 5.9-tools-6.2       "$R" 'Package@swift-5.9.swift=6.2|Sources/Specific'
selection 6.3-tools-6.1       "$R" 'Package@swift-6.3.swift=6.1|Sources/Specific'
selection no-dash             "$R" 'Package@swift6.4.swift=6.2|Sources/Specific'
selection word-after-version  "$R" 'Package@swift-6.4-x.swift=6.2|Sources/Specific'
selection other-word          "$R" 'Package@other-6.4.swift=6.2|Sources/Specific'
selection no-dot-before-swift "$R" 'Package@swift-6.4Xswift=6.2|Sources/Specific'
selection backup-suffix       "$R" 'Package@swift-6.4.swift.bak=6.2|Sources/Specific'
selection no-Package.swift    'Package@swift-6.4.swift=6.2|Sources/Specific'
selection lower-package.swift 'package.swift=6.2|Sources/Regular'

echo
echo "=== Part 2b: the review's route, SwiftPM's dump-package of the planted Packages/Design without and with SYLVIA_EXTRA"
for route_n in 1 2; do
  route="$(/usr/bin/python3 -I "$CMD/plant.py" --list | sed -n "${route_n}p")"
  copy="$WORK/route-$route_n"
  for value in '' Sources/Elsewhere; do
    if [[ -n "$value" ]]; then export SYLVIA_EXTRA="$value"; else unset SYLVIA_EXTRA; fi
    xcrun swift package --package-path "$copy/Packages/Design" --scratch-path "$WORK/dump-$route_n" dump-package > "$WORK/dump-$route_n.json" 2> "$WORK/dump-$route_n.err"
    code=$?
    target="$(/usr/bin/python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
t = next(t for t in d["targets"] if t["name"] == "SylviaDesign")
print("path " + str(t.get("path")) + ", dependencies " + json.dumps(t.get("dependencies")))' "$WORK/dump-$route_n.json" 2>&1)"
    echo "  $route, SYLVIA_EXTRA ${value:-unset}: exit $code; the SylviaDesign target: $target"
  done
  unset SYLVIA_EXTRA
done

echo
echo "=== Part 2c: SwiftPM and XcodeGen load a manifest named in another letter case; neither compiles a .SWIFT file"
C="$WORK/case"
mkdir -p "$C/lower-manifest/Sources/Tool" "$C/upper-project/Sources" "$C/swift-extension/Sources/Tool" "$C/xcodegen-extension/Sources"
printf '// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "Tool", targets: [.executableTarget(name: "Tool")])\n' > "$C/lower-manifest/package.swift"
printf 'print("built from a manifest named package.swift")\n' > "$C/lower-manifest/Sources/Tool/main.swift"
xcrun swift build --package-path "$C/lower-manifest" --scratch-path "$C/lower-manifest/.build" > "$C/lower-manifest.log" 2>&1
code=$?
echo "  a package whose only manifest is package.swift: swift build exit $code; the tool prints: $("$C/lower-manifest/.build/debug/Tool" 2>&1)"
[[ $code -eq 0 ]] || fails=$((fails + 1))
printf 'name: Probe\noptions:\n  bundleIdPrefix: com.example\n  deploymentTarget:\n    macOS: "26.0"\ntargets:\n  Probe:\n    type: tool\n    platform: macOS\n    sources: [Sources]\n' > "$C/upper-project/Project.yml"
printf 'print("probe")\n' > "$C/upper-project/Sources/main.swift"
(cd "$C/upper-project" && xcodegen generate --quiet) > "$C/upper-project.log" 2>&1
code=$?
echo "  a directory whose only project file is Project.yml, \`xcodegen generate\` run in it as sylvia_generate runs it: exit $code; it wrote: $(cd "$C/upper-project" && ls -d *.xcodeproj 2>/dev/null || echo nothing)"
[[ $code -eq 0 && -d "$C/upper-project/Probe.xcodeproj" ]] || fails=$((fails + 1))
printf '// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "Tool", targets: [.executableTarget(name: "Tool")])\n' > "$C/swift-extension/Package.swift"
printf 'print(Extra.text)\n' > "$C/swift-extension/Sources/Tool/main.swift"
printf 'enum Extra { static let text = "Extra.SWIFT compiled" }\n' > "$C/swift-extension/Sources/Tool/Extra.SWIFT"
xcrun swift build --package-path "$C/swift-extension" --scratch-path "$C/swift-extension/.build" > "$C/swift-extension.log" 2>&1
code=$?
echo "  a target whose Extra.SWIFT declares what main.swift uses: swift build exit $code ($( ((code != 0)) && echo 'fails, as expected' || echo UNEXPECTED)); SwiftPM's words on it: $(grep -m 1 -o 'warning: .*unhandled[^;]*' "$C/swift-extension.log" | sed 's/\x1b\[[0-9;]*m//g'); the compiler's: $(grep -m 1 -o "cannot find 'Extra' in scope" "$C/swift-extension.log")"
[[ $code -ne 0 ]] || fails=$((fails + 1))
printf 'name: Probe\noptions:\n  bundleIdPrefix: com.example\n  deploymentTarget:\n    macOS: "26.0"\ntargets:\n  Probe:\n    type: tool\n    platform: macOS\n    sources: [Sources]\n' > "$C/xcodegen-extension/project.yml"
printf 'print(Extra.text)\n' > "$C/xcodegen-extension/Sources/main.swift"
printf 'enum Extra { static let text = "Extra.SWIFT compiled" }\n' > "$C/xcodegen-extension/Sources/Extra.SWIFT"
(cd "$C/xcodegen-extension" && xcodegen generate --quiet) > "$C/xcodegen-extension.log" 2>&1
echo "  the same file in an XcodeGen project: generate exit $?; the build phase the project gives it: $(grep -o 'Extra.SWIFT in [A-Za-z]*' "$C/xcodegen-extension/Probe.xcodeproj/project.pbxproj" | sort -u | tr '\n' ' ')(main.swift: $(grep -o 'main.swift in [A-Za-z]*' "$C/xcodegen-extension/Probe.xcodeproj/project.pbxproj" | sort -u | tr '\n' ' '))"

echo
echo "=== Part 2d: which module map names clang (Xcode 27.1's) reads, by an @import of the module a map defines"
M="$WORK/modulemaps"
mkdir -p "$M"
mm=0
modmap() {  # <description> <module imported> <file>=<module defined> ...
  local what="$1" mod="$2"; shift 2
  mm=$((mm + 1))
  local d="$M/case$mm"; mkdir -p "$d/inc"
  printf 'int probe_value(void);\n' > "$d/inc/probe.h"
  printf 'int other_value(void);\n' > "$d/inc/other.h"
  for spec in "$@"; do
    local file="${spec%%=*}" m="${spec#*=}" header=probe.h
    [[ "$m" == OtherMod ]] && header=other.h
    printf 'module %s {\n  header "%s"\n  export *\n}\n' "$m" "$header" > "$d/inc/$file"
  done
  printf '@import %s;\nint main(void) { return 0; }\n' "$mod" > "$d/main.m"
  xcrun clang -fmodules -fsyntax-only -I "$d/inc" -fmodules-cache-path="$d/cache" "$d/main.m" > "$d/out.log" 2>&1
  local code=$?
  printf '  %-50s @import %s: exit %s %s\n' "$what:" "$mod" "$code" "$( ((code == 0)) && echo '(read)' || echo "($(grep -m1 -o "fatal error: [^\[]*" "$d/out.log" | sed 's/ *$//'))")"
}
modmap "module.modulemap" ProbeMod module.modulemap=ProbeMod
modmap "MODULE.MODULEMAP" ProbeMod MODULE.MODULEMAP=ProbeMod
modmap "Module.ModuleMap" ProbeMod Module.ModuleMap=ProbeMod
modmap "module.map" ProbeMod module.map=ProbeMod
modmap "MODULE.MAP" ProbeMod MODULE.MAP=ProbeMod
modmap "x.modulemap (named by no setting)" ProbeMod x.modulemap=ProbeMod
modmap "module.private.modulemap beside module.modulemap" OtherMod module.modulemap=ProbeMod module.private.modulemap=OtherMod
modmap "MODULE.PRIVATE.MODULEMAP beside module.modulemap" OtherMod module.modulemap=ProbeMod MODULE.PRIVATE.MODULEMAP=OtherMod
modmap "module_private.map beside module.modulemap" OtherMod module.modulemap=ProbeMod module_private.map=OtherMod
modmap "module_private.map beside module.map" OtherMod module.map=ProbeMod module_private.map=OtherMod
modmap "MODULE_PRIVATE.MAP beside module.map" OtherMod module.map=ProbeMod MODULE_PRIVATE.MAP=OtherMod
modmap "module.private.modulemap alone" OtherMod module.private.modulemap=OtherMod

echo
echo "=== Part 2e: git checks a path tracked under packages/ out into Packages/, and SwiftPM compiles it there"
G="$WORK/git-case"
mkdir -p "$G/Packages/P/Sources/P"
git -C "$G" init -q
printf '// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "P", targets: [.executableTarget(name: "P")])\n' > "$G/Packages/P/Package.swift"
printf 'print(Shadow.text)\n' > "$G/Packages/P/Sources/P/main.swift"
git -C "$G" add -A && git -C "$G" "${who[@]}" commit -q -m base
printf 'enum Shadow { static let text = "Shadow.swift, tracked as packages/P/Sources/P/Shadow.swift, was compiled" }\n' > "$WORK/Shadow.swift"
blob="$(git -C "$G" hash-object -w "$WORK/Shadow.swift")"
git -C "$G" update-index --add --cacheinfo "100644,$blob,packages/P/Sources/P/Shadow.swift"
git -C "$G" "${who[@]}" commit -q -m shadow
git clone -q "$G" "$WORK/git-case-clone"
echo "  the commit's paths (git ls-tree): $(git -C "$G" ls-tree -r --name-only HEAD | tr '\n' ' ')"
echo "  a fresh clone's files on disk: $(cd "$WORK/git-case-clone" && find . -path ./.git -prune -o -type f -print | sed 's#^\./##' | sort | tr '\n' ' ')"
echo "  the clone's git ls-files: $(git -C "$WORK/git-case-clone" ls-files | tr '\n' ' '); git status --porcelain: $(git -C "$WORK/git-case-clone" status --porcelain | wc -l | tr -d ' ') line(s)"
xcrun swift build --package-path "$WORK/git-case-clone/Packages/P" --scratch-path "$WORK/git-case-build" > "$WORK/git-case-build.log" 2>&1
code=$?
echo "  swift build of the clone's Packages/P: exit $code; the tool prints: $("$WORK/git-case-build/debug/P" 2>&1)"
[[ $code -eq 0 ]] || fails=$((fails + 1))

echo
echo "reproductions finished $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
echo "result: $( ((fails == 0)) && echo 'every route as expected' || echo "$fails NOT as expected")"
exit $(( fails == 0 ? 0 : 1 ))
