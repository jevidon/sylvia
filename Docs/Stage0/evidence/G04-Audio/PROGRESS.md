# G0.4 audio: progress (for the next agent)

**State: review rounds 1 to 5 fixed; complete for Stage 0 on the simulator; device run pending.** Report
`Docs/Stage0/G04-Audio.md`, ADR-0006, ADR-0007, device checklist `Docs/Stage0/device-checklists/G04-Audio.md`.

Branch `m0-g04-audio`. Simulator `Sylvia-M0-g04-audio` (iPhone 17, iOS 26.5). The CI drop-in
`Scripts/ci.d/60-g04-audio.sh` does everything (fixtures, generate, signed device build, simulator build, tests,
process-kill trial, ffmpeg portability, the quick-capture App Shortcut through the Shortcuts app and the control
through Control Center) and fails on any test failure, build warning, missing result table or missing quick-capture
result; `G04_SKIP_REALAV=1` runs only the fast unit suites;
`G04_DEVICE_FIXTURES=1` also builds and verifies the 8.6 GB device bundle with the fixtures; it samples the host's
load every 30 s (`host-load.tsv`) and shuts its simulator down on exit (`G04_KEEP_SIM=1` keeps it). Tests write
TSV/TXT results to `$G04_RESULTS_DIR` (relative paths are taken from the repository root). Every test, probe and
harness launch plays at 1 % volume unless `SYLVIA_AUDIBLE_PLAYBACK=1` (the Mac's speakers are shared; see "Quiet runs"
below).

## Verified

- Clean CI run from deleted DerivedData after the round-5 fixes (quiet output, with `G04_DEVICE_FIXTURES=1`): see
  the header of `ci-clean-run.log` (commit, times, exit codes, host load at the start and end); result tables in
  `results/`. `Scripts/ci.sh contracts` in the same log. After the run only documents, evidence and one comment line in `Spikes/G04-Audio/project.yml` changed. The clean
  runs of rounds 4 and 3 have their tables at commits `5d85b1f` and `943d5e7`; a targeted round-4 budget run under
  heavier load is `budgets-round4-targeted-run.txt`.

## Quiet runs (product-owner request, round 3)

- Tests create every player through `Tests/G04AudioTests/Support/TestAudio.swift` (volume 0.01 unless
  `SYLVIA_AUDIBLE_PLAYBACK=1`); the drop-in fails if a test file creates a player any other way (marker
  `full-volume-by-design` for the test of the engines' default). The harness starts at 1 % with a full-volume toggle
  (persisted; `-g04AudiblePlayback YES|NO` overrides it per launch) and logs an `output volume=...` line at launch;
  the process-kill trial and the quick-capture script pass `-g04AudiblePlayback NO` and fail unless every launch
  logged `volume=0.01`. The engines default to full volume (`AudioOutputTests`).
- Not `isMuted`: a muted AVPlayer rendered a different signal after the time-pitch stage at 2x and 3x (1 kHz tone
  measured about 665 and 351 Hz), which broke `rateAndPitch`; 1 % (accepted by the product owner) and volume 0 did
  not (`audio-output.txt`, `MutedRenderingTests`).

## Review round 5 (all findings R5-01 to R5-08 addressed)

- R5-01: the control path runs on the simulator. UI test `QuickCaptureThroughControlCenterUITests` (scheme
  `G04QuickCaptureUI`) opens Control Center from SpringBoard, removes earlier copies, adds "Capture the last 30
  seconds" from the controls gallery, reopens Control Center and presses it; `quick_capture_simulator_attempt.sh` runs
  it after the App Shortcut test, for the ad-hoc and the team-signed build. Result: `chronod` performs the control's
  intent in the playing app's process in both; the `surface` parameter arrives only with the team-signed build (ad
  hoc: AppEnum case "to-0.0", `CaptureSurface(nil)`, origin `intent@`).
- R5-02: `PlaybackService.load` ends the outgoing edition first (`leaveCurrentEdition`): a running preview stops, the
  outgoing edition's checkpoint (`editionChange`) is its saved main point, the session is released. Tests:
  `PlaybackServiceTests` (2), `RealPreviewTests.loadingAnotherEditionDuringPreview` (`preview-load-edition.txt`).
- R5-03: `MemberOrdering` reports absent tracks as ranges (`absentRanges`), bounded by the number of files.
- R5-04: ADR-0007 decision 4 says class C exactly, with the trade-off; the excerpt exporter sets class C on the
  finished excerpt (injectable `applyProtection`, `ExcerptProtectionTests`); stores create class-C directories; the
  harness logs `excerpt_protection=` (checklist step 9).
- R5-05: `long-formats-open.tsv` has 3 precise trials per file (median), the UTC time and the 1-minute load at each
  row's start and end; the remux rows record the load too; the documents state the length thresholds with the load.
- R5-06: the quick-capture script fails unless the control's capture is saved in the app's process (both builds) and,
  team-signed, the App Shortcut's `origin=intent@<app>` and the control's `origin=intent.control@<app>`.
- R5-07: stale "precise timing is mandatory" comments corrected (LongFileTests, LongFormatTests).
- R5-08: `Scripts/fixtures/generate-g04-audio-probes.sh` and `ContainerProbeTests` (`container-probes.txt`): the
  two-digit `CHAPTER01` form is not read, three digits from 001 or 000 are; MP3 packets are refused in MPEG-4 (.m4a
  and .mp4) and taken in CAF. `fixture-generation-long-formats.log` has a provenance header; row 32 points at G0.5 AI's
  T24.

## Review round 4 (all findings R4-01 to R4-05 addressed)

- R4-01: per-file timing mode (ADR-0006 decision 2). `MP3FrameScanner` proves a constant bit rate at import (every
  frame header walked; one bit rate, sample rate, version, layer and channel count, contiguous to the end of the
  audio or an APEv2/ID3v1 tag; `Info` tag with a matching frame count, or no tag; `Xing`/`VBRI` never; duration
  within three frames of AVFoundation's precise one). `AssetTiming` is stored with the member
  (`EditionMember.timing`) and carried by `EngineItem`, `PreviewSegment` and `SourceSegment`
  (`CaptureService(resolveTiming:)`); the harness uses the import's decision and logs `member ... timing=` lines.
  Evidence: `mp3-cbr-detection.tsv`, `estimated-timing-decoder.tsv`, `estimated-timing-capture.tsv`, the
  `estimatedCBR` rows of `budgets.txt`, both blocks of `real-engine-boundary.txt` and `real-engine-seek-rate.txt`;
  `MP3FrameScannerTests`, `PerFileTimingTests`. The remux (decision 17) now covers only VBR MP3, native FLAC and
  Ogg Opus.
- R4-02: timing tables record the host's load (start and end; `load_1m` per trial); the drop-in samples
  `host-load.tsv`; the clean-run header records `uptime` and booted simulators. Precise MP3 cold resume is asserted
  only up to 0.33 h; depth claims for precise MP3 are stated as load-dependent and indicative.
- R4-03: remote commands during a preview: pause and play/pause stop it (`PlaybackService.stopPreview`, the book
  restored paused, the session released), play is accepted, navigation is disabled and refused with
  `.commandFailed`; Now Playing shows the preview; every command's status is truthful (`NowPlayingController.handle`);
  `RemoteCommandTests`; the harness logs `remote` lines; checklist step 7.3.
- R4-04: the drop-in shuts down its simulator on exit, whether it passed or failed.
- R4-05: the fake engine ticks at every multiple of 0.5 s of media (as the real engine); the 3x checkpoint gap is
  asserted at 4.0-4.5 s and the fake crash loss at 4.5 s; the codec-matrix comment points at checklist step 1.
- Gate gap (device bundle): `G04_DEVICE_FIXTURES=1` builds the configuration checklist step 1 installs and checks
  every bundled fixture's SHA-256 and the signatures (`device-build-fixtures.txt`; run in the clean run).

## Review round 3 (all findings R3-01 to R3-06 addressed)

- R3-01: long (3 h and 10 h) fixtures of every provisional format (`Scripts/fixtures/generate-g04-audio-long-formats.sh`;
  native FLAC with a 10 s seek table); `LongFormatTests` measures open time against length, cold resume by depth,
  export and pending-preview start deep in each file, and remuxing native FLAC and Ogg Opus into MPEG-4 and MP3 into CAF at import
  (`ImportRemuxer`). The engine waits for an item with no time limit and the service reports `.preparing` while a
  member opens (a slow open is never a decode error; `PreparingStateTests`).
- R3-02: the MP3 cold-resume sweep runs every depth in 3 rounds; the crossing is reported as a range.
- R3-03: stale comments fixed; the deep-MP3 known issues are no longer marked intermittent (recorded whenever a miss
  occurs); table count corrected.
- R3-04: the in-player Capture button passes its own idempotency key per tap.
- R3-05: the drop-in builds the test bundle for a generic iOS device with automatic signing and records each
  product's signature (`device-build-signing.txt`).
- R3-06: ADR-0006's row for MP3 VBR without Xing notes the stall; checklist step 1.3 asks for every stall row.

## Review round 2 (all findings R2-01 to R2-07 addressed)

- R2-01: cold resume measured by depth into the file (0.33-10 h in the 10-hour files, plus the LibriVox section MP3
  and a multi-file book member); the start/resume budget is reported in terms of depth into an MP3 member (crossed
  at about 1.4-1.6 h on the simulator), whether the book is one file or many.
- R2-02: listening time counts wall time only while the media advances (`PlaybackService.accountProgress`); the
  soak compares it with the wall time from the first audio.
- R2-03: device checklist step 9 lists the capture line's fields separately and quotes the printed
  `NSURLFileProtectionCompleteUntilFirstUserAuthentication`.
- R2-04: a failed quick capture shows the proposed key `[audio.moment_not_saved]`, not `save.failed`.
- R2-05: the control sets the intent's optional `surface` parameter (`origin=intent.control@...`); the repeat window
  is per origin.
- R2-06: the audio session is released with `notifyOthersOnDeactivation` when playback stops for good (not after an
  interruption or headphone removal); harness logs `session` lines; checklist step 15.6-15.7.
- R2-07: pending-preview boundaries measured in all 16 provisional formats (`preview-end-formats.tsv`); tables name
  the build configuration; checklist step 1.5 (Release budgets) and a Release harness (step 2.1), both checked on
  the simulator (`release-build-simulator.txt`); T18 background-work check in step 3.

## Review round 1 (all findings R1-01 to R1-12 addressed)

- R1-01: cold resume deep in 10-hour files measured in `budgets.txt`; the start/resume budget is reported failed for
  long single-file MP3.
- R1-02: furthest position adopts a run that started ahead of the frontier after 30 s of contiguous listening
  (`PlaybackService.frontierAdoptionMs`; ADR-0006 decision 9).
- R1-03: results path made absolute, tables checked for presence and freshness, write failures are test failures.
- R1-04: two-hour-of-media soak at 3x on the real engine (`soak.txt`); row 3 renamed "long files".
- R1-05: interrupted (stale pending) exports resumed at launch; Retry offered when no export runs.
- R1-06: pending cross-file preview plays every range (AVQueuePlayer, `forwardPlaybackEndTime` per item).
- R1-07: device checklist step 15 (other app's audio during import, capture, export).
- R1-08: in-process crash simulation described as such; real SIGKILL trial on the simulator
  (`process-kill-relaunch.txt`); device step 16.
- R1-09: chapters written in every container that can carry them; the real 22.05 kHz MPEG-2 LibriVox MP3 in the matrix.
- R1-10: excerpts store each range's source format; the proposed anchor includes the asset digest (not in the spike's
  record).
- R1-11: device tables pulled from the app container instead of the console; step 9.5 failure signal corrected.
- R1-12: test stores removed after each test; `willTerminate` checkpoint; append-only harness log; repeat window
  against duplicate intent deliveries; run time documented from the clean run.
- Gate gap "App Shortcut through the system": UI test in the Shortcuts app; performed in the app process with a
  team-signed build, refused with an ad-hoc build (`quick-capture-simulator-*.txt`).

## Next (outside this workstream)

- Serialized device run: checklist steps 1-16.
- Integration: shared changes listed in the workstream result (LICENSES entry for the generated fixtures, ffmpeg in
  ADR-0002, vocabulary keys `audio.nothing_to_capture` and `audio.moment_not_saved`).

## Known problems / findings

- A constant-bit-rate MP3 opened with the per-file timing mode resumes cold in 0.14-0.15 s at every depth to 10 h.
- Cold resume in an MP3 on precise timing (VBR, or CBR without the per-file mode) takes about 1 s per hour of depth
  into the file, more under host load, and misses the 1.5 s budget beyond about 1.0-1.8 h into the file (0.41-1.52 h
  in the round-4 review's run at load averages of 60-148).
- Opening a native FLAC, an MP3 without a header or an Ogg Opus file scans it (about 2.8-3.4, 0.8-1.0 and
  0.09-0.16 s per hour of file over three runs): long files of those formats miss the budget at every depth (Ogg
  Opus at 10 h at the edge). MPEG-4, CAF and WAV are fast at every depth. The import remux (ADR-0006 decision 17)
  removes both costs for the files that stay precise; it needs product-owner approval.
- Where the process had just read a whole MP3 (the import's frame scan) before its first precise seek, the seek was
  fast (0.18-0.35 s at 5-10 h instead of several seconds); not measured as a mitigation.
- Export time from a cold deep MP3 and the remux time vary several-fold between runs (cause not isolated).
- The analysis tap processes whole buffers past a preview's end (363-775 ms of digital silence, depending on the
  sample rate); the per-format preview test judges the end by the audible content, not by that overrun.
- One intermittent player stall in a VBR MP3 without Xing header (`intermittent-player-stall.txt`), not reproduced.
- Quick capture on the simulator needs a team-signed build for full evidence: the ad-hoc build refuses the App Shortcut
  and loses the control's `surface` parameter (the control's intent still runs in the app process and saves).
- Open times of native FLAC, MP3 without a header and Ogg Opus grow with the host's load as well as with the file's
  length; the round-5 review saw a 10-minute native FLAC take 2.65 s to open during a load spike.
- The analysis tap sees pre-roll buffers and trailing silence; the probes measure the first continuous second and
  check that post-end audio is silent.
