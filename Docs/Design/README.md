# Sylvia design reference

Concept designs for Sylvia and the **Marginalia** design language. Section 4.4 of the [implementation plan](../../Sylvia_v1_iOS_Implementation_Plan.md) is the specification; these boards are the visual reference it cites as [P2].

**Status:** Marginalia confirmed as the v1 direction on 6 October 2026. Token values remain proposals until Stage 0 gate G0.6 checks them on devices.  
**Exported:** 6 October 2026. Rendered at 2x from the board source in `canvas/` with `render.py`.

## Design language sheet

Principles, color tokens in light and dark, the marker set, type roles, shape and motion, the component set, and the status vocabulary.

<img src="images/Main.png" alt="Marginalia design language sheet" width="100%">

## Library, intake and storage

<table>
<tr>
<td align="center"><img src="images/Onboarding.png" alt="Onboarding" width="250"><br><sub>Onboarding</sub></td>
<td align="center"><img src="images/Library.png" alt="Library with mini-player" width="250"><br><sub>Library with mini-player</sub></td>
<td align="center"><img src="images/WorkDetail.png" alt="Work detail" width="250"><br><sub>Work detail</sub></td>
</tr>
<tr>
<td align="center"><img src="images/Inbox.png" alt="Inbox with transfer states" width="250"><br><sub>Inbox with transfer states</sub></td>
<td align="center"><img src="images/InboxRowsA.png" alt="Inbox row layout option A" width="250"><br><sub>Inbox rows, option A</sub></td>
<td align="center"><img src="images/InboxRowsB.png" alt="Inbox row layout option B" width="250"><br><sub>Inbox rows, option B</sub></td>
</tr>
<tr>
<td align="center"><img src="images/PairMac.png" alt="Connect a Mac" width="250"><br><sub>Connect a Mac</sub></td>
<td align="center"><img src="images/Storage.png" alt="Storage and remove-download impact report" width="250"><br><sub>Storage, remove-download sheet</sub></td>
<td></td>
</tr>
</table>

## Reading and thought capture

<table>
<tr>
<td align="center"><img src="images/Reader.png" alt="Reader with selection" width="250"><br><sub>Reader with selection</sub></td>
<td align="center"><img src="images/CaptureSheet.png" alt="Capture sheet, saved state" width="250"><br><sub>Capture sheet, saved</sub></td>
<td align="center"><img src="images/ReaderDark.png" alt="Reader in Night theme with type settings" width="250"><br><sub>Reader, Night, type settings</sub></td>
</tr>
<tr>
<td align="center"><img src="images/Thoughts.png" alt="Thoughts" width="250"><br><sub>Thoughts, all capture kinds</sub></td>
<td align="center"><img src="images/AskAI.png" alt="Ask about this passage" width="250"><br><sub>Ask about this passage</sub></td>
<td></td>
</tr>
</table>

## Listening

<table>
<tr>
<td align="center"><img src="images/Player.png" alt="Player with capture control" width="250"><br><sub>Player with capture control</sub></td>
<td align="center"><img src="images/AudioCapture.png" alt="Audio capture detail" width="250"><br><sub>Audio capture detail</sub></td>
<td></td>
</tr>
</table>

## iPad and Mac

<img src="images/IPadReader.png" alt="iPad reader with Thoughts pane" width="100%">
<sub>iPad: reader with Thoughts pane</sub>

<img src="images/MacCompanion.png" alt="Mac companion window" width="100%">
<sub>Mac companion: sources, devices, queue and the three delivery receipts</sub>

## Marginalia in grayscale

The same screens through a luminance grayscale filter, as on an iPhone with Color Filters set to grayscale. The tablet board adds a slight contrast reduction to approximate a reflective display; that is an approximation, not a measured profile. This is the reference for acceptance test T53.

<table>
<tr>
<td align="center"><img src="images/GrayLibrary.png" alt="Library in grayscale" width="250"><br><sub>Library</sub></td>
<td align="center"><img src="images/GrayThoughts.png" alt="Thoughts in grayscale" width="250"><br><sub>Thoughts</sub></td>
<td align="center"><img src="images/GrayInbox.png" alt="Inbox in grayscale" width="250"><br><sub>Inbox</sub></td>
</tr>
<tr>
<td align="center"><img src="images/GrayReader.png" alt="Reader in grayscale" width="250"><br><sub>Reader</sub></td>
<td align="center"><img src="images/GrayPlayer.png" alt="Player in grayscale" width="250"><br><sub>Player</sub></td>
<td align="center"><img src="images/GrayAskAI.png" alt="Ask in grayscale" width="250"><br><sub>Ask</sub></td>
</tr>
</table>

<img src="images/GrayTablet.png" alt="Reflective grayscale tablet, reader with Thoughts pane" width="100%">
<sub>Reflective grayscale tablet, 4:3</sub>

What to check without color:

1. Quote and Audio tints collapse to almost the same light grey. The glyph, the label and the content form (serif text versus a waveform with a play button) carry the difference.
2. Receiving, Ready and Needs attention pills become similar greys. The dot, check and triangle do the work.
3. The Pine primary button becomes dark grey, still distinct from ink text and from hairline secondary buttons.
4. The reader highlight keeps its underline; the selection keeps its tint; the margin dot still marks a saved thought.
5. Rating stars lose Ochre, but filled versus outline still reads.
6. Generated keeps its dashed frame and label. Citation chips stay legible as chips.

## Board to plan section

| Board | Source | Plan section |
| --- | --- | --- |
| Design language sheet | `canvas/Main.dc.html` | 4.4 |
| Onboarding | `canvas/Onboarding.dc.html` | 4.2 |
| Library with mini-player | `canvas/Library.dc.html` | 4.1, 4.4.7 |
| Work detail | `canvas/WorkDetail.dc.html` | 4.1, 12 |
| Inbox with transfer states | `canvas/Inbox.dc.html` | 4.1, 8.2, 15.5 |
| Inbox row-layout options A and B | `canvas/InboxRowsA.dc.html`, `canvas/InboxRowsB.dc.html` | 4.1 |
| Connect a Mac | `canvas/PairMac.dc.html` | 15.2 |
| Storage and impact report | `canvas/Storage.dc.html` | 17.2 |
| Reader with selection | `canvas/Reader.dc.html` | 9.1 |
| Capture sheet, saved | `canvas/CaptureSheet.dc.html` | 4.1, 11.1 |
| Reader, Night, type settings | `canvas/ReaderDark.dc.html` | 9.1, 4.4.3 |
| Thoughts | `canvas/Thoughts.dc.html` | 4.4.5 |
| Ask about this passage | `canvas/AskAI.dc.html` | 13, 14 |
| Player | `canvas/Player.dc.html` | 10 |
| Audio capture detail | `canvas/AudioCapture.dc.html` | 10.2 |
| iPad reader with Thoughts pane | `canvas/IPadReader.dc.html` | 4.1 |
| Mac companion | `canvas/MacCompanion.dc.html` | 16 |
| Grayscale renderings | `canvas/Gray*.dc.html` | 4.4.8, T53 |

Sample content is public-domain text (Middlemarch, Walden, Meditations) and LibriVox recordings, so the quotations shown are real. Names of people in the recommendation examples are fixture data.

## Files and how to update

- `images/` holds the rendered PNGs embedded above, at 2x.
- `canvas/` holds the board source: one self-contained `.dc.html` per board plus `canvas.json`, which records each board's size and position. The boards open in any browser on their own; the `support.js` reference and the `text/x-dc` script block belong to the authoring tool and are inert outside it.
- `render.py` renders `canvas/` to `images/` with headless Chrome. Run it from anywhere; it needs a Chrome binary (set `CHROME` to override the macOS default) and a network connection for the Literata web font.

To change a board, edit its `.dc.html`, re-run `render.py`, and note the change in the plan's Appendix D if it affects tokens, roles, markers or vocabulary. Where a board and Section 4.4 disagree, the plan wins and the board is corrected.

The boards were authored on a claude.ai design canvas that is private to the product owner. This folder is the shared reference; nothing here depends on that canvas. Four palette alternatives (Seal, Vesper, Broadsheet, Nocturne) were reviewed on 6 October 2026 and dropped after Marginalia was confirmed; they are not included.
