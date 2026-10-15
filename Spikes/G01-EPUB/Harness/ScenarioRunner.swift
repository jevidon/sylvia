@preconcurrency import ReadiumShared
import UIKit

/// Scripted scenarios driven by the UI tests (launch arguments). Each writes a one-line status the UI test reads.
@MainActor final class ScenarioRunner {
    let name: String
    let fixture: String
    weak var host: ScenarioController?
    private var screen: ReaderScreen?

    /// The passage used by the anchor scenario (Meditations, Book I; contains U+2019).
    static let anchorHref = "epub/text/book-1.xhtml"
    static let anchorQuote = "From my governor, to be neither of the green nor of the blue party at the games in the Circus, nor a partisan either of the Parmularius or the Scutarius at the gladiators’ fights"

    init(name: String, fixture: String, host: ScenarioController) {
        self.name = name
        self.fixture = fixture
        self.host = host
    }

    func run() async {
        if name.hasPrefix("parse-") { return await parseScenario() }
        if host?.argument("-reset") == "1" { try? FileManager.default.removeItem(at: HighlightStore.url(for: fixture)) }
        guard let url = Fixtures.url(fixture) else { return status("error=fixture-missing") }
        guard case let .success(opened) = await EPUBOpener.open(fileURL: url) else { return status("error=open-failed") }
        let saved = HighlightStore.load(fixture: fixture)
        do {
            let session = try await ReadiumReaderSession.make(opened: opened, initialLocator: saved.first?.locator, editingActions: ReaderScreen.editingActions)
            let screen = ReaderScreen(session: session, fixture: fixture)
            self.screen = screen
            host?.pushViewController(screen, animated: false)
            guard await session.waitUntilLocated() else { return status("error=not-located") }
            await session.settleInitialLocation(saved.first?.locator)
            switch name {
            case "anchor": await anchorScenario(session, saved: saved)
            case "footnote": await footnoteScenario(session)
            default: status("error=unknown-scenario")
            }
        } catch {
            status("error=\(error)")
        }
    }

    /// Status label used before (or without) a reader screen.
    private var fallbackLabel: UILabel?

    private func status(_ text: String) {
        // Also written to a file when the UI test asks for one, so it can follow a scenario that may crash the app
        // without querying the accessibility tree of a dying process.
        if let path = ProcessInfo.processInfo.environment["SYLVIA_SCENARIO_STATUS_FILE"], !path.isEmpty {
            try? (text + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let screen { return screen.setStatus(text) }
        if fallbackLabel == nil, let view = host?.view {
            let label = UILabel()
            label.accessibilityIdentifier = "scenario.status"
            label.numberOfLines = 3
            label.font = .preferredFont(forTextStyle: .caption2)
            label.backgroundColor = .systemBackground
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
                label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                label.heightAnchor.constraint(equalToConstant: 48),
            ])
            fallbackLabel = label
        }
        fallbackLabel?.text = text
        fallbackLabel?.accessibilityLabel = text
    }

    // MARK: anchor (T15 relaunch and rotation, from outside the process)

    private func anchorScenario(_ session: ReadiumReaderSession, saved: [SavedHighlight]) async {
        guard let screen else { return }
        if let item = saved.first {
            // Relaunch: the highlight was restored from the store in ReaderScreen.viewDidLoad and the navigator
            // opened at the saved locator. Verify it is drawn over the same text and on screen.
            let ok = await verify(session, item: item)
            status("phase=relaunch \(ok)")
        } else {
            _ = await ReaderProbe.goToText(session, href: Self.anchorHref, exact: Self.anchorQuote)
            guard (try? await ReaderProbe.call(session, "selectText(\(ReaderProbe.jsString(Self.anchorQuote)), null)"))?["ok"] as? Bool == true,
                  await ReaderProbe.waitForSelection(session) != nil,
                  let item = await screen.capture(note: nil)
            else { return status("phase=create error=capture") }
            let ok = await verify(session, item: item)
            status("phase=created \(ok)")
        }
        screen.onSizeTransitionCompleted = { [weak self] in
            Task { @MainActor in
                guard let self, let item = HighlightStore.load(fixture: self.fixture).first else { return }
                self.status("phase=rotating")
                // Let Readium re-paginate after the size change, then reopen the saved locator.
                try? await Task.sleep(for: .seconds(1))
                _ = await session.navigate(to: item.locator)
                let ok = await self.verify(session, item: item)
                let size = self.screen?.view.bounds.size ?? .zero
                self.status("phase=rotated w=\(Int(size.width)) h=\(Int(size.height)) \(ok)")
            }
        }
    }

    private func verify(_ session: ReadiumReaderSession, item: SavedHighlight) async -> String {
        var inspection: ReaderProbe.Inspection?
        _ = await ReaderProbe.wait(timeout: .seconds(8)) {
            inspection = try? await ReaderProbe.inspect(session, exact: item.anchor.exactText, prefix: item.anchor.prefix, highlightID: item.id)
            return inspection?.covered == true && inspection?.visible == true && inspection?.renderings == 1
        }
        guard let i = inspection else { return "ok=0 reason=no-inspection" }
        let ok = i.covered && i.visible && i.renderings == 1
        return "ok=\(ok ? 1 : 0) covered=\(i.covered ? 1 : 0) visible=\(i.visible ? 1 : 0) renderings=\(i.renderings) boxes=\(i.boxes.count) lines=\(i.quoteRectCount) repairs=\(session.duplicateRepairs)"
    }

    // MARK: parse-* (plan 8.3 recursion; run in their own process because Readium alone crashes on them)

    /// `parse-<mode>-<safety>`: opens `fixture` with `.readiumDefaults` (`raw`) or `.sylvia` (`adapter`) and walks it
    /// with Readium's content iterator (`iterator`) or Readium's search service (`search`). Reports
    /// `phase=parse-done ...` when the walk returns; if Readium crashes, the UI test sees the app terminate instead.
    private func parseScenario() async {
        let parts = name.split(separator: "-").map(String.init)
        guard parts.count == 3, let url = Fixtures.url(fixture) else { return status("error=bad-parse-scenario") }
        let options: EPUBOpenOptions = parts[2] == "adapter" ? .sylvia : .readiumDefaults
        guard case let .success(opened) = await EPUBOpener.open(fileURL: url, options: options) else { return status("error=open-failed") }
        status("phase=parse-started mode=\(parts[1]) safety=\(parts[2]) pid=\(ProcessInfo.processInfo.processIdentifier)")
        // Give the UI test time to read the "started" status before the walk begins.
        try? await Task.sleep(for: .seconds(2))
        let clock = ContinuousClock()
        let start = clock.now
        var count = 0
        switch parts[1] {
        case "iterator":
            if let iterator = opened.publication.content()?.iterator() {
                while let element = try? await iterator.next() {
                    if element is TextContentElement { count += 1 }
                }
            }
        case "search":
            if case let .success(results) = await opened.publication.search(query: "Innermost") {
                while case let .success(page?) = await results.next() { count += page.locators.count }
            }
        default:
            return status("error=unknown-parse-mode")
        }
        let ms = Int(((clock.now - start).seconds * 1000).rounded())
        status("phase=parse-done mode=\(parts[1]) safety=\(parts[2]) count=\(count) ms=\(ms) unavailable=\(opened.sanitizer.unavailableHrefs.sorted().joined(separator: ","))")
    }

    // MARK: footnote (real tap from the UI test on a noteref link)

    private func footnoteScenario(_ session: ReadiumReaderSession) async {
        _ = await ReaderProbe.goToText(session, href: Self.anchorHref, exact: "From my grandfather Verus")
        try? await Task.sleep(for: .seconds(1))
        let before = session.currentLocator
        session.onNote = { [weak self] html, _ in
            let after = session.currentLocator
            let same = before?.href == after?.href && before?.progression == after?.progression
            let text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            self?.status("phase=note unchanged=\(same ? 1 : 0) note=\(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))")
            self?.screen?.presentNote(html)
        }
        status("phase=ready href=\(before?.href ?? "-") progression=\(before?.progression ?? -1)")
    }
}
