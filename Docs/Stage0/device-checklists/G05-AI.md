# G0.5 AI: device and human checklist

Steps that need a physical iPhone, a real network, a real model server, provider keys or a person. None of them has been run. Each is **pending** in `Docs/Stage0/G05-AI.md` until someone runs it and records the result here. Never copy a simulator result into this file.

**Recording.** For every step write the date, the person, the device model and iOS version (Settings › General › About), and paste or attach the output named in the step under `Docs/Stage0/evidence/G05-AI/device/` (plain text or a screenshot under 2 MB, with keys, IP addresses beyond the first two octets and personal data removed). Then mark the step passed-device or failed below and update the report row. Name the files `step-NN-<what>.log` for command output and `step-NN-<what>.txt` for the lines you record (steps 3-9).

**Setup for steps 1-4.** On the Mac, in a checkout of the commit that holds the records of the decisions (`m0-sessions`, in the checkout `~/Git/sylvia-sessions`, as runbook 0.3 says; `m0-integrate` is behind `main`, `m0-decisions` holds, past pull request #6, your first sittings' records and what they added, which reach `m0-sessions` by a merge before your checkout moves to it (runbook 0.3, step 1), and `m0-integrate`, and `main` up to pull request #5, hold neither the lock harness nor the records of the product owner's decisions of 22 October 2026, so this checklist's steps are older there (until 22 October 2026, after the review of the decisions round, this line named `m0-integrate`: its findings OWN-01 and H-01; until 23 October 2026 it put the merged `main` first: the review of the decisions round's fix, its findings OWN2-02 and OWN2-03; until 24 October 2026 it named `m0-decisions`, or `main` once it held `m0-decisions`, which pull request #6 merged into `main` that day; and until 26 October 2026 it said that `m0-decisions` is behind `main`, which your first sittings, committed there from 25 October 2026 UTC, had made untrue: the review of the update of 24 October 2026, its finding FID-DA-01); record `git rev-parse HEAD`):

```sh
source Scripts/lib/env.sh; source Scripts/lib/xcodegen.sh
sylvia_generate Spikes/G05-AI/ATSProbe
DEVICE=<device id from `xcrun devicectl list devices`>
```

Use the Identifier only when it is the device's UDID (copy the identifier alone); if devicectl shows an ECID or a CoreDevice identifier instead, take the UDID from Xcode > Window > Devices and Simulators > the device > Identifier: `xcodebuild -destination id=` needs the UDID.

The probe project is signed ad hoc for the simulator; for a device add `DEVELOPMENT_TEAM=$SYLVIA_TEAM_ID CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates -allowProvisioningDeviceRegistration` to each `xcodebuild` command (the second flag registers a device the team has not registered; it takes effect only with the first). The phone must be unlocked, on Wi-Fi, with Developer Mode on. Steps 1, 3 and 4 talk only to the phone's own addresses and to one reserved documentation address (192.0.2.1, which no host uses); step 2 also needs a Mac on the same Wi-Fi network.

## 1. App Transport Security on the minimum supported OS

Plan 14.3 allows a cleartext exception for a local model server only if the minimum OS's ATS behaviour passes testing. The iOS 26.5 simulator let cleartext HTTP to a private IP literal through ATS even with no exception (see the report), which contradicts Apple's documentation for iOS 17 and later, so the device result decides the policy.

1. Run on the iPhone 17 Pro (iOS 26.7) and, if device A, the small-screen baseline, has an earlier iOS 26.x, on it too, before it is ever updated (iOS cannot be downgraded, so the earliest 26.x on hand is the closest to the minimum, iOS 26.0, that can be tested); record each exact version and build:
   ```sh
   cd Spikes/G05-AI/ATSProbe
   xcodebuild test -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination "id=$DEVICE" \
     -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution <signing flags> 2>&1 | tee ../../../Docs/Stage0/evidence/G05-AI/device/step-01-ats.log
   grep -E "ATS-PROBE|✘|✔ Test run" ../../../Docs/Stage0/evidence/G05-AI/device/step-01-ats.log
   ```
   The scheme also runs the suspension UI test; its result belongs to step 4.
2. On first launch of each probe app iOS may ask for Local Network access. Allow it, then run the command again (record that the prompt appeared).
3. **Expected:**
   - `plainHTTPToAPrivateLANAddress` passes in all three variants. On the device the test expects the default variant (no ATS keys) to be **blocked** by ATS (URLError -1022) and the `NSAllowsLocalNetworking` and CIDR-exception variants to pass ATS and be refused locally (URLError -1004).
   - `plainHTTPToAPublicIPLiteral` passes in all three variants. On the device the test expects the default and CIDR variants to be **blocked** by ATS (192.0.2.1 is a public address outside every CIDR exception). For the `NSAllowsLocalNetworking` variant Apple's documentation does not settle it, so the test accepts either a block or a connection failure and the line is recorded. On the iOS 26.5 simulator all three variants blocked it.
   - `plainHTTPToAQualifiedNameIsBlockedInEveryVariant` passes (no variant allows cleartext to an internet name).
   - `plainHTTPToAnotherDeviceOnTheLAN` is skipped here (it runs in step 2).
   - The `ATS-PROBE` lines show the result for the private IP, the public IP and `localhost` in each variant.
4. **Record:** the three `ATS-PROBE variant=… private-ip=…` lines, the three `public-ip=192.0.2.1 … ats-blocked=…` lines, the three `localhost=` lines, and the final `✔`/`✘` summary. If the default variant does *not* block the private IP on the device either, record it: the report's ATS finding then holds on the device as well and ADR-0011 must say that Sylvia's own `EndpointPolicy` is the only cleartext gate. If the `NSAllowsLocalNetworking` variant lets the public IP through ATS (`ats-blocked=false`), record that too: shipping that key would then leave public cleartext to `EndpointPolicy` alone.

   A run on a later 26.x than 26.0 stands for the minimum OS of plan 14.3 only by the product owner's and the security reviewer's recorded decision (runbook decision D-9); otherwise ADR-0011 records an exception. *(22 October 2026: the product owner decided D-9 (b): ADR-0011 records the exception, so Sylvia's own `EndpointPolicy` is the cleartext gate on every OS version and no run stands for iOS 26.0. The run on the iPhone 17 Pro is still this step's result; a run on the oldest supported iPhone, the iPhone 11 Pro, is a record that no decision needs.)* *(24 October 2026: the phone on hand besides the iPhone 17 Pro is device A, the product owner's iPhone 13 mini (decision D-1, decided again: the iPhone 11 Pro no longer charges), which is not the oldest supported iPhone; a run on it, if it has an earlier iOS 26.x than the iPhone 17 Pro, before it is ever updated (runbook 8.8), is likewise a record that no decision needs. Until then item 1 named the oldest supported iPhone for that run.)*
5. **Decision this fed:** which Info.plist key the app ships (`NSAllowsLocalNetworking` alone, or CIDR `NSExceptionDomains` entries). *(Decided on 22 October 2026 by the product owner's decision D-9 (b), whose option has Sylvia ship `NSAllowsLocalNetworking` with its own `EndpointPolicy` as the cleartext gate on every OS version: the key is `NSAllowsLocalNetworking`, never `NSAllowsArbitraryLoads`, as ADR-0011 and plan 14.3 record. This step still records what ATS does on a phone, and a result that contradicts that choice, such as the `NSAllowsLocalNetworking` variant letting the public IP literal through ATS, reopens it. Until the review of the decisions round, the same day, this item left the key to this run: its finding FID-03.)*

## 2. Local Network permission denied is classified, not "AI failed"

Local Network privacy governs connections to *other* devices on the network; a load to the phone's own address may not be subject to it, so this step uses a Mac on the same Wi-Fi as the target.

1. On that Mac, in a new empty folder, start a plain web server bound to its Wi-Fi address (it only lists the empty folder):
   ```sh
   mkdir -p /tmp/g05-lan-target && cd /tmp/g05-lan-target && python3 -m http.server 8765 --bind <mac-wifi-ip>
   ```
   From the phone's Safari, `http://<mac-wifi-ip>:8765/` should show an empty directory listing (this confirms the network allows it).
2. Install `ProbeLocalNetworking` (step 1). With Local Network access **on** for "ATS local" (Settings › Privacy & Security › Local Network), run only the LAN test. `xcodebuild` passes variables prefixed `TEST_RUNNER_` to the test process without the prefix:
   ```sh
   TEST_RUNNER_G05_LAN_TARGET=<mac-wifi-ip>:8765 TEST_RUNNER_G05_EXPECT_LOCAL_NETWORK=allowed \
   xcodebuild test -project G05ATSProbe.xcodeproj -scheme G05ATSProbe -destination "id=$DEVICE" \
     '-only-testing:ProbeLocalNetworkingTests/ATSProbeTests/plainHTTPToAnotherDeviceOnTheLAN()' \
     -derivedDataPath .build/DerivedData -disableAutomaticPackageResolution <signing flags> 2>&1 | tee ../../../Docs/Stage0/evidence/G05-AI/device/step-02-lan-allowed.log
   ```
   **Expected:** the test passes, its `ATS-PROBE … lan-target=… expect=allowed result=success("http 200")` line is printed, and the Mac's server logs one `GET /`. If the test reports *skipped*, the variables did not reach the app: add them to the scheme's Test action (Arguments › Environment Variables) as `G05_LAN_TARGET` and `G05_EXPECT_LOCAL_NETWORK` and run again.
3. Turn Local Network access **off** for "ATS local" and run the same command with `TEST_RUNNER_G05_EXPECT_LOCAL_NETWORK=denied` (log to `../../../Docs/Stage0/evidence/G05-AI/device/step-02-lan-denied.log`). The test name ends in `()`, quoted for zsh: without the parentheses the filter selects no test and xcodebuild still reports success (`Docs/Stage0/evidence/M0-runbook/only-testing-ids.log`).
   **Expected:** the test passes and its line ends `classified=local_network_permission_denied` (the message "Sylvia isn't allowed to reach devices on your local network …"), and the Mac's server logs nothing new. Host tests prove this mapping only with a fake path inspector, so this step is the evidence that the real iOS error carries the network path the classifier reads.
4. **Record:** both `ATS-PROBE` lines and the test results. If the denied run shows any other `classified=` value (for example `offline`), record the URLError code: the classifier must be changed before M5 and this step has failed.
5. Turn Local Network access back on and stop the server (Ctrl-C), then delete `/tmp/g05-lan-target`.

## 3. Keychain accessibility for AI keys while locked and after reboot

AI keys use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (ADR-0011): readable only while the phone is unlocked, never synced, never restored to another device. The probe stores a non-secret marker with the same class and logs only status codes.

**3a. While locked.**

1. Launch "ATS default" on the phone (from step 1). Tap **Start Keychain lock probe**. The screen shows `saved marker; accessibility=akuo` (`akuo` is WhenUnlockedThisDeviceOnly).
2. Within 5 seconds press the side button to lock the phone. Wait 30 seconds. Unlock and return to the app.
3. **Expected:** lines while unlocked read `read=readable`; lines logged while locked (`protectedDataAvailable=false`) read `read=unavailableWhileLocked (errSecInteractionNotAllowed)`, or no lines appear for that period if iOS suspended the app (record which). After unlocking, reads are `readable` again. The timed probe deletes its marker after 60 seconds.

**3b. After a restart (an item saved before the restart is read after it).**

1. Tap **Save marker only**. Expected: `saved marker; accessibility=akuo` and `marker kept for the reboot check …`.
2. Restart the phone. Unlock it, launch "ATS default" and tap **Read marker only** (do not tap Save).
3. **Expected:** `read only: protectedDataAvailable=true read=readable`: the item saved before the restart is readable after the first unlock. `read=notFound` means the item did not survive the restart, which is a failed step.
4. Tap **Delete marker** (expected `marker deleted`), then **Read marker only** again (expected `read=notFound (no marker saved)`).

**Record:** the on-screen lines for 3a and 3b, or the file `Documents/keychain-lock-probe.txt` from the app container (Xcode › Devices and Simulators › the app › Download Container).

## 4. Foreground-only streaming is interrupted honestly by suspension

The probe app streams a long answer (about 60 seconds) from a fake OpenAI-compatible server it starts inside itself on 127.0.0.1, through the real generic adapter and `AskCoordinator`. When the scene leaves the foreground it stops every request with reason `.suspension` inside a background task, as the app must (plan 14.4). The same flow passed as a UI test on the iOS 26.5 simulator (`SuspensionUITests` in `simulator-ats-keychain-probe.log`); this step is the device run.

1. Either run the UI test on the phone (add `-only-testing:ProbeDefaultATSUITests` to the step 1 command; UI tests need the signing flags for the test runner too), or by hand: launch "ATS default", tap **Ask the in-app fake server**, wait until `characters` is at least 20, swipe up to go home, wait 60 seconds, and reopen the app.
2. **Expected:** the status reads `interrupted · Interrupted · partial answer`; `stored interrupted · Interrupted · partial answer · N characters` with N above zero (the record on disk); `requests 1` and `question sent 1 times`; a log line `left the foreground: stopped 1 request(s); records written=true`; and over the next 10 seconds nothing changes (no resend, no further text). With the UI test: `Test Case '…testLeavingTheForegroundMidStreamLeavesAnInterruptedPartialAnswer]' passed` and its `SUSPENSION-PROBE` line.
3. **Record:** the `SUSPENSION-PROBE` line or a screenshot of the probe screen after returning, and whether iOS suspended the app while it was away (if `records written=false` appears, the background task ran out: a failed step).
4. The M5 Ask screen must repeat this with a real local model server (step 5) before release; that run belongs to M5.

## 5. A real local model server through the generic adapter

The spike exercised the generic adapter only against its own in-process fake server. A person runs this with a real server; the agent did not start or configure LM Studio or any app.

1. On a Mac on the same network, start a local OpenAI-compatible server (for example LM Studio's server) bound to the Mac's LAN address, with a small text model loaded. Note the base URL (for example `http://192.168.1.20:1234/v1`) and model id.
2. From the repository on a Mac on that network, run the gated live test (it runs the connection test, then streams a grounded answer about one public-domain Walden sentence):
   ```sh
   source Scripts/lib/env.sh; cd Spikes/G05-AI
   SYLVIA_LIVE_PROVIDER_TESTS=1 SYLVIA_LIVE_COMPAT_BASE_URL=http://<lan-ip>:1234/v1 SYLVIA_LIVE_COMPAT_MODEL=<model id> \
     swift test --filter LiveProviderTests 2>&1 | grep -E "LIVE-COMPAT|✔|✘|➜"
   ```
   The same test was dry-run in CI against Sylvia's own loopback fake server (`Scripts/live-tests-dry-run.sh`); that proves the test code, not any real server.
3. **Expected:** (The run ends "✔ Test run with 4 tests in 1 suite passed" even when a test is skipped for missing variables: the step passes only if the named test has its own `✔ Test <name>() passed` line, never `➜ Test <name>() skipped`.) `openAICompatibleEndpointPassesTheConnectionTestAndStreams` passes; the `LIVE-COMPAT` line reads "Connected to <ip> · local · <model>. Test reply received as a stream."; the `LIVE-COMPAT-ANSWER` line shows `max-output=1024 finish=complete streamed=true`, `unresolved=0` and no `<think>` text in the answer start (step 6 explains `citations=0` and `finish=outputLimit`).
4. Also try by editing the variable: the base URL without `/v1` (expected failure message: "doesn't answer this kind of request at this address … many servers expect it to end in /v1"), a wrong model id (expected: "doesn't offer the model you entered"), the server stopped (expected: "didn't accept the connection").
5. **Record:** the `LIVE-COMPAT` and `LIVE-COMPAT-ANSWER` lines and test results for each try, and the server name and version.

## 6. Live OpenAI and Anthropic smoke tests

Needs a person with keys. Type each key at a hidden prompt so it never appears on screen or in shell history, and unset it afterwards:

```sh
source Scripts/lib/env.sh; cd Spikes/G05-AI
read -rs OPENAI_API_KEY && export OPENAI_API_KEY
SYLVIA_LIVE_PROVIDER_TESTS=1 SYLVIA_LIVE_OPENAI_MODEL=<model> swift test --filter LiveProviderTests 2>&1 | grep -E "LIVE-|✔|✘|➜"
unset OPENAI_API_KEY
read -rs ANTHROPIC_API_KEY && export ANTHROPIC_API_KEY
SYLVIA_LIVE_PROVIDER_TESTS=1 SYLVIA_LIVE_ANTHROPIC_MODEL=<model> swift test --filter LiveProviderTests 2>&1 | grep -E "LIVE-|✔|✘|➜"
unset ANTHROPIC_API_KEY
```

**Expected:** `openAIResponsesStreamsAGroundedAnswer` and `anthropicMessagesStreamsAGroundedAnswer` pass. (The run ends "✔ Test run with 4 tests in 1 suite passed" even when a test is skipped for missing variables: the step passes only if the named test has its own `✔ Test <name>() passed` line, never `➜ Test <name>() skipped`.) The test asserts what the adapter guarantees: the answer arrived as a stream of several deltas, finished `complete`, is not empty, contains no `<think>` text, and every citation in it resolves to the one supplied passage `c1`. Its `LIVE-OPENAI` / `LIVE-ANTHROPIC` line shows `max-output=` (the output limit sent), `finish=complete streamed=true`, the number of text events, `citations=` and `unresolved=0`, whether reasoning was withheld, and the start of the answer.

**Output limit.** The grounded request uses the output limit a real question gets: 1,024 tokens by default, or `SYLVIA_LIVE_MAX_OUTPUT_TOKENS=<n>` added to the command (the maximum output set in provider settings). A model that reasons before answering can spend that whole budget before any answer text. Then the line reads `finish=outputLimit`, a second line says `finish=outputLimit at max-output=… set SYLVIA_LIVE_MAX_OUTPUT_TOKENS higher and run again`, and the test fails on `finish == .complete`. That is a configuration result, not an adapter failure: run again with `SYLVIA_LIVE_MAX_OUTPUT_TOKENS=4096` (or more for a model that reasons at length) and record both runs, with the limit at which the model answered. It tells the product owner which maximum output that model needs (report F14, F18). A `finish=outputLimit` with `characters=` above zero means the answer itself was cut off at the limit; record it the same way.

**Record:** both `LIVE-…` lines, the `✔`/`✘` lines, the model ids (never the keys) and any `SYLVIA_LIVE_MAX_OUTPUT_TOKENS` used. `citations=0` is a model-behaviour finding (the prompt asks for a citation), recorded but not an adapter failure; `unresolved` above zero is a failure.

## 7. A real transcription endpoint

1. Run the gated test against an OpenAI-compatible `/audio/transcriptions` endpoint (OpenAI, or a local Whisper server). It uploads one second of generated silence (capability test), then `Fixtures/audio/meditations-02-first150s.mp3` (public domain LibriVox). Enter a key, if the endpoint needs one, at a hidden prompt:
   ```sh
   source Scripts/lib/env.sh; cd Spikes/G05-AI
   read -rs SYLVIA_LIVE_TRANSCRIPTION_API_KEY && export SYLVIA_LIVE_TRANSCRIPTION_API_KEY
   SYLVIA_LIVE_PROVIDER_TESTS=1 SYLVIA_LIVE_TRANSCRIPTION_BASE_URL=https://api.openai.com/v1 SYLVIA_LIVE_TRANSCRIPTION_MODEL=<model> \
     [SYLVIA_LIVE_TRANSCRIPTION_TIMESTAMPS=1] swift test --filter LiveProviderTests 2>&1 | grep -E "LIVE-TRANSCRIPTION|✔|✘|➜"
   unset SYLVIA_LIVE_TRANSCRIPTION_API_KEY
   ```
   Set `SYLVIA_LIVE_TRANSCRIPTION_TIMESTAMPS=1` only for a model that accepts `verbose_json` with `timestamp_granularities[]` (OpenAI documents this for `whisper-1` only). Run once without it and, for such a model, once with it.
2. **Expected:** (The run ends "✔ Test run with 4 tests in 1 suite passed" even when a test is skipped for missing variables: the step passes only if the named test has its own `✔ Test <name>() passed` line, never `➜ Test <name>() skipped`.) `transcriptionEndpointTranscribesTheFixtureClip` passes: the capability test succeeds, the transcript is not empty and carries the machine-transcription label, and with timestamps requested there is at least one segment and every segment lies within the 150-second clip. The `LIVE-TRANSCRIPTION` line shows the host, model, `timestamps-requested=`, the segment count, `discarded-segments=` (segments with unusable timing that were dropped; expected 0) and the start of the transcript, which should begin with the LibriVox section introduction.
3. **Record:** each `LIVE-TRANSCRIPTION` line, the endpoint kind and model. A non-zero `discarded-segments` is a finding to record with the endpoint.

## 8. Hermes or another gateway

*(22 October 2026: this step is M5's, not M0's: the product owner accepted runbook correction C49 with decisions D-4 (d) and D-6, and ADR-0011 says so, C49 applied there the same day (until the review of the decisions round this note said ADR-0011's owner would move it: its finding HON-10). Steps 5-7 stay in M0, run with the product owner's keys and a local model server: D-4 (a).)*

1. Confirm with the gateway's operator that the route is text-only with no tools or side effects (plan 14.1). Then run step 5's command with `SYLVIA_LIVE_COMPAT_BASE_URL` set to the gateway's OpenAI-compatible base (https unless it is a local IP literal) and `SYLVIA_LIVE_COMPAT_API_KEY` if it needs a key.
2. **Expected:** (The run ends "✔ Test run with 4 tests in 1 suite passed" even when a test is skipped for missing variables: the step passes only if the named test has its own `✔ Test <name>() passed` line, never `➜ Test <name>() skipped`.) The test passes; the `LIVE-COMPAT` line reads "Connected to {host} · user-managed · {model}" for any name or non-private address (Sylvia cannot see where a gateway forwards requests). The connection test is the route's conformance check: if the route answers with a tool call, the test fails at the connection step with "{host} answered the test by asking to run a tool. Sylvia never runs tools, so it can't use this route. Configure a text-only route or model for this endpoint." and nothing is executed; record that as a gateway configuration finding (the route is not usable). A refusal, a filtered reply or "reached the output limit … before any reply text" also fails the connection step with its own message; record the message.
3. If the gateway routes to a model that reasons before answering and the connection step reports the output limit, the configuration needs a larger maximum output; record it as a finding, then run again with `SYLVIA_LIVE_MAX_OUTPUT_TOKENS=4096` (the live test uses the configured maximum output for both the connection step and the grounded answer, 1,024 tokens by default; step 6 explains `finish=outputLimit`).
4. If the gateway answers any request with a 5xx status, the failure message reads "… reported a server or gateway error (HTTP {status}). The request may or may not have been processed, so Sylvia won't send it again without asking." (a gateway is user-managed, so no 5xx from it is resent automatically). Record the status and message.
5. **Record:** the `LIVE-COMPAT` line and the test results.

## 9. Human judgement

1. **Answer support (plan 20.3 human review).** For each advertised provider/model profile, a reviewer reads the answers to the evaluation set and marks each as supported by the displayed evidence, clearly labelled general explanation, or not supported. Target: at least 90 % supported or labelled; zero critical fabricated-quote, privacy or tool-execution failures. Belongs to M5 with the 100-question set; the Stage 0 seed (15 items) only checks the deterministic gates.
2. **Consent and status wording.** A reviewer reads the disclosure lines (`ConsentLedger.lines` and `EvidenceSummary`, for a text request and for an audio clip), the failure messages (`ProviderError.userMessage`), the answer-outcome messages (`AskRecord.outcomeMessage` and the no-answer-text messages in `AskCoordinator.apply`) and the transcription relaunch message for plain language and accuracy, and records each string that should change. The host tests print none of these, so read them in the sources or the test expectations; these cases must be included:
   - the "What is sent" line for each scope and for a pack that mixes passages and notes (`disclosureCountsPassagesByHowTheyWereChosenAndThoughtsApart`: for example "your question, 2 selected passages from Walden, 1 saved thought you selected", "1 selected passage and 3 nearby passages from …", "N retrieved passages from …");
   - a refusal with no reply text ("{host} declined to answer this question and gave no reply to show.") beside a refusal with text ("… Its reply is shown apart from answers.");
   - the neutral "No answer" status a failed record shows if it ever lacks a classified failure;
   - "The key stored for this provider was entered for a different address, so Sylvia won't send it to {host}. Enter the key for this address in provider settings." (a base URL edited after the key was entered);
   - the history exclusion reasons under "Do not include later passages" (`ContextPackBuilder`), one for each reason a turn is left out: beyond the position ("Earlier answers in this conversation used passages beyond your position, so they weren't sent. Start a new conversation with "Do not include later passages" to keep them out entirely."), counted in another edition ("Earlier answers in this conversation used passages from another edition, which Sylvia can't compare with your position, so they weren't sent."; a turn about another work also gets this reason, a known limitation, report F23), with an unknown place, such as an answer about a general note or about a thought captured in another edition ("Earlier answers in this conversation used material whose place in this edition isn't known, so they weren't sent.", review round 6), and with no position set (""Do not include later passages" is on, but no reading position is set, so earlier answers in this conversation that used passages or saved thoughts weren't sent.", round 6); and the thought limitation shared with thoughts whose place is unknown ("None of the thoughts you selected can be shown to come before your position, so none were sent.");
   - the refusal when the confirmed position is in another edition (round 6): "Your confirmed position is in another edition, which Sylvia can't compare with this one, and "Do not include later passages" is on. Confirm your position in this edition, or turn that setting off, to ask." (`ContextBuildError.confirmedPositionInAnotherEdition`);
   - a resend the user confirms that can't go out at once, because the device is offline (round 6) or because the destination needs consent first, for example after a relaunch or a model change (round 7): the record reads "Draft · not sent" for the resend, with nothing of the earlier attempt beside it. The earlier attempt, which may have reached the provider and been billed, keeps its partial text and how it ended only in the record's attempts: its outcome when the provider ended it or it produced text, and, when it failed, its failure kind and acceptance (`uncertain` whenever it may have reached the provider). If the user dismisses the consent sheet, the record stays a draft of the resend. Judge whether M5's request view must show that earlier attempt beside the draft (for example "An earlier attempt may have reached {host}"), and whether dismissing the consent sheet should instead return the record to its earlier state, and record both decisions;
   - the two messages for a wait to retry that ended without sending anything, by Cancel, suspension or a relaunch (round 7; the first predates it but was not listed): "Retry stopped. {host} refused the earlier attempt before answering, so nothing is pending." and "Retry stopped. The earlier attempt didn't reach {host}, so nothing is pending.";
   - the transcription failure messages that say a resend needs the user's confirmation ("… may or may not have been processed, so Sylvia won't send it again without asking.", "Sylvia closed while this clip was being sent. It may have reached {host}. Send it again if you still want a transcript."), and the confirmation the Send action will need for them.
   Expected: no string calls a refused, filtered or empty reply complete, none says something was sent that was not, and none counts a note as a passage from the book. These strings move to `Packages/Design` before any product UI uses them.
3. **Security review** of bring-your-own-key storage, the binding of each key to the origin it was entered for (the reference's `origin` and the Keychain item's account attribute), the cleartext rule and redirect blocking (plan 14.2, 18.1): agent-reviewed; human sign-off pending.
