# Device checklist: G0.1 PDF (PDFKit)

Status of every step: **pending** until run on a physical device. Nothing here has been inferred from the simulator.

## Setup

1. On the build Mac, from the repository root: `source Scripts/lib/env.sh; source Scripts/lib/xcodegen.sh; sylvia_generate Spikes/G01-PDF`.
2. Open `Spikes/G01-PDF/G01PDF.xcodeproj`, select the `PDFSpikeHarness` scheme, set the signing team to `A4KBDX665Z` for the `PDFSpikeHarness` and `PDFAnchorKit` targets (do not commit the change; the project is regenerated), choose the device and Run.
3. Record in `Docs/Stage0/evidence/G01-PDF/device-run.md`: device model, iOS version and build (Settings > General > About), Xcode build, the commit hash, date, and the tester's name. Screenshots go next to it as `device-<step>.png` (under 2 MB each; crop if needed).

The harness opens `labels-multipage.pdf`. Use the **Open** menu (top left) to switch fixtures. The bottom lines show the page index and printed label, highlight status, open timing, link decisions and any URL the system delivered to the harness. Below them are six invisible one-point labels that publish geometry for the UI tests (link, overlay and selection frames, a probe point, the view frame); they carry no page text, but VoiceOver will reach them (step 6). **Show** scrolls to the first highlight; **Zoom** sets 2.5 x the fit scale and scrolls to it.

On the simulator, `SelectionGestureUITests` already drags the end selection handle across three lines and from the left column into the right one (report row 2a). Downward drags there left the selection end about 29 pt above the touch point, so the test needed corrective drags; note in steps 1-2 whether a finger needs the same.

## Steps

1. **Finger selection across lines.** Open `labels-multipage.pdf`, scroll to page index 3 (printed label 1). Long-press a word in the first body line, drag the end handle down to the middle of the third line, then choose **Highlight** in the edit menu.
   - Expected: the status line reads "Saved highlight (n on this file)"; the selection is dismissed and, at once (no flash, no visible delay), an Ochre fill with a darker Ochre underline appears on exactly the selected words on all three lines and nowhere else.
   - Record: screenshot `device-1.png`; pass/fail, any mismatch, whether the handle landed where your finger aimed, and whether the highlight appeared at once.
2. **Selection across columns.** Open `two-column.pdf`. Start a selection in the last line of the left column ("row like the spines of closed books.") and drag the handle into the first two lines of the right column. Highlight.
   - Expected: the selection follows reading order (end of left column, then top of right column) without picking up unrelated lines; the overlay covers the same words.
   - Record: screenshot `device-2.png`; describe any lines the handle could not reach or any extra lines selected.
3. **Rotated pages.** Open `rotated.pdf`. On each of page indices 1 (90), 2 (180), 3 (270) and 5 (270 with crop), select two lines with a finger and Highlight.
   - Expected: the selection handles move along the rotated text; each overlay sits on the selected words, underline on the baseline side of the text.
   - Record: one screenshot per page `device-3-p<index>.png`; pass/fail per page.
4. **Relaunch.** Force-quit the harness (app switcher), relaunch, open each file used above.
   - Expected: the status line reads "Highlights: n stored, n restored exactly" with the same n as saved; overlays reappear in the same places.
   - Record: screenshot `device-4.png` and the status text.
5. **Zoom.** On `rotated.pdf` page index 1, pinch to about 400 % and pan across a highlight; then rotate the device to landscape and back. (The simulator measured the overlay's colours on screen at 2.5 x zoom and in both orientations, report row 11a; this step is the person's judgement of alignment at higher zoom with real gestures.)
   - Expected: the overlay stays aligned with the words at every zoom level and orientation (tiles redraw sharp after a moment); no offset grows with zoom.
   - Record: screenshots at about 100 % and 400 % (`device-5a.png`, `device-5b.png`), plus landscape (`device-5c.png`).
6. **VoiceOver reaches selection actions.** Turn on VoiceOver (Settings > Accessibility > VoiceOver). On `labels-multipage.pdf`, use the rotor or a double-tap-and-hold to select text, then find the selection actions.
   - Expected: VoiceOver reads the page text; a selection can be made; the **Highlight** action is reachable either in the edit menu or through the toolbar button announced "Highlight selection"; after activating it, the status line ("Saved highlight ...") is announced or reachable.
   - Record: which method worked (edit menu, toolbar, both, neither), exact VoiceOver announcements, and a screen recording if practical (`device-6.mov`, under 2 MB or describe instead). Note the invisible test-geometry labels VoiceOver reads (harness only, not shipped) but do not count them as a failure of the reader.
7. **Image-only pages.** Open `mixed-scanned.pdf`, go to page index 1 and try to select text.
   - Expected: nothing is selectable; the page line shows "No selectable text on this page"; Highlight gives "No selectable text on this page" or "Select text first", never a saved highlight.
   - Record: screenshot `device-7.png`.
8. **Links.** Open `actions.pdf`. Tap each of the four links once.
   - Expected: link A and link C (launch) do nothing visible except the "Links:" line showing "blocked"; link B shows "Open link?" with `https://example.invalid/track` (tap Cancel; Safari must not open); link D moves to page index 1; "URLs opened into the harness: none" throughout; no other app opens at any point, including when the file is first opened.
   - Record: the "Links:" and "URLs opened" lines; pass/fail.
   - Then open `actions-nonurl.pdf` and tap links A to I in order, returning to page index 0 (scroll up) after each. Expected: A goes to page index 1 and B to page index 2; C (Find), D (GoToPage) and F (another file) show "blocked" on the "Links:" line and stay on page 0; E (Print), H (JavaScript) and I (submit form) do nothing; G resets the field below the links to "Default"; "URLs opened into the harness: none" throughout and no other app opens. Record the "Links:" line and anything that differs.
9. **Protected and damaged files.** Open `encrypted-user-password.pdf` and `truncated.pdf` from the Open menu.
   - Expected: "This PDF is password-protected. Password-protected PDFs are not supported." and "This PDF is incomplete: the file ends early."; no password prompt; no crash.
   - Record: the two messages.
10. **Open time for a large PDF.** On the Mac, run `Scripts/fixtures/generate-g01-pdf-large.sh`, then AirDrop `$SYLVIA_FIXTURE_CACHE/generated/g01-pdf/large-1000.pdf` (1,000 pages, 1,713,026 bytes, SHA-256 `cfa95b03…2ee299`) to the device and save it in Files. Force-quit and relaunch the harness, then choose **Open > Open from Files…** and pick the file. Repeat five times (force-quit between runs so each open is cold for the app).
    - Expected (plan 19.2 budget for a typical file, p95 at or under 2 s): the timing line reads "Open … ms (digest, checks, parse); text of 1000 pages … ms; restore highlights … ms (n restored); first page drawn … ms after display began; total … ms". The budget applies to "open" plus "restore highlights" plus "first page drawn" (restoring stored highlights runs before display on every open; it touches only pages that carry highlights). The all-pages text extraction is the harness doing indexing synchronously and is recorded separately (the product indexes in the background).
    - Record: the five timing lines verbatim, the device model, and whether it is the iPhone 12-class baseline or a newer device (a newer device's result does not stand in for the baseline). Then select a word on any page, Highlight it, force-quit, and open the file from Files again five more times; record those timing lines too (they include restoring one highlight).

## Notes

- Steps 1-3 and 5 are judgements of on-screen alignment by a person; record what you see rather than "looks fine".
- If any step fails, record the failure as found; do not retry until it passes without noting the earlier failure.
