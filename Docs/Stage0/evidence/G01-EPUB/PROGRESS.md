# G0.1 EPUB spike: progress log

Branch `m0-g01-epub`. Each entry says what is verified (with the command and evidence file) and what is not.
Simulator results: iPhone 17 (iPhone18,3), iOS 26.5, simulator `Sylvia-M0-g01-epub`. Hosted XCTest in `EPUBHarness`.
Host results: `swift test` in `Spikes/G01-EPUB/Core` on macOS.

## Done (verified)

- Earlier WIP commits (`e5abd25` to `eb2bedc`) re-reviewed by the second agent and re-run with
  `Scripts/ci.d/31-g01-epub.sh`: 12 host tests, 22 hosted simulator tests and 2 UI tests passed (run of 6 Oct, 14:49).
- CI drop-in `Scripts/ci.d/31-g01-epub.sh`: fixture `--check`, host tests, XcodeGen, build-for-testing, all simulator
  tests. `G01_EPUB_EVIDENCE_DIR` chooses where the tests write evidence; `G01_EPUB_ONLY_TESTING` is for local iteration.
- D1 compatibility matrix, D2 selection, D3 decoration, D4 typography, D5 anchors (hosted and UI: rotation, relaunch),
  D6 footnotes (hosted and a real UI tap), D7 extraction/search: tests pass (see test names in the report).
- D8 safety (`SafetyTests`, `DeepNestingUITests`), new in this session:
  - Readium 3.11.0 alone runs publication scripts (inline, external, remote, SVG, event handlers, javascript: URLs) and
    let the hostile fixture make 17-18 loopback requests, and a meta refresh navigated the web view off the publication.
    With the adapter (sanitizer + CSP + WKContentRuleList): no script ran, zero requests, text still shown.
  - Archive preflight rejects traversal, absolute path, symlink, bomb (ratio and new 16 MiB markup cap), lying sizes
    and truncation in under 10 ms. Readium alone never writes ZIP entries to disk (container tree compared before and
    after), never follows the symlink entry, but reads a whole entry into one buffer (200 MiB peak for g01-bomb).
  - Readium's content iterator and search service crash the app (stack overflow in SwiftSoup `Node.language()`) on
    10,000 nested elements. Adapter control added: documents nesting deeper than 256 are replaced by a placeholder in
    the sanitized container; extraction reports `unavailable_excessive_nesting`. A chapter at exactly 256 works.
  - Font obfuscation opens and de-obfuscates (SHA-256 match). AES chapter with no known scheme: Readium alone opens it
    and serves ciphertext; adapter returns unsupported protection. LCP-like and ADEPT-like: Readium flags restricted;
    adapter returns unsupported protection. Truncated: clear error with and without preflight.
- `ReaderSession.search` now uses Sylvia's extraction and FTS5 index (Readium's search service is used only for
  comparison in tests).

## In progress / next

- Third agent (7 Oct): regenerated the protected fixtures after the generator switched to real AES-CBC chapter
  encryption (`--check` passed after regeneration; it failed before). Re-ran the whole suite in .build/scratch (all 30 hosted, 6 UI, 14 host tests passed,
  03:52-03:57). Added: plain-text note popup (no NSAttributedString HTML import of publication HTML), ciphertext
  digest checks in the protection test, a backlink tap + double return test, an endnote round trip without the
  repeat in navigation-race.json, a stricter fixture `--check`. Observed in that run: neither the decoration race
  nor the navigation reset reproduced (0 of 3 each); the report must say so.

- D9 anchor-samples.json, ADR-0004, report `Docs/Stage0/G01-EPUB.md`, device checklist, crash-summary script,
  full clean run into `Docs/Stage0/evidence/G01-EPUB/sim/` and `ci-clean-run.log`.

## Known problems

- None open. Adapter workarounds recorded as findings: navigation repeat after settle (navigation-race.json),
  decoration clear-and-redraw after settings changes and duplicate repair (decoration-race-observation.log).

## Third agent, 7 Oct (in progress, not yet verified by a run)

- FOUND: Readium 3.11.0 builds the selection locator from `navigator.currentLocation` + selected text
  (EPUBNavigatorViewController.spreadView(_:selectionDidChange:frame:)); run 1's anchor-samples.json had the Greek
  book-7 quote with href book-1. Added `ReaderSession.captureSelection()` (confirms the href against the document
  holding the selection; rebuilds the locator without progression when it differs; nil when the text changed).
  Capture is now async everywhere; new test SelectionCaptureTests.testSelectionRightAfterAJumpNamesTheRightResource;
  AnchorSamplesTests now asserts each anchor's resource and text_offsets.
- FOUND (gap): the sanitizer only rewrote HTML media types. New fixture g01-nonhtml-active.epub (SVG page and an
  application/xml XHTML item in the spine, both with scripts). Next: sanitizer rule for non-HTML reading-order
  documents and SVG, plus a SafetyTests case.
- Navigation race: reproduced 3/3 and 5/5 in later runs (0/3 in run 1): timing dependent.
- Drafted ADR-0004 and the device checklist; report still to write.
- Run at 04:31 (.build/scratch/run5.log, all of the above in): 15 host, 33 hosted simulator, 6 UI tests passed.
  Readium named the wrong resource in 3/3 jump-then-select captures; the adapter corrected all 3. Readium alone ran
  the scripts in the SVG page and the application/xml item; through the adapter neither ran. One build warning
  (ReaderScreen.swift:162, weak/strong capture) fixed after the run, not yet rebuilt.
- Next: write Docs/Stage0/G01-EPUB.md, delete DerivedData, clean run into Docs/Stage0/evidence/G01-EPUB.

## Done (third agent, 7 Oct, final)

- Clean run from commit 227a7eb with Spikes/G01-EPUB/.build and the generated project deleted:
  `ci-clean-run.log` (15 host, 33 hosted simulator, 6 UI tests passed; 0 warnings; only the 2 expected crashes).
  All evidence files in this directory come from that run, except `observations/` (see its README).
- Report `Docs/Stage0/G01-EPUB.md`, ADR-0004 (Proposed), device checklist `Docs/Stage0/device-checklists/G01-EPUB.md`.
- Code after 227a7eb: none (documentation only).

## Known problems

- None open in the spike. Device and human checks are pending (checklist). Findings F1-F12 are in the report.

## Review round 1 fixes (7 and 12 Oct)

- R1-01, R1-02, R1-04: the regex sanitizer and byte-scanner depth check were replaced by a parse-and-reserialize
  sanitizer (`MarkupCanonicalizer`, `PublicationHTMLSafety`) that checks its output in libxml2, `SwiftSoup.parse` (as
  Readium calls it) and SwiftSoup's HTML5 parser. New fixtures `g01-csp-bypass.epub` and `g01-nesting-bypass.epub`,
  host tests and simulator tests (`SafetyTests`, `DeepNestingUITests`, `SanitizerFidelityTests`). On 12 Oct: the DOCTYPE
  scan honors quoted identifiers, a head with the CSP is written before text directly in the root, and later reads of a
  document that ran over the time budget get the placeholder without a new worker.
- R1-03: the UI tests decide a crash from the app's process (`kill(pid, 0)`), not from XCTest's crash collection; the
  CI drop-in matches crash reports by pid, only from the run's simulator.
- R1-05: device checklist step 3 cites F8.
- Clean run from commit 2f20df2 with Spikes/G01-EPUB/.build and the generated project deleted: `ci-clean-run.log`
  (28 host, 36 hosted simulator, 8 UI tests passed; 0 warnings; only the 2 expected crashes; contracts passed). Every
  evidence file in this directory except `observations/` and `PROGRESS.md` comes from that run.

## Review round 2 fixes (12 Oct)

- R2-01: the adapter's publication container (`DeclaredResourceContainer`) serves only manifest-declared entries,
  each by the treatment of its declared media type (`PublicationResourcePolicy`); the non-HTML sanitizer withholds
  form controls, `action`/`formaction` and any XHTML element; the content rule list is compiled per publication and
  also blocks document loads outside the reading order. New fixture `g01-form-navigation.epub`, host tests
  (`PublicationResourcePolicyTests`, non-HTML cases) and `SafetyTests.testNonLinkNavigationsReachOnlySanitizedDeclaredDocuments`.
- R2-02: attribute-dense timing patterns, a 100,000-attributes-per-document cap (namespace declarations count), at
  most two sanitizer workers per open publication (host test `workerLimit`); report F5 and ADR "Bounds" corrected.
- R2-03: `Harness/CrashSignalRecorder.c` records the fatal signal and whether it was a stack overflow from an
  alternate signal stack; the UI crash tests require `kind=stack-overflow`, and the CI drop-in fails a crashed pid that
  has neither a stack-overflow crash report nor such a record.
- Clean run: see `ci-clean-run.log` (its first line names the commit). Every evidence file in this directory except
  `observations/` and `PROGRESS.md` comes from that run.
