# G0.2 step 20: why the signed Mac identity probe failed on 27 October 2026, and the fix

This folder records the diagnosis and fix of the one failure in your signed run of runbook 0.7 (G0.2 checklist step 20; ADR-0008). The work is on branch `m0-g02-probe-fix`, made from `m0-decisions` at `c72247a6`. Commits: `7d944c28` adds the diagnostic test, `d8ed94a2` fixes the identity test, and the commits after them add these logs and this README.

**Environment:** the build Mac (host): macOS 26.6.2 (25G83), Xcode 27.1 (27A9275), the pinned toolchain. The probe was signed by Xcode's automatic signing as "Apple Development: JUSTIN EVIDON (8CRWY2K873)", team A4KBDX665Z, with the keychain access group `A4KBDX665Z.com.jevidon.sylvia.spike.identityprobe` (each run log's codesign section). No simulator and no device were used. The network was used only by Xcode's signing (`-allowProvisioningUpdates`), by the checkouts of the pinned package versions that `xcodebuild` and `swift test` made for fresh build folders (no lock changed), and for the Apple pages below. Nothing was pushed or fetched from the repository's remote. Times are UTC, with the build Mac's clock (NZDT) where a log gives it. Other jobs shared the Mac (each log header records `uptime`), so no timing here is a result.

**Status:** written by an agent and not reviewed. Nothing here is a device result, a role sign-off, an ADR approval (decision D-6) or the M0 exit. Step 20 passes only when your own re-run passes (see "What you do next"). An agent's run on this Mac stands in for it only if you decide so.

## 1. The failure (your record)

Your log is `~/Git/sylvia-sessions/Docs/Stage0/evidence/G02-Transfer/keychain-identity-signed.log`. It is uncommitted on `m0-decisions` and was last written at 04:43:37 NZDT on 27 October 2026. This branch neither copies nor changes it. It says:

```
--- test output (xcodebuild exit 65)
✘ Test identityKeyIsInTheDataProtectionKeychainAfterFirstUnlockThisDeviceOnly() recorded an issue at DataProtectionKeychainTests.swift:36:9: Expectation failed: legacy.isEmpty
G02-PROBE backend: data-protection keychain
G02-PROBE items for the service in the login (file-based) keychain: 1
G02-PROBE kSecAttrAccessGroup: A4KBDX665Z.com.jevidon.sylvia.spike.identityprobe
G02-PROBE kSecAttrAccessible: cku (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly is cku)
G02-PROBE kSecAttrSynchronizable: false
G02-PROBE reloaded the same identity (same SPKI pin and source ID): true
RESULT: FAIL (full log: .build/scratch/g02-identity-probe/xcodebuild.log)
```

Every expectation of ADR-0008 held except one: "nowhere else". The test's "legacy" query (`DataProtectionKeychainTests.items(service:dataProtection: false)` at `c72247a6`) left out `kSecUseDataProtectionKeychain` and found one item. Its service, `com.jevidon.sylvia.spike.identityprobe.test.<UUID>`, is unique to the run. The store with its default policy `.dataProtectionOnly` adds the key only with `kSecUseDataProtectionKeychain` true (`SourceIdentity.swift`: `keychains` is `[true]`, used by `writeKey`).

## 2. Diagnosis: the check counted the data protection item a second time

There were two possible readings. Either the query without the flag also returns data protection items to a signed app with an access group, so the one item was the key itself counted twice; then the storage meets ADR-0008 and the check is wrong. Or the store left a second copy in the login keychain, which ADR-0008 forbids. **The first reading holds.** The evidence:

**(a) The query without the flag returned the data protection item itself.** The diagnostic test `KeychainQueryDiagnosticTests` (commit `7d944c28`) creates the key through the store, as the identity test does. It prints every item each query returns, attributes only. Run alone on `7d944c28` (`diagnostic-run1.log`), the query with the flag and the query without it returned the same item, with the same access group, the same class, the same creation time to the millisecond and the same attribute names:

```
G02-DIAG created | store's item | data protection | item 1: kSecAttrAccessGroup A4KBDX665Z.com.jevidon.sylvia.spike.identityprobe, kSecAttrAccessible cku, kSecAttrSynchronizable 0, kSecAttrLabel Sylvia source identity key, kSecAttrCreationDate 2026-10-26T16:10:48.623Z; attribute keys returned: accc acct agrp cdat labl mdat musr pdmn sha1 svce sync tomb
G02-DIAG created | store's item | unspecified | item 1: kSecAttrAccessGroup A4KBDX665Z.com.jevidon.sylvia.spike.identityprobe, kSecAttrAccessible cku, kSecAttrSynchronizable 0, kSecAttrLabel Sylvia source identity key, kSecAttrCreationDate 2026-10-26T16:10:48.623Z; attribute keys returned: accc acct agrp cdat labl mdat musr pdmn sha1 svce sync tomb
```

On macOS a generic password has `kSecAttrAccessGroup` and `kSecAttrAccessible` only "if kSecAttrSynchronizable and/or kSecUseDataProtectionKeychain set" (the pinned SDK's `SecItem.h`, lines 88-89; `apple-pages.txt`). An item that carries them is therefore the data protection keychain's.

**(b) No query that names the file-based keychains found anything for the store's service.** This held for `kSecUseDataProtectionKeychain` false, for `kSecMatchSearchList` with the login keychain alone, for `kSecMatchSearchList` with the whole search list (`login.keychain-db`, `System.keychain`), and for both keys together:

```
G02-DIAG summary | file-based [kSecUseDataProtectionKeychain false]: store's item 0 -> 0; test's file-based item 1 -> 0
G02-DIAG summary | login keychain [kSecMatchSearchList [login.keychain-db]]: store's item 0 -> 0; test's file-based item 1 -> 0
G02-DIAG summary | search list [kSecMatchSearchList [every keychain of the user's search list]]: store's item 0 -> 0; test's file-based item 1 -> 0
G02-DIAG summary | file-based, search list [kSecUseDataProtectionKeychain false and kSecMatchSearchList [every keychain of the search list]]: store's item 0 -> 0; test's file-based item 1 -> 0
```

**(c) The query without the flag reaches both keychains.** The diagnostic also adds a file-based item of its own, without the flag and under its own service. The same flagless query returned it too. It came back with no access group or class, a creation time in whole seconds, and the file-based attribute names. The data protection query did not see it.

```
G02-DIAG created | test's file-based item | unspecified | item 1: kSecAttrAccessGroup none, kSecAttrAccessible none, kSecAttrSynchronizable none, kSecAttrLabel Sylvia identity probe control item (not a secret), kSecAttrCreationDate 2026-10-26T16:10:48.000Z; attribute keys returned: acct cdat class labl mdat svce
G02-DIAG summary | data protection [kSecUseDataProtectionKeychain true]: store's item 1 -> 0; test's file-based item 0 -> 0
G02-DIAG summary | unspecified [no kSecUseDataProtectionKeychain, as the identity test's check in the owner's run]: store's item 1 -> 0; test's file-based item 1 -> 0
```

Apple's TN3137 (revised 2026-09-24; read on 27 October 2026, `apple-pages.txt`) says: "The SecItem API can target either implementation. It defaults to targeting the file-based keychain." That matches where `SecItemAdd` without the flag put the test's own item: in the login keychain, found by `kSecMatchSearchList [login.keychain-db]`. It does not describe what `SecItemCopyMatching` without the flag returned here: the data protection keychain's items as well, in this signed app on macOS 26.6.2. This record does not explain why. It shows what the queries returned, and the fix relies only on queries that name the keychains they search.

**(d) Your run's failure reproduces, with the cause seen in the same process.** Run 1 used your command (runbook 0.7) on `7d944c28`, where the identity test is unchanged. It failed exactly as your run did: the same issue at `DataProtectionKeychainTests.swift:36:9`, `Expectation failed: legacy.isEmpty`, and the same six G02-PROBE lines (`keychain-identity-signed-run1.log`). The diagnostic passed in the same test process with the summary above (`keychain-identity-signed-run1.console.log`).

**(e) Your run left nothing behind.** Before any run of this fix, at 05:05 NZDT, about 21 minutes after your log was last written, the login keychain held no item whose service begins with `com.jevidon.sylvia.spike.identityprobe.`, and so none with `.test.` (`login-keychain-items-before.log`). The listing reads attributes only, through `kSecMatchSearchList` with the login keychain alone, and lists without deleting. The data protection keychain held none of the probe's items created before each test process started either (the `G02-DIAG earlier runs: ... 0` line of every diagnostic run). The identity test's only deletion is the store's `reset()`, whose query sets `kSecUseDataProtectionKeychain` true (`SourceIdentity.swift`, `reset` and `baseQuery`). No query with that flag ever returned a file-based item in the diagnostic. So a login-keychain copy from your run would have had nothing in the test to remove it, and there is none.

## 3. The fix: the check, not the store

`SourceIdentity.swift` is unchanged: the diagnosis found nothing wrong in the store. The fix, in commit `d8ed94a2`, is in `Spikes/G02-Transfer/MacIdentityProbe/Tests/DataProtectionKeychainTests.swift`:

- **"Nowhere else" now looks in the file-based keychains only, and names them.** The query sets `kSecUseDataProtectionKeychain` to false and puts every keychain of the user's search list in `kSecMatchSearchList`. On this Mac those are `~/Library/Keychains/login.keychain-db` and `/Library/Keychains/System.keychain`, which TN3137 says a user context has ("a per-user login keychain and a single System keychain"). In the diagnostic, each of the two keys alone and both together excluded the data protection item and found the file-based one. The check uses both, so it does not rest on either alone. It still expects no item.
- **The data protection query now includes synchronizable items** (`kSecAttrSynchronizable` = `kSecAttrSynchronizableAny`). `SecItem.h` (lines 219-227) says that without the key "no synchronizable items will be added or returned". So `items.count == 1` and `kSecAttrSynchronizable` false could not have caught a synchronizable copy in iCloud Keychain. Now they can. This makes the check stricter, never looser. In the diagnostic, this query returned exactly the store's item.
- **Every other expectation of ADR-0008 is as it was:** backend `.dataProtection` (after creation and after the reload), `kSecAttrAccessible` equal to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable, the access group ending in `.com.jevidon.sylvia.spike.identityprobe`, a new key on first load and the same identity on reload.
- **The search list** comes from `SecKeychainCopySearchList` (`Tests/FileBasedKeychains.swift`). Every SecKeychain function in the SDK is marked deprecated since macOS 10.10 (`SecKeychain.h`: `API_DEPRECATED("SecKeychain is deprecated", macos(10.2, 10.10))`), but a `SecKeychain` is what `kSecMatchSearchList` takes (its page: "The value is a CFArray of SecKeychain items"). The call goes through a protocol, so the probe still builds with warnings as errors (`project.yml`).
- **The diagnostic test stays in the bundle** (`Tests/KeychainQueryDiagnosticTests.swift`, unchanged since `7d944c28`). It runs in every probe run. It expects only what the diagnosis rests on: each of the four file-based queries returns the store's item 0 times and its own file-based item once; both data protection queries return the store's item once; the plain data protection query does not return its own file-based item; and no query returns anything after deletion. It prints the flagless query's result without expecting it, because that is platform behaviour, not ADR-0008. Its `G02-DIAG` lines go to the full xcodebuild log (`.build/scratch/g02-identity-probe/xcodebuild.log`), which the run script does not copy, so for these runs `run-probe-script.sh` copied them into each run's `.console.log`.

The G02-PROBE lines change. The line "items for the service in the login (file-based) keychain" becomes "items for the service in the file-based keychains (login.keychain-db, System.keychain)", where the parenthesis lists the keychains actually searched. Two lines are new: the count in the data protection keychain, synchronizable or not, and the control (section 4).

## 4. The control: the check can still fail

In the identity test, right after the check, the test adds a generic password of its own under `com.jevidon.sylvia.spike.identityprobe.control.<UUID>`, a service unique to the run. It uses the attributes the store's login-keychain fallback writes: class, service, `kSecAttrSynchronizable` false, account, label, and a fixed text as data that is not a secret. It does not set `kSecUseDataProtectionKeychain`. TN3137: `SecItemAdd` "adds the item to the default keychain", the login keychain. The same function, with the same keychain list as the check, then counts it, and so does the data protection query. The test deletes it (`SecItemDelete` as added, then again naming the file-based keychain) and the check counts once more. The test expects 1 from the check, 0 from the data protection query, and 0 after the deletion. A `defer` deletes the item if the test stops early. Run 2 printed:

```
G02-PROBE control: the test's own item added without kSecUseDataProtectionKeychain, counted by the same file-based check: 1, by the data protection query: 0; after the test deleted it: 0
```

So the check counts an item written the way a login-keychain copy of the key would be written. If the search list came back empty, or the query stopped reaching the login keychain, the control's count would not be 1, and the test would fail rather than pass on an empty search.

## 5. Runs and checks

| Path | What it is | Result |
| --- | --- | --- |
| `login-keychain-items-before.log` | `commands/list-login-keychain-items.sh` on `c72247a6` (the commands then uncommitted), 16:05 UTC, before any run of this fix: the login keychain's generic passwords whose service begins with `com.jevidon.sylvia.spike.identityprobe.`, attributes only, never deleted | 0, and 0 with `.test.`: your run left none |
| `diagnostic-run1.log` | `commands/run-probe-tests.sh` (the run script's `xcodebuild test`, signed, `-allowProvisioningUpdates`) with `-only-testing:G02MacIdentityProbeTests/KeychainQueryDiagnosticTests`, on `7d944c28`, 16:10 UTC, screen unlocked | Passed; the diagnosis of section 2 |
| `keychain-identity-signed-run1.log`, `.console.log` | Your command, `Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh <log>`, through `commands/run-probe-script.sh`, on `7d944c28` (identity test unchanged), 16:20 UTC, screen unlocked | `RESULT: FAIL`, exit 1: your failure, line for line; the diagnostic passed in the same run |
| `keychain-identity-signed-run2.log`, `.console.log` | The same command on `d8ed94a2` (the fix), from a deleted DerivedData, 16:24 UTC, screen locked at start and end | `RESULT: PASS`, exit 0; `✔ Test run with 2 tests in 2 suites passed` |
| `host-sourceservice.log` | `xcrun swift test --force-resolved-versions --package-path Spikes/G02-Transfer/SourceService --skip LargeTransferTests` (the drop-in's `host-sourceservice` step, the store's host tests among them), with `G02_EVIDENCE_DIR` in `.build/scratch` so no committed evidence was rewritten, through `M0-Integration/repin-27.1/commands/run-logged.sh`, on `d8ed94a2`, 16:25 UTC | `✔ Test run with 67 tests in 7 suites passed`; no line skipped or failed (the drop-in's own check: `➜ Test .* skipped` or `✘`, 0) |
| `login-keychain-items-after.log` | The same listing after every run, 16:26 UTC | 0 |
| `login-keychain-items-after-host-tests.log` | The listing for the host tests' own services (`com.jevidon.sylvia.spike.source-identity-test.`; the prefix argument was added for it), 16:37 UTC | 0 |
| `diagnostic-final.log` | The diagnostic alone again, as `diagnostic-run1.log`, on `a50bd272`, 16:48 UTC, screen locked, after every other run | Passed; `earlier runs: ... 0`: neither your run nor any of these runs left a probe item in the data protection keychain |
| `apple-pages.txt` | The Apple pages and SDK header lines cited here, verbatim (`commands/apple-pages.sh`, `commands/apple-doc-text.py`) | |
| `checks/` | `Scripts/ci.sh contracts`, `Scripts/ci.d/13-hard-rules.sh` and `Scripts/ci.d/12-dependency-lock.sh`, through `run-logged.sh` | See section 5.1 |

Notes on the logs:

- Where a log header lists the uncommitted paths, the list includes the log being written, because the file exists before git is asked. The exception is the checks' logs (section 5.1), which were written outside this folder.
- In run 2's log, the lines `builtin-SwiftPerFileCompile ...BlindSigning.swift`, `SwiftCompile ... CertificateSigningRequest.swift` and the like are not test results. The run script's pattern `Signing` also matches those package file names when the packages are compiled from clean. Your incremental run will not print them.
- Run 2 ran with the screen locked (the lock-state lines). The key's class, after first unlock, and the unlocked login keychain allowed that. Your run will have the screen unlocked.

### 5.1 Repository checks

The three checks ran through `Docs/Stage0/evidence/M0-Integration/repin-27.1/commands/run-logged.sh` on `1da42a45`, the commit that added this README, with no uncommitted path (each header says so), on 26 October 2026 between 16:43 and 16:45 UTC. The logs were written to `.build/scratch` and copied here afterwards, in the next commit (`776be517`), which adds only these logs and this section. The commits after that change only this README's wording and add `diagnostic-final.log`.

| Log | Command | Result |
| --- | --- | --- |
| `checks/ci-contracts.log` | `Scripts/ci.sh contracts` | `00-git-lfs`, `10-contracts` and `11-capture-anchor-contracts` passed ("all 3 steps passed"); exit 0 |
| `checks/13-hard-rules.log` | `Scripts/ci.d/13-hard-rules.sh` | Self-test PASS; audit `result: PASS (0 finding(s), 49 allowed, 0 stale allowlist entries, 0 allowlist error(s))`; none of the allowed hits is in this branch's files; exit 0 |
| `checks/12-dependency-lock.log` | `Scripts/ci.d/12-dependency-lock.sh` | Self-test: 111 of 111 failure branches reached, 0 wrong; check: `0 failure(s), 0 warning(s)` (no lock or manifest changed here); exit 0 |

## 6. What you do next

1. **Between sittings, not during one,** in `~/Git/sylvia-sessions` on `m0-decisions`: commit your run's log as it is, `keychain-identity-signed.log`, as the record of the first signed run (runbook 0.3, step 6). This branch does not touch that file, so the merge works whether or not you commit it first.
2. Merge this branch as runbook 0.3, step 5 says (it is in the same repository, so no fetch is needed): `git merge m0-g02-probe-fix`, then note the new `git rev-parse HEAD` in the session log. It adds this folder and the two test files and changes `DataProtectionKeychainTests.swift`; nothing else. Under 0.3, step 7, only 0.7 is repeated: its diff over `Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists` lists only the three files in `Spikes/G02-Transfer/MacIdentityProbe/Tests/`.
3. Run 0.7 again **with a new log name**, so your first log stays as it is. The Mac is already set up for signing (your run signed), so the registration build of 0.7 is not needed again:

   ```sh
   Spikes/G02-Transfer/Scripts/mac-identity-probe-run.sh Docs/Stage0/evidence/G02-Transfer/keychain-identity-signed-fixed.log; echo "exit $?"
   ```

   Expect `exit 0`, and the log ending with these lines (the script sorts them):

   ```
   G02-PROBE backend: data-protection keychain
   G02-PROBE control: the test's own item added without kSecUseDataProtectionKeychain, counted by the same file-based check: 1, by the data protection query: 0; after the test deleted it: 0
   G02-PROBE items for the service in the data protection keychain, synchronizable or not: 1
   G02-PROBE items for the service in the file-based keychains (login.keychain-db, System.keychain): 0
   G02-PROBE kSecAttrAccessGroup: A4KBDX665Z.com.jevidon.sylvia.spike.identityprobe
   G02-PROBE kSecAttrAccessible: cku (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly is cku)
   G02-PROBE kSecAttrSynchronizable: false
   G02-PROBE reloaded the same identity (same SPKI pin and source ID): true
   ```

   The lines also include `✔ Test run with 2 tests in 2 suites passed` and no `✘` line, then `RESULT: PASS`. The parenthesis on the file-based line lists your search list's keychains. Anything else (`RESULT: FAIL`, a different count, `RESULT: NOT RUN`) is a result too: keep the log, do not run again to replace it, and pass it on.
4. Commit the new log on `m0-decisions` (runbook 0.3, step 6). The record changes in section 7 are for the run that updates the records, once your re-run is in.

## 7. Record changes this needs (requests; not made here)

Another run updates the records, after your re-run. This branch edits none of them.

1. **Runbook 0.7** (`Docs/Stage0/M0-device-runbook.md`, Session 0). The command's log name for the re-run (`keychain-identity-signed-fixed.log`, or whichever name you use). The expected result: replace "and no item in the login keychain" with the file-based line above (`items for the service in the file-based keychains (...): 0`), and add the control line and the data protection count line. A dated note saying the first signed run (27 October 2026) failed on the check, not on the storage, with this README as its evidence. The Record line: both logs. Correction C46 (`-allowProvisioningDeviceRegistration` in the script) is still open. Your run signed, so how this Mac was registered is yours to record.
2. **G0.2 checklist step 20** (`Docs/Stage0/device-checklists/G02-Transfer.md`). The introduction: history up to the first signed run and its diagnosis here. 20.2: the log name. 20.3: the expected lines, as for 0.7. 20.4: commit both logs and update the report row.
3. **G0.2 report** (`Docs/Stage0/G02-Transfer.md`). The row "Mac identity key in the Keychain": the first signed run (FAIL, the check's fault, this README), the re-run's result and log, and a status for a signed run on the build Mac (host), never a device status. The row on the clean CI run, which lists `mac-identity-signed` as not run for want of signing. Open question 9 (the account) and the Notes on code signing, now that this Mac signs. Today, `keychain-identity-signed.log` is cited for the "No Accounts" clean runs. Once your FAIL log is committed under that name, those citations need the earlier version by commit (`67eaf953`).
4. **ADR-0008** (Evidence: "not run (needs the account holder)"; Consequences: "The signed probe ... checks this as soon as the team can sign again"; Pending: the account holder's item) and **ADR-0015** (threat model, row "S: theft of the Mac's identity key ...": "signed probe **not run**"). Update both with the re-run's result. Both ADRs stay Proposed (D-6).
5. **`Docs/Stage0/M0-gate.md`** (the Session 0 row and the account-holder item) and **`Docs/Stage0/integration-log.md`**: the first signed run, this fix and the re-run.
6. **`Docs/Stage0/evidence/G02-Transfer/PROGRESS.md`**: a dated note under its lines on the signed probe (the account, then the first signed run and this fix).
7. **For the G0.2 owner (optional, not needed for step 20):**
   - The run script's pattern `Signing` could be `Signing Identity`, so a clean build adds no package file names to the log.
   - The CI drop-in's `mac-identity-signed` step writes `$G02_EVIDENCE_DIR/keychain-identity-signed.log`. A refresh run into the committed folder would replace your FAIL log there.
   - The host test `keychainIdentityStoreNeverFallsBackToTheLoginKeychainUnlessAskedTo` (`SourceSideTests.swift`) uses the same flagless query. It is correct in the unsigned test binary, which has no data protection keychain, but the companion (M6) must name the file-based keychains in any such check, as the probe now does.

## 8. Limits

- One Mac, one macOS build (26.6.2, 25G83), one signed app. What the flagless query returns may differ in another macOS version or another kind of program (TN3137 notes that the file-based keychain's shim "has limitations"). The fixed check does not depend on it.
- The probe checks the store in a probe app signed with a development profile. The companion app (M6) is re-tested when it exists (ADR-0008, Consequences). Keychain behaviour after a reboot and while a phone is locked is still pending on a device (checklist step 8).
- The keychains: the runs added and deleted only items under services unique to each run (the store's, the diagnostic's and the control's, and the host tests' own), and never read an item's data. Your earlier run's items were only listed. The listings found none, before or after, in the login keychain under the probe's or the host tests' prefix, and none of the probe's in the data protection keychain after every run (`diagnostic-final.log`).
