#!/bin/bash
# Fetches the Apple pages whose texts the records of the device-A change (24 October 2026) quote about the phones (the
# iPhone 13 mini's and the iPhone 11 Pro's technical specifications, those of the iPhone 11, the iPhone 11 Pro Max and
# the iPhone SE (2nd generation), whose chip the records name, and the iPhones iOS 26 supports) into a new folder
# under .build/scratch (never committed: Apple's content, read as data), and checks each quote with apple-device-pages.py
# beside this file. Reads only support.apple.com; nothing is sent but the requests; no git remote is contacted.
#   Docs/Stage0/evidence/M0-DeviceA/commands/apple-device-pages.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../.." && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
pages=.build/scratch/devicea-apple-device-pages
rm -rf "$pages"
mkdir -p "$pages"
{
  echo "command: Docs/Stage0/evidence/M0-DeviceA/commands/apple-device-pages.sh"
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "read: $(date -u +%Y-%m-%dT%H:%M:%SZ) (UTC; the build Mac's date: $(date +%Y-%m-%d))"
  echo
} > "$log"
fetch() { # file, URL
  local code
  code="$(curl -sS -L --max-time 60 -o "$pages/$1" -w '%{http_code}' "$2" 2>> "$log")"
  echo "fetched $2 -> HTTP $code, $(wc -c < "$pages/$1" | tr -d ' ') bytes" >> "$log"
}
fetch iphone-13-mini-specs.html https://support.apple.com/en-nz/111873
fetch iphone-11-pro-specs.html https://support.apple.com/en-nz/111879
fetch iphone-11-specs.html https://support.apple.com/en-nz/111865
fetch iphone-11-pro-max-specs.html https://support.apple.com/en-nz/111878
fetch iphone-se-2nd-generation-specs.html https://support.apple.com/en-nz/111882
fetch ios-26-models.html 'https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/26/ios/26'
echo >> "$log"
python3 -I "$here/apple-device-pages.py" "$pages" >> "$log" 2>&1
status=$?
rm -rf "$pages"
echo "exit: $status" >> "$log"
exit $status
