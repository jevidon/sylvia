@testable import EPUBHarness
import CryptoKit
import Foundation
import G01EPUBCore
@preconcurrency import ReadiumShared
import XCTest

/// Deliverable 8: EPUB safety (plan 8.3, 18.1; tests T12, T13). Simulator.
///
/// Every hostile fixture is opened twice: once with Readium 3.11.0 on its own (`.readiumDefaults`: no preflight, no
/// sanitizer, no content rule list, no encryption check) to record what Readium does by itself, and once through
/// Sylvia's adapter configuration (`.sylvia`). The assertions on the Readium-only runs pin down the behavior the
/// adapter controls exist for, so a Readium upgrade that changes it shows up here.
@MainActor final class SafetyTests: XCTestCase {
    static var report: [String: Any] = [:]

    override func tearDown() async throws { TestHost.tearDown() }

    override class func tearDown() {
        MainActor.assumeIsolated {
            var r = report
            r["environment"] = CompatibilityMatrixTests.environment
            ReaderProbe.writeEvidence("safety.json", json: r)
        }
        super.tearDown()
    }

    // MARK: Helpers

    static let placeholder = "127.0.0.1:00000"

    /// Copies g01-hostile.epub to a temporary file with the placeholder replaced by the recorder's address.
    func hostileFixture(port: UInt16) throws -> URL {
        let data = try Data(contentsOf: try TestHost.fixtureURL("g01-hostile.epub"))
        let address = "127.0.0.1:" + String(format: "%05d", Int(port))
        let (patched, entries) = try StoredEntryPatcher.replace(Self.placeholder, with: address, in: data)
        XCTAssertEqual(Set(entries), ["OEBPS/c1.xhtml", "OEBPS/c2.xhtml", "OEBPS/evil.js", "OEBPS/style.css"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("g01-hostile-\(port).epub")
        try patched.write(to: url, options: .atomic)
        return url
    }

    static let markerScript = """
    (function () {
      function txt(id) { const e = document.getElementById(id); return e ? e.textContent : null; }
      return JSON.stringify({
        href: location.href,
        inline_script_ran: window.__sylviaInline === true,
        external_script_ran: window.__sylviaExternal === true,
        remote_script_ran: window.__sylviaRemoteJS === true,
        svg_script_ran: window.__sylviaSvg === true,
        onload_handler_ran: window.__sylviaOnload === true,
        onerror_handler_ran: window.__sylviaOnerror === true,
        javascript_url_ran: window.__sylviaJsUrl === true,
        pwned_attribute: document.documentElement.getAttribute('data-sylvia-pwned'),
        pwned_external_attribute: document.documentElement.getAttribute('data-sylvia-pwned-external'),
        script_elements: document.querySelectorAll('script').length,
        csp_meta: !!document.querySelector('meta[http-equiv="Content-Security-Policy"]'),
        target_text: txt('target'),
        refresh_target_text: txt('refresh-target'),
        readium_injected: typeof window.readium !== 'undefined'
      });
    })()
    """

    func markers(_ s: ReadiumReaderSession) async -> [String: Any] {
        (try? await ReaderProbe.json(s, Self.markerScript)) ?? ["error": "evaluation failed"]
    }

    /// Relative paths and sizes of every file under `root`.
    static func tree(_ root: URL) -> [String: Int] {
        var out: [String: Int] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return out }
        let base = root.resolvingSymlinksInPath().path
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true || v.isSymbolicLink == true else { continue }
            let path = url.resolvingSymlinksInPath().path
            out[path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path] = v.fileSize ?? 0
        }
        return out
    }

    /// Absolute paths the traversal fixture's entries would reach if anything extracted them naively.
    static var escapeTargets: [String] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let tmp = FileManager.default.temporaryDirectory
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fixtureDir = Bundle.main.resourceURL!.appendingPathComponent("generated")
        var paths = ["/tmp/g01-escape-marker.txt", "/tmp/g01-absolute-marker.txt", "/private/tmp/g01-escape-marker.txt",
                     "/private/tmp/g01-absolute-marker.txt"]
        for dir in [home, tmp, docs, fixtureDir, home.deletingLastPathComponent()] {
            paths.append(dir.deletingLastPathComponent().appendingPathComponent("g01-escape-marker.txt").path)
            paths.append(dir.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("g01-escape-marker-2.txt").path)
            paths.append(dir.appendingPathComponent("g01-escape-marker.txt").path)
        }
        return Array(Set(paths)).sorted()
    }

    struct Timed<T> { var value: T; var seconds: Double; var footprintDeltaMB: Double; var footprintAfterMB: Double }

    func timed<T>(_ body: () async throws -> T) async rethrows -> Timed<T> {
        let before = physFootprint()
        let clock = ContinuousClock()
        let start = clock.now
        let value = try await body()
        let seconds = (clock.now - start).seconds
        let after = physFootprint()
        return Timed(value: value, seconds: (seconds * 1000).rounded() / 1000,
                     footprintDeltaMB: (Double(Int64(after) - Int64(before)) / 1_048_576 * 10).rounded() / 10,
                     footprintAfterMB: (Double(after) / 1_048_576 * 10).rounded() / 10)
    }

    func describe(_ r: Result<OpenedEPUB, ReaderOpenError>) -> String {
        switch r {
        case let .success(o): "opened (\(o.publication.readingOrder.count) reading-order items)"
        case let .failure(e): "error: \(e) [import state \(e.importState)]"
        }
    }

    /// Reads every resource of an opened publication through Readium, streaming, and reports bytes and outcomes.
    func readAll(_ pub: Publication) async -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for link in pub.readingOrder + pub.resources {
            guard let resource = pub.get(link) else { rows.append(["href": link.href, "result": "no resource"]); continue }
            let length = (try? await resource.estimatedLength().get()).flatMap { $0 }
            let counter = ByteCounter()
            let base = physFootprint()
            let t = await timed { await resource.stream(range: nil, consume: { @Sendable data in counter.add(data.count) }) }
            var row: [String: Any] = ["href": link.href, "estimated_length": length.map { Int($0) } ?? -1, "bytes_read": counter.value,
                                      "largest_single_buffer_bytes": counter.largestChunk, "chunks": counter.chunks,
                                      "peak_footprint_growth_mb": (Double(Int64(counter.peakFootprint) - Int64(base)) / 1_048_576 * 10).rounded() / 10,
                                      "seconds": t.seconds]
            switch t.value {
            case .success: row["result"] = "read"
            case let .failure(e): row["result"] = "error: \(e)"
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: T13: publication scripts and remote resources

    func testHostilePublicationRunsNoScriptAndMakesNoRequest() async throws {
        let recorder = LoopbackRecorder()
        try recorder.start()
        defer { recorder.stop() }

        // Positive control: the recorder is reachable from this process, so zero requests later means none were made.
        var control = URLRequest(url: URL(string: "http://127.0.0.1:\(recorder.port)/control")!)
        control.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: control)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let reachable = await ReaderProbe.wait(timeout: .seconds(3)) { recorder.requests.contains { $0.contains("/control") } }
        XCTAssertTrue(reachable, "loopback recorder did not see the control request")

        let file = try hostileFixture(port: recorder.port)
        struct Config { let name: String; let options: EPUBOpenOptions; let safety: ReadiumReaderSession.Safety }
        var sanitizerOnly = EPUBOpenOptions.readiumDefaults
        sanitizerOnly.sanitizeHTML = true
        let configs = [
            Config(name: "readium-defaults", options: .readiumDefaults, safety: .readiumDefaults),
            Config(name: "sanitizer-and-csp-only", options: sanitizerOnly, safety: .readiumDefaults),
            Config(name: "content-rule-list-only", options: .readiumDefaults, safety: .sylvia),
            Config(name: "sylvia", options: .sylvia, safety: .sylvia),
        ]
        var results: [String: Any] = ["loopback_port": Int(recorder.port), "control_request_seen": reachable]
        let clock = ContinuousClock()
        for config in configs {
            recorder.reset()
            let configStart = clock.now
            let screen = try await TestHost.open("g01-hostile.epub", options: config.options, safety: config.safety, url: file)
            let openedAfter = (clock.now - configStart).seconds
            let s = screen.session
            try await Task.sleep(for: .seconds(2.5))
            let c1 = await markers(s)
            // A script-driven click on the javascript: link.
            _ = try? await ReaderProbe.evaluate(s, "(function(){ const a = document.getElementById('jslink'); if (a) a.click(); return true; })()")
            try await Task.sleep(for: .milliseconds(500))
            let afterClick = await markers(s)
            // Chapter 2: meta refresh and a remote <base>.
            let went = await s.followLink(href: "OEBPS/c2.xhtml")
            try await Task.sleep(for: .seconds(2.5))
            let c2 = await markers(s)
            let requests = recorder.requests
            results[config.name] = [
                "chapter1": c1, "chapter1_after_javascript_link_click": afterClick, "moved_to_chapter2": went, "chapter2": c2,
                "loopback_requests": requests, "loopback_request_count": requests.count,
                "seconds_to_first_location": (openedAfter * 1000).rounded() / 1000,
                "seconds_total": ((clock.now - configStart).seconds * 1000).rounded() / 1000,
                "sanitized_documents": s.opened.sanitizer.documents, "removed_script_elements": s.opened.sanitizer.removedScripts,
                "removed_meta_refreshes": s.opened.sanitizer.removedRefreshes, "external_url_requests": s.externalURLRequests.map(\.absoluteString),
                "removed_event_handlers": s.opened.sanitizer.removedEventHandlers, "removed_script_urls": s.opened.sanitizer.removedScriptURLs,
                "removed_other": s.opened.sanitizer.removedOther, "documents_without_csp": s.opened.sanitizer.documentsWithoutCSP,
            ]
            switch config.name {
            case "readium-defaults":
                // What the adapter has to stop: Readium runs publication JavaScript and lets it reach the network.
                XCTAssertEqual(c1["inline_script_ran"] as? Bool, true, "Readium 3.11.0 alone is expected to run inline publication scripts")
                XCTAssertGreaterThan(requests.count, 0, "Readium 3.11.0 alone is expected to let the publication reach the network")
            case "sylvia":
                for (name, m) in [("chapter 1", c1), ("after the javascript: click", afterClick), ("chapter 2", c2)] {
                    for key in ["inline_script_ran", "external_script_ran", "remote_script_ran", "svg_script_ran", "onload_handler_ran",
                                "onerror_handler_ran", "javascript_url_ran"] {
                        XCTAssertEqual(m[key] as? Bool, false, "\(name): \(key)")
                    }
                    XCTAssertTrue(m["pwned_attribute"] is NSNull, "\(name): publication script changed the DOM")
                    XCTAssertTrue(m["pwned_external_attribute"] is NSNull, "\(name): external script changed the DOM")
                    XCTAssertEqual(m["readium_injected"] as? Bool, true, "\(name): Readium's own scripts must still run")
                    XCTAssertEqual(m["csp_meta"] as? Bool, true, "\(name): CSP missing")
                    XCTAssertEqual(m["script_elements"] as? Int, 0, "\(name): script elements left in the DOM")
                }
                XCTAssertEqual(c1["target_text"] as? String, "This hostile fixture paragraph is ordinary text that the reader must still display.")
                XCTAssertTrue(went)
                XCTAssertTrue((c2["href"] as? String ?? "").hasPrefix("readium:"), "chapter 2 left the publication: \(c2)")
                XCTAssertNotNil(c2["refresh_target_text"] as? String, "chapter 2 text not displayed: \(c2)")
                XCTAssertEqual(requests, [], "the publication reached the network")
                XCTAssertGreaterThanOrEqual(s.opened.sanitizer.removedScripts, 4)
                XCTAssertEqual(s.opened.sanitizer.removedRefreshes, 1)
                XCTAssertGreaterThanOrEqual(s.opened.sanitizer.removedEventHandlers, 2, "body onload and img onerror")
                XCTAssertGreaterThanOrEqual(s.opened.sanitizer.removedScriptURLs, 1, "the javascript: link")
                XCTAssertEqual(s.opened.sanitizer.documentsWithoutCSP, 0)
            default:
                break
            }
            TestHost.tearDown()
        }
        Self.report["hostile_content"] = results
    }

    /// Reading-order documents that are not HTML cannot carry the sanitizer's CSP: an SVG page and an item declared
    /// `application/xml` whose root is XHTML, both with scripts (g01-nonhtml-active.epub). Readium alone is recorded;
    /// through the adapter neither script may run and both pages show the placeholder.
    func testNonHTMLReadingOrderDocumentsRunNoScript() async throws {
        let probe = """
        (function () { const root = document.documentElement; return JSON.stringify({
          href: String(location.href), svg_document_script_ran: window.__sylviaSvgDoc === true,
          svg_onload_ran: window.__sylviaSvgOnload === true, xml_document_script_ran: window.__sylviaXmlDoc === true,
          pwned_attribute: root ? root.getAttribute('data-sylvia-pwned') : null,
          unavailable: root ? root.getAttribute('data-sylvia-unavailable') : null,
          text: root ? (root.textContent || '').trim().slice(0, 80) : '' }); })()
        """
        var results: [String: Any] = [:]
        let configs: [(String, EPUBOpenOptions, ReadiumReaderSession.Safety)] = [
            ("readium-defaults", .readiumDefaults, .readiumDefaults), ("sylvia", .sylvia, .sylvia),
        ]
        for (name, options, safety) in configs {
            let screen = try await TestHost.open("g01-nonhtml-active.epub", options: options, safety: safety)
            let s = screen.session
            var rows: [String: Any] = [:]
            for href in ["OEBPS/c2.svg", "OEBPS/c3.xml"] {
                let went = await s.followLink(href: href)
                try await Task.sleep(for: .seconds(1.5))
                let m = (try? await ReaderProbe.json(s, probe)) ?? ["error": "evaluation failed"]
                rows[href] = ["navigated": went, "current_locator_href": s.currentLocator?.href ?? "", "document": m]
                guard name == "sylvia" else { continue }
                XCTAssertTrue(went, "\(href): navigation failed")
                XCTAssertTrue((m["href"] as? String ?? "").hasSuffix(href), "\(href): the probe did not run in that document: \(m)")
                for key in ["svg_document_script_ran", "svg_onload_ran", "xml_document_script_ran"] {
                    XCTAssertEqual(m[key] as? Bool, false, "\(href): \(key)")
                }
                XCTAssertTrue(m["pwned_attribute"] is NSNull, "\(href): \(m)")
                XCTAssertEqual(m["unavailable"] as? String, "active-content", "\(href): placeholder not shown: \(m)")
            }
            if name == "sylvia" {
                XCTAssertEqual(s.opened.sanitizer.activeContentHrefs, ["OEBPS/c2.svg", "OEBPS/c3.xml"])
                let statuses = Dictionary(uniqueKeysWithValues: await EPUBExtraction.extract(s.opened).map { ($0.href, $0.status) })
                XCTAssertEqual(statuses["OEBPS/c1.xhtml"], "indexed")
                XCTAssertEqual(statuses["OEBPS/c2.svg"], "unavailable_active_content")
                XCTAssertEqual(statuses["OEBPS/c3.xml"], "unavailable_active_content")
                rows["extraction_statuses"] = statuses
                rows["non_html_documents_checked"] = s.opened.sanitizer.nonHTMLDocumentsChecked
            }
            results[name] = rows
            TestHost.tearDown()
        }
        Self.report["non_html_active_content"] = results
    }

    // MARK: T13: archive structure (traversal, absolute paths, symlink, bombs, recursion) and T12 truncation

    func testHostileArchivesAreRejectedOrBoundedAndNothingIsWrittenOutside() async throws {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        for path in Self.escapeTargets {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path), "marker already exists before the test: \(path)")
        }
        let before = Self.tree(home)

        let expected: [String: String] = [
            "g01-traversal.epub": "path_traversal", "g01-symlink.epub": "symlink", "g01-bomb.epub": "markup_too_large",
            "g01-bomb-lying.epub": "inconsistent_sizes", "g01-truncated.epub": "truncated",
        ]
        var rows: [String: Any] = [:]
        for name in expected.keys.sorted() {
            let url = try TestHost.fixtureURL(name)
            // Sylvia: rejected by the preflight before Readium sees the file.
            let sylvia = await timed { await EPUBOpener.open(fileURL: url, options: .sylvia) }
            var row: [String: Any] = ["sylvia": ["result": describe(sylvia.value), "seconds": sylvia.seconds, "footprint_delta_mb": sylvia.footprintDeltaMB]]
            if case let .failure(.unsafeArchive(codes)) = sylvia.value {
                XCTAssertTrue(codes.contains(expected[name]!), "\(name): \(codes)")
            } else {
                XCTFail("\(name): expected an unsafe-archive rejection, got \(describe(sylvia.value))")
            }
            XCTAssertLessThan(sylvia.seconds, 1.0, "\(name): preflight took too long")
            XCTAssertLessThan(sylvia.footprintDeltaMB, 20, "\(name): preflight memory")

            // Readium alone: what it opens and what reading every resource costs.
            let readium = await timed { await EPUBOpener.open(fileURL: url, options: .readiumDefaults) }
            var readiumRow: [String: Any] = ["open": describe(readium.value), "seconds": readium.seconds, "footprint_delta_mb": readium.footprintDeltaMB]
            if case let .success(opened) = readium.value {
                let all = await timed { await readAll(opened.publication) }
                readiumRow["resources"] = all.value
                readiumRow["read_all_seconds"] = all.seconds
                readiumRow["read_all_footprint_after_mb"] = all.footprintAfterMB
                if name == "g01-traversal.epub" {
                    // The OPF item that climbs out of the container, and the escaping entries by name.
                    var lookups: [String: String] = [:]
                    for href in ["../../../../../../../../etc/hosts", "../g01-escape-marker.txt", "/tmp/g01-absolute-marker.txt",
                                 "tmp/g01-absolute-marker.txt", "OEBPS/../../g01-escape-marker-2.txt", "/etc/hosts"] {
                        if let u = AnyURL(string: href), let r = opened.publication.get(u) {
                            let data = try? await r.read().get()
                            lookups[href] = data.map { "served \($0.count) bytes: \(String(decoding: $0.prefix(60), as: UTF8.self))" } ?? "resource present, read failed"
                        } else {
                            lookups[href] = "not served"
                        }
                    }
                    readiumRow["lookups"] = lookups
                    for (href, result) in lookups where href.contains("etc/hosts") {
                        XCTAssertFalse(result.contains("localhost"), "Readium served a host file for \(href): \(result)")
                    }
                }
                if name == "g01-symlink.epub" {
                    let c2 = try? await opened.publication.get(AnyURL(string: "OEBPS/c2.xhtml")!)?.read().get()
                    readiumRow["symlink_entry_content"] = c2.map { String(decoding: $0, as: UTF8.self) } ?? "unreadable"
                    XCTAssertEqual(c2.map { String(decoding: $0, as: UTF8.self) }, "/etc/hosts", "Readium must read the link text, never follow it")
                }
            }
            row["readium_defaults"] = readiumRow
            rows[name] = row
        }

        // Nothing landed outside the container, and nothing inside it carries the markers.
        let after = Self.tree(home)
        let added = after.keys.filter { before[$0] == nil }.sorted()
        for path in Self.escapeTargets {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path), "a ZIP entry was written to \(path)")
        }
        XCTAssertFalse(added.contains { $0.contains("g01-escape") || $0.contains("g01-absolute") }, "\(added)")
        rows["files_added_under_app_container"] = added
        rows["escape_targets_checked"] = Self.escapeTargets
        Self.report["archives"] = rows
    }

    /// Recursion (plan 8.3). Readium 3.11.0's content iterator overflows the stack on 10,000 nested spans (the
    /// Readium-only run is in `DeepNestingUITests`, in its own process, because it crashes the app). Through the
    /// adapter, the over-deep chapter is replaced by a placeholder before any Readium component parses it: the book
    /// opens, the chapter says why it cannot be shown, extraction reports it as unavailable, and search still works.
    func testExcessiveNestingIsWithheldAndReported() async throws {
        let open = try await timed { try await TestHost.open("g01-deep-nesting.epub") }
        let s = open.value.session
        let nav = await timed { await s.followLink(href: "OEBPS/c2.xhtml") }
        XCTAssertTrue(nav.value)
        try await Task.sleep(for: .seconds(1))
        let shown = try await ReaderProbe.json(s, """
        JSON.stringify({ unavailable: document.body.getAttribute('data-sylvia-unavailable'), text: document.body.textContent.trim(),
                         depth: (function(){ let d = 0, e = document.documentElement; while (e && e.firstElementChild) { e = e.lastElementChild; d++; } return d; })() })
        """)
        XCTAssertEqual(shown["unavailable"] as? String, "excessive-nesting", "\(shown)")
        XCTAssertEqual(shown["text"] as? String, "This section cannot be shown: its markup nests more than 256 levels deep.", "\(shown)")
        XCTAssertEqual(s.opened.sanitizer.unavailableHrefs, ["OEBPS/c2.xhtml"])
        XCTAssertEqual(s.opened.sanitizer.withheldReasons["OEBPS/c2.xhtml"], .excessiveNesting)

        let extraction = await timed { await EPUBExtraction.extract(s.opened) }
        let statuses = Dictionary(uniqueKeysWithValues: extraction.value.map { ($0.href, $0.status) })
        XCTAssertEqual(statuses["OEBPS/c1.xhtml"], "indexed")
        XCTAssertEqual(statuses["OEBPS/c2.xhtml"], "unavailable_excessive_nesting")
        XCTAssertFalse(extraction.value.flatMap(\.blocks).contains { $0.text.contains("cannot be shown") }, "placeholder text was indexed")
        let hits = try await s.search("orchard keeper")
        XCTAssertEqual(hits.first?.href, "OEBPS/c1.xhtml")
        let readiumHits = try await s.readiumSearch("Innermost")
        XCTAssertEqual(readiumHits.count, 0, "Readium's search must only see the placeholder")
        XCTAssertLessThan(open.seconds + nav.seconds + extraction.seconds, 30)
        Self.report["deep_nesting_through_adapter"] = [
            "open_seconds": open.seconds, "navigate_seconds": nav.seconds, "displayed": shown,
            "extraction_seconds": extraction.seconds, "statuses": statuses, "max_depth_seen": s.opened.sanitizer.maxElementDepth,
            "session_search_hits": hits.map(\.href), "readium_search_hits_for_innermost": readiumHits.count,
        ]
    }

    /// Review finding R1-01: nesting that a text-level depth scanner measured as shallow while SwiftSoup (inside
    /// Readium's content iterator) built a 10,000-deep tree and crashed the app through the adapter
    /// (g01-nesting-bypass.epub: spans after "<!-->", and "<span></x>" repeated). The sanitizer parses instead of
    /// scanning: the comment-wrapped spans are a comment to the XML parser and are not served at all; the unmatched end
    /// tags are not well-formed XML and the chapter is withheld. Extraction, Readium's own search and the navigator
    /// all run in this process; a stack overflow here would crash the test host.
    func testParserDivergenceNestingCannotReachReadium() async throws {
        let screen = try await TestHost.open("g01-nesting-bypass.epub")
        let s = screen.session
        var shown: [String: Any] = [:]
        for href in ["OEBPS/c2.xhtml", "OEBPS/c3.xhtml"] {
            let went = await s.followLink(href: href)
            XCTAssertTrue(went, href)
            try await Task.sleep(for: .seconds(1))
            shown[href] = try await ReaderProbe.json(s, """
            JSON.stringify({ href: String(location.href), unavailable: document.body.getAttribute('data-sylvia-unavailable'),
                             spans: document.getElementsByTagName('span').length, text: document.body.textContent.trim().slice(0, 120) })
            """)
        }
        let c2 = try XCTUnwrap(shown["OEBPS/c2.xhtml"] as? [String: Any])
        XCTAssertEqual(c2["spans"] as? Int, 0, "\(c2)")
        XCTAssertTrue((c2["text"] as? String ?? "").contains("After the comment."), "\(c2)")
        let c3 = try XCTUnwrap(shown["OEBPS/c3.xhtml"] as? [String: Any])
        XCTAssertEqual(c3["unavailable"] as? String, "unsupported-markup", "\(c3)")

        let extraction = await timed { await EPUBExtraction.extract(s.opened) }
        let statuses = Dictionary(uniqueKeysWithValues: extraction.value.map { ($0.href, $0.status) })
        XCTAssertEqual(statuses["OEBPS/c1.xhtml"], "indexed")
        XCTAssertEqual(statuses["OEBPS/c2.xhtml"], "indexed")
        XCTAssertEqual(statuses["OEBPS/c3.xhtml"], "unavailable_unsupported_markup")
        let c2Text = extraction.value.first { $0.href == "OEBPS/c2.xhtml" }?.blocks.map(\.text) ?? []
        XCTAssertTrue(c2Text.contains { $0.contains("After the comment.") }, "\(c2Text)")
        XCTAssertFalse(extraction.value.flatMap(\.blocks).contains { $0.text.contains("Innermost") || $0.text.contains("cannot be shown") })
        let readiumHits = try await s.readiumSearch("Innermost")
        XCTAssertEqual(readiumHits.count, 0)
        let hits = try await s.search("After the comment")
        XCTAssertEqual(hits.first?.href, "OEBPS/c2.xhtml")
        XCTAssertLessThanOrEqual(s.opened.sanitizer.maxElementDepth, PublicationHTMLSafety.maxElementDepth)
        XCTAssertEqual(s.opened.sanitizer.documentsWithoutCSP, 0)
        Self.report["nesting_parser_divergence_through_adapter"] = [
            "displayed": shown, "statuses": statuses, "extraction_seconds": extraction.seconds,
            "max_depth_seen": s.opened.sanitizer.maxElementDepth, "withheld": s.opened.sanitizer.withheldReasons.mapValues(\.rawValue),
            "withheld_details": s.opened.sanitizer.withheldDetails, "dropped_comments": s.opened.sanitizer.droppedComments,
            "readium_search_hits_for_innermost": readiumHits.count, "session_search_hits": hits.map(\.href),
        ]
    }

    /// Review finding R1-02: markup that put a regex-injected CSP inside a comment (a comment containing "<head>"), or
    /// left it out (a prefixed `<h:html>` root), so publication event handlers ran through the adapter; and "<!-->" in a
    /// text/html item, which WebKit's HTML parser reads as a whole comment followed by a live script. Readium alone is
    /// recorded as the positive control (each chapter's script or handler does run in WebKit); through the adapter none
    /// may run, every page carries the CSP in its head, and the text is shown.
    func testCSPPlacementBypassesRunNoScript() async throws {
        let probe = """
        (function () { const root = document.documentElement; const meta = document.querySelector('meta[http-equiv="Content-Security-Policy"]');
          return JSON.stringify({
            href: String(location.href), onload_ran: window.__sylviaBypassOnload === true, onerror_ran: window.__sylviaBypassOnerror === true,
            inline_ran: window.__sylviaBypassInline === true, pwned_attribute: root ? root.getAttribute('data-sylvia-pwned') : null,
            csp_meta_in_head: !!(meta && document.head && meta.parentNode === document.head),
            csp_meta_count: document.querySelectorAll('meta[http-equiv="Content-Security-Policy"]').length,
            script_elements: document.querySelectorAll('script').length,
            handler_attributes: Array.from(document.querySelectorAll('*')).reduce((n, e) => n + Array.from(e.attributes).filter(a => /^on/i.test(a.localName)).length, 0),
            target_text: (document.getElementById('target') || {}).textContent || null,
            readium_injected: typeof window.readium !== 'undefined' }); })()
        """
        let chapters = ["OEBPS/c1.xhtml", "OEBPS/c2.xhtml", "OEBPS/c3.html"]
        var results: [String: Any] = [:]
        for (name, options, safety) in [("readium-defaults", EPUBOpenOptions.readiumDefaults, ReadiumReaderSession.Safety.readiumDefaults),
                                        ("sylvia", .sylvia, .sylvia)] {
            let screen = try await TestHost.open("g01-csp-bypass.epub", options: options, safety: safety)
            let s = screen.session
            var rows: [String: Any] = [:]
            for href in chapters {
                let went = await s.followLink(href: href)
                var m: [String: Any] = [:]
                // Give handlers time to run (onload, onerror for a missing image), then read the page.
                _ = await ReaderProbe.wait(timeout: .seconds(5)) {
                    m = (try? await ReaderProbe.json(s, probe)) ?? [:]
                    let here = (m["href"] as? String ?? "").hasSuffix(href)
                    let ran = m["onload_ran"] as? Bool == true || m["onerror_ran"] as? Bool == true || m["inline_ran"] as? Bool == true
                    return here && (name == "sylvia" || ran)
                }
                if name == "sylvia" { try await Task.sleep(for: .seconds(1.5)); m = (try? await ReaderProbe.json(s, probe)) ?? [:] }
                rows[href] = ["navigated": went, "document": m]
                XCTAssertTrue(went, "\(name) \(href): navigation failed")
                XCTAssertTrue((m["href"] as? String ?? "").hasSuffix(href), "\(name) \(href): the probe did not run in that document: \(m)")
                let ran = m["onload_ran"] as? Bool == true || m["onerror_ran"] as? Bool == true || m["inline_ran"] as? Bool == true
                if name == "readium-defaults" {
                    XCTAssertTrue(ran, "positive control: \(href) is expected to run a publication script in WebKit without the adapter: \(m)")
                } else {
                    XCTAssertFalse(ran, "\(href): a publication script ran through the adapter: \(m)")
                    XCTAssertTrue(m["pwned_attribute"] is NSNull, "\(href): \(m)")
                    XCTAssertEqual(m["csp_meta_in_head"] as? Bool, true, "\(href): \(m)")
                    XCTAssertEqual(m["script_elements"] as? Int, 0, "\(href): \(m)")
                    XCTAssertEqual(m["handler_attributes"] as? Int, 0, "\(href): \(m)")
                    XCTAssertEqual(m["readium_injected"] as? Bool, true, "\(href): Readium's own scripts must still run")
                    XCTAssertNotNil(m["target_text"] as? String, "\(href): text not displayed: \(m)")
                }
            }
            if name == "sylvia" {
                XCTAssertEqual(s.opened.sanitizer.documentsWithoutCSP, 0)
                XCTAssertTrue(s.opened.sanitizer.withheldReasons.isEmpty, "\(s.opened.sanitizer.withheldDetails)")
                rows["sanitized_documents"] = s.opened.sanitizer.documents
                rows["documents_without_csp"] = s.opened.sanitizer.documentsWithoutCSP
                rows["removed_event_handlers"] = s.opened.sanitizer.removedEventHandlers
                rows["removed_scripts"] = s.opened.sanitizer.removedScripts
                rows["dropped_comments"] = s.opened.sanitizer.droppedComments
            }
            results[name] = rows
            TestHost.tearDown()
        }
        Self.report["csp_placement_bypasses"] = results
    }

    /// Review R2-01: Readium 3.11.0 cancels link activations only, and serves any archive entry the web view asks for
    /// (an undeclared one with a media type guessed from its extension). A form submission in a chapter that has no page
    /// CSP (a script-free spine item declared `application/xml` with an XHTML root) navigated the web view to an
    /// undeclared `evil.html` and to a declared non-spine XML resource, and their scripts ran (g01-form-navigation.epub).
    ///
    /// Every action starts from a freshly opened book. Actions: a form button tapped through `click()` (the navigation a
    /// finger tap on the button produces) in the XHTML chapter c1 and in the XML item c2, aimed at each target; and a
    /// navigation set by a reader-owned script (`location.href`, a test hook standing in for any navigation that is not
    /// a link activation), aimed at each target. Configurations: Readium alone (positive control: the scripts run),
    /// the adapter's container and sanitizers alone, the content rule list alone, and the full adapter. Through the
    /// adapter, and through each of its two layers alone, no target script may run.
    func testNonLinkNavigationsReachOnlySanitizedDeclaredDocuments() async throws {
        let probe = """
        (function () { const root = document.documentElement;
          return JSON.stringify({
            href: String(location.href), target_script_ran: window.__sylviaEvil === true,
            pwned_attribute: root ? root.getAttribute('data-sylvia-pwned') : null,
            unavailable: root ? root.getAttribute('data-sylvia-unavailable') : null,
            csp_meta: !!document.querySelector('meta[http-equiv="Content-Security-Policy"]'),
            buttons: document.querySelectorAll('button').length,
            text: root ? (root.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 80) : '' }); })()
        """
        struct Action { let name: String; let chapter: String; let script: String }
        func click(_ id: String) -> String {
            "(function(){ const b = document.getElementById('\(id)'); if (!b) return 'no-button'; b.click(); return 'clicked'; })()"
        }
        func go(_ target: String) -> String { "(function(){ location.href = '\(target)'; return 'navigating'; })()" }
        let actions = [
            Action(name: "c1 form to undeclared evil.html", chapter: "OEBPS/c1.xhtml", script: click("go")),
            Action(name: "c1 form to declared non-spine decl.xml", chapter: "OEBPS/c1.xhtml", script: click("go2")),
            Action(name: "c2.xml form to undeclared evil.html", chapter: "OEBPS/c2.xml", script: click("go")),
            Action(name: "c2.xml form to declared non-spine decl.xml", chapter: "OEBPS/c2.xml", script: click("go2")),
            Action(name: "c2.xml form to fake.png (markup declared image/png)", chapter: "OEBPS/c2.xml", script: click("go3")),
            Action(name: "c2.xml form to declared non-spine extra.xhtml", chapter: "OEBPS/c2.xml", script: click("go4")),
            Action(name: "script navigation to undeclared evil.html", chapter: "OEBPS/c1.xhtml", script: go("evil.html")),
            Action(name: "script navigation to declared non-spine decl.xml", chapter: "OEBPS/c1.xhtml", script: go("decl.xml")),
            Action(name: "script navigation to declared non-spine extra.xhtml", chapter: "OEBPS/c1.xhtml", script: go("extra.xhtml")),
            Action(name: "script navigation to fake.png", chapter: "OEBPS/c1.xhtml", script: go("fake.png")),
        ]
        let configs: [(String, EPUBOpenOptions, ReadiumReaderSession.Safety)] = [
            ("readium-defaults", .readiumDefaults, .readiumDefaults),
            ("container-and-sanitizers-only", .sylvia, .readiumDefaults),
            ("content-rule-list-only", .readiumDefaults, .sylvia),
            ("sylvia", .sylvia, .sylvia),
        ]
        var results: [String: Any] = [:]
        for (config, options, safety) in configs {
            var rows: [String: Any] = [:]
            var undeclared: Set<String> = []
            for action in actions {
                let screen = try await TestHost.open("g01-form-navigation.epub", options: options, safety: safety)
                let s = screen.session
                let went = await s.followLink(href: action.chapter)
                try await Task.sleep(for: .seconds(1))
                let before = (try? await ReaderProbe.json(s, probe)) ?? ["error": "evaluation failed"]
                let fired = (try? await ReaderProbe.evaluate(s, action.script)) ?? "evaluation failed"
                try await Task.sleep(for: .seconds(2.5))
                let after = (try? await ReaderProbe.json(s, probe)) ?? ["error": "evaluation failed"]
                let ran = after["target_script_ran"] as? Bool == true || !(after["pwned_attribute"] is NSNull || after["pwned_attribute"] == nil)
                rows[action.name] = ["navigated_to_chapter": went, "chapter_before": before, "action": fired, "after": after,
                                     "target_script_ran": ran]
                XCTAssertTrue(went, "\(config) \(action.name): could not open \(action.chapter)")
                XCTAssertTrue((before["href"] as? String ?? "").contains(action.chapter), "\(config) \(action.name): \(before)")
                switch config {
                case "readium-defaults":
                    // Positive controls: without the adapter the publication's own scripts run in the target.
                    if action.name.hasPrefix("c2.xml form to undeclared") || action.name.hasPrefix("c2.xml form to declared non-spine")
                        || action.name.hasPrefix("c1 form") || (action.name.hasPrefix("script navigation") && !action.name.hasSuffix("fake.png")) {
                        XCTAssertTrue(ran, "positive control: \(action.name) is expected to run the target's script without the adapter: \(after)")
                    }
                    // Markup served as image/png is shown as an image, never run (basis for the adapter's passive types).
                    if action.name.contains("fake.png") {
                        XCTAssertFalse(ran, "\(action.name): markup served as image/png ran a script: \(after)")
                    }
                default:
                    XCTAssertFalse(ran, "\(config) \(action.name): a publication script ran: \(after)")
                    XCTAssertTrue(after["pwned_attribute"] is NSNull, "\(config) \(action.name): \(after)")
                    XCTAssertTrue((after["href"] as? String ?? "").hasPrefix("readium:"), "\(config) \(action.name): left the publication: \(after)")
                }
                if options.sanitizeHTML, action.chapter == "OEBPS/c2.xml" {
                    // The XML item cannot carry a page CSP and holds XHTML form controls: it is withheld.
                    XCTAssertEqual(before["unavailable"] as? String, "active-content", "\(config) \(action.name): \(before)")
                    XCTAssertEqual(before["buttons"] as? Int, 0, "\(config) \(action.name): \(before)")
                }
                undeclared.formUnion(s.opened.sanitizer.undeclaredRequests)
                TestHost.tearDown()
            }
            if options.sanitizeHTML {
                rows["undeclared_requests_refused"] = undeclared.sorted()
            }
            if config == "container-and-sanitizers-only" {
                // Without the rule list the script navigation reaches Readium's scheme handler, and the container refuses it.
                XCTAssertTrue(undeclared.contains("OEBPS/evil.html"), "\(config): the script navigation to evil.html never reached the container: \(undeclared)")
            }
            results[config] = rows
        }

        // What the adapter's container serves for each target, read through Readium's publication API.
        var served: [String: Any] = [:]
        let fixture = try TestHost.fixtureURL("g01-form-navigation.epub")
        for (config, options) in [("readium-defaults", EPUBOpenOptions.readiumDefaults), ("sylvia", .sylvia)] {
            guard case let .success(opened) = await EPUBOpener.open(fileURL: fixture, options: options) else {
                XCTFail("\(config): open failed"); continue
            }
            var rows: [String: Any] = [:]
            for href in ["OEBPS/evil.html", "OEBPS/decl.xml", "OEBPS/extra.xhtml", "OEBPS/fake.png", "OEBPS/c2.xml", "OEBPS/content.opf",
                         "META-INF/container.xml"] {
                guard let resource = opened.publication.get(AnyURL(string: href)!) else { rows[href] = ["served": false]; continue }
                let text = (try? await resource.read().get()).map { String(decoding: $0, as: UTF8.self) } ?? ""
                rows[href] = ["served": true, "bytes": text.utf8.count, "has_script_element": text.contains("<script"),
                              "csp": text.contains("Content-Security-Policy"), "placeholder": text.contains(PublicationHTMLSafety.unavailableAttribute)]
            }
            rows["treatments"] = opened.sanitizer.treatments.mapValues(\.rawValue)
            served[config] = rows
            if config == "sylvia" {
                for href in ["OEBPS/evil.html", "OEBPS/content.opf", "META-INF/container.xml"] {
                    XCTAssertEqual((rows[href] as? [String: Any])?["served"] as? Bool, false, "\(href) is not declared and must not be served")
                }
                let decl = rows["OEBPS/decl.xml"] as? [String: Any]
                XCTAssertEqual(decl?["placeholder"] as? Bool, true, "decl.xml: \(decl ?? [:])")
                XCTAssertEqual(decl?["has_script_element"] as? Bool, false)
                let extra = rows["OEBPS/extra.xhtml"] as? [String: Any]
                XCTAssertEqual(extra?["csp"] as? Bool, true, "extra.xhtml: \(extra ?? [:])")
                XCTAssertEqual(extra?["has_script_element"] as? Bool, false)
                XCTAssertEqual(opened.sanitizer.treatments["OEBPS/fake.png"], .passive)
                XCTAssertEqual(opened.sanitizer.treatments["OEBPS/c2.xml"], .otherDocument)
                XCTAssertEqual(opened.sanitizer.treatments["OEBPS/decl.xml"], .otherDocument)
                XCTAssertEqual(opened.sanitizer.treatments["OEBPS/extra.xhtml"], .htmlDocument)
                let statuses = Dictionary(uniqueKeysWithValues: await EPUBExtraction.extract(opened).map { ($0.href, $0.status) })
                XCTAssertEqual(statuses["OEBPS/c1.xhtml"], "indexed")
                XCTAssertEqual(statuses["OEBPS/c2.xml"], "unavailable_active_content")
                rows["extraction_statuses"] = statuses
                served[config] = rows
            } else {
                XCTAssertEqual((rows["OEBPS/evil.html"] as? [String: Any])?["served"] as? Bool, true, "positive control: Readium alone serves the undeclared entry")
            }
        }
        results["served_by_publication_get"] = served
        Self.report["non_link_navigations"] = results
    }

    /// The limit itself is safe: a chapter nesting exactly 256 levels is shown, extracted by Readium's content iterator
    /// (the code path that crashes at 10,000) and searchable, in this process.
    func testNestingAtTheLimitIsShownAndExtracted() async throws {
        let screen = try await TestHost.open("g01-nesting-limit.epub")
        let s = screen.session
        let went = await s.followLink(href: "OEBPS/c2.xhtml")
        XCTAssertTrue(went)
        try await Task.sleep(for: .seconds(1))
        let text = try await ReaderProbe.evaluate(s, "document.getElementById('deep').textContent")
        XCTAssertEqual(text, "Words at the nesting limit.")
        let extraction = await timed { await EPUBExtraction.extract(s.opened) }
        let c2 = try XCTUnwrap(extraction.value.first { $0.href == "OEBPS/c2.xhtml" })
        XCTAssertEqual(c2.status, "indexed")
        XCTAssertTrue(c2.blocks.contains { $0.text.contains("Words at the nesting limit.") }, "\(c2.blocks.map(\.text))")
        XCTAssertEqual(s.opened.sanitizer.maxElementDepth, PublicationHTMLSafety.maxElementDepth)
        let readiumHits = try await s.readiumSearch("nesting limit")
        XCTAssertFalse(readiumHits.isEmpty)
        Self.report["nesting_at_limit"] = [
            "depth": s.opened.sanitizer.maxElementDepth, "extraction_seconds": extraction.seconds,
            "c2_blocks": c2.blocks.map(\.text), "readium_search_hits": readiumHits.count,
        ]
    }

    // MARK: T12: protection and encryption.xml

    func testFontObfuscationStillOpensAndIsDeobfuscated() async throws {
        let url = try TestHost.fixtureURL("g01-font-obfuscated.epub")
        guard case let .success(opened) = await EPUBOpener.open(fileURL: url, options: .sylvia) else {
            return XCTFail("an EPUB whose encryption.xml only obfuscates a font must open")
        }
        let entries = Set(ZIPPreflight.inspect(fileAt: url).entries.map(\.name))
        XCTAssertTrue(entries.contains("META-INF/encryption.xml"))
        let font = try await XCTUnwrap(opened.publication.get(AnyURL(string: "OEBPS/fonts/sylvia-test.otf")!)).read().get()
        let digest = SHA256.hash(data: font).map { String(format: "%02x", $0) }.joined()
        let expectedURL = Bundle.main.resourceURL!.appendingPathComponent("generated/g01-font-obfuscated.font-plain.sha256")
        let expected = try String(contentsOf: expectedURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(digest, expected, "Readium did not de-obfuscate the font")
        let algorithm = opened.publication.resources.first { $0.href.hasSuffix("sylvia-test.otf") }?.properties.encryption?.algorithm
        XCTAssertEqual(algorithm, "http://www.idpf.org/2008/embedding")
        let screen = try await TestHost.open("g01-font-obfuscated.epub")
        XCTAssertNotNil(screen.session.currentLocator)
        Self.report["font_obfuscation"] = ["opened": true, "deobfuscated_sha256": digest, "expected_sha256": expected, "algorithm": algorithm ?? ""]
    }

    func testProtectedContentGivesAClearUnsupportedProtectionError() async throws {
        let cases: [(String, String)] = [
            ("g01-encrypted-chapter.epub", "unknown"), ("g01-lcp-like.epub", "lcp"), ("g01-adept-like.epub", "adept"),
        ]
        // SHA-256 of chapter 2's plaintext and of the AES-CBC ciphertexts stored in the archives (written by the generator).
        let digestsURL = Bundle.main.resourceURL!.appendingPathComponent("generated/g01-protected-chapter.digests.txt")
        var digests: [String: String] = [:]
        for line in try String(contentsOf: digestsURL, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t").map(String.init)
            if parts.count == 2 { digests[parts[0]] = parts[1] }
        }
        let plaintextDigest = try XCTUnwrap(digests["plaintext"])
        let storedDigest = ["g01-encrypted-chapter.epub": digests["stored-aes256"], "g01-lcp-like.epub": digests["stored-aes256"],
                            "g01-adept-like.epub": digests["stored-aes128"]]
        var rows: [String: Any] = [:]
        for (name, scheme) in cases {
            let url = try TestHost.fixtureURL(name)
            let sylvia = await timed { await EPUBOpener.open(fileURL: url, options: .sylvia) }
            var row: [String: Any] = ["sylvia": describe(sylvia.value), "seconds": sylvia.seconds]
            if case let .failure(.unsupportedProtection(found, algorithms)) = sylvia.value {
                XCTAssertTrue(found.lowercased().contains(scheme), "\(name): scheme \(found)")
                if scheme == "unknown" { XCTAssertEqual(algorithms, ["http://www.w3.org/2001/04/xmlenc#aes256-cbc"]) }
                XCTAssertEqual(ReaderOpenError.unsupportedProtection(scheme: found, algorithms: algorithms).importState, "unsupported")
            } else {
                XCTFail("\(name): expected unsupported protection, got \(describe(sylvia.value))")
            }
            // Readium alone: does it open, and what does a reader of chapter 2 get?
            let readium = await EPUBOpener.open(fileURL: url, options: .readiumDefaults)
            row["readium_defaults"] = describe(readium)
            if case let .success(opened) = readium {
                let p = opened.publication
                row["readium_is_restricted"] = p.isRestricted
                row["readium_protection_scheme"] = p.protectionScheme?.rawValue.string ?? "none"
                row["readium_protection_error"] = p.protectionError.map { "\($0)" } ?? "none"
                if let resource = p.get(AnyURL(string: "OEBPS/c2.xhtml")!) {
                    switch await resource.read() {
                    case let .success(d):
                        // Readium never decrypts: what it serves for chapter 2 is the stored ciphertext, byte for byte.
                        let served = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
                        row["readium_chapter2"] = "read \(d.count) bytes"
                        row["readium_chapter2_sha256"] = served
                        row["readium_chapter2_is_stored_ciphertext"] = served == storedDigest[name] ?? nil
                        row["readium_chapter2_is_plaintext"] = served == plaintextDigest
                        XCTAssertEqual(served, storedDigest[name] ?? nil, "\(name): Readium did not serve the stored ciphertext")
                        XCTAssertNotEqual(served, plaintextDigest, "\(name): Readium decrypted the chapter")
                    case let .failure(e):
                        row["readium_chapter2"] = "error: \(e)"
                    }
                } else {
                    row["readium_chapter2"] = "no resource"
                }
                if scheme == "unknown" {
                    XCTAssertFalse(p.isRestricted, "Readium 3.11.0 is expected not to flag a non-LCP/ADEPT encryption.xml")
                } else {
                    XCTAssertTrue(p.isRestricted, "\(name): Readium's fallback protection should flag \(scheme)")
                }
            }
            rows[name] = row
        }
        // Truncated archive (T12): a clear error with and without the preflight, never a crash.
        let truncated = try TestHost.fixtureURL("g01-truncated.epub")
        let t1 = await EPUBOpener.open(fileURL: truncated, options: .sylvia)
        let t2 = await EPUBOpener.open(fileURL: truncated, options: .readiumDefaults)
        if case .success = t2 { XCTFail("Readium opened a truncated archive") }
        XCTAssertEqual(t1.failureCode, "unsafe_archive")
        rows["g01-truncated.epub"] = ["sylvia": describe(t1), "readium_defaults": describe(t2)]
        Self.report["protection"] = rows
    }
}

/// Counts bytes delivered by Readium's streaming reads (called off the main actor).
/// Also records the largest buffer Readium handed over and the process footprint while it was alive.
final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0, largest = 0, count = 0
    private var peak: UInt64 = 0
    func add(_ n: Int) {
        let footprint = physFootprint()
        lock.lock()
        total += n
        count += 1
        largest = max(largest, n)
        peak = max(peak, footprint)
        lock.unlock()
    }

    var value: Int { lock.lock(); defer { lock.unlock() }; return total }
    var largestChunk: Int { lock.lock(); defer { lock.unlock() }; return largest }
    var chunks: Int { lock.lock(); defer { lock.unlock() }; return count }
    var peakFootprint: UInt64 { lock.lock(); defer { lock.unlock() }; return peak }
}

extension Result where Success == OpenedEPUB, Failure == ReaderOpenError {
    var failureCode: String? {
        guard case let .failure(e) = self else { return nil }
        switch e {
        case .unsafeArchive: return "unsafe_archive"
        case .notARegularFile: return "not_a_regular_file"
        case .unreadable: return "unreadable"
        case .notAnEPUB: return "not_an_epub"
        case .unsupportedProtection: return "unsupported_protection"
        case .unsupportedLayout: return "unsupported_layout"
        }
    }
}
