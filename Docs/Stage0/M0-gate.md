# M0 gate summary

- **For:** the product owner, ahead of the M0 exit review (plan Sections 21.1, 21.2, 22.4 and 23.3).
- **Version:** first written on 15 October 2026 on top of `74be11e` (committed as `d8e7d39`). Refreshed on 19 October 2026 on top of `e3e8886`, the branch after the Git LFS adoption: the refresh adds the merge of the M0 work into `main`, the Git LFS adoption and its verification, plan draft 0.6 and the build Mac's Xcode 27.1, and checks every status again.
- **Branch:** `m0-integrate`. Since the second complete CI run (`efc9479`, Section 2.10), code, scripts, contracts, fixtures and the workflow changed only through the Git LFS adoption: `.gitattributes`, `Scripts/ci.d/00-git-lfs.sh`, `Scripts/ci.sh`, `Scripts/setup-repo.sh`, `.github/workflows/ci.yml`, and the 527 snapshot references, which are now LFS pointers to exactly the bytes that run compared (`evidence/M0-Integration/gate-refresh-checks.log`, part 1).
- **Written by:** an agent, from the eight gate reports, the sixteen ADRs, `M0-contracts.md`, `M0-device-runbook.md`, `M0-plan-amendments.md`, `integration-log.md` and the CI and Git LFS logs under `evidence/M0-Integration/`. Agent-reviewed inputs; human sign-off pending on everything below.
- **Evidence paths** are relative to `Docs/Stage0/` unless they start with a repository folder. The refresh's own checks are in `evidence/M0-Integration/gate-refresh-checks.log`, written by `evidence/M0-Integration/commands/gate-refresh-checks.sh` (which runs `evidence/M0-Integration/commands/gate-refresh-check.py`); the first version's checks stay in `evidence/M0-Integration/gate-summary-checks.log`. Host only: no simulator was created or used for this summary, and nothing played audio.

## 1. In short

**What M0 set out to prove.** Plan 21.1 asks Stage 0 to settle the risky platform assumptions before any feature is built: EPUB and PDF capture (G0.1), secure transfer from the Mac in the background (G0.2), large share-extension and cable intake (G0.3), audiobook playback and excerpts (G0.4), AI providers and a restore drill (G0.5), and the design tokens on devices (G0.6). Plan 21.2 adds the threat model, an interaction prototype, the dependency lock, the ADRs and the `SylviaDesign` v0.1 package.

**Did each gate meet its criteria?** Not yet, for any gate. Every gate's automated checks ran on the build Mac and the iOS 26.5 simulator, and every gate's CI drop-in passed from a clean tree on 14 October 2026, but every gate still has physical-device and human steps that have not been run, and nothing has been run on a phone. Four gates have rows that **failed** on the simulator:

- **G0.2:** a Tailscale address and a MagicDNS name are refused by App Transport Security when the Mac's pinned self-signed identity is used and no ATS exception is declared.
- **G0.4:** the 1.5 s start/resume budget is missed by long audio files that stay on precise timing (a cold resume deep into a VBR MP3; native FLAC and MP3 without a header beyond a length limit; Ogg Opus at about 10 hours at the edge).
- **G0.6:** type scaling through `UIFontMetrics`, as plan 4.4.3 specifies, does not track the system text sizes (up to 6.3 pt off at AX5).
- **G0.1 PDF:** highlights on text drawn with a rotated text matrix (vertical, upside-down or slanted lines on an upright page) are drawn wrongly; the anchors themselves restore exactly. This row (`G01-PDF.md` row 10c) came in after the plan amendments were written, so the plan and `M0-plan-amendments.md` still say "three gates", and no amendment changes the approach for it yet (Section 6.3).

Every other criterion is passed on the host or simulator, partial, or pending a device or a person. Section 2 lists each one.

**What happened since the first version of this summary (15 October 2026).**

- **The M0 work is on `main`, and the M0 gate is still pending.** On 15 October 2026 you merged `m0-integrate` (at `177ed9a`) into `main` through pull request #4 (merge commit `504fac2`), before the M0 gate was approved. The merge changes no status in this summary. `m0-integrate` was then fast-forwarded to `504fac2`, the later M0 work (the Git LFS adoption and this refresh) continues on it, and it goes to `main` by a follow-up pull request. The plan, the Companion Vision addendum, the README and the device-run setup lines now say this (integration log section 10).
- **Git LFS is adopted and verified** (your decision of 13 October 2026; Section 5.3). Its verification's verdict is accept-with-minor with no open serious finding.
- **Plan draft 0.6** records your direction of 15 October 2026: Gloss-informed M3 and M5 interactions and a later web reader. It is an approved product direction and approves none of the pending draft 0.5 amendments (Section 3).
- **The build Mac now has Xcode 27.1 (27A9275)**, not the pinned 27.0 (27A266a), so `12-dependency-lock` fails its toolchain check on this Mac whatever the commit; every other check it makes passes (Section 2.10). This bears on PO-35 (Section 4).
- **Records corrected:** G0.4's shared-file request outcomes, the Stage 0 README's list of failed rows and the record of G0.5 AI's review round 7 (Section 6.3). No gate report status needed a change.

**What changed in the plan.** Draft 0.5 of the plan proposes 53 amendments (`[M0-A01]` to `[M0-A53]`, `M0-plan-amendments.md`), all pending your approval. The main ones: Sylvia's own EPUB safety adapter around Readium (A02); a scoped ATS exception for the Tailscale route, new decision D16, or no Tailscale route in v1 (A13); a per-file timing mode and an import remux for long audio files (A22); Opus in WebM excluded and other extra formats admitted only after the device run (A23); quick capture not advertised until its device steps pass (A26); data-protection class C everywhere with a full-sync durability setting, new decision D17 (A27, A28); type scaling by the system styles' sizes with bounded Dynamic Type exceptions (A40); and each milestone, M1 included, starting only after the device steps of the gates it builds on have passed (A46). No budget was relaxed. Draft 0.6 then added your 15 October direction on top (Section 3); it changes no M0 criterion, gate result or pending amendment.

**What you need to do next.**

1. **Decide.** The plan amendments of draft 0.5, the new decisions D16 and D17, the changed decisions in Section 3, and the questions in Section 4 (36 from the amendments, plus the ones the merged reports and ADR-0014 added). D-1 and D-2 first: which phone is the "oldest supported iPhone", and whether the iPad steps belong to M0. PO-35 early too: the build Mac no longer has the Xcode build the pin names.
2. **Prepare the build Mac and devices.** The team account (A4KBDX665Z) in Xcode on the build Mac and its Program License Agreement accepted; the Xcode build the pin names installed (Section 5.2); the oldest supported iPhone and an iPad (ADR-0001).
3. **Book the security reviewer and the designer early, then run the device sessions** in `M0-device-runbook.md` (Sessions 0-9, in the order of its Section 3), and the reviews of Session 10.
4. **Have ADR-0014's owner close R4-01 and R4-02** (two routes around the dependency guard) before any product target is added.
5. **When you want the rest on `main`:** review the `CLAUDE.md` changes (integration log rows 22, 30 and 83, and the Setup section the Git LFS adoption added, section 9), push `m0-integrate` yourself (its first push uploads 719 LFS objects, 65.1 MB, to your GitHub LFS storage) and open the follow-up pull request.

**Recommendation** (Section 7): M0 cannot be approved yet. The exit gate needs approved evidence and ADRs and signed decisions, and none of the gates' device or human steps has run.

## 2. Criteria and deliverables

One row per sentence of plan 21.1 (split where a gate report gives a sentence several rows), per M0 deliverable of plan 21.2, and per ADR that plan 22.4 requires. **Status** is copied from the gate report row in the last column (for M0 deliverables and ADRs, from the record named there). Status values: passed-host, passed-simulator, failed, partial, pending-device, pending-human. No row is passed on a device: no device step has run.

**Checked on 19 October 2026.** `evidence/M0-Integration/commands/gate-refresh-check.py` compares the status of every row that cites a gate report with the status cell of each report row it cites, and the status of every ADR and deliverable row with the ADR's status line or the CI log it cites; every one agrees (`evidence/M0-Integration/gate-refresh-checks.log`, part 4), so no gate report status was changed. The rows it cannot check mechanically (67-70 and 81: judgements on the plan's text and on the other rows) say what they rest on. Plan draft 0.6 changed no criterion of plan 21.1, the M0 row of 21.2 or the artifacts of 22.4, so the rows are those of the first version, with their numbers.

### 2.1 G0.1 EPUB/PDF capture

| # | Criterion (plan 21.1) | Status | Evidence | Gate report row |
| --- | --- | --- | --- | --- |
| 1 | G0.1: demonstrate Readium selection (exact text, context, locator) | passed-simulator | `evidence/G01-EPUB/selection-samples.json`, `evidence/G01-EPUB/selection-after-jump.json` | `G01-EPUB.md` G1 |
| 2 | G0.1: selection by a finger and the edit menu | pending-device | `device-checklists/G01-EPUB.md` steps 1-4 | `G01-EPUB.md` G2 |
| 3 | G0.1: Readium decorations render the `ochre` fill-plus-underline highlight | passed-simulator | `evidence/G01-EPUB/highlight-decoration.json`, `evidence/G01-EPUB/highlight-paper.png`, `evidence/G01-EPUB/highlight-night.png` | `G01-EPUB.md` G3 |
| 4 | G0.1: the highlight stays readable without color (plan 4.4.8) | pending-human | `device-checklists/G01-EPUB.md` step 10 | `G01-EPUB.md` G4 |
| 5 | G0.1: locator restoration (same asset, through reflow, rotation and relaunch) | passed-simulator | `evidence/G01-EPUB/anchor-stability.json`, `evidence/G01-EPUB/ui-tests.log` | `G01-EPUB.md` G5 |
| 6 | G0.1: footnotes without losing the reading position | passed-simulator | `evidence/G01-EPUB/footnote-note.json`, `evidence/G01-EPUB/footnote-return.json` | `G01-EPUB.md` G6 |
| 7 | G0.1: extraction mapping | passed-simulator | `evidence/G01-EPUB/extraction-search.json`, `evidence/G01-EPUB/extraction-nonbmp.json` | `G01-EPUB.md` G7 |
| 8 | G0.1: prove PDF multiline and rotation anchors | passed-simulator | `evidence/G01-PDF/anchor-capture-restore.txt`, `evidence/G01-PDF/anchor-samples.json` | `G01-PDF.md` row 1 |
| 9 | G0.1: PDF selections made by a person's finger | pending-device | `device-checklists/G01-PDF.md` steps 1-3 | `G01-PDF.md` row 2 |
| 10 | G0.1 (beyond the gate's rotated pages): PDF highlight overlay on text drawn with rotated text matrices | failed | `evidence/G01-PDF/text-layout-rotated.txt`, `evidence/G01-PDF/overlay-rotated-text.png` | `G01-PDF.md` row 10c |
| 11 | G0.1: deliver a compatibility matrix | passed-simulator | `evidence/G01-EPUB/compatibility-matrix.json` | `G01-EPUB.md` G8 |
| 12 | G0.1: pinned package recommendation | pending-human | `Docs/ADRs/0004-epub-reader-adapter.md` | `G01-EPUB.md` G9 |
| 13 | G0.1: Literata as the default reading face with the user's size and spacing | passed-simulator | `evidence/G01-EPUB/typography-literata.json`, `evidence/G01-EPUB/typography-size-spacing.json` | `G01-EPUB.md` G10 |

### 2.2 G0.2 Transfer security and background

| # | Criterion (plan 21.1) | Status | Evidence | Gate report row |
| --- | --- | --- | --- | --- |
| 14 | G0.2: user-mediated trust bootstrap from iOS (pinned pairing, Mac approval, token in the Keychain) | passed-simulator | `evidence/G02-Transfer/simulator-pairing-run.log` | `G02-Transfer.md` part 1, "User-mediated trust bootstrap from iOS" |
| 15 | G0.2: user-mediated trust bootstrap on a physical iPhone over Wi-Fi | pending-device | `device-checklists/G02-Transfer.md` steps 2, 5 | `G02-Transfer.md` part 1, "... on a physical iPhone over Wi-Fi" |
| 16 | G0.2: certificate validation and pinning (forged pin refused before any request) | passed-simulator | `evidence/G02-Transfer/simulator-pairing-run.log`, `evidence/G02-Transfer/ci/host-sourceservice.log` | `G02-Transfer.md` part 1, "Certificate pinning on iOS" |
| 17 | G0.2: authorized ranged background downloads | partial | `evidence/G02-Transfer/simulator/background-full-transfer.log`; device steps 2, 9 pending | `G02-Transfer.md` part 1, "Authorized ranged downloads with verified parts" |
| 18 | G0.2: recovery after suspension and force-quit | partial | `evidence/G02-Transfer/faults/interrupted-engine-resume.log`, `evidence/G02-Transfer/simulator/relaunch-keep-alive.log`; device steps 13-15 pending | `G02-Transfer.md` part 1, "Recovery after suspension or force-quit" |
| 19 | G0.2: Mac source mutation never yields a mixed-version file | passed-host | `evidence/G02-Transfer/faults/mutation-while-streaming.log` | `G02-Transfer.md` part 1, "Mac source mutation ..." |
| 20 | G0.2: manual-address connectivity (loopback, LAN, Tailscale address and MagicDNS name, two processes on one Mac) | passed-host | `evidence/G02-Transfer/cli-run-lan.log`, `evidence/G02-Transfer/cli-run-tailscale-ip.log` | `G02-Transfer.md` part 1, "Manual-address connectivity ..." |
| 21 | G0.2: the pinned identity with a background session on iOS at local address forms (no ATS key) | passed-simulator | `evidence/G02-Transfer/simulator/background-address-forms.log`, `evidence/G02-Transfer/ats/ats-probe-none.log` | `G02-Transfer.md` part 2, "Plan 15.2 Stage 0 gate, local address forms" |
| 22 | G0.2: a Tailscale address and a MagicDNS name on iOS without an ATS exception | failed | `evidence/G02-Transfer/ats/ats-probe-none.log`, `evidence/G02-Transfer/simulator/background-address-forms.log` | `G02-Transfer.md` part 2, "Plan 15.2 Stage 0 gate, Tailscale address forms", and T43 (Tailscale) |
| 23 | G0.2: manual-address and Tailscale connectivity between a phone and the Mac | pending-device | `device-checklists/G02-Transfer.md` steps 6, 7 | `G02-Transfer.md` part 1, "Manual-address and Tailscale connectivity between a phone and the Mac" |
| 24 | G0.2: the security reviewer approves the pairing protocol | pending-human | `device-checklists/G02-Transfer.md` step 12; `Docs/ADRs/0008-pairing-and-transport-security.md` | `G02-Transfer.md` part 1, "Security reviewer approves the pairing protocol" |
| 25 | G0.2: no "temporary trust-all" code becomes the production baseline | passed-host | `evidence/G02-Transfer/ci/trust-guards.log`, `evidence/G02-Transfer/tls-negotiation.txt`; the repository-wide audit `13-hard-rules` passed in `evidence/M0-Integration/ci-full-clean-run-assembled.log` and again for this refresh (`evidence/M0-Integration/gate-refresh-checks.log`, part 6) | `G02-Transfer.md` part 1, "No trust-all path, no ATS exception in the harness, TLS 1.2 minimum" |

### 2.3 G0.3 Intake and cable

| # | Criterion (plan 21.1) | Status | Evidence | Gate report row |
| --- | --- | --- | --- | --- |
| 26 | G0.3: a large share-extension handoff without false acknowledgement (simulator, real share sheet and extension) | passed-simulator | `evidence/G03-Intake/sim-app-tests.log`, `evidence/G03-Intake/host-handoff-kill.log` | `G03-Intake.md` G1 |
| 27 | G0.3: the same on a device, from real providers, under the real extension memory limit | pending-device | `device-checklists/G03-Intake.md` steps 6-18 | `G03-Intake.md` G2 |
| 28 | G0.3: Finder `.sylviapack` transfer above 4 GiB, including a partial and a cancelled copy | pending-device | `device-checklists/G03-Intake.md` steps 19-23 | `G03-Intake.md` G6 |
| 29 | G0.3: ZIP64 validation and bounded-memory extraction above 4 GiB (host) | passed-host | `evidence/G03-Intake/host-large-pack.log` | `G03-Intake.md` G3 |
| 30 | G0.3: the same on iOS | passed-simulator | `evidence/G03-Intake/sim-app-tests.log` | `G03-Intake.md` G4 |
| 31 | G0.3: a partial bundle never passes validation | passed-host | `evidence/G03-Intake/host-large-pack.log`, `evidence/G03-Intake/sim-open-in.log` | `G03-Intake.md` G5 |
| 32 | G0.3: private data isolation (Documents is the inbound drop area only) | passed-simulator | `evidence/G03-Intake/sim-app-tests.log` | `G03-Intake.md` G7 |
| 33 | G0.3: private data not visible in Finder's file-sharing pane; data-protection class on a device | pending-device | `device-checklists/G03-Intake.md` steps 19, 24 | `G03-Intake.md` G8 |
| 34 | G0.3: the cable test T42 (valid bundle above 4 GiB imports, partial copy rejected, private database never Finder-visible) | partial | `evidence/G03-Intake/host-intakekit-tests.log`; the Finder copy and view pending-device | `G03-Intake.md` T42 |
| 35 | G0.3: document the exact fallback route when a share provider cannot supply a durable file | passed-host | `G03-Intake.md` "Fallback route"; `evidence/G03-Intake/host-intakekit-tests.log`, `evidence/G03-Intake/sim-intakekit-tests.log` | `G03-Intake.md` G9 |
| 36 | G0.3: the fallback with real third-party providers | pending-device | `device-checklists/G03-Intake.md` steps 8, 9, 10, 12, 18 | `G03-Intake.md` G10 |

### 2.4 G0.4 Audio

| # | Criterion (plan 21.1) | Status | Evidence | Gate report row |
| --- | --- | --- | --- | --- |
| 37 | G0.4: test the proposed codec/container matrix (16 of 17 pass; Opus in WebM does not open) | passed-simulator | `evidence/G04-Audio/results/codec-matrix.tsv`, `evidence/G04-Audio/results/codec-matrix-detail.tsv` | `G04-Audio.md` row 1 |
| 38 | G0.4: the release codec list (the matrix on a device) | pending-device | `device-checklists/G04-Audio.md` step 1 | `G04-Audio.md` row 2 |
| 39 | G0.4: long playback (10-hour files, the real M4B, two hours of media at 3x on the real engine) | passed-simulator | `evidence/G04-Audio/results/long-long-aac-10h.m4b.txt`, `evidence/G04-Audio/results/librivox-m4b.txt`, `evidence/G04-Audio/results/soak.txt` | `G04-Audio.md` rows 3 and 11 |
| 40 | G0.4: two-hour locked playback (T18) | pending-device | `device-checklists/G04-Audio.md` step 3 | `G04-Audio.md` row 12 |
| 41 | G0.4 (plan 19.2): start/resume within 1.5 s for MPEG-4 formats, Opus in CAF, WAV and, with the per-file timing mode, constant-bit-rate MP3, at every depth to 10 h | passed-simulator | `evidence/G04-Audio/results/budgets.txt`, `evidence/G04-Audio/results/long-formats-cold-resume.tsv` | `G04-Audio.md` row 21 (its passed part) |
| 42 | G0.4 (plan 19.2): start/resume within 1.5 s for files that stay on precise timing (VBR MP3 deeper than about 1-1.8 h; native FLAC longer than about 25-31 min; MP3 without a header longer than about 1.4-1.8 h; Ogg Opus at about 10 h at the edge) | failed | `evidence/G04-Audio/results/budgets.txt`, `evidence/G04-Audio/results/long-formats-cold-resume.tsv`, `evidence/G04-Audio/results/long-formats-open.tsv` | `G04-Audio.md` rows 21 and 33 (their failed parts) |
| 43 | G0.4: chapters (with the container limits stated) | passed-simulator | `evidence/G04-Audio/results/codec-matrix-detail.tsv`, `evidence/G04-Audio/results/container-probes.txt` | `G04-Audio.md` row 4 |
| 44 | G0.4: cross-file excerpts | passed-simulator | `evidence/G04-Audio/results/excerpt-timing-cross-file.tsv` | `G04-Audio.md` row 5 |
| 45 | G0.4: export timing against the 500 ms budget, per format | passed-simulator | `evidence/G04-Audio/results/excerpt-timing-single-file.tsv` | `G04-Audio.md` row 6 |
| 46 | G0.4: main-position-preserving preview | passed-simulator | `evidence/G04-Audio/results/preview.txt`, `evidence/G04-Audio/results/preview-end-formats.tsv` | `G04-Audio.md` row 7 |
| 47 | G0.4: separately evaluate lock-screen quick capture | partial | `Docs/ADRs/0007-quick-capture-evaluation.md`; `evidence/G04-Audio/results/quick-capture-simulator-signed.txt` | `G04-Audio.md` row 8 |
| 48 | G0.4: quick capture through the system on the simulator, unlocked (control from Control Center, App Shortcut) | passed-simulator | `evidence/G04-Audio/results/quick-capture-simulator-signed.txt`, `evidence/G04-Audio/results/quick-capture-simulator-adhoc.txt` | `G04-Audio.md` row 18 |
| 49 | G0.4: the locked quick-capture surface on a device | pending-device | `device-checklists/G04-Audio.md` steps 8-13 | `G04-Audio.md` row 19 |
| 50 | G0.4: record which part of the aspirational workflow can ship | partial | `G04-Audio.md` "Findings" and decisions PO-1 to PO-6 | `G04-Audio.md` row 9 |

### 2.5 G0.5 AI and recovery

| # | Criterion (plan 21.1) | Status | Evidence | Gate report row |
| --- | --- | --- | --- | --- |
| 51 | G0.5: demonstrate each provider dialect (OpenAI, Anthropic, generic) | partial | `evidence/G05-AI/host-test.log`, `evidence/G05-AI/simulator-package-test.log`; live runs pending-human (row P3) | `G05-AI.md` G1 |
| 52 | G0.5: plus a local endpoint | partial | `evidence/G05-AI/live-tests-dry-run-loopback.log`; a real local server pending-human (row P1) | `G05-AI.md` G2 |
| 53 | G0.5: correct context snapshot and citation resolution | passed-host | `evidence/G05-AI/host-test.log` | `G05-AI.md` G3 |
| 54 | G0.5: a transcription endpoint | partial | `evidence/G05-AI/host-test.log`; a real endpoint pending-human (row P4) | `G05-AI.md` G4 |
| 55 | G0.5: a restore drill after source deletion | passed-simulator | `evidence/G05-Recovery/logs/restore-drill.log`, `evidence/G05-Recovery/logs/simulator-tests.log` | `G05-Recovery.md` row 1 |
| 56 | G0.5: the recovery suite, restore drill included, on a physical device | pending-device | `device-checklists/G05-Recovery.md` step 1 | `G05-Recovery.md` row 22 |
| 57 | G0.5: confirm exact dependency and toolchain versions (persistence) | passed-host | `evidence/G05-Recovery/logs/toolchain.log`, `evidence/G05-Recovery/logs/env-report.log` (Xcode 27.0, 27A266a, at the time; the build Mac now has 27.1, Section 2.10) | `G05-Recovery.md` row 2 |
| 58 | G0.5: dependency and toolchain versions, license and security posture (AI part) | partial | `Spikes/G05-AI/Package.resolved`; security review pending-human (row P6) | `G05-AI.md` G6 |
| 59 | G0.5: security review of the protection class and the unencrypted backup format | pending-human | `Docs/ADRs/0012-retention-backup-restore.md` | `G05-Recovery.md` row 23 |

### 2.6 G0.6 Design tokens on devices

| # | Criterion (plan 21.1) | Status | Evidence | Gate report row |
| --- | --- | --- | --- | --- |
| 60 | G0.6: build the `SylviaDesign` package at v0.1 from Section 4.4 | passed-simulator | `evidence/G06-Design/ci-clean-run.log`, `evidence/G06-Design/test-simulator.log` | `G06-Design.md` gate table, "SylviaDesign package at v0.1" |
| 61 | G0.6: verify every token pair's contrast in the asset catalog in light and dark | passed-simulator | `evidence/G06-Design/contrast-catalog-simulator.md`, `evidence/G06-Design/contrast-components-catalog-simulator.md` | `G06-Design.md` gate table, "every token pair's contrast" |
| 62 | G0.6: type roles under Dynamic Type at the default and largest accessibility sizes on the oldest supported iPhone | pending-device | `evidence/G06-Design/type-roles-simulator.md` (simulator only); `device-checklists/G06-Design.md` steps 4, 15, 26 | `G06-Design.md` gate table, "type roles under Dynamic Type" |
| 63 | G0.6: type scaling through `UIFontMetrics` as plan 4.4.3 specifies | failed | `evidence/G06-Design/uifontmetrics-vs-system-simulator.md` | `G06-Design.md` part 1, "Scaling through UIFontMetrics as Section 4.4.3 specifies" |
| 64 | G0.6: view the component set on a device with Color Filters grayscale and with Increase Contrast on | pending-device | `device-checklists/G06-Design.md` steps 13, 14, 23, 24, 27 | `G06-Design.md` gate table, "component set viewed on a device" |
| 65 | G0.6: adjust token values where the device disagrees, and record the final values in an ADR | partial | `Docs/ADRs/0013-design-language.md`; no device comparison yet | `G06-Design.md` gate table, "token values adjusted ..." |

### 2.7 Exit gate (plan 21.1)

| # | Criterion (plan 21.1) | Status | Evidence | Source |
| --- | --- | --- | --- | --- |
| 66 | Exit gate: evidence and ADRs approved | pending-human | `Docs/ADRs/README.md`: ADR-0001 is accepted for the platform floor only and ADR-0002 for Stage 0 (its amendments, the Git LFS one included, pending); ADR-0003 to ADR-0016 are Proposed | ADR index |
| 67 | Exit gate: review decisions in Section 23 signed | pending-human | Section 3 below; `M0-device-runbook.md` Section 6. Plan draft 0.6 (an approved direction) signed none of them | plan 23.1, 23.3 |
| 68 | Exit gate: no unresolved P0 feasibility assumption hidden behind a feature flag | pending-human | No product code exists yet; every unresolved assumption is listed openly as a pending step (`M0-device-runbook.md` Section 7) or a proposed narrowing (`M0-plan-amendments.md` Section 1). The judgement is the exit review's | plan 21.1 |
| 69 | Exit gate: a failed spike changes the documented scope or approach before downstream work | partial | Approach changes proposed for three of the four gates with failed rows (A13 for G0.2, A22 for G0.4, A40 for G0.6), all pending your approval; none yet for G0.1 PDF row 10c (Section 6.3) | `M0-plan-amendments.md` "How to read this" |

### 2.8 M0 deliverables (plan 21.2)

| # | Deliverable (plan 21.2) | Status | Evidence | Source |
| --- | --- | --- | --- | --- |
| 70 | G0.1-G0.6 | partial | Rows 1-65: host and simulator evidence for every gate; device and human steps pending everywhere; failed rows in G0.1 PDF, G0.2, G0.4 and G0.6 | the eight gate reports |
| 71 | Threat model | pending-human | `Docs/ADRs/0015-threat-model.md` (Proposed; agent-reviewed, human security sign-off pending); TM-F1 and TM-F2 fixed at M0 assembly; `13-hard-rules` passing (`evidence/M0-Integration/ci-full-clean-run-assembled.log`, `evidence/M0-Integration/ci-documents-final.log`, `evidence/M0-Integration/gate-refresh-checks.log`); gap list in ADR-0015 section 7.1 | integration log row 60; ADR-0015 status |
| 72 | Interaction prototype: built and exercised on simulators (iPhone 17, iPhone SE (3rd generation), iPad) | passed-simulator | `evidence/G06-Design/tests-ui-iphone-simulator.log`, `evidence/G06-Design/tests-ui-iphone-se-simulator.log`, `evidence/G06-Design/tests-ui-ipad-simulator.log`. It predates plan draft 0.6 (Section 3): no passage preview kept in view while a note is written, no side-pane discussion on iPad. That is M3 and M5 design input, not an M0 defect | `G06-Design.md` part 3, "CI drop-in `Scripts/ci.d/21-design-catalog.sh`" |
| 73 | Interaction prototype matches the boards where they agree with Section 4.4 | pending-human | `device-checklists/G06-Design.md` step 31 | `G06-Design.md` part 3, "Prototype matches the boards ..." |
| 74 | Device review of the component set and the prototype (oldest iPhone, iPhone 17 Pro, iPad) | pending-device | `device-checklists/G06-Design.md` | `G06-Design.md` part 3, "G0.6 device review ..." |
| 75 | Dependency lock: one version per package, the license inventory and its CI check | passed-host | `12-dependency-lock` passed in `evidence/M0-Integration/ci-full-clean-run-assembled.log` and `evidence/M0-Integration/ci-documents-final.log` (Xcode 27.0); `Docs/Licenses/inventory.json`. With Xcode 27.1 on the build Mac it now fails its toolchain check only, every repository check passing (Section 2.10) | ADR-0014; integration log 7.1 |
| 76 | Dependency lock: the CI guard that keeps marmelroy/Zip 2.1.2 (CVE-2023-39135) out of product code | failed | Final agent review (round 4) verdict "reject": R4-01 and R4-02 open (Section 6.1). No product target exists yet, so neither route is in use | ADR-0014 status; integration log 7.1 |
| 77 | Dependency lock: the license and security decisions that need a person | pending-human | `Docs/ADRs/0014-dependency-lock-and-license-inventory.md` section 7 (nine items) | ADR-0014 section 7 |
| 78 | ADRs | pending-human | Rows 82-92 | ADR index |
| 79 | `SylviaDesign` v0.1: tokens, type roles, marker set, status vocabulary, component shells | passed-simulator | `G06-Design.md` part 1 and part 2 rows; `evidence/G06-Design/ci-clean-run.log`; `20-design` passed in `evidence/M0-Integration/ci-full-clean-run-assembled.log`, and again in clean clones after the Git LFS adoption (`evidence/M0-Integration/lfs/r3-fix/clean-checkout-20-design.log`) | `G06-Design.md` gate table, "SylviaDesign package at v0.1" |
| 80 | `SylviaDesign` v0.1: design review of the components and references | pending-human | `device-checklists/G06-Design.md` steps 21, 31 | `G06-Design.md` part 2, "Design review of the components and references" |
| 81 | M0 exit demonstration: the team approves supported scope, contracts and design tokens | pending-human | `M0-device-runbook.md` Section 6 (Session 10) | plan 21.2 |

### 2.9 Required execution artifacts (plan 22.4)

| # | Artifact (plan 22.4) | Status | Evidence | Source |
| --- | --- | --- | --- | --- |
| 82 | ADR: platform baseline | pending-human | `Docs/ADRs/0001-platform-baseline-and-toolchain.md`: accepted for the platform floor (6 October 2026); the toolchain pin awaits your confirmation that Xcode 27.0 (27A266a) is a release build (PO-35, D-3), and the build Mac now has 27.1 (27A9275) instead | ADR index |
| 83 | ADR: persistence | pending-human | `Docs/ADRs/0003-persistence.md` (Proposed) | ADR index |
| 84 | ADR: reader adapter | pending-human | `Docs/ADRs/0004-epub-reader-adapter.md`, `Docs/ADRs/0005-pdf-reading-and-anchors.md` (both Proposed) | ADR index |
| 85 | ADR: audio, timeline and excerpt strategy | pending-human | `Docs/ADRs/0006-audio-playback-and-excerpts.md` (Proposed; decisions PO-1 to PO-5 and the device run pending) | ADR index |
| 86 | ADR: pairing and transport security | pending-human | `Docs/ADRs/0008-pairing-and-transport-security.md` (Proposed; security sign-off pending), with `Docs/ADRs/0009-transfer-protocol.md` | ADR index |
| 87 | ADR: AI and context privacy | pending-human | `Docs/ADRs/0011-ai-providers-context-and-privacy.md` (Proposed) | ADR index |
| 88 | ADR: retention and backup | pending-human | `Docs/ADRs/0012-retention-backup-restore.md` (Proposed) | ADR index |
| 89 | ADR: design language (final token values, Literata bundling and licensing, Dynamic Type mapping, grayscale conformance method) | pending-human | `Docs/ADRs/0013-design-language.md` (Proposed; design review on devices pending) | ADR index |
| 90 | Full schemas and OpenAPI generated from the contract descriptions | passed-host | `10-contracts` and `11-capture-anchor-contracts` passed in `evidence/M0-Integration/ci-full-clean-run-assembled.log`, and again for this refresh (`evidence/M0-Integration/gate-refresh-checks.log`, part 6: 17 schemas, 644 fixtures, 1 OpenAPI document); ADR-0016 approval is row 92 | `Contracts/README.md`; `M0-contracts.md` |
| 91 | The design token export from Section 4.4 | passed-host | `Contracts/design/marginalia.v1.json`; `evidence/G06-Design/export-check.log` | `G06-Design.md` part 1, "Token export with schema, fixtures, `instances.json` and a CI drift check" |
| 92 | The other Stage 0 ADRs (ADR-0002 amendments, ADR-0007, ADR-0010, ADR-0014, ADR-0015, ADR-0016) | pending-human | `Docs/ADRs/README.md`; ADR-0002's amendments now include the Git LFS adoption (agent review and human sign-off pending) | ADR index |

**Count.** Of the 92 rows: COUNT_PLACEHOLDER (counted by `evidence/M0-Integration/commands/gate-refresh-check.py`; the same counts as on 15 October 2026).

### 2.10 The CI from a clean tree, and since

`Docs/Stage0/evidence/M0-Integration/commands/ci-assembled.sh` ran `Scripts/ci.sh` from a clean tree (all `.build` and DerivedData deleted; `Scripts/fixtures/fetch.sh` and the cache generators first), every drop-in on the simulator `Sylvia-M0-assemble` (iPhone 17, iOS 26.5), with `G02_LOOPBACK_ONLY=1` and every player at test volume 0.01, so every audio measurement in these runs was taken at test volume (integration log 7.6). Both runs used Xcode 27.0 (27A266a).

- **All 13 drop-ins have passed from a clean tree on the final code, but from two runs, not one.** The second complete run, on `efc9479` (14 October 2026, 17:31-20:53 UTC; `evidence/M0-Integration/ci-full-clean-run-assembled.log`): 12 of 13 passed. `71-g05-recovery` passed its 73 host tests and then stopped at its own guard because the build Mac's screen had locked, so the class-B protection tests had skipped. It was re-run alone on `6371c88` once the screen was unlocked (no code changed in between) and passed, with class B read back on 53 files and directories (`evidence/M0-Integration/ci-71-g05-recovery-unlocked.log`, `evidence/M0-Integration/ci-71-g05-recovery-unlocked-dropin.log`).
- **The first complete run** (on `4a44739`; `evidence/M0-Integration/ci-full-clean-run-assembled-first.log`) failed in `60-g04-audio` (an assembly change to G0.4's file protection did not compile) and `40-g02-transfer` (the Bonjour browse test cannot work under loopback-only). Both were caused by the assembly and fixed in `038145a`. Since then, an agent's run lists the Bonjour row as not run; the gate's own LAN runs cover it.
- **Durations** (second run): 3 h 22 min in all (12,104 s); the longest drop-ins `60-g04-audio` 5,330 s, `21-design-catalog` 2,623 s, `50-g03-intake` 1,872 s. The recovery re-run took 334 s. Other agents shared the Mac: the 1-minute load was 4.54 at the start and 12.59 at the end of the second run, 1.2-14.2 in G0.4's samples (`evidence/M0-Integration/ci-second-run-g04-host-load.tsv`), and up to 83 in the first run. Every timing is indicative only.
- **The documents drop-ins** (`contracts`, `dependency-lock`, `hard-rules`) passed again on `b08f927` (`evidence/M0-Integration/ci-documents-final.log`) and on `878f1cc`, the first version of this summary (`evidence/M0-Integration/gate-summary-checks.log`).
- **The Git LFS adoption (19 October 2026; integration log sections 9.3, 9.4 and 9.6).** `Scripts/ci.sh` now runs the new `00-git-lfs` first in every run. In the adoption's worktree `00-git-lfs`, `10-contracts`, `11-capture-anchor-contracts` and `13-hard-rules` passed; in clean clones of the local repository (no network) `20-design`, comparing the 527 smudged references in verify mode, and `21-design-catalog` passed; and clones checked out without Git LFS failed `00-git-lfs` with its instruction, which `Scripts/setup-repo.sh` then repaired (`evidence/M0-Integration/lfs/r3-fix/clean-checkout-clone.log`, `evidence/M0-Integration/lfs/clean-checkout-design.log`).
- **For this refresh** (`evidence/M0-Integration/gate-refresh-checks.log`, part 6, with its commit and the load in its header): `Scripts/ci.sh contracts dependency-lock hard-rules` ran `00-git-lfs`, `10-contracts`, `11-capture-anchor-contracts` and `13-hard-rules`, which passed, and `12-dependency-lock`, which failed on one line only, its toolchain check.
- **Xcode 27.1 on the build Mac.** Since 18 October 2026 (integration log 9.5) `/Applications/Xcode.app` is Xcode 27.1 (27A9275); ADR-0001 pins 27.0 (27A266a), and no Xcode 27.0 is installed. So `12-dependency-lock` fails its toolchain check on this Mac whatever the commit: a clone of `504fac2`, before the adoption, fails the same way (`evidence/M0-Integration/lfs/clean-checkout-base-control.log`), and every repository check the drop-in makes passes. The 13-of-13 result above is Xcode 27.0's. Of the runs this repository records under 27.1, only `00-git-lfs`, `10-contracts`, `11-capture-anchor-contracts`, `13-hard-rules`, `20-design` and `21-design-catalog` ran and passed; `31-g01-epub`, `32-g01-pdf`, `40-g02-transfer`, `50-g03-intake`, `60-g04-audio`, `70-g05-ai` and `71-g05-recovery` have not been run under it. Owner: you (PO-35): reinstall 27.0, or name 27.1 as the pin and have ADR-0001, the inventory's toolchain and `Scripts/lib/env.sh` changed together (ADR-0014 section 6).
- **Not run anywhere by agents:** `.github/workflows/ci.yml` (manual dispatch only; not yet run with `lfs: true`); the LAN, Tailscale, device-ATS and Bonjour steps of G0.2 (loopback-only rule; the gate's own clean run covered them); `mac-identity-signed` (Xcode on the build Mac has no account for team A4KBDX665Z); the G0.4 device bundle with its fixtures (`G04_DEVICE_FIXTURES` unset; G0.4's own clean run built it); a clone from GitHub, and any push.
- **The evidence folder's name.** The assembly's task named `Docs/Stage0/evidence/M0-integration`; the tracked folder is `M0-Integration`, which this Mac's case-insensitive file system treats as the same, so the assembly used it, and so does this summary.

## 3. Section 23.1 decisions

You approved D02-D15 as defaults on 6 October 2026 and amended D01 (plan 1.1). Draft 0.5 changes seven of them and adds two; those need your approval again, and several also need a technical, security, QA or design owner. "Confirmed" below means the host and simulator evidence supports the default as written, never that a device has.

| Decision | Outcome of the Stage 0 evidence | Amendment | Who still decides |
| --- | --- | --- | --- |
| D01 Platform floor (iOS/iPadOS 26+, macOS 26+) | **Confirmed** on the simulator: every spike builds and runs on iOS 26.5; iOS 26.0-26.4 are untested (ADR-0001) | A01 (status text only) | You: confirm the toolchain pin (PO-35, D-3), now that the build Mac has Xcode 27.1; which phone is the oldest supported (D-1) |
| D02 Core stack | **Changed**: Readium needs Sylvia's safety adapter (it runs publication scripts and reaches the network on its own); archives through `readium/ZIPFoundation` 3.0.1 behind Sylvia's strict layout check; versions pinned | A01, A02, A19 | Technical lead; you re-approve |
| D03 Lock-screen capture | **Changed**: one App Intent offered as a Control and an App Shortcut; not advertised until its device steps pass | A26 | You (PO-17, G0.4 PO-6) with the audio lead |
| D04 Audio words | **Confirmed** on the host against fake endpoints (no endpoint: nothing uploaded; offline: waits; error: clip kept); a real endpoint pending-human | none | none beyond the M0 review |
| D05 Supported formats | **Changed**: Opus in WebM excluded; FLAC, Opus and WAV only after the device run; per-file timing mode and import remux for long files | A22, A23 | You (PO-18, PO-20) with QA, after the device run |
| D06 Device state sync | **Confirmed** (unchanged): nothing in Stage 0 syncs progress or notes; G0.2's receipts carry delivery only | none | none |
| D07 Pairing | **Changed**: the `sylvia://` link is not advertised, because another app can claim the scheme | A16 | Security reviewer and you (PO-11, PO-10) |
| D08 Local model transport | **Changed**: ATS did not block local cleartext on the simulator, so Sylvia's own endpoint rules are what is enforced; cleartext proposed only at IP literals in local ranges | A14 | Security reviewer and you (PO-36, D-9) |
| D09 Retention | **Confirmed** on the simulator: removing every original keeps the knowledge record (T44) | none | none |
| D10 Export/restore | **Changed** in detail: format v1 proven as a directory bundle; the single-file form follows the archive rules | A19 | You (PO-22) with security |
| D11 Organization | **Unchanged**, not exercised by Stage 0 | none | none |
| D12 Ratings/history | **Confirmed** as far as built: the rating component (half stars, 1-10, clearing apart from zero) and the schema's ratings pass on the simulator | none | none |
| D13 Distribution | **Unchanged**; ADR-0014 section 7 item 2 asks whether the BoringSSL advertising clauses are acceptable for the notarized companion | none | Release owner and counsel |
| D14 Scope sequence | **Unchanged** (roadmap only); draft 0.6 adds a later web reader to Section 24 as a separate post-V1 workstream | none | You, when Phase A is sequenced |
| D15 Design language | **Changed**: type scaling by the system styles' sizes (the `UIFontMetrics` row failed); bounded Dynamic Type exceptions; dark tints, the Increase Contrast step and vocabulary gaps for design review | A40, A41, A45 | Design and iOS lead on devices; you (PO-28 to PO-32) |
| D16 Tailscale route and ATS (new) | Added because G0.2's Tailscale rows failed; a scoped ATS exception was measured working in a probe build | A13 | Security reviewer and you, at the M0 gate (PO-07) |
| D17 Data protection and durability (new) | Added: class C for every persistent file, set and read back; WAL with `synchronous = FULL` and `fullfsync` | A27, A28 | Security reviewer, you (PO-21) and persistence, before M1 |

**Your direction of 15 October 2026 (plan draft 0.6).** M3 keeps the selected passage and its source in view while a note is written and returns to the reading position; M5 adds Explain and Simplify question starters inside Ask, follow-ups in the same source-linked conversation and previews of a citation's retained evidence; a browser-based reader is a separate post-V1 workstream; native iOS/iPadOS V1 and the Mac companion stay first (plan 1.1, 4.1, 13.1, 21.2, 24; acceptance cases T55-T57). It is an approved product direction. It changes none of D01-D17, signs none of the changes above, and approves none of the pending amendments (`M0-plan-amendments.md` front matter). Its new labels, such as Explain and Simplify, go through the same vocabulary process as the AI status phrases the amendments propose (A45, PO-28): design review, a fixture update and a snapshot re-baseline (plan 4.4.9; plan 13.1 says the same of the new labels and prompt templates). Gloss itself is a design reference, not a dependency: the plan records that the snapshot it was read at declares no reuse license, and ADR-0014's inventory now lists it so (`Docs/Licenses/third-party-inventory.md`, "Design references").

**The G0.6 interaction prototype predates that direction.** Its capture sheet shows the quotation once, at the top of a sheet that scrolls, with nothing that keeps the passage in view while the note is written (`Packages/Design/Sources/SylviaDesign/Components/CaptureSheet.swift`; `Apps/DesignCatalog/Sources/App/Layout.swift`, `SheetPage`); and on iPad its side pane is the Thoughts pane, while Ask opens as a page pushed in the reader (`Apps/DesignCatalog/Sources/Prototype/ReaderScreens.swift`, `Apps/DesignCatalog/Sources/Prototype/AskScreen.swift`), with no side-pane discussion. That is design input for M3 and M5, which build these interactions with T55-T57, not an M0 defect: row 72 stands. (Read from the committed sources; nothing was run for this.)

## 4. Questions only you can answer

Taken from `M0-plan-amendments.md` Section 4 (options and recommended defaults as written there; read that table for the full reasoning), the gate reports, ADR-0014 and the runbook. Nothing new is raised here. Where you choose another option, the draft 0.5 text tagged in the amendments changes.

### 4.1 From the plan amendments (PO-01 to PO-36)

| ID | Question | Options (short) | Recommended default |
| --- | --- | --- | --- |
| PO-01 | Fixed-layout EPUB in V1? | (a) out; (b) in, after its own spike | (a) |
| PO-02 | Accept the EPUB compatibility subset and the spike's limits? | (a) accept as configurable defaults, recheck in M3; (b) relax; (c) tighten | (a) |
| PO-03 | Quotation continuing into the next chapter in the V1 UI? | (a) an "extend into next chapter" action; (b) storage only | (a) |
| PO-04 | Keep the reading position by text through settings changes? | (a) return to the text first in view; (b) Readium's progression | (a) |
| PO-05 | PDFs that forbid copying | (a) read only, no quotation, search or AI text; (b) personal quotation and search; (c) every text feature | (a) (a narrowing no failed spike forces) |
| PO-06 | Password-protected PDFs out of V1? | (a) excluded; (b) prompt | (a) |
| PO-07 | Tailscale route (with security) | (a) scoped ATS exception; (b) publicly trusted MagicDNS certificate; (c) no route | (a) if security approves, otherwise (c); decided at the M0 gate (D16) |
| PO-08 | Background transfer promise | (a) "continues when iOS allows it, resumes from verified parts"; (b) uninterrupted | (a) |
| PO-09 | Part size and task window | keep 16 MiB, two connections, four tasks per job; or change | keep, tune after the device run (the bound across jobs, which G0.2 added later, is in 4.2) |
| PO-10 | Invitation lifetime and pairing limits (with security) | (a) 10 minutes with per-invitation and per-address limits; (b) also a global cap | (a) |
| PO-11 | The `sylvia://` pairing link (with security) | (a) drop it (copied code, optional QR); (b) keep it | (a) |
| PO-12 | Repair path for a damaged transfer store | job store: (a) move aside and restart, (b) leave deferred; sources file and import ledger: no default | job store (a); no default for the other two |
| PO-13 | When the phone reads the device inbox | (a) launch, foreground, Inbox shown; (b) also periodically | (a) |
| PO-14 | Intake cleanup, limits and bundle rules | accept or change each | accept all as configurable defaults (see 4.2 for the manifest size limits G0.3 added later) |
| PO-15 | `LSSupportsOpeningDocumentsInPlace` | (a) NO; (b) YES | (a) until G0.3 device step 13; (b) if a phone also loses "Open With" |
| PO-16 | EPUBs stored as package folders | (a) accept on the phone; (b) Mac packs them; (c) refuse everywhere | (c) for V1 unless M6 has room for (b) |
| PO-17 | Quick-capture narrowing | (a) in-player Capture baseline, quick capture after device steps 8-13; (b) also fund the App Group spike | (a) |
| PO-18 | Extra audio formats | per format after the device run | admit each that passes, limits stated; WebM excluded |
| PO-19 | Mono excerpts | (a) mono AAC-LC 64 kb/s; (b) stereo | (a) |
| PO-20 | Per-file timing mode and import remux | timing mode yes or no; remux (a) keep original and copy, (b) copy only, (c) no remux | timing mode; remux (a) only for members long enough to miss the budget |
| PO-21 | The I-03 durability setting | (a) `FULL` + `fullfsync`; (b) GRDB's `NORMAL` | (a) |
| PO-22 | Unencrypted v1 backups with a warning | (a) approve; (b) fund encryption | (a) for internal and TestFlight use |
| PO-23 | The locked-device test T50 | (a) app-level part in M1, harness only if step 3 is inconclusive; (b) build the harness now | (a) |
| PO-24 | AI defaults (Responses with `store: false`, 8,192 tokens, manual offline send) | approve or change | approve all three |
| PO-25 | The exact-quotation rule | (a) strict; (b) looser | (a) |
| PO-26 | Generic adapter refuses first-party hosts? | (a) refuse; (b) allow | (a) |
| PO-27 | Uncertain server errors; provider switches | (a)/(b)/(b') retry rules; (c) leave earlier turns out, (d) ask to resend | (a) and (c) |
| PO-28 | Which missing states get vocabulary phrases | add each gap, or leave it | add every gap before the milestone that shows it, in one design pass |
| PO-29 | "Needs attention" reasons in the vocabulary | (a) before M2's Inbox; (b) later | (a) |
| PO-30 | System sheet motion | (a) accept and narrow T51's Reduce Motion clause; (b) custom presentation | (a) only if G0.6 device step 19 is acceptable, otherwise (b) |
| PO-31 | Bars stop growing at xxxLarge | (a) accept; (b) keep growing | (a) |
| PO-32 | Sheets, titles and the mini-player at accessibility sizes (with design) | content-sized or full sheets; title fitting or mid-word breaks; mini-player capped, one row, or growing | content-sized sheets; title fitting; mini-player capped at xxxLarge unless design prefers one row |
| PO-33 | The bundled onboarding sample | which public-domain text | a short Standard Ebooks (CC0) excerpt such as the prototype's Middlemarch passage |
| PO-34 | Starting milestones while device steps are pending | (a) hold all; (b) each milestone after its gates' steps on phone B, exit after the repeats on the baseline and an iPad; (c) as (b) but M1 earlier; (d) device steps as release criteria only | (b) |
| PO-35 | Is Xcode 27.0 (27A266a) the release build to pin? | confirm or name another | confirm after checking Apple's release notes. Since 18 October 2026 the build Mac has Xcode 27.1 (27A9275) and no 27.0 (Section 2.10), so confirming 27.0 means reinstalling it there; naming 27.1 means changing the pins together (ADR-0014 section 6) |
| PO-36 | Cleartext to a local model server by name or tailnet (with security) | (a) IP literals in local ranges only; (b) per-endpoint exception | (a) |

### 4.2 Added by the reports and records merged after the amendments were written

The amendments were read at `471b143`; the gate reports and ADRs changed afterwards, and their re-check is not recorded (Section 6.3). These questions are put to you by those later texts.

| Source | Question | Options | Recommended default |
| --- | --- | --- | --- |
| `G04-Audio.md` PO-5 | Playback control defaults (plan 10.1) | skip intervals (5-120 s); sleep-timer kinds; rewind after a long pause | 15 s back and forward; both sleep-timer kinds; the rewind as a setting, off by default |
| `G03-Intake.md` open question 1 | Manifest size limits (raised in review round 4) | accept or change: 16 MiB for a pack's manifest, 256 KiB for `handoff.json` | none stated for these two values; PO-14's default for the rest of open question 1 is to accept them as configurable defaults, and F19 gives the measured reason for 16 MiB |
| `G03-Intake.md` open question 8 | Raw files copied with Finder (F15) | keep the raw import (stages a paused copy as it is), or accept only `.sylviapack` from Finder above some size; and whether imported raw files are offered for removal | none in the report or the amendments |
| `G02-Transfer.md` open question 3 (its second part, review R3-05); ADR-0009 open items; ADR-0008 open items | A bound across transfer jobs on the outstanding requests that carry the bearer token (the spike bounds them per job only) | (a) two downloading jobs at a time, the rest queued; (b) a cap on outstanding tasks across all jobs | none chosen; ADR-0009 notes that the plan's wording more naturally limits jobs |
| `ADR-0014` section 7 item 1 (you and counsel) | OpenDyslexic fonts that Readium copies into the app (CC BY 3.0 and a Bitstream license no longer published) | (a) counsel confirms they can ship with attribution; (b) ask Readium for the OFL release or optional fonts; (c) remove them with a reviewed build step and its own ADR; (d) revisit the EPUB stack | (b), with (a) as the interim answer if counsel agrees; never (c) without that ADR |
| `ADR-0014` section 7 item 2 (release owner and counsel; the ADR's open items name you and counsel) | The advertising clauses of the BoringSSL in SwiftNIO SSL, for the notarized Mac companion (D13) | accept them, or require a SwiftNIO SSL release whose BoringSSL is Apache-2.0 before distribution | none given |
| `ADR-0014` section 7 item 3 (counsel; the same) | Two Readium Foundation files in ZIPFoundation whose headers point to a BSD-style license the fork's MIT license file does not contain | confirm that reproducing both texts suffices, or not | yes, and ask Readium to correct the headers or the license file |
| `ADR-0014` section 7 item 8 (counsel; the same) | A binary search in SwiftSoup adapted from a Stack Overflow answer | it carries that answer's CC BY-SA terms, or it is SwiftSoup's own MIT code | ask SwiftSoup's maintainers which answer it was and whether they relicensed it; treat the code as SwiftSoup's until counsel says otherwise |

ADR-0015 also asks you, with the security reviewer, to accept the residual risks it marks as owner decisions. Each is one of the questions above: the `sylvia://` link (PO-11) and the Tailscale exception (PO-07) at boundary B4, the cleartext rule (PO-36) and the 5xx policy (PO-27) at B6, unencrypted backups (PO-22, D10) at B8, class C (D17, PO-21 with security) at B9, and unauthenticated quick capture on a locked phone (PO-17, ADR-0007) at B11.

### 4.3 From the device runbook (Section 6, D-1 to D-9)

| ID | Question | Options | Recommended default |
| --- | --- | --- | --- |
| D-1 | Which phone is the oldest supported iPhone, and are the iPad's G0.6 steps part of M0? | iPhone 12-class (plan 19.1) or an older phone iOS 26 supports; iPad steps in M0 or in M3 (correction C51) | none given; plan 19.1 proposes iPhone 12-class |
| D-2 | If that phone cannot be had before the M0 exit | obtain it, or record an exception in ADR-0001 and ADR-0013 (and the items in ADR-0003, ADR-0005, ADR-0007, ADR-0009, ADR-0010 and G0.2 row T38) | none given |
| D-3 | Xcode 27.0 (27A266a) is a release build | as PO-35 | as PO-35 (the build Mac now has 27.1) |
| D-4 | Without keys, a local server or a transcription endpoint: move G0.5 AI steps 5-7 (and 8, the gateway) to M5 as a recorded exception? | run them in M0, or record the exception | none given |
| D-5 | The open questions the reports put to you | as Sections 4.1 and 4.2 | as there |
| D-6 | ADR approvals, with the corrections that move steps out of M0 (C47, C49, C50, C56) | approve, change or reject each | none given |
| D-7 | The plan changes deferred at integration (rows 3, 19, 20, now A40, A41, A45, A34) and the `CLAUDE.md` changes | approve or change | none given. The `CLAUDE.md` changes now also include assembly's (row 83) and the Git LFS adoption's Setup section; integration log rows 22 and 83 asked for your review before `m0-integrate` was merged, and the merge of 15 October came first (Section 6.3) |
| D-8 | Git LFS | decided by you on 13 October 2026 (adopt), and done on 19 October 2026: no longer a decision. What it leaves you is in Section 5.3 | |
| D-9 | What counts as the minimum OS for App Transport Security (with security) | the earliest 26.x tested stands for 26.0, or an exception in ADR-0011 | none given |

## 5. What remains pending

### 5.1 Device and human steps

`M0-device-runbook.md` gathers every pending step into sessions (Section 3 orders them) and says which block the M0 gate (Section 7, with the reason for each). Nothing in it has been run. In short:

**Blocking the M0 gate** (runbook Section 7; phone B is the iPhone 17 Pro, A the oldest supported iPhone, C an iPad):

| Gate | Blocking steps |
| --- | --- |
| G0.1 EPUB | 1-13 on B |
| G0.1 PDF | 1-10 on B; 1 on A |
| G0.2 | 1-10, 12-20 on B; 11 on A; 21 until ADR-0009's owner accepts C47 |
| G0.3 | 6-24 on B; 6-24 on A until ADR-0010's owner accepts C56 |
| G0.4 | 1-16 on B; 8-10, 12, 13 on A |
| G0.5 AI | 1-4, 5-7, 9.2, 9.3 on B (5-7 movable by D-4); 1 on A if A has an earlier iOS 26.x; 8 until ADR-0011's owner accepts C49 |
| G0.5 recovery | 1-4 on B; review row 23; 1-2 on A. The runbook also lists the Mac's class-B run (Session 0.8, correction C27); that is already done: integration log 7.3 records C27 as done by G0.5 recovery's round-4 clean run, and the assembly's re-run read class B back on 53 files and directories (`evidence/M0-Integration/ci-71-g05-recovery-unlocked-dropin.log`) |
| G0.6 | on B 1-9, 12-14, 16-19, 22-26, 29, 30; on A 4, 13-15, 22-27, 29, 30; the designer's 7, 9, 21, 31; on A the rest of 1-19 until ADR-0013's owner accepts C50; on C the steps the report's rows name, unless D-1 moves them to M3 |
| All | Session 10: the security, design, QA and product reviews and the M0 exit review |

**Not blocking** (runbook Section 7, "Can wait"): the G0.1 repeats on A and C (M3); G0.1 PDF step 10 on A (M3); G0.2 step 21 once C47 is accepted (M6); G0.3 steps 25-27 (M2) and 6-24 on A once C56 is accepted (M2); G0.4 steps 1, 3 and 15 on A (M4); G0.5 AI 4.4 and 9.1 (M5), and 8 once C49 is accepted (M5); G0.5 recovery 3-4 on A (M1), 4.5 (the first milestone with an app shell) and 5 (never: power loss cannot be produced on an unmodified iPhone); G0.6 step 10 (M6) and, once C50 is accepted, the A and C repeats it names (M3). Plan 20.4's user validation is M8's. Draft 0.6's acceptance cases T55-T57 are M3's and M5's, not M0 steps.

Six runbook corrections are deferred to your decisions D-1 and D-6 (C28, C47, C49, C50, C51, C56), and C46's script change waits for the G0.2/M6 owner (integration log 7.3); until a correction is accepted, its steps block M0.

### 5.2 Before the first device session

- The account holder accepts team A4KBDX665Z's Program License Agreement and adds the account to Xcode on the build Mac (`G02-Transfer.md` open question 9; runbook Session 0). Every phone step needs it, and so does `mac-identity-signed`.
- The Xcode build: the runbook (Section 1.1) asks for Xcode 27.0 (27A266a) on the build Mac, and the Mac has 27.1 (Section 2.10). Decide PO-35 first; otherwise every session would build with an Xcode that ADR-0001 does not pin, and `12-dependency-lock` keeps failing on the Mac.
- The leftover `g05-<uuid>` directories in this Mac's user temporary folder are yours to delete once no G0.5 run is in progress (`G05-AI.md` review round 7, R7-04, pending-human). Counted read-only again for this refresh: 1,664, and no `g05-tests-*` directory (`evidence/M0-Integration/gate-refresh-checks.log`, part 7).

### 5.3 Git LFS: decided and implemented

- **Decision.** "Adopt Git LFS for the snapshot and evidence images once the current integration is complete. Use repository-local configuration, update CI and setup instructions, and verify a clean checkout. Leave existing history intact." (product owner, 13 October 2026).
- **Implemented on 19 October 2026** (integration log section 9; ADR-0002, "Binary test baselines and evidence images"). The adoption commit `adab8e2` (parent `504fac2`) adds `.gitattributes` and turns exactly the 777 matched images into LFS pointers: the 527 snapshot references (37,703,582 bytes) and the 250 Stage 0 evidence images (29,875,981 bytes), 67,579,563 bytes in all, held in 719 distinct LFS objects (65,110,465 bytes). The 16 patterns are `**/__Snapshots__/**/*` and `Docs/Stage0/evidence/**/*` for png, jpg, jpeg, gif, heic, tif, tiff and webp, each extension matched in any letter case, each `filter=lfs diff=lfs merge=lfs -text`. The configuration is repository-local (`git lfs install --local`; nothing in your global or the system configuration). CI: `Scripts/ci.d/00-git-lfs.sh`, which `Scripts/ci.sh` runs first in every run, and `lfs: true` in the workflow. Setup: `Scripts/setup-repo.sh` and `CLAUDE.md`'s Setup section. A clean checkout was verified with clones of the local repository (no network). History was left intact: nothing was rewritten, so the image versions committed before the adoption stay in git history as they were.
- **Verification.** An independent agent verification ended with the verdict accept-with-minor and no open serious finding. Its three minor findings, R3-01 (the wording of a shared-object count), R3-02 (documents that still described LFS as a future step) and R3-03 (the `.gitattributes` comment on letter case), were fixed on 19 October 2026 (`75b312f` to `9ac7789`) and the checks run again (integration log 9.6); those fixes await the next agent review. Human sign-off pending.
- **This refresh's own check** (`evidence/M0-Integration/gate-refresh-checks.log`, part 3): `.gitattributes` present with the 16 patterns, the filter in the repository's own configuration, 777 files listed by `git lfs ls-files`, and `00-git-lfs` passing (part 6).
- **Pushing is your action, and it costs LFS quota.** No agent pushes. The first push of `m0-integrate` uploads the 719 LFS objects (65,110,465 bytes, about 0.061 GiB) through git-lfs's `pre-push` hook to your GitHub account's LFS storage for `jevidon/sylvia`. ADR-0002 quotes GitHub's documentation (read 19 October 2026): GitHub Free and Pro include 10 GiB of LFS storage and 10 GiB of bandwidth, storage counts every LFS object the repository has, and each workflow run with `lfs: true` and each clone that downloads the LFS files (65.1 MB at adoption) uses bandwidth. Which plan this account is on was not checked.
- **Not done yet:** the GitHub workflow has not run with `lfs: true`, and no clone was made from GitHub. The patterns cover images only: MP4 or MOV evidence from the device sessions goes into plain git unless you have the patterns extended first (runbook D-8).

### 5.4 Other owners' open items (not device steps)

- ADR-0014's owner: close R4-01 and R4-02 before the first product target is added (Section 6.1).
- You, with the technical lead: the toolchain pin and the Xcode on the build Mac (PO-35; Section 2.10).
- The plan amendments' owner: the re-check against the merged reports (Section 6.3).
- Contract consolidation and M3: an approach for G0.1 PDF row 10c (open question 7; Section 6.3).
- The validator's owner (ADR-0002, CI): `Scripts/validate-contracts.py` requests (a) and (b) (integration log row 51).
- `Scripts/tools`' owner: pin pip (row 50; ADR-0014 section 7 item 9).
- M5: the two contract patterns that are not portable (row 40).
- The `SylviaDesign` owner, with design review: the vocabulary keys G0.3, G0.4 and G0.5 AI asked for (rows 27 and 78), and the labels plan draft 0.6 adds (Explain, Simplify) when M5 needs them.
- G0.2/M6: C46's script change.

## 6. Known open findings

### 6.1 Blockers and serious findings still open

| Where | Finding | Severity | Owner and when |
| --- | --- | --- | --- |
| Dependency lock (ADR-0014; item `deps`, final agent review round 4: **reject**) | **R4-01:** XcodeGen expands `${VAR}` from the environment, so a product `project.yml` can reach `Spikes/` code, add `-import-module Zip` or use a test-only package without the check seeing it | serious | ADR-0014's owner; before the first product target is added (integration log 7.1, 7.7) |
| Same | **R4-02:** C-family `#include` paths are judged only against `Spikes/`, so an include outside the product roots or into a package checkout (Minizip's headers included) passes | serious | Same |

Both are routes around the guard that keeps marmelroy/Zip 2.1.2 (CVE-2023-39135), which Readium 3.11.0 depends on, out of product code. No product target exists yet, so neither route is in use.

Nothing else is open at that severity. The eight gates' final reviews and the other twelve M0 items each ended accept-with-minor with no open serious finding; the two serious findings G0.5 AI's review round 7 raised on `m0-int-minors-g05-ai` (R7-01, a blocker; R7-02, major) were fixed on that branch before its final review, with mutations M63-M77 (`evidence/G05-AI/mutation-checks.log`: 77 of 77 caught). The Git LFS verification's R2-01 ("Git LFS is still not adopted"), open in the first version of this summary, no longer applies: the adoption was carried out and verified (Section 5.3).

The failed rows of Section 2 (rows 10, 22, 42, 63 and 76) are results, not review findings; their approach changes are in the plan amendments except row 10's (Section 6.3).

### 6.2 Minor findings

| Where | Minor findings | State | Listed in |
| --- | --- | --- | --- |
| G0.1 EPUB, final review 3 | 2 (R3-01, R3-02) | closed (R3-02 at integration, R3-01 on `m0-int-minors-g01-epub`) | integration log section 2 row 3; `G01-EPUB.md` |
| G0.1 PDF, final review 2 | 3 (R2-01 to R2-03), with the later rounds' R3-01 to R3-06 and R4-01 to R4-07 | closed | integration log section 2 row 4; `G01-PDF.md` |
| G0.2, final review 3 | 6 (R3-01 to R3-06) | fixed, or handed to device and human steps | integration log section 2 row 6; `G02-Transfer.md` finding 21 |
| G0.3, final review 2 | 6 (R2-01 to R2-06), with the later rounds through round 4 | closed | integration log section 2 row 5; `G03-Intake.md` |
| G0.4, final review 6 | 6 (R6-01 to R6-06) | closed | integration log section 2 row 8; `G04-Audio.md` |
| G0.5 AI, final review 6 | 4 (R6-01 to R6-04), with round 7's R7-01 to R7-04 | fixed; R7-04 left as your action (Section 5.2) | integration log section 2 row 7; `G05-AI.md`, Review rounds 6 and 7 |
| G0.5 recovery, final review 3 | 5 (R3-01 to R3-05), with round 4's | fixed | integration log section 2 row 2; `G05-Recovery.md` |
| G0.6, final review 3 | 2 (R3-01, R3-02) and finding 18 | fixed | integration log section 2 row 1; `G06-Design.md` |
| Threat model (ADR-0015) | 4 (TM-F3 to TM-F6) | open, assigned to M1-M6 | ADR-0015 section 5 |
| Git LFS adoption, its verification | 3 (R3-01 to R3-03) | fixed; the fixes await the next agent review | integration log section 9.6 |
| The thirteen M0 items' own final reviews | not recorded | each returned accept-with-minor (deps: reject, Section 6.1); any minor findings they raised "stay with the gate" (`README.md`), but neither those findings nor their count were committed or handed to this summary | the workflow's review records; to be added to each gate's report before the exit review |

Still open and recorded in the repository besides these: the deferred requests of integration log 7.7 (Section 5.4).

### 6.3 Inconsistencies found, and records corrected

Open, for the named owner (none changes a status in a gate report):

1. **A fourth gate has a failed row, and no approach change.** `G01-PDF.md` row 10c (rotated text matrices, finding 12) is **failed**, but the plan's Section 1.1 and its 21.1 Stage 0 status and `M0-plan-amendments.md` ("rows failed in three gates") do not count it, and the amendments' ADR-0005 row still calls rotated text inside an unrotated page "untested" (Section 3.2, item 5). The row came in on `m0-int-minors-g01-pdf`, after the amendments were pinned at `471b143`. Plan 21.1 asks a failed spike to change the documented approach before downstream work; ADR-0005's open items and the report's open question 7 give the decision to contract consolidation and M3, and ADR-0016 does not address it. Owner: the plan amendments, with contract consolidation.
2. **The amendments' re-check against the merged reports is not recorded.** Their own checker, run for this refresh (`evidence/M0-Integration/gate-refresh-checks.log`, part 5), fails 14 checks, the same 14 before and after this refresh's edits: findings and open questions that the later review rounds added and the amendments do not cover (G0.1 PDF findings 10-15 and open questions 6-8, G0.2 findings 21-22 and open question 12, G0.3 F15-F19 and open questions 8-10, G0.4 finding 9, G0.5 recovery F11-F12, G0.6 finding 18 and open question 14), G0.4's open-question bullets, which no longer map one to one, the ADR consequence lists of ADR-0002, ADR-0003, ADR-0005, ADR-0010 and ADR-0014, which grew, and two checks that draft 0.6 changed on purpose (Section 24 and draft 0.5's front-matter phrases). Section 4.2 above lists the questions for you that these texts added. Owner: the amendments' owner.
3. **ADR-0002's branch rule and the merge.** ADR-0002 (accepted for Stage 0) says a milestone's branch is "merged after the milestone's exit review"; pull request #4 merged the M0 work into `main` on 15 October 2026, before that review. The merge changes no status. Owner: you, to amend the rule or record the merge as an exception when you approve ADR-0002's amendments.
4. **The `CLAUDE.md` review the merge was to wait for.** Integration log rows 22, 30 and 83 ask you to review the `CLAUDE.md` changes before `m0-integrate` is merged. It was merged on 15 October 2026, and no review of those changes is recorded; the Git LFS adoption has since changed `CLAUDE.md` again (its Setup section, integration log 9.1). The request stands, before the follow-up pull request. Owner: you.
5. **The runbook's build-Mac requirement.** `M0-device-runbook.md` Section 1.1 asks for Xcode 27.0 (27A266a) on the build Mac, which now has 27.1. It is left as written, because it states the pin; PO-35 decides (Section 5.2).

Corrected in this refresh (each recorded in integration log section 10):

6. `G04-Audio.md`'s shared-file requests 6 to 11 read "Open" although M0 assembly had decided each (integration log rows 76 to 81); their outcomes now match the log (five applied, row 8 deferred to the `SylviaDesign` owner). This is the one gate report edit, and it touches no criterion row.
7. `README.md` named only G0.2 and G0.4 in its sentence on failed rows; it now also names G0.6's `UIFontMetrics` row and G0.1 PDF row 10c.
8. Integration log section 2 row 7 and `README.md` recorded G0.5 AI's fixes as R6-01 to R6-04 with 62 mutations; they now also record round 7's R7-01 to R7-04 and the 77 of 77 mutations.

## 7. Recommendation

**M0 cannot be approved now.** Plan 21.1's exit gate asks for approved evidence and ADRs and signed decisions, and plan 23.3 for the security, design, QA and product sign-offs. None of these has happened: every Stage 0 ADR after ADR-0002 is Proposed, the draft 0.5 decisions are unsigned, and not one device or human step has run. Approving "with conditions" would let M1 start on a protection class and durability setting (D17) that no phone has confirmed, which plan 21.1 and PO-34's recommended default exist to prevent. The merge of the M0 work into `main` on 15 October 2026 does not change this: it approves nothing, and the gate stays pending.

**What would change that**, in the order that unblocks it:

1. Your decisions: draft 0.5's amendments, D16 and D17, the changed decisions of Section 3, the questions of Section 4, D-1 and D-2 (device A and the iPad), and PO-35 (the Xcode build to pin, now that the build Mac has 27.1).
2. The account and devices: the team account in Xcode on the build Mac; the pinned Xcode installed there; device A and, unless D-1 moves its steps, an iPad.
3. The blocking device and human steps of Section 5.1, recorded as passed (or, where one fails, the approach changed before downstream work, as plan 21.1 requires).
4. ADR-0014's R4-01 and R4-02 closed and its section 7 decisions taken; the open inconsistencies of Section 6.3 resolved, including an approach decision for G0.1 PDF row 10c and the amendments' re-check; and the item reviews' minor findings recorded with their gates.
5. The `CLAUDE.md` changes reviewed (integration log rows 22, 30 and 83, and the Git LFS Setup section) and the Git LFS fixes' review done (Section 5.3).
6. Session 10: the security, design, QA and technical-lead sign-offs, then the M0 exit review.

M1 in particular: draft 0.5 keeps M0 as M1's dependency and adds the G0.5 recovery device steps 1-4 on phone B (plan 21.2; PO-34, recommended default (b)), so M1 starts only after both. Whether the exit review may approve M0 while device steps that only later milestones build on are still pending is PO-34's question, and yours.
