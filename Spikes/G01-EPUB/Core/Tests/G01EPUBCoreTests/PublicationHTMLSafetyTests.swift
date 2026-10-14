import Foundation
@testable import G01EPUBCore
import SwiftSoup
import Testing

/// The publication HTML sanitizer (plan 8.3, 18.1; ADR-0004 section 4). Host (macOS); the same code runs in the
/// simulator harness, where SafetyTests checks the result in WebKit.
@Suite("Publication HTML sanitizer: canonical re-serialization, CSP, nesting and time bounds")
struct PublicationHTMLSafetyTests {
    typealias Safety = PublicationHTMLSafety
    static let xhtml = "http://www.w3.org/1999/xhtml"

    func doc(_ body: String, head: String = "<title>t</title>") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="\(Self.xhtml)" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en"><head>\(head)</head>
        <body>\(body)</body></html>
        """
    }

    func expectServedSafely(_ r: Safety.Result, _ comment: Testing.Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(r.withheld == nil, "\(comment.map { "\($0): " } ?? "")withheld \(String(describing: r.withheld)) \(r.detail ?? "")", sourceLocation: sourceLocation)
        #expect(r.cspInjected, comment, sourceLocation: sourceLocation)
        #expect(r.verification?.passed == true, "\(String(describing: r.verification))", sourceLocation: sourceLocation)
        #expect(!r.html.lowercased().contains("<script"), comment, sourceLocation: sourceLocation)
    }

    // MARK: Scripts, handlers, script URLs, CSP

    @Test("Scripts, meta refresh, handlers and script URLs are removed; the CSP is first in head; text is untouched")
    func basics() async throws {
        let html = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title><script src="a.js"/><SCRIPT type="text/javascript">alert(1 &lt; 2)</SCRIPT><meta http-equiv="refresh" content="0;url=http://x"/><link rel="dns-prefetch" href="//x.invalid"/></head>
        <body onload="x()"><p>Text with &lt;script&gt; written as words, and script mentioned.</p><svg xmlns="http://www.w3.org/2000/svg"><script>bad()</script><a href="java&#9;script&#58;bad()"><text>t</text></a></svg><img src="i.png" onerror="bad()" alt="a &amp; b"/></body></html>
        """
        let r = await Safety.sanitize(html: html)
        expectServedSafely(r)
        #expect(r.removedScripts == 3)
        #expect(r.removedRefreshes == 1)
        #expect(r.removedEventHandlers == 2)
        #expect(r.removedScriptURLs == 1)
        #expect(r.removedOther == 1)
        #expect(r.html.contains("<head>" + Safety.cspMetaElement + "<title>t</title>"))
        #expect(r.html.contains("<p>Text with &lt;script&gt; written as words, and script mentioned.</p>"))
        #expect(r.html.contains(#"<img alt="a &amp; b" src="i.png"/>"#))
        #expect(!r.html.contains("onload") && !r.html.contains("onerror") && !r.html.contains("refresh"))
        let rules = try JSONSerialization.jsonObject(with: Data(Safety.contentRuleListJSON.utf8)) as? [[String: Any]]
        #expect(rules?.count == 4)
    }

    /// R1-02's two inputs, and the other ways a text-level injector and a parser disagree about where `<head>` is.
    @Test("The CSP cannot be displaced: a head inside a comment, a prefixed root, a missing or late head")
    func cspPlacementBypasses() async {
        let cases: [(String, String)] = [
            ("comment containing <head> before the real head", """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><!-- <head> --><head><title>t</title></head>
            <body onload="window.__reviewProbe = true"><img src="missing.png" onerror="document.documentElement.setAttribute('data-review-pwned','1')"/><p>Text.</p></body></html>
            """),
            ("namespace-prefixed root", """
            <?xml version="1.0" encoding="UTF-8"?>
            <h:html xmlns:h="http://www.w3.org/1999/xhtml"><h:head><h:title>t</h:title></h:head>
            <h:body onload="window.__reviewProbe = true"><h:script>window.__reviewProbe = true</h:script><h:p>Text.</h:p></h:body></h:html>
            """),
            ("<!--> opener", #"<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><!--><script>bad()</script>--><p>Text.</p></body></html>"#),
            ("no head", #"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Text.</p></body></html>"#),
            ("head after body", #"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Text.</p></body><head><title>t</title></head></html>"#),
            ("script first", #"<html xmlns="http://www.w3.org/1999/xhtml"><script>bad()</script><head/><body><p>Text.</p></body></html>"#),
            // An HTML5 parser reads text before the head as the start of the body, and a meta after it as body content,
            // where WebKit ignores a CSP; the head with the CSP must come before such text.
            ("text before head", #"<html xmlns="http://www.w3.org/1999/xhtml">Text.<head><title>t</title></head><body onload="bad()"><p>More.</p></body></html>"#),
            ("CDATA before head", #"<html xmlns="http://www.w3.org/1999/xhtml"><![CDATA[Text.]]><head><title>t</title></head><body><p>More.</p></body></html>"#),
            ("empty root", #"<html xmlns="http://www.w3.org/1999/xhtml"/>"#),
            ("CDATA holding markup", #"<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p><![CDATA[</p><script>bad()</script>]]>Text.</p></body></html>"#),
            ("title holding markup", #"<html xmlns="http://www.w3.org/1999/xhtml"><head><title>&lt;/title&gt;&lt;script&gt;bad()&lt;/script&gt;</title></head><body><p>Text.</p></body></html>"#),
            ("prefixed script in another namespace", #"<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><x:script xmlns:x="urn:other">bad()</x:script><x:p xmlns:x="urn:other" x:onclick="bad()">Text.</x:p></body></html>"#),
            ("SVG animation to a script URL", #"<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><svg xmlns="http://www.w3.org/2000/svg"><a><set attributeName="href" to="javascript:bad()"/><text>Text.</text></a></svg></body></html>"#),
            ("embedding elements and base", #"<html xmlns="http://www.w3.org/1999/xhtml"><head><base href="http://127.0.0.1/"/></head><body><iframe srcdoc="&lt;script&gt;bad()&lt;/script&gt;"/><object data="x"/><embed src="x"/><p xml:base="http://127.0.0.1/">Text.</p></body></html>"#),
        ]
        for (name, html) in cases {
            let r = await Safety.sanitize(html: html)
            expectServedSafely(r, "\(name)")
            #expect(r.html.contains("<html xmlns=\"\(Self.xhtml)\""), "\(name): \(r.html)")
            #expect(r.html.contains("<head>" + Safety.cspMetaElement) || r.html.contains("<head>" + Safety.cspMetaElement + "</head>"), "\(name): \(r.html)")
            for needle in ["onload", "onerror", "onclick", "<!--", "javascript", "<base", "iframe", "<object", "<embed", "xml:base", "srcdoc", "<set "] {
                #expect(!r.html.contains(needle), "\(name): \(needle) survived: \(r.html)")
            }
            if html.contains("Text.") { #expect(r.html.contains("Text."), "\(name): text lost: \(r.html)") }
        }
    }

    @Test("A prefixed root comes out unprefixed in the XHTML namespace, with other prefixes kept")
    func namespaces() async {
        let html = """
        <h:html xmlns:h="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><h:head><h:title>t</h:title></h:head><h:body><h:p epub:type="z3998:verse" xml:lang="la">Arma</h:p><p>no namespace</p><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="a.png"/><foreignObject><h:p>inside</h:p></foreignObject></svg></h:body></h:html>
        """
        let r = await Safety.sanitize(html: html)
        expectServedSafely(r)
        #expect(r.html.contains(#"<html xmlns="http://www.w3.org/1999/xhtml" xmlns:h="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head>"#), "\(r.html)")
        #expect(r.html.contains(#"<p epub:type="z3998:verse" xml:lang="la">Arma</p>"#), "\(r.html)")
        #expect(r.html.contains(#"<p xmlns="">no namespace</p>"#), "\(r.html)")
        #expect(r.html.contains(#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="a.png"></image><foreignObject><p xmlns="http://www.w3.org/1999/xhtml">inside</p></foreignObject></svg>"#), "\(r.html)")
    }

    @Test("Self-closed non-void elements are closed explicitly, so an HTML5 parser does not nest what follows")
    func explicitClosing() async {
        let r = await Safety.sanitize(html: doc(#"<div id="a"/><p>after<br/>line</p><a id="x"/><td/>"#))
        expectServedSafely(r)
        #expect(r.html.contains(#"<div id="a"></div><p>after<br/>line</p><a id="x"></a><td></td>"#), "\(r.html)")
    }

    /// Foundation's XMLParser drops a U+FEFF that starts a reported string (NSString treats it as a byte-order mark).
    /// Standard Ebooks write U+FEFF as a word joiner right after inline elements, so the sanitizer escapes it around
    /// the parser. Literal U+E000 text, which the escape uses, must survive too.
    @Test("U+FEFF survives at the start of a text node or attribute, as a character or a reference; U+E000 too")
    func byteOrderMarkCharacters() async {
        let html = doc("<p title=\"\u{FEFF}t\"><i>Pioneer</i>\u{FEFF}\u{2014}a<i>b</i>&#xFEFF;c<i>d</i>&#65279;e \u{E000}F \u{E000}\u{E000} &#xE000;F</p><![CDATA[\u{FEFF}x]]>")
        let r = await Safety.sanitize(html: html)
        expectServedSafely(r)
        #expect(r.html.contains("<p title=\"\u{FEFF}t\"><i>Pioneer</i>\u{FEFF}\u{2014}a<i>b</i>\u{FEFF}c<i>d</i>\u{FEFF}e \u{E000}F \u{E000}\u{E000} \u{E000}F</p>\u{FEFF}x"), "\(r.html.debugDescription)")
    }

    @Test("Named entities from the XHTML DTDs become characters; unknown entities and entity declarations are refused")
    func entities() async {
        let xhtml11 = """
        <?xml version='1.0' encoding='iso-8859-1'?>
        <!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.1//EN' 'http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd'>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body><p title="a&nbsp;b">x&nbsp;y&mdash;z &amp; &#x1D509; caf\u{E9}</p></body></html>
        """
        let r = await Safety.sanitize(html: xhtml11)
        expectServedSafely(r)
        #expect(r.html.contains("<p title=\"a\u{A0}b\">x\u{A0}y\u{2014}z &amp; \u{1D509} caf\u{E9}</p>"), "\(r.html)")
        #expect(r.html.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n"))

        let unknown = await Safety.sanitize(html: doc("<p>a&bogus;b</p>"))
        #expect(unknown.withheld == .unsupportedMarkup)
        let declared = await Safety.sanitize(html: """
        <?xml version="1.0"?><!DOCTYPE html [<!ENTITY x "<script>bad()</script>">]><html xmlns="http://www.w3.org/1999/xhtml"><body>&x;</body></html>
        """)
        #expect(declared.withheld == .unsupportedMarkup)
        #expect(declared.detail?.contains("internalDTDSubset") == true, "\(declared.detail ?? "")")
        // A ">" inside a quoted public or system identifier does not end the DOCTYPE, so the internal subset after it is
        // still seen and refused.
        for doctype in [#"<!DOCTYPE html SYSTEM "a>b" [<!ATTLIST p onclick CDATA "bad()">]>"#,
                        #"<!DOCTYPE html PUBLIC 'x>' "y>" [<!ENTITY nbsp "&#160;">]>"#] {
            let quoted = await Safety.sanitize(html: """
            <?xml version="1.0"?>\(doctype)<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p>x&nbsp;y</p></body></html>
            """)
            #expect(quoted.withheld == .unsupportedMarkup, "\(doctype)")
            #expect(quoted.detail?.contains("internalDTDSubset") == true, "\(doctype): \(quoted.detail ?? "")")
        }
        // A quoted "[" is part of an identifier, not an internal subset.
        let bracket = await Safety.sanitize(html: """
        <?xml version="1.0"?><!DOCTYPE html SYSTEM "about:legacy-compat[1]"><html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p>x</p></body></html>
        """)
        expectServedSafely(bracket)
    }

    @Test("Documents that are not well-formed XHTML, or whose root is not XHTML html, are withheld")
    func refused() async {
        let inputs = [
            "<html xmlns=\"\(Self.xhtml)\"><head/><body><p>unclosed</body></html>",
            "<html><head/><body><p>no namespace</p></body></html>",
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><text>svg root</text></svg>",
            "<html xmlns=\"\(Self.xhtml)\"><head/><body><p a=\"1\" a=\"2\">dup</p></body></html>",
            "plain text",
            "",
        ]
        for input in inputs {
            let r = await Safety.sanitize(html: input)
            #expect(r.withheld == .unsupportedMarkup, "\(input): \(r.detail ?? "")")
            #expect(r.html == Safety.unavailablePlaceholder(.unsupportedMarkup))
            #expect(r.cspInjected, "the placeholder carries the CSP")
            #expect(r.verification?.passed == true)
        }
    }

    // MARK: Nesting (R1-01)

    func nested(_ n: Int) -> String {
        doc("<p>" + String(repeating: "<span>", count: n) + "Innermost words." + String(repeating: "</span>", count: n) + "</p>")
    }

    @Test("Nesting at the limit is served; deeper is withheld before any HTML parser builds the tree")
    func nesting() async {
        let limit = Safety.maxElementDepth
        // html, body, p = 3 levels around the spans.
        let atLimit = await Safety.sanitize(html: nested(limit - 3))
        expectServedSafely(atLimit)
        #expect(atLimit.elementDepth == limit)
        #expect(atLimit.verification?.html5Depth == limit)
        #expect(atLimit.verification?.readiumDepth == limit)
        #expect(atLimit.verification?.xmlDepth == limit)
        #expect(atLimit.html.contains("Innermost words."))

        let over = await Safety.sanitize(html: nested(limit - 2))
        #expect(over.withheld == .excessiveNesting)

        let deep = await Safety.sanitize(html: nested(10_000))
        #expect(deep.withheld == .excessiveNesting)
        #expect(deep.replacedForNesting)
        #expect(deep.elementDepth == limit + 1, "parsing stops at the first element past the limit")
        #expect(!deep.html.contains("Innermost words."))
        #expect(deep.html.contains("\(Safety.unavailableAttribute)=\"excessive-nesting\""))
        #expect(deep.cspInjected)
    }

    /// R1-01's two inputs: 10,000 spans inside `<!-->...-->` (well-formed XML: one comment) and 10,000
    /// `<span></x>` pairs (mismatched end tags). A byte scanner measured both as shallow while SwiftSoup built a
    /// 10,000-deep tree. Here the first is served without the comment (so no parser ever sees the spans), the second is
    /// refused as not well-formed; neither reaches an HTML parser deep.
    @Test("Parser-divergence nesting: comment-wrapped and unmatched-end-tag nesting cannot reach Readium deep")
    func nestingBypasses() async {
        let wrapped = doc("<!-->" + String(repeating: "<span>", count: 10_000) + "Innermost words." + "-->" + "<p>After.</p>")
        let w = await Safety.sanitize(html: wrapped)
        expectServedSafely(w)
        #expect(!w.html.contains("<span>") && !w.html.contains("Innermost"))
        #expect((w.verification?.html5Depth ?? .max) <= 4, "\(String(describing: w.verification))")
        #expect(w.droppedComments == 1)

        let unmatched = doc("<p>" + String(repeating: "<span></x>", count: 10_000) + "</p>")
        let u = await Safety.sanitize(html: unmatched)
        #expect(u.withheld == .unsupportedMarkup, "\(u.detail ?? "")")
        #expect(!u.html.contains("<span"))
    }

    /// XML depth within the limit but an HTML5 tree deeper than it: nested tables gain an implicit tbody per level when
    /// SwiftSoup's HTML5 parser reads them (as WebKit's HTML parser would for a `text/html` resource). The check on
    /// every parser's tree, not only the XML one, withholds it.
    @Test("A tree deeper in one parser than in XML is caught")
    func html5Restructuring() async {
        let k = 84 // html + body + 3 per level = 254 in XML; 4 per level in HTML5 = 338
        let body = String(repeating: "<table><tr><td>", count: k) + "cell" + String(repeating: "</td></tr></table>", count: k)
        let r = await Safety.sanitize(html: """
        <html xmlns="http://www.w3.org/1999/xhtml"><head/><body>\(body)</body></html>
        """)
        #expect(r.withheld == .excessiveNesting, "\(r.detail ?? "") \(String(describing: r.verification))")
        #expect(r.elementDepth > Safety.maxElementDepth)
        #expect(r.detail?.contains("HTML5 parse 338") == true, "\(r.detail ?? "")")
    }

    @Test("Element and attribute counts are bounded")
    func counts() async {
        let many = await Safety.sanitize(html: doc(String(repeating: "<br/>", count: Safety.maxElementsPerDocument)))
        #expect(many.withheld == .unsupportedMarkup)
        #expect(many.detail?.contains("tooManyElements") == true, "\(many.detail ?? "")")
        let attributes = (0 ... Safety.maxAttributesPerElement).map { "a\($0)=\"1\"" }.joined(separator: " ")
        let wide = await Safety.sanitize(html: doc("<p \(attributes)>x</p>"))
        #expect(wide.withheld == .unsupportedMarkup)
        #expect(wide.detail?.contains("tooManyAttributes") == true, "\(wide.detail ?? "")")
        // Namespace declarations are written out again and every HTML parser reads them as attributes, so they count.
        let declarations = (0 ... Safety.maxAttributesPerElement).map { "xmlns:p\($0)=\"urn:p\($0)\"" }.joined(separator: " ")
        let namespaces = await Safety.sanitize(html: doc("<p \(declarations)>x</p>"))
        #expect(namespaces.withheld == .unsupportedMarkup)
        #expect(namespaces.detail?.contains("tooManyAttributes(") == true, "\(namespaces.detail ?? "")")
        // Attributes per document (review R2-02): just past the cap is refused, and parsing stops there.
        let perElement = 200
        let dense = (0 ..< perElement).map { "a\($0)=\"v\"" }.joined(separator: " ")
        let over = await Safety.sanitize(html: doc(String(repeating: "<i \(dense)>x</i>", count: Safety.maxAttributesPerDocument / perElement + 1)))
        #expect(over.withheld == .unsupportedMarkup)
        #expect(over.detail?.contains("tooManyAttributesInDocument") == true, "\(over.detail ?? "")")
    }

    // MARK: Time (R1-04)

    /// R1-04: the old regex sanitizer took 21.5 s on 128 KiB of `<script ` tokens inside a comment (quadratic). The
    /// parser-based sanitizer is linear: the same patterns at 1 to 16 MiB (the preflight's markup limit) finish well
    /// inside the budget, and doubling the input roughly doubles the time.
    @Test("Sanitizing is linear in the input, up to the 16 MiB markup limit")
    func linearTime() async throws {
        let mib = 1 << 20
        func fill(_ unit: String, _ bytes: Int) -> String { String(repeating: unit, count: max(1, bytes / unit.utf8.count)) }
        let patterns: [(String, (Int) -> String)] = [
            // Reviewer's input: one comment of `<script ` tokens (libxml2 refuses comments over 10 MB, so the large
            // ones are refused quickly).
            ("script tokens in one comment", { doc("<!--" + fill("<script ", $0) + "-->") }),
            // The same tokens in many small comments (never refused for size).
            ("script tokens in 1 KiB comments", { doc(fill("<!--" + String(repeating: "<script ", count: 127) + "-->", $0)) }),
            // Escaped tokens in text.
            ("escaped script tokens in text", { doc("<p>" + fill("&lt;script ", $0) + "</p>") }),
            // Text with entity references.
            ("named entities in text", { doc("<p>" + fill("a&nbsp;b&amp;c&mdash;", $0) + "</p>") }),
            // Elements up to the element cap, with attributes.
            ("many elements with attributes", { doc(fill("<span class=\"a\" title=\"b\">x</span>", $0)) }),
            // Review R2-02: attribute-dense markup, the slowest per byte (refused once it passes the document's
            // attribute cap, so the larger sizes stop early).
            ("256 attributes per element", { doc(fill("<i " + attributeList(256) + ">x</i>", $0)) }),
            ("64 attributes per element", { doc(fill("<i " + attributeList(64) + ">x</i>", $0)) }),
            ("long attribute values", { doc(fill("<i title=\"" + String(repeating: "v", count: 4000) + "\">x</i>", $0)) }),
        ]
        let loadBefore = Self.loadAverage()
        var rows: [String] = []
        for (name, make) in patterns {
            var times: [Int: Double] = [:]
            for size in [1, 2, 4, 8, 16] {
                let input = make(size * mib)
                let r = await Safety.sanitize(html: input, budget: .seconds(120))
                #expect(r.withheld != .timeBudget, "\(name) \(size) MiB hit the budget")
                times[size] = r.seconds
                rows.append("\(name)\t\(size) MiB\t\(String(format: "%.3f", r.seconds)) s\t\(r.withheld?.rawValue ?? "served")")
            }
            #expect(times[16]! < Safety.defaultTimeBudget.seconds, "\(name): 16 MiB took \(times[16]!) s")
            // Linear: 16x the input takes well under 16 x 16 times as long (quadratic would be 256x).
            #expect(times[16]! <= max(0.05, times[1]!) * 40, "\(name): \(times)")
        }
        // The slowest documents that are still served: just under the caps (review R2-02).
        let atCaps: [(String, String)] = [
            ("256 attributes per element, just under the document's attribute cap",
             doc(String(repeating: "<i " + attributeList(256) + ">x</i>", count: Safety.maxAttributesPerDocument / 256 - 1))),
            ("one attribute per element, just under the element cap",
             doc(String(repeating: "<i a=\"v\">x</i>", count: Safety.maxElementsPerDocument - 10))),
            ("no attributes, just under the element cap", doc(String(repeating: "<i>x</i>", count: Safety.maxElementsPerDocument - 10))),
        ]
        // Review R3-01: one run of each is not a bound (a loaded rerun was up to 2.7x slower), so each is timed three
        // times and every run is recorded; SanitizerAtCapsTimingTests times the same documents on a simulator or phone.
        let atCapsRuns = 3
        for (name, input) in atCaps {
            for run in 1 ... atCapsRuns {
                let r = await Safety.sanitize(html: input, budget: .seconds(120))
                #expect(r.withheld == nil, "\(name): \(r.detail ?? "")")
                #expect(r.seconds < Safety.defaultTimeBudget.seconds, "\(name): \(r.seconds) s")
                let size = String(format: "%.2f MiB", Double(input.utf8.count) / Double(mib))
                rows.append("\(name) (run \(run) of \(atCapsRuns))\t\(size)\t\(String(format: "%.3f", r.seconds)) s\t\(r.withheld?.rawValue ?? "served") (\(r.elementCount) elements, \(r.attributeCount) attributes)")
            }
        }
        // Other jobs on the same Mac (and the other host tests, which Swift Testing runs in parallel with this one)
        // change these figures; the load averages make that visible.
        let header = "# load average (1, 5, 15 min) at start: \(loadBefore); at end: \(Self.loadAverage()); \(ProcessInfo.processInfo.activeProcessorCount) processors\n"
        let table = header + "# pattern\tinput\tseconds (host, debug build)\tresult\n" + rows.joined(separator: "\n") + "\n"
        HostEvidence.write("sanitizer-timing.tsv", table)
        print("sanitizer timing (host):\n" + table)
    }

    static func loadAverage() -> String {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, 3) == 3 else { return "unavailable" }
        return values.map { String(format: "%.2f", $0) }.joined(separator: ", ")
    }

    func attributeList(_ n: Int) -> String { (0 ..< n).map { "a\($0)=\"v\"" }.joined(separator: " ") }

    /// Review R2-02: a worker that runs over budget cannot be stopped, so one publication's workers are limited, a
    /// slot stays taken until the worker really finishes, and waiting for a slot counts against the budget.
    @Test("Sanitizer workers are limited per publication; a wait for a worker counts against the budget")
    func workerLimit() async throws {
        let limiter = Safety.WorkerLimiter(limit: 1)
        let overBudget = Safety.OverBudgetDocuments()
        // About 1.5 s of work on the host against a 10 ms budget: the worker keeps running after the result returns.
        let slow = doc("<p>" + String(repeating: "&lt;script ", count: (8 << 20) / 11) + "</p>")
        let first = await Safety.sanitize(html: slow, key: "OEBPS/slow.xhtml", overBudget: overBudget, limiter: limiter, budget: .milliseconds(10))
        #expect(first.withheld == .timeBudget)
        #expect(limiter.running == 1, "the over-budget worker still holds its slot")
        let waited = await Safety.sanitize(html: doc("<p>Fine.</p>"), key: "OEBPS/fine.xhtml", overBudget: overBudget, limiter: limiter,
                                           budget: .milliseconds(100))
        #expect(waited.withheld == .timeBudget)
        #expect(waited.detail?.contains("no sanitizer worker free") == true, "\(waited.detail ?? "")")
        #expect(!overBudget.contains("OEBPS/fine.xhtml"), "a document that only waited is tried again on the next read")
        #expect(overBudget.contains("OEBPS/slow.xhtml"))
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(60)
        while limiter.running > 0, clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(limiter.running == 0, "the background worker never finished")
        let fine = await Safety.sanitize(html: doc("<p>Fine.</p>"), key: "OEBPS/fine.xhtml", overBudget: overBudget, limiter: limiter)
        expectServedSafely(fine)

        // Many concurrent reads of one publication never run more workers than the limit.
        let two = Safety.WorkerLimiter(limit: 2)
        let medium = doc("<p>" + String(repeating: "Plain words in a paragraph. ", count: 20_000) + "</p>")
        let results = await withTaskGroup(of: Safety.Result.self) { group in
            for _ in 0 ..< 8 { group.addTask { await Safety.sanitize(html: medium, limiter: two, budget: .seconds(120)) } }
            var all: [Safety.Result] = []
            for await r in group { all.append(r) }
            return all
        }
        #expect(results.count == 8 && results.allSatisfy { $0.withheld == nil })
        #expect(two.peakRunning == 2, "peak \(two.peakRunning)")
        #expect(two.running == 0)
    }

    @Test("A document over the time budget is withheld, never served")
    func budget() async {
        // About 1.5 s of work on the host against a 10 ms budget.
        let slow = doc("<p>" + String(repeating: "&lt;script ", count: (8 << 20) / 11) + "</p>")
        let r = await Safety.sanitize(html: slow, budget: .milliseconds(10))
        #expect(r.withheld == .timeBudget)
        #expect(r.html == Safety.unavailablePlaceholder(.timeBudget))
        #expect(r.cspInjected)

        // Later reads of a document that ran over budget get the placeholder without starting another worker.
        let overBudget = Safety.OverBudgetDocuments()
        let first = await Safety.sanitize(html: slow, key: "OEBPS/slow.xhtml", overBudget: overBudget, budget: .milliseconds(10))
        #expect(first.withheld == .timeBudget)
        #expect(overBudget.contains("OEBPS/slow.xhtml") && overBudget.count == 1)
        let clock = ContinuousClock()
        let start = clock.now
        let again = await Safety.sanitize(html: slow, key: "OEBPS/slow.xhtml", overBudget: overBudget, budget: .seconds(120))
        #expect(clock.now - start < .milliseconds(200), "the second read must not sanitize again")
        #expect(again.withheld == .timeBudget && again.html == Safety.unavailablePlaceholder(.timeBudget))
        #expect(again.detail?.contains("earlier read") == true)
        let other = await Safety.sanitize(html: doc("<p>Fine.</p>"), key: "OEBPS/other.xhtml", overBudget: overBudget)
        expectServedSafely(other)
        #expect(overBudget.count == 1)
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg"><text>t</text></svg>"#
        #expect(await Safety.sanitize(nonHTMLDocument: svg, key: "OEBPS/slow.xhtml", overBudget: overBudget).withheld == .timeBudget)
        #expect(await Safety.sanitize(nonHTMLDocument: svg, key: "OEBPS/map.svg", overBudget: overBudget).withheld == nil)
    }

    // MARK: Documents that are not HTML

    @Test("Non-HTML documents: active content is withheld, everything else is served canonically")
    func nonHTML() async {
        let plain = """
        <?xml version="1.0"?><?xml-stylesheet type="text/xsl" href="evil.xsl"?><svg xmlns="http://www.w3.org/2000/svg"><!-- c --><title>A map</title><text x="1" y="2">Upon the river, one = two &amp; three</text></svg>
        """
        let kept = await Safety.sanitize(nonHTMLDocument: plain)
        #expect(!kept.replaced, "\(kept.detail ?? "")")
        #expect(kept.document.contains(#"<text x="1" y="2">Upon the river, one = two &amp; three</text>"#), "\(kept.document)")
        #expect(!kept.document.contains("xml-stylesheet") && !kept.document.contains("<!--"))
        let active = [
            #"<svg xmlns="http://www.w3.org/2000/svg"><script>x()</script></svg>"#,
            #"<svg:svg xmlns:svg="http://www.w3.org/2000/svg"><svg:script>x()</svg:script></svg:svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg" onload="x()"/>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><a href="JavaScript:x()"><text>t</text></a></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><a href="javascript&#58;x()"><text>t</text></a></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><a xlink:href="&#106;avascript:x()" xmlns:xlink="http://www.w3.org/1999/xlink"><text>t</text></a></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><p xmlns="http://www.w3.org/1999/xhtml">t</p></foreignObject></svg>"#,
            #"<html xmlns="http://www.w3.org/1999/xhtml"><body><h:script xmlns:h="http://www.w3.org/1999/xhtml">x()</h:script></body></html>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><set attributeName="href" to="javascript :x()"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><!-- <script>x()</script> --><SCRIPT>x()</SCRIPT></svg>"#,
            // Review R2-01: a script-free XHTML document declared application/xml whose form navigates the web view to
            // another archive entry. Without a page CSP nothing stops the submission, so any XHTML element, and any
            // form control or form target by local name, makes the document active.
            #"<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body><form action="evil.html"><button id="go" type="submit">Continue</button></form></body></html>"#,
            #"<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body><p>Only text.</p></body></html>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><h:meta xmlns:h="http://www.w3.org/1999/xhtml" http-equiv="refresh" content="0;url=evil.html"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><x:form xmlns:x="urn:other" action="evil.html"/><text>t</text></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><g formaction="evil.html"><text>t</text></g></svg>"#,
            #"<doc xmlns="urn:other"><button>go</button></doc>"#,
        ]
        for document in active {
            let r = await Safety.sanitize(nonHTMLDocument: document)
            #expect(r.withheld == .activeContent, "\(document): \(r.detail ?? "")")
            #expect(r.document == Safety.activeContentPlaceholder)
        }
        let broken = await Safety.sanitize(nonHTMLDocument: "<svg xmlns=\"http://www.w3.org/2000/svg\"><text>unclosed</svg>")
        #expect(broken.withheld == .unsupportedMarkup)
    }

    // MARK: The generated bypass fixtures (the same archives the simulator tests open in WebKit)

    @Test("g01-csp-bypass.epub and g01-nesting-bypass.epub: every chapter is served safely or withheld")
    func bypassFixtures() async throws {
        let csp = Dictionary(uniqueKeysWithValues: try Unzip.entries(of: FixturePaths.generated("g01-csp-bypass.epub")))
        for name in ["OEBPS/c1.xhtml", "OEBPS/c2.xhtml", "OEBPS/c3.html"] {
            let r = await Safety.sanitize(html: String(decoding: try #require(csp[name]), as: UTF8.self))
            expectServedSafely(r, "\(name)")
            #expect(r.html.contains("<p id=\"target\">"), "\(name): \(r.html)")
            for needle in ["onload", "onerror", "__sylviaBypass", "<!--"] { #expect(!r.html.contains(needle), "\(name): \(needle)") }
        }
        let nest = Dictionary(uniqueKeysWithValues: try Unzip.entries(of: FixturePaths.generated("g01-nesting-bypass.epub")))
        let wrapped = await Safety.sanitize(html: String(decoding: try #require(nest["OEBPS/c2.xhtml"]), as: UTF8.self))
        expectServedSafely(wrapped)
        #expect(wrapped.html.contains("Before the comment.") && wrapped.html.contains("After the comment."))
        #expect(!wrapped.html.contains("<span") && !wrapped.html.contains("Innermost"))
        #expect(wrapped.elementDepth <= 4)
        let unmatched = await Safety.sanitize(html: String(decoding: try #require(nest["OEBPS/c3.xhtml"]), as: UTF8.self))
        #expect(unmatched.withheld == .unsupportedMarkup, "\(unmatched.detail ?? "")")
        let deep = Dictionary(uniqueKeysWithValues: try Unzip.entries(of: FixturePaths.generated("g01-deep-nesting.epub")))
        let d = await Safety.sanitize(html: String(decoding: try #require(deep["OEBPS/c2.xhtml"]), as: UTF8.self))
        #expect(d.withheld == .excessiveNesting)
        let limit = Dictionary(uniqueKeysWithValues: try Unzip.entries(of: FixturePaths.generated("g01-nesting-limit.epub")))
        let l = await Safety.sanitize(html: String(decoding: try #require(limit["OEBPS/c2.xhtml"]), as: UTF8.self))
        expectServedSafely(l)
        #expect(l.elementDepth == Safety.maxElementDepth)
        let hostile = Dictionary(uniqueKeysWithValues: try Unzip.entries(of: FixturePaths.generated("g01-hostile.epub")))
        for name in ["OEBPS/c1.xhtml", "OEBPS/c2.xhtml"] {
            let r = await Safety.sanitize(html: String(decoding: try #require(hostile[name]), as: UTF8.self))
            expectServedSafely(r, "\(name)")
            #expect(!r.html.contains("<iframe") && !r.html.contains("<object") && !r.html.contains("<base") && !r.html.contains("http-equiv=\"refresh\""), "\(name)")
        }
    }

    // MARK: Fidelity on the real books

    /// Every XHTML document in the five real fixture books is served (none withheld), with the CSP in place, the same
    /// elements in the same order and exactly the same text. Both sides are read with SwiftSoup's XML parser, not with
    /// the `XMLParser` the sanitizer uses, so a character that parser loses shows up here (the simulator test
    /// `SanitizerFidelityTests` makes the same comparison in WebKit).
    @Test("Real books: every document is served with identical text and elements")
    func realBooks() async throws {
        let books = try FileManager.default.contentsOfDirectory(at: FixturePaths.repoEPUB, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "epub" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(books.count == 5)
        var documents = 0, maxDepth = 0, maxElements = 0, maxAttributes = 0, maxSeconds = 0.0
        for book in books {
            for (name, data) in try Unzip.entries(of: book) where name.hasSuffix(".xhtml") || name.hasSuffix(".html") {
                let original = String(decoding: data, as: UTF8.self)
                let r = await Safety.sanitize(html: original)
                expectServedSafely(r, "\(book.lastPathComponent) \(name)")
                let before = SoupContent.of(original)
                let after = SoupContent.of(r.html)
                if before.text != after.text {
                    let common = zip(before.text, after.text).prefix { $0 == $1 }.count
                    Issue.record("\(book.lastPathComponent) \(name): text changed at character \(common): \(String(before.text.dropFirst(max(0, common - 20)).prefix(60)).debugDescription) vs \(String(after.text.dropFirst(max(0, common - 20)).prefix(60)).debugDescription)")
                }
                // The canonical form adds a head only when missing; otherwise the element sequence is identical.
                #expect(before.elements == after.elements.filter { $0 != "meta#csp" }, "\(book.lastPathComponent) \(name): elements changed")
                documents += 1
                maxDepth = max(maxDepth, r.elementDepth)
                maxElements = max(maxElements, r.elementCount)
                maxAttributes = max(maxAttributes, r.attributeCount)
                maxSeconds = max(maxSeconds, r.seconds)
            }
        }
        #expect(documents > 150)
        let line = "real books (Fixtures/epub, 5 archives): \(documents) XHTML documents served, 0 withheld, text and element sequence identical to the original's (both read with SwiftSoup's XML parser, not the sanitizer's XMLParser); max depth \(maxDepth), max elements \(maxElements), max attributes \(maxAttributes), slowest \(String(format: "%.3f", maxSeconds)) s (host, debug build)\n"
        HostEvidence.write("sanitizer-real-books.txt", line)
        print(line)
        #expect(maxDepth < 64)
        #expect(maxAttributes < Safety.maxAttributesPerDocument / 4, "\(maxAttributes)")
    }
}

/// Writes host-test evidence into `SYLVIA_EVIDENCE_DIR` when the CI drop-in sets it.
enum HostEvidence {
    static func write(_ name: String, _ text: String) {
        guard let dir = ProcessInfo.processInfo.environment["SYLVIA_EVIDENCE_DIR"], !dir.isEmpty else { return }
        try? text.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}

/// Text and element sequence of a document as SwiftSoup's XML parser reads it (independent of Foundation's
/// `XMLParser`), for fidelity checks. Elements are compared by lower-cased local name, because the sanitizer writes
/// every element unprefixed; the sanitizer's CSP `<meta>` is marked `meta#csp`.
enum SoupContent {
    struct Content: Equatable { var text: String; var elements: [String] }

    static func of(_ markup: String) -> Content {
        guard let document = try? SwiftSoup.parseXML(markup) else { return Content(text: "<unparsable>", elements: []) }
        var text = "", elements: [String] = []
        // The root element only: whitespace around it (after the XML declaration) is not part of the document's text.
        var stack: [SwiftSoup.Node] = document.getChildNodes().filter { $0 is SwiftSoup.Element }.reversed()
        while let node = stack.popLast() {
            if let t = node as? SwiftSoup.TextNode {
                text += t.getWholeText()
            } else if let e = node as? SwiftSoup.Element {
                let local = e.tagName().split(separator: ":").last.map { String($0).lowercased() } ?? ""
                let csp = local == "meta" && (try? e.attr("content")) == PublicationHTMLSafety.contentSecurityPolicy
                elements.append(csp ? "meta#csp" : local)
            }
            stack.append(contentsOf: node.getChildNodes().reversed())
        }
        return Content(text: text, elements: elements)
    }
}

/// Reads the entries of a ZIP archive with the system `zipinfo` and `unzip` (host tests only).
enum Unzip {
    static func entries(of archive: URL) throws -> [(String, Data)] {
        let names = String(decoding: try run("/usr/bin/zipinfo", ["-1", archive.path]), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        return try names.map { ($0, try run("/usr/bin/unzip", ["-p", archive.path, $0])) }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }
}
