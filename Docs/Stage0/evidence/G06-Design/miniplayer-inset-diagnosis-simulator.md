# Mini-player inset: end of a list hidden under the mini-player (diagnosis)

Environment: simulator (iPhone SE (3rd generation), `Sylvia-M0-g06-design-SE`, iOS 26.5), largest accessibility text size (AX5), light. 2026-10-12, G0.6 part 3 (sixth agent).

**How it was found.** The inherited reachability check (`Harness.reach`) accepted an element as soon as `isHittable` was true. XCUITest reports an element hittable when any part of it is visible, so the check passed with the Inbox's Resolve button mostly under the mini-player (iPhone 17, AX5) and with the last thought on the Thoughts screen only partly visible. The check now requires the element's whole frame between the status bar and the mini-player's top edge (or, for an element taller than that band, its bottom edge inside the band). With that check the Thoughts visit failed on the iPhone SE at AX5.

**Diagnosis.** A scratch UI test (not committed) opened Thoughts at AX5, flung the list to its end 60 times, and printed the frames XCUITest reports. Values transcribed from the scratch logs (`.build/scratch/diag.log`, not committed):

| Build | Mini-player frame (x, y, w, h) | Last quotation (Walden) frame | Bottom edge of the quotation | Result |
| --- | --- | --- | --- | --- |
| Mini-player as a `safeAreaInset` on each area's `NavigationStack` (inherited) | 20, 225.5, 335, 359.5 | 44, -1776, 287, 2333 | 557 (under the mini-player, which ends at 585) | The end of the list cannot be scrolled clear of the mini-player. |
| Mini-player as a `safeAreaInset` on each screen inside the stack (fix) | 20, 225.5, 335, 359.5 | 44, -2155.5, 287, 2333 | 177.5 (above the mini-player's top at 225.5) | The end of the list scrolls clear. |

**Cause.** A `safeAreaInset` applied outside a `NavigationStack` did not become a content inset of the scroll views inside the stack's screens; at the end of a list the content stopped at the tab bar, under the mini-player. Applied to each screen inside the stack (`PrototypeRoot.swift`, `miniPlayer()` and `destinations(withMiniPlayer:)`), it does.

**Consequence for M2-M4.** Product screens must attach the mini-player inset per screen inside the navigation stack, not around it. The stricter reach check in `Apps/DesignCatalog/UITests/Support.swift` is what catches a regression.
