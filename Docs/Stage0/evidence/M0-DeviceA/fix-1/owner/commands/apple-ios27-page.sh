#!/bin/bash
# The fix of the owner-readability findings of the review of the update of 24 October 2026 (26 October 2026 on the build
# Mac's clock; integration log section 32), its finding OWN-DA-07: fetches Apple's iPhone User Guide page "iPhone models
# compatible with iOS 27", which the runbook's 1.1 row A now cites, into a new folder under .build/scratch (never
# committed: Apple's content, read as data), and checks the quotes the records give with apple-ios27-page.py beside this
# file. Reads only support.apple.com; nothing is sent but the request; no git remote is contacted.
#   Docs/Stage0/evidence/M0-DeviceA/fix-1/owner/commands/apple-ios27-page.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, owner, fix-1, M0-DeviceA, evidence, Stage0, Docs
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
pages=.build/scratch/devicea-fix1-own-apple-ios27
rm -rf "$pages"
mkdir -p "$pages"
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/fix-1/owner/commands/apple-ios27-page.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "read: $(date -u +%Y-%m-%dT%H:%M:%SZ) (UTC; the build Mac's date: $(date +%Y-%m-%d))"
  echo
} > "$log"
url='https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-27-iphe3fa5df43/27/ios/27'
code="$(curl -sS -L --max-time 60 -o "$pages/ios-27-models.html" -w '%{http_code}' "$url" 2>> "$log")"
echo "fetched $url -> HTTP $code, $(wc -c < "$pages/ios-27-models.html" | tr -d ' ') bytes" >> "$log"
echo >> "$log"
python3 -I "$here/apple-ios27-page.py" "$pages/ios-27-models.html" >> "$log" 2>&1
status=$?
rm -rf "$pages"
echo "exit: $status" >> "$log"
exit $status
