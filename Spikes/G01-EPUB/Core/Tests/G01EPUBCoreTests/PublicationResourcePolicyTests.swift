import Foundation
@testable import G01EPUBCore
import Testing

/// Which declared resources are served and how, and the engine-level rule list (review R2-01; ADR-0004 section 4).
/// Host (macOS). The simulator test `SafetyTests.testNonLinkNavigationsReachOnlySanitizedDeclaredDocuments` checks the
/// same policy in WebKit through Readium.
@Suite("Publication resource policy: treatment by media type, document loads limited to the reading order")
struct PublicationResourcePolicyTests {
    typealias Policy = PublicationResourcePolicy

    @Test("Every media type a web view can render as a document is sanitized; only known passive types pass unchanged")
    func treatments() {
        let expected: [(String?, Policy.Treatment)] = [
            ("application/xhtml+xml", .htmlDocument), ("text/html", .htmlDocument), ("TEXT/HTML; charset=utf-8", .htmlDocument),
            ("image/svg+xml", .otherDocument), ("application/xml", .otherDocument), ("text/xml", .otherDocument),
            ("application/x-dtbncx+xml", .otherDocument), ("application/smil+xml", .otherDocument),
            ("application/oebps-package+xml", .otherDocument), ("text/xsl", .otherDocument), ("application/xslt+xml", .otherDocument),
            ("image/png", .passive), ("image/jpeg", .passive), ("image/gif", .passive), ("image/webp", .passive),
            ("text/css", .passive), ("font/otf", .passive), ("font/woff2", .passive), ("application/vnd.ms-opentype", .passive),
            ("application/font-woff", .passive), ("application/x-font-ttf", .passive), ("audio/mpeg", .passive), ("video/mp4", .passive),
            ("text/javascript", .withheld), ("application/javascript", .withheld), ("text/plain", .withheld),
            ("application/json", .withheld), ("application/octet-stream", .withheld), ("application/pdf", .withheld),
            ("application/x-webarchive", .withheld), ("multipart/related", .withheld), ("message/rfc822", .withheld),
            ("text/x-html", .withheld), ("application/x-xml-ish", .withheld), ("", .withheld), ("image", .withheld), (nil, .withheld),
        ]
        for (type, treatment) in expected {
            #expect(Policy.treatment(forMediaType: type) == treatment, "\(type ?? "nil")")
        }
    }

    @Test("Reading-order hrefs become exact document patterns; anything not written literally turns the restriction off")
    func documentPatterns() throws {
        #expect(Policy.documentPattern(forHref: "OEBPS/c1.xhtml") == #"^readium://[0-9a-fA-F-]+/OEBPS/c1\.xhtml([?#].*)?$"#)
        #expect(Policy.documentPattern(forHref: "OEBPS/@public@vhost@g@gutenberg@html@files@205@205-h@205-h-0.htm.html")
            == #"^readium://[0-9a-fA-F-]+/OEBPS/@public@vhost@g@gutenberg@html@files@205@205-h@205-h-0\.htm\.html([?#].*)?$"#)
        #expect(Policy.documentPattern(forHref: "text/a%20b.xhtml") == #"^readium://[0-9a-fA-F-]+/text/a%20b\.xhtml([?#].*)?$"#)
        for unusable in ["text/(1).xhtml", "text/a+b.xhtml", "text/é.xhtml", "text/a b.xhtml", "text/a$.xhtml", "/abs.xhtml", "", "a[1].xhtml"] {
            #expect(Policy.documentPattern(forHref: unusable) == nil, "\(unusable)")
        }

        let list = Policy.contentRuleListJSON(readingOrderHrefs: ["OEBPS/c1.xhtml", "OEBPS/c2.xml", "OEBPS/c1.xhtml"])
        #expect(list.documentsLimitedToReadingOrder && list.unrepresentableHrefs.isEmpty)
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(list.json.utf8)) as? [[String: [String: Any]]])
        let summary = rules.map { r in
            "\(r["action"]?["type"] as? String ?? "?") \(r["trigger"]?["url-filter"] as? String ?? "?") \((r["trigger"]?["resource-type"] as? [String])?.joined() ?? "all")"
        }
        #expect(summary == [
            "block .* all", "ignore-previous-rules ^readium: all", "ignore-previous-rules ^data: all", "ignore-previous-rules ^about: all",
            "block .* document", "ignore-previous-rules ^about:blank document",
            #"ignore-previous-rules ^readium://[0-9a-fA-F-]+/OEBPS/c1\.xhtml([?#].*)?$ document"#,
            #"ignore-previous-rules ^readium://[0-9a-fA-F-]+/OEBPS/c2\.xml([?#].*)?$ document"#,
        ], "\(summary)")
        // The first four rules are the static list's.
        let base = try #require(try JSONSerialization.jsonObject(with: Data(PublicationHTMLSafety.contentRuleListJSON.utf8)) as? [Any])
        #expect(base.count == 4)

        let fallback = Policy.contentRuleListJSON(readingOrderHrefs: ["OEBPS/c1.xhtml", "OEBPS/chapter (2).xhtml"])
        #expect(!fallback.documentsLimitedToReadingOrder)
        #expect(fallback.unrepresentableHrefs == ["OEBPS/chapter (2).xhtml"])
        let fallbackRules = try #require(try JSONSerialization.jsonObject(with: Data(fallback.json.utf8)) as? [Any])
        #expect(fallbackRules.count == 4, "network rules only")
    }

    @Test("The hrefs of the real fixture books all become exact patterns")
    func realBookHrefs() throws {
        let books = try FileManager.default.contentsOfDirectory(at: FixturePaths.repoEPUB, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "epub" }
        #expect(books.count == 5)
        var checked = 0
        for book in books {
            for (name, _) in try Unzip.entries(of: book) where name.hasSuffix(".xhtml") || name.hasSuffix(".html") {
                #expect(Policy.documentPattern(forHref: name) != nil, "\(book.lastPathComponent): \(name)")
                checked += 1
            }
        }
        #expect(checked > 150)
    }
}
