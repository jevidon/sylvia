# ADR-0002: Repository, build and CI conventions

- **Status:** Accepted for Stage 0 (product owner approved the defaults on 6 October 2026); revisit at the M0 gate. Amended at M0 integration on 13 October 2026 (dependency inventory pointer, the GRDB row, and the binary-file storage decision below) and at the G0.4 merge on 14 October 2026 (ffmpeg as a host fixture tool under Tooling; G0.4's final evidence images in the binary-file measurement); the amendments are agent-proposed, product-owner approval pending
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
| groue/GRDB.swift | 7.11.1 | Persistence (D02, G0.5 recovery); FTS5 retrieval in the G0.5 AI spike (ADR-0011) |
| pointfreeco/swift-snapshot-testing | 1.19.6 | Design snapshots (T51, T53) |
| apple/swift-nio, swift-nio-ssl, swift-certificates, swift-crypto, swift-asn1 | 2.103.0, 2.37.5, 1.21.0, 5.0.0, 1.7.3 | Candidate stack for the Mac source service and certificate generation (G0.2 decides) |

Readium 3.11.0 brings its own transitive dependencies (among them `readium/ZIPFoundation`, whose module is `ReadiumZIPFoundation`); they are part of the lock and the license inventory. The complete lock after M0 integration, with every transitive package and its license read from the pinned checkout (including swift-nio's swift-atomics 1.3.1, swift-collections 1.7.1 and swift-system 1.8.1, and the BoringSSL that swift-nio-ssl vendors), is ADR-0014.

**Simulators.** Every job creates and uses its own named simulator (`Scripts/lib/sim.sh`), so parallel jobs never share one. The default is an iPhone 17 on the iOS 26.5 runtime. The paired physical iPhone is used only in serialized device runs.

**CI.** `Scripts/ci.sh` runs each executable drop-in in `Scripts/ci.d/` in name order and writes logs to `.build/ci-logs/`. Workstreams add their own numbered drop-in rather than editing shared files. GitHub Actions (`.github/workflows/ci.yml`) runs the same script on a macOS runner. Because macOS runner minutes are billed on a private repository, the workflow runs only on manual dispatch (with an optional list of drop-in filters), and the local script is the primary gate during Stage 0. The workflow refuses to run on a runner without the pinned Xcode build rather than silently using another one.

**Tooling.** Python contract and lint tooling runs from a shared virtualenv (`$SYLVIA_TOOLS_VENV`, default `~/Library/Caches/SylviaTools/venv`), installed from the pinned `Scripts/tools/requirements.txt` by `Scripts/tools/bootstrap.sh`. The G0.4 audio fixtures also need ffmpeg and ffprobe 8.1.x from Homebrew, built with libmp3lame, libopus and AudioToolbox (8.1.2 on the build Mac), and macOS `afconvert`: `Scripts/fixtures/generate-g04-audio-fixtures.sh`, `generate-g04-audio-long-formats.sh` and `generate-g04-audio-probes.sh` encode the fixtures with them, and `Scripts/ci.d/60-g04-audio.sh` decodes the exported excerpts with ffmpeg for its portability check. ffmpeg is a host tool only: it is not linked into or bundled with any target and is not a package dependency (ADR-0014). Each generator records the ffmpeg and macOS versions in its stamp and regenerates its fixtures when either changes, so another ffmpeg build can give other digests than the committed generation logs (`Docs/Stage0/evidence/G04-Audio/fixture-generation*.log`).

**Fixtures.** Small public-domain fixtures are committed under `Fixtures/`. Large ones are downloaded or generated into `$SYLVIA_FIXTURE_CACHE` (default `~/Library/Caches/SylviaFixtures`) by `Scripts/fixtures/fetch.sh` (SHA-256 pinned) and `Scripts/fixtures/generate-*.sh`. Provenance is in `Fixtures/LICENSES.md`.

**Branches.** One branch and one pull request per milestone (`m0`, `m1`, ...), merged after the milestone's exit review.

**Evidence.** Every Stage 0 claim names the command that produced it and the environment it ran in (host, simulator runtime and device type, or physical device and OS). Anything that needs a device or a person and has not been run is recorded as pending in `Docs/Stage0/`. Human sign-offs (security, QA, design) that were stood in for by review agents are marked "agent-reviewed; human sign-off pending".

**Binary test baselines and evidence images (M0 integration, 13 October 2026).** Snapshot reference PNGs and Stage 0 evidence images stay in plain git for now. Git LFS is deferred, not rejected.

- *Measured* (`Docs/Stage0/evidence/M0-Integration/binary-files.tsv`, written by `commands/measure.sh` beside it, read with git from all eight gate branches including `m0-g04-audio`): 786 binary files, 65,265,478 bytes. Of these, 762 are PNG (64,437,948 bytes, largest 450,701): 527 snapshot references in `Packages/Design/Tests/SylviaDesignSnapshotTests/__Snapshots__/` (37,703,582 bytes, largest 368,357) and 235 evidence images under `Docs/Stage0/evidence/` (26,734,366 bytes: G0.6 198, G0.1 PDF 20, G0.1 EPUB 11, G0.4 6). The rest are generated fixtures (17 EPUB, 3 PDF that git detects as binary, 1 SQLite database, 3 DER certificates; 827,530 bytes). Already in plain git before M0: `Docs/Design/images` (25 PNG, 5,953,264 bytes) and `Fixtures/` (6,782,114 bytes including `LICENSES.md`). *At the G0.4 merge* (14 October 2026) G0.4's final commit adds 12 evidence images (1,259,167 bytes, largest 222,609), not the 6 read at `943d5e7`, and no other binary file, so the eight gates add 792 binary files (66,082,214 bytes): 768 PNG (65,254,684 bytes, largest still 450,701), of which 241 are evidence images (27,551,102 bytes; G0.4 12) and the same 527 are snapshot references (`Docs/Stage0/evidence/M0-Integration/g04-binary-files.txt`, written by `commands/g04-binary-files.sh` beside it from the `m0-integrate` history). Every G0.4 image is under `Docs/Stage0/evidence/`, so the evidence pattern in step (1) below covers it.
- *Why not now.* On the build Mac, git-lfs 3.7.1 is installed but not set up: `git config --show-origin --list` shows no `filter.lfs.*` setting at the system (`/opt/homebrew/etc/gitconfig`) or repository level, and there is no user `~/.gitconfig`. With a `.gitattributes` rule in place, every checkout made on this Mac (each parallel agent's worktree, and the clean verification run that follows integration) would contain small pointer files instead of PNGs, so the snapshot suite would fail and the evidence images would be unreadable until the owner runs `git lfs install`, which writes the user's global git configuration. That is the owner's action, not an agent's, and many agents work from worktrees of this repository at once.
- *Cost of waiting.* PNG data does not delta-compress, so every committed version stays in history at about its full size: the 65 MB above already does, a full re-record of the snapshot references adds about 37 MB, and a G0.6 evidence refresh about 21 MB. LFS helps only from the commit that adopts it.
- *Trigger and steps.* Adopt LFS before the first re-record of the snapshot references after M0 (the first token value change) or before `m0` is first pushed, whichever comes first, once the owner has run `git lfs install` on every Mac that builds Sylvia: (1) a `.gitattributes` with `Packages/**/__Snapshots__/**/*.png filter=lfs diff=lfs merge=lfs -text` and `Docs/Stage0/evidence/**/*.png filter=lfs diff=lfs merge=lfs -text` (`Docs/Design/images` and `Fixtures/` stay plain; the evidence pattern also covers G0.4's images); (2) `git add --renormalize` of those paths in a dedicated commit; (3) a CI drop-in that runs first and fails with a clear message if a tracked file matching those patterns is still an LFS pointer, so the snapshot suite never fails confusingly; (4) `lfs: true` on the checkout step in `.github/workflows/ci.yml`. Rewriting the unpushed history with `git lfs migrate import` would also keep the earlier copies off GitHub, but it changes every commit SHA that parallel branches start from, so it is a separate owner decision.
- *Push-time cost once adopted.* LFS objects count against the owner's GitHub account LFS storage and bandwidth quotas (not verified here, so no figures are given). Old versions stay in LFS storage until purged, and each CI run with `lfs: true` downloads the current set, about 65 MB after the G0.4 merge.

## Consequences

- Generated projects cannot drift from `project.yml`, and package versions cannot drift silently.
- A clean clone needs XcodeGen, Python 3 and network access for package and fixture downloads, and Homebrew ffmpeg for the G0.4 audio fixtures.

## Alternatives considered

- **Commit `.xcodeproj` bundles.** Rejected: merge conflicts across parallel workstreams and drift from intent.
- **Tuist.** Not installed; XcodeGen covers the need with less machinery.
- **SwiftLint for design literals.** Not installed; a small purpose-built script checks exactly the Section 4.4.9 rules.
