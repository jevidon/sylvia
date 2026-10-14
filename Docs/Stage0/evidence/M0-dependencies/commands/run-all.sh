#!/bin/bash
# ADR-0014 evidence: regenerate every log in Docs/Stage0/evidence/M0-dependencies from the current tree, in order, and
# confirm that each text under Docs/Licenses/texts equals what the commands copy, extract or fetch today.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/run-all.sh > Docs/Stage0/evidence/M0-dependencies/run-all.log 2>&1
#
# Network: pinned Swift package resolution (resolve-locks.sh and the G0.2 iOS harness build in linkage.sh), public
# HTTPS GETs of license files, package metadata and upstream source files (fetch-external-licenses.sh,
# fetch-npm-licenses.py, readium-css-provenance.py, and vendored-advisories.py for attaswift/BigInt's releases), and
# queries of public advisory sources with public package names, versions, commits and project names (advisories-search.py
# and vendored-advisories.py: OSV, the GitHub Advisory Database and its keyword search, repository security advisories,
# and NVD's keyword search); nothing from this repository's code, documents or fixtures is sent. GitHub API requests use
# the gh CLI's token when it has one (never printed). round1-, round2- and round3-reproductions.sh read the committed
# tree (`git archive HEAD`), so commit before running. Host only; no simulator is booted. Downloads go to new
# directories under .build/scratch and are read as data.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
source "$ROOT/Scripts/lib/sim.sh"
source "$ROOT/Scripts/lib/xcodegen.sh"
cd "$ROOT" || exit 1
EV=Docs/Stage0/evidence/M0-dependencies
CMD=$EV/commands
RUN="$ROOT/.build/scratch/run-all-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
E=Spikes/G01-EPUB/.build/SourcePackages/checkouts
C=Spikes/G02-Transfer/SourceService/.build/checkouts
PY="$SYLVIA_TOOLS_VENV/bin/python"
fails=0
step() { # name, log, command...
  local name="$1" log="$2"; shift 2
  local start=$SECONDS
  if "$@" > "$log" 2>&1; then echo "ok    $name ($((SECONDS - start)) s) -> $log"; else echo "FAIL  $name ($((SECONDS - start)) s) -> $log"; fails=$((fails + 1)); fi
}
echo "run-all started $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD)"
echo "load: $(uptime)"

step toolchain $EV/toolchain.log bash $CMD/toolchain.sh
step resolve-locks $EV/resolve-locks.log bash $CMD/resolve-locks.sh
step transitive-modules $EV/transitive-modules.log /usr/bin/python3 -I $CMD/transitive-modules.py
step read-licenses $EV/read-licenses.log /usr/bin/python3 -I $CMD/read-licenses.py --copy "$RUN/license-texts"
# Every C-family target of every package with a product role (review R2-03: not a hand-picked list), then every source
# tree of the packages that ship, for origin notes; an origin note in a file the command has not reviewed fails it.
G=Spikes/G05-AI/.build/checkouts
step vendored-headers $EV/vendored-headers.log /usr/bin/python3 -I $CMD/vendored-headers.py \
  $E/swift-toolkit $E/ZIPFoundation $E/Fuzi $E/SwiftSoup $E/CryptoSwift $E/DifferenceKit $E/Zip $E/GCDWebServer \
  $E/SQLite.swift $G/GRDB.swift $C/swift-nio $C/swift-nio-ssl $C/swift-certificates $C/swift-crypto $C/swift-asn1 \
  $C/swift-atomics $C/swift-collections $C/swift-system \
  --dir $E/swift-toolkit/Sources --dir $E/ZIPFoundation/Sources --dir $E/Fuzi/Sources --dir $E/SwiftSoup/Sources \
  --dir $E/CryptoSwift/Sources --dir $E/DifferenceKit/Sources --dir $E/Zip/Zip --dir $G/GRDB.swift/GRDB \
  --dir $C/swift-nio/Sources --dir $C/swift-nio-ssl/Sources/NIOSSL --dir $C/swift-certificates/Sources \
  --dir $C/swift-crypto/Sources/Crypto --dir $C/swift-crypto/Sources/_CryptoExtras \
  --dir $C/swift-crypto/Sources/CryptoBoringWrapper --dir $C/swift-asn1/Sources --dir $C/swift-atomics/Sources \
  --dir $C/swift-collections/Sources
step copyright-lines $EV/copyright-lines.log /usr/bin/python3 -I $CMD/copyright-lines.py \
  $E/swift-toolkit/Sources $E/CryptoSwift/Sources $E/SwiftSoup/Sources $E/Fuzi/Sources $E/DifferenceKit/Sources \
  $E/ZIPFoundation/Sources $E/Zip/Zip Spikes/G05-AI/.build/checkouts/GRDB.swift/GRDB \
  Spikes/G02-Transfer/TransferKit/.build/checkouts/swift-asn1/Sources \
  $C/swift-nio/Sources $C/swift-nio-ssl/Sources/NIOSSL $C/swift-nio-ssl/Sources/CNIOBoringSSLShims $C/swift-certificates/Sources \
  $C/swift-crypto/Sources/Crypto $C/swift-crypto/Sources/CryptoExtras $C/swift-crypto/Sources/_CryptoExtras \
  $C/swift-crypto/Sources/CryptoBoringWrapper $C/swift-atomics/Sources $C/swift-collections/Sources/DequeModule \
  $C/swift-collections/Sources/InternalCollectionsUtilities
step font-names $EV/font-names.log /usr/bin/python3 -I $CMD/font-names.py \
  $E/swift-toolkit/Sources/Navigator/EPUB/Assets $E/swift-toolkit/Sources/Streamer/Assets Packages/Design/Sources/SylviaDesign/Resources/Fonts
step readium-js-closure $EV/readium-js-closure.log "$PY" -I $CMD/readium-js-closure.py $E/swift-toolkit
step privacy-manifests $EV/privacy-manifests.log /usr/bin/python3 -I $CMD/privacy-manifests.py \
  $E $C Spikes/G05-AI/.build/checkouts Packages/Design/.build/checkouts Spikes/G03-Intake/ZipEval/Upstream/.build/checkouts
step extract-notices $EV/extract-notices.log /usr/bin/python3 -I $CMD/extract-notices.py --check
step fetch-external-licenses $EV/fetch-external-licenses.log bash $CMD/fetch-external-licenses.sh "$RUN/external" $E/swift-toolkit
step fetch-npm-licenses $EV/fetch-npm-licenses.log /usr/bin/python3 -I $CMD/fetch-npm-licenses.py \
  "$RUN/external/npm-closure.txt" "$RUN/npm" "$RUN/npm-licenses.txt"
step advisories-search $EV/advisories-search.log /usr/bin/python3 -I $CMD/advisories-search.py \
  "$RUN/external/npm-closure.txt" "$RUN/advisories"
step vendored-advisories $EV/vendored-advisories.log /usr/bin/python3 -I $CMD/vendored-advisories.py \
  $C/swift-nio $C/swift-nio-ssl $C/swift-crypto $E/CryptoSwift "$RUN/vendored-advisories"
step readium-css-provenance $EV/readium-css-provenance.log /usr/bin/python3 -I $CMD/readium-css-provenance.py \
  $E/swift-toolkit "$RUN/readium-css"
step xcode-settings $EV/xcode-settings.log "$PY" -I $CMD/xcode-settings.py
step linkage $EV/linkage.log bash $CMD/linkage.sh
step xcodegen-requirements $EV/xcodegen-requirements.log bash $CMD/xcodegen-requirements.sh
step fixtures-crosscheck $EV/fixtures-crosscheck.log /usr/bin/python3 -I $CMD/fixtures-crosscheck.py
step round1-reproductions $EV/round1-reproductions.log bash $CMD/round1-reproductions.sh
step round2-reproductions $EV/round2-reproductions.log bash $CMD/round2-reproductions.sh
step round3-reproductions $EV/round3-reproductions.log bash $CMD/round3-reproductions.sh

echo
echo "texts under Docs/Licenses/texts compared with what the commands produced in this run:"
/usr/bin/python3 -I - "$RUN" <<'PY' || fails=$((fails + 1))
import filecmp, os, sys
run = sys.argv[1]
texts = 'Docs/Licenses/texts'
fetched = {  # committed copy -> file this run fetched or wrote
    'apple__swift-nio-ssl/external__boringssl-817ab07ebb53da35afea409ab9328f578492832d__LICENSE': 'external/boringssl-817ab07ebb53da35afea409ab9328f578492832d-LICENSE',
    'apple__swift-crypto/external__boringssl-0226f30467f540a3f62ef48d453f93927da199b6__LICENSE': 'external/boringssl-0226f30467f540a3f62ef48d453f93927da199b6-LICENSE',
    'apple__swift-crypto/external__boringssl-0226f30467f540a3f62ef48d453f93927da199b6__third_party__fiat__LICENSE': 'external/boringssl-0226f30467f540a3f62ef48d453f93927da199b6-third_party-fiat-LICENSE',
    'marmelroy__zip/external__zlib-v1.3.1__LICENSE': 'external/zlib-v1.3.1-LICENSE',
    'marmelroy__zip/external__infozip-license-2009-Jan-02.txt': 'external/infozip-license.txt',
    'readium__swift-toolkit/external__hypothesis-client-v1.1763.0__LICENSE': 'external/hypothesis-client-v1.1763.0-LICENSE',
    'krzyzanowskim__cryptoswift/external__attaswift-BigInt-v5.3.0__LICENSE.md': 'external/attaswift-BigInt-v5.3.0-LICENSE.md',
    'apple__swift-nio/external__uSHET-c09e0acafd86720efe42dc15c63e0cc228244c32__LICENSE': 'external/uSHET-c09e0acafd86720efe42dc15c63e0cc228244c32-LICENSE',
    'readium__swift-toolkit/external__navigator-scripts-npm-licenses.txt': 'npm-licenses.txt',
    'readium__swift-toolkit/external__readium-css-1ba225fecf1e63e6cccc93e1f4a50107e56f93e5__LICENSE': 'readium-css/LICENSE-1ba225fecf1e63e6cccc93e1f4a50107e56f93e5',
}
copied = os.path.join(run, 'license-texts')
bad = n = 0
for dp, _, fns in os.walk(texts):
    for fn in sorted(fns):
        rel = os.path.relpath(os.path.join(dp, fn), texts)
        n += 1
        if rel in fetched:
            src, how = os.path.join(run, fetched[rel]), 'fetched'
        elif rel.endswith('__notice') or rel.endswith('__header-comment'):
            print(f'  {rel}: extracted from a source file (extract-notices.log compares it)')
            continue
        else:
            src, how = os.path.join(copied, rel), 'copied from the pinned checkout'
        same = os.path.exists(src) and filecmp.cmp(src, os.path.join(texts, rel), shallow=False)
        print(f'  {"identical" if same else "DIFFERENT OR MISSING"}: {rel} ({how})')
        bad += 0 if same else 1
extra = []
for dp, _, fns in os.walk(copied):
    for fn in fns:
        rel = os.path.relpath(os.path.join(dp, fn), copied)
        if not os.path.exists(os.path.join(texts, rel)):
            extra.append(rel)
for rel in sorted(extra):
    print(f'  NOT COMMITTED: {rel} (read-licenses.py copied it)')
print(f'  {n} committed texts; {bad} differ; {len(extra)} copied but not committed')
sys.exit(1 if bad or extra else 0)
PY

echo
echo "run-all finished $(date -u +%Y-%m-%dT%H:%M:%SZ); failures: $fails"
echo "load: $(uptime)"
exit $fails
