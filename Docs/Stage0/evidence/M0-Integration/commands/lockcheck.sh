#!/bin/bash
# M0 integration fast check: every merged project and package resolves from its committed Package.resolved.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
source "$ROOT/Scripts/lib/sim.sh"
source "$ROOT/Scripts/lib/xcodegen.sh"
cd "$ROOT" || exit 1
echo "lock check started $(date -u +%Y-%m-%dT%H:%M:%SZ) at $(git rev-parse HEAD)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' '); xcodegen $(xcodegen --version)"
echo "load: $(uptime)"
fails=0

pins() { # identity version revision, sorted
  /usr/bin/python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1]))
for p in sorted(d.get("pins",[]), key=lambda p: p["identity"]):
    s=p["state"]; print(p["identity"], p["location"], s.get("version") or s.get("branch"), s.get("revision"))
' "$1"
}

echo
echo "### Xcode projects (sylvia_generate, then xcodebuild -resolvePackageDependencies -disableAutomaticPackageResolution -clonedSourcePackagesDirPath <dir>/.build/SourcePackages)"
for dir in Apps/DesignCatalog Spikes/G01-EPUB Spikes/G01-PDF Spikes/G02-Transfer/MacIdentityProbe Spikes/G02-Transfer/iOS Spikes/G03-Intake/App Spikes/G05-AI/ATSProbe; do
  echo
  echo "== $dir"
  if ! sylvia_generate "$dir"; then echo "FAIL: xcodegen"; fails=$((fails+1)); continue; fi
  proj="$(_sylvia_xcodeproj "$dir")"
  installed="$proj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  start=$SECONDS
  if xcodebuild -resolvePackageDependencies -project "$proj" -clonedSourcePackagesDirPath "$dir/.build/SourcePackages" \
       -disableAutomaticPackageResolution > "$ROOT/.build/scratch/resolve-$(echo "$dir" | tr / _).log" 2>&1; then
    echo "resolve: ok ($((SECONDS-start)) s)"
  else
    echo "FAIL: resolve exited non-zero ($((SECONDS-start)) s); tail:"; tail -n 15 "$ROOT/.build/scratch/resolve-$(echo "$dir" | tr / _).log"
    fails=$((fails+1))
  fi
  if [[ -f "$dir/Package.resolved" ]]; then
    if [[ -f "$installed" ]] && diff <(pins "$dir/Package.resolved") <(pins "$installed"); then
      echo "lock: unchanged after resolution ($(pins "$dir/Package.resolved" | wc -l | tr -d ' ') pins)"
    else
      echo "FAIL: lock changed by resolution"; fails=$((fails+1))
    fi
  else
    if [[ -f "$installed" ]]; then
      echo "no committed lock; Xcode wrote one with $(pins "$installed" | wc -l | tr -d ' ') pins:"; pins "$installed"
    else
      n=$(grep -c " @ [0-9]" "$ROOT/.build/scratch/resolve-$(echo "$dir" | tr / _).log"); echo "no committed lock, and Xcode wrote none; remote packages resolved: $n (versions below)"
    fi
  fi
  grep -E 'Resolved source packages|^  [A-Za-z].*@' "$ROOT/.build/scratch/resolve-$(echo "$dir" | tr / _).log" | head -30
done

echo
echo "### Swift packages (swift package resolve --force-resolved-versions)"
for dir in Packages/Design Spikes/G01-EPUB/Core Spikes/G02-Transfer/SourceService Spikes/G02-Transfer/TransferKit Spikes/G03-Intake/IntakeKit Spikes/G03-Intake/ZipEval/Common Spikes/G03-Intake/ZipEval/Readium Spikes/G03-Intake/ZipEval/Upstream Spikes/G05-AI Spikes/G05-Recovery; do
  echo
  echo "== $dir"
  had=0; [[ -f "$dir/Package.resolved" ]] && had=1
  start=$SECONDS
  if xcrun swift package resolve --force-resolved-versions --package-path "$dir" > "$ROOT/.build/scratch/spm-$(echo "$dir" | tr / _).log" 2>&1; then
    echo "resolve: ok ($((SECONDS-start)) s)"
  else
    echo "FAIL: resolve exited non-zero ($((SECONDS-start)) s)"; tail -n 15 "$ROOT/.build/scratch/spm-$(echo "$dir" | tr / _).log"; fails=$((fails+1))
  fi
  if (( had )); then
    if git diff --quiet -- "$dir/Package.resolved"; then
      echo "lock: unchanged ($(pins "$dir/Package.resolved" | wc -l | tr -d ' ') pins)"
    else
      echo "FAIL: lock changed"; git diff --stat -- "$dir/Package.resolved"; fails=$((fails+1))
    fi
  else
    if [[ -f "$dir/Package.resolved" ]]; then echo "FAIL: no committed lock but resolution wrote one"; fails=$((fails+1)); else echo "no committed lock and none written (no remote package dependencies)"; fi
  fi
done
echo
echo "Spikes/G03-Intake/ZipEval/IdentityProbe: not resolved here; it is G0.3's probe that two packages named ZIPFoundation cannot share one graph (expected resolver failure, recorded by ZipEval/dependency-probe.sh)."
echo
echo "lock check finished $(date -u +%Y-%m-%dT%H:%M:%SZ); failures: $fails"
echo "load: $(uptime)"
exit $fails
