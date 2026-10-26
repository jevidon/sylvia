# Xcode 27.1 (27A9275): Apple's pages, as relayed (24 October 2026)

The evidence for ADR-0001's open item: whether Xcode 27.1, build 27A9275, the toolchain pin since 20 October 2026 (PO-35 (b), which the product owner chose on 22 October 2026), is Apple's release build, not a beta or a release candidate. The recommendation of PO-35 (b) carried that check as its condition, and no record had read Apple's pages until now (ADR-0001, Decision and Open items).

**Where it comes from.** The orchestrating session of the M0 work read Apple's own pages on 24 October 2026 and relayed what they say to the assembly of the M0 exit preparation (branch `m0-exit-prep`; `Docs/Stage0/integration-log.md` section 30), which commits it here as relayed, word for word below. The assembling agent used no network and read none of the pages itself, so what the pages say rests on the relay; the URLs are given for anyone who reads them again.

**What it is not.** It is not the technical lead's confirmation, which ADR-0001's open item asks for and which the product owner gives personally (Sylvia is a solo project): that confirmation stays pending until the owner records it in ADR-0001. Nothing here is a device result or a sign-off.

## As relayed

> Evidence for ADR-0001's open item (Xcode 27.1, build 27A9275, is the release build), gathered by the orchestrating session on 24 October 2026 from Apple's own pages:
>
> - Apple Developer "Software Releases" entry https://developer.apple.com/news/releases/?id=10152026a: "Xcode 27.1 (27A9275)", dated October 15, 2026, listed with no beta or release-candidate label; the earlier beta was "Xcode 27.1 beta (27A9269)" (https://developer.apple.com/news/releases/?id=09182026a).
> - "Xcode 27.1 Release Notes" (not "Beta Release Notes"), https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes: Swift 6.4; SDKs for iOS 27.1, iPadOS 27, tvOS 27, watchOS 27, macOS 27, visionOS 27; on-device debugging for iOS 17 and later; requires macOS Tahoe 26.6 or later (the build Mac runs 26.6.2). Known issues: Mac Catalyst compile errors with iOS 27.1-only APIs and no Catalyst run destination for projects targeting iOS 27.1 (Sylvia does not use Mac Catalyst); slow initial Simulator launch; iPhone Duo simulator limits.

## How it reads against the records

Each point below is read in the repository (`commands/check-xcode-reading.py`, whose log is `check-xcode-reading.log` beside this file); none reads Apple's pages.

- **The build.** The relayed release entry names 27A9275, the build installed and pinned: ADR-0001's toolchain table, `SYLVIA_XCODE_BUILD_PINNED` in `Scripts/lib/env.sh` and the inventory's pin, which `12-dependency-lock` compares with the installed Xcode and finds equal (`12-dependency-lock.log` beside this file). The beta before it, as relayed, had another build number, 27A9269.
- **The label.** As relayed, the entry carries no beta or release-candidate label, and its notes are release notes, not beta release notes. So, by Apple's pages as relayed, 27A9275 is the release build, which the circumstantial evidence ADR-0001 recorded on 20 October 2026 (the build number's form, `Xcode.app` rather than `Xcode-beta.app`, the App Store's receipt) already pointed to.
- **What the notes state, against the build Mac and the pin.** Swift 6.4: ADR-0001's Swift row. The iOS 27.1 SDK: ADR-0001's SDK row. macOS Tahoe 26.6 or later: the build Mac runs macOS 26.6.2 (25G83), ADR-0001's build host row and the header of this round's gate checks. On-device debugging for iOS 17 and later: phone B's recorded iOS 26.7 (ADR-0001's test devices) is within it; the other devices' builds are recorded at runbook Session 0.4.
- **The known issues, against the repository.** Mac Catalyst: no project or package of the repository builds for Mac Catalyst (`git grep -i catalyst` finds the word only in `Scripts/check-dependency-lock.py`, which counts Mac Catalyst as iOS when it reads a target's platforms). A slow first launch of the Simulator: every timing the drop-ins take is indicative already, with the load beside it (`CLAUDE.md`, Evidence honesty). The iPhone Duo simulator: no drop-in names it (the drop-ins' simulators are the iPhone 17, the iPhone SE (3rd generation) and the iPad (A16)).

## What remains

- **The technical lead's confirmation, the product owner's** (ADR-0001, Open items; `Docs/Stage0/M0-gate.md` Section 1, item 1, step 7, and Section 5.4): read the two pages, or accept this relay, and record in ADR-0001's Deciders, with the date, that 27A9275 is the release build. If the pages say otherwise, PO-35 comes back to the product owner.
- **Then** the texts that still say the release notes await a check, which this round leaves as they are because the confirmation is still pending: `CLAUDE.md`'s toolchain line (the owner's file) and plan 6.3's A01 sentence (the plan's owner's).
