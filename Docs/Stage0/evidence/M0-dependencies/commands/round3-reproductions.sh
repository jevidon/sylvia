#!/bin/bash
# ADR-0014 evidence: review round 3's reproductions (R3-01, R3-04, R3-05), the further routes the fix closes, and the
# checks behind the advisory verdicts of R3-02.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/round3-reproductions.sh > Docs/Stage0/evidence/M0-dependencies/round3-reproductions.log 2>&1
#
# 1. R3-01: routes to Zip and Minizip (CVE-2023-39135), and out of Apps/ and Packages/, that need no import or include in
#    any source file: compiler flags, settings, prefix and bridging headers, module maps named by settings, definitions,
#    and search paths into package checkouts. Each case makes one change to a fresh copy of the committed tree
#    (git archive HEAD) and runs that copy's check; it passes only if the check reports the expected category. The same
#    change is made to a copy of the reviewed commit (REVIEWED) and that commit's check runs on it, to show what the
#    reviewed check reported ("missed" means nothing in that category). The allowed changes must pass.
# 2. R3-04: an Xcode project with a package reference of its own, force-added to a copy made into a git repository, as
#    the reviewer did.
# 3. The routes are real: each compiles against a stand-in module (BModule, with a header bmodule.h) with no import or
#    include in the source file, and calls into it.
# 4. A limit ADR-0014 section 3 lists stays unreported.
# 5. R3-05: Scripts/ci.sh dependency-lock with a tools virtualenv made as Scripts/tools/bootstrap.sh makes one: the
#    console shows only "pass" and the warning is in the drop-in's log. Then the same run of a copy of the tree in
#    which Scripts/ci.sh has the change ADR-0014 requests, which prints the warning.
# 6. R3-02: the fixes the advisory verdicts rely on are in the pinned revisions (git merge-base --is-ancestor in the
#    package checkouts that commands/resolve-locks.sh leaves).
#
# Host only; no network, no simulator; nothing is built but the stand-in module and the syntax checks. Copies are APFS
# clones (cp -c) under a new directory in .build/scratch; each is deleted after its case. Commit before running.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
REVIEWED=e38124785c5eca712122ce8e87191350c8cb3015  # the commit review round 3 examined
WORK="$ROOT/.build/scratch/round3-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$WORK/base" "$WORK/reviewed"
PY="$SYLVIA_TOOLS_VENV/bin/python"
echo "round 3 reproductions $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD); reviewed commit $REVIEWED"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); $(xcrun swift --version 2>&1 | head -1)"
echo "load: $(uptime)"
git archive HEAD | tar -x -C "$WORK/base" -f -
git archive "$REVIEWED" | tar -x -C "$WORK/reviewed" -f -
fails=0

check() { # tree -> the check's output in <tree>.out; returns the check's status
  "$PY" -I "$1/Scripts/check-dependency-lock.py" check --root "$1" > "$1.out" 2>&1
}
n=0
fresh() { # source tree -> sets $copy to a new copy of it
  n=$((n + 1))
  copy="$WORK/c$n"
  cp -cR "$1" "$copy" 2>/dev/null || { rm -rf "$copy"; cp -R "$1" "$copy"; }
}
case_() { # name, expected category, mutation (a shell function run inside the copy)
  local name="$1" category="$2" mutate="$3" hits before
  fresh "$WORK/reviewed"
  ( cd "$copy" && "$mutate" )
  check "$copy"
  before="$(grep -cE "^FAIL $category " "$copy.out")"
  rm -rf "$copy" "$copy.out"
  fresh "$WORK/base"
  ( cd "$copy" && "$mutate" )
  check "$copy"
  hits="$(grep -E "^FAIL " "$copy.out" || true)"
  if grep -qE "^FAIL $category " "$copy.out"; then
    echo "ok    $name -> $(grep -cE "^FAIL $category " "$copy.out") x $category (reviewed check: $([[ $before -gt 0 ]] && echo "$before x $category" || echo missed))"
    echo "$hits" | cut -c1-260 | sed 's/^/        /'
  else
    echo "FAIL  $name: expected $category; the check printed:"; sed 's/^/        /' "$copy.out"; fails=$((fails+1))
  fi
  rm -rf "$copy" "$copy.out"
}
allowed() { # name, change: the check must report no failure
  local name="$1" change="$2"
  fresh "$WORK/base"
  ( cd "$copy" && "$change" )
  if check "$copy"; then
    echo "ok    $name -> $(tail -1 "$copy.out")"
  else
    echo "FAIL  $name: expected no failure; the check printed:"; grep '^FAIL' "$copy.out" | sed 's/^/        /'; fails=$((fails+1))
  fi
  rm -rf "$copy" "$copy.out"
}
limit() { # name, change: a route ADR-0014 says the check cannot see; it must stay unreported (documented, not hidden)
  local name="$1" change="$2"
  fresh "$WORK/base"
  ( cd "$copy" && "$change" )
  if check "$copy"; then
    echo "ok    $name -> not reported, as ADR-0014 section 3 states ($(tail -1 "$copy.out"))"
  else
    echo "NOTE  $name -> reported after all:"; grep '^FAIL' "$copy.out" | sed 's/^/        /'
  fi
  rm -rf "$copy" "$copy.out"
}
edit() { # file, old text, new text (Python string literals), replacing the first occurrence; the old text must exist
  /usr/bin/python3 -I -c '
import sys
p, old, new = sys.argv[1], eval(sys.argv[2]), eval(sys.argv[3])
t = open(p).read()
assert old in t, f"{old!r} not in {p}"
open(p, "w").write(t.replace(old, new, 1))
' "$1" "$2" "$3"
}
put() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }  # file, text (printf %s: written as given)
SD=Packages/Design/Sources/SylviaDesign
PKG=Packages/Design/Package.swift
YML=Apps/DesignCatalog/project.yml
RES="'                .process(\"Resources/Vocabulary.xcstrings\"),\n            ]\n'"
swift_settings() { edit $PKG "$RES" "'                .process(\"Resources/Vocabulary.xcstrings\"),\n            ],\n            $1\n'"; }
app_setting() { edit $YML "'        PRODUCT_BUNDLE_IDENTIFIER: com.jevidon.sylvia.designcatalog\n'" "'        PRODUCT_BUNDLE_IDENTIFIER: com.jevidon.sylvia.designcatalog\n        $1\n'"; }

echo
echo "### The unchanged tree"
if check "$WORK/base"; then echo "ok    the committed tree passes: $(tail -1 "$WORK/base.out")"; else echo "FAIL  the committed tree fails:"; cat "$WORK/base.out"; fails=$((fails+1)); fi

echo
echo "### R3-01, the routes the review found: -import-module, -include, and bridging or prefix headers or search paths into package checkouts"
a1() { swift_settings 'swiftSettings: [.unsafeFlags([\"-Xfrontend\", \"-import-module\", \"-Xfrontend\", \"Zip\"])]'; }
a2() { app_setting 'OTHER_SWIFT_FLAGS: \"$(inherited) -Xfrontend -import-module -Xfrontend Zip\"'; }
a3() { app_setting 'OTHER_CFLAGS: \"-include unzip.h\"'; }
a4() { swift_settings 'swiftSettings: [.unsafeFlags([\"-Xcc\", \"-include\", \"-Xcc\", \"unzip.h\"])]'; }
a5() { app_setting 'SWIFT_OBJC_BRIDGING_HEADER: \"$(BUILD_DIR)/../../SourcePackages/checkouts/Zip/Zip/minizip/include/unzip.h\"'; }
a6() { app_setting 'GCC_PREFIX_HEADER: \"$(BUILD_DIR)/../../SourcePackages/checkouts/Zip/Zip/minizip/include/zip.h\"'; }
a7() { app_setting 'HEADER_SEARCH_PATHS: \"$(inherited) $(BUILD_DIR)/../../SourcePackages/checkouts/Zip/Zip/minizip/include\"'; }
a8() { app_setting 'SWIFT_INCLUDE_PATHS: \"$(BUILD_DIR)/../../SourcePackages/checkouts/Zip/Zip/minizip\"'; }
a9() { swift_settings 'cSettings: [.headerSearchPath(\"../../.build/checkouts/Zip/Zip/minizip/include\")]'; }
case_ "SylviaDesign imports Zip into every file with -Xfrontend -import-module (unsafeFlags)" transitive-direct a1
case_ "the design catalog app imports Zip into every file with -import-module (OTHER_SWIFT_FLAGS)" transitive-direct a2
case_ "the design catalog app force-includes Minizip's unzip.h (OTHER_CFLAGS -include)" transitive-direct a3
case_ "SylviaDesign force-includes unzip.h through -Xcc -include (unsafeFlags)" transitive-direct a4
case_ "the app takes unzip.h from the package checkouts beside the build products as its bridging header" transitive-direct a5
case_ "the app takes zip.h from the package checkouts as its prefix header" transitive-direct a6
case_ "the app searches Minizip's headers in the package checkouts through \$(BUILD_DIR)/.." outside-product a7
case_ "the app searches Swift modules in the package checkouts through \$(BUILD_DIR)/.." outside-product a8
case_ "SylviaDesign searches a package checkout under its own .build for headers" outside-product a9

echo
echo "### R3-01, further routes the same rules close"
b1() { app_setting 'SWIFT_MODULE_ALIASES: \"Archive=Zip\"'; }
b2() { edit $YML "'    sources:\n      - path: Sources\n    dependencies:\n      - package: SylviaDesign\n        product: SylviaDesign\n'" "'    sources:\n      - path: Sources\n        compilerFlags: [\"-include\", \"unzip.h\"]\n    dependencies:\n      - package: SylviaDesign\n        product: SylviaDesign\n'"; }
b3() { app_setting 'WARNING_CFLAGS: \"-Wall -Wp,-include,unzip.h\"'; }
b4() { app_setting 'GCC_PREPROCESSOR_DEFINITIONS: \"HDR=<unzip.h>\"'; put Apps/DesignCatalog/Sources/zipprobe.c $'#include HDR\n'; }
b5() { app_setting 'MODULEMAP_FILE: \"$(SRCROOT)/Support/Archive.txt\"'; put Apps/DesignCatalog/Support/Archive.txt $'module Archive {\n    header \"unzip.h\"\n    export *\n}\n'; }
b6() { put Packages/Design/Tests/SylviaDesignTests/zipshim.h $'#include <unzip.h>\n'; }
b7() { edit $PKG "'        .target(\n            name: \"SylviaDesignGallery\",'" "'        .target(name: \"Vendored\", path: \".build/checkouts/Zip/Zip\"),\n        .target(\n            name: \"SylviaDesignGallery\",'"; }
b8() { app_setting 'CC: /opt/homebrew/opt/llvm/bin/clang'; }
b9() { swift_settings 'swiftSettings: [.unsafeFlags([\"-vfsoverlay\", \"overlay.yaml\"])]'; }
case_ "the app aliases Zip with the SWIFT_MODULE_ALIASES setting" transitive-direct b1
case_ "per-file compilerFlags force-include unzip.h" transitive-direct b2
case_ "WARNING_CFLAGS passes -Wp,-include,unzip.h to the preprocessor" flag b3
case_ "a definition names unzip.h and a C file includes it through the macro" transitive-direct b4
case_ "MODULEMAP_FILE names a module map called Archive.txt that wraps unzip.h" transitive-direct b5
case_ "a header in SylviaDesignTests includes unzip.h (headers are product code wherever they sit)" transitive-direct b6
case_ "a SylviaDesign package target takes its sources from a package checkout under .build" outside-product b7
case_ "the app replaces the C compiler (CC)" outside-product b8
case_ "SylviaDesign passes a VFS overlay (-vfsoverlay)" flag b9

echo
echo "### R3-04: an Xcode project force-added to the index, with its own package reference (the check reads the index)"
x1() {
  put Apps/DesignCatalog/DesignCatalog.xcodeproj/project.pbxproj $'/* XCRemoteSwiftPackageReference "Zip" */ = { isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/marmelroy/Zip"; requirement = { branch = master; kind = branch; }; };\n'
  git init -q . && git add -A && git add -f Apps/DesignCatalog/DesignCatalog.xcodeproj/project.pbxproj
}
case_ "Apps/DesignCatalog/DesignCatalog.xcodeproj is committed with a branch requirement on marmelroy/Zip" xcode-project x1

echo
echo "### Allowed: changes the rules must not report"
n1() { app_setting 'OTHER_SWIFT_FLAGS: \"$(inherited) -warnings-as-errors -enable-upcoming-feature ExistentialAny -strict-concurrency=complete\"'; }
n2() { edit $YML "'        TEST_HOST: \"\$(BUILT_PRODUCTS_DIR)/DesignCatalog.app/DesignCatalog\"\n'" "'        TEST_HOST: \"\$(BUILT_PRODUCTS_DIR)/DesignCatalog.app/DesignCatalog\"\n        OTHER_SWIFT_FLAGS: \"-Xfrontend -import-module -Xfrontend Zip\"\n        OTHER_CFLAGS: \"-include unzip.h\"\n'"; }
n3() { app_setting 'SWIFT_INCLUDE_PATHS: \"$(inherited) $(BUILT_PRODUCTS_DIR)\"'; }
allowed "the app passes only flags product targets may pass" n1
allowed "the catalog's unit-test target passes -import-module Zip and -include unzip.h (tests never ship)" n2
allowed "the app searches the build products directory for modules" n3

echo
echo "### A limit ADR-0014 section 3 lists: not reported"
l1() { edit $YML "'    sources:\n      - path: Sources\n    dependencies:\n      - package: SylviaDesign\n        product: SylviaDesign\n'" "'    sources:\n      - path: Sources\n    preBuildScripts:\n      - name: Copy\n        script: cp \"\$BUILD_DIR/../../SourcePackages/checkouts/Zip/Zip/minizip/include/un\$(printf zip).h\" \"\$DERIVED_FILE_DIR/\"\n    dependencies:\n      - package: SylviaDesign\n        product: SylviaDesign\n'"; }
limit "a build script assembles unzip.h's name from pieces (paths build scripts compute)" l1

echo
echo "### The routes are real: each compiles against a stand-in module with no import or include in the source, and calls into it"
P="$WORK/proof"; mkdir -p "$P/inc" "$P/mod" "$P/mcache"
printf 'public func bfunc() -> Int { 1 }\n' > "$P/BModule.swift"
printf 'int bfunc(void);\n' > "$P/inc/bmodule.h"
printf 'module Archive {\n    header "bmodule.h"\n    export *\n}\n' > "$P/inc/Archive.txt"
if xcrun swiftc -emit-module -module-name BModule -parse-as-library -swift-version 6 -o "$P/mod/BModule.swiftmodule" "$P/BModule.swift" > "$P/module.log" 2>&1; then
  echo "ok    stand-in Swift module BModule built ($(xcrun swiftc --version 2>&1 | head -1))"
else
  echo "FAIL  the stand-in module did not build:"; sed 's/^/        /' "$P/module.log"; fails=$((fails+1))
fi
proof() { # name, file, text, command... (run in $P; the file holds the text)
  local name="$1" file="$2" text="$3"; shift 3
  printf '%s\n' "$text" > "$P/$file"
  if ( cd "$P" && "$@" ) > "$P/proof.log" 2>&1; then
    echo "ok    compiles: $name ($*)"
  else
    echo "FAIL  does not compile: $name ($*)"; sed 's/^/        /' "$P/proof.log"; fails=$((fails+1))
  fi
}
proof "-import-module: a Swift file with no import calls into the module" use1.swift '@MainActor func useB() -> Int { bfunc() }' \
  xcrun swiftc -typecheck -parse-as-library -swift-version 6 -I mod -Xfrontend -import-module -Xfrontend BModule use1.swift
proof "-module-alias: import Archive loads BModule" use2.swift $'import Archive\n@MainActor func useB() -> Int { bfunc() }' \
  xcrun swiftc -typecheck -parse-as-library -swift-version 6 -I mod -module-alias Archive=BModule use2.swift
proof "-include: a C file with no include calls the header's function" use3.c 'int useB(void) { return bfunc(); }' \
  xcrun clang -fsyntax-only -Werror=implicit-function-declaration -I inc -include bmodule.h use3.c
proof "a bridging header (-import-objc-header): a Swift file with no import calls the C function" use4.swift '@MainActor func useC() -> Int32 { bfunc() }' \
  xcrun swiftc -typecheck -parse-as-library -swift-version 6 -import-objc-header inc/bmodule.h use4.swift
proof "a definition carries the header name into #include HDR" use5.c $'#include HDR\nint useB(void) { return bfunc(); }' \
  xcrun clang -fsyntax-only -Werror=implicit-function-declaration -I inc '-DHDR=<bmodule.h>' use5.c
proof "a module map called Archive.txt, named by -fmodule-map-file=, makes @import Archive work" use6.m $'@import Archive;\nint useB(void) { return bfunc(); }' \
  xcrun clang -fsyntax-only -fmodules -fmodules-cache-path=mcache -fmodule-map-file=inc/Archive.txt use6.m

echo
echo "### R3-05: what a passing Scripts/ci.sh run shows when the tools virtualenv holds a pip below the advisory floor"
FRESH="$WORK/fresh-venv"
PY3="$(command -v python3)"
echo "python3 on PATH (what bootstrap.sh runs): $PY3 -> $("$PY3" --version 2>&1); its ensurepip bundles pip $("$PY3" -I -c 'import ensurepip; print(ensurepip.version())')"
if "$PY3" -m venv "$FRESH"; then
  echo "python3 -m venv: $("$FRESH/bin/pip" --version)"
else
  echo "FAIL  python3 -m venv failed"; fails=$((fails+1))
fi
# Copy every distribution of the shared virtualenv except pip (the 20 pins) into the new one, as round 2 did: the
# distribution list is what `pip install -r Scripts/tools/requirements.txt` gives, and no network is used.
"$PY" -I - "$FRESH" <<'PYEOF'
import os, shutil, sys
from importlib import metadata
fresh = sys.argv[1]
src_site = next(p for p in sys.path if p.endswith('site-packages') and p.startswith(sys.prefix))
dst_site = os.path.join(fresh, os.path.relpath(src_site, sys.prefix))
copied = []
for d in metadata.distributions():
    if d.metadata['Name'].lower() == 'pip':
        continue
    for f in d.files or []:
        src = os.path.realpath(d.locate_file(f))
        if not src.startswith(os.path.realpath(src_site) + os.sep) or not os.path.isfile(src):
            continue
        dst = os.path.join(dst_site, os.path.relpath(src, os.path.realpath(src_site)))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
    copied.append(d.metadata['Name'])
print('copied from the shared virtualenv, pip excluded: %d distributions' % len(copied))
PYEOF
echo
echo "Scripts/ci.sh dependency-lock at HEAD, SYLVIA_TOOLS_VENV set to this virtualenv; the whole console output:"
start=$SECONDS
SYLVIA_TOOLS_VENV="$FRESH" Scripts/ci.sh dependency-lock > "$WORK/ci-fresh.out" 2>&1
echo "exit status $? ($((SECONDS - start)) s)"
sed 's/^/    | /' "$WORK/ci-fresh.out"
if grep -q '^WARN\|    | WARN' "$WORK/ci-fresh.out"; then echo "the console shows a warning"; else echo "the console shows no warning (review R3-05 reproduced)"; fi
echo "the drop-in's log, .build/ci-logs/12-dependency-lock.log, ends with:"
tail -n 3 "$ROOT/.build/ci-logs/12-dependency-lock.log" | cut -c1-300 | sed 's/^/    | /'
echo
echo "the same run in a copy of the tree whose Scripts/ci.sh has the change ADR-0014 requests (print a passing drop-in's WARN lines):"
fresh "$WORK/base"
CI="$copy"
edit "$CI/Scripts/ci.sh" "'    echo \"    pass (\$((SECONDS - start))s)\"\n'" "'    echo \"    pass (\$((SECONDS - start))s)\"\n    grep -E \"^WARN \" \"\$LOG_DIR/\$name.log\" | sed \"s/^/    | /\"\n'"
echo "the change, as a diff of Scripts/ci.sh:"
diff Scripts/ci.sh "$CI/Scripts/ci.sh" | sed 's/^/    /'
SYLVIA_TOOLS_VENV="$FRESH" "$CI/Scripts/ci.sh" dependency-lock > "$WORK/ci-proposed.out" 2>&1
echo "exit status $?; the whole console output:"
sed 's/^/    | /' "$WORK/ci-proposed.out"
if grep -q 'WARN toolchain' "$WORK/ci-proposed.out"; then echo "ok    with the requested change the console shows the warning"; else echo "FAIL  the requested change does not show the warning"; fails=$((fails+1)); fi
rm -rf "$CI"

echo
echo "### R3-02: the fixes the advisory verdicts rely on are in the pinned revisions (package checkouts from resolve-locks.sh)"
C=Spikes/G02-Transfer/SourceService/.build/checkouts
ancestor() { # checkout, fix commit or release tag, pinned revision, what
  if [[ ! -d "$1/.git" && ! -f "$1/.git" ]]; then
    echo "FAIL  $4: no checkout at $1 (run commands/resolve-locks.sh first)"; fails=$((fails+1)); return
  fi
  if git -C "$1" merge-base --is-ancestor "$2" "$3" 2>/dev/null; then
    echo "ok    $4: $2 ($(git -C "$1" log -1 --format='%h %ad %s' --date=short "$2" | cut -c1-90)) is an ancestor of the pinned $3"
  else
    echo "FAIL  $4: $2 is not an ancestor of $3"; fails=$((fails+1))
  fi
}
ancestor $C/swift-crypto 47d3869a a9d1d5ab8951ada40cafff8c8e2b551dfde4f390 "swift-crypto 5.0.0 has the fix for GHSA-8q93-f6xh-4f6f (CVE-2026-43823)"
ancestor $C/swift-nio-ssl 2.37.2 322f3c2a4a21df31c84ca416bf65ee5e9059e440 "swift-nio-ssl 2.37.5 follows 2.37.2, the patched release of GHSA-xfxg-9975-pc2j (CVE-2026-43820)"
ancestor $C/swift-nio 2.101.0 21de5f08c1a166a6dd293d0e587ad977bf8dac5d "swift-nio 2.103.0 follows 2.101.0, the patched release of GHSA-qcc5-f287-vgmq (CVE-2026-43678)"
ancestor $C/swift-nio 2.100.0 21de5f08c1a166a6dd293d0e587ad977bf8dac5d "swift-nio 2.103.0 follows 2.100.0, the patched release of four other swift-nio advisories"
echo "the 47d3869a commit message names the flaw it fixes:"
git -C $C/swift-crypto log -1 --format='%b' 47d3869a | head -3 | sed 's/^/    /'

echo
rm -rf "$WORK"
echo "round 3 reproductions finished $(date -u +%Y-%m-%dT%H:%M:%SZ); failures: $fails"
echo "load: $(uptime)"
exit $fails
