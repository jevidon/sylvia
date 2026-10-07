# Sylvia
## V1 iOS implementation plan
### Your library of thought.

**Status:** Team-review draft 0.3 - not yet approved for execution  
**Prepared:** 5 October 2026 · **Revised:** 7 October 2026 (unified content hub added to the roadmap; see Appendix D)  
**Product owner:** Justin Evidon  
**Delivery boundary:** Native iPhone/iPad application, iOS share extension, lightweight macOS transfer companion, portable data and transfer contracts. No mandatory service.  
**Source of truth:** Agreed product discussion, *Sylvia - Product Brief*, and the *Sylvia Concept Designs* boards in `Docs/Design/` for visual language. Technical recommendations below are proposals unless explicitly identified as confirmed. [P1, P2]

> **The release must prove one complete loop:** get a book onto the device reliably; read or listen offline; capture a passage and your thinking; ask a source-aware question when a model is reachable; then find that knowledge after the original media has been removed.

This is a greenfield implementation proposal, not an audit of an existing repository. No app code, performance results, platform spikes or compatibility tests have been executed for this document. Requirements, interfaces, recovery rules and acceptance criteria are specified for review; the initial feasibility stage must validate the risky platform assumptions before feature implementation begins.

# 1. Executive recommendation

Build a **local-first native application**, not a client for a future server. Its private database owns the user's catalog, consumption ledger, annotations and saved AI interactions. Imported media is replaceable storage attached to that record. The Mac companion is a source and transfer utility, not the owner of the user's knowledge.

Use Swift/SwiftUI for the application, a Readium adapter for EPUB, PDFKit for text-based PDF interaction, AVFoundation for local audio, and SQLite through GRDB for durable structured storage. Keep product entities and serialized contracts independent of those frameworks. This makes later Android development practical without pretending that SwiftUI screens or AVFoundation implementations are portable. Readium, GRDB and SQLite provide the underlying reading/data capabilities; their exact releases must be pinned after the feasibility stage. [S1-S4]

**The proposed release includes** the permanent ledger, EPUB/PDF reading, common audiobook playback, text highlights and notes, durable short audio captures, user-configured AI, local search, direct imports, a Mac source browser, resumable app-controlled LAN transfers, Finder-based wired imports, and knowledge backup/restore. A connected model is optional for using every non-AI feature.

**The proposed release does not include** Docker hosting, automatic cross-device state synchronization, RSS/Atom subscriptions, newsletter email ingestion, Calibre database integration, physical-page OCR, Spotify/Audible capture, precise audiobook/EPUB alignment, automatic full-book transcription, on-device language-model inference, or autonomous agent actions. The underlying data model leaves room for these, but no placeholder feature should imply that they already work.

The important decisions requiring explicit team approval are collected in Section 23. In particular, approve the proposed minimum OS versions, audio transcription scope, lock-screen clipping boundary, source-content retention defaults and transfer security design. These were not all settled in the discovery conversation.

## 1.1 What is confirmed versus proposed

**Confirmed:** Sylvia; native iOS first; eventual broader platform support; standalone use without an account/server; a lightweight Mac companion; direct, LAN and wired import; one-time pairing; 5,000+ titles; Work -> Edition -> Asset; English and DRM-free content first; passage-focused annotation; EPUB/audiobook association; retention of learning records after media removal; optional configurable AI and optional Hermes; Docker deferred. [P1] **Also confirmed (6 October 2026):** the *Marginalia* design language direction described in Section 4.4, chosen by the product owner after reviewing four alternatives; its exact token values remain proposals until checked on devices in Stage 0. [P2]

**Proposed for this review:** iOS/iPadOS 18+ and macOS 14+; iPhone-led design with a functional adaptive iPad layout; GRDB and Readium; the precise import/transfer protocol; a five-star rating with half-star steps; no automatic media eviction; short-clip transcription through an optional speech endpoint; explicit knowledge export and restore in v1; no cloud/state sync; minimal status-based organization rather than a fixed taxonomy; the Marginalia token values, type roles and component inventory in Section 4.4.

**Still open by design:** user-facing categorization, commercial model, production distribution and pricing. The engineering plan must not silently resolve these as subscriptions, a complex tagging system, or a hosted account service.

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
| Reading | Reflowable EPUB, text-based PDF, basic UTF-8 TXT/Markdown | No advanced PDF editing, scanned-PDF OCR or scripted EPUB support |
| Listening | M4B/M4A with tested supported codecs, MP3, ordered multi-file books | No streaming-service imports, format conversion farm or format-by-extension guarantees |
| Capture | Text highlights, comments, bookmarks, vocabulary, short local audio excerpts | No automatic exact audio/text alignment; no silent whole-book transcription |
| AI | OpenAI, Anthropic and generic compatible endpoints; saved source-linked conversations | No assumption that consumer subscriptions include API access; no autonomous tools |
| Transfer | Files, share, AirDrop handoff, direct file URL, Mac LAN pull, wired Finder route | No custom USB driver; no phone-as-always-on-upload-server |
| Search | Catalog and saved knowledge globally; local extracted text per work | No mandatory embeddings or server-based semantic search |
| Portability | Human-readable export and versioned backup/restore | No live multi-device conflict resolution in v1 |
| External consumption | Manually created physical/external records, manual progress and quotes | Camera capture and external playback observation deferred |

Common formats accepted during discovery remain the target direction. **The release-supported codec matrix is a proposed narrowing, not a claim that every AAC, FLAC or Opus file is supported.** Stage 0 must test representative files, including seek, chapters and clip extraction; only passing combinations go on the release support list. Additional natively supported formats may be admitted without conversion only after the same tests pass.

## 3.2 Default feature flags

Enabled for release: core reader/player, source-free records, capture, export, provider setup, direct import, LAN companion and Finder guide. AI remains inactive until configured. Clip transcription remains inactive until a speech endpoint is configured and authorized.

Disabled/absent: full transcription, external-service capture, OCR, feeds, email, cross-device sync, rich taxonomy, automatic eviction, cloud relay and remote agent actions. Use flags for safe development and rollback, not to ship misleading unfinished menus.

## 3.3 Specific scope reconciliations

The earlier ideal story included clipping from the lock screen. V1 must ship standard lock-screen/headphone playback controls; a dedicated quick-capture surface is a **separate feasibility gate**, not an assumed Media Player capability. Proposed baseline is one-tap capture inside the player and an approved shortcut/control only if its execution and save semantics pass Stage 0. The team must approve this narrowing before execution. [S8-S9]

The earlier browser-uploader concept is not required alongside the native Mac companion. Choose Mac-hosted pull as the supported v1 network path, avoiding two independent transfer implementations. A browser uploader can be added later if demand justifies it.

RSS/newsletter support - and the wider goal of one home for articles, feeds and Substack content, including their listen links - is retained in the phased roadmap (Section 24) and model extension points, not silently added to this release. An arbitrary webpage URL is not the same as a downloadable EPUB/PDF/audio URL.

# 4. User experience and end-to-end flows

## 4.1 Navigation

Use three primary areas: **Library**, **Thoughts**, and **Inbox**. Global search searches catalog and retained knowledge with clear result types. Settings contains AI connections, trusted sources, storage, backup/export and diagnostics. A mini-player persists above navigation while audio is active and carries a capture control, so a moment can be kept from any screen (Section 4.4.7).

**Library:** recently active works, status filters, available-on-device filter and list/grid toggle. A work detail screen shows editions, available assets, current position, history, rating, recommendation events and associated knowledge. Avoid a shelf full of duplicate entries just because an EPUB and audiobook are both present. Works without cover art use the typographic cover fallback (Section 4.4.7), so a record with no file never looks broken.

**Thoughts:** quotations, comments, audio captures, saved vocabulary and saved AI answers. Default ordering is recent activity, with per-work filtering and search. AI answers are not made equivalent to the user's own notes; each capture kind uses its marker treatment from Section 4.4.5. No forced topic taxonomy; categories remain a future product decision.

**Inbox:** pending local imports, items available from a paired Mac, duplicates needing review and failed jobs. Transfer states use the fixed vocabulary of Section 4.4.6: queued, receiving, verifying, preparing, ready, needs attention. Do not make users inspect a developer log to finish an import.

**Reader/player:** one consistent capture sheet with source preview, quote or audio range, comment, lookup, Ask AI and save status. The interaction must be usable one-handed on iPhone and adapt to a side pane on iPad without requiring a separate iPad product.

## 4.2 Onboarding

Start with "Import a book", "Connect a Mac" and "Add a record". Offer a bundled, licensed short sample for trying capture without networking. Explain that AI is optional; do not start with API keys. Ask local-network/camera access only in the pairing workflow that needs it. Explain what remains on the device, and expose backup setup after the first meaningful saved item.

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
| 5 | Reachable with one thumb | Primary actions in the lower half of the screen. Targets 44pt or larger. Anything draggable also has a numeric control. Dynamic Type everywhere, including the reader. | UX-01, Section 18.3 |

### 4.4.2 Color tokens

Two accents of similar lightness carry the brand: **Pine** for actions and the user's own notes, **Ochre** for highlights and exact quotations. A separate, muted marker set names the other capture kinds and statuses. Every text color must meet 4.5:1 against its ground (3:1 at 24pt and above) in both appearances; the values below were checked at authoring time and must be re-verified in the asset catalog during M0.

**Ground and ink**

| Token | Light (Paper) | Dark (Night) | Use |
| --- | --- | --- | --- |
| `ground` | #F4F2ED | #161512 | Screen background |
| `surface` | #FBFAF7 | #1E1C19 | Cards, bars, sheets |
| `ink` | #1C1B18 | #ECE7DD | Primary text, icons |
| `muted` | #6B6760 | #A8A298 | Captions, metadata, inactive tabs |
| `hairline` | ink at 12% | ink at 14% | 1px rules and borders; raised to 24% under Increase Contrast |
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
| `generated` | #6B4E8E | #B49BD6 | #E7DFF0 | #2E2838 | Prompt glyph; dashed 1px frame; the word "Generated"; citation chips |
| `attention` | #A63D2F | #E0837A | #F3DCD7 | #3A2522 | Triangle glyph; always paired with a reason and a next step |
| `pending` | #6B6760 | #A8A298 | #ECE9E2 | #2A2824 | Dot glyph; quiet by design |

Dark tints marked "derived" are the marker text color at approximately 14% over Night and are to be set in the asset catalog, not hard-coded. Tint fills carry no text of their own except the marker's own color; body text on a tint remains `ink`.

**Rules**

- One Pine primary action per screen. Destructive actions use `attention` as a hairline button and never sit beside a primary.
- Color is never the only carrier of meaning. Every marker and status also has a glyph and a label (4.4.5, 4.4.6). This is verified by T53.
- Covers without artwork use five muted fields assigned by a stable hash of the work title: #2F5D50, #5A6B4A, #7A4B3A, #3F5A78, #4A4A58, with `ground` as the title color. Real cover art from the file replaces them when present.
- No gradients, no glassmorphism, no colored shadows. Shadow is a single value (4.4.4) and only on the two floating objects.

### 4.4.3 Typography

Three faces, each with one job.

| Face | Role | License and source |
| --- | --- | --- |
| **Literata** (variable; optical size axis) | Everything that belongs to a book: screen and work titles, headings, quotations, and the default reading face | SIL Open Font License; bundled with the app [S23] |
| **System face** (SF Pro on Apple platforms) | Everything that belongs to the interface: labels, buttons, the user's notes, settings, status text | Platform; Dynamic Type for free |
| **System monospace** (SF Mono) | Values a person compares character by character: fingerprints, digests, timecodes, byte counts, part numbers; tabular figures | Platform |

**Type roles.** Sizes are at the default Dynamic Type setting; every role scales with the user's text size. Literata roles scale through `UIFontMetrics` against the mapped text style so they track system roles exactly. [S24]

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
- **Radii:** 10 for controls, 14 for cards and covers, 22 for sheets, full for pills and chips. Nothing else.
- **Hairline:** 1px at the `hairline` token. Rules separate; cards do not nest in cards.
- **Elevation:** one shadow, 0 8 24 at 10% ink, used only on sheets and the mini-player. Nothing else casts a shadow.
- **Motion:** 200ms ease-out for sheets; 120ms for a highlight appearing; progress rules animate; nothing else animates while reading. No bounces, no parallax. All motion is removed under Reduce Motion except opacity changes.
- **Sheets:** 22pt top radius, grabber, title in the Heading role, primary action at the bottom. A sheet never dismisses while it holds unsaved text (Section 11.1).

### 4.4.5 Marker set: the four capture kinds and two statuses

The marker is a small row at the top of any capture: glyph, then an uppercase Micro label, then the source label, in the marker's color. Icons are SF Symbols on device; the boards show 1.75pt stroke equivalents. [P2]

| Kind | Glyph | Label | Body treatment | Frame | Notes |
| --- | --- | --- | --- | --- | --- |
| Quote | Opening quotation mark, in Literata | QUOTE · source label | Exact text in Literata, Reading or Body size, on `quote` tint, radius 8 | none | Immutable captured wording (Section 11.1). A user's own note under it is in the system face, prefixed "Your note". |
| Note | Pen nib | NOTE · source label | User's words in the system face | none | No tint, ever: the user's own words need no box. |
| Audio | Waveform | AUDIO · source · duration | A tinted block containing a round play control and a waveform; "No transcript" caption until one exists | none | Never rendered as text. Preview playback does not move the main position (Section 10.3). |
| Generated | Prompt glyph (chevron and underscore) | GENERATED · provider · model | Question in Body 600, answer in Body; citation chips inline | 1px dashed in the `generated` color | No sparkle iconography. Unresolved citations render as struck-through grey chips with an explanation (Section 13.4). |
| Word | Open book | WORD · source | Headword in Literata 600, then the source sentence and the user's note | none | Shares the `quote` color family. |
| Attention | Triangle | NEEDS ATTENTION | Reason in Body; one or two actions | tinted row | Never shown without a reason and a next step. |
| Pending | Dot | QUEUED / WAITING | Caption | none | Quiet by design. |

Two markers never share a row without their labels. The Thoughts filter chips reuse the labels verbatim: All, Quotes, Notes, Audio, Generated, Words.

### 4.4.6 Status vocabulary

Status language is a component. Each moment has a fixed set of phrases tied to a state machine in this plan, and a list of phrases the interface never uses. A phrase changes only when the underlying state changes. All strings live in the design package (4.4.9) under stable keys and are the only strings permitted for these states (T54).

| Moment | State machine | We say | We never say |
| --- | --- | --- | --- |
| Saving a thought | Section 11.1 capture transaction | "Saving…" → "Saved" (with time, after the durable commit) · on failure "Not saved · your text is still here" | Done · Success · a dismissed sheet with nothing written |
| Import and transfer | Section 8.2; Section 15.5 | "Queued" · "Receiving" (with verified-of-total bytes) · "Verifying" · "Preparing" · "Ready" · "Ready · indexing continues" · "Needs attention" (with reason) | Complete before Ready · Error · Downloading for a Mac transfer that is verified by parts |
| Capturing audio | Section 10.2 | "Moment saved · preserving audio" → "Audio excerpt saved" · on failure "Excerpt not preserved · Retry" | Clip saved before export · any transcript text that was not transcribed |
| Asking a model | Section 14.4 | "Draft · not sent" · "Sending to {host}" · "Generated" · "Complete" · "Interrupted · partial answer" | Thinking… · The AI read your book · Free with your subscription |
| Context scope | Section 13.1 | "Selected passage" · "Passage and nearby text" · "Relevant passages from this work" · "Selected thoughts" | Whole book (unless it truly fits and was chosen) · Understands your library |
| Where a file is | Sections 7.1, 12 | "On this device" · "Not on this device · from {source}" · "Record only" | Deleted · Missing · Broken |
| Search coverage | Section 11.3 | "Saved thoughts only" · "Book text indexed" · "Indexing {n} of {m} chapters" · "Text unavailable" | Semantic search · Searched everything |
| Removing things | Section 17.2 | "Remove download" · "Manage retained text" · "Remove excerpt audio" · "Delete record and thoughts" (four separate actions) | Delete alone · a trash icon on a download |
| Endpoint disclosure | Section 14.2 | "{host} · hosted" / "{host} · local" / "{host} · user-managed" with the model identifier | Secure · Private (as unqualified claims) |

Microcopy conventions: sentence case; no exclamation marks; durations as "20h 58m left"; positions as chapter and percent, never a page number unless the publication supplies a real page mapping (Section 7.5); times in the Monospace face.

### 4.4.7 Component inventory

The small set every screen is assembled from. Each is a SwiftUI view in the design package (4.4.9) with light, dark and grayscale snapshot tests.

| Component | Specification |
| --- | --- |
| Buttons | Primary: Pine fill, `pine.on` text, 50pt, radius 12, one per screen. Secondary: hairline border, ink text. Quiet: Pine text, no border, 44pt minimum. Destructive: `attention` text and border; never adjacent to a primary. |
| Status pills | 22-26pt tall, radius full, Micro or Caption label, always with a glyph: dot (queued/receiving/verifying/preparing), check (ready), triangle (needs attention). Fill is the state's tint. |
| Availability badges | Hairline pill: "On this device". Dashed hairline pill in `muted`: "Not on this device · from {source}", "Record only". |
| Capture cards | Surface, hairline border, radius 14, 12-14pt padding; marker row, body per 4.4.5, optional "Your note" line, timestamp in Monospace. Generated cards use the dashed frame. |
| Rating | Five stars in `ochre`, half-star steps, stored as integer 1-10 (Section 12). Clearing is a separate action, not zero. Filled versus outline must read in grayscale. |
| Progress rule | 2-3pt track at `hairline`, Pine fill; caption shows chapter or part and percent, with time remaining in Monospace. |
| Tab bar | Three items: Library, Thoughts, Inbox. Active in Pine, inactive in `muted`. Search and Settings live in the navigation bar. Inbox shows an `attention` dot when an item needs the user. |
| Mini-player | Floats 12pt above the tab bar; surface, radius 14, the one shadow; cover, title, caption, a capture control (bracket glyph, "Capture the last 30 seconds") and play/pause. |
| Capture sheet | Section 4.1 reader/player sheet: marker row, quote block or audio range, "Your note" field, Look up and Ask actions, primary button whose label is the save state. |
| Selection menu | Ink pill over the selection: Highlight (with Ochre quotation glyph), Note, Look Up, Ask. |
| Typographic cover | Literata title on one of the five cover fields (4.4.2), author in small caption; 2:3 ratio in lists, square in the player. |
| Reader chrome | Minimal: back, book title in Micro, "Aa", bookmark, search. Footer: progress rule with chapter and percent. No page numbers unless mapped. |
| Impact report | Used before removal (Section 17.2): check-marked lines for what is freed and what is kept, an `attention` row for anything pending, then the safe choice as the primary button. |

### 4.4.8 Grayscale and accessibility conformance

Marginalia must hold on devices that show no color: an iPhone with Color Filters set to grayscale, and reflective grayscale tablets. `Docs/Design/` includes the six core iPhone screens and the iPad reader rendered through a luminance grayscale filter as the reference for this check. [P2] The intended results, verified by T53:

- Quote and Audio tints collapse to nearly the same light grey; the glyph, the label and the content form (serif text versus a waveform with a play control) carry the difference.
- Receiving, Ready and Needs attention pills become similar greys; the dot, check and triangle do the work.
- The Pine primary button becomes dark grey and stays distinct from ink text and from hairline secondary buttons.
- The reader highlight keeps its underline; the selection keeps its tint; the margin dot still marks a saved thought.
- Rating stars lose Ochre, but filled versus outline still reads.
- Generated keeps its dashed frame and label; citation chips remain legible as chips.

Further accessibility rules, extending Section 18.3: all roles scale through Dynamic Type up to the largest accessibility size without clipped labels in the capture sheet, player, Inbox and Thoughts; `hairline` rises to 24% and tints darken one step under Increase Contrast; Reduce Transparency removes the tab bar's translucency; Bold Text is honored by all roles; every icon-only control has a label; highlight colors are never the only way to distinguish capture types.

### 4.4.9 Implementation mapping

- **Package.** A `SylviaDesign` Swift package (Section 6.2) owns color tokens (asset catalog with light and dark variants, exposed as a typed enum), type roles (Literata registration, `UIFontMetrics` scaling, role enum), the marker enum and its presentation mapping from the domain's capture kinds, the status vocabulary strings under stable localization keys, and the SwiftUI component library in 4.4.7. The Mac companion consumes the same package; AppKit-hosted SwiftUI uses the same tokens with macOS control sizing.
- **Single source.** No view declares a literal color, font size or state string. Lint rejects hex literals, `Font.system(size:)` calls and status phrases outside the package in UI targets.
- **Portable tokens.** Tokens, type roles, marker definitions and the status vocabulary are also exported as versioned JSON under `Contracts/design/` alongside the schemas, so a later Android client implements the same system from the same file rather than from screenshots (Section 24).
- **Reference artifact.** The *Sylvia Concept Designs* boards are checked into `Docs/Design/` at each revision as rendered PNGs (`images/`) and board source (`canvas/`), with a README that maps each board to its plan section and a script that re-renders them. [P2] They are a reference, not a specification; this section is. The authoring canvas they come from is the product owner's private working copy; nothing in this plan requires access to it.
- **Change control.** Token, role, marker or vocabulary changes require design review, a fixture update and a snapshot re-baseline. A screen may not introduce a new status phrase; it requests one through the vocabulary.
- **Tests.** Snapshot tests for every component in light, dark, grayscale and Dynamic Type at the default and largest accessibility sizes (T51, T53); a vocabulary conformance test that walks every state machine's user-visible string (T54); a contrast check over every text/ground pair in the token file in CI.

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
| XFER-04 | Manual-address/Tailscale-compatible connectivity | P0 | Section 15; T43 |
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

Swift 6 concurrency with strict checking; Swift Package Manager; SwiftUI with UIKit representables where required; GRDB over SQLite; immutable typed command results; injectable clocks, file stores and clients. Select the current supported non-beta Xcode at kickoff and record the exact version; do not build against a moving SDK or dependency branch.

Readium supplies EPUB parsing/navigation through a narrow adapter. PDFKit remains the PDF implementation. AVPlayer/AVQueuePlayer plus Media Player handle local audio and supported system controls. SQLite FTS5 provides lexical search; semantic retrieval is a later interchangeable strategy. These choices are recommendations grounded in the available platforms, not benchmark results. [S1-S4, S8-S11]

Use one serialized database writer and bounded background workers. UI state is main-actor isolated. File hashing, EPUB extraction, audio preparation and indexing must not block the main actor. Cancellation must leave resumable checkpoints or a clearly failed operation; no unbounded detached tasks.

## 6.4 Job scheduling

Persist jobs before scheduling work. Classify them as user-blocking, user-requested background-capable, or deferrable. Prioritize capture commits and playback over indexing/transcription. Permit one heavy local processing job and two network transfers by default; tune with measurements.

Background URLSession is used for eligible downloads; BGTaskScheduler is opportunistic housekeeping, not a guarantee of completion. Reconcile persisted jobs with OS tasks on every launch. A force-quit/reboot path must safely recover on the next launch even where the OS does not continue or relaunch work. [S5]

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
| EditionAsset | Edition ID, Asset ID, role, sequence, timeline revision; unique ordered membership |
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
| RetainedExcerpt | Capture, local media blob, original audio ranges, clip-local offsets, export state and duration |
| Conversation / Message | Work/capture association, role, content, state, provider/model snapshot, request ID, timestamps |
| ContextPack / ContextEvidence | Immutable request scope, selected evidence snapshots, anchors, text hashes, truncation and retrieval metadata |
| TextDocument / TextChunk | Asset/extraction version, ordered resource/page blocks, provenance/quality, text and location mappings |
| Job / TransferPart | Job type/state, idempotency key, attempts, errors; part offsets, size, digest and verified status |
| ProviderConfig / TrustedDevice | Endpoint/model/capabilities and privacy policy; Keychain references, pairing status and revocation metadata |
| ChangeJournal / ExportRecord | Local mutation sequence, entity/revision and operation; export schema/time/counts/digests |

Use normalized relationships for identity and knowledge. JSON is appropriate for versioned locator payloads, context manifests and provider capabilities, not for opaque blobs replacing the entire library schema. Use 64-bit sizes and timestamps; durations/positions serialize as integer milliseconds, not floating-point percentages alone.

## 7.3 Identity and mutation rules

Generate UUIDs locally. Asset digests deduplicate bytes; they do not decide whether two works are the same intellectual work. Same-file reimport offers "Already imported" or restores local availability. Fuzzy title/author matches prompt the user to attach as an edition or create a separate work; no destructive automatic work merges in v1.

Support a reversible "Move this edition to another work" operation. Preserve IDs and anchors; record provenance. A work cannot be deleted accidentally through source cleanup. Bibliographic identifiers are hints, not unconditional unique keys across all kinds of editions.

Use foreign keys and explicit transactions. Cascade only genuinely subordinate processing data; media removal must never cascade into captures or ledger events. Revision-checked note edits prevent a stale editor window overwriting a later local edit. Store user-effective dates separately from UTC event timestamps and preserve date precision for historical completion/recommendation entries.

## 7.4 Durable commits and migrations

Store the main database under private Application Support, not Finder-exposed Documents. Enable foreign keys, WAL and a durability configuration tested for acknowledged saves. Use GRDB's supported transaction/migration/backup facilities; do not copy a live SQLite file while ignoring its WAL. [S2]

Each schema migration has an ID, fixture upgrades, integrity checks and a rollback/recovery plan. Before a destructive migration, create a consistent local recovery snapshot; if storage is insufficient, stop rather than deleting user data to proceed. A failed migration opens a recovery screen, not an empty replacement library.

ChangeJournal is a transactional local record of semantic mutations with a device-local sequence. It assists diagnostics and later sync development; it is **not** a complete distributed synchronization protocol. Do not implement speculative remote conflict resolution, CRDTs or full event sourcing for this release.

## 7.5 Canonical anchor rules

An anchor includes schema version, Work/Edition/Asset IDs as applicable, asset digest, kind and source locator. EPUB uses the Readium locator plus exact selected text and surrounding text. PDF uses physical page index, printed label when present, text selection mapping and normalized rectangles with rotation metadata. Audio uses asset-local milliseconds; cross-file selections use multiple ordered ranges. [S3, S10]

Store the original locator returned by the reader as opaque adapter data and a small portable envelope. Cross-platform text offsets must state their unit; use Unicode scalar offsets for Sylvia-extracted text, and explicitly convert native UTF-16 ranges at the adapter boundary. Never call a rendered EPUB "page 183" unless the publication actually provides that stable page mapping.

Reanchoring tries original locator, then exact text plus context within the same asset/version. Ambiguous matches show "Location needs review". Cross-edition relocation always requires confirmation. Loss of a precise location must not delete the quote or silently link it to the wrong passage.

# 8. Import pipeline and supported files

## 8.1 One pipeline, several entry points

Every intake route creates the same ImportJob. Route-specific code is responsible only for obtaining authorized bytes or a durable download request. The common pipeline copies/stages, sniffs type, verifies available checksums, inspects protection/structure, extracts minimal metadata, resolves grouping, commits assets and schedules nonblocking text indexing.

**Files/document picker:** use security-scoped access and file coordination while copying into private staging. Handle iCloud/provider items that must first download, revoked access, insufficient space and the source disappearing. Do not store a transient provider URL as the sole future access path.

**Share extension:** accept supported file representations and direct file URLs. Copy file representations to a unique App Group staging directory before reporting them received; write a small manifest atomically last. Do not assume provider-temporary URLs survive after the extension exits. For large files, stream/copy rather than reading into memory. If the extension cannot finish safely, show an actionable Files/LAN/wired alternative and do not claim receipt. URL download handoffs may use an extension-specific background session and the shared container. [S6]

**AirDrop/open-in:** accept the file through system document handling and feed it into the same staged importer. Sylvia does not implement or control AirDrop itself. [S7]

**URL import:** support HTTPS links whose response is a supported file, subject to content sniffing and size limits. Use redirects cautiously; never forward an Authorization header to a different origin. A URL returning HTML produces "This is a webpage, not a supported file" with the option to keep a manual reference, not a broken EPUB entry. Authenticated browser sessions, paywall extraction, streaming URLs and RSS discovery are not v1 features.

**Mac LAN:** consume a pinned source manifest and verified parts using Section 15. **Wired Finder:** use the supported file-sharing surface; explain that the user waits for Finder's copy to finish, then imports in Sylvia. The app does not pretend to control Finder's transport progress or resume. [S7]

## 8.2 State machine

Use persisted states: `created -> acquiring -> staged -> validating -> identifying -> needs_review | committing -> ready`. Failure branches are `waiting_for_source`, `waiting_for_space`, `unsupported`, `failed_retryable`, `failed_final` and `cancelled`. Downstream text indexing has its own state and cannot roll a readable book back to "not imported". User-visible names for these states are fixed in Section 4.4.6.

At `acquiring`, no library item claims a complete asset. At `staged`, bytes are owned by Sylvia but not yet trusted. At `ready`, the final content path and database relationship exist, required validation has passed, and the work is usable. Display "Ready · indexing continues" when appropriate.

Idempotency uses a stable job ID plus asset digest and source revision. A retry reuses that job. A relaunch scans staged manifests, unfinished commits and orphan final blobs; it either finishes the recorded operation or presents recovery. Use a durable commit journal because a filesystem rename and SQLite transaction are not a single atomic transaction.

Recommended commit sequence: verify staged bytes; persist a commit-intent row; move to an immutable final blob path on the same volume; transactionally attach asset/location/edition and mark ready; mark the intent complete. A crash between steps leaves a recoverable journal entry, not a duplicate work. Garbage collection must never remove a blob with a live commit intent or knowledge reference.

## 8.3 Type, structure and safety

Support reflowable EPUB 2/3 within a documented compatibility subset, text-based PDFs, UTF-8 text/Markdown, and tested audiobook combinations. Validate both container and codec. Do not reject an EPUB solely because `encryption.xml` exists: font obfuscation is not necessarily content DRM. Detect actual protected content with the reading adapter and return a clear unsupported-protection error without attempting circumvention. [S1]

EPUB parsing must reject path traversal, absolute paths, symlinks, decompression bombs and excessive recursion. Publication scripts and remote resources are disabled; only reader-owned interaction scripts may run in the renderer. Treat malformed chapter metadata, cover dimensions and embedded links as untrusted input. PDF launch actions and unsolicited external URLs are not executed.

Proposed configurable limits: 20 GiB per audio file; 2 GiB PDF; 1 GiB EPUB expanded content; 10,000 archive entries; 500 audio members per logical edition; bounded image dimensions and parser time. These are release safety defaults to validate against real samples, not claims about OS maxima. Reject oversized items before expensive processing when the size is known; enforce limits while streaming when it is not.

For multi-file audio, group by a selected folder or explicit import selection, not every adjacent MP3 in a mixed directory. Prefer embedded disc/track ordering, then natural filename order; show an editable order preview. Retain the original filenames and record the confirmed timeline revision. Never require destructive concatenation or transcoding simply to form one logical audiobook.

## 8.4 Checksums and truthful status

An app-controlled Mac manifest provides expected byte counts, part digests and final SHA-256. Ordinary user-supplied URLs may provide no trustworthy expected digest. For those, calculate a local digest for deduplication, verify HTTP completion and parseability, and label the provenance accordingly. A self-computed digest is not proof that the origin supplied the intended complete file.

Keep failed staging items only with a documented retry/cleanup policy. Offer "Retry", "Choose replacement file", "Inspect details" and "Discard partial data". Retrying must not discard already verified parts unless the source version changed. Space errors must name the additional space required where calculable.

## 8.5 Wired bundles

Add a versioned `.sylviapack` interchange bundle for the Mac companion's reliable wired handoff: a ZIP64-capable, non-executable container holding a manifest, relative file paths, sizes, digests, grouping and optional metadata. Large audio should be stored without redundant compression. Use an audited archive implementation and test files above 4 GiB before declaring support.

A raw file copied through Finder is allowed, but Sylvia cannot prove an external writer has finished merely from an unchanged size. Require user-initiated import after the Finder copy completes, coordinate the copy and validate. For bundled transfers, the manifest/digests supply an additional completeness check. A partial bundle must never pass validation. Do not describe cable import as the same resumable HTTP protocol: the **validation and commit stages** are shared, while transport guarantees differ.

# 9. Reading implementation

## 9.1 EPUB

Wrap Readium's publication opener and navigator behind `ReaderSession`. Required operations are open, navigate, read current locator, receive selection, apply/remove visual highlight decorations, search within work, and observe position changes. Readium locator and decoration capabilities should be demonstrated with the chosen release before committing to the adapter contract. [S1, S3]

V1 controls: typeface from a small accessible set (Literata as the default, system serif, system sans; Section 4.4.3), size, line spacing, margins, Paper and Night themes with an Auto option, publisher-style preference, table of contents, bookmarks and return-after-link navigation. Support internal notes/footnotes without losing reading position. Save settings per user with an optional per-book override. Prioritize a reliable paginated mode; continuous scrolling is a proposed secondary mode only if the same anchors and capture tests pass.

Selection opens Highlight, Note, Look Up and Ask (Section 4.4.7 selection menu). Capture the source locator and exact text immediately before a navigation or font change can invalidate the selection. Store highlights in Sylvia's database; reader decorations are only a presentation of those records, drawn with the `ochre` highlight fill and underline so they remain visible without color (Section 4.4.8). Long selections crossing resource boundaries may require multiple anchors; the UI must never silently truncate a quotation.

Index publication text resource by resource with extraction-version provenance. Preserve enough mapping to reopen search hits; normalize whitespace for search separately from the original quote. Rendered EPUB position is not a stable print page number. A failed/nonstandard publication must leave the source file available for removal or retry without crashing the library.

## 9.2 PDF

Use PDFKit for display, selection and navigation. Store text quotations and source anchors in Sylvia, not solely as annotations written into the original PDF. Display highlight overlays from saved records. Keep physical page index, printed page label if supplied and normalized selection geometry distinct. Handle rotated pages and multiline selections. [S10]

The supported experience is passage selection, comments, Ask AI, page navigation, search and zoom. No drawing tools, signatures, forms, stamps or PDF rewriting. Password-encrypted PDFs are a proposed v1 exclusion; do not conflate a password prompt with a right to bypass protection. Unsupported/encrypted items show a specific error.

Scanned or image-only pages may be visually readable, but text features show "No selectable text on this page". No guessed OCR text, no claim that AI has seen the page, and no silent image upload to compensate. Mixed PDFs can support text features on pages that actually have text; retain per-page extraction status.

## 9.3 TXT, Markdown and lookup

Provide a simple native/sanitized text renderer with selection and offsets against a retained original text representation. Markdown links and formatting may render, but embedded HTML/scripts and remote images remain disabled by default. Preserve exact original source bytes and extraction version so future renderer changes do not rewrite quotes.

Use the system dictionary interface where available. Availability of definitions/offline dictionaries must be checked at runtime. A dictionary lookup and a model-generated explanation are separate actions with different provenance. V1 can save a word, source sentence and user note; it must not promise bulk extraction/export of system dictionary definitions. [S11]

## 9.4 Reader acceptance boundaries

A same-asset highlight must survive relaunch, font size/theme changes, orientation and extraction-cache rebuild. Returning from footnotes, search results and capture preview must preserve the user's reading position. VoiceOver must reach selection actions and saved-note content. Unsupported layout, image-only content or imperfect extraction should degrade with specific explanations, not a false "full text available" badge.

# 10. Audiobook player and audio capture

## 10.1 Playback service

Use a single application-owned playback service with AVAudioSession playback configuration, background audio capability, AVPlayer/AVQueuePlayer as appropriate, and MPNowPlayingInfoCenter/MPRemoteCommandCenter for supported system controls. Activate the audio session only for playback; importing a book must not interrupt audio in another application. [S8-S9]

Expose play/pause, configurable skip intervals, speed 0.5x-3x where supported, chapter list, time elapsed/remaining, sleep timer and selection of an edition. Preserve pitch where the chosen playback path supports it. Test seeking, rate changes, chapter transitions and lock-screen controls with real devices and long files; file extension support alone is insufficient.

Persist asset-local position every five seconds while playing and on pause, seek, interruption, item change and lifecycle transitions. After a crash, the proposed maximum position loss is five seconds, not zero. Store last position separately from furthest progress. Playback error states identify a missing file, an unavailable source or a decode error.

On headphone removal, pause. On calls/interruption, pause and resume only when the platform indicates it is appropriate and the prior user state was playing. Audio-route changes must not accidentally play aloud. Resume-after-a-long-pause may rewind a configurable small amount, but should not mutate a saved bookmark or quote.

Multi-file editions have an ordered manifest and derived global timeline for display. Canonical anchors remain file-local. A changed order creates a new timeline revision; old captures continue pointing to the original files/ranges. A missing member blocks the unavailable segment and shows an incomplete-edition warning; v1 does not market partial remote streaming as complete offline availability.

## 10.2 Audio capture semantics

**Bookmark** means a position only. **Audio capture** means a bounded excerpt with its original source ranges, optional transcript and notes. **Text quotation** exists only when text was actually selected, supplied by the user or transcribed and labelled accordingly. Never generate a quotation from a title and timestamp.

The proposed default Capture action records the preceding 30 seconds of source time, clamped to valid bounds; permit trimming/extension up to 120 seconds through both range handles and numeric start/end controls (Section 4.4.1, principle 5). A cross-file selection stores several ranges. Capturing writes the anchor immediately, then exports a small playable excerpt into retained knowledge storage. User feedback distinguishes "Moment saved · preserving audio" from "Audio excerpt saved" (Section 4.4.6).

Export must use a tested codec path and include actual exported timing, since format boundaries can affect precision. Media retention must not delete the full source while a requested excerpt export is pending or failed without an explicit warning/choice. If export fails, the saved bookmark and note survive, and the UI offers retry ("Excerpt not preserved · Retry"); it does not claim to have preserved the words or sound.

Once successfully retained, the excerpt remains playable after removing the full audiobook. Excerpts count toward retained-knowledge storage, are included in default knowledge backups and can be removed separately by the user. This is intentionally different from treating every audio highlight as a pointer to a disposable file.

## 10.3 Replay without corrupting progress

Capture preview uses a bounded preview mode with a saved main-player context. It pauses the main session, plays only the excerpt, and returns to the prior book position/state. Preview playback must not update completion, furthest position or main listening-time totals. If a phone interruption occurs during preview, restoration still uses the preserved main context.

## 10.4 Optional transcription

V1 should support **user-requested short-clip transcription**, not whole-book processing. The selected speech adapter may be an OpenAI-compatible transcription endpoint; a configured text-chat server is not assumed to support audio. Transcription uses only the retained clip, not the source audiobook. Official APIs expose file-transcription capabilities, but per-provider/model limits must be discovered or configured rather than hard-coded from marketing names. [S16]

Require explicit audio-sharing consent and a separate capability test. Queue a local draft when offline; do not automatically transmit it later without the user's selected queue policy. Preserve raw transcript, provider/model, timestamps and user corrections separately. Label machine transcription as potentially inaccurate; users can edit a corrected version before saving it as a quote. When no speech service is configured, the capture detail says so plainly and offers "Set up transcription" and "Type what you heard".

A companion EPUB can be searched for a matching passage; candidates require confirmation and retain provenance. Merely pairing the titles does not map timestamps to sentences. With no transcription or companion passage, Ask AI can use the user's note or selected work text but must say that the current audio passage is unavailable.

## 10.5 External and lock-screen boundaries

Do not capture other apps' audio, inspect private playback data or depend on Spotify authorization in v1. Manual external-source ledger entries remain possible. Standard system playback controls are required; a dedicated lock-screen capture control must pass Stage 0 for supported iOS versions and locked-device persistence before it becomes a release promise. Do not repurpose play/skip buttons as undocumented clipping controls.

# 11. Annotations, retained knowledge and search

## 11.1 Capture transaction

A capture command takes the work/edition, source snapshot, exact selected text or audio ranges, optional comment and an idempotency key. Commit the capture, anchors, note and ledger activity in one database transaction. If storage is full, keep the editor content visible and show a save failure ("Not saved · your text is still here"); never dismiss a note that has not been persisted.

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

Listening sessions use observed playback intervals; report real active elapsed time separately from source-duration progress when playback speed differs. Reading time is an estimate based on foreground activity and idle thresholds, not proof of attention. Never infer reading progress from an AI answer, note preview or an open screen left unattended.

A proposed rating is nullable, 0.5-5 stars in half-star steps stored as integer 1-10, drawn with the rating component in Section 4.4.7. A clear rating is null. Keep the scale explicit in export rather than storing a bare number with an undocumented meaning. Support an optional short review note.

Recommendation events support inbound and outbound direction; a person, podcast, article, other work or free-text source label; date or approximate date; and a reason. One work may have many events. Outbound events mean "I recommended this", not that Sylvia sent a message. No contacts permission, messaging integration or automated recommendation delivery is required.

Allow a metadata-only physical/external work with manually entered page number, chapter or listening position. Mark those positions as manual and edition-specific. A photo of a page, automatic ISBN scanning and external playback observation remain later capture adapters.

Removing a book's last local file changes its action from "Read/Listen" to "Add file" or "Download from source" while leaving the title and record intact, with the availability badge "Record only" or "Not on this device · from {source}". The ledger must be visible and searchable even when no source location remains reachable.

# 13. Context assembly and source-aware AI

## 13.1 Context is a product surface

The user chooses among **selected passage**, **selected passage plus nearby text**, **search this work**, or **selected saved thoughts**, presented as scope chips with the labels fixed in Section 4.4.6. Default to the narrowest relevant context. For work search, retrieve bounded excerpts and say "Relevant passages retrieved", not "The AI read the entire book".

Whole-book inclusion is allowed only when the entire extracted text fits the configured input budget and the user explicitly chooses it. Comprehensive whole-book summarization with exhaustive chapter coverage is not a v1 guarantee. The interface must not claim completeness based on a handful of retrieved chunks.

A ContextPack is built and stored before sending a request. It contains the user question, evidence snippets with stable local IDs, source/edition anchors, source-quality labels, scope, prompt-template version, retrieval settings, available-text coverage and any truncation. Persist exact sent snippets so the conversation remains understandable after media/index removal.

## 13.2 Retrieval algorithm

For a text selection, prioritize exact text and bounded adjacent paragraphs from the same resource/page. For work search, run lexical search over that work's extracted text and optionally its retained knowledge, rank/deduplicate overlapping hits and include a limited number of adjacent chunks. Begin with 300-600-word extraction chunks preserving paragraph boundaries; tune using retrieval tests rather than treating this size as universal.

For audio, use a confirmed companion passage, transcript or user note. Do not turn a timestamp into assumed textual evidence. For a manual physical record, use entered quotes/notes only. Allow users to select up to a small reviewed set of saved passages across works for comparison; automatic whole-library semantic research is deferred.

Build the budget from the configured model context limit minus system text, question/history, output reserve and safety margin. Default unknown models to a conservative configurable budget, and disclose truncation. Use a model-appropriate tokenizer where supported; estimates must be labelled. A context-length error reduces scope with user-visible explanation, not silent evidence deletion.

## 13.3 Spoiler controls

Default to selection plus nearby context. Offer "Do not include later passages" where ordered text anchors make the boundary enforceable. Filter retrieval before sending; do not merely ask the model not to spoil material it already received. Cross-edition audio-to-text progress cannot enforce a precise spoiler boundary without an alignment; use a user-confirmed chapter/passage boundary or state the limitation.

Do not advertise guaranteed spoiler-free answers. A model may have prior knowledge. Prior conversations that used later passages must be excluded from a restricted context pack; start a clean restricted thread rather than leak older full-book content back into the prompt.

## 13.4 Grounding and citations

Delimit source material as untrusted evidence, not instructions. Ask the model to distinguish source-based statements from general explanation and to reference local evidence IDs. No tool invocation or automatic network fetch follows an instruction found in a book, note or provider response.

After generation, resolve citation IDs against the ContextPack allowlist. Invalid IDs remain visibly unresolved and are not turned into fabricated links; they render as struck-through grey chips with a one-line explanation beneath the answer (Section 4.4.5). A citation opens the exact retained snippet and, when available, the original anchor. Validate claimed direct quotations against supplied evidence; unverifiable wording is labelled as a paraphrase or unsupported quote, not an exact source quotation.

Citation validity does not establish entailment. Include human evaluation for whether the cited passage actually supports the answer. Saved AI content should retain a model-generated label and permit user comments/corrections. When evidence is insufficient, the expected behavior is to say so or ask for a passage, not invent the contents of the book.

# 14. AI providers, privacy and failure handling

## 14.1 Provider contract

Define separate `TextGenerationProvider` and `SpeechTranscriptionProvider` interfaces. Text generation accepts a provider-neutral request and returns a stream of text/status/usage events. Speech accepts a bounded local clip and returns text plus available timing/provenance. Model listing and token counting are optional capabilities, not prerequisites for configuring a custom endpoint.

V1 text adapters: **OpenAI API**, **Anthropic Messages API**, and **generic OpenAI-compatible chat API**. Start the OpenAI text path with a documented supported API and integration tests; the generic compatibility contract is `/chat/completions` relative to an explicitly configured API base. Anthropic gets its own request/stream adapter rather than being forced into OpenAI's payload. [S17-S18]

Configuration includes provider kind, display name, base URL, model identifier, credential reference, supported capabilities, context/output limits, optional request timeout, and privacy classification. Normalize base URLs once; avoid producing `/v1/v1/...`. Permit manual model entry because many local servers do not implement model discovery correctly. Do not hard-code a current model name or subscription tier into domain logic.

Hermes works as an optional compatible endpoint if its configured route passes conformance tests. The client cannot guarantee that a gateway is local-only simply from its address: the gateway could forward to another provider or run tools. Label this as a user-managed connection; require the operator to configure an appropriate text-only/no-side-effect route. Sylvia itself does not expose execution tools or silently grant access to the device library.

## 14.2 Credentials and consent

Store user credentials only in Keychain; never in SQLite, exported configuration, a bundled application secret, analytics, logs or screenshots. Ship no developer-owned provider key. Bring-your-own-key mode uses the user's own credential on their device; public distribution needs security review of this choice and a gateway option for users who prefer not to store a provider key in a mobile client.

Keep AI credentials inaccessible while locked where the selected interaction does not require them; transfer credentials may need after-first-unlock device-only accessibility to support authorized background transfers. Choose accessibility classes deliberately and test them after reboot/lock. Credentials do not migrate through Sylvia backups; restoration requires reauthentication/pairing. [S21]

Before the first request to an endpoint, show the destination host, whether it is local/user-managed/hosted, what will be sent, and that the endpoint operator's policies apply. The same disclosure appears as a persistent row on the Ask screen ("{host} · hosted · {model}"; Section 4.4.6). Reconfirm when the destination changes or the user broadens sharing to notes/audio. Apple requires explicit permission and disclosure when personal data is shared with third-party AI; a generic privacy policy is not the entire consent experience. [S19]

No automatic fallback between providers. No invisible upload of whole books, page images, contacts or recommendation relationships. Use selected evidence rather than bulk files. Do not claim provider-side zero retention unless independently supported by the user's actual provider/account configuration.

## 14.3 Network policy

HTTPS is the default. Paired Mac connections use the validated trust design in Section 15. For manually configured local inference, allow a narrowly scoped, explicit HTTP exception only for eligible local endpoints and only if the minimum OS's ATS behavior passes testing. Unrestricted cleartext internet endpoints are rejected. Do not globally disable App Transport Security to support a convenient development server. [S12-S13]

A Tailscale IP/name is a connectivity route, not evidence that an HTTP hop is encrypted end-to-end all the way to the model host; subnet routing and proxies can change the boundary. Recommend HTTPS even on a tailnet, and explain any exception. Do not use a `.local` name as the sole security check or allow a remote redirect to inherit local trust.

Connection tests classify failures: DNS, permission denied, host unreachable, TLS/pin mismatch, authentication, unsupported model, unsupported API dialect, rate limit and invalid response. Display actionable diagnostics with secrets removed. Avoid a generic "AI failed" for every cause.

## 14.4 Request lifecycle

Persist user question and ContextPack before sending. States: `draft -> awaiting_consent -> ready -> sending -> streaming -> complete`; alternatives are `cancelled`, `interrupted`, `failed_retryable`, `failed_final`. User-visible names are fixed in Section 4.4.6. Save partial output periodically, clearly marked "Interrupted · partial answer". Do not save provider-internal reasoning as a user-facing answer; process supported answer/status fields only.

On offline submission, save the question as a draft and show "Draft · not sent" with "Saved on this device". Proposed default is manual send when connectivity returns, avoiding unexpected later API costs or privacy changes. An opt-in auto-send policy can be reviewed separately.

Retry transient connection/429/5xx failures with capped exponential backoff and Retry-After when available. Do not automatically replay a generation whose acceptance is uncertain: the first request may already have incurred a charge. Use idempotency only where the provider actually documents it; otherwise ask the user before resubmitting an uncertain generation. Never duplicate the visible question or conversation on retry.

Use bounded streaming parsers tested against split UTF-8 characters, partial SSE events, keepalives, tool-call responses, refusal responses and malformed JSON. Reject unsupported tool calls without executing them. AI is foreground work in v1; suspension may interrupt streaming. The saved question/evidence remains, and the app does not promise that generation continues while force-quit.

## 14.5 UX, costs and user control

Provide Explain, Define in context, Summarize this passage and Ask a question. Save all explicitly sent interactions locally, with a separate "Save to Thoughts" action to promote an answer. Allow deleting a conversation with a clear explanation of retained evidence deletion.

Show provider/model and context preview before sending; display usage only when supplied reliably. Show a price estimate only when a maintained/user-configured pricing profile is available, and label it an estimate. No invented "free because you subscribe" messaging. Cap request/output sizes and audio duration rather than allowing accidental unbounded jobs.

# 15. Secure, resumable Mac-to-device transfer

## 15.1 Connectivity model

The **Mac hosts a source service; the phone is a client**. The app can discover the service through Bonjour on a LAN and can connect through a manually entered address or pairing payload. It never relies on the iPhone running a permanent local web server. The source must be awake, running and reachable; otherwise jobs wait without losing verified progress.

Register a product-specific Bonjour service type and request local-network permission in context. Manual-address connection is required because multicast discovery must not be assumed across VPNs. Support an explicitly entered Tailscale address/MagicDNS name through ordinary networking; do not build a Tailscale client, demand a public port, or require a cloud relay. [S12, S20]

V1 is pull-first. "Send to device" on the Mac adds an item to the device's source queue; the phone fetches it when it connects. Without a push infrastructure, that command cannot reliably wake a force-quit phone. Status must distinguish queued, observed, downloaded and imported. No real-time notification promise is made.

## 15.2 Pairing and trust bootstrap

Proposed default: the Mac generates an identity key/certificate plus a single-use invitation. A **pairing payload** contains protocol version, stable source ID, one or more endpoint addresses, the full certificate/public-key fingerprint, a high-entropy invitation secret and expiry. Present it as a copyable code/link and optionally a QR code. The iPhone obtains the trust fingerprint through that user-mediated channel before transmitting the secret.

Validate the peer against the pinned identity, exchange the invitation for a scoped per-device credential, and invalidate the invitation. Use at least 128 bits of invitation entropy, a short expiry and attempt limits. Display the device identity on both ends, with the fingerprint in the Monospace face grouped in fours, and let the Mac user approve it. Store secrets in Keychain; do not put invitations in logs, analytics or pasteboard history managed by Sylvia. Clear the app's temporary pairing state after completion.

A six-digit number over an unauthenticated connection is **not** the security design. A shorter human-only code requires a reviewed PAKE/authenticated pairing implementation; do not invent a new cryptographic protocol. The copyable invitation is the baseline review proposal for meeting one-time pairing without custom cryptography.

After pairing, verify the pinned identity on every connection. A changed source key requires explicit re-pairing; never present a generic "ignore certificate error" switch. Tokens are scoped to catalog/read/download/receipt operations, not arbitrary file access or source deletion. Revocation stops future access; it cannot erase files already imported by a device.

**Stage 0 gate:** prove the selected TLS identity/pinning path works with iOS background URLSession and the intended address forms. The app cannot bypass trust validation to achieve background transfer. If this combination fails, the team must choose a validated certificate-based alternative or a clearly foreground-only resumable mode before approving release promises.

## 15.3 HTTP contract

All API paths are versioned. This is a proposed contract to turn into OpenAPI and fixture tests at kickoff, not a claim that a server already implements it.

| Method and path | Purpose | Required behavior |
| --- | --- | --- |
| GET `/v1/capabilities` | Protocol compatibility and limits | Minimal unauthenticated data only; no library titles |
| POST `/v1/pair` | Exchange invitation after trust bootstrap | Single-use secret, source binding, expiry, approval and rate limits |
| GET `/v1/catalog?cursor=...&limit=...` | Browse selected source entries | Authenticated, stable pagination, metadata and immutable versions |
| GET `/v1/items/{id}/manifest` | Exact asset/group description | File sizes, digests, ordered members, chunk size/hashes, manifest version |
| GET `/v1/assets/{id}/content` | Download verified immutable bytes | Single Range support, strong ETag/If-Match, Content-Length, no transformation |
| GET `/v1/device-inbox?cursor=...` | Pending items queued for this device | Cursor and immutable item versions; no implied automatic import |
| POST `/v1/receipts` | Record download/import result | Idempotent receipt ID; no deletion of original source |
| DELETE `/v1/pairings/{device_id}` | Revoke a paired device | Owner-approved on Mac, or self-revocation for the authenticated device |

All endpoints except capability discovery and the pairing handshake require scoped authentication. Validate every supplied ID; never interpolate a remote path into filesystem access. No wildcard CORS or web browser exposure is needed. Reject protocol-major mismatches with an understandable update message; tolerate additive optional fields.

## 15.4 Manifest and resumability

The Mac prepares an immutable snapshot for each active file version. The manifest identifies the bytes, not a mutable file path. If the selected original changes, create a new version and invalidate old unserved manifests rather than mixing old and new ranges. Active transfers either read a managed immutable snapshot or fail on change; a checksum failure at the end is not the only defense against mutation.

Proposed part size: 16 MiB, configurable by protocol capability. Each part has an offset, length and SHA-256. The phone persists part completion only after validating the received bytes and retaining them on disk. Use background URLSession download tasks for eligible parts and restore OS task associations on launch. Two in-flight transfers and bounded queued parts avoid overwhelming system scheduling.

Requests use a single byte Range and If-Match tied to the manifest version. Accept only a correct 206, matching Content-Range and expected length/digest. A 200 for a partial request, 412, 416, changed ETag, unexpected encoding or changed manifest pauses/restarts explicitly; never append it to a previous partial file. Retry a failed part, not verified parts from the same immutable version.

After all parts verify, assemble or finalize through a journalled file-store operation; verify the complete SHA-256; then hand the asset to the normal importer. Keep 100% received distinct from 100% verified/ready. Disk reservation must account for temporary parts plus any assembly copy. Prefer a tested sparse/preallocated staging strategy to avoid double storage, but preserve recoverable part records until final validation succeeds.

Ordinary third-party URL downloads may use URLSession resume data and HTTP validators opportunistically, but do not inherit the Mac protocol's guaranteed immutable parts. If the origin cannot resume safely, explain that a restart is required. Wired Finder transfers share validation and commit logic, not resumability guarantees.

## 15.5 Recovery and visibility

On launch, reconcile persisted jobs, OS task IDs, part files and manifests. Use stable task descriptions containing a job/part ID, not secrets. Detect missing local parts and re-fetch only those. A stale/expired credential blocks access until reauthentication; it must not erase already verified bytes. A revoked pairing never silently reconnects with a broader credential.

Show current file, verified/total bytes ("3.1 of 5.2 GB verified"), stage, pause/resume/cancel and the blocking reason. Throughput/time remaining are estimates only while data is flowing. A phone force-quit, Mac sleep or network denial results in a resumable state and clear next step. No fixed completion-time promise is part of the UI.

# 16. Lightweight macOS companion

## 16.1 Product boundary

The companion exposes selected folders/files, lets the user group an audiobook, pairs trusted devices, queues files and shows transfer state. It exports wired `.sylviapack` bundles and provides a Finder handoff guide. It is not a desktop reader, full annotation app, canonical knowledge database or Calibre replacement. It uses the same design tokens, type roles and status vocabulary as the iOS app through the shared design package (Section 4.4.9), with macOS control sizing.

Start with user-selected folder access and explicit file picks. Use sandbox-compatible access/bookmarks and handle permissions being revoked, drives disconnecting and network shares becoming unavailable. Show source health. Preserve the original structure; do not rename, convert, move or delete source files.

For Calibre, v1 supports user-selected exported files/folders as ordinary sources. Direct reads/writes of Calibre's live database, custom-column mapping and live catalog integration are deferred to an adapter proposal. This avoids depending on Calibre internals or rewriting its organization without approval.

## 16.2 Source index and queue

Keep a small local index with opaque item IDs, known sizes, modification metadata, digest state and prepared snapshots. Enumerate incrementally; lazy-load thumbnails and compute hashes on demand/background rather than blocking a 5,000-item folder on first open. Detect the source changing between hash and serving. Explain "Preparing transfer" separately from copying to the phone.

The outbound queue is durable on the Mac. Users may add files while the phone is off; delivery waits until a connected phone requests them. This supplies a modest queued handoff without pretending that the Mac app is the future always-on Docker hub. Its queue does not accept autonomous book-acquisition tasks in v1.

Receipts are idempotent. A lost receipt may be retried without importing a duplicate. The Mac must not treat successful HTTP delivery as proof that Sylvia committed the library item; the companion shows the three receipts "Queued on Mac", "Downloaded to phone" and "Imported into Sylvia" as separate states. Display import failures returned by the phone and retain the source/queue entry for retry.

## 16.3 Distribution and service lifecycle

Proposed initial distribution is a signed, notarized Mac app for the testing group; public distribution is a product/release decision. Use no privileged helper, USB driver or kernel extension. The transfer service runs while the companion is running. Start-at-login is opt-in and reversible, not an invisible daemon installed by default.

Allow the user to stop serving immediately and revoke devices. Bind only intended interfaces, with LAN serving explicit. A private network is not a substitute for authentication. Transferred items remain limited to selected source roots and immutable prepared snapshots.

## 16.4 Wired flow

The Mac companion's "Prepare for cable transfer" produces a bundle and shows the exact steps: connect/unlock/trust the iPhone in Finder, choose Files -> Sylvia, copy the bundle, wait for Finder completion, then open Sylvia's import inbox. This relies on Apple's supported file-sharing flow. [S7, S22]

On device, Finder-visible Documents is an **inbound drop area only**. Put the library database, private notes, credentials, retained text and knowledge clips elsewhere. Staged bundles may be cleaned up only after successful import or explicit user action. Deleting a file through Finder must never delete the permanent catalog.

# 17. Storage, retention, export and recovery

## 17.1 Storage classes

| Class | Examples | Default policy |
| --- | --- | --- |
| Permanent knowledge | Ledger, ratings, recommendations, captures, exact quotes, notes, saved AI evidence, retained audio excerpts | Keep until explicit deletion; include in knowledge backup |
| Original media | EPUB, PDF, full audiobook and companion assets | User-managed; audio removal encouraged after completion, never automatic in v1 |
| Derived source content | Full extracted text, optional transcripts, location maps | Keep while source is retained; separate retain-after-removal choice |
| Rebuildable indexes/cache | FTS index, thumbnails beyond canonical cover, renderer caches | Rebuildable; removable without deleting user-authored knowledge |
| Staging/recovery | Partial transfers, import bundles, commit journals | Keep for live operations; visible cleanup policy for abandoned jobs |
| Secrets | Provider keys, device tokens, pairing identity | Keychain only; excluded from exports |

Distinguish durable saved evidence from a full extracted book corpus. Full text is content, not merely harmless metadata; the user must understand that retaining it can preserve almost the entire book after the EPUB is removed. Embeddings, if added later, are also derived content with their own deletion policy.

## 17.2 Deletion UX

Use separate actions: **Remove download**, **Manage retained text**, **Remove excerpt audio**, and **Delete library record and associated knowledge**. Never place the destructive last action behind an ambiguous trash icon on an audiobook download. The destructive action is styled per Section 4.4.7 and never sits beside a primary button.

Before removing a full audiobook, show the impact report (Section 4.4.7): retained knowledge counts, excerpt export failures/pending work, expected space freed and recovery sources. When an excerpt is still being preserved, the safe choice ("Wait, then remove") is the primary button. Pins and active playback prevent automatic removal. Proposed v1 default is manual removal; scheduled rules such as "remove finished audio after 30 days" are deferred until safety is demonstrated.

Removing EPUB/PDF offers an explicit text-retention choice, with the permanent quote/note/evidence exception explained. Source text required by saved ContextPacks remains as exact retained evidence even when the general text corpus is removed. A separate "erase retained content copies" operation must identify those dependencies rather than mislead the user.

## 17.3 Backup format

Ship a versioned `.sylviabackup` container with a manifest, consistent database snapshot, portable JSON exports, Markdown notes/captures, canonical cover thumbnails, retained excerpt audio and content digests. Include extraction-independent anchors and evidence snapshots. Full originals and full derived source text are optional and enumerated. FTS indexes may be excluded and rebuilt.

The default knowledge backup must preserve every acknowledged user knowledge item, including saved audio excerpts and AI evidence. Do not make a "complete backup" claim when original media is excluded. The export manifest records schema versions, counts, included/excluded classes, creation time, originating device ID and digests. No credentials or active pairing tokens are exported.

Proposed v1 exports are unencrypted containers with a prominent privacy warning and user-chosen destination. The team must approve this limitation for the release audience. Do not invent custom backup encryption; password-protected portable export needs a separately reviewed library/format. The application's device protection does not follow an exported file to an unprotected destination.

## 17.4 Consistent export and restore

Take a consistent database snapshot, freeze a manifest of referenced retained blobs, and hold temporary retention leases so cleanup cannot remove blobs during export. Exporting notes while the user reads is allowed, but capture the snapshot boundary and do not mix incompatible revisions. Finalize the container atomically and verify it before declaring success.

Restore into a temporary library, validate paths/digests/schema, apply supported migrations, check foreign keys/counts, and only then swap the active store while preserving a pre-restore recovery copy. Stop playback/writes during the final swap. Restore is **replace with confirmation**, not an unspecified merge of two active libraries; fresh-install restore is the primary supported workflow.

Reject newer unsupported schemas without altering existing data. Fail safely on truncated, malicious or corrupted archives. Rebuild indexes after the authoritative data is available. Missing original files become unavailable assets with intact knowledge. Re-pair sources and re-enter provider secrets; do not silently reuse stale device credentials from a restored database.

## 17.5 Device backup and loss

Use iOS backup classifications deliberately. Keep unique user knowledge backup-eligible; treat re-downloadable cache differently from sole-copy user imports. Do not exclude unique originals from system backup merely because they are large without explaining the recovery consequence. Show last successful explicit knowledge export and whether originals have other known copies; do not assert that an unreachable source is a verified backup.

A local app cannot preserve data after uninstall/device loss without a backup. State that plainly in onboarding/storage help. The permanent ledger means it survives **media removal inside Sylvia**, not that it survives destruction of every copy of the device.

# 18. Security, accessibility and release compliance

## 18.1 Threat model and controls

Treat publications, archive entries, provider responses, URLs, source metadata and pairing advertisements as untrusted. Threats include malicious EPUB HTML, parser crashes, archive traversal, oversized files, altered source bytes, credential leakage, rogue LAN hosts, prompt injection and accidental destructive deletion.

No publication-owned scripts, automatic remote images or hidden tracking requests. No execution of model-produced commands. Sanitize rendered Markdown/HTML and make external-link opening an explicit user action. A model cannot create a valid internal citation merely by emitting an arbitrary URL or entity ID.

Endpoint credentials are origin-scoped and redacted. No tokens in query strings for durable transfer URLs. Never log selected text, prompts, titles, notes, file paths or recommendation names by default. Scrub errors before display/export. Use a content-security test corpus containing malicious instructions, remote resources and path traversal attempts.

Use iOS Data Protection for persistent files. Select database/media accessibility consistent with authorized background playback and transfers after first unlock; document the tradeoff against stricter locked-device confidentiality. Apply the same protection to WAL/SHM, staging, retained excerpts and manifests. On reboot before first unlock, show/provide a safe unavailable state rather than attempting an unsafe downgrade. [S21]

## 18.2 Permissions and privacy

Permission requests are just in time: local network when connecting a source; camera only if QR pairing is enabled. No contacts, microphone, photo-library-wide access, location, email or tracking permission is needed for the baseline. Transcribing an imported clip is not microphone recording. Future physical-page capture or voice notes need their own permissions and consent flows.

No third-party product analytics by default in v1. Offer an opt-in, redacted diagnostics export with a preview. An API call goes to the user's configured endpoint; Sylvia's own infrastructure is not an intermediary in this proposal. Document any chosen crash SDK's real data collection before using it.

App privacy labels, privacy manifest, required-reason APIs and third-party SDK declarations must match the implementation. Review third-party AI consent and content-access rights before distribution. DRM-free user import is not a promise that every file's redistribution is authorized; fixtures, sample content and promotional material require appropriate rights. [S19]

## 18.3 Accessibility and interaction quality

Support Dynamic Type, VoiceOver, high-contrast appearance, reduced motion, landscape reading and accessible labels for icon actions. Highlight colors must not be the only way to distinguish capture types; the marker set in Section 4.4.5 and the grayscale conformance rules in Section 4.4.8 define how each distinction survives without color. Provide text labels for save states, progress and audio range controls. Test with hardware keyboards on iPad where the standard UI supports them.

Make all critical actions reachable without precision dragging: edit audio start/end numerically, navigate by chapter/page, and invoke capture through a labelled button. Announce saved/failed status without repeatedly interrupting screen-reader playback. Keep errors adjacent to the failed action and preserve the user's draft.

## 18.4 Distribution gates

Start with internal builds, then a small TestFlight cohort using licensed sample content and their own permitted files. Public App Store submission is a separate approval gate after product/legal review. Include a review path demonstrating core functionality without a paid model account; do not supply a shared production API key in app metadata.

No in-app purchase or subscription implementation is assumed because monetization is unresolved. Before public release, decide the commercial model and recheck App Store rules for the actual flow. Do not promise that bring-your-own-provider configuration automatically resolves every distribution-policy issue.

# 19. Performance, scale and observability

## 19.1 Reference datasets and devices

Use at least one older supported physical iPhone, a current iPhone, an iPad, and an Apple Silicon Mac. Proposed baseline is iPhone 12-class hardware on a supported OS, subject to actual Stage 0 availability. Run release builds, not debugger-attached results, and record OS/device/storage conditions. Simulator tests do not establish background, lock or real audio behavior.

Two datasets: **working set** with 50 locally stored mixed works including large audio; **catalog scale** with 10,000 metadata records, 100,000 knowledge artifacts, 5,000 source entries, and incremental text indexing on a selected subset. Include a 5 GiB audiobook, an audio edition with hundreds of members, a 1,000-page PDF and a large multi-resource EPUB. Use generated/licensed fixtures, not scraped copyrighted libraries.

## 19.2 Proposed measurable budgets

| Operation | Initial acceptance budget | Measurement conditions |
| --- | --- | --- |
| Cold launch to interactive library | p95 <= 2.5 seconds | Catalog-scale dataset, no blocking migrations/indexing |
| Catalog/retained-note search | p95 <= 500 ms | Warm local query, first 50 results, catalog-scale dataset |
| Acknowledged capture save | p95 <= 200 ms | After selection is available, excludes audio export/network |
| Start/resume local audio | p95 <= 1.5 seconds | Valid downloaded file, excludes first codec inspection |
| Open typical local EPUB/PDF | p95 <= 2 seconds | Defined representative fixture, not every pathological book |
| Playback position crash loss | <= 5 seconds | Periodic checkpoint plus boundary events |
| UI during indexing/transfer | No sustained main-thread stalls over 100 ms | Instruments trace during scrolling/capture |
| Capture preview timing | Within 500 ms of intended boundary | Tested release codec matrix; actual export range recorded |
| Memory during large-file transfer | Bounded; no growth proportional to file size | 5 GiB transfer, repeated interruption/retry |
| Acknowledged knowledge durability | Zero missing items in fault tests | Kill/restart, disk-full and restore corpus |

These are proposed pass/fail budgets, not claims of measured performance. Large/complex books get separate preparation indicators; do not falsify responsiveness by hiding a blocking import behind an unbounded spinner. External AI latency and LAN throughput are measured distributions, not guaranteed app service levels. The flat, shadow-free surfaces of Section 4.4.4 are chosen partly so that scrolling the Library and Thoughts at catalog scale does not spend its budget on compositing.

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

**UI/contract tests:** import all supported routes, save and reopen captures, provider consent, source removal, restore and accessibility. Contract tests run the phone's client fixtures against the Mac server and a fake future-server implementation of the same schema. Provider tests must include streaming and nonstreaming compatible endpoints with missing optional capabilities.

**Design conformance tests:** snapshot tests for every component in Section 4.4.7 in light, dark and grayscale, at the default and largest accessibility Dynamic Type sizes; a token contrast check in CI; a vocabulary conformance test that walks every state machine's user-visible strings; lint that rejects literal colors, sizes and status phrases outside the design package.

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
| T43 | LAN permission denied and Tailscale/manual host | Clear remediation; manual route supported; no dependence on multicast or public ports |
| T44 | Remove all original media for a work | Ledger/rating/recommendations/quotes/notes/AI evidence survive |
| T45 | Migration from every supported schema | Integrity and invariant checks pass; failure restores/reopens recovery snapshot |
| T46 | Corrupt/newer/malicious backup | Existing library untouched; no traversal; precise unsupported/corrupt error |
| T47 | Export during edits/restore crash | Consistent snapshot; leased blobs retained; atomic final restore/recovery |
| T48 | EPUB/note/provider prompt injection | No tool execution, external fetch, automatic metadata change or secret exposure |
| T49 | Inspect logs, export, crash diagnostics | No credentials/content/PII by default; user reviews diagnostics export |
| T50 | Locked/rebooted device file access | Protection policy honored; no disabling protection to fix background behavior |
| T51 | VoiceOver/Dynamic Type/reduced motion | Core import/read/listen/capture/search/restore flows usable at every text size up to the largest accessibility size; no clipped labels in capture sheet, player, Inbox or Thoughts; Reduce Motion removes all non-opacity animation |
| T52 | Every save/import/network failure UI | Draft preserved; truthful status; actionable retry/cancel and no duplicate commits |
| T53 | Grayscale and Increase Contrast pass | With Color Filters set to grayscale and with Increase Contrast on, every capture kind, status pill, availability badge and button role in Section 4.4 remains distinguishable by glyph, label, typeface or frame; snapshot comparison against the color baseline shows no information carried by hue alone; hairline rises to 24% under Increase Contrast |
| T54 | Status vocabulary conformance | Every user-visible state string across Sections 8.2, 10.2, 11.3, 14.4, 15.5 and 17.2 comes from the design package vocabulary; forbidden phrases in Section 4.4.6 are absent from all UI targets; "Saved" is rendered only after the durable commit callback (ties to T02); no literal color, font size or status phrase exists outside the design package |

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

## 21.2 Milestones and acceptance gates

| Milestone | Deliverables | Dependencies | Exit demonstration |
| --- | --- | --- | --- |
| M0 - Feasibility and design freeze | G0.1-G0.6, threat model, interaction prototype, dependency lock, ADRs, `SylviaDesign` v0.1 (tokens, type roles, marker set, status vocabulary, component shells) | None | Team approves supported scope, contracts and design tokens |
| M1 - Durable foundation | Domain, repositories, schema, file store, manual works, migrations, recovery journal | M0 | Offline records/capture fixture persists through faults |
| M2 - Direct ingestion | Files/share/AirDrop/URL, multi-file order, manifests, minimal metadata, import recovery, Inbox using the status vocabulary | M1 | J-01 import portion; T06-T14; T54 for import states |
| M3 - Reading and knowledge | EPUB/PDF/TXT views, capture/comments/lookup, anchors, Thoughts and FTS, all screens composed from `SylviaDesign` | M1-M2 | J-01 complete; same-asset anchor tests; design review on device including grayscale |
| M4 - Audio learning | Player, system controls, timeline, durable clips, safe preview, progress, mini-player with capture control | M1-M2 | J-02 without AI; locked-device and clip tests; T54 for capture states |
| M5 - Contextual AI | Provider setup, consent, evidence packs, retrieval, streaming, optional transcription, Generated marker and citation chips | M3-M4 context contracts | J-02/J-03; provider and grounding evaluation; T54 for AI states |
| M6 - Mac/LAN/cable delivery | Source companion using shared tokens, pairing, manifests/ranges, queue/receipts, wired bundle UX | M1-M2 and M0 security gate | J-05 including >4 GiB and adverse conditions |
| M7 - Lifelong record/recovery | Ledger polish, ratings/recommendations, retention controls and impact report, export/restore UX | M3-M6; backup foundations begin in M1 | J-04/J-06; no knowledge loss |
| M8 - Release hardening and pilot | Full matrix, accessibility, performance, migration/recovery drills, TestFlight/review docs, T53/T54 across every screen | M1-M7 | All P0 gates plus product pilot review |

M3 and M4 can proceed in parallel after domain/anchor contracts stabilize. M6 can proceed in parallel after the importer and protocol contracts stabilize. M5 must not invent new capture identities independent of M3/M4. Backup infrastructure starts in M1 even though its final user experience is accepted in M7. No screen is built before `SylviaDesign` v0.1 exists; screens built against it in M2 through M7 pick up token corrections without rework.

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
Docs/ADRs/                     # approved architecture decisions
Docs/Design/                   # design boards: rendered images, board source, render script, review notes
Docs/Runbooks/                 # import, restore, source and release procedures
```

Keep application deployment targets separate from the development SDK. Commit resolved package versions, dependency license inventory, fixture licenses, the Literata font license and CI toolchain configuration. Use no private platform API or undocumented app-service endpoint to make a user story appear complete.

## 22.2 Build and CI

Require domain/unit/schema tests on every change; integration and simulator UI smoke tests on merge; scheduled full provider/transfer fixtures and physical-device regressions on release candidates. Use macOS CI for Apple targets. Pin test server behavior and run fault injection deterministically before doing live provider smoke tests.

CI must lint contracts, validate all JSON fixtures, enforce migration sequencing, scan for bundled secrets, verify package licenses, check every token pair in `Contracts/design/` for contrast, and reject literal colors, font sizes and status phrases in UI targets. Snapshot tests for the design package run on every change. Use real Keychain/platform adapters only in targeted tests; never expose production credentials to untrusted pull-request code. TestFlight signing/distribution is restricted to release maintainers.

## 22.3 Definition of done for a work item

A completed issue contains the requirement/test IDs it satisfies, implementation and user-visible behavior, negative-case tests, logging/privacy review, accessibility implications and any schema/contract migration. No TODO or stub may stand in for an advertised capability. Add demonstration steps for physical-device behaviors and verify that failure messaging matches the actual state machine and uses the vocabulary's strings. A screen is not done until its snapshots pass in light, dark and grayscale.

AI-generated code receives the same review. A coding agent must not change release scope, weaken TLS validation, disable data protection, substitute a web wrapper for native reading, hard-code a developer API key, introduce a color, size or status phrase outside the design package, or rewrite a dependency to bypass a failed test without an approved ADR.

## 22.4 Required execution artifacts

Before the end of M0, produce ADRs for platform baseline, persistence, reader adapter, audio/timeline/excerpt strategy, pairing/transport security, AI/context privacy, retention/backup, and the design language (final token values, Literata bundling and licensing, Dynamic Type mapping, grayscale conformance method). Generate full schemas and OpenAPI from the proposed contract descriptions, and the design token export from Section 4.4; do not treat Appendix A's examples as an already complete schema implementation.

Before release, deliver install/setup instructions, source/import support matrix, backup/restore runbook, known limitations, provider configuration guide, privacy/permission text, fixture/test results, accessibility report including the grayscale pass, redacted diagnostics guide and a signed release checklist. Include instructions for a reviewer to test every golden journey without relying on the developer's home network.

# 23. Review decisions and risk register

## 23.1 Decisions to approve before execution

These are focused review decisions, not requests to repeat the completed discovery questionnaire. Defaults let the team assess a concrete plan; a changed decision must update affected estimates, acceptance tests and ADRs.

| Decision | Proposed default | Decision owner / consequence |
| --- | --- | --- |
| D01 - Platform floor | iOS/iPadOS 18+, macOS 14+; iPhone-led, functional adaptive iPad | Product + technical lead; affects APIs/test matrix |
| D02 - Core stack | SwiftUI, Readium EPUB, PDFKit, AVFoundation, GRDB/SQLite | Technical lead; confirm versions after M0 |
| D03 - Lock-screen capture | Standard playback required; dedicated capture gated, not assumed | Product + audio lead; explicitly approve ideal-story narrowing |
| D04 - Audio words | Durable excerpts plus optional short-clip endpoint transcription; no full transcription | Product + AI/audio; test speech configuration complexity |
| D05 - Supported formats | EPUB/PDF/TXT/Markdown and tested MP3/AAC-based audiobook matrix | Product + QA; publish actual codec/container list |
| D06 - Device state sync | None in v1; Mac transfer does not synchronize progress/notes | Product; prevents accidental sync scope |
| D07 - Pairing | High-entropy code/link plus optional QR and pinned trust; short-code PAKE only if separately reviewed | Security + transfer; M0 gate |
| D08 - Local model transport | HTTPS default; narrowly scoped local HTTP opt-in only if validated | Security + iOS; no broad ATS bypass |
| D09 - Retention | Manual audio eviction; permanent knowledge retained; full text independently controllable | Product + persistence; deletion copy and safety tests |
| D10 - Export/restore | Knowledge backup required; replace-with-confirmation restore; unencrypted export warned | Product + security; approve privacy limitation or fund encryption |
| D11 - Organization | Status, work association and search only; no fixed taxonomy | Product; categorization remains open |
| D12 - Ratings/history | Half-star rating, explicit completion, rereads, local recommendation events | Product; export schema and UI semantics |
| D13 - Distribution | Internal/TestFlight first; notarized Mac testing build; no monetization implementation yet | Product + release; public release approval later |
| D14 - Scope sequence | Articles/feeds/newsletters (phases A-C in Section 24), Docker, OCR, Calibre adapter and external-player capture later | Product; preserve roadmap without adding P0 scope. Decide Phase A versus Docker hub ordering and the Phase C feasibility bar |
| D15 - Design language | Marginalia (Section 4.4): Paper/Night grounds, Pine and Ochre accents, six-marker set, Literata plus system faces, three-tab navigation, fixed status vocabulary. Direction chosen by the product owner on 6 October 2026 after reviewing four alternatives | Design + iOS lead confirm token values on devices in G0.6; any change to the marker set or vocabulary is a plan change, not a styling tweak |

## 23.2 Risk register

| Risk | Impact | Mitigation / release condition |
| --- | --- | --- |
| Reading adapter cannot provide robust selection/anchors | Core knowledge loop breaks | M0 sample corpus; adapter spike; no launch without stable same-asset reopens |
| Certificate strategy fails in background downloads | Unreliable or insecure transfers | M0 proof and reviewed alternative; no trust-all fallback |
| Share providers terminate large handoffs | Lost files or false acknowledgement | Durable staging; provider matrix; truthful Files/LAN/wired fallback |
| Original source changes mid-transfer | Corrupted mixed-version audiobook | Immutable prepared version, ETag/parts/final digest; source mutation test |
| Media deletion breaks audio highlights | Highest-priority retention promise fails | Retained excerpt blobs and deletion guard; T23/T44 |
| Models invent passages or misuse context | User trust compromised | Evidence snapshots, quotation validation, scope UI and evaluation corpus |
| Compatible gateway secretly routes externally/runs tools | Privacy or unintended side effects | User-managed disclosure; verified no-tool route; no client tool execution |
| Multi-file/audio edition mismatch | Wrong quote or progress | File-local anchors, explicit association and timeline revisions |
| No backup before phone loss | Permanent record lost | Required export/restore, clear local-only warning and backup visibility |
| Ambiguous source/knowledge deletion | Unintentional data loss | Separate commands, reference checks, trash and explicit destructive review |
| 5,000+ library becomes blocking | Poor adoption despite working features | Lazy metadata, incremental processing, performance gates |
| Scope expands into a general feed/agent platform | Delayed core validation | Explicit v1 boundary; architecture seams only; change-control requirement |
| Dependency/API policy changes | Build or distribution disruption | Exact version lock, source review at kickoff/release, compatibility fixtures |
| Name/distribution rights not cleared | Public launch delay | Product/legal review; Sylvia is chosen, but this plan is not brand clearance |
| Design tokens drift per screen; status phrases invented ad hoc | Quote/note/generated distinction erodes; "Saved" and "Ready" lose their meaning | Single design package, lint and conformance tests (T53, T54); vocabulary change control in 4.4.9 |
| Literata or Dynamic Type scaling fails on the oldest device | Reader or capture sheet unusable at large text sizes | G0.6 on the oldest supported iPhone; system-face fallback for UI roles; reading face always user-switchable |

## 23.3 Review sign-off

Product approves scope, experience boundaries and retention language. Technical leads approve architecture, contracts and migration strategy. Security approves pairing, endpoint/content isolation and exports. QA approves fixture coverage, device matrix and failure tests. Design approves capture/accessibility flows, the Marginalia token values after G0.6, the marker set and the status vocabulary. Release owner approves distribution and privacy declarations.

Approval should result in a versioned 1.0 execution specification and prioritized backlog. This review draft is not authorization to implement unapproved speculative features or to skip feasibility gates.

# 24. Roadmap seams without building the roadmap

**Docker hub (v1.5 candidate):** implement the same source/manifest contracts as the Mac, add an always-on ingestion inbox and authorized agent-delivered assets, then design actual state synchronization separately. Server authority, managed versus referenced storage, metadata conflict rules and household profiles are not settled by this v1 document.

**Articles, feeds and newsletters - the unified content hub (post-v1, phased).** Product intent from the product owner (7 October 2026): content from many disparate systems - bookmarks, a standalone Substack app, RSS readers - should have one home in Sylvia, with the same permanent record of notes and questions that books get, and without relying on another service to synchronize that content or its context across devices. This is a stated goal for later releases; none of it is in v1 scope (Section 3.3).

*Phase A - Saved articles (first post-v1 release).* The share extension and URL entry accept a webpage link and create an **Article** work kind: sanitized readable text and an HTML snapshot with provenance (source URL, publisher, author, published and saved dates, fetch time). The article opens in the existing reader and uses the same capture, note, Ask AI and search flows. When the page or its feed entry exposes an audio version (for example a Substack post's "listen" link or an enclosure), record it as an `AssetLocation` of kind remote-audio, with the URL and provenance. The player offers it as an explicit stream-or-download choice and never presents it as a local file until downloaded. Pasting one Substack article link therefore ends in the Inbox, readable and listenable later, with no bookmark folder or separate app.

*Phase B - Subscriptions.* Add recurring Source adapters for RSS/Atom, including public Substack publications (their `/feed` addresses and per-post audio enclosures). New entries arrive in the Inbox as **Unread** items. Refresh runs on app open and on iOS background refresh, which the system schedules opportunistically; the interface must say when a feed was last checked and must not promise always-current delivery. An always-current Inbox is a property of the Docker hub or Mac companion (v1.5 candidate, above), not of the phone alone.

*Phase C - Paid and authenticated sources.* Paid Substack posts, other paywalled newsletters and email forwarding/IMAP each need their own authentication, security and terms-of-service review before any commitment. Substack offers no public API for a reader's paid subscriptions, so this phase is a feasibility question, not a scheduled feature. Never ask the user to hand over a password, and never scrape behind a login without a documented, authorized route. Email/IMAP/forwarding is a different integration from RSS.

*Rules that apply to every phase.* Keep arrival, read status, deliberate retention and saved knowledge separate: a feed arrival is Unread, not a consumed work; only a user action ("Keep") makes it a retained Work, and unread items may expire under a user-visible policy. Notes, questions and quotes on an article persist after the snapshot is removed, per invariants I-03 and I-08. Respect publishers: fetch only what the user subscribes to or saves, honor robots/terms for fetching, and keep snapshots private to the user. Duplicate detection uses canonical URL plus content hash. A new work kind receives a marker only through the process in Section 4.4.9; Article does not borrow Quote or Note. The Inbox grows beyond transfer states (Section 4.1) to include Unread, Saved and "Listen available", and Section 4.4.6 gains those words only through the same process.

*Requirement stubs for later backlog (not scheduled):* ART-01 save a link as an Article with snapshot and provenance; ART-02 capture and play a source-provided listen link; FEED-01 subscribe to RSS/Atom and populate the Inbox; FEED-02 public Substack subscription; FEED-03 retention and expiry of unread items; FEED-04 duplicate handling across feed and one-off saves; SRC-01 authenticated-source feasibility study.

**Physical reading:** add camera/photo capture and OCR as another producer of captures/anchors. Preserve image/text confidence and manual page correction. An image-only PDF in v1 must not be misrepresented as already supporting this flow.

**External players:** investigate documented metadata/control APIs and policy constraints per service. Do not inherit earlier speculative assumptions about automatically hearing Spotify or tracking every audiobook. External audio capture requires independent technical and authorization review, not a generic plugin hook.

**Alignment/transcription:** add full-book asynchronous speech processing and edition-aware audio/text alignment after durable capture is proven. Store alignment confidence and provenance; preserve manual association and no-context modes.

**Broader platforms:** reuse exported schemas, test fixtures, the transfer protocol and the exported design tokens in `Contracts/design/`; implement native platform adapters. A portable data model and token file are an investment in future clients, not a claim that a single Swift package will run every platform unchanged. The grayscale conformance work in Section 4.4.8 also prepares the language for reflective e-paper tablets, which are a plausible later target.

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

Production anchors also bind to the asset digest. For PDF, replace the reader locator with page/label/text-range/geometry data. For audio, `quoted_text` is absent unless a labelled transcript/user quotation exists, and `anchors` contain file-local start/end milliseconds. Never make fake text mandatory to fit an audio capture into a quote schema. The `kind` field maps one-to-one onto the marker set in Section 4.4.5; a client renders a capture it does not recognize with the Pending marker and its raw kind label, never as a Quote.

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

Production packs include exact evidence snapshots/digests, selected endpoint/model identity without credentials, budget accounting, spoiler boundary and any included conversation turns. Only `c1` can become a resolved source citation for this example; an invented `c99` cannot link into the broader library.

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
TransferService.enqueue(sourceItemVersion) -> TransferJobID
RetentionService.previewRemoval(assetID) -> ImpactReport
RetentionService.removeDownload(approvedImpact) -> RemovalResult
BackupService.export(snapshotOptions) -> VerifiedExport
BackupService.validateRestore(bundle) -> RestorePlan
```

Mutating calls return typed errors and durable state, not booleans that hide partial completion. Command idempotency is local and under Sylvia's control; it does not imply that a remote model provider honors the same key. UI reads observable projections rather than directly mutating service internals, and renders each projected state with the vocabulary string for that state.

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
    "note":      {"text": {"light": "#2F5D50", "dark": "#7FB5A3"}, "glyph": "pencil", "label": "NOTE"},
    "audio":     {"text": {"light": "#3F5A78", "dark": "#8FB0D4"}, "glyph": "waveform", "label": "AUDIO"},
    "generated": {"text": {"light": "#6B4E8E", "dark": "#B49BD6"}, "glyph": "chevron.right.underscore", "label": "GENERATED", "frame": "dashed"},
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

The export is generated from the Swift package, not hand-maintained; glyph names are SF Symbols identifiers with documented equivalents for other platforms. Tints marked "derived" in Section 4.4.2 appear here only once set in the asset catalog.

# Appendix B. Source notes and technical references

[P1] **Product basis:** *Sylvia - Product Brief*, October 2026, and the product decisions in the accompanying discussion. The brief establishes standalone native iOS plus a Mac companion, permanent knowledge, reliable import, Work -> Edition -> Asset, 5,000+ scale and optional providers. RSS/newsletters were subsequently raised as a compatible roadmap direction, not an approved v1 requirement. The transcript supersedes the brief where a later user decision is explicit.

[P2] **Design basis:** *Sylvia Concept Designs*, 5-6 October 2026, checked in under `Docs/Design/` in this repository: rendered boards in `images/`, board source in `canvas/`, and a README that maps each board to its plan section. Contains the Marginalia design-language sheet, thirteen iPhone screens, an iPad reader with Thoughts pane, the Mac companion window, two Inbox row-layout options, and the six iPhone screens plus the tablet reader rendered in grayscale. Four palette alternatives were reviewed on 6 October 2026 and removed after the product owner confirmed Marginalia. The boards were authored on a design canvas private to the product owner; the checked-in export is the citable reference, and Section 4.4 is the specification.

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

[S24] **Apple: UIFontMetrics** - scaling custom fonts with Dynamic Type against a text style. Added 6 October 2026. https://developer.apple.com/documentation/uikit/uifontmetrics

# Appendix C. Final release checklist

Approve the versioned scope and decision register. Pin the SDK/dependencies and pass all Stage 0 gates. Demonstrate all six golden journeys on real devices. Pass every P0 acceptance case, including source deletion and restore. Resolve all critical/high privacy, data-loss, security and crash defects. Record any gated-feature exclusions in user-facing release notes rather than hiding them.

Verify source/capture fidelity, no false ready/saved states, no unexpected provider transmission and no leaked credentials. Complete the compatibility matrix, accessibility pass including the grayscale and Increase Contrast pass (T53), the vocabulary conformance run (T54), catalog-scale measurements and backup/migration drills. Validate the application without a server, Mac, model subscription or developer account configuration.

Complete privacy/distribution review, licensed sample content, support documentation and pilot feedback review. The final go/no-go question is not whether every component exists: **can a user reliably turn a reading or listening moment into knowledge they can find and trust later, even after the media is gone?**

# Appendix D. Change log

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

**Draft 0.3 - 7 October 2026.** Roadmap-only change at the product owner's request. No v1 scope, security, data-model or transfer-protocol decision was changed.

- Section 24: the RSS/newsletter paragraph is replaced by the unified content hub roadmap (Phases A-C: saved articles with listen links, subscriptions including public Substack, authenticated sources), shared rules and requirement stubs ART-01/02 and FEED-01 to FEED-04, SRC-01.
- Section 3.3 and decision D14: wording updated to point at that roadmap.
