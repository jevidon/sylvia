@testable import EPUBHarness
import Darwin
import Foundation
import G01EPUBCore
import UIKit
import XCTest

/// Review R3-01: the slowest documents the sanitizer still serves are the ones just under its caps. The host test
/// (`PublicationHTMLSafetyTests.linearTime`) times them on the Mac; this test times the same three documents wherever
/// the hosted tests run, so device checklist step 11 measures them on a phone. Each document is sanitized three times
/// with a generous budget (so a slow run is measured, not cut off), and each run must finish inside the product's
/// 20 s budget: a run over it means that legitimate document would be withheld on this machine. The load average
/// before and after is recorded because other jobs on the same machine change the figures.
@MainActor final class SanitizerAtCapsTimingTests: XCTestCase {
    typealias Safety = PublicationHTMLSafety
    static let runs = 3

    /// The same documents as the host test's `atCaps` list (same `doc` wrapper, same element and attribute counts).
    static func doc(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en"><head><title>t</title></head>
        <body>\(body)</body></html>
        """
    }

    static func attributeList(_ n: Int) -> String { (0 ..< n).map { "a\($0)=\"v\"" }.joined(separator: " ") }

    static var atCaps: [(String, String)] {
        [
            ("256 attributes per element, just under the document's attribute cap",
             doc(String(repeating: "<i " + attributeList(256) + ">x</i>", count: Safety.maxAttributesPerDocument / 256 - 1))),
            ("one attribute per element, just under the element cap",
             doc(String(repeating: "<i a=\"v\">x</i>", count: Safety.maxElementsPerDocument - 10))),
            ("no attributes, just under the element cap", doc(String(repeating: "<i>x</i>", count: Safety.maxElementsPerDocument - 10))),
        ]
    }

    static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values.map { (($0 * 100).rounded()) / 100 } : []
    }

    func testDocumentsJustUnderTheCapsAreServedWithinTheBudget() async throws {
        let budget = Safety.defaultTimeBudget.seconds
        #if DEBUG
            let configuration = "Debug"
        #else
            let configuration = "Release"
        #endif
        var report: [String: Any] = [
            "environment": CompatibilityMatrixTests.environment,
            "build_configuration": configuration,
            "budget_seconds": budget,
            "runs_per_document": Self.runs,
            "load_average_before": Self.loadAverage(),
            "processor_count": ProcessInfo.processInfo.activeProcessorCount,
        ]
        var documents: [[String: Any]] = []
        for (name, input) in Self.atCaps {
            var seconds: [Double] = []
            var last: Safety.Result?
            for _ in 0 ..< Self.runs {
                let r = await Safety.sanitize(html: input, budget: .seconds(120))
                XCTAssertNil(r.withheld, "\(name): \(r.detail ?? "")")
                XCTAssertLessThan(r.seconds, budget, "\(name): \(r.seconds) s is over the \(budget) s budget; this document would be withheld here")
                seconds.append((r.seconds * 1000).rounded() / 1000)
                last = r
            }
            documents.append([
                "document": name,
                "input_mib": ((Double(input.utf8.count) / Double(1 << 20)) * 100).rounded() / 100,
                "elements": last?.elementCount ?? -1,
                "attributes": last?.attributeCount ?? -1,
                "seconds": seconds,
                "max_seconds": seconds.max() ?? -1,
                "served": last?.withheld == nil,
            ])
        }
        report["documents"] = documents
        report["load_average_after"] = Self.loadAverage()
        report["note"] = "Wall-clock time of PublicationHTMLSafety.sanitize per run; the product withholds a document that takes longer than budget_seconds."
        #if targetEnvironment(simulator)
            ReaderProbe.writeEvidence("sanitizer-at-caps-simulator.json", json: report)
        #else
            ReaderProbe.writeEvidence("sanitizer-at-caps-device.json", json: report)
        #endif
    }
}
