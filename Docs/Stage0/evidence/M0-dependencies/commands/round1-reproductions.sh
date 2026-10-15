#!/bin/bash
# ADR-0014 evidence: the review round 1 reproductions (R1-01, R1-02, R1-08, R1-09) and the further routes the fix
# closes, run against copies of this repository's committed tree rather than the checker's synthetic one. Each case
# starts from a fresh copy of `git archive HEAD`, makes one change, runs that copy's Scripts/check-dependency-lock.py
# check, and passes only if the check fails with the expected category (the matching FAIL lines are printed). The
# unchanged copy, and each change under "Allowed", must pass with no failure.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/round1-reproductions.sh > Docs/Stage0/evidence/M0-dependencies/round1-reproductions.log 2>&1
#
# Host only; no network (dump-package evaluates manifests locally), no build, no simulator. Copies are APFS clones
# (cp -c) under a new directory in .build/scratch; each is deleted after its case.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
WORK="$ROOT/.build/scratch/round1-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$WORK/base"
PY="$SYLVIA_TOOLS_VENV/bin/python"
echo "round 1 reproductions $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "load: $(uptime)"
git archive HEAD | tar -x -C "$WORK/base" -f -
fails=0

check() { # copy -> the check's output in <copy>.out; returns the check's status
  "$PY" -I "$1/Scripts/check-dependency-lock.py" check --root "$1" > "$1.out" 2>&1
}
n=0
fresh() { # sets $copy to a new copy of the base tree
  n=$((n + 1))
  copy="$WORK/c$n"
  cp -cR "$WORK/base" "$copy" 2>/dev/null || { rm -rf "$copy"; cp -R "$WORK/base" "$copy"; }
}
case_() { # name, expected category, mutation (a shell function run inside the copy)
  local name="$1" category="$2" mutate="$3" hits
  fresh
  ( cd "$copy" && "$mutate" )
  check "$copy"
  hits="$(grep -E "^FAIL $category " "$copy.out" || true)"
  if [[ -n "$hits" ]]; then
    echo "ok    $name -> $(echo "$hits" | wc -l | tr -d ' ') x $category"
    echo "$hits" | cut -c1-240 | sed 's/^/        /'
  else
    echo "FAIL  $name: expected $category; the check printed:"; sed 's/^/        /' "$copy.out"; fails=$((fails+1))
  fi
  rm -rf "$copy" "$copy.out"
}
allowed() { # name, change (a shell function run inside the copy): the check must report no failure
  local name="$1" change="$2"
  fresh
  ( cd "$copy" && "$change" )
  if check "$copy"; then
    echo "ok    $name -> $(tail -1 "$copy.out")"
  else
    echo "FAIL  $name: expected no failure; the check printed:"; grep '^FAIL' "$copy.out" | sed 's/^/        /'; fails=$((fails+1))
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
CATALOG=Apps/DesignCatalog/project.yml
CATALOG_SOURCES="'    sources:\n      - path: Sources\n'"
CATALOG_SETTING="'        PRODUCT_BUNDLE_IDENTIFIER: com.jevidon.sylvia.designcatalog\n'"

echo
echo "### The unchanged tree"
if check "$WORK/base"; then echo "ok    the committed tree passes: $(tail -1 "$WORK/base.out")"; else echo "FAIL  the committed tree fails:"; cat "$WORK/base.out"; fails=$((fails+1)); fi

echo
echo "### R1-01: imports of Zip and Minizip in product code"
probe_swift() { printf '%s\n' "$1" > Packages/Design/Sources/SylviaDesign/ZipProbe.swift; }
r01a() { probe_swift $'internal import Zip\ninternal import Minizip'; }
r01b() { probe_swift 'import Zip'; }
r01c() { probe_swift $'public import Zip\npackage import Minizip'; }
r01d() { probe_swift 'import Foundation; import Zip'; }
r01e() { probe_swift $'@preconcurrency\nfileprivate import\n    Minizip'; }
r01f() { printf '@import Minizip;\n' > Packages/Design/Sources/SylviaDesign/ZipProbe.m; }
r01g() { printf '#include <unzip.h>\n#import <Minizip/zip.h>\n' > Packages/Design/Sources/SylviaDesign/zipprobe.c; }
r01h() { edit "$CATALOG" "$CATALOG_SETTING" "$CATALOG_SETTING + '        OTHER_SWIFT_FLAGS: \"\$(inherited) -module-alias Archive=Zip\"\n'"; }
r01i() { mkdir -p Packages/Design/Sources/SylviaDesign/include
  printf 'module ArchiveC {\n    header "unzip.h"\n    export *\n}\n' > Packages/Design/Sources/SylviaDesign/include/module.modulemap; }
r01j() { mkdir -p Shared/Code; printf 'internal import Zip\n' > Shared/Code/ZipProbe.swift
  edit "$CATALOG" "$CATALOG_SOURCES" "$CATALOG_SOURCES + '      - path: ../../Shared/Code\n'"; }
case_ "internal import Zip and internal import Minizip (the reviewer's case)" transitive-direct r01a
case_ "import Zip (the reviewer's control)" transitive-direct r01b
case_ "public import Zip, package import Minizip" transitive-direct r01c
case_ "import Foundation; import Zip on one line" transitive-direct r01d
case_ "an attribute line, then fileprivate import with a line break before Minizip" transitive-direct r01e
case_ "@import Minizip; in an Objective-C file" transitive-direct r01f
case_ "#include <unzip.h> and #import <Minizip/zip.h> in a C file" transitive-direct r01g
case_ "the DesignCatalog target aliases Zip with -module-alias Archive=Zip" transitive-direct r01h
case_ "a module map under Packages/Design wraps Minizip's unzip.h" transitive-direct r01i
case_ "the import moved to shared code outside Apps/ and Packages/ that DesignCatalog compiles" outside-product r01j

echo
echo "### R1-02: Spikes code (or any code outside Apps/ and Packages/) reached from a product target"
r02a() { edit "$CATALOG" "$CATALOG_SOURCES" "$CATALOG_SOURCES + '      - path: ../../Spikes/G01-EPUB/Core/Sources/G01EPUBCore\n'"; }
r02b() { ln -s ../Spikes/G01-EPUB/Core Packages/Linked
  edit "$CATALOG" "'packages:\n'" "'packages:\n  Linked:\n    path: ../../Packages/Linked\n'"; }
r02c() { ln -s ../../../../Spikes/G01-EPUB/Core/Sources/G01EPUBCore/MarkupCanonicalizer.swift Packages/Design/Sources/SylviaDesign/Linked.swift; }
r02f() { ln -s ../../../../../Elsewhere/Code.swift Packages/Design/Sources/SylviaDesign/Linked.swift; }
r02d() { mkdir -p Apps/DesignCatalog/Config
  printf 'HEADER_SEARCH_PATHS = $(inherited) $(SRCROOT)/../../Spikes/G01-EPUB/Core/Sources\n' > Apps/DesignCatalog/Config/Catalog.xcconfig
  edit "$CATALOG" "'targets:\n'" "'configFiles:\n  Debug: Config/Catalog.xcconfig\ntargets:\n'"; }
r02e() { mkdir -p Shared/Code; printf 'struct Shared {}\n' > Shared/Code/Shared.swift
  edit "$CATALOG" "$CATALOG_SOURCES" "$CATALOG_SOURCES + '      - path: ../../Shared/Code\n'"; }
case_ "the DesignCatalog target's sources include Spikes/G01-EPUB/Core sources (the reviewer's case)" spike-in-product r02a
case_ "a symbolic link Packages/Linked -> ../Spikes/G01-EPUB/Core used as a local package" spike-in-product r02b
case_ "a symbolic link to a Spikes source file inside SylviaDesign's sources" spike-in-product r02c
case_ "a symbolic link inside SylviaDesign's sources that leaves the repository" outside-product r02f
case_ "an xcconfig the DesignCatalog project uses searches Spikes/ for headers" spike-in-product r02d
case_ "the DesignCatalog target compiles shared code outside Apps/ and Packages/" outside-product r02e

echo
echo "### R1-08: a lock that no longer covers its manifest"
r08a() { edit Spikes/G05-AI/Package.swift "'.package(url: \"https://github.com/groue/GRDB.swift.git\", exact: \"7.11.1\"),'" \
    "'.package(url: \"https://github.com/groue/GRDB.swift.git\", exact: \"7.11.1\"),\n        .package(url: \"https://github.com/scinfu/SwiftSoup.git\", exact: \"2.13.9\"),'"
  /usr/bin/python3 -I -c '
import json
i = "Docs/Licenses/inventory.json"
d = json.load(open(i))
next(x for x in d["packages"] if x["name"] == "scinfu/SwiftSoup")["direct_in"].append("Spikes/G05-AI/Package.swift")
json.dump(d, open(i, "w"), indent=2)
'; }
r08b() { /usr/bin/python3 -I -c '
import json
l = "Spikes/G05-Recovery/Package.resolved"
d = json.load(open(l))
d["pins"] = [x for x in d["pins"] if x["identity"] != "grdb.swift"]
json.dump(d, open(l, "w"), indent=2)
i = "Docs/Licenses/inventory.json"
d = json.load(open(i))
next(x for x in d["packages"] if x["name"] == "groue/GRDB.swift")["locks"].remove(l)
json.dump(d, open(i, "w"), indent=2)
'; }
case_ "G05-AI's manifest gains an exact, inventoried requirement (SwiftSoup) but its lock is not re-resolved" pin-missing r08a
case_ "G05-Recovery's lock and the inventory both drop GRDB, which its manifest requires" pin-missing r08b

echo
echo "### R1-09: third-party binaries in product targets"
r09a() { edit Packages/Design/Package.swift "'        .testTarget(\n            name: \"SylviaDesignTokensTests\",'" \
    "'        .binaryTarget(name: \"Vendor\", url: \"https://example.com/vendor.xcframework.zip\", checksum: \"' + '1' * 64 + '\"),\n        .testTarget(\n            name: \"SylviaDesignTokensTests\",'"; }
r09b() { mkdir -p Apps/DesignCatalog/Vendor/Foo.xcframework/ios-arm64/Foo.framework
  printf '\xcf\xfa\xed\xfe\x0c\x00\x00\x01' > Apps/DesignCatalog/Vendor/Foo.xcframework/ios-arm64/Foo.framework/Foo
  edit "$CATALOG" "'        product: SylviaDesignGallery\n'" "'        product: SylviaDesignGallery\n      - framework: Vendor/Foo.xcframework\n'"; }
r09c() { edit Packages/Design/Package.swift "'                .process(\"Resources/Vocabulary.xcstrings\"),\n            ]\n        ),'" \
    "'                .process(\"Resources/Vocabulary.xcstrings\"),\n            ],\n            linkerSettings: [.linkedLibrary(\"vendorfoo\")]\n        ),'"; }
r09d() { edit "$CATALOG" "$CATALOG_SETTING" "$CATALOG_SETTING + '        OTHER_LDFLAGS: \"\$(inherited) -L/opt/homebrew/lib -lfoo\"\n'"; }
case_ "Packages/Design declares a remote binary target" binary r09a
case_ "the DesignCatalog target links a committed xcframework" binary r09b
case_ "SylviaDesign links a library no SDK provides (.linkedLibrary)" binary r09c
case_ "the DesignCatalog target searches /opt/homebrew/lib and links -lfoo" binary r09d

echo
echo "### Allowed: changes the rules must not report"
a1() { printf 'internal import Zip\n' > Packages/Design/Tests/SylviaDesignTests/ZipProbeTests.swift; }
a2() { edit "$CATALOG" "$CATALOG_SETTING" "$CATALOG_SETTING + '        OTHER_LDFLAGS: \"\$(inherited) -lsqlite3 -framework CoreText\"\n        HEADER_SEARCH_PATHS: \"\$(SRCROOT)/Sources \$(BUILT_PRODUCTS_DIR)/include\"\n'"; }
allowed "a test of the design package imports Zip (tests never ship)" a1
allowed "the DesignCatalog target links SDK libraries and searches its own and build-product directories" a2

echo
rm -rf "$WORK"
echo "round 1 reproductions finished $(date -u +%Y-%m-%dT%H:%M:%SZ); failures: $fails"
echo "load: $(uptime)"
exit $fails
