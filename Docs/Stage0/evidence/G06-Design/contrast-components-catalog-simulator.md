# Component contrast measured from the compiled asset catalog

Environment: simulator: Sylvia-M0-g06-design (iPhone18,3), iOS 26.5

Text and glyphs as the components draw them where that differs from a token pair (`ComponentContrastPairs`: the selection menu's opposite-appearance contents on its ink fill, the selected filter chip, the round play controls, the busy "Saving…" button, and every button role pressed and disabled, composited over the ground at the state's opacity). Colors from `ColorToken.catalogValue(in:)`. 56 measurements, 0 failing; 16 disabled-state measurements below the minimum, reported and exempt (WCAG 1.4.3: inactive controls). Text needs 4.5:1, glyphs 3:1.

| Appearance | Component | State | Content | Text color | Fill color | Ratio | Needs | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| light | selection_menu | action | text | #ECE7DD | #1C1B18 | 13.98 | 4.5 | pass |
| light | selection_menu | highlight_glyph | glyph | #D9A24A | #1C1B18 | 7.56 | 3.0 | pass |
| light | filter_chip | selected | text | #F4F2ED | #1C1B18 | 15.39 | 4.5 | pass |
| light | audio_block | play_control | glyph | #FBFAF7 | #3F5A78 | 6.83 | 3.0 | pass |
| light | play_pause_button | default | glyph | #F4F2ED | #2F5D50 | 6.70 | 3.0 | pass |
| light | capture_save_button | busy | text | #F4F2ED | #2F5D50 | 6.70 | 4.5 | pass |
| light | button_primary | pressed | text | #F4F2ED | #436C60 | 5.28 | 4.5 | pass |
| light | button_secondary | pressed | text | #32312D | #F4F2ED | 11.64 | 4.5 | pass |
| light | button_quiet | pressed | text | #436C60 | #F4F2ED | 5.28 | 4.5 | pass |
| light | button_destructive | pressed | text | #AE4F42 | #F4F2ED | 4.70 | 4.5 | pass |
| light | button_primary | disabled | text | #F4F2ED | #9BAFA6 | 2.07 | 4.5 | below (disabled, exempt) |
| light | button_secondary | disabled | text | #93918D | #F4F2ED | 2.81 | 4.5 | below (disabled, exempt) |
| light | button_quiet | disabled | text | #9BAFA6 | #F4F2ED | 2.07 | 4.5 | below (disabled, exempt) |
| light | button_destructive | disabled | text | #D1A198 | #F4F2ED | 2.03 | 4.5 | below (disabled, exempt) |
| dark | selection_menu | action | text | #1C1B18 | #ECE7DD | 13.98 | 4.5 | pass |
| dark | selection_menu | highlight_glyph | glyph | #8A5410 | #ECE7DD | 5.08 | 3.0 | pass |
| dark | filter_chip | selected | text | #161512 | #ECE7DD | 14.82 | 4.5 | pass |
| dark | audio_block | play_control | glyph | #1E1C19 | #8FB0D4 | 7.55 | 3.0 | pass |
| dark | play_pause_button | default | glyph | #161512 | #7FB5A3 | 7.86 | 3.0 | pass |
| dark | capture_save_button | busy | text | #161512 | #7FB5A3 | 7.86 | 4.5 | pass |
| dark | button_primary | pressed | text | #161512 | #75A595 | 6.58 | 4.5 | pass |
| dark | button_secondary | pressed | text | #D7D2C9 | #161512 | 12.13 | 4.5 | pass |
| dark | button_quiet | pressed | text | #75A595 | #161512 | 6.58 | 4.5 | pass |
| dark | button_destructive | pressed | text | #CC7870 | #161512 | 5.64 | 4.5 | pass |
| dark | button_primary | disabled | text | #161512 | #455D53 | 2.56 | 4.5 | below (disabled, exempt) |
| dark | button_secondary | disabled | text | #76746D | #161512 | 3.90 | 4.5 | below (disabled, exempt) |
| dark | button_quiet | disabled | text | #455D53 | #161512 | 2.56 | 4.5 | below (disabled, exempt) |
| dark | button_destructive | disabled | text | #714741 | #161512 | 2.33 | 4.5 | below (disabled, exempt) |
| light_increased_contrast | selection_menu | action | text | #ECE7DD | #1C1B18 | 13.98 | 4.5 | pass |
| light_increased_contrast | selection_menu | highlight_glyph | glyph | #D9A24A | #1C1B18 | 7.56 | 3.0 | pass |
| light_increased_contrast | filter_chip | selected | text | #F4F2ED | #1C1B18 | 15.39 | 4.5 | pass |
| light_increased_contrast | audio_block | play_control | glyph | #FBFAF7 | #3F5A78 | 6.83 | 3.0 | pass |
| light_increased_contrast | play_pause_button | default | glyph | #F4F2ED | #2F5D50 | 6.70 | 3.0 | pass |
| light_increased_contrast | capture_save_button | busy | text | #F4F2ED | #2F5D50 | 6.70 | 4.5 | pass |
| light_increased_contrast | button_primary | pressed | text | #F4F2ED | #436C60 | 5.28 | 4.5 | pass |
| light_increased_contrast | button_secondary | pressed | text | #32312D | #F4F2ED | 11.64 | 4.5 | pass |
| light_increased_contrast | button_quiet | pressed | text | #436C60 | #F4F2ED | 5.28 | 4.5 | pass |
| light_increased_contrast | button_destructive | pressed | text | #A74C40 | #F4F2ED | 5.00 | 4.5 | pass |
| light_increased_contrast | button_primary | disabled | text | #F4F2ED | #9BAFA6 | 2.07 | 4.5 | below (disabled, exempt) |
| light_increased_contrast | button_secondary | disabled | text | #93918D | #F4F2ED | 2.81 | 4.5 | below (disabled, exempt) |
| light_increased_contrast | button_quiet | disabled | text | #9BAFA6 | #F4F2ED | 2.07 | 4.5 | below (disabled, exempt) |
| light_increased_contrast | button_destructive | disabled | text | #CD9F97 | #F4F2ED | 2.09 | 4.5 | below (disabled, exempt) |
| dark_increased_contrast | selection_menu | action | text | #1C1B18 | #ECE7DD | 13.98 | 4.5 | pass |
| dark_increased_contrast | selection_menu | highlight_glyph | glyph | #875210 | #ECE7DD | 5.25 | 3.0 | pass |
| dark_increased_contrast | filter_chip | selected | text | #161512 | #ECE7DD | 14.82 | 4.5 | pass |
| dark_increased_contrast | audio_block | play_control | glyph | #1E1C19 | #8FB0D4 | 7.55 | 3.0 | pass |
| dark_increased_contrast | play_pause_button | default | glyph | #161512 | #7FB5A3 | 7.86 | 3.0 | pass |
| dark_increased_contrast | capture_save_button | busy | text | #161512 | #7FB5A3 | 7.86 | 4.5 | pass |
| dark_increased_contrast | button_primary | pressed | text | #161512 | #75A595 | 6.58 | 4.5 | pass |
| dark_increased_contrast | button_secondary | pressed | text | #D7D2C9 | #161512 | 12.13 | 4.5 | pass |
| dark_increased_contrast | button_quiet | pressed | text | #75A595 | #161512 | 6.58 | 4.5 | pass |
| dark_increased_contrast | button_destructive | pressed | text | #CC7870 | #161512 | 5.64 | 4.5 | pass |
| dark_increased_contrast | button_primary | disabled | text | #161512 | #455D53 | 2.56 | 4.5 | below (disabled, exempt) |
| dark_increased_contrast | button_secondary | disabled | text | #76746D | #161512 | 3.90 | 4.5 | below (disabled, exempt) |
| dark_increased_contrast | button_quiet | disabled | text | #455D53 | #161512 | 2.56 | 4.5 | below (disabled, exempt) |
| dark_increased_contrast | button_destructive | disabled | text | #714741 | #161512 | 2.33 | 4.5 | below (disabled, exempt) |
