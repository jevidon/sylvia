# ADR-0001: Platform baseline and toolchain

- **Status:** Accepted for the platform floor (product owner, 6 October 2026). Toolchain pin proposed; awaiting the product owner's confirmation that Xcode 27.0 (27A266a) is a non-beta release.
- **Date:** 2026-10-06
- **Deciders:** Justin Evidon (product owner) for D01; technical-lead confirmation pending the M0 gate
- **Plan references:** Sections 6.3, 19.1, 22.1, 22.2; decision D01; gate G0.5 (toolchain confirmation)

## Context

Draft 0.2 proposed iOS/iPadOS 18+ and macOS 14+ (D01) and asked that the exact non-beta Xcode be selected and recorded at kickoff (Section 6.3). The development Mac has Xcode 27.0 with the iOS 27 SDK and simulator runtimes for iOS 26.5 and 27.0 only, so iOS 18 could not be tested without additional runtimes or hardware, and iOS 18 is two major releases old at kickoff.

## Decision

**Deployment targets.** iOS and iPadOS 26.0; macOS 26.0 for the Mac companion. Packages declare `.iOS(.v26), .macOS(.v26)`.

**Toolchain.**

| Item | Pinned value |
| --- | --- |
| Xcode | 27.0, build 27A266a (`/Applications/Xcode.app`) |
| Swift compiler | Apple Swift 6.4 (swiftlang-6.4.0.34.1, clang-2100.3.34.1) |
| SDKs | iOS 27.0, iOS Simulator 27.0, macOS 27.0 |
| Simulator runtimes | iOS 26.5 (23F77), the default test runtime because it is closest to the floor; iOS 27.0 (24A434) |
| Project generation | XcodeGen 2.46.0 (`project.yml` per app or spike; ADR-0002) |
| Package manifests | `swift-tools-version: 6.2`, Swift 6 language mode, complete strict concurrency checking |
| Build host | macOS 26.6.2 (25G83), Apple M5 Max |

Scripts select Xcode through `DEVELOPER_DIR` (`Scripts/lib/env.sh`) and never change the machine's `xcode-select` setting. `sylvia_check_xcode` warns when the active build differs from the pin.

**Signing and identifiers.** Development team `A4KBDX665Z` (Justin Evidon, Individual program). Bundle identifiers live under `com.jevidon.sylvia`: the app `com.jevidon.sylvia`, the share extension `com.jevidon.sylvia.share`, the Mac companion `com.jevidon.sylvia.mac`, and Stage 0 harnesses under `com.jevidon.sylvia.spike.*`. The App Group is `group.com.jevidon.sylvia` (spikes use `group.com.jevidon.sylvia.spike`). Simulator and host builds need no team.

**Test devices.** Recorded for Stage 0: iPhone 17 Pro (iPhone18,1), iOS 26.7 (23H24), Developer Mode enabled, paired over the local network. The plan's proposed iPhone 12-class baseline device (Section 19.1) and an iPad are not yet available; until they are, results from them are pending, not inferred from newer hardware.

## Evidence

- `xcodebuild -version` → Xcode 27.0, Build version 27A266a; `version.plist` ProductBuildVersion 27A266a.
- `xcrun swift --version` (with `DEVELOPER_DIR` set) → Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1).
- `xcrun simctl list runtimes` → iOS 26.5 (23F77), iOS 27.0 (24A434).
- `xcrun devicectl device info details` → iPhone 17 Pro, iOS 26.7 (23H24), Developer Mode enabled.
- The build number 27A266a does not follow Apple's beta numbering pattern (a four-digit number beginning with 5, as in 17A5241e), and the app is installed as `Xcode.app`, not `Xcode-beta.app`. This suggests a release build but does not prove it; the product owner confirms.

## Consequences

- SwiftUI and platform APIs introduced through iOS 26 and macOS 26 can be used without availability checks.
- iOS 26 runs on iPhone 11 and later, so the iPhone 12-class baseline remains supported.
- Building against the iOS 27 SDK gives system bars the Liquid Glass treatment. Sylvia's chrome is its own opaque component per Section 4.4.7, so that change does not reach Sylvia's screens; any system surface Sylvia still presents (menus, alerts, share sheets) follows the system.
- Results on iOS 26.0 through 26.4 are untested; the 26.5 runtime is the closest available.

## Alternatives considered

- **Keep iOS 18+ and macOS 14+.** Rejected by the product owner: it needs extra runtimes for testing, availability checks around newer APIs, and a floor that cannot be tested on any device here.
- **iOS 27+ only.** Smaller matrix, but it would exclude users on iOS 26 for no feature the plan requires.

## Open items

- Product owner: confirm Xcode 27.0 (27A266a) is the non-beta release to pin.
- Product owner: an iPhone 12-class device and an iPad for G0.6 and the device matrix.
