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

/// Every action a PDF declares, read from the file's own dictionaries (not from PDFKit's action objects, which
/// re-type some actions: PDFKit presents a /Launch action as a URL action). Used for diagnostics and tests.
public struct DeclaredAction: Hashable, Sendable, CustomStringConvertible {
    /// Where it was found: "catalog /OpenAction", "page 0 /AA /O", "page 0 annotation 2 /A", "names /JavaScript".
    public var location: String
    /// The PDF /S value: URI, Launch, GoTo, JavaScript, ...
    public var type: String
    /// URI, launch file, or a short summary.
    public var target: String?

    public var description: String { "\(location): /\(type) \(target ?? "")" }
}

public enum PDFActionAudit {
    public static func audit(_ document: PDFDocument) -> [DeclaredAction] {
        var out: [DeclaredAction] = []
        if let catalog = document.documentRef?.catalog {
            var openAction: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(catalog, "OpenAction", &openAction), let openAction {
                out += actions(in: openAction, location: "catalog /OpenAction")
            }
            var openArray: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(catalog, "OpenAction", &openArray), openArray != nil {
                out.append(DeclaredAction(location: "catalog /OpenAction", type: "destination", target: nil))
            }
            out += additionalActions(in: catalog, location: "catalog")
            var names: CGPDFDictionaryRef?
            var js: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names,
               CGPDFDictionaryGetDictionary(names, "JavaScript", &js), js != nil
            {
                out.append(DeclaredAction(location: "catalog /Names /JavaScript", type: "JavaScript", target: nil))
            }
        }
        for index in 0..<document.pageCount {
            guard let dict = document.page(at: index)?.pageRef?.dictionary else { continue }
            out += additionalActions(in: dict, location: "page \(index)")
            var annots: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(dict, "Annots", &annots), let annots else { continue }
            for i in 0..<CGPDFArrayGetCount(annots) {
                var annot: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(annots, i, &annot), let annot else { continue }
                var a: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(annot, "A", &a), let a {
                    out += actions(in: a, location: "page \(index) annotation \(i) /A")
                }
            }
        }
        return out
    }

    static func additionalActions(in dict: CGPDFDictionaryRef, location: String) -> [DeclaredAction] {
        var aa: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, "AA", &aa), let aa else { return [] }
        var out: [DeclaredAction] = []
        for key in ["O", "C", "WC", "WS", "DS", "WP", "DP"] {
            var a: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(aa, key, &a), let a {
                out += actions(in: a, location: "\(location) /AA /\(key)")
            }
        }
        return out
    }

    static func actions(in action: CGPDFDictionaryRef, location: String) -> [DeclaredAction] {
        var s: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(action, "S", &s), let s else { return [] }
        let type = String(cString: s)
        var target: String?
        switch type {
        case "URI": target = string(action, "URI")
        case "Launch": target = string(action, "F")
        case "JavaScript": target = string(action, "JS")
        default: target = nil
        }
        return [DeclaredAction(location: location, type: type, target: target)]
    }

    static func string(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var str: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dict, key, &str), let str else { return nil }
        return CGPDFStringCopyTextString(str) as String?
    }
}
