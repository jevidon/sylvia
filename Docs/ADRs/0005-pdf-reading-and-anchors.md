# ADR-0005: PDF reading and anchors

- **Status:** Proposed
- **Date:** 2026-10-06
- **Deciders:** pending (product owner; iOS lead at the M0 gate)
- **Plan references:** Sections 2.2 (I-05, I-08), 7.5, 9.2, 9.4, 11.1, 11.3, 18.1, 19.2; requirement READ-02; tests T12, T16; gate G0.1 (PDF half)

## Context

Plan 7.5 asks for PDF anchors made of a physical page index, the printed label when present, a text selection mapping and normalized rectangles with rotation metadata, with text offsets in Unicode scalars and native UTF-16 converted at the adapter boundary. Plan 9.2 asks for PDFKit display and selection, highlights stored in Sylvia rather than written into the PDF, overlays drawn from saved records, per-page extraction status with "No selectable text on this page" and no OCR, and a specific error for encrypted files. Plan 18.1 forbids launch actions and unsolicited URLs. Gate G0.1 asks the spike to prove multiline and rotation anchors. The evidence is in `Docs/Stage0/G01-PDF.md`.

## Decision

**Framework.** PDFKit (system framework) for display, selection, navigation and text extraction. No third-party PDF code. The adapter is `Spikes/G01-PDF/Sources/PDFAnchorKit` and is the only place PDFKit types and UTF-16 ranges appear.

**Opening a file.** Sylvia opens a stored copy read-only and never writes to it. In order:

1. Stream the file through SHA-256 (1 MiB chunks). Failure to read: `fileUnreadable`.
2. Structure check: `%PDF-` within the first 1,024 bytes, otherwise `notAPDF`; `%%EOF` within the last 1,024 bytes, otherwise `truncated`.
3. `PDFDocument(url:)`; `nil` is `unparseable`.
4. `isLocked` (a user password is needed) is `passwordProtected`. Sylvia never calls `unlock(withPassword:)`, never asks for a password and never tries one.
5. Zero pages is `noPages`.

Each error maps to its own message. A file that is encrypted but opens without a password (owner password only) opens for reading; if it does not allow copying, Sylvia offers no text features on it (status `restrictedByPermissions`), because PDFKit itself does not enforce that flag (see Evidence). This last rule is a proposal that needs the product owner's decision (Open items).

**Extraction.** Page text is `PDFPage.string`, kept exactly as returned (no normalization), with a SHA-256 of its UTF-8 bytes. Each page has a status: `text(scalarCount)`, `noSelectableText` (nil or whitespace-only text) or `restrictedByPermissions`. A page without text shows "No selectable text on this page"; it is never OCRed, never given guessed text, never searched and contributes nothing to an AI context pack. The extraction version is `{extractor: "pdfkit.PDFPage.string", adapter_version: 1, platform: "<OS> <version> (<build>)"}`, because PDFKit's extractor ships with the OS and can change with it. Only the CropBox's text is extracted (PDFKit's behaviour).

**Anchor (portable envelope, one `anchors[]` entry of the capture envelope, plan A.1).**

Real example: the `multiline` sample from `Docs/Stage0/evidence/G01-PDF/anchor-samples.json` (a point-to-point drag on physical page 3, printed label "1"; fixture asset ID).

```json
{
  "version": 1,
  "kind": "pdf",
  "asset_id": "00000000-0000-4000-8000-000000000001",
  "asset_sha256": "6ffa266bf32eea6c9bc2984d351bc55d19bd948c65714a4e6d2b9ab41d8138d1",
  "exact_text": "ts own counsel. Under a skin of grey ice the water\nstill moves, slowly, turning over the cold it gathered in the night. A walker\nwho stops at the",
  "extraction": {"extractor": "pdfkit.PDFPage.string", "adapter_version": 1, "platform": "iOS 26.5 (23F77)"},
  "segments": [{
    "page_index": 3,
    "page_label": "1",
    "page_rotation": 0,
    "page_box": {"name": "crop", "rect": [0, 0, 612, 792]},
    "text": "ts own counsel. Under a skin of grey ice the water\nstill moves, slowly, turning over the cold it gathered in the night. A walker\nwho stops at the",
    "text_range": {"unit": "unicode_scalar", "start": 48, "end": 193},
    "prefix": "age 4\nThe pond in winter keeps i",
    "suffix": " shore hears it settle.\nSnow lie",
    "line_rects": [[0.327438, 0.880644, 0.396593, 0.013889],
                   [0.117647, 0.861705, 0.577392, 0.013889],
                   [0.117647, 0.842765, 0.130886, 0.013889]],
    "page_text_sha256": "a4746ee93c002a1122b57c8fb100a7a44d2d5700b22cd541f84ad01634e6d570"
  }],
  "reader_locator": {"adapter": "pdfkit", "utf16_ranges": [{"page_index": 3, "location": 48, "length": 145}]}
}
```

- One segment per contiguous text range per page, in document order. A selection across pages has one segment per page; a selection from one column into the next is one segment when the page text runs column by column (it does in PDFKit for the fixture).
- `page_label` is the printed label from the file's `/PageLabels`, or `null`. PDFKit returns "1", "2", ... for files without `/PageLabels`; Sylvia does not store those invented labels.
- Text offsets are Unicode scalar offsets into the stored page text. PDFKit's UTF-16 character indices are converted at the adapter boundary, exactly, and rejected (not rounded) if a boundary falls inside a surrogate pair. They are kept only in the adapter-opaque `reader_locator`.
- Quotation comparison is scalar-exact, not Swift `String ==` (which treats "é" and "é" as equal).

**Coordinates.** `line_rects` are PDFKit's per-line selection bounds (`selectionsByLine`, `bounds(for:)`), which are in PDF user space, normalized to the CropBox: `[x, y, w, h]` as fractions of the box, origin at the box's lower-left, y up, unrotated (the page's own coordinate system, before `/Rotate`), rounded to 6 decimals. `page_rotation` is the effective `/Rotate` (inherited) normalized to 0, 90, 180 or 270 degrees clockwise. A client on any platform draws a stored rectangle on the page as displayed, normalized to the displayed page with origin top-left, as:

| Rotation | Displayed rect |
| --- | --- |
| 0 | `(x, 1 - y - h, w, h)` |
| 90 | `(y, x, h, w)` |
| 180 | `(1 - x - w, y, w, h)` |
| 270 | `(1 - y - h, 1 - x - w, h, w)` |

This mapping agrees with PDFKit's `transform(for: .cropBox)` and with `PDFView.convert(_:from:)` on every rotation tested.

**Restoring.** In the order of plan 7.5: (1) same asset digest, same page text digest, the stored scalar range rebuilt into a selection whose text equals the stored text, and the combined selection equals `exact_text`: exact. (2) Otherwise, within the same asset, the segment text with its exact stored prefix and suffix found exactly once: relocated (the new range should be saved). Several matches, or matches of the bare text without its context: "Location needs review". No match: not found; the quotation is kept unchanged. (3) A different asset digest is never relocated automatically (cross-edition needs confirmation).

**Highlights and overlays.** Highlights are Sylvia records (in the product, rows written in the capture transaction of plan 11.1; in the spike, an atomically written JSON file with `completeFileProtectionUntilFirstUserAuthentication`). They are never PDF annotations and the PDF file is never written. They are drawn by a `PDFDocument` subclass whose `pageClass` is a `PDFPage` subclass that, after drawing the page, draws the `ochre.tint` fill with multiply blending and an `ochre` underline in user space (`transform(_:for:)` then the stored rects). This is the same path PDFView uses for its tiles and that offscreen rendering uses. The page subclass must not have stored properties: PDFKit creates pages without running Swift initializers, so per-page overlay data lives in an associated object guarded by a mutex (PDFView draws tiles on background threads while the main thread changes highlights). Applying highlights touches only the pages that carry them or carried them, so opening a long document does not instantiate every page. PDFView keeps its rendered tiles when only the overlay changes; after a new highlight the reader calls `PDFView.setNeedsDisplay()`, which redraws the visible tiles through the overlay and keeps selection, page and scale, and dismisses the saved selection so its tint does not cover the highlight. Colours come from the design package in the product; the spike copies the plan 4.4.2 light values because PDF pages are drawn on white in both appearances.

**Links and actions.** The reader installs a `PDFViewDelegate` (`LinkInterceptor`), so PDFKit's default for URL links (opening the URL) never runs. What Sylvia decides, through the delegate:

- URL actions (`pdfViewWillClick(onLink:with:)`): `http`, `https` and `mailto` show the full URL and open only after the user confirms; every other scheme is blocked, including `file:` (PDFKit presents a `/Launch` action as a URL action whose URL is the launch file resolved against the PDF's location) and custom app schemes.
- /GoToR (`pdfViewOpenPDF(_:forRemoteGoToAction:)`), named Find (`pdfViewPerformFind`) and named GoToPage (`pdfViewPerformGo(toPage:)`): nothing happens (recorded as blocked).

What PDFView does by itself, with no delegate call, observed with the interceptor installed (`actions-nonurl.pdf`, `actions.pdf`): internal GoTo and named NextPage and LastPage navigate inside the document; ResetForm resets in-memory form field values (the file is not written). JavaScript, SubmitForm and named Print do nothing on iOS, and the document-level JavaScript and open actions do not run when a file is opened. Other relative named actions (PrevPage, GoBack, GoForward, ZoomIn, ZoomOut) were not in the fixtures and are assumed to be performed by PDFView like NextPage. None of these opens anything or leaves the document. `LinkPolicy.decide(action:in:)` states the same outcomes for every action type, so tests can compare; it is not called for the actions PDFView performs itself. Sylvia never calls `PDFView.perform(_:)` for an action from the file.

**Search.** "Search this book" runs over Sylvia's stored page text and returns scalar ranges; a hit becomes an anchor through the same builder and reopens through the same resolver. Image-only pages never produce hits.

## Evidence

All automated results: **simulator**, iPhone 17 (iPhone18,3), iOS 26.5 (23F77), Xcode 27.0 (27A266a), from `Scripts/ci.d/32-g01-pdf.sh` (log `Docs/Stage0/evidence/G01-PDF/ci-clean-run.log`; 41 unit tests and 9 UI tests, all passing, then the 2 overlay concurrency tests in a Thread Sanitizer build with no reports). Fixture regeneration check: **host** (macOS, Python 3 standard library).

- Ten captured selections (multiline, cross-column, rotations 0/90/180/270, inherited rotation, rotation 270 with an offset CropBox, two pages, non-BMP plus combining marks) restore exactly with identical text; the rebuilt selection's line rectangles equal the stored ones (deviation 0.0, tolerance 0.0005), which shows the rebuild is deterministic but not where the rectangles are drawn: `anchor-capture-restore.txt`, `anchor-samples.json`.
- Overlay rectangles from the stored `line_rects` vs PDFKit's line bounds of the restored selection on a fresh open, every rotation: at most 0.00036 pt in user space and 0.00023 pt in a live PDFView (tolerance 0.005 pt): `overlay-vs-restored-selection.txt`.
- Stored-rect display mapping vs PDFKit's transform: maximum deviation below 2e-16; vs a live `PDFView.convert`: 0.000000 (tolerance 0.001): `geometry-transform-check.txt`, `geometry-pdfview-check.txt`.
- Offscreen overlay pixels on every rotation: fill exactly `#F1E4C8`, underline exactly `#8A5410`, absent without the overlay; grayscale levels 0.38 (underline) and 0.90 (fill) against 1.00 paper: `overlay-pixels.txt`, `overlay-*.png`. PDFView draws the highlighted page through the overlay on its tile threads: `pdfview-overlay-draws.txt`. Real screen captures from UI tests show the overlay on a `/Rotate 90` page, after a relaunch, in portrait and landscape and at 2.5 x zoom, and after simulated handle drags across lines and columns: `ui-overlay-rotate-90.txt`, `ui-touch-highlight-relaunch.txt`, `ui-orientation-zoom.txt`, `ui-drag-selection-lines.txt`, `ui-drag-selection-columns.txt`.
- Concurrency: background drawing while the main thread changes highlights, offscreen with 6 workers and in a live PDFView with scale changes: no crash, no torn read, and no Thread Sanitizer report; with the mutex removed the sanitizer reports the race in the offscreen test (control; the live-PDFView test raised no report in that run, so only the offscreen test is shown to discriminate): `overlay-concurrency-*.txt`, `tsan-control-unguarded.txt`. The stored-property crash that led to the associated object: `overlay-stored-property-crash.txt`, `pdfkit-page-class-initializers.txt`.
- Redraw: PDFView makes no draws of a page whose overlay changed until told; `setNeedsDisplay()` redraws it with the new highlight and keeps the selection; on screen the highlight appears with the call and not without it (control): `overlay-redraw-invalidation.txt`, `ui-touch-highlight-relaunch.txt`, `ui-redraw-control.txt`.
- File bytes, size, modification date and annotation counts unchanged after capture, store, overlay and display: `original-bytes-unchanged.txt`.
- UTF-16 to scalar conversion exact for every range of a mixed test string and for PDFKit text with non-BMP scalars, combining marks and a ZWJ sequence: `unicode-offsets.txt`.
- Extraction status on the mixed document, no text on image-only pages: `t16-extraction-status.txt`.
- Search hits reopen at the right page and selection, matching PDFKit's own find: `search-mapping.txt`.
- Errors: `passwordProtected` with zero unlock calls (spy subclass, with a control proving the spy counts); `truncated` at every 3 % cut point; `notAPDF`, `fileUnreadable`, `unparseable`; 25 repeated opens without a crash: `t12-open-errors.txt`, `t12-truncation-sweep.txt`.
- Non-URL actions with the interceptor: `links-nonurl-actions.txt`.
- Accessibility (not VoiceOver): Highlight is exposed as a button and an edit-menu item; the audit found no issue on the reader's own controls: `ui-accessibility.txt`.
- Links: with the interceptor nothing is opened (canary scheme registered by the harness; control tests prove a deliberate open and PDFKit's default both deliver the canary); real taps in the UI test: canary and launch blocked, https asks and is declined, GoTo navigates, app stays in the foreground: `links-*.txt`, `ui-link-taps.txt`, `ui-link-control.txt`.
- Large PDF (1,000 pages): open 1.2 ms median, PDFView first page drawn 30.6 ms median, extraction of all pages 585 ms median, applying highlights on open 0.0 ms (none) and 0.8 ms (one), **simulator on the build Mac, not a device result**: `large-pdf-timing.txt`.
- **Pending (device):** a person's finger selection across lines, columns and rotated pages, alignment judged at zoom and in landscape, VoiceOver reaching selection actions, open time on a device: `Docs/Stage0/device-checklists/G01-PDF.md`.

## Consequences

- PDF anchors are portable without PDFKit: page index, scalar range into recorded extracted text, and geometry that any renderer can draw with the table above. Another platform must reproduce page text to use `text_range`; when its extractor differs, `page_text_sha256` detects it and re-anchoring falls back to exact text plus context, then review.
- An OS update can change `PDFPage.string`. The extraction version and page digests make that visible; re-extraction plus re-anchoring must run after an OS change before ranges are trusted.
- The page subclass is coupled to PDFKit's page-instantiation behaviour (no Swift initializers) and to PDFKit drawing it on background threads. These tests must stay in the product suite: `GeometryOverlayTests.testOverlayPagesAreTheSubclass` and the overlay pixel tests, `PDFKitObservationTests.testPageClassInstancesSkipSwiftPropertyInitializers`, `OverlayConcurrencyTests` (both tests, and their Thread Sanitizer run), and `OverlayRedrawTests`.
- PDFView caches rendered tiles; a new highlight needs `setNeedsDisplay()`. Its cost on a device was not measured.
- Rotated text inside an unrotated page (text drawn with a rotated matrix) was not tested; underlines assume horizontal lines in user space.
- Owner-password PDFs that forbid copying get no quotation, search or AI text if the proposal is accepted.
- The truncation check looks for `%%EOF` in the last 1,024 bytes. A valid file with more than 1 KB of junk after its last `%%EOF` would be reported as truncated; an incrementally updated file cut just after an earlier `%%EOF` passes the check and is then judged by PDFKit's parser. Neither case is in the fixtures.

## Alternatives considered

- **Write highlights as PDF annotations.** Rejected by plan 9.2 and I-08: it modifies the user's file and ties Sylvia's record to a third-party format.
- **`PDFPageOverlayViewProvider` overlay views.** Not chosen: a separate view cannot multiply its fill with the page, so the fill would cover glyphs or need transparency that changes the token colour, and it needs its own coordinate mapping. The page subclass draws in the same pass as the page.
- **`PDFView.highlightedSelections`.** Draws PDFKit's own highlight colour with no underline; it cannot carry the Ochre fill-plus-underline that survives grayscale.
- **Store UTF-16 offsets in the portable anchor.** Rejected by plan 7.5; they stay in `reader_locator`.
- **Text range only, no geometry.** Loses position when text extraction changes and cannot draw on another platform; rectangles are cheap to store.
- **Third-party PDF engines.** Not needed for anything tested; they add a license and a dependency for no gained capability.

## Open items

- Product owner: confirm that PDFs which open without a password but forbid copying get no text features (quotation, search, AI text), or choose to allow quotation for personal use.
- Product owner: confirm password-protected PDFs stay excluded in v1 (plan 9.2 proposes it); the spike shows a specific error and never prompts.
- iOS lead: confirm on the baseline device that `setNeedsDisplay()` after a new highlight shows it without a visible flash or delay (device checklist step 1).
- Device run of `Docs/Stage0/device-checklists/G01-PDF.md` (selection gestures, zoom and orientation judged by a person, VoiceOver, open time).
- Contract consolidation: turn the envelope above into the `anchor` schema with fixtures from `anchor-samples.json`.
