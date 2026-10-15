import Foundation
import GRDB

/// The spike schema: the subset of plan Section 7.2 needed for the recovery drill.
///
/// Rules applied everywhere (plan 7.2, 7.3):
/// * `STRICT` tables, so an INTEGER column never silently stores text or a float.
/// * Identifiers are lowercase UUID text generated on device.
/// * Sizes, durations and positions are 64-bit INTEGER (bytes, milliseconds).
/// * Event timestamps are UTC integer milliseconds (`*_at_ms`). User-effective dates are stored
///   separately as text with an explicit precision (`year` / `month` / `day`).
/// * Foreign keys are enforced. `ON DELETE CASCADE` is used only for genuinely subordinate rows
///   (a capture's anchors, a note's revisions, a conversation's messages, a context pack's evidence,
///   an asset's location rows, membership joins). Everything that is knowledge references media
///   with `RESTRICT`, so no media deletion can cascade into knowledge; media removal never deletes
///   `asset` rows in the first place (it changes `asset_location.availability`).
public enum LibrarySchema {
    public struct MigrationInfo: Sendable, Hashable {
        public let identifier: String
        /// Library schema version reached once this migration (and all before it) is applied.
        public let version: Int
        /// Rebuilds or drops a table; a recovery snapshot is required first (plan 7.4).
        public let destructive: Bool
    }

    public static let migrations: [MigrationInfo] = [
        MigrationInfo(identifier: "v1-initial", version: 1, destructive: false),
        MigrationInfo(identifier: "v2-rating-review-note", version: 2, destructive: false),
        MigrationInfo(identifier: "v2-recommendation-date-precision", version: 2, destructive: true),
        MigrationInfo(identifier: "v2-edition-cover-thumbnail", version: 2, destructive: false),
    ]

    public static var currentVersion: Int { migrations.map(\.version).max() ?? 0 }
    public static var knownIdentifiers: Set<String> { Set(migrations.map(\.identifier)) }

    /// Library schema version implied by a set of applied migration identifiers. Returns nil when
    /// the set contains an identifier this build does not know (a newer library).
    public static func version(forApplied applied: Set<String>) -> Int? {
        guard applied.isSubset(of: knownIdentifiers) else { return nil }
        // The highest version whose migrations (and all earlier ones) are all applied. A partially
        // applied version reports the previous complete one; the identifier list is exact.
        var version = 0
        for candidate in Set(migrations.map(\.version)).sorted() {
            let required = migrations.filter { $0.version <= candidate }.map(\.identifier)
            guard required.allSatisfy(applied.contains) else { break }
            version = candidate
        }
        return version
    }

    /// Every applied migration identifier: known ones in registration order, then any unknown ones
    /// (sorted). GRDB's `appliedMigrations(_:)` returns only *registered* identifiers, so it cannot
    /// detect a library written by a newer build; this uses `appliedIdentifiers(_:)` instead.
    public static func applied(_ db: Database) throws -> [String] {
        let all = try DatabaseMigrator().appliedIdentifiers(db)
        let known = migrations.map(\.identifier).filter(all.contains)
        return known + all.subtracting(knownIdentifiers).sorted()
    }

    /// Test-only fault injection for migration failure drills (T45). Production uses `.none`.
    public struct Faults: Sendable {
        public var throwDuringRecommendationRebuild = false
        public var dropRowsDuringRecommendationRebuild = false
        public init() {}
        public static let none = Faults()
    }

    public struct InjectedMigrationFault: Error, CustomStringConvertible {
        public var description: String { "injected fault during v2-recommendation-date-precision" }
    }

    public static func migrator(faults: Faults = .none) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // Never erase a user's library because the schema changed (plan 7.4).
        migrator.eraseDatabaseOnSchemaChange = false

        migrator.registerMigration("v1-initial") { db in
            try db.execute(sql: v1SQL)
        }

        migrator.registerMigration("v2-rating-review-note") { db in
            try db.execute(sql: "ALTER TABLE rating ADD COLUMN review_note TEXT")
        }

        // Destructive: rebuilds recommendation_event to split the free-form v1 `event_date` into a
        // checked date plus precision and to constrain `direction`. Rows that cannot be converted
        // fail the migration (CHECK constraint) instead of being dropped.
        migrator.registerMigration("v2-recommendation-date-precision") { db in
            try db.execute(sql: """
                CREATE TABLE recommendation_event_v2 (
                  id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                  work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
                  direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
                  counterpart_kind TEXT CHECK (counterpart_kind IN ('person', 'podcast', 'article', 'work', 'other')),
                  counterpart_label TEXT NOT NULL,
                  event_date TEXT,
                  event_date_precision TEXT CHECK (event_date_precision IN ('year', 'month', 'day')),
                  reason TEXT,
                  url TEXT,
                  recorded_at_ms INTEGER NOT NULL,
                  CHECK ((event_date IS NULL) = (event_date_precision IS NULL))
                ) STRICT;
                """)
            let filter = faults.dropRowsDuringRecommendationRebuild ? "WHERE direction = 'inbound'" : ""
            try db.execute(sql: """
                INSERT INTO recommendation_event_v2
                  (id, work_id, direction, counterpart_kind, counterpart_label, event_date,
                   event_date_precision, reason, url, recorded_at_ms)
                SELECT id, work_id, direction, counterpart_kind, counterpart_label, event_date,
                       CASE WHEN event_date IS NULL THEN NULL
                            WHEN event_date GLOB '[0-9][0-9][0-9][0-9]' THEN 'year'
                            WHEN event_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]' THEN 'month'
                            WHEN event_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' THEN 'day'
                            ELSE NULL END,
                       reason, url, recorded_at_ms
                FROM recommendation_event \(filter)
                """)
            if faults.throwDuringRecommendationRebuild {
                throw InjectedMigrationFault()
            }
            try db.execute(sql: """
                DROP TABLE recommendation_event;
                ALTER TABLE recommendation_event_v2 RENAME TO recommendation_event;
                CREATE INDEX recommendation_event_work ON recommendation_event(work_id);
                """)
        }

        // The edition's canonical cover thumbnail (plan 17.1, 17.3): a small content-addressed image
        // under Blobs/covers/, kept with the knowledge and included in every backup. It is not
        // original media: removing a work's media never touches it.
        migrator.registerMigration("v2-edition-cover-thumbnail") { db in
            try db.execute(sql: """
                ALTER TABLE edition ADD COLUMN cover_thumbnail_sha256 TEXT
                  CHECK (cover_thumbnail_sha256 IS NULL OR (\(hex64("cover_thumbnail_sha256"))));
                ALTER TABLE edition ADD COLUMN cover_thumbnail_extension TEXT
                  CHECK ((cover_thumbnail_extension IS NULL) = (cover_thumbnail_sha256 IS NULL)
                         AND (cover_thumbnail_extension IS NULL OR cover_thumbnail_extension IN ('jpg', 'png', 'heic')));
                """)
        }
        return migrator
    }

    /// Tables in dependency order, with their primary-key ordering for canonical dumps.
    public static let tables: [(name: String, orderBy: String)] = [
        ("work", "id"),
        ("contributor", "id"),
        ("work_contributor", "work_id, contributor_id, role"),
        ("edition", "id"),
        ("asset", "id"),
        ("edition_asset", "edition_id, asset_id"),
        ("asset_location", "id"),
        ("consumption_run", "id"),
        ("rating", "work_id"),
        ("recommendation_event", "id"),
        ("capture", "id"),
        ("capture_anchor", "capture_id, ordinal"),
        ("conversation", "id"),
        ("context_pack", "id"),
        ("context_evidence", "context_pack_id, citation_id"),
        ("message", "id"),
        ("note", "id"),
        ("note_revision", "note_id, revision"),
        ("retained_excerpt", "id"),
        ("ledger_event", "id"),
        ("change_journal", "seq"),
        ("export_record", "id"),
        ("retention_lease", "id"),
    ]

    /// Tables whose rows are the permanent record compared by the restore drill. Excludes
    /// `asset_location` (availability legitimately changes on restore), `change_journal` (restore
    /// appends to it), `export_record` (written after the snapshot) and `retention_lease`
    /// (processing data).
    public static let knowledgeTables: [String] = [
        "work", "contributor", "work_contributor", "edition", "asset", "edition_asset",
        "consumption_run", "rating", "recommendation_event", "capture", "capture_anchor",
        "conversation", "context_pack", "context_evidence", "message", "note", "note_revision",
        "retained_excerpt", "ledger_event",
    ]

    // A lowercase hex SHA-256 check, reused in several tables.
    private static func hex64(_ column: String) -> String {
        "length(\(column)) = 64 AND \(column) NOT GLOB '*[^0-9a-f]*'"
    }

    static let v1SQL = """
        CREATE TABLE work (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          title TEXT NOT NULL,
          sort_title TEXT NOT NULL,
          description TEXT,
          language_tag TEXT,
          metadata_revision INTEGER NOT NULL DEFAULT 1 CHECK (metadata_revision >= 1),
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          deleted_at_ms INTEGER
        ) STRICT;

        CREATE TABLE contributor (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          display_name TEXT NOT NULL,
          kind TEXT NOT NULL CHECK (kind IN ('person', 'organization')),
          created_at_ms INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE work_contributor (
          work_id TEXT NOT NULL REFERENCES work(id) ON DELETE CASCADE,
          contributor_id TEXT NOT NULL REFERENCES contributor(id) ON DELETE RESTRICT,
          role TEXT NOT NULL,
          ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
          PRIMARY KEY (work_id, contributor_id, role)
        ) STRICT;
        CREATE INDEX work_contributor_contributor ON work_contributor(contributor_id);

        CREATE TABLE edition (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
          medium TEXT NOT NULL CHECK (medium IN ('epub', 'pdf', 'text', 'audio', 'physical', 'external')),
          language_tag TEXT,
          publisher TEXT,
          published_date TEXT,
          published_date_precision TEXT CHECK (published_date_precision IN ('year', 'month', 'day')),
          identifiers_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(identifiers_json)),
          narrator TEXT,
          abridged INTEGER NOT NULL DEFAULT 0 CHECK (abridged IN (0, 1)),
          page_count INTEGER CHECK (page_count > 0),
          created_at_ms INTEGER NOT NULL,
          CHECK ((published_date IS NULL) = (published_date_precision IS NULL))
        ) STRICT;
        CREATE INDEX edition_work ON edition(work_id);

        CREATE TABLE asset (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          sha256 TEXT NOT NULL UNIQUE CHECK (\(hex64("sha256"))),
          byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
          media_type TEXT NOT NULL,
          original_filename TEXT,
          duration_ms INTEGER CHECK (duration_ms >= 0),
          validation_status TEXT NOT NULL CHECK (validation_status IN ('pending', 'valid', 'invalid')),
          created_at_ms INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE edition_asset (
          edition_id TEXT NOT NULL REFERENCES edition(id) ON DELETE CASCADE,
          asset_id TEXT NOT NULL REFERENCES asset(id) ON DELETE RESTRICT,
          role TEXT NOT NULL CHECK (role IN ('primary', 'member', 'companion', 'cover')),
          sequence INTEGER NOT NULL CHECK (sequence >= 0),
          timeline_revision INTEGER NOT NULL DEFAULT 1 CHECK (timeline_revision >= 1),
          PRIMARY KEY (edition_id, asset_id),
          UNIQUE (edition_id, role, sequence)
        ) STRICT;
        CREATE INDEX edition_asset_asset ON edition_asset(asset_id);

        CREATE TABLE asset_location (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          asset_id TEXT NOT NULL REFERENCES asset(id) ON DELETE CASCADE,
          source_kind TEXT NOT NULL CHECK (source_kind IN ('local_import', 'mac_source', 'files_provider')),
          source_id TEXT,
          source_item TEXT,
          source_version TEXT,
          local_relative_path TEXT,
          availability TEXT NOT NULL CHECK (availability IN ('on_device', 'at_source', 'unavailable')),
          last_verified_at_ms INTEGER,
          CHECK ((availability = 'on_device') = (local_relative_path IS NOT NULL))
        ) STRICT;
        CREATE INDEX asset_location_asset ON asset_location(asset_id);

        CREATE TABLE consumption_run (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
          state TEXT NOT NULL CHECK (state IN ('planned', 'in_progress', 'paused', 'finished', 'abandoned')),
          started_date TEXT,
          started_date_precision TEXT CHECK (started_date_precision IN ('year', 'month', 'day')),
          finished_date TEXT,
          finished_date_precision TEXT CHECK (finished_date_precision IN ('year', 'month', 'day')),
          manual_completion INTEGER NOT NULL DEFAULT 0 CHECK (manual_completion IN (0, 1)),
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          CHECK ((started_date IS NULL) = (started_date_precision IS NULL)),
          CHECK ((finished_date IS NULL) = (finished_date_precision IS NULL))
        ) STRICT;
        CREATE INDEX consumption_run_work ON consumption_run(work_id);

        CREATE TABLE rating (
          work_id TEXT PRIMARY KEY NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
          value INTEGER CHECK (value IS NULL OR value BETWEEN 1 AND 10),
          scale TEXT NOT NULL DEFAULT 'half_stars_1_10' CHECK (scale = 'half_stars_1_10'),
          updated_at_ms INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE recommendation_event (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
          direction TEXT NOT NULL,
          counterpart_kind TEXT,
          counterpart_label TEXT NOT NULL,
          event_date TEXT,
          reason TEXT,
          url TEXT,
          recorded_at_ms INTEGER NOT NULL
        ) STRICT;
        CREATE INDEX recommendation_event_work ON recommendation_event(work_id);

        CREATE TABLE capture (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
          edition_id TEXT REFERENCES edition(id) ON DELETE RESTRICT,
          kind TEXT NOT NULL CHECK (kind IN ('quote', 'note', 'audio', 'generated', 'word')),
          quoted_text TEXT,
          source_snapshot_json TEXT NOT NULL CHECK (json_valid(source_snapshot_json)),
          idempotency_key TEXT NOT NULL UNIQUE,
          revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          trashed_at_ms INTEGER,
          CHECK (kind <> 'quote' OR quoted_text IS NOT NULL),
          CHECK (kind <> 'audio' OR quoted_text IS NULL)
        ) STRICT;
        CREATE INDEX capture_work ON capture(work_id);
        CREATE INDEX capture_edition ON capture(edition_id);

        CREATE TABLE capture_anchor (
          capture_id TEXT NOT NULL REFERENCES capture(id) ON DELETE CASCADE,
          ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
          schema_version INTEGER NOT NULL CHECK (schema_version >= 1),
          kind TEXT NOT NULL CHECK (kind IN ('epub', 'pdf', 'text', 'audio', 'manual')),
          work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
          edition_id TEXT REFERENCES edition(id) ON DELETE RESTRICT,
          asset_id TEXT REFERENCES asset(id) ON DELETE RESTRICT,
          asset_sha256 TEXT CHECK (asset_sha256 IS NULL OR (\(hex64("asset_sha256")))),
          start_ms INTEGER CHECK (start_ms >= 0),
          end_ms INTEGER,
          text_offset_unit TEXT CHECK (text_offset_unit IN ('unicode_scalar')),
          locator_json TEXT NOT NULL CHECK (json_valid(locator_json)),
          adapter_payload TEXT,
          PRIMARY KEY (capture_id, ordinal),
          CHECK ((asset_id IS NULL) = (asset_sha256 IS NULL)),
          CHECK (kind <> 'audio' OR (asset_id IS NOT NULL AND start_ms IS NOT NULL AND end_ms > start_ms))
        ) STRICT;
        CREATE INDEX capture_anchor_asset ON capture_anchor(asset_id);
        CREATE INDEX capture_anchor_work ON capture_anchor(work_id);
        CREATE INDEX capture_anchor_edition ON capture_anchor(edition_id);

        CREATE TABLE conversation (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          work_id TEXT REFERENCES work(id) ON DELETE RESTRICT,
          capture_id TEXT REFERENCES capture(id) ON DELETE RESTRICT,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL
        ) STRICT;
        CREATE INDEX conversation_work ON conversation(work_id);
        CREATE INDEX conversation_capture ON conversation(capture_id);

        CREATE TABLE context_pack (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          request_id TEXT NOT NULL UNIQUE,
          schema_version INTEGER NOT NULL CHECK (schema_version >= 1),
          scope TEXT NOT NULL CHECK (scope IN ('selected_passage', 'passage_and_nearby', 'work_relevant', 'selected_thoughts')),
          mode TEXT NOT NULL,
          coverage TEXT NOT NULL,
          question TEXT NOT NULL,
          truncated INTEGER NOT NULL CHECK (truncated IN (0, 1)),
          retrieval_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(retrieval_json)),
          endpoint_json TEXT NOT NULL CHECK (json_valid(endpoint_json)),
          prompt_template_version TEXT NOT NULL,
          created_at_ms INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE context_evidence (
          context_pack_id TEXT NOT NULL REFERENCES context_pack(id) ON DELETE CASCADE,
          citation_id TEXT NOT NULL,
          ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
          capture_id TEXT REFERENCES capture(id) ON DELETE RESTRICT,
          origin TEXT NOT NULL CHECK (origin IN ('source_text', 'capture', 'note', 'transcript')),
          text TEXT NOT NULL,
          text_sha256 TEXT NOT NULL CHECK (\(hex64("text_sha256"))),
          anchor_json TEXT CHECK (anchor_json IS NULL OR json_valid(anchor_json)),
          location_label TEXT,
          PRIMARY KEY (context_pack_id, citation_id)
        ) STRICT;
        CREATE INDEX context_evidence_capture ON context_evidence(capture_id);

        CREATE TABLE message (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          conversation_id TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
          ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
          role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
          content TEXT NOT NULL,
          state TEXT NOT NULL CHECK (state IN ('draft', 'sending', 'generated', 'complete', 'interrupted')),
          provider_json TEXT CHECK (provider_json IS NULL OR json_valid(provider_json)),
          request_id TEXT,
          context_pack_id TEXT REFERENCES context_pack(id) ON DELETE RESTRICT,
          created_at_ms INTEGER NOT NULL,
          UNIQUE (conversation_id, ordinal)
        ) STRICT;
        CREATE INDEX message_context_pack ON message(context_pack_id);

        CREATE TABLE note (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
          capture_id TEXT REFERENCES capture(id) ON DELETE RESTRICT,
          conversation_id TEXT REFERENCES conversation(id) ON DELETE RESTRICT,
          current_revision INTEGER NOT NULL CHECK (current_revision >= 1),
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          trashed_at_ms INTEGER
        ) STRICT;
        CREATE INDEX note_work ON note(work_id);
        CREATE INDEX note_capture ON note(capture_id);
        CREATE INDEX note_conversation ON note(conversation_id);

        CREATE TABLE note_revision (
          note_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
          revision INTEGER NOT NULL CHECK (revision >= 1),
          body TEXT NOT NULL,
          format TEXT NOT NULL CHECK (format IN ('plain', 'markdown')),
          origin TEXT NOT NULL CHECK (origin IN ('user', 'transcript_correction', 'ai_derived')),
          saved_at_ms INTEGER NOT NULL,
          PRIMARY KEY (note_id, revision)
        ) STRICT;

        CREATE TABLE retained_excerpt (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          capture_id TEXT NOT NULL REFERENCES capture(id) ON DELETE RESTRICT,
          blob_sha256 TEXT NOT NULL CHECK (\(hex64("blob_sha256"))),
          byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
          media_type TEXT NOT NULL,
          file_extension TEXT NOT NULL CHECK (length(file_extension) BETWEEN 1 AND 8 AND file_extension NOT GLOB '*[^a-z0-9]*'),
          source_ranges_json TEXT NOT NULL CHECK (json_valid(source_ranges_json)),
          clip_duration_ms INTEGER NOT NULL CHECK (clip_duration_ms >= 0),
          export_state TEXT NOT NULL CHECK (export_state IN ('pending', 'preserved', 'failed')),
          created_at_ms INTEGER NOT NULL,
          CHECK (export_state <> 'preserved' OR byte_count > 0)
        ) STRICT;
        CREATE INDEX retained_excerpt_capture ON retained_excerpt(capture_id);
        CREATE INDEX retained_excerpt_blob ON retained_excerpt(blob_sha256);

        CREATE TABLE ledger_event (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
          run_id TEXT REFERENCES consumption_run(id) ON DELETE RESTRICT,
          capture_id TEXT REFERENCES capture(id) ON DELETE SET NULL,
          event_type TEXT NOT NULL,
          effective_date TEXT,
          effective_date_precision TEXT CHECK (effective_date_precision IN ('year', 'month', 'day')),
          recorded_at_ms INTEGER NOT NULL,
          payload_version INTEGER NOT NULL CHECK (payload_version >= 1),
          payload_json TEXT NOT NULL CHECK (json_valid(payload_json)),
          CHECK ((effective_date IS NULL) = (effective_date_precision IS NULL))
        ) STRICT;
        CREATE INDEX ledger_event_work ON ledger_event(work_id);
        CREATE INDEX ledger_event_run ON ledger_event(run_id);
        CREATE INDEX ledger_event_capture ON ledger_event(capture_id);

        CREATE TABLE change_journal (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          entity TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          revision INTEGER,
          operation TEXT NOT NULL CHECK (operation IN ('insert', 'update', 'delete', 'trash', 'restore')),
          recorded_at_ms INTEGER NOT NULL
        ) STRICT;
        CREATE INDEX change_journal_entity ON change_journal(entity, entity_id);

        CREATE TABLE export_record (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          manifest_schema_version INTEGER NOT NULL,
          library_schema_version INTEGER NOT NULL,
          created_at_ms INTEGER NOT NULL,
          snapshot_journal_seq INTEGER NOT NULL,
          counts_json TEXT NOT NULL CHECK (json_valid(counts_json)),
          manifest_sha256 TEXT NOT NULL CHECK (\(hex64("manifest_sha256"))),
          status TEXT NOT NULL CHECK (status IN ('completed', 'failed'))
        ) STRICT;

        -- Processing data, not knowledge: a temporary hold that stops blob cleanup from removing a
        -- retained excerpt while an export copies it (plan 17.4). Cleared on restore.
        CREATE TABLE retention_lease (
          id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
          blob_sha256 TEXT NOT NULL CHECK (\(hex64("blob_sha256"))),
          holder TEXT NOT NULL,
          acquired_at_ms INTEGER NOT NULL,
          expires_at_ms INTEGER NOT NULL CHECK (expires_at_ms > acquired_at_ms)
        ) STRICT;
        CREATE INDEX retention_lease_blob ON retention_lease(blob_sha256);
        """
}
