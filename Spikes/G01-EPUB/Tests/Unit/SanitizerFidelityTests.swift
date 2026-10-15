@testable import EPUBHarness
import Foundation
import G01EPUBCore
@preconcurrency import ReadiumShared
import WebKit
import XCTest

/// The sanitizer changes markup, never text, as WebKit sees it (simulator). Every reading-order document of the five
/// real books is read twice through Readium (without the adapter: the original bytes; with it: what the navigator is
/// served), each is loaded into an off-screen WKWebView as `application/xhtml+xml` (page JavaScript off, every load
/// but `about:` blocked), and the two `document.documentElement.textContent` strings must be identical. This compares
/// what the reader shows, independently of the parser the sanitizer itself uses (a host test that compared both sides
/// through Foundation's `XMLParser` missed lost U+FEFF characters that this check found).
@MainActor final class SanitizerFidelityTests: XCTestCase {
    func testSanitizedDocumentsShowTheSameTextInWebKit() async throws {
        let dom = try await OffscreenDOM.make()
        var report: [String: Any] = ["environment": CompatibilityMatrixTests.environment]
        var total = 0, identical = 0
        for name in CompatibilityMatrixTests.fixtures {
            let url = try TestHost.fixtureURL(name)
            guard case let .success(raw) = await EPUBOpener.open(fileURL: url, options: .readiumDefaults),
                  case let .success(sylvia) = await EPUBOpener.open(fileURL: url, options: .sylvia)
            else { XCTFail("\(name) did not open"); continue }
            var mismatches: [[String: Any]] = []
            var documents = 0, characters = 0
            for link in raw.publication.readingOrder where link.mediaType?.isHTML == true {
                guard let original = try await raw.publication.get(link)?.read().get(),
                      let served = try await sylvia.publication.get(link)?.read().get()
                else { XCTFail("\(name) \(link.href): unreadable"); continue }
                let a = try await dom.textContent(of: original)
                let b = try await dom.textContent(of: served)
                documents += 1
                characters += (a as NSString).length
                if a != b {
                    let common = zip(a, b).prefix { $0 == $1 }.count
                    mismatches.append(["href": link.href, "original_utf16": (a as NSString).length, "served_utf16": (b as NSString).length,
                                       "first_difference_at": common])
                }
            }
            XCTAssertEqual(mismatches.count, 0, "\(name): \(mismatches)")
            XCTAssertTrue(sylvia.sanitizer.withheldReasons.isEmpty, "\(name): \(sylvia.sanitizer.withheldDetails)")
            XCTAssertGreaterThan(documents, 0)
            total += documents
            identical += documents - mismatches.count
            report[name] = ["documents": documents, "identical_text": documents - mismatches.count, "text_utf16_units": characters,
                            "mismatches": mismatches]
        }
        XCTAssertGreaterThan(total, 150)
        report["documents"] = total
        report["identical_text"] = identical
        ReaderProbe.writeEvidence("sanitizer-fidelity-webkit.json", json: report)
    }
}

/// An off-screen web view that parses a document and returns its text, with page JavaScript off.
@MainActor final class OffscreenDOM: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var pending: CheckedContinuation<Void, Error>?

    static func make() async throws -> OffscreenDOM {
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "sylvia-fidelity-block-all-v1",
            encodedContentRuleList: #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}}]"#
        )
        return OffscreenDOM(rules: rules)
    }

    private init(rules: WKContentRuleList?) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        if let rules { config.userContentController.add(rules) }
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 600), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func textContent(of data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            pending = c
            webView.load(data, mimeType: "application/xhtml+xml", characterEncodingName: "utf-8", baseURL: URL(string: "about:blank")!)
        }
        let value = try await webView.evaluateJavaScript("document.documentElement ? document.documentElement.textContent : ''")
        return value as? String ?? ""
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { pending?.resume(); pending = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { pending?.resume(throwing: error); pending = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { pending?.resume(throwing: error); pending = nil }
    }
}
