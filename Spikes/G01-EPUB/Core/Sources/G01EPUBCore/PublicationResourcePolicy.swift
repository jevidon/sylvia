import Foundation

/// Which publication resources the reader may serve, and how (plan 8.3, 18.1; ADR-0004 section 4; review R2-01).
///
/// Readium 3.11.0 serves any archive entry a web view asks for (`EPUBNavigatorViewModel.serve(href:)`), with the media
/// type the manifest declares or, for an entry the manifest does not declare, one guessed from its file extension, and
/// it lets every navigation that is not a link activation (a form submission, a script or a dropped link) through. So
/// the adapter decides, for each request, before Readium does anything with it:
///
/// - an entry the manifest does not declare is not served at all (the adapter's container answers "no such entry");
/// - a declared entry is treated by the media type Readium will serve it with (`treatment(forMediaType:)`): HTML goes
///   through the HTML sanitizer (CSP), any other document type a web view can render (SVG, XML, `+xml`) through the
///   non-HTML sanitizer (withheld if it holds anything active), known passive types are served as they are, and
///   everything else is served empty.
///
/// As a second, engine-level layer, `contentRuleListJSON(readingOrderHrefs:)` builds a WebKit content rule list that
/// blocks every document load except the publication's reading-order documents, so a navigation that is not a link
/// activation cannot leave the reading order even if a document reached the web view unsanitized.
public enum PublicationResourcePolicy {
    public enum Treatment: String, Sendable, Equatable {
        /// `text/html`, `application/xhtml+xml`: the HTML sanitizer, with the page CSP.
        case htmlDocument = "html-document"
        /// SVG, XML and any `+xml` type: documents a web view renders that cannot carry a page CSP; the non-HTML
        /// sanitizer serves them only when nothing active is in them.
        case otherDocument = "other-document"
        /// Images other than SVG, style sheets, fonts, audio and video: served unchanged. A web view that navigates to
        /// one shows it as an image, text or media, never as a document that runs scripts.
        case passive = "passive"
        /// Anything else (scripts, plain text, JSON, PDF, web archives, binary, no declared type): served empty.
        case withheld = "withheld"
    }

    /// The lower-cased `type/subtype` of a media type string, without parameters.
    static func essence(_ mediaType: String) -> String {
        let base = mediaType.split(separator: ";", maxSplits: 1).first.map(String.init) ?? mediaType
        return base.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static let fontTypes: Set<String> = [
        "application/vnd.ms-opentype", "application/vnd.ms-fontobject", "application/font-sfnt", "application/font-woff",
        "application/font-woff2", "application/x-font-ttf", "application/x-font-otf", "application/x-font-truetype",
        "application/x-font-opentype", "application/x-font-woff",
    ]

    /// How a declared resource is served, given the media type Readium will serve it with (the manifest's).
    public static func treatment(forMediaType mediaType: String?) -> Treatment {
        guard let mediaType else { return .withheld }
        let e = essence(mediaType)
        let parts = e.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return .withheld }
        let (type, subtype) = (parts[0], parts[1])
        if e == "text/html" || e == "application/xhtml+xml" { return .htmlDocument }
        // WebKit renders every XML type as a document (`*/*+xml`, `application/xml`, `text/xml`, `text/xsl`), and an
        // element in the XHTML namespace inside one is a live HTML element.
        if subtype == "xml" || subtype.hasSuffix("+xml") || e == "text/xsl" { return .otherDocument }
        if subtype.contains("html") || subtype.contains("xml") { return .withheld }
        if type == "image" || type == "audio" || type == "video" || type == "font" || e == "text/css" || fontTypes.contains(e) {
            return .passive
        }
        return .withheld
    }

    // MARK: Engine-level layer: document loads limited to the reading order

    public struct RuleList: Sendable, Equatable {
        public var json: String
        /// False when some reading-order href cannot be written as a content-rule pattern exactly; then document loads
        /// are not restricted for this publication (the network rules still apply) and the hrefs are listed.
        public var documentsLimitedToReadingOrder: Bool
        public var unrepresentableHrefs: [String]
    }

    /// Characters a reading-order href may contain for an exact content-rule pattern: they mean themselves in
    /// WebKit's url-filter syntax (`.` is escaped). An href with any other character (including a raw non-ASCII
    /// character, which WebKit would percent-encode) disables the document restriction for that publication.
    static let literalHrefBytes: Set<UInt8> = Set(Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_~/%@,;=:!'&".utf8))

    /// `^readium://<route>/<href>([?#].*)?$`, or nil when `href` has a character outside `literalHrefBytes`.
    /// Readium 3.11.0 serves a publication at `readium://<UUID>/`; the route is matched as hexadecimal digits and
    /// hyphens. url-filter patterns are case-insensitive by default.
    public static func documentPattern(forHref href: String) -> String? {
        guard !href.isEmpty, !href.hasPrefix("/") else { return nil }
        var escaped = ""
        for byte in href.utf8 {
            if byte == UInt8(ascii: ".") {
                escaped += "\\."
            } else if literalHrefBytes.contains(byte) {
                escaped.append(Character(UnicodeScalar(byte)))
            } else {
                return nil
            }
        }
        return "^readium://[0-9a-fA-F-]+/" + escaped + "([?#].*)?$"
    }

    /// The content rule list for one publication: every load except `readium:`, `data:` and `about:` is blocked (as in
    /// `PublicationHTMLSafety.contentRuleListJSON`), and then every document load (a navigation of the page or of a
    /// frame) is blocked unless it is one of `readingOrderHrefs` (Readium's normalized hrefs) or `about:blank`.
    public static func contentRuleListJSON(readingOrderHrefs: [String]) -> RuleList {
        func rule(_ filter: String, _ action: String, documents: Bool = false) -> [String: Any] {
            var trigger: [String: Any] = ["url-filter": filter]
            if documents { trigger["resource-type"] = ["document"] }
            return ["trigger": trigger, "action": ["type": action]]
        }
        var rules: [[String: Any]] = [
            rule(".*", "block"),
            rule("^readium:", "ignore-previous-rules"),
            rule("^data:", "ignore-previous-rules"),
            rule("^about:", "ignore-previous-rules"),
        ]
        var patterns: [String] = []
        var unrepresentable: [String] = []
        for href in readingOrderHrefs {
            if let p = documentPattern(forHref: href) { patterns.append(p) } else { unrepresentable.append(href) }
        }
        let limited = unrepresentable.isEmpty && !patterns.isEmpty
        if limited {
            rules.append(rule(".*", "block", documents: true))
            rules.append(rule("^about:blank", "ignore-previous-rules", documents: true))
            for p in Array(Set(patterns)).sorted() { rules.append(rule(p, "ignore-previous-rules", documents: true)) }
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("[]".utf8)
        return RuleList(json: String(decoding: data, as: UTF8.self), documentsLimitedToReadingOrder: limited,
                        unrepresentableHrefs: unrepresentable)
    }
}
