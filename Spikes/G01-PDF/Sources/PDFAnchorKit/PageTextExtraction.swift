import CryptoKit
import Foundation
import PDFKit

/// Identifies how page text was produced, so a later extractor change can be detected (plan 9.1, 9.2, 11.3).
/// PDFKit's text extraction belongs to the OS, so the OS version is part of the identity.
public struct ExtractionVersion: Codable, Hashable, Sendable {
    public var extractor: String
    public var adapterVersion: Int
    public var platform: String

    public static let currentAdapterVersion = 1

    enum CodingKeys: String, CodingKey {
        case extractor
        case adapterVersion = "adapter_version"
        case platform
    }

    public init(extractor: String, adapterVersion: Int, platform: String) {
        self.extractor = extractor
        self.adapterVersion = adapterVersion
        self.platform = platform
    }

    /// The version this process produces: PDFKit `PDFPage.string`, adapter v1, this OS build.
    public static var current: ExtractionVersion {
        ExtractionVersion(
            extractor: "pdfkit.PDFPage.string",
            adapterVersion: currentAdapterVersion,
            platform: platformDescription()
        )
    }

    public static func platformDescription() -> String {
        // e.g. "iOS 26.5 (23F77)". operatingSystemVersionString is "Version 26.5 (Build 23F77)".
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let raw = ProcessInfo.processInfo.operatingSystemVersionString
        var build = ""
        if let r = raw.range(of: "Build ") {
            build = String(raw[r.upperBound...].prefix { $0 != ")" })
        }
        #if os(iOS)
        let os = "iOS"
        #else
        let os = "macOS"
        #endif
        let patch = v.patchVersion > 0 ? ".\(v.patchVersion)" : ""
        return "\(os) \(v.majorVersion).\(v.minorVersion)\(patch)" + (build.isEmpty ? "" : " (\(build))")
    }
}

/// What text features a page supports. Never guessed: an image-only page has no text, and Sylvia does not OCR
/// it, does not invent text for it and does not tell a model it can see it (plan 9.2, T16).
public enum PageTextStatus: Hashable, Sendable {
    /// The page has selectable text.
    case text(scalarCount: Int)
    /// The page has no selectable text (for example a scanned image). UI: "No selectable text on this page".
    case noSelectableText
    /// The PDF's permissions do not allow copying or extracting text, so text features are off.
    case restrictedByPermissions
}

extension PageTextStatus {
    public var hasText: Bool {
        if case .text = self { return true }
        return false
    }

    /// The explanation shown in place of text features (plan 9.2, 9.4). Product strings come from the design
    /// package's status vocabulary; these are the plan's wording, used by the Stage 0 harness only.
    public var unavailableMessage: String? {
        switch self {
        case .text: return nil
        case .noSelectableText: return PageTextStatus.noSelectableTextMessage
        case .restrictedByPermissions: return PageTextStatus.restrictedMessage
        }
    }

    public static let noSelectableTextMessage = "No selectable text on this page"
    public static let restrictedMessage = "This PDF does not allow copying its text"
}

public struct PageExtraction: Sendable {
    public var pageIndex: Int
    public var pageLabel: String?
    public var status: PageTextStatus
    /// The page text exactly as PDFKit returned it; nil unless `status` is `.text`.
    public var text: String?
    /// Lowercase hex SHA-256 of the page text's UTF-8 bytes; nil unless `status` is `.text`.
    public var textSHA256: String?

    /// Text features (selection capture, search, quoting, sending text as AI context) are offered only when the page
    /// actually has extracted text. For an image-only page there is nothing to offer: no OCR, no guessed text, no
    /// image sent in its place.
    public var supportsTextFeatures: Bool { status.hasText }

    /// The only page content Sylvia may put into an AI context pack: the extracted text, or nothing.
    public var textForAIContext: String? { status.hasText ? text : nil }
}

public struct DocumentExtraction: Sendable {
    public var version: ExtractionVersion
    public var pages: [PageExtraction]

    public var pagesWithText: Int { pages.filter { $0.status.hasText }.count }

    public func page(_ index: Int) -> PageExtraction? {
        pages.indices.contains(index) ? pages[index] : nil
    }
}

public enum PageTextExtractor {
    public static func extract(_ source: PDFSourceDocument) -> DocumentExtraction {
        var pages: [PageExtraction] = []
        pages.reserveCapacity(source.document.pageCount)
        for index in 0..<source.document.pageCount {
            pages.append(extractPage(at: index, of: source))
        }
        return DocumentExtraction(version: .current, pages: pages)
    }

    public static func extractPage(at index: Int, of source: PDFSourceDocument) -> PageExtraction {
        let label = source.printedLabel(forPageAt: index)
        guard source.permissions.allowsCopying else {
            return PageExtraction(pageIndex: index, pageLabel: label, status: .restrictedByPermissions, text: nil, textSHA256: nil)
        }
        let text = source.page(at: index).flatMap { page in autoreleasepool { page.string } }
        guard let text, hasNonWhitespace(text) else {
            return PageExtraction(pageIndex: index, pageLabel: label, status: .noSelectableText, text: nil, textSHA256: nil)
        }
        return PageExtraction(
            pageIndex: index,
            pageLabel: label,
            status: .text(scalarCount: text.unicodeScalars.count),
            text: text,
            textSHA256: sha256Hex(text)
        )
    }

    static func hasNonWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
