#!/bin/bash
# ADR-0014 evidence: review round 2's reproductions (R2-01, R2-02) and the further routes the fix closes.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/round2-reproductions.sh > Docs/Stage0/evidence/M0-dependencies/round2-reproductions.log 2>&1
#
# 1. R2-02, the import ban for CVE-2023-39135 (Zip and Minizip): each case makes one change to a fresh copy of the
#    committed tree (`git archive HEAD`) and runs that copy's check; it passes only if the check reports the expected
#    category. The same change is also made to a copy of the reviewed commit (REVIEWED, below) and that commit's check
#    is run on it, to show what the reviewed check reported for the route ("missed" means it reported nothing in that
#    category). The allowed changes must pass with no failure.
# 2. The Swift and C forms of part 1 compile against a stand-in module (BModule, with a header bmodule.h), each followed
#    by a call into that module, so the import or include that a lexer could misread is a real one.
# 3. The limits ADR-0014 lists under "What the check cannot see": each form compiles, and the check does not report it.
# 4. R2-01: a tools virtualenv made the way Scripts/tools/bootstrap.sh makes one (`python3 -m venv`, then exactly the
#    pinned requirements), with the pip its Python bundles. `Scripts/ci.sh dependency-lock` must pass with it (with a
#    warning when that pip is below the advisory floor); the reviewed commit's check fails it. The pinned distributions
#    are copied from the shared virtualenv instead of downloaded from PyPI, so no network is used: the distribution list
#    is what `pip install -r Scripts/tools/requirements.txt` gives.
#
# Host only; no network, no simulator; nothing is built but the stand-in module and the syntax checks. Copies are APFS
# clones (cp -c) under a new directory in .build/scratch; each is deleted after its case. Commit before running.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
REVIEWED=1442a66860577512a13861667c1b573ea755a1e6  # the commit review round 2 examined
WORK="$ROOT/.build/scratch/round2-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$WORK/base" "$WORK/reviewed"
PY="$SYLVIA_TOOLS_VENV/bin/python"
echo "round 2 reproductions $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD); reviewed commit $REVIEWED"
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
    echo "$hits" | cut -c1-250 | sed 's/^/        /'
  else
    echo "FAIL  $name: expected $category; the check printed:"; sed 's/^/        /' "$copy.out"; fails=$((fails+1))
  fi
  rm -rf "$copy" "$copy.out"
}
allowed() { # name, change (a shell function run inside the copy): the check must report no failure
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
SD=Packages/Design/Sources/SylviaDesign
put() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }  # file, text (printf %s: written as given)

echo
echo "### The unchanged tree"
if check "$WORK/base"; then echo "ok    the committed tree passes: $(tail -1 "$WORK/base.out")"; else echo "FAIL  the committed tree fails:"; cat "$WORK/base.out"; fails=$((fails+1)); fi

echo
echo "### R2-02 (a): non-test code in a directory named like test code (test code is now what only test targets build)"
a1() { put $SD/ABTests/Experiment.swift $'internal import Zip\nstruct Experiment {}\n'; }
a2() { put $SD/ABTests/Experiment.swift $'struct Experiment {}\n'; }
a3() { put $SD/ABTests/zipprobe.c $'#include <unzip.h>\n'; }
a4() { put $SD/ABTests/module.modulemap $'module ArchiveC {\n    header "unzip.h"\n    export *\n}\n'; }
a5() { put Apps/DesignCatalog/Sources/FeatureTests/ZipProbe.swift $'import Zip\n'; }
a6() { put Packages/Design/Tests/Shared/ZipProbe.swift $'import Zip\n'; }
case_ "SylviaDesign builds ABTests/Experiment.swift, which imports Zip (the reviewer's case)" transitive-direct a1
case_ "SylviaDesign builds a file from ABTests/ (named like test code)" test-layout a2
case_ "a C file in SylviaDesign's ABTests/ includes Minizip's unzip.h" transitive-direct a3
case_ "a module map in SylviaDesign's ABTests/ wraps unzip.h" transitive-direct a4
case_ "the DesignCatalog app target builds Sources/FeatureTests/ZipProbe.swift, which imports Zip" transitive-direct a5
case_ "a file under Packages/Design/Tests that no target includes imports Zip" transitive-direct a6

echo
echo "### R2-02 (b): literals and identifiers a lexer can misread (the check now reads the raw text)"
probe() { put $SD/ZipProbe.swift "$1"; }
b1() { probe $'@MainActor let r1 = #/ /* /#\nimport Zip\n@MainActor let r2 = #/ */ /#\n'; }
b2() { probe $'@MainActor let r3 = /"/; import Zip\n'; }
b3() { probe $'@MainActor let r1 = #/\n  [/*]\n/#\nimport Zip\n@MainActor let r2 = #/\n  [*/]\n/#\n'; }
b4() { probe $'func `a /* b`() {}\nimport Zip\nfunc `c */ d`() {}\n'; }
b5() { probe $'func `e " f`() {}; import Zip\n'; }
b6() { probe $'// a note that says import Zip\n'; }
b7() { put $SD/zipprobe.cpp $'const char *a = R"(\n/*)";\n#include <unzip.h>\nconst char *b = "*/";\n'; }
b8() { put $SD/zipprobe.c $'/* a comment that ends with a spliced *\\\n/\n#include <unzip.h>\n/* another comment */\n'; }
b9() { put $SD/zipprobe.c $'%:include <unzip.h>\n'; }
b10() { put $SD/zipprobe.c $'??=include <unzip.h>\n'; }
b11() { put $SD/zipprobe.c $'#define HEADER <unzip.h>\n#include HEADER\n'; }
b12() { put $SD/zipprobe.c $'_Pragma("clang module import Minizip")\n'; }
b13() { put $SD/ZipProbe.m $'#import "Zip-Swift.h"\n'; }
b14() { edit Packages/Design/Package.swift "'            dependencies: [\"SylviaDesignTokens\"],\n            path: \"Sources/SylviaDesign\",'" \
    "'            dependencies: [\"SylviaDesignTokens\", .product(name: \"SnapshotTesting\", package: \"swift-snapshot-testing\", moduleAliases: [\"Zip\": \"Archive\"])],\n            path: \"Sources/SylviaDesign\",'"; }
case_ "import Zip between two extended regex literals that hold /* and */" transitive-direct b1
case_ "import Zip after a bare regex literal that holds a quote, on one line" transitive-direct b2
case_ "import Zip between two multi-line extended regex literals that hold /* and */" transitive-direct b3
case_ "import Zip between two raw identifiers that hold /* and */" transitive-direct b4
case_ "import Zip after a raw identifier that holds a quote" transitive-direct b5
case_ "a comment that names the import is reported too (the cost of reading the raw text; the reviewed check rightly ignored it)" transitive-direct b6
case_ "#include <unzip.h> after a C++ raw string that holds /*" transitive-direct b7
case_ "#include <unzip.h> after a comment that a line splice ends" transitive-direct b8
case_ "%:include <unzip.h> (digraph)" transitive-direct b9
case_ "??=include <unzip.h> (trigraph)" transitive-direct b10
case_ "a computed #include through a macro that names unzip.h" transitive-direct b11
case_ "_Pragma(\"clang module import Minizip\")" transitive-direct b12
case_ "#import \"Zip-Swift.h\" (the Swift module's generated header)" transitive-direct b13
case_ "SylviaDesign renames Zip with SwiftPM module aliasing (moduleAliases:); also test-in-product and a stale used_by_targets, since the only remote package a product manifest requires today is a test package" transitive-direct b14

echo
echo "### Allowed: changes the rules must not report"
n1() { put Packages/Design/Tests/SylviaDesignTests/ZipProbeTests.swift $'internal import Zip\n'; }
n2() { put $SD/Testing/Probe.swift $'struct Probe {}\n'; }
allowed "a test of the design package imports Zip (SylviaDesignTests builds it; tests never ship)" n1
allowed "SylviaDesign builds a file from Testing/ (a name that does not end in Tests)" n2

echo
echo "### Limits ADR-0014 section 3 lists: not reported"
l1() { put $SD/zipprobe.c $'#define CAT(a, b) a##b\n#define STR(x) #x\n#define XSTR(x) STR(x)\n#include XSTR(CAT(un, zip).h)\n'; }
l2() { probe $'@_silgen_name("unzOpen64") func openArchive(_ path: UnsafeRawPointer?) -> OpaquePointer?\n'; }
limit "a computed #include whose header name a macro assembles by token pasting (unzip.h never appears whole)" l1
limit "@_silgen_name declares a Minizip C function by symbol, with no import" l2

echo
echo "### The forms compile: each hides a real import or include of a stand-in module, then calls into it"
P="$WORK/proof"; mkdir -p "$P/inc" "$P/mod" "$P/mcache"
printf 'public func bfunc() -> Int { 1 }\n' > "$P/BModule.swift"
printf 'int bfunc(void);\n' > "$P/inc/bmodule.h"
printf 'module BModule {\n    header "bmodule.h"\n    export *\n}\n' > "$P/inc/module.modulemap"
if xcrun swiftc -emit-module -module-name BModule -parse-as-library -swift-version 6 -o "$P/mod/BModule.swiftmodule" "$P/BModule.swift" > "$P/module.log" 2>&1; then
  echo "ok    stand-in Swift module BModule built ($(xcrun swiftc --version 2>&1 | head -1))"
else
  echo "FAIL  the stand-in module did not build:"; sed 's/^/        /' "$P/module.log"; fails=$((fails+1))
fi
USE_B='@MainActor func useB() -> Int { bfunc() }'
swiftform() { # name, source text (the probe's form with BModule in place of Zip)[, the use that must resolve]
  local use="${3:-$USE_B}"
  printf '%s%s\n' "$2" "$use" > "$P/use.swift"
  if xcrun swiftc -typecheck -parse-as-library -swift-version 6 -I "$P/mod" "$P/use.swift" > "$P/use.log" 2>&1; then
    echo "ok    compiles (swiftc -typecheck -swift-version 6), and \`$use\` resolves: $1"
  else
    echo "FAIL  does not compile: $1"; sed 's/^/        /' "$P/use.log"; fails=$((fails+1))
  fi
}
cform() { # name, file name, source text, extra compiler flags...
  local name="$1" file="$2" text="$3"; shift 3
  local cc=clang; [[ "$file" == *.cpp ]] && cc=clang++
  printf '%s\nint useB(void) { return bfunc(); }\n' "$text" > "$P/$file"
  if xcrun "$cc" -fsyntax-only -Werror=implicit-function-declaration -I "$P/inc" "$@" "$P/$file" > "$P/c.log" 2>&1; then
    echo "ok    compiles ($cc -fsyntax-only -Werror=implicit-function-declaration${*:+ $*}), and bfunc is declared by the header: $name"
  else
    echo "FAIL  does not compile: $name"; sed 's/^/        /' "$P/c.log"; fails=$((fails+1))
  fi
}
swiftform "import between two extended regex literals that hold /* and */" $'@MainActor let r1 = #/ /* /#\nimport BModule\n@MainActor let r2 = #/ */ /#\n'
swiftform "import after a bare regex literal that holds a quote" $'@MainActor let r3 = /"/; import BModule\n'
swiftform "import between two multi-line extended regex literals" $'@MainActor let r1 = #/\n  [/*]\n/#\nimport BModule\n@MainActor let r2 = #/\n  [*/]\n/#\n'
swiftform "import between two raw identifiers that hold /* and */" $'func `a /* b`() {}\nimport BModule\nfunc `c */ d`() {}\n'
swiftform "import after a raw identifier that holds a quote" $'func `e " f`() {}; import BModule\n'
cform "#include after a C++ raw string that holds /*" use.cpp $'const char *a = R"(\n/*)";\n#include <bmodule.h>\nconst char *b = "*/";' -std=c++17
cform "#include after a comment that a line splice ends" use.c $'/* a comment that ends with a spliced *\\\n/\n#include <bmodule.h>\n/* another comment */'
cform "%:include (digraph)" use.c $'%:include <bmodule.h>'
cform "??=include (trigraph, with -trigraphs)" use.c $'??=include <bmodule.h>' -trigraphs
cform "computed #include through a macro" use.c $'#define HEADER <bmodule.h>\n#include HEADER'
cform "_Pragma(\"clang module import BModule\")" use.c $'_Pragma("clang module import BModule")' -fmodules "-fmodules-cache-path=$P/mcache"
cform "limit: #include assembled by token pasting (bmodule.h never appears whole)" use.c $'#define CAT(a, b) a##b\n#define STR(x) #x\n#define XSTR(x) STR(x)\n#include XSTR(CAT(bmod, ule).h)'
swiftform "limit: @_silgen_name declares a C function by its symbol, with no import" $'@_silgen_name("bfunc") func cBfunc() -> Int32\n' '@MainActor func useC() -> Int32 { cBfunc() }'

echo
echo "### R2-01: a tools virtualenv as a fresh bootstrap makes it"
FRESH="$WORK/fresh-venv"
PY3="$(command -v python3)"
echo "python3 on PATH (what bootstrap.sh runs): $PY3 -> $("$PY3" --version 2>&1); its ensurepip bundles pip $("$PY3" -I -c 'import ensurepip; print(ensurepip.version())')"
if "$PY3" -m venv "$FRESH"; then
  echo "python3 -m venv: $("$FRESH/bin/pip" --version)"
else
  echo "FAIL  python3 -m venv failed"; fails=$((fails+1))
fi
# Copy every distribution of the shared virtualenv except pip (the 20 pins) into the new one's site-packages.
"$PY" -I - "$FRESH" <<'EOF'
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
            continue  # console scripts in bin/ are not needed by the check
        dst = os.path.join(dst_site, os.path.relpath(src, os.path.realpath(src_site)))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
    copied.append(f"{d.metadata['Name']} {d.version}")
print(f'copied from the shared virtualenv ({sys.prefix}), pip excluded: {len(copied)} distributions')
EOF
echo "the new virtualenv's distributions: $("$FRESH/bin/python" -I -c 'from importlib import metadata; print(", ".join(sorted(d.metadata["Name"] + " " + d.version for d in metadata.distributions())))')"
echo
echo "the reviewed commit's check (check --toolchain on the reviewed tree) with this virtualenv:"
if "$FRESH/bin/python" -I "$WORK/reviewed/Scripts/check-dependency-lock.py" check --toolchain --root "$WORK/reviewed" > "$WORK/reviewed-toolchain.out" 2>&1; then
  echo "  passed (the reviewer's failure did not reproduce)"
else
  echo "  failed, as review R2-01 reported:"; grep -E '^FAIL' "$WORK/reviewed-toolchain.out" | cut -c1-220 | sed 's/^/    /'
fi
echo
echo "Scripts/ci.sh dependency-lock at HEAD with SYLVIA_TOOLS_VENV set to this virtualenv (the drop-in runs the self-test, then check --toolchain):"
start=$SECONDS
if SYLVIA_TOOLS_VENV="$FRESH" Scripts/ci.sh dependency-lock > "$WORK/ci-fresh.out" 2>&1; then
  echo "ok    passed ($((SECONDS - start)) s, load $(uptime | sed 's/.*load averages*: //'))"
else
  echo "FAIL  failed ($((SECONDS - start)) s):"; sed 's/^/        /' "$WORK/ci-fresh.out"; fails=$((fails+1))
fi
sed 's/^/    | /' "$WORK/ci-fresh.out"
grep -E '^(WARN|FAIL) |^ok    python tools:|^dependency lock check:|^self-test:' "$ROOT/.build/ci-logs/12-dependency-lock.log" | cut -c1-400 | sed 's/^/    drop-in log: /'

echo
rm -rf "$WORK"
echo "round 2 reproductions finished $(date -u +%Y-%m-%dT%H:%M:%SZ); failures: $fails"
echo "load: $(uptime)"
exit $fails
