import CryptoKit
import Foundation
import PDFKit

/// Why a PDF could not be opened for reading. Each case maps to its own user-facing message (plan 9.2, T12).
public enum PDFOpenError: Error, Equatable, Sendable {
    /// The file could not be read from disk.
    case fileUnreadable
    /// The bytes do not start with a PDF header.
    case notAPDF
    /// The file ends before the PDF's end-of-file marker: it was cut short.
    case truncated
    /// PDFKit could not parse the file.
    case unparseable
    /// The PDF needs a password to open. Password-protected PDFs are a proposed v1 exclusion; Sylvia never
    /// asks for, guesses or tries a password (no `unlock(withPassword:)` call is made).
    case passwordProtected
    /// The PDF parsed but has no pages.
    case noPages
}

/// Document-level permission flags that change what Sylvia offers (an encrypted PDF that opens without a
/// password can still restrict copying).
public struct PDFPermissionSummary: Codable, Hashable, Sendable {
    public var isEncrypted: Bool
    public var allowsCopying: Bool
    public var allowsContentAccessibility: Bool
}

/// An opened, validated PDF plus the facts an anchor needs about it.
public final class PDFSourceDocument {
    public let url: URL
    public let sha256: String
    public let byteCount: Int64
    public let document: PDFDocument
    /// True when the catalog has a /PageLabels number tree. Without one PDFKit still returns "1", "2", ... from
    /// `PDFPage.label`, so labels are only stored when the file actually supplies them (plan 7.5, 9.2).
    public let pageLabelsSupplied: Bool
    public let permissions: PDFPermissionSummary

    /// Bytes inspected at each end of the file for the header and end-of-file marker.
    static let structureWindow = 1024

    init(url: URL, sha256: String, byteCount: Int64, document: PDFDocument) {
        self.url = url
        self.sha256 = sha256
        self.byteCount = byteCount
        self.document = document
        self.pageLabelsSupplied = PDFSourceDocument.catalogHasPageLabels(document)
        self.permissions = PDFPermissionSummary(
            isEncrypted: document.isEncrypted,
            allowsCopying: document.allowsCopying,
            allowsContentAccessibility: document.allowsContentAccessibility
        )
    }

    /// Opens `url` read-only. Nothing is ever written back to the file.
    ///
    /// Order of checks: readable → PDF header → end-of-file marker (truncation) → PDFKit parse → password
    /// required → has pages. `makeDocument` exists so tests can observe what is called on the document. The default
    /// creates an `OverlayPDFDocument`, whose pages can draw Sylvia's highlight overlays.
    public static func open(
        url: URL,
        makeDocument: (URL) -> PDFDocument? = { OverlayPDFDocument(url: $0) }
    ) throws(PDFOpenError) -> PDFSourceDocument {
        let digest: (String, Int64)
        do {
            digest = try sha256OfFile(at: url)
        } catch {
            throw .fileUnreadable
        }
        let structure: StructureCheck
        do {
            structure = try checkStructure(at: url, byteCount: digest.1)
        } catch {
            throw .fileUnreadable
        }
        switch structure {
        case .notAPDF: throw .notAPDF
        case .missingEndOfFile: throw .truncated
        case .ok: break
        }
        guard let document = makeDocument(url) else { throw .unparseable }
        if document.isLocked { throw .passwordProtected }
        guard document.pageCount > 0 else { throw .noPages }
        return PDFSourceDocument(url: url, sha256: digest.0, byteCount: digest.1, document: document)
    }

    enum StructureCheck: Equatable {
        case ok, notAPDF, missingEndOfFile
    }

    /// A PDF must have "%PDF-" in its first 1024 bytes and "%%EOF" in its last 1024 bytes (ISO 32000-1 7.5.2,
    /// 7.5.5; readers conventionally tolerate up to 1 KB of leading or trailing junk). In the truncation sweep
    /// (`t12-truncation-sweep.txt`) `PDFDocument(url:)` returned nil at every cut point, which alone could not tell a
    /// cut-off file from any other unreadable one; this check is what makes truncation a specific, reportable error.
    static func checkStructure(at url: URL, byteCount: Int64) throws -> StructureCheck {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: structureWindow) ?? Data()
        guard head.range(of: Data("%PDF-".utf8)) != nil else { return .notAPDF }
        let tailStart = max(0, byteCount - Int64(structureWindow))
        try handle.seek(toOffset: UInt64(tailStart))
        let tail = try handle.readToEnd() ?? Data()
        guard tail.range(of: Data("%%EOF".utf8)) != nil else { return .missingEndOfFile }
        return .ok
    }

    /// Streams the file through SHA-256 in 1 MiB chunks so memory does not grow with file size.
    public static func sha256OfFile(at url: URL) throws -> (String, Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 1 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }

    static func catalogHasPageLabels(_ document: PDFDocument) -> Bool {
        guard let catalog = document.documentRef?.catalog else { return false }
        var labels: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(catalog, "PageLabels", &labels) && labels != nil
    }

    /// The printed label for a page, or nil when the PDF supplies no /PageLabels.
    public func printedLabel(forPageAt index: Int) -> String? {
        guard pageLabelsSupplied, let page = document.page(at: index) else { return nil }
        return page.label
    }

    public func page(at index: Int) -> PDFPage? {
        document.page(at: index)
    }

    public func index(of page: PDFPage) -> Int {
        document.index(for: page)
    }

    /// The box anchors are normalized to: the CropBox (PDFKit returns the MediaBox when no CropBox is set). It is the
    /// region PDFKit displays and the only region whose text `PDFPage.string` returns.
    public static let anchorBox: PDFDisplayBox = .cropBox
    public static let anchorBoxName = "crop"

    public func anchorBoxRect(forPageAt index: Int) -> CGRect? {
        document.page(at: index)?.bounds(for: Self.anchorBox)
    }
}
