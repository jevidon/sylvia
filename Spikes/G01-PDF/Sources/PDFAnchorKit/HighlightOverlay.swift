import CoreGraphics
import Foundation
import ObjectiveC
import PDFKit
import Synchronization

/// Highlight appearance (plan 4.4.2, 4.4.8, 9.1): an `ochre.tint` fill multiplied over the page plus an `ochre`
/// underline, so the highlight still reads in grayscale. Stage 0 harness values copied from plan 4.4.2; the product
/// reads them from `Packages/Design` and never declares them here.
public enum HighlightStyle {
    /// `ochre.tint`, light appearance: #F1E4C8. PDF pages are drawn on white paper in both appearances (PDFKit does
    /// not invert page content), so the light values are used.
    public static let fill = CGColor(srgbRed: 0xF1 / 255.0, green: 0xE4 / 255.0, blue: 0xC8 / 255.0, alpha: 1)
    /// `ochre`, light appearance: #8A5410.
    public static let underline = CGColor(srgbRed: 0x8A / 255.0, green: 0x54 / 255.0, blue: 0x10 / 255.0, alpha: 1)
    /// Underline thickness as a fraction of the line height (minimum 1 pt), drawn inside the bottom of the line box.
    public static let underlineFraction: CGFloat = 0.12
    public static let underlineMinimum: CGFloat = 1

    public static func underlineRect(for line: CGRect) -> CGRect {
        let h = max(underlineMinimum, line.height * underlineFraction)
        return CGRect(x: line.minX, y: line.minY, width: line.width, height: h)
    }
}

/// Draws highlight rectangles given in PDF user space into a context already transformed to user space.
public enum HighlightPainter {
    public static func paint(_ lines: [CGRect], in context: CGContext) {
        guard !lines.isEmpty else { return }
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setFillColor(HighlightStyle.fill)
        context.fill(lines)
        context.setBlendMode(.normal)
        context.setFillColor(HighlightStyle.underline)
        context.fill(lines.map(HighlightStyle.underlineRect(for:)))
        context.restoreGState()
    }
}

/// A PDFDocument whose pages are `OverlayPage`s. Overriding `pageClass` (rather than setting a delegate after
/// creation) makes every page the subclass from the moment PDFKit instantiates it.
open class OverlayPDFDocument: PDFDocument {
    override open var pageClass: AnyClass { OverlayPage.self }
}

/// A page that draws Sylvia's highlight overlays on top of the page content whenever PDFKit draws it (in a PDFView,
/// a thumbnail or an offscreen render). The overlays live only in memory, from Sylvia's highlight records. Nothing
/// is added to the page's annotations and nothing is written to the PDF file (plan 9.2).
///
/// No stored properties: PDFKit instantiates `pageClass` through an Objective-C initializer that does not run Swift
/// property initializers, so a stored property is zeroed memory (the harness crashed reading a stored array this way,
/// simulator iOS 26.5; `PDFKitObservationTests.testPageClassInstancesSkipSwiftPropertyInitializers` shows the zeroed
/// value). The rectangles live in an associated object instead. PDFView draws tiles on background threads while the
/// main thread changes highlights, so the box is guarded by a mutex (`OverlayConcurrencyTests`, also run under the
/// Thread Sanitizer by `Scripts/ci.d/32-g01-pdf.sh`).
public final class OverlayPage: PDFPage {
    /// Highlight line rectangles in PDF user space (the same space as `PDFSelection.bounds(for:)`). Setting an empty
    /// array on a page that never had highlights creates no storage.
    public var highlightRects: [CGRect] {
        get { OverlayStorage.box(for: self, create: false)?.rects.withLock { $0 } ?? [] }
        set {
            guard let box = OverlayStorage.box(for: self, create: !newValue.isEmpty) else { return }
            box.rects.withLock { $0 = newValue }
            if !newValue.isEmpty, let document {
                let index = document.index(for: self)
                if index != NSNotFound { OverlayStorage.markHighlighted(index, in: document) }
            }
        }
    }

    /// Diagnostics for tests: whether this page has overlay storage at all.
    public var hasOverlayStorage: Bool { OverlayStorage.box(for: self, create: false) != nil }

    override public func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        let rects = highlightRects
        OverlayDrawLog.shared.record(page: self, box: box, highlightCount: rects.count)
        guard !rects.isEmpty else { return }
        context.saveGState()
        // super.draw leaves the context as it found it; map user space onto the displayed box the same way PDFKit
        // did for the content (rotation plus box origin).
        transform(context, for: box)
        HighlightPainter.paint(rects, in: context)
        context.restoreGState()
    }
}

/// Diagnostics: the last draw calls of overlay pages (which page, which thread, how many highlights). Used by tests to
/// prove that PDFView's own tile renderer draws pages through `OverlayPage.draw(with:to:)`. Holds no page content.
public final class OverlayDrawLog: Sendable {
    public struct Event: Sendable, Equatable {
        public var page: ObjectIdentifier
        public var box: Int
        public var highlightCount: Int
        public var onMainThread: Bool
    }

    public static let shared = OverlayDrawLog()
    private let events = Mutex<[Event]>([])
    static let capacity = 512

    public func record(page: PDFPage, box: PDFDisplayBox, highlightCount: Int) {
        let event = Event(page: ObjectIdentifier(page), box: box.rawValue, highlightCount: highlightCount, onMainThread: Thread.isMainThread)
        events.withLock {
            $0.append(event)
            if $0.count > OverlayDrawLog.capacity { $0.removeFirst($0.count - OverlayDrawLog.capacity) }
        }
    }

    public var snapshot: [Event] { events.withLock { $0 } }

    public func reset() {
        events.withLock { $0.removeAll() }
    }
}

private final class OverlayBox: Sendable {
    let rects = Mutex<[CGRect]>([])
}

/// Indices of the pages of one document that currently carry highlights, so that replacing highlights touches only
/// those pages instead of instantiating every page of a long document.
private final class HighlightedPages: Sendable {
    let indices = Mutex<Set<Int>>([])
}

private enum OverlayStorage {
    nonisolated(unsafe) static let key = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    nonisolated(unsafe) static let documentKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    static let creation = Mutex<Void>(())

    static func box(for page: PDFPage, create: Bool) -> OverlayBox? {
        if let box = objc_getAssociatedObject(page, key) as? OverlayBox { return box }
        guard create else { return nil }
        return creation.withLock { _ in
            if let box = objc_getAssociatedObject(page, key) as? OverlayBox { return box }
            let box = OverlayBox()
            objc_setAssociatedObject(page, key, box, .OBJC_ASSOCIATION_RETAIN)
            return box
        }
    }

    static func highlightedPages(of document: PDFDocument) -> HighlightedPages {
        if let set = objc_getAssociatedObject(document, documentKey) as? HighlightedPages { return set }
        return creation.withLock { _ in
            if let set = objc_getAssociatedObject(document, documentKey) as? HighlightedPages { return set }
            let set = HighlightedPages()
            objc_setAssociatedObject(document, documentKey, set, .OBJC_ASSOCIATION_RETAIN)
            return set
        }
    }

    static func markHighlighted(_ index: Int, in document: PDFDocument) {
        _ = highlightedPages(of: document).indices.withLock { $0.insert(index) }
    }
}

public enum HighlightOverlay {
    /// User-space line rectangles for one anchor on one page, from the anchor's normalized rectangles and the page's
    /// current anchor box.
    public static func userSpaceRects(for anchor: PDFAnchor, pageIndex: Int, box: CGRect) -> [CGRect] {
        anchor.segments
            .filter { $0.pageIndex == pageIndex }
            .flatMap { $0.lineRects.map { PageGeometry.denormalize($0, in: box) } }
    }

    /// Replaces the document's highlights with those of `anchors`. Only pages that had highlights or receive them
    /// are touched (a long document's other pages are never instantiated here). Returns the number of pages whose
    /// highlights changed from or to non-empty.
    @discardableResult
    public static func apply(_ anchors: [PDFAnchor], to document: PDFDocument) -> Int {
        var byPage: [Int: [CGRect]] = [:]
        for anchor in anchors {
            for segment in anchor.segments {
                guard let page = document.page(at: segment.pageIndex) else { continue }
                let box = page.bounds(for: PDFSourceDocument.anchorBox)
                byPage[segment.pageIndex, default: []] += segment.lineRects.map { PageGeometry.denormalize($0, in: box) }
            }
        }
        let tracked = OverlayStorage.highlightedPages(of: document)
        let previous = tracked.indices.withLock { $0 }
        var touched = 0
        for index in previous.union(byPage.keys).sorted() {
            guard let page = document.page(at: index) as? OverlayPage else { continue }
            let rects = byPage[index] ?? []
            if !(page.highlightRects.isEmpty && rects.isEmpty) { touched += 1 }
            page.highlightRects = rects
        }
        let now = Set(byPage.filter { !$0.value.isEmpty }.keys)
        tracked.indices.withLock { $0 = now }
        return touched
    }

    /// Pages of `document` that currently carry highlights (diagnostics and tests).
    public static func highlightedPageIndices(in document: PDFDocument) -> Set<Int> {
        OverlayStorage.highlightedPages(of: document).indices.withLock { $0 }
    }
}

/// Offscreen page rendering, using exactly the drawing path PDFView uses (`PDFPage.draw(with:to:)`).
public enum PageRenderer {
    /// Renders the page's anchor box as displayed (rotation applied) at `scale` pixels per point, on white.
    /// The returned image's pixel (0, 0) is the top-left of the displayed page.
    public static func render(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        guard let rotation = try? PageRotation(degrees: page.rotation) else { return nil }
        let box = page.bounds(for: PDFSourceDocument.anchorBox)
        let size = PageGeometry.displaySize(of: box, rotation: rotation)
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: PDFSourceDocument.anchorBox, to: ctx)
        return ctx.makeImage()
    }
}
