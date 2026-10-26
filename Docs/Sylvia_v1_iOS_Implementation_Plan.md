# Sylvia
## V1 iOS implementation plan
### Your library of thought.

**Status:** Draft 0.8 - the product owner's decisions of 22 October 2026 on the M0 gate's questions recorded: the amendments of drafts 0.5 and 0.7 (`Docs/Stage0/M0-plan-amendments.md`) and the Section 23.1 decisions D01-D17 are approved by the product owner, as recommended except where the owner chose otherwise (PO-13, PO-23, PO-33, PO-39 and D-1; Appendix D); and the owner's answers of 23 October 2026 on what those decisions left open (PO-12's sources file and import ledger, PO-41 to PO-44, the iPad) are recorded within this draft (Appendix D). It sits on top of draft 0.7, draft 0.5's re-check against the gate reports and ADRs as merged at M0 assembly (19 October 2026), draft 0.6, the product owner's Gloss-informed M3/M5 interaction direction and a later web-reader roadmap (15 October 2026; approved product direction, written on main as its draft 0.4), and draft 0.5, the amendments from the Stage 0 results (14 October 2026). Stage 0 (M0) in progress: approving a decision is not a device result, so every gate's device and human steps are still pending, and so are the role sign-offs of Section 23.3, which the product owner gives personally once the device sessions have produced their evidence. Not yet the versioned 1.0 execution specification: Section 23.3 says that follows the M0 exit, which waits for the device sessions.  
**Prepared:** 5 October 2026 · **Revised:** 23 October 2026 (6 October: design language folded in, draft 0.2; product-owner decisions and Section 4.4 consistency fixes recorded, draft 0.3. 7 October: unified content hub added to the roadmap, draft 0.4. 14 October: amendments from the Stage 0 results proposed at the M0 gate, pending product-owner approval, draft 0.5. 15 October: Gloss-informed M3/M5 interactions and later web-reader roadmap, draft 0.6. 19 October: the merge of the M0 work into main recorded as a fact, draft 0.6 unchanged otherwise; draft 0.5's amendments re-checked against the merged gate reports and ADRs, draft 0.7, pending product-owner approval. 20 October: draft 0.7 corrected within its tags; the toolchain pin in Section 6.3 changed to Xcode 27.1 by the product owner's decision of PO-35, as ADR-0001 records the reading of the owner's reply. 22 October: the product owner's decisions on the M0 gate's questions recorded, draft 0.8. 23 October: the product owner's answers on what those decisions left open recorded within draft 0.8, and three of those records corrected the same day after an agent review. See Appendix D)  
**Product owner:** Justin Evidon  
**Delivery boundary:** Native iPhone/iPad application, iOS share extension, lightweight macOS transfer companion, portable data and transfer contracts. No mandatory service.  
**Source of truth:** Agreed product discussion, *Sylvia - Product Brief*, and the *Sylvia Concept Designs* boards in `Docs/Design/` for visual language. Technical recommendations below are proposals unless explicitly identified as confirmed. [P1, P2]

> **The release must prove one complete loop:** get a book onto the device reliably; read or listen offline; capture a passage and your thinking; ask a source-aware question when a model is reachable; then find that knowledge after the original media has been removed.

This is a greenfield implementation proposal, not an audit of an existing repository. Drafts 0.1 to 0.4 were written before any app code, performance result, platform spike or compatibility test existed. Draft 0.5 proposed amendments from the Stage 0 feasibility spikes (Section 21.1), which ran on the build Mac and the iOS Simulator only: their reports and evidence are in `Docs/Stage0/`, every physical-device and human step is still pending, and no product feature has been built beyond the `SylviaDesign` v0.1 package. Requirements, interfaces, recovery rules and acceptance criteria are specified for review; the feasibility stage must validate the risky platform assumptions before feature implementation begins, and each milestone, M1 included, starts only after the device steps of the gates it builds on have passed (Section 21.1; decided by the product owner on 22 October 2026, PO-34). [M0-A01] [M0-A46] Draft 0.6 adds the product owner's 15 October direction for M3/M5 interactions and a later web reader. It was written on main independently of the M0 work, which main links as [P3], and it changes no M0 gate result or pending amendment. Draft 0.7 re-checked draft 0.5's amendments against the gate reports and ADRs as merged at M0 assembly: it corrected what the merged evidence contradicts and added three amendments. Draft 0.8 records the product owner's decisions of 22 October 2026: the amendments of drafts 0.5 and 0.7 are approved, except where the owner chose otherwise, and the text the recommendations drove is changed there (Appendix D). No requirement in this plan is a claim that a feature or feasibility gate has passed, and no decision recorded here is a device result.

# 1. Executive recommendation

Build a **local-first native application**, not a client for a future server. Its private database owns the user's catalog, consumption ledger, annotations and saved AI interactions. Imported media is replaceable storage attached to that record. The Mac companion is a source and transfer utility, not the owner of the user's knowledge.

Use Swift/SwiftUI for the application, a Readium adapter for EPUB, PDFKit for text-based PDF interaction, AVFoundation for local audio, and SQLite through GRDB for durable structured storage. Keep product entities and serialized contracts independent of those frameworks. This makes later Android development practical without pretending that SwiftUI screens or AVFoundation implementations are portable. Readium, GRDB and SQLite provide the underlying reading/data capabilities; their exact releases are pinned at the M0 gate (Readium 3.11.0 and GRDB 7.11.1 over the system SQLite; ADR-0002, with the full lock in ADR-0014), approved by the product owner on 22 October 2026 with decision D02, the technical lead's sign-off pending until the device evidence (Section 23.1). [S1-S4] [M0-A01]

**The proposed release includes** the permanent ledger, EPUB/PDF reading, common audiobook playback, text highlights and notes, durable short audio captures, user-configured AI, local search, direct imports, a Mac source browser, resumable app-controlled LAN transfers, Finder-based wired imports, and knowledge backup/restore. A connected model is optional for using every non-AI feature.

**The proposed release does not include** Docker hosting, automatic cross-device state synchronization, RSS/Atom subscriptions, newsletter email ingestion, Calibre database integration, physical-page OCR, Spotify/Audible capture, precise audiobook/EPUB alignment, automatic full-book transcription, on-device language-model inference, or autonomous agent actions. The underlying data model leaves room for these, but no placeholder feature should imply that they already work.

The important decisions requiring explicit team approval are collected in Section 23. In particular, approve the proposed minimum OS versions, audio transcription scope, lock-screen clipping boundary, source-content retention defaults and transfer security design. These were not all settled in the discovery conversation. *(22 October 2026: the product owner approved them with every Section 23.1 decision, D01-D17; the role sign-offs of Section 23.3 are pending until the device sessions have produced their evidence.)*

## 1.1 What is confirmed versus proposed

**Confirmed:** Sylvia; native iOS first; eventual broader platform support; standalone use without an account/server; a lightweight Mac companion; direct, LAN and wired import; one-time pairing; 5,000+ titles; Work -> Edition -> Asset; English and DRM-free content first; passage-focused annotation; EPUB/audiobook association; retention of learning records after media removal; optional configurable AI and optional Hermes; Docker deferred. [P1] **Also confirmed (6 October 2026):** the *Marginalia* design language direction described in Section 4.4, chosen by the product owner after reviewing four alternatives; its exact token values remain proposals until checked on devices in Stage 0. [P2] **Also confirmed (6 October 2026, before Stage 0):** the product owner approved the Section 23.1 decision defaults D02-D15 as proposed and amended D01 to iOS/iPadOS 26+ and macOS 26+; chose Inbox row layout B (Section 4.1); and chose Sylvia's own opaque navigation chrome over the system's translucent bars (Sections 4.4.2, 4.4.7). Decisions that also name a technical, security, QA or design owner still need that confirmation through the Stage 0 evidence and ADRs. *(22 October 2026: the product owner has since approved every Section 23.1 decision, D01-D17; the technical, security, QA and design confirmations are the role sign-offs of Section 23.3, which the product owner gives personally, each once the device sessions have produced the evidence it signs, and which are pending until then.)*

**Proposed in draft 0.2, approved as defaults by the product owner on 6 October 2026, and still subject to Stage 0 evidence:** iOS/iPadOS 26+ and macOS 26+ (amended from 18+ and 14+); iPhone-led design with a functional adaptive iPad layout; GRDB and Readium; the precise import/transfer protocol; a five-star rating with half-star steps; no automatic media eviction; short-clip transcription through an optional speech endpoint; explicit knowledge export and restore in v1; no cloud/state sync; minimal status-based organization rather than a fixed taxonomy; the Marginalia token values, type roles and component inventory in Section 4.4.

**Proposed at the M0 gate (draft 0.5) and approved by the product owner on 22 October 2026 (draft 0.8):** the amendments the Stage 0 results call for, each tagged [M0-Ann] in the text and listed in Appendix D, with its evidence in `Docs/Stage0/M0-plan-amendments.md`. The product owner decided their questions (PO-01 to PO-44 there, D-1 to D-10 in `Docs/Stage0/M0-device-runbook.md` Section 6) as recommended, except PO-13 (Section 15.1), PO-23 (Sections 20.2, 21.1 and 21.2), PO-33 (Section 4.2), PO-39 (Section 10.1) and D-1 (Section 19.1), where the text now says what the owner chose and what it replaced. Rows failed in four gates on the simulator, and each failure changes the approach before downstream work (Section 21.1): the highlight overlay on PDF text drawn with a rotated text matrix (Section 9.2; found after draft 0.5 was written and proposed in draft 0.7) [M0-A54], Tailscale address forms under App Transport Security (Section 15.1, D16), the start/resume budget for long audio files that stay on precise timing (Sections 10.1 and 19.2), and `UIFontMetrics` scaling (Section 4.4.3). Every narrowing of release scope in draft 0.5 was a proposal. Some are forced by a failed or narrowed spike; each of the others, which no failed spike forces, was named in the text as a product-owner decision beside the alternative that keeps the plan's scope, so approving draft 0.5 did not by itself approve it: the product owner decided each of them explicitly on 22 October 2026, as recommended (PO-05, PO-16, PO-27, PO-30, PO-31, PO-32 and PO-36). Appendix D lists both kinds. Approving them approves no device result: every device and human step is still pending. Draft 0.8 changes the wording where a sentence carries an amendment or the pending text of a question decided on 22 October 2026; text kept from drafts 0.1 to 0.4 still calls some defaults proposed, and where such a default belongs to a Section 23.1 decision, that decision's approval covers it until the versioned 1.0 specification restates it (Section 23.3). [M0-A01]

**Still open by design:** user-facing categorization, commercial model, production distribution and pricing. The engineering plan must not silently resolve these as subscriptions, a complex tagging system, or a hosted account service.

**Confirmed direction (15 October 2026):** native iOS/iPadOS V1 and its lightweight Mac companion remain first. M3 and M5 refine passage capture, asking and source navigation using Gloss as an interaction reference; a browser-based reader is a separate post-V1 roadmap workstream (Section 24). This direction does not approve any pending M0 amendment, change the release's platforms or add accounts, state synchronization, web search or article ingestion to V1. [P3]

**Implementation reference:** the M0 feasibility work reviewed on `m0-integrate` (native reader/anchor, AI/context, intake/transfer, audio and recovery spikes, plus a design package and interaction prototype [P3]) was merged into `main` on 15 October 2026, and the M0 gate is pending approval. Evaluate that work for promotion through the normal milestone gates. Gloss informs interaction design and later article extraction; fit those ideas to Sylvia's planned native domain, evidence, provider and persistence architecture. Reconcile the recorded spike-to-product gaps before reuse, and avoid rebuilding its Markdown/JSON export without first assessing it for M7. No effort reduction or M0 approval is assumed from this comparison.

# 2. Product goals and release invariants

## 2.1 Goals

Sylvia should turn reading and listening into a durable personal knowledge record. Priority follows the user's stated order: permanent history; better capture; contextual AI; dependable transfer; a unified reader/player; control over source files; reduced lock-in. Do not trade capture reliability or data preservation for additional formats or an elaborate AI interface.

Support an individual with a large collection, but do not require all 5,000+ media files or all extracted text to live on the phone. A local catalog of 5,000-10,000 works, a substantial annotation corpus and a user-selected media working set are the release-scale targets. A future server may retain much more media.

## 2.2 Non-negotiable invariants

**I-01 - Standalone operation.** First launch, file import, reading, listening, capture, editing, search and export work without creating a Sylvia account or configuring a server/model.

**I-02 - A file is not a work.** Removing bytes changes local availability, not bibliographic identity, reading history, ratings, recommendations or knowledge artifacts.

**I-03 - Durable acknowledgement.** The interface says "Saved" only after a durable local write succeeds. A background task being scheduled is not the same as the operation completing.

**I-04 - No false completion.** A staged or partial import is not offered as a ready book. A cancelled or truncated AI response is not displayed as a completed answer. A timestamp without words is not presented as a quotation.

**I-05 - Source fidelity.** Every captured quotation preserves the exact captured text plus an edition-specific anchor. Generated explanations and paraphrases remain distinct from quotations.

**I-06 - Honest context.** AI requests disclose the endpoint and context scope. A companion EPUB is not evidence of exact alignment to the current audio moment. A valid citation link is not proof that a model's interpretation is correct.

**I-07 - No hidden cloud escalation.** Loss of a local endpoint never causes automatic fallback to a hosted provider. No content or personal notes are sent until the user has authorized the destination and scope.

**I-08 - External sources are not modified.** Imports copy into Sylvia-managed storage. Removing a local download does not delete or reorganize Mac, Calibre or future server originals.

**I-09 - Recoverability.** The permanent record can be exported and restored without a running Sylvia service. Media excluded from a backup is explicitly identified.

**I-10 - Honest platform behavior.** Background execution and networking are subject to iOS scheduling; the app must recover from suspension, termination and failed transfers rather than promise uninterrupted execution.

The design language in Section 4.4 is the visible form of I-03 through I-06: the status vocabulary enforces I-03 and I-04 on screen, and the marker set enforces I-05 and I-06 by making a quotation, a note, an audio moment and a generated answer visually and semantically distinct.

# 3. Scope and capability boundary

## 3.1 Release surface

| Area | V1 commitment | Explicit boundary |
| --- | --- | --- |
| Native clients | iOS/iPadOS app; share extension; lightweight Mac companion | No Android, Windows or Linux client in this release |
| Standalone library | Local catalog, manual entries, editions/assets, basic metadata editing | No mandatory central catalog or account |
| Reading | Reflowable EPUB, text-based PDF, basic UTF-8 TXT/Markdown | No advanced PDF editing, scanned-PDF OCR, scripted or fixed-layout EPUB, or EPUB content outside the documented subset (Section 8.3) [M0-A03] |
| Listening | M4B/M4A with tested supported codecs, MP3, ordered multi-file books | No streaming-service imports, format conversion farm or format-by-extension guarantees |
| Capture | Text highlights, comments, bookmarks, vocabulary, short local audio excerpts | No automatic exact audio/text alignment; no silent whole-book transcription |
| AI | OpenAI, Anthropic and generic compatible endpoints; saved source-linked conversations | No assumption that consumer subscriptions include API access; no autonomous tools |
| Transfer | Files, share, AirDrop handoff, direct file URL, Mac LAN pull, wired Finder route | No custom USB driver; no phone-as-always-on-upload-server |
| Search | Catalog and saved knowledge globally; local extracted text per work | No mandatory embeddings or server-based semantic search |
| Portability | Human-readable export and versioned backup/restore | No live multi-device conflict resolution in v1 |
| External consumption | Manually created physical/external records, manual progress and quotes | Camera capture and external playback observation deferred |

Common formats accepted during discovery remain the target direction. **The release-supported codec matrix is a proposed narrowing, not a claim that every AAC, FLAC or Opus file is supported.** Stage 0 must test representative files, including seek, chapters and clip extraction; only passing combinations go on the release support list. Additional natively supported formats may be admitted without conversion only after the same tests pass. Stage 0 result on the simulator (device run pending): 16 of 17 tested container and codec combinations pass the playback, duration, chapter, seek and excerpt tests: MP3 (constant bit rate; variable bit rate with and without a Xing/VBRI header; with ID3 chapters; and a real 22.05 kHz LibriVox file), AAC-LC, HE-AAC v1 and v2 and ALAC in M4A, FLAC native and in MP4, Opus in Ogg (`.ogg` and `.opus`), MP4 and CAF, and WAV. Opus in WebM cannot be opened and is excluded. FLAC, Opus and WAV join the release list only if the device run passes them: the product owner decided on 22 October 2026 to admit each one that passes, with its limits stated (PO-18); a WAV book has no chapters, and Opus in CAF has untested chapters. Long files that stay on precise timing are slow to resume (Section 10.1). [M0-A23]

## 3.2 Default feature flags

Enabled for release: core reader/player, source-free records, capture, export, provider setup, direct import, LAN companion and Finder guide. AI remains inactive until configured. Clip transcription remains inactive until a speech endpoint is configured and authorized.

Disabled/absent: full transcription, external-service capture, OCR, feeds, email, cross-device sync, rich taxonomy, automatic eviction, cloud relay and remote agent actions. Use flags for safe development and rollback, not to ship misleading unfinished menus.

## 3.3 Specific scope reconciliations

The earlier ideal story included clipping from the lock screen. V1 must ship standard lock-screen/headphone playback controls; a dedicated quick-capture surface is a **separate feasibility gate**, not an assumed Media Player capability. Proposed baseline is one-tap capture inside the player and an approved shortcut/control only if its execution and save semantics pass Stage 0. The team must approve this narrowing before execution. [S8-S9] Stage 0 result (G0.4, simulator, unlocked; device steps pending): the only plausible surface is an App Intent that adopts `AudioPlaybackIntent`, so that the system performs it in the playing app's process, offered as a Control (Control Center, Lock Screen, Action button) and as an App Shortcut; on the simulator both ran through the system and saved before acknowledging (the App Shortcut only in a team-signed build). The bookmark remote command (reportedly not shown since iOS 16) and Live Activity buttons (documented as inactive while locked) are not adopted. Decided by the product owner on 22 October 2026 (D03; PO-17 (a)): the in-player Capture button is the release baseline, and quick capture is advertised only after its device steps pass (G0.4 steps 8-13, pending), locked behavior included; an App Group fallback is funded only if the device shows the intent performed outside the app's process; adopting `AudioPlaybackIntent` for an action that plays no audio carries an App Review risk (Section 23.2). [M0-A26]

The earlier browser-uploader concept is not required alongside the native Mac companion. Choose Mac-hosted pull as the supported v1 network path, avoiding two independent transfer implementations. A browser uploader can be added later if demand justifies it.

RSS/newsletter support - and the wider goal of one home for articles, feeds and Substack content, including their listen links - is retained in the phased roadmap (Section 24) and model extension points, not silently added to this release. An arbitrary webpage URL is not the same as a downloadable EPUB/PDF/audio URL.

# 4. User experience and end-to-end flows

## 4.1 Navigation

Use three primary areas: **Library**, **Thoughts**, and **Inbox**. Global search searches catalog and retained knowledge with clear result types. Settings contains AI connections, trusted sources, storage, backup/export and diagnostics. A mini-player persists above navigation while audio is active and carries a capture control, so a moment can be kept from any screen (Section 4.4.7).

**Library:** recently active works, status filters, available-on-device filter and list/grid toggle. A work detail screen shows editions, available assets, current position, history, rating, recommendation events and associated knowledge. Avoid a shelf full of duplicate entries just because an EPUB and audiobook are both present. Works without cover art use the typographic cover fallback (Section 4.4.7), so a record with no file never looks broken.

**Thoughts:** quotations, comments, audio captures, saved vocabulary and saved AI answers. Default ordering is recent activity, with per-work filtering and search. AI answers are not made equivalent to the user's own notes; each capture kind uses its marker treatment from Section 4.4.5. No forced topic taxonomy; categories remain a future product decision.

**Inbox:** pending local imports, items available from a paired Mac, duplicates needing review and failed jobs. Transfer states use the fixed vocabulary of Section 4.4.6: queued, receiving, verifying, preparing, ready, needs attention. Do not make users inspect a developer log to finish an import.

Inbox rows use the compact layout chosen on 6 October 2026 (board *Inbox rows, option B* in `Docs/Design/`): title and kind; a status pill with a one-line detail; one trailing action (Pause, Open or Resolve) or a disclosure chevron; transfer progress drawn as a rule along the row's bottom edge. A Needs attention row's trailing action is Resolve, which opens a detail view with the full reason and every next step, so the row itself never has to hold two actions. At accessibility text sizes the detail line wraps instead of truncating and the trailing action moves below it (T51).

**Reader/player:** one consistent capture sheet with source preview, quote or audio range, comment, lookup, Ask AI and save status. The interaction must be usable one-handed on iPhone and adapt to a side pane on iPad without requiring a separate iPad product.

**Passage and discussion:** M3 keeps the selected quotation and its source available while a reader writes a note, then returns to the same reading position. M5 extends this flow to questions, answers and follow-ups attached to that passage. Use the existing sheet on iPhone and the reader's side pane on iPad when there is sufficient space; compact layouts may use a sheet. Keep the passage visible where it fits, with an accessible expandable preview when the keyboard or large text needs the space. Compact presentation must not truncate saved text or reduce touch targets. Preserve Marginalia's distinct Quote, Note and Generated treatments. The four selection actions remain Highlight, Note, Look Up and Ask; the AI question starters belong inside Ask (Section 13.1). [P3, S25]

## 4.2 Onboarding

Start with "Import a book", "Connect a Mac" and "Add a record". Offer bundled, licensed short samples for trying capture without networking. The product owner decided on 22 October 2026 (PO-33) that three ship in M2, each a short excerpt of a Standard Ebooks (CC0) edition: *Middlemarch*, *Walden* and *Meditations*, each clearly marked as a sample and removable like any other item. *Meditations* is paired with an excerpt of its LibriVox recording (public domain), an audio edition of the same work associated with the text, not aligned to it (Section 7.1, I-06), so that onboarding can show listening and audio capture as well, once the player exists (M4). Their provenance is recorded in `Fixtures/LICENSES.md`. (Until 22 October 2026 this section asked for one sample, and the recommendation was one short Standard Ebooks excerpt, such as the prototype's Middlemarch passage; the owner chose all three, with the audio pairing.) Explain that AI is optional; do not start with API keys. Ask local-network/camera access only in the pairing workflow that needs it. Explain what remains on the device, and expose backup setup after the first meaningful saved item.

AI onboarding chooses a provider type, endpoint if relevant, model, credential and privacy mode. A connection test sends synthetic text, not the current book. Show API billing versus consumer subscription clearly. ChatGPT and Claude consumer plans are separate from their API billing; no unsupported subscription-login workaround is part of this design. [S14-S15]

## 4.3 Golden journeys

**J-01 - Offline reading.** Import an EPUB through Files; open it; change font size; select a passage; save a quote and comment; close and relaunch offline; return to the same passage from Thoughts. No AI setup required.

**J-02 - Audio learning.** Import a multi-file audiobook; confirm order; listen with the screen locked; return to the player and capture the preceding 30 seconds; add a note. Replay that excerpt without moving the main listening position. With a configured speech service, transcribe the excerpt and ask about it. Without one, the playable capture and note still work.

**J-03 - Paired context.** Associate an EPUB with an audiobook's work; select a relevant EPUB passage or search the text; ask a question. The interface states whether the text was manually chosen or retrieved and does not imply it was automatically aligned to playback.

**J-04 - Knowledge after media removal.** Finish a book, rate it and record an outbound recommendation. Remove the full audiobook. Search a phrase from a saved note; open the quote, clip, source details and saved AI evidence offline. Reimport the original later without creating a duplicate work.

**J-05 - Reliable large transfer.** Pair with a Mac; choose a large audiobook; interrupt the network; relaunch the app; resume verified chunks; verify the final file; import exactly once. Finish a separate wired transfer through Finder and the same import validator.

**J-06 - Recovery.** Export knowledge, reset a test installation, restore, and recover works, edition anchors, history, recommendations, clips, quotes, notes and conversations. Missing full media is shown as unavailable, not as a corrupt record.

## 4.4 Design language: Marginalia

Marginalia is the visual and verbal system for every Sylvia surface: iPhone, iPad, the share extension's handoff screens and the Mac companion. It was developed as the *Sylvia Concept Designs* boards, checked in under `Docs/Design/` as rendered images and board source; they remain the visual reference for the screens described in this plan, and this section is the normative specification. [P2] Where the boards and this section disagree, this section wins and the boards are corrected.

The name describes the arrangement: a book carries its meaning in the text, and its reader's meaning in the margin. The interface is a quiet page on which the reader's own marks are the brightest thing.

### 4.4.1 Principles

Five rules decide every screen. When a design question comes up, one of these should settle it.

| # | Principle | What it means | Serves |
| --- | --- | --- | --- |
| 1 | Paper, not panels | One warm ground, hairline rules, flat surfaces. Depth appears only on sheets and the mini-player, the two objects that float above the page. Cards never nest. | UX-01; performance budgets in Section 19 (no layered blur or shadow during scrolling) |
| 2 | Ink first | Hierarchy comes from type, weight and spacing. Color is reserved for meaning: one action accent, one highlight accent, and the marker set. Never decoration. | UX-01 |
| 3 | A quote is not a note is not an answer | Each capture kind has its own glyph, label, typeface treatment and tint. Color never works alone, so the distinction survives colorblindness, grayscale displays and VoiceOver. | I-05, I-06, KNOW-01, AI-02 |
| 4 | Say what is true | A fixed status vocabulary (4.4.6) tied to the state machines in Sections 8, 10, 14, 15 and 17. "Saved" only after a durable write. "Ready" is not "indexed". "Generated" is always labelled. | I-03, I-04, I-06, UX-01 |
| 5 | Reachable with one thumb | Primary actions in the lower half of the screen. Targets 44pt or larger. Anything draggable also has a numeric control. Dynamic Type everywhere, including the reader, with the bounded exceptions of Section 4.4.3, which the product owner decided on 22 October 2026 (for example, bars stop growing at xxxLarge and use the large content viewer, as system bars do; PO-31) [M0-A40]. | UX-01, Section 18.3 |

### 4.4.2 Color tokens

Two accents of similar lightness carry the brand: **Pine** for actions and the user's own notes, **Ochre** for highlights and exact quotations. A separate, muted marker set names the other capture kinds and statuses. Every text color must meet 4.5:1 against its ground (3:1 at 24pt and above) in both appearances; the values below were checked at authoring time and must be re-verified in the asset catalog during M0. G0.6 verified every token pair in the compiled asset catalog on the host and the simulator (176 of 176 pass, lowest 4.52:1); the device check is pending. [M0-A41]

**Ground and ink**

| Token | Light (Paper) | Dark (Night) | Use |
| --- | --- | --- | --- |
| `ground` | #F4F2ED | #161512 | Screen background |
| `surface` | #FBFAF7 | #1E1C19 | Cards, bars, sheets |
| `ink` | #1C1B18 | #ECE7DD | Primary text, icons |
| `muted` | #6B6760 | #A8A298 | Captions, metadata, inactive tabs |
| `hairline` | ink at 12% | ink at 14% | 1pt rules and borders (approved by the product owner on 22 October 2026, design review pending; was 1px) [M0-A41]; raised to 24% under Increase Contrast |
| `pine` | #2F5D50 | #7FB5A3 | Primary action, links, progress, active tab, Note marker |
| `pine.on` | #F4F2ED | #161512 | Text on a Pine fill |
| `pine.tint` | #DCE8E2 | #233A33 (derived) | Ready pill, Note-related fills |
| `ochre` | #8A5410 | #D9A24A | Quote marker, highlight underline, rating stars |
| `ochre.tint` | #F1E4C8 | #3A2E17 | Highlight fill, Quote block fill |

**Marker set**

| Marker | Light text | Dark text | Light tint | Dark tint (derived) | Carries without color |
| --- | --- | --- | --- | --- | --- |
| `quote` | #8A5410 | #D9A24A | #F1E4C8 | #3A2E17 | Opening quotation-mark glyph; Literata; tinted block |
| `note` | #2F5D50 | #7FB5A3 | none | none | Pen-nib glyph; system face; no tint |
| `audio` | #3F5A78 | #8FB0D4 | #DCE4EE | #26323E | Waveform glyph; block with a play control; never rendered as text |
| `generated` | #6B4E8E | #B49BD6 | #E7DFF0 | #2E2838 | Prompt glyph; dashed 1pt frame [M0-A41]; the word "Generated"; citation chips |
| `attention` | #A63D2F | #E0837A | #F3DCD7 | #3A2522 | Triangle glyph; always paired with a reason and a next step |
| `pending` | #6B6760 | #A8A298 | #ECE9E2 | #2A2824 | Dot glyph; quiet by design |

Dark tints marked "derived" are the marker text color at approximately 14% over Night and are to be set in the asset catalog, not hard-coded. Tint fills carry no text of their own except the marker's own color; body text on a tint remains `ink`. Muted text is never set on a tint: it falls below 4.5:1 on seven of the eight Paper tints (4.29-4.64:1), so a caption inside a tinted block uses `ink` or the marker's own color. [M0-A41]

**Dark tints (design review pending).** The dark tints printed above do not follow the 14% rule they cite. Composited exactly, the rule gives `pine.tint` #252B26, Quote and Word #31291A, Audio #272B2D, Generated #2C282D, Attention #322421 and Pending #2A2925, which `SylviaDesign` v0.1 ships (ADR-0013). `ochre.tint` dark is printed above without "(derived)", and as a literal in Appendix A.5. Design chooses the rule's values or the printed ones; these tables and A.5 are then corrected to match. [M0-A41]

**Rules**

- One Pine primary action per screen. Destructive actions use `attention` as a hairline button and never sit beside a primary.
- Color is never the only carrier of meaning. Every marker and status also has a glyph and a label (4.4.5, 4.4.6). This is verified by T53.
- Covers without artwork use five muted fields assigned by a stable hash of the work title: #2F5D50, #5A6B4A, #7A4B3A, #3F5A78, #4A4A58, with Paper (#F4F2ED) as the title color in both appearances (Night's ground on the fields would measure 2.10-3.16:1) [M0-A41]. Real cover art from the file replaces them when present.
- No gradients, no glassmorphism, no colored shadows. Shadow is a single value (4.4.4) and only on the two floating objects. This includes navigation chrome: the tab bar, navigation bars and mini-player are Sylvia's own opaque components (4.4.7), not the system's translucent Liquid Glass bars.

### 4.4.3 Typography

Three faces, each with one job.

| Face | Role | License and source |
| --- | --- | --- |
| **Literata** (variable; optical size axis) | Everything that belongs to a book: screen and work titles, headings, quotations, and the default reading face | SIL Open Font License; bundled with the app [S23] |
| **System face** (SF Pro on Apple platforms) | Everything that belongs to the interface: labels, buttons, the user's notes, settings, status text | Platform; Dynamic Type for free |
| **System monospace** (SF Mono) | Values a person compares character by character: fingerprints, digests, timecodes, byte counts, part numbers; tabular figures | Platform |

**Type roles.** Sizes are at the default Dynamic Type setting; every role scales with the user's text size. A role's size is its default size times the ratio of its mapped text style's system size at the current content size category to that style's default size, so every role tracks the system text styles exactly. `UIFontMetrics` is not used: on iOS 26.5 its scaled sizes differed from the system styles by up to 6.3pt (Body at AX5: 48 against 53). [S24] [M0-A40] Two bounded exceptions were decided by the product owner on 22 October 2026 (PO-31 (a) and PO-32): bars stop growing at xxxLarge and rely on the large content viewer (Section 4.4.7), and area, sheet and work titles in the Title role step down one Dynamic Type size at a time, never below Large, until their longest word fits, instead of breaking inside it. Each narrows "every role scales" for the elements it names, and no failed spike forces it; the alternative, not chosen, was that bars keep growing and titles break inside a word at the largest sizes. The mini-player is a third exception unless design prefers its one-row form (Section 4.4.7, PO-32). [M0-A40]

| Role | Face · weight | Size / line (pt) | Maps to | Where |
| --- | --- | --- | --- | --- |
| Display | Literata 600 | 34 / 40, tracking -1.5% | Large Title | Top of each primary area |
| Title | Literata 600 | 28 / 34, tracking -1% | Title 1 | Work titles, sheet titles |
| Heading | Literata 500 | 22 / 28 | Title 2 | Section and dialog heads |
| Reading | Literata 400 | 19 / 30 default; user range 14-28 | Body (scaled, with user override) | Reader body, quotations |
| Body | System 400 | 17 / 23 | Body | All interface text, notes |
| Callout | System 500 | 15 / 20 | Subheadline | Explanations beside an action |
| Caption | System 400 | 13 / 18 | Footnote | Metadata, timestamps |
| Micro | System 600, uppercase, +8% tracking | 11 / 14 | Caption 2 | Marker labels and section eyebrows only; never body copy |

**Reader settings** (Section 9.1): typeface choice of Literata, system serif, or system sans; size within the Reading range; four line-spacing steps; three margin widths; themes Paper, Night and Auto; paginated or scrolling layout; a publisher-styles toggle. Settings are global with an optional per-book override. Highlights must survive every one of these changes (T15).

### 4.4.4 Shape, space, elevation and motion

- **Grid:** 4pt. Spacing steps 4, 8, 12, 16, 20, 24, 32. Screen gutter 20pt on iPhone, 32pt on iPad. Reading margins belong to the user.
- **Radii:** 8 for blocks inset in a card (quote and audio blocks) and for cover thumbnails 56pt or smaller; 10 for small controls (icon buttons, fields, segmented controls); 12 for buttons; 14 for cards and covers; 22 for sheets; full for pills and chips. Nothing else.
- **Hairline:** 1pt at the `hairline` token (approved by the product owner on 22 October 2026, design review pending; earlier drafts said 1px, and one device pixel is a third of a point on a 3x screen) [M0-A41]. Rules separate; cards do not nest in cards.
- **Elevation:** one shadow, 0 8 24 at 10% Paper ink in both appearances (a light shadow on Night would be a glow; approved by the product owner on 22 October 2026, design review pending) [M0-A41], used only on sheets and the mini-player. Nothing else casts a shadow.
- **Motion:** 200ms ease-out for sheets; 120ms ease-out for a highlight appearing; progress rules animate over 200ms ease-out; nothing else animates while reading. No bounces, no parallax. All motion is removed under Reduce Motion except opacity changes. The two ease-out curves and the progress-rule timing were approved by the product owner on 22 October 2026 and await design review [M0-A41]. Sheets presented by the system follow the system's timing and its Reduce Motion behavior, not these values. Decided by the product owner on 22 October 2026 (PO-30 (a)), if G0.6 device step 19 shows the system's Reduce Motion behavior acceptable: accept that rather than build a custom presentation, which narrows T51's Reduce Motion clause to Sylvia's own components; otherwise a custom presentation keeps T51 as written. Step 19 is pending [M0-A42].
- **Sheets:** 22pt top radius, grabber, title in the Heading role, primary action at the bottom. A sheet never dismisses while it holds unsaved text (Section 11.1). Sheets are sized to their content, full height only when the content is taller than the screen (decided by the product owner on 22 October 2026 for M3, PO-32; design review pending) [M0-A42].

### 4.4.5 Marker set: five capture kinds and two statuses

The marker is a small row at the top of any capture: glyph, then an uppercase Micro label, then the source label, in the marker's color. Icons are SF Symbols on device; the boards show 1.75pt stroke equivalents. [P2] Two glyphs have no SF Symbol and ship as custom symbols in the design package so they scale and weight like system symbols: the Generated prompt glyph (chevron and underscore) and the bracket capture glyph of the mini-player and player (4.4.7). The set has seven markers: Quote, Note, Audio, Generated and Word are capture kinds; Attention and Pending are statuses. Word uses the `quote` color family with its own glyph and label.

| Kind | Glyph | Label | Body treatment | Frame | Notes |
| --- | --- | --- | --- | --- | --- |
| Quote | Opening quotation mark, in Literata | QUOTE · source label | Exact text in Literata, Reading or Body size, on `quote` tint, radius 8 | none | Immutable captured wording (Section 11.1). A user's own note under it is in the system face, prefixed "Your note". |
| Note | Pen nib (`pencil.tip`) | NOTE · source label | User's words in the system face | none | No tint, ever: the user's own words need no box. |
| Audio | Waveform | AUDIO · source · duration | A tinted block containing a round play control and a waveform; "No transcript" caption until one exists, set on the card surface, never on the tint [M0-A41] | none | Never rendered as text. Preview playback does not move the main position (Section 10.3). |
| Generated | Prompt glyph (chevron and underscore) | GENERATED · provider · model | Question in Body 600, answer in Body; citation chips inline | 1pt dashed in the `generated` color [M0-A41] | No sparkle iconography. Unresolved citations render as struck-through grey chips with an explanation (Section 13.4). |
| Word | Open book | WORD · source | Headword in Literata 600, then the source sentence and the user's note | none | Shares the `quote` color family. |
| Attention | Triangle | NEEDS ATTENTION | Reason in Body; one or two actions | tinted row | Never shown without a reason and a next step. |
| Pending | Dot | QUEUED / WAITING | Caption | none | Quiet by design. |

Two markers never share a row without their labels. The Thoughts filter chips reuse the labels verbatim: All, Quotes, Notes, Audio, Generated, Words.

### 4.4.6 Status vocabulary

Status language is a component. Each moment has a fixed set of phrases tied to a state machine in this plan, and a list of phrases the interface never uses. A phrase changes only when the underlying state changes. All strings live in the design package (4.4.9) under stable keys and are the only strings permitted for these states (T54).

| Moment | State machine | We say | We never say |
| --- | --- | --- | --- |
| Saving a thought | Section 11.1 capture transaction | "Saving…" → "Saved" (with time, after the durable commit) · on failure "Not saved · your text is still here" | Done · Success · a dismissed sheet with nothing written |
| Import and transfer | Section 8.2; Section 15.5 | "Queued" · "Waiting for {source}" · "Receiving" (with verified-of-total bytes) · "Verifying" · "Preparing" · "Needs review" · "Ready" · "Ready · indexing continues" · "Needs attention" (with reason) | Complete before Ready · Error · Downloading for a Mac transfer that is verified by parts |
| Delivery receipts (Mac companion) | Section 16.2 | "Queued on Mac" · "Downloaded to phone" · "Imported into Sylvia" | Sent · Delivered (as a claim that the item was imported) |
| Capturing audio | Section 10.2 | "Moment saved · preserving audio" → "Audio excerpt saved" · on failure "Excerpt not preserved · Retry" | Clip saved before export · any transcript text that was not transcribed |
| Asking a model | Section 14.4 | "Draft · not sent" · "Sending to {host}" · "Generated" · "Complete" · "Interrupted · partial answer" | Thinking… · The AI read your book · Free with your subscription |
| Context scope | Section 13.1 | Chips: "Selected passage" · "Passage and nearby text" · "Relevant passages from this work" · "Selected thoughts"; after a work search: "Relevant passages retrieved" | Whole book (unless it truly fits and was chosen) · Understands your library · The AI read the entire book |
| Where a file is | Sections 7.1, 12 | "On this device" · "Not on this device · from {source}" · "Record only" | Deleted · Missing · Broken |
| Search coverage | Section 11.3 | "Saved thoughts only" · "Book text indexed" · "Indexing {n} of {m} chapters" · "Text unavailable" | Semantic search · Searched everything |
| Removing things | Section 17.2 | "Remove download" · "Manage retained text" · "Remove excerpt audio" · "Delete record and thoughts" (four separate actions) | Delete alone · a trash icon on a download |
| Endpoint disclosure | Section 14.2 | "{host} · hosted" / "{host} · local" / "{host} · user-managed" with the model identifier | Secure · Private (as unqualified claims) |

**Import state mapping (Section 8.2).** `created` shows "Queued"; `acquiring` shows "Receiving"; `staged` and `validating` show "Verifying"; `identifying` and `committing` show "Preparing"; `needs_review` shows "Needs review" (a duplicate or association choice, listed in the Inbox section of the same name); `ready` shows "Ready", or "Ready · indexing continues" while text indexing runs; `waiting_for_source` shows "Waiting for {source}" with the pending dot, since no user action is required; `waiting_for_space`, `unsupported`, `failed_retryable` and `failed_final` show "Needs attention" with their reason and next step; `cancelled` items leave the Inbox. "Waiting for {source}" and "Needs review" use the pending and attention glyphs respectively.

Microcopy conventions: sentence case; no exclamation marks; durations as "20h 58m left"; positions as chapter and percent, never a page number unless the publication supplies a real page mapping (Section 7.5); times in the Monospace face.

**Vocabulary gaps found in Stage 0 (draft 0.5, pending design review).** The rows below list the states this plan's state machines show, and the status phrases, reasons, next steps and state-dependent actions that other sections of this plan quote, for which the table above has no phrase. Labels that name no state are outside this table: the onboarding actions of Section 4.2, "Move this edition to another work" (Section 7.3), "Search this book" (Section 11.3), the setting "Do not include later passages" (Section 13.3), "Save to Thoughts" (Section 14.5) and the Mac companion's "Send to device" and "Prepare for cable transfer" (Sections 15.1 and 16.4). The component labels of Sections 4.4.5 and 4.4.7 ("Your note", "No transcript", "Capture the last 30 seconds") are already in the design package. Each gap is added to the design package only through the change control of Section 4.4.9 (design review, a fixture update and a snapshot re-baseline), before the milestone that first shows it; design chooses the wording, and until then no screen invents one. The product owner decided on 22 October 2026 to add every gap this way, each before the milestone that first shows it, in one design review pass (PO-28), and the reasons and next steps that "Needs attention" must show before M2's Inbox (PO-29 (a)); the wording itself still awaits that design review. The interim texts are what the Stage 0 spikes and prototype showed; they are not vocabulary. [M0-A45]

| Moment | State machine | States or phrases with no vocabulary entry | Stage 0 interim text | Source |
| --- | --- | --- | --- | --- |
| Share extension handoff | Section 8.1 | Received (with the item and its byte count); not received, with the reason and the fallback steps | "Received"; "Not received. Nothing was saved to Sylvia." | G0.3 F7 |
| Import and transfer | Sections 7.3, 8.1, 8.2, 8.4, 8.5, 15.5, 16.2 | "Preparing transfer" (the Mac preparing a snapshot; Section 16.2); "Already imported" (a same-file reimport; Section 7.3); "This is a webpage, not a supported file" (Section 8.1); the reasons and next steps that "Needs attention" must show, for example "still copying or incomplete; wait for Finder and try again" (Section 8.5), local network access turned off or not enough space, and the actions "Retry", "Choose replacement file", "Inspect details" and "Discard partial data" (Section 8.4) | Example sentences in the design catalog's fixtures | G0.6 open questions 2 and 4; G0.3 F5; G0.2 finding 19; Sections 7.3, 8.1 and 8.4 (draft 0.5 review) |
| Reopening a saved passage | Section 7.5 | "Location needs review" (an ambiguous reanchoring match) | "Location needs review" (G0.1 PDF spike) | Section 7.5 (draft 0.5 review); G0.1 PDF row 24 |
| Reading | Sections 9.1, 9.2 | "No selectable text on this page" (an image-only PDF page; Section 9.2); the action that extends a quotation into the next chapter (Section 9.1; decided by the product owner on 22 October 2026, PO-03) | "No selectable text on this page" (G0.1 PDF spike) | Sections 9.1 and 9.2 (draft 0.5 review); G0.1 PDF row 13; G0.1 EPUB F8 |
| Capturing audio | Section 10.2 | A moment that could not be written (nothing kept); a capture asked for with nothing loaded | Proposed keys `audio.moment_not_saved` and `audio.nothing_to_capture` | G0.4 open questions; G0.6 open question 12 |
| Playback | Section 10.1 | A member being opened (`preparing`), which can last tens of seconds; the incomplete-edition warning (Section 10.1), each member that cannot play using the existing `file.not_on_device` phrase; the brief notice that playback resumed earlier after a long pause, with its action that undoes the rewind (Section 10.1, PO-39; added in draft 0.8) | The state's name; proposed key `audio.edition_incomplete`; none for the rewind notice (the G0.4 harness shows none) | G0.4 open questions; PO-39 (22 October 2026) |
| Asking a model | Sections 13.4, 14.4 | `awaiting_consent`, `ready`, `streaming`, `cancelled`, `failed_retryable`, `failed_final`; stopped before any answer text; a refusal or content-filter stop with no answer text; the reason shown beside "Interrupted · partial answer"; a failed record with no classified failure; the limitation disclosures, "No passages sent" and the disclosure's counted phrases; the quotation labels of Section 13.4 (exact, paraphrase, unsupported, and the "short quoted phrase" labels) and its "[earlier source]" marker; "Saved on this device" (Section 14.4) | Classified messages (ADR-0011) | G0.5 AI F5; G0.6 open questions 2, 3 and 10; Section 13.4 (draft 0.5 review) |
| Transcription | Section 10.4 | "Set up transcription" and "Type what you heard" (Section 10.4); the machine-transcription label; the confirmation an uncertain resend needs | "Machine transcription · may be inaccurate" | G0.6 open question 2; G0.5 AI F20 and F22 |
| Removing things | Section 17.2 | "Wait, then remove" and the separate "erase retained content copies" operation (Section 17.2) | none | G0.6 open question 2; Section 17.2 (draft 0.5 review) |
| Where a file is | Section 12 | "Read/Listen" while a file is here; "Add file" and "Download from source" when it is not (Section 12) | none | G0.6 open question 2; Section 12 (draft 0.5 review) |

### 4.4.7 Component inventory

The small set every screen is assembled from. Each is a SwiftUI view in the design package (4.4.9) with light, dark and grayscale snapshot tests.

| Component | Specification |
| --- | --- |
| Buttons | Primary: Pine fill, `pine.on` text, 50pt, radius 12, one per screen. Secondary: hairline border, ink text. Quiet: Pine text, no border, 44pt minimum. Destructive: `attention` text and border; never adjacent to a primary. Pressed and disabled states change opacity only: pressed 0.9, the smallest step that keeps every pressed label at 4.5:1 (0.7 failed), and disabled 0.45, exempt from contrast as an inactive control, so no status phrase is ever shown on a disabled button; a busy primary ("Saving…") keeps full contrast (approved by the product owner on 22 October 2026; design review pending) [M0-A43]. |
| Status pills | 22-26pt tall, radius full, Micro or Caption label, always with a glyph: dot (queued/receiving/verifying/preparing), check (ready), triangle (needs attention). Fill is the state's tint. |
| Availability badges | Hairline pill: "On this device". Dashed hairline pill in `muted`: "Not on this device · from {source}", "Record only". |
| Capture cards | Surface, hairline border, radius 14, 12-14pt padding; marker row, body per 4.4.5, optional "Your note" line, timestamp in Monospace. Generated cards use the dashed frame. |
| Rating | Five stars in `ochre`, half-star steps, stored as integer 1-10 (Section 12). Clearing is a separate action, not zero. Filled versus outline must read in grayscale. |
| Progress rule | 2-3pt track at `hairline`, Pine fill; caption shows chapter or part and percent, with time remaining in Monospace. |
| Tab bar | A Sylvia component, not the system tab bar: opaque `surface` with a hairline top rule. Three items: Library, Thoughts, Inbox. Active in Pine, inactive in `muted`. Search and Settings live in the navigation bar, which follows the same rule (opaque `ground`, plain icon buttons, no system glass). Inbox shows an `attention` dot when an item needs the user. On iPad in regular width the same three areas move to a sidebar built from the same tokens. Each item exposes the accessibility traits, labels, large-content viewer and hardware-keyboard behavior of the system control it replaces, including opening the item under the finger when it lifts during the large content viewer (SwiftUI's viewer does not; the design package adds it), checked on a device because the viewer is not exposed to automated accessibility tests [M0-A43]. Like the system bars it replaces, the bar stops growing at xxxLarge and relies on the large content viewer beyond it (decided by the product owner on 22 October 2026, PO-31 (a); Section 4.4.3) [M0-A40]. |
| Mini-player | Floats 12pt above the tab bar; surface, radius 14, the one shadow; cover, title, caption, a capture control (custom bracket glyph, "Capture the last 30 seconds") and play/pause. Each screen that shows it insets its own scrolling content by its height, so the end of every list scrolls clear of it. It grows with Dynamic Type (54% of an iPhone SE screen at AX5 in G0.6); decided by the product owner on 22 October 2026 (PO-32): it stops growing at xxxLarge like the bars, a third bounded exception to Dynamic Type (Section 4.4.3), unless design prefers to collapse it to one row that keeps growing; design's review of that choice is pending [M0-A43]. |
| Capture sheet | Section 4.1 reader/player sheet: marker row, quote block or audio range, "Your note" field, Look up and Ask actions, primary button whose label is the save state. |
| Selection menu | Ink pill over the selection: Highlight (with Ochre quotation glyph), Note, Look Up, Ask. |
| Typographic cover | Literata title on one of the five cover fields (4.4.2), author in small caption; 2:3 ratio in lists, square in the player. |
| Reader chrome | Minimal: back, book title in Micro, "Aa", bookmark, search. Footer: progress rule with chapter and percent. No page numbers unless mapped. |
| Impact report | Used before removal (Section 17.2): check-marked lines for what is freed and what is kept, an `attention` row for anything pending, then the safe choice as the primary button. |

### 4.4.8 Grayscale and accessibility conformance

Marginalia must hold on devices that show no color: an iPhone with Color Filters set to grayscale, and reflective grayscale tablets. `Docs/Design/` includes the six core iPhone screens and the iPad reader rendered through a luminance grayscale filter as the reference for this check. [P2] The intended results, verified by T53:

- Quote and Audio tints collapse to nearly the same light grey; the glyph, the label and the content form (serif text versus a waveform with a play control) carry the difference.
- Receiving, Ready and Needs attention pills become similar greys; the dot, check and triangle do the work.
- The Pine primary button becomes dark grey and stays distinct from ink text and from hairline secondary buttons by its fill (6.66:1 against the ground in light grayscale, 7.86:1 in dark); the secondary button's hairline is faint by design (1.27:1 in light, 1.66:1 with Increase Contrast), so a secondary button is recognized by its label and outline (design to confirm on a device) [M0-A43].
- The reader highlight keeps its underline; the selection keeps its tint; the margin dot still marks a saved thought.
- Rating stars lose Ochre, but filled versus outline still reads.
- Generated keeps its dashed frame and label; citation chips remain legible as chips.

Further accessibility rules, extending Section 18.3: all roles scale through Dynamic Type up to the largest accessibility size without clipped labels in the capture sheet, player, Inbox and Thoughts, with the bounded exceptions of Section 4.4.3 [M0-A40]; `hairline` rises to 24% under Increase Contrast, and tints move one step, 10% of the way, toward their marker's text color, which darkens them in Paper and strengthens them in Night, where darkening would erase them; in Paper three text colors are darkened by the smallest step that keeps 4.5:1 on the stronger tints (Ochre #875210, Attention #9E3A2D, Muted #646059) (approved by the product owner on 22 October 2026; design review pending) [M0-A41]; Sylvia's tab bar, navigation bars and mini-player are already opaque, so Reduce Transparency changes nothing there, and any system-provided surface follows the system setting; Bold Text is honored by all roles; every icon-only control has a label; highlight colors are never the only way to distinguish capture types.

### 4.4.9 Implementation mapping

- **Package.** A `SylviaDesign` Swift package (Section 6.2) owns color tokens (asset catalog with light and dark variants, exposed as a typed enum), type roles (Literata registration, scaling by the mapped text style's system size [M0-A40], role enum), the marker enum and its presentation mapping from the domain's capture kinds, the status vocabulary strings under stable localization keys, and the SwiftUI component library in 4.4.7. The Mac companion consumes the same package; AppKit-hosted SwiftUI uses the same tokens with macOS control sizing.
- **Single source.** No view declares a literal color, font size or state string. Lint rejects hex literals, `Font.system(size:)` calls and status phrases outside the package in UI targets.
- **Portable tokens.** Tokens, type roles, marker definitions and the status vocabulary are also exported as versioned JSON under `Contracts/design/` alongside the schemas, so later Android and web clients implement the same system from the same file rather than from screenshots (Section 24). Platform mappings, including web typography and glyph equivalents, must preserve meaning and accessibility; they do not require identical native and browser layouts.
- **Reference artifact.** The *Sylvia Concept Designs* boards are checked into `Docs/Design/` at each revision as rendered PNGs (`images/`) and board source (`canvas/`), with a README that maps each board to its plan section and a script that re-renders them. [P2] They are a reference, not a specification; this section is. The authoring canvas they come from is the product owner's private working copy; nothing in this plan requires access to it.
- **Change control.** Token, role, marker or vocabulary changes require design review, a fixture update and a snapshot re-baseline. A screen may not introduce a new status phrase; it requests one through the vocabulary.
- **Tests.** Snapshot tests for every component in light, dark, grayscale and Dynamic Type at the default and largest accessibility sizes (T51, T53); a vocabulary conformance test that walks every state machine's user-visible string (T54); a contrast check over every text/ground pair in the token file in CI. Snapshot references alone do not catch clipping (G0.6 found references that had recorded truncated labels and passed), so a layout audit at the default and largest accessibility sizes runs beside them, new or re-recorded references are reviewed by a person before they are committed, and the contrast check also covers the text and glyphs that components draw in every state that changes color or opacity (pressed, disabled, busy). [M0-A44]

# 5. Requirement inventory and traceability

Requirement identifiers below are stable review handles. Detailed behavior is defined in subsequent sections. Priority P0 means required for v1; P1 means a proposed gated enhancement whose exclusion needs a release-note decision, not an implementation shortcut.

| ID | Requirement | Priority | Specification / acceptance |
| --- | --- | --- | --- |
| LIB-01 | Local-first catalog and no mandatory account | P0 | Sections 6-7; T01, T02 |
| LIB-02 | Works, editions, assets and explicit associations | P0 | Section 7; T03, T04 |
| LIB-03 | 5,000+ titles with responsive queries | P0 | Section 19; T34 |
| LIB-04 | Manual records and manual external progress | P0 | Section 12; T05 |
| IMP-01 | Files, share, AirDrop and supported URL intake | P0 | Section 8; T06-T09 |
| IMP-02 | Crash-safe staging, validation and idempotency | P0 | Section 8; T10-T13 |
| IMP-03 | Multi-file audio grouping/order confirmation | P0 | Sections 8, 10; T14 |
| READ-01 | EPUB navigation, settings and stable highlights | P0 | Section 9; T15 |
| READ-02 | PDF text selection and source-linked notes | P0 | Section 9; T16 |
| READ-03 | Basic TXT/Markdown reading and capture | P0 | Section 9; T17 |
| AUD-01 | Local playback, chapter navigation and persistence | P0 | Section 10; T18-T20 |
| AUD-02 | Durable short audio captures and isolated preview | P0 | Section 10; T21-T23 |
| AUD-03 | Optional short-clip transcription endpoint | P0 capability | Sections 10, 14; T24 |
| AUD-04 | Dedicated lock-screen quick capture | P1 / gate | Stage 0; T25 |
| KNOW-01 | Quotes, comments, vocabulary and source snapshots | P0 | Section 11; T26 |
| KNOW-02 | Global retained-knowledge search and export | P0 | Sections 11, 17; T27, T35 |
| LED-01 | Progress, history, completion and rereads | P0 | Section 12; T28 |
| LED-02 | Rating and recommendation events | P0 | Section 12; T29 |
| AI-01 | Pluggable providers with explicit consent | P0 | Section 14; T30, T31 |
| AI-02 | Context selection, citations and graceful limits | P0 | Sections 13-14; T32, T33 |
| AI-03 | Durable conversations and offline drafts | P0 | Section 14; T33 |
| XFER-01 | One-time secure pairing and revocation | P0 | Section 15; T36, T37 |
| XFER-02 | Resumable and verified Mac-to-device transfer | P0 | Section 15; T38-T41 |
| XFER-03 | Wired import without a custom USB protocol | P0 | Sections 8, 16; T42 |
| XFER-04 | Manual-address/Tailscale-compatible connectivity | P0 | Section 15; T43; the Tailscale route depends on D16 [M0-A13] |
| STORE-01 | Media removal without knowledge loss | P0 | Section 17; T23, T44 |
| STORE-02 | Consistent backup, restore and migration | P0 | Sections 7, 17; T35, T45-T47 |
| SEC-01 | Content, credential and endpoint isolation | P0 | Section 18; T31, T48-T50 |
| UX-01 | Accessible capture and truthful failure states | P0 | Sections 4, 18; T51, T52 |
| UX-02 | Design language conformance: tokens, type roles, marker set, status vocabulary, grayscale | P0 | Section 4.4; T51, T53, T54 |

# 6. Application architecture

## 6.1 Architecture and ownership

Use a modular monolith on device. UI issues typed application commands; application services coordinate transactions and jobs; domain types encode invariants; adapters handle platform frameworks and network protocols. No view directly writes database rows, mutates media files or constructs model-provider payloads.

The local dependency flow is: **SwiftUI features -> application services -> domain/repositories -> SQLite and file store**, with separate adapters for reading, playback, provider networking and source transfer. The share extension writes only a durable import handoff to an App Group inbox; the main application remains responsible for catalog mutations.

The Mac companion exposes selected files and transfer manifests. It may retain its own source index and durable delivery queue, but it neither synchronizes nor owns the iPhone's annotations in v1. "Queued on Mac", "downloaded to phone" and "imported into Sylvia" are separate acknowledgements.

## 6.2 Targets and packages

| Module | Responsibilities | Forbidden dependencies |
| --- | --- | --- |
| SylviaDomain | Entity IDs, value objects, anchors, policies, validation | SwiftUI, Readium, AVFoundation, provider SDK types |
| SylviaApplication | Import/capture/ledger/AI commands and orchestration | Direct view access; global mutable state |
| SylviaPersistence | GRDB repositories, migrations, transactions, FTS | UI logic; network calls inside transactions |
| SylviaFiles | Blob store, staging, hashes, bundles, recovery | Bibliographic merge decisions |
| SylviaReading | EPUB/PDF/TXT adapters, navigation and selections | Owning annotations or canonical identifiers |
| SylviaAudio | Playback state machine, timeline and clip export | Provider credentials; work matching |
| SylviaAI | Context builder, provider adapters, streaming and evidence | Agent tools or unrestricted filesystem access |
| SylviaTransfer | Pairing, source catalog, transfer jobs and contracts | Ledger authority; arbitrary remote paths |
| SylviaImportHandoff | Extension-safe manifests and shared staging | Main-app-only APIs |
| SylviaDesign | Color tokens, type roles, marker presentation, status vocabulary strings, component library (Section 4.4.9) | Domain logic; persistence; networking; any literal not in the token file |
| SylviaUI / MacUI | Screens, presentation state and accessibility, composed from SylviaDesign | Reimplementing domain rules; literal colors, sizes or status strings |

Share platform-neutral Swift packages between Apple targets now. Share schemas, fixtures, state-machine definitions, protocol semantics and the exported design tokens with Android later. Do not introduce Rust/Kotlin Multiplatform merely to promise reuse before the actual seams are stable.

## 6.3 Technical defaults

Swift 6 concurrency with strict checking; Swift Package Manager; SwiftUI with UIKit representables where required; GRDB over SQLite; immutable typed command results; injectable clocks, file stores and clients. Select the current supported non-beta Xcode at kickoff and record the exact version; do not build against a moving SDK or dependency branch. Recorded at kickoff (ADR-0001): Xcode 27.0 (27A266a) with Swift 6.4 and the iOS 27 SDK, deployment targets iOS/iPadOS 26.0 and macOS 26.0. Re-pinned on 20 October 2026 by the product owner's decision of PO-35 (as ADR-0001 records the reading of the owner's reply, which named no option), after the build Mac's Xcode updated itself from the App Store: Xcode 27.1 (27A9275), with the same Swift 6.4 and the iOS 27.1 SDK. On 22 October 2026 the product owner confirmed that decision as their own, and reported that the App Store's automatic updates are now turned off on the build Mac; a read-only check the same day found the key the re-pin round had read for that setting, `AutoUpdate` in `/Library/Preferences/com.apple.commerce`, at 0, where it read 1 on 20 October 2026 (`Docs/Stage0/evidence/M0-Decisions/plan/auto-update-check.log`, `Docs/Stage0/evidence/M0-Integration/repin-27.1/toolchain-state.log`); no agent changed it. Whether that build is the non-beta release still awaits a check of Apple's release notes, the condition its recommendation carried, which is the technical lead's (ADR-0001, open items); the Stage 0 gate evidence was produced under 27.0 (ADR-0001). [M0-A01]

Readium supplies EPUB parsing/navigation through a narrow adapter, which is also Sylvia's content-safety boundary: on its own, Readium 3.11.0 lets a publication run scripts and reach the network, so the adapter enforces Section 8.3 [M0-A02]. PDFKit remains the PDF implementation. AVPlayer/AVQueuePlayer plus Media Player handle local audio and supported system controls. SQLite FTS5 provides lexical search; semantic retrieval is a later interchangeable strategy. These choices are recommendations grounded in the available platforms, not benchmark results. [S1-S4, S8-S11]

Use one serialized database writer and bounded background workers. UI state is main-actor isolated. File hashing, EPUB extraction, audio preparation and indexing must not block the main actor. Cancellation must leave resumable checkpoints or a clearly failed operation; no unbounded detached tasks.

## 6.4 Job scheduling

Persist jobs before scheduling work. Classify them as user-blocking, user-requested background-capable, or deferrable. Prioritize capture commits and playback over indexing/transcription. Permit one heavy local processing job and two network transfers by default; tune with measurements.

Background URLSession is used for eligible downloads; BGTaskScheduler is opportunistic housekeeping, not a guarantee of completion. Transfers created while the app is in the background are discretionary for iOS: on the simulator, part tasks created during a background relaunch opened no connection in the next 59 seconds, so background progress depends on tasks created while the app was in the foreground (Section 15.4). [M0-A15] Reconcile persisted jobs with OS tasks on every launch. A force-quit/reboot path must safely recover on the next launch even where the OS does not continue or relaunch work. [S5]

# 7. Data model, identities and persistence

## 7.1 Domain model

**Work** is the lasting intellectual item. It can exist without a file. **Edition** is a particular textual publication, translation or audio narration/abridgment. **Asset** is an immutable byte representation with a SHA-256 digest. **EditionAsset** attaches assets to editions and orders multi-file audio. **AssetLocation** describes availability on this device or a source, not whether the user has read the work.

An EPUB edition and an audio edition can belong to the same Work while preserving distinct anchors and progress. A PDF companion can be attached with a companion role. Matching editions is not automatic merely because the titles are similar. Source revisions never overwrite the bytes of an existing asset identity.

Keep medium/type separate from user categorization. V1 uses a book-oriented interface and manual external records. Versioned serialization must tolerate future item kinds such as article/newsletter without pretending those ingestion paths exist now. Do not implement a fixed genre hierarchy or automatic topic tagging in this release.

## 7.2 Logical tables

| Entity / table | Required fields and relationships |
| --- | --- |
| Work | UUID, title, sort title, description, language tag, metadata revision, created/updated timestamps, optional deleted timestamp |
| Contributor / WorkContributor | Person/organization display name, role, ordering; no device-contacts dependency |
| Edition | Work ID, medium, language, publisher/date, identifiers, narrator/abridgment where applicable, optional page count |
| Asset | UUID, SHA-256, byte count, sniffed media type, original filename, duration if applicable, validation status |
| EditionAsset | Edition ID, Asset ID, role, sequence, timeline revision, the timing mode the import chose for an audio member and, for a member the import remuxes, its derived playback copy (Section 8.3) [M0-A22]; unique ordered membership |
| AssetLocation | Asset ID, Source ID, opaque source item/version, local relative path if applicable, availability and last verification |
| Source / SourceItem | Source kind, stable ID, display name; external identity mapping and provenance, credential references only |
| MetadataProvenance | Entity/field, imported value, source, timestamp and manual-override flag |
| ConsumptionRun | Work ID, started/finished dates, state, explicit/manual completion flag; permits rereads |
| Progress / Session | Run/edition, current anchor, furthest comparable anchor, heartbeat timestamps, active elapsed time and source |
| LedgerEvent | Work/run, typed event, user-effective date plus recorded timestamp, small versioned payload |
| Rating | Work, nullable value 1-10 representing half-stars, updated timestamp; clear is distinct from zero |
| RecommendationEvent | Work, inbound/outbound direction, person or source label, event date precision, reason and optional URL |
| Capture / CaptureAnchor | Work, kind, exact quoted text when applicable, immutable source metadata snapshot, one or more anchors |
| Note / NoteRevision | Work and optional capture/conversation, user Markdown/plain text, revision, saved timestamp |
| VocabularyEntry | Word, capture/anchor, user note and optional user-authored meaning; no assumed dictionary-content export rights |
| RetainedExcerpt | Capture, local media blob, requested and actual exported audio ranges with each range's source format, clip-local offsets, excerpt format, export state and duration [M0-A24] |
| Conversation / Message | Work/capture association, role, content, state, provider/model snapshot, request ID, timestamps |
| ContextPack / ContextEvidence | Immutable request scope, selected evidence snapshots, anchors, text hashes, truncation and retrieval metadata |
| TextDocument / TextChunk | Asset/extraction version, ordered resource/page blocks, provenance/quality, text and location mappings |
| Job / TransferPart | Job type/state, idempotency key, attempts, errors; part offsets, size, digest and verified status |
| ProviderConfig / TrustedDevice | Endpoint/model/capabilities and privacy policy; Keychain references, each provider key bound to the origin it was entered for [M0-A32], pairing status and revocation metadata |
| ChangeJournal / ExportRecord | Local mutation sequence, entity/revision and operation; export schema/time/counts/digests |

Use normalized relationships for identity and knowledge. JSON is appropriate for versioned locator payloads, context manifests and provider capabilities, not for opaque blobs replacing the entire library schema. Use 64-bit sizes and timestamps; durations/positions serialize as integer milliseconds, not floating-point percentages alone.

## 7.3 Identity and mutation rules

Generate UUIDs locally. Asset digests deduplicate bytes; they do not decide whether two works are the same intellectual work. Same-file reimport offers "Already imported" or restores local availability. Fuzzy title/author matches prompt the user to attach as an edition or create a separate work; no destructive automatic work merges in v1.

Support a reversible "Move this edition to another work" operation. Preserve IDs and anchors; record provenance. A work cannot be deleted accidentally through source cleanup. Bibliographic identifiers are hints, not unconditional unique keys across all kinds of editions.

Use foreign keys and explicit transactions. Cascade only genuinely subordinate processing data; media removal must never cascade into captures or ledger events. Revision-checked note edits prevent a stale editor window overwriting a later local edit. Store user-effective dates separately from UTC event timestamps and preserve date precision for historical completion/recommendation entries.

## 7.4 Durable commits and migrations

Store the main database under private Application Support, not Finder-exposed Documents. Enable foreign keys, WAL and a durability configuration tested for acknowledged saves. Decided (D17; approved by the product owner on 22 October 2026 with PO-21 (a); the security and persistence sign-offs and the phone's check, G0.5 recovery device steps 1 and 2, pending): WAL with `synchronous = FULL`, `fullfsync` and `checkpoint_fullfsync`, applied on the writer after the pool opens and read back on every open, a mismatch failing the open; GRDB 7.11.1 resets `synchronous` after its `prepareDatabase` hook, so a setting placed there is silently lost. `NORMAL` may roll back recent commits after a power loss or an OS crash, which I-03 forbids. On the host the setting's capture saves stay far below the 200 ms budget (p95 3.25 ms in the gate's final run); its cost against `NORMAL` was not resolved under parallel load (that run measured it higher, an earlier one lower). [M0-A28] Use GRDB's supported transaction/migration/backup facilities; do not copy a live SQLite file while ignoring its WAL. [S2]

Each schema migration has an ID, fixture upgrades, integrity checks and a rollback/recovery plan. Before a destructive migration, create a consistent local recovery snapshot; if storage is insufficient, stop rather than deleting user data to proceed. A failed migration opens a recovery screen, not an empty replacement library. The open reads every applied migration identifier and refuses, with nothing changed, a library that holds one this build does not know (a newer build's; GRDB's list of applied registered migrations cannot show that). Putting a snapshot back, like any operation that replaces the library's files, first writes an intent and is finished or rolled back by the next open before SQLite opens anything, and the open never lets SQLite create a database where one existed. [M0-A28]

ChangeJournal is a transactional local record of semantic mutations with a device-local sequence. It assists diagnostics and later sync development; it is **not** a complete distributed synchronization protocol. Do not implement speculative remote conflict resolution, CRDTs or full event sourcing for this release.

## 7.5 Canonical anchor rules

An anchor includes schema version, Work/Edition/Asset IDs as applicable, asset digest, kind and source locator. EPUB uses the Readium locator plus exact selected text and surrounding text. PDF uses physical page index, printed label only when the file supplies one in `/PageLabels` (PDFKit invents "1", "2", ... otherwise, and those are never stored) [M0-A11], text selection mapping and normalized rectangles with rotation metadata. Audio uses asset-local milliseconds; cross-file selections use multiple ordered ranges. [S3, S10]

Store the original locator returned by the reader as opaque adapter data and a small portable envelope. Cross-platform text offsets must state their unit; use Unicode scalar offsets for Sylvia-extracted text, and explicitly convert native UTF-16 ranges at the adapter boundary. In an EPUB anchor such offsets are optional: they are absent when a selection spans blocks or is ambiguous in Sylvia's extraction, and reanchoring never depends on them [M0-A07]. Never call a rendered EPUB "page 183" unless the publication actually provides that stable page mapping.

Reanchoring tries original locator, then exact text plus context within the same asset/version. A reader locator is fallible, the resource it names included (Section 9.1): it is trusted only where its stored exact text is found [M0-A04]. Ambiguous matches show "Location needs review". Cross-edition relocation always requires confirmation. Loss of a precise location must not delete the quote or silently link it to the wrong passage.

# 8. Import pipeline and supported files

## 8.1 One pipeline, several entry points

Every intake route creates the same ImportJob. Route-specific code is responsible only for obtaining authorized bytes or a durable download request. The common pipeline copies/stages, sniffs type, verifies available checksums, inspects protection/structure, extracts minimal metadata, resolves grouping, commits assets and schedules nonblocking text indexing.

**Files/document picker:** use security-scoped access and file coordination while copying into private staging. Handle iCloud/provider items that must first download, revoked access, insufficient space and the source disappearing. Do not store a transient provider URL as the sole future access path.

**Share extension:** accept supported file representations and direct file URLs. Copy file representations to a unique App Group staging directory before reporting them received; write a small manifest atomically last. Do not assume provider-temporary URLs survive after the extension exits. For large files, stream/copy rather than reading into memory. Apple documents no number for the extension's memory limit: in the simulator the extension's footprint rose over the first 2 GiB copied and then stayed flat (peak 49.1 MB, in the 8 GiB + 1 run) up to an 8 GiB file, and the real limit is measured on a device before any margin is assumed. A provider that makes no progress for 60 seconds before delivering a file is cut off with the fallback; once copying has started there is no timeout, only user cancellation. [M0-A20] A cancel stops the extension's own load at once and claims nothing, but it may not reach the sharing app: on the simulator the sharing app's provider kept going after a cancel, so a large iCloud download or Mail fetch may continue (G0.3 device steps 9 and 18 record what a phone does). [M0-A20] If the extension cannot finish safely, show an actionable Files/LAN/wired alternative and do not claim receipt. An extension stopped after its commit but before it showed "Received" leaves a complete handoff that the app imports, so an item can arrive unconfirmed: the Inbox names the route it came by, and a retry of the same bytes is a duplicate needing review, not a second book. [M0-A20] In Stage 0 the share extension refused an EPUB offered as a folder (unpacked, as iCloud Drive or a Mac's Books library can keep one), with its own reason. Decided for V1 by the product owner on 22 October 2026 (PO-16 (c)): EPUBs are imported only as single files, so a folder is refused that way on every route, a narrowing no failed spike forces, because earlier drafts did not restrict an EPUB's form; the alternatives were accepting folders on the phone, behind safety checks of their own, which V1 never does because the EPUB checks are built for archives, or having the Mac companion pack them into `.epub` files, which remains possible if M6 has room for it. [M0-A53] URL download handoffs may use an extension-specific background session and the shared container. [S6]

**AirDrop/open-in:** accept the file through system document handling and feed it into the same staged importer. Sylvia does not implement or control AirDrop itself. [S7] With `LSSupportsOpeningDocumentsInPlace` set to NO (Sylvia never edits a document in place), the Documents folder is not shown in the Files app, and on the iOS 26.5 simulator the Files app's "Open With" does not list Sylvia; YES restores both, while the importer still copies inside coordinated reads. Decided by the product owner on 22 October 2026 (PO-15 (a)): NO until the device run shows a phone's behavior (G0.3 device step 13, pending), then YES if a phone also leaves Sylvia out of "Open With", so that route is kept either way. [M0-A20]

**URL import:** support HTTPS links whose response is a supported file, subject to content sniffing and size limits. Use redirects cautiously; never forward an Authorization header to a different origin. A URL returning HTML produces "This is a webpage, not a supported file" with the option to keep a manual reference, not a broken EPUB entry. Authenticated browser sessions, paywall extraction, streaming URLs and RSS discovery are not v1 features.

**Mac LAN:** consume a pinned source manifest and verified parts using Section 15. **Wired Finder:** use the supported file-sharing surface; explain that the user waits for Finder's copy to finish, then imports in Sylvia. The app does not pretend to control Finder's transport progress or resume. [S7]

## 8.2 State machine

Use persisted states: `created -> acquiring -> staged -> validating -> identifying -> needs_review | committing -> ready`. Failure branches are `waiting_for_source`, `waiting_for_space`, `unsupported`, `failed_retryable`, `failed_final` and `cancelled`. Downstream text indexing has its own state and cannot roll a readable book back to "not imported". User-visible names for these states are fixed in Section 4.4.6.

At `acquiring`, no library item claims a complete asset. At `staged`, bytes are owned by Sylvia but not yet trusted. At `ready`, the final content path and database relationship exist, required validation has passed, and the work is usable. Display "Ready · indexing continues" when appropriate.

Idempotency uses a stable job ID plus asset digest and source revision. A retry reuses that job. A relaunch scans staged manifests, unfinished commits and orphan final blobs; it either finishes the recorded operation or presents recovery. Use a durable commit journal because a filesystem rename and SQLite transaction are not a single atomic transaction.

Recommended commit sequence: verify staged bytes; persist a commit-intent row; move to an immutable final blob path on the same volume; transactionally attach asset/location/edition and mark ready; mark the intent complete. A crash between steps leaves a recoverable journal entry, not a duplicate work. Garbage collection must never remove a blob with a live commit intent or knowledge reference.

## 8.3 Type, structure and safety

Support reflowable EPUB 2/3 within a documented compatibility subset, text-based PDFs, UTF-8 text/Markdown, and tested audiobook combinations. The EPUB subset (approved by the product owner on 22 October 2026 as configurable V1 defaults, rechecked against a larger real-book sample in M3: PO-01 (a) and PO-02 (a)): reflowable EPUB 2 and 3 only, fixed layout refused with a specific message; a content document declared `application/xhtml+xml` or `text/html` in the manifest must be well-formed XHTML with an XHTML `html` root, encoded as UTF-8, without entity declarations or named entities outside XHTML 1.x; a document of another type a web view renders (SVG or other XML) is shown only when nothing active is in it, and an XHTML element counts as active there, so XHTML declared as generic XML is withheld (next paragraph); content the manifest does not declare is never shown. A document outside the subset is shown as a placeholder and left out of search, with a per-resource status; all 195 XHTML documents of the five real Stage 0 fixtures are inside it, their text unchanged. [M0-A03] Markdown is recognized by its extensions (`.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`) as well as by its type, because iOS 26.5 maps only `.md` to the Markdown type. [M0-A20] Validate both container and codec. Do not reject an EPUB solely because `encryption.xml` exists: font obfuscation is not necessarily content DRM. Detect actual protected content with the reading adapter and return a clear unsupported-protection error without attempting circumvention. [S1]

EPUB parsing must reject path traversal, absolute paths, symlinks, decompression bombs and excessive recursion. Publication scripts and remote resources are disabled; only reader-owned interaction scripts may run in the renderer. The reading engine does not do this itself: G0.1 found Readium 3.11.0 alone running inline, external and SVG scripts, event handlers and a `javascript:` URL, making 18 network requests, following a meta refresh, serving undeclared archive entries to navigations that are not link taps, and overflowing its stack on 10,000 nested elements. The controls are therefore Sylvia's, in the reader adapter (ADR-0004): only resources the publication's manifest declares are served, each treated by its declared media type; every document a web view can render is parsed and written out again in a canonical form, with scripts, event handlers and script URLs removed and a Content Security Policy first in its head, and is checked in every parser that will read it; documents that cannot carry a page policy (SVG, generic XML) are shown only when nothing active is in them; nesting is measured by the parsers and limited; a WebKit content rule list on every reader web view blocks network loads and any document load outside the reading order; resources are read from local files only. A document that fails these checks is replaced by a placeholder with a per-resource status, never shown raw. The controls are product code with their own tests, re-run on every Readium upgrade. [M0-A02] Treat malformed chapter metadata, cover dimensions and embedded links as untrusted input. PDF launch actions and unsolicited external URLs are not executed (Section 9.2) [M0-A09].

Proposed configurable limits: 20 GiB per audio file; 2 GiB PDF; 1 GiB EPUB expanded content; 10,000 archive entries; 500 audio members per logical edition; bounded image dimensions and parser time. These are release safety defaults to validate against real samples, not claims about OS maxima. For the EPUB values the plan left open, the product owner approved Stage 0's on 22 October 2026 as configurable defaults (PO-02 (a); if a phone takes longer than 20 seconds for documents near the caps, G0.1 EPUB device step 11, the choice between lower caps and a longer budget comes back to the product owner): any archive entry above 256 MiB, any markup or style entry above 16 MiB, and any deflated entry of 1 MiB or more expanding beyond 100:1 are refused before reading; a content document is withheld above 256 levels of nesting, 100,000 elements, 256 attributes on one element or 100,000 attributes in all, or when sanitizing it takes more than 20 seconds, with at most two sanitizer workers per open publication. The reading engine reads a whole archive entry into memory and trusts its declared size, so these limits on declared sizes are what bound memory. Limits inside a `.sylviapack` are in Section 8.5. [M0-A03] Reject oversized items before expensive processing when the size is known; enforce limits while streaming when it is not.

For multi-file audio, group by a selected folder or explicit import selection, not every adjacent MP3 in a mixed directory. Prefer embedded disc/track ordering, then natural filename order; show an editable order preview. Retain the original filenames and record the confirmed timeline revision. Never require destructive concatenation or transcoding simply to form one logical audiobook.

**Import remux (decided by the product owner on 22 October 2026, PO-20).** A member that stays on precise timing (Section 10.1) and is long enough to open or seek slowly (native FLAC, Ogg Opus, a long VBR MP3) gets a derived playback copy: its compressed packets are copied unchanged into MPEG-4 (FLAC, Opus) or CAF (MP3). This is not transcoding: nothing is decoded or re-encoded. On the simulator every such copy resumed in 0.11-0.16 seconds, near the start of the file and near its end, and decoded sample-identically to its original, so file-local anchors stay valid on it. The copy is 0.15-3.2 % larger than its original, so what to keep is a storage choice. Decided (PO-20, remux option (a)): the original remains the asset of record (its digest names the anchors) and the copy is derived playback data, removed with its source, so a remuxed member takes about twice its original's space on the device (a 10.2-hour native FLAC is 0.97 GB). The alternative, not chosen, keeps only the copy and records the original's digest beside it: 0.15-3.2 % more space than the original, but the original's bytes are then no longer on the device and the stored bytes no longer match the asset's digest (Section 7.1). To limit the doubling, only members long enough to miss the start/resume budget are remuxed: on the simulator a native FLAC file beyond about 25-31 minutes, a VBR MP3 beyond about an hour and an Ogg Opus file near 10 hours, shorter under load; the device run (G0.4 step 1.5, pending) sets the lengths. Constant-bit-rate MP3 and MPEG-4 books are never remuxed. The third option, no remux, which would list those formats with their length or depth limits, was not chosen. [M0-A22]

## 8.4 Checksums and truthful status

An app-controlled Mac manifest provides expected byte counts, part digests and final SHA-256. Ordinary user-supplied URLs may provide no trustworthy expected digest. For those, calculate a local digest for deduplication, verify HTTP completion and parseability, and label the provenance accordingly. A self-computed digest is not proof that the origin supplied the intended complete file.

Keep failed staging items only with a documented retry/cleanup policy. The policy, approved by the product owner on 22 October 2026 as a configurable V1 default (PO-14): a share-extension handoff without a manifest is removed after 1 hour without modification, claimed first by a rename so that a live extension can never commit into it, and a rejected handoff is kept 7 days for inspection; each removal is recorded. [M0-A21] Offer "Retry", "Choose replacement file", "Inspect details" and "Discard partial data". Retrying must not discard already verified parts unless the source version changed. Space errors must name the additional space required where calculable.

## 8.5 Wired bundles

Add a versioned `.sylviapack` interchange bundle for the Mac companion's reliable wired handoff: a ZIP64-capable, non-executable container holding a manifest, relative file paths, sizes, digests, grouping and optional metadata. Large audio should be stored without redundant compression. Use an audited archive implementation and test files above 4 GiB before declaring support. Stage 0 showed that the archive library alone is not enough: neither candidate detected partial copies of a 4.5 GiB archive (one opened truncated copies as empty archives after scanning for 43-78 seconds over four runs, the other did not finish within 120 seconds). Sylvia therefore proves a bundle's exact layout with bounded reads (the end record at the end of the file, entries back to back, every local header equal to its central-directory record) before any library reads it, which rejects a partial copy in constant time, and the format accepts only what Sylvia's writer produces (no data descriptors, comments, directory entries or links). The library is `readium/ZIPFoundation` 3.0.1, already in the dependency lock through Readium, always behind that check; upstream ZIPFoundation cannot share a package graph with Readium. [M0-A19] Limits, approved by the product owner on 22 October 2026 as configurable V1 defaults (PO-14): 10,000 entries; per file 20 GiB audio, 2 GiB PDF, 1 GiB EPUB file, 256 MiB text and 32 MiB cover; 500 audio members per group; 200 GiB in all; each deflated entry above 1 MiB at most 100:1, and all deflated entries together at most 100 times their compressed size plus 16 MiB; paths of at most 15 components and 512 bytes; extraction needs the declared total plus 64 MiB free; a pack's manifest at most 16 MiB, enough for 10,000 entries at the path limit, and a share handoff's manifest at most 256 KiB, a larger one refused by both readers and never written by the writers. The EPUB's own expanded size is checked by the reading adapter (Section 8.3). [M0-A21]

A raw file copied through Finder is allowed, but Sylvia cannot prove an external writer has finished merely from an unchanged size. Require user-initiated import after the Finder copy completes, coordinate the copy and validate. Finder's file-sharing copy takes no part in file coordination, so the import takes an APFS clone inside a coordinated read and validates the clone. For a bundle that is a proof of completeness: a copy still in progress fails because its end record is not yet at the end of the file, and is reported as "still copying or incomplete; wait for Finder and try again", not as a corrupt file. [M0-A20] A raw file has no manifest and no end record, so nothing proves it complete (G0.3 F15, host and simulator): the import refuses a file whose device, inode, size or modification time changes between the clone and the end of hashing, with nothing staged, but a copy that has paused or stopped looks finished and is staged as it is (in the host test 2,097,152 of 4,194,304 bytes). Staged is not ready (Section 8.2), so each type's validation must catch a cut file before the item becomes ready (I-04), and for audio it may not: an MP3 or CAF cut short can still play. Decided by the product owner on 22 October 2026 (PO-37 (a) and (c)): keep the raw import, asking the user to wait until Finder has finished; steer large transfers to `.sylviapack`, as the companion's cable flow already does; and leave a raw file in Documents after its import, because removing it could cut off a copy still running. Choosing this keeps a residual exception to I-04 for raw audio copied with Finder, which the decision accepts: a cut MP3 or CAF that still plays could become ready, and steering is advice, not enforcement, until the device run (G0.3 steps 28-30, pending) shows how often a real Finder copy is staged incomplete. The alternative, accepting only `.sylviapack` from Finder above a size set after the device run, which removes that exception above the size, is revisited if those steps show a real Finder copy pausing or stopping unseen. (Draft 0.7 did not name the exception; added on 20 October 2026, M0 final review round 2, plan R2-05.) [M0-A20] For bundled transfers, the manifest/digests supply an additional completeness check. A partial bundle must never pass validation. Do not describe cable import as the same resumable HTTP protocol: the **validation and commit stages** are shared, while transport guarantees differ.

# 9. Reading implementation

## 9.1 EPUB

Wrap Readium's publication opener and navigator behind `ReaderSession`. Required operations are open, navigate, read current locator, receive selection, apply/remove visual highlight decorations, search within work, and observe position changes. Readium locator and decoration capabilities should be demonstrated with the chosen release before committing to the adapter contract. [S1, S3] G0.1 demonstrated them with Readium 3.11.0 on the simulator, with two adapter workarounds for engine defects, carried with tests until a fixed Readium release is pinned and re-measured on every upgrade: the selection check below, and a navigation settle (a single jump into a just-preloaded resource was undone in some runs, so the adapter repeats it after 600 ms, and each navigation is final about 600 ms later). The adapter also clears and redraws highlights after a settings change and repairs a highlight drawn twice; that defends against a duplicate-decoration race seen before Stage 0 which G0.1 did not reproduce, so it is kept with its tests but is not proven necessary (ADR-0004). [M0-A04]

V1 controls: typeface from a small accessible set (Literata as the default, system serif, system sans; Section 4.4.3), size, line spacing, margins, Paper and Night themes with an Auto option, publisher-style preference, table of contents, bookmarks and return-after-link navigation. Support internal notes/footnotes without losing reading position. Note content from a publication is shown as plain text or through Sylvia's own sanitizing renderer, never through a system HTML importer (`NSAttributedString`'s can load remote resources). [M0-A08] Save settings per user with an optional per-book override. Prioritize a reliable paginated mode; continuous scrolling is a proposed secondary mode only if the same anchors and capture tests pass.

Selection opens Highlight, Note, Look Up and Ask (Section 4.4.7 selection menu). Capture the source locator and exact text immediately before a navigation or font change can invalidate the selection. The reader's own locator cannot be trusted blindly: just after a jump Readium 3.11.0 named the previously displayed resource in 3 of 3 captures, so the adapter checks that the locator names the resource that holds the selection, rebuilds it for that resource when it does not (exact text kept, the other resource's progression dropped), and asks the user to select again if the selection changed meanwhile; an adapter script call that fails while a page is being replaced counts as unknown, never as success. [M0-A04] Store highlights in Sylvia's database; reader decorations are only a presentation of those records, drawn with the `ochre` highlight fill and underline so they remain visible without color (Section 4.4.8). Long selections crossing resource boundaries require multiple anchors: Readium renders each resource in its own web view, so one gesture cannot select across them. A quotation that continues into the next resource is stored as ordered anchors whose text is joined without loss, and the capture flow offers an action that extends a quotation into the next chapter, which keeps the cross-resource quotations earlier drafts provided for (decided by the product owner on 22 October 2026, PO-03 (a); the alternative, each selection kept within one resource, would have narrowed them). Whether a finger can extend a selection past a page edge within one resource in paginated mode is a device step (G0.1 EPUB step 3). [M0-A05] The UI must never silently truncate a quotation.

Index publication text resource by resource with extraction-version provenance. Preserve enough mapping to reopen search hits; normalize whitespace for search separately from the original quote. Rendered EPUB position is not a stable print page number. A failed/nonstandard publication must leave the source file available for removal or retry without crashing the library.

## 9.2 PDF

Use PDFKit for display, selection and navigation. Store text quotations and source anchors in Sylvia, not solely as annotations written into the original PDF. Display highlight overlays from saved records. Keep physical page index, printed page label if supplied and normalized selection geometry distinct. Handle rotated pages and multiline selections. [S10] The reader always installs a link delegate, because PDFKit's default link handling opens URLs by itself. The link policy is an allowlist: `http`, `https` and `mailto` links are shown in full and opened only after the user confirms; every other scheme is blocked, `file:` included, which is how PDFKit presents a `/Launch` action. In-document navigation actions and in-memory form resets are performed by PDFKit itself and never write the file. PDFKit never performs an action named by /Next, and presents some additional actions (a link's mouse-up action) as the annotation's own, which a tap then sends to the delegate; outline items' actions are presented like link actions, so the table of contents navigates to each item's destination and sends any other outline action through the same policy, with the delegate installed. [M0-A09]

The supported experience is passage selection, comments, Ask AI, page navigation, search and zoom. No drawing tools, signatures, forms, stamps or PDF rewriting. Password-encrypted PDFs are excluded from v1, as the product owner decided on 22 October 2026 (PO-06 (a)); do not conflate a password prompt with a right to bypass protection. Unsupported/encrypted items show a specific error. A PDF that opens without a password but forbids copying is a separate case, which earlier drafts left ambiguous: it is encrypted, yet text-based and readable without a password. PDFKit does not enforce the flag (page text and selections still return the text), so Sylvia must apply its own policy, which the product owner chose on 22 October 2026 (PO-05 (a)): such files open for reading with no quotation, search or AI text, and say why; this narrows the supported experience above for those files, and no failed spike forces it. The alternatives, not chosen, were personal quotation and search without AI text, or every text feature. [M0-A10]

Scanned or image-only pages may be visually readable, but text features show "No selectable text on this page". No guessed OCR text, no claim that AI has seen the page, and no silent image upload to compensate. Mixed PDFs can support text features on pages that actually have text; retain per-page extraction status. PDF text extraction ships with the OS, so the extraction version includes the OS build and each anchor stores a digest of its page's extracted text: after an OS update pages are re-extracted, and stored ranges are trusted only where the digest still matches; otherwise reanchoring falls back to exact text plus context, then review. [M0-A11] Stage 0 tested generated PDFs only; a small public-domain real-world set (a scanned book, a two-column journal, CJK and right-to-left text, embedded and CID fonts) joins the reference datasets before M3 relies on extraction quality (Section 19.1), as the G0.1 PDF report also asks, because PDF extraction, anchors and search are first built in M3 (Section 21.2). PDF pages are drawn as published, white in every theme, so highlights on them use the light Ochre values; whether Night offers a darkened page is a design question. [M0-A12]

Text drawn with a rotated text matrix on an unrotated page (vertical, upside-down or slanted lines) is extracted line by line and its anchors restore exactly, but the overlay draws its highlight wrongly: the underline follows the bottom edge of PDFKit's axis-aligned line box, which is the baseline side only for upright text, and a slanted line's box covers its neighbours (G0.1 PDF row 10c, failed on the simulator). Approved by the product owner on 22 October 2026 (A54), with design: each line rectangle of a PDF anchor also carries the line's reading direction, which PDFKit gives from the line's first and last characters, so the overlay draws the underline on the baseline side of vertical and upside-down lines; this is an additive field in the anchor contract (Appendix A.1), added with the M3 reader before it writes anchors. A slanted line needs a quadrilateral, which PDFKit's selection API does not give; what is drawn for one is decided with design in M3, before the overlay is built. The alternative, keeping the current drawing for such text, was not chosen. [M0-A54]

## 9.3 TXT, Markdown and lookup

Provide a simple native/sanitized text renderer with selection and offsets against a retained original text representation. Markdown links and formatting may render, but embedded HTML/scripts and remote images remain disabled by default. Preserve exact original source bytes and extraction version so future renderer changes do not rewrite quotes.

Use the system dictionary interface where available. Availability of definitions/offline dictionaries must be checked at runtime. A dictionary lookup and a model-generated explanation are separate actions with different provenance. V1 can save a word, source sentence and user note; it must not promise bulk extraction/export of system dictionary definitions. [S11]

## 9.4 Reader acceptance boundaries

A same-asset highlight must survive relaunch, font size/theme changes, orientation and extraction-cache rebuild. After a settings change Readium restores the reading progression, not the text: the passage that was in view left the restored page in 4 of 13 G0.1 steps, although highlights stayed on the right text. Decided by the product owner on 22 October 2026 (PO-04 (a)): after a settings change the reader returns to the text that was first in view (an M3 adapter behavior with its own test). [M0-A06] Returning from footnotes, search results and capture preview must preserve the user's reading position. VoiceOver must reach selection actions and saved-note content. Unsupported layout, image-only content or imperfect extraction should degrade with specific explanations, not a false "full text available" badge.

M3 demonstrates selection → note → durable save → return to reading without losing the selected wording or the reading position (T55). Opening a saved capture from the work's Thoughts view preserves its retained quotation even if the source is unavailable or its anchor is ambiguous. Native Look Up retains the offline/runtime availability behavior in Section 9.3 and never silently becomes an AI request. This capture journey works without a configured provider; M5 adds the contextual Ask journey to the same presentation and records.

# 10. Audiobook player and audio capture

## 10.1 Playback service

Use a single application-owned playback service with AVAudioSession playback configuration, background audio capability, AVPlayer/AVQueuePlayer as appropriate, and MPNowPlayingInfoCenter/MPRemoteCommandCenter for supported system controls. Activate the audio session only for playback; importing a book must not interrupt audio in another application. [S8-S9]

Expose play/pause, configurable skip intervals, speed 0.5x-3x where supported, chapter list, time elapsed/remaining, sleep timer and selection of an edition. Preserve pitch where the chosen playback path supports it. Test seeking, rate changes, chapter transitions and lock-screen controls with real devices and long files; file extension support alone is insufficient. Chapters come from the container: QuickTime chapter tracks (M4A/M4B) and ID3 `CHAP` frames are read exactly; Vorbis-comment chapters in FLAC and Ogg only in the three-digit `CHAPTERxxx` form, the last chapter closed at the duration; WAV cue points are not read, so a WAV book has no chapters; the import guide states this. [M0-A23]

**Per-file timing mode (decided by the product owner on 22 October 2026, PO-20).** Without precise timing, AVFoundation places positions seconds to minutes off in VBR MP3, native FLAC and Ogg Opus files (the decoder landed up to 129 seconds off 9.5 hours into a 10-hour VBR MP3 on the simulator), so precise timing is the rule. Its cost grows with length: opening a native FLAC file, an MP3 without a Xing/VBRI header or an Ogg Opus file scans it (a 10-hour native FLAC took 28-30 seconds to resume in the gate's final run), and the first seek in an MP3 grows by about a second per hour of depth. The import therefore decides per file and records the decision with the member: estimated timing only for an MP3 it proves constant bit rate by walking every frame header (exact for such a file, and resumed in 0.14-0.15 seconds at every depth tested, up to 10 hours), precise timing for every other file, with the remux of Section 8.3 for the long ones. While a member opens the player reports a preparing state; a slow open is never an error. [M0-A22]

Persist asset-local position every five seconds while playing and on pause, seek, interruption, item change and lifecycle transitions. After a crash, the proposed maximum position loss is five seconds, not zero. Loss is counted in book time, so checkpoints are written every 5 seconds of wall time or 4 seconds of media time while playing, whichever comes first (at 3x, 5 wall seconds would be 15 seconds of book); at a member boundary the checkpoint names the member that starts, because AVQueuePlayer reports the end of an item before it advances. [M0-A25] Store last position separately from furthest progress. Playback error states identify a missing file, an unavailable source or a decode error.

On headphone removal, pause. On calls/interruption, pause and resume only when the platform indicates it is appropriate and the prior user state was playing. Audio-route changes must not accidentally play aloud.

**Playback control defaults (decided by the product owner on 22 October 2026, PO-39).** Skip intervals default to 15 seconds back and 15 seconds forward, each configurable in whole seconds from 5 to 120, as the G0.4 spike built them (ADR-0006 decision 18). The sleep timer offers both kinds the spike built: after a duration of playback, and at the end of the chapter (decision 19). Resuming after a long pause rewinds by default, graduated as other audiobook players do: about 10 seconds after a pause of a few minutes, rising to about 60 seconds after a pause of a day; M4 sets the exact steps within those bounds and states them in ADR-0006. Each rewind is shown with a brief notice that offers to undo it, returning the playhead to where it paused (its wording comes through the vocabulary, Section 4.4.6), and the rewind is configurable, and can be turned off, in Settings. It moves only the playhead: it never changes a saved bookmark, quote or capture anchor, and, as in ADR-0006 decision 20, it is a seek that never lowers the furthest position. The recommendation was the rewind as a setting, off by default, because a rewind the listener did not ask for moves the playhead; the owner chose it on by default, as other audiobook players have it, and the notice with its undo answers that concern. The G0.4 spike built one rule, off unless set (a pause of at least N seconds rewinds M seconds), which M4 extends to the graduated default; its device check (G0.4 step 17) is pending. (Until 22 October 2026 this paragraph said only that resuming after a long pause may rewind a configurable small amount without mutating a saved bookmark or quote, and draft 0.7 left these defaults to M4.)

Multi-file editions have an ordered manifest and derived global timeline for display. Canonical anchors remain file-local. A changed order creates a new timeline revision; old captures continue pointing to the original files/ranges. A missing member blocks the unavailable segment and shows an incomplete-edition warning; v1 does not market partial remote streaming as complete offline availability.

## 10.2 Audio capture semantics

**Bookmark** means a position only. **Audio capture** means a bounded excerpt with its original source ranges, optional transcript and notes. **Text quotation** exists only when text was actually selected, supplied by the user or transcribed and labelled accordingly. Never generate a quotation from a title and timestamp.

The proposed default Capture action records the preceding 30 seconds of source time, clamped to valid bounds; permit trimming/extension up to 120 seconds through both range handles and numeric start/end controls (Section 4.4.1, principle 5). A cross-file selection stores several ranges. Capturing writes the anchor immediately, then exports a small playable excerpt into retained knowledge storage. User feedback distinguishes "Moment saved · preserving audio" from "Audio excerpt saved" (Section 4.4.6).

Export must use a tested codec path and include actual exported timing, since format boundaries can affect precision. Excerpt format: AAC-LC 64 kb/s, mono for speech (a stereo source is averaged to mono, which keeps speech recorded in both channels at its level, where an equal-power sum raised it by 3 dB), 44.1 kHz, in `.m4a`, at most 120 seconds, about 8 KB per second (mono decided by the product owner on 22 October 2026, PO-19 (a)). The recorded actual timing is what the decoder reports for the first and last exported samples; against the true content it is off by a constant per codec (13.1 ms for the 44.1 kHz MP3 encodes, 47.9 ms for HE-AAC, about 1 ms or less for the others), so each range's source format is stored with the excerpt and a correction can be applied later if a budget needs it. [M0-A24] Media retention must not delete the full source while a requested excerpt export is pending or failed without an explicit warning/choice. If export fails, the saved bookmark and note survive, and the UI offers retry ("Excerpt not preserved · Retry"); it does not claim to have preserved the words or sound.

Once successfully retained, the excerpt remains playable after removing the full audiobook. Excerpts count toward retained-knowledge storage, are included in default knowledge backups and can be removed separately by the user. This is intentionally different from treating every audio highlight as a pointer to a disposable file.

## 10.3 Replay without corrupting progress

Capture preview uses a bounded preview mode with a saved main-player context. It pauses the main session, plays only the excerpt, and returns to the prior book position/state. Preview playback must not update completion, furthest position or main listening-time totals. If a phone interruption occurs during preview, restoration still uses the preserved main context.

## 10.4 Optional transcription

V1 should support **user-requested short-clip transcription**, not whole-book processing. The selected speech adapter may be an OpenAI-compatible transcription endpoint; a configured text-chat server is not assumed to support audio. Transcription uses only the retained clip, not the source audiobook. Official APIs expose file-transcription capabilities, but per-provider/model limits must be discovered or configured rather than hard-coded from marketing names. [S16] Timestamps are a configured capability of the endpoint, never inferred from a model name (OpenAI documents them for `whisper-1` only). [M0-A31]

Require explicit audio-sharing consent and a separate capability test. Queue a local draft when offline; do not automatically transmit it later without the user's selected queue policy. The queue is durable: a queued clip, its configuration and its audio consent survive a relaunch, and consent is checked again when a queued clip is sent. A clip found mid-upload after a relaunch, or whose upload failed with uncertain acceptance, is resent only when the user confirms. A clip has one job, so a second request never uploads it twice or replaces its transcript or the user's correction. [M0-A37] Preserve raw transcript, provider/model, timestamps and user corrections separately. Label machine transcription as potentially inaccurate; users can edit a corrected version before saving it as a quote. When no speech service is configured, the capture detail says so plainly and offers "Set up transcription" and "Type what you heard".

A companion EPUB can be searched for a matching passage; candidates require confirmation and retain provenance. Merely pairing the titles does not map timestamps to sentences. With no transcription or companion passage, Ask AI can use the user's note or selected work text but must say that the current audio passage is unavailable.

## 10.5 External and lock-screen boundaries

Do not capture other apps' audio, inspect private playback data or depend on Spotify authorization in v1. Manual external-source ledger entries remain possible. Standard system playback controls are required; a dedicated lock-screen capture control must pass Stage 0 for supported iOS versions and locked-device persistence before it becomes a release promise (the Stage 0 outcome is in Section 3.3; its device steps are pending) [M0-A26]. Do not repurpose play/skip buttons as undocumented clipping controls.

# 11. Annotations, retained knowledge and search

## 11.1 Capture transaction

A capture command takes the work/edition, source snapshot, exact selected text or audio ranges, optional comment and an idempotency key. Commit the capture, anchors, note and ledger activity in one database transaction. If storage is full, keep the editor content visible and show a save failure ("Not saved · your text is still here"); never dismiss a note that has not been persisted. Text holding U+0000 cannot be stored exactly through the database library's text binding (GRDB binds and reads text as C strings, so Stage 0 saw such text stored cut off at the NUL); the capture and note commands refuse it with a clear message, or remove the character visibly before saving, and never store it cut off. [M0-A55]

Save immutable captured wording separately from editable comments. A user's corrected transcript or cleaned-up quote is a distinct revision with origin metadata; the original is retained unless the user explicitly deletes it. Save AI answers with links to their question/context pack rather than flattening them into unattributed user notes.

Notes may be work-level or attached to a capture. V1 supports plain text with a modest Markdown subset; rich editing, handwriting, note-to-note knowledge graphs and complex project notebooks are deferred. Show related material from the same work without requiring the user to choose categories.

## 11.2 Persistent provenance

A saved source snapshot includes title, author display, edition identifiers when known, chapter/page/timestamp label and source type as observed at capture time. Live metadata may change; the historical snapshot remains available. A capture can therefore be exported meaningfully even after its source is gone or the work's title is corrected.

For AI, preserve the exact evidence snippets actually supplied, request scope, model/endpoint identity without secrets and the user question. Do not promise bit-for-bit model reproducibility; provider implementations may change. The goal is an auditable record of what evidence was available for that answer.

## 11.3 Search design

Use separate indexed surfaces: catalog metadata; retained user knowledge; and extracted source text. Global search defaults to catalog and retained knowledge. "Search this book" uses source text when present. Display result kind and source, including quote versus user note versus generated answer, using the marker set of Section 4.4.5. [S4]

FTS5 lexical ranking is the baseline. Use bound parameters, escape literal user input and prohibit arbitrary FTS syntax unless explicitly offered. Indexing is incremental, cancellable and rebuildable. Search never waits for all 5,000 works to be extracted before showing metadata or saved-note results.

Expose coverage: "Saved thoughts only", "Book text indexed", "Indexing 12 of 40 chapters", or "Text unavailable". Do not label a lexical search as semantic understanding. Vector embeddings and whole-library AI retrieval are future work; the repository boundary accepts another retrieval strategy later.

## 11.4 Deletion and editing

Removing a source file cannot delete a capture. Removing a capture is an explicit knowledge action with undo/trash behavior. Proposed default: 30-day local trash for knowledge records, with immediate permanent deletion available through a clearly described action. Trash is excluded from ordinary AI retrieval/search and included in backup only as identified trash data.

If a user requests removal of retained text, enumerate dependent context packs and saved quotations; deleting an index alone does not erase retained snippets. Offer a separate explicit operation to remove those dependent copies. Do not silently alter evidence inside an already saved AI conversation.

# 12. Consumption ledger, ratings and recommendations

Maintain a Work-level permanent history with one or more **ConsumptionRuns**. Suggested states are planned, in progress, paused, finished and abandoned. Reading and listening have edition-specific positions within a run; they do not become one synchronized percentage merely by sharing a Work.

Completion is explicit or confirmed after a detected end. Seeking to the last second is not evidence of listening to the entire book. Let users mark completion, correct dates, record prior reading and start a reread without overwriting the original run. Preserve latest position, furthest comparable position and completion as distinct facts.

Listening sessions use observed playback intervals; report real active elapsed time separately from source-duration progress when playback speed differs. Audio's furthest position is derived from observed contiguous main playback, never from a seek: a listening run that starts ahead of the furthest point becomes it after 30 seconds of contiguous listening, so a skip followed by listening does not freeze progress and a jump alone never moves it. The furthest position is therefore a place reached by listening, not proof that everything before it was heard; listening time counts only intervals in which the media advanced. [M0-A25] Reading time is an estimate based on foreground activity and idle thresholds, not proof of attention. Never infer reading progress from an AI answer, note preview or an open screen left unattended.

A proposed rating is nullable, 0.5-5 stars in half-star steps stored as integer 1-10, drawn with the rating component in Section 4.4.7. A clear rating is null. Keep the scale explicit in export rather than storing a bare number with an undocumented meaning. Support an optional short review note.

Recommendation events support inbound and outbound direction; a person, podcast, article, other work or free-text source label; date or approximate date; and a reason. One work may have many events. Outbound events mean "I recommended this", not that Sylvia sent a message. No contacts permission, messaging integration or automated recommendation delivery is required.

Allow a metadata-only physical/external work with manually entered page number, chapter or listening position. Mark those positions as manual and edition-specific. A photo of a page, automatic ISBN scanning and external playback observation remain later capture adapters.

Removing a book's last local file changes its action from "Read/Listen" to "Add file" or "Download from source" while leaving the title and record intact, with the availability badge "Record only" or "Not on this device · from {source}". The ledger must be visible and searchable even when no source location remains reachable.

# 13. Context assembly and source-aware AI

## 13.1 Context is a product surface

The user chooses among **selected passage**, **selected passage plus nearby text**, **search this work**, or **selected saved thoughts**, presented as scope chips with the labels fixed in Section 4.4.6. Default to the narrowest relevant context. For work search, retrieve bounded excerpts and say "Relevant passages retrieved", not "The AI read the entire book". The chip that chooses work search reads "Relevant passages from this work" (Section 4.4.6).

Whole-book inclusion is allowed only when the entire extracted text fits the configured input budget and the user explicitly chooses it. It is unavailable while "Do not include later passages" is on: a pack limited by a spoiler boundary is never labelled whole book. [M0-A34] Comprehensive whole-book summarization with exhaustive chapter coverage is not a v1 guarantee. The interface must not claim completeness based on a handful of retrieved chunks.

A ContextPack is built and stored before sending a request. It contains the user question, evidence snippets with stable local IDs, source/edition anchors, source-quality labels, scope, prompt-template version, retrieval settings, available-text coverage and any truncation. Persist exact sent snippets so the conversation remains understandable after media/index removal. Earlier turns of a conversation are content too: each turn records what it shared and where it went, and is resent only to the same destination (origin, classification and model). Decided by the product owner on 22 October 2026 (PO-27 (c)): switching provider or model starts the new destination without earlier turns, with a stated reason. Earlier drafts asked for consent again when the destination changed (Section 14.2), which kept the conversation going, so this is a narrowing that no failed spike forces; the alternative asks the user whether to resend the earlier turns, with consent for the new destination, and was not chosen. [M0-A34]

M5 offers **Explain** and **Simplify** inside Ask as editable question starters. Explain asks what the selected passage means in context; Simplify asks for a plain-language rendering that preserves its meaning. Both prepare a question for review and explicit Send through the normal endpoint, scope, consent and request lifecycle. Opening Ask or choosing a starter sends nothing and never widens the evidence scope. Generated wording remains labelled Generated and does not replace the quotation. Native dictionary lookup stays a separate action. New labels and prompt templates follow the design-vocabulary and prompt-version rules. [P3, S25]

Keep follow-ups in the same source-linked conversation without requiring another selection. The latest answer and composer are easy to reach; earlier turns may collapse but remain available. Each request saves its own ContextPack and applies the context budget, spoiler controls and destination consent in Sections 13.2, 13.3 and 14.2 to any included history; retaining a conversation in the interface does not authorize sending all its turns. Citations in earlier turns remain bound to their original ContextPacks; when history is supplied to a new request, those markers must not be interpreted as IDs in the new pack. Preserve the question draft when the sheet closes or a request fails, and preserve partial answers with their actual lifecycle status (Section 14.4). Closing the discussion restores the reading context. T56 exercises this flow on compact and wide layouts.

## 13.2 Retrieval algorithm

For a text selection, prioritize exact text and bounded adjacent paragraphs from the same resource/page. For work search, run lexical search over that work's extracted text and optionally its retained knowledge, rank/deduplicate overlapping hits and include a limited number of adjacent chunks. Begin with 300-600-word extraction chunks preserving paragraph boundaries; tune using retrieval tests rather than treating this size as universal.

For audio, use a confirmed companion passage, transcript or user note. Do not turn a timestamp into assumed textual evidence. For a manual physical record, use entered quotes/notes only. Allow users to select up to a small reviewed set of saved passages across works for comparison; automatic whole-library semantic research is deferred.

Build the budget from the configured model context limit minus system text, question/history, output reserve and safety margin. Default unknown models to a conservative configurable budget (an 8,192-token context, approved by the product owner on 22 October 2026, PO-24), and disclose truncation. Use a model-appropriate tokenizer where supported; estimates must be labelled (without a bundled tokenizer, Stage 0 estimates UTF-8 bytes divided by 3, which over-counts English). [M0-A35] A context-length error reduces scope with user-visible explanation, not silent evidence deletion.

## 13.3 Spoiler controls

Default to selection plus nearby context. Offer "Do not include later passages" where ordered text anchors make the boundary enforceable. Filter retrieval before sending; do not merely ask the model not to spoil material it already received. Cross-edition audio-to-text progress cannot enforce a precise spoiler boundary without an alignment; use a user-confirmed chapter/passage boundary or state the limitation. A selection after the confirmed position is refused with an explanation (move the position or turn the setting off); it never widens the boundary silently. Positions are extracted-paragraph ordinals of one edition: the boundary has paragraph granularity (later sentences of the selected paragraph itself can be retrieved, never a later paragraph), and a saved thought or earlier turn from another edition has no known place, so a restricted pack leaves it out. [M0-A34]

Do not advertise guaranteed spoiler-free answers. A model may have prior knowledge. Prior conversations that used later passages must be excluded from a restricted context pack; start a clean restricted thread rather than leak older full-book content back into the prompt.

## 13.4 Grounding and citations

Delimit source material as untrusted evidence, not instructions. Ask the model to distinguish source-based statements from general explanation and to reference local evidence IDs. No tool invocation or automatic network fetch follows an instruction found in a book, note or provider response.

After generation, resolve citation IDs against the ContextPack allowlist. Invalid IDs remain visibly unresolved and are not turned into fabricated links; they render as struck-through grey chips with a one-line explanation beneath the answer (Section 4.4.5). A citation opens the exact retained snippet and, when available, the original anchor. Validate claimed direct quotations against supplied evidence; unverifiable wording is labelled as a paraphrase or unsupported quote, not an exact source quotation. The rule, decided by the product owner on 22 October 2026 (PO-25 (a)): a quotation of three or more words is exact only when its words and punctuation match one supplied passage as whole tokens, letter case included except its first letter, with each ellipsis segment at least three words long; whitespace, quotation-mark and dash styles, invisible characters and edge punctuation are normalized. One- or two-word quotations get a "short quoted phrase" label, never "exact". Citation IDs are local to one pack: an earlier answer resent with a request has its citation markers replaced by "[earlier source]". [M0-A36]

Citation validity does not establish entailment. Include human evaluation for whether the cited passage actually supports the answer. Saved AI content should retain a model-generated label and permit user comments/corrections. When evidence is insufficient, the expected behavior is to say so or ask for a passage, not invent the contents of the book.

M5 adds an evidence preview to citation navigation: tapping a resolved citation opens the exact retained snippet from that answer's ContextPack, with its source and location. Offer a separate action to show the passage in the reader only when the original asset and anchor resolve; returning preserves the answer, draft and prior reading position. With missing media or an ambiguous anchor the retained snippet remains available, and the unavailable source action explains why. Invalid citation IDs retain the unresolved treatment above. Preview and navigation must work by touch, keyboard and VoiceOver without depending on hover (T57). [P3, S25]

# 14. AI providers, privacy and failure handling

## 14.1 Provider contract

Define separate `TextGenerationProvider` and `SpeechTranscriptionProvider` interfaces. Text generation accepts a provider-neutral request and returns a stream of text/status/usage events. Speech accepts a bounded local clip and returns text plus available timing/provenance. Model listing and token counting are optional capabilities, not prerequisites for configuring a custom endpoint.

V1 text adapters: **OpenAI API**, **Anthropic Messages API**, and **generic OpenAI-compatible chat API**. Start the OpenAI text path with a documented supported API and integration tests (the Responses API, with `store: false` on every request, because OpenAI stores responses by default; approved by the product owner on 22 October 2026, PO-24) [M0-A31]; the generic compatibility contract is `/chat/completions` relative to an explicitly configured API base (it refuses the first-party hosts, which always use their own adapters; decided by the product owner on 22 October 2026, PO-26 (a)) [M0-A31]. Anthropic gets its own request/stream adapter rather than being forced into OpenAI's payload. [S17-S18]

Configuration includes provider kind, display name, base URL, model identifier, credential reference, supported capabilities, context/output limits, optional request timeout, and privacy classification. Normalize base URLs once; avoid producing `/v1/v1/...`. Permit manual model entry because many local servers do not implement model discovery correctly. Do not hard-code a current model name or subscription tier into domain logic.

Hermes works as an optional compatible endpoint if its configured route passes conformance tests. The connection test is that conformance check: it passes only when the reply ends normally with answer text, so a route that answers with a tool call, a refusal, a filtered reply or reasoning that reaches its output limit is shown as not usable; the route's maximum output is part of its configuration (default reserve 1,024 tokens). [M0-A31] The client cannot guarantee that a gateway is local-only simply from its address: the gateway could forward to another provider or run tools. Label this as a user-managed connection; require the operator to configure an appropriate text-only/no-side-effect route. Sylvia itself does not expose execution tools or silently grant access to the device library.

## 14.2 Credentials and consent

Store user credentials only in Keychain; never in SQLite, exported configuration, a bundled application secret, analytics, logs or screenshots. A key is bound to the origin it was entered for, in its Keychain item and its reference: editing a configuration's base URL to another origin, or importing a configuration that names a key beside another origin, requires entering the key again, and no provider sends a key to another origin. [M0-A32] Ship no developer-owned provider key. Bring-your-own-key mode uses the user's own credential on their device; public distribution needs security review of this choice and a gateway option for users who prefer not to store a provider key in a mobile client.

Keep AI credentials inaccessible while locked where the selected interaction does not require them; transfer credentials may need after-first-unlock device-only accessibility to support authorized background transfers. Choose accessibility classes deliberately and test them after reboot/lock. Credentials do not migrate through Sylvia backups; restoration requires reauthentication/pairing. [S21]

Before the first request to an endpoint, show the destination host, whether it is local/user-managed/hosted, what will be sent, and that the endpoint operator's policies apply. The same disclosure appears as a persistent row on the Ask screen ("{host} · hosted · {model}"; Section 4.4.6). Reconfirm when the destination changes or the user broadens sharing to notes/audio. Earlier turns resent with a request count toward consent and are named in the disclosure. [M0-A34] Apple requires explicit permission and disclosure when personal data is shared with third-party AI; a generic privacy policy is not the entire consent experience. [S19]

No automatic fallback between providers. No invisible upload of whole books, page images, contacts or recommendation relationships. Use selected evidence rather than bulk files. Do not claim provider-side zero retention unless independently supported by the user's actual provider/account configuration.

## 14.3 Network policy

HTTPS is the default. Paired Mac connections use the validated trust design in Section 15. For manually configured local inference, allow a narrowly scoped, explicit HTTP exception only for eligible local endpoints and only if the minimum OS's ATS behavior passes testing. No phone on hand runs the minimum OS, iOS 26.0, so the product owner decided on 22 October 2026 (decision D-9 (b) of the device runbook) that Sylvia ships `NSAllowsLocalNetworking` with its own endpoint rules below as the cleartext gate on every OS version, an exception recorded in ADR-0011: the exception then rests on rules tested on the host and the simulator, not on an untested OS version's ATS behavior, and the device run (G0.5 AI step 1, pending) still records ATS on the phones on hand. Unrestricted cleartext internet endpoints are rejected. Do not globally disable App Transport Security to support a convenient development server. [S12-S13] Stage 0 found that ATS cannot be relied on for local addresses: on the iOS 26.5 simulator, cleartext HTTP to loopback, private IP addresses and `.local` names loaded even with no ATS key (G0.2 and G0.5), contrary to Apple's documentation for iOS 17 and later, while public addresses and qualified names were blocked. Sylvia's own rules are therefore the enforced ones, on every request path and with tests: the transfer client builds only `https` URLs to a paired source, and the AI client allows cleartext only when the user enabled it for that endpoint, the host counts as local, the endpoint is classified local and the adapter is not a first-party one. Which hosts count as local was decided by the product owner on 22 October 2026 (PO-36 (a); the security sign-off pending until the device evidence): only IP literals in the loopback, private and link-local ranges, because a name can be spoofed or rebound. That narrows the local HTTP exception, and no failed spike forces it: a local model server reached by name (`localhost`, a `.local` name) or over a tailnet (a 100.64.0.0/10 address, which is also carrier-grade NAT space, or a MagicDNS name) needs HTTPS. The alternative, not chosen, was an explicit per-endpoint exception for such names and addresses, which rests on name resolution and on the tailnet's routing. The ATS key is `NSAllowsLocalNetworking`, by the decision D-9 (b) above; until 22 October 2026 this section left the key to the device run. [M0-A14]

A Tailscale IP/name is a connectivity route, not evidence that an HTTP hop is encrypted end-to-end all the way to the model host; subnet routing and proxies can change the boundary. Recommend HTTPS even on a tailnet, and explain any exception (under the rule decided above, a tailnet endpoint gets none) [M0-A14]. Do not use a `.local` name as the sole security check or allow a remote redirect to inherit local trust.

Connection tests classify failures: DNS, permission denied, host unreachable, TLS/pin mismatch, authentication, unsupported model, unsupported API dialect, rate limit and invalid response. Display actionable diagnostics with secrets removed. Avoid a generic "AI failed" for every cause. Local Network denial is detected with a documented check (a plain connection attempt whose network path reports the denial), not from an undocumented error key, and its next step points to Settings. [M0-A32]

## 14.4 Request lifecycle

Persist user question and ContextPack before sending. States: `draft -> awaiting_consent -> ready -> sending -> streaming -> complete`; alternatives are `cancelled`, `interrupted`, `failed_retryable`, `failed_final`. User-visible names are fixed in Section 4.4.6. Save partial output periodically, clearly marked "Interrupted · partial answer". Only a normal end with visible answer text ends `complete` with outcome `answer`, and only that reads "Complete". After some answer text, any other end, a refusal or content-filter stop included, ends `interrupted` and is shown as a labelled partial answer. With no answer text, a refusal or content-filter stop ends `complete` with outcome `refusal` or `content_filtered` and shows its classified message instead of "Complete", and any other end (reasoning only, or an output limit reached first) ends `failed_retryable` (a context-window stop `failed_final`), a failure whose resend needs confirmation. A request ID has exactly one record: a second draft never rewrites it, sending is single-flight per request, and a stop is honored at any point, including before the request leaves. [M0-A33] Do not save provider-internal reasoning as a user-facing answer; process supported answer/status fields only.

On offline submission, save the question as a draft and show "Draft · not sent" with "Saved on this device". The default, approved by the product owner on 22 October 2026 (PO-24), is manual send when connectivity returns, avoiding unexpected later API costs or privacy changes. An opt-in auto-send policy can be reviewed separately.

Retry transient connection and 429 failures, and 503 or 529 from a hosted or local endpoint, with capped exponential backoff and Retry-After when available. Treat every other 5xx (a 500, 502 or 504 among them), and any 5xx from a user-managed endpoint (which may be a gateway), as uncertain: the generation may already have been accepted and billed upstream, so the user confirms before a resend (decided by the product owner on 22 October 2026, PO-27 (a)) [M0-A33]. Do not automatically replay a generation whose acceptance is uncertain: the first request may already have incurred a charge. Use idempotency only where the provider actually documents it; otherwise ask the user before resubmitting an uncertain generation. Never duplicate the visible question or conversation on retry.

Use bounded streaming parsers tested against split UTF-8 characters, partial SSE events, keepalives, tool-call responses, refusal responses and malformed JSON. Reject unsupported tool calls without executing them. AI is foreground work in v1; suspension may interrupt streaming. The saved question/evidence remains, and the app does not promise that generation continues while force-quit.

## 14.5 UX, costs and user control

Within Ask, provide Explain, Simplify, Define in context, Summarize this passage and Ask a question. These are editable question starters governed by Section 13.1's preview and explicit Send behavior. Simplify requests plainer wording while preserving meaning; Summarize requests a shorter account of the passage. Save all explicitly sent interactions locally, with a separate "Save to Thoughts" action to promote an answer. Allow deleting a conversation with a clear explanation of retained evidence deletion.

Show provider/model and context preview before sending; display usage only when supplied reliably. Show a price estimate only when a maintained/user-configured pricing profile is available, and label it an estimate. No invented "free because you subscribe" messaging. Cap request/output sizes and audio duration rather than allowing accidental unbounded jobs. A request timeout alone is an idle timeout that a trickling server never trips, so every response also has a wall-clock and a size limit. The values, approved by the product owner on 22 October 2026 with A35: a streamed response body at most 1 KiB per requested output token (at least 4 MiB) within 600 seconds; a single JSON answer at most 8 MiB; answer text at most 16 characters per requested output token (at least 32,768); a transcription response at most 4 MiB within 300 seconds; uploads at most 25 MB (OpenAI's documented upload limit) and 5 minutes of audio, the G0.5 spike's defaults, unless the endpoint is configured otherwise. A response stopped at a limit keeps what arrived, labelled partial. [M0-A35]

# 15. Secure, resumable Mac-to-device transfer

## 15.1 Connectivity model

The **Mac hosts a source service; the phone is a client**. The app can discover the service through Bonjour on a LAN and can connect through a manually entered address or pairing payload. It never relies on the iPhone running a permanent local web server. The source must be awake, running and reachable; otherwise jobs wait without losing verified progress.

Register a product-specific Bonjour service type and request local-network permission in context. Manual-address connection is required because multicast discovery must not be assumed across VPNs. Support an explicitly entered Tailscale address/MagicDNS name through ordinary networking; do not build a Tailscale client, demand a public port, or require a cloud relay. [S12, S20] **Stage 0 result (failed gate rows):** with the pinned self-signed Mac identity and no App Transport Security key, iOS refuses a Tailscale address (100.64.0.0/10) and a MagicDNS name (`*.ts.net`) after the pin has matched, because ATS applies default trust to those hosts. Decided by the product owner on 22 October 2026 (D16, PO-07 (a)): a scoped ATS exception for `ts.net` and `100.64.0.0/10`, measured working on the simulator, under which the pin stays the only trust decision and the client itself refuses any non-`https` URL, because the exception also permits cleartext to those hosts and covers every tailnet name, not only the user's Mac (ADR-0008). The decision holds if the security reviewer approves the exception; the product owner gives that sign-off personally once G0.2's device steps have tested it on a phone (steps 6 and 23, pending), and a contrary device result reopens the decision before M6 builds the route. If the exception is not approved, v1 offers no Tailscale route and XFER-04 narrows to LAN addresses, `.local` names and manually entered LAN addresses. [M0-A13]

V1 is pull-first. "Send to device" on the Mac adds an item to the device's source queue; the phone fetches it when it connects. Without a push infrastructure, that command cannot reliably wake a force-quit phone. Status must distinguish queued, observed, downloaded and imported. No real-time notification promise is made. Decided by the product owner on 22 October 2026 (PO-13 (b)): the phone reads the device inbox on launch, on returning to the foreground and when the Inbox is shown, while a paired Mac is reachable, and also periodically in the background whenever iOS gives the app background time. iOS runs that background read only when it chooses, so it is opportunistic and adds no promise of timely delivery: no real-time delivery is promised, as above. (The recommendation was the foreground reads alone, because background refresh is opportunistic; the owner chose to add the periodic background read.) [M0-A15]

## 15.2 Pairing and trust bootstrap

Default (D07, approved by the product owner on 22 October 2026; the security sign-off of the pairing protocol pending until G0.2's device steps have run): the Mac generates an identity key/certificate plus a single-use invitation. A **pairing payload** contains protocol version, stable source ID, one or more endpoint addresses, the full certificate/public-key fingerprint, a high-entropy invitation secret and expiry. Present it as a copyable code and optionally a QR code, scanned only with Sylvia's own scanner. Earlier drafts also offered a link. A custom-scheme link (`sylvia://`) can be claimed by another installed app, which would then receive the pin and the secret, so the product does not advertise such a link for the system Camera or other apps, as the product owner decided on 22 October 2026 (PO-11 (a)); keeping it would have needed the security reviewer to accept that interception risk, and a universal link can replace it if Sylvia gets a verified domain. [M0-A16] The iPhone obtains the trust fingerprint through that user-mediated channel before transmitting the secret.

Validate the peer against the pinned identity, exchange the invitation for a scoped per-device credential, and invalidate the invitation. Use at least 128 bits of invitation entropy, a short expiry and attempt limits. The values, decided by the product owner on 22 October 2026 (PO-10 (a), with no global cap unless the security reviewer asks for one; the security sign-off pending): a 256-bit single-use secret, consumed when presented, before the approval prompt; a 10-minute default expiry, configurable from 1 to 60 minutes; five wrong secrets destroy the invitation; ten pairing requests per address per minute; a Mac approval prompt that expires after 120 seconds. [M0-A16] Display the device identity on both ends, with the fingerprint in the Monospace face grouped in fours, and let the Mac user approve it. Store secrets in Keychain; do not put invitations in logs, analytics or pasteboard history managed by Sylvia. Clear the app's temporary pairing state after completion.

A six-digit number over an unauthenticated connection is **not** the security design. A shorter human-only code requires a reviewed PAKE/authenticated pairing implementation; do not invent a new cryptographic protocol. The copyable invitation is the baseline, approved by the product owner with D07 and awaiting the security sign-off, for meeting one-time pairing without custom cryptography.

After pairing, verify the pinned identity on every connection. A changed source key requires explicit re-pairing; never present a generic "ignore certificate error" switch. Tokens are scoped to catalog/read/download/receipt operations, not arbitrary file access or source deletion. Revocation stops future access; it cannot erase files already imported by a device.

**Stage 0 gate:** prove the selected TLS identity/pinning path works with iOS background URLSession and the intended address forms. The app cannot bypass trust validation to achieve background transfer. If this combination fails, the team must choose a validated certificate-based alternative or a clearly foreground-only resumable mode before approving release promises. G0.2 result (simulator; device steps pending): the pinned identity works with background URLSession for loopback, LAN IPv4 and `.local` addresses; Tailscale address forms fail without an ATS exception (Section 15.1, D16). [M0-A13]

## 15.3 HTTP contract

All API paths are versioned. This is a proposed contract to turn into OpenAPI and fixture tests at kickoff, not a claim that a server already implements it.

| Method and path | Purpose | Required behavior |
| --- | --- | --- |
| GET `/v1/capabilities` | Protocol compatibility and limits | Minimal unauthenticated data only; no library titles |
| POST `/v1/pair` | Exchange invitation after trust bootstrap | Single-use secret, source binding, expiry, approval and rate limits |
| GET `/v1/catalog?cursor=...&limit=...` | Browse selected source entries | Authenticated, stable pagination, metadata and immutable versions |
| GET `/v1/items/{id}/manifest` | Exact asset/group description | File sizes, digests, ordered members, chunk size/hashes, manifest version; 503 `preparing` with `Retry-After` while a snapshot takes more than 10 seconds to prepare, and the client polls [M0-A17] |
| GET `/v1/assets/{id}/content` | Download verified immutable bytes | Single Range support, strong ETag/If-Match, Content-Length, no transformation |
| GET `/v1/device-inbox?cursor=...` | Pending items queued for this device | Cursor and immutable item versions; no implied automatic import |
| POST `/v1/receipts` | Record download/import result | Idempotent receipt ID; no deletion of original source |
| DELETE `/v1/pairings/{device_id}` | Revoke a paired device | Owner-approved on Mac, or self-revocation for the authenticated device |

All endpoints except capability discovery and the pairing handshake require scoped authentication. Validate every supplied ID; never interpolate a remote path into filesystem access. No wildcard CORS or web browser exposure is needed. Reject protocol-major mismatches with an understandable update message; tolerate additive optional fields.

## 15.4 Manifest and resumability

The Mac prepares an immutable snapshot for each active file version. The manifest identifies the bytes, not a mutable file path. If the selected original changes, create a new version and invalidate old unserved manifests rather than mixing old and new ranges. Active transfers either read a managed immutable snapshot or fail on change; a checksum failure at the end is not the only defense against mutation.

Part size: 16 MiB, configurable by protocol capability. Each part has an offset, length and SHA-256. The phone persists part completion only after validating the received bytes and retaining them on disk. Use background URLSession download tasks for eligible parts and restore OS task associations on launch. Two in-flight transfers and bounded queued parts avoid overwhelming system scheduling. Stage 0's values, kept by the product owner on 22 October 2026 and tuned after the device measurements (G0.2 steps 11 and 13, pending; PO-09): at most four outstanding part tasks per job, two connections per host, 16 MiB parts. A background download task stores the whole response body before the app can inspect its head: the head is checked before the file is opened, and an over-long body can be cancelled only while the app runs. Each outstanding task also holds its request, bearer token included, inside the system's transfer daemon until it ends; the task window bounds those copies per job, and in the Stage 0 spike nothing bounds them across jobs: N jobs from one Mac downloading at once hold up to 4N requests carrying that Mac's token. Decided by the product owner on 22 October 2026 (PO-38 (a)): the job scheduler (Section 6.4) lets two jobs download at a time and queues the rest, so at most eight requests carrying a token wait in the daemon; the alternative, a bound on the outstanding tasks across all jobs, was not chosen. A pause or revocation cancels a job's tasks, and the behavior is re-checked with each iOS release. [M0-A15]

Requests use a single byte Range and If-Match tied to the manifest version. Accept only a correct 206, matching Content-Range and expected length/digest. A 200 for a partial request, 412, 416, changed ETag, unexpected encoding or changed manifest pauses/restarts explicitly; never append it to a previous partial file. Retry a failed part, not verified parts from the same immutable version. The manifest refresh that a 412, 416 or changed ETag calls for is a foreground request: if the app is suspended first, the job waits and continues at the next launch (Section 15.5). [M0-A15]

After all parts verify, assemble or finalize through a journalled file-store operation; verify the complete SHA-256; then hand the asset to the normal importer. Keep 100% received distinct from 100% verified/ready. Disk reservation must account for temporary parts plus any assembly copy. Prefer a tested sparse/preallocated staging strategy to avoid double storage, but preserve recoverable part records until final validation succeeds.

Ordinary third-party URL downloads may use URLSession resume data and HTTP validators opportunistically, but do not inherit the Mac protocol's guaranteed immutable parts. If the origin cannot resume safely, explain that a restart is required. Wired Finder transfers share validation and commit logic, not resumability guarantees.

## 15.5 Recovery and visibility

On launch, reconcile persisted jobs, OS task IDs, part files and manifests. Use stable task descriptions containing a job/part ID, not secrets. Detect missing local parts and re-fetch only those. A stale/expired credential blocks access until reauthentication; it must not erase already verified bytes. A revoked pairing never silently reconnects with a broader credential.

Show current file, verified/total bytes ("3.1 of 5.2 GB verified"), stage, pause/resume/cancel and the blocking reason. Throughput/time remaining are estimates only while data is flowing. A phone force-quit, Mac sleep or network denial results in a resumable state and clear next step. No fixed completion-time promise is part of the UI. The background promise is "continues in the background when iOS allows it, and resumes from verified parts whenever Sylvia runs", not uninterrupted completion while the phone is locked (decided by the product owner on 22 October 2026, PO-08 (a)); whether more part tasks are created while the app is in the foreground is decided after the device run (G0.2 step 13, pending), as that decision provides. A damaged transfer store (the job store, the sources file with each paired Mac's pin, or the import ledger) is never overwritten; the Stage 0 spike keeps the client's launch deferred when one is damaged. Decided for the job store by the product owner on 22 October 2026 (PO-12 (a)): it is moved aside for the diagnostic export and its jobs restart from the Mac. For the other two the recommendation proposed no repair path and no default, so approving PO-12 as recommended chose nothing for them that day. Decided for the sources file and the import ledger by the product owner on 23 October 2026: each is set aside and recovered. A damaged sources file is moved aside for the diagnostic export and every Mac is paired again; a damaged import ledger is moved aside, giving up its exactly-once record, so an item already imported may arrive again as a duplicate for review (Sections 7.3 and 8.1); transfers keep working. The transfer client built in M6 has these three repairs. (Until 23 October 2026 this paragraph left the repair path for a damaged sources file or import ledger to the product owner, a damaged one keeping the launch deferred until it was decided.) [M0-A15] A background relaunch gets limited time, so the full-file check that follows the last part may finish only the next time Sylvia runs; whether that check and the receipts run inside a background-task window is decided after G0.2 device step 22. [M0-A15]

# 16. Lightweight macOS companion

## 16.1 Product boundary

The companion exposes selected folders/files, lets the user group an audiobook, pairs trusted devices, queues files and shows transfer state. It exports wired `.sylviapack` bundles and provides a Finder handoff guide. It is not a desktop reader, full annotation app, canonical knowledge database or Calibre replacement. It uses the same design tokens, type roles and status vocabulary as the iOS app through the shared design package (Section 4.4.9), with macOS control sizing.

Start with user-selected folder access and explicit file picks. Use sandbox-compatible access/bookmarks and handle permissions being revoked, drives disconnecting and network shares becoming unavailable. Show source health. Preserve the original structure; do not rename, convert, move or delete source files.

For Calibre, v1 supports user-selected exported files/folders as ordinary sources. Direct reads/writes of Calibre's live database, custom-column mapping and live catalog integration are deferred to an adapter proposal. This avoids depending on Calibre internals or rewriting its organization without approval.

## 16.2 Source index and queue

Keep a small local index with opaque item IDs, known sizes, modification metadata, digest state and prepared snapshots. Enumerate incrementally; lazy-load thumbnails and compute hashes on demand/background rather than blocking a 5,000-item folder on first open. Detect the source changing between hash and serving. Explain "Preparing transfer" separately from copying to the phone. Prepared snapshots are APFS clones when the source and the companion's snapshot store share an APFS volume; otherwise preparation is a full copy, which costs space and time, so the companion checks free space for it first and shows progress while "Preparing transfer" (ADR-0009). Preparation time on slower Macs and external drives is not yet measured. [M0-A17]

The outbound queue is durable on the Mac. Users may add files while the phone is off; delivery waits until a connected phone requests them. This supplies a modest queued handoff without pretending that the Mac app is the future always-on Docker hub. Its queue does not accept autonomous book-acquisition tasks in v1.

Receipts are idempotent. A lost receipt may be retried without importing a duplicate. The Mac must not treat successful HTTP delivery as proof that Sylvia committed the library item; the companion shows the three receipts "Queued on Mac", "Downloaded to phone" and "Imported into Sylvia" as separate states. Display import failures returned by the phone and retain the source/queue entry for retry.

## 16.3 Distribution and service lifecycle

Proposed initial distribution is a signed, notarized Mac app for the testing group; public distribution is a product/release decision. Use no privileged helper, USB driver or kernel extension. The companion is signed with a keychain access group so that its identity key is stored in the data-protection keychain; with a missing entitlement it fails to start rather than fall back to a weaker store. [M0-A17] The transfer service runs while the companion is running. Start-at-login is opt-in and reversible, not an invisible daemon installed by default.

Allow the user to stop serving immediately and revoke devices. Bind only intended interfaces, with LAN serving explicit. A private network is not a substitute for authentication. Transferred items remain limited to selected source roots and immutable prepared snapshots.

## 16.4 Wired flow

The Mac companion's "Prepare for cable transfer" produces a bundle and shows the exact steps: connect/unlock/trust the iPhone in Finder, choose Files -> Sylvia, copy the bundle, wait for Finder completion, then open Sylvia's import inbox. This relies on Apple's supported file-sharing flow. [S7, S22]

On device, Finder-visible Documents is an **inbound drop area only**. Put the library database, private notes, credentials, retained text and knowledge clips elsewhere. Staged bundles may be cleaned up only after successful import or explicit user action. Stage 0 reads "successful import" as the bundle's contents being durably staged in Sylvia's private storage, from which the import continues and can be retried, and the product owner approved on 22 October 2026 (PO-14) that the app then removes the transport copy from Documents, but only if it is still the file that was validated, so a newer copy Finder wrote meanwhile is kept; a rejected or partial bundle stays until the user removes it. [M0-A20] Deleting a file through Finder must never delete the permanent catalog.

# 17. Storage, retention, export and recovery

## 17.1 Storage classes

| Class | Examples | Default policy |
| --- | --- | --- |
| Permanent knowledge | Ledger, ratings, recommendations, captures, exact quotes, notes, saved AI evidence, retained audio excerpts | Keep until explicit deletion; include in knowledge backup |
| Original media | EPUB, PDF, full audiobook and companion assets | User-managed; audio removal encouraged after completion, never automatic in v1 |
| Derived source content | Full extracted text, optional transcripts, location maps; remuxed playback copies of long audio members (Section 8.3), each about the size of its original, removed with their source [M0-A22] | Keep while source is retained; separate retain-after-removal choice |
| Rebuildable indexes/cache | FTS index, thumbnails beyond canonical cover, renderer caches | Rebuildable; removable without deleting user-authored knowledge |
| Staging/recovery | Partial transfers, import bundles, commit journals | Keep for live operations; visible cleanup policy for abandoned jobs. The staging and recovery directories and the App Group handoff inbox are excluded from device backup [M0-A20] [M0-A29]; a commit journal or intent kept in the library is backed up with it, and a bundle the user leaves in the Documents drop area stays backup-eligible [M0-A20]. Each component that keeps files in staging owns one subdirectory and cleans only its own, so a persistence cleanup never removes intake's staged imports; the recovery copies keep one pre-migration snapshot and one failed copy, and each pre-restore copy until the user removes it, listed with their sizes and a remove action; the product owner decided on 22 October 2026 that for V1 they are kept until the user removes them, with no age-based expiry, which is revisited with the M7 retention controls (PO-40 (a)) [M0-A29] |
| Secrets | Provider keys, device tokens, pairing identity | Keychain only; excluded from exports |

Distinguish durable saved evidence from a full extracted book corpus. Full text is content, not merely harmless metadata; the user must understand that retaining it can preserve almost the entire book after the EPUB is removed. Embeddings, if added later, are also derived content with their own deletion policy.

## 17.2 Deletion UX

Use separate actions: **Remove download**, **Manage retained text**, **Remove excerpt audio**, and **Delete record and thoughts** (the library record and its associated knowledge; labels per Section 4.4.6). Never place the destructive last action behind an ambiguous trash icon on an audiobook download. The destructive action is styled per Section 4.4.7 and never sits beside a primary button.

Before removing a full audiobook, show the impact report (Section 4.4.7): retained knowledge counts, excerpt export failures/pending work, expected space freed and recovery sources. When an excerpt is still being preserved, the safe choice ("Wait, then remove") is the primary button. Pins and active playback prevent automatic removal. Proposed v1 default is manual removal; scheduled rules such as "remove finished audio after 30 days" are deferred until safety is demonstrated.

Removing EPUB/PDF offers an explicit text-retention choice, with the permanent quote/note/evidence exception explained. Source text required by saved ContextPacks remains as exact retained evidence even when the general text corpus is removed. A separate "erase retained content copies" operation must identify those dependencies rather than mislead the user.

## 17.3 Backup format

Ship a versioned `.sylviabackup` container with a manifest, consistent database snapshot, portable JSON exports, Markdown notes/captures, canonical cover thumbnails, retained excerpt audio and content digests. Format v1 was proven as a directory bundle; the single-file form uses the `.sylviapack` archive rules of Section 8.5 (the strict layout check, then the same path, link, size, digest, entry-count and expansion limits) before the backup validator runs. Until it exists a backup is a directory bundle, which may not survive every share or AirDrop path as one item. [M0-A19] Include extraction-independent anchors and evidence snapshots. Full originals and full derived source text are optional and enumerated. FTS indexes may be excluded and rebuilt.

The default knowledge backup must preserve every acknowledged user knowledge item, including saved audio excerpts and AI evidence. Do not make a "complete backup" claim when original media is excluded. The export manifest records schema versions, counts, included/excluded classes, creation time, originating device ID and digests. No credentials or active pairing tokens are exported.

V1 exports are unencrypted containers with a prominent privacy warning and user-chosen destination. The team must approve this limitation for the release audience: the product owner approved it on 22 October 2026 for internal and TestFlight use, to be revisited at the public-release gate of Section 18.4 (PO-22 (a), D10); the security sign-off of the unencrypted format is pending until the device evidence (Section 23.3). Do not invent custom backup encryption; password-protected portable export needs a separately reviewed library/format. The application's device protection does not follow an exported file to an unprotected destination.

## 17.4 Consistent export and restore

Take a consistent database snapshot, freeze a manifest of referenced retained blobs, and hold temporary retention leases so cleanup cannot remove blobs during export. Leases expire (one hour in Stage 0) so that a crashed export cannot pin blobs for ever, and a running export renews them. [M0-A29] Exporting notes while the user reads is allowed, but capture the snapshot boundary and do not mix incompatible revisions. Finalize the container atomically and verify it before declaring success.

Restore into a temporary library, validate paths/digests/schema, apply supported migrations, check foreign keys/counts, and only then swap the active store while preserving a pre-restore recovery copy. Stop playback/writes during the final swap. Restore is **replace with confirmation**, not an unspecified merge of two active libraries; fresh-install restore is the primary supported workflow.

Reject newer unsupported schemas without altering existing data. Fail safely on truncated, malicious or corrupted archives. A backup's database is untrusted code, not only untrusted data: restore opens the copy in SQLite's defensive mode with `trusted_schema` off, requires its schema (every table, index, trigger and view, with its exact SQL) to equal the schema this build produces for the snapshot's migrations before anything else runs, checks the row values the schema does not constrain, and repeats these checks after its own last write. The swap into place writes an intent first and is finished or abandoned by the next launch. [M0-A29] Rebuild indexes after the authoritative data is available. Missing original files become unavailable assets with intact knowledge. Re-pair sources and re-enter provider secrets; do not silently reuse stale device credentials from a restored database.

## 17.5 Device backup and loss

Use iOS backup classifications deliberately. Staging and the App Group handoff inbox (G0.3) and the recovery copies and restore work (ADR-0012) are excluded from device backup; the library, knowledge and media stay backup-eligible. [M0-A20] [M0-A29] Keep unique user knowledge backup-eligible; treat re-downloadable cache differently from sole-copy user imports. Do not exclude unique originals from system backup merely because they are large without explaining the recovery consequence. Show last successful explicit knowledge export and whether originals have other known copies; do not assert that an unreachable source is a verified backup.

A local app cannot preserve data after uninstall/device loss without a backup. State that plainly in onboarding/storage help. The permanent ledger means it survives **media removal inside Sylvia**, not that it survives destruction of every copy of the device.

# 18. Security, accessibility and release compliance

## 18.1 Threat model and controls

Treat publications, archive entries, provider responses, URLs, source metadata and pairing advertisements as untrusted. Numbers from those sources (a `Retry-After` header, transcript segment times, track numbers and totals in audio tags) are parsed strictly, converted with checked conversions and bounded: Stage 0 found an oversized `Retry-After` and a segment time of `1e300` crashing the app, and a stated track total able to make the order proposal unbounded. [M0-A38] Text from those sources is checked before it is decoded (strict JSON: UTF-8 only, no member name twice, bounded nesting and integers) and compared, hashed and looked up byte for byte, because Swift's `String` equality treats canonically equivalent text as equal (Stage 0: a reader accepted a group identifier its contract refuses); path and file-name rules work on UTF-8 bytes, never on Swift `Character`s, which hide a slash followed by a combining mark (Stage 0: a manifest path escaped its extraction directory by one level); and dates are converted with proleptic Gregorian arithmetic. [M0-A38] Threats include malicious EPUB HTML, parser crashes, archive traversal, oversized files, altered source bytes, credential leakage, rogue LAN hosts, prompt injection and accidental destructive deletion.

No publication-owned scripts, automatic remote images or hidden tracking requests. The reading engine does not enforce this itself; Sylvia's reader adapter does (Section 8.3) [M0-A02]. No execution of model-produced commands. Sanitize rendered Markdown/HTML and make external-link opening an explicit user action. For PDFs only `http`, `https` and `mailto` links open, each after confirmation (Section 9.2) [M0-A09]. A model cannot create a valid internal citation merely by emitting an arbitrary URL or entity ID.

Endpoint credentials are origin-scoped and redacted. No tokens in query strings for durable transfer URLs. The bearer token of each outstanding background download task is held by the system's transfer daemon until the task ends (Section 15.4) [M0-A15]. Never log selected text, prompts, titles, notes, file paths or recommendation names by default. Scrub errors before display/export. Use a content-security test corpus containing malicious instructions, remote resources and path traversal attempts.

Use iOS Data Protection for persistent files. Select database/media accessibility consistent with authorized background playback and transfers after first unlock; document the tradeoff against stricter locked-device confidentiality. Apply the same protection to WAL/SHM, staging, retained excerpts and manifests. On reboot before first unlock, show/provide a safe unavailable state rather than attempting an unsafe downgrade. [S21] **Proposed at the M0 gate (D17) and approved by the product owner on 22 October 2026; the security sign-off of the class and its locked-device trade-off is pending until a phone has shown it (G0.5 recovery device steps 1-4):** class C (`completeUntilFirstUserAuthentication`) for every persistent file, the capture path included (captures, anchors, checkpoints, retained excerpts), and for media, staging and recovery copies, export bundles and restore work. Class A would stop locked playback checkpoints, locked capture and background transfers, and in a class-A directory SQLite created its shared-memory file with class C (observed on the host), which the readback would refuse. The trade-off is that these files are readable while the phone is locked once it has been unlocked since its restart. Directories are created with the class so that the files SQLite creates inherit it; the class is set and read back on every file Sylvia writes; copies are created new with the class, because a file copied with `FileManager.copyItem` keeps its source's class (observed on the macOS host), and an APFS clone may as well (G0.3; the device run checks the class of imported clones); a mismatch is an error, never a fallback. Only a device shows protection: the simulator neither enforces nor faithfully reports the classes. [M0-A27] A store that exists but cannot be read (before the first unlock, or damaged) is never treated as empty: the component defers or fails with nothing changed. `UIApplication.isProtectedDataAvailable` reports class A availability, which is false whenever a passcode-protected phone is locked, so it never decides whether class C data can be used. [M0-A18]

## 18.2 Permissions and privacy

Permission requests are just in time: local network when connecting a source; camera only if QR pairing is enabled. No contacts, microphone, photo-library-wide access, location, email or tracking permission is needed for the baseline. Transcribing an imported clip is not microphone recording. Future physical-page capture or voice notes need their own permissions and consent flows.

No third-party product analytics by default in v1. Offer an opt-in, redacted diagnostics export with a preview. An API call goes to the user's configured endpoint; Sylvia's own infrastructure is not an intermediary in this proposal. Document any chosen crash SDK's real data collection before using it.

App privacy labels, privacy manifest, required-reason APIs and third-party SDK declarations must match the implementation. Stage 0 found two required-reason API categories that the app and the share extension use: disk space (checking room before a copy and naming a shortfall) and file timestamps (detecting a changed source and abandoned handoffs) (ADR-0010). [M0-A51] Review third-party AI consent and content-access rights before distribution. DRM-free user import is not a promise that every file's redistribution is authorized; fixtures, sample content and promotional material require appropriate rights. [S19]

## 18.3 Accessibility and interaction quality

Support Dynamic Type, VoiceOver, high-contrast appearance, reduced motion, landscape reading and accessible labels for icon actions. Highlight colors must not be the only way to distinguish capture types; the marker set in Section 4.4.5 and the grayscale conformance rules in Section 4.4.8 define how each distinction survives without color. Provide text labels for save states, progress and audio range controls. Test with hardware keyboards on iPad where the standard UI supports them.

Make all critical actions reachable without precision dragging: edit audio start/end numerically, navigate by chapter/page, and invoke capture through a labelled button. Announce saved/failed status without repeatedly interrupting screen-reader playback. Keep errors adjacent to the failed action and preserve the user's draft.

## 18.4 Distribution gates

Start with internal builds, then a small TestFlight cohort using licensed sample content and their own permitted files. Public App Store submission is a separate approval gate after product/legal review. Include a review path demonstrating core functionality without a paid model account; do not supply a shared production API key in app metadata.

No in-app purchase or subscription implementation is assumed because monetization is unresolved. Before public release, decide the commercial model and recheck App Store rules for the actual flow. Do not promise that bring-your-own-provider configuration automatically resolves every distribution-policy issue.

# 19. Performance, scale and observability

## 19.1 Reference datasets and devices

Use at least one older supported physical iPhone, a current iPhone, an iPad, and an Apple Silicon Mac. The baseline, the oldest supported iPhone (device A in `Docs/Stage0/M0-device-runbook.md`), is an iPhone 11 Pro: the product owner chose the iPhone 11 family on 22 October 2026 (the runbook's decision D-1 (b)), among the oldest iPhones iOS 26 supports, and has access to an iPhone 11 Pro and an iPhone 11. Both have Apple's A13 chip, a generation older than the A14 of the iPhone 12-class hardware earlier drafts proposed, so every budget of Section 19.2 measured on them is stricter to meet, while no budget value changes. The iPhone 11 Pro's 375 × 812 pt screen, narrower than the iPhone 11's 414 × 896 pt, is the layout floor on a device, and the iPhone 11 is a second A13 phone. The 375 × 667 pt screen of the iPhone SE (2nd generation), the smallest iOS 26 supports, is not available on a device and stays a simulator check (G0.6 used the iPhone SE (3rd generation) simulator, whose screen is the same size). The current iPhone is an iPhone 17 Pro on iOS 26.7 (phone B in the runbook); the product owner has an iPad with a hardware keyboard and a trackpad or mouse (23 October 2026), whose model the device runbook's Session 0 records, and kept the iPad's device steps in M0 (D-1, its second part). iOS 26.0-26.4 are untested (the simulator runtime is 26.5). Stage 0 results are host and simulator only, and every device step is pending in `Docs/Stage0/device-checklists/`, those on device A included. (Until 22 October 2026 this section proposed iPhone 12-class hardware on a supported OS as the baseline, subject to actual Stage 0 availability, and said that neither the baseline device nor an iPad was available; until 23 October 2026 it said that no iPad was recorded as available.) [M0-A46] Run release builds, not debugger-attached results, and record OS/device/storage conditions. Simulator tests do not establish background, lock or real audio behavior.

Two datasets: **working set** with 50 locally stored mixed works including large audio; **catalog scale** with 10,000 metadata records, 100,000 knowledge artifacts, 5,000 source entries, and incremental text indexing on a selected subset. Include a 5 GiB audiobook, an audio edition with hundreds of members, a 1,000-page PDF, the small real-world PDF set of Section 9.2 [M0-A12] and a large multi-resource EPUB. Use generated/licensed fixtures, not scraped copyrighted libraries.

## 19.2 Proposed measurable budgets

| Operation | Initial acceptance budget | Measurement conditions |
| --- | --- | --- |
| Cold launch to interactive library | p95 <= 2.5 seconds | Catalog-scale dataset, no blocking migrations/indexing |
| Catalog/retained-note search | p95 <= 500 ms | Warm local query, first 50 results, catalog-scale dataset |
| Acknowledged capture save | p95 <= 200 ms | After selection is available, excludes audio export/network |
| Start/resume local audio | p95 <= 1.5 seconds | Valid downloaded file, excludes first codec inspection (done at import); includes a cold resume at the stored position after a relaunch. Simulator: met at every depth tested, to 10 hours, for MPEG-4 files, Opus in CAF, WAV and a proved constant-bit-rate MP3; failed for long files on precise timing (Section 10.1) [M0-A22] |
| Open typical local EPUB/PDF | p95 <= 2 seconds | Defined representative fixture, not every pathological book |
| Playback position crash loss | <= 5 seconds | Periodic checkpoint plus boundary events; counted in book time (Section 10.1) [M0-A25] |
| UI during indexing/transfer | No sustained main-thread stalls over 100 ms | Instruments trace during scrolling/capture |
| Capture preview timing | Within 500 ms of intended boundary | Tested release codec matrix; actual export range recorded as the decoder reports it (Section 10.2) [M0-A24] |
| Memory during large-file transfer | Bounded; no growth proportional to file size | 5 GiB transfer, repeated interruption/retry |
| Acknowledged knowledge durability | Zero missing items in fault tests | Kill/restart, disk-full and restore corpus; these prove process-death durability, while power loss and kernel panics cannot be tested on an unmodified iPhone and rest on SQLite's and APFS's documented behavior with the Section 7.4 setting [M0-A28] |

These are proposed pass/fail budgets, not claims of measured performance. Stage 0 measured some of them on the host and the simulator (indicative only, taken under parallel load, in `Docs/Stage0/`); none has a device number yet, the start/resume budget failed on the simulator for long audio files on precise timing, and no budget was relaxed. [M0-A22] [M0-A46] Large/complex books get separate preparation indicators; do not falsify responsiveness by hiding a blocking import behind an unbounded spinner. External AI latency and LAN throughput are measured distributions, not guaranteed app service levels. The flat, shadow-free surfaces of Section 4.4.4 are chosen partly so that scrolling the Library and Thoughts at catalog scale does not spend its budget on compositing.

## 19.3 Resource management

Limit concurrent extraction and database batch sizes. Yield while audio is active, thermal pressure is high or storage is low. Avoid holding entire PDFs/audio files in memory. Use lazy covers, paginated catalog queries and lightweight projections instead of loading all relationships for every shelf item.

Full-text extraction is per-asset and resumable with versioned checkpoints. Metadata/retained-note search does not depend on completing a corpus scan. Use bounded caches with explicit invalidation when a file or extraction version changes.

## 19.4 Diagnostics

Define structured error codes and correlation IDs for import, transfer, reader, audio, AI and restore. Signpost stage duration, queue length, byte counts and outcomes with OSLog privacy controls. Keep a small redacted local event ring; no content-bearing network telemetry by default.

Support a user-reviewed diagnostic bundle: app/OS versions, dependency/build identifier, failing job state, anonymized source type, error code, storage totals and redacted timing. Secrets, source text, titles and personal notes are excluded. Provide an explicit separate mechanism for a tester to attach a permitted failing sample file; never auto-upload it.

# 20. Test strategy and release acceptance

## 20.1 Test layers

**Unit/property tests:** identity, edition membership, ordering, text-offset conversion, progress comparisons, budgets, deletion policies, job transitions, manifest validation, retry decisions and archive path checks. Generate randomized chapter orders, Unicode selections and interrupted-job sequences.

**Repository/integration tests:** SQLite constraints/migrations, concurrent capture/editing, filesystem commit recovery, FTS rebuilds, export snapshots, malicious imports, provider stream parsing and transfer version changes. Use deterministic fake clocks, model endpoints and source servers.

**UI/contract tests:** import all supported routes, save and reopen captures, provider consent, source removal, restore and accessibility. A control counts as reachable only when its whole frame is visible clear of obstructing chrome such as the mini-player; XCUITest's `isHittable` is true when any part shows. [M0-A44] A custom control's touch handling is tested at press durations around the system's own thresholds, not only well inside them: in Stage 0 the large content viewer took over a press of 0.161 seconds, sooner than the first lift activation assumed. [M0-A44] Contract tests run the phone's client fixtures against the Mac server and a fake future-server implementation of the same schema. Provider tests must include streaming and nonstreaming compatible endpoints with missing optional capabilities.

**Design conformance tests:** snapshot tests for every component in Section 4.4.7 in light, dark and grayscale, at the default and largest accessibility Dynamic Type sizes; a token contrast check in CI; a vocabulary conformance test that walks every state machine's user-visible strings; lint that rejects literal colors, sizes and status phrases outside the design package; and the layout audit and reviewed references of Section 4.4.9 [M0-A44].

**Physical-device tests:** locked playback, real interruptions/routes, Files providers, AirDrop, share extension termination, Finder cable transfer, network permission denial, Mac sleep, background downloads, reboot before first unlock, force-quit and large-file behavior. Every relevant Stage 0 spike must produce reproducible scripts/steps and evidence, not just a demo video.

**Human evaluation:** EPUB/PDF selection quality, capture friction, correct audio context, AI evidence relevance and citation support. Automated citation-ID checks do not replace human grounding review. A design review pass on real devices, including one with Color Filters set to grayscale, is part of each milestone exit from M3 onward.

## 20.2 Acceptance matrix

| Test | Scenario | Required result |
| --- | --- | --- |
| T01 | Fresh install in airplane mode | Sample/manual entry/import/read/capture/export work without account or AI setup |
| T02 | Kill/relaunch after acknowledged note save | Quote and note persist exactly; no duplicate ledger activity |
| T03 | Import EPUB and audiobook of same work | User-confirmed association; distinct editions, anchors and progress |
| T04 | Reimport identical bytes / different edition | Identical content restores availability; different edition is not silently merged |
| T05 | Metadata-only physical/external work | Manual progress, quotes, rating and recommendations work without media |
| T06 | Files import from local and cloud provider | Source copied durably; permission/download failures preserve actionable state |
| T07 | Share extension terminated mid-copy | No false success, invalid library asset or lost acknowledged handoff |
| T08 | AirDrop/open-in of supported file | Enters common importer; duplicate handling matches Files import |
| T09 | URL returns redirect/HTML/unknown size | No credential leakage; unsupported content rejected; stream limit enforced |
| T10 | Kill at every import commit boundary | Recovery journal reconciles file/database; exactly one valid library record |
| T11 | Disk fills while staging/committing | No partial ready asset; existing knowledge unchanged; retry after freeing space |
| T12 | Truncated EPUB/PDF/audio or protection | Clear parse/protection status; no circumvention or crash loop |
| T13 | ZIP traversal/bomb/remote EPUB resource | Extraction bounded; no sandbox escape, script execution or unsolicited network request |
| T14 | Multi-file audiobook with ambiguous order | Confirmation required; order stable; missing members identified |
| T15 | EPUB highlight then reflow/rotate/relaunch | Exact quote retained; same-source anchor returns to intended passage |
| T16 | PDF multiline/rotated/mixed scanned pages | Text/geometry correct where available; no OCR claim for image-only page |
| T17 | TXT/Markdown with Unicode and links | Stable offsets, exact capture and safe rendering without remote tracking |
| T18 | Two-hour locked local playback | Plays with supported controls; position checkpoints; no unrelated background work |
| T19 | Headphones removed/call/route change | Safe pause/resume behavior; no unexpected loudspeaker playback |
| T20 | Seek/rate change/file boundary/relaunch | Position within budget; no skipped/duplicated member due to queue bug |
| T21 | Capture preceding 30 seconds across files | Correct ranges; excerpt preserved or explicit retry state; no fabricated transcript |
| T22 | Replay capture while halfway through book | Main listening position and totals unchanged; context restored afterward |
| T23 | Remove source after pending/successful clip | Pending retention guarded; successful excerpt, quote and notes still available |
| T24 | Transcribe with no endpoint/offline/error | Capture survives; no hidden upload/fallback; labelled transcript on success |
| T25 | Optional locked quick-capture surface | Success acknowledged only after save; otherwise not advertised/shipped as supported |
| T26 | Edit quote/comment/AI-derived note | Original wording and provenance distinguishable; stale editor cannot overwrite silently |
| T27 | Search after media and index removal | Saved knowledge searchable; source-corpus coverage disclosed |
| T28 | Reread/seek-to-end/manual completion | Separate runs; no false full consumption; prior completion preserved |
| T29 | Several inbound/outbound recommendations | Events retain direction/date/source/reason; no messages sent; rating scale round-trips |
| T30 | OpenAI/Anthropic/local dialect matrix | Capability tests and provider-specific adapters work; no consumer-plan assumption |
| T31 | New endpoint, redirect or fallback failure | Consent required; credentials origin-scoped; no unapproved content/provider transmission |
| T32 | Insufficient/contradictory/spoiler evidence | Scope disclosed; filtered retrieval; no invented passage quotation or false alignment |
| T33 | Stream interruption/refusal/bad citation | Partial output labelled; invalid IDs unresolved; exact evidence and question retained |
| T34 | Catalog-scale performance dataset | Meets approved p95 budgets; no full-library materialization on main thread |
| T35 | Export/restore golden knowledge corpus | Counts/digests/anchors/notes/clips/evidence match; secrets absent |
| T36 | Rogue host/wrong pin/reused invitation | Pairing fails; no secret sent to untrusted peer; invitation single-use |
| T37 | Revoke phone/source identity changes | Future requests denied or re-pair required; no silent trust reset |
| T38 | 5 GiB transfer, network lost mid-part | Verified parts retained; correct range retry; final digest and single import |
| T39 | Mac file changes during transfer | Source version change detected; no mixed-version ready file |
| T40 | 200/412/416/wrong digest on range | Safe recovery path; never append invalid bytes; actionable reason |
| T41 | Suspend/force-quit/reboot/background job | Reconcile on launch; no orphan "complete" task or erased valid parts |
| T42 | Cable `.sylviapack` above 4 GiB / partial copy | Valid bundle imports; partial copy rejected; private DB never Finder-visible |
| T43 | LAN permission denied and Tailscale/manual host | Clear remediation; manual route supported; a Tailscale address and MagicDNS name work through the pinned identity under the scoped ATS exception of D16 (approved by the product owner on 22 October 2026, subject to the security sign-off and G0.2 device step 6), and are otherwise not offered [M0-A13]; no dependence on multicast or public ports |
| T44 | Remove all original media for a work | Ledger/rating/recommendations/quotes/notes/AI evidence survive |
| T45 | Migration from every supported schema | Integrity and invariant checks pass; failure restores/reopens recovery snapshot |
| T46 | Corrupt/newer/malicious backup | Existing library untouched; no traversal; precise unsupported/corrupt error |
| T47 | Export during edits/restore crash | Consistent snapshot; leased blobs retained; atomic final restore/recovery |
| T48 | EPUB/note/provider prompt injection | No tool execution, external fetch, automatic metadata change or secret exposure |
| T49 | Inspect logs, export, crash diagnostics | No credentials/content/PII by default; user reviews diagnostics export |
| T50 | Locked/rebooted device file access | Protection policy honored; no disabling protection to fix background behavior. Decided by the product owner on 22 October 2026 (PO-23 (b)): Stage 0 builds a background-audio harness for the locked-device check (G0.5 recovery device step 3) before the device run, so that the run is conclusive the first time even if iOS suspends the test runner while the phone is locked; the app-level unavailable state before the first unlock is demonstrated in M1 with the app shell. The recommendation had been to build the harness only if step 3 proved inconclusive. The harness runs both parts of that step, the writes while the phone is locked and the restart, and was built on 22 October 2026 (`Spikes/G05-Recovery/LockHarness`; its device run is pending) [M0-A30] |
| T51 | VoiceOver/Dynamic Type/reduced motion | Core import/read/listen/capture/search/restore flows usable at every text size up to the largest accessibility size; no clipped labels in capture sheet, player, Inbox or Thoughts; Reduce Motion removes all non-opacity animation (decided by the product owner on 22 October 2026, PO-30 (a): in Sylvia's own components, system sheet presentation following the system if G0.6 device step 19 shows that acceptable, Section 4.4.4) [M0-A42] |
| T52 | Every save/import/network failure UI | Draft preserved; truthful status; actionable retry/cancel and no duplicate commits |
| T53 | Grayscale and Increase Contrast pass | With Color Filters set to grayscale and with Increase Contrast on, every capture kind, status pill, availability badge and button role in Section 4.4 remains distinguishable by glyph, label, typeface or frame; snapshot comparison against the color baseline shows no information carried by hue alone; hairline rises to 24% under Increase Contrast |
| T54 | Status vocabulary conformance | Every user-visible state string across Sections 8.2, 10.2, 11.3, 14.4, 15.5 and 17.2, and each state, phrase and action that the Section 4.4.6 gaps table adds from Sections 7.3, 7.5, 8.1, 8.4, 8.5, 9.1, 9.2, 10.1, 10.4, 12, 13.4 and 16.2 once it is in the vocabulary [M0-A45], comes from the design package vocabulary; forbidden phrases in Section 4.4.6 are absent from all UI targets; "Saved" is rendered only after the durable commit callback (ties to T02); no literal color, font size or status phrase exists outside the design package |
| T55 | M3 passage capture and return | Select a multiline EPUB/PDF passage, open Note, type with the keyboard visible, save and return to the prior reading position with one saved capture; exact quotation and source remain accessible. Reopen from Thoughts offline after relaunch; an unavailable or ambiguous source leaves the retained quotation intact. Repeat with rotation, large Dynamic Type and VoiceOver; Look Up sends no AI request |
| T56 | M5 question starters and contextual follow-ups | Explain/Simplify populate an editable question without sending or widening scope; explicit Send uses the disclosed destination and persisted ContextPack. Ask a follow-up without reselecting; history follows consent, budget and spoiler rules. Passage preview, answer and composer remain reachable on iPhone/iPad with keyboard and large text. Closing/reopening preserves the draft; interruption retains truthful partial-output state |
| T57 | M5 citation preview and source return | A valid citation opens that answer's retained evidence; source navigation is offered only for a resolvable anchor and preserves the answer, draft and return position. After media removal the evidence still opens; ambiguous/missing anchors and invalid IDs never fabricate a destination. Two answers using the same citation label for different snippets still open their own retained evidence. Touch, keyboard and VoiceOver can complete the flow with predictable focus return |

T55-T57 are implementation acceptance cases for M3/M5, not additional M0 feasibility results. They use the capture, evidence and lifecycle requirements in this plan, and receive the same accessibility, grayscale and vocabulary checks as T51/T53/T54.

## 20.3 AI evaluation set

Create a licensed small corpus of at least 100 test questions: passage explanations, absent-information questions, contradictory text, misleading titles, audio without transcripts, companion-edition mismatches, spoiler boundaries, prompt injection and after-media-removal queries. Store expected evidence/behavior rather than a single expected prose answer.

Deterministic gates: all citations resolve only to supplied evidence; no quote marked exact unless verified against evidence; no content crosses an unauthorized boundary; no later text enters a restricted ContextPack. Human-review target: at least 90% of tested substantive answers are supported by the displayed evidence or clearly labelled as general explanation, with zero observed critical fabricated-quote/privacy/tool-execution failures in the release set. This is a proposed evaluation threshold, not a guarantee of model correctness.

Evaluate separately for each advertised provider/model profile. Arbitrary user models receive capability/compatibility support but no blanket quality guarantee. An unsupported weak model must not cause the app to falsify citation validity to appear more capable.

## 20.4 Product validation

With consent, recruit approximately 8-12 target users for structured sessions and a short real-use pilot. Test whether they can import without coaching, capture without losing place, remove media confidently, and find a useful saved idea later. Suggested product targets: 80% complete first import/capture unaided; 80% retrieve a known saved idea within one minute; no participant mistakes a bookmark for retained audio or "search this book" for full-book model ingestion. Add one observation to the protocol: whether participants can tell a quote, a note and a generated answer apart in Thoughts without being told, including on a device with Color Filters set to grayscale.

These are review hypotheses, not established demand metrics. A weekly return to saved knowledge is the primary signal to investigate; raw listening minutes or AI message counts do not alone validate Sylvia's thesis. V1 can gather this through interviews and local opt-in diagnostics without building a tracking platform.

# 21. Delivery plan, dependencies and staffing

## 21.1 Stage 0 - Resolve feasibility before feature commitments

**G0.1 EPUB/PDF capture:** demonstrate Readium selection/decorations/locator restoration, footnotes and extraction mapping; prove PDF multiline/rotation anchors. Deliver a compatibility matrix and pinned package recommendation. Confirm that Readium decorations can render the `ochre` fill-plus-underline highlight and that Literata can be injected as the default reading face with the user's size and spacing settings.

**G0.2 Transfer security/background:** demonstrate user-mediated trust bootstrap, certificate validation/pinning, authorized ranged background downloads, recovery after suspension/force-quit, Mac source mutation and manual-address connectivity. Security reviewer approves the pairing protocol. No "temporary trust-all" code may become the production baseline.

**G0.3 Intake and cable:** demonstrate a large share-extension handoff without false acknowledgement, Finder `.sylviapack` transfer above 4 GiB, ZIP64 validation and private data isolation. Document the exact fallback route where a third-party share provider cannot supply a durable file.

**G0.4 Audio:** test the proposed codec/container matrix, long playback, chapters, cross-file excerpts, export timing and main-position-preserving preview. Separately evaluate lock-screen quick capture. Record which part of the aspirational workflow can ship.

**G0.5 AI and recovery:** demonstrate each provider dialect plus a local endpoint, correct context snapshot/citation resolution, a transcription endpoint and a restore drill after source deletion. Confirm exact dependency/toolchain versions and license/security posture.

**G0.6 Design tokens on devices:** build the `SylviaDesign` package at v0.1 from Section 4.4; verify every token pair's contrast in the asset catalog in light and dark; check the type roles under Dynamic Type at the default and largest accessibility sizes on the oldest supported iPhone; view the component set on a device with Color Filters set to grayscale and with Increase Contrast on. Adjust token values where the device disagrees with the canvas, and record the final values in an ADR.

**Exit gate:** evidence and ADRs approved; review decisions in Section 23 signed; no unresolved P0 feasibility assumption hidden behind a feature flag. A failed spike changes the documented scope/approach before downstream work, not after the team has built around it.

**Stage 0 status at the M0 gate (draft 0.5).** All eight gate reports are in `Docs/Stage0/`, with host and simulator evidence. Every gate still has pending device and human steps, every Stage 0 ADR is Proposed, and rows failed in four gates, each changing the approach before downstream work: the highlight overlay on PDF text drawn with a rotated text matrix (Section 9.2) [M0-A54], Tailscale address forms without an ATS exception (Section 15.1, D16), the start/resume budget for long audio files on precise timing (Sections 10.1 and 19.2), and `UIFontMetrics` scaling (Section 4.4.3). Decided by the product owner on 22 October 2026 (PO-34 (b)), so that no downstream work builds on an unconfirmed device behavior: each milestone, M1 included, starts only after the device steps of the gates it builds on have passed on the iPhone available now (M1: G0.5 recovery steps 1-4, which run the persistence and restore tests on the phone and check there the protection class and durability setting of D17 that M1's file store and schema are built on, except step 4's app-level check before the first unlock, which needs the app shell and moves into M1 itself; M2: G0.3, and G0.6, whose design package every screen from M2 on is built from; M3: G0.1; M4: G0.4; M5: G0.5 AI; M6: G0.2, whose step 6 tests D16's exception on a phone, and G0.3); and no milestone exits before the same steps have also passed where the checklists repeat them, on the baseline iPhone (device A, an iPhone 11 Pro; Section 19.1) and an iPad. The iPhone available now is phone B, the iPhone 17 Pro, on which the device runbook runs the steps first. The product owner has access to device A (22 October 2026) and has an iPad with a hardware keyboard and a trackpad or mouse (23 October 2026; ADR-0001), whose model and iPadOS the device runbook records at Session 0: no device has to be acquired if that iPad runs iPadOS 26 or later, which every Stage 0 harness needs and the runbook checks before Session 0; the device sessions on both are on every milestone's path to exit (until 23 October 2026 this sentence said that no iPad was recorded as available, so that acquiring one was on that path; and until the review of the follow-up of the decisions round, the same day, that no device had to be acquired, though the iPad's model and iPadOS were not known: its finding FID4-03). Each serialized device run, which needs the team's code signing, comes before the milestone that waits for it, M1's included. Stage 0 builds a background-audio harness for G0.5 recovery step 3 before the device run, so that the locked-device check is conclusive the first time even if iOS suspends the test runner while the phone is locked (PO-23 (b), decided by the product owner on 22 October 2026; until then this paragraph said that M1 would wait for such a harness only if step 3 proved inconclusive). The product owner also decided on 22 October 2026 that the M0 exit itself waits for every device step the device runbook's Section 7 marks blocking to pass, or, where one fails, for the approach to change, those on device A and the iPad included (decisions D-10 (i), D-2 (a) and D-1 in `Docs/Stage0/M0-device-runbook.md` Section 6). PO-34's rule above therefore governs only the steps the runbook lets wait for a later milestone, M1's dependency on the G0.5 recovery device steps (Section 21.2) is met by the M0 exit itself, and the exit, like every role sign-off of Section 23.3, waits for the device sessions. The amendments, their evidence and the product owner's questions are in `Docs/Stage0/M0-plan-amendments.md`. [M0-A01] [M0-A46]

## 21.2 Milestones and acceptance gates

| Milestone | Deliverables | Dependencies | Exit demonstration |
| --- | --- | --- | --- |
| M0 - Feasibility and design freeze | G0.1-G0.6, threat model, interaction prototype, dependency lock, ADRs, `SylviaDesign` v0.1 (tokens, type roles, marker set, status vocabulary, component shells) | None | Team approves supported scope, contracts and design tokens |
| M1 - Durable foundation | Domain, repositories, schema, file store, manual works, migrations, recovery journal; the app-level part of T50 (a safe unavailable state before the first unlock), which needs the app shell (decided by the product owner on 22 October 2026, PO-23 (b): Stage 0 builds the locked-device harness, and this part stays in M1) [M0-A30] | M0; the G0.5 recovery device steps (Section 21.1) [M0-A46] | Offline records/capture fixture persists through faults |
| M2 - Direct ingestion | Files/share/AirDrop/URL, multi-file order, manifests, minimal metadata, import recovery, Inbox using the status vocabulary; the three bundled onboarding samples (Section 4.2; PO-33, decided by the product owner on 22 October 2026) | M1; the G0.3 and G0.6 device steps (Section 21.1) [M0-A46] | J-01 import portion; T06-T14; T54 for import states |
| M3 - Reading and knowledge | EPUB/PDF/TXT views, capture/comments/lookup, anchors, Thoughts and FTS; passage preview while writing and return to reading (Sections 4.1, 9.4), composed from `SylviaDesign` | M1-M2; the G0.1 device steps (Section 21.1) [M0-A46] | J-01 complete; same-asset anchor tests; T55; design review on device including grayscale |
| M4 - Audio learning | Player, system controls, timeline, durable clips, safe preview, progress, mini-player with capture control | M1-M2; the G0.4 device steps (Section 21.1) [M0-A46] | J-02 without AI; locked-device and clip tests; T54 for capture states |
| M5 - Contextual AI | Provider setup, consent, evidence packs, retrieval, streaming, optional transcription, Generated marker and citation chips; Explain/Simplify starters, contextual follow-ups and citation evidence preview (Sections 13.1, 13.4) | M3-M4 context contracts; the G0.5 AI device steps (Section 21.1) [M0-A46] | J-02/J-03; provider and grounding evaluation; T56/T57; T54 for AI states |
| M6 - Mac/LAN/cable delivery | Source companion using shared tokens, pairing, manifests/ranges, queue/receipts, wired bundle UX | M1-M2, M0 security gate, which includes the security sign-off of the Tailscale/ATS decision (D16, approved by the product owner on 22 October 2026) [M0-A13]; the G0.2 and G0.3 device steps (Section 21.1) [M0-A46] | J-05 including >4 GiB and adverse conditions |
| M7 - Lifelong record/recovery | Ledger polish, ratings/recommendations, retention controls and impact report, export/restore UX | M3-M6; backup foundations begin in M1 | J-04/J-06; no knowledge loss |
| M8 - Release hardening and pilot | Full matrix, accessibility, performance, migration/recovery drills, TestFlight/review docs, T53/T54 across every screen | M1-M7 | All P0 gates plus product pilot review |

M3 and M4 can proceed in parallel after domain/anchor contracts stabilize. M6 can proceed in parallel after the importer and protocol contracts stabilize. M5 must not invent new capture identities independent of M3/M4. Backup infrastructure starts in M1 even though its final user experience is accepted in M7. No screen is built before `SylviaDesign` v0.1 exists; screens built against it in M2 through M7 pick up token corrections without rework.

The M0 feasibility work was merged into `main` on 15 October 2026, and the M0 gate is pending approval [P3]; assess its native components and contracts against M1-M7 before commissioning replacements. The Gloss reference refines M3/M5 interaction outcomes within these milestones. No V1 milestone depends on the later web reader, which does not appear among its exit gates. Existing milestone dependencies and effort estimates remain unchanged. [S25]

## 21.3 Recommended ownership

Assign one accountable technical lead for domain boundaries, schema and integration. Use an iOS reading/knowledge owner, an iOS audio/AI owner, and a Mac/transfer owner; one person may hold multiple roles, but the estimates must reflect that. Add QA ownership for real-device/fault testing, part-time product design and an independent security review for pairing/content isolation. The product designer owns `SylviaDesign` tokens, the vocabulary and the design boards; the iOS reading/knowledge owner owns the package's code.

No workstream owns a private copy of the schema or of the design tokens. Schema, locator, retention, transfer-contract and design-token changes require shared review and fixture updates. Library, player and AI teams must agree what "saved", "ready", "context available" and "removed" mean, and use the vocabulary's strings for them.

## 21.4 Effort model for planning, not a delivery promise

Proposed engineering effort ranges assume experienced native developers, reuse of reviewed components and the scope above. They exclude app-store waiting time, legal costs and a full redesign after user research. Coding-agent use is not assumed to eliminate integration, device testing or review work.

| Workstream | Engineering person-weeks |
| --- | --- |
| Feasibility, architecture and contracts | 3-5 |
| Persistence, identity, migration and job foundations | 4-6 |
| Design package: tokens, type roles, components, vocabulary, snapshot and conformance tests | 2-3 |
| Imports, validation and grouping | 4-6 |
| EPUB/PDF/TXT reading and anchors | 5-7 |
| Audio playback, excerpts and progress | 5-8 |
| Notes, ledger, search and recommendation UX | 4-6 |
| Context, provider adapters and clip transcription | 5-8 |
| Mac companion, security, LAN and wired bundles | 6-10 |
| Export, restore and storage controls | 3-5 |
| Integration, performance and release hardening | 5-8 |
| **Base engineering total** | **46-72** |

The design package row is new in draft 0.2. It is partly offset by less per-screen styling work in the UX rows, which have not been reduced here; re-estimate both after M0. Add a 20-30% contingency after the team reviews the difficult samples and feasibility results. QA/design/security are additional capacity, not silently included as zero-cost support. Do not convert person-weeks directly into a calendar date before staffing, parallel dependencies and device-lab access are agreed. Re-estimate after M0 and M2.

**At the M0 gate (draft 0.5) the ranges are unchanged.** Stage 0 measured feasibility, not effort, and the spikes were built by coding agents, so their duration is no evidence of person-weeks. The team's re-estimate should weigh what the spikes added (the EPUB adapter's safety layers and their upkeep on every Readium upgrade, the per-file audio timing mode and the import remux, the vocabulary gaps of Section 4.4.6, the Tailscale decision D16 and the device runs; draft 0.8 adds the decisions of 22 October 2026 that the owner chose otherwise than recommended: the background-audio harness built in Stage 0 (PO-23), three onboarding samples with an audio pairing (PO-33), the periodic background inbox read (PO-13), the graduated rewind with its notice (PO-39) and an older baseline iPhone (D-1)) against what now exists as agent-reviewed Stage 0 code to port (the `SylviaDesign` v0.1 package with its components and checks, the contracts, and the spike adapters). [M0-A49]

## 21.5 Safe scope reduction order

When capacity is constrained, first cut the gated quick-capture surface, secondary reader presentation modes, extra passing-but-unneeded audio formats and cosmetic shelf options. A narrowed provider/transcription matrix or a later Mac companion would require explicit product approval because it changes the proposed v1 experience. Never cut durable capture, truthful import state, backup/restore, accessible error recovery, retained-knowledge safety, or the marker set and status vocabulary to meet a date; they are how the invariants become visible.

# 22. Engineering handoff and repository workflow

## 22.1 Repository layout

Suggested monorepo layout, to be created at execution time:

```text
Apps/SylviaIOS/                 # app and share-extension targets
Apps/SylviaMac/                 # lightweight companion
Packages/Domain/
Packages/Application/
Packages/Persistence/
Packages/Files/
Packages/Reading/
Packages/Audio/
Packages/AI/
Packages/Transfer/
Packages/ImportHandoff/
Packages/Design/               # tokens, type roles, markers, vocabulary, components
Contracts/                     # versioned JSON Schema and OpenAPI
Contracts/design/              # exported design tokens and vocabulary (portable)
Fixtures/                      # licensed/generated books, audio and failures
Tests/                         # unit, integration, contract, UI, performance, snapshots
Spikes/                        # Stage 0 feasibility harnesses; evidence code, never shipped
Scripts/                       # CI, fixture, lint and contract tooling
Docs/ADRs/                     # approved architecture decisions
Docs/Stage0/                   # gate evidence reports and physical-device checklists
Docs/Design/                   # design boards: rendered images, board source, render script, review notes
Docs/Runbooks/                 # import, restore, source and release procedures
```

Keep application deployment targets separate from the development SDK. Commit resolved package versions, dependency license inventory, fixture licenses, the Literata font license and CI toolchain configuration. Use no private platform API or undocumented app-service endpoint to make a user story appear complete.

## 22.2 Build and CI

Require domain/unit/schema tests on every change; integration and simulator UI smoke tests on merge; scheduled full provider/transfer fixtures and physical-device regressions on release candidates. Use macOS CI for Apple targets. Pin test server behavior and run fault injection deterministically before doing live provider smoke tests.

CI must lint contracts, validate all JSON fixtures, enforce migration sequencing, scan for bundled secrets, verify package licenses, check every token pair in `Contracts/design/` for contrast, and reject literal colors, font sizes and status phrases in UI targets. Snapshot tests for the design package run on every change; references are re-recorded only on the reference simulator and reviewed by a person before they are committed [M0-A44]. Use real Keychain/platform adapters only in targeted tests, hosted in an app target (an unhosted package test bundle cannot use the data-protection keychain on the simulator) [M0-A39]; never expose production credentials to untrusted pull-request code. TestFlight signing/distribution is restricted to release maintainers.

## 22.3 Definition of done for a work item

A completed issue contains the requirement/test IDs it satisfies, implementation and user-visible behavior, negative-case tests, logging/privacy review, accessibility implications and any schema/contract migration. No TODO or stub may stand in for an advertised capability. Add demonstration steps for physical-device behaviors and verify that failure messaging matches the actual state machine and uses the vocabulary's strings. A screen is not done until its snapshots pass in light, dark and grayscale and its layout audit passes at the largest accessibility size [M0-A44].

AI-generated code receives the same review. A coding agent must not change release scope, weaken TLS validation, disable data protection, substitute a web wrapper for native reading, hard-code a developer API key, introduce a color, size or status phrase outside the design package, or rewrite a dependency to bypass a failed test without an approved ADR.

## 22.4 Required execution artifacts

Before the end of M0, produce ADRs for platform baseline, persistence, reader adapter, audio/timeline/excerpt strategy, pairing/transport security, AI/context privacy, retention/backup, and the design language (final token values, Literata bundling and licensing, Dynamic Type mapping, grayscale conformance method). Generate full schemas and OpenAPI from the proposed contract descriptions, and the design token export from Section 4.4; do not treat Appendix A's examples as an already complete schema implementation.

Before release, deliver install/setup instructions, source/import support matrix, backup/restore runbook, known limitations, provider configuration guide, privacy/permission text, fixture/test results, accessibility report including the grayscale pass, redacted diagnostics guide and a signed release checklist. Include instructions for a reviewer to test every golden journey without relying on the developer's home network.

# 23. Review decisions and risk register

## 23.1 Decisions to approve before execution

These are focused review decisions, not requests to repeat the completed discovery questionnaire. Defaults let the team assess a concrete plan; a changed decision must update affected estimates, acceptance tests and ADRs. Draft 0.5 updates D02, D03, D05, D07, D08, D10 and D15 and adds D16 and D17 from the Stage 0 evidence; the smaller product-owner questions the spikes raised are listed, with options and recommended defaults, in `Docs/Stage0/M0-plan-amendments.md`. [M0-A47]

**Approved by the product owner on 22 October 2026.** The product owner approved every decision below, D01 to D17, D16 and D17 included, with the defaults as written here, and decided the smaller questions: PO-01 to PO-44 of `Docs/Stage0/M0-plan-amendments.md` and D-1 to D-10 of `Docs/Stage0/M0-device-runbook.md` Section 6, each as recommended except PO-13, PO-23, PO-33, PO-39 and D-1 (Appendix D, draft 0.8). The last column records what each approval chose and what remains pending. The product owner approved as product owner. The role sign-offs a row names (security reviewer, QA, design, technical lead) are given by the product owner personally, each only after the device sessions have produced the evidence that role signs, and until then each is pending (Section 23.3); approval is not a device result, so each device step named below is pending too. (Until 22 October 2026 the second column was headed Proposed default and the last column named the decision owners only; the decisions approved on 6 October 2026 before Stage 0, D02-D15 and the amended D01, are recorded in Section 1.1.)

| Decision | Default, as approved | Decision owner / consequence; approval and what remains pending |
| --- | --- | --- |
| D01 - Platform floor | iOS/iPadOS 26+, macOS 26+ (amended by the product owner on 6 October 2026 from the proposed 18+ and 14+); iPhone-led, functional adaptive iPad. The oldest supported iPhone, the baseline device, is an iPhone 11 Pro (A13; Section 19.1) | Product + technical lead; affects APIs/test matrix. Approved by the product owner on 22 October 2026, with the oldest supported iPhone decided (runbook D-1 (b): the iPhone 11 family, device A an iPhone 11 Pro, the iPhone 11 a second A13 phone, the iPhone SE (2nd generation) screen a simulator check), the iPad's device steps kept in M0 (D-1, its second part), and the toolchain pin, Xcode 27.1, confirmed (PO-35, D-3). Pending: the technical lead's sign-off, with the check of Apple's release notes for Xcode 27.1 (ADR-0001) |
| D02 - Core stack | SwiftUI, Readium EPUB behind Sylvia's safety adapter, PDFKit, AVFoundation, GRDB/SQLite; archives through `readium/ZIPFoundation` behind Sylvia's layout check | Technical lead; versions pinned at M0 (Readium 3.11.0, GRDB 7.11.1, readium/ZIPFoundation 3.0.1; the full lock and licenses in ADR-0014). Approved by the product owner on 22 October 2026. Pending: the technical lead's sign-off; the two routes around the marmelroy/Zip guard (ADR-0014 R4-01 and R4-02) closed before the M1 app target is created, or before any product target links Readium if that comes first (Section 23.2) *(24 October 2026: answered by an agent's change, review pending: ADR-0014 status. Until 26 October 2026 this note said closed: the third review of the M0 exit preparation, its finding HON-EP-01.)* [M0-A01] [M0-A02] [M0-A19] |
| D03 - Lock-screen capture | Standard playback required; dedicated capture gated, not assumed. After G0.4 the candidate is one App Intent offered as a Control and an App Shortcut; the bookmark command and Live Activity buttons are not adopted; it is not advertised until its device steps pass [M0-A26] | Product + audio lead; explicitly approve ideal-story narrowing. Approved by the product owner on 22 October 2026, with the narrowing (PO-17 (a): in-player Capture is the baseline; an App Group fallback only if the device shows the intent performed outside the app's process). Pending: G0.4 device steps 8-13 on phone B, and 8-10, 12 and 13 on device A, which has no Action button; the security sign-off of residual risk B11, unauthenticated quick capture on a locked phone (Section 23.3) |
| D04 - Audio words | Durable excerpts plus optional short-clip endpoint transcription; no full transcription | Product + AI/audio; test speech configuration complexity. Approved by the product owner on 22 October 2026. Pending: the run against a real transcription endpoint (G0.5 AI step 7, kept in M0 by runbook decision D-4 (a)) |
| D05 - Supported formats | EPUB/PDF/TXT/Markdown and tested MP3/AAC-based audiobook matrix. On the simulator 16 of 17 container and codec combinations pass and Opus in WebM is excluded; FLAC, Opus and WAV are admitted only after the device run; the per-file timing mode and the import remux are decided for long files (Sections 3.1, 8.3, 10.1) | Product + QA; publish actual codec/container list after the device run. Approved by the product owner on 22 October 2026, with the remux (PO-20: the original kept beside the copy, which about doubles each remuxed member's storage, for the members long enough to miss the budget) and the extra formats (PO-18: each one that passes the device run is admitted, its limits stated; WebM stays excluded). Pending: the device run (G0.4 step 1) and the QA sign-off of the codec list [M0-A22] [M0-A23] |
| D06 - Device state sync | None in v1; Mac transfer does not synchronize progress/notes | Product; prevents accidental sync scope. Approved by the product owner on 22 October 2026; nothing pending beyond the M0 exit |
| D07 - Pairing | High-entropy code plus an optional QR code scanned in Sylvia, and pinned trust; the custom-scheme link is not advertised, because another app can claim it; short-code PAKE only if separately reviewed | Security + transfer; M0 gate. Approved by the product owner on 22 October 2026, with the link dropped (PO-11 (a)) and the invitation values (PO-10 (a)). Pending: the security sign-off of the pairing protocol, after G0.2's device steps (step 12, the review, reads them) [M0-A16] |
| D08 - Local model transport | HTTPS default; narrowly scoped local HTTP opt-in only if validated. On the iOS 26.5 simulator ATS did not block local cleartext, so Sylvia's own endpoint rules are the enforced ones, with cleartext only at IP literals in the loopback, private and link-local ranges (Section 14.3) | Security + iOS + product; no broad ATS bypass. Approved by the product owner on 22 October 2026, with cleartext only at IP literals in local ranges (PO-36 (a)) and `NSAllowsLocalNetworking` with Sylvia's own endpoint rules as the cleartext gate on every OS version, so no claim about iOS 26.0's ATS behavior is needed (runbook D-9 (b), an exception recorded in ADR-0011). Pending: the security sign-off, after G0.5 AI device steps 1 and 2 [M0-A14] |
| D09 - Retention | Manual audio eviction; permanent knowledge retained; full text independently controllable | Product + persistence; deletion copy and safety tests. Approved by the product owner on 22 October 2026; nothing pending beyond the M0 exit |
| D10 - Export/restore | Knowledge backup required; replace-with-confirmation restore; unencrypted export warned; format v1 proven as a directory bundle, the single-file form through the archive rules of Section 8.5 [M0-A19] | Product + security; approve privacy limitation or fund encryption. Approved by the product owner on 22 October 2026, with the privacy limitation approved for internal and TestFlight use and revisited at the public-release gate (PO-22 (a)). Pending: the security sign-off of the unencrypted format (G0.5 recovery review row 23) |
| D11 - Organization | Status, work association and search only; no fixed taxonomy | Product; categorization remains open. Approved by the product owner on 22 October 2026 |
| D12 - Ratings/history | Half-star rating, explicit completion, rereads, local recommendation events | Product; export schema and UI semantics. Approved by the product owner on 22 October 2026 |
| D13 - Distribution | Internal/TestFlight first; notarized Mac testing build; no monetization implementation yet | Product + release; public release approval later. Approved by the product owner on 22 October 2026. Whether BoringSSL's advertising clauses are acceptable for the notarized companion (PO-42; ADR-0014 section 7 item 2) had no default and was left to counsel, before the companion was distributed beyond the team; on 23 October 2026 the product owner took it on for now, with PO-41, PO-43 and PO-44: the owner's own and TestFlight builds carry the notices the licenses require, and a lawyer's review, the advertising clauses included, comes before any public App Store release; the answer does not name the notarized companion's builds, so PO-42 is still settled before one is distributed beyond the team, as on 22 October 2026 (until the review of the follow-up of the decisions round, the same day, this row read the answer as putting that review before the companion's public release too: its finding FID4-05) |
| D14 - Scope sequence | Articles/feeds/newsletters (phases A-C in Section 24), Docker, OCR, Calibre adapter and external-player capture later | Product; preserve roadmap without adding P0 scope. Decide Phase A versus Docker hub ordering and the Phase C feasibility bar. Approved by the product owner on 22 October 2026; that ordering is decided when Phase A is sequenced |
| D15 - Design language | Marginalia (Section 4.4): Paper/Night grounds, Pine and Ochre accents, seven-marker set (five capture kinds, two statuses), Literata plus system faces, three-tab navigation in Sylvia's own opaque chrome, fixed status vocabulary. Direction chosen by the product owner on 6 October 2026 after reviewing four alternatives | Design + iOS lead confirm token values on devices in G0.6; any change to the marker set or vocabulary is a plan change, not a styling tweak. G0.6 (simulator) built `SylviaDesign` v0.1; type scaling moved from `UIFontMetrics` to the system styles' sizes. Approved by the product owner on 22 October 2026, with the bounded Dynamic Type exceptions of Section 4.4.3 (PO-31 (a), PO-32), the vocabulary gaps of Section 4.4.6 added before the milestones that show them (PO-28, PO-29 (a)) and system sheet motion under Reduce Motion if G0.6 device step 19 shows it acceptable (PO-30 (a)). Pending: the design sign-off, after the device review (G0.6 on phone B, device A and the iPad); the printed dark tints, the Increase Contrast step and the wording of the vocabulary gaps await design review [M0-A40] [M0-A41] [M0-A45] |
| D16 - Tailscale route and ATS | A scoped ATS exception (`NSExceptionDomains` for `ts.net` and `100.64.0.0/10`), the pin remaining the only trust decision and the client refusing non-`https` URLs itself; alternative: no Tailscale route in v1, XFER-04 narrowed. A publicly trusted MagicDNS certificate was not tested (it publishes the machine name in Certificate Transparency logs) | Security + product; signed at the M0 gate like every decision here (the exit gate of Section 21.1), the route built in M6 after G0.2's device step 6 has tested the exception on a phone; added at the M0 gate because G0.2's Tailscale rows failed without an exception. Approved by the product owner on 22 October 2026: the scoped exception if the security reviewer approves it, otherwise no Tailscale route (PO-07 (a)). Pending: the security sign-off at the M0 gate, after G0.2 device steps 6 and 23; a contrary device result reopens the decision before M6 [M0-A13] |
| D17 - Data protection and durability | Class C (`completeUntilFirstUserAuthentication`) for every persistent file, set and read back; WAL with `synchronous = FULL` and `fullfsync` for acknowledged saves | Security (the class and its locked-device trade-off) + product (I-03) + persistence; before M1; added at the M0 gate. Approved by the product owner on 22 October 2026, with the durability setting (PO-21 (a)). Pending: the security sign-off of class C and its locked-device trade-off, and the persistence owner's, after G0.5 recovery device steps 1-4 on phone B and steps 1 and 2 on device A, before M1 [M0-A27] [M0-A28] |

## 23.2 Risk register

Draft 0.5 updates five rows and adds ten from the Stage 0 evidence; draft 0.7, its re-check against the merged gate reports, corrects four rows and adds two. Each carries the tag of the amendment it comes from. [M0-A48] Draft 0.8 records in eleven rows what the product owner's decisions of 22 October 2026 settled, none of them a device result, and adds one row, for the rewind after a long pause that PO-39 turned on by default; that row carries no amendment tag, because it comes from a decision, not an amendment.

| Risk | Impact | Mitigation / release condition |
| --- | --- | --- |
| Reading adapter cannot provide robust selection/anchors | Core knowledge loop breaks | M0 sample corpus; adapter spike; no launch without stable same-asset reopens. G0.1 (simulator): selection, highlights, footnotes and same-asset reopening pass with Readium 3.11.0 and PDFKit, with adapter workarounds for the engine defects found and page-text digests against OS extraction changes, except highlights on PDF text drawn with a rotated text matrix, where the overlay failed and Section 9.2 gives the approach the product owner approved on 22 October 2026 (A54); finger selection, VoiceOver and real-world PDFs pending [M0-A04] [M0-A11] [M0-A54] |
| Certificate strategy fails in background downloads | Unreliable or insecure transfers | M0 proof and reviewed alternative; no trust-all fallback. G0.2 (simulator): the pinned identity works with background URLSession for local addresses; Tailscale forms fail without an ATS exception, and D16, approved by the product owner on 22 October 2026, adopts the scoped exception subject to the security sign-off and G0.2 device step 6; locked-device behavior pending [M0-A13] |
| Share providers terminate large handoffs | Lost files or false acknowledgement | Durable staging; provider matrix; truthful Files/LAN/wired fallback; the extension's memory limit is undocumented and is measured on a device before any margin is assumed [M0-A20] |
| Original source changes mid-transfer | Corrupted mixed-version audiobook | Immutable prepared version, ETag/parts/final digest; source mutation test |
| Media deletion breaks audio highlights | Highest-priority retention promise fails | Retained excerpt blobs and deletion guard; T23/T44 |
| Models invent passages or misuse context | User trust compromised | Evidence snapshots, quotation validation, scope UI and evaluation corpus |
| Compatible gateway secretly routes externally/runs tools | Privacy or unintended side effects | User-managed disclosure; verified no-tool route; no client tool execution |
| Multi-file/audio edition mismatch | Wrong quote or progress | File-local anchors, explicit association and timeline revisions |
| No backup before phone loss | Permanent record lost | Required export/restore, clear local-only warning and backup visibility |
| Ambiguous source/knowledge deletion | Unintentional data loss | Separate commands, reference checks, trash and explicit destructive review |
| 5,000+ library becomes blocking | Poor adoption despite working features | Lazy metadata, incremental processing, performance gates |
| Scope expands into a general feed/agent platform | Delayed core validation | Explicit v1 boundary; architecture seams only; change-control requirement |
| Dependency/API policy changes | Build or distribution disruption | Exact version lock, source review at kickoff/release, compatibility fixtures; on every Readium, GRDB or SQLite upgrade, re-run the EPUB safety suite, the durability-setting readback and the backup schema comparison; a named owner watches swift-nio-ssl releases for BoringSSL fixes [M0-A01] [M0-A02] [M0-A28] [M0-A29]; GRDB upgrades also re-check how it binds text, so text is never stored cut off [M0-A55]; every Readium upgrade also re-checks what Readium bundles and whether it still links marmelroy/Zip (the advisory row below) [M0-A56] |
| Name/distribution rights not cleared | Public launch delay | Product/legal review; Sylvia is chosen, but this plan is not brand clearance |
| Design tokens drift per screen; status phrases invented ad hoc | Quote/note/generated distinction erodes; "Saved" and "Ready" lose their meaning | Single design package, lint and conformance tests (T53, T54); vocabulary change control in 4.4.9 |
| Literata or Dynamic Type scaling fails on the oldest device | Reader or capture sheet unusable at large text sizes | G0.6 on the oldest supported iPhone, an iPhone 11 Pro (A13, 375 × 812 pt; D-1, decided by the product owner on 22 October 2026), to which the product owner has access; the 375 × 667 pt floor of the iPhone SE (2nd generation) stays a simulator check; system-face fallback for UI roles; reading face always user-switchable. Roles scale by the system text styles' sizes (`UIFontMetrics` did not track them); bars and titles have bounded exceptions (decided by the product owner on 22 October 2026, PO-31 and PO-32); the oldest-device check waits for its device session (runbook Session 8) [M0-A40] [M0-A46] |
| Reading engine runs publication content unsafely by default (Readium 3.11.0) | Script execution, tracking requests or a crash from a hostile book | Sylvia's adapter controls (Section 8.3) with their tests, re-run on every Readium upgrade; the defects found reported upstream [M0-A02] |
| Real-world EPUBs fall outside the compatibility subset (Section 8.3) | Chapters of books a user owns show as placeholders and are left out of search (tag-soup HTML, entity declarations, encodings other than UTF-8; fixed layout refused) | The subset was measured on five real fixtures only (all 195 documents inside it): recheck it against a larger real-book sample in M3 before relying on it; a per-resource status names what is withheld; the import guide states the subset [M0-A03] |
| App Transport Security does not protect local traffic | Cleartext to a LAN host through a programming mistake or a misconfigured endpoint | Client-side HTTPS-only and endpoint-policy rules on every request path, with tests; ATS never relied on for local addresses (Section 14.3); those rules are the cleartext gate on every OS version, with `NSAllowsLocalNetworking` (runbook D-9 (b), decided by the product owner on 22 October 2026) [M0-A14] |
| Background transfers stall while the app is suspended or the phone is locked | A large transfer finishes only when the user opens Sylvia | The honest promise of Section 15.5; part tasks created in the foreground; resumable verified parts; the task window set after the device measurement [M0-A15] |
| Background download tasks hold the bearer token and store a whole body before Sylvia sees it | A copy of the token in the system's transfer daemon for each outstanding task; an unexpected or over-long body written to disk before its head is checked | The task window bounds the outstanding tasks per job (four, kept by the product owner's decision of 22 October 2026, PO-09); across jobs, the job scheduler lets two jobs download at a time, so at most eight requests carrying a token wait (PO-38 (a), decided the same day; Section 15.4), which nothing enforces until the scheduler is built; pause and revocation cancel them; the head is checked before the file is opened, and an over-long body is cancelled while the app runs; disk reservation covers the parts in flight; re-checked with each iOS release; security review [M0-A15] |
| Pairing invitation intercepted through a custom URL scheme | Another app pairs as a new device before the real phone | Scanning in Sylvia or pasting the code; no advertised custom-scheme link (decided by the product owner on 22 October 2026, PO-11 (a)); single use, short expiry and Mac approval; security review [M0-A16] |
| Long audiobook files resume slowly on precise timing | Seconds before a resumed book plays (28-30 s for a 10-hour native FLAC on the simulator) | Per-file timing mode; import remux for the long files that stay precise (keeping the original beside the copy about doubles each remuxed member's storage), both decided by the product owner on 22 October 2026 (PO-20); a visible preparing state; the device run (G0.4 step 1.5) sets which lengths are remuxed [M0-A22] |
| Quick capture relies on `AudioPlaybackIntent` for an action that plays no audio | App Review or a future iOS removes the surface | Not advertised until the device pass; the in-player button is the baseline; an App Group fallback needs its own spike, funded only if the device shows the intent performed outside the app's process (PO-17 (a), decided by the product owner on 22 October 2026) [M0-A26] |
| Durability across power loss cannot be tested | A power loss or an OS crash loses acknowledged saves | `FULL` with `F_FULLFSYNC` per SQLite's and APFS's documented guarantees (D17 and PO-21 (a), decided by the product owner on 22 October 2026); process-death drills; the setting read back on every open [M0-A28] |
| No device evidence yet; the baseline iPhone and an iPad are at hand but untested | Budgets, memory limits, locked behavior and large-size accessibility may differ on hardware, and the baseline's A13 makes the budgets stricter to meet | Serialized device runs from the Stage 0 checklists: each milestone, M1 included, starts after the device steps it builds on have passed on the iPhone available now, and exits after their repeats on the baseline iPhone and an iPad (Section 21.1; PO-34 (b), decided by the product owner on 22 October 2026); the M0 exit waits for every device step the runbook marks blocking (D-10 (i)); no device result inferred from the simulator; the baseline device is the iPhone 11 Pro the product owner has access to (D-1), and the product owner has an iPad with a keyboard and a trackpad or mouse (23 October 2026) [M0-A46] |
| A raw file copied with Finder can be staged incomplete | A paused or stopped Finder copy looks finished, and an audio file cut short can still play, so an incomplete item could become ready (I-04) | The import refuses a file that changes while it is cloned and hashed; staged is not ready, and each type's validation runs first; large transfers are steered to `.sylviapack`, whose layout check proves completeness (advice, not enforcement: the product owner kept the raw import on 22 October 2026, PO-37 (a) and (c), accepting its residual exception to I-04 for raw audio; Section 8.5); G0.3 device steps 28-30 record a real Finder copy, and accepting only `.sylviapack` from Finder above a size, PO-37's alternative, is revisited if they show a copy pausing or stopping unseen [M0-A20] |
| A linked dependency carries an advisory with no fixed release: marmelroy/Zip 2.1.2, CVE-2023-39135 (High, path traversal in `Zip.unzipFile`), linked into the app through Readium and never called | A product code path that reached `Zip` could write outside its target directory | Product code never reaches `Zip` or Minizip, and CI enforces it (ADR-0014 section 3) within stated limits; the final agent review of that guard found two routes around it (ADR-0014 R4-01 and R4-02), to be closed before the M1 app target is created, or before any product target links Readium if that comes first *(24 October 2026: answered by an agent's change, review pending: ADR-0014 status. Until 26 October 2026 this note said closed: the third review of the M0 exit preparation, its finding HON-EP-01.)*; the security reviewer accepts the residual risk; Readium is asked to drop the dependency or move to a fixed fork, and every Readium upgrade re-checks it [M0-A56] |
| A rewind after a long pause, on by default, moves the playhead without being asked (draft 0.8) | A listener resumes earlier than they left off, or hears a passage again, without having asked for it | The rewind is graduated and bounded (about 10 seconds after a pause of a few minutes, rising to about 60 seconds after a day), shown with a brief notice that offers to undo it, configurable and able to be turned off in Settings, and it never changes a saved bookmark, quote or capture anchor (Section 10.1; PO-39, the product owner's choice of 22 October 2026 over the recommended off-by-default setting); M4 sets the exact steps and states them in ADR-0006; G0.4 device step 17 checks the spike's rule on a phone |

## 23.3 Review sign-off

Product approves scope, experience boundaries and retention language. Technical leads approve architecture, contracts and migration strategy. Security approves pairing (including the Tailscale exception, D16), endpoint/content isolation (including the EPUB adapter's safety configuration and the archive rules), the data-protection class (D17) and exports, and accepts with the product owner the residual risks the threat model (ADR-0015) marks as owner decisions, among them quick capture on a locked phone without authentication (B11, with D03) and asking before resending after an uncertain 5xx answer (B6) [M0-A52], and accepts the marmelroy/Zip advisory's residual risk with its CI guard, once that guard's two open routes are closed (Section 23.2) [M0-A56]. QA approves fixture coverage, device matrix and failure tests. Design approves capture/accessibility flows, the Marginalia token values after G0.6, the marker set and the status vocabulary. Release owner approves distribution and privacy declarations.

**Who signs (decided by the product owner on 22 October 2026).** Sylvia is a solo project. The product owner signs the roles of the security reviewer, QA, design and the technical lead above personally, and records each role's sign-off only after the device sessions have produced the evidence that role signs (`Docs/Stage0/M0-device-runbook.md`, Sections 6 and 7); until then each stays pending, and none is signed in this draft. The product owner's approval of the Section 23.1 decisions and of the amendments on 22 October 2026 was given as product owner: it is no role's sign-off and no device result. Every review of the M0 work so far was made by agents, not by independent people. Before any public release, a security review by someone outside the project is recommended, the independent security review for pairing and content isolation that Section 21.3 already asks for.

Approval should result in a versioned 1.0 execution specification and prioritized backlog. This review draft is not authorization to implement unapproved speculative features or to skip feasibility gates. The decisions of 22 October 2026 do not complete that approval: the 1.0 specification follows the M0 exit, which waits for the device sessions and the role sign-offs above.

# 24. Roadmap seams without building the roadmap

**Sequence:** deliver native iOS/iPadOS V1 with the lightweight Mac companion first. Saved articles, a browser-based reader, subscriptions and companion-mode capture are later workstreams with separate implementation decisions. Shared contracts and design tokens support those clients without requiring web infrastructure during V1. [P3]

**Docker hub (v1.5 candidate):** implement the same source/manifest contracts as the Mac, add an always-on ingestion inbox and authorized agent-delivered assets, then design actual state synchronization separately. Server authority, managed versus referenced storage, metadata conflict rules and household profiles are not settled by this v1 document.

**Articles, feeds and newsletters - the unified content hub (post-v1, phased).** Product intent from the product owner (7 October 2026): content from many disparate systems - bookmarks, a standalone Substack app, RSS readers - should have one home in Sylvia, with the same permanent record of notes and questions that books get, and without relying on another service to synchronize that content or its context across devices. This is a stated goal for later releases; none of it is in v1 scope (Section 3.3).

*Phase A - Saved articles (first post-v1 release).* The share extension and URL entry accept a webpage link and create an **Article** work kind: sanitized readable text and an HTML snapshot with provenance (source URL, publisher, author, published and saved dates, fetch time). The article opens in the existing reader and uses the same capture, note, Ask AI and search flows. When the page or its feed entry exposes an audio version (for example a Substack post's "listen" link or an enclosure), record it as an `AssetLocation` of kind remote-audio, with the URL and provenance. The player offers it as an explicit stream-or-download choice and never presents it as a local file until downloaded. Pasting one Substack article link therefore ends in the Inbox, readable and listenable later, with no bookmark folder or separate app.

For Phase A, evaluate Gloss's `fetch-article.ts`, `html-to-blocks.ts` and `images.ts` as references for Readability preparation, streamed-page content, images, captions and tables. Test a bounded article corpus before selecting an implementation. Feed extracted content into Sylvia's planned intake, provenance, retained-snapshot and capture contracts; preserve exact source wording separately from reading/search normalization, and apply Sylvia's content-isolation and network rules. Adaptation may be native or use an explicitly chosen processing service; this investigation does not mandate a Node runtime or hosted account. Gloss's evaluation cases can inform coverage, while Sylvia verifies its own results. [S25]

*Phase B - Subscriptions.* Add recurring Source adapters for RSS/Atom, including public Substack publications (their `/feed` addresses and per-post audio enclosures). New entries arrive in the Inbox as **Unread** items. Refresh runs on app open and on iOS background refresh, which the system schedules opportunistically; the interface must say when a feed was last checked and must not promise always-current delivery. An always-current Inbox is a property of the Docker hub or Mac companion (v1.5 candidate, above), not of the phone alone.

*Phase C - Paid and authenticated sources.* Paid Substack posts, other paywalled newsletters and email forwarding/IMAP each need their own authentication, security and terms-of-service review before any commitment. Substack offers no public API for a reader's paid subscriptions, so this phase is a feasibility question, not a scheduled feature. Never ask the user to hand over a password, and never scrape behind a login without a documented, authorized route. Email/IMAP/forwarding is a different integration from RSS.

*Rules that apply to every phase.* Keep arrival, read status, deliberate retention and saved knowledge separate: a feed arrival is Unread, not a consumed work; only a user action ("Keep") makes it a retained Work, and unread items may expire under a user-visible policy. Notes, questions and quotes on an article persist after the snapshot is removed, per invariants I-03 and I-08. Respect publishers: fetch only what the user subscribes to or saves, honor robots/terms for fetching, and keep snapshots private to the user. Duplicate detection uses canonical URL plus content hash. A new work kind receives a marker only through the process in Section 4.4.9; Article does not borrow Quote or Note. The Inbox grows beyond transfer states (Section 4.1) to include Unread, Saved and "Listen available", and Section 4.4.6 gains those words only through the same process.

*Requirement stubs for later backlog (not scheduled):* ART-01 save a link as an Article with snapshot and provenance; ART-02 capture and play a source-provided listen link; FEED-01 subscribe to RSS/Atom and populate the Inbox; FEED-02 public Substack subscription; FEED-03 retention and expiry of unread items; FEED-04 duplicate handling across feed and one-off saves; SRC-01 authenticated-source feasibility study.

**Physical reading:** add camera/photo capture and OCR as another producer of captures/anchors. Preserve image/text confidence and manual page correction. An image-only PDF in v1 must not be misrepresented as already supporting this flow.

**External players:** investigate documented metadata/control APIs and policy constraints per service. Do not inherit earlier speculative assumptions about automatically hearing Spotify or tracking every audiobook. External audio capture requires independent technical and authorization review, not a generic plugin hook.

**Alignment/transcription:** add full-book asynchronous speech processing and edition-aware audio/text alignment after durable capture is proven. Store alignment confidence and provenance; preserve manual association and no-context modes.

**Broader platforms:** reuse exported schemas, test fixtures, the transfer protocol and the exported design tokens in `Contracts/design/`; implement native platform adapters. A portable data model and token file are an investment in future clients, not a claim that a single Swift package will run every platform unchanged. The grayscale conformance work in Section 4.4.8 also prepares the language for reflective e-paper tablets, which are a plausible later target.

**Web reader (post-V1, separate from saved-article ingestion):** add a browser client for reading supported content and revisiting the same source-linked knowledge. Use Gloss's typography, selection toolbar, anchored margin conversations, citation previews and responsive layout as design references, expressed through Sylvia's Marginalia tokens and Quote/Note/Generated distinctions. A React implementation is a candidate for evaluation, not a chosen framework or a replacement for the native clients. [P3, S25]

Use Sylvia's planned versioned capture, anchor and ContextPack contracts and `Contracts/design/` export, validating the finalized contracts before the web prototype. Browser selection offsets need an explicit mapping to the declared locator units and source/extraction version; they must not become a competing identity system. Preserve retained quotations, answer evidence, unknown record kinds and original edition/asset bindings through import, editing and export. A web client must not imply access to a full work from a retained excerpt, or silently reinterpret a native anchor.

Start with a bounded reading → annotation → question → evidence-preview prototype using fixture/imported data and a controllable test provider. Before committing the web build, decide supported formats, durable browser storage and eviction/recovery, backup/migration, credentials and provider access, untrusted-document isolation, keyboard/screen-reader/mobile-browser behavior, and how the client receives a user's library. Hosting, accounts, transfer and any cross-device synchronization require explicit architecture decisions; browser access alone does not establish sync. A hub dependency is optional and must be chosen separately. Promote the prototype only after it demonstrates fidelity, durable save/recovery, truthful AI scope and accessible return-to-source behavior. Its schedule follows V1; its ordering relative to article Phase A remains a roadmap decision.

Any direct reuse of Gloss source or assets requires a suitable license or explicit permission recorded through the dependency and license review in Sections 18 and 22 before adoption. The reviewed snapshot declares no reuse license; interaction ideas can be implemented independently. Reuse must retain Sylvia's existing evidence, privacy and retention guarantees, and estimated savings require a measured adaptation rather than similarity of screens. [S25]

**Later knowledge tools:** semantic retrieval, broader research across works, projects/taxonomy, vocabulary review and integrations can follow demonstrated use of retained knowledge. Do not make the initial data model depend on a particular embedding dimension, model provider or AI framework.

# Appendix A. Contract sketches

These examples make the boundaries reviewable. They are representative payloads, not compiled code or complete JSON Schema/OpenAPI documents. Replace example IDs/digests with generated fixtures and validate exact optionality, limits and error enums during M0.

## A.1 Portable capture envelope

```json
{
  "schema_version": 1,
  "capture_id": "4d76e6bc-9e23-4d23-8b1a-1b3b8c487fe9",
  "work_id": "e8b1c045-32a7-47bc-9f0c-5f6788c405bb",
  "edition_id": "f95a48f1-c7b9-4bcb-8886-7728e490c5c2",
  "kind": "text_quote",
  "quoted_text": "Example passage from a licensed test fixture.",
  "source_snapshot": {
    "title": "Sylvia Test Book",
    "author_display": "Fixture Author",
    "location_label": "Chapter 2",
    "source_kind": "local_epub"
  },
  "anchors": [{
    "version": 1,
    "kind": "epub",
    "asset_id": "ba28d451-0e31-4dca-9822-bdc10fdf1dfd",
    "resource_href": "text/chapter02.xhtml",
    "exact_text": "Example passage from a licensed test fixture.",
    "prefix": "The preceding sentence. ",
    "suffix": " The next sentence.",
    "reader_locator": {
      "href": "text/chapter02.xhtml",
      "type": "application/xhtml+xml",
      "locations": {"progression": 0.25}
    }
  }],
  "created_at": "2026-10-05T00:00:00Z",
  "revision": 1
}
```

Production anchors also bind to the asset digest. For PDF, replace the reader locator with page/label/text-range/geometry data. For audio, `quoted_text` is absent unless a labelled transcript/user quotation exists, and `anchors` contain file-local start/end milliseconds. Never make fake text mandatory to fit an audio capture into a quote schema. The `kind` field maps one-to-one onto the marker set in Section 4.4.5; a client renders a capture it does not recognize with the Pending marker and its raw kind label, never as a Quote. The kind strings of the design package, approved by the product owner with the amendments on 22 October 2026, are `text_quote`, `note`, `audio_capture`, `generated_answer` and `word`, matched exactly and case-sensitively (ADR-0013). Stage 0 found what the full schemas must also carry: for EPUB, one anchor per resource, with an ordered segment for a quotation that continues, optional Sylvia-extraction offsets and the verbatim reader locator with its adapter version (ADR-0004); for PDF, page segments with CropBox-normalized line rectangles, the printed label only from `/PageLabels`, the extraction version and a page-text digest (ADR-0005); for audio, one ordered list of file-local ranges, each bound to its member's asset ID and digest, with the excerpt's actual ranges, source formats and format (ADR-0006). The `anchor` and `capture-envelope` schemas were written by M0 contract consolidation and merged at M0 assembly (`Contracts/schemas/`, ADR-0016; proposed like the rest of Stage 0). For PDF, a quotation of several pieces is the reader's composition of them, not their join (G0.1 PDF finding 15), so a client restores segment by segment and keeps `exact_text` as the quotation. [M0-A50] Since the product owner approved Section 9.2's approach on 22 October 2026, each PDF line rectangle also carries its reading direction, an additive field added with the M3 reader. [M0-A54]

## A.2 Context pack envelope

```json
{
  "schema_version": 1,
  "request_id": "ad6f50e5-489e-49c8-bf5e-ec5c2520bb12",
  "scope": "selected_passage",
  "mode": "source_grounded",
  "coverage": "excerpt_only",
  "question": "What does the author mean here?",
  "evidence": [{
    "citation_id": "c1",
    "capture_id": "4d76e6bc-9e23-4d23-8b1a-1b3b8c487fe9",
    "text": "Example passage from a licensed test fixture.",
    "origin": "source_text",
    "location_label": "Chapter 2"
  }],
  "truncated": false,
  "prompt_template_version": "sylvia-grounded-1"
}
```

Production packs include exact evidence snapshots/digests, selected endpoint/model identity without credentials, budget accounting, spoiler boundary and any included conversation turns. Only `c1` can become a resolved source citation for this example; an invented `c99` cannot link into the broader library. The v1 contract (`Contracts/schemas/context-pack.v1.schema.json`) adds edition-bound positions for the spoiler boundary, stated limitations, included and excluded earlier turns with their destination, and a digest over an exactly specified serialization; every pack numbers its citations from `c1` (Section 13.4). [M0-A36]

## A.3 Transfer manifest requirements

A complete schema must define: protocol version, source ID, immutable item/asset version, manifest digest, edition/grouping metadata, asset IDs, media type, 64-bit total byte length, strong ETag, full SHA-256, chunk size, ordered part offsets/lengths/digests, and optional cover references. Paths are source-relative opaque content identifiers, never arbitrary filesystem paths supplied by the phone.

For zero-length files, duplicate parts, overlapping ranges, missing final bytes, inconsistent total length, changed ETag or unsupported major version, reject the manifest before downloading. Limit metadata sizes and part counts. A source manifest never sets a local file path or overwrites the phone's annotation/ledger state.

## A.4 Command boundaries

```text
ImportService.accept(input, idempotencyKey) -> ImportJobID
CaptureService.save(selection, comment, idempotencyKey) -> SavedCapture
AudioService.captureRecent(sourceDuration) -> CaptureID + preservationState
ContextService.prepare(scope, question, privacyPolicy) -> ContextPack
AIService.send(contextPack, providerConfig, consent) -> AnswerEventStream
TranscriptionService.request(clip, speechConfig, audioConsent) -> TranscriptionJobID
TransferService.enqueue(sourceItemVersion) -> TransferJobID
RetentionService.previewRemoval(assetID) -> ImpactReport
RetentionService.removeDownload(approvedImpact) -> RemovalResult
BackupService.export(snapshotOptions) -> VerifiedExport
BackupService.validateRestore(bundle) -> RestorePlan
```

Mutating calls return typed errors and durable state, not booleans that hide partial completion. Command idempotency is local and under Sylvia's control; it does not imply that a remote model provider honors the same key. UI reads observable projections rather than directly mutating service internals, and renders each projected state with the vocabulary string for that state. `AIService.send` is single-flight per request ID and accepts a stop at any point, and a request ID has exactly one record [M0-A33]. `TranscriptionService.request` (added in draft 0.5) is single-flight per clip: a second request returns the clip's existing job and never replaces a transcript or the user's correction [M0-A37].

## A.5 Design token export sketch

```json
{
  "schema_version": 1,
  "language": "marginalia",
  "color": {
    "ground":  {"light": "#F4F2ED", "dark": "#161512"},
    "surface": {"light": "#FBFAF7", "dark": "#1E1C19"},
    "ink":     {"light": "#1C1B18", "dark": "#ECE7DD"},
    "muted":   {"light": "#6B6760", "dark": "#A8A298"},
    "pine":    {"light": "#2F5D50", "dark": "#7FB5A3"},
    "ochre":   {"light": "#8A5410", "dark": "#D9A24A"},
    "ochre_tint": {"light": "#F1E4C8", "dark": "#3A2E17"}
  },
  "marker": {
    "quote":     {"text": {"light": "#8A5410", "dark": "#D9A24A"}, "glyph": "quote.opening", "label": "QUOTE"},
    "note":      {"text": {"light": "#2F5D50", "dark": "#7FB5A3"}, "glyph": "pencil.tip", "label": "NOTE"},
    "audio":     {"text": {"light": "#3F5A78", "dark": "#8FB0D4"}, "glyph": "waveform", "label": "AUDIO"},
    "generated": {"text": {"light": "#6B4E8E", "dark": "#B49BD6"}, "glyph": "sylvia.prompt", "label": "GENERATED", "frame": "dashed"},
    "word":      {"text": {"light": "#8A5410", "dark": "#D9A24A"}, "glyph": "book", "label": "WORD"},
    "attention": {"text": {"light": "#A63D2F", "dark": "#E0837A"}, "glyph": "exclamationmark.triangle", "label": "NEEDS ATTENTION"},
    "pending":   {"text": {"light": "#6B6760", "dark": "#A8A298"}, "glyph": "circle.fill", "label": "QUEUED"}
  },
  "type": {
    "display": {"face": "Literata", "weight": 600, "size": 34, "line": 40, "maps_to": "largeTitle"},
    "reading": {"face": "Literata", "weight": 400, "size": 19, "line": 30, "user_range": [14, 28]},
    "body":    {"face": "system",   "weight": 400, "size": 17, "line": 23, "maps_to": "body"}
  },
  "vocabulary": {
    "save.in_progress": "Saving…",
    "save.done": "Saved",
    "save.failed": "Not saved · your text is still here",
    "import.ready_indexing": "Ready · indexing continues"
  }
}
```

The export is generated from the Swift package, not hand-maintained; glyph names are SF Symbols identifiers, or `sylvia.*` custom symbols shipped in the design package, with documented equivalents for other platforms. Tints marked "derived" in Section 4.4.2 appear here only once set in the asset catalog. The generated export now exists (`Contracts/design/marginalia.v1.json`, from `SylviaDesign` v0.1) and supersedes this sketch; it ships the derived `ochre_tint` dark #31291A rather than the #3A2E17 above, pending the design choice in Section 4.4.2. [M0-A41]

# Appendix B. Source notes and technical references

[P1] **Product basis:** *Sylvia - Product Brief*, October 2026, and the product decisions in the accompanying discussion. The brief establishes standalone native iOS plus a Mac companion, permanent knowledge, reliable import, Work -> Edition -> Asset, 5,000+ scale and optional providers. RSS/newsletters were subsequently raised as a compatible roadmap direction, not an approved v1 requirement. The transcript supersedes the brief where a later user decision is explicit.

[P2] **Design basis:** *Sylvia Concept Designs*, 5-6 October 2026, checked in under `Docs/Design/` in this repository: rendered boards in `images/`, board source in `canvas/`, and a README that maps each board to its plan section. Contains the Marginalia design-language sheet, thirteen iPhone screens, an iPad reader with Thoughts pane, the Mac companion window, two Inbox row-layout options, and the six iPhone screens plus the tablet reader rendered in grayscale. Four palette alternatives were reviewed on 6 October 2026 and removed after the product owner confirmed Marginalia. The boards were authored on a design canvas private to the product owner; the checked-in export is the citable reference, and Section 4.4 is the specification.

[P3] **Product direction, 15 October 2026:** the product owner directed the plan to keep iOS V1 first, incorporate relevant Gloss UX ideas into M3/M5 and include a later web reader. The M0 baseline, reviewed separately on the M0 integration branch, is [the gate summary at `d8e7d39`](https://github.com/jevidon/sylvia/blob/d8e7d399cd3f6468fa0b2c79c26868deeaa8b302/Docs/Stage0/M0-gate.md); integration gaps are recorded in [the contracts review at that snapshot](https://github.com/jevidon/sylvia/blob/d8e7d399cd3f6468fa0b2c79c26868deeaa8b302/Docs/Stage0/M0-contracts.md). That M0 feasibility work was merged into main on 15 October 2026 (pull request #4), and the M0 gate is pending approval. These are background references, not files or amendments incorporated by this revision. The direction approves the UX and roadmap additions, not the pending Stage 0 proposals or a web implementation schedule. *(22 October 2026: the product owner has since decided the Stage 0 proposals, draft 0.8; the M0 gate itself is still pending.)*

External references below were reviewed or retrieved on 5 October 2026 unless noted. These are implementation references, not a substitute for running Stage 0. Some Apple reference pages expose their full content only through JavaScript/Markdown; the exact API configuration and minimum-OS behavior must be checked in Xcode/documentation at kickoff. Avoid beta/develop branch assumptions. All security/API/store guidance must be rechecked before public release.

[S1] **Readium Swift Toolkit** - official repository; supported publication/navigation capabilities and integration requirements. https://github.com/readium/swift-toolkit

[S2] **GRDB.swift** - official repository/documentation; SQLite access, transactions, migrations and backups. https://github.com/groue/GRDB.swift

[S3] **Readium Locators** - official architecture model for publication positions and text context. https://readium.org/architecture/models/locators/

[S4] **SQLite FTS5** - official full-text search documentation. https://www.sqlite.org/fts5.html

[S5] **Apple: Downloading files in the background** - URLSession scheduling, lifecycle handoff and download completion behavior. https://developer.apple.com/documentation/foundation/downloading-files-in-the-background

[S6] **Apple: App Extension Programming Guide, Handling Common Scenarios** - shared containers and background session coordination. Archived guide; validate current target behavior. https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html

[S7] **Apple: Use Finder to share files between Mac and iPhone/iPad** - supported cable/file-sharing user flow. https://support.apple.com/en-nz/119585

[S8] **Apple: Configuring Audio Settings** - playback audio session and background audio. Archived guide; use current APIs in implementation. https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MediaPlaybackGuide/Contents/Resources/en.lproj/ConfiguringAudioSettings/ConfiguringAudioSettings.html

[S9] **Apple: MPRemoteCommandCenter** - supported remote media commands; does not establish a custom lock-screen clip button. https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter

[S10] **Apple: PDFSelection** - PDF text-selection API reference. https://developer.apple.com/documentation/pdfkit/pdfselection

[S11] **Apple: UIReferenceLibraryViewController** - system dictionary interface. https://developer.apple.com/documentation/uikit/uireferencelibraryviewcontroller

[S12] **Apple TN3179: Understanding local network privacy** - permissions and local discovery considerations. https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

[S13] **Apple: NSAllowsLocalNetworking** - ATS local-network configuration reference; validate address-specific behavior on the deployment floor. https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking

[S14] **OpenAI: Managing billing for ChatGPT and the API platform** - distinct billing systems. https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform

[S15] **Anthropic: Paid Claude subscriptions versus API/Console billing** - separate API access/billing. https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-do-i-have-to-pay-separately-to-use-the-claude-api-and-console

[S16] **OpenAI: File transcription** - speech-to-text API capabilities and limits. https://developers.openai.com/api/docs/guides/speech-to-text

[S17] **OpenAI: Chat API reference** - request/response/stream contract for compatible chat adapters. https://developers.openai.com/api/reference/resources/chat

[S18] **Anthropic: Create a Message** - native Messages API contract. https://platform.claude.com/docs/en/api/messages/create

[S19] **Apple App Review Guidelines** - including privacy/third-party AI disclosure, user data and media access. This document is not legal advice or a guarantee of approval. https://developer.apple.com/app-store/review/guidelines/

[S20] **Tailscale: MagicDNS** - user-configured hostname routing; Sylvia must support direct addressing without relying on discovery. https://tailscale.com/docs/features/magicdns

[S21] **Apple: Keychain accessibility** - device-only/after-first-unlock accessibility reference; broader file-protection policy requires its own implementation validation. https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly

[S22] **Apple: UIFileSharingEnabled** - application file-sharing configuration reference. https://developer.apple.com/documentation/bundleresources/information-property-list/uifilesharingenabled

[S23] **Literata** - variable serif designed for long-form screen reading; SIL Open Font License. Confirm the license text and the exact release to bundle at kickoff. Added 6 October 2026. https://github.com/googlefonts/literata

[S24] **Apple: UIFontMetrics** - scaling custom fonts with Dynamic Type against a text style. Added 6 October 2026. Evaluated at the M0 gate and not used for the type roles (Section 4.4.3) [M0-A40]. https://developer.apple.com/documentation/uikit/uifontmetrics

[S25] **Gloss reference implementation** - reviewed 15 October 2026 at [commit `54b13b8882d8a109132c5b2045acd6b45628563d`](https://github.com/Nutlope/gloss/tree/54b13b8882d8a109132c5b2045acd6b45628563d). Interaction references: `components/reader/Lens.tsx`, `Margin.tsx`, `Answer.tsx`, `Reader.tsx`, and `lib/actions.ts` / `lib/prompts.ts`. Article references: `lib/fetch-article.ts`, `lib/html-to-blocks.ts`, `lib/images.ts` and the image/PDF evaluation cases under `scripts/`. These inform design and extraction experiments; they do not establish Sylvia's runtime behavior or replace its native stack. No reuse license was declared in that snapshot; direct source or asset adoption requires permission/license review under Sections 18 and 22.

# Appendix C. Final release checklist

Approve the versioned scope and decision register. Pin the SDK/dependencies and pass all Stage 0 gates, their device steps included [M0-A46]. Demonstrate all six golden journeys on real devices. Pass every P0 acceptance case, including source deletion and restore. Resolve all critical/high privacy, data-loss, security and crash defects. Record any gated-feature exclusions in user-facing release notes rather than hiding them. Ship the third-party acknowledgements the dependency licenses require (copyright notices and license texts, and the NOTICE contents of the Apache-2.0 packages that have one; ADR-0014) and the Literata Open Font License with the font. [M0-A51]

Verify source/capture fidelity, no false ready/saved states, no unexpected provider transmission and no leaked credentials. Complete the compatibility matrix, accessibility pass including the grayscale and Increase Contrast pass (T53), the vocabulary conformance run (T54), catalog-scale measurements and backup/migration drills. Validate the application without a server, Mac, model subscription or developer account configuration.

Complete privacy/distribution review, licensed sample content, support documentation and pilot feedback review. The final go/no-go question is not whether every component exists: **can a user reliably turn a reading or listening moment into knowledge they can find and trust later, even after the media is gone?**

# Appendix D. Change log

**Draft 0.8 - 22 October 2026: the product owner's decisions on the M0 gate's questions recorded.** On 22 October 2026 the product owner decided all 128 items put to them for the M0 gate: the Section 23.1 decisions D01-D17, the amendment tags A01-A56 of drafts 0.5 and 0.7, the product-owner questions PO-01 to PO-44 (`Docs/Stage0/M0-plan-amendments.md` Section 4), the device runbook's decisions D-1 to D-10 (`Docs/Stage0/M0-device-runbook.md` Section 6) and H-1. 123 of them accept the recommendation as the documents state it; five do not: PO-13, PO-23, PO-33, PO-39 and D-1, each with clarifications the owner gave in conversation the same day. This draft records the decisions as they were relayed to it, where the plan put each question or its pending text, keeping the reasoning; where the owner chose otherwise, it changes the text the recommendation drove and says what that text said. Approving a decision is not a device result: every device and human step stays pending, the M0 exit still needs every device step the device runbook's Section 7 marks blocking (D-10 (i)), and the role sign-offs of Section 23.3 are the product owner's, given personally and each only after the device sessions have produced the evidence it signs, so none is signed here. It is still not the versioned 1.0 execution specification, which follows the M0 exit (Section 23.3). Agent-written; not reviewed; human sign-off pending. No budget was relaxed, no scope changed beyond the decisions, and Sections 2.2, 21.5 and 24 are unchanged. *(23 October 2026: two agent reviews have since read this draft, the review of the decisions round's assembly on 22 October 2026, whose finding FID-01 corrected Section 15.5 and the entry above, and the review of that fix the same day; neither accepted it, and the human sign-off is still pending. A third agent review read it with the second fix on 23 October 2026, and none of its findings relayed to the follow-up names a defect in it; the follow-up's changes of that day (the item recorded on 23 October 2026, below) were read by a fourth agent review the same day, whose findings named three defects in them, corrected in the last item of this entry, which has not been reviewed. Until then this entry said only "not reviewed": that second review, its finding HON-12.)*

The five decisions that are not the recommendation:

- **D-1** (Section 19.1; also Sections 21.1, 23.1 (D01) and 23.2): device A, the oldest supported iPhone and the baseline device, is the iPhone 11 Pro (A13, 375 × 812 pt), and the iPhone 11 is a second A13 phone; the product owner has access to both. The recommendation, option (a), kept the iPhone 12-class baseline of earlier drafts. On A13 phones the Section 19.2 budgets, whose values do not change, are stricter to meet; the 375 × 667 pt floor of the iPhone SE (2nd generation) stays a simulator check, because no such device is at hand. The second part of D-1, answered separately, keeps the iPad's device steps (runbook Session 9) in M0, as recommended. Changed: 19.1's baseline and the statement that neither the baseline device nor an iPad was available; 21.1's iPhone 12-class baseline; D01's row; the oldest-device and device-evidence risk rows.
- **PO-13** (Section 15.1): the phone also reads the device inbox periodically in the background when iOS gives the app background time, opportunistically and with no promise of timely delivery; 15.1 still promises no real-time delivery. The recommendation, option (a), read it only on launch, on returning to the foreground and when the Inbox is shown.
- **PO-23** (Sections 20.2 (T50), 21.1 and 21.2 (M1)): Stage 0 builds the background-audio harness for the locked-device test (G0.5 recovery device step 3) before the device run, so that the run is conclusive the first time; the app-level unavailable state before the first unlock stays in M1 with the app shell. The recommendation, option (a), built the harness only if step 3 proved inconclusive, and M1 then waited for it. This draft records the decision only: the harness and its results belong to the Stage 0 records.
- **PO-33** (Sections 4.2 and 21.2 (M2)): three samples ship in M2, short excerpts of the Standard Ebooks (CC0) editions of *Middlemarch*, *Walden* and *Meditations*, each clearly marked as a sample and removable; *Meditations* is paired with an excerpt of its LibriVox (public domain) recording, so onboarding can show listening and capture too; their provenance goes in `Fixtures/LICENSES.md`. The recommendation was one short Standard Ebooks excerpt, such as the prototype's Middlemarch passage, and draft 0.7 left the choice to M2.
- **PO-39** (Section 10.1; also Sections 4.4.6 and 23.2): skip intervals of 15 seconds back and 15 seconds forward and both sleep-timer kinds, as recommended; the rewind after a long pause on by default and graduated (about 10 seconds after a pause of a few minutes, rising to about 60 seconds after a day, the exact steps set in M4 within those bounds and stated in ADR-0006), shown with a brief notice that offers Undo, configurable and able to be turned off in Settings, and never changing a saved bookmark, quote or capture anchor. The recommendation was the rewind as a setting, off by default, and draft 0.7 left these defaults to M4. The 4.4.6 gaps table lists the notice and its undo action, and a new risk row, without an amendment tag, covers a rewind the listener did not ask for.

Recorded as decided, as recommended, each where the plan carried its pending text:

- Front matter, introduction and Sections 1 and 1.1: the draft's status; the amendments approved; the narrowings no failed spike forces each decided explicitly (PO-05, PO-16, PO-27, PO-30, PO-31, PO-32, PO-36); a note that text from drafts 0.1-0.4 that still calls a Section 23.1 default proposed is covered by that decision's approval.
- Section 3.1 (PO-18); 3.3 (D03, PO-17); 4.4.1, 4.4.3 and 4.4.7 (PO-31, PO-32); 4.4.2, 4.4.4, 4.4.7 and 4.4.8, the token, motion and component values approved by the product owner with design review still pending; 4.4.4 and T51 (PO-30, conditional on G0.6 device step 19); 4.4.6 (PO-28, PO-29, PO-03).
- Section 6.3 (PO-35): the owner confirmed the Xcode 27.1 pin as their own decision and reported the App Store's automatic updates turned off, which a read-only check of the setting's key bore out the same day; the check of Apple's release notes stays the technical lead's.
- Sections 7.2, 8.3, 10.1, 17.1 and the long-audio risk row (PO-20); 7.4, 18.1 and the power-loss row (D17, PO-21); 8.1 (PO-16, PO-15); 8.3 (PO-01, PO-02); 8.4, 8.5 and 16.4 (PO-14); 8.5 and the raw-copy row (PO-37); 9.1 (PO-03); 9.2 (PO-05, PO-06, and the approach for rotated PDF text); 9.4 (PO-04); 10.2 (PO-19).
- Sections 13.1 and 14.4 (PO-27); 13.2, 14.1 and 14.4 (PO-24); 13.4 (PO-25); 14.1 (PO-26); 14.3 and the ATS row (PO-36, and runbook decision D-9 (b), which ships `NSAllowsLocalNetworking` with Sylvia's own endpoint rules as the cleartext gate on every OS version, where 14.3 had left the ATS key to the device run); 14.5 (the response caps).
- Section 15.1, T43, the M6 row and the certificate row (D16, PO-07: the scoped exception if the security reviewer approves it); 15.2 and the pairing row (D07, PO-10, PO-11); 15.4 and the token row (PO-09, PO-38); 15.5 (PO-08; PO-12 for the job store; for the sources file and the import ledger the recommendation proposed no option, so the decision chose none: each stays the product owner's to decide, and a damaged one keeps the launch deferred until then; decided on 23 October 2026, the item recorded that day, below).
- Sections 17.1 (PO-40) and 17.3 (PO-22, D10); 21.1, 21.2 and the device-evidence row (PO-34; runbook decisions D-10 (i) and D-2 (a)); 21.4, whose inputs to the re-estimate name the decisions that add work; Appendix A.1 (the capture-kind strings and the PDF reading direction).
- Section 23.1: every decision, D01-D17, approved by the product owner on 22 October 2026, with the choices each approval made and the role sign-offs and device steps still pending in its last column, which named the decision owners only. Section 23.2: eleven rows record what the decisions settled, and one row is added (PO-39, above). Section 23.3: the product owner signs the roles of the security reviewer, QA, design and the technical lead personally, each only after the device sessions have produced its evidence; all reviews of the M0 work so far were made by agents, not independent people; a security review by someone outside the project is recommended before any public release.
- Dated notes: Appendix B [P3], and the draft 0.7, 0.6, 0.5 and 0.3 entries below.
- *Corrected on 22 October 2026, after the review of the decisions round (its finding FID-01): Section 15.5 and the 15.5 item above said that the product owner's decision kept the sources file and the import ledger without a repair path, as if the owner had chosen the deferred launch for them; nothing was chosen for either, and both stay open with the product owner, as `Docs/Stage0/M0-gate.md`, the amendments and ADR-0009 say (decided on 23 October 2026, set aside and recover: the item recorded that day, below). Not reviewed.*
- No plan text changes for the other decisions: D-3 is PO-35; D-4, D-5, D-6, D-7 (for which the draft 0.6 entry has a note) and D-8 concern the device runbook, the ADRs and the Stage 0 records; PO-41, PO-43 and PO-44 are license decisions recorded in ADR-0014; PO-42 has no default and stays with counsel, as D13's row then said (23 October 2026: the product owner took all four on for now, the item recorded that day, below). H-1 concerns ADR-0002's branch rule, which records it (pull request #4's merge before the M0 exit review, a one-off exception), and this draft carries no text for it.
- *Recorded on 23 October 2026, within draft 0.8: the product owner's answers of that day on what the decisions left open, as relayed to the follow-up of the decisions round (`Docs/Stage0/evidence/M0-Decisions/followup/owner-answers-2026-10-23.md`). PO-12's sources file and import ledger: set aside and recover, a damaged sources file moved aside for the diagnostic export and every Mac paired again, a damaged import ledger moved aside and an item already imported possibly arriving again as a duplicate for review, transfers working on (Section 15.5; the job store's (a) stands). PO-41 to PO-44, the questions left for counsel, PO-42 included: the product owner handles them for now, their recommended defaults applying to the owner's own and TestFlight builds with the notices the licenses require, and a lawyer's review comes before any public App Store release (D13's row; ADR-0014 records the rest; for the Mac companion's notarized builds, which the answer does not name, the next item). The iPad: the product owner has one with a keyboard and a trackpad or mouse for the device runbook's Session 9, its model recorded at Session 0 (Sections 19.1 and 21.1 and the device-evidence risk row). H-1's exception also covers pull request #5 and the merge of the M0 decisions branch into main before the M0 exit (ADR-0002; no text here). The readings of D-6, D-7 and D-9 (b) are confirmed (the draft 0.6 entry's note; ADR-0011 already records D-9 (b)'s key). The revision date above moved to 23 October 2026; no budget, scope or decision of 22 October 2026 changed. Agent-written; not reviewed.*
- *Corrected on 23 October 2026, after an agent review of the item above, the review of the follow-up of the decisions round (its findings FID4-03, FID4-04 and FID4-05): Section 21.1 said that no device has to be acquired, though the iPad's model and iPadOS were not known, and now makes that depend on the device runbook's check, before its Session 0, that the iPad runs iPadOS 26 or later; D13's row read the answer as putting the lawyer's review before the Mac companion's public release too, which the answer, naming the owner's own and TestFlight builds and a public App Store release, does not say, so for the companion's notarized builds PO-42 is still settled before one is distributed beyond the team, as on 22 October 2026; and the 15.5 items above, the item on the decisions with no plan text and this entry's review note now point to the answers of 23 October 2026. No budget, scope or decision changed. Agent-written; not reviewed.*

**Draft 0.7 - draft 0.5 re-checked at the M0 final fix, pending product-owner approval.** 19 October 2026. Draft 0.5 was read at `471b143` and promised to re-check the rows citing the gate branches still unmerged then; all of them were merged at M0 assembly on 14 October 2026. This revision is that re-check, made after the M0 final review (its plan finding R1-01) against the eight gate reports and ADR-0001 to ADR-0016 as merged. Agent-written, not yet reviewed again; human sign-off pending. It approves nothing: every change below is proposed like draft 0.5's, and its findings, evidence and new product-owner questions (PO-37 to PO-44) are in `Docs/Stage0/M0-plan-amendments.md`. No budget was relaxed and no narrowing of release scope was added; the one considered, accepting only `.sylviapack` from Finder above a size, is PO-37's alternative (A20). Draft 0.6's text, Section 24 included, is unchanged.

*Revised on 20 October 2026, after the M0 final review's second round (plan findings R2-02 to R2-07; `Docs/Stage0/integration-log.md` section 12), within the same tags and still pending approval: Section 8.5 and the raw-copy risk row (A20) name the residual exception to I-04 that keeping the raw Finder import leaves for raw audio, and the row says that large transfers are steered to `.sylviapack`, enforced only under PO-37's alternative; Section 23.3 (A52) adds to the security reviewer's scope the residual risks ADR-0015 marks as owner decisions, quick capture on a locked phone (B11) and the 5xx policy (B6) among them; the draft 0.6 entry lists two wordings of main's draft 0.6 the merge did not keep, and the draft 0.5 entry its final review; the A12 cross-reference below is corrected. Not reviewed again.*

*Decided on 20 October 2026 (PO-35, option (b); ADR-0001; `Docs/Stage0/integration-log.md` section 13): the toolchain pin. Draft 0.5's Section 6.3 (A01) recorded Xcode 27.0 (27A266a), awaiting the product owner's confirmation that it was a release; the build Mac's Xcode updated itself to 27.1 (27A9275) on 18 October 2026, and PO-35 was decided for option (b), pinning 27.1 rather than reinstalling 27.0 (ADR-0001 records the decision and its basis). Section 6.3 now records that pin. It is the product owner's decision of one question, as ADR-0001 records the reading of the owner's reply (which named no option), not a proposal; whether 27A9275 is the non-beta release that Section 6.3 asks for awaits a check of Apple's release notes, which the recommendation of option (b) had made its condition and which nobody has made yet (ADR-0001, open items; corrected on 20 October 2026 after the review of the re-pin round, `Docs/Stage0/integration-log.md` section 14). The rest of A01, and every other amendment, stays pending approval.*

*22 October 2026: the product owner approved this draft's amendments and decided its questions, as recommended except PO-13, PO-23, PO-33, PO-39 and D-1, and confirmed the PO-35 pin as their own decision (draft 0.8 above). This entry's title and text record the state before that.*

Corrections of draft 0.5's text, each under its existing tag:

- Section 8.5 (A20): draft 0.5 said the APFS clone of a Finder copy proves it complete, which holds for a bundle only. A raw file has no manifest or end record and cannot be proved complete (G0.3 F15): the limit is stated, keeping the raw import is proposed beside its alternative, and a new risk row covers an incomplete copy staged as it is. Section 8.1 (A20): the merged report's peak footprint is 49.1 MB (draft 0.5 quoted 48.1 MB), and a cancel may not reach the sharing app (G0.3 F17).
- Section 15.4 and the token risk row (A15): the task window bounds the bearer-token copies per job, not in all; a bound across jobs is proposed for the product owner (G0.2 findings 5 and 21, R3-05; ADR-0008, ADR-0009). Section 15.5 (A15): a background relaunch gets limited time for the full-file check (G0.2 finding 21, R3-04).
- Sections 1.1 and 21.1 (A01) and the reading-adapter risk row: rows failed in four gates, not three; G0.1 PDF's row 10c was found after `471b143` (A54 below).
- Section 9.2 and the A12 bullet below, in the draft 0.5 entry (A12): the G0.1 PDF report now also asks for the real-world PDF set before M3. Section 9.2 (A09): /Next, additional actions and outline actions (G0.1 PDF findings 10 and 13).
- Appendix A.1 (A50): the schemas were merged at M0 assembly (ADR-0016), and a composed PDF quotation is the reader's composition of its pieces (G0.1 PDF finding 15).
- Figures the merged reports changed: Section 7.4 (A28) the durability setting's save latency; Section 8.3 (A22) native FLAC remuxed beyond about 25-31 minutes, not 25-30; Section 8.5 (A19) 43-78 seconds over four runs; Section 10.1 and the long-audio risk row (A22) a 10-hour native FLAC resumed in 28-30 s, not about 27 s; Section 10.2 (A24) a stereo source averaged to mono, since an equal-power sum raised stereo speech by 3 dB (G0.4 finding 9).
- Additions under existing tags: Section 8.5 (A21) the manifest size limits (G0.3 F19); Section 17.1 (A29) the retention of recovery copies and one owner per staging subdirectory (G0.5 recovery F11); Section 18.1 (A38) text from outside the app checked before decoding and compared byte for byte, path rules on UTF-8 bytes, proleptic Gregorian dates (G0.3 F16 and F18); Section 20.1 (A44) touch handling tested around the system's thresholds (G0.6 finding 18); Section 4.4.6 (A45) the incomplete-edition warning in the gaps table (G0.4 open questions); Section 23.2 (A48) its introduction counts draft 0.7's rows.

New amendments:

- **A54** (Sections 1.1, 9.2, 21.1, 23.2, Appendix A.1): highlights on PDF text drawn with a rotated text matrix (G0.1 PDF row 10c, failed): a per-line reading direction in the anchor (proposed), what to draw for a slanted line decided with design in M3; the failed-row count and the reading-adapter risk row follow.
- **A55** (Sections 11.1, 23.2): text holding U+0000 refused, or the character removed visibly, before a capture or note is saved, never stored cut off; GRDB upgrades re-check its text binding (G0.5 recovery F12).
- **A56** (Sections 23.2, 23.3): the marmelroy/Zip 2.1.2 advisory (CVE-2023-39135), linked through Readium with no fixed release; the CI guard and its two open routes (ADR-0014 R4-01 and R4-02), closed before the M1 app target is created or any product target links Readium; security accepts the residual risk. *(24 October 2026: answered by an agent's change, review pending: ADR-0014 status. Until 26 October 2026 this note said closed: the third review of the M0 exit preparation, its finding HON-EP-01.)*

**Draft 0.6 - Gloss UX and roadmap revision, written on main.** 15 October 2026. Written on main as its draft 0.4, based on main's content-hub revision (draft 0.4 here), independently of the separately reviewed M0 branch and its own document revisions. Renumbered 0.6 when main was merged into the M0 integration branch, after the draft 0.5 amendments, which it neither approves nor changes. Native iOS/iPadOS V1 and its lightweight Mac companion remain first. This revision does not import the M0 implementation, evidence, proposed amendments or gate approvals. [P3, S25]

- Sections 1.1 and 21.2: assess the separately reviewed native work for reuse as it is integrated; preserve this plan's milestone dependencies, platform proposals and effort estimates.
- Sections 4.1, 9.4, 13.1, 13.4 and 14.5: passage preview during capture/Ask, adaptive sheet/pane discussion, editable Explain/Simplify starters, source-linked follow-ups and retained-evidence previews with optional source navigation. M3's capture path remains independent of AI configuration.
- Sections 20.2 and 21.2: acceptance cases T55-T57 and their M3/M5 exit demonstrations, including accessibility, missing-source and interrupted-request behavior. These are future product checks, not M0 passes.
- Sections 4.4.9 and 24: portable design tokens include web clients; article extraction remains in post-V1 Phase A; the web reader is a separate later workstream with a bounded prototype and unresolved browser storage, provider, hosting and library-exchange decisions. No account, sync or web target is added to V1.
- Appendix B: pin the M0 and Gloss background references and distinguish interaction inspiration from source reuse requiring a suitable license or permission. The companion addendum's sequencing note points to this roadmap; its future capture scope is unchanged.
- Merge into the M0 integration branch: the Section 21.2 M3 and M5 rows combine draft 0.5's proposed device-step dependencies with draft 0.6's deliverables and exit demonstrations, and the M5 row keeps "citation chips" beside the citation evidence preview. Section 20.2 keeps draft 0.5's T54 and adds T55-T57.
- Two wordings of draft 0.6 as written on main that the merge did not keep, for the product owner to confirm or revert (listed on 20 October 2026, M0 final review round 2, plan R1-03 and R2-02; neither changes a decision): (1) main's M5 row replaced "Generated marker and citation chips" with "Generated marker; Explain/Simplify starters, contextual follow-ups and citation evidence preview"; the merged row keeps "citation chips" before main's new deliverables (citation chips remain in Section 4.4.5); (2) main's introduction deleted "This is a greenfield implementation proposal, not an audit of an existing repository" and said that "this documentation revision incorporates its lessons for reuse without importing its implementation, gate evidence or proposed amendments"; the merged introduction keeps the first sentence and, in place of that clause, gives draft 0.5's account of Stage 0 and says that draft 0.6 was written on main independently of the M0 work and changes no M0 gate result or pending amendment. The review's line-by-line comparison with main's text (`git diff b51d19e 4c49b5b`) found no other unrecorded difference. *(22 October 2026: decided as runbook decision D-7 recommended, with the amendments, which the product owner approved as the documents state them, so the merged wordings stand; draft 0.8.)* *(23 October 2026: the product owner confirmed this reading of D-7: both merged wordings are kept.)*
- 19 October 2026, on the M0 integration branch, a record of fact that changes no decision, amendment or gate status: Sections 1.1 and 21.2 and Appendix B [P3] now say that the M0 feasibility work was merged into main on 15 October 2026 (pull request #4) and that the M0 gate is pending approval. The pinned `d8e7d39` references are kept.

**Draft 0.5 - proposed at the M0 gate, pending product-owner approval.** 14 October 2026. Amendments from the Stage 0 results (Section 21.1), written at M0 integration from the eight gate reports and ADR-0001 to ADR-0014 (`m0-integrate` at `471b143`) and revised after two agent review rounds; the item's final agent review read the commit holding the second round's revisions (`694518f`) and returned accept-with-minor (integration log section 7.1, row 12; squash commit `8d34e8c`; the review's own record is not in the repository); agent-written, human sign-off pending. (Until 20 October 2026 this entry said the second round's revisions had not been reviewed again, which was written before that final review: M0 final review round 2, plan R2-03.) Each change carries its tag `[M0-Ann]` in the text; the findings, their evidence and classification, and the product owner's open questions with options and recommended defaults are in `Docs/Stage0/M0-plan-amendments.md`. No budget was relaxed. Every narrowing of release scope is a proposal. Those a failed or narrowed spike forces: the Tailscale route depends on the new decision D16 (G0.2's Tailscale rows failed; A13); Opus in WebM is excluded (A23); long audio files that stay on precise timing get the per-file timing mode and the import remux, or are listed with their limits (G0.4's start/resume rows failed; A22); the EPUB compatibility subset is documented (A03); quick capture stays gated (A26); the `sylvia://` pairing link is not advertised, because another app can intercept it (a G0.2 security finding; A16). Six others, which no failed spike forces, are the product owner's decisions, each stated beside the alternative that keeps the plan's scope, and approving this draft does not by itself approve them: PDFs that forbid copying get no text features (A10); cleartext to a local model server only at an IP literal (A14); bounded Dynamic Type exceptions for bars, titles and possibly the mini-player (A40, A43); system sheet motion under Reduce Motion, if the device shows it acceptable (A42); EPUBs imported only as single files, never as folders (A53); earlier turns of a conversation left out when the provider or model changes (A34). Two narrowings were considered and are not proposed: the cross-resource EPUB quotation earlier drafts provided for is kept (A05), and so is "Open With" from the Files app (A20). The Companion Vision addendum and Section 24 are unchanged. *(22 October 2026: the product owner approved these amendments and decided each narrowing above that no failed spike forces, as recommended; where the owner chose otherwise on other questions, draft 0.8 above says what changed. This entry's title and text record the state before that.)*

- **A01** (front matter, Sections 1, 1.1, 6.3, 21.1, 23.1, 23.2): draft 0.5 status; Stage 0 has run on the host and simulator with every device and human step pending; the toolchain and dependency pins recorded; the failed gate rows named.
- **A02** (Sections 6.3, 8.3, 18.1, 23.1, 23.2): the EPUB safety controls are Sylvia's reader adapter (declared resources only, a parse-and-reserialize sanitizer with a CSP, a content rule list, local files only), because on its own Readium 3.11.0 lets a publication run scripts and reach the network.
- **A03** (Sections 3.1, 8.3, 23.2): the EPUB compatibility subset and the EPUB preflight and sanitizer limits, as proposals; a risk row for real-world EPUBs outside the subset.
- **A04** (Sections 7.5, 9.1, 23.2): the adapter's selection check and navigation settle; the highlight redraw kept as a defense not proven necessary; a reader locator, its resource included, is fallible.
- **A05** (Section 9.1): one gesture cannot select across EPUB resources, so the capture flow offers an action that extends a quotation into the next chapter (proposed; keeping each selection within one resource is the alternative, a narrowing).
- **A06** (Section 9.4): proposed, the reader returns to the text first in view after a settings change.
- **A07** (Section 7.5): Sylvia-extraction offsets are optional in an EPUB anchor.
- **A08** (Section 9.1): publication notes never go through a system HTML importer.
- **A09** (Sections 8.3, 9.2, 18.1): the PDF link delegate and allowlist.
- **A10** (Section 9.2): PDFs that forbid copying get no text features (proposed; a narrowing no failed spike forces).
- **A11** (Sections 7.5, 9.2, 23.2): printed labels only from `/PageLabels`; the extraction version includes the OS build; page-text digests.
- **A12** (Sections 9.2, 19.1): a real-world PDF set before M3 relies on extraction quality, as the G0.1 PDF report asks since M0 assembly (at `471b143` it said before M1; PDF extraction is first built in M3); PDF pages white in every theme.
- **A13** (Sections 5, 15.1, 15.2, 20.2, 21.2, 23.1, 23.2): the Tailscale route needs a scoped ATS exception (new D16, signed at the M0 gate, the route built in M6), or XFER-04 narrows.
- **A14** (Sections 14.3, 23.1, 23.2): ATS does not protect local cleartext; Sylvia's own endpoint rules are enforced and tested; cleartext only to IP literals in local ranges (proposed; a narrowing no failed spike forces).
- **A15** (Sections 6.4, 15.1, 15.4, 15.5, 18.1, 23.2): background transfer behavior and the honest promise; the task window; tokens and bodies in the transfer daemon, with a risk row; the foreground manifest refresh; when the inbox is read; a repair path for a damaged job store (proposals), the sources file and import ledger left open.
- **A16** (Sections 15.2, 23.1, 23.2): a copied code and an optional QR code scanned in Sylvia instead of an advertised custom-scheme link (a narrowing the security finding forces, unless the security reviewer accepts the risk); invitation values (proposals).
- **A17** (Sections 15.3, 16.2, 16.3): the manifest's 503 `preparing`; APFS clones, or full copies with a space check and progress; the signed companion's keychain.
- **A18** (Section 18.1): an unreadable store is never treated as empty; `isProtectedDataAvailable` never decides class C access.
- **A19** (Sections 8.5, 17.3, 23.1): the strict archive layout check before `readium/ZIPFoundation` 3.0.1; the single-file backup on the same rules.
- **A20** (Sections 8.1, 8.3, 8.5, 16.4, 17.1, 17.5, 23.2): intake behavior: extension memory, provider stalls, arrival without "Received", `LSSupportsOpeningDocumentsInPlace` (switched to YES if a phone also loses "Open With"), Markdown types, Finder clone validation, bundle cleanup and the backup exclusion of staging and the handoff inbox.
- **A21** (Sections 8.4, 8.5): the handoff cleanup values and the `.sylviapack` limits (proposals).
- **A22** (Sections 7.2, 8.3, 10.1, 17.1, 19.2, 23.1, 23.2): the per-file timing mode and the import remux, limited to members long enough to miss the budget, with its storage cost (proposals); the start/resume budget kept, its condition made explicit and its simulator failure recorded.
- **A23** (Sections 3.1, 10.1, 23.1): the simulator codec results; Opus in WebM excluded; extra formats only after the device run; chapters by container.
- **A24** (Sections 7.2, 10.2, 19.2): the excerpt format (mono to confirm) and the decoder-reported actual timing with each range's source format.
- **A25** (Sections 10.1, 12, 19.2): checkpoints in book time and at member boundaries; the furthest-position rule.
- **A26** (Sections 3.3, 10.5, 23.1, 23.2): the quick-capture outcome; in-player Capture is the baseline; the App Review risk.
- **A27** (Sections 18.1, 23.1): class C for every persistent file, set and read back (new D17); copies created new with the class; only a device shows protection.
- **A28** (Sections 7.4, 19.2, 23.1, 23.2): the durability setting applied after open and read back (D17); unknown migrations refused; an intent before replacing the library's files; power loss untestable.
- **A29** (Sections 17.1, 17.4, 17.5, 23.2): export leases renewed; the backup's database treated as untrusted code; recovery copies and restore work excluded from device backup (ADR-0012).
- **A30** (Sections 20.2, 21.2): the app-level part of T50 moves to M1 (proposed).
- **A31** (Sections 10.4, 14.1): the Responses API with `store: false`; the generic adapter refuses first-party hosts; the connection test as the conformance check; transcription timestamps as a configured capability (proposals).
- **A32** (Sections 7.2, 14.2, 14.3): keys bound to their origin; Local Network denial detected by a documented check.
- **A33** (Section 14.4, Appendix A.4): outcome `answer` and "Complete" need answer text; refusal and filter stops, with and without text; uncertain server errors, every 5xx but a 503 or 529 from a hosted or local endpoint, ask first (proposed); one record per request and single-flight sends.
- **A34** (Sections 13.1, 13.3, 14.2): no whole book under a spoiler boundary; a selection after the position refused; edition-specific paragraph positions; earlier turns resent only to their own destination, so a new provider or model starts without them (proposed; a narrowing no failed spike forces).
- **A35** (Sections 13.2, 14.5): an 8,192-token default for unknown models, the response caps and the G0.5 spike's upload defaults (proposals).
- **A36** (Section 13.4, Appendix A.2): the exact-quotation rule (proposed); citation IDs local to one pack; the v1 context-pack contract.
- **A37** (Section 10.4, Appendix A.4): a durable transcription queue, confirmation before an uncertain resend and one job per clip; `TranscriptionService` added.
- **A38** (Section 18.1): numbers from untrusted sources parsed strictly and bounded.
- **A39** (Section 22.2): Keychain tests hosted in an app target.
- **A40** (Sections 4.4.1, 4.4.3, 4.4.7, 4.4.8, 4.4.9, 23.1, 23.2, Appendix B): Dynamic Type scaling by the system styles' sizes instead of `UIFontMetrics`; bounded exceptions for bars and titles (proposed; a narrowing no failed spike forces).
- **A41** (Sections 4.4.2, 4.4.4, 4.4.5, 4.4.8, 23.1, Appendix A.5): cover titles in Paper; no muted text on tints; the dark-tint conflict for design; the Increase Contrast step and overrides; hairline 1pt, the Night shadow and the motion curves (proposals).
- **A42** (Sections 4.4.4, 20.2): system sheet motion accepted if the device shows its Reduce Motion behavior acceptable, which narrows T51's Reduce Motion clause, and content-sized sheets (proposals).
- **A43** (Sections 4.4.7, 4.4.8): pressed, disabled and busy button states; the large content viewer's lift activation and device check; the mini-player's inset, and its size at accessibility sizes (stopping it at xxxLarge would be a third Dynamic Type exception); the Pine primary distinct by its fill.
- **A44** (Sections 4.4.9, 20.1, 22.2, 22.3): a layout audit beside the snapshots, reviewed references, component contrast pairs and frame-based reachability.
- **A45** (Sections 4.4.6, 20.2, 23.1): the vocabulary gaps table, covering every phrase the plan quotes for a state (wording pending design review); T54 checks each gap once it is in the vocabulary.
- **A46** (introduction, Sections 19.1, 19.2, 21.1, 21.2, 23.2, Appendix C): no device evidence yet and the reference devices unavailable; each milestone, M1 included, starts after its gates' device steps on the iPhone available now (M1: G0.5 recovery steps 1-4; M2: G0.3 and G0.6), and exits after their repeats on the baseline iPhone and an iPad (proposed).
- **A47** (Section 23.1): D02, D03, D05, D07, D08, D10 and D15 updated; D16 and D17 added.
- **A48** (Section 23.2): five rows updated and ten added.
- **A49** (Section 21.4): the ranges unchanged, with the inputs to the team's re-estimate.
- **A50** (Appendix A.1): the proposed capture-kind strings and the anchor fields Stage 0 found.
- **A51** (Section 18.2, Appendix C): the required-reason API categories; the license acknowledgements and the Literata license.
- **A52** (Section 23.3): the security sign-off scope.
- **A53** (Section 8.1): EPUBs offered as folders are refused; proposed, EPUBs are imported only as single files in V1 (a narrowing no failed spike forces; the alternatives are accepting folders on the phone or having the Mac companion pack them). Added in the second review round, when this change was split out of A20.

**Draft 0.4 - 7 October 2026.** Roadmap-only change at the product owner's request. No v1 scope, security, data-model or transfer-protocol decision was changed. (Written on `main` as draft 0.3 while Stage 0 recorded its own draft 0.3; renumbered 0.4 when the two were merged at M0 integration, content unchanged.)

- Section 24: the RSS/newsletter paragraph is replaced by the unified content hub roadmap (Phases A-C: saved articles with listen links, subscriptions including public Substack, authenticated sources), shared rules and requirement stubs ART-01/02 and FEED-01 to FEED-04, SRC-01.
- Section 3.3 and decision D14: wording updated to point at that roadmap.

**Draft 0.3 - 6 October 2026.** Product-owner decisions taken before Stage 0, and consistency fixes inside Section 4.4. The fixes are flagged for design review at the M0 gate; none changes a token value.

- Front matter and Section 1.1: status moved to draft 0.3; the product owner's approval of D02-D15 as proposed, the D01 amendment, Inbox layout B and opaque chrome recorded as confirmed. Approvals that also name a technical, security, QA or design owner remain subject to Stage 0 evidence.
- D01: platform floor amended from iOS/iPadOS 18+ and macOS 14+ to iOS/iPadOS 26+ and macOS 26+. The pinned toolchain cannot test iOS 18 and has iOS 26.5 and 27.0 simulator runtimes; iPhone 12-class hardware remains the proposed baseline device (Section 19.1). *(22 October 2026: the product owner has since chosen the iPhone 11 family as the baseline, device A an iPhone 11 Pro; draft 0.8.)*
- Section 4.1: Inbox rows use layout B (compact), with the Resolve detail view and the accessibility-size wrapping rule. Board *Inbox rows, option A* is retained as a reference only.
- Sections 4.4.2, 4.4.7 and 4.4.8: the tab bar, navigation bars and mini-player are Sylvia's own opaque components, not the system's Liquid Glass bars. This resolves a conflict between the "no glassmorphism" rule and a Reduce Transparency rule that assumed a translucent tab bar. The tab bar row now also requires system-equivalent accessibility and a regular-width iPad sidebar.
- Section 4.4.4: the radius scale listed 10, 14, 22 and full with "nothing else", while the component specifications use 12 for buttons and 8 for quote blocks and the boards draw both. The scale now names 8 (inset blocks, small cover thumbnails), 10 (small controls), 12 (buttons), 14, 22 and full.
- Section 4.4.5 and D15: the heading said four capture kinds and D15 said six markers, while the table defines Word as a fifth capture kind. The set is now stated as seven markers; Word uses the `quote` colors. The Note glyph is `pencil.tip`. The Generated prompt glyph and the bracket capture glyph have no SF Symbol and ship as custom `sylvia.*` symbols (the A.5 sketch named a nonexistent `chevron.right.underscore`).
- Section 4.4.6: added "Waiting for {source}" and "Needs review" (both used by the Section 8.2 state machine or the Inbox board but missing from the vocabulary), a full mapping from Section 8.2 states to phrases, a Delivery receipts row for the Mac companion's three receipts (Section 16.2), and "Relevant passages retrieved" as the post-retrieval disclosure next to the "Relevant passages from this work" chip (reconciling Section 13.1).
- Section 17.2: the fourth removal action uses its vocabulary label, "Delete record and thoughts".
- Section 22.1: `Spikes/`, `Scripts/` and `Docs/Stage0/` added to the repository layout.
- Appendix A.5: Note glyph `pencil.tip`, Generated glyph `sylvia.prompt`, Word marker added.

No scope, security, data-model or transfer-protocol decision from draft 0.2 was changed other than D01.

**Draft 0.2 - 6 October 2026.** Folded the Marginalia design language into the plan. Changes from draft 0.1:

- Front matter: status, revision date and [P2] source added.
- Section 1.1: Marginalia direction recorded as confirmed by the product owner; token values listed as proposed.
- Section 2.2: closing paragraph tying the design language to invariants I-03 through I-06.
- Section 4.1: references to the mini-player capture control, typographic covers, marker treatment and the status vocabulary.
- Section 4.4 (new): principles, color tokens, typography, shape and motion, marker set, status vocabulary, component inventory, grayscale and accessibility conformance, implementation mapping.
- Section 5: requirement UX-02 added.
- Section 6.2: `SylviaDesign` package added; SylviaUI/MacUI forbidden dependencies extended.
- Sections 8.2, 9.1, 10.2, 10.4, 11.1, 11.3, 12, 13.1, 13.4, 14.2, 14.4, 15.2, 15.5, 16.1, 16.2, 17.2, 18.3, 19.2: wording aligned with the vocabulary and cross-referenced to Section 4.4.
- Section 20.1: design conformance test layer; grayscale device in human evaluation. Section 20.2: T51 strengthened; T53 and T54 added. Section 20.4: one observation added.
- Section 21.1: gate G0.6 added. Section 21.2: `SylviaDesign` v0.1 in M0 and conformance demonstrations per milestone. Section 21.3: ownership of tokens and vocabulary. Section 21.4: design package row added; total 46-72. Section 21.5: marker set and vocabulary protected from cuts.
- Section 22: `Packages/Design/`, `Contracts/design/`, `Docs/Design/`; CI contrast and literal checks; definition of done and agent rules extended; design-language ADR required.
- Section 23: decision D15; two risks added; design sign-off scope extended.
- Section 24: marker rule for new work kinds; token export for broader platforms.
- Appendix A.5 (new): design token export sketch. Appendix B: [P2], [S23], [S24]. Appendix C: grayscale and vocabulary passes.
- Later the same day: [P2] and the Section 4.4 references now point at the checked-in boards in `Docs/Design/` (rendered images plus source) rather than at the private authoring canvas, so the plan can be read from the repository alone.

No scope, security, data-model or transfer-protocol decision from draft 0.1 was changed.
