#!/bin/bash
# G0.2 probe fix: writes, verbatim, the paragraphs of Apple's pages and of the pinned SDK's SecItem.h that the fix's
# README cites. The pages' JSON (developer.apple.com's documentation data, what the pages render) was downloaded with
# curl into .build/scratch/apple-docs/ on 26 October 2026 at 16:00 UTC (27 October, 05:00 NZDT); this script only
# extracts from those files and from Xcode 27.1's macOS SDK.
#   Docs/Stage0/evidence/G02-Transfer/probe-fix/commands/apple-pages.sh > Docs/Stage0/evidence/G02-Transfer/probe-fix/apple-pages.txt
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../../../.." && pwd)"
docs="$root/.build/scratch/apple-docs"
header="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Security.framework/Headers/SecItem.h"
text() { python3 -I "$here/apple-doc-text.py" "$docs/$1"; }
pick() { local file="$1"; shift; local args=(); for p in "$@"; do args+=(-e "$p"); done; text "$file" | grep -F "${args[@]}"; }
echo "Read on 26 October 2026, 16:00 UTC (27 October, 05:00 NZDT). Each page's paragraphs are printed by"
echo "commands/apple-doc-text.py from the page's documentation JSON; only the paragraphs the README cites are kept."
echo
echo "== TN3137: On Mac keychain APIs and implementations"
echo "   https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains"
echo "   (data: https://developer.apple.com/tutorials/data/documentation/technotes/tn3137-on-mac-keychains.json)"
pick tn3137.json 'The Keychain and SecKeychain APIs always target' 'Every context has a keychain search list' \
  'When using the SecItem API to target the file-based keychain' 'adds the item to the default keychain' \
  'consult all keychains in the search list' 'The SecItem API is well aligned with the data protection keychain' \
  'macOS builds the list of data protection keychain access groups' '2026-09-24 ' '2022-11-01 '
echo
echo "== kSecUseDataProtectionKeychain"
echo "   https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain"
echo "   (data: https://developer.apple.com/tutorials/data/documentation/security/ksecusedataprotectionkeychain.json)"
pick ksecusedataprotectionkeychain.json 'abstract:' 'Set the value for this key to true' 'The data protection key affects operations only in macOS'
echo
echo "== kSecMatchSearchList"
echo "   https://developer.apple.com/documentation/security/ksecmatchsearchlist"
echo "   (data: https://developer.apple.com/tutorials/data/documentation/security/ksecmatchsearchlist.json)"
pick ksecmatchsearchlist.json 'abstract:' 'The value is a CFArray'
echo
echo "== SecItem.h, Xcode 27.1 (27A9275) macOS SDK, lines 85-89, 219-227 and 257-260"
echo "   $header"
LC_ALL=C sed -n '85,89p;219,227p;257,260p' "$header"
