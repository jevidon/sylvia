#!/bin/bash
# The build Mac's state, read-only, for the records of the product owner's M0 decisions (22 October 2026; integration
# log section 15): the installed Xcode against the pin (PO-35 (b), Xcode 27.1, 27A9275), whether the App Store's
# automatic updates are on (the owner confirmed them off on the decision page; on 20 October 2026 the same key read 1:
# Docs/Stage0/evidence/M0-Integration/repin-27.1/toolchain-state.log), and the count of leftover g05-* directories in the
# user's temporary folder (G0.5 AI review R7-04; the owner's to delete). It changes no setting and deletes nothing.
#   Docs/Stage0/evidence/M0-Decisions/stage0/commands/build-mac-state.sh > <log> 2>&1
set -u
root="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
cd "$root" || exit 1
source Scripts/lib/env.sh
echo "command: Docs/Stage0/evidence/M0-Decisions/stage0/commands/build-mac-state.sh"
echo "commit: $(git rev-parse HEAD); uncommitted paths: $(git status --porcelain | wc -l | tr -d ' ')"
echo "date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ'); the build Mac's clock: $(date '+%Y-%m-%d %H:%M %Z')"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
echo "load: $(uptime)"
echo
echo "== Xcode"
echo "DEVELOPER_DIR=$DEVELOPER_DIR"
xcodebuild -version
echo "Xcode installs in /Applications: $(ls -d /Applications/Xcode*.app | tr '\n' ' ')"
echo "/Applications/Xcode.app modified: $(stat -f '%Sm' /Applications/Xcode.app)"
if [[ -e /Applications/Xcode.app/Contents/_MASReceipt/receipt ]]; then
  echo "Mac App Store receipt: present (installed or updated by the App Store)"
else
  echo "Mac App Store receipt: absent"
fi
if sylvia_check_xcode; then
  echo "sylvia_check_xcode: the installed build equals the pin ($SYLVIA_XCODE_BUILD_PINNED)"
else
  echo "sylvia_check_xcode: the installed build differs from the pin ($SYLVIA_XCODE_BUILD_PINNED)"
fi
echo
echo "== App Store automatic updates (read-only)"
echo "defaults read /Library/Preferences/com.apple.commerce AutoUpdate: $(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>&1)"
echo "defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallAppUpdates: $(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallAppUpdates 2>&1)"
echo "(the first key is the one the re-pin round read on 20 October 2026, when it gave 1; 0 means off. A key that does not"
echo " exist prints an error and says nothing about the setting.)"
echo
echo "== Leftover G0.5 temporary directories (read-only count)"
tmp="$(getconf DARWIN_USER_TEMP_DIR)"
echo "g05-* directories in the user's temporary folder: $(find "$tmp" -maxdepth 1 -name 'g05-*' -type d 2>/dev/null | wc -l | tr -d ' ')"
echo "g05-tests-* directories there: $(find "$tmp" -maxdepth 1 -name 'g05-tests-*' -type d 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "end: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
