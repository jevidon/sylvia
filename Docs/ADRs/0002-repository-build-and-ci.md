# ADR-0002: Repository, build and CI conventions

- **Status:** Accepted for Stage 0 (product owner approved the defaults on 6 October 2026); revisit at the M0 gate
- **Date:** 2026-10-06
- **Deciders:** Justin Evidon (product owner)
- **Plan references:** Sections 22.1-22.3; Appendix C

## Context

Section 22 asks for a monorepo, pinned dependencies, CI that lints contracts and design literals, and reproducible Stage 0 evidence. Several workstreams run in parallel, so conventions must keep their files apart.

## Decision

**Layout.** As Section 22.1, plus `Spikes/` (Stage 0 harnesses: evidence code that is never shipped and is not a product UI target), `Scripts/` and `Docs/Stage0/` (gate reports and physical-device checklists).

**Xcode projects.** Each app, extension or spike with an Xcode target has a `project.yml` for XcodeGen 2.46.0. Generated `.xcodeproj` bundles are not committed. Each project's package lock is committed as `Package.resolved` next to its `project.yml`; `sylvia_generate` (`Scripts/lib/xcodegen.sh`) installs it into the generated project, and builds pass `-disableAutomaticPackageResolution` so they use exactly the locked versions. Pure Swift packages commit their own `Package.resolved`.

**Dependencies.** Third-party code is limited to what the plan needs. Each package is pinned to an exact version, justified in the ADR of the workstream that needs it, and listed with its license in the inventory produced at the M0 gate (ADR-0014). The pinned set at kickoff (latest releases on 6 October 2026):

| Package | Version | Needed for |
| --- | --- | --- |
| readium/swift-toolkit | 3.11.0 | EPUB (D02, G0.1) |
| groue/GRDB.swift | 7.11.1 | Persistence (D02, G0.5 recovery) |
| pointfreeco/swift-snapshot-testing | 1.19.6 | Design snapshots (T51, T53) |
| apple/swift-nio, swift-nio-ssl, swift-certificates, swift-crypto, swift-asn1 | 2.103.0, 2.37.5, 1.21.0, 5.0.0, 1.7.3 | Candidate stack for the Mac source service and certificate generation (G0.2 decides) |

Readium 3.11.0 brings its own transitive dependencies (among them `readium/ZIPFoundation`, whose module is `ReadiumZIPFoundation`); they are part of the lock and the license inventory.

**Simulators.** Every job creates and uses its own named simulator (`Scripts/lib/sim.sh`), so parallel jobs never share one. The default is an iPhone 17 on the iOS 26.5 runtime. The paired physical iPhone is used only in serialized device runs.

**CI.** `Scripts/ci.sh` runs each executable drop-in in `Scripts/ci.d/` in name order and writes logs to `.build/ci-logs/`. Workstreams add their own numbered drop-in rather than editing shared files. GitHub Actions runs the same script on a macOS runner. Because macOS runner minutes are billed on a private repository, the workflow runs on pull requests and manual dispatch, and the local script is the primary gate during Stage 0.

**Tooling.** Python contract and lint tooling runs from a shared virtualenv (`$SYLVIA_TOOLS_VENV`, default `~/Library/Caches/SylviaTools/venv`), installed from the pinned `Scripts/tools/requirements.txt` by `Scripts/tools/bootstrap.sh`.

**Fixtures.** Small public-domain fixtures are committed under `Fixtures/`. Large ones are downloaded or generated into `$SYLVIA_FIXTURE_CACHE` (default `~/Library/Caches/SylviaFixtures`) by `Scripts/fixtures/fetch.sh` (SHA-256 pinned) and `Scripts/fixtures/generate-*.sh`. Provenance is in `Fixtures/LICENSES.md`.

**Branches.** One branch and one pull request per milestone (`m0`, `m1`, ...), merged after the milestone's exit review.

**Evidence.** Every Stage 0 claim names the command that produced it and the environment it ran in (host, simulator runtime and device type, or physical device and OS). Anything that needs a device or a person and has not been run is recorded as pending in `Docs/Stage0/`. Human sign-offs (security, QA, design) that were stood in for by review agents are marked "agent-reviewed; human sign-off pending".

## Consequences

- Generated projects cannot drift from `project.yml`, and package versions cannot drift silently.
- A clean clone needs XcodeGen, Python 3 and network access for package and fixture downloads.

## Alternatives considered

- **Commit `.xcodeproj` bundles.** Rejected: merge conflicts across parallel workstreams and drift from intent.
- **Tuist.** Not installed; XcodeGen covers the need with less machinery.
- **SwiftLint for design literals.** Not installed; a small purpose-built script checks exactly the Section 4.4.9 rules.
