#!/usr/bin/env python3
"""Does the device runbook say what each checklist step says, and does every expected text it adds come from a source
that still says it? (M0 final review round 2: evidence R2-01, owner readability R6-01 and R6-02; round 3: owner
readability R7-01; the review of the re-pin round: R8-01. The step-number check beside it is
Docs/Stage0/evidence/M0-Integration/final-fix/commands/runbook-coverage.py.)

This version (22 October 2026, the assembly of the M0 decisions round on branch m0-decisions) replaces
Docs/Stage0/evidence/M0-Decisions/stage0/commands/runbook-content-check.py. Its comparison is that version's, which is
the round-2 version's, unchanged; only its lists changed, because the assembly carried the lock harness's step 3 into
the runbook (the harness branch's text for 6.1, which the runbook now gives in full) and quoted plan 19.1's new
baseline in Section 1.1:
- DEFERRED loses G0.5 recovery step 3: the runbook's 6.1 now carries that step's actions, expected lines and records,
  so its markers are compared both ways again, as every other step's are (the Stage 0 round's version left the whole
  step to the checklist while the harness was being built on another branch).
- RUNBOOK_OWN gains plan 19.1's sentence on the baseline device, which Section 1.1 quotes ("is an iPhone 11 Pro: the
  product owner chose the iPhone 11 family on 22 October 2026"), read in the plan (draft 0.8).
The Stage 0 round's version, run on the runbook as assembled, reports exactly those changes (the runner's control p).

The Stage 0 round's version (22 October 2026, the records of the product owner's M0 decisions) replaced
Docs/Stage0/evidence/M0-Integration/repin-27.1/round-2/commands/runbook-content-check.py. Its comparison was that
version's, unchanged; only its lists changed, because the decisions changed the texts three of their entries rest on
and moved a step to a harness whose steps the runbook then left to its checklist:
- DEFERRED gains G0.5 recovery step 3: PO-23 (b) has the locked-device harness built in Stage 0 for that step, and the
  runbook's 6.1 now leaves the harness's steps and expected lines to the checklist, in the words given below.
- RUNBOOK_OWN loses three entries whose texts the runbook no longer quotes: "iPhone 12-class hardware" (plan 19.1's
  baseline, which decision D-1 (b) replaces with the iPhone 11 Pro), "Run on both when available" (the G0.3 checklist's
  Setup 1, which correction C56, accepted with decision D-6, replaced) and "once available" (ADR-0013's open item, which
  correction C50, accepted with D-6, rewrites).
The earlier version, run on the runbook of 22 October 2026, reports exactly those changes (the runner's control n).

The round-2 version, in turn, replaced repin-27.1/commands/runbook-content-check.py, which took a step's
gates only from the parenthesis after its bold heading, so a step that names its gate in the heading itself, as 0.8
does ("G0.5 recovery report row 10"), was compared with every checklist: a G0.5 AI-only text added to 0.8 passed (R8-01).
That one replaced final-fix-2/commands/runbook-content-check.py, whose reverse pass compared four count forms only, with
all eight checklists joined: R7-01. Besides the gates, this version changes only what it prints: the counts of the
entries of NOT_CARRIED and RUNBOOK_OWN by kind, so the documents' description of them can be read off its log.)

    python3 -I runbook-content-check.py <repository root> [<runbook file to check instead of Docs/Stage0/M0-device-runbook.md>]

Markers. In a text, outside fenced code blocks, with runs of whitespace made one space and curly quotes made
straight: each text of 3 to 300 characters in double quotes (an on-screen or log text a step expects, or a name it
uses), and each text of 3 to 300 characters in backticks that holds a log field (an "=") or a count ("Test run with",
"Executed N", "read back on", or a number followed by test(s), suite(s), file(s), table(s), item(s) or part(s)).
Backticks are paired left to right whatever the length of the text between them (the check before the last required
three characters, so after a short span such as `y` it paired them wrongly and missed markers, among them four of G0.5
AI step 6). In the reverse pass a double-quoted text that starts inside backticks is a command's argument, or part of a
backtick text compared whole, not a marker.

Forward. Every marker of every step of the eight checklists (Docs/Stage0/device-checklists/, by each file's own
numbering, as runbook-coverage.py reads it) must occur in the runbook's header or Sections 1-7, where its steps are
(not only in Sections 8 and 9, which record corrections and checks), unless the runbook leaves that step's values to
the checklist and says so where the step is (DEFERRED, with the runbook's words), or the marker is listed in
NOT_CARRIED with its kind and the reason it is not carried.

Reverse. Every marker of the runbook's header and Sections 1-7, and every count the runbook states in prose in one of
three forms ("Test run with N tests in N suites", "Executed N tests", "read back on N files and directories"), must
occur in the checklist of the gate its step names: a step is a bold numbered step ("**4.1 ...**", from its heading to
the next one), and its gates are those named in its bold heading ("**0.8 G0.5 recovery report row 10 ...**") or in the
parenthesis that follows it ("G0.2 step 4", "EPUB step 1", "G0.5 recovery step 4 and G0.5 AI step 3b"); text in a
session outside such a step takes the gates of that session's steps; and text outside the sessions (the header and
Sections 1-3, 6 and 7), or in a step that names no gate (0.2-0.5), may match any checklist. A marker that does not must
be listed in RUNBOOK_OWN, with its kind, what it is and where it comes from: for an app's or script's text, a
repository document, or a tool's committed output, the entry names the file and the fragment of it that says the text,
and the check fails unless that fragment is still in that file, so a runbook-only text that its source no longer says
is caught; a text from outside the repository (an Apple support page) or a name the runbook defines itself can only be
checked for being in the runbook. An entry whose marker is no longer in the header or Sections 1-7 is stale and fails.
"pull the N result tables" (1.4) is also compared with the number of tables G0.4 step 1.2's loop names.

Not compared, in either direction:
- meaning: a paraphrase that changed what a step asks would pass;
- a text in backticks that holds neither a log field nor a count: a status or message the runbook writes in backticks
  (4.4's `pairing failed: pinMismatch`, 4.14's `reauthentication_required`, 0.7's `RESULT: PASS`), a command or a file
  name;
- numbers and expected results written in prose, outside quotes and backticks, except the three count forms and the
  table count above: for example 1.4's count of the release tables it pulls, the four test counts of 1.4's filters, or
  4.18's number of parts verified before the phone is locked.
The runner, runbook-content-check.sh, changes one text of each kind and shows the check passing. Sections 8 and 9
(records of corrections and checks) are not read by the reverse pass. Read-only; standard library only. Exit status 1
if any problem is printed.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
RUNBOOK = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "Docs/Stage0/M0-device-runbook.md"
CHECKLISTS = ROOT / "Docs/Stage0/device-checklists"

# Steps whose expected values the runbook leaves to the checklist, saying so where the step is: (file, step) -> the
# runbook's words that say so (which must occur in the runbook, or the deferral itself is a problem).
DEFERRED = {
    ("G04-Audio.md", 1): "G0.4 step 1.3's result tables",
    ("G05-AI.md", 9): "G0.5 AI step 9.2's strings",
}

# Markers of a checklist step that the runbook does not carry, each with its kind and the reason. Keyed by (file, step,
# marker). The kinds (printed with their counts, so the documents that describe this list can be checked against it):
PH = "a placeholder the runbook fills in"
HI = "the checklist's history, or a simulator result it quotes"
FO = "a description of a log's format, not an expected value"
WO = "said in other words in the runbook"
WA = "the expected result of a step that can wait for a later milestone"
RV = "a detail of a review done from the checklist"
NOT_CARRIED: dict[tuple[str, int, str], tuple[str, str]] = {
    ("G02-Transfer.md", 8, "Download <title>"): (PH, "the runbook names the item it downloads (4.8: \"Download from inbox: large-5GiB\")"),
    ("G02-Transfer.md", 8, "Download from inbox: <title>"): (PH, "the same: the runbook names the item"),
    ("G02-Transfer.md", 13, "app_state=background_relaunch"): (HI, "a quotation of the simulator's events in the step's introduction; "
        "the runbook writes the expected result as the step does, `app_state=background` or `background_relaunch` (4.10)"),
    ("G02-Transfer.md", 20, "No Accounts"): (HI, "the step's history of the failed signing attempts of 12 and 13 October 2026; the "
        "runbook states the build Mac's state instead (Section 1.5: no developer account in Xcode)"),
    ("G02-Transfer.md", 4, "Sylvia connects to the Mac you paired with on your network..."): (WO, "the checklist shortens the "
        "prompt's text; the runbook quotes it in full (4.1), as the harness's Info.plist gives it"),
    ("G01-PDF.md", 10, "id=<device UDID>"): (PH, "the checklist's destination placeholder; the runbook's commands target the phone as "
        "\"id=$DEVICE_ID\", the UDID Section 1.5 says how to find (correction C1)"),
    ("G02-Transfer.md", 1, "id=<device UDID>"): (PH, "the same placeholder (1.1)"),
    ("G02-Transfer.md", 6, "id=<device UDID>"): (PH, "the same placeholder (4.15)"),
    ("G05-Recovery.md", 2, "id=<device UDID>"): (PH, "the same placeholder (1.2)"),
    ("G02-Transfer.md", 23, "Spikes/G02-Transfer/Scripts/device-ats-probe.sh Docs/Stage0/evidence/G02-Transfer/device/23-ats-none.log "
        "none 'platform=iOS,name=<the iPhone>' -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z"):
        (PH, "the checklist's command with its destination placeholder; the runbook's command targets the phone by its UDID, "
             "\"id=$DEVICE_ID\" (correction C1; 4.19)"),
    ("G04-Audio.md", 9, "key=value"): (FO, "the checklist's description of the log format; the runbook names the fields to check (3.8)"),
    ("G04-Audio.md", 9, "ranges="): (FO, "the same: a field named in that description, not an expected value"),
    ("G04-Audio.md", 9, "origin=intent.control@..."): (HI, "the simulator's result quoted in the step's introduction; the runbook gives "
        "the device's expected origin in full (3.8)"),
    ("G04-Audio.md", 12, "loaded=true played_since_load=false"): (HI, "the step's history: the simulator's line under the rule before "
        "review 6; the runbook gives the rule and each field to check (3.11)"),
    ("G04-Audio.md", 12, "nothing loaded"): (HI, "the step's history: the name of the rule review 6 replaced (3.11 gives the rule since)"),
    ("G04-Audio.md", 15, "music uninterrupted during steps 2-4"): (WO, "the runbook names the parts (the copy, the launch and the "
        "captures) instead of the checklist's sub-step numbers (3.14)"),
    ("G05-Recovery.md", 4, "Sylvia shows a safe unavailable state before first unlock (class-C files unreadable, no class lowered)"):
        (WA, "step 4.5, which can wait for the first milestone with an app shell (Section 7); 6.3 says it stays pending"),
    ("G06-Design.md", 21, "API.EXAMPLE.CO / M"): (RV, "step 21 is the designer's review of the snapshot references, done from the "
        "checklist (Session 10)"),
    ("G06-Design.md", 21, "Saved 2:02 PM"): (RV, "the same: a detail of the designer's review of the snapshot references"),
}

# Markers of the runbook's Sections 1-7 that are in no checklist of their step's gate: marker -> (what it is, sources).
# Each source is (repository path, fragment): the fragment must be in that file. No source means the marker is the
# runbook's own name or instruction, or comes from outside the repository; the reason says which.
H = "harness"      # an app's or script's own text, read in its source
D = "document"     # quoted from a repository document (plan, ADR, report, another gate's checklist)
T = "tool"         # a tool's output, as committed evidence records it
X = "external"     # from outside the repository: not checkable here
R = "runbook"      # a name, value or instruction the runbook itself defines
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
G02_MODEL = "Spikes/G02-Transfer/iOS/Sources/Harness/HarnessModel.swift"
G02_VIEWS = "Spikes/G02-Transfer/iOS/Sources/Harness/HarnessViews.swift"
G02_MESSAGES = "Spikes/G02-Transfer/TransferKit/Sources/SylviaTransferCore/PartResponseValidation.swift"
G04_MODEL = "Spikes/G04-Audio/Sources/Harness/HarnessModel.swift"
RUNBOOK_OWN: dict[str, tuple[str, str, list[tuple[str, str]]]] = {
    # Section 1 (what you need first) and Section 3.
    "missing tool": (H, "what the G0.4 fixture generators print without ffmpeg (1.1)",
                     [("Scripts/fixtures/generate-g04-audio-fixtures.sh", 'echo "missing tool: $tool (brew install ffmpeg)"')]),
    "Apple Development: JUSTIN EVIDON": (T, "the build Mac's signing identity (1.5)",
                                         [("Docs/Stage0/evidence/M0-runbook/build-mac-state.txt", "Apple Development: JUSTIN EVIDON")]),
    "No profiles for 'com.jevidon.sylvia.spike.identityprobe' were found": (T, "the Mac identity probe's signing error without the account (1.5, 0.7)",
        [("Docs/Stage0/evidence/M0-runbook/device-builds/g02-mac-identity-probe-signing.log",
          "No profiles for 'com.jevidon.sylvia.spike.identityprobe' were found")]),
    "demonstrate each provider dialect plus a local endpoint ... a transcription endpoint": (D, "plan 21.1's G0.5 text (1.6, D-4)",
        [(PLAN, "demonstrate each provider dialect plus a local endpoint"), (PLAN, "a transcription endpoint and a restore drill")]),
    "is an iPhone 11 Pro: the product owner chose the iPhone 11 family on 22 October 2026": (D, "plan 19.1's baseline device "
        "since draft 0.8 (decision D-1 (b)), quoted in 1.1", [(PLAN, "is an iPhone 11 Pro: the product owner chose the iPhone 11 "
                                                                  "family on 22 October 2026")]),
    "Sets Auto-Lock to 30 seconds": (X, "Apple Support, https://support.apple.com/en-us/101604 (read 14 October 2026), on Low Power "
                                        "Mode (Session 1, C54)", []),
    # Session 0.
    "Sylvia test": (R, "the iCloud Drive folder this runbook has you make in 0.6 and use in 2.20, 5.2, 5.4 and 5.9", []),
    "G05_LOG_DIR=Docs/Stage0/evidence/G05-Recovery/logs": (D, "the G0.5 recovery report's documented evidence command, which 0.8 "
        "says not to use", [("Docs/Stage0/G05-Recovery.md", "G05_LOG_DIR=Docs/Stage0/evidence/G05-Recovery/logs Scripts/ci.d/71-g05-recovery.sh")]),
    "row 10 evidence present": (H, "the G0.5 recovery drop-in's line when it finds the class-B readback (0.8)",
                                [("Scripts/ci.d/71-g05-recovery.sh", 'echo "row 10 evidence present: class-B readback and inheritance lines found in host-tests.log"')]),
    # Session 1.
    "ATS CIDR": (H, "the display name of the ATS probe's CIDR variant (1.3)",
                 [("Spikes/G05-AI/ATSProbe/project.yml", "CFBundleDisplayName: ATS CIDR")]),
    "✔ Test run with 1 test in 1 suite passed": (T, "1.4's Low Power Mode run of the budget suite alone, whose filter selects one test",
        [("Docs/Stage0/evidence/M0-runbook/only-testing-ids.log",
          "-only-testing:G04AudioTests/RealAV/BudgetTests (exit 0) selected by the filter: 1;")]),
    "Test run with 1 test in 1 suite": (T, "the same count in prose (1.4)",
        [("Docs/Stage0/evidence/M0-runbook/only-testing-ids.log",
          "-only-testing:G04AudioTests/RealAV/BudgetTests (exit 0) selected by the filter: 1;")]),
    # Session 2.
    "From my governor, to be neither of the green nor of the blue party…": (T, "the fixture's text where 2.1's selection starts "
        "(correction C2), as the gate's evidence records it",
        [("Docs/Stage0/evidence/G01-EPUB/anchor-samples.json", "From my governor, to be neither of the green nor of the blue party")]),
    # Session 3.
    "The book folder": (R, "the title of this runbook's paragraph at the start of Session 3", []),
    "(2 files)": (H, "the Player title's file count for 3.14's book, as the harness writes it (correction C22)",
                  [(G04_MODEL, 'return (members, urls, "G04Book (\\(members.count) files)")')]),
    "G04Book (2 files)": (H, "the same title in 3.14", [(G04_MODEL, 'return (members, urls, "G04Book (\\(members.count) files)")')]),
    "member ... timing=estimatedCBR": (H, "the harness's log line for each book member, with the timing chosen for a constant-bit-rate MP3 (3.13)",
        [(G04_MODEL, 'log.write("member", "index=\\(i) duration_ms=\\(m.durationMs) timing=\\(m.timing.rawValue)")'),
         ("Spikes/G04-Audio/Sources/G04AudioKit/Media/AssetTiming.swift", "case estimatedCBR")]),
    # Session 4.
    "L=~/SylviaDeviceTest/library": (R, "this session's library folder, a variable the runbook defines", []),
    "P=47800": (R, "this session's fixed port (correction C33), a variable the runbook defines", []),
    "Addresses": (R, "the title of this runbook's paragraph on redacting addresses (Session 4)", []),
    "Receive a file from the remote device": (T, "devicectl's own description of `device copy from` (4.2)",
        [("Docs/Stage0/evidence/M0-runbook/tool-help.txt", "Receive a file from the remote device")]),
    "Sylvia source identity key": (H, "the label of the Mac source's identity key in the login keychain (Session 4, 4.19)",
        [("Spikes/G02-Transfer/SourceService/Sources/SylviaSourceService/SourceIdentity.swift",
          'attributes[kSecAttrLabel as String] = "Sylvia source identity key"')]),
    "on the same port, state and identity store": (H, "the source service's host tests, on how they restart it (Session 4, C33)",
        [("Spikes/G02-Transfer/SourceService/Tests/SylviaSourceServiceTests/Harness.swift",
          "Restarts the service on the same port, state and identity store")]),
    "large-5GiB": (H, "the catalog title of the 5 GiB file: its file name without the extension",
        [("Scripts/fixtures/generate-g02-transfer-large.sh", 'out="$out_dir/large-5GiB.bin"'),
         ("Spikes/G02-Transfer/SourceService/Sources/SylviaSourceService/SourceLibrary.swift",
          "let base = (name as NSString).deletingPathExtension")]),
    "Download se-walden": (H, "the harness's download button for an item (the checklist's \"Download <title>\")",
                           [(G02_VIEWS, 'Button("Download \\(item.title)")')]),
    "Download large-5GiB": (H, "the same button for the 5 GiB item", [(G02_VIEWS, 'Button("Download \\(item.title)")')]),
    "Download from inbox: large-5GiB": (H, "the harness's button for an inbox entry (the checklist's \"Download from inbox: <title>\")",
                                        [(G02_VIEWS, 'Button("Download from inbox: \\(entry.title)")')]),
    "Paired with Device test Mac. Token stored in the Keychain (after first unlock, this device only).": (H,
        "the harness's pairing status, with the source name this session gives (--name \"Device test Mac\"; 4.1)",
        [(G02_MODEL, 'pairingStatus = "Paired with \\(paired.sourceName). Token stored in the Keychain (after first unlock, this device only)."')]),
    "Sylvia connects to the Mac you paired with on your network to download books and audiobooks you send to this iPhone.": (H,
        "the harness's local network usage description, which iOS shows in its prompt (4.1)",
        [("Spikes/G02-Transfer/iOS/Config/Harness-Info.plist",
          "<string>Sylvia connects to the Mac you paired with on your network to download books and audiobooks you send to this iPhone.</string>")]),
    "Pairing will connect only to <address>:<P2>. The fingerprint is still the code's.": (H, "the harness's status after \"Use address\" (4.4)",
        [(G02_MODEL, 'pairingStatus = "Pairing will connect only to \\(payload.endpoints[0].urlHost):\\(port). The fingerprint is still the code\'s."')]),
    "<address>:<port> did not work: Turn on Local Network for Sylvia …": (H, "the harness's status when a manual address fails while Local "
        "Network is off (4.7)",
        [(G02_MODEL, 'manualStatus = "\\(endpoint.urlHost):\\(endpoint.port) did not work: \\(Self.describe(error))"'),
         (G02_MESSAGES, "Turn on Local Network for Sylvia in Settings > Privacy & Security > Local Network, then resume.")]),
    "… did not work: …": (H, "the same status, for the Tailscale forms (4.15)",
        [(G02_MODEL, 'manualStatus = "\\(endpoint.urlHost):\\(endpoint.port) did not work: \\(Self.describe(error))"')]),
    "Using …: the Mac's key matches the paired fingerprint.": (H, "the harness's status after \"Use\" (4.15)",
        [(G02_MODEL, 'manualStatus = "Using \\(endpoint.urlHost):\\(endpoint.port): the Mac\'s key matches the paired fingerprint."')]),
    "Make sure the Mac is awake, running Sylvia and reachable, then resume.": (H, "the client's pause message for an unreachable Mac (4.9)",
        [(G02_MESSAGES, 'case .sourceUnreachable: "Make sure the Mac is awake, running Sylvia and reachable, then resume."')]),
    "Make sure the Mac is awake…": (H, "the start of the same message (4.14)",
        [(G02_MESSAGES, 'case .sourceUnreachable: "Make sure the Mac is awake, running Sylvia and reachable, then resume."')]),
    "The Mac's identity changed. Pair again and compare the fingerprint.": (H, "the client's message for a changed Mac key (4.14)",
        [(G02_MESSAGES, 'case .sourceIdentityChanged: "The Mac\'s identity changed. Pair again and compare the fingerprint."')]),
    "This iPhone's access was removed on the Mac. Pair again to continue.": (H, "the client's message for a 403, which 4.14 says the "
        "owner's revocation must not produce (the gate's review R3-02)",
        [(G02_MESSAGES, 'case .accessRevoked: "This iPhone\'s access was removed on the Mac. Pair again to continue."')]),
    # Session 5.
    "excluded from backup: Staging=true handoffInbox=true": (H, "the in-app layout test's evidence line (5.6)",
        [("Spikes/G03-Intake/App/Tests/Unit/InAppLayoutTests.swift", 'print("G03-EVIDENCE layout: excluded from backup: Staging=\\(')]),
    # Session 6.
    "discarded-segments=0": (H, "a field of the live transcription test's LIVE-TRANSCRIPTION line (6.6)",
        [("Spikes/G05-AI/Tests/LiveProviderTests/LiveProviderSmokeTests.swift", '"discarded-segments=\\(record.discardedSegmentCount)')]),
    # Session 7.
    "Sylvia Catalog": (H, "the design catalog's display name", [("Apps/DesignCatalog/project.yml", "INFOPLIST_KEY_CFBundleDisplayName: Sylvia Catalog")]),
    "Slow writes (5 seconds)": (H, "the prototype's switch for slow writes (7.10)",
                                [("Apps/DesignCatalog/Sources/Prototype/StorageAndSettings.swift", 'toggle("Slow writes (5 seconds)"')]),
    # Session 8 and its repeats.
    "type roles under Dynamic Type at the default and largest accessibility sizes on the oldest supported iPhone": (D,
        "plan 21.1's G0.6 text, quoted in 8.1", [(PLAN, "type roles under Dynamic Type at the default and largest accessibility sizes on the oldest supported iPhone")]),
    "T38 on a device (Wi-Fi, oldest supported iPhone)": (D, "the G0.2 report's row name (8.7, Section 7)",
                                                          [("Docs/Stage0/G02-Transfer.md", "T38 on a device (Wi-Fi, oldest supported iPhone)")]),
    "memory on the oldest supported iPhone": (D, "ADR-0009's pending item (8.7, Section 7)",
                                              [("Docs/ADRs/0009-transfer-protocol.md", "memory on the oldest supported iPhone")]),
    "Timings": (R, "the title of this runbook's paragraph on timed steps (Section 1.5), which 8.7 refers to", []),
    "if available": (D, "the G0.2 checklist's step 22, quoted in Session 8's repeats",
                     [("Docs/Stage0/device-checklists/G02-Transfer.md", "if available")]),
    # Session 9.
    "pointer hover over links and form fields on an iPad": (D, "ADR-0005's pending device list (9.7, Section 7)",
        [("Docs/ADRs/0005-pdf-reading-and-anchors.md", "pointer hover over links and form fields on an iPad")]),
    # Section 6 (Session 10) and Section 7.
    "Security approves pairing (including the Tailscale exception, D16), endpoint/content isolation (including the EPUB adapter's "
    "safety configuration and the archive rules), the data-protection class (D17) and exports": (D, "plan 23.3 as drafts 0.5 and 0.7 "
        "propose it (Session 10)", [(PLAN, "Security approves pairing (including the Tailscale exception, D16), endpoint/content isolation "
                                           "(including the EPUB adapter's safety configuration and the archive rules), the data-protection class (D17) and exports")]),
    "Design approves capture/accessibility flows, the Marginalia token values after G0.6, the marker set and the status vocabulary": (D,
        "plan 23.3 (Session 10)", [(PLAN, "Design approves capture/accessibility flows, the Marginalia token values after G0.6, the marker set and the status vocabulary")]),
    "Security + iOS": (D, "the owners plan 23.1 gives decision D08 (D-9)", [(PLAN, "Security + iOS")]),
    "don't know how to pin xcode": (D, "the product owner's reply on PO-35, as ADR-0001 quotes it (D-3; added at the review of the "
        "re-pin round, R8-03 and R8-04)", [("Docs/ADRs/0001-platform-baseline-and-toolchain.md", "\"don't know how to pin xcode\"")]),
    "only if the minimum OS's ATS behavior passes testing": (D, "plan 14.3 (D-9)", [(PLAN, "only if the minimum OS's ATS behavior passes testing")]),
    "evidence and ADRs approved": (D, "plan 21.1's exit gate (D-10)", [(PLAN, "evidence and ADRs approved")]),
    "type roles ... on the oldest supported iPhone": (D, "plan 21.1's G0.6 text, shortened (D-2)",
        [(PLAN, "type roles under Dynamic Type at the default and largest accessibility sizes on the oldest supported iPhone")]),
    "Push-time cost": (D, "the paragraph of ADR-0002 that D-8 refers to", [("Docs/ADRs/0002-repository-build-and-ci.md", "*Push-time cost.*")]),
    "Blocks M0": (R, "the name of a column of Section 7's table, which D-10 refers to", []),
    "15.4 when the system cannot store a background download": (D, "the G0.2 report's row name (Section 7)",
        [("Docs/Stage0/G02-Transfer.md", "15.4 when the system cannot store a background download")]),
    "T08 (device)": (D, "the G0.3 report's row name (Section 7)", [("Docs/Stage0/G03-Intake.md", "T08 (device)")]),
    "Device runs in": (D, "ADR-0010's open item (Section 7)", [("Docs/ADRs/0010-intake-handoff-and-wired-bundles.md", "Device runs in")]),
    "consent-wording review": (D, "ADR-0011's pending human evidence (Section 7)",
                               [("Docs/ADRs/0011-ai-providers-context-and-privacy.md", "consent-wording review")]),
    "token values adjusted where devices disagree": (D, "the G0.6 report's row name (Section 7)",
                                                     [("Docs/Stage0/G06-Design.md", "token values adjusted where devices disagree")]),
}


def normalized(text: str) -> str:
    text = text.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", text)


def without_code_blocks(text: str) -> str:
    return re.sub(r"^\s*```.*?^\s*```", " ", text, flags=re.M | re.S)


def checklist_steps(name: str) -> dict[int, str]:
    """Step number -> the step's text, by the file's own numbering (as runbook-coverage.py reads the numbers)."""
    text = (CHECKLISTS / name).read_text(encoding="utf-8")
    if name == "G02-Transfer.md":
        pattern = r"^### (\d+)\. "
    elif name in ("G04-Audio.md", "G05-AI.md", "G05-Recovery.md"):
        pattern = r"^## (\d+)\. "
    elif name in ("G01-EPUB.md", "G01-PDF.md"):
        pattern = r"^(\d+)\. \*\*"
    elif name == "G03-Intake.md":
        pattern = r"^(\d+)\. "
    else:
        pattern = r"^\| (\d+) \| "
    starts = [(m.start(), int(m.group(1))) for m in re.finditer(pattern, text, re.M)]
    if name == "G03-Intake.md":
        starts = [(s, n) for s, n in starts if n >= 6]
    steps: dict[int, str] = {}
    for i, (start, number) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
        heading = text.find("\n## ", start + 1)  # a section that follows the last step (Notes) is not the step's
        if heading != -1:
            end = min(end, heading)
        if name == "G06-Design.md":
            end = text.index("\n", start)  # one table row
        steps[number] = steps.get(number, "") + text[start:end]
    return steps


QUOTED = re.compile(r'(?<![\w"])"([^"\n]{3,300}?)"(?![\w"])')
# Backtick spans paired left to right, whatever their length (the check this replaces required three characters, so a
# short span such as `y` shifted the pairing and made text between two spans look like one, " = " for example).
SPAN = re.compile(r"`([^`\n]*)`")
COUNT_LIKE = re.compile(r"=|Test run with|Executed \d|read back on|\b\d+ (?:tests?|suites?|files?|tables?|items?|parts?)\b")


def markers(text: str, quotes_in_code: bool = True) -> list[str]:
    """The text's markers. With quotes_in_code False (the reverse pass), a double-quoted text that starts inside a
    backtick span is not a marker of its own: it is a command's argument, or part of a backtick text compared whole."""
    text = normalized(without_code_blocks(text))
    spans = [(m.start(), m.end(), m.group(1)) for m in SPAN.finditer(text)]
    found = []
    for m in QUOTED.finditer(text):
        value = m.group(1)
        if value != value.strip() or "**" in value:
            continue  # a fragment between two quotations, not a quotation
        if not quotes_in_code and any(a < m.start() < b for a, b, _ in spans):
            continue
        found.append(value)
    for a, b, value in spans:
        if 3 <= len(value) <= 300 and COUNT_LIKE.search(value):
            found.append(value)
    return sorted(set(found))


# Counts the runbook states in prose as expected results (the reverse pass of the check this one replaces).
PROSE_COUNTS = re.compile(r"Test run with \d+ tests? in \d+ suites?|Executed \d+ tests|read back on \d+ files and directories")


# Gate names in a step heading's parenthesis -> the checklist file.
GATE_NAMES = [
    (re.compile(r"\bG0\.1 EPUB\b|\bEPUB steps?\b"), "G01-EPUB.md"),
    (re.compile(r"\bG0\.1 PDF\b|\bPDF steps?\b"), "G01-PDF.md"),
    (re.compile(r"\bG0\.2\b"), "G02-Transfer.md"),
    (re.compile(r"\bG0\.3\b"), "G03-Intake.md"),
    (re.compile(r"\bG0\.4\b"), "G04-Audio.md"),
    (re.compile(r"\bG0\.5 AI\b"), "G05-AI.md"),
    (re.compile(r"\bG0\.5 recovery\b"), "G05-Recovery.md"),
    (re.compile(r"\bG0\.6\b"), "G06-Design.md"),
]
STEP = re.compile(r"^(?:- )?\*\*(\d+\.\d+[a-z]?) [^*\n]*\*\*", re.M)
SESSION = re.compile(r"^### Session (\d+) ", re.M)
SECTION = re.compile(r"^## \d+\. ", re.M)


def heading_parenthesis(text: str, start: int) -> str:
    """The text of the parenthesis that follows a step's bold heading at `start`, nested parentheses included."""
    close = text.index("**", text.index("**", start) + 2) + 2
    rest = text[close:close + 2000]
    if not rest.lstrip().startswith("("):
        return ""
    depth, out = 0, []
    for ch in rest[rest.index("("):]:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        out.append(ch)
        if depth == 0:
            break
    return "".join(out)


def gates_named(parenthesis: str) -> set[str]:
    return {name for pattern, name in GATE_NAMES if pattern.search(parenthesis)}


def runbook_units(sessions_text: str) -> list[tuple[str, set[str] | None, str]]:
    """(label, gate checklists or None for any, text) for Sections 1-7, split at sections, sessions and bold steps."""
    cuts = sorted({0, len(sessions_text)} | {m.start() for m in SECTION.finditer(sessions_text)}
                  | {m.start() for m in SESSION.finditer(sessions_text)} | {m.start() for m in STEP.finditer(sessions_text)})
    units = []
    session = None
    for a, b in zip(cuts, cuts[1:]):
        chunk = sessions_text[a:b]
        sm, st, se = SESSION.match(chunk), STEP.match(chunk), SECTION.match(chunk)
        if se:
            session = None
        if sm:
            session = sm.group(1)
            units.append((f"Session {session}", "session", chunk))
        elif st:
            # The gates the step names in its bold heading or in the parenthesis after it (the check this one replaces
            # read only the parenthesis, so 0.8, whose heading names G0.5 recovery, matched every checklist: R8-01).
            heading = chunk[:chunk.index("**", chunk.index("**") + 2) + 2]
            gates = gates_named(heading + " " + heading_parenthesis(chunk, 0))
            units.append((f"step {st.group(1)}", gates or None, chunk))
        else:
            units.append((f"Session {session}" if session else f"text at offset {a}", "session" if session else None, chunk))
        units[-1] = units[-1] + (session,)
    # Text in a session outside its gated steps takes the union of the gates its steps name.
    by_session: dict[str, set[str]] = {}
    for label, gates, chunk, sess in units:
        if sess and isinstance(gates, set):
            by_session.setdefault(sess, set()).update(gates)
    resolved = []
    for label, gates, chunk, sess in units:
        if gates == "session":
            gates = by_session.get(sess) or None
        resolved.append((label, gates, chunk))
    return resolved


def main() -> int:
    runbook = RUNBOOK.read_text(encoding="utf-8")
    # The steps are in the header and Sections 1-7; Sections 8 and 9 record corrections and checks, so a checklist
    # text that only a correction quotes is not carried (the check this one replaces read the whole file).
    rb = normalized(runbook.split("\n## 8. ")[0])
    problems = 0
    print(f"runbook: {RUNBOOK.relative_to(ROOT) if RUNBOOK.is_relative_to(ROOT) else RUNBOOK}")
    print("== forward: each checklist step's markers, in the runbook")
    used_not_carried = set()
    for path in sorted(CHECKLISTS.glob("*.md")):
        steps = checklist_steps(path.name)
        checked = carried = deferred = listed = 0
        missing = []
        for number, text in sorted(steps.items()):
            deferral = DEFERRED.get((path.name, number))
            if deferral and normalized(deferral) not in rb:
                print(f"PROBLEM {path.name} step {number}: listed as left to the checklist, but the runbook no longer says so")
                problems += 1
            for marker in markers(text):
                checked += 1
                if marker in rb:
                    carried += 1
                elif deferral:
                    deferred += 1
                elif (path.name, number, marker) in NOT_CARRIED:
                    listed += 1
                    used_not_carried.add((path.name, number, marker))
                else:
                    missing.append((number, marker))
        print(f"{path.name}: {len(steps)} steps, {checked} markers: {carried} in the runbook, {deferred} in steps left to "
              f"the checklist, {listed} listed as not carried, {len(missing)} missing")
        for number, marker in missing:
            print(f"  MISSING step {number}: {marker[:200]}")
        problems += len(missing)
    for key in sorted(set(NOT_CARRIED) - used_not_carried):
        print(f"PROBLEM stale NOT_CARRIED entry (the marker is in the runbook now, or no longer in its step): {key}")
        problems += 1
    by_kind: dict[str, int] = {}
    for kind, _ in NOT_CARRIED.values():
        by_kind[kind] = by_kind.get(kind, 0) + 1
    print(f"  NOT_CARRIED: {len(NOT_CARRIED)} entries: " + "; ".join(f"{v} {k}" for k, v in by_kind.items()))

    print("== reverse: each marker of the runbook's header and Sections 1-7, in its step's gate checklist or listed as the "
          "runbook's own")
    texts = {p.name: normalized(p.read_text(encoding="utf-8")) for p in sorted(CHECKLISTS.glob("*.md"))}
    every = " ".join(texts.values())
    sessions = runbook.split("\n## 8. ")[0]
    seen_own = set()
    counts = {"in its gate's checklist": 0, "in a checklist (no gate named)": 0, "listed as the runbook's own": 0}
    kinds: dict[str, int] = {}
    reported = set()
    for label, gates, chunk in runbook_units(sessions):
        unit_markers = set(markers(chunk, quotes_in_code=False))
        unit_markers |= set(PROSE_COUNTS.findall(normalized(without_code_blocks(chunk))))
        for marker in sorted(unit_markers):
            where = " ".join(texts[g] for g in sorted(gates)) if gates else every
            if marker in where:
                counts["in its gate's checklist" if gates else "in a checklist (no gate named)"] += 1
            elif marker in RUNBOOK_OWN:
                counts["listed as the runbook's own"] += 1
                seen_own.add(marker)
                kinds[RUNBOOK_OWN[marker][0]] = kinds.get(RUNBOOK_OWN[marker][0], 0) + 1
            elif (label, marker) not in reported:
                reported.add((label, marker))
                elsewhere = [n for n, t in texts.items() if marker in t]
                print(f"  UNLISTED {label} ({', '.join(sorted(gates)) if gates else 'any checklist'}): {marker[:200]}"
                      + (f" [only in {', '.join(elsewhere)}]" if elsewhere else ""))
                problems += 1
    print("  " + "; ".join(f"{v} {k}" for k, v in counts.items())
          + " (by kind: " + ", ".join(f"{k} {v}" for k, v in sorted(kinds.items())) + ")")
    for marker in sorted(set(RUNBOOK_OWN) - seen_own):
        print(f"PROBLEM stale RUNBOOK_OWN entry (no longer in the header or Sections 1-7): {marker[:200]}")
        problems += 1
    sources = 0
    for marker, (kind, reason, refs) in sorted(RUNBOOK_OWN.items()):
        if kind in (H, D, T) and not refs:
            print(f"PROBLEM RUNBOOK_OWN entry of kind {kind} without a source: {marker[:120]}")
            problems += 1
        for path, fragment in refs:
            sources += 1
            file = ROOT / path
            if not file.is_file():
                print(f"PROBLEM source missing for {marker[:80]!r}: {path}")
                problems += 1
            elif normalized(fragment) not in normalized(file.read_text(encoding="utf-8", errors="replace")):
                print(f"PROBLEM source no longer says it, for {marker[:80]!r}: {path} lacks {fragment[:120]!r}")
                problems += 1
    print(f"  {sources} source fragments of {len(RUNBOOK_OWN)} entries looked up in their files")
    sourced = sum(1 for _, _, refs in RUNBOOK_OWN.values() if refs)
    unsourced: dict[str, int] = {}
    for kind, _, refs in RUNBOOK_OWN.values():
        if not refs:
            unsourced[kind] = unsourced.get(kind, 0) + 1
    print(f"  RUNBOOK_OWN: {len(RUNBOOK_OWN)} entries: {sourced} with a source whose fragment is read in its file; "
          f"{len(RUNBOOK_OWN) - sourced} without one, checked only for being in the runbook ("
          + ", ".join(f"{k} {v}" for k, v in sorted(unsourced.items())) + ")")
    loop = re.search(r"for t in (.*?); do", (CHECKLISTS / "G04-Audio.md").read_text(encoding="utf-8"), re.S)
    tables = len(re.findall(r"\b[\w.-]+\.(?:txt|tsv)\b", loop.group(1))) if loop else 0
    stated = re.search(r"pull the (\d+) result tables", normalized(sessions))
    if stated and int(stated.group(1)) != tables:
        print(f"PROBLEM the runbook says {stated.group(0)}, and G0.4 step 1.2's loop names {tables}")
        problems += 1
    elif stated:
        print(f"  ok   {stated.group(0)}: G0.4 step 1.2's loop names {tables} tables")
    print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} problem(s))")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
