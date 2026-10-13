# G0.4 audio: physical-device checklist

Status of every step: **pending** (not run). Stage 0 agents did not use the physical iPhone; this checklist is for the serialized device run. Nothing here may be inferred from the simulator results.

**Device:** iPhone 17 Pro (iPhone18,1), iOS 26.7 (23H24), Developer Mode on (ADR-0001). Repeat steps 1, 3, 9-13 and 15 on the iPhone 12-class baseline when one is available (it has no Action button: skip step 11 there).

**Accessories:** wired or Bluetooth headphones (step 4), a second phone to place a call (step 5), a Bluetooth speaker or headset (step 6).

## Setup

1. On the build Mac, from the repository root (branch `m0` after integration, or `m0-g04-audio`):

   ```sh
   source Scripts/lib/env.sh; source Scripts/lib/xcodegen.sh
   Scripts/fixtures/fetch.sh
   Scripts/fixtures/generate-g04-audio-fixtures.sh
   Scripts/fixtures/generate-g04-audio-long-formats.sh
   Scripts/fixtures/generate-g04-audio-probes.sh
   sylvia_generate Spikes/G04-Audio
   xcrun devicectl list devices          # note the device identifier: <device-id>
   ```

2. Signing: the project uses automatic signing with team `A4KBDX665Z`. Every `xcodebuild` command below adds `-allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z`. (The CI drop-in already builds the test bundle for a generic iOS device with automatic signing on the build Mac and checks every product's signature, `results/device-build-signing.txt`; what remains for the device is installing and running it.)
3. Device test builds copy the fixtures into the test bundle (about 8.6 GB: the PCM masters, the 10-minute matrix files, the 3- and 10-hour files of every provisional format, the 60 s container probes and the LibriVox M4B; `du -sh ~/Library/Caches/SylviaFixtures/generated/g04-audio` shows the exact size). The phone needs at least 15 GB free; allow for the install time over the cable or network. The CI drop-in builds and signs this exact configuration on the build Mac when run with `G04_DEVICE_FIXTURES=1` and checks every bundled file against the fixture manifests' SHA-256 (`results/device-build-fixtures.txt`); what remains for the device is installing and running it.
4. Sound. The spike's tests and harness play **quietly, at 1 % volume**, unless asked otherwise (product-owner request: the build Mac's speakers are shared). The volume is applied after everything the tests measure, so the automated results are the same at 1 % (`results/audio-output.txt`). Full volume is needed only where a step says **listen**:
   - harness: tap **"Full volume (now quiet, 1 %)"** in the Player section (step 2.4). The button then reads "Quiet playback (now full volume)", the log gets `output volume=1.0 preview_volume=1.0 reason=toggle`, and the setting is kept across launches until you tap it again. A launch with `SYLVIA_AUDIBLE_PLAYBACK=1` in its environment is at full volume too (`xcrun devicectl device process launch ... --environment-variables '{"SYLVIA_AUDIBLE_PLAYBACK":"1"}'`; check the option name with `--help`).
   - automated tests (step 1): nothing needs listening; they stay quiet. To hear them, prefix the `xcodebuild` command with `TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK=1`; every result table's environment line then says `output at full volume (SYLVIA_AUDIBLE_PLAYBACK=1)` instead of `output at 1 % volume (quiet test runs)`.
5. Build configurations (plan 19.1 asks for release builds, not debugger-attached results). `xcodebuild test` builds the Debug configuration (the scheme's test action) and attaches no debugger; every result table names its configuration in its environment line (`..., Debug build` or `..., Release build`; step 1.2 lists where that line is). Step 1.5 repeats the budget measurements in a Release build, and the harness for steps 2-16 is built and installed in the Release configuration and launched without Xcode. Record budget numbers with their configuration; the Release numbers are the ones that count against plan 19.2.

## Recording

- Save every console output and pulled file as plain text under `Docs/Stage0/evidence/G04-Audio/device/`, with the step number in the file name (for example `device/step-01-tests.log`, `device/step-03-harness.log`). Screenshots: PNG under 2 MB.
- In `Docs/Stage0/G04-Audio.md`, change the step's rows from pending-device to passed or failed, with the date, device model and iOS build.
- Never edit an expected result to match what happened. A different result is a failure, recorded as one, with what happened instead.
- The harness log is `Documents/g04-harness.log` in the app container. Pull it with:

  ```sh
  xcrun devicectl device copy from --device <device-id> --domain-type appDataContainer \
    --domain-identifier com.jevidon.sylvia.spike.g04audio \
    --source Documents/g04-harness.log --destination Docs/Stage0/evidence/G04-Audio/device/step-NN-harness.log
  ```

  Capture records are JSON files under `Library/Application Support/G04Harness/Captures/captures/` in the same container (pull them the same way when a step asks for them).

## 1. Automated tests on the device: codec matrix, excerpt timing, long files, real engine, budgets (T18-T23 automated parts)

1. Run:

   ```sh
   xcodebuild test -project Spikes/G04-Audio/G04Audio.xcodeproj -scheme G04AudioHarness \
     -destination "id=<device-id>" -derivedDataPath Spikes/G04-Audio/.build/DerivedData \
     -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z 2>&1 | tee step-01-tests.log
   ```

   On the simulator the tests took about 78 minutes in the clean runs of rounds 4 and 5: the soak test alone plays two hours of media at 3x for 40 minutes, and the 3- and 10-hour files of every format and the cold-resume sweeps take most of the rest. The device may differ. Keep the phone unlocked, on a charger, with auto-lock set to Never for this step. The tests play at 1 % volume (Setup 4); nothing in this step needs listening.
2. On a device the tests write every result table to `Documents/G04Results/` in the test host's (the harness app's) container (`Results.write`; the console copies printed between `=== <name> ===` lines can be interleaved with system log lines, so do not extract them from the log). Pull the tables:

   ```sh
   mkdir -p Docs/Stage0/evidence/G04-Audio/device/step-01
   for t in audio-output.txt audio-session.txt budgets.txt codec-matrix-detail.tsv codec-matrix.tsv container-probes.txt \
            estimated-timing-capture.tsv estimated-timing-decoder.tsv excerpt-timing-cross-file.tsv \
            excerpt-timing-single-file-detail.tsv excerpt-timing-single-file.tsv excerpt-timing-three-formats.txt \
            librivox-m4b.txt long-long-aac-10h.m4b.txt long-long-mp3-cbr-10h.mp3.txt long-long-mp3-vbr-10h.mp3.txt \
            long-formats-open.tsv long-formats-cold-resume.tsv long-formats-capture.tsv long-formats-remux.tsv \
            long-seek-latency.txt mp3-cbr-detection.tsv now-playing.txt preview-end-formats.tsv preview-interruption.txt preview-load-edition.txt preview.txt rate-pitch.txt \
            real-engine-boundary.txt real-engine-error-states.txt real-engine-relaunch.txt real-engine-seek-rate.txt \
            soak.txt t23-source-removal.txt; do
     xcrun devicectl device copy from --device <device-id> --domain-type appDataContainer \
       --domain-identifier com.jevidon.sylvia.spike.g04audio \
       --source "Documents/G04Results/$t" --destination "Docs/Stage0/evidence/G04-Audio/device/step-01/$t"
   done
   head -1 Docs/Stage0/evidence/G04-Audio/device/step-01/*
   ```

   Every pulled file must exist, and its environment line names the device (the first line of most tables; the second of `audio-output.txt`, `long-formats-cold-resume.tsv` and `estimated-timing-capture.tsv`, the third of `long-formats-remux.tsv`, the fourth of `long-formats-capture.tsv`; `codec-matrix-detail.tsv` and `excerpt-timing-single-file-detail.tsv` have no header, their summaries do): it must contain `device iPhone18,1, iOS`, for this step `Debug build`, and `output at 1 % volume (quiet test runs)` unless you ran with `TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK=1`. The timing tables (`budgets.txt`, `long-seek-latency.txt`, the four `long-formats-*.tsv`, the two `estimated-timing-*.tsv`) also print `device load averages ...` at their start (and most at their end), and some a `load_1m` column per trial (`long-formats-open.tsv`: `load_1m_start` and `load_1m_end` per file, with its `utc` time; review R5-05): on the device that is the phone's own load (review R4-02; on the simulator it was the build Mac's). (The simulator-only tables `process-kill-relaunch.txt`, `excerpt-portability.tsv`, `device-build-signing.txt`, `device-build-fixtures.txt`, `host-load.tsv` and `quick-capture-simulator-*.txt` come from host steps of the CI drop-in and are not produced here; the device counterparts are step 16 (process kill) and steps 9-11 (quick capture); the ffmpeg decode is a host check and is not repeated.)
3. Expected:
   - All suites pass, as on the simulator, with the same test count as `ci-clean-run.log`. The portability test ("Excerpts decoded by ffmpeg ...") is skipped by design: it runs only in the CI drop-in's host phase.
   - `codec-matrix.tsv`: every format on the provisional release list (ADR-0006) has verdict `pass`, and the chapter expectations hold; Opus in WebM is `unsupported`. If a listed format fails, or WebM opens, the test fails by design: record the row, then ADR-0006's list changes. This step is what turns the provisional list into the release list.
   - Player stalls (review R3-06): check every format, in particular `mp3-vbr-noxing` (MP3 VBR without a Xing/VBRI header), for a zero-tolerance player seek that produced no audio. Such a seek shows up in the last column (reasons) of its `codec-matrix.tsv` row as `player seek <t>s unmeasurable [... start_latency_s=none ...]` or `no audio at <t>s within 15 s of play`, and an unmeasurable seek has no `player_seek` row in `codec-matrix-detail.tsv` (every format otherwise has three, at 37.3, 333.3 and 587.2 s). That is a stall: on the simulator one codec-matrix run in twelve (review rounds 2 to 5) had two such seeks in that file (`Docs/Stage0/evidence/G04-Audio/intermittent-player-stall.txt`), and the format then fails the matrix. Record every stall row with the format, the seek target and the run number, even if a later run passes; if the matrix fails only because of a stall, repeat step 1.1 once more and record both runs. Two or more stalls of a format across the device runs (1.1 and the repeats of 1.4) remove it from the release list unless the product owner decides otherwise.
   - `excerpt-timing-single-file.tsv`: every row `within_budget = yes` (all errors at most 500 ms).
   - `budgets.txt`: warm start/resume p95 at most 1.5 s; cold resume in the 10-hour AAC M4B at most 1.5 s at every depth (0.33 to 10 h); with the per-file timing mode (the `cold_resume` rows with timing `estimatedCBR`: the 10-hour CBR MP3 at every depth, the LibriVox section MP3 and the book member; ADR-0006 decision 2, review R4-01) at most 1.5 s at every depth, and the line `content error, estimatedCBR minus precise at the same file and depth` with `max_abs` at most 1.0 ms; cold resume in MP3 with precise timing at most 1.5 s at 0.33 h and shallower (both 10-hour MP3s at 0.33 h, the LibriVox section MP3 at 10 minutes, the multi-file book member at 2 minutes); acknowledged capture save p95 at most 200 ms. Every depth is measured in 3 rounds. Record the `import timing decision` lines (the same as on the simulator: `estimatedCBR` for the CBR files, `precise` for the M4B and the VBR MP3), the `budget crossing, long-mp3-*, precise` lines (per round and over the rounds: the depth at which an MP3 cold resume with precise timing reaches 1.5 s), the `by depth` lines and every `cold_resume` row of the two 10-hour MP3s with its `load_1m` (the phone's own 1-minute load average). On the simulator the precise cold resume grew by about 1 s per hour of depth and more under host load, and the crossing lay between about 1.0 and 1.8 h into the file over the runs of rounds 3 to 5 (a known issue in the test). If the device meets the budget at every depth with precise timing, the known issue is not recorded and the test still passes: record that as a finding (it changes ADR-0006 and the report), not as a device failure.
   - The per-file timing mode (review R4-01): `mp3-cbr-detection.tsv` gives the same `timing` in every row as on the simulator (`estimatedCBR` for the eight CBR fixtures and the variants `cbr-no-info-tag.mp3` and `cbr-plus-id3v1.mp3`; `precise`, with the same reason, for the VBR fixtures, the other variants and the non-MP3 files); record `scan_s` of `long-mp3-cbr-10h.mp3` (the import's scan of a 294 MB file on the phone; 0.21 s on the simulator). `estimated-timing-decoder.tsv`: in every `proved-cbr` row `estimated_error_ms` equals `precise_error_ms` within 1 ms (on the simulator the decodes were sample-identical, `sample_diff` 0.000000); record the `estimated-not-chosen` rows (on the simulator every window of the 10-hour VBR MP3 and of the 3- and 10-hour native FLAC files was more than 500 ms off or not found; the test fails if all of a long file's windows land within 500 ms, which would change ADR-0006 decision 2). `estimated-timing-capture.tsv`: every error at most 500 ms in absolute value; record `seconds` of the exports and previews (0.07-0.08 s for a 30 s export and 0.13 s to start a pending preview 9.5 h into the 10-hour CBR MP3 on the simulator). `real-engine-boundary.txt` and `real-engine-seek-rate.txt`: both blocks (`members opened: precise,...` and `members opened: estimatedCBR,...`) pass, with the same content errors.
   - `soak.txt`: content error at most 150 ms every minute, checkpoint gaps at most 5.5 s (wall) and 5,000 ms (media), the first checkpoint within 5.5 s of the first audio, the listening total within 2 s of the wall time from the first audio, memory growth at most 64 MB. Record the `play() to first audio` line (a seek 9.5 h into the 10-hour VBR MP3, which the test's import inspection has just read through: 0.33 s on the simulator in round 5, 0.35 s in round 4, 8.5 s in round 3; report rows 11 and 21).
   - `preview.txt`: head error, seam errors and player end error at most 500 ms.
   - `preview-load-edition.txt` (review R5-02): `preview_playing=false`, `preview_player_rate=0.0`, `preview_items=0`, `preview_tap_chunks_later_than_1s=0`, `session_active=false`, `edition_is_new=true`, and the outgoing checkpoint with `reason=editionChange`, `last` equal to `saved_main_point`, furthest and listened equal to their values before the preview.
   - `container-probes.txt` (review R5-08): the four three-digit probes (`chapters-3digit-001` and `-000`, `.flac` and `.ogg`) read 3 chapters at 0, 20000 and 40000 ms with the titles Opening, Chapter Two, Chapter Three and `last_end_closed_at_duration` 1; the two-digit probes read 0 chapters; each 10-minute MP3 is `refused` in `mpeg4 (.m4a)` and `mpeg4 (.mp4 ...)` and `written` in `caf` with the source's duration. Any other result fails the test by design: record it (it changes ADR-0006: the chapter note, or the remux container for VBR MP3).
   - `preview-end-formats.tsv`: for every format on the provisional list, `head_err_ms`, `end_err_ms` and `player_end_ms` at most 500 ms in absolute value, and `post_end_rms_ratio` below 0.05 (nothing audible past the intended end). `tap_end_overrun_ms` is recorded, not judged: the analysis tap processes whole buffers past the end (363-775 ms on the simulator, digital silence), so a value above 500 ms there is not a failure as long as `post_end_rms_ratio` is below 0.05.
   - Long files of every provisional format (review R3-01; on the simulator: report rows 3 and 33, ADR-0006 decision 2 and its table). `long-formats-open.tsv`: every file opens (`ready_precise_s`, the median of the three `ready_precise_trials_s`, and `ready_estimated_s` are numbers, never `failed`), precise duration within 500 ms, the chapter counts as on the simulator; record the `open_growth` lines (seconds of opening per hour of file, per format) and, for the native FLAC, Ogg Opus and MP3-without-header rows, the three trials with the row's `load_1m_start` and `load_1m_end` (review R5-05: on the simulator the open time of these formats grew with the host's load, so the device's own numbers decide the length limits in ADR-0006). `long-formats-cold-resume.tsv`: `status_after_load` is `paused` in every row (a slow open is `preparing` while it lasts, never `failed`), content error at most 500 ms; record the summary line of each format with its `within_budget` count. The formats asserted within the budget on the simulator (MPEG-4 FLAC and Opus, Opus in CAF, WAV, ALAC, HE-AAC v1 and v2) must stay within it, or the test fails; record the others (native FLAC, Ogg Opus `.ogg` and `.opus`, MP3 without a header) whatever they show. `long-formats-capture.tsv`: every export and preview within 500 ms at both ends; record `export_s` and `preview_start_s` per format. `long-formats-remux.tsv`: every remuxed copy opens, its duration within 50 ms of the source, decoder windows sample-identical (`max_abs_sample_difference=0.000000`), cold resume of the copy at most 1.5 s; record the `remux_s` values (on the simulator they varied several-fold between runs).
   - `audio-output.txt`: the `test (quiet)` rows show `player_volume` 0.01, `peak_over_reference` between 0.9 and 1.1 and `measured_tone_hz` within 20 Hz of 1000 at 1x-3x on both taps (the 1 % volume changes nothing the tests measure); record the `muted` rows (in the simulator's clean run the muted player's post-effects tone measured 684 Hz at 2x and 351 Hz at 3x, which is why the tests are quiet rather than muted).
   - `audio-session.txt`: the last line reads `after a user pause: setActive(false, notifyOthersOnDeactivation) calls=1 error=none ...`.
   - The test "Seek latency in 10-hour files" passes with one known issue (10-hour MP3 with precise timing is slow to start after a seek). If instead it reports that the known issue was **not** recorded, the device meets the 1.5 s budget there: record that as a finding (it changes ADR-0006), not as a failure of the device.
4. Run it twice more with the phone on a charger and not in Low Power Mode, and once in Low Power Mode. Record the budget lines of each run.
5. Release build of the budget and preview measurements (plan 19.1). The `@testable` imports need `ENABLE_TESTABILITY=YES`; a separate derived-data folder keeps the Debug products of 1.1:

   ```sh
   xcodebuild test -project Spikes/G04-Audio/G04Audio.xcodeproj -scheme G04AudioHarness -configuration Release ENABLE_TESTABILITY=YES \
     -destination "id=<device-id>" -derivedDataPath Spikes/G04-Audio/.build/DerivedData-release \
     -only-testing:G04AudioTests/RealAV/BudgetTests -only-testing:G04AudioTests/RealAV/RealPreviewTests \
     -only-testing:G04AudioTests/RealAV/LongFormatTests -only-testing:G04AudioTests/RealAV/PerFileTimingTests \
     -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z 2>&1 | tee step-01-5-release.log
   ```

   Pull `budgets.txt`, `preview.txt`, `preview-end-formats.tsv`, `preview-interruption.txt`, `preview-load-edition.txt`, the four `long-formats-*.tsv`, `mp3-cbr-detection.tsv` and the two `estimated-timing-*.tsv` as in 1.2, into `Docs/Stage0/evidence/G04-Audio/device/step-01-release/`. Expected: the four suites pass; the environment line of each table (as in 1.2) contains `device iPhone18,1, iOS` and `Release build`; the same expectations as in 1.3 for these tables. Record the budget lines next to the Debug ones of 1.1 and 1.4. (In round 2 this command, then with the budget and preview suites only and the simulator as destination, was run on the build Mac: `Docs/Stage0/evidence/G04-Audio/release-build-simulator.txt`; the long-format and per-file timing suites were not built in Release on the simulator.)

## 2. Harness setup for the manual steps

1. Build the harness app in the Release configuration, install it and launch it once without Xcode (no debugger attached; plan 19.1):

   ```sh
   xcodebuild build -project Spikes/G04-Audio/G04Audio.xcodeproj -scheme G04AudioHarness -configuration Release \
     -destination "id=<device-id>" -derivedDataPath Spikes/G04-Audio/.build/DerivedData-release \
     -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z
   xcrun devicectl device install app --device <device-id> \
     Spikes/G04-Audio/.build/DerivedData-release/Build/Products/Release-iphoneos/G04AudioHarness.app
   xcrun devicectl device process launch --device <device-id> com.jevidon.sylvia.spike.g04audio
   ```
2. Copy the real LibriVox M4B (4 h 47 m) into the harness's book folder, then force-quit and relaunch the harness:

   ```sh
   xcrun devicectl device copy to --device <device-id> --domain-type appDataContainer \
     --domain-identifier com.jevidon.sylvia.spike.g04audio \
     --source ~/Library/Caches/SylviaFixtures/downloads/MeditationsMarcusAurelius_librivox.m4b \
     --destination Documents/G04Book/MeditationsMarcusAurelius_librivox.m4b
   ```

3. Expected: the Player section title reads `Player · G04Book (1 files)` and the log has a `loaded` line with `duration_ms=17267125`, preceded by an `output volume=0.01 preview_volume=0.01 reason=default` line (the harness starts quiet) and followed by `member index=0 duration_ms=17267125 timing=precise` (the import's timing decision for the M4B: precise, as for every file that is not a proved constant-bit-rate MP3; ADR-0006 decision 2).
4. Tap **"Full volume (now quiet, 1 %)"** (Setup 4). Expected: the button reads "Quiet playback (now full volume)" and the log has `output volume=1.0 preview_volume=1.0 reason=toggle`; after any later relaunch the `output` line reads `volume=1.0 preview_volume=1.0 reason=toggle_or_launch_argument`. Steps 3-7, 14 and 15 need full volume: check the button label before each of them. A step in which you heard nothing because the harness was quiet is repeated, not failed.

## 3. Two-hour locked playback (T18)

1. In the harness, play from the start at 1x. Note the time (UTC) just before you lock the phone with the side button. Leave it locked, on battery, for 2 hours. Do not touch it.
2. **Listen** (full volume, step 2.4) at the start, after about one hour and at the end: audio is continuous.
3. Note the time (UTC) just before you unlock. Unlock, pause, and pull the harness log.
4. Check the checkpoints, and every other event the harness logged while the phone was locked (T18: "no unrelated background work"), with (the two times are the lock and unlock times noted above, for example `2026-11-02T09:00:00Z`):

   ```sh
   python3 - step-03-harness.log <lock time> <unlock time> <<'EOF'
   import sys, datetime, collections
   ts = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
   lock, unlock = ts(sys.argv[2]), ts(sys.argv[3])
   lines = [l.split() for l in open(sys.argv[1]) if l.strip()]
   locked = [l for l in lines if lock <= ts(l[0]) <= unlock]
   rows = [l for l in locked if l[1] == "checkpoint"]
   t = [ts(r[0]) for r in rows]
   gaps = [(b - a).total_seconds() for a, b in zip(t, t[1:])]
   print("checkpoints", len(rows), "max gap s", max(gaps), "locked rows", sum("protectedDataAvailable=false" in " ".join(r) for r in rows))
   print("events while locked", dict(collections.Counter(l[1] for l in locked)))
   print("checkpoint reasons while locked", dict(collections.Counter(r[2] for r in rows)))
   EOF
   ```

5. Expected:
   - Audio continuous for the whole two hours; the lock screen shows the title, elapsed time and the controls.
   - Periodic checkpoints throughout, the largest gap between consecutive checkpoints at most 5.5 s while playing; most rows written with `protectedDataAvailable=false` (the phone was locked); no `checkpoint-failed` line.
   - No unrelated background work: while locked the harness logged only `checkpoint` events (the script prints `events while locked {'checkpoint': N}`), with `reason=periodic`, plus `reason=lifecycle` when the app moves to the background at the lock (and `reason=itemChange` only for a multi-file book). Any `launch`, `loaded`, `capture`, `export`, `export-resumed` or `session` line, or any other checkpoint reason, in that window is a failure (the app relaunched or did work nobody asked for).
   - Settings > Battery (after the step, "Last 24 Hours"): record the G04 Audio row (screen and background minutes, and any activity label shown) with a screenshot. This is a record, not a pass criterion: iOS's attribution is coarse.
   - The final `last_ms` is within 10 s of the elapsed playing time (about 7,200,000 ms).
6. Record the script output, the first and last checkpoint lines, the Settings > Battery screenshot and the battery percentage before and after.

## 4. Headphone removal (T19)

1. At full volume (step 2.4), connect headphones, play, then unplug (or switch off) the headphones and **listen** to the speaker.
2. Expected: playback pauses at once and nothing plays from the speaker; the log has `checkpoint reason=routeChange`. Reconnecting the headphones does not start playback.

## 5. Phone call (T19)

1. At full volume (step 2.4), play, then call the phone from another phone. Answer, talk for 20 s, hang up.
2. Expected: playback pauses when the call starts (`checkpoint reason=interruption`). After the call it resumes only if the system indicates it should (record whether it resumed). Repeat with playback paused before the call: it must stay paused after the call.
3. Repeat once with the call declined.

## 6. Bluetooth route change (T19)

1. At full volume (step 2.4), play through the phone speaker, then connect a Bluetooth headset: playback continues on the headset without pausing (**listen** on the headset).
2. Switch the headset off: playback pauses and does not continue on the speaker (`checkpoint reason=routeChange`).

## 7. Lock-screen and Control Center playback controls (plan 10.1)

1. While playing and locked, use the lock-screen player: pause, play, skip back 15 s, skip forward 15 s, drag the scrubber, previous and next track. Repeat from Control Center.
2. Expected: each control acts once; skip moves 15 s; previous and next track move by chapter (the M4B has 12 chapters); the elapsed time and title are correct; the log shows `pause` and `seek` checkpoints for those actions, and one `remote` line per action with the fields `mode=main` and `status=success` (for example `remote command=skipForward mode=main status=success`). Take one screenshot of the lock-screen player.
3. Remote commands during a capture preview (review R4-03; ADR-0006 decisions 5 and 16). At full volume (step 2.4), play the book, tap "Capture the last 30 seconds", then tap Preview on the new capture.
   1. While the preview plays, press the play/pause button on wired or Bluetooth headphones once. Expected: the preview stops at once and nothing else plays (**listen**); the harness's play button reads "Play" again (not "Stop preview"); the book stays paused at the position it had when the preview started (the position line in the Player section does not move); the log has `session deactivate ok notifyOthersOnDeactivation=true` immediately followed by `remote command=togglePlayPause mode=preview status=success` (the session is released while the command is handled, before its `remote` line is written), and no `checkpoint` line between the `checkpoint reason=previewStart` line written when the preview started and those two lines (a preview writes nothing).
   2. Start the preview again, lock the phone, and look at the Lock Screen player while it plays. Record (screenshot) what it shows: the expected state is the book's title, the preview's own elapsed time and length (30 s, not the book's), playing, and the skip, scrubber and previous/next track controls unavailable (greyed out or hidden; record which). Press pause on the Lock Screen. Expected: as 3.1 (`remote command=pause mode=preview status=success`), and the Lock Screen then shows the book, paused, at its saved position.
   3. Start the preview a third time and, if the Lock Screen or Control Center still offers skip or the scrubber during it, use one. Expected: nothing moves (the preview keeps playing, the book's position is unchanged) and the log has a `remote` line with `mode=preview status=commandFailed`. If the controls are not offered, record that instead.
   4. Record yes or no for each expected result. A preview that keeps playing after pause, a book that resumes by itself, a moved book position, or a `status=success` for a skip during the preview is a failure.

## 8. Bookmark remote command visibility (ADR-0007)

1. In the harness, tap "Enable remote bookmark command". Play, lock, and look at the lock-screen player and the Control Center player for any bookmark or "Capture" item, including in any menu.
2. Expected (from developer reports, not Apple documentation): no such item appears on iOS 26. Record yes or no with a screenshot. If it does appear, use it while locked and check that the log has `capture origin=remote-bookmark-command ... result=saved`.

## 9. Control in Control Center and on the Lock Screen while locked (T25)

1. Add the "Capture the last 30 seconds" control (G04 Capture) to Control Center and to a Lock Screen control slot. (On the unlocked simulator a UI test adds it to Control Center and presses it: the control's intent was performed in the playing app's process, `origin=intent.control@...` with the team-signed build; `results/quick-capture-simulator-signed.txt`, review R5-01. This step checks the device, the Lock Screen placement and the locked case.)
2. Play the book, lock the phone, wait at least 20 s (so protected data becomes unavailable), then press the control on the Lock Screen. Wait 10 s, then press it in Control Center (still locked).
3. Pull the harness log and the capture records.
4. Expected for each press:
   - The system does not ask to unlock.
   - One `capture` line in `g04-harness.log`. Its fields are separated by spaces and others (`app_state=`, `was_playing=`, `id=`, `ranges=`) sit between them, so check each of these `key=value` fields separately, each exactly as written:
     - `origin=intent.control@com.jevidon.sylvia.spike.g04audio` (the control's own intent, performed in the app, with its `surface` parameter; `intent@...` without `.control` means the parameter was lost, as with the ad-hoc-signed simulator build, or another entry point: record which, ADR-0007 decision 2)
     - `process=com.jevidon.sylvia.spike.g04audio`
     - `protectedDataAvailable=false`
     - `was_playing=true`
     - `result=saved`
     - `record_protection=NSURLFileProtectionCompleteUntilFirstUserAuthentication` (the harness prints `URLFileProtection.rawValue`, which has the `NSURL` prefix; the simulator printed the same value, `quick-capture-simulator-signed.txt`)
   - After it, an `export` line with the same `id=`, `status=Audio excerpt saved` and `excerpt_protection=NSURLFileProtectionCompleteUntilFirstUserAuthentication` (the retained excerpt's class read back on the device; review R5-04: the simulator ignores file protection, `simulator-file-protection.txt`, and reads back this value, so only the device shows that the exporter's class C took effect). Any other `excerpt_protection=` or `record_protection=` value is a failure to record (ADR-0007 decision 4: class C, never weaker).
   - Playback continues uninterrupted.
   - Record exactly what the system showed as acknowledgement (screenshot if possible).
   - The control's two placements (Lock Screen, Control Center) and the Action button run the same intent instance, so the record cannot tell them apart: tell the two presses apart by their times (10 s apart).
5. Failure conditions (record them; they decide ADR-0007): a request to unlock; the intent ran in the control extension instead of the app, which shows as the system displaying the error text `[quick_capture.not_in_app_process com.jevidon.sylvia.spike.g04audio.capturecontrol]` (the extension has no capture handler, so the intent throws) and **no** `capture` line in `g04-harness.log` for that press; any other press with no `capture` line in the log; a success shown without a `result=saved` line.

## 10. Siri and App Shortcut while locked (T25)

1. Play, lock, and say "Capture a moment in G04 Audio".
2. Expected: Siri answers "Moment saved · preserving audio" without asking to unlock; the log has a `capture` line with the fields `origin=intent@com.jevidon.sylvia.spike.g04audio` (no `.control`: the App Shortcut), `process=com.jevidon.sylvia.spike.g04audio` and `result=saved`, then an `export` line with `status=Audio excerpt saved`.
3. Unlocked, with the book playing, open the Shortcuts app and tap the "Capture moment" tile under G04 Audio (the run the simulator made; `quick-capture-simulator-signed.txt`). Expected: a `capture` line with the fields `origin=intent@com.jevidon.sylvia.spike.g04audio`, `process=com.jevidon.sylvia.spike.g04audio` and `result=saved`. On the simulator this worked only with a team-signed build; an ad-hoc-signed build was rejected by the system ("Unable to run App Shortcut", `quick-capture-simulator-adhoc.txt`). The device build is team-signed, so a rejection here is a failure to record.

## 11. Action button (T25; iPhone 15 Pro and later)

1. Settings > Action Button > Controls: choose the G04 Capture control. Play, lock, press the Action button.
2. Expected: as step 9 (the same fields, including `origin=intent.control@com.jevidon.sylvia.spike.g04audio`). Then assign the "Capture moment" shortcut instead and repeat: as step 9, except that the origin field is `origin=intent@com.jevidon.sylvia.spike.g04audio` (the App Shortcut has no surface parameter).

## 12. Quick capture with nothing playing (T25 negative case)

1. Force-quit the harness. Lock the phone. Press the Lock Screen control.
2. Expected: no success acknowledgement (if the system shows the intent's error text, it is the proposed vocabulary key `[audio.nothing_to_capture]`); the log (after unlocking) has a `capture` line with the field `result=nothing_to_capture` and no new capture record.

## 13. Quick capture before the first unlock after a restart (T25 negative case)

1. Restart the phone. Do not unlock it. Press the Lock Screen control (if the system offers it before the first unlock).
2. Expected: no success acknowledgement (class C data is not yet available, so nothing can be saved): never "Moment saved · preserving audio". If the intent ran and the write failed, the system shows the intent's error text, the proposed vocabulary key `[audio.moment_not_saved]` (never `save.failed`'s "Not saved · your text is still here": a capture has no text). After unlocking, the log has no `result=saved` line for that press (the log itself is class C, so a line for the press may be missing entirely). Record what the system showed.

## 14. Preview end, by ear (plan 10.3, 19.2; human judgement)

1. At full volume (step 2.4; the toggle sets the preview player too), make five captures at different places, edit two of them with the numeric controls to 5-10 s, and preview each, **listening**.
2. Expected: each preview starts at the start of the excerpt and stops at its end with no audible extra speech (more than about half a second). On the simulator the player's own end time was within a few milliseconds of the intended end and everything the analysis tap processed past the end was silence (`preview.txt`, `preview-end-formats.tsv`). Record pass or fail per preview.
3. Make one capture across a member boundary of a multi-file book (copy the four `multi/*.mp3` fixtures into `Documents/G04Book` instead of the M4B, relaunch, seek to 2:20 and capture), then preview it immediately while it still reads "Moment saved · preserving audio" (the pending source ranges play back to back), and again after "Audio excerpt saved". Expected: the log's four `member` lines after the relaunch read `timing=estimatedCBR` (the import proves these MP3 files constant bit rate and opens them with estimated timing; ADR-0006 decision 2), and both previews play the end of the first file straight into the start of the next, with no gap or repeat you can hear.

## 15. Importing, capturing and exporting never interrupt another app's audio (plan 10.1)

The simulator showed only that the harness leaves the shared audio session alone (`audio-session.txt`: the category is unchanged and the harness activates the session 0 times before `play()`). Whether AVFoundation activates a session on its own during loading, seeking or export can only be heard on the device.

1. Check that the harness is at full volume (step 2.4), so that when it does play you hear it. Force-quit the harness. Start music in the Music app (or another audio app) through the speaker or headphones.
2. Copy a new audio file into the harness's book folder (as in step 2, for example `multi/Part 3.mp3`), then launch the harness from the Home Screen. It inspects the book's files, loads the edition and seeks to its saved position.
3. In the harness, without pressing Play or Preview (both play audio by design), tap "Capture the last 30 seconds" twice; each capture exports an excerpt. (Each tap of the in-player button is its own capture, even two quick taps at the same position: the 2 s repeat window applies only to the quick-capture intent and the bookmark command; ADR-0007 decision 2.)
4. Wait until both captures read "Audio excerpt saved". Pull the harness log.
5. Expected: the music never stops, pauses, ducks or skips during steps 2-4; the log has the `loaded` line, two `export` lines with `status=Audio excerpt saved`, and no `session` line. Then press Play in the harness: the music stops (the harness's playback session interrupts it, as it should) and the log has `session activate ok`. Record yes or no for "music uninterrupted during steps 2-4" and attach the log.
6. Release (review R2-06): let the harness play for 10 s, then press Pause in the harness. Expected: the log has `session deactivate ok notifyOthersOnDeactivation=true` right after the `checkpoint reason=pause` line, and the music resumes by itself within about 5 s, without touching the Music app. Record yes or no for "music resumed by itself" and how long it took. A `session deactivate error=...` line, or music that stays paused, is a failure to record.
7. Repeat 6 with a preview instead: with the harness paused and the music playing, tap Preview on one of the captures. Expected: the music stops while the excerpt plays, the log has `session activate ok` and, when the preview ends, `session deactivate ok notifyOthersOnDeactivation=true`, and the music resumes by itself.

## 16. Force-quit while playing and relaunch (crash position loss, plan 10.1 and 19.2)

The simulator trial killed the harness with SIGKILL from the host (`process-kill-relaunch.txt`); this is the device equivalent.

1. With the LibriVox M4B in the book folder (step 2), force-quit the harness, then launch it so that it starts playing by itself and logs the player's position every 0.5 s:

   ```sh
   xcrun devicectl device process launch --device <device-id> com.jevidon.sylvia.spike.g04audio -g04AutoPlay YES
   ```

2. After at least 30 s of playback, with the harness still in front, kill it with SIGKILL (no lifecycle event reaches it, as in a crash). `process launch` prints the process identifier; check the exact options with `xcrun devicectl device process signal --help` if they differ:

   ```sh
   xcrun devicectl device process signal --device <device-id> --pid <pid> --signal SIGKILL
   ```

3. Relaunch the harness from the Home Screen (no arguments, so it does not play by itself) and pull the log.
4. Expected: the relaunch's `loaded` line has a `position_ms` at most 5,000 ms behind the last `position` line logged before the kill, and not more than 500 ms ahead of it. Record both values. Repeat the whole step twice more (each relaunch continues from the resumed position).
5. Once more, but instead of the signal, open the app switcher and swipe the harness away while it plays. The system makes it inactive first, so a lifecycle checkpoint is expected: the resumed position is within 5,000 ms behind the last `position` line.
