# Stage 0 evidence

Evidence for the feasibility gates in plan Section 21.1 and the M0 deliverables in Section 21.2. Each gate has a report here, raw outputs under `evidence/<gate>/`, and any physical-device steps under `device-checklists/`.

**How to read a result.** Every result names its environment:

- **host:** macOS tests on the build Mac
- **simulator:** iOS runtime and device type
- **device:** physical model and OS version

**pending** means the check needs a physical device, a second device or a person, and has not been run. It is never shown as passed. Reviews done by agents in place of a security, QA or design reviewer are marked "agent-reviewed; human sign-off pending". Timings taken while other agents were building on the same Mac are indicative only and say so, with the load recorded next to them.

| Gate | Report | Device and human steps | Spike | Final review (agent) |
| --- | --- | --- | --- | --- |
| G0.1 EPUB/PDF capture | [G01-EPUB.md](G01-EPUB.md), [G01-PDF.md](G01-PDF.md) | [EPUB](device-checklists/G01-EPUB.md), [PDF](device-checklists/G01-PDF.md) | `Spikes/G01-EPUB/`, `Spikes/G01-PDF/` | accept-with-minor (EPUB review 3, PDF review 2). At M0 assembly: EPUB R3-01 closed (R3-02 at integration), and PDF R2-01 to R2-03 closed with the later rounds' R3-01 to R3-06 and R4-01 to R4-07, each on its `m0-int-minors-*` branch, whose final agent review was accept-with-minor |
| G0.2 Transfer security and background | [G02-Transfer.md](G02-Transfer.md) | [G02-Transfer](device-checklists/G02-Transfer.md) | `Spikes/G02-Transfer/` | accept-with-minor (review 3); security sign-off pending. At M0 assembly: R3-01 to R3-06 fixed or handed to device and human steps on `m0-int-minors-g02-transfer` (final agent review accept-with-minor); the two failed Tailscale rows are unchanged |
| G0.3 Intake and cable | [G03-Intake.md](G03-Intake.md) | [G03-Intake](device-checklists/G03-Intake.md) | `Spikes/G03-Intake/` | accept-with-minor (review 2). At M0 assembly: R2-01 to R2-06 closed, with the later rounds through round 4, on `m0-int-minors-g03-intake` (final agent review accept-with-minor) |
| G0.4 Audio | [G04-Audio.md](G04-Audio.md) | [G04-Audio](device-checklists/G04-Audio.md) | `Spikes/G04-Audio/` | accept-with-minor (review 6). At M0 assembly: R6-01 to R6-06 closed on `m0-int-minors-g04-audio` (final agent review accept-with-minor) |
| G0.5 AI and recovery | [G05-AI.md](G05-AI.md), [G05-Recovery.md](G05-Recovery.md) | [AI](device-checklists/G05-AI.md), [recovery](device-checklists/G05-Recovery.md) | `Spikes/G05-AI/`, `Spikes/G05-Recovery/` | accept-with-minor (AI review 6, recovery review 3). At M0 assembly: AI R6-01 to R6-04 fixed (mutations M59-M62 added, 62 of 62 caught) and recovery R3-01 to R3-05 and its round-4 findings fixed, each on its `m0-int-minors-*` branch (final agent review accept-with-minor); human sign-off pending |
| G0.6 Design tokens on devices | [G06-Design.md](G06-Design.md) | [G06-Design](device-checklists/G06-Design.md) | `Packages/Design/`, `Apps/DesignCatalog/` | accept-with-minor (review 3); design review pending. At M0 assembly: R3-01, R3-02 and finding 18 fixed on `m0-int-minors-g06-design` (final agent review accept-with-minor) |

An "accept-with-minor" verdict is an agent review's judgment that the branch is fit to merge with its listed minor findings still open; it is not a gate pass. Each report's own result table is the gate status: many criteria are **pending-device** or **pending-human**, G0.2 records two **failed** rows (a Tailscale address and a MagicDNS name without an App Transport Security exception), and G0.4 records the plan 19.2 start/resume budget as **failed** on the simulator for long files that stay on precise timing (rows 21 and 33: a cold resume deeper than about 1-1.8 hours into a VBR MP3, and native FLAC and MP3-without-header files beyond a length limit), with quick capture and the shippable-workflow recommendation **partial**.

An agent review's "accept-with-minor" on an `m0-int-minors-*` branch accepts the fixes of the findings named above; any minor findings that review raised stay with the gate, and the fixes are agent-reviewed, human sign-off pending.

[integration-log.md](integration-log.md) records how the gate branches were combined into one tree at M0 integration (G0.4 a day after the other seven) and how the thirteen M0 items below were merged at M0 assembly (section 7): the commit for each, the shared-file requests and their outcomes, and the checks run, including the complete CI runs from a clean tree on the assembled commits (section 7.6).

The M0 deliverables beyond the gates (plan 21.2), each Proposed and agent-reviewed, with human sign-off pending:

- [M0-contracts.md](M0-contracts.md) records the capture-envelope and anchor contracts ([ADR-0016](../ADRs/0016-capture-envelope-and-anchors.md)): how they were checked against what the G0.1, G0.4 and G0.5 spikes write, and what was found. Evidence in `evidence/M0-contracts/`; CI `Scripts/ci.d/11-capture-anchor-contracts.sh`.
- The M0 threat model is [ADR-0015](../ADRs/0015-threat-model.md). Its evidence (the hard-rule audit run by `Scripts/ci.d/13-hard-rules.sh`, and a host probe of the file-protection resource key) is in `evidence/M0-threat-model/`.
- The M0 dependency lock and license inventory: [ADR-0014](../ADRs/0014-dependency-lock-and-license-inventory.md), [`Docs/Licenses/third-party-inventory.md`](../Licenses/third-party-inventory.md); evidence in `evidence/M0-dependencies/`; CI `Scripts/ci.d/12-dependency-lock.sh`. Its final agent review (round 4) rejected the CI import guard with two serious findings still open (R4-01, R4-02; ADR-0014 status).
- [M0-device-runbook.md](M0-device-runbook.md) gathers every pending device and human step of the eight checklists and reports into sessions for the product owner, says which block the M0 gate and which can wait, and lists 56 corrections to the checklists, reports and ADRs (its Section 8; the integration log, section 7, says which were applied to those files at M0 assembly).
- [M0-plan-amendments.md](M0-plan-amendments.md) turns every gate finding into a proposed plan amendment (plan draft 0.5; each change tagged `[M0-Ann]` in the plan and logged in its Appendix D), lists the findings that change nothing, and gives the product owner's open questions with options and recommended defaults. Pending product-owner approval.
- [M0-gate.md](M0-gate.md) is the gate summary for the product owner (15 October 2026): every plan 21.1 criterion, 21.2 deliverable and 22.4 ADR with its status and evidence, the Section 23.1 decisions, the open questions, what remains pending and the recommendation. Agent-written; human sign-off pending.
