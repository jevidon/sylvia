# Contrast check over the token export (Python, independent of the Swift package)

Source: `Contracts/design/marginalia.v1.json` (token_version 0.3.0). Command: `Scripts/lint-design.py contrast`. Environment: host (Python 3.14.6).

176 measurements (44 pairs x 4 appearances), 0 failing; lowest 4.52 (marker.attention.text on marker.attention.tint, light_increased_contrast).

| Appearance | Text | Fill | Text color | Fill color | Ratio | Needs | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| light | color.ink | color.ground | #1C1B18 | #F4F2ED | 15.39 | 4.5 | pass |
| light | color.muted | color.ground | #6B6760 | #F4F2ED | 5.03 | 4.5 | pass |
| light | color.pine | color.ground | #2F5D50 | #F4F2ED | 6.70 | 4.5 | pass |
| light | color.ochre | color.ground | #8A5410 | #F4F2ED | 5.59 | 4.5 | pass |
| light | marker.quote.text | color.ground | #8A5410 | #F4F2ED | 5.59 | 4.5 | pass |
| light | marker.note.text | color.ground | #2F5D50 | #F4F2ED | 6.70 | 4.5 | pass |
| light | marker.audio.text | color.ground | #3F5A78 | #F4F2ED | 6.37 | 4.5 | pass |
| light | marker.generated.text | color.ground | #6B4E8E | #F4F2ED | 6.04 | 4.5 | pass |
| light | marker.word.text | color.ground | #8A5410 | #F4F2ED | 5.59 | 4.5 | pass |
| light | marker.attention.text | color.ground | #A63D2F | #F4F2ED | 5.64 | 4.5 | pass |
| light | marker.pending.text | color.ground | #6B6760 | #F4F2ED | 5.03 | 4.5 | pass |
| light | color.ink | color.surface | #1C1B18 | #FBFAF7 | 16.50 | 4.5 | pass |
| light | color.muted | color.surface | #6B6760 | #FBFAF7 | 5.39 | 4.5 | pass |
| light | color.pine | color.surface | #2F5D50 | #FBFAF7 | 7.18 | 4.5 | pass |
| light | color.ochre | color.surface | #8A5410 | #FBFAF7 | 5.99 | 4.5 | pass |
| light | marker.quote.text | color.surface | #8A5410 | #FBFAF7 | 5.99 | 4.5 | pass |
| light | marker.note.text | color.surface | #2F5D50 | #FBFAF7 | 7.18 | 4.5 | pass |
| light | marker.audio.text | color.surface | #3F5A78 | #FBFAF7 | 6.83 | 4.5 | pass |
| light | marker.generated.text | color.surface | #6B4E8E | #FBFAF7 | 6.48 | 4.5 | pass |
| light | marker.word.text | color.surface | #8A5410 | #FBFAF7 | 5.99 | 4.5 | pass |
| light | marker.attention.text | color.surface | #A63D2F | #FBFAF7 | 6.04 | 4.5 | pass |
| light | marker.pending.text | color.surface | #6B6760 | #FBFAF7 | 5.39 | 4.5 | pass |
| light | color.pine_on | color.pine | #F4F2ED | #2F5D50 | 6.70 | 4.5 | pass |
| light | color.ink | color.pine_tint | #1C1B18 | #DCE8E2 | 13.68 | 4.5 | pass |
| light | color.pine | color.pine_tint | #2F5D50 | #DCE8E2 | 5.95 | 4.5 | pass |
| light | color.ink | color.ochre_tint | #1C1B18 | #F1E4C8 | 13.67 | 4.5 | pass |
| light | color.ochre | color.ochre_tint | #8A5410 | #F1E4C8 | 4.97 | 4.5 | pass |
| light | color.ink | marker.quote.tint | #1C1B18 | #F1E4C8 | 13.67 | 4.5 | pass |
| light | marker.quote.text | marker.quote.tint | #8A5410 | #F1E4C8 | 4.97 | 4.5 | pass |
| light | color.ink | marker.word.tint | #1C1B18 | #F1E4C8 | 13.67 | 4.5 | pass |
| light | marker.word.text | marker.word.tint | #8A5410 | #F1E4C8 | 4.97 | 4.5 | pass |
| light | color.ink | marker.audio.tint | #1C1B18 | #DCE4EE | 13.43 | 4.5 | pass |
| light | marker.audio.text | marker.audio.tint | #3F5A78 | #DCE4EE | 5.56 | 4.5 | pass |
| light | color.ink | marker.generated.tint | #1C1B18 | #E7DFF0 | 13.30 | 4.5 | pass |
| light | marker.generated.text | marker.generated.tint | #6B4E8E | #E7DFF0 | 5.22 | 4.5 | pass |
| light | color.ink | marker.attention.tint | #1C1B18 | #F3DCD7 | 13.15 | 4.5 | pass |
| light | marker.attention.text | marker.attention.tint | #A63D2F | #F3DCD7 | 4.81 | 4.5 | pass |
| light | color.ink | marker.pending.tint | #1C1B18 | #ECE9E2 | 14.20 | 4.5 | pass |
| light | marker.pending.text | marker.pending.tint | #6B6760 | #ECE9E2 | 4.64 | 4.5 | pass |
| light | color.cover_title | color.cover_field_1 | #F4F2ED | #2F5D50 | 6.70 | 4.5 | pass |
| light | color.cover_title | color.cover_field_2 | #F4F2ED | #5A6B4A | 5.16 | 4.5 | pass |
| light | color.cover_title | color.cover_field_3 | #F4F2ED | #7A4B3A | 6.48 | 4.5 | pass |
| light | color.cover_title | color.cover_field_4 | #F4F2ED | #3F5A78 | 6.37 | 4.5 | pass |
| light | color.cover_title | color.cover_field_5 | #F4F2ED | #4A4A58 | 7.78 | 4.5 | pass |
| dark | color.ink | color.ground | #ECE7DD | #161512 | 14.82 | 4.5 | pass |
| dark | color.muted | color.ground | #A8A298 | #161512 | 7.20 | 4.5 | pass |
| dark | color.pine | color.ground | #7FB5A3 | #161512 | 7.86 | 4.5 | pass |
| dark | color.ochre | color.ground | #D9A24A | #161512 | 8.01 | 4.5 | pass |
| dark | marker.quote.text | color.ground | #D9A24A | #161512 | 8.01 | 4.5 | pass |
| dark | marker.note.text | color.ground | #7FB5A3 | #161512 | 7.86 | 4.5 | pass |
| dark | marker.audio.text | color.ground | #8FB0D4 | #161512 | 8.11 | 4.5 | pass |
| dark | marker.generated.text | color.ground | #B49BD6 | #161512 | 7.48 | 4.5 | pass |
| dark | marker.word.text | color.ground | #D9A24A | #161512 | 8.01 | 4.5 | pass |
| dark | marker.attention.text | color.ground | #E0837A | #161512 | 6.69 | 4.5 | pass |
| dark | marker.pending.text | color.ground | #A8A298 | #161512 | 7.20 | 4.5 | pass |
| dark | color.ink | color.surface | #ECE7DD | #1E1C19 | 13.79 | 4.5 | pass |
| dark | color.muted | color.surface | #A8A298 | #1E1C19 | 6.71 | 4.5 | pass |
| dark | color.pine | color.surface | #7FB5A3 | #1E1C19 | 7.32 | 4.5 | pass |
| dark | color.ochre | color.surface | #D9A24A | #1E1C19 | 7.46 | 4.5 | pass |
| dark | marker.quote.text | color.surface | #D9A24A | #1E1C19 | 7.46 | 4.5 | pass |
| dark | marker.note.text | color.surface | #7FB5A3 | #1E1C19 | 7.32 | 4.5 | pass |
| dark | marker.audio.text | color.surface | #8FB0D4 | #1E1C19 | 7.55 | 4.5 | pass |
| dark | marker.generated.text | color.surface | #B49BD6 | #1E1C19 | 6.96 | 4.5 | pass |
| dark | marker.word.text | color.surface | #D9A24A | #1E1C19 | 7.46 | 4.5 | pass |
| dark | marker.attention.text | color.surface | #E0837A | #1E1C19 | 6.23 | 4.5 | pass |
| dark | marker.pending.text | color.surface | #A8A298 | #1E1C19 | 6.71 | 4.5 | pass |
| dark | color.pine_on | color.pine | #161512 | #7FB5A3 | 7.86 | 4.5 | pass |
| dark | color.ink | color.pine_tint | #ECE7DD | #252B26 | 11.73 | 4.5 | pass |
| dark | color.pine | color.pine_tint | #7FB5A3 | #252B26 | 6.23 | 4.5 | pass |
| dark | color.ink | color.ochre_tint | #ECE7DD | #31291A | 11.65 | 4.5 | pass |
| dark | color.ochre | color.ochre_tint | #D9A24A | #31291A | 6.30 | 4.5 | pass |
| dark | color.ink | marker.quote.tint | #ECE7DD | #31291A | 11.65 | 4.5 | pass |
| dark | marker.quote.text | marker.quote.tint | #D9A24A | #31291A | 6.30 | 4.5 | pass |
| dark | color.ink | marker.word.tint | #ECE7DD | #31291A | 11.65 | 4.5 | pass |
| dark | marker.word.text | marker.word.tint | #D9A24A | #31291A | 6.30 | 4.5 | pass |
| dark | color.ink | marker.audio.tint | #ECE7DD | #272B2D | 11.59 | 4.5 | pass |
| dark | marker.audio.text | marker.audio.tint | #8FB0D4 | #272B2D | 6.35 | 4.5 | pass |
| dark | color.ink | marker.generated.tint | #ECE7DD | #2C282D | 11.76 | 4.5 | pass |
| dark | marker.generated.text | marker.generated.tint | #B49BD6 | #2C282D | 5.94 | 4.5 | pass |
| dark | color.ink | marker.attention.tint | #ECE7DD | #322421 | 12.09 | 4.5 | pass |
| dark | marker.attention.text | marker.attention.tint | #E0837A | #322421 | 5.46 | 4.5 | pass |
| dark | color.ink | marker.pending.tint | #ECE7DD | #2A2925 | 11.81 | 4.5 | pass |
| dark | marker.pending.text | marker.pending.tint | #A8A298 | #2A2925 | 5.75 | 4.5 | pass |
| dark | color.cover_title | color.cover_field_1 | #F4F2ED | #2F5D50 | 6.70 | 4.5 | pass |
| dark | color.cover_title | color.cover_field_2 | #F4F2ED | #5A6B4A | 5.16 | 4.5 | pass |
| dark | color.cover_title | color.cover_field_3 | #F4F2ED | #7A4B3A | 6.48 | 4.5 | pass |
| dark | color.cover_title | color.cover_field_4 | #F4F2ED | #3F5A78 | 6.37 | 4.5 | pass |
| dark | color.cover_title | color.cover_field_5 | #F4F2ED | #4A4A58 | 7.78 | 4.5 | pass |
| light_increased_contrast | color.ink | color.ground | #1C1B18 | #F4F2ED | 15.39 | 4.5 | pass |
| light_increased_contrast | color.muted | color.ground | #646059 | #F4F2ED | 5.59 | 4.5 | pass |
| light_increased_contrast | color.pine | color.ground | #2F5D50 | #F4F2ED | 6.70 | 4.5 | pass |
| light_increased_contrast | color.ochre | color.ground | #875210 | #F4F2ED | 5.79 | 4.5 | pass |
| light_increased_contrast | marker.quote.text | color.ground | #875210 | #F4F2ED | 5.79 | 4.5 | pass |
| light_increased_contrast | marker.note.text | color.ground | #2F5D50 | #F4F2ED | 6.70 | 4.5 | pass |
| light_increased_contrast | marker.audio.text | color.ground | #3F5A78 | #F4F2ED | 6.37 | 4.5 | pass |
| light_increased_contrast | marker.generated.text | color.ground | #6B4E8E | #F4F2ED | 6.04 | 4.5 | pass |
| light_increased_contrast | marker.word.text | color.ground | #875210 | #F4F2ED | 5.79 | 4.5 | pass |
| light_increased_contrast | marker.attention.text | color.ground | #9E3A2D | #F4F2ED | 6.06 | 4.5 | pass |
| light_increased_contrast | marker.pending.text | color.ground | #646059 | #F4F2ED | 5.59 | 4.5 | pass |
| light_increased_contrast | color.ink | color.surface | #1C1B18 | #FBFAF7 | 16.50 | 4.5 | pass |
| light_increased_contrast | color.muted | color.surface | #646059 | #FBFAF7 | 5.99 | 4.5 | pass |
| light_increased_contrast | color.pine | color.surface | #2F5D50 | #FBFAF7 | 7.18 | 4.5 | pass |
| light_increased_contrast | color.ochre | color.surface | #875210 | #FBFAF7 | 6.20 | 4.5 | pass |
| light_increased_contrast | marker.quote.text | color.surface | #875210 | #FBFAF7 | 6.20 | 4.5 | pass |
| light_increased_contrast | marker.note.text | color.surface | #2F5D50 | #FBFAF7 | 7.18 | 4.5 | pass |
| light_increased_contrast | marker.audio.text | color.surface | #3F5A78 | #FBFAF7 | 6.83 | 4.5 | pass |
| light_increased_contrast | marker.generated.text | color.surface | #6B4E8E | #FBFAF7 | 6.48 | 4.5 | pass |
| light_increased_contrast | marker.word.text | color.surface | #875210 | #FBFAF7 | 6.20 | 4.5 | pass |
| light_increased_contrast | marker.attention.text | color.surface | #9E3A2D | #FBFAF7 | 6.50 | 4.5 | pass |
| light_increased_contrast | marker.pending.text | color.surface | #646059 | #FBFAF7 | 5.99 | 4.5 | pass |
| light_increased_contrast | color.pine_on | color.pine | #F4F2ED | #2F5D50 | 6.70 | 4.5 | pass |
| light_increased_contrast | color.ink | color.pine_tint | #1C1B18 | #CBDAD3 | 11.90 | 4.5 | pass |
| light_increased_contrast | color.pine | color.pine_tint | #2F5D50 | #CBDAD3 | 5.18 | 4.5 | pass |
| light_increased_contrast | color.ink | color.ochre_tint | #1C1B18 | #E7D6B6 | 12.05 | 4.5 | pass |
| light_increased_contrast | color.ochre | color.ochre_tint | #875210 | #E7D6B6 | 4.53 | 4.5 | pass |
| light_increased_contrast | color.ink | marker.quote.tint | #1C1B18 | #E7D6B6 | 12.05 | 4.5 | pass |
| light_increased_contrast | marker.quote.text | marker.quote.tint | #875210 | #E7D6B6 | 4.53 | 4.5 | pass |
| light_increased_contrast | color.ink | marker.word.tint | #1C1B18 | #E7D6B6 | 12.05 | 4.5 | pass |
| light_increased_contrast | marker.word.text | marker.word.tint | #875210 | #E7D6B6 | 4.53 | 4.5 | pass |
| light_increased_contrast | color.ink | marker.audio.tint | #1C1B18 | #CCD6E2 | 11.71 | 4.5 | pass |
| light_increased_contrast | marker.audio.text | marker.audio.tint | #3F5A78 | #CCD6E2 | 4.85 | 4.5 | pass |
| light_increased_contrast | color.ink | marker.generated.tint | #1C1B18 | #DBD1E6 | 11.71 | 4.5 | pass |
| light_increased_contrast | marker.generated.text | marker.generated.tint | #6B4E8E | #DBD1E6 | 4.60 | 4.5 | pass |
| light_increased_contrast | color.ink | marker.attention.tint | #1C1B18 | #EBCCC6 | 11.47 | 4.5 | pass |
| light_increased_contrast | marker.attention.text | marker.attention.tint | #9E3A2D | #EBCCC6 | 4.52 | 4.5 | pass |
| light_increased_contrast | color.ink | marker.pending.tint | #1C1B18 | #DFDCD5 | 12.58 | 4.5 | pass |
| light_increased_contrast | marker.pending.text | marker.pending.tint | #646059 | #DFDCD5 | 4.57 | 4.5 | pass |
| light_increased_contrast | color.cover_title | color.cover_field_1 | #F4F2ED | #2F5D50 | 6.70 | 4.5 | pass |
| light_increased_contrast | color.cover_title | color.cover_field_2 | #F4F2ED | #5A6B4A | 5.16 | 4.5 | pass |
| light_increased_contrast | color.cover_title | color.cover_field_3 | #F4F2ED | #7A4B3A | 6.48 | 4.5 | pass |
| light_increased_contrast | color.cover_title | color.cover_field_4 | #F4F2ED | #3F5A78 | 6.37 | 4.5 | pass |
| light_increased_contrast | color.cover_title | color.cover_field_5 | #F4F2ED | #4A4A58 | 7.78 | 4.5 | pass |
| dark_increased_contrast | color.ink | color.ground | #ECE7DD | #161512 | 14.82 | 4.5 | pass |
| dark_increased_contrast | color.muted | color.ground | #A8A298 | #161512 | 7.20 | 4.5 | pass |
| dark_increased_contrast | color.pine | color.ground | #7FB5A3 | #161512 | 7.86 | 4.5 | pass |
| dark_increased_contrast | color.ochre | color.ground | #D9A24A | #161512 | 8.01 | 4.5 | pass |
| dark_increased_contrast | marker.quote.text | color.ground | #D9A24A | #161512 | 8.01 | 4.5 | pass |
| dark_increased_contrast | marker.note.text | color.ground | #7FB5A3 | #161512 | 7.86 | 4.5 | pass |
| dark_increased_contrast | marker.audio.text | color.ground | #8FB0D4 | #161512 | 8.11 | 4.5 | pass |
| dark_increased_contrast | marker.generated.text | color.ground | #B49BD6 | #161512 | 7.48 | 4.5 | pass |
| dark_increased_contrast | marker.word.text | color.ground | #D9A24A | #161512 | 8.01 | 4.5 | pass |
| dark_increased_contrast | marker.attention.text | color.ground | #E0837A | #161512 | 6.69 | 4.5 | pass |
| dark_increased_contrast | marker.pending.text | color.ground | #A8A298 | #161512 | 7.20 | 4.5 | pass |
| dark_increased_contrast | color.ink | color.surface | #ECE7DD | #1E1C19 | 13.79 | 4.5 | pass |
| dark_increased_contrast | color.muted | color.surface | #A8A298 | #1E1C19 | 6.71 | 4.5 | pass |
| dark_increased_contrast | color.pine | color.surface | #7FB5A3 | #1E1C19 | 7.32 | 4.5 | pass |
| dark_increased_contrast | color.ochre | color.surface | #D9A24A | #1E1C19 | 7.46 | 4.5 | pass |
| dark_increased_contrast | marker.quote.text | color.surface | #D9A24A | #1E1C19 | 7.46 | 4.5 | pass |
| dark_increased_contrast | marker.note.text | color.surface | #7FB5A3 | #1E1C19 | 7.32 | 4.5 | pass |
| dark_increased_contrast | marker.audio.text | color.surface | #8FB0D4 | #1E1C19 | 7.55 | 4.5 | pass |
| dark_increased_contrast | marker.generated.text | color.surface | #B49BD6 | #1E1C19 | 6.96 | 4.5 | pass |
| dark_increased_contrast | marker.word.text | color.surface | #D9A24A | #1E1C19 | 7.46 | 4.5 | pass |
| dark_increased_contrast | marker.attention.text | color.surface | #E0837A | #1E1C19 | 6.23 | 4.5 | pass |
| dark_increased_contrast | marker.pending.text | color.surface | #A8A298 | #1E1C19 | 6.71 | 4.5 | pass |
| dark_increased_contrast | color.pine_on | color.pine | #161512 | #7FB5A3 | 7.86 | 4.5 | pass |
| dark_increased_contrast | color.ink | color.pine_tint | #ECE7DD | #2E3933 | 9.74 | 4.5 | pass |
| dark_increased_contrast | color.pine | color.pine_tint | #7FB5A3 | #2E3933 | 5.17 | 4.5 | pass |
| dark_increased_contrast | color.ink | color.ochre_tint | #ECE7DD | #42351F | 9.68 | 4.5 | pass |
| dark_increased_contrast | color.ochre | color.ochre_tint | #D9A24A | #42351F | 5.24 | 4.5 | pass |
| dark_increased_contrast | color.ink | marker.quote.tint | #ECE7DD | #42351F | 9.68 | 4.5 | pass |
| dark_increased_contrast | marker.quote.text | marker.quote.tint | #D9A24A | #42351F | 5.24 | 4.5 | pass |
| dark_increased_contrast | color.ink | marker.word.tint | #ECE7DD | #42351F | 9.68 | 4.5 | pass |
| dark_increased_contrast | marker.word.text | marker.word.tint | #D9A24A | #42351F | 5.24 | 4.5 | pass |
| dark_increased_contrast | color.ink | marker.audio.tint | #ECE7DD | #31383E | 9.65 | 4.5 | pass |
| dark_increased_contrast | marker.audio.text | marker.audio.tint | #8FB0D4 | #31383E | 5.28 | 4.5 | pass |
| dark_increased_contrast | color.ink | marker.generated.tint | #ECE7DD | #3A343E | 9.79 | 4.5 | pass |
| dark_increased_contrast | marker.generated.text | marker.generated.tint | #B49BD6 | #3A343E | 4.94 | 4.5 | pass |
| dark_increased_contrast | color.ink | marker.attention.tint | #ECE7DD | #432E2A | 10.25 | 4.5 | pass |
| dark_increased_contrast | marker.attention.text | marker.attention.tint | #E0837A | #432E2A | 4.63 | 4.5 | pass |
| dark_increased_contrast | color.ink | marker.pending.tint | #ECE7DD | #373531 | 9.93 | 4.5 | pass |
| dark_increased_contrast | marker.pending.text | marker.pending.tint | #A8A298 | #373531 | 4.83 | 4.5 | pass |
| dark_increased_contrast | color.cover_title | color.cover_field_1 | #F4F2ED | #2F5D50 | 6.70 | 4.5 | pass |
| dark_increased_contrast | color.cover_title | color.cover_field_2 | #F4F2ED | #5A6B4A | 5.16 | 4.5 | pass |
| dark_increased_contrast | color.cover_title | color.cover_field_3 | #F4F2ED | #7A4B3A | 6.48 | 4.5 | pass |
| dark_increased_contrast | color.cover_title | color.cover_field_4 | #F4F2ED | #3F5A78 | 6.37 | 4.5 | pass |
| dark_increased_contrast | color.cover_title | color.cover_field_5 | #F4F2ED | #4A4A58 | 7.78 | 4.5 | pass |

## Component pairs

`contrast.component_pairs`: 56 measurements, 0 failing, 16 exempt disabled-state measurements below the minimum (reported, not enforced). Colors after compositing a faded control over the ground. Text needs 4.5:1, glyphs 3.0:1.

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

## Not permitted, for reference

Section 4.4.2 allows only ink and the marker's own color on a tint. Muted text on tints, measured here so components never use it:

| Appearance | Fill | Muted | Fill color | Ratio |
| --- | --- | --- | --- | --- |
| light | color.ochre_tint | #6B6760 | #F1E4C8 | 4.46 |
| light | color.pine_tint | #6B6760 | #DCE8E2 | 4.47 |
| light | marker.attention.tint | #6B6760 | #F3DCD7 | 4.29 |
| light | marker.audio.tint | #6B6760 | #DCE4EE | 4.39 |
| light | marker.generated.tint | #6B6760 | #E7DFF0 | 4.34 |
| light | marker.pending.tint | #6B6760 | #ECE9E2 | 4.64 |
| light | marker.quote.tint | #6B6760 | #F1E4C8 | 4.46 |
| light | marker.word.tint | #6B6760 | #F1E4C8 | 4.46 |
| dark | color.ochre_tint | #A8A298 | #31291A | 5.67 |
| dark | color.pine_tint | #A8A298 | #252B26 | 5.71 |
| dark | marker.attention.tint | #A8A298 | #322421 | 5.88 |
| dark | marker.audio.tint | #A8A298 | #272B2D | 5.64 |
| dark | marker.generated.tint | #A8A298 | #2C282D | 5.72 |
| dark | marker.pending.tint | #A8A298 | #2A2925 | 5.75 |
| dark | marker.quote.tint | #A8A298 | #31291A | 5.67 |
| dark | marker.word.tint | #A8A298 | #31291A | 5.67 |
| light_increased_contrast | color.ochre_tint | #646059 | #E7D6B6 | 4.37 |
| light_increased_contrast | color.pine_tint | #646059 | #CBDAD3 | 4.32 |
| light_increased_contrast | marker.attention.tint | #646059 | #EBCCC6 | 4.16 |
| light_increased_contrast | marker.audio.tint | #646059 | #CCD6E2 | 4.25 |
| light_increased_contrast | marker.generated.tint | #646059 | #DBD1E6 | 4.25 |
| light_increased_contrast | marker.pending.tint | #646059 | #DFDCD5 | 4.57 |
| light_increased_contrast | marker.quote.tint | #646059 | #E7D6B6 | 4.37 |
| light_increased_contrast | marker.word.tint | #646059 | #E7D6B6 | 4.37 |
| dark_increased_contrast | color.ochre_tint | #A8A298 | #42351F | 4.71 |
| dark_increased_contrast | color.pine_tint | #A8A298 | #2E3933 | 4.74 |
| dark_increased_contrast | marker.attention.tint | #A8A298 | #432E2A | 4.98 |
| dark_increased_contrast | marker.audio.tint | #A8A298 | #31383E | 4.69 |
| dark_increased_contrast | marker.generated.tint | #A8A298 | #3A343E | 4.76 |
| dark_increased_contrast | marker.pending.tint | #A8A298 | #373531 | 4.83 |
| dark_increased_contrast | marker.quote.tint | #A8A298 | #42351F | 4.71 |
| dark_increased_contrast | marker.word.tint | #A8A298 | #42351F | 4.71 |

## Tints in grayscale, for reference

Grey level (0-255) of each marker tint and text color after a luminance grayscale conversion.

| Appearance | Marker | Tint | Tint grey | Text | Text grey |
| --- | --- | --- | --- | --- | --- |
| light | quote | #F1E4C8 | 229 | #8A5410 | 96 |
| light | note | none | - | #2F5D50 | 85 |
| light | audio | #DCE4EE | 227 | #3F5A78 | 88 |
| light | generated | #E7DFF0 | 226 | #6B4E8E | 91 |
| light | word | #F1E4C8 | 229 | #8A5410 | 96 |
| light | attention | #F3DCD7 | 225 | #A63D2F | 96 |
| light | pending | #ECE9E2 | 233 | #6B6760 | 103 |
| dark | quote | #31291A | 42 | #D9A24A | 172 |
| dark | note | none | - | #7FB5A3 | 170 |
| dark | audio | #272B2D | 42 | #8FB0D4 | 173 |
| dark | generated | #2C282D | 41 | #B49BD6 | 166 |
| dark | word | #31291A | 42 | #D9A24A | 172 |
| dark | attention | #322421 | 39 | #E0837A | 157 |
| dark | pending | #2A2925 | 41 | #A8A298 | 163 |
| light_increased_contrast | quote | #E7D6B6 | 216 | #875210 | 94 |
| light_increased_contrast | note | none | - | #2F5D50 | 85 |
| light_increased_contrast | audio | #CCD6E2 | 213 | #3F5A78 | 88 |
| light_increased_contrast | generated | #DBD1E6 | 213 | #6B4E8E | 91 |
| light_increased_contrast | word | #E7D6B6 | 216 | #875210 | 94 |
| light_increased_contrast | attention | #EBCCC6 | 211 | #9E3A2D | 91 |
| light_increased_contrast | pending | #DFDCD5 | 220 | #646059 | 96 |
| dark_increased_contrast | quote | #42351F | 55 | #D9A24A | 172 |
| dark_increased_contrast | note | none | - | #7FB5A3 | 170 |
| dark_increased_contrast | audio | #31383E | 55 | #8FB0D4 | 173 |
| dark_increased_contrast | generated | #3A343E | 54 | #B49BD6 | 166 |
| dark_increased_contrast | word | #42351F | 55 | #D9A24A | 172 |
| dark_increased_contrast | attention | #432E2A | 51 | #E0837A | 157 |
| dark_increased_contrast | pending | #373531 | 53 | #A8A298 | 163 |
