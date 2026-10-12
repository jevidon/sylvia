# ADR-0014: Dependency lock and license inventory

- **Status:** Proposed (M0 integration, 13 October 2026). G0.4 audio is not merged yet; its dependencies, if any, are added when it is.
- **Date:** 2026-10-13
- **Deciders:** pending (technical lead for the lock; release owner for the licenses). Prepared by the M0 integration agent: agent-reviewed, human sign-off pending.
- **Plan references:** Sections 6.3, 21.1 (G0.5: "confirm exact dependency/toolchain versions and license/security posture"), 21.2 (M0 dependency lock), 22.2 (CI verifies package licenses); ADR-0002 (pinning rules)

## Context

ADR-0002 pins every third-party package exactly, commits each project's and package's `Package.resolved`, and defers the full inventory, transitive packages included, to this record. Each gate recorded its own packages in its ADR (ADR-0003, 0004, 0008 to 0011, 0013) and asked for them to be consolidated here at the M0 gate.

## Decision

**The lock.** The dependency lock is the set of committed `Package.resolved` files, 13 on this branch: `Apps/DesignCatalog`, `Packages/Design`, `Spikes/G01-EPUB`, `Spikes/G01-EPUB/Core`, `Spikes/G02-Transfer/SourceService`, `Spikes/G02-Transfer/TransferKit`, `Spikes/G03-Intake/App`, `Spikes/G03-Intake/IntakeKit`, `Spikes/G03-Intake/ZipEval/Readium`, `Spikes/G03-Intake/ZipEval/Upstream`, `Spikes/G05-AI`, `Spikes/G05-AI/ATSProbe`, `Spikes/G05-Recovery`. Together they pin 23 packages, and no package appears at two versions or revisions anywhere in the repository. One version per package across the repository is the rule from now on: a change to a package's version changes every lock that holds it, in the same commit.

**The inventory.** Licenses were read from the license file of a checkout at the exact pinned revision (evidence below), not from package metadata. "Role" says how the package is used at M0; everything is still Stage 0 spike or test code, so "product candidate" means the owning ADR proposes it for the product.

| Package | Version | Revision | License (from the pinned checkout) | Role | Locks | Owning ADR |
| --- | --- | --- | --- | --- | --- | --- |
| readium/swift-toolkit | 3.11.0 | `d82f44f4f05d` | BSD-3-Clause | Product candidate (EPUB); products ReadiumShared, ReadiumStreamer, ReadiumNavigator only | G01-EPUB | 0004 |
| readium/ZIPFoundation (module `ReadiumZIPFoundation`) | 3.0.1 | `adb49c8bfe06` | MIT | Product candidate: linked through Readium, and a direct dependency of IntakeKit for `.sylviapack` and the later backup archive | G01-EPUB, G03-Intake App, IntakeKit, ZipEval/Readium | 0004, 0010 |
| readium/Fuzi (`ReadiumFuzi`) | 4.0.1 | `173ec944ca6f` | MIT | Linked through Readium | G01-EPUB | 0004 |
| scinfu/SwiftSoup | 2.13.9 | `18b80329749e` | MIT | Linked through Readium; direct dependency of the EPUB sanitizer (`Spikes/G01-EPUB/Core`) | G01-EPUB, G01-EPUB/Core | 0004 |
| krzyzanowskim/CryptoSwift | 1.10.0 | `f2a627b84c1f` | zlib-style (CryptoSwift license) | Linked through Readium | G01-EPUB | 0004 |
| ra1028/DifferenceKit | 1.3.0 | `073b9671ce2b` | Apache-2.0 | Linked through Readium | G01-EPUB | 0004 |
| marmelroy/Zip | 2.1.2 | `67fa55813b9e` | MIT; bundles Minizip (zlib license, per its source headers) | Linked through Readium | G01-EPUB | 0004 |
| readium/GCDWebServer | 4.0.1 | `584db89a4c3c` | BSD 3-clause style (three conditions, Pierre-Olivier Latour) | Resolved only, not linked (adapter product unused) | G01-EPUB | 0004 |
| stephencelis/SQLite.swift | 0.16.0 | `964c300fb073` | MIT | Resolved only, not linked (LCP adapter unused) | G01-EPUB | 0004 |
| groue/GRDB.swift | 7.11.1 | `b83108d10f42` | MIT | Product candidate (persistence); FTS5 retrieval in the G0.5 AI spike | G05-Recovery, G05-AI, G05-AI/ATSProbe | 0003, 0011 |
| pointfreeco/swift-snapshot-testing | 1.19.6 | `28e5de025e3f` | MIT | Test only (`SylviaDesignSnapshotTests`); never linked into the library | Packages/Design, Apps/DesignCatalog | 0013 |
| pointfreeco/swift-custom-dump | 1.7.3 | `4fb9e7cbb4b8` | MIT | Test only (transitive of swift-snapshot-testing) | Packages/Design, Apps/DesignCatalog | 0013 |
| pointfreeco/swift-issue-reporting | 2.1.1 | `75b000cea2ca` | MIT | Test only (transitive of swift-snapshot-testing) | Packages/Design, Apps/DesignCatalog | 0013 |
| swiftlang/swift-syntax | 604.0.0 | `050f1a346fbb` | Apache-2.0 with Runtime Library Exception | Test only (transitive of swift-snapshot-testing) | Packages/Design, Apps/DesignCatalog | 0013 |
| apple/swift-nio | 2.103.0 | `21de5f08c1a1` | Apache-2.0 (NOTICE file) | Mac source service only | G02 SourceService | 0009 |
| apple/swift-nio-ssl | 2.37.5 | `322f3c2a4a21` | Apache-2.0 (NOTICE file); vendors BoringSSL, which its NOTICE lists under the combined ISC and OpenSSL license | Mac source service only | G02 SourceService | 0008, 0009 |
| apple/swift-certificates | 1.21.0 | `ff86b924ead6` | Apache-2.0 (NOTICE file) | Mac source service only (self-signed identity) | G02 SourceService | 0008 |
| apple/swift-crypto | 5.0.0 | `a9d1d5ab8951` | Apache-2.0 (NOTICE file) | Mac source service only (P-256 identity key). The checkout also contains a vendored BoringSSL copy (`Sources/CCryptoBoringSSL`); whether the Mac build links it was not checked here | G02 SourceService | 0008 |
| apple/swift-asn1 | 1.7.3 | `3b6410f7dee0` | Apache-2.0 (NOTICE file) | Shared transfer core, iOS and macOS (SPKI pin extraction) | G02 TransferKit, SourceService | 0008 |
| apple/swift-atomics | 1.3.1 | `0442cb5a3f98` | Apache-2.0 with Runtime Library Exception | Transitive of swift-nio; Mac only | G02 SourceService | 0009 |
| apple/swift-collections | 1.7.1 | `98ef3c98609a` | Apache-2.0 with Runtime Library Exception | Transitive of swift-nio; Mac only | G02 SourceService | 0009 |
| apple/swift-system | 1.8.1 | `869129b7bf4e` | Apache-2.0 with Runtime Library Exception | Transitive of swift-nio; Mac only | G02 SourceService | 0009 |
| weichsel/ZIPFoundation | 0.9.20 | `22787ffb59de` | MIT | Evaluation only (`Spikes/G03-Intake/ZipEval/Upstream`); not used by IntakeKit or any app, and cannot share a graph with Readium (same package identity) | ZipEval/Upstream | 0010 |

Every license above is permissive. None is copyleft. Distribution obligations to carry into the release checklist: reproduce the copyright notices and license texts (BSD, MIT, zlib-style, ISC/OpenSSL for BoringSSL) in the app's and the Mac companion's acknowledgements, and include the NOTICE contents of the Apache-2.0 packages that ship one. Test-only and resolved-only packages ship in no build.

**Not a package, also third-party.** Literata 3.103 (SIL Open Font License 1.1), bundled in `Packages/Design`; provenance and digests in `Fixtures/LICENSES.md`.

## Evidence

All on the **host** (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.0 (27A266a), XcodeGen 2.46.0), at M0 integration, under parallel load from other agents (load averages 13 to 16; resolution timings are not budgets).

- `Docs/Stage0/evidence/M0-Integration/package-locks.log`: every Xcode project was regenerated with `sylvia_generate` and resolved with `xcodebuild -resolvePackageDependencies -disableAutomaticPackageResolution`; every Swift package with `swift package resolve --force-resolved-versions`. All 17 resolved, and no committed `Package.resolved` changed.
- `Docs/Stage0/evidence/M0-Integration/license-inventory.log`: for each of the 23 pinned packages, a checkout whose `HEAD` equals the pinned revision, its license file and the file's opening lines.

## Consequences

- The license check that plan 22.2 asks CI to run can start from this table: a CI step that lists the pins of every committed `Package.resolved` and fails on a package missing here is a small addition (not done at integration).
- Two Stage 0 Xcode projects have no committed lock: `Spikes/G02-Transfer/iOS` and `Spikes/G02-Transfer/MacIdentityProbe`. Each depends only on a local package, so Xcode writes no lock for it. For the iOS project the only remote package, swift-asn1, is fixed by TransferKit's `exact:` requirement. For MacIdentityProbe, SourceService's direct packages are `exact:`, but swift-atomics, swift-collections and swift-system are reached through swift-nio's version ranges and are not pinned for that project: today they resolve to the same versions as `SourceService/Package.resolved`, but a fresh resolution after a new release could pick newer ones. MacIdentityProbe is a signed probe that the G0.2 CI drop-in lists as not run when the Mac cannot sign for the team. Open item below.

## Alternatives considered

- **Keep the inventory spread across the gate ADRs.** Rejected: the plan asks for one dependency lock at M0, and transitive packages had no owner.

## Open items

- G0.4 audio: add its packages (if any) when `m0-g04-audio` is merged. Owner: the agent that merges it.
- `Spikes/G02-Transfer/MacIdentityProbe`: pin swift-atomics, swift-collections and swift-system for the project (for example by committing a lock next to `project.yml`), or record why not. Owner: G0.2 transfer.
- A CI license step (above). Owner: M1 foundation.
- Release owner: approve the licenses and produce the acknowledgements text before any distribution.
