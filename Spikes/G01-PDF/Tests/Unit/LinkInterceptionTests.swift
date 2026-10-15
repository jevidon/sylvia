import PDFAnchorKit
import PDFKit
import UIKit
import XCTest

/// Brief item 7 and plan 18.1: no launch actions, no automatic or unsolicited URL opens.
///
/// Detection: the harness app registers the fixture's canary scheme (`sylvia-g01-canary`). Any canary URL that the
/// system opens is delivered back to the harness scene and recorded by `URLOpenRecorder`. A control test proves the
/// detector works by opening a canary URL deliberately.
@MainActor
final class LinkInterceptionTests: XCTestCase {
    static let canaryWait: TimeInterval = 3

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { URLOpenRecorder.shared.reset() }
    }

    func actionsView(delegate: PDFViewDelegate?) throws -> (UIWindow, PDFView, PDFSourceDocument) {
        let source = try Fixture.open("actions.pdf")
        let window = makeHostWindow()
        let view = PDFView(frame: window.bounds)
        view.autoScales = true
        view.delegate = delegate
        window.rootViewController?.view.addSubview(view)
        view.document = source.document
        view.layoutIfNeeded()
        return (window, view, source)
    }

    func linkAction(_ source: PDFSourceDocument, _ index: Int) throws -> PDFAction {
        try XCTUnwrap(source.page(at: 0)?.annotations[index].action)
    }

    func testDeclaredActionsAndPolicyDecisions() throws {
        let source = try Fixture.open("actions.pdf")
        let declared = PDFActionAudit.audit(source.document)
        let types = declared.map(\.type)
        XCTAssertTrue(types.contains("Launch"))
        XCTAssertTrue(types.contains("JavaScript"))
        XCTAssertEqual(declared.filter { $0.location == "catalog /OpenAction" }.map(\.type), ["URI"])
        XCTAssertEqual(declared.filter { $0.location == "page 0 /AA /O" }.map(\.target), ["sylvia-g01-canary://page-open-action"])

        // How PDFKit presents the four link annotations, and what Sylvia decides for each.
        let actions = try (0..<4).map { try linkAction(source, $0) }
        XCTAssertEqual((actions[0] as? PDFActionURL)?.url?.absoluteString, "sylvia-g01-canary://link-uri")
        XCTAssertEqual((actions[1] as? PDFActionURL)?.url?.absoluteString, "https://example.invalid/track")
        // Observation: PDFKit re-types the /Launch action as a URL action whose URL is the launch file resolved
        // against the PDF's own location: a file: URL ending in "/bin/sh".
        let launchURL = try XCTUnwrap((actions[2] as? PDFActionURL)?.url)
        XCTAssertEqual(launchURL.scheme, "file")
        XCTAssertTrue(launchURL.path.hasSuffix("/bin/sh"), launchURL.path)
        XCTAssertTrue(actions[3] is PDFActionGoTo)
        let decisions = actions.map { LinkPolicy.decide(action: $0, in: source.document) }
        XCTAssertEqual(decisions[0], .blocked(reason: "scheme sylvia-g01-canary is not allowed"))
        XCTAssertEqual(decisions[1], .askUserBeforeOpening(URL(string: "https://example.invalid/track")!))
        XCTAssertEqual(decisions[2], .blocked(reason: "scheme file is not allowed"))
        XCTAssertEqual(decisions[3], .navigate(pageIndex: 1))
        XCTAssertEqual(LinkPolicy.decide(url: URL(string: "file:///etc/hosts")!), .blocked(reason: "scheme file is not allowed"))
        XCTAssertEqual(LinkPolicy.decide(url: URL(string: "javascript:alert(1)")!), .blocked(reason: "scheme javascript is not allowed"))

        var lines = ["actions.pdf: declared actions (read from the file's dictionaries), \(Evidence.environmentLabel)"]
        lines += declared.map { "  \($0)" }
        lines.append("link annotations as PDFKit presents them -> Sylvia's decision:")
        for (a, d) in zip(actions, decisions) {
            lines.append("  \(type(of: a)) \((a as? PDFActionURL)?.url?.absoluteString ?? (a as? PDFActionGoTo).map { _ in "GoTo" } ?? a.type) -> \(d)")
        }
        Evidence.write("links-declared-and-decided.txt", lines.joined(separator: "\n") + "\n")
    }

    /// Control: the canary detector works. A deliberate open of a canary URL comes back to the harness.
    func testControlCanaryDetectorReceivesADeliberateOpen() async throws {
        let url = URL(string: "sylvia-g01-canary://control-deliberate")!
        let opened = await UIApplication.shared.open(url)
        XCTAssertTrue(opened, "the system did not open the harness's own scheme")
        XCTAssertTrue(waitUntil(timeout: 10) { URLOpenRecorder.shared.received.contains(url) },
                      "the canary detector did not see a deliberate open; later 'no canary' results would prove nothing")
    }

    /// Control: without Sylvia's delegate, PDFKit's default link handling opens the URL by itself, and only that URL
    /// (the file's open action, page-open action and document JavaScript, all canaries too, do not arrive).
    func testControlPDFKitDefaultOpensURLWithoutInterceptor() throws {
        let (window, view, source) = try actionsView(delegate: nil)
        defer { window.isHidden = true }
        view.perform(try linkAction(source, 0))
        let received = waitUntil(timeout: 10) { URLOpenRecorder.shared.received.contains(URL(string: "sylvia-g01-canary://link-uri")!) }
        XCTAssertTrue(received, "expected PDFKit's default to open the canary link (this is the behaviour the interceptor prevents)")
        spinRunLoop(seconds: Self.canaryWait)
        XCTAssertEqual(URLOpenRecorder.shared.received.map(\.absoluteString), ["sylvia-g01-canary://link-uri"],
                       "PDFKit's default opens the performed link and nothing else")
        Evidence.write("links-control-no-interceptor.txt",
                       "Control without LinkInterceptor, \(Evidence.environmentLabel): PDFView.perform(link A), then \(Self.canaryWait) s -> URLs delivered to the harness: \(URLOpenRecorder.shared.received.map(\.absoluteString))\n")
    }

    /// Control for `testOpeningTheDocumentRunsNoOpenActionOrJavaScript`, without Sylvia's delegate: displaying
    /// actions.pdf and changing pages delivers none of its canaries (catalog /OpenAction URI, page 0 /AA /O URI,
    /// document JavaScript), so PDFKit itself does not run them; the delegate is not what stops them. That PDFKit's
    /// default does deliver a canary it performs is the control above.
    func testControlWithoutInterceptorOpeningRunsNoOpenActionOrJavaScript() throws {
        let (window, view, _) = try actionsView(delegate: nil)
        defer { window.isHidden = true }
        view.go(to: try XCTUnwrap(view.document?.page(at: 1)))
        view.go(to: try XCTUnwrap(view.document?.page(at: 0)))
        spinRunLoop(seconds: Self.canaryWait)
        XCTAssertEqual(URLOpenRecorder.shared.received, [], "without the delegate, the /OpenAction, page /AA /O and JavaScript must not open anything")
        Evidence.write("links-open-actions-control-no-interceptor.txt", "Control without LinkInterceptor: displaying actions.pdf (catalog /OpenAction URI "
                       + "sylvia-g01-canary://open-action, page 0 /AA /O URI sylvia-g01-canary://page-open-action, /Names JavaScript asking for "
                       + "sylvia-g01-canary://javascript) for \(Self.canaryWait) s with page changes 1, 0, \(Evidence.environmentLabel)\n"
                       + "URLs delivered to the harness: \(URLOpenRecorder.shared.received.map(\.absoluteString))\n")
    }

    func testInterceptorReceivesLinksAndNothingIsOpened() throws {
        let interceptor = LinkInterceptor()
        let (window, view, source) = try actionsView(delegate: interceptor)
        defer { window.isHidden = true }
        for index in 0..<3 {
            view.perform(try linkAction(source, index))
        }
        spinRunLoop(seconds: Self.canaryWait)
        XCTAssertEqual(interceptor.interceptedURLs.prefix(2).map(\.absoluteString),
                       ["sylvia-g01-canary://link-uri", "https://example.invalid/track"])
        XCTAssertEqual(interceptor.interceptedURLs.count, 3)
        XCTAssertTrue(interceptor.interceptedURLs.last?.isFileURL == true && interceptor.interceptedURLs.last?.path.hasSuffix("/bin/sh") == true)
        XCTAssertEqual(interceptor.decisions, [
            .blocked(reason: "scheme sylvia-g01-canary is not allowed"),
            .askUserBeforeOpening(URL(string: "https://example.invalid/track")!),
            .blocked(reason: "scheme file is not allowed"),
        ])
        XCTAssertEqual(URLOpenRecorder.shared.received, [], "nothing may be opened while the interceptor is installed")
        // Internal GoTo still navigates.
        view.perform(try linkAction(source, 3))
        view.layoutIfNeeded()
        XCTAssertEqual(view.currentPage.map { source.index(of: $0) }, 1)
        Evidence.write("links-intercepted.txt", "With LinkInterceptor, \(Evidence.environmentLabel)\n"
                       + "PDFView.perform(link A, B, C) -> intercepted \(interceptor.interceptedURLs.map(\.absoluteString))\n"
                       + "decisions \(interceptor.decisions)\n"
                       + "URLs delivered to the harness after \(Self.canaryWait) s: \(URLOpenRecorder.shared.received.map(\.absoluteString))\n"
                       + "link D (GoTo) -> current page index \(view.currentPage.map { source.index(of: $0) } ?? -1)\n")
    }

    func testOpeningTheDocumentRunsNoOpenActionOrJavaScript() throws {
        let interceptor = LinkInterceptor()
        let (window, view, _) = try actionsView(delegate: interceptor)
        defer { window.isHidden = true }
        view.go(to: try XCTUnwrap(view.document?.page(at: 1)))
        view.go(to: try XCTUnwrap(view.document?.page(at: 0)))
        spinRunLoop(seconds: Self.canaryWait)
        XCTAssertEqual(URLOpenRecorder.shared.received, [], "the /OpenAction, page /AA and JavaScript must not open anything")
        XCTAssertEqual(interceptor.interceptedURLs, [], "nothing should even be attempted without a tap")
        Evidence.write("links-open-actions.txt", "Displaying actions.pdf (catalog /OpenAction URI, page 0 /AA /O URI, /Names JavaScript) for \(Self.canaryWait) s with page changes, \(Evidence.environmentLabel)\n"
                       + "URLs delivered to the harness: \(URLOpenRecorder.shared.received.map(\.absoluteString)); interceptor calls: \(interceptor.interceptedURLs.count)\n")
    }
}
