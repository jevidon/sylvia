# G0.5 AI spike: progress log

Resume notes for the next agent on branch `m0-g05-ai`. Everything under "Done" was run on the host (macOS 26.6.2, Xcode 27.0 27A266a, Swift 6.4) unless stated.

## State of the earlier WIP

The first agent's commit `d7ba9cc` contained only `Spikes/G05-AI/Package.swift` and `Package.resolved` (GRDB 7.11.1 pinned exact). Reviewed and kept; the `EvaluationSet` resource declaration was removed until the evaluation set exists.

## Done

- Package `Spikes/G05-AI` builds with Swift 6 language mode, complete strict concurrency, `ExistentialAny`; no warnings in `swift build --build-tests`.
- SylviaAI: provider config and base-URL normalization, endpoint policy (classification, cleartext rule), credentials (`Secret`, Keychain store, in-memory fake), redaction and log sink, SSE parser, three dialect decoders (Chat Completions, Responses, Anthropic Messages), think-tag filter, URLSession transport with cross-origin redirect blocking, error classification, provider-neutral `TextGenerationProvider`, ContextPack model, prompt template, citation resolver, quote verifier.
- SylviaContext: bounded ZIP reader (stored/deflate, CRC-32, path safety), EPUB XHTML text extractor, paragraph chunker.
- Tests passing: `swift test` → SSE parser (12), dialect streams (33), extraction and chunking (5). Live tests skip with a reason when keys are absent.
- Mutation check: letting Anthropic `thinking_delta` or Responses `reasoning_*` through as text makes 2 tests fail (then restored).

- Provider end-to-end tests over loopback (FakeHTTPServer on 127.0.0.1:0) for all three dialects, connection-test classification (20 tests), network policy and redirect blocking (11), request lifecycle with consent, retries, checkpoints, relaunch reconciliation, offline drafts and no-fallback (20 + 1 local end to end), credential safety (5). All pass on host.

- GRDB FTS5 passage index and ContextPack builder: four scopes plus whole-work-if-it-fits, budget arithmetic, truncation disclosure, spoiler boundary filtered in SQL, history exclusion (25 tests on Walden and Middlemarch).

- Grounding (citations, quote verification) and T48 prompt-injection tests; transcription adapter, audio consent, offline queue policy.
- Contracts: context-pack.v1 and provider-config.v1 schemas; valid fixtures exported from Swift (`Spikes/G05-AI/Scripts/make-contract-fixtures.py`), single-mutation invalid fixtures; `Scripts/ci.sh contracts` passes (2 schemas, 33 fixtures).
- Evaluation set seed: 15 items, 9 categories (`Tests/SylviaContextTests/EvaluationSet/eval-set.v0.json`), deterministic gates pass. Finding: bag-of-words paraphrase labelling called an invented quote a paraphrase; tightened to content words, 0.75 overlap, 3 matches.

- Simulator (iOS 26.5, iPhone 17, Sylvia-M0-g05-ai): package tests pass via `xcodebuild test -scheme G05AI-Package`; ATS/Keychain probe (`Spikes/G05-AI/ATSProbe`, three host apps: default ATS, NSAllowsLocalNetworking, CIDR exceptions) passes. Findings: unhosted SwiftPM test bundles get errSecMissingEntitlement (-34018) from the Keychain, so Keychain tests are hosted in the probe app; the simulator lets cleartext HTTP to a private IP literal through ATS even in the default variant, contrary to Apple's iOS 17+ documentation (device check pending); loopback literals and `localhost` pass ATS in every variant.
- Fixed a timing assumption in the checkpoint test that the slower simulator exposed (now polls the store).

## Review by the resuming agent (third session, after an editor restart)

- Reviewed the two unreviewed WIP commits (`702264e` Keychain lock probe button in the probe app; `9f72334` stop during backoff and "never claims not sent"). Kept both; their tests pass on host.
- Reviewed all SylviaAI and SylviaContext sources against the brief and the current OpenAI and Anthropic references. Fixed:
  - Lifecycle race 1: a second `send` for the same record could slip through while the first was suspended loading the record, so the question went out twice. Now an in-flight guard refuses it (`concurrentSendsOfOneRecordPutTheQuestionOnTheWireOnce`; fails without the fix).
  - Lifecycle race 2: a Cancel tapped while the `sending` record was being written was ignored and the request was sent. Now the stop is honoured before the request leaves (`stopWhileTheSendingRecordIsBeingWrittenSendsNothing`; fails without the fix).
  - Quote verification matched substrings ("at the end" inside "that the endless") and accepted ellipsis-stitched one-word fragments as exact. Now whole tokens (words and punctuation) and at least 3 words per ellipsis segment; 3 new tests; the evaluation set re-check now uses an independent implementation.
  - "Whole book" plus "Do not include later passages" produced a pack labelled whole book that held only text up to the position. Now refused with an explanation.
  - Connection test said "received as a stream" from configuration; now from what the server actually sent (new `delivery` status).
  - Transcription adapter refuses a non-transcription configuration (a chat server is not assumed to accept audio).
  - Retry-After milliseconds kept sub-second precision.
- Host: 134 + 31 package tests pass, 2 live tests skip with a reason.

- Probe app from WIP `702264e` did not compile (`catch .unavailableWhileLocked` on an untyped do block); fixed, and the background task is now ended once (no double end, no Swift 6 capture warning). Simulator CI then passed.
- Live tests now need `SYLVIA_LIVE_PROVIDER_TESTS=1` plus key and model (no model name assumed, no paid call from a key left in a shell); added gated tests for a user's OpenAI-compatible server or gateway and for a transcription endpoint; `Scripts/live-tests-dry-run.sh` runs them against a loopback fake server (`Scripts/fake-openai-compatible-server.py`) in CI.
- Contract rule added: whole_work packs cannot carry a spoiler boundary (new invalid fixture). `Scripts/ci.sh contracts` passes (2 schemas, 34 fixtures).
- Device checklist written: `Docs/Stage0/device-checklists/G05-AI.md`.

- Report `Docs/Stage0/G05-AI.md`, ADR-0011 (Proposed) and the device checklist written. Mutation checks: 9 of 9 caught (`mutation-checks.log`).
- Final clean run: build products deleted, `Scripts/ci.sh g05-ai` re-run from scratch; logs filed with `Spikes/G05-AI/Scripts/collect-evidence.sh` and the full drop-in log as `ci-clean-run.log`.

## Review round 1 fixes (fourth and fifth sessions)

- An earlier fixer started on the round 1 findings and was stopped by the usage limit (WIP `14b18d2`, `030247f`). The next session read those commits as unreviewed and kept them after checking each change: Retry-After and segment-time clamping (R1-01), selection-after-boundary refusal and the pack self-check (R1-02), send-time consent tests (R1-03), mid-chapter and time-checkpoint tests (R1-04), destination derived from the configuration (R1-05), tool call then [DONE] (R1-06), output caps (R1-07) and pack limitations (R1-08).
- Fixed in review of that WIP: the coordinator's time cap discarded the event that arrived after the limit and raced with the test's clock change, which could leave a scripted stream waiting for ever (the first full test run hung); the time check now runs after the event is kept, and the clock-dependent tests wait until the coordinator holds the text before moving the clock.
- Added: quotation styles and short-quotation labels (R1-09); `limitations` and `no_passages` in the context-pack schema with new valid and invalid fixtures, exact digest serialization, Python checks of the code-checked pack rules, deterministic fixture export, a one-reason check for every invalid fixture and a regeneration check in CI (R1-10); wall-clock limits on every response body, enforced by a timer because URLSession can hold back a small trickled body (R1-07); Keychain save-only and read-only actions, a Local Network test against another device, a public IP ATS case, live tests that print and check what the checklist records (R1-11); `stopAll(.suspension)` and a simulator UI test that backgrounds the probe app mid-stream (D4 gate gap); 12 more mutation checks (M10-M21).
- Simulator: the public IP literal 192.0.2.1 was ATS-blocked in all three variants; the suspension UI test passed.
- A scripted stream that waits for cancellation now gives up after 10 s, so a mutation that removes a stop cannot hang the suite.

## Review round 2 fixes (sixth and seventh sessions)

- An earlier fixer was stopped by the usage limit after one change (WIP `5f4a42e`: `SYLVIA_G05_SIM_NAME` in the CI drop-in, R2-06). The next session checked it, kept it, and fixed the rest.
- R2-01: the connection test passes only a normal end with answer text; tool calls, refusals, filters, output limits and early ends fail with their own messages; the probe uses the configured maximum output or 1,024 tokens.
- R2-02 and R2-03: each earlier turn records its shared scopes and destination; turns are resent only to their own destination, count towards consent and are disclosed; their citation markers become `[earlier source]` (template `sylvia-grounded-3`); the context-pack schema, fixtures and Python checks follow.
- R2-04: 5xx acceptance by status and endpoint class (only 503 and 529 from hosted or local endpoints are retried automatically). The first-party error references were re-read on 12 October 2026 (OpenAI and Anthropic both say to retry a 500; Anthropic's 504 is a timeout while processing); the trade-off is open question Q8.
- R2-05: Markdown block quotes are checked as claimed quotations.
- Mutation checks M22-M30 added; all 30 caught.

## Review round 3 fixes (eighth session)

- No earlier fixer had started on round 3 (no WIP commits after `4592e76`).
- R3-01 and R3-02: only a normal end with answer text is "Complete". A final event with no answer text (reasoning only, a think block only, `[DONE]` alone, an output limit or an early end) is `failed_retryable` with acceptance uncertain; a refusal or content-filter stop after some text is "Interrupted · partial answer" with its reason; with none, the classified message replaces "Complete". Tested over HTTP with the reviewer's probes.
- R3-03: the disclosure lists only what the request carries; an audio request no longer says "your question".
- R3-04: the transcription queue, its clips and the audio consent are stored (`FileTranscriptionQueueStore`) and restored on launch; a clip found uploading after a relaunch is an uncertain failure, never resent automatically; audio consent is checked again at send time.
- R3-05: test scratch directories live under one per-process root removed at exit; CI sets `G05_TEST_SCRATCH` and fails if anything is left. A control run without the removal left its root behind (checked by hand, then deleted). The `g05-<uuid>` directories earlier runs left in this Mac's temporary directory were not touched.
- R3-06: letter case is significant for "Exact quotation" except the quotation's first letter; F3 and Q2 state the rule.
- R3-07: test doubles moved to `G05TestSupport`; CI fails if one is defined in a library target.
- Mutation checks M31-M42 added; all 42 caught.

## Review round 4 fixes (ninth session)

- No earlier fixer had started on round 4 (no WIP commits after `9d0d04b`).
- R4-01: a clip has one transcription job; a second request returns it (a double tap uploads once) and a finished transcript and its correction are never replaced.
- R4-02: a key is bound to the origin it was entered for (`CredentialRef.origin`, the Keychain account attribute); the providers send it nowhere else. `provider-config.v1` requires the origin; the Python export check verifies it against the base URL.
- R4-03: the disclosure counts passages by how they were chosen and saved thoughts apart.
- R4-04: an uncertain transcription failure is resent only on the user's confirmation.
- R4-05: a refusal with no text says there is no reply to show; a failed record without a failure reads "No answer".
- R4-06: saved thoughts on the work keep their place; the Swift and Python spoiler checks cover them; new fixture `selected-thoughts-restricted`.
- R4-07: the live grounded request uses the configured maximum output or 1,024 tokens; checklist step 6 explains `finish=outputLimit`.
- Mutation checks M43-M53 added; all 53 caught.

## Review round 5 fixes (tenth session)

- No earlier fixer had started on round 5 (no WIP commits after `ab024f8`).
- R5-01: a request ID has one record; `createDraft` returns the existing record unchanged in any state (memory or store), concurrent calls share one creation, and a different pack under the ID is refused (`requestAlreadyExists`).
- R5-02: the opt-in transcription reconnect loop checks the policy and each clip again just before sending it, skips a clip that is no longer queued and never stops at one clip's error; `send` restores a clip's state when `sending` could not be saved.
- R5-03: saved thoughts and earlier turns carry the edition their ordinal counts in; positions are compared and recorded only in the pack's edition. The Swift self-check, the schema (`edition_id` with a position and on a turn that used evidence), the Python rule and two new invalid fixtures cover it. `TestPacks` now writes the work and edition on source text, as the builder does.
- Mutation checks M54-M58 added (the mutation script now accepts several anchors for one safeguard, used by M54).

## In progress / next

Nothing in progress after the round 5 fixes. The workstream is complete for Stage 0 apart from the device and human steps in `Docs/Stage0/device-checklists/G05-AI.md` (pending by design). If resuming: re-run `Scripts/ci.sh g05-ai` and compare with `ci-clean-run.log`.

## Known problems

None in the automated scope. Open risks are recorded as findings F1 (ATS on the simulator does not block cleartext to private IP literals), F6 (Local Network denial read from an undocumented error key) and the open questions in the report.
