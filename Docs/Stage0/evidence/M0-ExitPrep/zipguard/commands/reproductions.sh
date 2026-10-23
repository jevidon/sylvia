#!/bin/bash
# ADR-0014 review round 4: R4-01, R4-02, R4-03 and R4-04, and the routes of the same kind the fix closes with them.
#
#   Docs/Stage0/evidence/M0-ExitPrep/zipguard/commands/reproductions.sh <base commit> \
#     > Docs/Stage0/evidence/M0-ExitPrep/zipguard/reproductions.log 2>&1
#
# Part 1. Each route of plant.py is planted in a copy of the tree at <base commit> (git archive, so the check walks
#   every file), and Scripts/check-dependency-lock.py is run on it twice: as it was at <base commit>, before the fix,
#   and as it is in this checkout's working tree, after it (`check --root <copy>`, no --toolchain). Before the fix
#   every route must pass; after it, every route must fail.
# Part 2. What the tools do with each kind of route, so that the check's reasons stand on the tools, not on reading:
#   XcodeGen 2.46.0 on probe projects (what it expands and how it reads YAML, with and without --no-env); SwiftPM's
#   dump-package of a planted Packages/Design manifest with and without the environment variable it reads; clang and
#   the linker on probe files against Minizip's own sources (marmelroy/Zip 2.1.2, from the checkout under
#   Spikes/G01-EPUB/.build that Docs/Stage0/evidence/M0-dependencies/xcode-27.1/run-2 left, at the pinned revision);
#   xcodebuild -showBuildSettings for build-settings files that #include others (a probe project with no package, so
#   nothing is resolved); and the files in the public include directories of the transitive-only packages' C targets.
# Everything runs under .build/scratch/zipguard-repro, from new directories. No network: GIT_ALLOW_PROTOCOL=file for
# every git this starts. No simulator; host only.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
BASE="${1:?usage: reproductions.sh <base commit>}"
CMD=Docs/Stage0/evidence/M0-ExitPrep/zipguard/commands
WORK="$ROOT/.build/scratch/zipguard-repro"
ZIP="$ROOT/Spikes/G01-EPUB/.build/SourcePackages/checkouts/Zip"
export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
rm -rf "$WORK"
mkdir -p "$WORK"
fails=0
echo "reproductions started $(date -u +%Y-%m-%dT%H:%M:%SZ); base $(git rev-parse "$BASE"); working tree at $(git rev-parse HEAD)" \
     "with Scripts/check-dependency-lock.py $(git diff --quiet HEAD -- Scripts/check-dependency-lock.py && echo 'as committed' || echo 'modified (the fix, not yet committed)')"
echo "check after the fix: Scripts/check-dependency-lock.py, sha256 $(shasum -a 256 Scripts/check-dependency-lock.py | cut -c1-64)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); $(xcrun swift --version 2>&1 | head -1); xcodegen $(xcodegen --version)"
echo "load: $(uptime)"

echo
echo "=== Part 1: each route in a copy of the tree at the base commit, the check before and after the fix"
git show "$BASE:Scripts/check-dependency-lock.py" > "$WORK/check-before.py"
mkdir -p "$WORK/base"
git archive "$BASE" | tar -x -C "$WORK/base"
summary() { grep -E '^(FAIL|dependency lock check)' "$1" | cut -c1-300 | sed 's/^/      /'; }
for side in before after; do
  checker="$WORK/check-before.py"; [[ $side == after ]] && checker="$ROOT/Scripts/check-dependency-lock.py"
  sylvia_python "$checker" check --root "$WORK/base" > "$WORK/unplanted-$side.log" 2>&1
  echo "  the unplanted copy, check $side the fix: exit $? -> $(tail -n 1 "$WORK/unplanted-$side.log")"
done
n=0
while IFS= read -r route; do
  n=$((n + 1))
  copy="$WORK/route-$n"
  cp -cR "$WORK/base" "$copy" 2>/dev/null || cp -R "$WORK/base" "$copy"
  if ! /usr/bin/python3 -I "$CMD/plant.py" "$copy" "$route" < /dev/null; then echo "FAIL: could not plant $route"; fails=$((fails + 1)); continue; fi
  sylvia_python "$WORK/check-before.py" check --root "$copy" > "$WORK/route-$n-before.log" 2>&1 < /dev/null &
  sylvia_python "$ROOT/Scripts/check-dependency-lock.py" check --root "$copy" > "$WORK/route-$n-after.log" 2>&1 < /dev/null &
  wait
  before=$(grep -c '^FAIL' "$WORK/route-$n-before.log"); after=$(grep -c '^FAIL' "$WORK/route-$n-after.log")
  verdict="ok (passed before the fix, fails after it)"
  if [[ $before -ne 0 || $after -eq 0 ]]; then verdict="UNEXPECTED"; fails=$((fails + 1)); fi
  echo
  echo "--- route $n: $route: $verdict"
  echo "    before the fix ($BASE):"; summary "$WORK/route-$n-before.log"
  echo "    after the fix:"; summary "$WORK/route-$n-after.log"
done < <(/usr/bin/python3 -I "$CMD/plant.py" --list)

echo
echo "=== Part 2a: XcodeGen $(xcodegen --version | awk '{print $2}') on probe projects"
P="$WORK/xcodegen"
mkdir -p "$P/env/Sources" "$P/yaml/Sources" "$P/tilde/Sources" "$P/tilde/~/Vendor/Zip/Sources/Zip" "$P/tilde/plain/Vendor/Zip/Sources/Zip"
printf 'import Foundation\n' | tee "$P/env/Sources/App.swift" "$P/yaml/Sources/App.swift" "$P/tilde/Sources/App.swift" > /dev/null
cat > "$P/env/project.yml" <<'EOF'
name: Env
options:
  bundleIdPrefix: com.example
targetTemplates:
  Quiet:
    settings:
      base:
        OTHER_SWIFT_FLAGS: "-Xfrontend -import-module -Xfrontend Zip"
  Attr:
    settings:
      base:
        OTHER_CFLAGS: "-DATTR_${attr1} -DNAME_${target_name}"
targets:
  App:
    type: application
    platform: iOS
    templates:
      - ${PROBE_TEMPLATE}
      - Attr
    templateAttributes:
      attr1: hello
    sources:
      - path: Sources
    settings:
      base:
        PROBE_BRACES: "${PROBE_VALUE}"
        PROBE_BARE: "$PROBE_VALUE"
        PROBE_DEFAULT: "${PROBE_VALUE:-dflt}"
        PROBE_ESCAPED: "\x24{PROBE_VALUE}"
        PROBE_UNSET: "${PROBE_UNSET_VAR}"
        ${PROBE_KEY}: keyvalue
EOF
echo "project.yml (env):"; sed 's/^/  | /' "$P/env/project.yml"
for mode in env no-env; do
  extra=(); [[ $mode == no-env ]] && extra=(--no-env)
  rm -rf "$P/env/Env.xcodeproj"
  env PROBE_TEMPLATE=Quiet PROBE_VALUE=expanded PROBE_KEY=KEY_FROM_ENV xcodegen generate --quiet ${extra[@]+"${extra[@]}"} \
    --spec "$P/env/project.yml" --project "$P/env"
  echo "xcodegen generate ${extra[*]:-(as sylvia_generate runs it)}, with PROBE_TEMPLATE=Quiet PROBE_VALUE=expanded PROBE_KEY=KEY_FROM_ENV: exit $?; the App target's settings:"
  grep -E '(PROBE_|OTHER_SWIFT_FLAGS|OTHER_CFLAGS|KEY_FROM_ENV|keyvalue)' "$P/env/Env.xcodeproj/project.pbxproj" | sort -u | sed 's/^[[:space:]]*/  /'
done
cat > "$P/yaml/project.yml" <<'EOF'
name: Yaml
options:
  bundleIdPrefix: com.example
x-base: &base
  PROBE_MERGED: frommerge
  PROBE_OVERRIDE: frommerge
targets:
  App:
    type: application
    platform: iOS
    sources:
      - path: Sources
    settings:
      base:
        <<: *base
        PROBE_OVERRIDE: explicit
        PROBE_TAG: !!str tagged
        PROBE_BOOL: on
        PROBE_OCTAL: 010
        PROBE_SEXA: 1:20
        PROBE_DUP: first
        PROBE_DUP: second
EOF
echo
echo "project.yml (yaml): a merge key, a tag, YAML 1.1 scalars and a duplicate key, read by XcodeGen and by the check's PyYAML:"
sed 's/^/  | /' "$P/yaml/project.yml"
xcodegen generate --quiet --spec "$P/yaml/project.yml" --project "$P/yaml"; echo "xcodegen exit: $?; XcodeGen's values:"
grep -E 'PROBE_' "$P/yaml/Yaml.xcodeproj/project.pbxproj" | sort -u | sed 's/^[[:space:]]*/  /'
echo "PyYAML's values (as the check reads them):"
sylvia_python -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1]))["targets"]["App"]["settings"]["base"]; [print(f"  {k} = {v!r}") for k, v in sorted(d.items())]' "$P/yaml/project.yml"
printf '// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "Zip", products: [.library(name: "Zip", targets: ["Zip"])], targets: [.target(name: "Zip")])\n' \
  | tee "$P/tilde/~/Vendor/Zip/Package.swift" "$P/tilde/plain/Vendor/Zip/Package.swift" > /dev/null
printf 'public struct Zip {}\n' | tee "$P/tilde/~/Vendor/Zip/Sources/Zip/Zip.swift" "$P/tilde/plain/Vendor/Zip/Sources/Zip/Zip.swift" > /dev/null
for path in '~/Vendor/Zip' 'plain/Vendor/Zip'; do
  printf 'name: Tilde\noptions:\n  bundleIdPrefix: com.example\npackages:\n  Vendored:\n    path: %s\ntargets:\n  App:\n    type: application\n    platform: iOS\n    sources:\n      - path: Sources\n    dependencies:\n      - package: Vendored\n        product: Zip\n' "$path" > "$P/tilde/project.yml"
  echo
  echo "a local package at path: $path, with a package at the literal $path inside the project directory:"
  xcodegen generate --quiet --spec "$P/tilde/project.yml" --project "$P/tilde" 2>&1 | sed 's/^/  /'
  echo "  xcodegen exit: ${PIPESTATUS[0]}; the package reference it wrote: $(grep -h -o 'relativePath = [^;]*' "$P/tilde/Tilde.xcodeproj/project.pbxproj" 2>/dev/null || echo none)"
  rm -rf "$P/tilde/Tilde.xcodeproj"
done
echo "(The same package at a plain relative path validates; at a path that starts with ~ it does not, though the literal"
echo "directory is there: XcodeGen does not read a leading ~ as a directory in the project.)"

echo
echo "=== Part 2b: SwiftPM evaluates a Package.swift again for each build, in that build's environment"
for route in 'Package.swift reads the environment through Context (adds SnapshotTesting to SylviaDesign)' \
             'Package.swift imports Foundation and reads ProcessInfo (adds SnapshotTesting to SylviaDesign)'; do
  copy="$WORK/swiftpm-$(echo "$route" | cut -c1-30 | tr -c 'A-Za-z0-9' '_')"
  mkdir -p "$copy"
  git archive "$BASE" Packages/Design | tar -x -C "$copy"
  /usr/bin/python3 -I "$CMD/plant.py" "$copy" "$route"
  echo "$route:"
  for value in unset 1; do
    how=(-u SYLVIA_EXTRA); [[ $value == 1 ]] && how=(SYLVIA_EXTRA=1)
    deps="$(env "${how[@]}" xcrun swift package --package-path "$copy/Packages/Design" --scratch-path "$copy/.build-dump" dump-package 2>&1 \
      | /usr/bin/python3 -I -c 'import json,sys; d=json.load(sys.stdin); t=[t for t in d["targets"] if t["name"]=="SylviaDesign"][0]; print(json.dumps(t["dependencies"]))' 2>&1)"
    echo "  SYLVIA_EXTRA $value: the SylviaDesign target's dependencies in dump-package: $deps"
  done
done

echo
echo "=== Part 2c: clang and the linker on probe files (xcrun clang, the macOS SDK; Minizip from $ZIP)"
C="$WORK/clang"
mkdir -p "$C/probe" "$C/outside"
if [[ -f "$ZIP/Zip/minizip/unzip.c" ]]; then
  echo "Minizip checkout: marmelroy/Zip as Spikes/G01-EPUB/Package.resolved pins it ($(/usr/bin/python3 -I -c 'import json,sys; p=[p for p in json.load(open(sys.argv[1]))["pins"] if p["identity"]=="zip"][0]["state"]; print(p["version"], p["revision"])' Spikes/G01-EPUB/Package.resolved)), resolved offline by run-2; its include directory: $(ls "$ZIP/Zip/minizip/include" | tr '\n' ' ')"
  printf '/* a product C file */\n#include "../unzip.c"\nint probe(const char *p) { unzFile f = unzOpen(p); return f != 0; }\n' > "$C/probe/dotdot.c"
  printf '/* a product C file */\n#define MINIZIP_SOURCE "../unzip.c"\n#include MINIZIP_SOURCE\nint probe(const char *p) { unzFile f = unzOpen(p); return f != 0; }\n' > "$C/probe/computed.c"
  printf '/* a product C file */\n#include <../unzip.c>\nint probe(const char *p) { unzFile f = unzOpen(p); return f != 0; }\n' > "$C/probe/angled.c"
  for f in dotdot computed angled; do
    echo "$f.c:"; sed 's/^/  | /' "$C/probe/$f.c"
    xcrun clang -c -w -I "$ZIP/Zip/minizip/include" "$C/probe/$f.c" -o "$C/probe/$f.o"
    echo "  xcrun clang -c -w -I <Minizip>/include $f.c: exit $?; Minizip functions defined in the object: $(nm "$C/probe/$f.o" 2>/dev/null | grep -cE ' T _unz') (for example '$(nm "$C/probe/$f.o" 2>/dev/null | grep -E ' T _unzOpen$' | awk '{print $2, $3}')')"
  done
else
  echo "FAIL: no Minizip checkout at $ZIP (run Docs/Stage0/evidence/M0-dependencies/xcode-27.1/commands/run-offline.sh first)"; fails=$((fails + 1))
fi
head -c 4096 /dev/urandom > "$C/outside/blob.bin"
printf 'static const unsigned char blob[] = {\n#embed "../outside/blob.bin"\n};\nconst unsigned char *blob_data(void) { return blob; }\n' > "$C/probe/embed.c"
sections() { size -m "$1" 2>/dev/null | grep -E '\((__TEXT, __const|__DATA, __data|__DATA, __const)\)' | sed 's/ (addr.*//; s/^[[:space:]]*/; /' | tr -d '\n'; }
xcrun clang -c -w -std=c23 "$C/probe/embed.c" -o "$C/probe/embed.o"
echo "embed.c (#embed \"../outside/blob.bin\", a 4096-byte file): xcrun clang -c -std=c23: exit $?$(sections "$C/probe/embed.o")"
printf '.data\n.globl _blob\n_blob:\n.incbin "../outside/blob.bin"\n' > "$C/probe/blob.s"
(cd "$C/probe" && xcrun clang -c blob.s -o blob.o)
echo "blob.s (.incbin \"../outside/blob.bin\", from the assembler's working directory): xcrun clang -c: exit $?$(sections "$C/probe/blob.o")"
printf '__asm__(".data\\n.globl _blob2\\n_blob2:\\n.incbin \\"../outside/blob.bin\\"\\n.text");\n' > "$C/probe/inline.c"
(cd "$C/probe" && xcrun clang -c -w inline.c -o inline.o)
echo "inline.c ($(tr -d '\n' < "$C/probe/inline.c")): xcrun clang -c: exit $?$(sections "$C/probe/inline.o")"
printf 'int evil(void) { return 42; }\n' > "$C/probe/evil.c"
printf 'int x(void) { return 1; }\n' > "$C/probe/x.c"
(cd "$C/probe" && xcrun clang -c evil.c -o Evil && xcrun clang -c x.c -o x.o && xcrun clang -dynamiclib -Werror Evil x.o -o libx.dylib)
echo "OTHER_LDFLAGS \"-Werror Evil\" (review R4-04): xcrun clang -dynamiclib -Werror Evil x.o: exit $?; $(nm "$C/probe/libx.dylib" 2>/dev/null | grep -E ' T _evil$' | sed 's/^[0-9a-f]* //') in the library"

echo
echo "=== Part 2d: Xcode follows a build-settings file's #include outside the project, and #include? (a probe project with no package)"
X="$WORK/xcconfig"
mkdir -p "$X/app/Sources" "$X/app/Config" "$X/elsewhere"
printf 'import Foundation\n' > "$X/app/Sources/App.swift"
printf 'name: Cfg\noptions:\n  bundleIdPrefix: com.example\nconfigFiles:\n  Debug: Config/Debug.xcconfig\ntargets:\n  App:\n    type: application\n    platform: iOS\n    sources:\n      - path: Sources\n' > "$X/app/project.yml"
printf '#include "../../elsewhere/Base.xcconfig"\n#include? "Generated.xcconfig"\n' > "$X/app/Config/Debug.xcconfig"
printf 'PROBE_FROM_OUTSIDE = included from outside the project\n' > "$X/elsewhere/Base.xcconfig"
xcodegen generate --quiet --spec "$X/app/project.yml" --project "$X/app"
for state in absent present; do
  [[ $state == present ]] && printf 'PROBE_GENERATED = from a file that appeared after generation\n' > "$X/app/Config/Generated.xcconfig"
  echo "Generated.xcconfig $state; xcodebuild -showBuildSettings -project Cfg.xcodeproj -target App -configuration Debug:"
  (cd "$X/app" && "$DEVELOPER_DIR/usr/bin/xcodebuild" -showBuildSettings -project Cfg.xcodeproj -target App -configuration Debug 2>&1) \
    | grep -E 'PROBE_' | sed 's/^[[:space:]]*/  /'
done

echo
echo "=== Part 2e: the public include directories of the transitive-only packages' C targets, at the pinned revisions"
sylvia_python - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
inv = json.load(open(os.path.join(root, 'Docs/Licenses/inventory.json')))
places = ['Spikes/G01-EPUB/.build/SourcePackages/checkouts', 'Spikes/G02-Transfer/SourceService/.build/checkouts']
for p in inv['packages']:
    if p['role'] != 'product-transitive':
        continue
    repo = p['url'].rstrip('/').split('/')[-1].removesuffix('.git')
    found = [os.path.join(root, d, repo) for d in places if os.path.isdir(os.path.join(root, d, repo))]
    if not found:
        print(f'  {p["name"]}: no checkout here')
        continue
    headers = {h.casefold() for h in p.get('headers', [])}
    dirs = []
    for dp, dns, fns in os.walk(found[0]):
        dns[:] = [d for d in dns if d not in ('.git', 'Tests', 'Benchmarks', 'Documentation') and not d.endswith('Tests')]
        if os.path.basename(dp) == 'include':
            dirs.append((dp, sorted(fns)))
    if not dirs:
        print(f'  {p["name"]}: no directory named include (no C target with public headers)')
    for dp, fns in dirs:
        others = [f for f in fns if f.casefold() not in headers and f != 'module.modulemap']
        print(f'  {p["name"]}: {os.path.relpath(dp, found[0])}: {len(fns)} files; listed headers {sum(f.casefold() in headers for f in fns)}, '
              f'module maps {fns.count("module.modulemap")}, anything else: {others or "none"}')
PY

echo
echo "reproductions finished $(date -u +%Y-%m-%dT%H:%M:%SZ); problems: $fails"
echo "load: $(uptime)"
exit $fails
