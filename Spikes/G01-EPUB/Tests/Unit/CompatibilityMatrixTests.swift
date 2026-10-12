@testable import EPUBHarness
import Foundation
import G01EPUBCore
@preconcurrency import ReadiumShared
import XCTest

/// Deliverable 1: compatibility matrix over every EPUB in Fixtures/epub (simulator).
@MainActor final class CompatibilityMatrixTests: XCTestCase {
    static let fixtures = ["se-meditations.epub", "se-walden.epub", "se-middlemarch.epub", "pg-walden-epub2.epub", "pg-walden-epub3.epub"]

    override func tearDown() async throws { TestHost.tearDown() }

    func testCompatibilityMatrix() async throws {
        var rows: [[String: Any]] = []
        for name in Self.fixtures {
            let url = try TestHost.fixtureURL(name)
            let preflight = ZIPPreflight.inspect(fileAt: url)
            let entryNames = Set(preflight.entries.map(\.name))
            guard case let .success(opened) = await EPUBOpener.open(fileURL: url) else {
                XCTFail("\(name) did not open")
                continue
            }
            let pub = opened.publication
            let toc = try await pub.tableOfContents().get()
            func flatten(_ links: [ReadiumShared.Link]) -> Int { links.reduce(0) { $0 + 1 + flatten($1.children) } }
            let positions = try await pub.positions().get()

            // OPF version, read through Readium's unfiltered container (the adapter's container does not serve the OPF,
            // which the manifest does not declare), and footnote/endnote structure, read through the adapter.
            var opfVersion = "?"
            if case let .success(unfiltered) = await EPUBOpener.open(fileURL: url, options: .readiumDefaults),
               let opf = preflight.entries.first(where: { $0.name.hasSuffix(".opf") }), let href = AnyURL(string: opf.name),
               let data = try? await unfiltered.publication.get(href)?.read().get() {
                opfVersion = Self.firstMatch(#"<package[^>]*\bversion\s*=\s*['"]([^'"]+)['"]"#, String(decoding: data, as: UTF8.self)) ?? "?"
            }
            var noterefs = 0, endnoteSections = 0, footnoteAsides = 0, backlinks = 0
            for link in pub.readingOrder + pub.resources where link.mediaType?.isHTML == true {
                guard let html = try? await pub.get(link)?.read().get() else { continue }
                let s = String(decoding: html, as: UTF8.self)
                noterefs += Self.count(#"epub:type="[^"]*\bnoteref\b"#, s)
                endnoteSections += Self.count(#"epub:type="[^"]*\bendnotes\b"#, s)
                footnoteAsides += Self.count(#"<aside[^>]*epub:type="[^"]*\bfootnote\b"#, s)
                backlinks += Self.count(#"epub:type="[^"]*\bbacklink\b"#, s)
            }

            // Navigator open time: from creating the session to the first reported location (indicative only).
            let clock = ContinuousClock()
            let start = clock.now
            let session = try await ReadiumReaderSession.make(opened: opened, initialLocator: nil)
            _ = TestHost.show(session.navigator)
            let located = await session.waitUntilLocated()
            let renderSeconds = (clock.now - start).seconds
            XCTAssertTrue(located, "\(name) never reported a location")

            let row: [String: Any] = [
                "fixture": name,
                "opened": true,
                "opf_version": opfVersion,
                "title": pub.metadata.title ?? "",
                "layout": "\(pub.metadata.layout.map { "\($0)" } ?? "reflowable (default)")",
                "reading_order": pub.readingOrder.count,
                "toc_entries": flatten(toc),
                "positions": positions.count,
                "noterefs": noterefs,
                "endnotes_sections": endnoteSections,
                "footnote_asides": footnoteAsides,
                "backlinks": backlinks,
                "encryption_xml": entryNames.contains("META-INF/encryption.xml"),
                "zip_entries": preflight.entries.count,
                "expanded_bytes": preflight.totalUncompressedBytes,
                "parse_seconds": (opened.openSeconds * 1000).rounded() / 1000,
                "first_location_seconds": (renderSeconds * 1000).rounded() / 1000,
                "sanitized_documents": opened.sanitizer.documents,
                "max_element_depth": opened.sanitizer.maxElementDepth,
                "largest_markup_bytes": preflight.entries.filter(\.isMarkup).map(\.uncompressedSize).max() ?? 0,
                "unavailable_resources": opened.sanitizer.unavailableHrefs.sorted(),
                "withheld_resources": opened.sanitizer.withheldReasons.mapValues(\.rawValue),
                "documents_without_csp": opened.sanitizer.documentsWithoutCSP,
                "max_elements_per_document": opened.sanitizer.maxElements,
                "slowest_sanitize_seconds": (opened.sanitizer.slowestSeconds * 1000).rounded() / 1000,
                "document_loads_limited_to_reading_order": session.ruleList?.documentsLimitedToReadingOrder ?? false,
                "undeclared_requests": opened.sanitizer.undeclaredRequests.sorted(),
                "treatments": Dictionary(grouping: opened.sanitizer.treatments.values, by: \.rawValue).mapValues(\.count),
            ]
            rows.append(row)
            XCTAssertGreaterThan(pub.readingOrder.count, 0, name)
            XCTAssertGreaterThan(flatten(toc), 0, name)
            XCTAssertGreaterThan(positions.count, 0, name)
            XCTAssertTrue(opened.sanitizer.withheldReasons.isEmpty, "\(name): a real book's resource was withheld: \(opened.sanitizer.withheldDetails)")
            XCTAssertEqual(opened.sanitizer.documentsWithoutCSP, 0, "\(name): a served document has no CSP first in head")
            XCTAssertLessThan(opened.sanitizer.maxElementDepth, 64, "\(name): unexpectedly deep markup")
            // The per-publication rule list restricts document loads to the reading order for every real fixture.
            XCTAssertNotEqual(opfVersion, "?", name)
            XCTAssertEqual(session.ruleList?.documentsLimitedToReadingOrder, true, "\(name): \(session.ruleList?.unrepresentableHrefs ?? [])")
            TestHost.tearDown()
        }
        XCTAssertEqual(rows.count, Self.fixtures.count)
        ReaderProbe.writeEvidence("compatibility-matrix.json", json: [
            "environment": Self.environment,
            "rows": rows,
        ])
        var md = "| Fixture | OPF | Reading order | TOC entries | Positions | Noterefs | Endnote sections | Backlinks | encryption.xml | Max depth | Parse s | First location s |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        for r in rows {
            md += "| \(r["fixture"]!) | \(r["opf_version"]!) | \(r["reading_order"]!) | \(r["toc_entries"]!) | \(r["positions"]!) | \(r["noterefs"]!) | \(r["endnotes_sections"]!) | \(r["backlinks"]!) | \(r["encryption_xml"]!) | \(r["max_element_depth"]!) | \(r["parse_seconds"]!) | \(r["first_location_seconds"]!) |\n"
        }
        ReaderProbe.writeEvidence("compatibility-matrix.md", text: "Environment: \(Self.environment)\n\n" + md)
        print(md)
    }

    static var environment: String {
        let d = UIDevice.current
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? d.model
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? d.name
        #if targetEnvironment(simulator)
            return "simulator: \(name) (\(model)), \(d.systemName) \(d.systemVersion)"
        #else
            return "device: \(model), \(d.systemName) \(d.systemVersion)"
        #endif
    }

    static func count(_ pattern: String, _ s: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) ?? 0
    }

    static func firstMatch(_ pattern: String, _ s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 1 else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }

}
