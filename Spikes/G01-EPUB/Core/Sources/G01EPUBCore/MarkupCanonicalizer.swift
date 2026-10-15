import Foundation

/// Parses a publication document as XML (libxml2, through Foundation's `XMLParser`) and writes it out again in a
/// canonical form that every parser reading it afterwards (WebKit's XML parser, WebKit's HTML parser, SwiftSoup's
/// HTML5 parser inside Readium) reads the same way:
///
/// - no comments, CDATA sections, processing instructions or DTD: only elements, attributes and text;
/// - every `<`, `&` and `>` in text, and every `<`, `&`, `"` and whitespace control in attribute values, escaped;
/// - every element unprefixed, with its namespace given by an explicit default `xmlns` wherever it changes;
/// - every non-void element closed explicitly (`<span></span>`, never `<span/>`, which HTML parsers ignore);
/// - script elements, embedding elements, SVG animation elements, `<base>`, meta refresh, resource-hint links,
///   event-handler attributes and `javascript:` URLs removed, under any namespace prefix and in any letter case;
/// - for an XHTML document, a Content Security Policy `<meta>` as the first child of a `<head>` that is the first
///   child of the root.
///
/// Because the output is produced from the parse rather than edited in place, the tricks that make a text-level
/// sanitizer and a browser disagree (a `<head>` inside a comment, `<!-->`, a prefixed root such as `<h:html>`,
/// unmatched end tags) cannot carry markup past it: whatever the parser understood as a comment is gone, and whatever
/// it understood as an element is written out explicitly. Input that is not well-formed XML is refused.
///
/// Work is linear in the input: one pass to rewrite entity references, one `XMLParser` pass, and output appends.
/// Nothing here recurses.
struct MarkupCanonicalizer {
    enum Mode { case xhtml, nonHTML }

    enum Failure: Error, Equatable, Sendable {
        case notWellFormed(String)
        case excessiveNesting(atLeast: Int)
        case tooManyElements(atLeast: Int)
        case tooManyAttributes(element: String, count: Int)
        case tooManyAttributesInDocument(atLeast: Int)
        case internalDTDSubset
        case entityDeclaration
        case unknownEntity(String)
        case notXHTMLRoot(String)
    }

    struct Output: Sendable {
        var markup: String
        var elementDepth: Int
        var elementCount: Int
        /// Attributes and namespace declarations read so far (all elements).
        var attributeCount = 0
        var removedScripts = 0
        var removedRefreshes = 0
        var removedEventHandlers = 0
        var removedScriptURLs = 0
        /// Embedding, animation and `<base>` elements, resource-hint links, `ping`, `srcdoc` and `xml:base`.
        var removedOther = 0
        var droppedComments = 0
        var droppedProcessingInstructions = 0
        var cspInserted = false
    }

    static let xhtmlNamespace = "http://www.w3.org/1999/xhtml"

    struct Limits: Sendable {
        var maxDepth: Int
        var maxElements: Int
        var maxAttributesPerElement: Int
        var maxAttributesPerDocument: Int
    }

    let mode: Mode
    let limits: Limits
    let cspMetaElement: String

    func canonicalize(_ input: String) -> Result<Output, Failure> {
        let prepared: [UInt8]
        switch Self.prepare(input) {
        case let .success(bytes): prepared = bytes
        case let .failure(f): return .failure(f)
        }
        let writer = Writer(mode: mode, limits: limits, cspMetaElement: cspMetaElement, inputSize: prepared.count)
        let parser = XMLParser(data: Data(prepared))
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = writer
        let ok = parser.parse()
        if let failure = writer.failure { return .failure(failure) }
        guard ok else {
            let error = parser.parserError.map { "XMLParser error \(($0 as NSError).code) at line \(parser.lineNumber)" } ?? "XMLParser failed"
            return .failure(.notWellFormed(error))
        }
        return writer.finish()
    }

    // MARK: Entity references and the XML declaration

    /// Returns the UTF-8 bytes of `input` with its XML declaration (if any) replaced by a UTF-8 one (the text has
    /// already been decoded as UTF-8) and every named character reference other than XML's five predefined ones
    /// replaced by the numeric reference for the XHTML 1.x entity of that name (not inside comments, CDATA sections
    /// or processing instructions). A DOCTYPE with an internal subset (which can declare entities) and an unknown
    /// entity name are refused. One forward pass.
    ///
    /// U+FEFF is also escaped, everywhere, as U+E000 followed by "F" (and U+E000 itself as U+E000 U+E000), whether
    /// written as a character or as a numeric reference; `restoreEscapes` undoes it on the output. Foundation's
    /// `XMLParser` builds each string it reports with `NSString`'s UTF-8 decoding, which drops a U+FEFF at the start of
    /// a string as if it were a byte-order mark; Standard Ebooks put U+FEFF (as a word joiner) right after inline
    /// elements, so a text node can start with one. Found by comparing WebKit's `textContent` with and without the
    /// sanitizer (9 characters lost in one Middlemarch chapter before this escape).
    static func prepare(_ input: String) -> Result<[UInt8], Failure> {
        let b = Array(input.utf8)
        let n = b.count
        var out: [UInt8] = []
        out.reserveCapacity(n + 64)
        var i = 0
        if n >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF { i = 3 }
        func starts(_ s: StaticString, at k: Int) -> Bool {
            let len = s.utf8CodeUnitCount
            guard k + len <= n else { return false }
            return s.withUTF8Buffer { p in
                for j in 0 ..< len where b[k + j] != p[j] { return false }
                return true
            }
        }
        /// Index just past the first occurrence of `s` at or after `k`, or `n`.
        func past(_ s: StaticString, from k: Int) -> Int {
            let len = s.utf8CodeUnitCount
            let first = s.withUTF8Buffer { $0[0] }
            var x = k
            while x + len <= n {
                if b[x] == first, starts(s, at: x) { return x + len }
                x += 1
            }
            return n
        }
        if starts("<?xml", at: i), i + 5 < n, b[i + 5] == 0x20 || b[i + 5] == 0x09 || b[i + 5] == 0x0A || b[i + 5] == 0x0D {
            i = past("?>", from: i + 5)
            out.append(contentsOf: Array(#"<?xml version="1.0" encoding="UTF-8"?>"#.utf8))
        }
        let predefined: Set<String> = ["lt", "gt", "amp", "quot", "apos"]
        /// Appends `b[range]` with U+FEFF and U+E000 escaped.
        func appendEscaping(_ range: Range<Int>) {
            var k = range.lowerBound
            while k < range.upperBound {
                if k + 2 < range.upperBound, b[k] == 0xEF, b[k + 1] == 0xBB, b[k + 2] == 0xBF {
                    out.append(contentsOf: Self.escapeIntroducer); out.append(UInt8(ascii: "F")); k += 3
                } else if k + 2 < range.upperBound, b[k] == 0xEE, b[k + 1] == 0x80, b[k + 2] == 0x80 {
                    out.append(contentsOf: Self.escapeIntroducer); out.append(contentsOf: Self.escapeIntroducer); k += 3
                } else {
                    out.append(b[k]); k += 1
                }
            }
        }
        while i < n {
            let c = b[i]
            if c == 0xEF || c == 0xEE {
                appendEscaping(i ..< min(n, i + 3))
                i = min(n, i + 3)
                continue
            }
            if c == UInt8(ascii: "<") {
                let end: Int
                if starts("<!--", at: i) { end = past("-->", from: i + 4) }
                else if starts("<![CDATA[", at: i) { end = past("]]>", from: i + 9) }
                else if starts("<?", at: i) { end = past("?>", from: i + 2) }
                else if starts("<!DOCTYPE", at: i) {
                    // Up to the first ">" outside a quoted public or system identifier; a "[" outside quotes opens an
                    // internal subset.
                    var x = i + 9
                    var quote: UInt8?
                    while x < n {
                        let ch = b[x]
                        if let q = quote {
                            if ch == q { quote = nil }
                        } else if ch == UInt8(ascii: "\"") || ch == UInt8(ascii: "'") {
                            quote = ch
                        } else if ch == UInt8(ascii: "[") {
                            return .failure(.internalDTDSubset)
                        } else if ch == UInt8(ascii: ">") {
                            break
                        }
                        x += 1
                    }
                    end = min(n, x + 1)
                } else {
                    out.append(c); i += 1; continue
                }
                appendEscaping(i ..< end)
                i = end
                continue
            }
            if c == UInt8(ascii: "&"), i + 2 < n, b[i + 1] == UInt8(ascii: "#") {
                // A numeric reference to U+FEFF or U+E000 is escaped like the character; any other is copied.
                let hex = b[i + 2] == UInt8(ascii: "x")
                var x = i + (hex ? 3 : 2)
                var value: UInt32 = 0
                while x < n, x - i <= 12, let d = Self.digit(b[x], hex: hex) { value = value &* (hex ? 16 : 10) &+ d; x += 1 }
                if x < n, b[x] == UInt8(ascii: ";"), x > i + (hex ? 3 : 2), value == 0xFEFF || value == 0xE000 {
                    out.append(contentsOf: Self.escapeIntroducer)
                    if value == 0xFEFF { out.append(UInt8(ascii: "F")) } else { out.append(contentsOf: Self.escapeIntroducer) }
                    i = x + 1
                    continue
                }
            }
            if c == UInt8(ascii: "&"), i + 1 < n, b[i + 1] != UInt8(ascii: "#") {
                var x = i + 1
                while x < n, x - i <= 32, Self.isNameByte(b[x]) { x += 1 }
                if x < n, b[x] == UInt8(ascii: ";"), x > i + 1 {
                    let name = String(decoding: b[(i + 1) ..< x], as: UTF8.self)
                    if predefined.contains(name) {
                        out.append(contentsOf: b[i ... x])
                    } else if let cp = XHTMLEntities.codePoints[name] {
                        out.append(contentsOf: Array("&#x\(String(cp, radix: 16));".utf8))
                    } else {
                        return .failure(.unknownEntity(name))
                    }
                    i = x + 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return .success(out)
    }

    /// U+E000 in UTF-8: introduces the escapes `prepare` writes for U+FEFF ("F") and for U+E000 itself.
    static let escapeIntroducer: [UInt8] = [0xEE, 0x80, 0x80]

    /// Undoes `prepare`'s escapes in the written output: U+E000 "F" becomes U+FEFF, U+E000 U+E000 becomes U+E000.
    static func restoreEscapes(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var k = 0
        let n = bytes.count
        func introducer(at x: Int) -> Bool { x + 2 < n && bytes[x] == 0xEE && bytes[x + 1] == 0x80 && bytes[x + 2] == 0x80 }
        while k < n {
            if introducer(at: k) {
                if k + 3 < n, bytes[k + 3] == UInt8(ascii: "F") { out.append(contentsOf: [0xEF, 0xBB, 0xBF]); k += 4; continue }
                if introducer(at: k + 3) { out.append(contentsOf: escapeIntroducer); k += 6; continue }
            }
            out.append(bytes[k])
            k += 1
        }
        return out
    }

    private static func digit(_ c: UInt8, hex: Bool) -> UInt32? {
        if c >= 0x30 && c <= 0x39 { return UInt32(c - 0x30) }
        guard hex else { return nil }
        if c >= 0x61 && c <= 0x66 { return UInt32(c - 0x61 + 10) }
        if c >= 0x41 && c <= 0x46 { return UInt32(c - 0x41 + 10) }
        return nil
    }

    private static func isNameByte(_ c: UInt8) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x2D || c == 0x5F
    }

    // MARK: What is removed

    /// Removed with everything inside them (compared by local name, case-insensitively, in every namespace).
    static let removedElements: Set<String> = [
        "script", "iframe", "frame", "frameset", "object", "embed", "applet", "portal", "base",
        "handler", "listener", "set", "animate", "animatemotion", "animatetransform", "animatecolor",
    ]
    /// Also removed from documents that cannot carry a CSP (SVG pages, XML items): `foreignObject` (it can carry XHTML),
    /// and the form controls that navigate without a link activation (`form`, `button`, `input` and the rest), by
    /// local name in every namespace. Any element in the XHTML namespace is removed from such documents as well
    /// (`Writer`): WebKit makes it a live HTML element, and without a page CSP nothing stops a form submission or a
    /// meta refresh (review R2-01). A removal makes the whole document withheld (`sanitize(nonHTMLDocument:)`).
    static let removedElementsNonHTML: Set<String> = [
        "foreignobject", "form", "button", "input", "select", "textarea", "isindex", "keygen",
    ]
    /// Attributes removed from documents that cannot carry a CSP (navigation targets of form controls).
    static let removedAttributesNonHTML: Set<String> = ["formaction", "action"]
    static let removedLinkRelations: Set<String> = ["prefetch", "dns-prefetch", "preconnect", "prerender", "preload", "modulepreload", "import"]
    static let removedHTTPEquiv: Set<String> = ["refresh", "set-cookie"]
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr",
    ]

    /// True for a URL with a script scheme, after removing what URL parsers ignore (ASCII whitespace and controls).
    static func isScriptURL(_ value: String) -> Bool {
        guard value.utf8.contains(UInt8(ascii: ":")) else { return false }
        var folded: [UInt8] = []
        folded.reserveCapacity(value.utf8.count)
        for c in value.utf8 where c > 0x20 && c != 0x7F {
            folded.append(c >= 0x41 && c <= 0x5A ? c + 0x20 : c)
        }
        let s = String(decoding: folded, as: UTF8.self)
        return s.contains("javascript:") || s.contains("vbscript:") || s.contains("livescript:")
    }

    // MARK: The writer

    private final class Writer: NSObject, XMLParserDelegate {
        let mode: Mode
        let limits: Limits
        let cspMetaElement: String
        var failure: Failure?
        var out: [UInt8] = []
        var output: Output

        private var depth = 0
        /// > 0 while inside a removed element; counts its nesting.
        private var skipDepth = 0
        /// Start tag written without its closing `>` until we know whether the element has content.
        private var pendingStart = false
        private var pendingVoid = false
        private var openNames: [String] = []
        private var defaultNamespaces: [String] = []
        private var pendingMappings: [(String, String)] = []
        private var headHandled = false

        init(mode: Mode, limits: Limits, cspMetaElement: String, inputSize: Int) {
            self.mode = mode
            self.limits = limits
            self.cspMetaElement = cspMetaElement
            output = Output(markup: "", elementDepth: 0, elementCount: 0)
            out.reserveCapacity(inputSize + inputSize / 8 + 512)
            switch mode {
            case .xhtml: out.append(contentsOf: Array("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n".utf8))
            case .nonHTML: out.append(contentsOf: Array("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n".utf8))
            }
        }

        func finish() -> Result<Output, Failure> {
            if mode == .xhtml, !headHandled { return .failure(.notWellFormed("no root element")) }
            output.markup = String(decoding: MarkupCanonicalizer.restoreEscapes(out), as: UTF8.self)
            output.cspInserted = mode == .xhtml && headHandled
            return .success(output)
        }

        private func fail(_ f: Failure, _ parser: XMLParser) {
            if failure == nil { failure = f }
            parser.abortParsing()
        }

        private func write(_ s: String) { out.append(contentsOf: s.utf8) }

        private func closePendingStart() {
            if pendingStart { out.append(UInt8(ascii: ">")); pendingStart = false }
        }

        private func writeHead(withAttributes attributes: String?) {
            write("<head")
            if let attributes { write(attributes) }
            out.append(UInt8(ascii: ">"))
            write(cspMetaElement)
            headHandled = true
        }

        func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
            pendingMappings.append((prefix, namespaceURI))
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            guard failure == nil else { return }
            depth += 1
            output.elementCount += 1
            output.elementDepth = max(output.elementDepth, depth)
            let mappings = pendingMappings
            pendingMappings = []
            if depth > limits.maxDepth { return fail(.excessiveNesting(atLeast: depth), parser) }
            if output.elementCount > limits.maxElements { return fail(.tooManyElements(atLeast: output.elementCount), parser) }
            // Namespace declarations count as attributes: they are written out again, and every HTML parser reads them
            // as attributes (review R2-02: attribute-dense markup is the slowest per byte for SwiftSoup).
            let attributesHere = attributeDict.count + mappings.count
            if attributesHere > limits.maxAttributesPerElement {
                return fail(.tooManyAttributes(element: qName ?? elementName, count: attributesHere), parser)
            }
            output.attributeCount += attributesHere
            if output.attributeCount > limits.maxAttributesPerDocument {
                return fail(.tooManyAttributesInDocument(atLeast: output.attributeCount), parser)
            }
            if skipDepth > 0 { skipDepth += 1; return }

            let local = elementName
            let lower = local.lowercased()
            let namespace = namespaceURI ?? ""

            if depth == 1, mode == .xhtml, !(local == "html" && namespace == MarkupCanonicalizer.xhtmlNamespace) {
                return fail(.notXHTMLRoot("{\(namespace)}\(qName ?? local)"), parser)
            }

            // Elements removed with their content.
            var remove = MarkupCanonicalizer.removedElements.contains(lower)
                || (mode == .nonHTML && (MarkupCanonicalizer.removedElementsNonHTML.contains(lower)
                    || namespace == MarkupCanonicalizer.xhtmlNamespace))
            if !remove, lower == "meta",
               let equiv = Self.value(of: "http-equiv", in: attributeDict)?.trimmingCharacters(in: .whitespaces).lowercased(),
               MarkupCanonicalizer.removedHTTPEquiv.contains(equiv) {
                remove = true
                if equiv == "refresh" { output.removedRefreshes += 1 } else { output.removedOther += 1 }
            } else if !remove, lower == "link", let rel = Self.value(of: "rel", in: attributeDict)?.lowercased(),
                      rel.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\u{0C}" })
                      .contains(where: { MarkupCanonicalizer.removedLinkRelations.contains(String($0)) }) {
                remove = true
                output.removedOther += 1
            } else if remove {
                if lower == "script" { output.removedScripts += 1 } else { output.removedOther += 1 }
            }

            // The CSP goes first in a head that is the root's first child; a missing head is created.
            if depth == 2, mode == .xhtml, !headHandled {
                closePendingStart()
                if !remove, local == "head", namespace == MarkupCanonicalizer.xhtmlNamespace {
                    writeHead(withAttributes: namespaceDeclarations(mappings) + attributes(attributeDict))
                    openNames.append(local)
                    defaultNamespaces.append(namespace)
                    return
                }
                writeHead(withAttributes: nil)
                write("</head>")
            }
            if remove { skipDepth = 1; return }

            closePendingStart()
            out.append(UInt8(ascii: "<"))
            write(local)
            let parentDefault = defaultNamespaces.last ?? ""
            if namespace != parentDefault || (depth == 1 && !namespace.isEmpty) {
                write(" xmlns=\"")
                appendEscapedAttribute(namespace)
                write("\"")
            }
            write(namespaceDeclarations(mappings))
            write(attributes(attributeDict))
            pendingStart = true
            pendingVoid = namespace == MarkupCanonicalizer.xhtmlNamespace && MarkupCanonicalizer.voidElements.contains(local)
            openNames.append(local)
            defaultNamespaces.append(namespace)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard failure == nil else { return }
            defer { depth -= 1 }
            if skipDepth > 0 { skipDepth -= 1; return }
            if depth == 1, mode == .xhtml, !headHandled {
                closePendingStart()
                writeHead(withAttributes: nil)
                write("</head>")
            }
            guard let local = openNames.popLast() else { return }
            defaultNamespaces.removeLast()
            if pendingStart {
                pendingStart = false
                if pendingVoid { write("/>") } else { write("></\(local)>") }
            } else {
                write("</\(local)>")
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard failure == nil, skipDepth == 0, depth > 0 else { return }
            closePendingStart()
            headBeforeRootText(string)
            appendEscapedText(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard failure == nil, skipDepth == 0, depth > 0 else { return }
            closePendingStart()
            let text = String(decoding: CDATABlock, as: UTF8.self)
            headBeforeRootText(text)
            appendEscapedText(text)
        }

        /// Text other than XML whitespace directly in the root, before the head: an HTML parser starts the body there
        /// and would put a later head's `<meta>` in the body, where WebKit ignores a CSP. The head with the CSP is
        /// written first.
        private func headBeforeRootText(_ text: String) {
            guard depth == 1, mode == .xhtml, !headHandled,
                  text.utf8.contains(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }) else { return }
            writeHead(withAttributes: nil)
            write("</head>")
        }

        func parser(_ parser: XMLParser, foundComment comment: String) { output.droppedComments += 1 }
        func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
            output.droppedProcessingInstructions += 1
        }

        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { fail(.entityDeclaration, parser) }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
            fail(.entityDeclaration, parser)
        }
        func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?, systemID: String?, notationName: String?) {
            fail(.entityDeclaration, parser)
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            fail(.unknownEntity(name), parser)
            return nil
        }
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
            if failure == nil { failure = .notWellFormed("XMLParser error \((parseError as NSError).code) at line \(parser.lineNumber)") }
        }

        // MARK: Attributes and escaping

        static func value(of localName: String, in attributes: [String: String]) -> String? {
            for (name, value) in attributes where Self.localName(name).lowercased() == localName { return value }
            return nil
        }

        static func localName(_ qualified: String) -> Substring {
            if let colon = qualified.lastIndex(of: ":") { return qualified[qualified.index(after: colon)...] }
            return qualified[...]
        }

        /// ` xmlns:prefix="uri"` for the prefixes declared on this element (the default namespace is written separately).
        private func namespaceDeclarations(_ mappings: [(String, String)]) -> String {
            var s = ""
            for (prefix, uri) in mappings where !prefix.isEmpty && prefix != "xml" && prefix != "xmlns" {
                s += " xmlns:\(prefix)=\"" + Self.escapedAttribute(uri) + "\""
            }
            return s
        }

        /// Kept attributes, sorted by name (the parser reports them unordered), as ` name="value"` pairs.
        private func attributes(_ dict: [String: String]) -> String {
            var s = ""
            for name in dict.keys.sorted() {
                let value = dict[name]!
                let lower = Self.localName(name).lowercased()
                if lower.hasPrefix("on") { output.removedEventHandlers += 1; continue }
                if lower == "srcdoc" || lower == "ping" || name == "xml:base" { output.removedOther += 1; continue }
                if mode == .nonHTML, MarkupCanonicalizer.removedAttributesNonHTML.contains(lower) { output.removedOther += 1; continue }
                if MarkupCanonicalizer.isScriptURL(value) { output.removedScriptURLs += 1; continue }
                s += " \(name)=\""
                s += Self.escapedAttribute(value)
                s += "\""
            }
            return s
        }

        private func appendEscapedAttribute(_ value: String) { write(Self.escapedAttribute(value)) }

        static func escapedAttribute(_ value: String) -> String {
            var needs = false
            for c in value.utf8 where c == 0x26 || c == 0x3C || c == 0x3E || c == 0x22 || c == 0x09 || c == 0x0A || c == 0x0D { needs = true; break }
            guard needs else { return value }
            var r = [UInt8]()
            r.reserveCapacity(value.utf8.count + 16)
            for c in value.utf8 {
                switch c {
                case 0x26: r.append(contentsOf: Array("&amp;".utf8))
                case 0x3C: r.append(contentsOf: Array("&lt;".utf8))
                case 0x3E: r.append(contentsOf: Array("&gt;".utf8))
                case 0x22: r.append(contentsOf: Array("&quot;".utf8))
                case 0x09: r.append(contentsOf: Array("&#9;".utf8))
                case 0x0A: r.append(contentsOf: Array("&#10;".utf8))
                case 0x0D: r.append(contentsOf: Array("&#13;".utf8))
                default: r.append(c)
                }
            }
            return String(decoding: r, as: UTF8.self)
        }

        private func appendEscapedText(_ text: String) {
            for c in text.utf8 {
                switch c {
                case 0x26: out.append(contentsOf: [0x26, 0x61, 0x6D, 0x70, 0x3B]) // &amp;
                case 0x3C: out.append(contentsOf: [0x26, 0x6C, 0x74, 0x3B]) // &lt;
                case 0x3E: out.append(contentsOf: [0x26, 0x67, 0x74, 0x3B]) // &gt;
                case 0x0D: out.append(contentsOf: [0x26, 0x23, 0x31, 0x33, 0x3B]) // &#13;
                default: out.append(c)
                }
            }
        }
    }
}
