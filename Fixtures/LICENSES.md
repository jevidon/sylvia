# Fixture provenance and licenses

Every fixture used by Sylvia's tests is listed here with its source, license and SHA-256. Only public-domain, CC0 or generated content is used; no scraped copyrighted library (plan Sections 18.2 and 19.1). Retrieved 6 October 2026.

Files over a few megabytes are not committed. They are listed in `Scripts/fixtures/manifest.tsv` and fetched into `$SYLVIA_FIXTURE_CACHE` (default `~/Library/Caches/SylviaFixtures`) by `Scripts/fixtures/fetch.sh`, which verifies each digest. Generated fixtures (for example the 5 GiB audiobook and the hundreds-of-members edition) are produced by `Scripts/fixtures/generate-*.sh` into the same cache and are not committed.

## Committed

| File | Source | License | SHA-256 |
| --- | --- | --- | --- |
| `epub/se-walden.epub` | Standard Ebooks, *Walden* by Henry David Thoreau, https://standardebooks.org/ebooks/henry-david-thoreau/walden | Text believed public domain in the USA (per the book's Uncopyright page); Standard Ebooks' contributions dedicated under CC0 1.0 | `6168a788b950aae3e778bfe9e176feda5d948453ca0050cf00ba9e706d7332ae` |
| `epub/se-meditations.epub` | Standard Ebooks, *Meditations* by Marcus Aurelius, translated by George Long, https://standardebooks.org/ebooks/marcus-aurelius/meditations/george-long | Text believed public domain in the USA (per the book's Uncopyright page); Standard Ebooks' contributions dedicated under CC0 1.0 | `c2b77e9daa37694b978f78f9ae2d801fd263be533af187e8b36b7da28845e0c8` |
| `epub/se-middlemarch.epub` | Standard Ebooks, *Middlemarch* by George Eliot, https://standardebooks.org/ebooks/george-eliot/middlemarch | Text believed public domain in the USA (per the book's Uncopyright page); Standard Ebooks' contributions dedicated under CC0 1.0 | `cc2f7d8113f526335de81455b5bea9d3750a935f4b751cbdc6a191b3138ffcc8` |
| `epub/pg-walden-epub2.epub` | Project Gutenberg eBook #205, EPUB 2 without images, https://www.gutenberg.org/ebooks/205 | Public domain in the USA; file carries the Project Gutenberg License | `657b0f7fcb603f4c386ea249b46b6282c0aded09ea2f65d324ec3d84e61d9b59` |
| `epub/pg-walden-epub3.epub` | Project Gutenberg eBook #205, EPUB 3 with images, https://www.gutenberg.org/ebooks/205 | Public domain in the USA; file carries the Project Gutenberg License | `0b757000593518f64818283abc6e337e9f0c174a276d027d41e87194675ab0c0` |
| `audio/meditations-01-first180s.mp3` | First 180 s of LibriVox *The Meditations of the Emperor Marcus Aurelius Antoninus*, section 01, 64 kbps MP3 (stream copy, no re-encode), https://archive.org/details/themeditationsofmarcusaurelius_1801_librivox | Public domain (Public Domain Mark 1.0) | `6a3b752cc744ccb310a6d71149b96a7f29d632e35ca5a6ad8abb3e46c532a1ad` |
| `audio/meditations-02-first150s.mp3` | First 150 s of the same recording, section 02 | Public domain (Public Domain Mark 1.0) | `4e27b8d12646a2fc6c9e37bd31229405ea52a65a4904a069ce7aa5b005a163f3` |

The two audio excerpts were cut with `ffmpeg -t <seconds> -c copy -map_metadata 0` from the full section files listed below.

**Project Gutenberg files.** The texts are public domain in the USA, but the files include the Project Gutenberg License and trademark terms. They are fine as private test fixtures. Before this repository or any build is distributed publicly, either comply with those terms or replace them with Standard Ebooks or generated EPUB 2 fixtures.

## Fetched into the cache

| File | Source | License |
| --- | --- | --- |
| `meditationsofmarcusaurelius_01_aurelius_64kb.mp3` | LibriVox recording above, section 01 | Public domain |
| `meditationsofmarcusaurelius_02_aurelius_64kb.mp3` | LibriVox recording above, section 02 | Public domain |
| `MeditationsMarcusAurelius_librivox.m4b` | LibriVox recording above, single M4B with 12 chapters (AAC, 44.1 kHz mono, 4 h 47 m) | Public domain |

Digests and sizes are pinned in `Scripts/fixtures/manifest.tsv`.

## Bundled with the app (not fixtures)

`Packages/Design/Sources/SylviaDesign/Resources/Fonts/`: Literata 3.103 variable fonts (`Literata[opsz,wght].ttf` renamed `Literata-Variable.ttf`, SHA-256 `b41138c9373112f32abb589cc22e8674b06ed4048b0c513be922bdd26f274440`; `Literata-Italic[opsz,wght].ttf` renamed `Literata-Italic-Variable.ttf`, SHA-256 `d483dfaeba9cbf4ce71d32a52ee65df82f7e35b15fff8d1011cdb242d1fcd465`) from https://github.com/googlefonts/literata/releases/tag/3.103 (release archive SHA-256 `f7fb973cafb26cf785cbebaeaf51c18f87c15a3bcf4d82a7d4857564db5b056d`). SIL Open Font License 1.1; `OFL.txt` sits beside the fonts. No Reserved Font Name is declared; the font files are unmodified.
