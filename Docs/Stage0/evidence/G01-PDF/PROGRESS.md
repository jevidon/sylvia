# G0.1 PDF spike: progress log

Branch `m0-g01-pdf`. Simulator `Sylvia-M0-g01-pdf` (iPhone 17, iOS 26.5). Final state: complete for Stage 0; device steps pending.

Latest rounds: branch `m0-int-minors-g01-pdf` (after M0 integration, three rounds), simulators `Sylvia-M0-minors-g01-pdf` on iOS 26.5 and iOS 27.0, deleted at the end of each round. Final state: complete for Stage 0 on the simulator, with one failed row (overlay on rotated-matrix text, report row 10c, a decision for contract consolidation and M3); device and human steps pending.

## Review of the earlier WIP commit (11089f0)

- `Tools/make_pdf_fixtures.py` and the nine committed fixtures: reviewed and kept. `--check` regenerates all nine byte-identically (host). Literal non-ASCII characters in the source were replaced by escapes (output unchanged).
- `Sources/PDFAnchorKit/*.swift`: reviewed and kept with changes (typed throws, overlay document default, anchor-box helpers, status messages). The rotation mapping was re-derived and is now checked against PDFKit's transform and PDFView's conversion by tests.

## Review round 1 (findings R1-01 to R1-09)

Earlier fixer WIP commits (6f4d359, 4f19e00, fa8dd37) were read and treated as unreviewed. Kept: the overlay concurrency, redraw, non-URL action, page-class and overlay-vs-selection tests, `actions-nonurl.pdf`, the seeded random generator, apply-only-highlighted-pages and the harness redraw by `setNeedsDisplay()`. Reverted: fa8dd37 had left the overlay store's `Mutex` replaced by an unguarded control cell (a Thread Sanitizer experiment); the mutex is restored and the control now runs from `Tools/tsan_control_unguarded.sh` on a copy of the spike, never on the source tree.

- R1-01: `OverlayConcurrencyTests` (offscreen workers and live PDFView), run again under the Thread Sanitizer by the drop-in; control `tsan-control-unguarded.txt`; listed in ADR-0005's must-stay tests.
- R1-02: `OverlayRedrawTests` and the on-screen check after Highlight, with a no-redraw control (`ui-redraw-control.txt`); report finding 5 and ADR-0005 reworded.
- R1-03: report row 9 and summary say what the 0.0 measures; `overlay-vs-restored-selection.txt` adds the direct check.
- R1-04: `Fixtures/LICENSES.md` entry requested in the report (outside this workstream's files).
- R1-05: ADR-0005 "Links and actions" rewritten as observed behaviour; `actions-nonurl.pdf` and `NonURLActionTests`.
- R1-06: `OrientationZoomUITests` (portrait, landscape, landscape at 2.5 x zoom, portrait zoomed); checklist step 5 kept for the person's judgement.
- R1-07: stale class name, unsupported repair comment and unseeded generator fixed.
- R1-08: `overlay-stored-property-crash.txt`, `ui-runner-nan-crash.txt`, runner crash listed below.
- R1-09: `HighlightOverlay.apply` touches only pages that had or get highlights; timing line and checklist step 10 name "restore highlights".
- Gate gaps also closed on the simulator: simulated handle drags across lines and columns (`SelectionGestureUITests`), accessibility exposure and audit (`AccessibilityUITests`).

## Minor-findings round after M0 integration (branch `m0-int-minors-g01-pdf`)

Started from the integration branch at `b354dc7`. A stopped agent had left five WIP commits on this branch (`d892c35`, `01c2ab4`, `11aa7e1`, `08cc1e8`, `d5b01c4`). They were read in full and treated as unreviewed; they were built and their new tests run before anything was changed. Kept: the chained-action fixture and tests; the audit following /Next and reading /AA; `HighlightRestorer`, with the harness drawing and saving relocated highlights; `HighlightRestoreTests`; the relocated-highlight, rotated-page drag and chained-tap UI tests; `CrossOSRestoreTests` with its committed iOS 26.5 anchors (checked identical to the samples in `anchor-samples.json`); and the drop-in's iOS 27.0 step. Added or changed in this round:

- R2-01: `NonURLActionTests` asserts every outcome ADR-0005 states: the delegate decisions for Find and GoToPage, empty decisions for the others, the field's value before and after each action, nothing presented, no URL.
- R2-02: `actions-chained.pdf` gains the document-level /AA (close, save, print), every widget and field trigger on the text field, and a JavaScript action in a /Next array. Also added: a control without the delegate (PDFKit ignores /Next by itself, and its default opens an /AA-only link), closing the document, and nothing-presented checks. The audit gets a total row cap, because a /Next graph with repeated entries has exponentially many paths within the depth limit (`testAuditStopsOnAnExponentialNextGraph`). `PDFKitObservationTests` now includes the new file and checks its list against the bundled fixtures. ADR-0005 has a paragraph on chained and additional actions.
- R2-03: the previous agent's harness path is kept; report rows 24 and 24a and ADR-0005 "Restoring" describe it.
- Gate gaps: rotated-page drags are automated (row 2a; checklist step 3 remains for a finger). The extraction-cache rebuild is covered on iOS 26.5 and 27.0 and by the simulated change (rows 24, 24a). Pointer-only /AA triggers are checklist step 8 (iPad). The real-world corpus stays open question 5: QA has to choose the sources.
- R1-04: the ten earlier fixtures were added to `Fixtures/LICENSES.md` at M0 integration; the row for `actions-chained.pdf` is requested in the report.
- Drop-in and tests: the drop-in resolves a relative `G01_PDF_EVIDENCE_DIR` (the first clean run failed on it; report, "Development crashes and failures") and logs `uptime` around the tests. A UI test now fails when it cannot write its evidence, and the timing test records the build Mac's load.
- Clean run on `9decb79`: 61 tests (49 unit, 12 UI), Thread Sanitizer 2 of 2 with no reports, `CrossOSRestoreTests` on iOS 27.0 1 of 1, contracts pass (`ci-clean-run.log`).

## Second minor-findings round (findings R3-01 to R3-06, branch `m0-int-minors-g01-pdf`)

Started from `7884a59` (the reviewed head; no later WIP commits). Two WIP commits of the stopped agent from the previous round, `d5b01c4` and `08cc1e8`, have a summary line but no "why" paragraph; history is not rewritten (the report, the integration log and the workflow cite later SHAs). Their why: `d5b01c4` added the iOS 27.0 `CrossOSRestoreTests` step to the drop-in, because plan 9.4 asks that anchors survive an extraction change and PDFKit's extractor ships with the OS; `08cc1e8` measured the rotated-page drag overlays at 2.5 x zoom on the revealed page, because at fit scale those pages are drawn at about half size and the underline is under 1 pt on screen.

- R3-01 (major): `PDFActionAudit` now also walks the JavaScript name tree (/Kids, with each action's /Next), the outline (/First and /Next) and the form field tree (/Kids; a merged field is listed once, with its page). Its documentation and ADR-0005 list exactly what it reads and what it skips. `actions-chained.pdf` gained the shapes; `testAuditListsEveryPlaceItReads` asserts all 73 rows; `testAuditStopsAtCyclesAndDepthInTrees` covers cycles and 100-level nesting in each tree.
- R3-02: links H ({D, U}), I ({U, D}), J ({D}), K ({U, E}) and L (canary URI + /Next canary), a separate field dictionary with /AA and a separate widget with /AA {U}; every claim in the `LinkInterceptor` documentation, ADR-0005 and the report is scoped to these shapes, with and without the delegate (unit and real-tap controls).
- R3-03: the merged field now declares every annotation and field trigger; the harness publishes the fields' values (bundled fixtures only); the UI tests type a digit into each field and assert the value (letters were rewritten by autocorrection).
- R3-04: `NonURLActionTests.testControlPresentedUIDetectorSeesAnAlertAndAPrintJob`.
- R3-05: report row 26a gives the issue count as varying from run to run.
- R3-06: the report requests `Fixtures/LICENSES.md` rows for `actions-chained.pdf` (new digest), `text-layout.pdf` and `anchors-captured-ios-26.5-23F77.json`.
- Gate gap, generated layouts: new fixture `text-layout.pdf` (rotated text matrices, scrambled and bottom-up stream order), `TextLayoutTests`. It found that the overlay is wrong on rotated-matrix text (report row 10c, failed; finding 12) and recorded PDFKit's text-order flaws (finding 14).
- Found by a probe while closing that gap: a selection ending at a line's last character was stored with the line break in its range and could not be restored. Fixed in `PDFAnchorBuilder` (trailing breaks dropped; anchors that cannot give back their quotation are refused); `LineEndSelectionTests` with a control, `HighlightUITests.testLineEndWordHighlightSurvivesRelaunch`.
- R1-04: still pending the shared-file owner (the ten original fixtures were added at M0 integration).

## Third minor-findings round (findings R4-01 to R4-07, branch `m0-int-minors-g01-pdf`)

Started from `11736d1` (the reviewed head; no later WIP commits). A temporary probe test in the spike (run on iOS 26.5, removed before any commit) confirmed R4-01 and showed more: PDFKit keeps the line break after an inner piece that ends at a line's end, so no fixed join rule describes a composed selection's text.

- R4-01 (major): `PDFAnchorBuilder.capture` checks a new anchor by restoring it through `PDFAnchorResolver.resolveExactly` (same extraction) instead of joining the segments with "\n". New `ComposedSelectionTests`: 11 composed shapes (6 of which the old guard refused) capture and restore exactly, a selection across pages ending at a line's end restores exactly (with a control), a relocated composed record is rebuilt and saved, and a selection whose ranges cannot give back its quotation is refused with `quotationMismatch` (a `PDFSelection` test subclass; the old guard would have accepted one of the two cases). The `PDFAnchor`/builder comments, the envelope description in `anchor-samples.json`, ADR-0005 and report findings 11 and 15 describe PDFKit's composition and the restore check.
- R4-02: device checklist step 1 names the first body line for "water".
- R4-03: `LineEndSelectionTests` uses the first left-column line of `two-column.pdf` (not the full-width title), drags to 6 pt past the line's end, asserts the trailing break for all five shapes on all three lines and for every rotated-text line but the last, and records (not asserts) a 40 pt overshoot. ADR-0005, finding 11 and the builder comment are scoped to these lines and shapes.
- R4-04: `actions-chained.pdf`'s open action and page 0's open trigger go to page index 2; `ChainedActionTests` asserts the view stays on page 0 with and without the delegate. `LinkInterceptionTests` has a no-delegate opening control for `actions.pdf`, and its link control asserts that only the performed link's canary arrives.
- R4-05: the `PDFActionAudit` comment names `testAuditListsEveryPlaceItReads`.
- R4-06: `CrossOSRestoreTests.testRecordPageTextOfEveryFixturePage` records every fixture page's text digest on each runtime; the drop-in compares the iOS 26.5 and 27.0 lists line by line.
- R4-07: ADR-0005's audit, non-URL and chained-fixture wording; the README, generator, checklist and test comments no longer say every action aims at the canary.
- R1-04 / R3-06: `Fixtures/LICENSES.md` rows still requested (shared file); the `actions-chained.pdf` digest changed again (`21f84806…cc3f89b4`).

## Done (all verified by the clean run, `ci-clean-run.log`)

- Brief 1 fixtures (host check) and the large-PDF generator `Scripts/fixtures/generate-g01-pdf-large.sh` (pinned digest).
- Brief 2-8: capture (including selections that end at a line break and selections composed of several pieces, checked by restoring each new anchor), Sylvia-side store with unchanged file bytes, exact restore and geometry, Ochre overlay (offscreen pixels, PDFView draw path, on-screen captures in both orientations and zoomed), Unicode offsets, extraction status and version, search mapping, T12 errors, link and non-URL action handling (unit and real-tap UI tests with controls), `anchor-samples.json`.
- Harness app with edit-menu and toolbar Highlight, Files import with open timing, relaunch restore.
- `Scripts/ci.d/32-g01-pdf.sh`: 74 tests (60 unit, 14 UI) plus the Thread Sanitizer run of the 2 concurrency tests and the 2 `CrossOSRestoreTests` on the iOS 27.0 runtime, then a line-by-line comparison of every fixture page's text on the two runtimes (printed, not failed); fails on any failed, skipped or crashed test or sanitizer report. Clean run on `177395f`.
- Report `Docs/Stage0/G01-PDF.md`, ADR-0005 (Proposed), device checklist.

## Pending

- Device checklist `Docs/Stage0/device-checklists/G01-PDF.md` (finger selection across lines, columns and rotated pages and to a line's end; zoom and orientation judged by a person; VoiceOver; pointer hover over links and fields on an iPad; open time on a device; rotated text by finger).
- Product-owner, QA and contract decisions listed in the report's open questions.
- `Fixtures/LICENSES.md` rows for `actions-chained.pdf` (now `21f84806…cc3f89b4`), `text-layout.pdf` and `Tests/Resources/anchors-captured-ios-26.5-23F77.json` (shared file, requested in the report; the other ten fixtures were added at M0 integration).
- Decision on drawing highlights over rotated-matrix text (report open question 7).

## Known problems

- `drawHierarchy` snapshots of PDFView do not include PDFKit tiles on the simulator; on-screen checks use XCUITest screen captures.
- The simulator occasionally refused to launch the test host right after boot ("Application failed preflight checks"); the drop-in boots first and retries once, logged, only when no test has failed. It did not trigger in the clean run.
- During development (6 October, 10:06) the UI-test runner crashed once converting a non-finite rect to `Int` in the pixel reader; a guard fixed it before the first commit (`ui-runner-nan-crash.txt`). Not seen since.
- During development the harness crashed 8 times from a stored property on the `PDFPage` subclass (`overlay-stored-property-crash.txt`); fixed by the associated-object store.
- Simulated downward handle drags on unrotated pages land the selection end 19 to 29 pt above the touch point, so `SelectionGestureUITests` corrects with up to three drags (logged); on the rotated pages one drag was enough. Whether a finger sees the same is checklist steps 1-3.
- The simulator keyboard autocorrects typed letters when a form field's editing ends, differently from run to run, and writing the keyboard preferences (`KeyboardAutocorrection` and related keys) did not stop it; the field-typing UI tests type digits. On a newly created simulator the keyboard first shows its "slide to type" introduction over the keys; the tests dismiss it (Continue) and log it.
