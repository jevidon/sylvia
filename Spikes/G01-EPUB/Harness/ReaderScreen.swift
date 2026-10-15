import G01EPUBCore
@preconcurrency import ReadiumNavigator
import UIKit

/// Saved highlight as the harness persists it (stands in for Sylvia's database row; plan 11.1).
struct SavedHighlight: Codable, Equatable {
    var id: String
    var locator: ReaderLocator
    var anchor: PortableEPUBAnchor
    var note: String?
    var savedAt: Date
}

/// JSON file store under Application Support, written atomically. Harness only.
enum HighlightStore {
    static func url(for fixture: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("g01-highlights-\(fixture).json")
    }

    static func load(fixture: String) -> [SavedHighlight] {
        guard let data = try? Data(contentsOf: url(for: fixture)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SavedHighlight].self, from: data)) ?? []
    }

    static func save(_ items: [SavedHighlight], fixture: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(items).write(to: url(for: fixture), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// The harness reading screen: hosts a `ReaderSession`, the selection menu actions of plan 4.4.7
/// (Highlight, Note, Look Up, Ask) and minimal "Aa" controls. Harness chrome only; never shipped.
@MainActor final class ReaderScreen: UIViewController {
    let session: ReadiumReaderSession
    let fixture: String
    let statusLabel = UILabel()
    private(set) var saved: [SavedHighlight] = []
    private var positionObservation: ReaderObservation?
    /// Called after a size change (rotation) has finished animating.
    var onSizeTransitionCompleted: (() -> Void)?

    static var editingActions: [EditingAction] {
        [
            EditingAction(title: "Highlight", action: #selector(ReaderScreen.sylviaHighlight(_:))),
            EditingAction(title: "Note", action: #selector(ReaderScreen.sylviaNote(_:))),
            .lookup,
            EditingAction(title: "Ask", action: #selector(ReaderScreen.sylviaAsk(_:))),
        ]
    }

    init(session: ReadiumReaderSession, fixture: String) {
        self.session = session
        self.fixture = fixture
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addChild(session.navigator)
        session.navigator.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(session.navigator.view)
        session.navigator.didMove(toParent: self)

        statusLabel.accessibilityIdentifier = "scenario.status"
        // Fixed height: a label that grows with its text would resize the navigator, and Readium re-paginates on resize.
        statusLabel.numberOfLines = 2
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let bar = UIStackView(arrangedSubviews: [
            button("A−", id: "aa.smaller") { [weak self] in self?.adjustFont(-2) },
            button("A+", id: "aa.larger") { [weak self] in self?.adjustFont(+2) },
            button("Theme", id: "aa.theme") { [weak self] in self?.toggleTheme() },
            button("Face", id: "aa.face") { [weak self] in self?.cycleFace() },
            button("Back", id: "nav.return") { [weak self] in Task { _ = await self?.session.returnFromLink() } },
            button("Saved", id: "nav.saved") { [weak self] in self?.showSaved() },
        ])
        bar.axis = .horizontal
        bar.distribution = .fillEqually
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
            session.navigator.view.topAnchor.constraint(equalTo: bar.bottomAnchor),
            session.navigator.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            session.navigator.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            session.navigator.view.bottomAnchor.constraint(equalTo: statusLabel.topAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.heightAnchor.constraint(equalToConstant: 34),
        ])

        saved = HighlightStore.load(fixture: fixture)
        session.apply(highlights: saved.map { HighlightPresentation(id: $0.id, locator: $0.locator) })
        session.onNote = { [weak self] html, _ in self?.presentNote(html) }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.onSizeTransitionCompleted?() }
    }

    private func button(_ title: String, id: String, action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system, primaryAction: UIAction(title: title) { _ in action() })
        b.accessibilityIdentifier = id
        return b
    }

    func setStatus(_ text: String) {
        statusLabel.text = text
        statusLabel.accessibilityLabel = text
    }

    // MARK: Aa controls

    private func adjustFont(_ delta: Double) {
        var s = session.settings
        s.fontSizePoints = (s.fontSizePoints + delta).clamped(to: ReaderSettings.fontSizeRange)
        session.apply(settings: s)
    }

    private func toggleTheme() {
        var s = session.settings
        s.theme = s.theme == .paper ? .night : .paper
        session.apply(settings: s)
    }

    private func cycleFace() {
        var s = session.settings
        let all = ReaderTypeface.allCases
        s.typeface = all[(all.firstIndex(of: s.typeface)! + 1) % all.count]
        session.apply(settings: s)
    }

    // MARK: Selection menu (plan 4.4.7). The selection is captured before anything else can invalidate it.

    @objc func sylviaHighlight(_ sender: Any?) { Task { await capture(note: nil) } }

    @objc func sylviaNote(_ sender: Any?) {
        Task { [weak self] in
            guard let self else { return }
            // Captured now, before the note editor (or anything else) can change the selection.
            guard let selection = await session.captureSelection() else { return setStatus("Not saved · select the text again") }
            let alert = UIAlertController(title: "Note", message: selection.exactText, preferredStyle: .alert)
            alert.addTextField { $0.accessibilityLabel = "Your note" }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
                let note = alert?.textFields?.first?.text
                Task { await self?.capture(selection: selection, note: note) }
            })
            present(alert, animated: true)
        }
    }

    @objc func sylviaAsk(_ sender: Any?) {
        guard let selection = session.currentSelection else { return }
        let alert = UIAlertController(title: "Ask (not sent)", message: "Selected passage:\n\(selection.exactText)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    @discardableResult
    func capture(selection given: ReaderSelection? = nil, note: String?) async -> SavedHighlight? {
        let selection: ReaderSelection
        if let given {
            selection = given
        } else {
            guard session.currentSelection != nil else { return nil }
            guard let confirmed = await session.captureSelection() else {
                setStatus("Not saved · select the text again")
                return nil
            }
            selection = confirmed
        }
        do {
            let anchor = try CaptureBuilder.anchor(for: selection, assetID: "harness-\(fixture)", assetDigest: session.opened.sha256, extraction: nil)
            let item = SavedHighlight(id: UUID().uuidString.lowercased(), locator: selection.locator, anchor: anchor, note: note, savedAt: Date())
            var next = saved
            next.append(item)
            try HighlightStore.save(next, fixture: fixture)
            saved = next // "Saved" only after the durable write (plan I-03).
            session.apply(highlights: saved.map { HighlightPresentation(id: $0.id, locator: $0.locator) })
            session.clearSelection()
            setStatus("Saved")
            return item
        } catch {
            setStatus("Not saved · your text is still here")
            return nil
        }
    }

    // MARK: Notes and saved list

    /// Shows a footnote or endnote as plain text. The note HTML comes from the publication, so it is never handed to an
    /// HTML renderer outside the locked-down web view (NSAttributedString's HTML importer can fetch remote resources).
    func presentNote(_ html: String) {
        let text = Self.plainText(fromNoteHTML: html)
        let alert = UIAlertController(title: "Note", message: text.trimmingCharacters(in: .whitespacesAndNewlines), preferredStyle: .alert)
        alert.view.accessibilityIdentifier = "note.popup"
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    /// Tags removed, numeric character references and the predefined XML entities decoded, whitespace collapsed.
    nonisolated static func plainText(fromNoteHTML html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        if let re = try? NSRegularExpression(pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);") {
            let ns = text as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let body = ns.substring(with: m.range(at: 1))
                let value = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
                out += value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ns.substring(with: m.range)
                last = m.range.location + m.range.length
            }
            text = out + ns.substring(from: last)
        }
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", "\u{00A0}"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func showSaved() {
        let list = SavedListController(items: saved)
        present(UINavigationController(rootViewController: list), animated: true)
    }
}

/// Saved highlights and notes, reachable with VoiceOver (plan 9.4 device check).
final class SavedListController: UITableViewController {
    let items: [SavedHighlight]
    init(items: [SavedHighlight]) {
        self.items = items
        super.init(style: .insetGrouped)
        title = "Saved"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let item = items[indexPath.row]
        cell.textLabel?.text = "Quote: " + item.anchor.exactText
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = item.note.map { "Your note: \($0)" }
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }
}
