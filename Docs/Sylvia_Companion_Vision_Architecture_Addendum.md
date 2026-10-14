# Sylvia
## Companion vision and architectural guardrails

**Prepared:** 12 October 2026  
**Revised:** 15 October 2026 (sequencing aligned with the standalone Gloss UX and roadmap revision)\
**Status:** Proposed architecture addendum for review, not an expanded V1 implementation mandate  
**Baseline reviewed:** *Sylvia_v1_iOS_Implementation_Plan.md*, team-review draft 0.1, 5 October 2026  
**Scope authority:** The latest user direction is to keep V1 at its current scope. Nothing here promotes a deferred capability into V1 or resolves an existing open decision about AI, transfer, platform support or release delivery.

> **Sylvia should preserve what a person takes from a work, regardless of where they read or listen. It must distinguish that retained knowledge from access to the underlying work.**

This is a standalone supplement. It does not overwrite the original implementation plan. The baseline's relevant architecture and roadmap sections were reviewed; no application repository, runtime, connector or migration has been audited or tested for this addendum.

**Current planning reference:** the 15 October implementation-plan revision adds Gloss-informed M3/M5 passage interactions and a later web reader while keeping native iOS/iPadOS V1 first. The native feasibility components, contracts and design prototype reviewed on `m0-integrate` remain separate, unmerged work linked in plan [P3]; their integration and M0 approvals are not part of this documentation revision. This update does not expand the future capture capabilities below.

---

## 1. Product decision

Sylvia has two complementary long-term roles: a native reader/player for supported files, and a knowledge companion for works consumed elsewhere. Both should contribute to one library and one permanent record, rather than separate “real books” and “external notes” products.

A person could read a physical book, use a Kindle edition, listen to an externally hosted audiobook, or play a podcast in another app. They should eventually be able to retain selected passages, clips, observations and reading/listening history in Sylvia without importing the complete work or replacing their existing reader/player.

The promise is **equal standing for the user's knowledge, not identical access to source content**. A photographed passage deserves the same ability to be found, annotated, revisited and exported as a native EPUB highlight. It does not establish that Sylvia can search the rest of the book. Likewise, a saved episode clip does not establish access to the episode's other audio, transcript or playback history.

The prospective companion-mode value is consequently specific: keep a useful passage or moment, connect it to the correct work, preserve one's reaction, retrieve it later, and use that actual evidence in a source-aware question. AI extends this value; reliable capture and retrieval must remain useful without it.

## 2. Release boundary

### V1 remains the existing project

Continue the current native reading/listening and retained-knowledge plan. Do not add a podcast client, subscription management, page-photography workflow, external-player clip importer, account connectors, automatic outside playback observation or cross-platform progress synchronisation to satisfy this addendum.

The reviewed draft already describes metadata-only physical/external records and manual ledger positions in Sections 7 and 12. This addendum neither expands nor removes that baseline facility. It also does not settle whether an optional or previously proposed AI capability belongs in the final release. The latest explicit scope decisions take precedence over the older review draft.

Architecture readiness means preserving appropriate boundaries, identifiers and data ownership. It does **not** mean implementing every future table, adding unused screens, shipping provider stubs, or designing a universal plugin runtime before V1.

### Future capabilities under discussion

The long-term vision includes native podcast subscriptions/listening and a separate ability to capture insights from other players. It also includes imported screenshots, physical-page photographs, selected quotations, notes and service references. Each future intake route must establish exactly what it received before offering further capabilities.

DRM circumvention is not a dependency or proposed feature. No claim is made here that a particular service permits export, third-party analysis, transcript retrieval or content copying. Those are separate, per-service technical and authorisation checks at the time of implementation.

## 3. What the existing architecture already provides

The important foundation is present in the written plan; this is not a proposal to replace it. [P1]

| Existing plan element | Relevance to companion mode | Clarification to preserve |
| --- | --- | --- |
| Work → Edition → Asset, with separate locations | Bibliographic identity need not depend on local bytes | A work can exist with no imported media; an edition need not have an available full asset |
| Source / SourceItem and metadata provenance | Outside identities and observed source information have a home | A source reference is not proof of content availability or permission |
| Capture / CaptureAnchor, Note / NoteRevision | Native and external knowledge can converge | Keep edition-specific locations and separate captured wording from the user's comments |
| RetainedExcerpt and durable knowledge storage | A useful fragment can survive media removal | Future images and imported clips need the same preservation semantics |
| ContextPack / ContextEvidence | Answers can preserve their actual input evidence | Full media availability, indexed coverage and evidence sent are separate facts |
| Versioned locators, migrations and exports | New capture types can be introduced later | Unsupported kinds must not be silently discarded or mislabelled |

Sections 7, 10–13 and 24 are the relevant baseline sections. The substantial addition in this discussion is a clearer common capture contract and an explicit podcast show/episode/subscription distinction, not another competing library model.

## 4. The shared knowledge model

### 4.1 A work is not a file, and a source is not an asset

Retain **Work** as the durable intellectual identity. Retain **Edition** for the particular publication, translation, narration or other relevant version. A Work-level note can be saved without a precise edition. Where an edition is unknown, leave it unresolved rather than inventing one.

Retain **Asset** as an identified byte representation. A full EPUB, a retained photograph and a short audio clip can all have bytes, but their roles differ. A photographed page is evidence of a fragment, not the native digital edition of the complete book. The ability to display that photograph must not activate “Read full book”.

Retain **Source / SourceItem** for external identifiers, origin and references. Distinguish the source work or platform from the intake mechanism. For example, a passage may have been read on an e-reader, photographed with a camera, then imported through Photos. Those are not three different works. Store a claimed source app only when supplied or confirmed; do not invent it from an image's appearance.

### 4.2 Separate the original, its extraction, the user's thoughts and AI output

A future capture should be able to retain these independently:

**Original evidence:** the selected source text, imported image, retained audio/video clip, or user-provided attachment. Preserve the accepted original locally unless the user explicitly chooses to remove it.

**Extraction:** OCR or transcription output, linked to the exact input and processing version. Keep raw output and user-corrected revisions distinct. A correction must not silently rewrite an earlier saved conversation's evidence.

**User annotation:** the reader's comment, a confirmed transcription of their margin note, or a voice note recording their reaction. The author's words and the user's reaction must never be flattened into one unattributed quotation.

**Derived interpretation:** an AI summary, suggested theme, proposed link or imported machine-generated explanation. Label it as derived and retain its supporting evidence references. It must not acquire the status of source text merely because it was saved.

Conceptually these fit the existing Capture, Note, TextDocument/processing and ContextEvidence boundaries. Optional future records such as CaptureAttachment or ExtractionResult are design options, not instructions to create new V1 tables. Use normalised relationships where these concepts require independent identity and lifecycle.

### 4.3 Preserve locators at their true level of certainty

A native text anchor can identify an exact range in an asset. A photographed passage may identify a region in an image and a printed page label. A podcast clip can identify a range in the retained clip while its position in the full episode is unknown. A general reflection needs no invented page or timestamp.

Retain Work identity for organisation, but bind precise locations to the relevant edition, asset or observed external source version. Store whether a location was supplied by an app, entered by the user, machine-suggested or user-confirmed. Missing information stays missing.

When later importing another edition, offer candidate connections without moving the original locator or replacing it. A matching paragraph does not prove equivalent page numbering or synchronised audio progress.

### 4.4 Save first; resolve uncertain identity later

A future capture inbox should preserve a durable draft even when the title or episode is unknown. After saving, the user can attach it to an existing Work or confirm creation of a new one.

Keep unresolved identity in a **draft/intake state**, rather than forcing an “Unknown Book” into the permanent library or making every established Capture relationship nullable. This is a proposed future workflow, not a new V1 inbox requirement.

## 5. Future capture workflows

### 5.1 Photographing a physical book

The intended interaction is: choose or photograph a page, save it, identify the work when practical, and review the selected passage and any extracted annotations. Saving the image must not depend on successful OCR, network access or completion of metadata lookup.

Apple's Vision APIs provide text recognition and text-region observations, which are useful building blocks for the later extraction adapter. They do not by themselves constitute Sylvia's intended-marking review workflow. [S1]

Sylvia should separately propose printed text, selected/highlighted regions and handwriting interpretation, and allow the user to confirm or correct them. The first future implementation should remain useful when the user manually crops/selects the relevant region or types the margin note. Automatic understanding of underlines, arrows and difficult handwriting must be treated as a capability to test, not a guaranteed property of OCR.

Store the original accepted image, the selected image regions, extracted text, confirmed selections, user notes, source snapshot and the page label when known. A photographed page number is not the same as an image index or an EPUB position. An unresolved page remains unresolved.

Later, a question such as “What did I note about this idea?” can use the saved selections and comments. “Explain the argument in all of chapter seven” requires that chapter's evidence; a single page is not enough.

### 5.2 Importing a screenshot or selected quotation

Use the same capture and evidence model, with an intake-specific adapter. Where the source permits a user export, accept the actual material provided: text, image, attachment, metadata or reference.

Distinguish a literal selected quote from a paraphrase, summary card or remembered note. A screenshot may have incomplete title/page information. Suggestions can assist matching, but uncertain attribution requires review.

A service link alone should create a reference with optional user commentary. It must not manufacture a quotation or imply that the linked book's text has been imported. Source-content retrieval, where authorised and technically supported, is a separate operation with its own result and provenance.

### 5.3 Importing a podcast clip from another player

The intake must inspect the shared representation. Apple's sharing architecture passes host-provided items to an extension; NSItemProvider is the mechanism for conveying offered data or files. Therefore the design must work from what the exporting app actually supplies, not from an assumption that “Share clip” always transfers audio and a complete metadata bundle. [S2]

| Material actually received | Sylvia's honest initial result |
| --- | --- |
| Audio file | Retained, replayable clip; transcript can be requested through an eligible future processor |
| Video-wrapped clip | Retained attachment; audio extraction is a separately implemented and tested capability |
| Text transcript or quotation | Saved text, with its reported or confirmed origin and location |
| Image/quote card | Saved image; extraction requires the future image pipeline |
| Episode link and timestamp | Source reference and supplied position, not preserved audio |
| Link only | Reference with optional user note; no invented timestamp or spoken words |

Where available, preserve the show, episode title, publication date, source URL/ID, duration, speakers and original episode range. Treat omitted fields as unknown and supplied metadata as attributed information, not independently verified truth. User speech and episode speech must remain distinguishable.

For retained media, **clip-local time and episode time are different coordinate systems**. A 40-second clip has its own start at zero; it may also have an observed source range elsewhere in the episode. Preserve both and their relationship only when known. If a later episode asset differs, including its edit or advert placement, do not reuse that mapping without validation. The retained clip remains the reliable evidence for the original capture.

OCR/transcription and optional enrichment should follow the durable save. Failed extraction or identification must leave the clip and the user's note intact. Imported snippets must not mark the episode finished or assert that Sylvia observed the user's external listening session.

## 6. Podcast subscriptions are a separate capability

Podcast capture should not require a full podcast client, and following a feed should not require listening in Sylvia. Preserve that separation in the roadmap.

For future native support, use a **Series/Show** container, **Episode Works**, and a separate **Subscription** relationship. Each episode is an intellectual item with its own captures, listening history and assets; episodes are not editions of the show. Editions or source variants describe different representations of that episode. A publisher transcript should retain its own origin and attachment/extraction relationship rather than being silently treated as user-authored text.

Apple's feed requirements distinguish episode GUIDs from media enclosure URLs. The Podcast Namespace also defines an episode-level transcript link. Those are useful inputs to a future feed adapter, not evidence that every source exposes every field or that a shared player link contains them. [S3, S4]

Use Sylvia-owned internal identities. Record observed feed identity, feed-scoped episode identifiers and provider aliases separately, so matching does not depend solely on a title or a changing media URL. Proposed cross-provider matches require confirmation when ambiguous.

Keep subscription state, the episode discovery catalogue, media downloads, the user's listening queue, consumption records and deliberately retained knowledge separate. Arrival in a subscribed feed must not automatically count as consumption or fill the permanent knowledge ledger. An episode with saved captures must survive feed removal or unfollowing.

No feed polling, OPML handling, podcast discovery, subscription screens, episode queue or outside progress synchronisation is added to V1 by this design.

## 7. Evidence-aware search and AI

### 7.1 Track three different scopes

**Available material:** what Sylvia currently holds or can access, such as metadata, retained images, clips, selected text or a full file.

**Processed coverage:** what has actually been extracted and indexed, including missing pages, transcription status, unresolved image regions and processing failures. A full audio file without a transcript is not automatically searchable text. Direct audio/image reasoning requires a separately supported model capability.

**Request evidence:** the exact selections and representations sent for this particular answer, including revisions, original anchors, quality labels and truncation. Having indexed a book does not mean the entire book was supplied to the model.

These are not mutually exclusive “native / external / physical” modes. One Work can have a full EPUB, a physical-page photo, an external listening reference and several retained clips at the same time. Calculate capabilities from the evidence and permission available, rather than one permanent access-mode flag.

### 7.2 Make the scope legible

Appropriate interface descriptions would include “Saved excerpts only”, “3 page photographs; 2 reviewed text extractions”, “Clip available; transcription not complete”, or “Relevant passages retrieved from this edition”. Only show counts and coverage that the system actually knows.

Preserve the baseline ContextPack: exact evidence snapshots, source identity, request scope, extraction quality, retrieval metadata and truncation. Adding a file later must not retroactively imply that an earlier answer used it. [P1, Sections 11 and 13]

A source-grounded answer can explain a saved passage, compare selected captures or summarise the user's recorded thoughts. It should acknowledge when the question requires uncaptured material. A separate general-explanation mode can draw on model knowledge, but must not present that knowledge as verified content of an unseen book or episode.

Citation targets should open the retained quote, image region or clip range, rather than merely the work's title card. Validate citation IDs against the supplied evidence and check exact quotations. A valid ID does not prove that the evidence supports the claim; later evaluation must test support as well as link correctness.

### 7.3 Preserve the distinction between context and authority

A title, blurb, user note, publisher transcript and generated summary can all be relevant context, but they have different origins. Maintain those labels through retrieval. An imported description of a speaker's views does not become a direct quotation from the speaker.

Treat all imported material as untrusted data. Instructions inside a page, transcript or metadata field must not trigger tool execution, new downloads or changes to provider permissions. Proposed enrichment must be a separately authorised action, never a side effect of text encountered in a capture.

## 8. Retention, privacy and portability

Retained knowledge must have a lifecycle separate from replaceable full media and external account access. Preserve accepted evidence attachments and their provenance with the capture; include them in the appropriate knowledge export/backup when that capture type ships.

Deduplicated bytes may be shared internally, but deletion must follow references and retention intent. Removing a downloaded episode, disconnecting a provider or unfollowing a show must not remove a pinned clip or page image. Conversely, an explicit request to erase retained evidence must account for copies in saved context packs, notes and backups rather than deleting only the search index.

Network extraction, model inference and metadata enrichment need separate, visible controls. A clip may be small but still contain sensitive material. Prefer local processing where suitable; preserve the existing configurable-provider policy and disclose exactly which text, image or audio is being transmitted. Consent to a model call is not evidence that a platform permits that use of its content.

Private-feed credentials and secret-bearing URLs must not be written into ordinary exports, analytics or AI context. Keep credential references separate from historical source metadata. Avoid including unrelated photo metadata in external processing. Default to a private library, not public republication of excerpts.

This addendum establishes product boundaries, not a legal determination about any particular book, service, jurisdiction or reproduction use. A service-specific integration must pass technical, privacy and authorisation review before being advertised.

## 9. V1 architectural review: preserve the boundaries, do not build the future

The review should verify the baseline's existing invariants rather than automatically create new work. [P1]

| Check in the current design | Required property | Not required now |
| --- | --- | --- |
| Work and availability | A work and its knowledge remain valid without local full media | External account connection or new external-capture UI |
| Capture ownership | Captures and notes belong to the library, not to a reader view or download | Camera/OCR or external clip adapters |
| Evidence and notes | Source wording, user edits and generated outputs retain separate origins | Automatic handwriting interpretation |
| Anchors | Versioned, source-aware and honest about missing locations | Automatic paper/EPUB/audio alignment |
| Retention | Media removal does not cascade into saved knowledge | A new cloud archive or sync service |
| Context assembly | Actual supplied evidence and coverage are recorded whenever AI is used | Whole-library research or additional AI features |
| Portable contracts | Future kinds have an explicit migration/compatibility path | Pre-creating the entire podcast schema |

Unknown future record types require a documented compatibility policy: preserve them without enabling unsupported actions, or refuse an incompatible restore before altering existing data. Do not silently discard them. Do not expand V1 export support to formats the release cannot actually create or restore.

Any proposed schema change must identify an invariant the existing design cannot satisfy and the smallest corrective change. New future entities and provider-specific fields can be introduced through tested migrations when their features are approved.

The earlier conversational estimate of “5–10% extra schema work” was not evidence-based and should not be used for scheduling. The written plan suggests useful preparation already exists; actual effort depends on implementation and migration review. No code audit has established that effort here.

## 10. Later acceptance scenarios

These are **future feature tests**, not additions to V1's acceptance gate. Use the subset relevant to each approved workstream.

| Scenario | Expected outcome |
| --- | --- |
| Photograph a page; OCR fails | The accepted image and user note survive; extraction can be retried |
| OCR confuses handwriting with printed text | The user can separate and correct them; no silent attribution as an author quote |
| Share an unidentified audio clip | A durable draft exists; no fabricated episode or forced permanent Work |
| Share only an episode link | Sylvia records a reference; it does not claim to retain audio or know the current position |
| Retry the same intake job after interruption | The durable job completes without accidental duplicate captures; intentional new notes remain possible |
| Import a clip whose original episode position is unknown | Clip replay works; full-episode navigation remains unavailable |
| Later download a different episode version | Existing clip and source observations remain unchanged; alignment requires validation |
| Ask about an uncaptured chapter | Source-grounded mode explains the evidence gap instead of inventing chapter contents |
| Import a generated summary card | It remains labelled as derived material, not original book or episode text |
| Add a full EPUB after photographing pages | Attach it to a confirmed Work/Edition; preserve photo captures and review cross-edition anchors |
| Delete full media or unfollow a feed | Retained captures, notes and consumption history remain available |
| Correct an OCR/transcript revision after an AI answer | Future retrieval can use the correction; the earlier answer's evidence remains traceable |
| Receive a new subscribed episode | Discovery/subscription state updates without asserting consumption |
| Restore with an older client | Explicit compatibility handling prevents silent knowledge loss |
| Attempt cloud processing without the required approval | Evidence remains local and saved; processing does not proceed silently |

## 11. Future sequencing

Treat external capture, podcast subscriptions/native playback, and service-specific integrations as separable workstreams after V1.

The later web reader is another separate workstream, governed by implementation plan Section 24. It can draw on Gloss's contextual reading interface while using Sylvia's versioned captures, evidence, locators and exported Marginalia tokens. Saved-article ingestion and browser-based reading have separate delivery decisions; neither adds a web target, account service or state synchronization to V1. Browser storage, credentials, library exchange and any hub or sync dependency are decisions for that later workstream. Its capture and AI flows preserve the evidence and retention boundaries in Sections 4, 7 and 8 of this addendum.

The proposed first companion workstream should prove one complete capture-to-retrieval loop with real exported material, not start with a universal connector catalogue. Test a bounded physical-page flow or one explicitly supported clip representation. Verify save reliability, metadata ambiguity, provenance, correction, retention and evidence-scoped answers before claiming broad compatibility.

Native podcast subscriptions can then use the same knowledge model while adding the distinct show/episode, feed-refresh and queue responsibilities. Rich external connectors remain optional enrichment; the core companion value should not depend on their continued availability.

The largest unresolved delivery question is how reliably target apps provide useful exports and how much correction a capture needs. That must be tested with real app/OS versions before promising “works with every reader or player”. No vendor compatibility claim has been validated in this addendum.

## 12. Suggested addition to the implementation plan's roadmap section

The following wording can supplement Section 24 after review; it is not an instruction to implement the deferred features:

> **Companion knowledge capture and podcasts — future scope.** Sylvia's Work/Edition, Capture/Anchor, Note, Source and ContextEvidence boundaries must allow later knowledge capture from sources not opened natively. Future adapters may accept authorised user-provided quotations, screenshots, photographed pages and podcast clips, retaining original evidence, extraction revisions, source provenance and uncertain locations. Notes and captures must remain useful without a complete source file. Search and AI must distinguish available source material, processed coverage and the evidence actually supplied to an answer. Podcast shows, episode works and subscriptions are separate concepts; subscription or capture does not establish consumption. No camera/OCR pipeline, external-player importer, RSS subscription engine, service connector, DRM circumvention or cross-service progress synchronisation is added to V1. Introduce additional entities and ingestion capabilities only through separately approved feature work and tested migrations.

---

## References and source boundaries

**[P1] Project baseline.** *Sylvia_v1_iOS_Implementation_Plan.md*, team-review draft 0.1, 5 October 2026. Relevant sections reviewed: 1; 7; 10.2–10.5; 11–13; 24; Appendix A.1–A.2. The baseline is a proposal with open decisions, not proof of implemented behaviour. The present conversation supplies the explicit instruction to avoid expanding V1.

**[S1] Apple Developer Documentation — Recognizing Text in Images; VNRecognizedTextObservation.** Consulted 12 October 2026. Establishes text-recognition and text-region building blocks, not Sylvia's future handwriting or highlight-detection performance.  
`https://developer.apple.com/documentation/vision/recognizing-text-in-images`  
`https://developer.apple.com/documentation/vision/vnrecognizedtextobservation`

**[S2] Apple Developer Documentation — NSItemProvider; App Extension Programming Guide: Share.** Consulted 12 October 2026. Establishes host-provided item/file transfer to extensions. The Share guide is archival platform guidance; validate current SDK and target-app behaviour during implementation.  
`https://developer.apple.com/documentation/foundation/nsitemprovider`  
`https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html`

**[S3] Apple Podcasts for Creators — Podcast RSS feed requirements.** Consulted 12 October 2026. Describes episode GUID and enclosure requirements for feeds submitted to Apple Podcasts; not a guarantee about arbitrary/private feeds.  
`https://podcasters.apple.com/support/823-podcast-requirements`

**[S4] Podcasting 2.0 — Podcast Namespace: Transcript.** Consulted 12 October 2026. Defines links to episode transcripts/captions; does not establish universal availability or permission for every downstream use.  
`https://podcasting2.org/docs/podcast-namespace/tags/transcript`
