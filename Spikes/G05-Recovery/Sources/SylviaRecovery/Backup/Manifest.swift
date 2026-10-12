import Foundation

/// `manifest.json` of a `.sylviabackup` (plan 17.3). Contract:
/// `Contracts/schemas/backup-manifest.v1.schema.json` (`urn:sylvia:schema:backup-manifest:v1`).
public struct BackupManifest: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let formatName = "sylviabackup"
    public static let fileName = "manifest.json"
    /// Upper bound on the manifest size a reader will parse (malicious-manifest defense).
    public static let maximumBytes = 4 << 20

    public var schema_version: Int
    public var format: String
    public var backup_id: String
    /// RFC 3339 UTC, e.g. "2026-10-06T01:02:03.004Z".
    public var created_at: String
    public var originating_device_id: String
    public var library: Library
    public var snapshot: SnapshotBoundary
    public var counts: [String: Int64]
    public var included_classes: [String]
    public var excluded_classes: [Exclusion]
    /// Original media not in this backup, identified so the restore can show it as unavailable (I-09).
    public var excluded_media: [ExcludedAsset]
    /// True exactly when no original media known to the library was left out (`excluded_media` is
    /// empty). Indexes, staging and secrets are never backed up and do not count. The UI must not
    /// call a backup "complete" when this is false (plan 17.3).
    public var complete: Bool
    public var encryption: String
    public var files: [FileEntry]

    public struct Library: Codable, Sendable, Equatable {
        public var schema_version: Int
        public var migrations: [String]
    }

    public struct SnapshotBoundary: Codable, Sendable, Equatable {
        /// Highest ChangeJournal sequence inside the snapshot; later edits are not in this backup.
        public var change_journal_seq: Int64
        public var method: String
    }

    public struct Exclusion: Codable, Sendable, Equatable {
        public var `class`: String
        public var reason: String
    }

    public struct ExcludedAsset: Codable, Sendable, Equatable {
        public var asset_id: String
        public var sha256: String
        public var byte_count: Int64
        public var media_type: String
    }

    public struct FileEntry: Codable, Sendable, Equatable {
        public var path: String
        public var role: Role
        public var sha256: String
        public var byte_count: Int64
    }

    public enum Role: String, Codable, Sendable, CaseIterable {
        case database_snapshot
        case portable_json
        case markdown
        case retained_excerpt
        case cover_thumbnail
    }

    /// The contract's `storage_class` enum (plan 17.1 classes and the parts of a backup).
    public static let storageClasses: Set<String> = [
        "permanent_knowledge", "retained_excerpt_audio", "saved_ai_evidence", "canonical_cover_thumbnail",
        "database_snapshot", "portable_json", "markdown", "original_media", "derived_source_text",
        "rebuildable_indexes", "staging_recovery", "secrets",
    ]

    public static let snapshotMethod = "sqlite_online_backup"

    public static let includedClasses = [
        "permanent_knowledge", "retained_excerpt_audio", "saved_ai_evidence", "canonical_cover_thumbnail",
        "database_snapshot", "portable_json", "markdown",
    ]

    public static let standardExclusions = [
        Exclusion(class: "original_media", reason: "Knowledge backup; originals are listed in excluded_media."),
        Exclusion(class: "derived_source_text", reason: "Full extracted text is optional and not included."),
        Exclusion(class: "rebuildable_indexes", reason: "Search indexes and thumbnails beyond the canonical cover are rebuilt after restore."),
        Exclusion(class: "staging_recovery", reason: "Partial transfers, staging and recovery copies."),
        Exclusion(class: "secrets", reason: "Provider keys and pairing identity stay in the Keychain."),
    ]
}

/// Paths inside a bundle: relative, "/"-separated, every component `[A-Za-z0-9][A-Za-z0-9._-]*`.
/// No absolute paths, no ".." or ".", no backslashes, no empty components, nothing outside ASCII.
public enum BundlePath {
    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 512, !path.hasPrefix("/"), !path.hasSuffix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= 8 else { return false }
        for component in components {
            guard (1...128).contains(component.utf8.count), component != ".", component != ".." else { return false }
            let bytes = Array(component.utf8)
            guard isAlnum(bytes[0]) else { return false }
            for byte in bytes where !(isAlnum(byte) || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")) {
                return false
            }
        }
        return true
    }

    private static func isAlnum(_ b: UInt8) -> Bool {
        (48...57).contains(b) || (65...90).contains(b) || (97...122).contains(b)
    }

    /// The only path each role may use.
    public static func matchesRole(_ path: String, _ role: BackupManifest.Role) -> Bool {
        switch role {
        case .database_snapshot: return path == "database/library.sqlite"
        case .portable_json: return path == "export/library.json"
        case .markdown: return path.hasPrefix("export/markdown/") && path.hasSuffix(".md") && path.split(separator: "/").count == 3
        case .retained_excerpt:
            let parts = path.split(separator: "/")
            guard parts.count == 3, parts[0] == "blobs", parts[1] == "excerpts" else { return false }
            let name = parts[2].split(separator: ".", omittingEmptySubsequences: false)
            // Same rule as the contract and the retained_excerpt.file_extension CHECK: [a-z0-9]{1,8}.
            return name.count == 2 && Digest.isHex64(String(name[0])) && (1...8).contains(name[1].count)
                && name[1].utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) }
        case .cover_thumbnail:
            let parts = path.split(separator: "/")
            guard parts.count == 3, parts[0] == "blobs", parts[1] == "covers" else { return false }
            let name = parts[2].split(separator: ".", omittingEmptySubsequences: false)
            // Same rule as the contract and the edition.cover_thumbnail_extension CHECK.
            return name.count == 2 && Digest.isHex64(String(name[0])) && CoverStore.allowedExtensions.contains(String(name[1]))
        }
    }
}

public enum BackupError: Error, Equatable, CustomStringConvertible {
    case notABundle(String)
    case manifestMissing
    case manifestTooLarge(Int64)
    case manifestUnreadable(String)
    case unsupportedManifestVersion(Int)
    case unsupportedFormat(String)
    /// The backup was made by a newer Sylvia: library schema or migrations this build does not know.
    case newerLibrarySchema(found: Int, supported: Int, unknownMigrations: [String])
    case unsafePath(String)
    case duplicatePath(String)
    case roleMismatch(path: String, role: String)
    case symlinkInBundle(String)
    case notARegularFile(String)
    case missingFile(String)
    case unlistedFile(String)
    case sizeMismatch(path: String, expected: Int64, actual: Int64)
    case digestMismatch(path: String)
    case invalidField(String)
    case databaseCount(Int)
    case corruptDatabase(String)
    /// The snapshot's schema (tables, indexes, triggers, views) is not the one this build's
    /// migrations produce for the snapshot's migration list.
    case schemaMismatch(String)
    /// `excluded_media` or `complete` does not describe the snapshot's assets (I-09).
    case excludedMediaMismatch(String)
    case foreignKeyViolations(Int)
    /// Row values the schema does not constrain but this build rejects (`RowCheck`): an effective
    /// date that is not a date of its precision, or a ChangeJournal sequence that is not the highest
    /// journal entry.
    case invalidRows(String)
    case countMismatch(table: String, expected: Int64, actual: Int64)
    case missingBlob(String)
    case unreferencedBlob(String)
    case insufficientSpace(required: Int64, available: Int64)
    case destinationExists(String)
    case confirmationRequired
    case simulatedCrash(String)

    public var description: String {
        switch self {
        case .notABundle(let why): return "not a .sylviabackup bundle: \(why)"
        case .manifestMissing: return "manifest.json is missing"
        case .manifestTooLarge(let n): return "manifest.json is too large (\(n) bytes)"
        case .manifestUnreadable(let why): return "manifest.json is unreadable: \(why)"
        case .unsupportedManifestVersion(let v): return "backup manifest version \(v) is not supported"
        case .unsupportedFormat(let f): return "unsupported backup format \(f)"
        case .newerLibrarySchema(let found, let supported, let unknown):
            return "backup was written by a newer Sylvia (library schema \(found), this build supports \(supported); unknown migrations: \(unknown.joined(separator: ", ")))"
        case .unsafePath(let p): return "unsafe path in manifest: \(p)"
        case .duplicatePath(let p): return "duplicate path in manifest: \(p)"
        case .roleMismatch(let p, let r): return "path \(p) is not allowed for role \(r)"
        case .symlinkInBundle(let p): return "symbolic link in bundle: \(p)"
        case .notARegularFile(let p): return "not a regular file: \(p)"
        case .missingFile(let p): return "missing file: \(p)"
        case .unlistedFile(let p): return "file not listed in manifest: \(p)"
        case .sizeMismatch(let p, let e, let a): return "size mismatch for \(p): manifest \(e), file \(a)"
        case .digestMismatch(let p): return "SHA-256 mismatch for \(p)"
        case .invalidField(let f): return "invalid manifest field: \(f)"
        case .databaseCount(let n): return "expected exactly one database snapshot, found \(n)"
        case .corruptDatabase(let why): return "database snapshot failed checks: \(why)"
        case .schemaMismatch(let why): return "database snapshot schema does not match this build's schema for its migrations: \(why)"
        case .excludedMediaMismatch(let why): return "excluded_media does not match the snapshot's assets: \(why)"
        case .foreignKeyViolations(let n): return "database snapshot has \(n) foreign key violations"
        case .invalidRows(let why): return "database snapshot has values this build rejects: \(why)"
        case .countMismatch(let t, let e, let a): return "row count for \(t): manifest \(e), database \(a)"
        case .missingBlob(let sha): return "blob \(sha) referenced by the snapshot is missing"
        case .unreferencedBlob(let sha): return "blob \(sha) is not referenced by the snapshot"
        case .insufficientSpace(let r, let a): return "insufficient space: need \(r) bytes, \(a) available"
        case .destinationExists(let p): return "destination already exists: \(p)"
        case .confirmationRequired: return "restore replaces the library and needs confirmation"
        case .simulatedCrash(let step): return "simulated crash after \(step)"
        }
    }
}

enum RFC3339 {
    static func string(millis: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    static func isValid(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return value.hasSuffix("Z") }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil && value.hasSuffix("Z")
    }
}
