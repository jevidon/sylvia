#!/usr/bin/env bash
# G0.2: the Mac identity key in the data protection keychain, from a signed app (ADR-0008; gate gap from the
# round 1 review). Builds Spikes/G02-Transfer/MacIdentityProbe with automatic signing (team A4KBDX665Z) and runs
# its hosted test, which uses KeychainIdentityStore with its default policy (data protection keychain only).
#
#   Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh LOG
#
# Needs a development certificate and an Xcode account for the team on this Mac (-allowProvisioningUpdates
# may register the Mac and create a development profile). Exit 0: passed; 1: failed; 2: not run because code
# signing for the team is unavailable on this Mac (LOG says why). That result is recorded, never replaced by the
# unsigned store. Environment: host (macOS).
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
source "$SYLVIA_ROOT/Scripts/lib/xcodegen.sh"

log="$1"
dir="$SYLVIA_ROOT/Spikes/G02-Transfer/MacIdentityProbe"
work="$SYLVIA_ROOT/.build/scratch/g02-identity-probe"
rm -rf "$work"
mkdir -p "$work" "$(dirname "$log")"
sylvia_generate "$dir"
: > "$log"
note() { printf '%s\n' "$*" >> "$log"; }
note "environment: host macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | tr '\n' ' ')"
note "script> xcodebuild test -scheme G02MacIdentityProbe -destination platform=macOS -allowProvisioningUpdates (automatic signing, team $SYLVIA_TEAM_ID)"
status=0
(cd "$dir" && xcodebuild test -project G02MacIdentityProbe.xcodeproj -scheme G02MacIdentityProbe -destination platform=macOS \
  -derivedDataPath "$dir/.build/DerivedData" -disableAutomaticPackageResolution -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$SYLVIA_TEAM_ID" > "$work/xcodebuild.log" 2>&1) || status=$?
app="$dir/.build/DerivedData/Build/Products/Debug/G02MacIdentityProbe.app"
if [[ -d "$app" ]]; then
  note "--- code signature of the host app (codesign -d)"
  codesign -d --verbose=2 "$app" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Signature)' >> "$log" || true
  note "--- entitlements of the host app"
  codesign -d --entitlements - --xml "$app" 2>/dev/null | /usr/bin/plutil -p - >> "$log" 2>&1 || true
fi
note "--- test output (xcodebuild exit $status)"
grep -E 'G02-PROBE|✔|✘|recorded an issue|error:|\*\* TEST|Signing|requires a provisioning profile|No Account|No profiles' "$work/xcodebuild.log" \
  | grep -v '^\[' | sort -u | sed "s#$SYLVIA_ROOT/##g" >> "$log" || true
if (( status != 0 )) || ! grep -q 'G02-PROBE backend: data-protection keychain' "$log"; then
  # Signing needs the team's account in a usable state; say so plainly when that is what stopped the run.
  if grep -qE 'Program License Agreement|No Account for Team|No profiles for' "$work/xcodebuild.log"; then
    note "BLOCKED: code signing for team $SYLVIA_TEAM_ID is not available on this Mac (see the error lines above);"
    note "  the account holder must resolve it (for example accept the Program License Agreement), then rerun this script."
    note "RESULT: NOT RUN (signing unavailable; full log: ${work#"$SYLVIA_ROOT"/}/xcodebuild.log)"
    exit 2
  fi
  note "RESULT: FAIL (full log: ${work#"$SYLVIA_ROOT"/}/xcodebuild.log)"
  exit 1
fi
note "RESULT: PASS"
