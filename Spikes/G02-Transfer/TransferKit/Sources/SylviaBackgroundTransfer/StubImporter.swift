import Foundation
import Synchronization
import SylviaTransferCore

/// Stand-in for Sylvia's importer (plan 8.1), used to prove the transfer client hands each verified
/// item version over exactly once, also across crashes and relaunches (T38 "single import").
///
/// It does what the handoff needs and nothing more: it moves the verified files into a library folder
/// and records the import in a durable ledger keyed by item version. It does not parse, index or
/// display the book; that is the real importer's job in M1.
///
/// Exactly once: the ledger first records an "importing" intent with a fixed import ID and
/// destination, then moves the files (a rename, idempotent when repeated), then records "imported".
/// A stop between those steps is completed by the next call; a call after "imported" changes nothing
/// and is counted as a duplicate request.
public final class StubImporter: Sendable {
    public struct ImportedAsset: Codable, Hashable, Sendable {
        public var assetID: String
        public var sha256: String
        public var length: Int64

        enum CodingKeys: String, CodingKey {
            case assetID = "asset_id"
            case sha256
            case length
        }
    }

    public struct Record: Codable, Hashable, Sendable {
        public enum State: String, Codable, Hashable, Sendable {
            case importing
            case imported
        }

        public var importID: String
        public var jobID: String
        public var itemID: String
        public var itemVersionID: String
        public var assets: [ImportedAsset]
        public var state: State
        public var startedAt: Date
        public var importedAt: Date?
        /// Times the record moved to `imported`. Always 0 or 1; tests assert it.
        public var completions: Int
        /// Calls that arrived after the import was complete and changed nothing.
        public var duplicateRequests: Int

        enum CodingKeys: String, CodingKey {
            case importID = "import_id"
            case jobID = "job_id"
            case itemID = "item_id"
            case itemVersionID = "item_version_id"
            case assets
            case state
            case startedAt = "started_at"
            case importedAt = "imported_at"
            case completions
            case duplicateRequests = "duplicate_requests"
        }
    }

    public struct VerifiedAsset: Sendable {
        public var assetID: String
        public var url: URL
        public var sha256: String
        public var length: Int64

        public init(assetID: String, url: URL, sha256: String, length: Int64) {
            self.assetID = assetID
            self.url = url
            self.sha256 = sha256
            self.length = length
        }
    }

    public enum Outcome: Equatable, Sendable {
        case imported(Record)
        case alreadyImported(Record)
    }

    public enum ImportError: Error, Equatable, Sendable {
        case missingVerifiedFile(assetID: String)
        case lengthMismatch(assetID: String)
        /// imports.json exists but cannot be read now; importing would overwrite the record of earlier imports.
        case ledgerUnreadable
        case io(String)
    }

    public let ledgerURL: URL
    public let libraryRoot: URL
    /// Nil while imports.json exists but cannot be read (before the first unlock, or damaged).
    private let ledger: Mutex<[String: Record]?>
    /// Test hook: called at named points ("after_intent", "after_move:<asset_id>"); throwing simulates a stop there.
    private let stopHook: Mutex<(@Sendable (String) throws -> Void)?> = Mutex(nil)

    public init(root: URL) throws {
        ledgerURL = root.appendingPathComponent("imports.json")
        libraryRoot = root.appendingPathComponent("Library", isDirectory: true)
        try DurableFile.createDirectory(libraryRoot)
        ledger = Mutex(Self.read(ledgerURL))
    }

    private static func read(_ url: URL) -> [String: Record]? {
        do { return try DurableFile.readJSON([String: Record].self, from: url) ?? [:] } catch { return nil }
    }

    /// Reads the ledger again (after protected data became available). Returns whether it is readable now.
    @discardableResult
    public func reload() -> Bool {
        let fresh = Self.read(ledgerURL)
        ledger.withLock { $0 = fresh }
        return fresh != nil
    }

    /// Whether imports.json exists but could not be read; then nothing is imported and nothing is written.
    public var isUnreadable: Bool { ledger.withLock { $0 == nil } }

    public func setStopHook(_ hook: (@Sendable (String) throws -> Void)?) { stopHook.withLock { $0 = hook } }

    public var records: [Record] { ledger.withLock { Array(($0 ?? [:]).values) }.sorted { $0.startedAt < $1.startedAt } }

    public func record(itemVersionID: String) -> Record? { ledger.withLock { $0?[itemVersionID] } }

    public func destination(importID: String, assetID: String) -> URL {
        libraryRoot.appendingPathComponent(importID, isDirectory: true).appendingPathComponent(assetID + ".bin")
    }

    public func importVerified(
        jobID: String, itemID: String, itemVersionID: String, assets: [VerifiedAsset], now: Date = Date()
    ) throws(ImportError) -> Outcome {
        let hook = stopHook.withLock { $0 }
        return try ledger.withLock { (stored: inout [String: Record]?) throws(ImportError) -> Outcome in
            // A ledger that exists but could not be read is never replaced by an empty one: that would
            // forget earlier imports and break exactly-once (review finding R1-04).
            guard var ledger = stored else { throw .ledgerUnreadable }
            defer { stored = ledger }
            if var existing = ledger[itemVersionID], existing.state == .imported {
                existing.duplicateRequests += 1
                ledger[itemVersionID] = existing
                try persist(ledger)
                return .alreadyImported(existing)
            }
            var record = ledger[itemVersionID] ?? Record(
                importID: CanonicalID.make(), jobID: jobID, itemID: itemID, itemVersionID: itemVersionID,
                assets: assets.map { ImportedAsset(assetID: $0.assetID, sha256: $0.sha256, length: $0.length) },
                state: .importing, startedAt: now, importedAt: nil, completions: 0, duplicateRequests: 0)
            if ledger[itemVersionID] == nil {
                ledger[itemVersionID] = record
                try persist(ledger)
            }
            do { try hook?("after_intent") } catch { throw .io("stopped after intent") }

            let fileManager = FileManager.default
            do {
                try DurableFile.createDirectory(libraryRoot.appendingPathComponent(record.importID, isDirectory: true))
            } catch {
                throw .io("library folder")
            }
            for asset in record.assets {
                let target = destination(importID: record.importID, assetID: asset.assetID)
                if let size = (try? fileManager.attributesOfItem(atPath: target.path))?[.size] as? NSNumber {
                    guard size.int64Value == asset.length else { throw .lengthMismatch(assetID: asset.assetID) }
                    continue  // moved before a stop
                }
                guard let source = assets.first(where: { $0.assetID == asset.assetID })?.url,
                    fileManager.fileExists(atPath: source.path)
                else { throw .missingVerifiedFile(assetID: asset.assetID) }
                guard rename(source.path, target.path) == 0 else { throw .io("move") }
                do { try hook?("after_move:\(asset.assetID)") } catch { throw .io("stopped after move") }
            }
            record.state = .imported
            record.importedAt = now
            record.completions += 1
            ledger[itemVersionID] = record
            try persist(ledger)
            return .imported(record)
        }
    }

    private func persist(_ ledger: [String: Record]) throws(ImportError) {
        do { try DurableFile.writeJSON(ledger, to: ledgerURL) } catch { throw .io("ledger") }
    }
}
