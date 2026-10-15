#!/usr/bin/env bash
# G0.3 archive-library dependency facts (host): which ZIPFoundation readium/swift-toolkit 3.11.0 resolves to, and the
# SwiftPM resolver's full answer when upstream weichsel/ZIPFoundation 0.9.20 joins the same graph (IdentityProbe).
# ADR-0010 section 3 rests on two of these facts, so the script fails if either changes:
#   1. Readium 3.11.0 resolves readium/ZIPFoundation to the same revision IntakeKit locks;
#   2. upstream 0.9.20 cannot be resolved in the same graph as Readium 3.11.0.
# Run by Scripts/ci.d/50-g03-intake.sh.
#
#   Spikes/G03-Intake/ZipEval/dependency-probe.sh [log]     default log: Docs/Stage0/evidence/G03-Intake/zip-dependency-probe.log
set -uo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
here="$SYLVIA_ROOT/Spikes/G03-Intake/ZipEval"
log="${1:-$SYLVIA_ROOT/Docs/Stage0/evidence/G03-Intake/zip-dependency-probe.log}"
work="$SYLVIA_ROOT/.build/g03-dependency-probe"
mkdir -p "$(dirname "$log")"
exec > >(tee "$log") 2>&1

echo "# G0.3 archive dependency probe"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "environment: host, $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcrun swift --version 2>/dev/null | head -1)"

echo; echo "## 1. readium/swift-toolkit 3.11.0 alone: its ZIPFoundation requirement and what it resolves to"
rm -rf "$work"; mkdir -p "$work/Sources/Probe"
cat > "$work/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Probe", platforms: [.iOS(.v26), .macOS(.v26)],
  dependencies: [.package(url: "https://github.com/readium/swift-toolkit.git", exact: "3.11.0")],
  targets: [.target(name: "Probe", dependencies: [.product(name: "ReadiumShared", package: "swift-toolkit")])])
SWIFT
echo 'public let probe = 1' > "$work/Sources/Probe/Probe.swift"
(cd "$work" && swift package resolve >/dev/null 2>&1) || { echo "resolve failed"; exit 1; }
echo "requirement in swift-toolkit 3.11.0 Package.swift:"
grep -n 'ZIPFoundation' "$work/.build/checkouts/swift-toolkit/Package.swift" | sed 's/^/  /'
pin() {   # identity location version revision of the zipfoundation pin in a Package.resolved
  /usr/bin/python3 -c '
import json, sys
for pin in json.load(open(sys.argv[1]))["pins"]:
    if pin["identity"] == "zipfoundation":
        print("identity=%s location=%s version=%s revision=%s" % (pin["identity"], pin["location"], pin["state"].get("version"), pin["state"]["revision"]))
' "$1"
}
readium_pin="$(pin "$work/Package.resolved")"
kit_pin="$(pin "$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit/Package.resolved")"
echo "resolved pin:"; echo "  $readium_pin"
echo "IntakeKit lock:"; echo "  $kit_pin"
echo "license of the resolved fork (first line):"
sed -n 1p "$work/.build/checkouts/ZIPFoundation/LICENSE" | sed 's/^/  /'

echo; echo "## 2. Readium 3.11.0 plus upstream weichsel/ZIPFoundation 0.9.20 in one graph (full resolver output)"
resolve_out="$work/identity-resolve.txt"
(cd "$here/IdentityProbe" && rm -rf .build Package.resolved && swift package resolve) >"$resolve_out" 2>&1
resolve_status=$?
grep -v '^Fetching\|^Fetched\|^Cloning\|^Cloned\|^Creating working copy\|^Working copy\|^Computing\|^Computed' "$resolve_out" | sed 's/^/  /'
echo "  exit status of the resolve: $resolve_status"
identity_conflict=no
grep -q "Dependencies could not be resolved because root depends on 'zipfoundation' 0.9.20" "$resolve_out" && identity_conflict=yes
rm -rf "$here/IdentityProbe/.build" "$here/IdentityProbe/Package.resolved" "$work"

echo; echo "## 3. Checks (ADR-0010 section 3)"
status=0
if [[ -n "$readium_pin" && "$readium_pin" == "$kit_pin" ]]; then
  echo "ok: Readium 3.11.0 resolves the same ZIPFoundation fork revision that IntakeKit locks"
else
  echo "CHANGED: Readium 3.11.0's ZIPFoundation pin differs from IntakeKit's lock; revisit ADR-0010 section 3"; status=1
fi
if (( resolve_status != 0 )) && [[ "$identity_conflict" == yes ]]; then
  echo "ok: upstream ZIPFoundation 0.9.20 cannot join the graph (same package identity 'zipfoundation')"
else
  echo "CHANGED: the resolver no longer refuses upstream 0.9.20 beside Readium 3.11.0 as before; revisit ADR-0010 section 3"; status=1
fi
echo; echo "dependency probe finished, status=$status"
exit $status
