import UIKit

/// Root of the harness. Without launch arguments it lists the bundled fixtures (for manual device checks).
/// `-scenario <name> -fixture <file>` runs a scripted scenario for the UI tests; results go to the
/// `scenario.status` label so the UI test can read them.
@MainActor final class ScenarioController: UINavigationController {
    let arguments: [String]
    /// Kept alive for the whole run: the scenario's callbacks (rotation, notes) hold it weakly.
    private var runner: ScenarioRunner?

    init(arguments: [String]) {
        self.arguments = arguments
        super.init(rootViewController: FixtureListController())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Value following `name` in the launch arguments.
    func argument(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Hosted unit tests run inside this app; they build their own screens.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        if let scenario = argument("-scenario") {
            let runner = ScenarioRunner(name: scenario, fixture: argument("-fixture") ?? "se-meditations.epub", host: self)
            self.runner = runner
            Task { await runner.run() }
        }
    }
}

enum Fixtures {
    static func url(_ name: String) -> URL? {
        let base = Bundle.main.resourceURL!
        for dir in ["epub", "generated"] {
            let u = base.appendingPathComponent(dir).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    static var all: [String] {
        let base = Bundle.main.resourceURL!
        return ["epub", "generated"].flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(dir).path)) ?? [])
                .filter { $0.hasSuffix(".epub") }.sorted()
        }
    }
}

final class FixtureListController: UITableViewController {
    let names = Fixtures.all

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "G0.1 EPUB fixtures"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { names.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = names[indexPath.row]
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let name = names[indexPath.row]
        Task { @MainActor in
            guard let url = Fixtures.url(name) else { return }
            switch await EPUBOpener.open(fileURL: url) {
            case let .failure(error):
                let alert = UIAlertController(title: "Cannot open", message: error.description, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            case let .success(opened):
                do {
                    let session = try await ReadiumReaderSession.make(opened: opened, initialLocator: nil, editingActions: ReaderScreen.editingActions)
                    navigationController?.pushViewController(ReaderScreen(session: session, fixture: name), animated: true)
                } catch {
                    let alert = UIAlertController(title: "Cannot open", message: "\(error)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                }
            }
        }
    }
}
