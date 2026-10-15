import Foundation
@preconcurrency import SwiftSoup

/// Adapter-level controls that keep publication-owned scripts and remote resources out of the renderer and keep
/// hostile markup away from Readium's parsers (plan 8.3, 18.1). Readium 3.11.0 renders publication HTML in a WKWebView
/// with JavaScript enabled, allows non-link navigations, and walks SwiftSoup trees recursively, so these are applied by
/// Sylvia, not inherited from Readium (see ADR-0004).
///
/// Every publication document Readium reads goes through `sanitize(html:)` or `sanitize(nonHTMLDocument:)`, and what
/// Readium (its navigator, content iterator and search service) receives is either the document's canonical
/// re-serialization (`MarkupCanonicalizer`) or a "cannot be shown" placeholder. The served HTML is then parsed again,
/// once as XML (what WebKit does for `application/xhtml+xml`) and once with SwiftSoup's HTML5 parser (what Readium's
/// content iterator and search service do, and close to what WebKit does for `text/html`), and checked in both: the
/// CSP `<meta>` is the first child of the first `<head>`, there is no script element, event-handler attribute or
/// script URL, and the tree is no deeper than `maxElementDepth`. Anything that fails is withheld.
public enum PublicationHTMLSafety {
    /// Content Security Policy injected as the first element of every publication HTML document's head.
    /// Readium serves the publication and its own assets from the custom `readium:` scheme; nothing else may load.
    /// Reader-owned scripts are WKUserScripts and `evaluateJavaScript` calls, which a page CSP does not govern.
    public static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src 'none'",
        "style-src readium: 'unsafe-inline'",
        "img-src readium: data:",
        "font-src readium: data:",
        "media-src readium:",
        "connect-src 'none'",
        "frame-src 'none'",
        "child-src 'none'",
        "object-src 'none'",
        "worker-src 'none'",
        "manifest-src 'none'",
        "base-uri 'none'",
        "form-action 'none'",
    ].joined(separator: "; ")

    public static let cspMetaElement =
        "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\"/>"

    /// WKContentRuleList source: blocks every load except the `readium:` scheme, `data:` and `about:`.
    /// Second layer for what a CSP does not cover (for example a meta refresh, which Readium's navigation policy allows).
    public static let contentRuleListJSON = """
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^readium:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """

    // MARK: Limits (spike proposals, ADR-0004 section 4)

    /// Element nesting limit (plan 8.3, "excessive recursion"). Readium 3.11.0's content iterator walks parent chains
    /// recursively (`Node.language()` over SwiftSoup's tree) and overflowed a Swift concurrency thread's stack at a depth
    /// of 10,000 (SafetyTests, DeepNestingUITests). 256 is libxml2's historical default; the real fixtures nest 8-11.
    /// Checked on the XML parse and again on the SwiftSoup tree Readium will build from the served document.
    public static let maxElementDepth = 256
    /// Elements per document. Bounds the size of the SwiftSoup tree Readium builds (and its memory); the largest real
    /// fixture document has a few thousand.
    public static let maxElementsPerDocument = 100_000
    /// Attributes on one element (namespace declarations included). SwiftSoup stores attributes in an array and checks
    /// for duplicates linearly, so an element with a very large number of attributes costs quadratic time to parse.
    public static let maxAttributesPerElement = 256
    /// Attributes in one document (namespace declarations included). Attribute-dense markup is the slowest input per
    /// byte (review R2-02: about 6 s per MiB on the host, debug build, at 256 attributes per element, where element-dense
    /// markup takes about 2), so the total is capped too; the largest real fixture document has a few thousand.
    public static let maxAttributesPerDocument = 100_000
    /// Sanitizer workers that may run at once for one open publication. A worker that runs over the time budget cannot
    /// be stopped (it finishes in the background and its result is discarded), so without a limit a publication with
    /// many slow documents could keep many threads busy (review R2-02). Further reads wait for a worker, and the wait
    /// counts against their time budget.
    public static let maxConcurrentWorkersPerPublication = 2
    /// Wall-clock budget for sanitizing one document (parse, re-serialize, verify). Structural limits above keep the
    /// work linear; this is the backstop. A document over budget is withheld; Readium never parses it.
    public static let defaultTimeBudget: Duration = .seconds(20)
    /// Sanitizing runs on its own thread with this stack, so even a pathological tree cannot overflow it.
    static let workerStackBytes = 64 << 20

    // MARK: Results

    /// Why a document was replaced by a placeholder. The raw value is the placeholder's `data-sylvia-unavailable`.
    public enum Withheld: String, Sendable, Equatable {
        case excessiveNesting = "excessive-nesting"
        case unsupportedMarkup = "unsupported-markup"
        case timeBudget = "time-budget"
        case verificationFailed = "verification-failed"
        case activeContent = "active-content"
        /// A declared resource whose media type is neither a document the sanitizer handles nor a known passive type
        /// (image, style sheet, font, audio, video): served empty (`PublicationResourcePolicy`).
        case unsupportedType = "unsupported-type"

        /// Per-resource coverage status for "Search this book" (plan 11.3).
        public var extractionStatus: String { "unavailable_" + rawValue.replacingOccurrences(of: "-", with: "_") }
    }

    public struct Result: Sendable, Equatable {
        public var html: String
        /// Non-nil when `html` is a placeholder instead of the document.
        public var withheld: Withheld?
        /// Why the parse failed, for logs and evidence (never shown to the reader).
        public var detail: String?
        public var removedScripts = 0
        public var removedRefreshes = 0
        public var removedEventHandlers = 0
        public var removedScriptURLs = 0
        public var removedOther = 0
        public var droppedComments = 0
        /// True only when both parses of the served document find the CSP `<meta>` as the first child of the first
        /// `<head>` (`Verification`).
        public var cspInjected: Bool
        /// Deepest element nesting seen: the larger of the XML parse and SwiftSoup's tree of the served document. For
        /// a document withheld for nesting, the depth at which parsing stopped (the document nests at least this deep).
        public var elementDepth: Int
        public var elementCount: Int
        public var verification: Verification?
        public var seconds: Double = 0
        /// Attributes and namespace declarations in the parsed input (0 when parsing stopped early).
        public var attributeCount = 0

        public var replacedForNesting: Bool { withheld == .excessiveNesting }
    }

    /// What the served document looks like to each parser that reads it after the sanitizer.
    public struct Verification: Sendable, Equatable {
        public var xmlWellFormed: Bool
        /// XML view (libxml2; WebKit for `application/xhtml+xml`): root `{XHTML}html`, first child `{XHTML}head`, whose
        /// first child is `{XHTML}meta` carrying exactly `contentSecurityPolicy`.
        public var xmlCSPFirstInHead: Bool
        /// HTML5 view (SwiftSoup's HTML parser, forced; close to WebKit for `text/html`): the same structure.
        public var html5CSPFirstInHead: Bool
        public var xmlDepth: Int
        /// Readium's view: the tree `SwiftSoup.parse(_:)` builds, exactly as Readium 3.11.0's content iterator calls it
        /// (it picks SwiftSoup's XML tree builder when the text starts with `<?xml`, as every served document does).
        public var readiumDepth: Int
        public var readiumElements: Int
        public var html5Depth: Int
        public var html5Elements: Int
        /// Totals over all three views; all must be zero.
        public var scriptElements: Int
        public var eventHandlerAttributes: Int
        public var scriptURLAttributes: Int
        /// Both SwiftSoup parses returned a document.
        public var swiftSoupParsed = true

        /// Deepest nesting in any view.
        public var maxDepth: Int { max(xmlDepth, readiumDepth, html5Depth) }

        public var passed: Bool {
            xmlWellFormed && swiftSoupParsed && xmlCSPFirstInHead && html5CSPFirstInHead && scriptElements == 0 && eventHandlerAttributes == 0
                && scriptURLAttributes == 0
        }
    }

    /// Marker attribute on placeholders, so extraction can report the resource as unavailable instead of indexing it.
    public static let unavailableAttribute = "data-sylvia-unavailable"

    /// The XHTML document served instead of one that is withheld. Readium's navigator, content iterator and search
    /// service all read the publication through the sanitized container, so none of them sees the original.
    public static func unavailablePlaceholder(_ reason: Withheld) -> String {
        let why = switch reason {
        case .excessiveNesting: "its markup nests more than \(maxElementDepth) levels deep"
        case .unsupportedMarkup: "its markup is not XHTML that Sylvia can read safely"
        case .timeBudget: "preparing it took too long"
        case .verificationFailed: "it could not be made safe to display"
        case .activeContent: "it contains scripts or interactive content"
        case .unsupportedType: "its media type is not one Sylvia displays"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml"><head>\(cspMetaElement)<title>Unavailable</title></head>
        <body \(unavailableAttribute)="\(reason.rawValue)"><p>This section cannot be shown: \(why).</p></body></html>
        """
    }

    // MARK: HTML documents

    /// Sanitizes one publication HTML document on a dedicated thread (large stack) within `budget`. With a `limiter`,
    /// the worker first waits for one of the publication's worker slots; the wait counts against `budget`.
    public static func sanitize(html input: String, limiter: WorkerLimiter? = nil, budget: Duration = defaultTimeBudget) async -> Result {
        await sanitizeBounded(html: input, limiter: limiter, budget: budget).result
    }

    private static func sanitizeBounded(html input: String, limiter: WorkerLimiter?, budget: Duration) async -> (result: Result, ranOverBudget: Bool) {
        switch await runBounded(budget: budget, limiter: limiter, { sanitizeOnCurrentThread(html: input) }) {
        case let .finished(r): return (r, false)
        case .overBudget: return (placeholderResult(.timeBudget, detail: "over the \(budget) budget", depth: 0, count: 0), true)
        case .waitedOut: return (placeholderResult(.timeBudget, detail: "no sanitizer worker free within the \(budget) budget", depth: 0, count: 0), false)
        }
    }

    /// Documents of one open publication that ran over the time budget. Readium reads a document again for every use
    /// (each time the navigator loads it, the content iterator, the search service), and each read is sanitized
    /// again; once a document has run over budget, later reads get the placeholder at once instead of starting another
    /// worker. (A worker that ran over budget cannot be stopped; it finishes in the background and its result is
    /// discarded, so without this record a hostile document would start one more on every read.)
    public final class OverBudgetDocuments: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: Set<String> = []
        public init() {}
        public func contains(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return keys.contains(key) }
        func insert(_ key: String) { lock.lock(); keys.insert(key); lock.unlock() }
        public var count: Int { lock.lock(); defer { lock.unlock() }; return keys.count }
    }

    /// `sanitize(html:budget:)` for the document at `key` of a publication whose over-budget documents are `overBudget`
    /// and whose sanitizer workers are limited by `limiter`. Only a document whose own worker ran over the budget is
    /// recorded; one that waited for a worker past its budget is withheld this time and tried again on the next read.
    public static func sanitize(html input: String, key: String, overBudget: OverBudgetDocuments, limiter: WorkerLimiter? = nil,
                                budget: Duration = defaultTimeBudget) async -> Result {
        if overBudget.contains(key) {
            return placeholderResult(.timeBudget, detail: "over the \(budget) budget on an earlier read", depth: 0, count: 0)
        }
        let r = await sanitizeBounded(html: input, limiter: limiter, budget: budget)
        if r.ranOverBudget { overBudget.insert(key) }
        return r.result
    }

    /// `sanitize(nonHTMLDocument:budget:)` with the same record of over-budget documents and worker limit.
    public static func sanitize(nonHTMLDocument input: String, key: String, overBudget: OverBudgetDocuments, limiter: WorkerLimiter? = nil,
                                budget: Duration = defaultTimeBudget) async -> NonHTMLResult {
        if overBudget.contains(key) {
            return NonHTMLResult(document: nonHTMLPlaceholder(.timeBudget), withheld: .timeBudget, detail: "over budget on an earlier read")
        }
        let r = await sanitizeBounded(nonHTMLDocument: input, limiter: limiter, budget: budget)
        if r.ranOverBudget { overBudget.insert(key) }
        return r.result
    }

    /// Limits how many sanitizer workers run at once for one open publication (`maxConcurrentWorkersPerPublication`).
    /// A slot is held until the worker thread finishes, including a worker that ran over budget and whose result was
    /// discarded, so the CPU a publication's sanitizing can use is bounded however many documents it has.
    public final class WorkerLimiter: @unchecked Sendable {
        public let limit: Int
        private let lock = NSLock()
        private var active = 0
        private var peak = 0
        private var nextWaiter: UInt64 = 0
        private var waiters: [(id: UInt64, continuation: CheckedContinuation<Bool, Never>)] = []

        public init(limit: Int = maxConcurrentWorkersPerPublication) { self.limit = max(1, limit) }

        /// Workers running now (including ones that ran over budget and have not finished).
        public var running: Int { lock.lock(); defer { lock.unlock() }; return active }
        /// Most workers that ran at once.
        public var peakRunning: Int { lock.lock(); defer { lock.unlock() }; return peak }

        /// Takes a slot, waiting until `deadline` at most. Returns false if none became free in time.
        func acquire(deadline: ContinuousClock.Instant) async -> Bool {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                lock.lock()
                if active < limit {
                    active += 1
                    peak = max(peak, active)
                    lock.unlock()
                    continuation.resume(returning: true)
                    return
                }
                let id = nextWaiter
                nextWaiter += 1
                waiters.append((id, continuation))
                lock.unlock()
                let wait = max(0, (deadline - ContinuousClock.now).seconds)
                DispatchQueue.global().asyncAfter(deadline: .now() + wait) { [self] in
                    lock.lock()
                    guard let i = waiters.firstIndex(where: { $0.id == id }) else { return lock.unlock() }
                    let w = waiters.remove(at: i)
                    lock.unlock()
                    w.continuation.resume(returning: false)
                }
            }
        }

        /// Frees a slot, handing it straight to the oldest waiter if there is one.
        func release() {
            lock.lock()
            if waiters.isEmpty {
                active -= 1
                lock.unlock()
            } else {
                let w = waiters.removeFirst()
                lock.unlock()
                w.continuation.resume(returning: true)
            }
        }
    }

    /// The same work on the caller's thread (tests and benchmarks). Needs a stack of a few megabytes for SwiftSoup's
    /// parse of a document at the nesting limit; `sanitize(html:)` provides one.
    static func sanitizeOnCurrentThread(html input: String) -> Result {
        let clock = ContinuousClock()
        let start = clock.now
        var result = sanitizeUntimed(input)
        result.seconds = (clock.now - start).seconds
        return result
    }

    private static func canonicalizer(_ mode: MarkupCanonicalizer.Mode) -> MarkupCanonicalizer {
        MarkupCanonicalizer(mode: mode, limits: .init(maxDepth: maxElementDepth, maxElements: maxElementsPerDocument,
                                                       maxAttributesPerElement: maxAttributesPerElement,
                                                       maxAttributesPerDocument: maxAttributesPerDocument),
                            cspMetaElement: cspMetaElement)
    }

    private static func sanitizeUntimed(_ input: String) -> Result {
        let output: MarkupCanonicalizer.Output
        switch canonicalizer(.xhtml).canonicalize(input) {
        case let .success(o): output = o
        case let .failure(failure):
            if case let .excessiveNesting(depth) = failure {
                return placeholderResult(.excessiveNesting, detail: "\(failure)", depth: depth, count: 0)
            }
            return placeholderResult(.unsupportedMarkup, detail: "\(failure)", depth: 0, count: 0)
        }
        let v = verify(servedHTML: output.markup)
        var result = Result(
            html: output.markup, withheld: nil, detail: nil,
            removedScripts: output.removedScripts, removedRefreshes: output.removedRefreshes,
            removedEventHandlers: output.removedEventHandlers, removedScriptURLs: output.removedScriptURLs,
            removedOther: output.removedOther, droppedComments: output.droppedComments,
            cspInjected: v.xmlCSPFirstInHead && v.html5CSPFirstInHead,
            elementDepth: max(output.elementDepth, v.maxDepth),
            elementCount: max(output.elementCount, v.readiumElements, v.html5Elements),
            verification: v
        )
        result.attributeCount = output.attributeCount
        if v.maxDepth > maxElementDepth {
            return placeholderResult(.excessiveNesting, detail: "served tree depth: XML \(v.xmlDepth), Readium's SwiftSoup parse \(v.readiumDepth), HTML5 parse \(v.html5Depth)",
                                     depth: result.elementDepth, count: result.elementCount)
        }
        if max(v.readiumElements, v.html5Elements) > maxElementsPerDocument {
            return placeholderResult(.unsupportedMarkup, detail: "served tree has \(max(v.readiumElements, v.html5Elements)) elements",
                                     depth: result.elementDepth, count: result.elementCount)
        }
        if !v.passed {
            result = placeholderResult(.verificationFailed, detail: "\(v)", depth: result.elementDepth, count: result.elementCount)
        }
        return result
    }

    private static func placeholderResult(_ reason: Withheld, detail: String, depth: Int, count: Int) -> Result {
        let html = unavailablePlaceholder(reason)
        let v = verify(servedHTML: html)
        return Result(html: html, withheld: reason, detail: detail, cspInjected: v.xmlCSPFirstInHead && v.html5CSPFirstInHead,
                      elementDepth: depth, elementCount: count, verification: v)
    }

    // MARK: Verification of the served document

    /// Parses `html` three ways (libxml2; `SwiftSoup.parse` as Readium calls it; SwiftSoup's HTML5 parser) and reports
    /// what each sees (see `Verification`). Iterative: no recursion over the trees.
    public static func verify(servedHTML html: String) -> Verification {
        let xml = XMLView.inspect(html)
        var v = Verification(xmlWellFormed: xml.wellFormed, xmlCSPFirstInHead: xml.cspFirstInHead, html5CSPFirstInHead: false,
                             xmlDepth: xml.depth, readiumDepth: 0, readiumElements: 0, html5Depth: 0, html5Elements: 0,
                             scriptElements: xml.scripts, eventHandlerAttributes: xml.handlers, scriptURLAttributes: xml.scriptURLs)
        if let readium = try? SwiftSoup.parse(html) {
            let r = SoupView.inspect(readium)
            v.readiumDepth = r.depth
            v.readiumElements = r.elements
            v.scriptElements += r.scripts
            v.eventHandlerAttributes += r.handlers
            v.scriptURLAttributes += r.scriptURLs
        } else {
            v.swiftSoupParsed = false
        }
        if let html5 = try? SwiftSoup.parseHTML(html, "") {
            let h = SoupView.inspect(html5)
            v.html5Depth = h.depth
            v.html5Elements = h.elements
            v.html5CSPFirstInHead = h.cspFirstInHead
            v.scriptElements += h.scripts
            v.eventHandlerAttributes += h.handlers
            v.scriptURLAttributes += h.scriptURLs
        } else {
            v.swiftSoupParsed = false
        }
        return v
    }

    /// One SwiftSoup tree: depth, element count, scripts, handlers, script URLs, and whether the CSP `<meta>` is the
    /// first element child of a `<head>` that is the first element child of the root `html`.
    private enum SoupView {
        struct Report { var depth = 0, elements = 0, scripts = 0, handlers = 0, scriptURLs = 0; var cspFirstInHead = false }

        static func inspect(_ document: SwiftSoup.Document) -> Report {
            var r = Report()
            // SwiftSoup's Document is itself an Element; depth counts from its children (the root `html` is 1).
            var stack: [(SwiftSoup.Node, Int)] = document.getChildNodes().map { ($0, 0) }
            while let (node, level) = stack.popLast() {
                let isElement = node is SwiftSoup.Element
                if let element = node as? SwiftSoup.Element {
                    r.elements += 1
                    r.depth = max(r.depth, level + 1)
                    if element.tagName().lowercased() == "script" { r.scripts += 1 }
                    if let attributes = element.getAttributes() {
                        for a in attributes {
                            let key = a.getKey()
                            let local = key.split(separator: ":").last.map(String.init) ?? key
                            if local.lowercased().hasPrefix("on") { r.handlers += 1 }
                            if MarkupCanonicalizer.isScriptURL(a.getValue()) { r.scriptURLs += 1 }
                        }
                    }
                }
                for child in node.getChildNodes() { stack.append((child, isElement ? level + 1 : level)) }
            }
            func firstElementChild(_ node: SwiftSoup.Node) -> SwiftSoup.Element? {
                node.getChildNodes().lazy.compactMap { $0 as? SwiftSoup.Element }.first
            }
            if let root = firstElementChild(document), root.tagName() == "html",
               let head = firstElementChild(root), head.tagName() == "head",
               let meta = firstElementChild(head), meta.tagName() == "meta",
               (try? meta.attr("http-equiv"))?.lowercased() == "content-security-policy",
               (try? meta.attr("content")) == contentSecurityPolicy {
                r.cspFirstInHead = true
            }
            return r
        }
    }

    /// The XML side of `verify`: one `XMLParser` pass.
    private final class XMLView: NSObject, XMLParserDelegate {
        var wellFormed = false
        var cspFirstInHead = false
        var maxDepthSeen = 0, scripts = 0, handlers = 0, scriptURLs = 0
        /// Root, the root's first element child, and that element's first element child.
        private var firstChildPath: [(String, String, [String: String])] = []
        private var childCounts: [Int] = []
        private var onPath: [Bool] = []

        struct Report { var wellFormed: Bool; var cspFirstInHead: Bool; var depth: Int; var scripts: Int; var handlers: Int; var scriptURLs: Int }

        static func inspect(_ markup: String) -> Report {
            let view = XMLView()
            let parser = XMLParser(data: Data(markup.utf8))
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = view
            view.wellFormed = parser.parse()
            let path = view.firstChildPath
            let xhtml = MarkupCanonicalizer.xhtmlNamespace
            view.cspFirstInHead = view.wellFormed && path.count >= 3
                && path[0].0 == "html" && path[0].1 == xhtml
                && path[1].0 == "head" && path[1].1 == xhtml
                && path[2].0 == "meta" && path[2].1 == xhtml
                && MarkupCanonicalizerAttributes.value("http-equiv", path[2].2)?.lowercased() == "content-security-policy"
                && MarkupCanonicalizerAttributes.value("content", path[2].2) == contentSecurityPolicy
            return Report(wellFormed: view.wellFormed, cspFirstInHead: view.cspFirstInHead, depth: view.maxDepthSeen,
                          scripts: view.scripts, handlers: view.handlers, scriptURLs: view.scriptURLs)
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            let d = childCounts.count
            let isOnPath = d == 0 ? firstChildPath.isEmpty : (d < 3 && onPath[d - 1] && childCounts[d - 1] == 0)
            if d > 0 { childCounts[d - 1] += 1 }
            if isOnPath { firstChildPath.append((elementName, namespaceURI ?? "", attributeDict)) }
            childCounts.append(0)
            onPath.append(isOnPath)
            let depth = d + 1
            maxDepthSeen = max(maxDepthSeen, depth)
            if elementName.lowercased() == "script" { scripts += 1 }
            for (name, value) in attributeDict {
                let local = name.split(separator: ":").last.map(String.init) ?? name
                if local.lowercased().hasPrefix("on") { handlers += 1 }
                if MarkupCanonicalizer.isScriptURL(value) { scriptURLs += 1 }
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            childCounts.removeLast()
            onPath.removeLast()
        }
    }

    // MARK: Documents that are not HTML (SVG pages, XML items in the reading order)

    /// A page CSP can only be declared by an HTML `<meta>` element, so an SVG or generic XML document has none. Such a
    /// document is served (re-serialized canonically) only when the parse finds no active content; otherwise it is
    /// replaced by a placeholder. Active content: a `script` element under any prefix, an event-handler attribute, a
    /// script URL, `foreignObject` (it can carry XHTML), an embedding element (`iframe`, `object`, `embed`, ...),
    /// `handler`/`listener`, SVG animation elements, `<base>`, a meta refresh, a resource-hint link, a form control
    /// (`form`, `button`, `input`, ...) or `formaction`/`action` attribute, and any element in the XHTML namespace
    /// (WebKit makes it a live HTML element, and such a document has no CSP to stop a form submission; review R2-01).
    public static let activeContentAttribute = unavailableAttribute

    public static func nonHTMLPlaceholder(_ reason: Withheld) -> String {
        let why = reason == .activeContent ? "it contains scripts or interactive content" : "it could not be read safely"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="0 0 600 120" \(unavailableAttribute)="\(reason.rawValue)"><text x="10" y="40">This section cannot be shown: \(why).</text></svg>
        """
    }

    public static var activeContentPlaceholder: String { nonHTMLPlaceholder(.activeContent) }

    public struct NonHTMLResult: Sendable, Equatable {
        public var document: String
        public var withheld: Withheld?
        public var detail: String?
        public var replaced: Bool { withheld != nil }
    }

    public static func sanitize(nonHTMLDocument input: String, limiter: WorkerLimiter? = nil, budget: Duration = defaultTimeBudget) async -> NonHTMLResult {
        await sanitizeBounded(nonHTMLDocument: input, limiter: limiter, budget: budget).result
    }

    private static func sanitizeBounded(nonHTMLDocument input: String, limiter: WorkerLimiter?, budget: Duration) async -> (result: NonHTMLResult, ranOverBudget: Bool) {
        switch await runBounded(budget: budget, limiter: limiter, { sanitizeOnCurrentThread(nonHTMLDocument: input) }) {
        case let .finished(r): return (r, false)
        case .overBudget: return (NonHTMLResult(document: nonHTMLPlaceholder(.timeBudget), withheld: .timeBudget, detail: "over budget"), true)
        case .waitedOut: return (NonHTMLResult(document: nonHTMLPlaceholder(.timeBudget), withheld: .timeBudget, detail: "no sanitizer worker free within the budget"), false)
        }
    }

    static func sanitizeOnCurrentThread(nonHTMLDocument input: String) -> NonHTMLResult {
        switch canonicalizer(.nonHTML).canonicalize(input) {
        case let .failure(f):
            return NonHTMLResult(document: nonHTMLPlaceholder(.unsupportedMarkup), withheld: .unsupportedMarkup, detail: "\(f)")
        case let .success(o):
            let removed = o.removedScripts + o.removedRefreshes + o.removedEventHandlers + o.removedScriptURLs + o.removedOther
            if removed > 0 {
                return NonHTMLResult(document: nonHTMLPlaceholder(.activeContent), withheld: .activeContent, detail: "\(removed) active items")
            }
            let check = XMLView.inspect(o.markup)
            guard check.wellFormed, check.scripts == 0, check.handlers == 0, check.scriptURLs == 0 else {
                return NonHTMLResult(document: nonHTMLPlaceholder(.verificationFailed), withheld: .verificationFailed, detail: "\(check)")
            }
            return NonHTMLResult(document: o.markup, withheld: nil, detail: nil)
        }
    }

    // MARK: Worker thread with a time budget

    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?
        init(_ c: CheckedContinuation<T, Never>) { continuation = c }
        func resume(_ value: T) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }

    enum Bounded<T: Sendable>: Sendable {
        case finished(T)
        /// The worker did not finish within the budget; it runs to completion in the background (holding its
        /// limiter slot) and its result is discarded.
        case overBudget
        /// No limiter slot became free within the budget; no worker was started.
        case waitedOut
    }

    /// Runs `work` on a new thread with `workerStackBytes` of stack, after taking a slot from `limiter` (if any). The
    /// budget covers the wait for a slot and the work.
    static func runBounded<T: Sendable>(budget: Duration, limiter: WorkerLimiter?, _ work: @escaping @Sendable () -> T) async -> Bounded<T> {
        let deadline = ContinuousClock.now + budget
        if let limiter, !(await limiter.acquire(deadline: deadline)) { return .waitedOut }
        let remaining = deadline - ContinuousClock.now
        guard remaining > .zero else {
            limiter?.release()
            return .waitedOut
        }
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let thread = Thread {
                let value = work()
                limiter?.release()
                once.resume(.finished(value))
            }
            thread.stackSize = workerStackBytes
            thread.name = "sylvia.publication-html-safety"
            thread.start()
            DispatchQueue.global().asyncAfter(deadline: .now() + remaining.seconds) { once.resume(.overBudget) }
        }
    }
}

enum MarkupCanonicalizerAttributes {
    /// Value of the attribute whose local name is `localName` (case-insensitive), whatever its prefix.
    static func value(_ localName: String, _ attributes: [String: String]) -> String? {
        for (name, value) in attributes {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            if local.lowercased() == localName { return value }
        }
        return nil
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
