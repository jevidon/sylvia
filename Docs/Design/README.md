# Sylvia design reference

This folder holds the checked-in export of the *Sylvia Concept Designs* canvas, the visual reference for the Marginalia design language specified in Section 4.4 of the implementation plan. The plan is the specification; these files are the reference it points at as [P2].

**Live canvas:** https://claude.ai/artifact/6gkxB1iCyGhjMZvhFMePWC  
**Exported version:** 1791216877-9460, 6 October 2026  
**Status:** Marginalia confirmed as the v1 direction on 6 October 2026. Token values remain proposals until Stage 0 gate G0.6 checks them on devices.

## What is here

`canvas/` contains the canvas's own files in the Design canvas authoring format: one `.dc.html` per artboard plus `canvas.json`, the index that places each board. Each `.dc.html` is a self-contained HTML page with the board's markup, styles and sample content. They open in a browser on their own for a rough view; the canvas renders them with its runtime, which is not included here.

| Board | File | Plan section |
| --- | --- | --- |
| Design language sheet: principles, tokens, type, components, status vocabulary | `Main.dc.html` | 4.4 |
| Onboarding | `Onboarding.dc.html` | 4.2 |
| Library with mini-player | `Library.dc.html` | 4.1, 4.4.7 |
| Work detail: editions, history, rating, recommendations | `WorkDetail.dc.html` | 4.1, 12 |
| Inbox with transfer states | `Inbox.dc.html` | 4.1, 8.2, 15.5 |
| Inbox row-layout options A and B | `InboxRowsA.dc.html`, `InboxRowsB.dc.html` | 4.1 |
| Connect a Mac (pairing) | `PairMac.dc.html` | 15.2 |
| Storage and the remove-download impact report | `Storage.dc.html` | 17.2 |
| Reader with selection and action menu | `Reader.dc.html` | 9.1 |
| Capture sheet in its saved state | `CaptureSheet.dc.html` | 4.1, 11.1 |
| Reader in Night theme with type settings | `ReaderDark.dc.html` | 9.1, 4.4.3 |
| Thoughts with all capture kinds | `Thoughts.dc.html` | 4.4.5 |
| Ask about this passage: scope, disclosure, citations | `AskAI.dc.html` | 13, 14 |
| Player with capture control | `Player.dc.html` | 10 |
| Audio capture detail | `AudioCapture.dc.html` | 10.2 |
| iPad reader with Thoughts pane | `IPadReader.dc.html` | 4.1 |
| Mac companion window | `MacCompanion.dc.html` | 16 |
| Grayscale renderings of six iPhone screens and the tablet reader | `Gray*.dc.html` | 4.4.8, T53 |

Sample content on the boards is public-domain text (Middlemarch, Walden, Meditations) and LibriVox recordings so the quotations shown are real. Names of people in the recommendation examples are fixture data.

## How to update

1. Change the canvas, or change Section 4.4 of the plan, whichever is the source of the change. Where they disagree, the plan wins and the canvas is corrected.
2. Re-export the canvas's `project/` files into `canvas/` and update the version line above.
3. Note the change in the plan's Appendix D if it affects tokens, roles, markers or vocabulary.

Four palette alternatives (Seal, Vesper, Broadsheet, Nocturne) were reviewed on 6 October 2026 and removed from the canvas after Marginalia was confirmed. They are not in this export.
