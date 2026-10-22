# G0.5 recovery: physical-device checklist

Status of every step: **pending** (not run). Stage 0 agents did not use the physical iPhone; this checklist is for the serialized device run.

**Device:** iPhone 17 Pro (iPhone18,1), iOS 26.7 (23H24), Developer Mode on (ADR-0001). Repeat steps 1-4 on device A, the oldest supported iPhone: the iPhone 11 Pro (iPhone12,3 expected, confirmed in runbook Session 0.4; A13), with the owner's iPhone 11 (iPhone12,1 expected; A13) as a second phone of the same chip (decision D-1 (b), product owner, 22 October 2026; until then this line asked for the iPhone 12-class baseline, which was not available). On A, steps 1-2 block M0 (runbook 8.10, before the M0 exit) and steps 3-4 can wait for M1 (runbook Section 7). Record A's results with `-A` in each file name (for example `step-1-A-tests.log`).

**Step 3 uses the lock harness** (since 22 October 2026): the product owner decided to build the background-audio harness in Stage 0, before the device run, so that step 3 is conclusive the first time (PO-23 option (b), product owner, 22 October 2026; G0.5 recovery finding F5). Until then step 3 ran the XCTest probe `DeviceLockProbeTests`, which runs inside the test runner that iOS may suspend when the phone locks.

**Setup:**

- On the build Mac, check out the M0 integration branch (`m0-integrate`, or `main` once the later M0 work has reached it, since pull request #4 merged `m0-integrate` up to `177ed9a` into `main` on 15 October 2026; record `git rev-parse HEAD`) and run `Scripts/fixtures/fetch.sh`. No fixtures are needed beyond the committed ones.
- Find the device ID with `xcrun devicectl list devices`. Use the Identifier only when it is the device's UDID (copy the identifier alone); if devicectl shows an ECID or a CoreDevice identifier instead, take the UDID from Xcode > Window > Devices and Simulators > the device > Identifier: `xcodebuild -destination id=` needs the UDID.
- All commands run from `Spikes/G05-Recovery` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Test runs need signing for the device: add `-allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=A4KBDX665Z` (the second flag registers a device the team has not registered; it takes effect only with the first).

**Recording:**

- Save every console output as plain text under `Docs/Stage0/evidence/G05-Recovery/device/` with the step number in the file name, for example `device/step-1-tests.log`.
- In `Docs/Stage0/G05-Recovery.md`, change the step's row from pending-device to passed-device or failed, with the date, device model and iOS build (step 3: rows 9 and 26).
- Never edit an expected result to match what happened. A different result is a failure, recorded as one.

## 1. Test suite on the device (T45, T46, T47, T35 on device; protection readback, including the non-default class)

1. Run:

   ```sh
   xcodebuild test -scheme G05Recovery-Package -destination "id=<device-id>" -derivedDataPath .build/DerivedData \
     -disableAutomaticPackageResolution -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=A4KBDX665Z 2>&1 | tee step-1-tests.log
   ```

2. Expected:
   - `Test run with 68 tests in 11 suites passed` (the five macOS-only tests, the three SIGKILL drills, the real full-volume test and the locked-host observation, are not built for iOS). This is the simulator's count on the current code: 68 in M0 assembly's re-run (`Docs/Stage0/evidence/M0-Integration/ci-71-g05-recovery-unlocked-dropin.log`) and in the M0 final fix's second round (`Docs/Stage0/evidence/M0-Integration/final-fix-2/g05-recovery/simulator-tests.log`); the review-round-4 clean run had 67, the count this line gave until 20 October 2026 (M0 final review round 2, evidence R2-01). The device builds the same tests.
   - Exactly four skipped tests, each with its reason printed: the device lock probe (not run on the phone since 22 October 2026: step 3 uses the lock harness instead; until then step 3 ran it), the device persistence probe (step 4 runs it), and the two contract-fixture tests (`ManifestContractTests`), which read `Contracts/` from the Mac's checkout and cannot on the phone (the host and simulator runs cover them). Every other test, including the parameterized ones, shows `passed`.
   - The test `a file with the wrong class is detected, never silently accepted` **runs** on the device (it is skipped only in the simulator) and passes. Record whether its evidence line says the class change was "applied and verified" or "refused"; either passes, but note which.
   - The test `with non-default class B supplied in StoreOptions, every file and directory carries class B` **runs** on the device (it is skipped only in the simulator and on a locked Mac) and passes.
3. Expected evidence lines:
   - `class C (chosen; also the platform default) read back on 53 files and directories: ["NSFileProtectionCompleteUntilFirstUserAuthentication": 53]`. There must be no `none reported` entries; directories report a class on the device. Class C is also iOS's default class for app files, so this line alone does not show that the code applied the class; the next line does.
   - `class B (non-default) requested: read back on 53 files and directories: ["NSFileProtectionCompleteUnlessOpen": 53]`. This is the discriminating check: every file and directory the library, export and restore create (including copied media, bundle blobs, restored files and recovery snapshots) carries the class the code asked for, not the platform default. Any other class on any item is a failure; the test's failure message names the item.
   - `files SQLite created in a class-B directory: probe.sqlite=NSFileProtectionCompleteUnlessOpen probe.sqlite-wal=NSFileProtectionCompleteUnlessOpen probe.sqlite-shm=NSFileProtectionCompleteUnlessOpen`. This shows SQLite-created files inherit the directory's class on iOS.
   - Record the line `files SQLite created in a class-A directory: …` as an observation (on the Mac the `-shm` file comes out class C; note whether the iPhone does the same). It is not pass or fail.
   - Record the line `default GRDB connection: SQLITE_DBCONFIG_DEFENSIVE=… trusted_schema=…`. The untrusted-database test that follows it must pass whatever the default is.
4. Record the evidence lines `SQLite …` (version and compile options) and `writer pragmas: …`. Expected: `journal_mode=wal synchronous=FULL fullfsync=1 checkpoint_fullfsync=1`. If the SQLite version differs from the host's 3.51.0, note it; it is not a failure by itself.

## 2. Capture save latency on the device (plan 19.2)

1. Step 1's log already contains `capture save latency synchronous=FULL fullfsync=ON: n=400 p50=… p95=… p99=… max=…`.
2. Run step 1 two more times with the phone on the cable and not in Low Power Mode (`step-2-run2.log`, `step-2-run3.log`), and once in Low Power Mode on battery (`step-2-low-power.log`): unplug the cable, keep the phone on the Mac's Wi-Fi, check that `xcrun devicectl list devices` still lists it as available, start fully charged, turn on Low Power Mode, keep the phone unlocked by touching the clock in the status bar at least every 20 s until the run ends (Low Power Mode sets Auto-Lock to 30 seconds; if it locks part way, run it again), and check after the run that Low Power Mode stayed on (iOS turns it off once charging reaches 80 %: https://support.apple.com/en-us/101604).
3. Expected: p95 at most 200 ms in every run. Record all six p95 values (with step 4), each with its configuration and power state. A p95 above 200 ms is a failure of the proposed budget and must be reported, not retried away.
4. Release build of the latency test (plan 19.1). From `Spikes/G05-Recovery`: `xcodebuild test -scheme G05Recovery-Package -configuration Release ENABLE_TESTABILITY=YES -destination "id=<device UDID>" -derivedDataPath .build/DerivedData-release -disableAutomaticPackageResolution -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=A4KBDX665Z '-only-testing:SylviaRecoveryTests/DurabilityTests/latency()' 2>&1 | tee step-2-release.log`, once on the cable and once in Low Power Mode on battery as in 2.2 (`step-2-release-low-power.log`). **Expected:** `✔ Test run with 1 test in 1 suite passed` and p95 at most 200 ms in both.

## 3. Writes continue while the phone is locked, and the library survives a restart (T50), with the lock harness

The lock harness, the app "G05 Lock" (`Spikes/G05-Recovery/LockHarness`), stays running while the phone is locked by playing a quiet tone: UIBackgroundModes audio, at a player volume of 0.01, never muted (the phone's own volume is not touched; launched with the environment variable SYLVIA_AUDIBLE_PLAYBACK=1 it plays at full volume, for a listening check, not needed here). While a run is active it makes one attempt every 2 s: a durable capture save in the spike's library at `Application Support/Sylvia` (class C, WAL with synchronous FULL and fullfsync: D17), the save's read-back, a class-C file written and read back, and a readback of the files' classes. It records each attempt, with the time, `isProtectedDataAvailable`, the outcome and any error, as one line of its log, `Library/Application Support/G05LockHarness/harness.log` in its container (class C, so it can be written while the phone is locked after the first unlock), and of the unified log (subsystem `com.jevidon.sylvia.spike.g05lockharness`, which keeps lines that the class-C file cannot take before the first unlock). A class-A file, unreadable about 10 s after the phone locks, detects the lock, as the XCTest probe did. At every launch it records how its last run ended (from its class-C record and the phone's boot time) and checks the library that run left. It asks iOS for background refresh launches, which iOS may or may not make, before or after the first unlock. The phone needs a passcode: without one, iOS never locks the classes. Its logic was tested on the simulator, which cannot lock (`Docs/Stage0/evidence/M0-Decisions/harness/`); nothing it does on a phone has been seen yet. *(Until 22 October 2026 this step ran `DeviceLockProbeTests.lockedWrites` in the test runner, a 120 s probe with a 90 s lock; that probe stays in the package and is not run.)*

1. Generate the project, from the repository root: `source Scripts/lib/env.sh; source Scripts/lib/xcodegen.sh; sylvia_generate Spikes/G05-Recovery/LockHarness`. Then, with the phone unlocked and on the cable, from `Spikes/G05-Recovery`, build and install it:

   ```sh
   xcodebuild build -project LockHarness/G05LockHarness.xcodeproj -scheme G05LockHarness -configuration Debug \
     -destination "id=<device-id>" -derivedDataPath LockHarness/.build/DerivedData -disableAutomaticPackageResolution \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=A4KBDX665Z 2>&1 | tee step-3-build.log
   xcrun devicectl device install app --device <device-id> LockHarness/.build/DerivedData/Build/Products/Debug-iphoneos/G05LockHarness.app
   ```

   Expected: `** BUILD SUCCEEDED **` and "G05 Lock" on the Home Screen.
2. On the phone: Settings > General > Background App Refresh on, with G05 Lock on in its list, and Low Power Mode off (both only for the launch before the first unlock that iOS may make, item 8). Nothing else playing audio.
3. Start. Open G05 Lock from the Home Screen, not with Xcode's Run: a debugger attached keeps an app running when iOS would suspend it, so the step would show nothing. Tap Start. Expected on the screen, newest line first: a `start` line with `volume=0.01`, `audio=playing`, `protection=NSFileProtectionCompleteUntilFirstUserAuthentication`, `durability=journal_mode=wal,synchronous=FULL,fullfsync=1,checkpoint_fullfsync=1` and `store=open`, then an `attempt` line every 2 s with `protectedDataAvailable=true`, `classA=readable`, `save=saved`, `readback=equal`, `file=ok` and `classes=ok`. Note the time.
4. Lock for 5 minutes. After at least 10 `attempt` lines, press the side button. Put the phone face down and leave it untouched for at least 5 minutes (raising it or looking at it can unlock it with Face ID); no calls, no Siri, no other audio.
5. Restart without unlocking. Hold the side button and either volume button, slide to power off, and as soon as the screen is black, hold the side button until the Apple logo shows. If iOS asks for the passcode before it powers off, enter it and say so in the record: the unlock this step is about is the first one after the restart. Note the time it powered off. Leave the phone locked for at least 2 minutes after the Lock Screen appears.
6. Unlock, the first unlock since the restart, and open G05 Lock from the Home Screen. It records the launch, how the run ended, and its check of the library.
7. Record, from `Spikes/G05-Recovery` (the two `sudo` commands ask for your Mac password; in zsh `log` is a shell command, so its path is given):

   ```sh
   xcrun devicectl device copy from --device <device-id> --domain-type appDataContainer \
     --domain-identifier com.jevidon.sylvia.spike.g05lockharness \
     --source "Library/Application Support/G05LockHarness/harness.log" --destination step-3-harness.log
   mkdir -p .build
   sudo /usr/bin/log collect --device-udid <device-id> --last 2h \
     --predicate 'subsystem == "com.jevidon.sylvia.spike.g05lockharness"' --output .build/step-3.logarchive
   /usr/bin/log show --style compact --predicate 'subsystem == "com.jevidon.sylvia.spike.g05lockharness"' .build/step-3.logarchive > step-3-unified-log.txt
   sudo rm -rf .build/step-3.logarchive
   xcrun devicectl device info files --device <device-id> --domain-type systemCrashLogs > step-3-crash-logs.txt
   ```

   The archive is written in the spike's ignored `.build` folder and deleted (it belongs to root, hence `sudo rm`) once `step-3-unified-log.txt` is written: never keep or commit it, since an archive can hold more of the phone's logs than the harness's. The harness's Export log button shares the same `harness.log`, for example by AirDrop, if devicectl cannot copy it. If devicectl refuses the systemCrashLogs domain, look in Settings > Privacy & Security > Analytics & Improvements > Analytics Data instead and write what is there into `step-3-crash-logs.txt`.
8. Expected:
   - In `step-3-harness.log`, every `attempt` line of the run after its `event name=protected-data-will-become-unavailable` line has `save=saved` (or `save=already-saved`), `readback=equal`, `file=ok` and `classes=ok`, and there is no `gap` line.
   - The `previous-session` line after the restart has `result=ended-by-restart`, `lockedFailures=0` and `gaps=0`; its `lockedAttempts` and `classAUnreadable` are at least 120 each (5 minutes at one attempt every 2 s, less the 10 s before class A locks), and its `lastRecordToBoot` is at most 120 (seconds: the run was still running when the phone powered off).
   - The `verify` line after it has `result=ok`, `failures=0`, `integrity=ok`, `foreignKeyViolations=0`, `extra=0` or `extra=1` (a save committed in the last second before the power-off, and not yet acknowledged, is allowed) and `classes=ok`; the `verify-classes` line after it gives every item `NSFileProtectionCompleteUntilFirstUserAuthentication` except `class-a-canary.bin=NSFileProtectionComplete`. Any other class, or none-reported, is a failure.
   - No crash report whose name starts with G05LockHarness in `step-3-crash-logs.txt`.
   - Before the first unlock (an observation, not a criterion): iOS decides whether to launch the harness in the background then. If it did, `step-3-unified-log.txt` has a `launch` line with `protectedDataAvailable=false` before the first `event name=protected-data-did-become-available` after the restart, followed by `result=unreadable` (the run's record) and `result=could-not-read` (the library), each with its error; if the harness was still running at the first unlock, the same lines are in `step-3-harness.log` too, marked `written-late=`. Record "observed before the first unlock" with those lines, or "not observed: iOS did not launch the harness before the first unlock". Either way the app's own state before the first unlock stays pending (step 4.5).
9. **Inconclusive** (record it, and repeat the step): a `gap` line while the phone was locked (iOS suspended the harness); an `event name=audio` line with interruption-began during the lock (a call or another app's audio stopped the tone); fewer than 120 locked attempts; or a `lastRecordToBoot` above 120 with no crash report (the run ended before the restart, and the log does not say why). **Failed:** any attempt of the run with `save=failed`, `readback=differs`, `readback=failed`, `file=failed` or `classes=differs:`, a `verify` line whose result is not ok, any item of another class, or a crash report of the harness.
10. Write `step-3-results.txt`: the device model and identifier, its iOS version and build, the start, lock and power-off times, the `previous-session`, `verify` and `verify-classes` lines, the counts above, the result (passed-device, inconclusive or failed), and "observed before the first unlock" or "not observed". Then delete G05 Lock from the phone, which removes its library and log.

## 4. Reboot before first unlock (T50)

Expected behaviour (plan 18.1): before first unlock, class-C files cannot be opened, and Sylvia shows a safe unavailable state without lowering any protection class. **What this step can and cannot show.** The test runner cannot be launched on a phone that has not been unlocked since boot, so this step cannot observe Sylvia's files *before* the first unlock. It shows that a class-C library written before a restart is still there, intact and still class C after the restart and first unlock. Since 22 October 2026 the lock harness of step 3 can observe the time before the first unlock, but only if iOS launches it in the background then, which iOS decides (step 3, item 8); until then this paragraph said that no Stage 0 code ran in the background. The app's own state before the first unlock needs the app (step 4.5 and finding F5).

One restart can serve steps 3 and 4: run 4.1 before step 3's item 3, make 4.3's observation while step 3's item 5 waits before the first unlock, and run 4.4 after step 3's item 7.

Every other test deletes its library when it ends. This step uses `DevicePersistenceProbeTests`, which writes a library under `Application Support/Sylvia` in the test runner's container and leaves it there.

1. Unlock the phone. Write the persistent library:

   ```sh
   TEST_RUNNER_SYLVIA_DEVICE_PERSIST_PROBE=write \
   xcodebuild test -scheme G05Recovery-Package -destination "id=<device-id>" -derivedDataPath .build/DerivedData \
     -disableAutomaticPackageResolution -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=A4KBDX665Z \
     -only-testing:SylviaRecoveryTests/DevicePersistenceProbeTests 2>&1 | tee step-4-write.log
   ```

   Expected: the test passes, and the log has `T50 persistence probe write: library at …/Application Support/Sylvia with 20 captures and … journal entries, knowledge sha256 …; canary sha256 …; classes …`, where every listed item (`Sylvia`, `Library`, `library.sqlite`, `library.sqlite-wal` and `library.sqlite-shm` when listed, `installation.json`, `t50-canary.bin`, `t50-expected.json`) is `NSFileProtectionCompleteUntilFirstUserAuthentication`. Any other class, or `none reported`, is a failure. (The probe's code was checked on the simulator, `Docs/Stage0/evidence/G05-Recovery/simulator-persist-probe-smoke.log`; that run is not T50 evidence.)
2. Restart the phone (hold the side and volume buttons, slide to power off, then power on). Do **not** unlock it. Wait at least 60 s.
3. Observation only, not a pass criterion: run `xcrun devicectl device info files --device <device-id> --domain-type appDataContainer --domain-identifier <test runner bundle ID>` (find the test runner's bundle ID before the restart with `xcrun devicectl device info apps --device <device-id>`; the probe's log prints its library's path, not that ID; if no test runner is listed, record that and skip this observation) and save the output as `step-4-before-unlock.txt`. `devicectl` generally cannot reach a phone that has not been unlocked since boot whatever the files' class, so its result says nothing about Sylvia's protection.
4. Unlock the phone. Verify the library:

   ```sh
   TEST_RUNNER_SYLVIA_DEVICE_PERSIST_PROBE=verify \
   xcodebuild test -scheme G05Recovery-Package -destination "id=<device-id>" -derivedDataPath .build/DerivedData \
     -disableAutomaticPackageResolution -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=A4KBDX665Z \
     -only-testing:SylviaRecoveryTests/DevicePersistenceProbeTests 2>&1 | tee step-4-verify.log
   ```

   Expected: the test passes, and the log has `T50 persistence probe verify: written N s ago; knowledge sha256 equal; 20 captures, … journal entries, integrity ok, 0 foreign-key violations; canary intact; classes …` with every item class C (including `library.sqlite-wal` and `library.sqlite-shm`), and N larger than the time since the restart. The journal entry count must equal step 4.1's. Then run the same command with `TEST_RUNNER_SYLVIA_DEVICE_PERSIST_PROBE=clean` to remove the library.
5. Record the app-level check, "Sylvia shows a safe unavailable state before first unlock (class-C files unreadable, no class lowered)", as **pending (needs the app)**. There is no app target in Stage 0. The check moves to the first milestone with an app shell and a background launch path. The lock harness is not that app: whatever step 3 observed before the first unlock is recorded there, and this check stays pending for M1 with the app shell (PO-23 option (b), product owner, 22 October 2026).

## 5. Power loss (not testable)

Pulling power from an iPhone is not possible without disassembly, so durability across sudden power loss cannot be shown on the device. Do not record it as passed. The decision rests on SQLite's documented WAL + `synchronous=FULL` behaviour and `F_FULLFSYNC` (ADR-0003).
