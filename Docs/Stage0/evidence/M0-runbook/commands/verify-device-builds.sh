#!/usr/bin/env bash
# M0 device runbook: checks that each Stage 0 harness's device build command builds for a generic iOS device on
# this Mac. Build only: nothing is installed on, launched on or copied to a physical device, and no device is
# contacted. Environment: host (macOS), Xcode from Scripts/lib/env.sh.
#
#   Docs/Stage0/evidence/M0-runbook/commands/verify-device-builds.sh [check-name ...]   # default: every check
#
# How each command differs from the checklist command it checks, on purpose:
#   - `-destination generic/platform=iOS` instead of a device identifier (no device is used);
#   - `build-for-testing` where the checklist runs `test` (build only);
#   - no `-allowProvisioningUpdates` and no `-allowProvisioningDeviceRegistration` (which takes effect only with
#     the first). They let xcodebuild contact Apple's developer service to create profiles and App IDs and to
#     register the destination device, which is outside what this job may do on the network. Builds here use
#     only the signing identity and profiles already on this Mac, as Scripts/ci.d/60-g04-audio.sh does.
#     When a build stops because a profile is not on this Mac, the log says so and an unsigned compile check
#     (CODE_SIGNING_ALLOWED=NO) follows, so a code problem and a signing problem are told apart.
#   - conventions the checklist command lacks are added and named in the check's note (CLAUDE.md and ADR-0002:
#     `-derivedDataPath` inside the project directory, `-disableAutomaticPackageResolution`).
#
# Exit status: 0 only when every check ran as expected (its stated expectation, pass or signing-stop, held);
# otherwise 1, after every check has run.
#
# Outputs: Docs/Stage0/evidence/M0-runbook/device-builds/<check>.log (command, environment, load, exit status,
# error and signing lines, the end of the xcodebuild output, codesign checks of the products) and one row per
# check in Docs/Stage0/evidence/M0-runbook/device-builds/summary.tsv. Full xcodebuild output stays in
# .build/scratch/device-builds/ (gitignored, not committed).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$ROOT"
source Scripts/lib/env.sh
source Scripts/lib/sim.sh
source Scripts/lib/xcodegen.sh

EVID="$ROOT/Docs/Stage0/evidence/M0-runbook/device-builds"
FULL="$ROOT/.build/scratch/device-builds"
mkdir -p "$EVID" "$FULL"
SUMMARY="$EVID/summary.tsv"
# One summary per invocation (the committed one comes from a run of every check).
printf 'check\tstarted_utc\tseconds\texit\tresult\texpected\tas_expected\tnote\n' > "$SUMMARY"

TEAM="$SYLVIA_TEAM_ID"
CHECKS_RUN=0
NOT_AS_EXPECTED=0
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"

trim() { sed -e "s#$ROOT/##g" -e "s#$HOME#~#g"; }

# run_check NAME EXPECT NOTE PRODUCT_DIR "PRODUCTS..." -- command...
#   EXPECT: what this check is expected to show on this Mac, written before the run: "pass", or "signing-stop"
#           (the build stops at code signing because a profile it needs is not on this Mac)
#   PRODUCT_DIR: folder holding the products to verify with codesign after a successful build ("" for none)
#   PRODUCTS: space-separated product paths relative to PRODUCT_DIR (codesign --verify --strict on each)
run_check() {
  local name="$1" expect="$2" note="$3" pdir="$4" products="$5"
  shift 5
  [[ "$1" == "--" ]] && shift
  local log="$EVID/$name.log" full="$FULL/$name.log" started rc elapsed result as_expected
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    echo "# check: $name"
    echo "# expected on this Mac (stated before the run): $expect"
    echo "# note: $note"
    echo "# commit: $COMMIT"
    echo "# environment: host macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(xcodebuild -version | tr '\n' ' ')"
    echo "# started: $started; load at start: $(uptime | sed 's/.*load averages*: //')"
    echo "# command (from the repository root):"
    printf '#   '; printf '%q ' "$@" | trim; echo
  } > "$log"
  local t0=$SECONDS
  ( "$@" ) > "$full" 2>&1
  rc=$?
  elapsed=$((SECONDS - t0))
  {
    echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ) after ${elapsed} s; exit status $rc; load at end: $(uptime | sed 's/.*load averages*: //')"
    echo "--- result lines"
    grep -E '\*\* (BUILD|TEST BUILD|CLEAN) (SUCCEEDED|FAILED|INTERRUPTED) \*\*|^Build complete|^gen-pack ok|Test run with|Executed [0-9]+ test' "$full" | trim | sort -u
    echo "--- error lines ($(grep -c 'error:' "$full") in all; first 40 unique)"
    grep -E 'error:' "$full" | trim | sort -u | head -40
    echo "--- signing lines (first 20 unique)"
    grep -E 'Signing Identity|Provisioning Profile|requires a provisioning profile|No profiles for|No Account|No signing certificate|Automatic signing' "$full" | trim | sed -E 's/^ +//' | sort -u | head -20
    echo "--- warning count: $(grep -c 'warning:' "$full") (first 20 unique)"
    grep -E 'warning:' "$full" | trim | sort -u | head -20
    echo "--- last 15 lines of the output"
    tail -15 "$full" | trim
  } >> "$log"
  if (( rc == 0 )); then result=pass; else result=FAIL; fi
  if (( rc == 0 )) && [[ -n "$pdir" ]]; then
    echo "--- codesign checks of the products (in $(echo "$pdir" | trim))" >> "$log"
    local p
    for p in $products; do
      if codesign --verify --strict "$pdir/$p" >> "$log" 2>&1; then
        echo "== $p: codesign --verify --strict ok" >> "$log"
        codesign -dvv "$pdir/$p" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)=' >> "$log"
        if [[ -f "$pdir/$p/embedded.mobileprovision" ]]; then
          security cms -D -i "$pdir/$p/embedded.mobileprovision" > "$FULL/.profile.plist" 2>/dev/null
          echo "profile Name=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$FULL/.profile.plist" 2>/dev/null)" >> "$log"
          rm -f "$FULL/.profile.plist"
        fi
      else
        echo "== $p: codesign --verify --strict FAILED" >> "$log"
        result=FAIL
      fi
    done
  fi
  as_expected=no
  if [[ "$expect" == pass && "$result" == pass ]]; then as_expected=yes; fi
  if [[ "$expect" == signing-stop && "$result" == FAIL ]] \
    && grep -qE "doesn't include the|No profiles for|requires a provisioning profile|No Account" "$full" \
    && ! grep -qE '(\.swift|\.c|\.m):[0-9]+:[0-9]+: error:' "$full"; then
    as_expected=yes
  fi
  echo "# result: $result; expected: $expect; as expected: $as_expected" >> "$log"
  CHECKS_RUN=$((CHECKS_RUN + 1))
  [[ "$as_expected" == yes ]] || NOT_AS_EXPECTED=$((NOT_AS_EXPECTED + 1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$started" "$elapsed" "$rc" "$result" "$expect" "$as_expected" "$note" >> "$SUMMARY"
  echo "$name: $result (exit $rc, ${elapsed} s; expected $expect; as expected: $as_expected)"
  return 0
}

# sig_info LOG PATH: records a product's signature state as information (not a pass criterion).
sig_info() {
  {
    echo "--- signature state of $(basename "$2") (information; codesign -dv)"
    codesign -dv "$2" 2>&1 | trim | head -5
  } >> "$1"
}

gen() { sylvia_generate "$1" > "$FULL/generate-$(basename "$1").log" 2>&1 || echo "sylvia_generate $1 failed"; }

check_design_catalog() {
  gen Apps/DesignCatalog
  run_check design-catalog-debug pass \
    "G06 checklist Prerequisite: the checklist installs from Xcode (Run, Debug); this is that build on the command line." \
    "$ROOT/Apps/DesignCatalog/.build/DerivedData/Build/Products/Debug-iphoneos" "DesignCatalog.app" -- \
    xcodebuild build -project Apps/DesignCatalog/DesignCatalog.xcodeproj -scheme DesignCatalog -configuration Debug \
      -destination generic/platform=iOS -derivedDataPath Apps/DesignCatalog/.build/DerivedData \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
}

check_pdf() {
  gen Spikes/G01-PDF
  run_check g01-pdf-debug pass \
    "G01-PDF checklist Setup 2 (Xcode Run, Debug) on the command line; DEVELOPMENT_TEAM signs both targets (PDFSpikeHarness and the embedded PDFAnchorKit)." \
    "$ROOT/Spikes/G01-PDF/.build/DerivedData-device/Build/Products/Debug-iphoneos" "PDFSpikeHarness.app PDFSpikeHarness.app/Frameworks/PDFAnchorKit.framework" -- \
    xcodebuild build -project Spikes/G01-PDF/G01PDF.xcodeproj -scheme PDFSpikeHarness -configuration Debug \
      -destination generic/platform=iOS -derivedDataPath Spikes/G01-PDF/.build/DerivedData-device \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
  run_check g01-pdf-release pass \
    "Runbook correction for G01-PDF step 10 (plan 19.1: timings from a Release build without a debugger): Release build of the harness." \
    "$ROOT/Spikes/G01-PDF/.build/DerivedData-device-release/Build/Products/Release-iphoneos" "PDFSpikeHarness.app PDFSpikeHarness.app/Frameworks/PDFAnchorKit.framework" -- \
    xcodebuild build -project Spikes/G01-PDF/G01PDF.xcodeproj -scheme PDFSpikeHarness -configuration Release \
      -destination generic/platform=iOS -derivedDataPath Spikes/G01-PDF/.build/DerivedData-device-release \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
}

# plugins_info LOG APP: records what an app bundle carries in PlugIns and its size (information).
plugins_info() {
  {
    echo "--- contents of $(basename "$2")/PlugIns and the bundle's size (information)"
    ls "$2/PlugIns" 2>&1
    echo "size: $(du -sh "$2" | cut -f1) (du -h, binary units); apparent size: $(du -skA "$2" | cut -f1) KiB"
  } >> "$1"
}

check_g04_app() {
  gen Spikes/G04-Audio
  run_check g04-harness-release pass \
    "G04 checklist step 2.1 as corrected in the runbook (C32): the Release harness in a derived-data folder of its own, so no test bundle from step 1.5 ends up in the app that is installed." \
    "$ROOT/Spikes/G04-Audio/.build/DerivedData-release-app/Build/Products/Release-iphoneos" "G04AudioHarness.app G04AudioHarness.app/PlugIns/G04CaptureControl.appex G04AudioHarness.app/Frameworks/G04AudioKit.framework" -- \
    xcodebuild build -project Spikes/G04-Audio/G04Audio.xcodeproj -scheme G04AudioHarness -configuration Release \
      -destination generic/platform=iOS -derivedDataPath Spikes/G04-Audio/.build/DerivedData-release-app \
      DEVELOPMENT_TEAM="$TEAM"
  plugins_info "$EVID/g04-harness-release.log" \
    "$ROOT/Spikes/G04-Audio/.build/DerivedData-release-app/Build/Products/Release-iphoneos/G04AudioHarness.app"
}

# Runs after check_g04_tests, in the checklist's order (step 1.5, then step 2.1 in the same folder).
check_g04_app_as_written() {
  run_check g04-harness-release-as-written pass \
    "G04 checklist step 2.1 exactly as written (-derivedDataPath Spikes/G04-Audio/.build/DerivedData-release), run after step 1.5's build-for-testing in the same folder: does the Release app it installs carry step 1.5's test bundle?" \
    "$ROOT/Spikes/G04-Audio/.build/DerivedData-release/Build/Products/Release-iphoneos" "G04AudioHarness.app" -- \
    xcodebuild build -project Spikes/G04-Audio/G04Audio.xcodeproj -scheme G04AudioHarness -configuration Release \
      -destination generic/platform=iOS -derivedDataPath Spikes/G04-Audio/.build/DerivedData-release \
      DEVELOPMENT_TEAM="$TEAM"
  plugins_info "$EVID/g04-harness-release-as-written.log" \
    "$ROOT/Spikes/G04-Audio/.build/DerivedData-release/Build/Products/Release-iphoneos/G04AudioHarness.app"
}

check_recovery() {
  run_check g05-recovery-tests pass \
    "G05-Recovery checklist step 1 (xcodebuild test on the device), as build-for-testing; the CI drop-in only builds this unsigned. A Swift package's test bundle gets no code-signing step in build-for-testing (first run of this check, 14 Oct 2026), so its signature is recorded as information: whether xcodebuild test signs it for the phone only the device run shows." \
    "" "" -- \
    bash -c 'cd Spikes/G05-Recovery && exec xcodebuild build-for-testing -scheme G05Recovery-Package -destination generic/platform=iOS \
      -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$0"' "$TEAM"
  local products="$ROOT/Spikes/G05-Recovery/.build/DerivedData/Build/Products"
  if [[ -d "$products/Debug-iphoneos/SylviaRecoveryTests.xctest" ]]; then
    sig_info "$EVID/g05-recovery-tests.log" "$products/Debug-iphoneos/SylviaRecoveryTests.xctest"
    {
      echo "--- test host named by the .xctestrun (plutil -p)"
      plutil -p "$products"/*.xctestrun | grep -E '"(TestHostPath|TestBundlePath|BlueprintName)"' | sed -E 's/^ +//'
    } >> "$EVID/g05-recovery-tests.log"
  fi
}

check_recovery_release() {
  run_check g05-recovery-tests-release pass \
    "Runbook correction for G05-Recovery step 2 (plan 19.1: budgets from a Release build): the package tests in the Release configuration with ENABLE_TESTABILITY=YES (the tests use @testable import), as build-for-testing, in a derived-data folder of its own; the runbook then runs only DurabilityTests/latency() from it." \
    "" "" -- \
    bash -c 'cd Spikes/G05-Recovery && exec xcodebuild build-for-testing -scheme G05Recovery-Package -configuration Release ENABLE_TESTABILITY=YES \
      -destination generic/platform=iOS -derivedDataPath .build/DerivedData-release -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$0"' "$TEAM"
  local products="$ROOT/Spikes/G05-Recovery/.build/DerivedData-release/Build/Products"
  if [[ -d "$products/Release-iphoneos/SylviaRecoveryTests.xctest" ]]; then
    sig_info "$EVID/g05-recovery-tests-release.log" "$products/Release-iphoneos/SylviaRecoveryTests.xctest"
  fi
}

check_ai_probe() {
  gen Spikes/G05-AI/ATSProbe
  run_check g05-ai-atsprobe-tests pass \
    "G05-AI checklist steps 1-4 (xcodebuild test with the device signing flags), as build-for-testing." \
    "$ROOT/Spikes/G05-AI/ATSProbe/.build/DerivedData/Build/Products/Debug-iphoneos" "ProbeDefaultATS.app ProbeLocalNetworking.app ProbeCIDRException.app" -- \
    bash -c 'cd Spikes/G05-AI/ATSProbe && exec xcodebuild build-for-testing -project G05ATSProbe.xcodeproj -scheme G05ATSProbe \
      -destination generic/platform=iOS -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution \
      DEVELOPMENT_TEAM="$0" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"' "$TEAM"
}

check_transfer() {
  gen Spikes/G02-Transfer/iOS
  run_check g02-harness-debug pass \
    "G02 checklist Before you start (Xcode Run of G02TransferHarness, Debug) on the command line; -derivedDataPath and -disableAutomaticPackageResolution added (the checklist's step-1 command has neither)." \
    "$ROOT/Spikes/G02-Transfer/iOS/.build/DerivedData/Build/Products/Debug-iphoneos" "G02TransferHarness.app" -- \
    xcodebuild build -project Spikes/G02-Transfer/iOS/G02Transfer.xcodeproj -scheme G02TransferHarness -configuration Debug \
      -destination generic/platform=iOS -derivedDataPath Spikes/G02-Transfer/iOS/.build/DerivedData \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
  run_check g02-harness-release pass \
    "Runbook 8.7 (G02 step 11 on device A; plan 19.1: timings from a Release build without a debugger): the harness in Release, in a derived-data folder of its own. Its entitlements are recorded: Instruments attaches to it only with get-task-allow." \
    "$ROOT/Spikes/G02-Transfer/iOS/.build/DerivedData-release/Build/Products/Release-iphoneos" "G02TransferHarness.app" -- \
    xcodebuild build -project Spikes/G02-Transfer/iOS/G02Transfer.xcodeproj -scheme G02TransferHarness -configuration Release \
      -destination generic/platform=iOS -derivedDataPath Spikes/G02-Transfer/iOS/.build/DerivedData-release \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
  local relapp="$ROOT/Spikes/G02-Transfer/iOS/.build/DerivedData-release/Build/Products/Release-iphoneos/G02TransferHarness.app"
  if [[ -d "$relapp" ]]; then
    {
      echo "--- entitlements of the Release app (information; codesign -d --entitlements -, get-task-allow lines)"
      codesign -d --entitlements - --xml "$relapp" 2>/dev/null | plutil -p - 2>&1 | grep -E 'get-task-allow|application-identifier|team-identifier'
    } >> "$EVID/g02-harness-release.log"
  fi
  run_check g02-harness-tests pass \
    "G02 checklist step 1 (KeychainCredentialStoreTests on the device), as build-for-testing of the same scheme." \
    "$ROOT/Spikes/G02-Transfer/iOS/.build/DerivedData/Build/Products/Debug-iphoneos" "G02TransferHarness.app G02TransferHarness.app/PlugIns/G02TransferHostedTests.xctest" -- \
    xcodebuild build-for-testing -project Spikes/G02-Transfer/iOS/G02Transfer.xcodeproj -scheme G02TransferHarness \
      -destination generic/platform=iOS -derivedDataPath Spikes/G02-Transfer/iOS/.build/DerivedData \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
  run_check g02-ats-variant-tailnet pass \
    "G02 checklist step 6.3: the ATS probe app with G02_ATS_VARIANT=tailnet-exception (the checklist names the scheme and setting but gives no command)." \
    "$ROOT/Spikes/G02-Transfer/iOS/.build/DerivedData-ats/Build/Products/Debug-iphoneos" "G02TransferATSVariant.app" -- \
    xcodebuild build -project Spikes/G02-Transfer/iOS/G02Transfer.xcodeproj -scheme G02TransferATSVariant -configuration Debug \
      G02_ATS_VARIANT=tailnet-exception -destination generic/platform=iOS -derivedDataPath Spikes/G02-Transfer/iOS/.build/DerivedData-ats \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
  local plist="$ROOT/Spikes/G02-Transfer/iOS/.build/DerivedData-ats/Build/Products/Debug-iphoneos/G02TransferATSVariant.app/Info.plist"
  if [[ -f "$plist" ]]; then
    {
      echo "--- built Info.plist of the ATS probe app (plutil -p, ATS keys and display name)"
      plutil -p "$plist" | grep -E 'CFBundleDisplayName|CFBundleIdentifier|G02ATSVariant|NSAppTransportSecurity|NSExceptionDomains|ts.net|100.64|NSIncludesSubdomains|NSExceptionAllowsInsecureHTTPLoads'
    } >> "$EVID/g02-ats-variant-tailnet.log"
  fi
}

check_intake() {
  gen Spikes/G03-Intake/App
  run_check g03-intake-tests-signed signing-stop \
    "G03 checklist step 3 command line (xcodebuild test ... CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM CODE_SIGN_IDENTITY), as build-for-testing; -disableAutomaticPackageResolution added. Expected to need an App Group profile (group.com.jevidon.sylvia.spike) that only -allowProvisioningUpdates with an Xcode account can create." \
    "$ROOT/Spikes/G03-Intake/App/.build/DerivedData-device/Build/Products/Debug-iphoneos" "IntakeHarness.app IntakeHarness.app/PlugIns/IntakeShare.appex" -- \
    xcodebuild build-for-testing -project Spikes/G03-Intake/App/G03Intake.xcodeproj -scheme IntakeHarness \
      -destination generic/platform=iOS -derivedDataPath Spikes/G03-Intake/App/.build/DerivedData-device \
      -disableAutomaticPackageResolution CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development"
  run_check g03-intake-tests-unsigned pass \
    "Unsigned compile check of the same G03 build (CODE_SIGNING_ALLOWED=NO): separates a code problem from a signing problem." \
    "" "" -- \
    xcodebuild build-for-testing -project Spikes/G03-Intake/App/G03Intake.xcodeproj -scheme IntakeHarness \
      -destination generic/platform=iOS -derivedDataPath Spikes/G03-Intake/App/.build/DerivedData-device \
      -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO
}

check_epub() {
  gen Spikes/G01-EPUB
  run_check g01-epub-release pass \
    "G01-EPUB checklist install command (Release build for every step except 11)." \
    "$ROOT/Spikes/G01-EPUB/.build/DerivedData-device/Build/Products/Release-iphoneos" "EPUBHarness.app" -- \
    xcodebuild build -project Spikes/G01-EPUB/G01EPUB.xcodeproj -scheme EPUBHarness -configuration Release \
      -destination generic/platform=iOS -derivedDataPath Spikes/G01-EPUB/.build/DerivedData-device \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
  run_check g01-epub-tests-debug pass \
    "G01-EPUB checklist step 11 (Debug, hosted tests on the device), as build-for-testing." \
    "$ROOT/Spikes/G01-EPUB/.build/DerivedData-device-debug/Build/Products/Debug-iphoneos" "EPUBHarness.app EPUBHarness.app/PlugIns/EPUBHarnessTests.xctest" -- \
    xcodebuild build-for-testing -project Spikes/G01-EPUB/G01EPUB.xcodeproj -scheme EPUBHarness -configuration Debug \
      -destination generic/platform=iOS -derivedDataPath Spikes/G01-EPUB/.build/DerivedData-device-debug \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
}

check_g04_tests() {
  gen Spikes/G04-Audio
  run_check g04-tests-debug-fixtures pass \
    "G04 checklist step 1.1 (xcodebuild test, Debug), as build-for-testing: the post-build script bundles the 8.6 GB of fixtures, as on a device run." \
    "$ROOT/Spikes/G04-Audio/.build/DerivedData/Build/Products/Debug-iphoneos" "G04AudioHarness.app G04AudioHarness.app/PlugIns/G04AudioTests.xctest" -- \
    xcodebuild build-for-testing -project Spikes/G04-Audio/G04Audio.xcodeproj -scheme G04AudioHarness \
      -destination generic/platform=iOS -derivedDataPath Spikes/G04-Audio/.build/DerivedData DEVELOPMENT_TEAM="$TEAM"
  local x="$ROOT/Spikes/G04-Audio/.build/DerivedData/Build/Products/Debug-iphoneos/G04AudioHarness.app/PlugIns/G04AudioTests.xctest"
  if [[ -d "$x" ]]; then
    {
      echo "--- bundled fixtures in G04AudioTests.xctest"
      echo "size: $(du -sh "$x" | cut -f1) (du -h, binary units); apparent size: $(du -skA "$x" | cut -f1) KiB"
      echo "files under G04Fixtures/generated/g04-audio: $(find "$x/G04Fixtures/generated/g04-audio" -type f ! -name '.*' | wc -l | tr -d ' ')"
      echo "downloads: $(ls "$x/G04Fixtures/downloads" | tr '\n' ' ')"
    } >> "$EVID/g04-tests-debug-fixtures.log"
  fi
  run_check g04-tests-release-fixtures pass \
    "G04 checklist step 1.5 (Release, ENABLE_TESTABILITY=YES), as build-for-testing; fixtures bundled as in 1.1." \
    "$ROOT/Spikes/G04-Audio/.build/DerivedData-release/Build/Products/Release-iphoneos" "G04AudioHarness.app G04AudioHarness.app/PlugIns/G04AudioTests.xctest" -- \
    xcodebuild build-for-testing -project Spikes/G04-Audio/G04Audio.xcodeproj -scheme G04AudioHarness -configuration Release \
      ENABLE_TESTABILITY=YES -destination generic/platform=iOS -derivedDataPath Spikes/G04-Audio/.build/DerivedData-release \
      DEVELOPMENT_TEAM="$TEAM"
}

check_host_tools() {
  run_check g02-sylvia-source pass \
    "G02 checklist Before you start: the Mac source (host build, as written)." "" "" -- \
    xcrun swift build --package-path Spikes/G02-Transfer/SourceService --product sylvia-source
  run_check g02-sylvia-test-source pass \
    "G02 checklist Before you start: the request-logging test source for steps 13-17 (host build, as written)." "" "" -- \
    xcrun swift build --package-path Spikes/G02-Transfer/SourceService --product sylvia-test-source
  gen Spikes/G02-Transfer/MacIdentityProbe
  run_check g02-mac-identity-probe-signing signing-stop \
    "G02 checklist step 20 prerequisite: signed macOS build of the identity probe WITHOUT -allowProvisioningUpdates. Expected to stop for want of a Mac development profile (none on this Mac; Xcode has no account)." "" "" -- \
    xcodebuild build -project Spikes/G02-Transfer/MacIdentityProbe/G02MacIdentityProbe.xcodeproj -scheme G02MacIdentityProbe \
      -destination platform=macOS -derivedDataPath Spikes/G02-Transfer/MacIdentityProbe/.build/DerivedData \
      -disableAutomaticPackageResolution DEVELOPMENT_TEAM="$TEAM"
  local packdir="$ROOT/.build/scratch/g03-small-pack"
  rm -rf "$packdir"; mkdir -p "$packdir/work"
  run_check g03-small-pack pass \
    "G03 checklist step 4 small pack (written to .build/scratch instead of ~/Desktop), host." "" "" -- \
    bash -c 'cd Spikes/G03-Intake/IntakeKit && exec xcrun swift run -c release sylviapack-tool gen-pack "$0/small.sylviapack" "$0/work" 1000000' "$packdir"
  if [[ -f "$packdir/small.sylviapack" ]]; then
    {
      echo "--- small pack contents (zipinfo -1)"
      zipinfo -1 "$packdir/small.sylviapack"
      echo "size: $(stat -f %z "$packdir/small.sylviapack") bytes"
    } >> "$EVID/g03-small-pack.log"
  fi
  run_check g05-ai-live-tests-skip pass \
    "G05-AI checklist steps 5-8 command shape: swift test --filter LiveProviderTests WITHOUT SYLVIA_LIVE_PROVIDER_TESTS (every live test must skip; nothing is sent anywhere)." "" "" -- \
    bash -c 'cd Spikes/G05-AI && unset SYLVIA_LIVE_PROVIDER_TESTS OPENAI_API_KEY ANTHROPIC_API_KEY SYLVIA_LIVE_TRANSCRIPTION_API_KEY SYLVIA_LIVE_COMPAT_API_KEY; exec xcrun swift test --filter LiveProviderTests'
  {
    echo "--- live test lines (skips and results)"
    grep -E '➜|✔|✘|skipped' "$FULL/g05-ai-live-tests-skip.log" | trim | sort -u | head -20
  } >> "$EVID/g05-ai-live-tests-skip.log"
}

ALL=(design_catalog pdf g04_app recovery recovery_release ai_probe transfer intake epub g04_tests g04_app_as_written host_tools)
CHECKS=("$@")
(( ${#CHECKS[@]} )) || CHECKS=("${ALL[@]}")
echo "verify-device-builds: commit $COMMIT; checks: ${CHECKS[*]}"
for c in "${CHECKS[@]}"; do
  "check_$c"
done
echo "verify-device-builds: done; $CHECKS_RUN checks, $NOT_AS_EXPECTED not as expected; summary in ${SUMMARY#"$ROOT"/}"
(( NOT_AS_EXPECTED == 0 ))
