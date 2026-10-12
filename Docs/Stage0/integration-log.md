# M0 integration log

Branch `m0-integrate`, started from `m0` at `b4bca76` on 13 October 2026. It combines the latest `main` and the seven Stage 0 gate branches whose final review is complete, so parallel M1 work can start from one tree. Integration by an agent; every outcome below is agent-reviewed, human sign-off pending.

**G0.4 audio is not merged here.** `m0-g04-audio` is still in a fix-and-review round and is merged later by another agent. Its report (`G04-Audio.md`), ADR-0006, ADR-0007, `Spikes/G04-Audio/` and `Scripts/ci.d/60-g04-audio.sh` are therefore absent from this branch, and the indexes below mark them as such.

## 1. Merge of `main`

`git merge --no-ff main` (merge commit `cf88104`). `main` carried three changes `m0` lacked:

| Change | Outcome |
| --- | --- |
| `Docs/Sylvia_Companion_Vision_Architecture_Addendum.md` (proposed addendum, 12 October 2026) | Brought in unchanged. Its suggestions (including its Section 12 roadmap addition) are not applied to the plan. |
| `Docs/Sylvia_Product_Brief.md`: "Later - one home for everything you read and hear" paragraph | Merged without conflict. |
| Plan: unified content hub roadmap in Section 24, a Section 3.3 sentence, D14, front matter and an Appendix D entry, labelled "draft 0.3" on `main` | Merged; see below. |

The plan had two textual conflicts (front matter; the D14/D15 rows) and one semantic one (both sides call their revision "draft 0.3"). Resolution, keeping every change from both sides:

- `m0`'s pre-M0 decision revision stays **draft 0.3** (6 October).
- `main`'s roadmap revision becomes **Draft 0.4 - 7 October 2026** in Appendix D, same bullets, with one sentence saying it was written on `main` as 0.3 and renumbered at integration. Appendix D lists revisions newest first (as `m0` already did: 0.3 above 0.2), so 0.4 is the first entry; `main` had appended its entry at the end of the file.
- Front matter: status "Draft 0.4", revised 7 October 2026, naming drafts 0.2, 0.3 and 0.4.
- D14 takes `main`'s wording (articles/feeds/newsletters, phases A-C, the Phase A versus Docker ordering decision). D15 keeps `m0`'s wording (seven-marker set, opaque chrome); `main`'s D15 was the unchanged draft 0.2 row.
- Section 3.3 and Section 24 merged automatically. A diff of the result against each parent shows every `m0` change and every `main` change present once.

## 2. Gate branches (squash merges)

Each branch was merged with `git merge --squash <branch>` in the order below. No merge produced a conflict: the seven branches add 1,822 files and modify none that existed on `m0`, and no file is touched by two branches. After the seventh merge a script compared every path each branch changes (relative to its merge base `77f0be4`) with the integration tree: all 1,822 blobs are identical to the branch's final commit.

| Order | Gate | Branch | Final commit (reviewed) | Final review | Verdict | Open findings | Report | Integration commit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | G0.6 Design | `m0-g06-design` | `32f37065cb637345b5e958133513640ecba9850b` | g06-design:review-3 | accept-with-minor | R3-01, R3-02 (minor) | [G06-Design.md](G06-Design.md) | `c72c7ebf3836eece05065e2369485c38061b306a` |
| 2 | G0.5 Recovery | `m0-g05-recovery` | `66f96eafee70ba9c18751f026cf593bc93c56db8` | g05-recovery:review-3 | accept-with-minor | R3-01 to R3-05 (minor) | [G05-Recovery.md](G05-Recovery.md) | `2a37a00b1e5ba5f067653bf6669d9ac6b3c77f6e` |
| 3 | G0.1 EPUB | `m0-g01-epub` | `d86abbf0cd90df615d5ee2af68860f648d14a49b` | g01-epub:review-3 | accept-with-minor | R3-01, R3-02 (minor) | [G01-EPUB.md](G01-EPUB.md) | `35fef38a40f6273427fb5bd4ea7f949945c7e237` |
| 4 | G0.1 PDF | `m0-g01-pdf` | `71cb1e2a7e1b41bf00d7e88c87da787ca0c0966e` | g01-pdf:review-2 | accept-with-minor | R2-01 to R2-03 (minor) | [G01-PDF.md](G01-PDF.md) | `01fc7ac18fede8dcd449717a683fb25417b073f9` |
| 5 | G0.3 Intake | `m0-g03-intake` | `2881de6ffc29cf17c59a6afce3eefb3d6a9e290a` | g03-intake:review-2 | accept-with-minor | R2-01 to R2-06 (minor) | [G03-Intake.md](G03-Intake.md) | `9798110cfe2830261cffea9edce3189b70a3220b` |
| 6 | G0.2 Transfer | `m0-g02-transfer` | `5ef3f844b5707f0a0c399bd65967d4bc25238e35` | g02-transfer:review-3 | accept-with-minor | R3-01 to R3-06 (minor) | [G02-Transfer.md](G02-Transfer.md) | `67eaf953a331d71f9a45bae65bdd06969ca21782` |
| 7 | G0.5 AI | `m0-g05-ai` | `0e4fbf90da3dcc48f45d6f467e2a2f4b063c9a4f` | g05-ai:review-6 | accept-with-minor | R6-01 to R6-04 (minor) | [G05-AI.md](G05-AI.md) | `1d32f4eeb15adf3c68482b987a62ff1a34bcc88a` |
| later | G0.4 Audio | `m0-g04-audio` | (in review) | - | - | - | `G04-Audio.md` (not on this branch) | merged later by another agent |

Each branch head equalled the final commit its last review examined, so no unreviewed commit was merged. The open findings are minor and stay with their gates; they are listed in each review and are not fixed by this integration.

The review findings stay open except one: g01-epub R3-02 ("committed generated EPUB fixtures are missing from `Fixtures/LICENSES.md`, which says generated fixtures are never committed") is resolved by the `Fixtures/LICENSES.md` update below.

## 3. Shared files

Gate implementers could not edit shared files, so they listed requests. Each was checked against the branch's final state (several were written before later fix rounds changed the files) and against the files on disk. Outcomes: **applied**, **already-done**, **declined** (with reason) or **deferred** (with reason and owner).

| # | Source | Request | Outcome | Note |
| --- | --- | --- | --- | --- |
| 1 | g06-design | `Docs/ADRs/README.md`: link the ADR-0013 row | applied | Every ADR that exists on this branch is now linked, with its status. |
| 2 | g06-design | `Fixtures/LICENSES.md`: generated contract fixtures (`Contracts/design/marginalia.v1.json`, `design-tokens.v1` valid and invalid) | applied | Corrected to the final branch: 2 valid and **12** invalid fixtures (the request said 10), about 64 KB each (it said 49 or 58 KB). |
| 3 | g06-design | Plan 4.4.3 (Literata scaling wording) and 4.4.2 (printed dark tints) | deferred | Product-owner decision; the plan is not edited by integration. Evidence: `G06-Design.md` (UIFontMetrics row failed; approach changed) and ADR-0013 Section 2. |
| 4 | g06-design | `Fixtures/LICENSES.md`: snapshot reference PNGs | applied | Measured on this branch: 527 files, 37,703,582 bytes, largest 368,357 (supersedes the request's earlier 374-file figure). |
| 5 | g06-design | List the test-only transitive packages of swift-snapshot-testing | applied | In ADR-0014 rather than `LICENSES.md` (which lists fixtures), with licenses read from the pinned checkouts. |
| 6 | g05-recovery | `Fixtures/LICENSES.md`: `library-v1.sqlite` row with SHA-256 computed at integration | applied | SHA-256 `eae90f68...e592`; the row says a rerun of the generator gives a different file (random entity UUIDs). The backup-manifest fixtures are now 2 valid and 20 invalid (the request said 16 invalid). |
| 7 | g01-epub | `Fixtures/LICENSES.md`: "Generated (G0.1 EPUB)" section | applied | The branch commits **17** EPUBs (the request listed 14; `g01-csp-bypass`, `g01-form-navigation` and `g01-nesting-bypass` came in later rounds). Per-file digests are in the committed `MANIFEST.tsv`, which `--check` verifies. |
| 8 | g01-epub | ADR-0014: take the ADR-0004 Section 1 dependency table | applied | ADR-0014 created (owner "M0 integration" in the ADR index); every license was re-read from the pinned checkout. |
| 9 | g01-epub | ADR-0002: no change needed for Readium | already-done | Readium 3.11.0 was already pinned in ADR-0002. |
| 10 | g01-pdf | `Fixtures/LICENSES.md`: "Generated (G0.1 PDF spike)" section with nine SHA-256 values | applied | All nine values match the committed files. The branch also commits a tenth file, `actions-nonurl.pdf` (same generator), added with its SHA-256. |
| 11 | g01-pdf | Cache list: `generated/g01-pdf/large-1000.pdf` | applied | SHA-256 pinned in the generator; size from `evidence/G01-PDF/large-pdf-timing.txt`. |
| 12 | g01-pdf | Contracts: base the PDF kind of the `anchor` schema on ADR-0005, fixtures from `anchor-samples.json` | deferred | The `anchor` and `capture-envelope` schemas belong to contract consolidation after G0.4's locator evidence is merged; recorded as that row's inputs in `Contracts/README.md`. |
| 13 | g03-intake | Cache list: `generated/g03-intake/large.sylviapack` and `work/part-01.caf` | applied | SHA-256 and size pinned in the generator. |
| 14 | g03-intake | Note that the import-handoff and sylviapack contract fixtures are hand-written | applied | Counts from the branch: 3 valid and 17 invalid; 4 valid and 22 invalid. |
| 15 | g02-transfer | `Fixtures/LICENSES.md`: generated committed fixtures, certificates, and the 5 GiB cache file | applied | 60 contract fixture files, 14 semantic-invalid manifests, 3 certificates with pins (private keys discarded by the generator; none committed). |
| 16 | g02-transfer | ADR-0002 table or ADR-0014: transitive swift-nio packages and BoringSSL | applied | ADR-0014; ADR-0002 now points to it. The licenses of swift-atomics, swift-collections and swift-system are Apache-2.0 with the Runtime Library Exception (read from the checkouts). |
| 17 | g02-transfer | Cache list: `sim-*.bin` from `generate-g02-transfer-sim-files.sh` | applied | |
| 18 | g05-ai | ADR-0002: GRDB "Needed for" adds FTS5 retrieval in the G0.5 AI spike | applied | |
| 19 | g05-ai | Plan 4.4.6: fixed phrases for cancelled, stopped, failed, refusal, content filtered, output limit (finding F5) | deferred | Product-owner decision (vocabulary change control, plan 4.4.9). |
| 20 | g05-ai | Plan 13.1 or 13.3: whole-book inclusion unavailable when "Do not include later passages" is on (finding F4) | deferred | Product-owner decision. |
| 21 | g05-ai | `Fixtures/LICENSES.md`: note that context-pack fixtures and the evaluation seed quote the Standard Ebooks *Walden* and *Middlemarch* | applied | Checked: the fixtures' titles are only *Walden* and *Middlemarch*. Counts from the branch: context-pack 8 valid and 21 invalid, provider-config 5 valid and 12 invalid (the request said 5, 13, 5 and 11). |
| 22 | integration | `CLAUDE.md`: current milestone and new conventions | applied | Milestone status; ADR-0014 and one version per package; `.build/scratch/` for temporary files; committed generated fixtures; binary files and LFS; quiet test audio; timings under load. These are repository instructions for agents, so the product owner should review them before `m0-integrate` is merged. |
| 23 | integration | Quiet test audio in the merged gates | already-done | `git grep` for AVPlayer, AVQueuePlayer, AVAudioPlayer, AVAudioEngine, AVAudioPlayerNode, AudioServicesPlay, NSSound and afplay in `Spikes`, `Packages`, `Apps` and `Scripts` finds nothing: none of the seven merged gates plays audio. G0.4 makes its own tests quiet in its current round. |
| 24 | integration | `Docs/Stage0/README.md`, `Contracts/README.md` | applied | Gate reports and checklists linked, honest-status rules kept, G0.4 marked as later; contract owners after M0. |

## 4. Binary files and Git LFS

**Decision: plain git for now; LFS deferred, not rejected.** Recorded with the measurements, the reason, the trigger and the exact steps in ADR-0002 ("Binary test baselines and evidence images"). In short: all eight gate branches (G0.4 read with git at `943d5e778de2b58f47343f0e146f9e3ed7baa70e`, still in review) add 786 binary files, 65,265,478 bytes, of which 762 PNG (64,437,948 bytes, largest 450,701): 527 snapshot references and 235 evidence images. git-lfs 3.7.1 is installed on the build Mac but no LFS filter is configured at any level, so adopting LFS now would leave every worktree on this Mac, including the clean verification run that follows integration, with pointer files instead of PNGs until the owner runs `git lfs install`. Measurements: `evidence/M0-Integration/binary-files.tsv` and `binary-files-summary.txt` (command `evidence/M0-Integration/commands/measure.sh`). No `.gitattributes` was added and no remote operation was run.

## 5. Checks run at integration

Fast checks only; the complete CI from a clean tree is run on the final commit by a separate verification agent. Host: macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.0 (27A266a), XcodeGen 2.46.0. No simulator was created or used.

| Check | Command | Result | Evidence |
| --- | --- | --- | --- |
| Contracts | `Scripts/ci.sh contracts` | pass: 15 schemas, 188 fixtures, 1 OpenAPI document, 1 instance | `evidence/M0-Integration/contracts.log` |
| Package locks | `evidence/M0-Integration/commands/lockcheck.sh`: `sylvia_generate` and `xcodebuild -resolvePackageDependencies -disableAutomaticPackageResolution` for the 7 Xcode projects; `swift package resolve --force-resolved-versions` for the 10 Swift packages | pass: all 17 resolve and no committed `Package.resolved` changes. Two projects have no committed lock (below). `ZipEval/IdentityProbe` is not resolved: it is G0.3's probe that two packages named ZIPFoundation cannot share a graph | `evidence/M0-Integration/package-locks.log` |
| Licenses | `evidence/M0-Integration/commands/license_inventory.py` over the checkouts the lock check left | 23 of 23 pinned packages found at their pinned revision; licenses in ADR-0014 | `evidence/M0-Integration/license-inventory.log` |
| Squash fidelity | compare every path each branch changes with the integration tree (blob IDs) | 1,822 of 1,822 identical | section 2 |

## 6. Open items from integration

- **Owner:** run `git lfs install` on each Mac that builds Sylvia, then adopt LFS per ADR-0002 before the first snapshot re-record or the first push of `m0`.
- **Owner:** decide the four deferred plan changes (rows 3, 19, 20) and review the `CLAUDE.md` changes (row 22).
- **G0.2:** `Spikes/G02-Transfer/MacIdentityProbe` has no committed lock, and swift-atomics, swift-collections and swift-system reach it only through swift-nio's version ranges, so a fresh resolution after a new release could pick newer versions (ADR-0014 open item). `Spikes/G02-Transfer/iOS` has no lock either, but its only remote package, swift-asn1, is fixed by an `exact:` requirement.
- **G0.4 merge (another agent):** link ADR-0006 and ADR-0007 in the ADR index, link `G04-Audio.md` and its checklist in `Docs/Stage0/README.md`, add G0.4 fixtures to `Fixtures/LICENSES.md` and any packages to ADR-0014, record its row in section 2, and confirm its evidence images fall under the LFS evidence pattern when LFS is adopted.
- **M0 integration (not done here):** ADR-0015 threat model; contract consolidation (`capture-envelope`, `anchor`); the M0 gate summary `M0-gate.md`.
