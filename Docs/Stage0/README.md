# Stage 0 evidence

Evidence for the feasibility gates in plan Section 21.1 and the M0 deliverables in Section 21.2. Each gate has a report here, raw outputs under `evidence/<gate>/`, and any physical-device steps under `device-checklists/`.

**How to read a result.** Every result names its environment:

- **host:** macOS tests on the build Mac
- **simulator:** iOS runtime and device type
- **device:** physical model and OS version

**pending** means the check needs a physical device, a second device or a person, and has not been run. It is never shown as passed. Reviews done by agents in place of a security, QA or design reviewer are marked "agent-reviewed; human sign-off pending".

| Gate | Report | Spike |
| --- | --- | --- |
| G0.1 EPUB/PDF capture | `G01-EPUB.md`, `G01-PDF.md` | `Spikes/G01-EPUB/`, `Spikes/G01-PDF/` |
| G0.2 Transfer security and background | `G02-Transfer.md` | `Spikes/G02-Transfer/` |
| G0.3 Intake and cable | `G03-Intake.md` | `Spikes/G03-Intake/` |
| G0.4 Audio | `G04-Audio.md` | `Spikes/G04-Audio/` |
| G0.5 AI and recovery | `G05-AI.md`, `G05-Recovery.md` | `Spikes/G05-AI/`, `Spikes/G05-Recovery/` |
| G0.6 Design tokens on devices | `G06-Design.md` | `Packages/Design/`, `Apps/DesignCatalog/` |

The gate summary (`M0-gate.md`) is written at the end of M0 and lists every criterion with its status.
