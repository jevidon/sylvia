# G0.1 PDF spike: progress log

Branch `m0-g01-pdf`. Simulator `Sylvia-M0-g01-pdf` (iPhone 17, iOS 26.5). Final state: complete for Stage 0; device steps pending.

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

## Done (all verified by the clean run, `ci-clean-run.log`)

- Brief 1 fixtures (host check) and the large-PDF generator `Scripts/fixtures/generate-g01-pdf-large.sh` (pinned digest).
- Brief 2-8: capture, Sylvia-side store with unchanged file bytes, exact restore and geometry, Ochre overlay (offscreen pixels, PDFView draw path, on-screen captures in both orientations and zoomed), Unicode offsets, extraction status and version, search mapping, T12 errors, link and non-URL action handling (unit and real-tap UI tests with controls), `anchor-samples.json`.
- Harness app with edit-menu and toolbar Highlight, Files import with open timing, relaunch restore.
- `Scripts/ci.d/32-g01-pdf.sh`: 50 tests (41 unit, 9 UI) plus the Thread Sanitizer run of the 2 concurrency tests; fails on any failed, skipped or crashed test or sanitizer report.
- Report `Docs/Stage0/G01-PDF.md`, ADR-0005 (Proposed), device checklist.

## Pending

- Device checklist `Docs/Stage0/device-checklists/G01-PDF.md` (finger selection across lines, columns and rotated pages; zoom and orientation judged by a person; VoiceOver; open time on a device).
- Product-owner decisions listed in the report's open questions.
- `Fixtures/LICENSES.md` entry (shared file, requested).

## Known problems

- `drawHierarchy` snapshots of PDFView do not include PDFKit tiles on the simulator; on-screen checks use XCUITest screen captures.
- The simulator occasionally refused to launch the test host right after boot ("Application failed preflight checks"); the drop-in boots first and retries once, logged, only when no test has failed. It did not trigger in the clean run.
- During development (6 October, 10:06) the UI-test runner crashed once converting a non-finite rect to `Int` in the pixel reader; a guard fixed it before the first commit (`ui-runner-nan-crash.txt`). Not seen since.
- During development the harness crashed 8 times from a stored property on the `PDFPage` subclass (`overlay-stored-property-crash.txt`); fixed by the associated-object store.
- Simulated downward handle drags land the selection end about 29 pt above the touch point, so `SelectionGestureUITests` corrects with up to three drags (logged). Whether a finger sees the same is checklist steps 1-2.
