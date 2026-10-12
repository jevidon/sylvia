import PDFAnchorKit
import PDFKit
import UIKit
import XCTest

/// What PDFView does with link actions that are not URLs (actions-nonurl.pdf), with Sylvia's interceptor installed:
/// named actions, /GoToR, /ResetForm, /JavaScript and /SubmitForm. ADR-0005 "Links and actions" describes exactly
/// this behaviour. The canary scheme detects any URL the system is asked to open (see `LinkInterceptionTests`).
@MainActor
final class NonURLActionTests: XCTestCase {
    static let labels = ["A NextPage", "B LastPage", "C Find", "D GoToPage", "E Print", "F GoToR", "G ResetForm",
                         "H JavaScript", "I SubmitForm"]

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { URLOpenRecorder.shared.reset() }
    }

    func testNonURLActionsStayInsideTheViewAndOpenNothing() throws {
        let copy = try Fixture.copy("actions-nonurl.pdf")
        let digestBefore = try PDFSourceDocument.sha256OfFile(at: copy)
        let source = try PDFSourceDocument.open(url: copy)
        let page0 = try XCTUnwrap(source.page(at: 0))
        let links = page0.annotations.filter { $0.type == "Link" }
        let field = try XCTUnwrap(page0.annotations.first { $0.type == "Widget" })
        XCTAssertEqual(links.count, Self.labels.count)

        let interceptor = LinkInterceptor()
        let window = makeHostWindow()
        defer { window.isHidden = true }
        let view = PDFView(frame: window.bounds)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.delegate = interceptor
        window.rootViewController?.view.addSubview(view)
        view.document = source.document
        view.layoutIfNeeded()

        var report = ["actions-nonurl.pdf: PDFView.perform(link action) with LinkInterceptor installed, starting on page index 0 each time, "
                      + "\(Evidence.environmentLabel)"]
        var outcomes: [String: (page: Int, decisions: [LinkDecision], policy: LinkDecision)] = [:]
        for (label, link) in zip(Self.labels, links) {
            let action = try XCTUnwrap(link.action, label)
            view.go(to: page0)
            view.layoutIfNeeded()
            spinRunLoop(seconds: 0.2)
            let decisionsBefore = interceptor.decisions.count
            let fieldBefore = field.widgetStringValue ?? "nil"
            view.perform(action)
            spinRunLoop(seconds: 0.5)
            let pageAfter = view.currentPage.map { source.index(of: $0) } ?? -1
            let decisions = Array(interceptor.decisions.dropFirst(decisionsBefore))
            let policy = LinkPolicy.decide(action: action, in: source.document)
            outcomes[label] = (pageAfter, decisions, policy)
            report.append("\(label): PDFKit presents \(type(of: action)) type \(action.type)\((action as? PDFActionNamed).map { " name \(LinkPolicy.name(of: $0.name))" } ?? ""); "
                          + "page index after: \(pageAfter); delegate decisions: \(decisions); policy: \(policy); "
                          + "form field \"\(fieldBefore)\" -> \"\(field.widgetStringValue ?? "nil")\"")
        }
        spinRunLoop(seconds: 2)
        let opened = URLOpenRecorder.shared.received.map(\.absoluteString)
        let digestAfter = try PDFSourceDocument.sha256OfFile(at: copy)
        report.append("URLs delivered to the harness after all actions and 2 s: \(opened)")
        report.append("file SHA-256 before \(digestBefore.0), after \(digestAfter.0)")
        Evidence.write("links-nonurl-actions.txt", report.joined(separator: "\n") + "\n")

        XCTAssertEqual(opened, [], "no action may open a URL (JavaScript launchURL and SubmitForm aim at the canary)")
        XCTAssertEqual(digestBefore.0, digestAfter.0, "the file is never written")
        XCTAssertEqual(interceptor.interceptedURLs, [], "none of these is a URL action")
        // Named page navigation is performed by PDFView itself.
        XCTAssertEqual(outcomes["A NextPage"]?.page, 1)
        XCTAssertEqual(outcomes["B LastPage"]?.page, 2)
        XCTAssertEqual(outcomes["A NextPage"]?.policy, .performedByPDFView("named action NextPage"))
        XCTAssertEqual(outcomes["B LastPage"]?.policy, .navigate(pageIndex: 2))
        // /GoToR reaches the delegate, which blocks it; the view stays put.
        XCTAssertEqual(outcomes["F GoToR"]?.decisions, [.blocked(reason: "remote GoTo opens another file")])
        XCTAssertEqual(outcomes["F GoToR"]?.page, 0)
        // Nothing else moves the view.
        for label in ["C Find", "D GoToPage", "E Print", "G ResetForm", "H JavaScript", "I SubmitForm"] {
            XCTAssertEqual(outcomes[label]?.page, 0, label)
        }
    }
}
