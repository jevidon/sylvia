import PDFAnchorKit
import PDFKit
import UIKit
import XCTest

/// Plan 18.1 and brief item 7 for action structures beyond a single /A (actions-chained.pdf). Every URI and JavaScript
/// action in the file aims at the canary scheme except link D's https URI; the other actions are GoTo and Named
/// actions inside the file and a /Launch of /bin/sh. Shapes: /Next chains after GoTo, named and URI actions (one
/// dictionary; an array with a /Launch and a JavaScript action; a two-action cycle); links without /A whose /AA holds
/// mouse-up only, mouse-down and mouse-up in both orders, mouse-down only, or mouse-up and mouse-enter; a link whose
/// /AA declares every annotation trigger; three text fields (merged with its widget and declaring every annotation and
/// field trigger; a separate field dictionary holding the field triggers plus mouse-down, mouse-up, focus and blur; a
/// separate widget holding only mouse-up); page 0's /AA /O (a GoTo to page index 2, then a /Next canary) and /C; the
/// catalog /OpenAction (a GoTo to page index 2, then a /Next canary), the document-level /AA (close, save, print), an
/// outline and a document JavaScript name tree. The open action and page 0's open trigger go to page index 2 so that
/// running either would show: the view would leave page 0 when the file is displayed or when page 0 is shown again
/// (PDFKit ignores /Next, so their /Next canaries alone could not show it). The harness registers the canary scheme,
/// so any canary URL the system opens is recorded (`LinkInterceptionTests` has the control that shows a deliberate open
/// is detected; the controls below show PDFKit's default does open this file's presented /AA and outline actions).
@MainActor
final class ChainedActionTests: XCTestCase {
    static let canary = "sylvia-g01-canary://"
    static let canaryWait: TimeInterval = 3
    static let links = ["A GoTo+Next", "B NextPage+Next", "C GoTo+Next[URI,Launch,JavaScript]", "D https+Next", "E AA U only",
                        "F GoTo+AA every trigger", "G GoTo+Next cycle", "H AA D,U", "I AA U,D", "J AA D only", "K AA U,E",
                        "L canary URI+Next"]
    /// The text fields on page 0, in annotation order: merged; separate field with /AA; separate widget with /AA /U.
    static let fields = ["note", "second", "third"]

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { URLOpenRecorder.shared.reset() }
    }

    func row(_ d: DeclaredAction) -> String { "\(d.location) | \(d.type) | \(d.target ?? "-")" }

    func describe(_ action: PDFAction?) -> String {
        guard let action else { return "no action" }
        return "\(type(of: action)) type \(action.type)" + ((action as? PDFActionURL)?.url.map { " \($0.absoluteString)" } ?? "")
    }

    func makeView(_ source: PDFSourceDocument, delegate: PDFViewDelegate?) -> (UIWindow, PDFView) {
        let window = makeHostWindow()
        let view = PDFView(frame: window.bounds)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.delegate = delegate
        window.rootViewController?.view.addSubview(view)
        view.document = source.document
        view.layoutIfNeeded()
        return (window, view)
    }

    /// Outline items in display order with their position ("1.0" is the first child of the second item).
    func outlineItems(_ document: PDFDocument) -> [(path: String, item: PDFOutline)] {
        var out: [(String, PDFOutline)] = []
        func walk(_ node: PDFOutline, _ path: String) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                let p = path.isEmpty ? "\(i)" : "\(path).\(i)"
                out.append((p, child))
                walk(child, p)
            }
        }
        if let root = document.outlineRoot { walk(root, "") }
        return out
    }

    /// The audit lists the actions of every place it reads: the chained open action, the document triggers, the
    /// JavaScript name tree (through /Kids, with a /Next), the outline (siblings, a child, a /Next), the separate
    /// field dictionary's /AA, the page triggers, each link's /A with its /Next chain (dictionary, array, the cycle
    /// reported once) and /AA, and both widgets' /AA. The merged field is listed once, with its page; the separate
    /// widgets are listed with their page, and field three's dictionary has no action.
    func testAuditListsEveryPlaceItReads() throws {
        let source = try Fixture.open("actions-chained.pdf")
        let rows = PDFActionAudit.audit(source.document).map(row)
        let c = Self.canary
        func js(_ path: String) -> String { "JavaScript | app.launchURL('\(c)\(path)', true);" }
        func uri(_ path: String) -> String { "URI | \(c)\(path)" }
        let triggerNames = ["E": "enter", "X": "exit", "D": "mouse-down", "U": "mouse-up", "Fo": "focus", "Bl": "blur",
                            "PO": "page-open", "PC": "page-close", "PV": "page-visible", "PI": "page-invisible",
                            "K": "keystroke", "F": "format", "V": "validate", "C": "calculate"]
        func trigger(_ prefix: String, _ key: String) -> String {
            let path = prefix + (triggerNames[key] ?? key)
            return ["K", "F", "V", "C"].contains(key) ? js(path) : uri(path)
        }
        var expected = [
            "catalog /OpenAction | GoTo | -",
            "catalog /OpenAction /Next | \(uri("open-action-next"))",
            "catalog /AA /DP | \(uri("doc-did-print"))",
            "catalog /AA /DS | \(uri("doc-did-save"))",
            "catalog /AA /WC | \(uri("doc-will-close"))",
            "catalog /AA /WP | \(uri("doc-will-print"))",
            "catalog /AA /WS | \(uri("doc-will-save"))",
            "catalog /Names /JavaScript [0] | \(js("javascript-tree"))",
            "catalog /Names /JavaScript [0] /Next | \(uri("javascript-tree-next"))",
            "catalog /Names /JavaScript [1] | \(js("javascript-tree-second"))",
            "catalog /Outlines item 0 /A | \(uri("outline-uri"))",
            "catalog /Outlines item 1 /A | GoTo | -",
            "catalog /Outlines item 1 /A /Next | \(uri("outline-next"))",
            "catalog /Outlines item 1.0 /A | \(js("outline-child-javascript"))",
        ]
        expected += ["Bl", "C", "D", "F", "Fo", "K", "U", "V"].map { "catalog /AcroForm field 1 /AA /\($0) | \(trigger("second-field-", $0))" }
        expected += [
            "page 0 /AA /C | \(uri("page-close"))",
            "page 0 /AA /O | GoTo | -",
            "page 0 /AA /O /Next | \(uri("page-open-next"))",
            "page 0 annotation 0 /A | GoTo | -",
            "page 0 annotation 0 /A /Next | \(uri("next-after-goto"))",
            "page 0 annotation 1 /A | Named | -",
            "page 0 annotation 1 /A /Next | \(uri("next-after-named"))",
            "page 0 annotation 2 /A | GoTo | -",
            "page 0 annotation 2 /A /Next[0] | \(uri("next-array"))",
            "page 0 annotation 2 /A /Next[1] | Launch | /bin/sh",
            "page 0 annotation 2 /A /Next[2] | \(js("next-array-javascript"))",
            "page 0 annotation 3 /A | URI | https://example.invalid/chained",
            "page 0 annotation 3 /A /Next | \(uri("next-after-uri"))",
            "page 0 annotation 4 /AA /U | \(uri("aa-mouse-up-only"))",
            "page 0 annotation 5 /A | GoTo | -",
        ]
        expected += ["Bl", "D", "E", "Fo", "PC", "PI", "PO", "PV", "U", "X"].map { "page 0 annotation 5 /AA /\($0) | \(uri("aa-" + $0.lowercased()))" }
        expected += [
            "page 0 annotation 6 /A | GoTo | -",
            "page 0 annotation 6 /A /Next | \(uri("next-cycle"))",
            "page 0 annotation 6 /A /Next /Next | \(PDFActionAudit.cycleMarker) | returns to an action listed above",
            "page 0 annotation 7 /AA /D | \(uri("aa-down-up-d"))",
            "page 0 annotation 7 /AA /U | \(uri("aa-down-up-u"))",
            "page 0 annotation 8 /AA /D | \(uri("aa-up-down-d"))",
            "page 0 annotation 8 /AA /U | \(uri("aa-up-down-u"))",
            "page 0 annotation 9 /AA /D | \(uri("aa-down-only"))",
            "page 0 annotation 10 /AA /E | \(uri("aa-up-enter-e"))",
            "page 0 annotation 10 /AA /U | \(uri("aa-up-enter-u"))",
            "page 0 annotation 11 /A | \(uri("uri-first"))",
            "page 0 annotation 11 /A /Next | \(uri("uri-next"))",
        ]
        expected += ["Bl", "C", "D", "E", "F", "Fo", "K", "PC", "PI", "PO", "PV", "U", "V", "X"].map {
            "page 0 annotation 12 /AA /\($0) | \(trigger("field-", $0))"
        }
        expected.append("page 0 annotation 14 /AA /U | \(uri("third-field-mouse-up"))")
        let declared = rows.filter { !$0.contains(" | (") }.count
        Evidence.write("links-chained-declared.txt", "actions-chained.pdf: declared actions read from the file's dictionaries (PDFActionAudit: "
                       + "open action, document /AA, JavaScript name tree, outline, form fields, page /AA, annotations /A and /AA, every /Next), "
                       + "\(Evidence.environmentLabel)\n\(declared) actions and \(rows.count - declared) marker row(s):\n"
                       + rows.map { "  \($0)" }.joined(separator: "\n") + "\n")
        XCTAssertEqual(rows, expected)
        XCTAssertEqual(declared, 73)
    }

    /// A chain longer than the audit's depth limit (built in memory: 100 GoTo actions, each /Next naming a new one)
    /// is cut and reported, not followed to the end.
    func testAuditCutsAChainPastTheDepthLimit() throws {
        let actions = (0..<100).map { i in "<< /S /GoTo /D [3 0 R /Fit]\(i + 1 < 100 ? " /Next \(5 + i) 0 R" : "") >>" }
        let document = try XCTUnwrap(PDFDocument(data: Self.minimalPDF(actions: actions)), "the in-memory PDF must parse")
        let rows = PDFActionAudit.audit(document)
        let chain = rows.filter { $0.location.hasPrefix("catalog /OpenAction") }
        XCTAssertEqual(chain.count, PDFActionAudit.maximumChainDepth + 1)
        XCTAssertEqual(chain.prefix(PDFActionAudit.maximumChainDepth).map(\.type),
                       Array(repeating: "GoTo", count: PDFActionAudit.maximumChainDepth))
        XCTAssertEqual(chain.last?.type, PDFActionAudit.depthLimitMarker)
    }

    /// A small file whose /Next arrays name the same action twice at each of 30 levels has 2^30 - 1 paths through its
    /// chain (no cycle, within the depth limit). The audit lists `maximumListedActions` rows, then one list-limit row,
    /// and stops; it never walks the paths.
    func testAuditStopsOnAnExponentialNextGraph() throws {
        let depth = 30
        let actions = (0..<depth).map { i in
            "<< /S /GoTo /D [3 0 R /Fit]\(i + 1 < depth ? " /Next [\(5 + i) 0 R \(5 + i) 0 R]" : "") >>"
        }
        let data = Self.minimalPDF(actions: actions)
        let document = try XCTUnwrap(PDFDocument(data: data), "the in-memory PDF must parse")
        let rows = PDFActionAudit.audit(document)
        XCTAssertEqual(rows.count, PDFActionAudit.maximumListedActions + 1)
        XCTAssertEqual(rows.dropLast().map(\.type), Array(repeating: "GoTo", count: PDFActionAudit.maximumListedActions))
        XCTAssertEqual(rows.last?.type, PDFActionAudit.listLimitMarker)
        // Depth first: the first rows walk straight down the first /Next of every level.
        XCTAssertEqual(rows.prefix(depth).map(\.location),
                       (0..<depth).map { "catalog /OpenAction" + String(repeating: " /Next[0]", count: $0) })
        Evidence.write("links-audit-limits.txt", """
            PDFActionAudit limits on in-memory PDFs, \(Evidence.environmentLabel)
            /Next chain of 100 GoTo actions: \(PDFActionAudit.maximumChainDepth) listed, then "\(PDFActionAudit.depthLimitMarker)" (testAuditCutsAChainPastTheDepthLimit)
            /Next arrays naming the same action twice at each of \(depth) levels (\(data.count) bytes, 2^\(depth) - 1 paths): \(rows.count - 1) rows listed, then "\(rows.last?.type ?? "-")": \(rows.last?.target ?? "-")
            cycles and 100-level nesting in the outline, the form field tree and the JavaScript name tree: see links-audit-trees.txt (testAuditStopsAtCyclesAndDepthInTrees)

            """)
    }

    /// The trees the audit walks are bounded like the /Next chains: an outline whose sibling and child links loop, a
    /// form field that is its own grandchild and a name tree whose leaf names the root are each reported once as a
    /// cycle; outline, field and name-tree nesting 100 levels deep is cut at the depth limit. Built in memory.
    func testAuditStopsAtCyclesAndDepthInTrees() throws {
        let cyclic = Self.minimalPDF(catalog: "/Outlines 4 0 R /AcroForm << /Fields [7 0 R] >> /Names << /JavaScript 9 0 R >>", objects: [
            "<< /Type /Outlines /First 5 0 R >>",                                                                   // 4
            "<< /Title (a) /A << /S /URI /URI (\(Self.canary)outline-a) >> /Next 6 0 R >>",                         // 5
            "<< /Title (b) /A << /S /URI /URI (\(Self.canary)outline-b) >> /First 6 0 R /Next 5 0 R >>",            // 6
            "<< /T (f) /AA << /K << /S /JavaScript /JS (keystroke) >> >> /Kids [8 0 R] >>",                          // 7
            "<< /T (g) /A << /S /URI /URI (\(Self.canary)field-g) >> /Kids [7 0 R] >>",                             // 8
            "<< /Kids [10 0 R] >>",                                                                                  // 9
            "<< /Names [(a) << /S /JavaScript /JS (script) >>] /Kids [9 0 R] >>",                                   // 10
        ])
        let document = try XCTUnwrap(PDFDocument(data: cyclic), "the in-memory PDF must parse")
        let rows = PDFActionAudit.audit(document).map(row)
        let marker = PDFActionAudit.cycleMarker
        XCTAssertEqual(rows, [
            "catalog /Names /JavaScript [0] | JavaScript | script",
            "catalog /Names /JavaScript /Kids | \(marker) | reaches a node visited above",
            "catalog /Outlines item 0 /A | URI | \(Self.canary)outline-a",
            "catalog /Outlines item 1 /A | URI | \(Self.canary)outline-b",
            "catalog /Outlines item 1.0 | \(marker) | reaches an item visited above",
            "catalog /Outlines item 2 | \(marker) | reaches an item visited above",
            "catalog /AcroForm field 0 /AA /K | JavaScript | keystroke",
            "catalog /AcroForm field 0.0 /A | URI | \(Self.canary)field-g",
            "catalog /AcroForm field 0.0.0 | \(marker) | reaches a field visited above",
        ])

        // 100 levels of nesting in each tree, without actions: one depth-limit row per tree.
        let levels = 100
        var objects = ["<< /Type /Outlines /First 5 0 R >>"]                                                          // 4
        objects += (0..<levels).map { i in i + 1 < levels ? "<< /Title (x) /First \(6 + i) 0 R >>" : "<< /Title (x) >>" } // 5 ... 104
        let fieldBase = 5 + levels
        objects += (0..<levels).map { i in i + 1 < levels ? "<< /T (x) /Kids [\(fieldBase + i + 1) 0 R] >>" : "<< /T (x) >>" }
        let treeBase = fieldBase + levels
        objects += (0..<levels).map { i in i + 1 < levels ? "<< /Kids [\(treeBase + i + 1) 0 R] >>" : "<< /Names [] >>" }
        let nested = Self.minimalPDF(catalog: "/Outlines 4 0 R /AcroForm << /Fields [\(fieldBase) 0 R] >> /Names << /JavaScript \(treeBase) 0 R >>",
                                     objects: objects)
        let deep = try XCTUnwrap(PDFDocument(data: nested), "the in-memory PDF must parse")
        let deepRows = PDFActionAudit.audit(deep).map(row)
        let path = Array(repeating: "0", count: PDFActionAudit.maximumChainDepth + 1).joined(separator: ".")
        let limit = "\(PDFActionAudit.depthLimitMarker) | not followed past \(PDFActionAudit.maximumChainDepth) levels"
        XCTAssertEqual(deepRows, [
            "catalog /Names /JavaScript /Kids | \(limit)",
            "catalog /Outlines item \(path) | \(limit)",
            "catalog /AcroForm field \(path) | \(limit)",
        ])
        Evidence.write("links-audit-trees.txt", "PDFActionAudit on in-memory PDFs with cyclic and deeply nested trees, \(Evidence.environmentLabel)\n"
                       + "cycles (outline siblings and a child pointing back, a field that is its own grandchild, a name-tree leaf naming the root):\n"
                       + rows.map { "  \($0)" }.joined(separator: "\n")
                       + "\n\(levels) levels of nesting in the outline, the field tree and the name tree (\(nested.count) bytes):\n"
                       + deepRows.map { "  \($0)" }.joined(separator: "\n") + "\n")
    }

    /// Each presented action performed through `PDFView.perform(_:)` with Sylvia's interceptor installed, from page
    /// index 0: every link, every field widget and every outline item. Real taps on the links and fields are
    /// `LinkTapUITests.testChainedAndAdditionalActionTaps`.
    func testChainedAndAdditionalActionsOpenNothing() throws {
        let copy = try Fixture.copy("actions-chained.pdf")
        let digestBefore = try PDFSourceDocument.sha256OfFile(at: copy)
        let source = try PDFSourceDocument.open(url: copy)
        let page0 = try XCTUnwrap(source.page(at: 0))
        let links = page0.annotations.filter { $0.type == "Link" }
        let widgets = page0.annotations.filter { $0.type == "Widget" }
        XCTAssertEqual(links.count, Self.links.count)
        XCTAssertEqual(widgets.map(\.fieldName), Self.fields)
        let items = outlineItems(source.document)

        let interceptor = LinkInterceptor()
        let (window, view) = makeView(source, delegate: interceptor)
        defer { window.isHidden = true }

        var report = ["actions-chained.pdf: PDFView.perform(presented action) with LinkInterceptor installed, starting on page index 0 each time, "
                      + "\(Evidence.environmentLabel)"]
        var outcomes: [String: (presented: String, page: Int, intercepted: [String], decisions: [LinkDecision])] = [:]
        // Page 0's /AA /O is a GoTo to page index 2: had PDFKit run it when page 0 was shown again, the view would have
        // left page 0 before the action was performed.
        var pagesBeforeActions: [Int] = []
        func perform(_ action: PDFAction?, label: String) {
            guard let action else {
                outcomes[label] = ("no action", -1, [], [])
                report.append("\(label): PDFKit presents no action; nothing to perform")
                return
            }
            view.go(to: page0)
            view.layoutIfNeeded()
            spinRunLoop(seconds: 0.2)
            pagesBeforeActions.append(view.currentPage.map { source.index(of: $0) } ?? -1)
            let interceptedBefore = interceptor.interceptedURLs.count
            let decisionsBefore = interceptor.decisions.count
            view.perform(action)
            spinRunLoop(seconds: 0.5)
            let pageAfter = view.currentPage.map { source.index(of: $0) } ?? -1
            let intercepted = interceptor.interceptedURLs.dropFirst(interceptedBefore).map(\.absoluteString)
            let decisions = Array(interceptor.decisions.dropFirst(decisionsBefore))
            outcomes[label] = (describe(action), pageAfter, intercepted, decisions)
            report.append("\(label): PDFKit presents \(describe(action)); page index after: \(pageAfter); "
                          + "URLs reaching the delegate: \(intercepted); delegate decisions: \(decisions)")
        }
        for (label, link) in zip(Self.links, links) { perform(link.action, label: label) }
        for (name, widget) in zip(Self.fields, widgets) { perform(widget.action, label: "field \(name)") }
        for (path, item) in items { perform(item.action, label: "outline \(path) \"\(item.label ?? "")\"") }
        spinRunLoop(seconds: Self.canaryWait)
        let opened = URLOpenRecorder.shared.received.map(\.absoluteString)
        let presented = presentedUI()
        let digestAfter = try PDFSourceDocument.sha256OfFile(at: copy)
        report.append("page index shown after going back to page 0 before each of the \(pagesBeforeActions.count) actions: "
                      + (pagesBeforeActions.allSatisfy { $0 == 0 } ? "0 every time (page 0's /AA /O, a GoTo to page index 2, did not run)" : "\(pagesBeforeActions)"))
        report.append("URLs delivered to the harness after all actions and \(Self.canaryWait) s: \(opened)")
        report.append("presented over the app: \(presented.isEmpty ? "nothing" : presented.joined(separator: ", "))")
        report.append("file SHA-256 before \(digestBefore.0), after \(digestAfter.0)")
        Evidence.write("links-chained-actions.txt", report.joined(separator: "\n") + "\n")

        XCTAssertEqual(pagesBeforeActions, Array(repeating: 0, count: pagesBeforeActions.count),
                       "page 0's open trigger (a GoTo to page index 2) must not run when page 0 is shown")
        XCTAssertEqual(opened, [], "no chained, additional or outline action may open a URL")
        XCTAssertEqual(presented, [], "no action may present anything")
        XCTAssertEqual(digestBefore.0, digestAfter.0, "the file is never written")
        // PDFKit performs the first action and ignores /Next: nothing in a chain reaches the delegate or the system.
        for label in ["A GoTo+Next", "B NextPage+Next", "C GoTo+Next[URI,Launch,JavaScript]", "G GoTo+Next cycle"] {
            XCTAssertEqual(outcomes[label]?.page, 1, label)
            XCTAssertEqual(outcomes[label]?.intercepted, [], "\(label): the /Next action must not run")
            XCTAssertEqual(outcomes[label]?.decisions, [], label)
        }
        // A URI link with a /Next URI: only the first URL reaches Sylvia (https asks; the canary is blocked).
        let https = try XCTUnwrap(URL(string: "https://example.invalid/chained"))
        XCTAssertEqual(outcomes["D https+Next"]?.intercepted, [https.absoluteString])
        XCTAssertEqual(outcomes["D https+Next"]?.decisions, [.askUserBeforeOpening(https)])
        XCTAssertEqual(outcomes["D https+Next"]?.page, 0)
        let blocked = LinkDecision.blocked(reason: "scheme sylvia-g01-canary is not allowed")
        XCTAssertEqual(outcomes["L canary URI+Next"]?.presented, "PDFActionURL type URI \(Self.canary)uri-first")
        XCTAssertEqual(outcomes["L canary URI+Next"]?.intercepted, ["\(Self.canary)uri-first"], "the /Next URI must not run")
        XCTAssertEqual(outcomes["L canary URI+Next"]?.decisions, [blocked])
        // Links without /A: PDFKit presents the /AA mouse-up action as the link's own when /AA is {U} or {U, E}; the
        // URL then reaches the delegate like any link and the policy blocks the canary. With mouse-down in the /AA
        // ({D, U}, {U, D}, {D}) PDFKit presents no action.
        for (label, path) in [("E AA U only", "aa-mouse-up-only"), ("K AA U,E", "aa-up-enter-u")] {
            XCTAssertEqual(outcomes[label]?.presented, "PDFActionURL type URI \(Self.canary)\(path)", label)
            XCTAssertEqual(outcomes[label]?.intercepted, ["\(Self.canary)\(path)"], label)
            XCTAssertEqual(outcomes[label]?.decisions, [blocked], label)
            XCTAssertEqual(outcomes[label]?.page, 0, label)
        }
        for label in ["H AA D,U", "I AA U,D", "J AA D only"] {
            XCTAssertEqual(outcomes[label]?.presented, "no action", label)
        }
        // A link with /A and a full /AA: PDFKit presents /A (GoTo page three); none of the /AA triggers runs.
        XCTAssertEqual(outcomes["F GoTo+AA every trigger"]?.presented, "PDFActionGoTo type GoTo")
        XCTAssertEqual(outcomes["F GoTo+AA every trigger"]?.page, 2)
        XCTAssertEqual(outcomes["F GoTo+AA every trigger"]?.intercepted, [])
        // Fields: no action for the merged widget with every trigger or for the widget whose field dictionary holds
        // the triggers; the separate widget whose /AA holds only mouse-up is presented as a URL action, like link E.
        XCTAssertEqual(outcomes["field note"]?.presented, "no action")
        XCTAssertEqual(outcomes["field second"]?.presented, "no action")
        XCTAssertEqual(outcomes["field third"]?.presented, "PDFActionURL type URI \(Self.canary)third-field-mouse-up")
        XCTAssertEqual(outcomes["field third"]?.intercepted, ["\(Self.canary)third-field-mouse-up"])
        XCTAssertEqual(outcomes["field third"]?.decisions, [blocked])
        // Outline: PDFKit presents each item's /A (a destination-only item as a GoTo); the URI item reaches the
        // delegate and is blocked; the GoTo item navigates without its /Next; the JavaScript child does nothing.
        XCTAssertEqual(items.map(\.path), ["0", "1", "1.0", "2"])
        let outline = items.map { outcomes["outline \($0.path) \"\($0.item.label ?? "")\""] }
        XCTAssertEqual(outline.map { $0?.presented }, ["PDFActionURL type URI \(Self.canary)outline-uri", "PDFActionGoTo type GoTo",
                                                        "PDFAction type JavaScript", "PDFActionGoTo type GoTo"])
        XCTAssertEqual(outline.map { $0?.intercepted }, [["\(Self.canary)outline-uri"], [], [], []])
        XCTAssertEqual(outline.map { $0?.decisions }, [[blocked], [], [], []])
        XCTAssertEqual(outline.map { $0?.page }, [0, 1, 0, 0])
    }

    /// Controls without Sylvia's delegate (PDFKit's default handling), so that the results above describe PDFKit and
    /// not only Sylvia's interceptor. Displaying the file, changing pages and setting the three fields open nothing,
    /// and the view stays on the page it was given: the open action and page 0's open trigger (each a GoTo to page
    /// index 2) do not run. Links A, B, C and L and the GoTo outline item run their first action and nothing named by
    /// /Next. The presented /AA mouse-up actions (links E and K, field three's widget) and the outline's URI item are
    /// opened by PDFKit's default: those are live paths, and the interceptor is what stops them above. Closing the file
    /// opens nothing more. Not performed here: link D (its https URL would open Safari) and the cycle G (no /Next runs,
    /// as A, B, C and L show).
    func testControlsWithoutInterceptorPDFKitIgnoresNextButOpensPresentedActions() throws {
        let source = try Fixture.open("actions-chained.pdf")
        let page0 = try XCTUnwrap(source.page(at: 0))
        let links = page0.annotations.filter { $0.type == "Link" }
        let widgets = page0.annotations.filter { $0.type == "Widget" }
        XCTAssertEqual(links.count, Self.links.count)
        XCTAssertEqual(widgets.map(\.fieldName), Self.fields)
        let items = outlineItems(source.document)
        let (window, view) = makeView(source, delegate: nil)
        defer { window.isHidden = true }

        var report = ["actions-chained.pdf: control without LinkInterceptor (PDFKit's default), \(Evidence.environmentLabel)"]
        spinRunLoop(seconds: 1)
        let pageAfterDisplay = view.currentPage.map { source.index(of: $0) } ?? -1
        var pagesShown: [Int] = []
        for index in [1, 2, 0, 1, 0] {
            view.go(to: try XCTUnwrap(source.page(at: index)))
            view.layoutIfNeeded()
            spinRunLoop(seconds: 0.3)
            pagesShown.append(view.currentPage.map { source.index(of: $0) } ?? -1)
        }
        for (widget, value) in zip(widgets, ["Edited one", "Edited two", "Edited three"]) { widget.widgetStringValue = value }
        spinRunLoop(seconds: Self.canaryWait)
        let pageAfterWait = view.currentPage.map { source.index(of: $0) } ?? -1
        let afterDisplay = URLOpenRecorder.shared.received.map(\.absoluteString)
        report.append("displayed: page index \(pageAfterDisplay) after 1 s (the open action is a GoTo to page index 2); then pages 1, 2, 0, 1, 0 "
                      + "requested, page index shown after each: \(pagesShown) (page 0's /AA /O is a GoTo to page index 2); the three fields set in memory; "
                      + "after \(Self.canaryWait) s: page index \(pageAfterWait), URLs delivered to the harness: \(afterDisplay)")

        var pages: [String: Int] = [:]
        var pagesBeforeActions: [Int] = []
        func perform(_ action: PDFAction, label: String, expecting canary: String?) {
            view.go(to: page0)
            view.layoutIfNeeded()
            spinRunLoop(seconds: 0.2)
            pagesBeforeActions.append(view.currentPage.map { source.index(of: $0) } ?? -1)
            view.perform(action)
            if let canary, let url = URL(string: Self.canary + canary) {
                _ = waitUntil(timeout: 10) { URLOpenRecorder.shared.received.contains(url) }
            }
            spinRunLoop(seconds: Self.canaryWait)
            pages[label] = view.currentPage.map { source.index(of: $0) } ?? -1
            report.append("\(label): PDFView.perform from page index 0; page index after: \(pages[label] ?? -1); "
                          + "URLs delivered to the harness so far: \(URLOpenRecorder.shared.received.map(\.absoluteString))")
        }
        let linkAction = { (label: String) throws -> PDFAction in
            let index = try XCTUnwrap(Self.links.firstIndex(of: label))
            return try XCTUnwrap(links[index].action, label)
        }
        for label in ["A GoTo+Next", "B NextPage+Next", "C GoTo+Next[URI,Launch,JavaScript]"] {
            perform(try linkAction(label), label: label, expecting: nil)
        }
        let afterChains = URLOpenRecorder.shared.received.map(\.absoluteString)
        perform(try linkAction("L canary URI+Next"), label: "L canary URI+Next", expecting: "uri-first")
        perform(try linkAction("E AA U only"), label: "E AA U only", expecting: "aa-mouse-up-only")
        perform(try linkAction("K AA U,E"), label: "K AA U,E", expecting: "aa-up-enter-u")
        perform(try XCTUnwrap(widgets[2].action, "field third"), label: "field third", expecting: "third-field-mouse-up")
        XCTAssertEqual(items.map(\.path), ["0", "1", "1.0", "2"])
        perform(try XCTUnwrap(items[0].item.action), label: "outline 0 (URI)", expecting: "outline-uri")
        perform(try XCTUnwrap(items[1].item.action), label: "outline 1 (GoTo + /Next)", expecting: nil)
        perform(try XCTUnwrap(items[2].item.action), label: "outline 1.0 (JavaScript)", expecting: nil)
        let beforeClose = URLOpenRecorder.shared.received.map(\.absoluteString)
        view.document = nil
        view.layoutIfNeeded()
        spinRunLoop(seconds: Self.canaryWait)
        let afterClose = URLOpenRecorder.shared.received.map(\.absoluteString)
        report.append("page index shown after going back to page 0 before each performed action: \(pagesBeforeActions)")
        report.append("document removed from the view: URLs delivered to the harness after \(Self.canaryWait) s: \(afterClose)")
        Evidence.write("links-chained-control-no-interceptor.txt", report.joined(separator: "\n") + "\n")

        XCTAssertEqual(pageAfterDisplay, 0, "PDFKit itself does not run the open action (a GoTo to page index 2)")
        XCTAssertEqual(pagesShown, [1, 2, 0, 1, 0], "PDFKit itself does not run page 0's open trigger (a GoTo to page index 2)")
        XCTAssertEqual(pageAfterWait, 0)
        XCTAssertEqual(pagesBeforeActions, Array(repeating: 0, count: pagesBeforeActions.count))
        XCTAssertEqual(afterDisplay, [], "PDFKit itself runs no open, page or field action")
        XCTAssertEqual(pages["A GoTo+Next"], 1)
        XCTAssertEqual(pages["B NextPage+Next"], 1)
        XCTAssertEqual(pages["C GoTo+Next[URI,Launch,JavaScript]"], 1)
        XCTAssertEqual(pages["outline 1 (GoTo + /Next)"], 1)
        XCTAssertEqual(afterChains, [], "PDFKit itself performs none of the /Next actions")
        // Exactly the first action of each performed URL action, in order: never a /Next URL, never the JavaScript.
        let expected = ["uri-first", "aa-mouse-up-only", "aa-up-enter-u", "third-field-mouse-up", "outline-uri"].map { Self.canary + $0 }
        XCTAssertEqual(beforeClose, expected, "control: PDFKit's default opens the presented URL actions and nothing else")
        XCTAssertEqual(afterClose, expected, "closing the file opens nothing more")
    }

    /// Displaying the document, moving between pages (page /AA /O and /C, annotation /PO, /PV, /PC, /PI), setting all
    /// three fields' values in memory and closing the document (removing it from the view, as the reader does when it
    /// opens another file; document /AA /WC) runs none of the chained or additional actions. The open action and page
    /// 0's open trigger are GoTo actions to page index 2, so their not running is seen as the view staying on the page
    /// it was given. Sylvia never saves or prints a PDF, so the save and print triggers have no event to run on.
    func testDisplayingEditingAndClosingRunNoAdditionalAction() throws {
        let source = try Fixture.open("actions-chained.pdf")
        let interceptor = LinkInterceptor()
        let (window, view) = makeView(source, delegate: interceptor)
        defer { window.isHidden = true }
        spinRunLoop(seconds: 1)
        let pageAfterDisplay = view.currentPage.map { source.index(of: $0) } ?? -1
        var pagesShown: [Int] = []
        for index in [1, 2, 0, 1, 0] {
            view.go(to: try XCTUnwrap(source.page(at: index)))
            view.layoutIfNeeded()
            spinRunLoop(seconds: 0.3)
            pagesShown.append(view.currentPage.map { source.index(of: $0) } ?? -1)
        }
        let widgets = try XCTUnwrap(source.page(at: 0)).annotations.filter { $0.type == "Widget" }
        XCTAssertEqual(widgets.map(\.fieldName), Self.fields)
        for (widget, value) in zip(widgets, ["Edited one", "Edited two", "Edited three"]) { widget.widgetStringValue = value }
        spinRunLoop(seconds: 0.5)
        let pageBeforeClose = view.currentPage.map { source.index(of: $0) } ?? -1
        view.document = nil
        view.layoutIfNeeded()
        spinRunLoop(seconds: Self.canaryWait)
        let opened = URLOpenRecorder.shared.received.map(\.absoluteString)
        let presented = presentedUI()
        Evidence.write("links-chained-open-actions.txt",
                       "Displaying actions-chained.pdf (catalog /OpenAction: a GoTo to page index 2 + /Next canary; document /AA close, save and print "
                       + "canaries; page 0 /AA /O: a GoTo to page index 2 + /Next canary, and /C canary; link /AA with every trigger; three text fields "
                       + "with /AA in the widget, the field dictionary or both) with page changes 1, 2, 0, 1, 0, the three fields set in memory, then "
                       + "the document removed from the view, then \(Self.canaryWait) s, \(Evidence.environmentLabel)\n"
                       + "page index 1 s after display: \(pageAfterDisplay); page index shown after each requested page change: \(pagesShown); "
                       + "page index before closing: \(pageBeforeClose)\n"
                       + "URLs delivered to the harness: \(opened); URLs reaching the delegate: \(interceptor.interceptedURLs.map(\.absoluteString)); "
                       + "delegate decisions: \(interceptor.decisions); presented over the app: \(presented.isEmpty ? "nothing" : presented.joined(separator: ", "))\n")
        XCTAssertEqual(pageAfterDisplay, 0, "the open action (a GoTo to page index 2) must not run")
        XCTAssertEqual(pagesShown, [1, 2, 0, 1, 0], "page 0's open trigger (a GoTo to page index 2) must not run")
        XCTAssertEqual(pageBeforeClose, 0)
        XCTAssertEqual(opened, [], "no open, page, field or close action may open anything")
        XCTAssertEqual(interceptor.interceptedURLs, [], "nothing is even attempted without a tap")
        XCTAssertEqual(interceptor.decisions, [])
        XCTAssertEqual(presented, [])
    }

    /// A one-page PDF whose catalog /OpenAction is object 4, followed by the given action objects (numbered from 4,
    /// so an action can name the next one as `5 0 R` and so on). Built here so the committed fixtures stay small.
    static func minimalPDF(actions: [String]) -> Data {
        minimalPDF(catalog: "/OpenAction 4 0 R", objects: actions)
    }

    /// A one-page PDF: object 1 is the catalog (with `catalog` added to its entries), 2 the page tree, 3 the page,
    /// and `objects` are numbered from 4.
    static func minimalPDF(catalog: String, objects extra: [String]) -> Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R \(catalog) >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 612 792] >>",
            "<< /Type /Page /Parent 2 0 R /Resources << >> >>",
        ] + extra
        var out = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { out += String(format: "%010d 00000 n \n", offset) }
        out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }
}
