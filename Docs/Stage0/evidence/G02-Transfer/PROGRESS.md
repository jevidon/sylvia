# G0.2 part 1 progress (pairing, Mac source service, contracts, host fault tests)

Updated after each deliverable. Final evidence is written by `Scripts/ci.d/40-g02-transfer.sh`
(`Scripts/ci.sh g02-transfer`); per-step logs in `ci/`, the clean run in `ci-clean-run.log`.

## Review of the earlier WIP commits

- **1809b7c** scaffolding only. Kept.
- **ebdf0be, 0824fd3, e5d072f ... 3ea0c2f** (second agent): reviewed by that agent; seven problems fixed then
  (idempotent stop, symlink containment, revoke-all on new key, approval timeout, idle limit, local-only Bonjour,
  unbounded memory in the 5 GiB run: `faults/large-5GiB-transfer-before-fix.log`).
- **e078c6c, e689d81** (unreviewed captures) and everything else re-read by the third agent on 7 Oct. Found and fixed:
  1. A pairing approval (120 s timeout) was cut off by the 60 s connection idle limit after the invitation had been
     consumed. Fixed (idle limit does not apply while a request is being handled); test
     `slowApprovalOutlivesTheConnectionIdleLimit` fails without the fix (`review/idle-limit-cut-off-approval-before-fix.log`).
  2. Content: the snapshot was opened after the library actor returned its path (race with invalidation). Now opened
     inside the actor; test `anOpenSnapshotKeepsServingItsVersionAfterInvalidation`.
  3. Snapshots: realpath check then clone by path (check-then-use race). Now each component is opened with
     O_NOFOLLOW from the root and cloned from the descriptor (`fclonefileat`, fallback `fcopyfile`).
  4. A large item's first manifest request could stay silent past the phone's request timeout. Now 503 `preparing`
     with Retry-After after 10 s, preparation continues, the client polls (`slowPreparationAnswersPreparingAndTheClientWaits`).
  5. Smaller: rate-limit table pruning; directory fsync after state-file renames; staging recovery after a stop between
     the final rename and the journal (`stopBetweenFinalMoveAndJournalKeepsTheVerifiedParts`); CLI prompt race on timeout;
     engine started requests after cancellation; rogue-host tests now count decrypted application bytes (0).

## Done

- Deliverables 1-6 implemented and tested. Host: TransferKit 53 tests, SourceService 44 tests + the 5 GiB test.
  Simulator (iPhone 17, iOS 26.5): TransferKit tests, hosted Keychain tests, and a pinned pairing plus 138 MB
  verified download from the simulator to `sylvia-source` (`simulator-pairing-run.log`).
- Scripted CLI runs over IPv4/IPv6 loopback, LAN, Tailscale IP and MagicDNS name (`cli-run-*.log`).
- Contracts: OpenAPI and nine schemas with fixtures; captured payloads validate (`ci/captured-payloads.log`).
- ADR-0008, ADR-0009 (Proposed); device checklist `Docs/Stage0/device-checklists/G02-Transfer.md`.

## Status

Part 1 complete. Report `Docs/Stage0/G02-Transfer.md`. Final clean run (all package, iOS and Xcode build products
deleted first, started after the last code change): `ci-clean-run.log`, all 14 steps pass.

## Next (G0.2 part 2)

Background URLSession download tasks with the pinned delegate, task reconciliation on launch, the harness UI the
device checklist needs (pairing paste field, manual address, Bonjour list, fingerprint display, progress).

## Known problems / limits

- Unsigned binaries cannot use the data-protection keychain on macOS (-34018); the CLI and host tests use the login
  keychain. The signed companion is needed to verify the after-first-unlock class on macOS (pending).
- Background URLSession with the pinned delegate is G0.2 part 2.
- `Scripts/validate-contracts.py` uses Python `re` (`$` matches before a trailing newline); schemas avoid relying on it.

# G0.2 part 2 progress (iOS background transfer client)

Started 7 Oct 2026 by the part-2 agent on top of 48b601f (part 1 complete; no part-2 WIP existed).

## Plan

1. `SylviaBackgroundTransfer` target in TransferKit: job store, task descriptors, launch reconciliation planner,
   background URLSession coordinator (pinned challenges, Range + If-Match + bearer header, synchronous move in
   didFinishDownloadingTo, verified-only part journal, assembly journal, stub importer with exactly-once ledger).
2. Host tests of that coordinator against the in-process source (download tasks in a default session).
3. `sylvia-test-source` (SourceService): the part-1 CLI plus test-only fault, throttle, connection-close and
   auto-approve options; `sylvia-source` itself stays fault-free.
4. iOS harness UI: pairing (paste, link, QR on device), fingerprint in fours, manual address, Bonjour browse,
   jobs with received vs verified, event log.
5. Simulator hosted tests (background session) and an XCUITest terminate-and-relaunch run; ATS probe matrix.
6. Report, ADR-0008/0009 extensions, device checklist, CI drop-in, clean run.

## Done (part 2)

- `SylviaBackgroundTransfer` (TransferKit): TaskDescriptor, JobStore/DurableFile, ReconciliationPlanner, StubImporter,
  ProgressText, BackgroundTransferCoordinator. Host unit tests: `swift test --package-path TransferKit` (planner,
  descriptors, importer crash windows, wording) pass.
- Host coordinator tests (`SourceService/Tests/.../BackgroundClientHostTests.swift`, in-process download tasks against
  the in-process source): full transfer, wrong digest, 7 bad responses, source change, revocation + relaunch,
  relaunch reconciliation, changed key. All pass; logs `background-host/*.log`.
- Found and fixed a part-1 server trap: a connection accepted after `stop()` dropped an unused NIOAsyncChannel
  ("NIOCore/NIOAsyncWriter.swift:177: Fatal error: Deinited NIOAsyncWriter without calling finish()"); seen once in
  the first host run of the new tests (receipts connecting while a test stopped the source). Fix in HTTPServer.swift.
- `sylvia-test-source` (SourceService): CLI moved to library `SylviaSourceCLI`; test-only options gated to the test binary.
- iOS harness (pairing, fingerprint in fours, manual address, Bonjour, jobs with received vs verified, events),
  ATS variant app target, hosted simulator tests, UI terminate/relaunch test, run scripts.
- First simulator run (iOS 26.5): background-session transfers with the pinned task-level challenge work for
  127.0.0.1, ::1, LAN IP, .local name; wrong digest refetched; source change detected; revocation blocks and keeps
  verified bytes across a relaunch. **Tailscale IP (100.64/10) and MagicDNS name fail: ATS blocks cleartext (-1022)
  and the pinned HTTPS fails (tlsFailure) with no ATS key.** ATS variants being measured next.
- Simulator reports no data-protection class on files (nil); the protection check is a device step.

## Done by the earlier part-2 agent after the notes above (from the WIP commits, re-checked by the next agent)

- ATS probe variants measured (`ats/ats-probe-*.log`); relaunch UI test runs (`simulator/relaunch-*.log`);
  CI drop-in steps `simulator-background` and `simulator-relaunch`; ADR-0008/0009 part-2 sections; checklist
  steps 13-18. The report `Docs/Stage0/G02-Transfer.md` was NOT yet updated for part 2.

## Resumed 12 Oct 2026 (third part-2 agent)

Review of the unreviewed WIP (c281e02, 1d36063 and earlier part-2 commits):
- TransferKit host tests re-run: 45 + 8 + 15 pass (`.build/scratch`, not evidence; the CI run is the evidence).
- Found: launch reconciliation could adopt a task whose completion the delegate had already received (the
  session's `allTasks` answer and its delegate events are not ordered). The adopted task would hold its part's
  slot and the job would never finish. Fixed (`completedBeforeReconciliation`), regression test
  `taskCompletedBeforeReconciliationIsNotAdopted` (host) through a test seam `start(beforeReconciliation:)`.
- ADR-0008 cited "Apple's documentation" for the iOS 17 IP-address ATS change; checked: the iOS 17 release
  notes as quoted by Apple DTS (developer forums threads 731217, 747421), which also confirm CIDR keys in
  NSExceptionDomains. Wording to be made precise.

- Also fixed: the trust guard failed on Swift comments naming an ATS key (first clean run failed only that step);
  the hosted test bundles linked the TransferKit products again, which made Xcode 27 print "missing a
  dependency" warnings (removed; tests take the modules from the host app).
- Re-read the relaunch event logs: tasks created during a background relaunch did not start while the app
  stayed suspended (discretionary per Apple's docs); the earlier ADR and checklist wording said the keep-alive
  run's background-created parts arrived, which was wrong. Report finding 4, ADR-0008/0009 and checklist step 13
  corrected; step 19 (QR and paste pairing) added.

## Status (part 2 complete)

- Final clean run from deleted build products at commit e936f1d: `ci-clean-run.log`, all 16 steps pass
  (host and simulator), no warnings from Sylvia code. Only documents changed after it.
- Report `Docs/Stage0/G02-Transfer.md` covers parts 1 and 2; ADR-0008 and ADR-0009 extended (Proposed).

## Next

- Device run of the checklist (steps 1 to 19); security review (step 12) and the Tailscale ATS decision.

## Known problems / limits (part 2)

- Tailscale address and MagicDNS name fail without an ATS exception (negative gate result, report finding 2).
- Background progress while suspended is unproven and may need tasks created in the foreground (finding 4).
- Data protection class, Keychain before first unlock, permission prompt: device only.

## Round 1 review fixes (12 October 2026)

Findings R1-01 to R1-11 and the reviewer's gate gaps; details in the report (findings 14 to 17) and the ADRs.

- R1-01 (blocker): HTTPServer wraps each connection and starts its serving task in the child initializer, under
  one lock with stop(); stress test `ServerStopStressTests` (trapped on the old code: `review/stop-trap-before-fix.log`);
  test cleanups awaited (`defer { await ... }`); host suite repeated (`review/sourceservice-repeat.log`).
- R1-02: captured/ emptied before host-sourceservice; captured-payloads requires all twelve files and a passing
  host-sourceservice step.
- R1-03: cleartext controls started in the script's own shell (PIDs kept); they also exit when orphaned; the
  script fails if anything it started is still running.
- R1-04: deferred launch (protected data, unreadable stores), stores refuse writes when unreadable; host tests.
- R1-05: local storage failures classified (insufficient_space at once, storage_unavailable after retries),
  reservation at job creation and resume; a real full volume (hdiutil disk image) in a host test. Found on the
  way: URL caches volume capacity, so the free space was stale (fixed: fresh URL per query).
- R1-06, R1-07: ADR-0009 wording; 5 GiB numbers described per run (the test log now separates faulted and
  in-flight extra requests).
- R1-08: SIGTERM handled with a dispatch source; no leaked continuation.
- R1-09, R1-10: pre-pairing address field in the harness; `PairingEntryUITests` (paste, link, rogue address) and
  `simulator-pairing-entry-run.sh`; checklist steps 1, 3, 19 rewritten. The new rows pushed "Pair" below the fold,
  so the UI tests now look above and below for an element (the relaunch test failed once on that).
- R1-11: identity store policy (data protection only by default; the CLI opts in to the login keychain).
- Gate gaps: 5 GiB through the background client with a relaunch (launch re-hash moved outside the lock);
  signed identity probe (`MacIdentityProbe`) not signed: first the team's Program License Agreement was not
  accepted, then (clean runs) Xcode reported "No Accounts" (checklist step 20, CI step listed as not run).
- Flaky test found: `changedSourceKeyPausesBeforeAnyRequestIsSent` counted requests before an in-flight one
  arrived; it now waits 300 ms first.
- Paste test: its Command-V fallback produced one failure in a clean run (no connection reached the source);
  removed; the test retries the edit menu and checks the field holds exactly the code; 3 of 3 runs passed
  (`review/pairing-entry-repeat.log`). Then the final clean run.

## Round 2 review fixes (12 October 2026)

Findings R2-01 to R2-06 and the reviewer's gate gaps; details in the report (findings 18 to 20) and the ADRs.

- R2-01 (major): launch no longer waits for isProtectedDataAvailable (logged only); it defers only when a store
  exists and cannot be read; a deferred background relaunch releases its completion handler; host test
  `lockedAfterFirstUnlockStillStartsReconcilesAndRequestsParts` (failed on the round 1 code:
  `review/round2-before-fix.log`).
- R2-02: system download errors classified as local storage (out of space, or file errors with less than a part
  free: insufficient_space; other file errors: storage_unavailable); reservation before every request, with free
  space read outside the lock (the first clean run caught a 425 ms wait when it was read under the lock:
  `review/round2-first-clean-run-failed.log`).
- R2-03: `LocalNetworkProbe` (connection path unsatisfied reason) after network failures; `localNetworkDenied`
  error and `local_network_denied` pause with the Settings next step; device steps 4 and 18.
- R2-04: final full-file check on its own queue; background completion held until it publishes; 5 GiB test
  times polls during "assembling"; `commit_ms` logged per part (part commits still hold the lock: finding 20).
- R2-05, R2-06: ADR-0008 custom URL scheme risk; checklist (signing prerequisite, Swift Testing line, step 8 via
  the inbox, steps 4, 8, 11, 12, 13, 15, 18 updated, new step 21).
- Gate gap: device inbox in the coordinator and harness ("Check inbox"); `--test-send-on-pair` in
  sylvia-test-source; host and simulator tests.
- Test races found in repeat runs and fixed: wait for a stopped coordinator to go quiet; wait for the part 3
  request instead of "3 verified, 1 outstanding". Then the final clean run (`ci-clean-run.log`).

## Round 3 review fixes (13 October 2026, NZDT)

Branch `m0-int-minors-g02-transfer`, from the integration commit `b354dc7`. Findings R3-01 to R3-06 and the
reviewer's gate gaps; details in the report (findings 21, 22) and the ADRs.

First agent (WIP commits `ece6965` to `ce8e41c`; it was stopped and restarted):
- R3-01: free space read before reconcile takes the lock, `spaceShortfallLocked` per job before its launch
  requests; host test `relaunchWithTooLittleSpacePausesBeforeAnyRequest` failed on the round 2 code
  (`review/round3-before-fix.log`).
- Gate gap: `--qr` draws the pairing link as a QR code on `/dev/tty` only (`PairingQRCode`, Vision decode test,
  `qr-terminal-check.py` in CI step `cli-qr`).
- R3-03: the checklist's "logging source" command line (tee to the terminal, redacting sed into `source.log`),
  checked on a pseudo-terminal by `logging-source-recipe-check.py` (CI step `cli-logging-recipe`).
- R3-06: `device-ats-probe.sh` runs `ATSProbeTests` on a phone with inline inputs (CI step
  `simulator-ats-device-recipe` tries it on the simulator); checklist steps 10 (R3-02), 22 (R3-04) and 23 (R3-06);
  ADR-0009 and report wording (R3-04, R3-05, R3-06).
- Its first clean run failed the 5 GiB background-client test's 1 s budget at a load average of about 130
  (`review/round3-first-clean-run-failed.log`); three re-runs passed (`review/round3-5gib-repeat.log`).

Second agent (re-checked all of the above as unreviewed; the code changes held):
- Found and fixed: ADR-0008 had no round 3 change (it still said the QR code is not drawn, that the four-task
  window bounds the token copies, and stated the ATS conclusions without "simulator"); the QR test called eight
  71-character endpoints "the largest payload the protocol allows" (a link at the protocol's limits, eight
  253-character names, is valid but does not fit a QR code; the test now shows it is refused); report finding 22
  cited a check time and a commit time from a test log the re-runs had overwritten (removed); "one part per
  outstanding task" for the reservation, which is one part per window slot; checklist step 19's column figure.
- Added: `import_ms` on the `imported` event, the job state the slowest poll returned and the load averages in the
  5 GiB logs, and the CI step now deletes old 5 GiB logs first and prints them even when a test fails, so a failing
  run's diagnosis is kept.
- M0 integration open item: `MacIdentityProbe/Package.resolved` and `iOS/Package.resolved` committed (each pins
  exactly what `SourceService`'s and `TransferKit`'s lock pin; Xcode kept them unchanged when resolving), checked
  by the new CI step `package-locks` (`package-locks.log`).
- Final clean run at `41b93e7` (build products deleted, simulator `Sylvia-M0-minors-g02-transfer` recreated):
  `ci-clean-run.log`, contracts pass, 21 of the drop-in's 22 steps pass, `mac-identity-signed` not run (Xcode:
  "No Accounts"). Load average 132 at the start. Only documents and evidence summaries changed after it.
- Development 5 GiB run kept as `review/round3-5gib-dev-run.log` (full-file check 29 s as the load rose to 67).

## Status (round 3 complete)

All six round 3 findings are closed in code or documents, or have device or human steps (report finding 21).
Still pending: the device run of the checklist (steps 1 to 23, signing first), the security review (step 12), the
Tailscale ATS decision, the signed identity probe (step 20), and the product owner's decision on a bound across
jobs (open question 3).

Shared files this round needs changed by their owners (not edited here): ADR-0014's note that the two G0.2 Xcode
projects have no committed lock, and its open item for `MacIdentityProbe` (both now commit locks, `package-locks.log`);
the matching G0.2 open item in `Docs/Stage0/integration-log.md` section 6.
