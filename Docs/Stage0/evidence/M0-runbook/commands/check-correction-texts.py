#!/usr/bin/env python3
# M0 device runbook, Section 8: each correction quotes the text it replaces in a checklist, report, ADR or
# script; this check confirms that every quoted text occurs, as quoted, in the file named, so each
# correction can be applied as written. Read-only; run from the repository root. Environment: host (macOS).
#
#   python3 -I Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py
#       > Docs/Stage0/evidence/M0-runbook/correction-texts.log
"""Check that each text a Section 8 correction replaces occurs, as quoted, in the file it names."""
import datetime, sys

print(f"# texts that Section 8 of the M0 device runbook replaces; checked {datetime.datetime.now(datetime.timezone.utc):%Y-%m-%dT%H:%M:%SZ}"
      " from the repository root (the commit is in clean-run.log)")

CL = "Docs/Stage0/device-checklists/"
ST = "Docs/Stage0/"
AD = "Docs/ADRs/"
PAIRS = [
("C2", CL + "G01-EPUB.md", 'Long-press the word "governor" in "From my governor, to be neither of the green nor of the blue party", drag the end handle to "fights" at the end of that sentence.'),
("C2", CL + "G01-EPUB.md", 'the row reads "Quote: From my governor, … gladiators\' fights"'),
("C3", CL + "G01-EPUB.md", "(compare with the specimen in `Docs/Design/`)"),
("C4", CL + "G01-EPUB.md", "Repeat steps 1, 6 and 11 on the iPhone 12-class baseline and an iPad once they are available (ADR-0001 open item)."),
("C5", ST + "G01-EPUB.md", "Status values: passed-host, passed-simulator, failed, partial, pending-device, pending-human, not-applicable."),
("C10", CL + "G02-Transfer.md", "On the phone, open the part 2 harness pairing screen and paste the printed code (send it through a channel you control, for example AirDrop of a text file you delete afterwards, not a cloud note)."),
("C11", CL + "G02-Transfer.md", "`sylvia-source --root @@LT@@any folder@@GT@@ --lan --port @@LT@@P2@@GT@@ --ephemeral-identity --name Rogue`"),
("C13", CL + "G02-Transfer.md", '(scheme `G02TransferATSVariant`, build setting `G02_ATS_VARIANT=tailnet-exception`, app "Sylvia ATS Probe")'),
("C14", CL + "G02-Transfer.md", "`sylvia-test-source --root @@LT@@folder with the 5 GiB file@@GT@@ --lan --test-log-requests @@GT@@ source.log`. Pair, start the download, wait for two verified parts."),
("C15", CL + "G02-Transfer.md", 'Fresh install of the harness. Tap "Browse the local network" before pairing.'),
("C15", CL + "G02-Transfer.md", "screenshots of the error and of the successful retry"),
("C16", CL + "G02-Transfer.md", 'the transfer finishes with the pinned digest and "Imported" once.'),
("C16", CL + "G02-Transfer.md", "the transfer finishes and is imported once."),
("C16", CL + "G02-Transfer.md", "**Expected after the import:**"),
("C17", CL + "G02-Transfer.md", "earlier the agreement was not accepted: `Docs/Stage0/evidence/G02-Transfer/keychain-identity-signed*.log`)."),
("C17", ST + "G02-Transfer.md", 'Every phone step needs code signing for the team, which this Mac could not do on 12 October 2026 (checklist "Before you start").'),
("C18", CL + "G03-Intake.md", "-derivedDataPath Spikes/G03-Intake/App/.build/DerivedData-device -allowProvisioningUpdates"),
("C20", CL + "G03-Intake.md", "In Files, open an EPUB and use Share @@GT@@ **Open in Sylvia Intake Spike** (or the app icon row). Expected: as step 25. Repeat with the same file."),
("C21", CL + "G03-Intake.md", '"Opened file staged: 5 file(s), state staged"'),
("C22", CL + "G04-Audio.md", "(copy the four `multi/*.mp3` fixtures into `Documents/G04Book` instead of the M4B, relaunch, seek to 2:20 and capture)"),
("C22", CL + "G04-Audio.md", "With the LibriVox M4B in the book folder (step 2)"),
("C23", ST + "G04-Audio.md", "The device equivalent is checklist step 16."),
("C23", ST + "G04-Audio.md", "Device: steps 1, 1.5 and 14."),
("C24", CL + "G05-AI.md", "-only-testing:ProbeLocalNetworkingTests/ATSProbeTests/plainHTTPToAnotherDeviceOnTheLAN"),
("C26", CL + "G05-AI.md", "@@LT@@signing flags@@GT@@ | tee ats-device.log"),
("C26", CL + "G05-AI.md", "@@LT@@signing flags@@GT@@ | tee lan-allowed.log"),
("C26", CL + "G05-AI.md", "(log to `lan-denied.log`)"),
("C28", CL + "G06-Design.md", "On the iPhone 12-class baseline (iOS 26.x), Settings @@GT@@ Display & Brightness @@GT@@ Light."),
("C30", CL + "G04-Audio.md", "(branch `m0` after integration, or `m0-g04-audio`)"),
("C30", CL + "G05-AI.md", "in a checkout of branch `m0` (or the G0.5 branch before integration)"),
("C30", CL + "G05-Recovery.md", "check out the branch"),
("C31", CL + "G01-EPUB.md", "the result (**pass** or **fail**)"),
("C31", CL + "G01-PDF.md", "pass/fail"),
("C31", CL + "G02-Transfer.md", "pass or fail"),
("C31", CL + "G03-Intake.md", "write PASS or FAIL"),
("C31", CL + "G04-Audio.md", "from pending-device to passed or failed"),
("C31", CL + "G05-AI.md", "mark the step passed or failed"),
("C31", CL + "G05-Recovery.md", "from pending to passed or failed"),
("C31", CL + "G06-Design.md", "pass or fail"),
("C31", ST + "G05-AI.md", "Status values: passed-host, passed-simulator, partial, pending-device, pending-human, not-applicable."),
("C34", CL + "G02-Transfer.md", "the phone reports the same SHA-256 as `shasum -a 256 @@LT@@file@@GT@@` on the Mac"),
("C34", CL + "G02-Transfer.md", "the final file's SHA-256 is `d2383fe38d8033b62ef9e6222756369fab813d2c64b2bce41e86ad9494af16d9`"),
("C35", CL + "G02-Transfer.md", "`devices` the phone's device ID"),
("C35", CL + "G02-Transfer.md", "run `revoke @@LT@@device-id@@GT@@` on the Mac"),
("C36", CL + "G02-Transfer.md", "Pair again; then stop the source, delete its identity (`--state` directory's `identity.json` and the Keychain item `com.jevidon.sylvia.source.identity`, or start with a new `--state`), start it again and resume."),
("C37", CL + "G02-Transfer.md", "Share the 5 GiB generated file (`Scripts/fixtures/generate-g02-transfer-large.sh --print-path`)"),
("C39", CL + "G03-Intake.md", "Put `Fixtures/epub/se-walden.epub` in On My iPhone (AirDrop it or use Finder file sharing to another app)."),
("C39", CL + "G03-Intake.md", "one MP3 excerpt from `Fixtures/audio/`"),
("C40", CL + "G04-Audio.md", "Run it twice more with the phone on a charger and not in Low Power Mode, and once in Low Power Mode. Record the budget lines of each run."),
("C40", CL + "G05-Recovery.md", "Run step 1 two more times with the phone on a charger and not in Low Power Mode, and once in Low Power Mode. Save each log."),
("C41", CL + "G05-Recovery.md", "Record all four p95 values."),
("C42", CL + "G05-Recovery.md", "(the bundle ID is in step 4.1's log)"),
("C43", CL + "G06-Design.md", "(3) the primary button is a dark grey block, distinct from ink text and from the hairline secondary button;"),
("C45", CL + "G04-Audio.md", "`-allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z`"),
("C45", CL + "G05-Recovery.md", "`-allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z`"),
("C45", CL + "G05-AI.md", "-allowProvisioningUpdates` to each `xcodebuild` command"),
("C46", "Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh", "-disableAutomaticPackageResolution -allowProvisioningUpdates"),
("C46", "Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh", "-allowProvisioningUpdates (automatic signing"),
("C47", AD + "0009-transfer-protocol.md", "- Device run of the part 2 checklist steps (13 to 19, and 21 added in round 2): suspension, lock, force-quit, reboot before first unlock, Wi-Fi loss, data protection class, pairing by QR code, a full phone during a background download."),
("C47", ST + "G02-Transfer.md", "Which error iOS reports for its own failed write: checklist step 21."),
("C47", ST + "G02-Transfer.md", "is written as device steps 4, 6, 8, 9, 13 to 19 and 21 (a full phone during a background download)"),
("C48", CL + "G05-AI.md", "Run, on an iPhone with iOS 26.0-26.x if available (record the exact version; iOS 26.7 is the device on hand):"),
("C48", ST + "G05-AI.md", "| D1 | ATS behaviour on a device with the minimum OS | pending-device | checklist step 1 |"),
("C49", AD + "0011-ai-providers-context-and-privacy.md", "- **Pending (human):** a real local model server, Hermes or another gateway, live OpenAI and Anthropic, a real transcription endpoint, human answer-support review, consent-wording review, security review (steps 5-9)."),
("C49", AD + "0011-ai-providers-context-and-privacy.md", "- Human runs (steps 5-8): real local server, gateway, live first-party providers, real transcription endpoint."),
("C49", ST + "G05-AI.md", "| P2 | Hermes or another gateway | pending-human | checklist step 8 |"),
("C50", AD + "0013-design-language.md", "- Devices: checklist steps 1-21 and the part 3 review steps 22-31, on the iPhone 12-class baseline, the iPhone 17 Pro and an iPad once available."),
("C51", ST + "G06-Design.md", "Checklist steps 13, 14, 23, 24 and 27 on the oldest supported iPhone (no hardware yet), the iPhone 17 Pro and an iPad (no hardware yet)."),
("C51", ST + "G06-Design.md", "oldest supported iPhone, iPhone 17 Pro, iPad"),
("C51", AD + "0001-platform-baseline-and-toolchain.md", "- Product owner: an iPhone 12-class device and an iPad for G0.6 and the device matrix."),
("C52", CL + "G04-Audio.md", "Repeat steps 1, 3, 9-13 and 15 on the iPhone 12-class baseline when one is available (it has no Action button: skip step 11 there)."),
("C53", CL + "G04-Audio.md", "xcrun devicectl device process launch --device @@LT@@device-id@@GT@@ com.jevidon.sylvia.spike.g04audio -g04AutoPlay YES"),
("C54", CL + "G04-Audio.md", "Keep the phone unlocked, on a charger, with auto-lock set to Never for this step."),
("C55", AD + "0010-intake-handoff-and-wired-bundles.md", "Whether an iCloud download reports its progress through this Progress on a device is checklist step 16."),
("C56", CL + "G03-Intake.md", "Run on both when available."),
("C56", AD + "0010-intake-handoff-and-wired-bundles.md", "- Device runs in `Docs/Stage0/device-checklists/G03-Intake.md`, in particular the extension memory limit and the Finder cable copy (owner: serialized device run)."),
("C56", ST + "G03-Intake.md", "the share extension's real memory limit and peak on the iPhone 17 Pro and an iPhone 12-class phone"),
]
bad = 0
for cid, path, old in PAIRS:
    old = old.replace("@@LT@@", "<").replace("@@GT@@", ">")
    n = open(path, encoding="utf-8").read().count(old)
    status = "ok" if n >= 1 else "MISSING"
    if n == 0:
        bad += 1
    print(f"{cid:4} {status:7} x{n} {path}: {old[:70]}")
print(f"{len(PAIRS)} texts checked, {bad} missing")
sys.exit(1 if bad else 0)
