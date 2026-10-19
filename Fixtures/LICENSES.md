# Fixture provenance and licenses

Every fixture used by Sylvia's tests is listed here with its source, license and SHA-256. Only public-domain, CC0 or generated content is used; no scraped copyrighted library (plan Sections 18.2 and 19.1). Retrieved 6 October 2026.

Files over a few megabytes are not committed. They are listed in `Scripts/fixtures/manifest.tsv` and fetched into `$SYLVIA_FIXTURE_CACHE` (default `~/Library/Caches/SylviaFixtures`) by `Scripts/fixtures/fetch.sh`, which verifies each digest. Large generated fixtures (for example the 5 GiB audiobook and the hundreds-of-members edition) are produced by `Scripts/fixtures/generate-*.sh` into the same cache and are not committed. Small generated fixtures may be committed beside the test or contract that uses them; they are listed under "Generated, committed" with their generator.

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

## Generated, committed

Small generated fixtures sit beside the tests or contracts that use them. Each is produced by a script or tool in this repository from text and data written for the fixture; none contains third-party content unless its row names a public-domain source listed above. Entries were added at M0 integration (13 October 2026) from each gate's request and checked against the files: every listed file exists, and each SHA-256 below was recomputed from the committed file.

### G0.1 EPUB (`Spikes/G01-EPUB/Fixtures/generated/`)

Generator: `Scripts/fixtures/generate-g01-epub-fixtures.sh` (deterministic; `--check` regenerates and compares). Text written for the fixtures; no third-party content. The obfuscated "font" is 4,096 synthetic bytes, not a usable font. The AES keys in the protected-chapter fixtures are derived from public strings and protect nothing.

| Files | SHA-256 |
| --- | --- |
| 17 EPUBs: `g01-adept-like`, `g01-bomb`, `g01-bomb-lying`, `g01-csp-bypass`, `g01-deep-nesting`, `g01-encrypted-chapter`, `g01-font-obfuscated`, `g01-form-navigation`, `g01-hostile`, `g01-lcp-like`, `g01-nesting-bypass`, `g01-nesting-limit`, `g01-nonhtml-active`, `g01-symlink`, `g01-traversal`, `g01-truncated`, `g01-unicode` (`.epub`; 1,299 to 205,767 bytes) | Per file in `MANIFEST.tsv` beside them, with every entry's size and CRC-32 |
| `g01-font-obfuscated.font-plain.sha256`, `g01-protected-chapter.digests.txt`, `MANIFEST.tsv` | Written by the same run; checked by `--check` |

### G0.1 PDF (`Spikes/G01-PDF/Fixtures/`)

Generator: `Spikes/G01-PDF/Tools/make_pdf_fixtures.py` (`--check` regenerates and compares). Original generated prose; the standard Helvetica font is referenced, not embedded; the "scanned" pages are generated grey bars.

| File | SHA-256 |
| --- | --- |
| `labels-multipage.pdf` | `6ffa266bf32eea6c9bc2984d351bc55d19bd948c65714a4e6d2b9ab41d8138d1` |
| `rotated.pdf` | `892a204ec897d8294fe7ae618a2b4fe276135e7be3a0b2fd020c6f67acec653c` |
| `two-column.pdf` | `0ac65589469fc610ac4a5650c5732bc37c3d3d587a367afaee82b922da0165af` |
| `mixed-scanned.pdf` | `1fa0c32f14825e52b04350d882471f732b475c930bd0dae50cc4e9fe0235e293` |
| `unicode.pdf` | `0d2182907c8bdde33b4553c2daf267f6d6b422acaab848d5b71d5d2817a52131` |
| `encrypted-user-password.pdf` | `6d7bef64f1e295a8cb38e47234be09021b19030afc9dfe5bef558323b5f41315` |
| `encrypted-owner-only-nocopy.pdf` | `7119b57492bcebb531b5a81a0b89f36de4c7c0d7ff1423861bf31571a49d26a9` |
| `truncated.pdf` | `0fc3c7bece261dc6f3228270eeaeedea86c6b1525f103e98972c81f82b923f6a` |
| `actions.pdf` | `9f17e4d7a9295a348dbafe7b6206fd5140bc373f06faa1a059a60293fa13dba0` |
| `actions-nonurl.pdf` | `3dcd59c685784d304990bcaa8cabcf36311cd5f3ce23244d547eac00d2b06829` |
| `actions-chained.pdf` (12,952 bytes) | `21f8480692ca81003190b7fd496acf9255fcd9e4a73b1950daafd1c9cc3f89b4` |
| `text-layout.pdf` (3,363 bytes) | `cf2d5a1fa176f2cfc33ad43db210434f342d987c236f1bfa8fb3e56e37266153` |
| `Spikes/G01-PDF/Tests/Resources/anchors-captured-ios-26.5-23F77.json` (24,138 bytes; a test input, not a PDF) | `11e0a2c2f2204489ec0462a3d62964c75ac54eb028f04cefc50c48326172abb9` |

`actions-chained.pdf` and `text-layout.pdf` were added on `m0-int-minors-g01-pdf` and merged at M0 assembly (14 October 2026); the earlier digests requested for `actions-chained.pdf` (`02e43a75…`, `ce2eb738…`) belong to superseded versions. The JSON file is the input of `CrossOSRestoreTests`: the ten anchors that `AnchorCaptureRestoreTests.testWriteAnchorSamples` wrote on the iOS 26.5 (23F77) simulator from these generated fixtures; no third-party content. Each digest above was recomputed from the committed file at assembly.

### G0.2 Transfer

| Files | Generator and content |
| --- | --- |
| `Contracts/fixtures/{transfer-manifest,pairing-payload,pair-request,pair-response,capabilities,catalog-page,device-inbox-page,receipt,receipt-ack,error}.v1/{valid,invalid}/*.json` (69 files; `receipt-ack.v1` with 3 valid and 4 invalid added on 19 October 2026, and 2 more invalid ones, the two mixed forms of `queue_entry_id` and `entry_state`, on 20 October 2026) | `Scripts/fixtures/generate-g02-transfer-contract-fixtures.sh`, deterministic; synthetic data. The G0.2 CI drop-in checks that the generator reproduces them exactly. |
| `Spikes/G02-Transfer/TransferKit/Tests/SylviaTransferCoreTests/Fixtures/manifests/semantic-invalid/*.json` (14 files) | Same generator; synthetic data. |
| `Spikes/G02-Transfer/TransferKit/Tests/SylviaTransferCoreTests/Fixtures/certs/{p256,p384,rsa2048}.der` and `.spki-sha256` | `Scripts/fixtures/generate-g02-transfer-test-certs.sh`: throwaway self-signed test certificates and their OpenSSL-computed SPKI pins. The private keys were discarded when the script ran; no key material is committed. |

### G0.3 Intake (hand-written)

`Contracts/fixtures/import-handoff-manifest.v1/` (5 valid, 30 invalid) and `Contracts/fixtures/sylviapack-manifest.v1/` (7 valid, 48 invalid) hold hand-written example JSON with placeholder IDs and digests (counted at M0 assembly, 14 October 2026; the fixtures added in G0.3's later review rounds are committed valid fixtures with one field changed each, with the same placeholder IDs and digests). `sylviapack-manifest.v1/valid/generated-large-pack.json` reproduces the manifest that `Scripts/fixtures/generate-g03-intake-pack.sh` writes.

### G0.4 Audio

None committed (checked at its merge on 14 October 2026: the branch adds no audio, data or test-resource file). Its generated fixtures stay in the cache; see "Generated into the cache" below.

### G0.5 Recovery

| File | Source | SHA-256 |
| --- | --- | --- |
| `Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Fixtures/library-v1.sqlite` (352,256 bytes) | Generated by `g05-recovery-tool make-v1-fixture --out <file>` (`Spikes/G05-Recovery`): a v1-schema Sylvia library holding the G0.5 golden corpus; deterministic content and clock, random entity UUIDs, so a rerun produces a different file. Contents: text written for the spike, generated digests, and short public-domain quotations: George Long's 1862 translation of *Meditations* as `epub/se-meditations.epub` (above) prints it (IV.17 verbatim; V.6 verbatim up to "come and see", followed by Unicode test characters written for the spike; V.6 abridged) and Henry David Thoreau ("Simplify, simplify." from *Walden*, 1854; "sauntering" from *Walking*, 1862). Full list: `Spikes/G05-Recovery/FIXTURES.md`. Regenerated in G0.5 recovery review round 4 (merged at M0 assembly, 14 October 2026). | `b3a4df0a7d45675bc36ff4de862a9ebd984036c808e392cec9db64ac5ac11b5e` |

`Contracts/fixtures/backup-manifest.v1/` (2 valid, 20 invalid) is hand-written.

### G0.5 AI

| Files | Generator and content |
| --- | --- |
| `Contracts/fixtures/context-pack.v1/valid/*.json` (8) and `Contracts/fixtures/provider-config.v1/valid/*.json` (5) | Swift-built instances exported by `ContractExportTests` (`G05_CONTRACT_EXPORT`) and written by `Spikes/G05-AI/Scripts/make-contract-fixtures.py`. |
| `Contracts/fixtures/context-pack.v1/invalid/*.json` (21) and `Contracts/fixtures/provider-config.v1/invalid/*.json` (12) | One named mutation each of a valid fixture, by the same script. |
| `Spikes/G05-AI/Tests/SylviaContextTests/EvaluationSet/eval-set.v0.json` (15,795 bytes) | Hand-authored 15-item evaluation seed. |

The context-pack fixtures and the evaluation seed quote short passages from the Standard Ebooks *Walden* and *Middlemarch* listed under "Committed" above; no other text source.

### G0.6 Design

| Files | Generator and content |
| --- | --- |
| `Contracts/design/marginalia.v1.json` (65,683 bytes) | `sylvia-design-export write` (`Packages/Design`, `Sources/SylviaDesignTokens/Generation/TokenExport.swift`) from the token definitions. CI checks the generator output against the committed file. |
| `Contracts/fixtures/design-tokens.v1/valid/*.json` (2) and `invalid/*.json` (12, one defect each), about 64 KB each | Same tool (`ContractFixtures.swift`). |
| `Packages/Design/Tests/SylviaDesignSnapshotTests/__Snapshots__/ComponentSnapshotTests/*.png` (527 files, 37,703,582 bytes, largest 368,357 bytes) | Snapshot references recorded by `ComponentSnapshotTests` in record mode on the simulator `Sylvia-M0-g06-design` (iPhone 17, iOS 26.5). Content: Sylvia components rendering public-domain sample text (*Middlemarch*, *Walden*, *Meditations*) in Literata (SIL OFL 1.1, below) and the system fonts. |
| `Packages/Design/LintFixtures/**` (9 files) | Hand-written samples for the design lint. |

Generated, committed, not fixtures: `Packages/Design/Sources/SylviaDesign/Resources/Colors.xcassets`, `Symbols.xcassets` and `Vocabulary.xcstrings` (written by `sylvia-design-export write`). The images under `Docs/Stage0/evidence/` are evidence written by the gates' own runs, not fixtures; for G0.6 they are 196 screenshots under `G06-Design/screens/` from `Scripts/ci.d/21-design-catalog.sh` on the iPhone 17, iPhone SE (3rd generation) and iPad (A16) simulators (iOS 26.5), plus two symbol sheets, showing the same public-domain sample text; for G0.4 they are 14 screenshots (`G04-Audio/results/quick-capture-simulator-*.png`, 1,754,208 bytes, largest 241,516; 12 at the G0.4 merge, 2 added in its review round 6) taken by its quick-capture UI tests on the iPhone 17 simulator (iOS 26.5), showing the Shortcuts app, Control Center and the G0.4 harness.

### M0 contract consolidation (ADR-0016)

| Files | Generator and content |
| --- | --- |
| `Contracts/fixtures/anchor.v1/` (15 valid, 151 invalid, 20 semantic-invalid, `mutations.json`) and `Contracts/fixtures/capture-envelope.v1/` (31 valid, 219 invalid, 39 semantic-invalid, `mutations.json`); counted again on 19 October 2026, when three composed PDF selections from `Docs/Stage0/evidence/G01-PDF/anchor-composed-samples.json` (the G0.1 PDF generator's prose) became valid anchor fixtures, one of them a valid capture fixture, with two more semantic-invalid fixtures (ADR-0016 section 11) | Written by `Scripts/contracts/make-contract-fixtures.py` (deterministic; `Scripts/ci.d/11-capture-anchor-contracts.sh` checks that it reproduces them exactly). Sources: the G0.1 EPUB and PDF anchor samples (Standard Ebooks *Meditations*, listed above; the generated `g01-unicode.epub`; the G0.1 PDF generator's prose), the G0.4 capture probe's records (digests, byte counts and timing of excerpts made from the LibriVox *Meditations* recording, listed above; no audio is committed), and short public-domain passages of Thoreau's *Walden* (1854) and *Walking* (1862; the Markdown fixture adds emphasis) and George Long's translation of *Meditations*, written into the generator. IDs, digests not taken from a spike, transcripts, answers and the ISBN are fixtures. Counted at M0 assembly (14 October 2026). |

## Generated into the cache (not committed)

| File under `$SYLVIA_FIXTURE_CACHE` | Generator | Size and SHA-256 | Content |
| --- | --- | --- | --- |
| `generated/g01-pdf/large-1000.pdf` | `Scripts/fixtures/generate-g01-pdf-large.sh` | 1,000 pages, 1,713,026 bytes; `cfa95b03bc0bc3a268a7738c491b1ac974ccd72023c5bd171eb048351d2ee299` (pinned in the script) | Original generated prose |
| `generated/g02-transfer/large-5GiB.bin` | `Scripts/fixtures/generate-g02-transfer-large.sh` | 5,368,709,120 bytes; `d2383fe38d8033b62ef9e6222756369fab813d2c64b2bce41e86ad9494af16d9` (pinned) | AES-128-CTR keystream (key `000102...0f`, zero IV) |
| `generated/g02-transfer/sim-*.bin` | `Scripts/fixtures/generate-g02-transfer-sim-files.sh` | Sizes and SHA-256 values pinned in the script | AES-128-CTR keystream, for the G0.2 simulator runs |
| `generated/g03-intake/large.sylviapack` and `generated/g03-intake/work/part-01.caf` | `Scripts/fixtures/generate-g03-intake-pack.sh` | Pack 4,846,059,727 bytes; `982562b020ea7213721661fa0a6adf4d7a81c9bf68e5eda498bc417beebf0268` (pinned). `part-01.caf` 4,831,838,986 bytes; `b4e3eac6d299ef937eb52a103187a2847a63cc0084e9ab2d4c18d41bfa91bcc1` (pinned in the script since G0.3 review R2-06 and checked on every rebuild) | Seeded synthetic CAF audio, fixed text, and the LibriVox *Meditations* section 01 MP3 listed above (public domain) |
| `generated/g04-audio/` (28 files): two PCM masters (`master-600s.wav`, `master-long.wav`), a 1 kHz tone (`tone-1khz-60s.wav` and `.m4a`), 17 format fixtures (`fmt-*`: 16 ten-minute files made from `master-600s.wav` and the 22-minute LibriVox section 01 MP3), the four-member MP3 book `multi/` and three 10-hour files (`long-*`) | `Scripts/fixtures/generate-g04-audio-fixtures.sh` | 1,189,609,084 bytes in all; SHA-256 and size per file in `manifest.tsv` beside the files and in `Docs/Stage0/evidence/G04-Audio/fixture-generation.log` | Derived from the public-domain LibriVox *Meditations* sections 01 and 02 MP3 listed above (decoded, resampled, cut, concatenated, looped and re-encoded; `fmt-librivox-mp3-22k.mp3` is the section 01 MP3 copied unchanged), plus a generated 1 kHz sine |
| `generated/g04-audio/long-formats/` (13 files): 10.2-hour files of every other provisional format and 3.0-hour native FLAC and Ogg Opus | `Scripts/fixtures/generate-g04-audio-long-formats.sh` | 7,804,065,816 bytes in all; per file in its own `manifest.tsv` and in `Docs/Stage0/evidence/G04-Audio/fixture-generation-long-formats.log` | `master-long.wav` above, looped and re-encoded (public domain, derived) |
| `generated/g04-audio/probes/` (6 files): 60 s native FLAC and Ogg Opus with three Vorbis-comment chapter numberings | `Scripts/fixtures/generate-g04-audio-probes.sh` | 5,279,460 bytes in all; per file in its own `manifest.tsv` and in `Docs/Stage0/evidence/G04-Audio/fixture-generation-probes.log` | The first 60 s of `master-600s.wav` above (public domain, derived) |
| `generated/g04-audio/stereo/` (15 files): a 300 s stereo master (`master-stereo-300s.wav`), its encodes in the provisional formats (`st-*`), and a FLAC with the left channel in both (`st-dual-mono.flac`) | `Scripts/fixtures/generate-g04-audio-stereo.sh` (added in G0.4 review round 6, merged at M0 assembly) | 144,591,691 bytes in all; per file in its own `manifest.tsv` and in `Docs/Stage0/evidence/G04-Audio/fixture-generation-stereo.log` (two generations, identical) | `master-600s.wav` (section 01, left channel) and `master-long.wav` from 1,400 s (section 02, right channel) above (public domain, derived) |

The G0.4 generators use Homebrew ffmpeg/ffprobe 8.1.2 (built with libmp3lame, libopus and AudioToolbox; the HE-AAC files come from AudioToolbox through ffmpeg's `aac_at`) and macOS `afconvert` (Opus in CAF), on macOS 26.6.2 (25G83). Each script writes a `.stamp` naming its own SHA-256, the ffmpeg version and the macOS version (and the master's SHA-256 for the long-format and probe scripts), and rebuilds everything when one of them changes; the AudioToolbox outputs are reproducible only on the same macOS version. The G0.4 tests also read the LibriVox M4B listed under "Fetched into the cache" as downloaded. A device build of the G0.4 test bundle copies these files and the M4B into the build products (about 8.6 GB; the CI drop-in builds it only with `G04_DEVICE_FIXTURES=1`), never into the repository. The G0.4 harness app bundles the two committed excerpts under `audio/` and plays them when no book has been copied into its Documents folder. Checked at the G0.4 merge (14 October 2026): all 47 generated files in the cache match their manifests' SHA-256 and size, and each manifest equals the one in the committed generation log (`Docs/Stage0/evidence/M0-Integration/g04-fixture-cache-check.log`). The fourth generator, `generate-g04-audio-stereo.sh`, uses the same tools; at M0 assembly its 15 files matched their manifest's SHA-256 and size.

## Bundled with the app (not fixtures)

`Packages/Design/Sources/SylviaDesign/Resources/Fonts/`: Literata 3.103 variable fonts (`Literata[opsz,wght].ttf` renamed `Literata-Variable.ttf`, SHA-256 `b41138c9373112f32abb589cc22e8674b06ed4048b0c513be922bdd26f274440`; `Literata-Italic[opsz,wght].ttf` renamed `Literata-Italic-Variable.ttf`, SHA-256 `d483dfaeba9cbf4ce71d32a52ee65df82f7e35b15fff8d1011cdb242d1fcd465`) from https://github.com/googlefonts/literata/releases/tag/3.103 (release archive SHA-256 `f7fb973cafb26cf785cbebaeaf51c18f87c15a3bcf4d82a7d4857564db5b056d`). SIL Open Font License 1.1; `OFL.txt` sits beside the fonts. No Reserved Font Name is declared; the font files are unmodified.

Third-party code, fonts and scripts that ship inside the app's and the companion's packages (for example the fonts and scripts in Readium's resources) are inventoried in `Docs/Licenses/third-party-inventory.md` (ADR-0014).
