import Foundation
import GRDB

/// Where an asset's bytes are, as the UI must describe it (plan 4.4.6 "Where a file is").
public enum AssetAvailability: Sendable, Equatable {
    /// "On this device"; the file exists and has the recorded size.
    case onDevice(URL)
    /// "Not on this device · from {source}".
    case atSource(sourceKind: String)
    /// "Record only": no reachable copy. The work, edition, asset identity and all knowledge remain.
    case recordOnly
}

/// What removing a work's original media would affect (plan 17.2 impact report).
public struct RemovalImpact: Sendable, Equatable {
    public var assetCount = 0
    public var bytesFreed: Int64 = 0
    public var captures = 0
    public var notes = 0
    public var ledgerEvents = 0
    public var recommendations = 0
    public var hasRating = false
    public var excerptsPreserved = 0
    public var excerptsPending = 0
    public var contextEvidence = 0
    /// Assets that are also members of another work's editions (removing bytes affects both).
    public var sharedWithOtherWorks = 0
}

public enum PendingExcerptPolicy: Sendable {
    /// "Wait, then remove" (the safe primary choice): refuse while any excerpt is pending.
    case waitForPendingExcerpts
    /// The user explicitly chose to remove anyway.
    case removeAnyway
}

/// Original media: import into `Library/Media/<asset-id>/`, availability, and removal (T44).
///
/// Removal changes `asset_location` availability and deletes files; it never deletes `asset`,
/// `edition` or `work` rows, and every knowledge table references media with `ON DELETE RESTRICT`,
/// so even a buggy delete of an asset row would fail rather than cascade into knowledge.
public struct MediaService: Sendable {
    public let store: LibraryStore

    public init(_ store: LibraryStore) { self.store = store }

    /// Copies a file into managed storage and records Asset, EditionAsset and an on-device
    /// AssetLocation. Same bytes already known: reuses the asset (I-02 "Already imported").
    @discardableResult
    public func importOriginal(_ file: URL, id: String = EntityID.make(), editionID: String, role: String, sequence: Int,
                               mediaType: String, durationMs: Int64? = nil, sourceKind: String = "local_import",
                               sourceID: String? = nil) throws -> String {
        let (sha, size) = try Digest.sha256Hex(fileAt: file)
        let existing = try store.pool.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM asset WHERE sha256 = ?", arguments: [sha])
        }
        let assetID = existing ?? id
        let directory = store.layout.mediaDirectory.appending(path: assetID, directoryHint: .isDirectory)
        try store.protector.ensureDirectory(directory)
        let name = Self.safeFileName(file.lastPathComponent)
        let destination = directory.appending(path: name, directoryHint: .notDirectory)
        if !FileManager.default.fileExists(atPath: destination.path) {
            let temp = store.layout.stagingDirectory.appending(path: "\(EntityID.make()).media", directoryHint: .notDirectory)
            try store.protector.copyFile(from: file, to: temp)
            try DurableFile.sync(temp)
            try DurableFile.rename(temp, to: destination)
            try DurableFile.syncDirectory(directory)
        }
        let relative = "Media/\(assetID)/\(name)"
        try store.pool.write { db in
            let now = store.clock.nowMillis()
            if existing == nil {
                try store.insertJournaled(db, "asset", id: assetID, [
                    "id": assetID, "sha256": sha, "byte_count": size, "media_type": mediaType,
                    "original_filename": file.lastPathComponent, "duration_ms": durationMs,
                    "validation_status": "valid", "created_at_ms": now,
                ])
            }
            let member = try Bool.fetchOne(db, sql: "SELECT 1 FROM edition_asset WHERE edition_id = ? AND asset_id = ?",
                                           arguments: [editionID, assetID]) ?? false
            if !member {
                try LibraryStore.insert(db, "edition_asset", [
                    "edition_id": editionID, "asset_id": assetID, "role": role, "sequence": sequence, "timeline_revision": 1,
                ])
                try LibraryStore.journal(db, "edition_asset", "\(editionID)/\(assetID)", "insert", at: now)
            }
            let locationID = try String.fetchOne(db, sql: "SELECT id FROM asset_location WHERE asset_id = ? AND source_kind = ?",
                                                 arguments: [assetID, sourceKind])
            if let locationID {
                try db.execute(sql: """
                    UPDATE asset_location SET availability = 'on_device', local_relative_path = ?, last_verified_at_ms = ?
                    WHERE id = ?
                    """, arguments: [relative, now, locationID])
                try LibraryStore.journal(db, "asset_location", locationID, "update", at: now)
            } else {
                let newID = EntityID.make()
                try store.insertJournaled(db, "asset_location", id: newID, [
                    "id": newID, "asset_id": assetID, "source_kind": sourceKind, "source_id": sourceID,
                    "source_item": nil, "source_version": nil, "local_relative_path": relative,
                    "availability": "on_device", "last_verified_at_ms": now,
                ])
            }
        }
        return assetID
    }

    /// Resolves an asset for playback/reading. A missing file is reported as unavailable (never as a
    /// corrupt record) and never throws for a known asset.
    public func availability(assetID: String) throws -> AssetAvailability {
        let rows = try store.pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT l.availability, l.local_relative_path, l.source_kind, a.byte_count
                FROM asset a LEFT JOIN asset_location l ON l.asset_id = a.id WHERE a.id = ?
                """, arguments: [assetID])
        }
        guard !rows.isEmpty else { throw StoreError.notFound(entity: "asset", id: assetID) }
        for row in rows where (row["availability"] as String?) == "on_device" {
            guard let relative = row["local_relative_path"] as String?,
                  let url = Self.resolveInsideLibrary(relative, layout: store.layout) else { continue }
            if FileManager.default.sizeOfFile(at: url) == (row["byte_count"] as Int64? ?? -1),
               FileManager.default.fileExists(atPath: url.path) {
                return .onDevice(url)
            }
        }
        if let source = rows.first(where: { ($0["availability"] as String?) == "at_source" }) {
            return .atSource(sourceKind: source["source_kind"] ?? "source")
        }
        return .recordOnly
    }

    public func removalImpact(workID: String) throws -> RemovalImpact {
        try store.pool.read { db in
            var impact = RemovalImpact()
            let assets = try Row.fetchAll(db, sql: """
                SELECT DISTINCT a.id, a.byte_count FROM asset a
                JOIN edition_asset ea ON ea.asset_id = a.id JOIN edition e ON e.id = ea.edition_id
                JOIN asset_location l ON l.asset_id = a.id
                WHERE e.work_id = ? AND ea.role <> 'cover' AND l.availability = 'on_device'
                """, arguments: [workID])
            impact.assetCount = assets.count
            impact.bytesFreed = assets.reduce(0) { $0 + ($1["byte_count"] as Int64? ?? 0) }
            for asset in assets {
                let others = try Int.fetchOne(db, sql: """
                    SELECT count(*) FROM edition_asset ea JOIN edition e ON e.id = ea.edition_id
                    WHERE ea.asset_id = ? AND e.work_id <> ?
                    """, arguments: [asset["id"] as String, workID]) ?? 0
                if others > 0 { impact.sharedWithOtherWorks += 1 }
            }
            func count(_ sql: String) throws -> Int { try Int.fetchOne(db, sql: sql, arguments: [workID]) ?? 0 }
            impact.captures = try count("SELECT count(*) FROM capture WHERE work_id = ?")
            impact.notes = try count("SELECT count(*) FROM note WHERE work_id = ?")
            impact.ledgerEvents = try count("SELECT count(*) FROM ledger_event WHERE work_id = ?")
            impact.recommendations = try count("SELECT count(*) FROM recommendation_event WHERE work_id = ?")
            impact.hasRating = try count("SELECT count(*) FROM rating WHERE work_id = ? AND value IS NOT NULL") > 0
            impact.excerptsPreserved = try count("""
                SELECT count(*) FROM retained_excerpt r JOIN capture c ON c.id = r.capture_id
                WHERE c.work_id = ? AND r.export_state = 'preserved'
                """)
            impact.excerptsPending = try count("""
                SELECT count(*) FROM retained_excerpt r JOIN capture c ON c.id = r.capture_id
                WHERE c.work_id = ? AND r.export_state = 'pending'
                """)
            impact.contextEvidence = try count("""
                SELECT count(*) FROM context_evidence ev JOIN capture c ON c.id = ev.capture_id WHERE c.work_id = ?
                """)
            return impact
        }
    }

    /// "Remove download" for every original of a work (T44). Commits the availability change first,
    /// then deletes files; a crash in between leaves orphan files that `sweepOrphanMedia` removes,
    /// never a record that claims a file is on the device when it is not.
    @discardableResult
    public func removeAllOriginalMedia(workID: String, policy: PendingExcerptPolicy = .waitForPendingExcerpts) throws -> RemovalImpact {
        let impact = try removalImpact(workID: workID)
        if impact.excerptsPending > 0, policy == .waitForPendingExcerpts {
            throw StoreError.excerptsPending(count: impact.excerptsPending)
        }
        let removedAssets: [String] = try store.pool.write { db in
            let now = store.clock.nowMillis()
            let locations = try Row.fetchAll(db, sql: """
                SELECT DISTINCT l.id, l.asset_id, l.source_id FROM asset_location l
                JOIN edition_asset ea ON ea.asset_id = l.asset_id JOIN edition e ON e.id = ea.edition_id
                WHERE e.work_id = ? AND ea.role <> 'cover' AND l.availability = 'on_device'
                """, arguments: [workID])
            for location in locations {
                let next = (location["source_id"] as String?) == nil ? "unavailable" : "at_source"
                try db.execute(sql: """
                    UPDATE asset_location SET availability = ?, local_relative_path = NULL, last_verified_at_ms = ?
                    WHERE id = ?
                    """, arguments: [next, now, location["id"] as String])
                try LibraryStore.journal(db, "asset_location", location["id"], "update", at: now)
            }
            return Array(Set(locations.map { $0["asset_id"] as String })).sorted()
        }
        for assetID in removedAssets {
            try removeMediaDirectoryIfUnreferenced(assetID)
        }
        try DurableFile.syncDirectory(store.layout.mediaDirectory)
        return impact
    }

    /// Deletes `Media/<id>/` directories that no on-device location points at (crash leftovers).
    @discardableResult
    public func sweepOrphanMedia() throws -> [String] {
        let directories = try FileManager.default.contentsOfDirectory(atPath: store.layout.mediaDirectory.path)
        var removed: [String] = []
        for name in directories.sorted() where try removeMediaDirectoryIfUnreferenced(name) {
            removed.append(name)
        }
        return removed
    }

    @discardableResult
    private func removeMediaDirectoryIfUnreferenced(_ assetID: String) throws -> Bool {
        guard EntityID.isValid(assetID) else { return false }
        let stillOnDevice = try store.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM asset_location WHERE asset_id = ? AND availability = 'on_device'",
                             arguments: [assetID]) ?? 0
        }
        guard stillOnDevice == 0 else { return false }
        let directory = store.layout.mediaDirectory.appending(path: assetID, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        try FileManager.default.removeItem(at: directory)
        return true
    }

    /// Accepts only `Media/<uuid>/<safe name>` and returns a URL inside the library.
    static func resolveInsideLibrary(_ relative: String, layout: LibraryLayout) -> URL? {
        guard BundlePath.isSafeRelativePath(relative), relative.hasPrefix("Media/") else { return nil }
        return layout.libraryDirectory.appending(path: relative, directoryHint: .notDirectory)
    }

    static func safeFileName(_ name: String) -> String {
        let allowed = name.unicodeScalars.map { scalar -> Character in
            let ok = (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar)))
            return ok ? Character(scalar) : "_"
        }
        var result = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if result.isEmpty { result = "file" }
        if !(result.first!.isLetter || result.first!.isNumber) { result = "f" + result }
        return String(result.prefix(120))
    }
}
