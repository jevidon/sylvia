import CoreGraphics
import Foundation
import PDFKit

/// What Sylvia does with a link or action from a PDF (plan 18.1: publications are untrusted; external-link opening
/// is an explicit user action; no launch actions; no unsolicited URLs).
public enum LinkDecision: Equatable, Sendable {
    /// Move to a page in the same document (internal GoTo or a named navigation action).
    case navigate(pageIndex: Int)
    /// A web or mail link. Sylvia shows the full URL and opens it only if the user then confirms. Never automatic.
    case askUserBeforeOpening(URL)
    /// Never performed. The reason is for diagnostics, not for display.
    case blocked(reason: String)
    /// PDFView performs it itself and gives Sylvia no hook (relative named navigation, zoom, form reset). These stay
    /// inside the view: they change the page, the scale or in-memory form values, never the file, and never open
    /// anything. Recorded so the policy says what actually happens (`NonURLActionTests`).
    case performedByPDFView(String)
}

/// Sylvia's decision for every kind of action a PDF can carry. Where the reader enforces it: URL actions (including
/// /Launch, which PDFKit presents as a `file:` URL), /GoToR and the named Find and GoToPage actions reach
/// `LinkInterceptor` through `PDFViewDelegate` and are decided here; internal GoTo, the other named actions and
/// ResetForm are performed by PDFView itself, so for them this function describes PDFKit's behaviour (observed in
/// `NonURLActionTests` and `LinkTapUITests` for GoTo, NextPage, LastPage and ResetForm) rather than a choice Sylvia
/// makes. JavaScript, SubmitForm and Print reach neither the delegate nor anything else on iOS.
public enum LinkPolicy {
    /// Schemes Sylvia may offer to open after the user confirms. Everything else is blocked: custom app schemes,
    /// `javascript:`, scheme-less strings and `file:` (PDFKit presents a /Launch action as a URL action whose URL is
    /// the launch file resolved against the PDF's location, so a launch arrives here as a `file:` URL).
    public static let confirmableSchemes: Set<String> = ["http", "https", "mailto"]

    public static func decide(url: URL) -> LinkDecision {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return .blocked(reason: "no scheme")
        }
        guard confirmableSchemes.contains(scheme) else { return .blocked(reason: "scheme \(scheme) is not allowed") }
        return .askUserBeforeOpening(url)
    }

    public static func decide(action: PDFAction, in document: PDFDocument) -> LinkDecision {
        if let goTo = action as? PDFActionGoTo {
            guard let page = goTo.destination.page else { return .blocked(reason: "GoTo without a page") }
            let index = document.index(for: page)
            guard index != NSNotFound else { return .blocked(reason: "GoTo to a page outside this document") }
            return .navigate(pageIndex: index)
        }
        if let named = action as? PDFActionNamed {
            return decide(named: named.name, document: document)
        }
        if let link = action as? PDFActionURL {
            guard let url = link.url else { return .blocked(reason: "URL action without a URL") }
            return decide(url: url)
        }
        if action is PDFActionRemoteGoTo { return .blocked(reason: "remote GoTo opens another file") }
        if action is PDFActionResetForm { return .performedByPDFView("form reset (in memory)") }
        return .blocked(reason: "action type \(action.type) is not supported")
    }

    static func decide(named: PDFActionNamedName, document: PDFDocument) -> LinkDecision {
        switch named {
        case .firstPage: return .navigate(pageIndex: 0)
        case .lastPage: return .navigate(pageIndex: max(0, document.pageCount - 1))
        // Relative to the view's current page or history, performed by PDFView itself. Observed for NextPage
        // (`links-nonurl-actions.txt`); the others are not in the fixture and are assumed to behave the same way.
        case .nextPage, .previousPage, .goBack, .goForward, .zoomIn, .zoomOut:
            return .performedByPDFView("named action \(name(of: named))")
        // Delivered to the delegate (Find, GoToPage) or not handled by PDFView on iOS (Print): Sylvia does nothing.
        default: return .blocked(reason: "named action \(name(of: named)) is not supported")
        }
    }

    /// The PDF name of a named action (ISO 32000-1 12.6.4.11 plus the Acrobat names PDFKit maps).
    public static func name(of named: PDFActionNamedName) -> String {
        switch named {
        case .nextPage: return "NextPage"
        case .previousPage: return "PrevPage"
        case .firstPage: return "FirstPage"
        case .lastPage: return "LastPage"
        case .goBack: return "GoBack"
        case .goForward: return "GoForward"
        case .goToPage: return "GoToPage"
        case .find: return "Find"
        case .print: return "Print"
        case .zoomIn: return "ZoomIn"
        case .zoomOut: return "ZoomOut"
        case .none: return "none"
        @unknown default: return "named \(named.rawValue)"
        }
    }
}

/// PDFView delegate that receives every URL-link activation instead of PDFKit's default (which opens the URL), and the
/// /GoToR, Find and GoToPage actions PDFView hands to its delegate. It never opens or performs anything itself: it
/// records the request and hands Sylvia's decision to `onDecision`.
///
/// Also arriving here, as observed on iOS 26.5 for the shapes in actions-chained.pdf (`ChainedActionTests`, with
/// controls without the delegate): for an annotation without /A, PDFKit can present the mouse-up (/U) action of its
/// /AA as the annotation's own action, and a URL action presented that way reaches `pdfViewWillClick` like any link.
/// It did so for links whose /AA is {U} or {U, E} and for a field widget whose /AA is {U}. It presented no action for
/// links whose /AA also or only holds mouse-down ({D, U}, {U, D}, {D}), for a widget whose /AA declares every trigger,
/// or for a widget whose field dictionary holds the triggers. An outline item's URI action is presented the same way
/// (`PDFOutline.action`). PDFKit performed no action named by /Next in any shape tested.
@MainActor
public final class LinkInterceptor: NSObject, @MainActor PDFViewDelegate {
    public private(set) var interceptedURLs: [URL] = []
    public private(set) var decisions: [LinkDecision] = []
    public var onDecision: ((LinkDecision) -> Void)?

    override public init() {
        super.init()
    }

    public func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
        interceptedURLs.append(url)
        record(LinkPolicy.decide(url: url))
    }

    /// PDFKit's default "simply beeps"; Sylvia does not open other files from a PDF.
    public func pdfViewOpenPDF(_ sender: PDFView, forRemoteGoToAction action: PDFActionRemoteGoTo) {
        record(LinkPolicy.decide(action: action, in: sender.document ?? PDFDocument()))
    }

    public func pdfViewPerformFind(_ sender: PDFView) {
        record(LinkPolicy.decide(named: .find, document: sender.document ?? PDFDocument()))
    }

    public func pdfViewPerformGo(toPage sender: PDFView) {
        record(LinkPolicy.decide(named: .goToPage, document: sender.document ?? PDFDocument()))
    }

    private func record(_ decision: LinkDecision) {
        decisions.append(decision)
        onDecision?(decision)
    }
}

/// An action a PDF declares, read from the file's own dictionaries (not from PDFKit's action objects, which
/// re-type some actions: PDFKit presents a /Launch action as a URL action). Used for diagnostics and tests.
public struct DeclaredAction: Hashable, Sendable, CustomStringConvertible {
    /// Where it was found: "catalog /OpenAction", "catalog /Names /JavaScript [0]", "catalog /Outlines item 1.0 /A",
    /// "catalog /AcroForm field 1 /AA /K", "page 0 /AA /O", "page 0 annotation 2 /A", "page 0 annotation 4 /AA /U",
    /// "page 0 annotation 0 /A /Next", "page 0 annotation 2 /A /Next[1]".
    public var location: String
    /// The PDF /S value: URI, Launch, GoTo, JavaScript, ... A chain or tree the audit stopped following is reported
    /// with the type `PDFActionAudit.cycleMarker`, `PDFActionAudit.depthLimitMarker` or
    /// `PDFActionAudit.listLimitMarker`.
    public var type: String
    /// URI, launch file, or a short summary.
    public var target: String?

    public init(location: String, type: String, target: String?) {
        self.location = location
        self.type = type
        self.target = target
    }

    public var description: String { "\(location): \(type.hasPrefix("(") ? type : "/" + type) \(target ?? "")" }
}

/// Lists, for diagnostics, the actions a PDF declares in the places listed below, read from the file's own
/// dictionaries. It never performs anything, and the reader's safety does not depend on it (`LinkInterceptor` and
/// PDFKit's own behaviour do; `ChainedActionTests`). The places, in this order:
///
/// 1. the catalog's /OpenAction (an action, or a destination array, listed as "destination") and its /AA (every key);
/// 2. every entry of the document-level JavaScript name tree (/Names /JavaScript), following /Kids;
/// 3. every item of the document outline (/Outlines), following /First and /Next: its /A;
/// 4. every interactive form field (/AcroForm /Fields), following /Kids: its /A and /AA, except a field dictionary that
///    is also an annotation of a page (a field merged with its widget), whose actions are listed with that page;
/// 5. each page's /AA (every key), and each annotation in the page's /Annots: its /A and /AA (every key), for links,
///    widgets and any other subtype.
///
/// It does not read: XFA form scripts (/AcroForm /XFA), presentation steps (a page's /PresSteps navigation nodes and
/// their /NA and /PA actions), a link annotation's /PA (a URI action kept for Web Capture), scripts held in the media,
/// rich-media or 3D dictionaries of annotations rather than in /A or /AA, files embedded in the PDF, and any action in
/// an object that none of the places above refers to.
///
/// Each action's /Next is followed, whether it is one dictionary or an array, so a chained action is listed after the
/// one that names it. A /Next that returns to an action already on the current chain is reported once as a cycle and
/// not followed again; chains deeper than `maximumChainDepth` are cut and reported. A name-tree node, outline item or
/// form field reached a second time (a cycle or a shared node) is reported once and not followed again, and those
/// trees are not followed deeper than `maximumChainDepth` levels. A /Next array may name the same action several
/// times at every level, so the number of paths through a small file can grow exponentially with the chain's depth;
/// the whole audit therefore stops after `maximumListedActions` rows and says so.
public enum PDFActionAudit {
    public static let cycleMarker = "(cycle)"
    public static let depthLimitMarker = "(depth limit)"
    public static let listLimitMarker = "(list limit)"
    /// A hostile file can chain thousands of actions; the audit stops following a chain past this depth.
    public static let maximumChainDepth = 64
    /// The most rows one audit lists before it stops (`listLimitMarker`), whatever the file's shape.
    public static let maximumListedActions = 4096

    /// The rows of one audit, cut after `maximumListedActions` with one `listLimitMarker` row.
    struct Rows {
        private(set) var items: [DeclaredAction] = []
        private(set) var isFull = false

        mutating func append(_ row: DeclaredAction) {
            guard !isFull else { return }
            guard items.count < PDFActionAudit.maximumListedActions else {
                items.append(DeclaredAction(location: row.location, type: PDFActionAudit.listLimitMarker,
                                            target: "nothing listed after \(PDFActionAudit.maximumListedActions) rows"))
                isFull = true
                return
            }
            items.append(row)
        }
    }

    public static func audit(_ document: PDFDocument) -> [DeclaredAction] {
        var rows = Rows()
        // Page dictionaries straight from the CGPDFDocument, so the audit never instantiates PDFKit's page objects.
        guard let file = document.documentRef else { return [] }
        let pages = (0..<file.numberOfPages).map { file.page(at: $0 + 1)?.dictionary }
        // Annotations that a page lists: a form field merged with its widget is listed with its page, not again with
        // the form. CGPDFDocument hands out one dictionary reference per indirect object, so identity is enough.
        var pageAnnotations = Set<CGPDFDictionaryRef>()
        for dict in pages.compactMap({ $0 }) {
            for annot in dictionaries(in: dict, "Annots") { pageAnnotations.insert(annot) }
        }
        if let catalog = file.catalog {
            var openAction: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(catalog, "OpenAction", &openAction), let openAction {
                actions(in: openAction, location: "catalog /OpenAction", into: &rows)
            }
            var openArray: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(catalog, "OpenAction", &openArray), openArray != nil {
                rows.append(DeclaredAction(location: "catalog /OpenAction", type: "destination", target: nil))
            }
            additionalActions(in: catalog, location: "catalog", into: &rows)
            var names: CGPDFDictionaryRef?
            var javaScript: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names,
               CGPDFDictionaryGetDictionary(names, "JavaScript", &javaScript), let javaScript
            {
                var visited = Set<CGPDFDictionaryRef>()
                var entries = 0
                nameTreeActions(javaScript, location: "catalog /Names /JavaScript", depth: 0, entries: &entries,
                                visited: &visited, into: &rows)
            }
            var outlines: CGPDFDictionaryRef?
            var first: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(catalog, "Outlines", &outlines), let outlines,
               CGPDFDictionaryGetDictionary(outlines, "First", &first), let first
            {
                var visited: Set<CGPDFDictionaryRef> = [outlines]
                outlineActions(first: first, path: "", depth: 0, visited: &visited, into: &rows)
            }
            var form: CGPDFDictionaryRef?
            var fields: CGPDFArrayRef?
            if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form,
               CGPDFDictionaryGetArray(form, "Fields", &fields), let fields
            {
                var visited = Set<CGPDFDictionaryRef>()
                fieldActions(fields, path: "", depth: 0, pageAnnotations: pageAnnotations, visited: &visited, into: &rows)
            }
        }
        for (index, dict) in pages.enumerated() where !rows.isFull {
            guard let dict else { continue }
            additionalActions(in: dict, location: "page \(index)", into: &rows)
            var annots: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(dict, "Annots", &annots), let annots else { continue }
            for i in 0..<CGPDFArrayGetCount(annots) where !rows.isFull {
                var annot: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(annots, i, &annot), let annot else { continue }
                var a: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(annot, "A", &a), let a {
                    actions(in: a, location: "page \(index) annotation \(i) /A", into: &rows)
                }
                additionalActions(in: annot, location: "page \(index) annotation \(i)", into: &rows)
            }
        }
        return rows.items
    }

    /// The dictionaries in an array-valued key (entries that are not dictionaries are skipped).
    static func dictionaries(in dict: CGPDFDictionaryRef, _ key: String) -> [CGPDFDictionaryRef] {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, key, &array), let array else { return [] }
        return (0..<CGPDFArrayGetCount(array)).compactMap { i in
            var item: CGPDFDictionaryRef?
            return CGPDFArrayGetDictionary(array, i, &item) ? item : nil
        }
    }

    /// The action of every entry of a name tree whose values are actions (ISO 32000-1 7.9.6: a node has /Kids, or
    /// /Names holding key and value pairs). Entries are numbered in tree order: "catalog /Names /JavaScript [0]".
    static func nameTreeActions(_ node: CGPDFDictionaryRef, location: String, depth: Int, entries: inout Int,
                                visited: inout Set<CGPDFDictionaryRef>, into rows: inout Rows) {
        guard !rows.isFull else { return }
        guard visited.insert(node).inserted else {
            rows.append(DeclaredAction(location: "\(location) /Kids", type: cycleMarker, target: "reaches a node visited above"))
            return
        }
        guard depth < maximumChainDepth else {
            rows.append(DeclaredAction(location: "\(location) /Kids", type: depthLimitMarker,
                                       target: "not followed past \(maximumChainDepth) levels"))
            return
        }
        var pairs: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &pairs), let pairs {
            var i = 1
            while i < CGPDFArrayGetCount(pairs), !rows.isFull {
                var action: CGPDFDictionaryRef?
                let entry = "\(location) [\(entries)]"
                if CGPDFArrayGetDictionary(pairs, i, &action), let action {
                    actions(in: action, location: entry, into: &rows)
                } else {
                    rows.append(DeclaredAction(location: entry, type: "(not a dictionary)", target: nil))
                }
                entries += 1
                i += 2
            }
        }
        for kid in dictionaries(in: node, "Kids") where !rows.isFull {
            nameTreeActions(kid, location: location, depth: depth + 1, entries: &entries, visited: &visited, into: &rows)
        }
    }

    /// The /A of every outline item, from `first` along its /Next siblings and into each item's /First children.
    /// Items are named by position: "catalog /Outlines item 1.0" is the first child of the second top-level item.
    static func outlineActions(first: CGPDFDictionaryRef, path: String, depth: Int, visited: inout Set<CGPDFDictionaryRef>,
                               into rows: inout Rows) {
        guard depth < maximumChainDepth else {
            rows.append(DeclaredAction(location: "catalog /Outlines item \(path)0", type: depthLimitMarker,
                                       target: "not followed past \(maximumChainDepth) levels"))
            return
        }
        var item: CGPDFDictionaryRef? = first
        var index = 0
        while let current = item, !rows.isFull {
            let location = "catalog /Outlines item \(path)\(index)"
            guard visited.insert(current).inserted else {
                rows.append(DeclaredAction(location: location, type: cycleMarker, target: "reaches an item visited above"))
                return
            }
            var a: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "A", &a), let a {
                actions(in: a, location: "\(location) /A", into: &rows)
            }
            var child: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "First", &child), let child {
                outlineActions(first: child, path: "\(path)\(index).", depth: depth + 1, visited: &visited, into: &rows)
            }
            var next: CGPDFDictionaryRef?
            item = CGPDFDictionaryGetDictionary(current, "Next", &next) ? next : nil
            index += 1
        }
    }

    /// The /A and /AA of every form field in `fields` and, recursively, in each field's /Kids, except a dictionary
    /// that a page lists as an annotation (a field merged with its widget): the page listing covers it. Fields are
    /// named by position: "catalog /AcroForm field 1.0" is the first kid of the second field.
    static func fieldActions(_ fields: CGPDFArrayRef, path: String, depth: Int, pageAnnotations: Set<CGPDFDictionaryRef>,
                             visited: inout Set<CGPDFDictionaryRef>, into rows: inout Rows) {
        guard depth < maximumChainDepth else {
            rows.append(DeclaredAction(location: "catalog /AcroForm field \(path)0", type: depthLimitMarker,
                                       target: "not followed past \(maximumChainDepth) levels"))
            return
        }
        for i in 0..<CGPDFArrayGetCount(fields) where !rows.isFull {
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, i, &field), let field else { continue }
            let location = "catalog /AcroForm field \(path)\(i)"
            guard visited.insert(field).inserted else {
                rows.append(DeclaredAction(location: location, type: cycleMarker, target: "reaches a field visited above"))
                continue
            }
            if !pageAnnotations.contains(field) {
                var a: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(field, "A", &a), let a {
                    actions(in: a, location: "\(location) /A", into: &rows)
                }
                additionalActions(in: field, location: location, into: &rows)
            }
            var kids: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(field, "Kids", &kids), let kids {
                fieldActions(kids, path: "\(path)\(i).", depth: depth + 1, pageAnnotations: pageAnnotations,
                             visited: &visited, into: &rows)
            }
        }
    }

    /// Every trigger in a dictionary's /AA (catalog: WC, WS, DS, WP, DP; page: O, C; annotation: E, X, D, U, Fo, Bl,
    /// PO, PC, PV, PI; form field: K, F, V, C), in key order. Keys are read generically, so a trigger name the audit
    /// does not know is still listed.
    static func additionalActions(in dict: CGPDFDictionaryRef, location: String, into rows: inout Rows) {
        var aa: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, "AA", &aa), let aa else { return }
        var keys: [String] = []
        CGPDFDictionaryApplyBlock(aa, { key, _, _ in
            keys.append(String(cString: key))
            return true
        }, nil)
        for key in keys.sorted() where !rows.isFull {
            var a: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(aa, key, &a), let a {
                actions(in: a, location: "\(location) /AA /\(key)", into: &rows)
            } else {
                rows.append(DeclaredAction(location: "\(location) /AA /\(key)", type: "(not a dictionary)", target: nil))
            }
        }
    }

    /// The action and, recursively, every action its /Next names (ISO 32000-1 12.6.2: one dictionary or an array).
    static func actions(in action: CGPDFDictionaryRef, location: String, into rows: inout Rows) {
        var chain: [CGPDFDictionaryRef] = []
        follow(action, location: location, chain: &chain, into: &rows)
    }

    private static func follow(_ action: CGPDFDictionaryRef, location: String, chain: inout [CGPDFDictionaryRef],
                               into out: inout Rows) {
        // Once the list is full, every remaining call returns here, so a wide or deep chain costs no more than the
        // rows already listed (`testAuditStopsOnAnExponentialNextGraph`).
        guard !out.isFull else { return }
        // CGPDFDocument hands out one dictionary reference per indirect PDF object, so a /Next that refers back to an
        // action already on this chain gets the same reference (`ChainedActionTests.testAuditListsEveryPlaceItReads`
        // checks that the fixture's cycle, link G, is caught here: its row "page 0 annotation 6 /A /Next /Next" is the
        // cycle marker). The depth limit stops anything that escapes this check.
        if chain.contains(where: { $0 == action }) {
            out.append(DeclaredAction(location: location, type: cycleMarker, target: "returns to an action listed above"))
            return
        }
        guard chain.count < maximumChainDepth else {
            out.append(DeclaredAction(location: location, type: depthLimitMarker,
                                      target: "not followed past \(maximumChainDepth) actions"))
            return
        }
        chain.append(action)
        defer { chain.removeLast() }
        var s: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(action, "S", &s), let s {
            let type = String(cString: s)
            let target: String? = switch type {
            case "URI": string(action, "URI")
            case "Launch": string(action, "F")
            case "JavaScript": string(action, "JS")
            default: nil
            }
            out.append(DeclaredAction(location: location, type: type, target: target))
        } else {
            out.append(DeclaredAction(location: location, type: "(no /S)", target: nil))
        }
        var next: CGPDFDictionaryRef?
        var nextArray: CGPDFArrayRef?
        if CGPDFDictionaryGetDictionary(action, "Next", &next), let next {
            follow(next, location: "\(location) /Next", chain: &chain, into: &out)
        } else if CGPDFDictionaryGetArray(action, "Next", &nextArray), let nextArray {
            for i in 0..<CGPDFArrayGetCount(nextArray) where !out.isFull {
                var item: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(nextArray, i, &item), let item {
                    follow(item, location: "\(location) /Next[\(i)]", chain: &chain, into: &out)
                }
            }
        }
    }

    static func string(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var str: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dict, key, &str), let str else { return nil }
        return CGPDFStringCopyTextString(str) as String?
    }
}
