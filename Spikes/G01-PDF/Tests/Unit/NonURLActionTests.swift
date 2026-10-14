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
        var outcomes: [String: (page: Int, decisions: [LinkDecision], policy: LinkDecision, fieldBefore: String, fieldAfter: String,
                                presented: [String])] = [:]
        let initialField = field.widgetStringValue
        XCTAssertEqual(presentedUI(), [], "nothing is presented before the first action")
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
            let fieldAfter = field.widgetStringValue ?? "nil"
            let presented = presentedUI()
            outcomes[label] = (pageAfter, decisions, policy, fieldBefore, fieldAfter, presented)
            report.append("\(label): PDFKit presents \(type(of: action)) type \(action.type)\((action as? PDFActionNamed).map { " name \(LinkPolicy.name(of: $0.name))" } ?? ""); "
                          + "page index after: \(pageAfter); delegate decisions: \(decisions); policy: \(policy); "
                          + "form field \"\(fieldBefore)\" -> \"\(fieldAfter)\"; presented: \(presented.isEmpty ? "nothing" : presented.joined(separator: ", "))")
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
        // Named Find and GoToPage reach Sylvia's delegate, which records them as blocked and does nothing else.
        XCTAssertEqual(outcomes["C Find"]?.decisions, [.blocked(reason: "named action Find is not supported")])
        XCTAssertEqual(outcomes["D GoToPage"]?.decisions, [.blocked(reason: "named action GoToPage is not supported")])
        // PDFView performs NextPage, LastPage and ResetForm itself, and Print, JavaScript and SubmitForm do nothing:
        // none of them reaches the delegate.
        for label in ["A NextPage", "B LastPage", "E Print", "G ResetForm", "H JavaScript", "I SubmitForm"] {
            XCTAssertEqual(outcomes[label]?.decisions, [], "\(label) must not reach the delegate")
        }
        // ResetForm changes the in-memory field value from its /V to its /DV; no other action touches the field.
        XCTAssertEqual(initialField, "Filled in", "the fixture's field starts at its /V value")
        for label in ["A NextPage", "B LastPage", "C Find", "D GoToPage", "E Print", "F GoToR"] {
            XCTAssertEqual(outcomes[label]?.fieldBefore, "Filled in", label)
            XCTAssertEqual(outcomes[label]?.fieldAfter, "Filled in", "\(label) must not change the field")
        }
        XCTAssertEqual(outcomes["G ResetForm"]?.fieldBefore, "Filled in")
        XCTAssertEqual(outcomes["G ResetForm"]?.fieldAfter, "Default", "ResetForm resets the field to its /DV in memory")
        // H and I run after the reset, so the field holds "Default" before and after each of them.
        for label in ["H JavaScript", "I SubmitForm"] {
            XCTAssertEqual(outcomes[label]?.fieldBefore, "Default", label)
            XCTAssertEqual(outcomes[label]?.fieldAfter, "Default", "\(label) must not change the field")
        }
        // No action presents anything: no print sheet for Print, no find or page-number UI for Find and GoToPage.
        for label in Self.labels {
            XCTAssertEqual(outcomes[label]?.presented, [], "\(label) must not present anything")
        }
        // Print, JavaScript and SubmitForm do nothing at all: no page change, no delegate call, no field change, nothing
        // presented and no URL (all asserted above). The policy states the same outcome for each.
        XCTAssertEqual(outcomes["E Print"]?.policy, .blocked(reason: "named action Print is not supported"))
        XCTAssertEqual(outcomes["H JavaScript"]?.policy, .blocked(reason: "action type JavaScript is not supported"))
        XCTAssertEqual(outcomes["I SubmitForm"]?.policy, .blocked(reason: "action type SubmitForm is not supported"))
        XCTAssertEqual(outcomes["G ResetForm"]?.policy, .performedByPDFView("form reset (in memory)"))
    }

    /// Control for the "nothing presented" assertions here and in `ChainedActionTests`: `presentedUI()` does report a
    /// view controller presented over a window of the app and a print job handed to the shared print controller, and
    /// reports nothing again once they are gone. Without this, an empty result could mean a detector that never sees
    /// anything.
    func testControlPresentedUIDetectorSeesAnAlertAndAPrintJob() throws {
        var lines = ["presentedUI() control, \(Evidence.environmentLabel)"]
        let baseline = presentedUI()
        lines.append("baseline: \(baseline)")
        XCTAssertEqual(baseline, [], "nothing is presented before the control")

        let window = makeHostWindow()
        defer { window.isHidden = true }
        let alert = UIAlertController(title: "Control", message: nil, preferredStyle: .alert)
        window.rootViewController?.present(alert, animated: false)
        XCTAssertTrue(waitUntil(timeout: 5) { presentedUI() == ["UIAlertController"] }, "\(presentedUI())")
        lines.append("with a UIAlertController presented over a window of the app: \(presentedUI())")
        alert.dismiss(animated: false)
        XCTAssertTrue(waitUntil(timeout: 5) { presentedUI().isEmpty }, "\(presentedUI())")
        lines.append("after dismissing it: \(presentedUI())")

        let printer = UIPrintInteractionController.shared
        printer.printingItem = Fixture.url("actions-nonurl.pdf")
        let withPrintJob = presentedUI()
        lines.append("with UIPrintInteractionController.shared.printingItem set to a PDF: \(withPrintJob)")
        XCTAssertEqual(withPrintJob, ["UIPrintInteractionController has a print job"])
        printer.printingItem = nil
        let cleared = presentedUI()
        lines.append("after clearing the print job: \(cleared)")
        XCTAssertEqual(cleared, [])
        Evidence.write("presented-ui-control.txt", lines.joined(separator: "\n") + "\n")
    }
}
