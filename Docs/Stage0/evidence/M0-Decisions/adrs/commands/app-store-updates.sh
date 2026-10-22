#!/usr/bin/env bash
# Read-only: the App Store's automatic-update settings and the installed Xcode, to compare with the product owner's
# statement of 22 October 2026 on the M0 decision page (PO-35's note: "auto updates is confirmed disabled"). The same
# `defaults read` as the re-pin round's toolchain-state.sh (Docs/Stage0/evidence/M0-Integration/repin-27.1/), which
# printed AutoUpdate 1 on 20 October 2026, plus the Software Update preference macOS also keeps for app updates.
# Nothing is written; no setting is changed. Host only.
#   Docs/Stage0/evidence/M0-Decisions/adrs/commands/app-store-updates.sh > <log>
set -u
echo "command: Docs/Stage0/evidence/M0-Decisions/adrs/commands/app-store-updates.sh"
echo "date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
echo
echo "== defaults read /Library/Preferences/com.apple.commerce AutoUpdate"
defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>&1
echo "exit status: $?"
echo
echo "== defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallAppUpdates"
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallAppUpdates 2>&1
echo "exit status: $?"
echo
echo "== the installed Xcode"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version 2>&1
echo "exit status: $?"
/usr/bin/stat -f 'Xcode.app modified: %Sm' /Applications/Xcode.app 2>&1
