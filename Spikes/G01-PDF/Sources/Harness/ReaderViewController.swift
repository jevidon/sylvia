import PDFAnchorKit
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// PDFView with a "Highlight" item in the text-selection edit menu.
final class HarnessPDFView: PDFView {
    var onHighlight: (() -> Void)?

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard currentSelection?.string?.isEmpty == false else { return }
        let highlight = UIAction(title: "Highlight", image: UIImage(systemName: "quote.opening")) { [weak self] _ in
            self?.onHighlight?()
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [highlight]), atStartOfMenu: .root)
    }
}

/// Stage 0 PDF reader harness: open a fixture, select text, save a highlight as a Sylvia-side record, redraw stored
/// highlights as overlays, show per-page extraction status, intercept links. Harness chrome only, never shipped:
/// its strings and system colours are exempt from the design package rules (CLAUDE.md, ADR-0002).
final class ReaderViewController: UIViewController {
    private let options: HarnessOptions
    private let pdfView = HarnessPDFView()
    private let interceptor = LinkInterceptor()
    private let statusLabel = UILabel()
    private let pageLabel = UILabel()
    private let linkLogLabel = UILabel()
    private let openedLabel = UILabel()
    private let linkFramesLabel = UILabel()
    private let overlayFramesLabel = UILabel()
    private let probePointLabel = UILabel()
    private let selectionInfoLabel = UILabel()
    private let selectionFramesLabel = UILabel()
    private let pdfViewFrameLabel = UILabel()
    private let lineEndProbeLabel = UILabel()
    private let fieldValuesLabel = UILabel()
    private let timingLabel = UILabel()

    private var source: PDFSourceDocument?
    /// True while the open file is one of the bundled generated fixtures. Form field values are published for UI tests
    /// only then, never for a file opened from Files.
    private var isBundledFixture = false
    private var extraction: DocumentExtraction?
    private var anchors: [PDFAnchor] = []
    private var linkLog: [String] = []
    /// The page Show or Zoom scrolled to, or the -startPage page. The UI-test geometry is published for it rather
    /// than for `PDFView.currentPage`, which can be a neighbouring page when the target sits near a page edge.
    private var revealedPage: PDFPage?
    private let store: HighlightStore?

    init(options: HarnessOptions) {
        self.options = options
        self.store = (try? HighlightStore.defaultDirectory()).map(HighlightStore.init(directory:))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = options.fixture

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.accessibilityIdentifier = "pdfView"
        pdfView.onHighlight = { [weak self] in self?.highlightSelection() }
        if options.installLinkInterceptor {
            pdfView.delegate = interceptor
            interceptor.onDecision = { [weak self] decision in self?.handle(decision) }
        }

        for (label, id) in [(statusLabel, "status"), (pageLabel, "page"), (linkLogLabel, "linkLog"), (openedLabel, "openedURLs"), (timingLabel, "timing")] {
            label.accessibilityIdentifier = id
            label.font = .preferredFont(forTextStyle: .footnote)
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        // Geometry published for UI tests (window coordinates, points). Present but visually negligible.
        for (label, id) in [(linkFramesLabel, "linkFrames"), (overlayFramesLabel, "overlayFrames"), (probePointLabel, "probePoint"),
                            (selectionInfoLabel, "selectionInfo"), (selectionFramesLabel, "selectionFrames"),
                            (pdfViewFrameLabel, "pdfViewFrame"), (lineEndProbeLabel, "lineEndProbePoint"),
                            (fieldValuesLabel, "fieldValues")] {
            label.accessibilityIdentifier = id
            label.font = .systemFont(ofSize: 1)
            label.textColor = .clear
            label.numberOfLines = 1
            label.isAccessibilityElement = true
            label.text = " "
        }
        let stack = UIStackView(arrangedSubviews: [pageLabel, statusLabel, timingLabel, linkLogLabel, openedLabel, linkFramesLabel,
                                                   overlayFramesLabel, probePointLabel, selectionInfoLabel, selectionFramesLabel,
                                                   pdfViewFrameLabel, lineEndProbeLabel, fieldValuesLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pdfView)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])

        let highlight = UIBarButtonItem(title: "Highlight", style: .plain, target: self, action: #selector(highlightTapped))
        highlight.accessibilityLabel = "Highlight selection"
        highlight.accessibilityIdentifier = "highlightButton"
        // Zoom and reveal: let UI tests check overlay alignment at a zoomed scale and after rotation.
        let zoom = UIBarButtonItem(title: "Zoom", style: .plain, target: self, action: #selector(zoomTapped))
        zoom.accessibilityLabel = "Zoom to first highlight"
        zoom.accessibilityIdentifier = "zoomButton"
        let reveal = UIBarButtonItem(title: "Show", style: .plain, target: self, action: #selector(revealTapped))
        reveal.accessibilityLabel = "Show first highlight"
        reveal.accessibilityIdentifier = "revealButton"
        let fixtures = ["labels-multipage.pdf", "rotated.pdf", "two-column.pdf", "mixed-scanned.pdf", "unicode.pdf", "text-layout.pdf",
                        "actions.pdf", "actions-nonurl.pdf", "actions-chained.pdf", "encrypted-user-password.pdf", "encrypted-owner-only-nocopy.pdf",
                        "truncated.pdf"]
        let fromFiles = UIAction(title: "Open from Files…") { [weak self] _ in self?.pickFromFiles() }
        let openItem = UIBarButtonItem(title: "Open", image: nil, primaryAction: nil, menu: UIMenu(children: fixtures.map { name in
            UIAction(title: name) { [weak self] _ in self?.open(fixture: name, reset: false) }
        } + [fromFiles]))
        openItem.accessibilityIdentifier = "openMenu"
        navigationItem.rightBarButtonItems = [highlight, zoom, reveal]
        navigationItem.leftBarButtonItem = openItem

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewScaleChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        // UI tests read the published geometry; keep it current while PDFView settles its layout.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishGeometry() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(urlRecorded), name: URLOpenRecorder.didRecord, object: nil)
        updateOpenedLabel()
        open(fixture: options.fixture, reset: options.resetHighlights)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        publishGeometry()
    }

    // MARK: Opening

    private func open(fixture name: String, reset: Bool) {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            statusLabel.text = "Fixture \(name) is missing"
            return
        }
        open(url: url, name: name, reset: reset, bundled: true)
    }

    /// Device open-time check: a PDF chosen in Files is copied into the harness (as Sylvia copies imports) and
    /// opened; the status line reports the open time and the time until PDFView first draws page 0.
    private func pickFromFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func open(url: URL, name: String, reset: Bool, bundled: Bool) {
        title = name
        isBundledFixture = bundled
        revealedPage = nil
        source = nil
        extraction = nil
        anchors = []
        pdfView.document = nil
        let started = ContinuousClock.now
        let opened: PDFSourceDocument
        do {
            opened = try PDFSourceDocument.open(url: url)
        } catch {
            statusLabel.text = Self.message(for: error)
            pageLabel.text = name
            return
        }
        source = opened
        let openDuration = ContinuousClock.now - started
        let extractStarted = ContinuousClock.now
        let ex = PageTextExtractor.extract(opened)
        let extractDuration = ContinuousClock.now - extractStarted
        extraction = ex
        if reset { try? store?.removeAll(assetSHA256: opened.sha256) }
        if let seed = options.seedRange, name == options.fixture {
            seedHighlight(seed, source: opened, extraction: ex)
        }
        let restoreStarted = ContinuousClock.now
        restoreHighlights()
        let restoreDuration = ContinuousClock.now - restoreStarted
        OverlayDrawLog.shared.reset()
        let displayStarted = ContinuousClock.now
        pdfView.document = opened.document
        let startIndex = name == options.fixture ? (options.seedRange?.page ?? options.startPage) : 0
        if let page = opened.page(at: startIndex) {
            pdfView.layoutIfNeeded()
            // -startPage: publish the UI-test geometry for that page even when PDFView reports a neighbour as current
            // (the last page cannot scroll to the top of the view).
            if name == options.fixture, options.seedRange == nil, options.startPage != 0 { revealedPage = page }
            showTop(of: page)
            // PDFView settles its scale after the first layout pass; pin the top of the page again afterwards.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showTop(of: page) }
        }
        pageChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.publishGeometry() }
        reportOpenTime(open: openDuration, extract: extractDuration, restore: restoreDuration, started: started,
                       displayStarted: displayStarted, firstPage: opened.page(at: startIndex))
    }

    /// Shows open, extraction, highlight-restore and first-draw times on the timing line once PDFView has drawn the
    /// first page. "Restore highlights" is loading the stored records, re-anchoring them and handing their rectangles
    /// to the pages that carry them; it runs before display, so it is part of the time until the first page is drawn.
    private func reportOpenTime(open: Duration, extract: Duration, restore: Duration, started: ContinuousClock.Instant,
                                displayStarted: ContinuousClock.Instant, firstPage: PDFPage?) {
        guard let firstPage else { return }
        let id = ObjectIdentifier(firstPage)
        func ms(_ d: Duration) -> String {
            String(format: "%.0f", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        }
        func poll(_ attempt: Int) {
            if OverlayDrawLog.shared.snapshot.contains(where: { $0.page == id }) {
                let now = ContinuousClock.now
                timingLabel.text = "Open \(ms(open)) ms (digest, checks, parse); text of \(source?.document.pageCount ?? 0) pages \(ms(extract)) ms; "
                    + "restore highlights \(ms(restore)) ms (\(anchors.count) restored); "
                    + "first page drawn \(ms(now - displayStarted)) ms after display began; total \(ms(now - started)) ms"
            } else if attempt < 400 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { poll(attempt + 1) }
            }
        }
        poll(0)
    }

    private func showTop(of page: PDFPage) {
        let box = page.bounds(for: .cropBox)
        // Destination points are in page space; the displayed top-left depends on the rotation.
        let point: CGPoint
        switch ((page.rotation % 360) + 360) % 360 {
        case 90: point = CGPoint(x: box.minX, y: box.minY)
        case 180: point = CGPoint(x: box.maxX, y: box.minY)
        case 270: point = CGPoint(x: box.maxX, y: box.maxY)
        default: point = CGPoint(x: box.minX, y: box.maxY)
        }
        pdfView.go(to: PDFDestination(page: page, at: point))
        publishGeometry()
    }

    static func message(for error: PDFOpenError) -> String {
        switch error {
        case .passwordProtected: return "This PDF is password-protected. Password-protected PDFs are not supported."
        case .truncated: return "This PDF is incomplete: the file ends early."
        case .notAPDF: return "This file is not a PDF."
        case .unparseable: return "This PDF could not be read."
        case .noPages: return "This PDF has no pages."
        case .fileUnreadable: return "The file could not be read."
        }
    }

    private func seedHighlight(_ seed: (page: Int, start: Int, end: Int), source: PDFSourceDocument, extraction: DocumentExtraction) {
        do {
            var anchor = try PDFAnchorBuilder.anchor(forScalarRange: ScalarRange(start: seed.start, end: seed.end),
                                                     onPage: seed.page, in: source, extraction: extraction)
            if options.simulateExtractionDrift { anchor = Self.simulatingExtractionDrift(anchor) }
            try store?.append(HighlightRecord(anchor: anchor))
        } catch {
            statusLabel.text = "Seed failed: \(error)"
        }
    }

    /// Re-anchors every stored record against the opened file (`HighlightRestorer`), draws the exact and relocated
    /// ones, and writes a relocated record's new location back to the store so it restores exactly next time.
    private func restoreHighlights() {
        guard let source, let extraction, let store else { return }
        let records = (try? store.load(assetSHA256: source.sha256)) ?? []
        let outcome = HighlightRestorer.restore(records, in: source, extraction: extraction)
        var relocatedNote = ""
        if outcome.needsSave {
            do {
                try store.save(outcome.records, assetSHA256: source.sha256)
                relocatedNote = " (new location saved)"
            } catch {
                relocatedNote = " (new location not saved)"
            }
        }
        anchors = outcome.drawable
        HighlightOverlay.apply(anchors, to: source.document)
        statusLabel.text = "Highlights: \(records.count) stored, \(outcome.exact) restored exactly"
            + (outcome.relocated > 0 ? ", \(outcome.relocated) relocated\(relocatedNote)" : "")
            + (outcome.relocationNotRebuilt > 0 ? ", \(outcome.relocationNotRebuilt) relocated but not redrawn" : "")
            + (outcome.needsReview > 0 ? ", \(outcome.needsReview) location needs review" : "")
            + (outcome.notFound > 0 ? ", \(outcome.notFound) not found" : "")
    }

    /// UI-test stand-in for a record written before the page text changed (an OS update changing PDFKit's extractor,
    /// or a rebuilt extraction cache): every segment's page-text digest no longer matches, its scalar range points
    /// 5 scalars later, and its stored line rectangles are 0.05 of the page lower. Exact restore fails; the text and
    /// its context are unchanged, so the record relocates. Drawing the stale rectangles would put the overlay in the
    /// wrong place, which the UI test checks for.
    static func simulatingExtractionDrift(_ anchor: PDFAnchor) -> PDFAnchor {
        var drifted = anchor
        for i in drifted.segments.indices {
            drifted.segments[i].pageTextSHA256 = String(repeating: "0", count: 64)
            drifted.segments[i].textRange.start += 5
            drifted.segments[i].textRange.end += 5
            drifted.segments[i].lineRects = drifted.segments[i].lineRects.map {
                NormalizedRect(x: $0.x, y: $0.y - 0.05, width: $0.width, height: $0.height)
            }
        }
        return drifted
    }

    // MARK: Highlighting

    @objc private func highlightTapped() { highlightSelection() }

    private func highlightSelection() {
        guard let source, let extraction else { return }
        guard let selection = pdfView.currentSelection, selection.string?.isEmpty == false else {
            statusLabel.text = "Select text first"
            return
        }
        do {
            let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
            guard let store else { throw CocoaError(.fileWriteUnknown) }
            try store.append(HighlightRecord(anchor: anchor))
            // Only after the durable write: redraw and report.
            anchors.append(anchor)
            HighlightOverlay.apply(anchors, to: source.document)
            // The selection tint would cover the new highlight, so the saved selection is dismissed (PDFView keeps it
            // through the redraw otherwise: OverlayRedrawTests).
            pdfView.clearSelection()
            if options.redrawAfterHighlight { redrawPages() }
            statusLabel.text = "Saved highlight (\(anchors.count) on this file)"
        } catch let error as AnchorCaptureError {
            statusLabel.text = Self.message(for: error)
        } catch {
            statusLabel.text = "Not saved: the highlight could not be written"
        }
    }

    static func message(for error: AnchorCaptureError) -> String {
        switch error {
        case .noSelectableText: return PageTextStatus.noSelectableTextMessage
        case .textRestricted: return PageTextStatus.restrictedMessage
        case .emptySelection: return "Select text first"
        default: return "Not saved: the selection could not be anchored"
        }
    }

    /// PDFView caches rendered tiles and does not redraw a page because its overlay changed.
    /// `setNeedsDisplay()` makes it redraw the visible tiles through `OverlayPage.draw(with:to:)` and keeps the
    /// selection, page and scale (`OverlayRedrawTests`); on screen, `HighlightUITests` checks the new highlight with
    /// and (control) without this call.
    private func redrawPages() {
        pdfView.setNeedsDisplay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.publishGeometry() }
    }

    @objc private func zoomTapped() {
        pdfView.autoScales = false
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit * 2.5
        revealFirstHighlight()
    }

    @objc private func revealTapped() { revealFirstHighlight() }

    /// Scrolls the first highlight into view at the current scale.
    private func revealFirstHighlight() {
        guard let source, let segment = anchors.first?.segments.first,
              let page = source.page(at: segment.pageIndex) as? OverlayPage,
              let first = page.highlightRects.first
        else { return }
        revealedPage = page
        pdfView.go(to: page.highlightRects.reduce(first) { $0.union($1) }, on: page)
        publishGeometry()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.publishGeometry() }
    }

    // MARK: Status

    @objc private func pageChanged() {
        guard let source, let page = pdfView.currentPage else { return }
        let index = source.index(of: page)
        let label = source.printedLabel(forPageAt: index).map { "printed label \($0)" } ?? "no printed label"
        let status = extraction?.page(index)?.status.unavailableMessage
        pageLabel.text = "Page index \(index) of \(source.document.pageCount), \(label)" + (status.map { ". \($0)" } ?? "")
        publishGeometry()
    }

    private func handle(_ decision: LinkDecision) {
        switch decision {
        case .blocked(let reason):
            linkLog.append("blocked: \(reason)")
        case .performedByPDFView(let what):
            linkLog.append("pdfview: \(what)")
        case .navigate(let index):
            linkLog.append("navigate: \(index)")
        case .askUserBeforeOpening(let url):
            linkLog.append("ask: \(url.absoluteString)")
            let alert = UIAlertController(title: "Open link?", message: url.absoluteString, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in UIApplication.shared.open(url) })
            present(alert, animated: false)
        }
        linkLogLabel.text = "Links: " + linkLog.joined(separator: " | ")
    }

    @objc private func urlRecorded() { updateOpenedLabel() }

    /// Publishes the shape of the current selection (never its text) for UI tests: pages, line count and UTF-16
    /// length, and each line's frame in window coordinates (where the selection handles are).
    @objc private func selectionChanged() {
        guard let source, let selection = pdfView.currentSelection, let text = selection.string, !text.isEmpty else {
            Self.publish(selectionInfoLabel, "")
            Self.publish(selectionFramesLabel, "")
            return
        }
        let pages = selection.pages.map { source.index(of: $0) }.sorted()
        let lines = selection.selectionsByLine().filter { !($0.string ?? "").isEmpty }
        Self.publish(selectionInfoLabel, "pages \(pages.map(String.init).joined(separator: ",")); lines \(lines.count); utf16 \(text.utf16.count)")
        Self.publish(selectionFramesLabel, lines.compactMap { line -> String? in
            guard let page = line.pages.first else { return nil }
            let r = pdfView.convert(pdfView.convert(line.bounds(for: page), from: page), to: nil)
            return String(format: "%.1f,%.1f,%.1f,%.1f", r.minX, r.minY, r.width, r.height)
        }.joined(separator: ";"))
    }

    private func updateOpenedLabel() {
        let urls = URLOpenRecorder.shared.received.map(\.absoluteString)
        openedLabel.text = "URLs opened into the harness: " + (urls.isEmpty ? "none" : urls.joined(separator: ", "))
    }

    private static func publish(_ label: UILabel, _ value: String) {
        label.text = value.isEmpty ? " " : value
        label.accessibilityLabel = value
    }

    /// Publishes link and highlight-underline rectangles of the current page in window coordinates for UI tests.
    private func publishGeometry() {
        guard let page = revealedPage ?? pdfView.currentPage else { return }
        func windowRect(_ pageRect: CGRect) -> CGRect {
            pdfView.convert(pdfView.convert(pageRect, from: page), to: nil)
        }
        func fmt(_ r: CGRect) -> String { String(format: "%.1f,%.1f,%.1f,%.1f", r.minX, r.minY, r.width, r.height) }
        Self.publish(linkFramesLabel, page.annotations.filter { $0.action != nil }.map { fmt(windowRect($0.bounds)) }.joined(separator: ";"))
        // A point on the first body line of the generated fixtures (page space x 200, y 703), for long-press tests.
        let probe = pdfView.convert(pdfView.convert(CGPoint(x: 200, y: 703), from: page), to: nil)
        Self.publish(probePointLabel, String(format: "%.1f,%.1f", probe.x, probe.y))
        // A point on the last character of that line, so a long press selects the line's last word (a selection that
        // ends at a line break: LineEndSelectionTests). Only the point is published, never the text.
        if let line = page.selectionForLine(at: CGPoint(x: 200, y: 703)), !line.bounds(for: page).isEmpty {
            let box = line.bounds(for: page)
            let end = pdfView.convert(pdfView.convert(CGPoint(x: box.maxX - 2, y: box.midY), from: page), to: nil)
            Self.publish(lineEndProbeLabel, String(format: "%.1f,%.1f", end.x, end.y))
        } else {
            Self.publish(lineEndProbeLabel, "")
        }
        // Text form field values on this page, for UI tests that type into a field ("name=value;..."). Bundled
        // generated fixtures only: a file chosen in Files may hold a person's form entries.
        let fields = isBundledFixture ? page.annotations.filter { $0.widgetFieldType == .text } : []
        Self.publish(fieldValuesLabel, fields.map { "\($0.fieldName ?? "?")=\($0.widgetStringValue ?? "")" }.joined(separator: ";"))
        // The PDF view's frame in window points, then the affine map from the current page's user space to window
        // points (a,b,c,d,tx,ty), so UI tests can aim a touch at any page point on a rotated or zoomed page.
        let origin = pdfView.convert(pdfView.convert(CGPoint.zero, from: page), to: nil)
        let unitX = pdfView.convert(pdfView.convert(CGPoint(x: 100, y: 0), from: page), to: nil)
        let unitY = pdfView.convert(pdfView.convert(CGPoint(x: 0, y: 100), from: page), to: nil)
        Self.publish(pdfViewFrameLabel, fmt(pdfView.convert(pdfView.bounds, to: nil)) + String(
            format: ";%.5f,%.5f,%.5f,%.5f,%.2f,%.2f", (unitX.x - origin.x) / 100, (unitX.y - origin.y) / 100,
            (unitY.x - origin.x) / 100, (unitY.y - origin.y) / 100, origin.x, origin.y))
        let lines = (page as? OverlayPage)?.highlightRects ?? []
        Self.publish(overlayFramesLabel, lines.map {
            "u=" + fmt(windowRect(HighlightStyle.underlineRect(for: $0)))
                + " f=" + fmt(windowRect(CGRect(x: $0.minX, y: HighlightStyle.underlineRect(for: $0).maxY, width: $0.width,
                                                height: $0.maxY - HighlightStyle.underlineRect(for: $0).maxY)))
        }.joined(separator: ";"))
    }
}

extension ReaderViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        open(url: url, name: url.lastPathComponent, reset: false, bundled: false)
    }
}
