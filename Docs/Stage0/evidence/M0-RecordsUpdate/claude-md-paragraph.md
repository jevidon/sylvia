# `CLAUDE.md`: two texts for the product owner to apply (26 October 2026)

`m0-records-update` brings to `m0-decisions` the milestone paragraph that the orchestrating session wrote on
`m0-sessions` at the product owner's request on 24 October 2026 (`6cede84a`, after `5aec2518`). It names `m0-sessions`
as the branch the M0 work and the device sessions use, which no longer holds: `m0-decisions` is the owner's session
branch and `m0-sessions` is retired (integration log section 41). No agent changes `CLAUDE.md` on a workflow's request
(the gate summary's Section 6.3, item 46), so this branch leaves the file as the merge of `m0-sessions` left it and gives
the texts here. Apply them on `m0-decisions` (in `~/Git/sylvia-sessions`, between sittings), or have them applied at
your request, before you ask an agent for anything: until then an agent reads that the M0 work is on `m0-sessions`, so
name `m0-decisions` as its base in your request.

*(26 October 2026: since the fix of the review of `m0-records-update`, that branch no longer brings `6cede84a`'s
paragraph to `m0-decisions`: it leaves `CLAUDE.md` exactly as `m0-decisions` has it (`c72247a6`), whose milestone
paragraph, of 22 October 2026, says that the gate branches and the M0 items are combined on `m0-integrate`, and whose
toolchain line is the one quoted below. Until the texts below are applied, an agent reads that paragraph, so name
`m0-decisions` as its base in your request. They replace it and that line as they would have replaced `6cede84a`'s: its
third paragraph also begins "Current milestone:". The paragraph above, as it read until then, is kept as the record of
it: the review's finding FID-RU-03; [`fix-1/`](fix-1/README.md).)*

*(27 October 2026: apply them at the latest in the same pause between sittings as your merge of `m0-records-update`,
right after it, the merge bringing this file into `~/Git/sylvia-sessions`, and in any case before you ask an agent for
anything: [`README.md`](README.md), "Merging it into `m0-decisions`", gives the commands with the merge's (runbook 0.3,
step 2). Until the fix of the same review's completeness findings this file set no time but before your first request
to an agent: its finding CMP-01; [`fix-1/completeness/`](fix-1/completeness/README.md).)*

Agent-written, not reviewed. Neither text changes the Xcode pin (27.1, 27A9275), which
`Scripts/ci.d/12-dependency-lock.sh` compares with the inventory's: after a change, run that check again
(`source Scripts/lib/env.sh; Scripts/ci.d/12-dependency-lock.sh`).

## 1. The milestone paragraph

Replace the paragraph that begins "Current milestone:" (the third paragraph of `CLAUDE.md`) with:

```markdown
Current milestone: **M0, Stage 0 feasibility and design freeze** (plan Section 21.1). Decisions are recorded in `Docs/ADRs/`; gate evidence in `Docs/Stage0/`. The eight gate branches (G0.1 EPUB and PDF, G0.2, G0.3, G0.4, G0.5 AI and recovery, G0.6) and the M0 items that followed them (the remaining review findings of each gate, the capture-envelope and anchor contracts in ADR-0016, the threat model in ADR-0015, the dependency lock in ADR-0014, the device runbook and the plan amendments) were combined on `m0-integrate` and merged into `main` by pull requests #4 and #5; the records of the product owner's decisions and the lock harness of PO-23 (b) were made on `m0-decisions` and merged by pull request #6 (23 October 2026 UTC, `96bdc7e9`). H-1's one-off exception covered those merges only: nothing else reaches `main` before the M0 exit unless the product owner decides otherwise (ADR-0002, Branches). **`m0-decisions` is the product owner's session branch**: the owner builds the device sessions from it, in `~/Git/sylvia-sessions`, and commits the session records and evidence on it, as since the first sittings of 25 October 2026 (`Docs/Stage0/M0-device-runbook.md` 0.3). Agent work goes on a branch of its own made from `m0-decisions`, never on `m0-decisions` itself, and reaches the owner's build only when merged into `m0-decisions` between sittings, by the owner or by an agent the owner asks; never change the owner's session records or evidence. `m0-exit-prep` (ADR-0014's R4-01 and R4-02 closed in the Zip guard, the M0 items' review records, `linkage.sh` and the Xcode 27.1 evidence) and `m0-sessions` (the device-A change) were made before that rule was restated, from `5aec2518`, whose code is that of `044ed3cf`, the commit of `m0-decisions` before the sessions; `m0-records-update` brought both onto `m0-decisions`'s line. `m0-sessions` is retired: nothing is built from it. Never build on `m0-integrate`, `m0-sessions` or `main`, which lacks the session records. On 22 October 2026 the product owner decided every item of the M0 decision page: the Section 23.1 decisions and the plan amendments are approved (plan draft 0.8), as recommended except PO-13, PO-23, PO-33, PO-39 and D-1 (and on 24 October 2026 the owner decided D-1 again: device A is the iPhone 13 mini, the iPhone 11 Pro no longer charging; the device runbook's Section 6), and every Stage 0 ADR stays Proposed until Session 10's review of it is recorded (decision D-6). Every gate still has pending device and human steps, and the M0 exit review (plan 21.1, 23.3) waits for the device sessions of `Docs/Stage0/M0-device-runbook.md`: every step its Section 7 marks blocking comes first (decision D-10 (i)), and the plan 23.3 sign-offs, which the product owner gives personally, are each recorded only once the evidence it rests on exists. See `Docs/Stage0/README.md` and `Docs/Stage0/integration-log.md`.
```

## 2. The toolchain line

In the first bullet of "## Toolchain", replace

> whether 27A9275 is the non-beta release awaits a check of Apple's release notes

with

> whether 27A9275 is the non-beta release awaits the technical lead's one-line confirmation of Apple's pages, which the orchestrating session read on 24 October 2026 and which list Xcode 27.1 (27A9275) as released, with no beta or release-candidate label (ADR-0001, Evidence; `Docs/Stage0/M0-device-runbook.md` 0.2)

This is the text the fix of the device-A update's completeness findings asked for
(`../M0-DeviceA/fix-1/completeness/README.md`), with ADR-0001's Evidence, which records the pages since `m0-exit-prep`,
named beside the runbook.
