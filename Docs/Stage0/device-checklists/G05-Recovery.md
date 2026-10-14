# G0.5 recovery: physical-device checklist

Status of every step: **pending** (not run). Stage 0 agents did not use the physical iPhone; this checklist is for the serialized device run.

**Device:** iPhone 17 Pro (iPhone18,1), iOS 26.7 (23H24), Developer Mode on (ADR-0001). Repeat steps 1-4 on the iPhone 12-class baseline when one is available.

**Setup:**

- On the build Mac, check out the branch and run `Scripts/fixtures/fetch.sh`. No fixtures are needed beyond the committed ones.
- Find the device ID with `xcrun devicectl list devices`.
- All commands run from `Spikes/G05-Recovery` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Test runs need signing for the device: add `-allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z`.

**Recording:**

- Save every console output as plain text under `Docs/Stage0/evidence/G05-Recovery/device/` with the step number in the file name, for example `device/step-1-tests.log`.
- In `Docs/Stage0/G05-Recovery.md`, change the step's row from pending to passed or failed, with the date, device model and iOS build.
- Never edit an expected result to match what happened. A different result is a failure, recorded as one.

## 1. Test suite on the device (T45, T46, T47, T35 on device; protection readback, including the non-default class)

1. Run:

   ```sh
   xcodebuild test -scheme G05Recovery-Package -destination "id=<device-id>" -derivedDataPath .build/DerivedData \
     -disableAutomaticPackageResolution -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z 2>&1 | tee step-1-tests.log
   ```

2. Expected:
   - `Test run with 67 tests in 11 suites passed` (the five macOS-only tests, the three SIGKILL drills, the real full-volume test and the locked-host observation, are not built for iOS). This is the simulator's count in the review-round-4 clean run; the device builds the same tests.
   - Exactly four skipped tests, each with its reason printed: the device lock probe (step 3 runs it), the device persistence probe (step 4 runs it), and the two contract-fixture tests (`ManifestContractTests`), which read `Contracts/` from the Mac's checkout and cannot on the phone (the host and simulator runs cover them). Every other test, including the parameterized ones, shows `passed`.
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
2. Run step 1 two more times with the phone on a charger and not in Low Power Mode, and once in Low Power Mode. Save each log.
3. Expected: p95 at most 200 ms in every run. Record all four p95 values. A p95 above 200 ms is a failure of the proposed budget and must be reported, not retried away.

## 3. Writes continue while the phone is locked after first unlock (T50)

This runs `DeviceLockProbeTests.lockedWrites`. The probe saves a capture to a class-C library and writes a class-C file every second. It uses a class-A canary file, unreadable about 10 s after the phone locks, to detect the lock.

1. Unlock the phone and keep the screen on. Run:

   ```sh
   TEST_RUNNER_SYLVIA_DEVICE_LOCK_PROBE=1 TEST_RUNNER_SYLVIA_DEVICE_LOCK_PROBE_SECONDS=120 \
   xcodebuild test -scheme G05Recovery-Package -destination "id=<device-id>" -derivedDataPath .build/DerivedData \
     -disableAutomaticPackageResolution -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z \
     -only-testing:SylviaRecoveryTests/DeviceLockProbeTests 2>&1 | tee step-3-lock-probe.log
   ```

2. When the log shows `lock probe: lock the device now`, press the side button to lock the phone. Leave it locked, untouched, for at least 90 s, then unlock it.
3. Expected:
   - The per-second lines show `classA_readable=false` for at least 30 consecutive seconds while locked, with `classC_save=ok` on every one of those lines.
   - The summary line reads `lock probe summary: N locked samples, 0 failed class-C saves while locked` with N ≥ 30, and the test passes.
4. If `classA_readable` never becomes false, the phone was not locked long enough, or test execution was suspended while locked. If the log has a gap of more than 5 s between lines while locked, execution was suspended. Record either case as **inconclusive**, not passed, and note that a background-capable harness app is needed (see open questions in `Docs/Stage0/G05-Recovery.md`).

## 4. Reboot before first unlock (T50)

Expected behaviour (plan 18.1): before first unlock, class-C files cannot be opened, and Sylvia shows a safe unavailable state without lowering any protection class. **What this step can and cannot show.** The test runner cannot be launched on a phone that has not been unlocked since boot, and no Stage 0 code runs in the background, so nothing can observe Sylvia's files *before* the first unlock. This step shows that a class-C library written before a restart is still there, intact and still class C after the restart and first unlock. The before-first-unlock behaviour itself needs an app target (step 4.5 and finding F5).

Every other test deletes its library when it ends. This step uses `DevicePersistenceProbeTests`, which writes a library under `Application Support/Sylvia` in the test runner's container and leaves it there.

1. Unlock the phone. Write the persistent library:

   ```sh
   TEST_RUNNER_SYLVIA_DEVICE_PERSIST_PROBE=write \
   xcodebuild test -scheme G05Recovery-Package -destination "id=<device-id>" -derivedDataPath .build/DerivedData \
     -disableAutomaticPackageResolution -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z \
     -only-testing:SylviaRecoveryTests/DevicePersistenceProbeTests 2>&1 | tee step-4-write.log
   ```

   Expected: the test passes, and the log has `T50 persistence probe write: library at …/Application Support/Sylvia with 20 captures and … journal entries, knowledge sha256 …; canary sha256 …; classes …`, where every listed item (`Sylvia`, `Library`, `library.sqlite`, `library.sqlite-wal` and `library.sqlite-shm` when listed, `installation.json`, `t50-canary.bin`, `t50-expected.json`) is `NSFileProtectionCompleteUntilFirstUserAuthentication`. Any other class, or `none reported`, is a failure. (The probe's code was checked on the simulator, `Docs/Stage0/evidence/G05-Recovery/simulator-persist-probe-smoke.log`; that run is not T50 evidence.)
2. Restart the phone (hold the side and volume buttons, slide to power off, then power on). Do **not** unlock it. Wait at least 60 s.
3. Observation only, not a pass criterion: run `xcrun devicectl device info files --device <device-id> --domain-type appDataContainer --domain-identifier <test runner bundle ID>` (the bundle ID is in step 4.1's log) and save the output as `step-4-before-unlock.txt`. `devicectl` generally cannot reach a phone that has not been unlocked since boot whatever the files' class, so its result says nothing about Sylvia's protection.
4. Unlock the phone. Verify the library:

   ```sh
   TEST_RUNNER_SYLVIA_DEVICE_PERSIST_PROBE=verify \
   xcodebuild test -scheme G05Recovery-Package -destination "id=<device-id>" -derivedDataPath .build/DerivedData \
     -disableAutomaticPackageResolution -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z \
     -only-testing:SylviaRecoveryTests/DevicePersistenceProbeTests 2>&1 | tee step-4-verify.log
   ```

   Expected: the test passes, and the log has `T50 persistence probe verify: written N s ago; knowledge sha256 equal; 20 captures, … journal entries, integrity ok, 0 foreign-key violations; canary intact; classes …` with every item class C (including `library.sqlite-wal` and `library.sqlite-shm`), and N larger than the time since the restart. The journal entry count must equal step 4.1's. Then run the same command with `TEST_RUNNER_SYLVIA_DEVICE_PERSIST_PROBE=clean` to remove the library.
5. Record the app-level check, "Sylvia shows a safe unavailable state before first unlock (class-C files unreadable, no class lowered)", as **pending (needs the app)**. There is no app target in Stage 0. The check moves to the first milestone with an app shell and a background launch path.

## 5. Power loss (not testable)

Pulling power from an iPhone is not possible without disassembly, so durability across sudden power loss cannot be shown on the device. Do not record it as passed. The decision rests on SQLite's documented WAL + `synchronous=FULL` behaviour and `F_FULLFSYNC` (ADR-0003).
