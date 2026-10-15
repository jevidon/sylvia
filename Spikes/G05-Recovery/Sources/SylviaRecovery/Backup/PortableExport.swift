import Foundation
import GRDB

/// Portable exports read straight from the database snapshot (plan 17.3): one JSON document with
/// every knowledge table, and Markdown per work. They need no Sylvia build to read (I-09).
public enum PortableExport {
    public static let jsonFormat = "sylvia-portable-export"

    /// Tables exported to JSON: the knowledge tables plus where each asset was.
    public static var jsonTables: [String] { LibrarySchema.knowledgeTables + ["asset_location"] }

    /// `{"format", "schema_version", "library_schema_version", "units", "tables": {name: [row objects]}}`.
    /// Integers are JSON integers (64-bit sizes and millisecond timestamps all fit below 2^53 here,
    /// and the export asserts it); `*_json` columns are kept as the exact stored strings.
    public static func json(_ db: Database, librarySchemaVersion: Int) throws -> Data {
        var tables: [String: Any] = [:]
        for table in jsonTables {
            let columns = try db.columns(in: table).map(\.name)
            let order = LibrarySchema.tables.first { $0.name == table }!.orderBy
            var rows: [[String: Any]] = []
            for row in try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY \(order)") {
                var object: [String: Any] = [:]
                for column in columns {
                    let value: DatabaseValue = row[column]
                    switch value.storage {
                    case .null: object[column] = NSNull()
                    case .int64(let v):
                        // Compared without `abs`, which traps on Int64.min.
                        guard v < (1 << 53) && v > -(1 << 53) else { throw StoreError.invalid("\(table).\(column) exceeds 2^53") }
                        object[column] = NSNumber(value: v)
                    case .double(let v): object[column] = NSNumber(value: v)
                    case .string(let s): object[column] = s
                    case .blob(let d): object[column] = ["base64": d.base64EncodedString()]
                    }
                }
                rows.append(object)
            }
            tables[table] = rows
        }
        let document: [String: Any] = [
            "format": jsonFormat,
            "schema_version": 1,
            "library_schema_version": librarySchemaVersion,
            "units": [
                "timestamps": "*_at_ms: integer milliseconds since 1970-01-01T00:00:00Z (UTC)",
                "effective_dates": "text YYYY, YYYY-MM or YYYY-MM-DD with a *_precision column",
                "sizes": "byte_count: integer bytes",
                "durations": "*_ms: integer milliseconds",
                "rating": "value: integer 1-10 = 0.5-5 stars in half-star steps; null = no rating",
                "text_offsets": "unicode_scalar",
            ],
            "tables": tables,
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    /// Rebuilds the canonical dump of the knowledge tables from the JSON export alone, to prove the
    /// JSON carries the same values as the database snapshot.
    public static func canonicalDump(fromJSON data: Data) throws -> String {
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tables = document["tables"] as? [String: [[String: Any]]] else {
            throw StoreError.invalid("portable JSON has no tables")
        }
        var out = ""
        for table in LibrarySchema.knowledgeTables {
            let rows = tables[table] ?? []
            out += "## \(table) (\(rows.count))\n"
            for row in rows {
                out += row.keys.sorted().map { "\($0)=\(CanonicalValue.render(json: row[$0]!))" }.joined(separator: "|") + "\n"
            }
        }
        return out
    }

    /// One Markdown file per work with its quotes (exact text), audio moments, notes (current
    /// revision) and saved AI conversations (those of the work and those started from one of its
    /// captures), plus one file for conversations with neither. Returns `[file name: contents]`.
    public static func markdown(_ db: Database) throws -> [String: String] {
        var files: [String: String] = [:]
        for work in try Row.fetchAll(db, sql: "SELECT id, title FROM work ORDER BY sort_title, id") {
            let workID: String = work["id"]
            let title: String = work["title"]
            var md = "# \(singleLine(title))\n\n"
            let contributors = try String.fetchAll(db, sql: """
                SELECT c.display_name FROM work_contributor wc JOIN contributor c ON c.id = wc.contributor_id
                WHERE wc.work_id = ? ORDER BY wc.ordinal
                """, arguments: [workID])
            if !contributors.isEmpty { md += "By \(contributors.map(singleLine).joined(separator: ", "))\n\n" }
            md += "Work ID: `\(workID)`\n\n"

            let captures = try Row.fetchAll(db, sql: """
                SELECT id, kind, quoted_text, source_snapshot_json, created_at_ms FROM capture
                WHERE work_id = ? AND trashed_at_ms IS NULL ORDER BY created_at_ms, id
                """, arguments: [workID])
            if !captures.isEmpty { md += "## Captures\n\n" }
            for capture in captures {
                let captureID: String = capture["id"]
                let kind: String = capture["kind"]
                let snapshot = (try? JSONSerialization.jsonObject(with: Data((capture["source_snapshot_json"] as String).utf8))) as? [String: Any]
                let label = singleLine(snapshot?["location_label"] as? String ?? "")
                md += "### \(kind.uppercased()) · \(label)\n\n"
                if let text = capture["quoted_text"] as String? {
                    md += text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n") + "\n\n"
                }
                for anchor in try Row.fetchAll(db, sql: "SELECT kind, start_ms, end_ms, asset_sha256 FROM capture_anchor WHERE capture_id = ? ORDER BY ordinal",
                                               arguments: [captureID]) where (anchor["kind"] as String) == "audio" {
                    md += "- Audio \(anchor["start_ms"] as Int64? ?? 0)–\(anchor["end_ms"] as Int64? ?? 0) ms in asset `\(anchor["asset_sha256"] as String? ?? "")`\n"
                }
                for excerpt in try Row.fetchAll(db, sql: "SELECT blob_sha256, file_extension FROM retained_excerpt WHERE capture_id = ? ORDER BY id",
                                                arguments: [captureID]) {
                    md += "- Excerpt audio: `blobs/excerpts/\(excerpt["blob_sha256"] as String).\(excerpt["file_extension"] as String)`\n"
                }
                for note in try String.fetchAll(db, sql: """
                    SELECT r.body FROM note n JOIN note_revision r ON r.note_id = n.id AND r.revision = n.current_revision
                    WHERE n.capture_id = ? AND n.trashed_at_ms IS NULL ORDER BY n.created_at_ms, n.id
                    """, arguments: [captureID]) {
                    md += "\nYour note:\n\n\(note)\n"
                }
                md += "\n"
            }

            let notes = try String.fetchAll(db, sql: """
                SELECT r.body FROM note n JOIN note_revision r ON r.note_id = n.id AND r.revision = n.current_revision
                WHERE n.work_id = ? AND n.capture_id IS NULL AND n.trashed_at_ms IS NULL ORDER BY n.created_at_ms, n.id
                """, arguments: [workID])
            if !notes.isEmpty { md += "## Notes\n\n" + notes.map { "\($0)\n" }.joined(separator: "\n") + "\n" }

            // A conversation belongs to its work directly, or through the capture it was started
            // from (plan 7.2: work/capture association; `work_id` may be null when `capture_id` is set).
            let conversations = try String.fetchAll(db, sql: """
                SELECT cv.id FROM conversation cv LEFT JOIN capture c ON c.id = cv.capture_id
                WHERE coalesce(cv.work_id, c.work_id) = ? ORDER BY cv.created_at_ms, cv.id
                """, arguments: [workID])
            md += try conversationsMarkdown(db, conversations)
            files["\(slug(title))-\(workID.prefix(8)).md"] = md
        }
        // Conversations with neither a work nor a capture still appear, in a file of their own.
        let unassociated = try String.fetchAll(db, sql: """
            SELECT id FROM conversation WHERE work_id IS NULL AND capture_id IS NULL ORDER BY created_at_ms, id
            """)
        if !unassociated.isEmpty {
            files[unassociatedConversationsFile] = "# Conversations without a work\n\n" + (try conversationsMarkdown(db, unassociated))
        }
        return files
    }

    /// File name for conversations that belong to no work. Work files always end in `-<id8>.md`, and
    /// "work" is not eight hex digits, so the names cannot collide.
    public static let unassociatedConversationsFile = "conversations-without-a-work.md"

    /// Every message of `conversations`, in order: questions, generated answers with their state,
    /// and each answer's context evidence.
    static func conversationsMarkdown(_ db: Database, _ conversations: [String]) throws -> String {
        guard !conversations.isEmpty else { return "" }
        var md = "## Conversations\n\n"
        for conversationID in conversations {
            for message in try Row.fetchAll(db, sql: "SELECT role, state, content, context_pack_id FROM message WHERE conversation_id = ? ORDER BY ordinal",
                                            arguments: [conversationID]) {
                let role: String = message["role"]
                md += "**\(role == "user" ? "Question" : "Generated (\(message["state"] as String))")**\n\n\(message["content"] as String)\n\n"
                if let pack = message["context_pack_id"] as String? {
                    for evidence in try Row.fetchAll(db, sql: "SELECT citation_id, text, location_label FROM context_evidence WHERE context_pack_id = ? ORDER BY ordinal",
                                                     arguments: [pack]) {
                        md += "- [\(evidence["citation_id"] as String)] \(singleLine(evidence["location_label"] as String? ?? "")): "
                            + "\(singleLine(evidence["text"] as String))\n"
                    }
                    md += "\n"
                }
            }
        }
        return md
    }

    static func singleLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) { out.unicodeScalars.append(scalar) }
            else if !out.hasSuffix("-") { out += "-" }
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "work" : String(out.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
