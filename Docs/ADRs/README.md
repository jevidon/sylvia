# Architecture decision records

Approved decisions for Sylvia (plan Section 22.4). Copy `0000-template.md` for a new record. Numbers are assigned in advance during Stage 0 so parallel workstreams never collide.

"Proposed" means written and agent-reviewed, with the named deciders' approval still pending; none of the Stage 0 records below is approved yet except where its status says so.

| ADR | Title | Status (20 October 2026) | Owner during Stage 0 |
| --- | --- | --- | --- |
| [0001](0001-platform-baseline-and-toolchain.md) | Platform baseline and toolchain | Accepted for the platform floor; toolchain pin awaiting the owner's confirmation | Kickoff |
| [0002](0002-repository-build-and-ci.md) | Repository, build and CI conventions | Accepted for Stage 0; amended at M0 integration and M0 assembly (approval of the amendments pending), and on 19 October 2026 by the Git LFS adoption the product owner decided on 13 October 2026 (verified by an agent review whose verdict has no committed record; its three minor fixes, and the M0 final fix's CI amendments of 19 and 20 October 2026 (the latter the G0.4 drop-in's host audio precondition), not yet reviewed again; human sign-off pending) | Kickoff |
| [0003](0003-persistence.md) | Persistence: GRDB, durability, migrations | Proposed | G0.5 recovery spike |
| [0004](0004-epub-reader-adapter.md) | EPUB reader adapter (Readium) | Proposed | G0.1 EPUB spike |
| [0005](0005-pdf-reading-and-anchors.md) | PDF reading and anchors (PDFKit) | Proposed | G0.1 PDF spike |
| [0006](0006-audio-playback-and-excerpts.md) | Audio playback, edition timeline and excerpt strategy | Proposed; device run and product-owner decisions PO-1 to PO-5 pending (release codec list, per-file timing mode, import remux, mono excerpts, playback-control defaults) | G0.4 audio spike |
| [0007](0007-quick-capture-evaluation.md) | Quick-capture surfaces outside the player | Proposed; device run and product-owner decision PO-6 (the narrowing) pending (quick capture is not advertised until its device steps pass) | G0.4 audio spike |
| [0008](0008-pairing-and-transport-security.md) | Pairing and transport security | Proposed; security sign-off pending | G0.2 transfer spike |
| [0009](0009-transfer-protocol.md) | Transfer protocol, manifests and resumability | Proposed | G0.2 transfer spike |
| [0010](0010-intake-handoff-and-wired-bundles.md) | Intake handoff and wired bundles (`.sylviapack`) | Proposed | G0.3 intake spike |
| [0011](0011-ai-providers-context-and-privacy.md) | AI providers, context packs and privacy | Proposed | G0.5 AI spike |
| [0012](0012-retention-backup-restore.md) | Retention, backup and restore | Proposed | G0.5 recovery spike |
| [0013](0013-design-language.md) | Design language: tokens, Literata, Dynamic Type, grayscale method | Proposed; design review on devices pending | G0.6 design package |
| [0014](0014-dependency-lock-and-license-inventory.md) | Dependency lock and license inventory | Proposed; G0.4 adds no package; license and security decisions pending (ADR-0014 section 7). Its final agent review (round 4) rejected the CI import guard with two serious findings open (R4-01, R4-02; integration log section 7), to be closed before the M1 app target is created, or before any product target links Readium if that comes first | M0 integration |
| [0015](0015-threat-model.md) | Threat model | Proposed; security sign-off pending (agent-reviewed as merged; its revisions of 19 and 20 October 2026, the latter the audit's trust and TLS patterns, not reviewed again) | M0 integration |
| [0016](0016-capture-envelope-and-anchors.md) | Capture envelope and anchors (portable contracts v1) | Proposed; revised on 19 October 2026 at the M0 final fix (rule A3 and two records, section 11) and on 20 October 2026 at its second round (A3 checked in linear time); neither revision reviewed again | M0 integration (contract consolidation) |
