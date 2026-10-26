#!/bin/bash
# Fetches Apple's own pages that the records of 24 October 2026 quote (the iPhone 13 mini's and the iPhone 11 Pro's
# technical specifications, the iPhones iOS 26 supports, and Xcode 27.1's release entry, its beta's entry and its
# release notes) into a new folder under .build/scratch (never committed: Apple's content, read as data), and checks
# each quote with apple-pages.py beside this file. Reads only support.apple.com and developer.apple.com; nothing is
# sent but the requests; no git remote is contacted.
#   Docs/Stage0/evidence/M0-DeviceA/instructions/commands/apple-pages.sh <log>
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$(dirname "$1")"
log="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$root" || exit 1
pages=.build/scratch/devicea-apple-pages
rm -rf "$pages"
mkdir -p "$pages"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD))"
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
fetch ios-26-models.html 'https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/26/ios/26'
fetch xcode-27.1-release.html 'https://developer.apple.com/news/releases/?id=10152026a'
fetch xcode-27.1-beta.html 'https://developer.apple.com/news/releases/?id=09182026a'
fetch xcode-27.1-release-notes.json https://developer.apple.com/tutorials/data/documentation/xcode-release-notes/xcode-27_1-release-notes.json
echo >> "$log"
python3 -I "$here/apple-pages.py" "$pages" >> "$log" 2>&1
status=$?
rm -rf "$pages"
echo "exit: $status" >> "$log"
exit $status
