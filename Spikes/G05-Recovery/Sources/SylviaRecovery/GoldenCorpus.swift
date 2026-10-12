import Foundation
import GRDB

/// Deterministic pseudo-random bytes (SplitMix64) used as stand-in media. The recovery gate tests
/// the persistence record (identities, digests, availability), not decoding, so media bytes are
/// generated rather than taken from fixtures.
public enum DeterministicBytes {
    public static func make(seed: UInt64, count: Int) -> Data {
        var state = seed
        var data = Data(count: count)
        data.withUnsafeMutableBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var i = 0
            while i < count {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                z ^= z >> 31
                for shift in stride(from: 0, to: 64, by: 8) where i < count {
                    bytes[i] = UInt8(truncatingIfNeeded: z >> UInt64(shift))
                    i += 1
                }
            }
        }
        return data
    }
}

/// IDs and expectations of the golden knowledge corpus (T35, J-06).
public struct GoldenCorpus: Sendable {
    public var works: [String: String] = [:]          // key -> work id
    public var editions: [String: String] = [:]
    public var assets: [String: String] = [:]
    public var captures: [String: String] = [:]
    public var notes: [String: String] = [:]
    public var conversationID = ""
    public var contextPackID = ""
    public var excerptSHA256 = ""
    public var excerptExtension = "mp3"
    public var remoteAssetBytes: Int64 = 5 * 1024 * 1024 * 1024 + 7
    /// Exact quoted texts by capture key, for the Markdown and restore checks.
    public var quotes: [String: String] = [:]
    /// Canonical cover thumbnails by edition key: (digest, file extension). Empty when the corpus is
    /// built at schema v1, which has no cover columns.
    public var covers: [String: (sha256: String, fileExtension: String)] = [:]

    /// Text deliberately mixing combining marks, emoji with modifiers, right-to-left script, CJK and
    /// Markdown metacharacters, so any normalization or escaping bug changes bytes.
    public static let unicodeQuote = "We ought to do good to others as simply as \"a horse runs\" — e\u{301}te\u{301} 👩🏽‍🔬 שָׁלוֹם 東京 *not emphasis* | pipe\nSecond line."

    /// Builds the corpus in `store`, importing generated media from `sourceDirectory` (the stand-in
    /// for a Mac source or Files location, deleted by the drill).
    public static func build(in store: LibraryStore, sourceDirectory: URL) throws -> GoldenCorpus {
        var c = GoldenCorpus()
        let media = MediaService(store)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        func source(_ name: String, seed: UInt64, bytes: Int) throws -> URL {
            let url = sourceDirectory.appending(path: name, directoryHint: .notDirectory)
            try DeterministicBytes.make(seed: seed, count: bytes).write(to: url)
            return url
        }
        func id() -> String { EntityID.make() }

        // Works, contributors, editions.
        try store.pool.write { db in
            let now = store.clock.nowMillis()
            for (key, title, sort) in [("meditations", "Meditations", "meditations"),
                                       ("walden", "Walden; or, Life in the Woods", "walden"),
                                       ("physical", "Ødegård’s Field Notes — 東京 edition", "odegard field notes")] {
                let workID = id()
                c.works[key] = workID
                try store.insertJournaled(db, "work", id: workID, [
                    "id": workID, "title": title, "sort_title": sort, "description": nil, "language_tag": "en",
                    "metadata_revision": 1, "created_at_ms": now, "updated_at_ms": now, "deleted_at_ms": nil,
                ])
            }
            let people = [("marcus", "Marcus Aurelius", "author", "meditations", 0),
                          ("long", "George Long", "translator", "meditations", 1),
                          ("thoreau", "Henry David Thoreau", "author", "walden", 0),
                          ("odegard", "Ingrid Ødegård", "author", "physical", 0)]
            for (key, name, role, work, ordinal) in people {
                let contributorID = id()
                try store.insertJournaled(db, "contributor", id: contributorID, [
                    "id": contributorID, "display_name": name, "kind": "person", "created_at_ms": now,
                ])
                try LibraryStore.insert(db, "work_contributor", [
                    "work_id": c.works[work]!, "contributor_id": contributorID, "role": role, "ordinal": ordinal,
                ])
                _ = key
            }
            let editions: [(String, String, String, [String: (any DatabaseValueConvertible)?])] = [
                ("med-epub", "meditations", "epub", ["publisher": "Standard Ebooks", "published_date": "2020", "published_date_precision": "year",
                                                     "identifiers_json": #"{"se":"marcus-aurelius/meditations/george-long"}"#]),
                ("med-audio", "meditations", "audio", ["narrator": "LibriVox volunteers", "abridged": 0]),
                ("med-pdf", "meditations", "pdf", ["page_count": 254]),
                ("walden-epub", "walden", "epub", ["published_date": "1854-08-09", "published_date_precision": "day"]),
                ("walden-audio", "walden", "audio", ["narrator": "Remote narrator"]),
                ("physical-book", "physical", "physical", ["page_count": 312, "publisher": "Small Press", "published_date": "2011-03",
                                                           "published_date_precision": "month"]),
            ]
            for (key, work, medium, extra) in editions {
                let editionID = id()
                c.editions[key] = editionID
                var values: [String: (any DatabaseValueConvertible)?] = [
                    "id": editionID, "work_id": c.works[work]!, "medium": medium, "language_tag": "en", "created_at_ms": now,
                ]
                values.merge(extra) { $1 }
                try store.insertJournaled(db, "edition", id: editionID, values)
            }
        }

        // Canonical cover thumbnails (generated stand-in bytes; the gate tests storage, not images).
        let hasCoverColumns = try store.pool.read { db in
            try db.columns(in: "edition").contains { $0.name == "cover_thumbnail_sha256" }
        }
        if hasCoverColumns {
            for (key, seed, bytes, ext) in [("med-epub", UInt64(201), 24_576, "jpg"), ("walden-epub", UInt64(202), 12_288, "png")] {
                let sha = try CoverStore.setCoverThumbnail(store, editionID: c.editions[key]!,
                                                           data: DeterministicBytes.make(seed: seed, count: bytes), fileExtension: ext)
                c.covers[key] = (sha, ext)
            }
        }

        // Original media (generated stand-ins), imported into managed storage.
        c.assets["med-epub"] = try media.importOriginal(try source("meditations.epub", seed: 1, bytes: 1_572_864),
                                                        editionID: c.editions["med-epub"]!, role: "primary", sequence: 0,
                                                        mediaType: "application/epub+zip")
        c.assets["med-audio-1"] = try media.importOriginal(try source("meditations-01.mp3", seed: 2, bytes: 3_145_728),
                                                           editionID: c.editions["med-audio"]!, role: "member", sequence: 0,
                                                           mediaType: "audio/mpeg", durationMs: 1_966_080, sourceKind: "mac_source",
                                                           sourceID: "mac-source-fixture")
        c.assets["med-audio-2"] = try media.importOriginal(try source("meditations-02.mp3", seed: 3, bytes: 2_621_440),
                                                           editionID: c.editions["med-audio"]!, role: "member", sequence: 1,
                                                           mediaType: "audio/mpeg", durationMs: 1_638_400, sourceKind: "mac_source",
                                                           sourceID: "mac-source-fixture")
        c.assets["med-pdf"] = try media.importOriginal(try source("meditations-companion.pdf", seed: 4, bytes: 524_288),
                                                       editionID: c.editions["med-pdf"]!, role: "companion", sequence: 0,
                                                       mediaType: "application/pdf")
        c.assets["walden-epub"] = try media.importOriginal(try source("walden.epub", seed: 5, bytes: 1_048_576),
                                                           editionID: c.editions["walden-epub"]!, role: "primary", sequence: 0,
                                                           mediaType: "application/epub+zip")

        // A 5 GiB audiobook known only at its source (64-bit sizes; never downloaded).
        let remoteSHA = Digest.sha256Hex("walden-remote-audiobook-identity")
        try store.pool.write { db in
            let now = store.clock.nowMillis()
            let assetID = id()
            c.assets["walden-audio"] = assetID
            try store.insertJournaled(db, "asset", id: assetID, [
                "id": assetID, "sha256": remoteSHA, "byte_count": c.remoteAssetBytes, "media_type": "audio/mp4",
                "original_filename": "Walden.m4b", "duration_ms": Int64(14 * 3600 * 1000 + 59_123), "validation_status": "valid",
                "created_at_ms": now,
            ])
            try LibraryStore.insert(db, "edition_asset", [
                "edition_id": c.editions["walden-audio"]!, "asset_id": assetID, "role": "primary", "sequence": 0, "timeline_revision": 1,
            ])
            let locationID = id()
            try store.insertJournaled(db, "asset_location", id: locationID, [
                "id": locationID, "asset_id": assetID, "source_kind": "mac_source", "source_id": "mac-source-fixture",
                "source_item": "item-42", "source_version": "etag-\"v1\"", "local_relative_path": nil,
                "availability": "at_source", "last_verified_at_ms": now,
            ])
        }
        let digests: [String: String] = try store.pool.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, sha256 FROM asset").map { ($0["id"], $0["sha256"]) })
        }

        // Ledger: runs (with a reread), dated events with precision, rating, recommendations.
        var runs: [String: String] = [:]
        try store.pool.write { db in
            let now = store.clock.nowMillis()
            for (key, work, state, started, startedP, finished, finishedP, manual) in [
                ("med-1", "meditations", "finished", "2019", "year", "2019", "year", 1),
                ("med-2", "meditations", "in_progress", "2026-09", "month", nil, nil, 0),
                ("walden-1", "walden", "finished", "2024-06-01", "day", "2024-07-15", "day", 0),
                ("physical-1", "physical", "in_progress", "2026-10-01", "day", nil, nil, 0),
            ] as [(String, String, String, String?, String?, String?, String?, Int)] {
                let runID = id()
                runs[key] = runID
                try store.insertJournaled(db, "consumption_run", id: runID, [
                    "id": runID, "work_id": c.works[work]!, "state": state, "started_date": started,
                    "started_date_precision": startedP, "finished_date": finished, "finished_date_precision": finishedP,
                    "manual_completion": manual, "created_at_ms": now, "updated_at_ms": now,
                ])
            }
            for (work, run, type, date, precision, payload) in [
                ("meditations", "med-1", "finished_marked", "2019", "year", #"{"manual":true}"#),
                ("meditations", "med-2", "reread_started", "2026-09", "month", "{}"),
                ("walden", "walden-1", "finished_confirmed", "2024-07-15", "day", #"{"detected_end":true}"#),
                ("physical", "physical-1", "manual_progress", "2026-10-05", "day", #"{"page":112,"manual":true,"edition_specific":true}"#),
            ] {
                let eventID = id()
                try store.insertJournaled(db, "ledger_event", id: eventID, [
                    "id": eventID, "work_id": c.works[work]!, "run_id": runs[run]!, "capture_id": nil, "event_type": type,
                    "effective_date": date, "effective_date_precision": precision, "recorded_at_ms": now,
                    "payload_version": 1, "payload_json": payload,
                ])
            }
            for (work, direction, kind, label, date, precision, reason, url) in [
                ("meditations", "outbound", "person", "Ana", "2026-09-14", "day", "For the stoic chapter on anger", nil),
                ("meditations", "inbound", "podcast", "Philosophize This!", "2019", "year", "Episode on Stoicism", "https://example.invalid/ep"),
                ("walden", "inbound", "article", "An essay on simplicity", "2024-05", "month", nil, nil),
            ] as [(String, String, String, String, String, String, String?, String?)] {
                let recID = id()
                var values: [String: (any DatabaseValueConvertible)?] = [
                    "id": recID, "work_id": c.works[work]!, "direction": direction, "counterpart_kind": kind,
                    "counterpart_label": label, "event_date": date, "reason": reason, "url": url, "recorded_at_ms": now,
                ]
                // v2 stores the precision explicitly; v1 libraries derive it during migration.
                if try db.columns(in: "recommendation_event").contains(where: { $0.name == "event_date_precision" }) {
                    values["event_date_precision"] = precision
                }
                try store.insertJournaled(db, "recommendation_event", id: recID, values)
            }
        }
        try store.setRating(workID: c.works["meditations"]!, value: 9)
        try store.setRating(workID: c.works["walden"]!, value: 7)
        try store.setRating(workID: c.works["walden"]!, value: nil)   // cleared, distinct from zero

        // Captures with anchors, notes and ledger activity, each in one transaction.
        let medTitle = SourceSnapshot(title: "Meditations", authorDisplay: "Marcus Aurelius", locationLabel: "Book V, 6",
                                      sourceKind: "local_epub", editionIdentifiers: ["se": "marcus-aurelius/meditations/george-long"])
        let quote = unicodeQuote
        c.quotes["epub-quote"] = quote
        let epubLocator = #"{"href":"text/book-5.xhtml","locations":{"progression":0.4271,"position":118},"text":{"before":"Book V. ","highlight":"We ought to do good…","after":" Next."},"type":"application/xhtml+xml"}"#
        let epubCapture = try store.saveCapture(CaptureCommand(
            workID: c.works["meditations"]!, editionID: c.editions["med-epub"]!, runID: runs["med-2"], kind: .quote,
            quotedText: quote, snapshot: medTitle,
            anchors: [AnchorInput(kind: .epub, editionID: c.editions["med-epub"]!, assetID: c.assets["med-epub"]!,
                                  assetSHA256: digests[c.assets["med-epub"]!]!, textOffsetUnit: "unicode_scalar",
                                  locatorJSON: #"{"resource_href":"text/book-5.xhtml","exact_text_sha256":"\#(Digest.sha256Hex(quote))","prefix":"Book V. ","suffix":" Next.","start":120,"end":\#(120 + quote.unicodeScalars.count)}"#,
                                  adapterPayload: epubLocator)],
            comment: "First thought.", idempotencyKey: "golden-epub-quote"))
        c.captures["epub-quote"] = epubCapture.captureID
        if case .saved(_, let noteID?) = epubCapture { c.notes["epub-quote"] = noteID }
        try store.reviseNote(c.notes["epub-quote"]!, expectedRevision: 1, body: "Second thought, *Markdown*.")
        try store.reviseNote(c.notes["epub-quote"]!, expectedRevision: 2, body: "Third thought:\n\n- kindness as nature\n- [link](https://example.invalid)")

        let audioCapture = try store.saveCapture(CaptureCommand(
            workID: c.works["meditations"]!, editionID: c.editions["med-audio"]!, runID: runs["med-2"], kind: .audio,
            quotedText: nil,
            snapshot: SourceSnapshot(title: "Meditations", authorDisplay: "Marcus Aurelius", locationLabel: "Book I · 32:41",
                                     sourceKind: "local_audio"),
            anchors: [
                AnchorInput(kind: .audio, editionID: c.editions["med-audio"]!, assetID: c.assets["med-audio-1"]!,
                            assetSHA256: digests[c.assets["med-audio-1"]!]!, startMs: 1_950_000, endMs: 1_966_080,
                            locatorJSON: #"{"member_sequence":0,"timeline_revision":1}"#),
                AnchorInput(kind: .audio, editionID: c.editions["med-audio"]!, assetID: c.assets["med-audio-2"]!,
                            assetSHA256: digests[c.assets["med-audio-2"]!]!, startMs: 0, endMs: 13_920,
                            locatorJSON: #"{"member_sequence":1,"timeline_revision":1}"#),
            ],
            comment: "The part about the gods, across the file boundary.", idempotencyKey: "golden-audio-capture"))
        c.captures["audio"] = audioCapture.captureID
        let excerptData = DeterministicBytes.make(seed: 99, count: 240_000)
        c.excerptSHA256 = try BlobStore(store).saveRetainedExcerpt(
            captureID: audioCapture.captureID, data: excerptData, mediaType: "audio/mpeg", fileExtension: "mp3",
            sourceRangesJSON: #"[{"asset_sha256":"\#(digests[c.assets["med-audio-1"]!]!)","start_ms":1950000,"end_ms":1966080},{"asset_sha256":"\#(digests[c.assets["med-audio-2"]!]!)","start_ms":0,"end_ms":13920}]"#,
            clipDurationMs: 30_000)

        let pdfQuote = "Do not act as if thou wert going to live ten thousand years."
        c.quotes["pdf-quote"] = pdfQuote
        c.captures["pdf-quote"] = try store.saveCapture(CaptureCommand(
            workID: c.works["meditations"]!, editionID: c.editions["med-pdf"]!, kind: .quote, quotedText: pdfQuote,
            snapshot: SourceSnapshot(title: "Meditations", authorDisplay: "Marcus Aurelius", locationLabel: "p. 41 (label xli)", sourceKind: "local_pdf"),
            anchors: [AnchorInput(kind: .pdf, editionID: c.editions["med-pdf"]!, assetID: c.assets["med-pdf"]!,
                                  assetSHA256: digests[c.assets["med-pdf"]!]!, textOffsetUnit: "unicode_scalar",
                                  locatorJSON: #"{"page_index":40,"page_label":"xli","rotation":90,"rects":[[0.1015,0.2031,0.7969,0.0254],[0.1015,0.2304,0.4102,0.0254]],"text_range":[880,939]}"#)],
            comment: nil, idempotencyKey: "golden-pdf-quote")).captureID

        c.captures["word"] = try store.saveCapture(CaptureCommand(
            workID: c.works["walden"]!, editionID: c.editions["walden-epub"]!, kind: .word, quotedText: "sauntering",
            snapshot: SourceSnapshot(title: "Walden", authorDisplay: "Henry David Thoreau", locationLabel: "Walking", sourceKind: "local_epub"),
            anchors: [AnchorInput(kind: .epub, editionID: c.editions["walden-epub"]!, assetID: c.assets["walden-epub"]!,
                                  assetSHA256: digests[c.assets["walden-epub"]!]!, textOffsetUnit: "unicode_scalar",
                                  locatorJSON: #"{"resource_href":"text/chapter-1.xhtml","start":10,"end":20}"#)],
            comment: "My meaning: wandering with purpose.", idempotencyKey: "golden-word")).captureID
        c.quotes["word"] = "sauntering"

        c.captures["physical-note"] = try store.saveCapture(CaptureCommand(
            workID: c.works["physical"]!, editionID: c.editions["physical-book"]!, runID: runs["physical-1"], kind: .note, quotedText: nil,
            snapshot: SourceSnapshot(title: "Ødegård’s Field Notes — 東京 edition", authorDisplay: "Ingrid Ødegård", locationLabel: "p. 112 (manual)",
                                     sourceKind: "physical"),
            anchors: [AnchorInput(kind: .manual, editionID: c.editions["physical-book"]!, locatorJSON: #"{"page":112,"manual":true}"#)],
            comment: "Read on the train; the map on this page.", idempotencyKey: "golden-physical-note")).captureID

        c.notes["walden-work"] = try store.addNote(workID: c.works["walden"]!, body: "# Simplicity\n\nSimplify, simplify. See [Walden](https://example.invalid).")
        let trashedNote = try store.addNote(workID: c.works["walden"]!, body: "A note in the 30-day trash.")
        try store.pool.write { db in
            try db.execute(sql: "UPDATE note SET trashed_at_ms = ? WHERE id = ?", arguments: [store.clock.nowMillis(), trashedNote])
            try LibraryStore.journal(db, "note", trashedNote, "trash", at: store.clock.nowMillis())
        }
        c.notes["trashed"] = trashedNote

        // A saved AI exchange: question, context pack with exact evidence snapshots, complete and
        // interrupted answers, and a note derived from it.
        try store.pool.write { db in
            let now = store.clock.nowMillis()
            c.conversationID = id()
            c.contextPackID = id()
            try store.insertJournaled(db, "conversation", id: c.conversationID, [
                "id": c.conversationID, "work_id": c.works["meditations"]!, "capture_id": c.captures["epub-quote"]!,
                "created_at_ms": now, "updated_at_ms": now,
            ])
            try store.insertJournaled(db, "context_pack", id: c.contextPackID, [
                "id": c.contextPackID, "request_id": id(), "schema_version": 1, "scope": "selected_passage", "mode": "source_grounded",
                "coverage": "excerpt_only", "question": "What does he mean by a horse runs?", "truncated": 0,
                "retrieval_json": #"{"strategy":"selected_passage","budget_tokens":2000,"used_tokens":412}"#,
                "endpoint_json": #"{"host":"api.example.invalid","model":"fixture-model-1","dialect":"openai_responses","disclosure":"hosted"}"#,
                "prompt_template_version": "sylvia-grounded-1", "created_at_ms": now,
            ])
            let evidence = [("c1", c.captures["epub-quote"]!, "capture", quote, "Book V, 6"),
                            ("c2", nil, "source_text", "A horse when he has run, a dog when he has tracked the game…", "Book V, 6")]
            for (ordinal, (citation, capture, origin, text, label)) in evidence.enumerated() {
                try LibraryStore.insert(db, "context_evidence", [
                    "context_pack_id": c.contextPackID, "citation_id": citation, "ordinal": ordinal, "capture_id": capture,
                    "origin": origin, "text": text, "text_sha256": Digest.sha256Hex(text),
                    "anchor_json": #"{"edition_id":"\#(c.editions["med-epub"]!)","resource_href":"text/book-5.xhtml"}"#, "location_label": label,
                ])
            }
            for (ordinal, role, content, state, pack) in [
                (0, "user", "What does he mean by a horse runs?", "complete", c.contextPackID),
                (1, "assistant", "He compares doing good to a horse running: acting by nature without seeking thanks [c1][c2].", "complete", c.contextPackID),
                (2, "assistant", "A further thought that was cut o", "interrupted", c.contextPackID),
            ] as [(Int, String, String, String, String?)] {
                let messageID = id()
                try store.insertJournaled(db, "message", id: messageID, [
                    "id": messageID, "conversation_id": c.conversationID, "ordinal": ordinal, "role": role, "content": content,
                    "state": state, "provider_json": role == "assistant" ? #"{"host":"api.example.invalid","model":"fixture-model-1"}"# : nil,
                    "request_id": id(), "context_pack_id": pack, "created_at_ms": now,
                ])
            }
        }
        c.notes["ai-derived"] = try store.addNote(workID: c.works["meditations"]!, body: "From the AI answer: act by nature.",
                                                  conversationID: c.conversationID)
        return c
    }
}
