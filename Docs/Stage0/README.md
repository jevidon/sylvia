# Stage 0 evidence

Evidence for the feasibility gates in plan Section 21.1 and the M0 deliverables in Section 21.2. Each gate has a report here, raw outputs under `evidence/<gate>/`, and any physical-device steps under `device-checklists/`.

**How to read a result.** Every result names its environment:

- **host:** macOS tests on the build Mac
- **simulator:** iOS runtime and device type
- **device:** physical model and OS version

**pending** means the check needs a physical device, a second device or a person, and has not been run. It is never shown as passed. Reviews done by agents in place of a security, QA or design reviewer are marked "agent-reviewed; human sign-off pending". Timings taken while other agents were building on the same Mac are indicative only and say so, with the load recorded next to them.

| Gate | Report | Device and human steps | Spike | Final review (agent) |
| --- | --- | --- | --- | --- |
| G0.1 EPUB/PDF capture | [G01-EPUB.md](G01-EPUB.md), [G01-PDF.md](G01-PDF.md) | [EPUB](device-checklists/G01-EPUB.md), [PDF](device-checklists/G01-PDF.md) | `Spikes/G01-EPUB/`, `Spikes/G01-PDF/` | accept-with-minor (EPUB review 3, PDF review 2) |
| G0.2 Transfer security and background | [G02-Transfer.md](G02-Transfer.md) | [G02-Transfer](device-checklists/G02-Transfer.md) | `Spikes/G02-Transfer/` | accept-with-minor (review 3); security sign-off pending |
| G0.3 Intake and cable | [G03-Intake.md](G03-Intake.md) | [G03-Intake](device-checklists/G03-Intake.md) | `Spikes/G03-Intake/` | accept-with-minor (review 2) |
| G0.4 Audio | [G04-Audio.md](G04-Audio.md) | [G04-Audio](device-checklists/G04-Audio.md) | `Spikes/G04-Audio/` | accept-with-minor (review 6) |
| G0.5 AI and recovery | [G05-AI.md](G05-AI.md), [G05-Recovery.md](G05-Recovery.md) | [AI](device-checklists/G05-AI.md), [recovery](device-checklists/G05-Recovery.md) | `Spikes/G05-AI/`, `Spikes/G05-Recovery/` | accept-with-minor (AI review 6, recovery review 3) |
| G0.6 Design tokens on devices | [G06-Design.md](G06-Design.md) | [G06-Design](device-checklists/G06-Design.md) | `Packages/Design/`, `Apps/DesignCatalog/` | accept-with-minor (review 3); design review pending |

An "accept-with-minor" verdict is an agent review's judgment that the branch is fit to merge with its listed minor findings still open; it is not a gate pass. Each report's own result table is the gate status: many criteria are **pending-device** or **pending-human**, G0.2 records two **failed** rows (a Tailscale address and a MagicDNS name without an App Transport Security exception), and G0.4 records the plan 19.2 start/resume budget as **failed** on the simulator for long files that stay on precise timing (rows 21 and 33: a cold resume deeper than about 1-1.8 hours into a VBR MP3, and native FLAC and MP3-without-header files beyond a length limit), with quick capture and the shippable-workflow recommendation **partial**.

[integration-log.md](integration-log.md) records how the gate branches were combined into one tree at M0 integration (G0.4 a day after the other seven): the commit for each gate, the shared-file requests and their outcomes, and the checks run. The gate summary (`M0-gate.md`) is written at the end of M0 and lists every criterion with its status.
