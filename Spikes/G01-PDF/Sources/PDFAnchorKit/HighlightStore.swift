import Foundation

/// A Sylvia-side highlight record: the quotation and its anchor live here, never in the PDF (plan 9.2, 11.1).
public struct HighlightRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var anchor: PDFAnchor

    public init(id: UUID = UUID(), createdAt: Date = Date(), anchor: PDFAnchor) {
        self.id = id
        self.createdAt = createdAt
        self.anchor = anchor
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case anchor
    }
}

/// Stage 0 stand-in for the capture tables: one JSON file per asset digest in a Sylvia-owned directory, written
/// atomically with file protection. The product stores these rows in the database transaction of plan 11.1.
public struct HighlightStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("PDFSpikeHighlights", isDirectory: true)
    }

    func fileURL(forAsset sha256: String) -> URL {
        directory.appendingPathComponent("\(sha256).highlights.json")
    }

    public func load(assetSHA256: String) throws -> [HighlightRecord] {
        let url = fileURL(forAsset: assetSHA256)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try AnchorJSON.decoder().decode([HighlightRecord].self, from: data)
    }

    /// Appends a record and returns only after the file is durably replaced.
    public func append(_ record: HighlightRecord) throws {
        var all = try load(assetSHA256: record.anchor.assetSHA256)
        all.append(record)
        try save(all, assetSHA256: record.anchor.assetSHA256)
    }

    public func save(_ records: [HighlightRecord], assetSHA256: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try AnchorJSON.encoder().encode(records)
        #if os(iOS)
        try data.write(to: fileURL(forAsset: assetSHA256), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL(forAsset: assetSHA256), options: [.atomic])
        #endif
    }

    public func removeAll(assetSHA256: String) throws {
        let url = fileURL(forAsset: assetSHA256)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
