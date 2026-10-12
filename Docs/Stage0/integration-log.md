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
