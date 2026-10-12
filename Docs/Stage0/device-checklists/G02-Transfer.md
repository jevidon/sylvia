# G0.2 transfer: physical-device and human checklist

Everything here is **pending** until a person runs it on the hardware named and records the result. Nothing below was inferred from the simulator or the host tests. Report: `Docs/Stage0/G02-Transfer.md`; decisions: ADR-0008, ADR-0009.

## Before you start

- Mac: the build Mac (macOS 26.x) on the same Wi-Fi as the phone, Tailscale installed and logged in for steps 6 and 7.
- Phone: the paired iPhone 17 Pro (iOS 26.7) and, for step 11, the oldest supported iPhone when available. Developer Mode on.
- Code signing (every phone step, and step 20): the harness and the hosted tests must be signed for team A4KBDX665Z. Xcode on the build Mac needs the team's account (Xcode > Settings > Accounts), and the team's latest Program License Agreement must be accepted at developer.apple.com. On 12 October 2026 this Mac had neither (Xcode reported "No Accounts"; earlier the agreement was not accepted: `Docs/Stage0/evidence/G02-Transfer/keychain-identity-signed*.log`). Check first by building the scheme `G02TransferHarness` for the iPhone once in Xcode; a "No Accounts", provisioning or license error means this must be fixed before any step below.
- Build the Mac source: `source Scripts/lib/env.sh && xcrun swift build --package-path Spikes/G02-Transfer/SourceService --product sylvia-source`. The binary is in `Spikes/G02-Transfer/SourceService/.build/debug/sylvia-source`.
- Phone harness: the app `G02TransferHarness` ("Sylvia Transfer Spike", `Spikes/G02-Transfer/iOS`; `sylvia_generate Spikes/G02-Transfer/iOS`, open `G02Transfer.xcodeproj`, scheme `G02TransferHarness`, team A4KBDX665Z, run on the iPhone). It has a pairing field (paste the code or link; "Scan QR code" on a device), the fingerprint in groups of four, "Browse catalog" and "Download", "Check inbox" and "Download from inbox" (what the Mac queued with `send`), a manual "Host or IP" + "Port" field, "Browse the local network" (Bonjour), the transfer list (stage, "received", "verified", parts, Pause/Resume/Cancel, the next step when paused) and recent events. Step 1 uses the hosted tests of the same project.
- The app keeps an event log with IDs, counts, addresses and app states only (no codes, tokens or titles): `Library/Application Support/Transfers/events.jsonl` in its container. Download it with Xcode > Window > Devices and Simulators > the app > Download Container, and attach the `.jsonl` file to the step record. `Spikes/G02-Transfer/Scripts/analyze-relaunch.py <events.jsonl> <source output>` summarises it per launch.
- For a source that logs requests with timestamps (needed in steps 13 to 17), build `sylvia-test-source` the same way (`--product sylvia-test-source`) and add `--test-log-requests`; do not use any other `--test-*` option on a device run unless the step says so.
- Record each step in `Docs/Stage0/evidence/G02-Transfer/device/<NN>-<short-name>.md` with: date, device model and iOS version, Mac macOS version, the commit hash, pass or fail, what was seen, and the attached screenshots or logs named in the step. Never put a pairing code, token or invitation secret in a screenshot or log: redact the code line (`[pairing code redacted]`).

## Steps

### 1. Keychain class of the transfer token on a device (plan 14.2)

1. Generate the project (`source Scripts/lib/env.sh && source Scripts/lib/xcodegen.sh && sylvia_generate Spikes/G02-Transfer/iOS`), connect the iPhone, then run only the Keychain tests (the scheme's other tests need the simulator scripts' environment and would fail here):
   `cd Spikes/G02-Transfer/iOS && xcodebuild test -project G02Transfer.xcodeproj -scheme G02TransferHarness -destination 'platform=iOS,name=<the iPhone>' -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z -only-testing:G02TransferHostedTests/KeychainCredentialStoreTests`
2. **Expected:** `✔ Test run with 3 tests in 1 suite passed` and `** TEST SUCCEEDED **`: the stored item reports `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and is not synchronizable. These are Swift Testing tests, so xcodebuild's XCTest line says `Executed 0 tests, with 0 failures`; that line is expected and is not a failure.
3. **Record:** the last 20 lines of the xcodebuild output.

### 2. Pinned pairing and verified download from the phone, over Wi-Fi (T36, T43)

1. On the Mac: `sylvia-source --root <folder with one EPUB> --lan --bonjour --name "Device test Mac"`. Note the printed fingerprint and the LAN endpoint.
2. On the phone, open the part 2 harness pairing screen and paste the printed code (send it through a channel you control, for example AirDrop of a text file you delete afterwards, not a cloud note).
3. When iOS asks for local-network access, allow it.
4. On the Mac, compare the fingerprint in the prompt with the one the phone shows (groups of four), then type `y`.
5. **Expected:** pairing succeeds; the download completes; the phone reports the same SHA-256 as `shasum -a 256 <file>` on the Mac; the Mac's `devices` command lists the phone.
6. **Record:** the Mac terminal output (code line redacted), a phone screenshot showing the fingerprint, and the digest comparison.

### 3. Wrong pin and rogue host from the phone (T36)

The simulator runs this with two sources on the Mac's loopback (`simulator/pairing-entry.log`); here the phone reaches the rogue source over Wi-Fi.

1. Start a second source with a different key on another port: `sylvia-source --root <any folder> --lan --port <P2> --ephemeral-identity --name Rogue`.
2. On the phone, paste the genuine source's code and tap "Check code". Before tapping "Pair", type the rogue source's LAN address and port into "Other host or IP" and "Port" under the fingerprint and tap "Use address" (the status line then says "Pairing will connect only to <address>:<P2>"; the fingerprint stays the genuine one). Tap "Pair".
3. **Expected:** the status line says `pairing failed: pinMismatch`; the rogue terminal shows no pairing request and no approval prompt; the Mac prompt of the genuine source does not appear either. Then paste the same genuine code again, check it and pair without changing the address: it succeeds (the invitation was never presented to the genuine Mac, so it is still unused).
4. **Record:** both Mac terminals (codes redacted) and the phone's status line after each attempt.

### 4. Local-network permission denied (T43)

1. Delete the harness app, reinstall, start pairing over the LAN address, and choose "Don't Allow" at the local-network prompt.
2. **Expected:** the pairing status line says `pairing failed: local network access is off for this app. Turn on Local Network for Sylvia in Settings > Privacy & Security > Local Network, then pair with a new code from the Mac. Nothing was sent.` (the client recognizes the denial from the network path's unsatisfied reason, `LocalNetworkProbe`, ADR-0008); no secret was sent (the Mac shows no pairing request); after allowing in Settings, pairing with a new code succeeds. If the status line instead says `pairing failed: unreachable` (or another raw error), the denial was not recognized on this iOS version: record it as a failure of the classification, with the exact text. The classification was tested only on the host, with a substituted answer (`background-host/local-network-check-*.log`).
3. **Record:** screenshots of the error and of the successful retry; the Mac terminal.

### 5. Bonjour discovery on the LAN (plan 15.1)

1. With the source started with `--lan --bonjour`, open the harness's discovery list.
2. **Expected:** "Device test Mac" appears; selecting it still requires the pairing code and fingerprint (discovery alone grants nothing).
3. **Record:** screenshot of the list.

### 6. Tailscale address from the phone on cellular (T43)

The simulator showed that App Transport Security refuses the self-signed, pinned connection to a Tailscale address (100.64.0.0/10) and to a MagicDNS name (`*.ts.net`) after the pin matched (error -1200, stream -9802), unless the app declares a per-domain exception (`Docs/Stage0/evidence/G02-Transfer/ats/`). This step checks the same on a device, with both builds.

1. Phone: Wi-Fi off, cellular on, Tailscale connected. Mac: `sylvia-source --root <folder> --bind <Mac's Tailscale IPv4> --advertise-host <Mac's MagicDNS name>`.
2. With `G02TransferHarness` (no ATS key): pair with the printed code. **Expected (from the simulator; confirm or contradict):** pairing fails with a TLS failure and the Mac shows no pairing request (nothing was sent). Then try a manual address with the Tailscale IP and with the MagicDNS name on a source paired over the LAN first: both refused the same way.
3. With the ATS probe app (scheme `G02TransferATSVariant`, build setting `G02_ATS_VARIANT=tailnet-exception`, app "Sylvia ATS Probe"): pair and download one file through the IP and through the MagicDNS name. **Expected:** both work; no public port or relay is involved (the Mac binds only the Tailscale address); the digests match.
4. **Record:** Mac terminal (redacted), phone screenshots of both builds, the event logs, and `tailscale status` showing both devices (redact the tailnet name). The decision on shipping such an exception is an open question in ADR-0008; this step only measures.

### 7. Manual LAN address without multicast (T43)

1. Mac: `sylvia-source --root <folder> --bind <Mac's LAN IPv4>` (no `--bonjour`).
2. Pair by entering the address manually.
3. **Expected:** works without any Bonjour advertisement.
4. **Record:** Mac terminal and phone screenshot.

### 8. Token after reboot and while locked (plan 14.2, 18.1)

Two different states, which the client must treat differently: **before the first unlock** after a restart the store (class C) and the token cannot be read and the client defers its launch; **locked after the first unlock** both are readable and the client must start and run (a background relaunch while locked must not defer). `UIApplication.isProtectedDataAvailable` is false in both states, so the client does not use it (review finding R2-01); the harness only logs it.

1. Pair, then queue a large item for the phone on the Mac: `items` lists the item IDs, `devices` the phone's device ID, then `send <item-id> <device-id>` (the Mac prints `queued <entry-id> ... state queued_on_mac`). On the phone, under the paired Mac, tap "Check inbox": the entry appears as `observed_by_phone` (the Mac's `queue` command shows the same). Tap "Download from inbox: <title>" to start the background download. ("Browse catalog" > "Download <title>" also starts a download, but then no queue entry is acknowledged.)
2. Restart the phone and do not unlock it. Wait five minutes with the Mac source running.
3. **Expected:** no bytes are fetched before the first unlock (neither the token nor the job store is readable; the client defers its launch, step 15); the job keeps its verified parts; nothing is deleted.
4. Unlock once, then lock the phone again and leave it for ten minutes.
5. **Expected:** the background download continues while locked (after first unlock the token is readable) or waits for the system to schedule it; it never claims Ready before the full SHA-256 check. In `events.jsonl`: `protected_data_will_become_unavailable` when the phone locks; if iOS relaunches the app in the background while the phone stays locked, its `app_launch` has `protected_data_available=false` and is followed by `coordinator_start` (also `protected_data_available=false`) and `launch_reconciliation`, **never** `start_deferred` or `background_events_released`. A `start_deferred` while locked after the first unlock fails this step.
6. **Expected after the import:** the Mac's `queue` command shows the entry `imported_into_sylvia` (the phone's receipts named it).
7. **Record:** the Mac request log (`queue` and terminal output), the phone's job state before and after unlock, `events.jsonl`, and the times of the restart, the unlock and the lock.

### 9. Mac sleeps or quits mid-transfer (plan 15.1, 15.5)

1. Share the 5 GiB generated file (`Scripts/fixtures/generate-g02-transfer-large.sh --print-path`) and start downloading it on the phone.
2. At about 30 %, put the Mac to sleep for two minutes; wake it; later, quit `sylvia-source` and start it again with the same `--state` directory.
3. **Expected:** the phone pauses with "Make sure the Mac is awake, running Sylvia and reachable"; on resume it requests only parts not yet verified (check the Mac's request log or the phone's part counts); the final file's SHA-256 is `d2383fe38d8033b62ef9e6222756369fab813d2c64b2bce41e86ad9494af16d9`.
4. **Record:** phone screenshots of the paused and finished states, and the part counts before and after.

### 10. Revocation and a changed Mac key during a device transfer (T37)

1. During a download, run `revoke <device-id>` on the Mac.
2. **Expected:** the phone pauses with "This iPhone's access was removed on the Mac. Pair again to continue." and keeps verified bytes.
3. Pair again; then stop the source, delete its identity (`--state` directory's `identity.json` and the Keychain item `com.jevidon.sylvia.source.identity`, or start with a new `--state`), start it again and resume.
4. **Expected:** the phone pauses with the identity-changed message and offers re-pairing only; there is no "trust anyway" option.
5. **Record:** screenshots of both messages.

### 11. Memory and time on the oldest supported iPhone (T38, plan 19.1)

1. On the oldest supported iPhone, download the 5 GiB file with two interruptions (airplane mode for 30 seconds twice).
2. **Expected:** completes with the pinned digest; the app's memory (Xcode memory gauge or Instruments Allocations) stays flat rather than growing with the file; note the peak.
3. Watch the screen while the job shows "Checking the whole file" (the final full-file SHA-256 of 5 GiB) and while parts arrive. **Expected:** the screen keeps updating (the recent-events list moves, "Pause" responds) throughout: the check runs outside the coordinator's lock (review finding R2-04). Note the `milliseconds` value of the `assembly_verified` event (the check's duration) and of `staging_checked` after a relaunch. If the screen freezes for more than about half a second when a part arrives, note it: each part's 16 MiB copy and hash still holds the lock (ADR-0009 open item). For a measurement, run Instruments with the Hangs or Time Profiler instrument and record any hang it reports.
4. **Record:** peak memory, total time, the two `milliseconds` values, any hang, and screenshots.

### 12. Human review of the pairing protocol (gate G0.2)

1. A security reviewer reads ADR-0008 (including the interception risk of the `sylvia://` link: iOS does not reserve custom URL schemes, so another app may receive a tapped or Camera-scanned link with the pin and the invitation secret, and the device name on the Mac's prompt is chosen by the requester; in-app scanning and pasting are not exposed), `Contracts/openapi/source-service.v1.yaml` and `Spikes/G02-Transfer/SourceService/Sources/SylviaSourceService/PairingAuthority.swift`, `Router.swift`, `HTTPServer.swift`, `Spikes/G02-Transfer/TransferKit/Sources/SylviaTransferClient/PinnedSession.swift` and `Spikes/G02-Transfer/TransferKit/Sources/SylviaBackgroundTransfer/BackgroundTransferCoordinator.swift` (the background session's trust answer), and decides the ATS question in ADR-0008 (Tailscale exception or not).
2. **Expected:** written approval, or a list of required changes, recorded in ADR-0008's Deciders line and Open items. An agent review does not replace this sign-off.
3. **Record:** `Docs/Stage0/evidence/G02-Transfer/device/12-security-review.md` with the reviewer's name, date and verdict.

### 13. Background download while the app is suspended and the phone is locked (plan 6.4, 15.2 gate)

On the simulator (`Docs/Stage0/evidence/G02-Transfer/simulator/relaunch-*.log`, raw event lines): after the app was killed, tasks created in the foreground kept running in the system's daemon; about 4 s later the system relaunched the app in the background once, delivered the finished parts, and the app answered the waiting trust challenges of foreground-created tasks (`app_state=background_relaunch`). The tasks the app created during that background relaunch opened no connection in the following 59 s, and the system did not wake the app again in that time, so finished parts waited for the next launch. Apple documents that transfers started while the app is in the background are treated as discretionary; the simulator cannot tell that apart from tasks waiting for a trust answer. A device may schedule differently, and on battery or cellular it may defer discretionary tasks for longer; this step measures it.

1. Mac: `sylvia-test-source --root <folder with the 5 GiB file> --lan --test-log-requests > source.log`. Pair, start the download, wait for two verified parts.
2. Press the side button (lock) and leave the phone untouched for 15 minutes; do not open the app.
3. **Expected (to be measured, not assumed):** the Mac's request log keeps receiving part requests while the phone is locked; the app's event log shows `trust_challenge` entries with `app_state=background` or `background_relaunch` for new connections and `part_verified` entries in those states. The phone was unlocked before, so every launch while it is locked must start the client: `coordinator_start` and `launch_reconciliation` with `protected_data_available=false` are expected, and `start_deferred` fails this step (review finding R2-01: an earlier version deferred every launch while the phone was locked, which would have made this step measure a stall caused by the app). `background_events_finished` should follow each background relaunch. Note how long the transfer stalls, if it does, and whether it resumes without opening the app. For every `part_requested` entry with `app_state=background` or `background_relaunch`, note when (if ever) `source.log` shows that range: this tells whether tasks created in the background run while the phone stays locked.
4. Repeat with `--test-close-connections` added to the source. **Expected:** to be measured; if progress stops until the app is opened, record the stall length. This decides whether the background claim needs more tasks created while the app is in the foreground, long-lived connections, a certificate the system can validate without the app, or a foreground-only promise (ADR-0008, report finding 4).
5. **Record:** `source.log`, the app's `events.jsonl` (container download), timestamps of lock and unlock.

### 14. Force-quit from the app switcher mid-transfer (T41)

1. Start a download of the 5 GiB file; after a few verified parts swipe the app away in the app switcher.
2. Wait two minutes, watching the Mac's request log, then open the app.
3. **Expected:** iOS cancels the app's background tasks after a force-quit (no requests reach the Mac while the app is closed); on opening, the launch reconciliation (top of the screen) shows the verified parts kept, the cancelled tasks gone and only missing parts requested; the transfer finishes with the pinned digest and "Imported" once.
4. **Record:** screenshots of the reconciliation line and the finished job, `events.jsonl`, the Mac's request log.

### 15. Reboot before first unlock with a transfer in progress (plan 18.1, T41)

Before the first unlock the transfer store's files (class C) and the token cannot be read. The client detects that from the files themselves (a store that exists but cannot be read) and defers its whole launch: it creates no session (so it neither adopts nor cancels any outstanding task), pauses nothing and writes no store; if the launch was a background relaunch it releases the system's completion handler at once (`background_events_released`); it starts again when iOS reports protected data available, or at the next launch (`start_deferred` and `protected_data_available` in the event log). The event log (`events.jsonl`) is a class C file too, so entries from before the unlock may be missing; the Mac's request log is the primary evidence. On the host this is tested with files made unreadable (`background-host/unreadable-stores-deferred.log`); whether iOS relaunches the app before the first unlock at all, and what the system does with the outstanding background tasks meanwhile, only a device shows.

1. Start a download; after a few verified parts restart the phone and do not unlock it for five minutes.
2. **Expected:** no request reaches the Mac before the first unlock. If the app is launched in that time (it may not be), its event log has `start_deferred` with the reason `sources_not_accessible`, `imports_unreadable` or `job_store_not_accessible` and nothing else from the transfer client (no `launch_reconciliation`, no `paused`, no `blocked_at_launch`). After unlocking: `protected_data_available` (if the app was running), then one `launch_reconciliation` that keeps the verified parts; the transfer finishes and is imported once. Nothing verified is lost and `sources.json` still lists the paired Mac.
3. **Record:** the Mac's request log with timestamps, `events.jsonl` (`start_deferred`, `protected_data_available`, `launch_reconciliation`, `store_protection`), screenshots before and after unlocking.

### 16. Wi-Fi loss and Mac sleep during a background transfer (plan 15.1, 15.5)

1. Start a download; turn Wi-Fi off on the phone for two minutes, then on. Later, put the Mac to sleep for two minutes.
2. **Expected:** no part is accepted unless its digest verified; the job retries or waits (`waiting_for_connectivity` or `part_failed` with a transport error in the event log), never claims Imported early, and finishes without re-fetching verified parts.
3. **Record:** `events.jsonl`, the Mac's request log, screenshots of the job while waiting.

### 17. Data protection class of the transfer store (plan 18.1)

1. Open the harness once on the device.
2. **Expected:** the event log's `store_protection` entry reports `NSFileProtectionCompleteUntilFirstUserAuthentication` for `store_folder`, `events.jsonl` and `sources.json` (the simulator reports none, so this is device-only).
3. **Record:** the `store_protection` line from `events.jsonl`.

### 18. Local-network permission prompt timing in the harness (T43, plan 15.1)

1. Fresh install of the harness. Tap "Browse the local network" before pairing.
2. **Expected:** iOS shows the local-network prompt with the harness's explanation ("Sylvia connects to the Mac you paired with on your network..."); after "Don't Allow", Bonjour finds nothing; pairing over the LAN address shows the Settings next step of step 4; for an already paired Mac, "Use" with its LAN address says `did not work: Turn on Local Network for Sylvia in Settings > Privacy & Security > Local Network, then resume. Verified parts are kept.`; a transfer that was running pauses as `local_network_denied` with that next step (events `local_network_checked denied=true`, then `pause_reason_refined`), not with "Make sure the Mac is awake". Record exactly what each says; a raw error such as `unreachable` means the denial was not recognized.
3. **Record:** screenshots of the prompt and of each failure; `events.jsonl`.

### 19. Pairing by QR code on the phone (plan 15.2)

Pasting the code and opening a `sylvia://pair/v1#...` link run on the simulator (`simulator/pairing-entry.log`); only the camera needs a device.

1. Mac: `sylvia-source --root <folder> --lan --name "Device test Mac"`. Turn the printed `sylvia://pair/v1#...` link into a QR code on the Mac without sending it to any online service (for example the Shortcuts app's "Generate QR Code" action, shown on screen only).
2. Phone: in the harness, tap "Scan QR code" and scan it. **Expected:** the source name, addresses and the fingerprint in 16 groups of four appear and nothing is sent until "Pair" is tapped; the fingerprint matches the Mac's; after approval on the Mac the phone shows "Paired with Device test Mac" and the code field is empty.
3. **Record:** phone screenshots of the fingerprint screen (code line redacted) and of the paired state; the Mac terminal (code line redacted).

### 20. The Mac identity key from a signed app (ADR-0008; human step on the build Mac)

The signed probe (`Spikes/G02-Transfer/MacIdentityProbe`) could not be signed on 12 October 2026: Xcode could not create a development profile for team A4KBDX665Z, first because the team's Program License Agreement had not been accepted (`keychain-identity-signed-first-attempt.log`), then in the clean runs with "No Accounts" (`keychain-identity-signed.log`). The unsigned tools' store is tested on the host and now never falls back to the login keychain unless asked to (`keychain-identity-policy.txt`).

1. The account holder signs in at developer.apple.com and accepts the latest Program License Agreement for team A4KBDX665Z, and checks that Xcode on the build Mac lists the team's account (Xcode > Settings > Accounts).
2. On the build Mac: `Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh Docs/Stage0/evidence/G02-Transfer/keychain-identity-signed.log` (or the whole `Scripts/ci.sh g02-transfer`, whose step `mac-identity-signed` runs it).
3. **Expected:** `RESULT: PASS` with `G02-PROBE backend: data-protection keychain`, a `kSecAttrAccessible` value equal to the one printed for `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on the same line, `kSecAttrSynchronizable: false`, an access group ending in `com.jevidon.sylvia.spike.identityprobe`, and no item in the login keychain.
4. **Record:** commit the regenerated `keychain-identity-signed.log` and update the report row "Mac identity key in the Keychain".

### 21. A full phone during a background download (plan 15.4; review finding R2-02)

For a background session the system writes each 16 MiB part into the app's container itself before the app sees it. When that write fails on a full phone the task ends with an error and the app never gets the file; the client classifies such errors as this phone's storage (`insufficient_space` at once when out of space or when less free space than a part remains, otherwise `storage_unavailable` after retries), never "Make sure the Mac is awake". On the host this was tested with an injected task error and a substituted free-space figure (`background-host/system-download-not-stored-*.log`) and with a really full disk image for the app's own writes (`background-host/full-phone-storage.log`); which error iOS reports for its own failed write is unknown until this step.

1. Start a download of the 5 GiB file. When about a quarter is verified, fill the phone's storage until Settings > General > iPhone Storage shows less than about 100 MB free (for example by recording a long 4K video, or by copying large files into Files > On My iPhone), without closing the harness.
2. **Expected:** the job pauses with "Free up space on this iPhone, then resume. Verified parts are kept." (`insufficient_space`), either from the reservation before the next request (`space_check_failed`) or from a failed part (`system_download_not_stored`, or `part_failed failure=localStorageFull`); it does not end as `source_unreachable`; verified parts are kept. Note the exact `error=` value of any `system_download_not_stored` entry (the error domain and code iOS used).
3. Delete the filler and tap "Resume". **Expected:** the transfer finishes with the pinned digest and requests only parts not yet verified.
4. **Record:** `events.jsonl`, screenshots of the paused and finished states, and the free space shown in Settings at the pause.
