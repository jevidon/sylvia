# Sylvia

Local-first iOS/iPadOS reading, listening and knowledge app with a lightweight Mac companion. The specification is `Docs/Sylvia_v1_iOS_Implementation_Plan.md` (the plan); the product brief is `Docs/Sylvia_Product_Brief.md`; the visual reference is `Docs/Design/` (where a board and plan Section 4.4 disagree, the plan wins).

Current milestone: **M0, Stage 0 feasibility and design freeze** (plan Section 21.1). Decisions are recorded in `Docs/ADRs/`; gate evidence in `Docs/Stage0/`. Seven gate branches (G0.1 EPUB and PDF, G0.2, G0.3, G0.5 AI and recovery, G0.6) are combined on `m0-integrate`; G0.4 audio is merged later. Every gate still has pending device and human steps, every Stage 0 ADR is Proposed, and the M0 exit review (plan 21.1, 23.3) has not happened. See `Docs/Stage0/integration-log.md`.

## Toolchain

- Xcode 27.0 (27A266a), Swift 6.4, deployment targets iOS/iPadOS 26.0 and macOS 26.0 (ADR-0001).
- Run `source Scripts/lib/env.sh` before using `xcodebuild`, `xcrun` or `swift`. It sets `DEVELOPER_DIR`; never run `xcode-select -s`.
- Packages: `swift-tools-version: 6.2`, Swift 6 language mode, complete strict concurrency, `.iOS(.v26), .macOS(.v26)`.
- Xcode targets come from a `project.yml` (XcodeGen). Do not commit `.xcodeproj`. Use `sylvia_generate <dir>` from `Scripts/lib/xcodegen.sh` and build with `-disableAutomaticPackageResolution`; after changing dependencies run `sylvia_resolve <dir>` and commit `<dir>/Package.resolved` (ADR-0002).
- Use `-derivedDataPath .build/DerivedData` inside the project directory so parallel checkouts never share build products.
- Simulators: create your own with `sylvia_sim_udid <unique-name>` from `Scripts/lib/sim.sh` and target it by `id=`. Never boot, erase or delete a simulator you did not create. Do not use the physical iPhone unless the task explicitly says so.
- Pinned dependency versions are in ADR-0002; the full lock with every transitive package and its license is ADR-0014. One version per package across the repository: changing a version changes every committed `Package.resolved` that holds it, in the same commit. Never add a dependency without recording it in the owning ADR and in ADR-0014.
- Temporary scripts, logs, probe projects and downloads go under `.build/scratch/` in your own checkout (gitignored), never in a shared temporary directory, and never run a file another job left elsewhere.

## Repository conventions

- CI: `Scripts/ci.sh` runs each executable in `Scripts/ci.d/` in name order. Add a numbered drop-in for your workstream instead of editing shared scripts.
- Contracts: follow `Contracts/README.md` (file naming, `urn:sylvia:schema:<name>:v<N>` IDs, valid and invalid fixtures, units, and each contract's owner after M0). Validate with `Scripts/ci.sh contracts`.
- Fixtures: committed ones are in `Fixtures/`, or, when small and generated, beside the test or contract that uses them; every committed fixture has its provenance (source or generator) in `Fixtures/LICENSES.md`. Large ones come from `Scripts/fixtures/fetch.sh` or a `Scripts/fixtures/generate-*.sh` script into `$SYLVIA_FIXTURE_CACHE`; never commit them. Only public-domain, CC0 or generated content.
- Binary files (snapshot references, evidence images, fixtures) are plain git; Git LFS is deferred until the owner sets it up (ADR-0002, which gives the trigger and steps).
- Test audio is quiet. Every test, harness, probe and CI run that plays audio sets the player's volume to 0.01 (AVPlayer or AVQueuePlayer `.volume`, AVAudioPlayerNode or mixer volume) through the test or harness configuration: test setup, a harness launch argument or an injected engine option, never an engine's own default, so product playback stays at full volume. Do not use `isMuted` (a muted AVPlayer renders a different signal after the time-pitch stage at 2x and 3x). `SYLVIA_AUDIBLE_PLAYBACK=1` restores full volume for a person's listening check. Never change the Mac's output volume, mute state or audio device. Evidence states that measurements were taken at test volume.
- Commit messages: one imperative summary line, a blank line, then the why. End with the attribution trailer given in the session.

## Non-negotiable rules (plan Sections 2.2, 22.3)

- Do not change release scope, weaken TLS or certificate validation, add any trust-all path (even temporarily), disable data protection, substitute a web wrapper for native reading, hard-code or commit an API key, or rewrite a dependency to get past a failing test.
- Product UI targets never declare a literal color, font size or status phrase; those come from `Packages/Design` (plan 4.4.9). Stage 0 harness chrome under `Spikes/` is exempt but must not be shipped.
- "Saved" appears only after a durable commit. Nothing claims Ready, Complete or Verified before the state machine says so.
- Never log or persist provider keys, invitation secrets, pairing tokens, selected text, notes or titles outside their intended store. Provider keys come only from environment variables at test time.
- No TODO or stub stands in for a capability a report says works.

## Evidence honesty

- Every claim in a Stage 0 report cites the command that produced it and a log or output file under `Docs/Stage0/evidence/<gate>/`, and names its environment: host, simulator (runtime and device type) or device (model and OS).
- Anything not actually run is **pending**, with the reason. Never infer a device result from the simulator or a human judgment from a test.
- Timings taken while other jobs share the Mac are indicative only: record the load (`uptime`) next to them. If a budget or timing test fails, re-run it before concluding anything, never relax a budget to make it pass, and report a budget that fails only under parallel load as such.
- Physical-device and human steps go in `Docs/Stage0/device-checklists/` as numbered steps with the expected result and how to record it.
