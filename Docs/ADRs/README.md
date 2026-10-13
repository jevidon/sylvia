# Architecture decision records

Approved decisions for Sylvia (plan Section 22.4). Copy `0000-template.md` for a new record. Numbers are assigned in advance during Stage 0 so parallel workstreams never collide.

"Proposed" means written and agent-reviewed, with the named deciders' approval still pending; none of the Stage 0 records below is approved yet except where its status says so.

| ADR | Title | Status (14 October 2026) | Owner during Stage 0 |
| --- | --- | --- | --- |
| [0001](0001-platform-baseline-and-toolchain.md) | Platform baseline and toolchain | Accepted for the platform floor; toolchain pin awaiting the owner's confirmation | Kickoff |
| [0002](0002-repository-build-and-ci.md) | Repository, build and CI conventions | Accepted for Stage 0; amended at M0 integration (approval of the amendments pending) | Kickoff |
| [0003](0003-persistence.md) | Persistence: GRDB, durability, migrations | Proposed | G0.5 recovery spike |
| [0004](0004-epub-reader-adapter.md) | EPUB reader adapter (Readium) | Proposed | G0.1 EPUB spike |
| [0005](0005-pdf-reading-and-anchors.md) | PDF reading and anchors (PDFKit) | Proposed | G0.1 PDF spike |
| [0006](0006-audio-playback-and-excerpts.md) | Audio playback, edition timeline and excerpt strategy | Proposed; device run and product-owner decisions pending (release codec list, per-file timing mode, import remux) | G0.4 audio spike |
| [0007](0007-quick-capture-evaluation.md) | Quick-capture surfaces outside the player | Proposed; device run pending (quick capture is not advertised until its device steps pass) | G0.4 audio spike |
| [0008](0008-pairing-and-transport-security.md) | Pairing and transport security | Proposed; security sign-off pending | G0.2 transfer spike |
| [0009](0009-transfer-protocol.md) | Transfer protocol, manifests and resumability | Proposed | G0.2 transfer spike |
| [0010](0010-intake-handoff-and-wired-bundles.md) | Intake handoff and wired bundles (`.sylviapack`) | Proposed | G0.3 intake spike |
| [0011](0011-ai-providers-context-and-privacy.md) | AI providers, context packs and privacy | Proposed | G0.5 AI spike |
| [0012](0012-retention-backup-restore.md) | Retention, backup and restore | Proposed | G0.5 recovery spike |
| [0013](0013-design-language.md) | Design language: tokens, Literata, Dynamic Type, grayscale method | Proposed; design review on devices pending | G0.6 design package |
| [0014](0014-dependency-lock-and-license-inventory.md) | Dependency lock and license inventory | Proposed (G0.4, merged 14 October 2026, adds no package) | M0 integration |
| 0015 | Threat model | Not written yet | M0 integration |
