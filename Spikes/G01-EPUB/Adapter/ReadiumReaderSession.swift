import CryptoKit
import Foundation
import G01EPUBCore
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
import UIKit
import WebKit

/// Readium 3.11.0 implementation of `ReaderSession` (ADR-0004).
@MainActor public final class ReadiumReaderSession: NSObject, ReaderSession {
    public enum Safety: Sendable { case sylvia, readiumDefaults }

    public let opened: OpenedEPUB
    public let navigator: EPUBNavigatorViewController
    public let safety: Safety
    public private(set) var settings: ReaderSettings

    public var publication: Publication { opened.publication }
    public var viewController: UIViewController { navigator }

    private var highlights: [HighlightPresentation] = []
    private var linkHistory: [Locator] = []
    private var positionHandlers: [UUID: @MainActor (ReaderLocator) -> Void] = [:]
    private let contentRuleList: WKContentRuleList?

    // Observable state for the harness and tests.
    public private(set) var lastNote: (html: String, referrer: String, href: String)?
    public private(set) var externalURLRequests: [URL] = []
    public private(set) var resourceLoadFailures: [String] = []
    public private(set) var locationChangeCount = 0
    private var lastLocatedHref: String?
    public private(set) var userContentControllersConfigured = 0
    /// Called when a footnote/endnote link is tapped; the session stays on the current page (plan 9.1).
    public var onNote: (@MainActor (_ html: String, _ referrer: String) -> Void)?

    public nonisolated static let adapterName = "readium-swift"
    public nonisolated static let adapterVersion = "3.11.0"
    public static let highlightGroup = "sylvia-highlights"
    public static let searchGroup = "sylvia-search"

    /// The publication's content rule list: every load except `readium:`, `data:` and `about:` is blocked, and every
    /// document load (page or frame navigation) except the reading-order documents (ADR-0004 section 4 item 5).
    public let ruleList: PublicationResourcePolicy.RuleList?

    /// Builds the content rule list for `publication` from its reading-order hrefs, in both the form Readium writes in
    /// the web view's URL and Readium's normalized form.
    nonisolated static func ruleList(for publication: Publication) -> PublicationResourcePolicy.RuleList {
        let hrefs = publication.readingOrder.flatMap { [$0.url().string, $0.url().normalized.string] }
        return PublicationResourcePolicy.contentRuleListJSON(readingOrderHrefs: hrefs)
    }

    /// Compiles the content rule list (if any) before the first web view exists, then builds the navigator.
    public static func make(opened: OpenedEPUB, initialLocator: ReaderLocator?, settings: ReaderSettings = .init(),
                            safety: Safety = .sylvia, editingActions: [EditingAction] = []) async throws -> ReadiumReaderSession {
        var compiled: WKContentRuleList?
        var list: PublicationResourcePolicy.RuleList?
        if safety == .sylvia {
            let rules = ruleList(for: opened.publication)
            // The store keeps compiled lists on disk by identifier. The identifier is derived from the rules' content,
            // so one publication always reuses its own entry and two different lists never share one.
            let digest = SHA256.hash(data: Data(rules.json.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
            compiled = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "sylvia-epub-v2-\(digest)", encodedContentRuleList: rules.json
            )
            list = rules
        }
        return try ReadiumReaderSession(opened: opened, initialLocator: initialLocator, settings: settings, safety: safety,
                                        contentRuleList: compiled, ruleList: list, editingActions: editingActions)
    }

    private init(opened: OpenedEPUB, initialLocator: ReaderLocator?, settings: ReaderSettings, safety: Safety,
                 contentRuleList: WKContentRuleList?, ruleList: PublicationResourcePolicy.RuleList?,
                 editingActions: [EditingAction]) throws {
        self.opened = opened
        self.safety = safety
        self.settings = settings
        self.contentRuleList = contentRuleList
        self.ruleList = ruleList
        let config = EPUBNavigatorViewController.Configuration(
            preferences: SylviaReaderStyle.preferences(for: settings),
            editingActions: editingActions.isEmpty ? EditingAction.defaultActions : editingActions,
            decorationTemplates: SylviaReaderStyle.decorationTemplates(),
            fontFamilyDeclarations: SylviaReaderStyle.fontFamilyDeclarations()
        )
        navigator = try EPUBNavigatorViewController(
            publication: opened.publication,
            initialLocation: try initialLocator.map { try Self.readiumLocator($0) },
            config: config
        )
        super.init()
        navigator.delegate = self
    }

    // MARK: Locators

    static func readiumLocator(_ l: ReaderLocator) throws -> Locator {
        try Locator(jsonString: l.json)
    }

    static func readerLocator(_ l: Locator) -> ReaderLocator {
        ReaderLocator(
            json: (try? l.jsonString()) ?? "{}",
            href: l.href.string,
            mediaType: l.mediaType.string,
            progression: l.locations.progression,
            totalProgression: l.locations.totalProgression,
            position: l.locations.position,
            textBefore: l.text.before,
            textHighlight: l.text.highlight,
            textAfter: l.text.after,
            otherLocationKeys: l.locations.otherLocations.keys.sorted()
        )
    }

    public var currentLocator: ReaderLocator? { navigator.currentLocation.map(Self.readerLocator) }

    /// Readium's selection as it reports it. Its text is exact, but see `captureSelection()` for the locator.
    public var currentSelection: ReaderSelection? {
        guard let s = navigator.currentSelection, let text = s.locator.text.highlight else { return nil }
        return ReaderSelection(locator: Self.readerLocator(s.locator), exactText: text,
                               prefix: s.locator.text.before ?? "", suffix: s.locator.text.after ?? "", frame: s.frame)
    }

    /// Number of captures whose resource the adapter had to correct (see `captureSelection()`).
    public private(set) var selectionHrefCorrections = 0

    /// The selection to save, with its resource confirmed.
    ///
    /// Readium 3.11.0 builds the selection locator from `navigator.currentLocation` plus the selected text
    /// (`EPUBNavigatorViewController.spreadView(_:selectionDidChange:frame:)`); it does not use the resource the
    /// selection's JavaScript reports. Shortly after a jump into another resource, `currentLocation` can still name
    /// the previous resource, so the locator would pair the right text with the wrong `href` (AnchorSamplesTests saw
    /// this). The adapter asks the document that holds the selection for its URL and selected text. When the text
    /// matches and the resource differs, it rebuilds the locator for the right resource with the same text and no
    /// progression or position (those described the other resource). When the text no longer matches (the selection
    /// changed), it returns nil rather than guess; the caller asks the user to select again.
    public func captureSelection() async -> ReaderSelection? {
        guard let raw = currentSelection else { return nil }
        let script = "JSON.stringify({ url: String(location.href), text: String(window.getSelection()) })"
        guard case let .success(value) = await navigator.evaluateJavaScript(script), let json = value as? String,
              let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String],
              let url = obj["url"], let domText = obj["text"],
              CaptureBuilder.collapse(domText) == CaptureBuilder.collapse(raw.exactText),
              let link = readingOrderLink(forDocumentURL: url)
        else { return nil }
        let href = link.url().string
        if href == raw.locator.href { return raw }
        guard let rawLocator = try? Self.readiumLocator(raw.locator) else { return nil }
        let fixed = Locator(href: link.url(), mediaType: link.mediaType ?? .xhtml, title: link.title, text: rawLocator.text)
        selectionHrefCorrections += 1
        return ReaderSelection(locator: Self.readerLocator(fixed), exactText: raw.exactText, prefix: raw.prefix,
                               suffix: raw.suffix, frame: raw.frame)
    }

    /// The reading-order link of a document the navigator loaded (`readium://<publication id>/<href>`).
    func readingOrderLink(forDocumentURL url: String) -> ReadiumShared.Link? {
        guard let components = URLComponents(string: url) else { return nil }
        let path = String(components.percentEncodedPath.drop { $0 == "/" })
        guard let target = AnyURL(string: path)?.normalized.string else { return nil }
        return publication.readingOrder.first { $0.url().normalized.string == target }
    }

    // MARK: Navigation

    public func navigate(to locator: ReaderLocator) async -> Bool {
        guard let l = try? Self.readiumLocator(locator) else { return false }
        return await go(to: l)
    }

    /// Readium 3.11.0 observation (FootnoteTests, evidence/navigation-race.json): the first `go(to:)` into a
    /// resource whose spread was preloaded can be undone a few hundred milliseconds later, when the preloaded spread
    /// finishes loading and applies its own initial position (the start of the resource). The adapter therefore
    /// waits for the spread to settle and repeats the jump; the second `go(to:)` is a no-op when already in place.
    public private(set) var navigationRetries = 0
    public var repeatsJumpAfterSettle = true

    func go(to locator: Locator) async -> Bool {
        let options = NavigatorGoOptions(animated: false)
        guard await navigator.go(to: locator, options: options) else { return false }
        guard repeatsJumpAfterSettle else { return true }
        try? await Task.sleep(for: .milliseconds(600))
        navigationRetries += 1
        return await navigator.go(to: locator, options: options)
    }

    func go(to link: ReadiumShared.Link) async -> Bool {
        guard let locator = await publication.locate(link) else { return false }
        return await go(to: locator)
    }

    public func goForward() async -> Bool { await navigator.goForward(options: NavigatorGoOptions(animated: false)) }
    public func goBackward() async -> Bool { await navigator.goBackward(options: NavigatorGoOptions(animated: false)) }

    public func followLink(href: String) async -> Bool {
        guard let url = AnyURL(string: href), let link = publication.linkWithHREF(url) else { return false }
        if let here = navigator.currentLocation { linkHistory.append(here) }
        var target = link
        target.href = href
        return await go(to: target)
    }

    public func returnFromLink() async -> Bool {
        guard let back = linkHistory.popLast() else { return false }
        return await go(to: back)
    }

    public var linkHistoryDepth: Int { linkHistory.count }

    // MARK: Selection and highlights

    public func clearSelection() { navigator.clearSelection() }

    public func apply(highlights: [HighlightPresentation]) {
        self.highlights = highlights
        redrawHighlights()
    }

    /// Readium 3.11.0 observation: decorations applied while a spread is finishing its load can be added twice
    /// (the navigator's own replay in `spreadViewDidLoad` plus the diff script), leaving duplicate boxes. After each
    /// application the adapter counts the rendered items per highlight in the visible resource (a reader-owned script)
    /// and, if any highlight is drawn more than once, clears the group and draws it again.
    public private(set) var duplicateRepairs = 0
    private var verifyTask: Task<Void, Never>?

    static let duplicateCheckScript = """
    (function () {
      const counts = {};
      document.querySelectorAll('[data-group="\(highlightGroup)"]').forEach(function (g) {
        Array.from(g.children).forEach(function (item) {
          const box = item.firstElementChild;
          const id = box && box.dataset ? box.dataset.sylviaHighlightId : null;
          if (id) { counts[id] = (counts[id] || 0) + 1; }
        });
      });
      return JSON.stringify(counts);
    })()
    """

    private func scheduleDuplicateCheck() {
        verifyTask?.cancel()
        verifyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            await self.repairDuplicateHighlights()
        }
    }

    /// Counts the rendered items per highlight in the visible resource; if any is drawn twice, redraws the group.
    /// Returns true when a repair was made.
    @discardableResult
    public func repairDuplicateHighlights() async -> Bool {
        guard case let .success(value) = await navigator.evaluateJavaScript(Self.duplicateCheckScript),
              let json = value as? String,
              let counts = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Int],
              counts.values.contains(where: { $0 > 1 })
        else { return false }
        duplicateRepairs += 1
        navigator.apply(decorations: [], in: Self.highlightGroup)
        try? await Task.sleep(for: .milliseconds(150))
        redrawHighlights(check: false)
        return true
    }

    private func redrawHighlights(check: Bool = true) {
        let style = SylviaReaderStyle.highlightStyle(theme: settings.theme)
        let decorations = highlights.compactMap { h -> Decoration? in
            guard let l = try? Self.readiumLocator(h.locator) else { return nil }
            return Decoration(id: h.id, locator: l, style: style)
        }
        navigator.apply(decorations: decorations, in: Self.highlightGroup)
        if check { scheduleDuplicateCheck() }
    }

    /// Applies reader settings, then redraws the highlights once the navigator has settled.
    ///
    /// Readium 3.11.0 observation (evidence decoration-race.json): updating decorations right after a
    /// preference change could leave the previous boxes in the DOM next to the new ones. The adapter therefore clears
    /// the highlight group and re-applies it after a short settle delay, coalescing bursts of changes.
    public func apply(settings: ReaderSettings) {
        self.settings = settings
        navigator.submitPreferences(SylviaReaderStyle.preferences(for: settings))
        scheduleHighlightRefresh()
    }

    private var refreshTask: Task<Void, Never>?
    public private(set) var highlightRefreshCount = 0

    private func scheduleHighlightRefresh() {
        refreshTask?.cancel()
        let changesAtStart = locationChangeCount
        refreshTask = Task { [weak self] in
            // Let Readium apply the CSS or reload the spreads: wait for the next location report (sent once the
            // spread is laid out again), at least 300 ms and at most 2 s.
            try? await Task.sleep(for: .milliseconds(300))
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(2)
            while let self, !Task.isCancelled, self.locationChangeCount == changesAtStart, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.navigator.apply(decorations: [], in: Self.highlightGroup)
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self.redrawHighlights()
            self.highlightRefreshCount += 1
        }
    }

    /// Waits for any pending highlight refresh to finish (tests and scenarios).
    public func settle() async {
        await refreshTask?.value
        try? await Task.sleep(for: .milliseconds(200))
    }

    // MARK: Search

    /// "Search this book" over Sylvia's own extraction and FTS5 index (plan 11.3), built on first use. Readium's
    /// search service is not used by the adapter: it reads the same publication text through SwiftSoup, and Sylvia
    /// needs its own index anyway for coverage status, chunk mapping and extraction versions.
    public private(set) var extraction: [EPUBExtraction.Resource]?
    private var lexicalIndex: LexicalIndex?

    public func search(_ query: String) async throws -> [ReaderLocator] {
        if lexicalIndex == nil {
            let resources = await EPUBExtraction.extract(opened)
            let index = try LexicalIndex()
            for r in resources { for c in r.chunks { try index.add(c) } }
            extraction = resources
            lexicalIndex = index
        }
        guard let index = lexicalIndex, let resources = extraction else { return [] }
        return try index.search(query).compactMap { result in
            guard let hit = result.hit, let resource = resources.first(where: { $0.href == hit.chunk.resourceHref }) else { return nil }
            return (try? EPUBExtraction.locator(for: hit, blocks: resource.blocks)).map(Self.readerLocator)
        }
    }

    /// Readium's own search service, kept for comparison in the tests only.
    public func readiumSearch(_ query: String) async throws -> [ReaderLocator] {
        switch await publication.search(query: query) {
        case let .failure(error): throw error
        case let .success(iterator):
            var found: [ReaderLocator] = []
            while case let .success(page?) = await iterator.next() {
                found += page.locators.map(Self.readerLocator)
            }
            return found
        }
    }

    // MARK: Observation

    public func observePositions(_ handler: @escaping @MainActor (ReaderLocator) -> Void) -> ReaderObservation {
        let id = UUID()
        positionHandlers[id] = handler
        return ReaderObservation { [weak self] in self?.positionHandlers[id] = nil }
    }

    // MARK: Test hooks (harness only; a product adapter would not expose arbitrary script evaluation)

    /// Evaluates JavaScript in the currently visible resource.
    public func testHookEvaluate(_ script: String) async -> Result<Any, Error> {
        await navigator.evaluateJavaScript(script)
    }

    /// Opening at a saved locator: after the first page is laid out, repeat the jump once (see `go(to:)`).
    public func settleInitialLocation(_ locator: ReaderLocator?) async {
        guard let locator, repeatsJumpAfterSettle else { return }
        _ = await navigate(to: locator)
    }

    /// Waits until the navigator reports a location (first page laid out).
    public func waitUntilLocated(timeout: Duration = .seconds(20)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while navigator.currentLocation == nil {
            if clock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }
}

extension ReadiumReaderSession: EPUBNavigatorDelegate {
    public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        locationChangeCount += 1
        if locator.href.string != lastLocatedHref {
            lastLocatedHref = locator.href.string
            if !highlights.isEmpty { scheduleDuplicateCheck() }
        }
        let l = Self.readerLocator(locator)
        for handler in positionHandlers.values { handler(l) }
    }

    public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}

    public func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
        userContentControllersConfigured += 1
        if let list = contentRuleList { userContentController.add(list) }
    }

    public func navigator(_ navigator: Navigator, shouldNavigateToNoteAt link: ReadiumShared.Link, content: String, referrer: String?) -> Bool {
        // Show the note in place; the reading position does not move (plan 9.1, 9.4).
        lastNote = (content, referrer ?? "", link.href)
        onNote?(content, referrer ?? "")
        return false
    }

    public func navigator(_ navigator: VisualNavigator, shouldNavigateToLink link: ReadiumShared.Link) -> Bool {
        // Internal link taps go through the adapter so they get the same settle-and-repeat jump and a history entry
        // for return-after-link.
        if let here = self.navigator.currentLocation { linkHistory.append(here) }
        Task { _ = await self.go(to: link) }
        return false
    }

    public func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
        // External links open only on an explicit user action in the product (plan 18.1); the spike records them.
        externalURLRequests.append(url)
    }

    public func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
        resourceLoadFailures.append("\(href.string): \(error)")
    }
}
