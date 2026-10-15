#!/bin/bash
# ADR-0014 evidence: which third-party code ends up in a built binary, read from the binaries themselves.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/linkage.sh > Docs/Stage0/evidence/M0-dependencies/linkage.log 2>&1
#
# 1. The Mac source service (Spikes/G02-Transfer/SourceService, product sylvia-source, debug, host): defined-symbol
#    counts per vendored C library prefix (two BoringSSL copies, llhttp, SHA1) and per Swift module.
# 2. The EPUB harness app (Spikes/G01-EPUB, scheme EPUBHarness, Debug, generic iOS Simulator, unsigned): defined-symbol
#    counts per Swift module and C library in every Mach-O file of the .app, and the files of Readium's resource
#    bundles (fonts, scripts, styles), which ship in the app as they are.
# 3. GRDB (Spikes/G05-Recovery, product g05-recovery-tool, debug, host): GRDB's symbols, and whether SQLite is the
#    system library or a bundled copy.
# 4-6. iOS Simulator builds (Debug, generic destination, unsigned) for what the first three do not build for iOS: GRDB
#    in the G0.5 recovery package's test bundle (no M0 iOS app links GRDB), SwiftASN1 in the G0.2 transfer harness app
#    (through SylviaTransferCore), and the design catalog app (SylviaDesign with Literata; the snapshot-testing
#    packages must be absent).
# Builds use the committed locks (--force-resolved-versions, -disableAutomaticPackageResolution), except the G0.2 iOS
# harness, which has no committed lock (an inventory exemption) and whose resolved packages are printed and checked.
# Build products stay inside each project directory (.build). Run resolve-locks.sh first. Host only; no simulator is
# booted (a generic destination needs none).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
source "$ROOT/Scripts/lib/sim.sh"
source "$ROOT/Scripts/lib/xcodegen.sh"
cd "$ROOT" || exit 1
SCRATCH="$ROOT/.build/scratch/linkage"
mkdir -p "$SCRATCH"
echo "linkage started $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "load: $(uptime)"
fails=0

# count <file...>: defined symbols per marker, from nm (no symbol is printed in full). Each nm line's last field is
# the symbol name; a marker matches at the start of the name (C prefixes; Swift's "$s<length><module>" context, which
# names the module that defines the entity), and distinct names are counted.
count() {
  nm -m "$@" 2>/dev/null | grep -v ' (undefined) ' > "$SCRATCH/nm.txt"
  /usr/bin/python3 -I - "$SCRATCH/nm.txt" <<'PY'
import re, sys
names = set()
for line in open(sys.argv[1], errors="replace"):
    fields = line.split()
    if fields and not line.endswith(":\n"):
        names.add(fields[-1])
markers = [
    ("BoringSSL (swift-nio-ssl, CNIOBoringSSL_ prefix)", r"_CNIOBoringSSL_"),
    ("BoringSSL (swift-crypto, CCryptoBoringSSL_ prefix)", r"_CCryptoBoringSSL_"),
    ("llhttp (swift-nio CNIOLLHTTP, c_nio_llhttp_ prefix)", r"_c_nio_llhttp_"),
    ("SHA1 (swift-nio CNIOSHA1, c_nio_sha1 prefix)", r"_c_nio_sha1"),
    ("swift-nio CNIOAtomics functions generated with uSHET's cpp_magic.h macros (catmc_ prefix)", r"_catmc_"),
    # fiat-crypto's field arithmetic is static inline code in BoringSSL's curve25519 and P-256 files, so it has no
    # symbol of its own; these entry points of those files show whether the code that includes it is linked.
    ("BoringSSL (swift-nio-ssl) X25519, Ed25519 and P-256 entry points, whose files include fiat-crypto", r"_CNIOBoringSSL_(?:X25519|ED25519|EC_GFp_nistp256_method)"),
    ("BoringSSL (swift-crypto) X25519, Ed25519 and P-256 entry points, whose files include fiat-crypto", r"_CCryptoBoringSSL_(?:X25519|ED25519|EC_GFp_nistp256_method)"),
    ("Keccak (swift-crypto CXKCP)", r"_(?:CXKCP_|Keccak)"),
    ("Minizip (marmelroy/Zip; unz*/zip* C functions)", r"_(?:unz|zip)(?:Open|Close|GoTo|Read|Get|Write|Locate)"),
    ("Minizip write path (zipOpenNewFileInZip*)", r"_zipOpenNewFileInZip"),
    ("Swift module SylviaSourceService", r"_?\$s19SylviaSourceService"),
    ("Swift module NIOCore", r"_?\$s7NIOCore"),
    ("Swift module NIOPosix", r"_?\$s8NIOPosix"),
    ("Swift module NIOHTTP1", r"_?\$s8NIOHTTP1"),
    ("Swift module NIOSSL", r"_?\$s6NIOSSL"),
    ("Swift module NIOWebSocket", r"_?\$s12NIOWebSocket"),
    ("Swift module X509 (swift-certificates)", r"_?\$s4X509"),
    ("Swift module Crypto (swift-crypto)", r"_?\$s6Crypto"),
    ("Swift module CryptoExtras / _CryptoExtras", r"_?\$s(?:12CryptoExtras|13_CryptoExtras)"),
    ("Swift module SwiftASN1", r"_?\$s9SwiftASN1"),
    ("Swift module Atomics", r"_?\$s7Atomics"),
    ("Swift module DequeModule (swift-collections)", r"_?\$s11DequeModule"),
    ("Swift module SystemPackage (swift-system)", r"_?\$s13SystemPackage"),
    ("Swift module ReadiumShared", r"_?\$s13ReadiumShared"),
    ("Swift module ReadiumStreamer", r"_?\$s15ReadiumStreamer"),
    ("Swift module ReadiumNavigator", r"_?\$s16ReadiumNavigator"),
    ("Swift module ReadiumInternal", r"_?\$s15ReadiumInternal"),
    ("Swift module ReadiumOPDS", r"_?\$s11ReadiumOPDS"),
    ("Swift module ReadiumLCP", r"_?\$s10ReadiumLCP"),
    ("Swift module ReadiumAdapterGCDWebServer", r"_?\$s26ReadiumAdapterGCDWebServer"),
    ("Swift module ReadiumAdapterLCPSQLite", r"_?\$s23ReadiumAdapterLCPSQLite"),
    ("GCDWebServer (Objective-C classes)", r"_OBJC_CLASS_\$_GCDWebServer"),
    ("Swift module SQLite (SQLite.swift)", r"_?\$s6SQLite"),
    ("Swift module Zip (marmelroy/Zip Swift API)", r"_?\$s3Zip"),
    ("Swift module ReadiumZIPFoundation", r"_?\$s20ReadiumZIPFoundation"),
    ("Swift module ReadiumFuzi", r"_?\$s11ReadiumFuzi"),
    ("Swift module SwiftSoup", r"_?\$s9SwiftSoup"),
    ("Swift module CryptoSwift", r"_?\$s11CryptoSwift"),
    ("Swift module DifferenceKit", r"_?\$s13DifferenceKit"),
    ("Swift module G01EPUBCore (the spike's sanitizer)", r"_?\$s11G01EPUBCore"),
    ("Swift module GRDB", r"_?\$s4GRDB"),
    ("SQLite C API defined here (a bundled SQLite would define sqlite3_*)", r"_sqlite3_"),
    ("Swift module SylviaTransferCore (G0.2)", r"_?\$s18SylviaTransferCore"),
    ("Swift module SylviaDesign", r"_?\$s12SylviaDesign"),
    ("Swift module SnapshotTesting (test only)", r"_?\$s15SnapshotTesting"),
    ("Swift module CustomDump (test only)", r"_?\$s10CustomDump"),
    ("Swift module IssueReporting (test only)", r"_?\$s14IssueReporting"),
    ("Swift module SwiftSyntax (test only)", r"_?\$s11SwiftSyntax"),
]
print(f"  ({len(names)} distinct defined symbol names in all)")
for name, rx in markers:
    pattern = re.compile(rx)
    n = sum(1 for s in names if pattern.match(s))
    print(f"  {n:6d}  {name}")
PY
}

echo
echo "### 1. Mac source service: swift build --product sylvia-source (debug, host)"
SS=Spikes/G02-Transfer/SourceService
start=$SECONDS
if xcrun swift build --package-path "$SS" --product sylvia-source --force-resolved-versions > "$SCRATCH/sourceservice-build.log" 2>&1; then
  bin="$(xcrun swift build --package-path "$SS" --show-bin-path)/sylvia-source"
  echo "build: ok ($((SECONDS-start)) s); binary $(basename "$bin"), $(wc -c < "$bin" | tr -d ' ') bytes; $(file -b "$bin")"
  if git diff --quiet -- "$SS/Package.resolved"; then echo "lock: unchanged"; else echo "FAIL: lock changed"; fails=$((fails+1)); fi
  echo "defined symbols per marker (distinct names):"
  count "$bin"
  echo "dynamic libraries it loads (otool -L):"
  otool -L "$bin" | sed 1d | sed 's/^[[:space:]]*/  /'
else
  echo "FAIL: build exited non-zero ($((SECONDS-start)) s); tail:"; tail -n 20 "$SCRATCH/sourceservice-build.log"; fails=$((fails+1))
fi

echo
echo "### 2. EPUB harness: xcodebuild build, scheme EPUBHarness, Debug, generic/platform=iOS Simulator, unsigned"
EP=Spikes/G01-EPUB
if ! sylvia_generate "$EP"; then echo "FAIL: xcodegen"; fails=$((fails+1)); else
  proj="$(_sylvia_xcodeproj "$EP")"
  start=$SECONDS
  if xcodebuild build -project "$proj" -scheme EPUBHarness -configuration Debug -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath "$EP/.build/DerivedData" -clonedSourcePackagesDirPath "$EP/.build/SourcePackages" \
       -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO > "$SCRATCH/epub-build.log" 2>&1; then
    app="$EP/.build/DerivedData/Build/Products/Debug-iphonesimulator/EPUBHarness.app"
    echo "build: ok ($((SECONDS-start)) s); $app"
    machos=()
    while IFS= read -r f; do
      if file -b "$f" | grep -q 'Mach-O'; then machos+=("$f"); fi
    done < <(find "$app" -type f \( -perm -u+x -o -name '*.dylib' \) | sort)
    echo "Mach-O files in the app:"
    for f in "${machos[@]}"; do echo "  ${f#$app/} ($(wc -c < "$f" | tr -d ' ') bytes)"; done
    echo "defined symbols per marker across those files (distinct names):"
    count "${machos[@]}"
    echo "resource bundles in the app and the third-party files in them (fonts, scripts, styles, licenses):"
    find "$app" -maxdepth 1 -name '*.bundle' | sort | while read -r b; do
      echo "  ${b#$app/}: $(find "$b" -type f | wc -l | tr -d ' ') files"
      find "$b" -type f \( -iname '*.otf' -o -iname '*.ttf' -o -iname '*.woff*' -o -iname '*.js' -o -iname '*.css' -o -iname 'LICENSE*' -o -iname '*.xcprivacy' \) \
        | sed "s|^$b/|    |" | sort
    done
  else
    echo "FAIL: build exited non-zero ($((SECONDS-start)) s); tail:"; tail -n 25 "$SCRATCH/epub-build.log"; fails=$((fails+1))
  fi
fi

echo
echo "### 3. GRDB: swift build --product g05-recovery-tool (Spikes/G05-Recovery, debug, host)"
GR=Spikes/G05-Recovery
start=$SECONDS
if xcrun swift build --package-path "$GR" --product g05-recovery-tool --force-resolved-versions > "$SCRATCH/recovery-build.log" 2>&1; then
  bin="$(xcrun swift build --package-path "$GR" --show-bin-path)/g05-recovery-tool"
  echo "build: ok ($((SECONDS-start)) s); binary $(basename "$bin"), $(wc -c < "$bin" | tr -d ' ') bytes"
  if git diff --quiet -- "$GR/Package.resolved"; then echo "lock: unchanged"; else echo "FAIL: lock changed"; fails=$((fails+1)); fi
  nm -m "$bin" 2>/dev/null | grep -v ' (undefined) ' | awk '{print $NF}' | grep -c -E '^_?\$s4GRDB' | sed 's/^/  defined symbols of Swift module GRDB: /'
  nm -m "$bin" 2>/dev/null | grep -v ' (undefined) ' | awk '{print $NF}' | grep -c -E '^_sqlite3_' | sed 's/^/  defined sqlite3_* symbols (a bundled SQLite would define them): /'
  echo "SQLite library it loads (otool -L):"
  otool -L "$bin" | grep -i sqlite | sed 's/^[[:space:]]*/  /'
else
  echo "FAIL: build exited non-zero ($((SECONDS-start)) s); tail:"; tail -n 20 "$SCRATCH/recovery-build.log"; fails=$((fails+1))
fi

# ios_app <project dir> <scheme> <app name> <locked|unlocked>: build the scheme for a generic iOS Simulator (Debug,
# unsigned), then report the defined symbols per marker across the app's Mach-O files, the SQLite library it loads, and
# the fonts, licenses, scripts and styles in the app and its bundles. `locked` builds pass
# -disableAutomaticPackageResolution (the committed lock); `unlocked` is for a project with no committed lock (an
# inventory exemption), whose resolved packages are printed from the build log.
ios_app() {
  local dir="$1" scheme="$2" name="$3" mode="$4" proj start app log
  log="$SCRATCH/$(printf '%s' "$scheme" | tr -c 'A-Za-z0-9' '_')-build.log"
  IOS_LOG="$log"  # the build log, for checks after the call
  if ! sylvia_generate "$dir"; then echo "FAIL: xcodegen"; fails=$((fails+1)); return; fi
  proj="$(_sylvia_xcodeproj "$dir")"
  local extra=()
  [[ "$mode" == locked ]] && extra=(-disableAutomaticPackageResolution)
  start=$SECONDS
  if ! xcodebuild build -project "$proj" -scheme "$scheme" -configuration Debug -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath "$dir/.build/DerivedData" -clonedSourcePackagesDirPath "$dir/.build/SourcePackages" \
       ${extra[@]+"${extra[@]}"} CODE_SIGNING_ALLOWED=NO > "$log" 2>&1; then
    echo "FAIL: build exited non-zero ($((SECONDS-start)) s); tail:"; tail -n 25 "$log"; fails=$((fails+1)); return
  fi
  app="$dir/.build/DerivedData/Build/Products/Debug-iphonesimulator/$name.app"
  echo "build: ok ($((SECONDS-start)) s); $app"
  if [[ "$mode" == unlocked ]]; then
    echo "remote packages resolved for this build (from the build log; local packages omitted):"
    sed -n '/^Resolved source packages:/,/^$/p' "$log" | grep '@' | sed 's/^[[:space:]]*/  /'
  elif [[ -f "$dir/Package.resolved" ]] && ! git diff --quiet -- "$dir/Package.resolved"; then
    echo "FAIL: lock changed"; fails=$((fails+1))
  else
    echo "lock: the committed Package.resolved, unchanged"
  fi
  local machos=() f
  while IFS= read -r f; do
    if file -b "$f" | grep -q 'Mach-O'; then machos+=("$f"); fi
  done < <(find "$app" -type f \( -perm -u+x -o -name '*.dylib' \) | sort)
  echo "Mach-O files in the app:"
  for f in "${machos[@]}"; do echo "  ${f#$app/} ($(wc -c < "$f" | tr -d ' ') bytes)"; done
  echo "defined symbols per marker across those files (distinct names):"
  count "${machos[@]}"
  echo "SQLite libraries the app's Mach-O files load (otool -L):"
  otool -L "${machos[@]}" 2>/dev/null | grep -i sqlite | sed 's/^[[:space:]]*/  /' | sort -u
  echo "fonts, licenses, scripts and styles in the app and its bundles:"
  find "$app" -type f \( -iname '*.otf' -o -iname '*.ttf' -o -iname '*.woff*' -o -iname '*.js' -o -iname '*.css' -o -iname 'LICENSE*' -o -iname 'OFL*' -o -iname '*.xcprivacy' \) \
    | sed "s|^$app/|  |" | sort
}

echo
echo "### 4. GRDB built for iOS: xcodebuild build-for-testing, scheme G05Recovery-Package (Spikes/G05-Recovery), Debug, generic/platform=iOS Simulator, unsigned"
echo "No M0 iOS app links GRDB: the recovery tool (section 3) is a host build, and the G0.5 ATS probe apps link SylviaAI,"
echo "which does not use GRDB (Spikes/G05-AI/Package.swift: only SylviaContext depends on it). The M0 build that links GRDB"
echo "for iOS is the recovery package's test bundle, which 71-g05-recovery.sh also builds and runs on the simulator."
GRI=Spikes/G05-Recovery
start=$SECONDS
if (cd "$GRI" && xcodebuild build-for-testing -scheme G05Recovery-Package -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO) \
      > "$SCRATCH/recovery-ios-build.log" 2>&1; then
  products="$GRI/.build/DerivedData/Build/Products/Debug-iphonesimulator"
  echo "build: ok ($((SECONDS-start)) s); $products"
  if git diff --quiet -- "$GRI/Package.resolved"; then echo "lock: unchanged"; else echo "FAIL: lock changed"; fails=$((fails+1)); fi
  machos=()
  while IFS= read -r f; do
    if file -b "$f" | grep -q 'Mach-O'; then machos+=("$f"); fi
  done < <(find "$products/SylviaRecoveryTests.xctest" "$products/PackageFrameworks" -type f 2>/dev/null | sort)
  echo "Mach-O files in the test bundle and any package frameworks:"
  for f in "${machos[@]}"; do echo "  ${f#$products/} ($(wc -c < "$f" | tr -d ' ') bytes)"; done
  echo "defined symbols per marker across those files (distinct names):"
  count "${machos[@]}"
  echo "SQLite libraries they load (otool -L):"
  otool -L "${machos[@]}" 2>/dev/null | grep -i sqlite | sed 's/^[[:space:]]*/  /' | sort -u
else
  echo "FAIL: build exited non-zero ($((SECONDS-start)) s); tail:"; tail -n 25 "$SCRATCH/recovery-ios-build.log"; fails=$((fails+1))
fi

echo
echo "### 5. SwiftASN1 in an iOS app: scheme G02TransferHarness (Spikes/G02-Transfer/iOS: SylviaTransferCore over SwiftASN1)"
echo "This project has no committed lock (an inventory exemption: its one remote package, swift-asn1, is required exactly by"
echo "TransferKit), so this build lets Xcode resolve; what it resolved is printed below and must be swift-asn1 1.7.3 only."
ios_app Spikes/G02-Transfer/iOS G02TransferHarness G02TransferHarness unlocked
resolved="$(sed -n '/^Resolved source packages:/,/^$/p' "$IOS_LOG" | grep '@' | sed 's/^[[:space:]]*//')"
if [[ "$resolved" == "swift-asn1: https://github.com/apple/swift-asn1.git @ 1.7.3" ]]; then
  echo "resolved exactly what the inventory pins: $resolved"
else
  echo "FAIL: resolved '$resolved', not swift-asn1 1.7.3 alone"; fails=$((fails+1))
fi

echo
echo "### 6. The design catalog app: scheme DesignCatalog (Apps/DesignCatalog: SylviaDesign with Literata)"
echo "The snapshot-testing packages are in its lock for the design package's tests; none of their modules may be in the app."
ios_app Apps/DesignCatalog DesignCatalog DesignCatalog locked

echo
echo "linkage finished $(date -u +%Y-%m-%dT%H:%M:%SZ); failures: $fails"
echo "load: $(uptime)"
exit $fails
