import Foundation
import GRDB

// MARK: - Commands

public enum CaptureKind: String, Sendable, Codable, CaseIterable {
    case quote, note, audio, generated, word
}

public enum AnchorKind: String, Sendable, Codable {
    case epub, pdf, text, audio, manual
}

/// Source snapshot taken at capture time (plan 11.2); immutable afterwards.
public struct SourceSnapshot: Sendable, Codable, Hashable {
    public var title: String
    public var author_display: String
    public var location_label: String
    public var source_kind: String
    public var edition_identifiers: [String: String]?

    public init(title: String, authorDisplay: String, locationLabel: String, sourceKind: String,
                editionIdentifiers: [String: String]? = nil) {
        self.title = title
        self.author_display = authorDisplay
        self.location_label = locationLabel
        self.source_kind = sourceKind
        self.edition_identifiers = editionIdentifiers
    }
}

/// One canonical anchor (plan 7.5) as stored data: portable fields plus the reader's original
/// locator kept as an opaque adapter payload.
public struct AnchorInput: Sendable, Hashable {
    public var kind: AnchorKind
    public var editionID: String?
    public var assetID: String?
    public var assetSHA256: String?
    public var startMs: Int64?
    public var endMs: Int64?
    public var textOffsetUnit: String?
    /// Portable locator JSON (resource href, page index, exact/prefix/suffix text...).
    public var locatorJSON: String
    /// The reader's native locator, stored verbatim.
    public var adapterPayload: String?

    public init(kind: AnchorKind, editionID: String? = nil, assetID: String? = nil, assetSHA256: String? = nil,
                startMs: Int64? = nil, endMs: Int64? = nil, textOffsetUnit: String? = nil,
                locatorJSON: String, adapterPayload: String? = nil) {
        self.kind = kind
        self.editionID = editionID
        self.assetID = assetID
        self.assetSHA256 = assetSHA256
        self.startMs = startMs
        self.endMs = endMs
        self.textOffsetUnit = textOffsetUnit
        self.locatorJSON = locatorJSON
        self.adapterPayload = adapterPayload
    }
}

/// Plan 11.1: work/edition, source snapshot, exact text or audio ranges, optional comment and an
/// idempotency key, committed with anchors, note and ledger activity in one transaction.
public struct CaptureCommand: Sendable {
    public var captureID: String
    public var workID: String
    public var editionID: String?
    public var runID: String?
    public var kind: CaptureKind
    public var quotedText: String?
    public var snapshot: SourceSnapshot
    public var anchors: [AnchorInput]
    public var comment: String?
    public var idempotencyKey: String

    public init(captureID: String = EntityID.make(), workID: String, editionID: String?, runID: String? = nil,
                kind: CaptureKind, quotedText: String?, snapshot: SourceSnapshot, anchors: [AnchorInput],
                comment: String?, idempotencyKey: String) {
        self.captureID = captureID
        self.workID = workID
        self.editionID = editionID
        self.runID = runID
        self.kind = kind
        self.quotedText = quotedText
        self.snapshot = snapshot
        self.anchors = anchors
        self.comment = comment
        self.idempotencyKey = idempotencyKey
    }
}

public enum SaveOutcome: Sendable, Equatable {
    /// Durably committed by this call. Only now may the UI say "Saved".
    case saved(captureID: String, noteID: String?)
    /// The idempotency key was already committed (a retry after a crash or a double tap).
    case alreadySaved(captureID: String)

    public var captureID: String {
        switch self {
        case .saved(let id, _), .alreadySaved(let id): return id
        }
    }
}

// MARK: - Repository

extension LibraryStore {
    /// Inserts a row from a column dictionary. Text containing U+0000 is refused before anything is
    /// written: GRDB binds a `String` as a C string, so SQLite would store it cut off at the NUL and
    /// the caller would say "Saved" for text that was not saved exactly (finding F12; I-03, I-05).
    static func insert(_ db: Database, _ table: String, _ values: [String: (any DatabaseValueConvertible)?]) throws {
        for (column, value) in values.sorted(by: { $0.key < $1.key }) {
            if let text = value as? String, text.utf8.contains(0) {
                throw ValidationError.textContainsNUL(column: "\(table).\(column)")
            }
        }
        let columns = values.keys.sorted()
        let sql = "INSERT INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(columns.map { _ in "?" }.joined(separator: ", ")))"
        try db.execute(sql: sql, arguments: StatementArguments(columns.map { values[$0]! }))
    }

    /// Appends a ChangeJournal entry in the caller's transaction (plan 7.4).
    static func journal(_ db: Database, _ entity: String, _ id: String, _ operation: String, revision: Int? = nil,
                        at: Int64) throws {
        try db.execute(sql: """
            INSERT INTO change_journal (entity, entity_id, revision, operation, recorded_at_ms)
            VALUES (?, ?, ?, ?, ?)
            """, arguments: [entity, id, revision, operation, at])
    }

    /// Inserts a row and journals it, both in the caller's transaction.
    public func insertJournaled(_ db: Database, _ table: String, id: String,
                                _ values: [String: (any DatabaseValueConvertible)?]) throws {
        try Self.insert(db, table, values)
        try Self.journal(db, table, id, "insert", at: clock.nowMillis())
    }

    // MARK: Capture (plan 11.1)

    /// Commits a capture with its anchors, optional comment note and ledger activity in one write
    /// transaction. Returns only after the commit (and its WAL sync) has completed.
    /// `beforeCommit` runs inside the transaction; it exists for the crash drill.
    @discardableResult
    public func saveCapture(_ command: CaptureCommand, beforeCommit: (() throws -> Void)? = nil) throws -> SaveOutcome {
        guard !command.anchors.isEmpty else { throw ValidationError.emptyCapture }
        return try pool.write { db in
            if let existing = try String.fetchOne(db, sql: "SELECT id FROM capture WHERE idempotency_key = ?",
                                                  arguments: [command.idempotencyKey]) {
                return .alreadySaved(captureID: existing)
            }
            let now = clock.nowMillis()
            let snapshotJSON = String(decoding: try JSONEncoder.sorted.encode(command.snapshot), as: UTF8.self)
            try Self.insert(db, "capture", [
                "id": command.captureID, "work_id": command.workID, "edition_id": command.editionID,
                "kind": command.kind.rawValue, "quoted_text": command.quotedText,
                "source_snapshot_json": snapshotJSON, "idempotency_key": command.idempotencyKey,
                "revision": 1, "created_at_ms": now, "updated_at_ms": now, "trashed_at_ms": nil,
            ])
            try Self.journal(db, "capture", command.captureID, "insert", revision: 1, at: now)
            for (ordinal, anchor) in command.anchors.enumerated() {
                try Self.insert(db, "capture_anchor", [
                    "capture_id": command.captureID, "ordinal": ordinal, "schema_version": 1,
                    "kind": anchor.kind.rawValue, "work_id": command.workID, "edition_id": anchor.editionID,
                    "asset_id": anchor.assetID, "asset_sha256": anchor.assetSHA256,
                    "start_ms": anchor.startMs, "end_ms": anchor.endMs, "text_offset_unit": anchor.textOffsetUnit,
                    "locator_json": anchor.locatorJSON, "adapter_payload": anchor.adapterPayload,
                ])
            }
            var noteID: String?
            if let comment = command.comment {
                let id = EntityID.make()
                noteID = id
                try Self.insert(db, "note", [
                    "id": id, "work_id": command.workID, "capture_id": command.captureID, "conversation_id": nil,
                    "current_revision": 1, "created_at_ms": now, "updated_at_ms": now, "trashed_at_ms": nil,
                ])
                try Self.insert(db, "note_revision", [
                    "note_id": id, "revision": 1, "body": comment, "format": "markdown", "origin": "user",
                    "saved_at_ms": now,
                ])
                try Self.journal(db, "note", id, "insert", revision: 1, at: now)
            }
            let ledgerID = EntityID.make()
            try Self.insert(db, "ledger_event", [
                "id": ledgerID, "work_id": command.workID, "run_id": command.runID, "capture_id": command.captureID,
                "event_type": "capture_saved", "effective_date": nil, "effective_date_precision": nil,
                "recorded_at_ms": now, "payload_version": 1,
                "payload_json": #"{"kind":"\#(command.kind.rawValue)"}"#,
            ])
            try Self.journal(db, "ledger_event", ledgerID, "insert", at: now)
            try beforeCommit?()
            return .saved(captureID: command.captureID, noteID: noteID)
        }
    }

    // MARK: Notes (plan 7.3: revision-checked edits)

    /// Saves a new revision only if the editor's `expectedRevision` is still current, so a stale
    /// editor cannot silently overwrite a later edit. Returns the new revision.
    @discardableResult
    public func reviseNote(_ noteID: String, expectedRevision: Int, body: String, format: String = "markdown",
                           origin: String = "user") throws -> Int {
        try pool.write { db in
            guard let current = try Int.fetchOne(db, sql: "SELECT current_revision FROM note WHERE id = ?",
                                                 arguments: [noteID]) else {
                throw StoreError.notFound(entity: "note", id: noteID)
            }
            guard current == expectedRevision else {
                throw StoreError.staleRevision(noteID: noteID, expected: expectedRevision, current: current)
            }
            // RowCheck keeps restored values below 2^53; this guard keeps any other bad value an
            // error rather than an overflow trap.
            guard current < RowCheck.integerMagnitudeLimit else {
                throw StoreError.invalid("note \(noteID): current_revision \(current) is out of range")
            }
            let now = clock.nowMillis()
            let next = current + 1
            try Self.insert(db, "note_revision", [
                "note_id": noteID, "revision": next, "body": body, "format": format, "origin": origin, "saved_at_ms": now,
            ])
            try db.execute(sql: "UPDATE note SET current_revision = ?, updated_at_ms = ? WHERE id = ?",
                           arguments: [next, now, noteID])
            try Self.journal(db, "note", noteID, "update", revision: next, at: now)
            return next
        }
    }

    /// Creates a work-level note (no capture).
    @discardableResult
    public func addNote(workID: String, body: String, conversationID: String? = nil, id: String = EntityID.make()) throws -> String {
        try pool.write { db in
            let now = clock.nowMillis()
            try Self.insert(db, "note", [
                "id": id, "work_id": workID, "capture_id": nil, "conversation_id": conversationID,
                "current_revision": 1, "created_at_ms": now, "updated_at_ms": now, "trashed_at_ms": nil,
            ])
            try Self.insert(db, "note_revision", [
                "note_id": id, "revision": 1, "body": body, "format": "markdown", "origin": "user", "saved_at_ms": now,
            ])
            try Self.journal(db, "note", id, "insert", revision: 1, at: now)
            return id
        }
    }

    // MARK: Rating (plan 12: 1-10 half-stars, nil clears)

    public func setRating(workID: String, value: Int?) throws {
        if let value, !(1...10).contains(value) { throw ValidationError.invalidRating(value) }
        try pool.write { db in
            let now = clock.nowMillis()
            try db.execute(sql: """
                INSERT INTO rating (work_id, value, scale, updated_at_ms) VALUES (?, ?, 'half_stars_1_10', ?)
                ON CONFLICT(work_id) DO UPDATE SET value = excluded.value, updated_at_ms = excluded.updated_at_ms
                """, arguments: [workID, value, now])
            try Self.journal(db, "rating", workID, "update", at: now)
        }
    }
}

extension JSONEncoder {
    /// Deterministic JSON (sorted keys, no escaped slashes) for stored snapshots and exports.
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
