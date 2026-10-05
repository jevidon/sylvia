<!-- Converted from Sylvia_Product_Brief.docx (original kept alongside). Edit either, but keep them in step. -->

# Sylvia

**SYLVIA / PRODUCT CONCEPT · OCTOBER 2026**

*Your library of thought.*

A lifelong record of what you read, hear, learn, question and keep.

> **The 30-Second Pitch**
>
> Sylvia is a native reading and listening app built around a simple idea: the file is temporary, but what you learn from it should last. Read an EPUB or PDF, listen to an audiobook, capture a passage, add your own thinking and ask questions using the context available from the work. Sylvia keeps a permanent, searchable record of the books you consumed and the ideas you took from them - even after large media files are removed. It works standalone on your device, with optional Mac transfer, self-hosting and user-chosen AI services.

## The problem

Reading and listening are fragmented across Kindle, audiobook players, Calibre, media servers, notes apps and AI chat. The act of consumption happens in one place; highlights, questions, explanations, recommendations and personal reflections end up somewhere else - or disappear entirely. Existing tools tend to optimize for access to the media, not for preserving the understanding that grows around it.

## The value proposition

- Keep a lifelong consumption ledger: titles, progress, completion, personal ratings, who recommended a work to you and who you later recommended it to.
- Capture ideas without breaking the flow: highlight text, clip an audio moment, add a comment, look up a word or ask a question.
- Keep context attached: passages remain linked to the source, edition, page, chapter or timestamp that produced them.
- Use AI as a contextual learning tool, not an isolated chatbot. Ask about the current passage, chapter or full book when the source is available, and retain the resulting question, answer and supporting context.
- Own the experience without depending on a server. The core app remains useful offline; self-hosting, remote models and cloud AI are optional enhancements.

## Why Sylvia

The name traces back to Latin silva - “forest” or “wood.” The metaphor is a growing personal forest of knowledge: every book, passage, question and reflection can become another branch in a body of understanding that develops over time. Sylvia is not intended to be a media warehouse; it is the place where what you consume becomes part of what you know.

---

**SYLVIA / PRODUCT HYPOTHESIS**

## A concrete experience

Import an EPUB and its audiobook. Read on a flight, listen on a walk, and save a passage with a note about why it matters. Ask your configured AI to explain the idea or connect it to something you encountered earlier. Finish the book, rate it, record that you recommended it to a friend, then remove the large audio file to free storage. Months later, search Sylvia and return to the quote, its context, your note and the questions you asked.

The same knowledge layer can eventually extend beyond files stored inside Sylvia: photograph a page of a physical book and ask about the captured passage, or track an externally played audiobook where platform access allows. The quality of AI context degrades gracefully when the full work is unavailable rather than making the feature unusable.

## Initial audience hypothesis

Start with engaged readers and audiobook listeners who use books for learning, research or professional growth; already save highlights or notes; and value retaining a durable record of what they consume. Self-hosters and local-AI users are a promising early subset, but Sylvia should not require either self-hosting or local models to be useful.

## Proposed launch path

**V1 -** Native iOS app + lightweight Mac companion.

- EPUB/PDF reading focused on passage selection, highlights and context rather than rich document markup.
- Common audiobook formats, including multi-file books represented as one logical title.
- Offline local library, permanent reading/listening ledger, annotations, ratings, recommendation history and saved AI interactions.
- Direct import via Files/share sheet/AirDrop/URL plus dependable LAN and wired transfer from Mac.
- No mandatory account or backend. English and DRM-free/user-controlled files first.
- AI connects to a user-chosen hosted provider or OpenAI-compatible/local endpoint; Hermes integration remains optional.

**V1.5 -** Optional self-hosted Docker hub.

- Always-on catalog and media store for large collections, with Calibre as a possible e-book source rather than a required canonical database.
- Inbox for files, URLs, recommendations and agent-delivered content while the phone is offline.
- Background metadata extraction, indexing and later transcription/alignment workflows.
- Hermes or another agent may locate an authorized copy of requested content and deliver it to the hub for ingestion.

## Non-negotiable product principles

- Local-first, server-optional. A user can use Sylvia indefinitely on one device without creating an account or running infrastructure.
- Reliable transfer is a core product feature: resumable jobs, verification, retries, clear state and no half-complete books masquerading as finished imports.
- Work -> Edition -> Asset separates the intellectual work from the file that represents it. A work can have an EPUB, audiobook, companion PDF or external consumption source.
- Deleting source media - especially large audiobooks - must not delete the permanent ledger, highlights, quoted text, notes, recommendations or saved AI context.
- The architecture should comfortably support 5,000+ titles and sizable server-retained collections, while leaving room for iOS-first development to expand to Android and other platforms later.

## Feedback requested

1. When did you last lose a useful passage, note or question across reading/listening apps? What did you do instead?
2. Which part of Sylvia would change your behaviour most: the permanent history, easier capture, contextual AI, or one place for reading and listening?
3. Would importing your own files and configuring an AI connection be acceptable, or would either create too much friction?
4. What would Sylvia need to replace - or work alongside - for you to use it every week?
5. Would you try it with a real book or audiobook? What would make the product worth paying for?

**The key test: do people return to the knowledge they saved after they finish a book?**

*Working product brief - concept stage. Feature sequencing, pricing and business model remain open.*
