#!/bin/bash
# ADR-0014 evidence: resolve every committed lock exactly as committed, and leave a checkout of every pinned
# package at its pinned revision for read-licenses.py.
#
#   Docs/Stage0/evidence/M0-dependencies/commands/resolve-locks.sh > Docs/Stage0/evidence/M0-dependencies/resolve-locks.log 2>&1
#
# Xcode projects: sylvia_generate, then xcodebuild -resolvePackageDependencies -disableAutomaticPackageResolution with
# the clones under <dir>/.build/SourcePackages and DerivedData under <dir>/.build/DerivedData. Swift packages: swift
# package resolve --force-resolved-versions (clones under <dir>/.build/checkouts). A committed Package.resolved that
# changes is a failure. Network use: pinned Swift package resolution only. Host only; no simulator.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
source "$ROOT/Scripts/lib/sim.sh"
source "$ROOT/Scripts/lib/xcodegen.sh"
cd "$ROOT" || exit 1
SCRATCH="$ROOT/.build/scratch/resolve"
mkdir -p "$SCRATCH"
echo "resolve-locks started $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
echo "toolchain: $(xcodebuild -version | tr '\n' ' '); $(xcrun swift --version 2>&1 | head -1); xcodegen $(xcodegen --version)"
echo "load: $(uptime)"
fails=0

pins() { # identity location version revision, sorted
  /usr/bin/python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1]))
for p in sorted(d.get("pins",[]), key=lambda p: p["identity"]):
    s=p["state"]; print(p["identity"], p["location"], s.get("version") or s.get("branch"), s.get("revision"))
' "$1"
}
logname() { echo "$SCRATCH/$1-$(echo "$2" | tr / _).log"; }

echo
echo "### Xcode projects"
for dir in Apps/DesignCatalog Spikes/G01-EPUB Spikes/G01-PDF Spikes/G02-Transfer/MacIdentityProbe Spikes/G02-Transfer/iOS Spikes/G03-Intake/App Spikes/G05-AI/ATSProbe; do
  echo
  echo "== $dir"
  if ! sylvia_generate "$dir"; then echo "FAIL: xcodegen"; fails=$((fails+1)); continue; fi
  proj="$(_sylvia_xcodeproj "$dir")"
  installed="$proj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  log="$(logname xcode "$dir")"
  # xcodebuild accepts -derivedDataPath only together with a scheme; any shared scheme of the project will do, since
  # package resolution covers the whole project.
  scheme="$(ls "$proj/xcshareddata/xcschemes" 2>/dev/null | sed -n 's/\.xcscheme$//p' | head -1)"
  if [[ -z "$scheme" ]]; then echo "FAIL: no shared scheme in $proj"; fails=$((fails+1)); continue; fi
  start=$SECONDS
  if xcodebuild -resolvePackageDependencies -project "$proj" -scheme "$scheme" -derivedDataPath "$dir/.build/DerivedData" \
       -clonedSourcePackagesDirPath "$dir/.build/SourcePackages" -disableAutomaticPackageResolution > "$log" 2>&1; then
    echo "resolve: ok ($((SECONDS-start)) s; scheme $scheme)"
  else
    echo "FAIL: resolve exited non-zero ($((SECONDS-start)) s; scheme $scheme); tail:"; tail -n 15 "$log"; fails=$((fails+1))
    continue
  fi
  if [[ -f "$dir/Package.resolved" ]]; then
    if [[ -f "$installed" ]] && diff <(pins "$dir/Package.resolved") <(pins "$installed"); then
      echo "lock: unchanged after resolution ($(pins "$dir/Package.resolved" | wc -l | tr -d ' ') pins)"
    else
      echo "FAIL: lock changed by resolution"; fails=$((fails+1))
    fi
  elif [[ -f "$installed" ]]; then
    echo "no committed lock; Xcode wrote one with $(pins "$installed" | wc -l | tr -d ' ') pins:"; pins "$installed" | sed 's/^/  /'
  else
    n=$(grep -E '^  [A-Za-z].*@ ' "$log" | grep -vc ' @ local$')
    echo "no committed lock, and Xcode wrote none into the generated project; remote packages resolved: $n (listed below)"
  fi
  grep -E '^  [A-Za-z].*@ ' "$log" | sed 's/^/  resolved: /' | head -30
done

echo
echo "### Swift packages"
for dir in Packages/Design Spikes/G01-EPUB/Core Spikes/G02-Transfer/SourceService Spikes/G02-Transfer/TransferKit Spikes/G03-Intake/IntakeKit Spikes/G03-Intake/ZipEval/Common Spikes/G03-Intake/ZipEval/Readium Spikes/G03-Intake/ZipEval/Upstream Spikes/G05-AI Spikes/G05-Recovery; do
  echo
  echo "== $dir"
  had=0; [[ -f "$dir/Package.resolved" ]] && had=1
  log="$(logname spm "$dir")"
  start=$SECONDS
  if xcrun swift package resolve --force-resolved-versions --package-path "$dir" > "$log" 2>&1; then
    echo "resolve: ok ($((SECONDS-start)) s)"
  else
    echo "FAIL: resolve exited non-zero ($((SECONDS-start)) s)"; tail -n 15 "$log"; fails=$((fails+1))
    continue
  fi
  if (( had )); then
    if git diff --quiet -- "$dir/Package.resolved"; then
      echo "lock: unchanged ($(pins "$dir/Package.resolved" | wc -l | tr -d ' ') pins)"
    else
      echo "FAIL: lock changed"; git diff --stat -- "$dir/Package.resolved"; fails=$((fails+1))
    fi
  elif [[ -f "$dir/Package.resolved" ]]; then
    echo "FAIL: no committed lock but resolution wrote one"; fails=$((fails+1))
  else
    echo "no committed lock and none written (no remote package dependencies)"
  fi
done

echo
echo "### Spikes/G03-Intake/ZipEval/IdentityProbe (expected resolver refusal)"
log="$(logname spm Spikes/G03-Intake/ZipEval/IdentityProbe)"
if xcrun swift package resolve --package-path Spikes/G03-Intake/ZipEval/IdentityProbe > "$log" 2>&1; then
  echo "UNEXPECTED: resolved; ADR-0010 says two packages with identity 'zipfoundation' cannot share a graph"; fails=$((fails+1))
elif grep -q "could not be resolved" "$log" && grep -q "'zipfoundation'" "$log"; then
  # Only the resolver's own refusal over the shared identity counts; a network or cache failure is a failure.
  echo "refused as ADR-0010 records:"; grep -E "^error:" "$log" | head -5 | sed 's/^/  /'
else
  echo "FAIL: resolution failed for another reason:"; tail -n 10 "$log" | sed 's/^/  /'; fails=$((fails+1))
fi
rm -f Spikes/G03-Intake/ZipEval/IdentityProbe/Package.resolved

echo
echo "resolve-locks finished $(date -u +%Y-%m-%dT%H:%M:%SZ); failures: $fails"
echo "load: $(uptime)"
exit $fails
