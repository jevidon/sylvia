# ADR-0001: Platform baseline and toolchain

- **Status:** Accepted for the platform floor (product owner, 6 October 2026). Toolchain pin: Xcode 27.1 (27A9275), decided by the product owner on 20 October 2026 (PO-35, option (b): "The re-pin of 20 October 2026" below), in place of the Xcode 27.0 (27A266a) proposed at kickoff, which awaited the owner's confirmation that it was a non-beta release; technical-lead confirmation pending the M0 gate. This record of the re-pin is agent-written and not reviewed.
- **Date:** 2026-10-06; toolchain re-pinned 2026-10-20
- **Deciders:** Justin Evidon (product owner) for D01 and the toolchain pin; technical-lead confirmation pending the M0 gate
- **Plan references:** Sections 6.3, 19.1, 22.1, 22.2; decision D01; gate G0.5 (toolchain confirmation)

## Context

Draft 0.2 proposed iOS/iPadOS 18+ and macOS 14+ (D01) and asked that the exact non-beta Xcode be selected and recorded at kickoff (Section 6.3). The development Mac had Xcode 27.0 with the iOS 27 SDK and simulator runtimes for iOS 26.5 and 27.0 only, so iOS 18 could not be tested without additional runtimes or hardware, and iOS 18 is two major releases old at kickoff.

On 18 October 2026 at 07:28 NZDT the build Mac's Xcode updated itself from the Mac App Store to Xcode 27.1 (27A9275), and no Xcode 27.0 remained. From then `Scripts/ci.d/12-dependency-lock.sh` failed its toolchain check on this Mac whatever the commit, every repository check passing (integration log 9.5), and the Git LFS adoption, the M0 final review and both rounds of its fix were built and tested under 27.1. The product owner's question PO-35 (runbook decision D-3) put the choice: reinstall 27.0, or pin 27.1.

## Decision

**Deployment targets.** iOS and iPadOS 26.0; macOS 26.0 for the Mac companion. Packages declare `.iOS(.v26), .macOS(.v26)`.

**Toolchain.**

| Item | Pinned value |
| --- | --- |
| Xcode | 27.1, build 27A9275 (`/Applications/Xcode.app`), since 20 October 2026; 27.0, build 27A266a, from kickoff until then |
| Swift compiler | Apple Swift 6.4 (swiftlang-6.4.0.34.1, clang-2100.3.34.1), the same in 27.0 and 27.1 |
| SDKs | iOS 27.1, iOS Simulator 27.1, macOS 27.0 (Xcode 27.0 had iOS 27.0, iOS Simulator 27.0, macOS 27.0) |
| Simulator runtimes | iOS 26.5 (23F77), the default test runtime because it is closest to the floor; iOS 27.0 (24A434). Unchanged by 27.1, which brought no iOS 27.1 runtime |
| Project generation | XcodeGen 2.46.0 (`project.yml` per app or spike; ADR-0002) |
| Package manifests | `swift-tools-version: 6.2`, Swift 6 language mode, complete strict concurrency checking |
| Build host | macOS 26.6.2 (25G83), Apple M5 Max |

Scripts select Xcode through `DEVELOPER_DIR` (`Scripts/lib/env.sh`) and never change the machine's `xcode-select` setting. `sylvia_check_xcode` warns when the active build differs from the pin, and `Scripts/ci.d/12-dependency-lock.sh` fails on it (ADR-0014). The pin is recorded together in this table, `SYLVIA_XCODE_BUILD_PINNED` in `Scripts/lib/env.sh`, the toolchain of `Docs/Licenses/inventory.json`, the Xcode guard of `.github/workflows/ci.yml` and `CLAUDE.md`'s toolchain line, and changes in all of them at once (ADR-0014 section 6).

**The re-pin of 20 October 2026 (PO-35, D-3).**

- *Options.* (a) Confirm 27.0: reinstall it on the build Mac and repeat the complete CI under it, because the code changed since 14 October 2026 had been built only under 27.1. (b) Name 27.1 as the pin, changing the records above together; the evidence of 14 October stays recorded under 27.0. The recommended default was (b) (`Docs/Stage0/M0-gate.md` Section 4.1).
- *Decision and its basis.* Asked for a call on PO-35, with the recommendation to re-pin to 27.1, under which every drop-in but the toolchain check had passed, and to turn off Xcode's automatic updates, the product owner replied on 20 October 2026: "don't know how to pin xcode". The workflow took that as accepting the recommended option (b), which needs nothing done in Xcode: the pin is the repository's record of the build its checks expect, and this change makes that record 27.1. If that is not what the owner meant, option (a) is still open, and the pins change back together.
- *Why (b).* 27.1 is what the build Mac has and what the latest code was built and tested with: in the M0 final fix's second round every drop-in but the toolchain check passed under it, G0.4's clock tests and G0.5 recovery's class-B readback included (`Docs/Stage0/M0-gate.md` Section 2.10). (a) would repeat that work under an older build.
- *Is 27.1 a release build?* Its build number, 27A9275, does not follow Apple's beta numbering pattern (a four-digit number beginning with 5, as in 17A5241e); the app is `Xcode.app`, not `Xcode-beta.app`; and the Mac App Store installed it (its bundle carries the App Store's receipt, `Contents/_MASReceipt/receipt`), which distributes Xcode's releases, while betas come from Apple's developer site. That points to a release but is not Apple's statement: Apple's release notes were not read in this change, which used no network.
- *What changed with it, and what was checked* (20 October 2026; `Docs/Stage0/evidence/M0-Integration/repin-27.1/`; integration log section 13): `Scripts/lib/env.sh`, the inventory's toolchain and host-tool rows and `third-party-inventory.md`, the workflow's Xcode guard (which still stops a runner without the pinned build, with an error that names it), `CLAUDE.md`'s toolchain line, ADR-0002's CI paragraph, ADR-0014's notes, plan Section 6.3 (A01) and the Stage 0 records that named 27.0 as the pin. As ADR-0014 section 6 asks of a toolchain change, `xcode-settings.py` was run against 27.1: its output is the same as 27.0's, line for line, so the dependency check's setting lists need nothing new (`xcode-settings-compare.log`). `12-dependency-lock` failed on its toolchain line alone before the change and passes after it (`12-dependency-lock-before.log`, `12-dependency-lock.log`).
- *Which Xcode the evidence was produced on.* The Stage 0 gate evidence was produced on Xcode 27.0 (27A266a): the eight gate reports and their runs, M0 integration and M0 assembly, with its complete CI runs of 14 October 2026. The Git LFS adoption (19 October 2026), the M0 final review and both rounds of its fix (19 and 20 October 2026), and this re-pin ran on Xcode 27.1 (27A9275). Each record keeps the Xcode it names; none is rewritten.
- *Keeping the build Mac on the pin.* The App Store's automatic app updates were on when this change was made (`defaults read /Library/Preferences/com.apple.commerce AutoUpdate` printed 1, read-only, `toolchain-state.log`), so another Xcode release would replace 27.1 the same way. Turning them off is the owner's action, not an agent's: in the App Store app, App Store > Settings, clear Automatic Updates; or in System Settings > General > Software Update, the information button beside Automatic Updates, turn off the App Store's application updates. These are the setting names macOS 15 and later show, not checked on this Mac (no agent operates its settings); afterwards the same `defaults read` should print 0, which was not verified either. If Xcode changes anyway, `12-dependency-lock` fails naming the new build, and the choice of PO-35 comes back.

**Signing and identifiers.** Development team `A4KBDX665Z` (Justin Evidon, Individual program). Bundle identifiers live under `com.jevidon.sylvia`: the app `com.jevidon.sylvia`, the share extension `com.jevidon.sylvia.share`, the Mac companion `com.jevidon.sylvia.mac`, and Stage 0 harnesses under `com.jevidon.sylvia.spike.*`. The App Group is `group.com.jevidon.sylvia` (spikes use `group.com.jevidon.sylvia.spike`). Simulator and host builds need no team.

**Test devices.** Recorded for Stage 0: iPhone 17 Pro (iPhone18,1), iOS 26.7 (23H24), Developer Mode enabled, paired over the local network. The plan's proposed iPhone 12-class baseline device (Section 19.1) and an iPad are not yet available; until they are, results from them are pending, not inferred from newer hardware.

## Evidence

At kickoff (6 October 2026), under Xcode 27.0:

- `xcodebuild -version` → Xcode 27.0, Build version 27A266a; `version.plist` ProductBuildVersion 27A266a.
- `xcrun swift --version` (with `DEVELOPER_DIR` set) → Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1).
- `xcrun simctl list runtimes` → iOS 26.5 (23F77), iOS 27.0 (24A434).
- `xcrun devicectl device info details` → iPhone 17 Pro, iOS 26.7 (23H24), Developer Mode enabled.
- The build number 27A266a does not follow Apple's beta numbering pattern (a four-digit number beginning with 5, as in 17A5241e), and the app is installed as `Xcode.app`, not `Xcode-beta.app`. This suggests a release build but does not prove it; the product owner confirms. (Superseded by the re-pin of 20 October 2026: 27.0 was never confirmed and is no longer installed.)

At the re-pin (20 October 2026), under Xcode 27.1, host only, in `Docs/Stage0/evidence/M0-Integration/repin-27.1/` (each log names its command in `commands/`):

- `toolchain-state.log`: `xcodebuild -version` → Xcode 27.1, Build version 27A9275; `version.plist` ProductBuildVersion 27A9275; `Xcode.app` modified 18 October 2026 07:28:54 NZDT, with the App Store's receipt; no other Xcode in `/Applications`; Swift 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1); SDKs iOS and iOS Simulator 27.1, macOS 27.0; runtimes iOS 26.5 (23F77) and 27.0 (24A434), both present, and the drop-ins' device types (iPhone 17, iPhone SE (3rd generation), iPad (A16)) present; an iPhone 17 simulator on iOS 26.5 created, booted and shut down; devicectl 651.13.5 (642.16 under 27.0); App Store automatic updates on.
- `toolchain-27.1.log`: ADR-0014's toolchain inventory command, run again under 27.1 (`sylvia_check_xcode` matches the pin).
- `xcode-settings-compare.log`: the build settings Xcode 27.1's specifications pass to the compiler, linker and librarian, with the check's treatment of each, are the same as 27.0's line for line.
- `tool-help-compare.log`: the tool help the device runbook relies on, read again: the same, except devicectl's version and its `process launch` help, which now documents the `--` that correction C53 adds.
- `12-dependency-lock-before.log` and `12-dependency-lock.log`: the drop-in before the pins changed (one failure, the toolchain line) and on the round's last commit (no failure).
- No device was contacted: the phone's model and OS above are the kickoff record.

## Consequences

- SwiftUI and platform APIs introduced through iOS 26 and macOS 26 can be used without availability checks.
- iOS 26 runs on iPhone 11 and later, so the iPhone 12-class baseline remains supported.
- Building against the iOS 27 SDK (27.1 since the re-pin) gives system bars the Liquid Glass treatment. Sylvia's chrome is its own opaque component per Section 4.4.7, so that change does not reach Sylvia's screens; any system surface Sylvia still presents (menus, alerts, share sheets) follows the system.
- Results on iOS 26.0 through 26.4 are untested; the 26.5 runtime is the closest available.
- An Xcode update on the build Mac stops `12-dependency-lock` until the owner either reinstalls the pinned build or changes the pin, with every record of it, in one change.

## Alternatives considered

- **Keep iOS 18+ and macOS 14+.** Rejected by the product owner: it needs extra runtimes for testing, availability checks around newer APIs, and a floor that cannot be tested on any device here.
- **iOS 27+ only.** Smaller matrix, but it would exclude users on iOS 26 for no feature the plan requires.
- **Reinstall Xcode 27.0 after the update (PO-35 option (a)).** Not chosen on 20 October 2026: it would repeat under an older build the complete CI that had passed under 27.1.

## Open items

- Product owner: done on 20 October 2026, the toolchain pin (PO-35: Xcode 27.1). Still yours: turn off the App Store's automatic app updates on the build Mac (above), so the installed Xcode stays at the pin.
- Technical lead: confirm the pin at the M0 gate.
- Product owner: an iPhone 12-class device and an iPad for G0.6 and the device matrix.
