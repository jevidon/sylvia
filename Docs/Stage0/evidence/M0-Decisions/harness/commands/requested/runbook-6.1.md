**6.1 Writes continue while locked, and the library survives a restart, with the lock harness** (G0.5 recovery step 3, T50; since 22 October 2026 the step uses the lock harness, which the product owner decided to build before the device run, PO-23 option (b); until then 6.1 ran the XCTest probe `DeviceLockProbeTests`, inside the test runner, which iOS may suspend when the phone locks). The harness is the app "G05 Lock" (`Spikes/G05-Recovery/LockHarness`). While a run is active it plays a quiet tone (UIBackgroundModes audio, player volume 0.01, never muted), so iOS keeps it running while the phone is locked; every 2 s it saves a capture to the spike's class-C library, reads it back, writes and reads a class-C file and reads the files' classes back, one log line per attempt; after a restart it reports how its run ended and checks the library. The phone needs a passcode. Do:

1. Build and install it, the phone unlocked and on the cable:

   ```sh
   sylvia_generate Spikes/G05-Recovery/LockHarness
   xcodebuild build -project Spikes/G05-Recovery/LockHarness/G05LockHarness.xcodeproj -scheme G05LockHarness -configuration Debug \
     -destination "id=$DEVICE_ID" -derivedDataPath Spikes/G05-Recovery/LockHarness/.build/DerivedData -disableAutomaticPackageResolution \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=A4KBDX665Z 2>&1 \
     | tee Docs/Stage0/evidence/G05-Recovery/device/step-3-build.log
   xcrun devicectl device install app --device "$DEVICE_ID" \
     Spikes/G05-Recovery/LockHarness/.build/DerivedData/Build/Products/Debug-iphoneos/G05LockHarness.app
   ```

   Expect `** BUILD SUCCEEDED **` and "G05 Lock" on the Home Screen. On the phone: Settings > General > Background App Refresh on, with G05 Lock on in its list; Low Power Mode off; nothing else playing audio.
2. Open G05 Lock from the Home Screen, not with Xcode's Run (an attached debugger keeps an app running when iOS would suspend it), and tap Start. Expect a `start` line with `volume=0.01`, `audio=playing`, `protection=NSFileProtectionCompleteUntilFirstUserAuthentication`, `durability=journal_mode=wal,synchronous=FULL,fullfsync=1,checkpoint_fullfsync=1` and `store=open`, then an `attempt` line every 2 s with `protectedDataAvailable=true`, `classA=readable`, `save=saved`, `readback=equal`, `file=ok` and `classes=ok`. Note the time.
3. After at least 10 `attempt` lines, lock the phone, put it face down and leave it untouched for at least 5 minutes: no calls, no Siri, no other audio.
4. Restart it without unlocking: hold the side button and either volume button, slide to power off, and power on as soon as the screen is black. If iOS asks for the passcode before it powers off, enter it and say so in the record. Note the time it powered off, and leave it locked for at least 2 minutes after the Lock Screen appears.
5. Unlock, the first unlock since the restart, and open G05 Lock from the Home Screen.
6. Record (the second command asks for your Mac password; in zsh `log` is a shell command, so its path is given):

   ```sh
   D=Docs/Stage0/evidence/G05-Recovery/device
   xcrun devicectl device copy from --device "$DEVICE_ID" --domain-type appDataContainer \
     --domain-identifier com.jevidon.sylvia.spike.g05lockharness \
     --source "Library/Application Support/G05LockHarness/harness.log" --destination "$D/step-3-harness.log"
   sudo /usr/bin/log collect --device-udid "$DEVICE_ID" --last 2h \
     --predicate 'subsystem == "com.jevidon.sylvia.spike.g05lockharness"' --output .build/scratch/step-3.logarchive
   /usr/bin/log show --style compact --predicate 'subsystem == "com.jevidon.sylvia.spike.g05lockharness"' \
     .build/scratch/step-3.logarchive > "$D/step-3-unified-log.txt"
   rm -rf .build/scratch/step-3.logarchive
   xcrun devicectl device info files --device "$DEVICE_ID" --domain-type systemCrashLogs > "$D/step-3-crash-logs.txt"
   ```

Expect (checklist step 3, item 8): every `attempt` line of the run after its `event name=protected-data-will-become-unavailable` line has `save=saved` (or `save=already-saved`), `readback=equal`, `file=ok` and `classes=ok`, and there is no `gap` line; after the restart the `previous-session` line has `result=ended-by-restart`, `lockedFailures=0` and `gaps=0`, its `lockedAttempts` and `classAUnreadable` at least 120 each, and its `lastRecordToBoot` at most 120 (seconds); the `verify` line has `result=ok`, `failures=0`, `integrity=ok`, `foreignKeyViolations=0`, `extra=0` or `extra=1`, and `classes=ok`, every class `NSFileProtectionCompleteUntilFirstUserAuthentication` except `class-a-canary.bin=NSFileProtectionComplete`; no crash report of the harness. A launch before the first unlock is an observation, not a criterion: a `launch` line with `protectedDataAvailable=false` before the first `event name=protected-data-did-become-available` after the restart, with `result=unreadable` and `result=could-not-read`, in the unified log (in the harness's log too, marked `written-late=`, if it was still running at the first unlock). Record "observed before the first unlock" or "not observed: iOS did not launch the harness before the first unlock"; either way 6.3's item for the app's own state before the first unlock stays pending. **Inconclusive** (record it and repeat): a `gap` line while locked, an `event name=audio` line with an interruption during the lock, fewer than 120 locked attempts, or a `lastRecordToBoot` above 120 without a crash report. **Failed:** an attempt of the run with `save=failed`, `readback=differs`, `readback=failed`, `file=failed` or `classes=differs:`, a `verify` line without `result=ok`, another class, or a crash report. Record: `step-3-build.log`, `step-3-harness.log`, `step-3-unified-log.txt`, `step-3-crash-logs.txt` and `step-3-results.txt` (the checklist's item 10); then delete G05 Lock from the phone. 25 min.
