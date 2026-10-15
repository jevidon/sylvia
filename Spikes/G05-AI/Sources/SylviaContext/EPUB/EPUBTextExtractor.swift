import Foundation

/// A paragraph of extracted text with its position. `ordinal` is the global reading-order position used for
/// spoiler boundaries; it increases strictly through the spine.
public struct ExtractedParagraph: Codable, Sendable, Equatable {
    public let ordinal: Int
    public let spineIndex: Int
    public let resourceHref: String
    public let indexInResource: Int
    public let locationLabel: String
    public let text: String

    public var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

public struct ExtractedWork: Sendable {
    public let title: String
    public let author: String
    /// Body-matter resources in spine order (front and back matter such as the colophon are excluded).
    public let resourceHrefs: [String]
    public let paragraphs: [ExtractedParagraph]
}

public enum EPUBExtractionError: Error, Equatable {
    case missingContainer
    case missingPackage(String)
    case malformedXML(String)
}

/// Plain-text extraction from EPUB XHTML for the G0.5 spike (no Readium). It reads the package document's
/// spine, keeps linear body-matter documents, and splits text at block elements. `<br/>` becomes a newline.
/// Text inside head, script, style and nav is ignored.
public enum EPUBTextExtractor {
    public static func extract(epubAt url: URL) throws -> ExtractedWork {
        let zip = try ZipReader(url: url)
        guard let container = try? zip.read("META-INF/container.xml") else { throw EPUBExtractionError.missingContainer }
        let rootfile = try XMLScan.firstAttribute(in: container, element: "rootfile", attribute: "full-path")
        guard let opfPath = rootfile else { throw EPUBExtractionError.missingContainer }
        let opfData = try zip.read(opfPath)
        let package = try PackageDocument.parse(opfData)
        let base = (opfPath as NSString).deletingLastPathComponent

        var documents: [(href: String, title: String, isBody: Bool, blocks: [String])] = []
        for itemref in package.spine {
            guard itemref.linear, let item = package.manifest[itemref.idref],
                  item.mediaType == "application/xhtml+xml" else { continue }
            let path = Self.resolve(item.href, base: base)
            let xhtml = try zip.read(path)
            let parsed = try XHTMLBlocks.parse(xhtml)
            documents.append((item.href, parsed.title, parsed.bodyTypes.contains("bodymatter"), parsed.blocks))
        }
        let anyBody = documents.contains { $0.isBody }
        var paragraphs: [ExtractedParagraph] = []
        var hrefs: [String] = []
        for (spineIndex, document) in documents.enumerated() where !anyBody || document.isBody {
            hrefs.append(document.href)
            for (index, text) in document.blocks.enumerated() {
                paragraphs.append(ExtractedParagraph(ordinal: paragraphs.count, spineIndex: spineIndex, resourceHref: document.href,
                                                     indexInResource: index, locationLabel: document.title, text: text))
            }
        }
        return ExtractedWork(title: package.title, author: package.creator, resourceHrefs: hrefs, paragraphs: paragraphs)
    }

    static func resolve(_ href: String, base: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var parts = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for component in decoded.split(separator: "/") {
            if component == ".." { if !parts.isEmpty { parts.removeLast() } } else if component != "." { parts.append(String(component)) }
        }
        return parts.joined(separator: "/")
    }
}

// MARK: - Package document

struct PackageDocument {
    struct Item { let href: String; let mediaType: String }
    struct ItemRef { let idref: String; let linear: Bool }
    var manifest: [String: Item] = [:]
    var spine: [ItemRef] = []
    var title = ""
    var creator = ""

    static func parse(_ data: Data) throws -> PackageDocument {
        let delegate = PackageDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw EPUBExtractionError.malformedXML("package document") }
        return delegate.document
    }

    final class PackageDelegate: NSObject, XMLParserDelegate {
        var document = PackageDocument()
        var capture: String?
        var buffer = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            switch local {
            case "item":
                if let id = attributes["id"], let href = attributes["href"] {
                    document.manifest[id] = Item(href: href, mediaType: attributes["media-type"] ?? "")
                }
            case "itemref":
                if let idref = attributes["idref"] { document.spine.append(ItemRef(idref: idref, linear: attributes["linear"] != "no")) }
            case "title" where document.title.isEmpty, "creator" where document.creator.isEmpty:
                capture = local
                buffer = ""
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capture != nil { buffer += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            guard local == capture else { return }
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if local == "title" { document.title = text } else { document.creator = text }
            capture = nil
        }
    }
}

// MARK: - XHTML blocks

struct XHTMLBlocks {
    var title = ""
    var bodyTypes: Set<String> = []
    var blocks: [String] = []

    static let blockElements: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "dt", "dd", "td", "th", "figcaption", "pre", "blockquote",
        "div", "section", "header", "hgroup", "article", "aside", "footer", "tr", "body", "table", "ol", "ul", "dl",
        "figure", "cite",
    ]
    static let headingElements: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "hgroup"]
    static let ignoredElements: Set<String> = ["head", "script", "style", "nav"]

    static func parse(_ data: Data) throws -> XHTMLBlocks {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw EPUBExtractionError.malformedXML("xhtml") }
        delegate.flush()
        return delegate.result
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var result = XHTMLBlocks()
        var buffer = ""
        var ignoreDepth = 0
        var headingDepth = 0
        var inTitle = false
        var titleBuffer = ""
        static let lineBreak: Character = "\u{2028}"

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            if local == "title" && ignoreDepth > 0 { inTitle = true }
            if Self.isIgnored(local) { ignoreDepth += 1; return }
            guard ignoreDepth == 0 else { return }
            if local == "body", let types = attributes["epub:type"] {
                result.bodyTypes = Set(types.split(separator: " ").map(String.init))
            }
            if local == "br" { buffer.append(Self.lineBreak); return }
            if XHTMLBlocks.blockElements.contains(local) { flush() }
            if XHTMLBlocks.headingElements.contains(local) { headingDepth += 1 }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inTitle { titleBuffer += string }
            guard ignoreDepth == 0 else { return }
            buffer += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            if local == "title" && inTitle {
                inTitle = false
                result.title = Self.normalize(titleBuffer)
            }
            if Self.isIgnored(local) { ignoreDepth = max(0, ignoreDepth - 1); return }
            guard ignoreDepth == 0 else { return }
            if XHTMLBlocks.blockElements.contains(local) { flush() }
            if XHTMLBlocks.headingElements.contains(local) { headingDepth = max(0, headingDepth - 1); buffer = "" }
        }

        static func isIgnored(_ local: String) -> Bool { XHTMLBlocks.ignoredElements.contains(local) }

        func flush() {
            defer { buffer = "" }
            // Headings label a resource; they are not passage text.
            guard headingDepth == 0 else { return }
            let text = Self.normalize(buffer)
            if !text.isEmpty { result.blocks.append(text) }
        }

        /// Collapses source-formatting whitespace to single spaces and turns `<br/>` into newlines.
        static func normalize(_ raw: String) -> String {
            let lines = raw.split(separator: lineBreak, omittingEmptySubsequences: false).map { line in
                line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
            }
            return lines.filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }
}

enum XMLScan {
    static func firstAttribute(in data: Data, element: String, attribute: String) throws -> String? {
        final class Finder: NSObject, XMLParserDelegate {
            let element: String
            let attribute: String
            var value: String?
            init(element: String, attribute: String) {
                self.element = element
                self.attribute = attribute
            }
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                        attributes: [String: String] = [:]) {
                if value == nil, name == element || name.hasSuffix(":" + element) { value = attributes[attribute] }
            }
        }
        let finder = Finder(element: element, attribute: attribute)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = finder
        guard parser.parse() else { throw EPUBExtractionError.malformedXML(element) }
        return finder.value
    }
}
