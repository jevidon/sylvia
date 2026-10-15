#!/usr/bin/env bash
# M0 device runbook: records, read-only, what the build Mac has for signing device builds and which device-run
# fixtures are in the fixture cache. Prints no certificate hash, device identifier or account name.
# Environment: host (macOS).
#
#   Docs/Stage0/evidence/M0-runbook/commands/build-mac-state.sh > Docs/Stage0/evidence/M0-runbook/build-mac-state.txt
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$ROOT"
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh

echo "# build Mac state for the M0 device runbook"
echo "# recorded $(date -u +%Y-%m-%dT%H:%M:%SZ) on host macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | tr '\n' ' ')"
echo "# commit: $(git -C "$ROOT" rev-parse HEAD)"

echo
echo "## code-signing identities (security find-identity -v -p codesigning; hashes removed)"
security find-identity -v -p codesigning 2>&1 | sed -E 's/[0-9A-F]{40}/<sha1>/'

echo
echo "## provisioning profiles Xcode keeps (~/Library/Developer/Xcode/UserData/Provisioning Profiles)"
DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
# Decoded profiles are temporary files: they go under .build/scratch/ in this checkout (gitignored), never in a
# shared temporary directory, and are removed on exit.
mkdir -p "$ROOT/.build/scratch"
TMP="$(mktemp -d "$ROOT/.build/scratch/profiles.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
count=0
other=0
for f in "$DIR"/*; do
  [[ -f "$f" ]] || continue
  count=$((count + 1))
  P="$TMP/p.plist"
  if ! security cms -D -i "$f" > "$P" 2>/dev/null; then echo "- unreadable profile"; continue; fi
  appid="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$P" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$P" 2>/dev/null)"
  # Only profiles that can sign a Sylvia bundle ID (com.jevidon.sylvia*) are described; others are counted.
  case "$appid" in
    "$SYLVIA_TEAM_ID.*"|"$SYLVIA_TEAM_ID.com.jevidon.sylvia"*) ;;
    *) other=$((other + 1)); continue ;;
  esac
  name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$P")"
  platform="$(/usr/libexec/PlistBuddy -c 'Print :Platform:0' "$P" 2>/dev/null)"
  expires="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$P")"
  ndev="$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$P" 2>/dev/null | grep -c '^    ')"
  keys="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements' "$P" | grep -E '^    [A-Za-z]' | sed -E 's/^ +//; s/ = .*//' | tr '\n' ' ')"
  echo "- $name | platform $platform | app ID $appid | expires $expires | registered devices: $ndev"
  echo "  entitlement keys: $keys"
done
echo "profiles: $count in all; $other of them for other apps' bundle IDs (not described)"

echo
echo "## developer accounts in Xcode (defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists; names masked)"
accounts="$(defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null || true)"
if [[ -z "$accounts" ]]; then
  echo "not set"
else
  printf '%s\n' "$accounts" | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/<apple-account>/g'
  echo "entries naming an account: $(printf '%s\n' "$accounts" | grep -c '@' || true)"
fi

echo
echo "## System Information: does this Mac report a Provisioning UDID (the identifier a Mac is registered with for development; runbook 0.7)? The value is not printed"
if system_profiler SPHardwareDataType 2>/dev/null | grep -q 'Provisioning UDID:'; then
  echo "Provisioning UDID field: present"
else
  echo "Provisioning UDID field: absent"
fi

echo
echo "## device-run fixtures in \$SYLVIA_FIXTURE_CACHE ($SYLVIA_FIXTURE_CACHE)"
for p in downloads/MeditationsMarcusAurelius_librivox.m4b \
         downloads/meditationsofmarcusaurelius_01_aurelius_64kb.mp3 \
         downloads/meditationsofmarcusaurelius_02_aurelius_64kb.mp3 \
         generated/g01-pdf/large-1000.pdf \
         generated/g02-transfer/large-5GiB.bin \
         generated/g03-intake/large.sylviapack \
         generated/g03-intake/work/part-01.caf \
         "generated/g04-audio/multi/Part 1.mp3" "generated/g04-audio/multi/Part 2.mp3" \
         "generated/g04-audio/multi/Part 3.mp3" "generated/g04-audio/multi/Part 10.mp3"; do
  if [[ -f "$SYLVIA_FIXTURE_CACHE/$p" ]]; then
    echo "- $p: $(stat -f %z "$SYLVIA_FIXTURE_CACHE/$p") bytes"
  else
    echo "- $p: MISSING"
  fi
done
for d in generated/g04-audio generated/g04-audio/long-formats generated/g04-audio/probes; do
  if [[ -f "$SYLVIA_FIXTURE_CACHE/$d/.stamp" ]]; then echo "- $d: stamp present"; else echo "- $d: no stamp"; fi
done
echo "- generated/g04-audio in all: $(du -sh "$SYLVIA_FIXTURE_CACHE/generated/g04-audio" | cut -f1) (du -h, binary units); apparent size: $(du -skA "$SYLVIA_FIXTURE_CACHE/generated/g04-audio" | cut -f1) KiB"
